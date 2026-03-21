"""
Capture Backend - Screenshot to Calendar Event API

This FastAPI server receives screenshots, analyzes them with OpenAI Vision
to extract event information. Events are created locally by the iOS app via EventKit.
"""

import os
import uuid
import asyncio
from datetime import datetime, date
import time
from contextlib import asynccontextmanager
from collections import defaultdict
from typing import Dict, Any, Optional, NamedTuple

from fastapi import FastAPI, HTTPException, status, Request, Depends, BackgroundTasks
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from dotenv import load_dotenv

from models.schemas import (
    AnalyzeScreenshotRequest,
    AnalyzeScreenshotResponse,
    AnalyzeCaptureRequest,
    SetNotionParentRequest,
    HealthResponse,
    RegisterDeviceRequest,
    AsyncAnalyzeResponse,
    JobStatusResponse,
    ExtractedEventInfo,
)
from services.openai_service import OpenAIService
from services.apns_service import apns_service
from services.notion_agent import notion_agent
from models.notion_store import (
    get_user as notion_get_user,
    save_user as notion_save_user,
    delete_user as notion_delete_user,
    user_has_notion,
    NotionUserData,
)

# Load environment variables
load_dotenv()

# ============================================
# Rate Limit Configuration (adjust as needed)
# ============================================
RATE_LIMIT_PER_MINUTE = 100      # Global burst limit
GLOBAL_DAILY_LIMIT = 500         # Total requests per day (hard cost ceiling)
PER_USER_DAILY_LIMIT = 25        # Requests per user per day
MAX_IMAGE_SIZE_MB = 10           # Max base64 image size in MB
MAX_CONCURRENT_OPENAI = 5        # Max concurrent OpenAI API calls (prevents rate limit errors)

# API Key for app authentication
API_SECRET_KEY = os.getenv("API_SECRET_KEY", "")

# Notion OAuth configuration
NOTION_CLIENT_ID = os.getenv("NOTION_CLIENT_ID", "")
NOTION_CLIENT_SECRET = os.getenv("NOTION_CLIENT_SECRET", "")
NOTION_REDIRECT_URI = os.getenv("NOTION_REDIRECT_URI", "")

# ============================================
# Rate Limiting Setup
# ============================================
limiter = Limiter(key_func=get_remote_address)

# In-memory tracking for daily limits (resets on server restart)
class DailyLimitTracker:
    def __init__(self):
        self.global_count: int = 0
        self.user_counts: Dict[str, int] = defaultdict(int)
        self.current_date: date = date.today()
    
    def _reset_if_new_day(self):
        """Reset counters at midnight UTC."""
        today = date.today()
        if today != self.current_date:
            self.global_count = 0
            self.user_counts.clear()
            self.current_date = today
            print(f"🔄 Daily limits reset for {today}")
    
    def check_and_increment(self, user_id: str) -> tuple[bool, str]:
        """
        Check if request is allowed and increment counters.
        Returns (allowed: bool, error_message: str)
        """
        self._reset_if_new_day()
        
        # Check global daily limit
        if self.global_count >= GLOBAL_DAILY_LIMIT:
            return False, f"Daily limit reached ({GLOBAL_DAILY_LIMIT} requests). Try again tomorrow."
        
        # Check per-user daily limit
        if self.user_counts[user_id] >= PER_USER_DAILY_LIMIT:
            return False, f"You've reached your daily limit ({PER_USER_DAILY_LIMIT} captures). Try again tomorrow."
        
        # Increment counters
        self.global_count += 1
        self.user_counts[user_id] += 1
        
        return True, ""
    
    def get_stats(self) -> dict:
        """Get current usage stats."""
        self._reset_if_new_day()
        return {
            "global_used": self.global_count,
            "global_limit": GLOBAL_DAILY_LIMIT,
            "active_users": len(self.user_counts),
        }

daily_tracker = DailyLimitTracker()

# Initialize services
openai_service = OpenAIService()

# Semaphore to limit concurrent OpenAI API calls.
# Prevents hitting OpenAI rate limits when multiple users capture simultaneously.
openai_semaphore = asyncio.Semaphore(MAX_CONCURRENT_OPENAI)

# ============================================
# In-Memory Storage
# NOTE: These are lost on server restart. For production, use Redis or a database.
# The iOS app re-registers device tokens on app launch, so this is acceptable.
# ============================================

# Device tokens for push notifications: user_id -> DeviceInfo(token, is_sandbox)
class DeviceInfo(NamedTuple):
    token: str
    is_sandbox: bool

device_tokens: Dict[str, DeviceInfo] = {}

# Pending jobs for async processing: job_id -> job_data
pending_jobs: Dict[str, Dict[str, Any]] = {}

# TTL for completed/failed jobs before cleanup (seconds)
JOB_TTL_SECONDS = 3600  # 1 hour


def cleanup_expired_jobs():
    """Remove completed/failed jobs older than JOB_TTL_SECONDS."""
    now = datetime.utcnow()
    expired_ids = []
    
    for job_id, job_data in pending_jobs.items():
        job_status = job_data.get("status", "")
        # Only clean up completed or failed jobs (not processing ones)
        if job_status in ("completed", "failed"):
            created_at_str = job_data.get("created_at")
            if created_at_str:
                try:
                    created_at = datetime.strptime(created_at_str, "%Y-%m-%d %H:%M:%S UTC")
                    if (now - created_at).total_seconds() > JOB_TTL_SECONDS:
                        expired_ids.append(job_id)
                except (ValueError, TypeError):
                    # If timestamp is unparseable and job is done, clean it up
                    expired_ids.append(job_id)
            else:
                # No created_at timestamp on a finished job - use a fallback:
                # If there's a "completed_at" or just clean it up if status is terminal
                expired_ids.append(job_id)
    
    if expired_ids:
        for job_id in expired_ids:
            del pending_jobs[job_id]
        print(f"🧹 Cleaned up {len(expired_ids)} expired job(s). {len(pending_jobs)} remaining.")


# ============================================
# Security Middleware
# ============================================
def verify_api_key(request: Request):
    """Verify the API key is present and valid."""
    if not API_SECRET_KEY:
        # No API key configured - skip validation (for development)
        return
    
    api_key = request.headers.get("X-API-Key", "")
    if api_key != API_SECRET_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key"
        )


def validate_image_size(image_base64: str):
    """Validate the base64 image size."""
    # Base64 is ~33% larger than binary, so 10MB base64 ≈ 7.5MB actual
    max_size_bytes = MAX_IMAGE_SIZE_MB * 1024 * 1024
    if len(image_base64) > max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Image too large. Maximum size is {MAX_IMAGE_SIZE_MB}MB."
        )


async def periodic_job_cleanup():
    """Background task that periodically cleans up expired jobs."""
    while True:
        await asyncio.sleep(300)  # Run every 5 minutes
        cleanup_expired_jobs()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    print("🚀 Capture Backend starting up...")
    print(f"📍 OpenAI configured: {bool(os.getenv('OPENAI_API_KEY'))}")
    print(f"🔐 API Key configured: {bool(API_SECRET_KEY)}")
    print(f"📊 Rate limits: {RATE_LIMIT_PER_MINUTE}/min, {GLOBAL_DAILY_LIMIT}/day global, {PER_USER_DAILY_LIMIT}/day per user")
    print(f"⚡ Max concurrent OpenAI calls: {MAX_CONCURRENT_OPENAI}")
    
    # Start periodic job cleanup task
    cleanup_task = asyncio.create_task(periodic_job_cleanup())
    
    yield
    
    # Shutdown
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass
    print("👋 Capture Backend shutting down...")


# Create FastAPI app
app = FastAPI(
    title="Capture API",
    description="Screenshot to Calendar Event extraction API - events created locally via EventKit",
    version="2.0.0",
    lifespan=lifespan,
)

# Add rate limiter to app state
app.state.limiter = limiter


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    """Handle rate limit exceeded errors."""
    return JSONResponse(
        status_code=429,
        content={"detail": f"Rate limit exceeded. Please slow down."}
    )


# NOTE: CORS middleware removed - iOS native apps don't need CORS
# This prevents web-based attacks on the API


# ============================================
# Health Check
# ============================================

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Check if the service is running."""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow().isoformat()
    )


# ============================================
# Main Endpoint
# ============================================

@app.post(
    "/analyze-screenshot",
    response_model=AnalyzeScreenshotResponse,
    tags=["Screenshot Analysis"],
)
@limiter.limit(f"{RATE_LIMIT_PER_MINUTE}/minute")
async def analyze_screenshot(
    request: Request,
    body: AnalyzeScreenshotRequest,
    _: None = Depends(verify_api_key),
):
    """
    Analyze a screenshot for event information.
    
    This endpoint extracts calendar events from screenshots using OpenAI Vision.
    Events are returned to the client for local creation via EventKit.
    
    Supports MULTIPLE events per screenshot.
    
    Steps:
    1. Verifies API key (X-API-Key header)
    2. Checks rate limits (per-minute and daily) using user_id
    3. Sends the image to OpenAI Vision for analysis
    4. Returns extracted event details for client to create locally
    
    Args:
        body: Contains base64 encoded image and Apple user ID
        
    Returns:
        Success status, list of events to create, and status message
    """
    start_time = time.time()
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"\n[{timestamp}] === NEW CAPTURE REQUEST ===", flush=True)
    
    try:
        # Step 0: Validate image size
        validate_image_size(body.image)
        image_size_kb = len(body.image) / 1024
        print(f"[{timestamp}] Image size: {image_size_kb:.0f} KB", flush=True)
        
        # Step 1: Check daily limits using user_id
        user_id = body.user_id
        print(f"[{timestamp}] User: {user_id[:20]}..." if len(user_id) > 20 else f"[{timestamp}] User: {user_id}", flush=True)
        
        allowed, error_msg = daily_tracker.check_and_increment(user_id)
        if not allowed:
            print(f"[{timestamp}] RATE LIMITED: {error_msg}", flush=True)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=error_msg
            )
        
        # Step 2: Analyze screenshot with OpenAI Vision (throttled by semaphore)
        source = body.source or "screenshot"
        context = body.context
        openai_start = time.time()
        print(f"[{timestamp}] Waiting for OpenAI slot... (source: {source}, context: {bool(context)})", flush=True)
        async with openai_semaphore:
            print(f"[{timestamp}] Sending to OpenAI...", flush=True)
            analysis_result = await openai_service.analyze_screenshot(body.image, source=source, context=context)
            openai_elapsed = time.time() - openai_start
            print(f"[{timestamp}] OpenAI completed in {openai_elapsed:.1f}s", flush=True)
        
        if not analysis_result.found_events or len(analysis_result.events) == 0:
            total_elapsed = time.time() - start_time
            
            # Distinguish between "no events found" and "analysis error"
            is_error = analysis_result.raw_text and analysis_result.raw_text.startswith("OpenAI error:")
            if is_error:
                print(f"[{timestamp}] ANALYSIS ERROR: {analysis_result.raw_text} (total: {total_elapsed:.1f}s)", flush=True)
                message = analysis_result.raw_text
            else:
                print(f"[{timestamp}] No events found (total: {total_elapsed:.1f}s)", flush=True)
                message = "No event information found in the screenshot. Please try a clearer image."
            
            return AnalyzeScreenshotResponse(
                success=False,
                events_to_create=[],
                message=message
            )
        
        # Log detected events (compact format)
        print(f"[{timestamp}] Found {len(analysis_result.events)} event(s):", flush=True)
        for idx, event_info in enumerate(analysis_result.events, 1):
            print(f"[{timestamp}]   {idx}. {event_info.title} | {event_info.date} {event_info.start_time or 'all-day'}", flush=True)
        
        # Step 3: Return events for client to create locally
        total_elapsed = time.time() - start_time
        if len(analysis_result.events) == 1:
            message = f"Found event: '{analysis_result.events[0].title}'"
        else:
            message = f"Found {len(analysis_result.events)} events"
        
        print(f"[{timestamp}] SUCCESS: {message} (total: {total_elapsed:.1f}s)", flush=True)
        
        return AnalyzeScreenshotResponse(
            success=True,
            events_to_create=analysis_result.events,
            message=message
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ERROR: {str(e)}", flush=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process screenshot: {str(e)}"
        )


# ============================================
# Stats Endpoint (for monitoring)
# ============================================

@app.get("/stats", tags=["Monitoring"])
async def get_stats(request: Request, _: None = Depends(verify_api_key)):
    """Get current usage statistics (requires API key)."""
    stats = daily_tracker.get_stats()
    return {
        "date": date.today().isoformat(),
        "usage": stats,
        "limits": {
            "per_minute": RATE_LIMIT_PER_MINUTE,
            "global_daily": GLOBAL_DAILY_LIMIT,
            "per_user_daily": PER_USER_DAILY_LIMIT,
        }
    }


# ============================================
# Device Registration (for Push Notifications)
# ============================================

@app.post("/register-device", tags=["Push Notifications"])
async def register_device(
    body: RegisterDeviceRequest,
    _: None = Depends(verify_api_key),
):
    """
    Register a device token for push notifications.
    
    Called by the iOS app when the user grants notification permission
    and on each app launch (to handle server restarts).
    """
    # Validate token format (should be 64 hex characters)
    token = body.device_token.strip()
    if len(token) != 64:
        print(f"⚠️ Invalid device token length: {len(token)} (expected 64)")
        return {"success": False, "message": "Invalid device token format"}
    
    device_tokens[body.user_id] = DeviceInfo(token=token, is_sandbox=body.is_sandbox)
    env_type = "sandbox" if body.is_sandbox else "production"
    user_display = body.user_id[:20] + "..." if len(body.user_id) > 20 else body.user_id
    token_display = token[:16] + "..."
    print(f"📱 Device registered ({env_type}): user={user_display}, token={token_display}")
    
    return {"success": True, "message": "Device registered"}


# ============================================
# Async Screenshot Analysis (Push Notification Flow)
# ============================================

async def process_screenshot_and_notify(job_id: str, image: str, user_id: str, source: str = "screenshot", context: str = None):
    """
    Background task: Process screenshot and send push notification when done.
    """
    job_short = job_id[:8]
    start_time = time.time()
    
    def log(msg: str):
        ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
        print(f"[{ts}] [{job_short}] {msg}", flush=True)
    
    log("Started background processing")
    
    try:
        # Get device info (token + sandbox flag)
        device_info = device_tokens.get(user_id)
        if device_info:
            device_token = device_info.token
            use_sandbox = device_info.is_sandbox
            log(f"Device token: found ({'sandbox' if use_sandbox else 'production'})")
        else:
            device_token = None
            use_sandbox = False
            log("Device token: NOT FOUND")
        
        # Analyze screenshot with OpenAI (throttled by semaphore)
        log(f"Waiting for OpenAI slot... (source: {source}, context: {bool(context)})")
        async with openai_semaphore:
            log("Sending to OpenAI...")
            analysis_result = await openai_service.analyze_screenshot(image, source=source, context=context)
            elapsed = time.time() - start_time
            log(f"OpenAI completed in {elapsed:.1f}s")
        
        # Preserve the original created_at for TTL-based cleanup
        created_at = pending_jobs.get(job_id, {}).get("created_at", datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"))
        
        if not analysis_result.found_events or len(analysis_result.events) == 0:
            # Distinguish between "no events found" and "analysis error"
            is_error = analysis_result.raw_text and analysis_result.raw_text.startswith("OpenAI error:")
            
            if is_error:
                log(f"ANALYSIS ERROR: {analysis_result.raw_text}")
                pending_jobs[job_id] = {
                    "user_id": user_id,
                    "status": "failed",
                    "events": [],
                    "error": analysis_result.raw_text,
                    "created_at": created_at
                }
                if device_token:
                    await apns_service.send_error_notification(device_token, analysis_result.raw_text, job_id=job_id, use_sandbox=use_sandbox)
            else:
                log("No events found")
                pending_jobs[job_id] = {
                    "user_id": user_id,
                    "status": "completed",
                    "events": [],
                    "message": "No events found",
                    "created_at": created_at
                }
                if device_token:
                    await apns_service.send_no_events_notification(device_token, job_id=job_id, use_sandbox=use_sandbox)
            return
        
        # Success - store result
        pending_jobs[job_id] = {
            "user_id": user_id,
            "status": "completed",
            "events": analysis_result.events,
            "message": f"Found {len(analysis_result.events)} event(s)",
            "created_at": created_at
        }
        
        # Log detected events
        log(f"Found {len(analysis_result.events)} event(s):")
        for idx, event_info in enumerate(analysis_result.events, 1):
            log(f"  {idx}. {event_info.title} | {event_info.date} {event_info.start_time or 'all-day'}")
        
        # Send push notification (only job_id in payload, not full event data)
        if device_token:
            success = await apns_service.send_event_created_notification(device_token, analysis_result.events, job_id=job_id, use_sandbox=use_sandbox)
            log(f"Push: {'sent' if success else 'FAILED'}")
        else:
            log("Push: skipped (no device token)")
            
    except Exception as e:
        import traceback
        log(f"ERROR: {str(e)}")
        log(f"Traceback: {traceback.format_exc()}")
        
        created_at = pending_jobs.get(job_id, {}).get("created_at", datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"))
        pending_jobs[job_id] = {
            "user_id": user_id,
            "status": "failed",
            "error": str(e),
            "created_at": created_at
        }
        
        # Try to send error notification
        if device_token:
            await apns_service.send_error_notification(device_token, str(e), job_id=job_id, use_sandbox=use_sandbox)
    
    finally:
        elapsed = time.time() - start_time
        log(f"Completed in {elapsed:.1f}s")


@app.post(
    "/analyze-screenshot-async",
    response_model=AsyncAnalyzeResponse,
    tags=["Screenshot Analysis"],
)
@limiter.limit(f"{RATE_LIMIT_PER_MINUTE}/minute")
async def analyze_screenshot_async(
    request: Request,
    body: AnalyzeScreenshotRequest,
    background_tasks: BackgroundTasks,
    _: None = Depends(verify_api_key),
):
    """
    Analyze a screenshot asynchronously (for push notification flow).
    
    This endpoint returns immediately after queuing the job. The actual processing
    happens in the background, and a push notification is sent when complete.
    
    Use this when the iOS app has push notifications enabled.
    
    Steps:
    1. Validates request and checks rate limits
    2. Generates a job ID and queues background processing
    3. Returns immediately with job ID
    4. Background: Processes screenshot with OpenAI
    5. Background: Sends push notification with results
    """
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"\n[{timestamp}] === NEW ASYNC CAPTURE REQUEST ===", flush=True)
    
    try:
        # Validate image size
        validate_image_size(body.image)
        image_size_kb = len(body.image) / 1024
        print(f"[{timestamp}] Image size: {image_size_kb:.0f} KB", flush=True)
        
        # Check daily limits
        user_id = body.user_id
        print(f"[{timestamp}] User: {user_id[:20]}..." if len(user_id) > 20 else f"[{timestamp}] User: {user_id}", flush=True)
        
        allowed, error_msg = daily_tracker.check_and_increment(user_id)
        if not allowed:
            print(f"[{timestamp}] RATE LIMITED: {error_msg}", flush=True)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=error_msg
            )
        
        # Clean up expired jobs to prevent unbounded memory growth
        cleanup_expired_jobs()
        
        source = body.source or "screenshot"
        context = body.context
        
        # Generate job ID and store initial state
        job_id = str(uuid.uuid4())
        pending_jobs[job_id] = {
            "user_id": user_id,
            "status": "processing",
            "created_at": timestamp
        }
        
        # Queue background processing
        background_tasks.add_task(
            process_screenshot_and_notify,
            job_id=job_id,
            image=body.image,
            user_id=user_id,
            source=source,
            context=context
        )
        
        print(f"[{timestamp}] Job queued: {job_id[:8]}...", flush=True)
        
        return AsyncAnalyzeResponse(
            success=True,
            job_id=job_id,
            message="Processing started. You'll receive a notification when complete."
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ERROR: {str(e)}", flush=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to queue screenshot processing: {str(e)}"
        )


# ============================================
# Job Status (for fallback recovery)
# ============================================

@app.get(
    "/job-status/{job_id}",
    response_model=JobStatusResponse,
    tags=["Screenshot Analysis"],
)
async def get_job_status(
    job_id: str,
    _: None = Depends(verify_api_key),
):
    """
    Check the status of an async processing job.
    
    Used by the iOS app to recover pending jobs when opened.
    This is the fallback for users who don't have push notifications enabled.
    """
    job = pending_jobs.get(job_id)
    
    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found or expired"
        )
    
    return JobStatusResponse(
        job_id=job_id,
        status=job.get("status", "unknown"),
        events_to_create=job.get("events"),
        error=job.get("error")
    )


# ============================================
# Notion OAuth
# ============================================

@app.get("/notion/auth-url", tags=["Notion"])
async def get_notion_auth_url(
    user_id: str,
    _: None = Depends(verify_api_key),
):
    """Return the Notion OAuth authorization URL for the user."""
    if not NOTION_CLIENT_ID:
        raise HTTPException(status_code=500, detail="Notion OAuth not configured")

    url = (
        f"https://api.notion.com/v1/oauth/authorize"
        f"?client_id={NOTION_CLIENT_ID}"
        f"&response_type=code"
        f"&owner=user"
        f"&redirect_uri={NOTION_REDIRECT_URI}"
        f"&state={user_id}"
    )
    return {"url": url}


@app.get("/notion/callback", tags=["Notion"])
async def notion_oauth_callback(code: str, state: str):
    """
    Notion OAuth callback — exchanges the code for an access token
    and stores it for the user.
    """
    import httpx as httpx_lib

    user_id = state
    if not NOTION_CLIENT_ID or not NOTION_CLIENT_SECRET:
        raise HTTPException(status_code=500, detail="Notion OAuth not configured")

    async with httpx_lib.AsyncClient() as client:
        resp = await client.post(
            "https://api.notion.com/v1/oauth/token",
            json={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": NOTION_REDIRECT_URI,
            },
            auth=(NOTION_CLIENT_ID, NOTION_CLIENT_SECRET),
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=400, detail=f"Notion token exchange failed: {resp.text}")

    data = resp.json()
    notion_save_user(user_id, NotionUserData(
        access_token=data["access_token"],
        workspace_name=data.get("workspace_name"),
        workspace_id=data.get("workspace_id"),
    ))

    return {"success": True, "workspace_name": data.get("workspace_name")}


@app.get("/notion/status", tags=["Notion"])
async def notion_status(
    user_id: str,
    _: None = Depends(verify_api_key),
):
    """Check if a user has connected Notion."""
    user_data = notion_get_user(user_id)
    if not user_data:
        return {"connected": False}
    return {
        "connected": True,
        "workspace_name": user_data.workspace_name,
        "parent_page_id": user_data.parent_page_id,
        "parent_page_title": user_data.parent_page_title,
    }


@app.post("/notion/set-parent", tags=["Notion"])
async def set_notion_parent(
    body: SetNotionParentRequest,
    _: None = Depends(verify_api_key),
):
    """Set the Notion parent page for a user."""
    user_data = notion_get_user(body.user_id)
    if not user_data:
        raise HTTPException(status_code=404, detail="User has not connected Notion")

    user_data.parent_page_id = body.page_id
    user_data.parent_page_title = body.page_title
    notion_save_user(body.user_id, user_data)

    return {"success": True}


@app.post("/notion/disconnect", tags=["Notion"])
async def disconnect_notion(
    user_id: str,
    _: None = Depends(verify_api_key),
):
    """Disconnect Notion for a user."""
    notion_delete_user(user_id)
    return {"success": True}


@app.get("/notion/pages", tags=["Notion"])
async def list_notion_pages(
    user_id: str,
    _: None = Depends(verify_api_key),
):
    """List top-level pages from user's Notion workspace for parent page selection."""
    import httpx as httpx_lib

    user_data = notion_get_user(user_id)
    if not user_data:
        raise HTTPException(status_code=404, detail="User has not connected Notion")

    async with httpx_lib.AsyncClient() as client:
        resp = await client.post(
            "https://api.notion.com/v1/search",
            headers={
                "Authorization": f"Bearer {user_data.access_token}",
                "Notion-Version": "2022-06-28",
            },
            json={"filter": {"property": "object", "value": "page"}, "page_size": 50},
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=400, detail="Failed to list Notion pages")

    results = resp.json().get("results", [])
    pages = []
    for page in results:
        title_parts = page.get("properties", {}).get("title", {}).get("title", [])
        title = "".join(t.get("plain_text", "") for t in title_parts) if title_parts else "Untitled"
        pages.append({"id": page["id"], "title": title})

    return {"pages": pages}


# ============================================
# Unified Capture Endpoint (Notes + Camera)
# ============================================

async def process_capture_and_notify(
    job_id: str, image: Optional[str], text: Optional[str],
    user_id: str, source: str
):
    """
    Background task: Classify intent, then route to Calendar (existing) or Notion agent.
    """
    job_short = job_id[:8]
    start_time = time.time()

    def log(msg: str):
        ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
        print(f"[{ts}] [{job_short}] {msg}", flush=True)

    log(f"Started capture processing (source: {source})")

    device_info = device_tokens.get(user_id)
    device_token = device_info.token if device_info else None
    use_sandbox = device_info.is_sandbox if device_info else False

    created_at = pending_jobs.get(job_id, {}).get(
        "created_at", datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    )

    try:
        # Step 1: Intent classification
        intent_result = await openai_service.classify_intent(
            base64_image=image, text=text, source=source
        )
        intent = intent_result["intent"]
        log(f"Intent: {intent} (confidence: {intent_result['confidence']})")

        # Step 2: Route
        if intent == "calendar":
            if image:
                log("Routing to calendar (image)")
                async with openai_semaphore:
                    analysis_result = await openai_service.analyze_screenshot(
                        image, source=source, context=text
                    )

                if not analysis_result.found_events or not analysis_result.events:
                    pending_jobs[job_id] = {
                        "user_id": user_id, "status": "completed",
                        "events": [], "message": "No events found", "created_at": created_at,
                    }
                    if device_token:
                        await apns_service.send_no_events_notification(
                            device_token, job_id=job_id, use_sandbox=use_sandbox
                        )
                    return

                pending_jobs[job_id] = {
                    "user_id": user_id, "status": "completed",
                    "events": analysis_result.events,
                    "message": f"Found {len(analysis_result.events)} event(s)",
                    "created_at": created_at,
                }
                if device_token:
                    await apns_service.send_event_created_notification(
                        device_token, analysis_result.events,
                        job_id=job_id, use_sandbox=use_sandbox
                    )
            else:
                log("Routing to calendar (text-only)")
                async with openai_semaphore:
                    analysis_result = await openai_service.analyze_text_for_events(text, source=source)

                if not analysis_result.found_events or not analysis_result.events:
                    pending_jobs[job_id] = {
                        "user_id": user_id, "status": "completed",
                        "events": [], "message": "No events found", "created_at": created_at,
                    }
                    if device_token:
                        await apns_service.send_no_events_notification(
                            device_token, job_id=job_id, use_sandbox=use_sandbox
                        )
                    return

                pending_jobs[job_id] = {
                    "user_id": user_id, "status": "completed",
                    "events": analysis_result.events,
                    "message": f"Found {len(analysis_result.events)} event(s)",
                    "created_at": created_at,
                }
                if device_token:
                    await apns_service.send_event_created_notification(
                        device_token, analysis_result.events,
                        job_id=job_id, use_sandbox=use_sandbox
                    )

        elif intent == "notion":
            notion_user = notion_get_user(user_id)
            if not notion_user or not notion_user.parent_page_id:
                log("Notion not configured — falling back to calendar flow")
                if image:
                    async with openai_semaphore:
                        analysis_result = await openai_service.analyze_screenshot(
                            image, source=source, context=text
                        )
                    events = analysis_result.events if analysis_result.found_events else []
                else:
                    async with openai_semaphore:
                        analysis_result = await openai_service.analyze_text_for_events(text, source=source)
                    events = analysis_result.events if analysis_result.found_events else []

                pending_jobs[job_id] = {
                    "user_id": user_id, "status": "completed",
                    "events": events,
                    "message": f"Found {len(events)} event(s) (Notion not configured)",
                    "created_at": created_at,
                }
                if device_token and events:
                    await apns_service.send_event_created_notification(
                        device_token, events, job_id=job_id, use_sandbox=use_sandbox
                    )
                elif device_token:
                    await apns_service.send_no_events_notification(
                        device_token, job_id=job_id, use_sandbox=use_sandbox
                    )
                return

            content_for_agent = text or ""
            if image:
                async with openai_semaphore:
                    extracted = await openai_service.extract_text_only(image)
                content_for_agent = f"{content_for_agent}\n\n[Image content]: {extracted}".strip()

            log(f"Routing to Notion agent (parent: {notion_user.parent_page_id[:12]}...)")
            result = await notion_agent.execute(
                access_token=notion_user.access_token,
                parent_page_id=notion_user.parent_page_id,
                content=content_for_agent,
                source=source,
            )

            pending_jobs[job_id] = {
                "user_id": user_id,
                "status": "completed" if result["success"] else "failed",
                "events": [],
                "notion_result": result,
                "message": result["summary"],
                "created_at": created_at,
            }

            if device_token:
                if result["success"]:
                    await apns_service.send_notion_saved_notification(
                        device_token, result["summary"],
                        job_id=job_id, use_sandbox=use_sandbox
                    )
                else:
                    await apns_service.send_error_notification(
                        device_token, result["summary"],
                        job_id=job_id, use_sandbox=use_sandbox
                    )

    except Exception as e:
        import traceback
        log(f"ERROR: {e}")
        log(f"Traceback: {traceback.format_exc()}")
        pending_jobs[job_id] = {
            "user_id": user_id, "status": "failed",
            "error": str(e), "created_at": created_at,
        }
        if device_token:
            await apns_service.send_error_notification(
                device_token, str(e), job_id=job_id, use_sandbox=use_sandbox
            )
    finally:
        elapsed = time.time() - start_time
        log(f"Completed in {elapsed:.1f}s")


@app.post(
    "/analyze-capture-async",
    response_model=AsyncAnalyzeResponse,
    tags=["Capture"],
)
@limiter.limit(f"{RATE_LIMIT_PER_MINUTE}/minute")
async def analyze_capture_async(
    request: Request,
    body: AnalyzeCaptureRequest,
    background_tasks: BackgroundTasks,
    _: None = Depends(verify_api_key),
):
    """
    Unified capture endpoint — accepts image and/or text.
    Intent layer routes to Calendar or Notion automatically.
    """
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"\n[{timestamp}] === NEW UNIFIED CAPTURE REQUEST ===", flush=True)

    if not body.image and not body.text:
        raise HTTPException(status_code=400, detail="Either image or text is required")

    if body.image:
        validate_image_size(body.image)

    allowed, error_msg = daily_tracker.check_and_increment(body.user_id)
    if not allowed:
        raise HTTPException(status_code=429, detail=error_msg)

    cleanup_expired_jobs()

    job_id = str(uuid.uuid4())
    pending_jobs[job_id] = {
        "user_id": body.user_id, "status": "processing", "created_at": timestamp
    }

    background_tasks.add_task(
        process_capture_and_notify,
        job_id=job_id,
        image=body.image,
        text=body.text,
        user_id=body.user_id,
        source=body.source,
    )

    print(f"[{timestamp}] Job queued: {job_id[:8]}...", flush=True)

    return AsyncAnalyzeResponse(
        success=True, job_id=job_id,
        message="Processing started. You'll receive a notification when complete.",
    )


# ============================================
# Run Server
# ============================================

if __name__ == "__main__":
    import uvicorn
    
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    debug = os.getenv("DEBUG", "false").lower() == "true"
    
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        reload=debug,
    )
