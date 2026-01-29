"""
Capture Backend - Screenshot to Calendar Event API

This FastAPI server receives screenshots, analyzes them with OpenAI Vision
to extract event information. Events are created locally by the iOS app via EventKit.
"""

import os
from datetime import datetime, date
from contextlib import asynccontextmanager
from collections import defaultdict
from typing import Dict

from fastapi import FastAPI, HTTPException, status, Request, Depends
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from dotenv import load_dotenv

from models.schemas import (
    AnalyzeScreenshotRequest,
    AnalyzeScreenshotResponse,
    HealthResponse,
)
from services.openai_service import OpenAIService

# Load environment variables
load_dotenv()

# ============================================
# Rate Limit Configuration (adjust as needed)
# ============================================
RATE_LIMIT_PER_MINUTE = 100      # Global burst limit
GLOBAL_DAILY_LIMIT = 500         # Total requests per day (hard cost ceiling)
PER_USER_DAILY_LIMIT = 25        # Requests per user per day
MAX_IMAGE_SIZE_MB = 10           # Max base64 image size in MB

# API Key for app authentication
API_SECRET_KEY = os.getenv("API_SECRET_KEY", "")

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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    print("🚀 Capture Backend starting up...")
    print(f"📍 OpenAI configured: {bool(os.getenv('OPENAI_API_KEY'))}")
    print(f"🔐 API Key configured: {bool(API_SECRET_KEY)}")
    print(f"📊 Rate limits: {RATE_LIMIT_PER_MINUTE}/min, {GLOBAL_DAILY_LIMIT}/day global, {PER_USER_DAILY_LIMIT}/day per user")
    yield
    # Shutdown
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
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"\n[{timestamp}] === NEW CAPTURE REQUEST ===")
    
    try:
        # Step 0: Validate image size
        validate_image_size(body.image)
        
        # Step 1: Check daily limits using user_id
        user_id = body.user_id
        print(f"[{timestamp}] User: {user_id[:20]}..." if len(user_id) > 20 else f"[{timestamp}] User: {user_id}")
        
        allowed, error_msg = daily_tracker.check_and_increment(user_id)
        if not allowed:
            stats = daily_tracker.get_stats()
            print(f"[{timestamp}] RATE LIMITED: {error_msg}")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=error_msg
            )
        
        # Step 2: Analyze screenshot with OpenAI Vision
        print(f"[{timestamp}] Analyzing...")
        analysis_result = await openai_service.analyze_screenshot(body.image)
        
        if not analysis_result.found_events or len(analysis_result.events) == 0:
            print(f"[{timestamp}] No events found")
            return AnalyzeScreenshotResponse(
                success=False,
                events_to_create=[],
                message="No event information found in the screenshot. Please try a clearer image."
            )
        
        # Log detected events (compact format)
        for idx, event_info in enumerate(analysis_result.events, 1):
            print(f"[{timestamp}] Event {idx}: {event_info.title} | {event_info.date} {event_info.start_time or 'all-day'}")
        
        # Step 3: Return events for client to create locally
        if len(analysis_result.events) == 1:
            message = f"Found event: '{analysis_result.events[0].title}'"
        else:
            message = f"Found {len(analysis_result.events)} events"
        
        print(f"[{timestamp}] SUCCESS: {message}")
        
        return AnalyzeScreenshotResponse(
            success=True,
            events_to_create=analysis_result.events,
            message=message
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ERROR: {str(e)}")
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
