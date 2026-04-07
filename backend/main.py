"""
Capture Backend — AI-powered capture classification & extraction API.

Receives screenshots/photos/notes, classifies them into categories,
extracts structured data, and stores everything in Supabase.
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
    CaptureRequest,
    CaptureData,
    AsyncCaptureResponse,
    JobStatusResponse,
    HealthResponse,
    RegisterDeviceRequest,
    CreateTagRequest,
    TagData,
)
from services.openai_service import OpenAIService
from services.supabase_service import SupabaseService
from services.apns_service import apns_service

load_dotenv()

# ============================================
# Configuration
# ============================================
RATE_LIMIT_PER_MINUTE = 100
GLOBAL_DAILY_LIMIT = 500
PER_USER_DAILY_LIMIT = 25
MAX_IMAGE_SIZE_MB = 10
MAX_CONCURRENT_OPENAI = 5

API_SECRET_KEY = os.getenv("API_SECRET_KEY", "")

# ============================================
# Rate Limiting
# ============================================
limiter = Limiter(key_func=get_remote_address)


class DailyLimitTracker:
    def __init__(self):
        self.global_count: int = 0
        self.user_counts: Dict[str, int] = defaultdict(int)
        self.current_date: date = date.today()

    def _reset_if_new_day(self):
        today = date.today()
        if today != self.current_date:
            self.global_count = 0
            self.user_counts.clear()
            self.current_date = today

    def check_and_increment(self, user_id: str) -> tuple[bool, str]:
        self._reset_if_new_day()
        if self.global_count >= GLOBAL_DAILY_LIMIT:
            return False, f"Daily limit reached ({GLOBAL_DAILY_LIMIT} requests). Try again tomorrow."
        if self.user_counts[user_id] >= PER_USER_DAILY_LIMIT:
            return False, f"You've reached your daily limit ({PER_USER_DAILY_LIMIT} captures). Try again tomorrow."
        self.global_count += 1
        self.user_counts[user_id] += 1
        return True, ""

    def get_stats(self) -> dict:
        self._reset_if_new_day()
        return {
            "global_used": self.global_count,
            "global_limit": GLOBAL_DAILY_LIMIT,
            "active_users": len(self.user_counts),
        }


daily_tracker = DailyLimitTracker()

# ============================================
# Services
# ============================================
openai_service = OpenAIService()
supabase_service = SupabaseService()
openai_semaphore = asyncio.Semaphore(MAX_CONCURRENT_OPENAI)

# ============================================
# In-Memory State
# ============================================

class DeviceInfo(NamedTuple):
    token: str
    is_sandbox: bool

device_tokens: Dict[str, DeviceInfo] = {}
pending_jobs: Dict[str, Dict[str, Any]] = {}
JOB_TTL_SECONDS = 3600


def cleanup_expired_jobs():
    now = datetime.utcnow()
    expired = [
        jid for jid, data in pending_jobs.items()
        if data.get("status") in ("completed", "failed")
        and (now - datetime.strptime(data.get("created_at", "2000-01-01 00:00:00 UTC"), "%Y-%m-%d %H:%M:%S UTC")).total_seconds() > JOB_TTL_SECONDS
    ]
    for jid in expired:
        del pending_jobs[jid]
    if expired:
        print(f"🧹 Cleaned up {len(expired)} expired job(s).")


# ============================================
# Security
# ============================================
def verify_api_key(request: Request):
    if not API_SECRET_KEY:
        return
    if request.headers.get("X-API-Key", "") != API_SECRET_KEY:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing API key")


def validate_image_size(image_base64: str):
    max_bytes = MAX_IMAGE_SIZE_MB * 1024 * 1024
    if len(image_base64) > max_bytes:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=f"Image too large. Max {MAX_IMAGE_SIZE_MB}MB.")


# ============================================
# Lifespan
# ============================================
async def periodic_job_cleanup():
    while True:
        await asyncio.sleep(300)
        cleanup_expired_jobs()


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("🚀 Capture Backend starting up...")
    print(f"📍 OpenAI configured: {bool(os.getenv('OPENAI_API_KEY'))}")
    print(f"📍 Supabase configured: {bool(os.getenv('SUPABASE_URL'))}")
    cleanup_task = asyncio.create_task(periodic_job_cleanup())
    yield
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass


app = FastAPI(
    title="Capture API",
    description="AI-powered capture classification & extraction",
    version="3.0.0",
    lifespan=lifespan,
)
app.state.limiter = limiter


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded."})


# ============================================
# Health
# ============================================
@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    return HealthResponse(status="healthy", timestamp=datetime.utcnow().isoformat())


# ============================================
# Stats
# ============================================
@app.get("/stats", tags=["Monitoring"])
async def get_stats(request: Request, _: None = Depends(verify_api_key)):
    return {"date": date.today().isoformat(), "usage": daily_tracker.get_stats()}


# ============================================
# Device Registration
# ============================================
@app.post("/register-device", tags=["Push Notifications"])
async def register_device(body: RegisterDeviceRequest, _: None = Depends(verify_api_key)):
    token = body.device_token.strip()
    if len(token) != 64:
        return {"success": False, "message": "Invalid device token format"}
    device_tokens[body.user_id] = DeviceInfo(token=token, is_sandbox=body.is_sandbox)
    return {"success": True, "message": "Device registered"}


# ============================================
# Capture (async with push notification)
# ============================================
async def process_capture(job_id: str, image: Optional[str], text: Optional[str], user_id: str, source: str):
    """Background task: classify → extract → upload image → save to Supabase → push."""
    short = job_id[:8]
    start = time.time()

    def log(msg: str):
        ts = datetime.utcnow().strftime("%H:%M:%S")
        print(f"[{ts}] [{short}] {msg}", flush=True)

    log(f"Processing capture (source: {source})")

    device_info = device_tokens.get(user_id)
    device_token = device_info.token if device_info else None
    use_sandbox = device_info.is_sandbox if device_info else False
    created_at = pending_jobs.get(job_id, {}).get("created_at", datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"))

    try:
        # Step 1: Classify
        async with openai_semaphore:
            classification = await openai_service.classify_category(
                base64_image=image, text=text, source=source,
            )
        category = classification["category"]
        title = classification["title"]

        # Step 2: Extract
        async with openai_semaphore:
            extracted_data = await openai_service.extract_data(
                base64_image=image, text=text, category=category, title=title,
            )

        # Step 3: Assign tags from user's library
        user_tags_rows = supabase_service.get_user_tags(user_id)
        available_tag_names = [t["name"] for t in user_tags_rows]
        assigned_tags: list[str] = []
        if available_tag_names:
            async with openai_semaphore:
                assigned_tags = await openai_service.assign_tags(
                    available_tags=available_tag_names,
                    category=category,
                    title=title,
                    extracted_data=extracted_data,
                    base64_image=image,
                    text=text,
                )

        # Step 4: Upload image (if present)
        image_path = None
        if image:
            image_path = supabase_service.upload_image(user_id, image)

        # Determine capture_method from source
        method_map = {"screenshot": "screenshot", "camera": "photo", "notes": "note"}
        capture_method = method_map.get(source, "note")

        # Step 5: Save to Supabase
        capture = supabase_service.create_capture(
            user_id=user_id,
            title=title,
            category=category,
            method=capture_method,
            extracted_data=extracted_data,
            image_path=image_path,
            tags=assigned_tags,
        )

        if capture:
            image_url = None
            if image_path:
                image_url = supabase_service.get_signed_url(image_path)

            capture_data = CaptureData(
                id=capture["id"],
                capture_title=title,
                category=category,
                capture_method=capture_method,
                time_captured=capture["time_captured"],
                extracted_data=extracted_data,
                image_url=image_url,
                tags=assigned_tags,
            )

            pending_jobs[job_id] = {
                "user_id": user_id,
                "status": "completed",
                "capture": capture_data.model_dump(),
                "created_at": created_at,
            }

            log(f"Saved: {category} — \"{title}\"")

            if device_token:
                await apns_service.send_capture_saved_notification(
                    device_token, title=title, category=category,
                    job_id=job_id, use_sandbox=use_sandbox,
                )
        else:
            pending_jobs[job_id] = {
                "user_id": user_id, "status": "failed",
                "error": "Failed to save capture to database", "created_at": created_at,
            }
            if device_token:
                await apns_service.send_error_notification(
                    device_token, "Failed to save capture", job_id=job_id, use_sandbox=use_sandbox,
                )

    except Exception as e:
        import traceback
        log(f"ERROR: {e}")
        log(traceback.format_exc())
        pending_jobs[job_id] = {
            "user_id": user_id, "status": "failed",
            "error": str(e), "created_at": created_at,
        }
        if device_token:
            await apns_service.send_error_notification(
                device_token, str(e), job_id=job_id, use_sandbox=use_sandbox,
            )
    finally:
        log(f"Done in {time.time() - start:.1f}s")


@app.post("/capture", response_model=AsyncCaptureResponse, tags=["Capture"])
@limiter.limit(f"{RATE_LIMIT_PER_MINUTE}/minute")
async def create_capture(
    request: Request,
    body: CaptureRequest,
    background_tasks: BackgroundTasks,
    _: None = Depends(verify_api_key),
):
    """Accept a capture (image and/or text), process in background, notify via push."""
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

    if not body.image and not body.text:
        raise HTTPException(status_code=400, detail="Either image or text is required")
    if body.image:
        validate_image_size(body.image)

    allowed, error_msg = daily_tracker.check_and_increment(body.user_id)
    if not allowed:
        raise HTTPException(status_code=429, detail=error_msg)

    cleanup_expired_jobs()

    job_id = str(uuid.uuid4())
    pending_jobs[job_id] = {"user_id": body.user_id, "status": "processing", "created_at": timestamp}

    background_tasks.add_task(
        process_capture, job_id=job_id, image=body.image, text=body.text,
        user_id=body.user_id, source=body.source,
    )

    print(f"[{timestamp}] Job queued: {job_id[:8]}...", flush=True)
    return AsyncCaptureResponse(success=True, job_id=job_id, message="Processing started.")


# ============================================
# Job Status (push recovery)
# ============================================
@app.get("/job-status/{job_id}", response_model=JobStatusResponse, tags=["Capture"])
async def get_job_status(job_id: str, _: None = Depends(verify_api_key)):
    job = pending_jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found or expired")

    capture = None
    if job.get("capture"):
        capture = CaptureData(**job["capture"])

    return JobStatusResponse(
        job_id=job_id,
        status=job.get("status", "unknown"),
        capture=capture,
        error=job.get("error"),
    )


# ============================================
# Delete Capture
# ============================================
@app.delete("/captures/{capture_id}", tags=["Capture"])
async def delete_capture(
    capture_id: str,
    user_id: str,
    _: None = Depends(verify_api_key),
):
    """Delete a capture and its associated image."""
    success = supabase_service.delete_capture(capture_id=capture_id, user_id=user_id)
    if not success:
        raise HTTPException(status_code=404, detail="Capture not found or already deleted")
    return {"success": True, "message": "Capture deleted"}


# ============================================
# Get Captures (for iOS to read)
# ============================================
@app.get("/captures", tags=["Capture"])
async def get_captures(
    user_id: str,
    category: Optional[str] = None,
    limit: int = 30,
    _: None = Depends(verify_api_key),
):
    """Fetch recent captures for a user with signed image URLs."""
    captures = supabase_service.get_captures(user_id=user_id, limit=limit, category=category)
    return {"captures": captures}


# ============================================
# User Tags
# ============================================
@app.get("/tags", tags=["Tags"])
async def get_tags(user_id: str, _: None = Depends(verify_api_key)):
    """Fetch user's tag library (seeds defaults on first access)."""
    tags = supabase_service.get_user_tags(user_id)
    return {"tags": tags}


@app.post("/tags", tags=["Tags"])
async def create_tag(body: CreateTagRequest, _: None = Depends(verify_api_key)):
    """Create a new user tag."""
    tag = supabase_service.create_user_tag(user_id=body.user_id, name=body.name)
    if not tag:
        raise HTTPException(status_code=400, detail="Failed to create tag (may already exist)")
    return {"success": True, "tag": tag}


@app.delete("/tags/{tag_id}", tags=["Tags"])
async def delete_tag(tag_id: str, user_id: str, _: None = Depends(verify_api_key)):
    """Delete a user tag."""
    success = supabase_service.delete_user_tag(tag_id=tag_id, user_id=user_id)
    if not success:
        raise HTTPException(status_code=404, detail="Tag not found")
    return {"success": True, "message": "Tag deleted"}


# ============================================
# Run
# ============================================
if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    debug = os.getenv("DEBUG", "false").lower() == "true"
    uvicorn.run("main:app", host=host, port=port, reload=debug)
