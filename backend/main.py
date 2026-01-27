"""
Capture Backend - Screenshot to Calendar Event API

This FastAPI server receives screenshots, analyzes them with OpenAI Vision
to extract event information, and creates events in Google Calendar.
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
    EventDetails,
)
from services.openai_service import OpenAIService
from services.calendar_service import GoogleCalendarService

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
    
    def check_and_increment(self, user_email: str) -> tuple[bool, str]:
        """
        Check if request is allowed and increment counters.
        Returns (allowed: bool, error_message: str)
        """
        self._reset_if_new_day()
        
        # Check global daily limit
        if self.global_count >= GLOBAL_DAILY_LIMIT:
            return False, f"Daily limit reached ({GLOBAL_DAILY_LIMIT} requests). Try again tomorrow."
        
        # Check per-user daily limit
        if self.user_counts[user_email] >= PER_USER_DAILY_LIMIT:
            return False, f"You've reached your daily limit ({PER_USER_DAILY_LIMIT} captures). Try again tomorrow."
        
        # Increment counters
        self.global_count += 1
        self.user_counts[user_email] += 1
        
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
calendar_service = GoogleCalendarService()


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
    print(f"📍 Google Client ID configured: {bool(os.getenv('GOOGLE_CLIENT_ID'))}")
    print(f"🔐 API Key configured: {bool(API_SECRET_KEY)}")
    print(f"📊 Rate limits: {RATE_LIMIT_PER_MINUTE}/min, {GLOBAL_DAILY_LIMIT}/day global, {PER_USER_DAILY_LIMIT}/day per user")
    yield
    # Shutdown
    print("👋 Capture Backend shutting down...")


# Create FastAPI app
app = FastAPI(
    title="Capture API",
    description="Screenshot to Calendar Event conversion API",
    version="1.0.0",
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
    request: AnalyzeScreenshotRequest,
    http_request: Request,
    _: None = Depends(verify_api_key),
):
    """
    Analyze a screenshot for event information and create a calendar event.
    
    This endpoint:
    1. Verifies API key (X-API-Key header)
    2. Checks rate limits (per-minute and daily)
    3. Validates the Google OAuth token
    4. Sends the image to OpenAI Vision for analysis
    5. Extracts event details (title, date, time, location)
    6. Creates an event in the user's Google Calendar
    
    Args:
        request: Contains base64 encoded image and Google OAuth access token
        
    Returns:
        Success status, created event details, and status message
    """
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"\n{'='*50}")
    print(f"[{timestamp}] 📸 NEW CAPTURE REQUEST")
    print(f"{'='*50}")
    
    try:
        # Step 0: Validate image size
        validate_image_size(request.image)
        
        # Step 1: Validate Google token and get user info
        user_info = await calendar_service.validate_token(request.access_token)
        if not user_info:
            print(f"[{timestamp}] ❌ AUTH ERROR: Invalid or expired token")
            print(f"{'='*50}\n")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired Google access token"
            )
        
        user_email = user_info.get('email', 'unknown')
        print(f"[{timestamp}] ✅ AUTH OK: {user_email}")
        
        # Step 1.5: Check daily limits
        allowed, error_msg = daily_tracker.check_and_increment(user_email)
        if not allowed:
            stats = daily_tracker.get_stats()
            print(f"[{timestamp}] ⛔ RATE LIMITED: {error_msg}")
            print(f"[{timestamp}] 📊 Stats: {stats}")
            print(f"{'='*50}\n")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=error_msg
            )
        
        # Step 2: Analyze screenshot with OpenAI Vision
        print(f"[{timestamp}] 🤖 Analyzing screenshot with AI...")
        analysis_result = await openai_service.analyze_screenshot(request.image)
        
        if not analysis_result.found_event:
            print(f"[{timestamp}] ⚠️  NO EVENT FOUND in screenshot")
            print(f"[{timestamp}] 📝 Raw text: {analysis_result.raw_text[:200] if analysis_result.raw_text else 'None'}...")
            print(f"{'='*50}\n")
            return AnalyzeScreenshotResponse(
                success=False,
                event_created=None,
                message="No event information found in the screenshot. Please try a clearer image."
            )
        
        event_info = analysis_result.event_info
        source_app = getattr(event_info, 'source_app', None)
        print(f"[{timestamp}] ✅ EVENT DETECTED:")
        print(f"    📌 Title: {event_info.title or 'Untitled'}")
        print(f"    📅 Date: {event_info.date or 'Unknown'}")
        print(f"    🕐 Time: {event_info.start_time or 'All day'} - {event_info.end_time or 'N/A'}")
        print(f"    📍 Location: {event_info.location or 'None'}")
        print(f"    👤 Attendee: {getattr(event_info, 'attendee_name', None) or 'None'}")
        print(f"    📱 SOURCE APP: {source_app or 'NOT DETECTED'}")
        print(f"    🎯 Confidence: {(event_info.confidence or 0.5):.0%}")
        if analysis_result.raw_text:
            print(f"    📝 Raw text: {analysis_result.raw_text[:150]}...")
        
        # Step 3: Create calendar event
        print(f"[{timestamp}] 📅 Creating calendar event...")
        created_event = await calendar_service.create_event(
            access_token=request.access_token,
            event_info=event_info
        )
        
        if not created_event:
            print(f"[{timestamp}] ❌ CALENDAR ERROR: Failed to create event")
            print(f"{'='*50}\n")
            return AnalyzeScreenshotResponse(
                success=False,
                event_created=None,
                message="Event detected but failed to create in Google Calendar."
            )
        
        # Step 4: Return success response
        # Build start_time string
        start_time_str = event_info.date
        if event_info.start_time:
            start_time_str += "T" + event_info.start_time
        
        # Build end_time string (can be None)
        end_time_str = None
        if event_info.end_time:
            end_time_str = event_info.date + "T" + event_info.end_time
        
        event_details = EventDetails(
            id=created_event.get("id"),
            title=event_info.title,
            start_time=start_time_str,
            end_time=end_time_str,
            location=event_info.location,
            description=event_info.description,
            calendar_link=created_event.get("htmlLink"),
            source_app=event_info.source_app
        )
        
        print(f"[{timestamp}] ✅ SUCCESS: Event created!")
        print(f"    🔗 Link: {created_event.get('htmlLink')}")
        print(f"{'='*50}\n")
        
        return AnalyzeScreenshotResponse(
            success=True,
            event_created=event_details,
            message=f"Event '{event_info.title}' created successfully!"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ SERVER ERROR: {str(e)}")
        print(f"{'='*50}\n")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process screenshot: {str(e)}"
        )


# ============================================
# Stats Endpoint (for monitoring)
# ============================================

@app.get("/stats", tags=["Monitoring"])
async def get_stats(http_request: Request, _: None = Depends(verify_api_key)):
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
