"""
Capture Backend - Screenshot to Calendar Event API

This FastAPI server receives screenshots, analyzes them with OpenAI Vision
to extract event information, and creates events in Google Calendar.
"""

import os
from datetime import datetime
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
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

# Initialize services
openai_service = OpenAIService()
calendar_service = GoogleCalendarService()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    print("🚀 Capture Backend starting up...")
    print(f"📍 OpenAI configured: {bool(os.getenv('OPENAI_API_KEY'))}")
    print(f"📍 Google Client ID configured: {bool(os.getenv('GOOGLE_CLIENT_ID'))}")
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

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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
async def analyze_screenshot(request: AnalyzeScreenshotRequest):
    """
    Analyze a screenshot for event information and create a calendar event.
    
    This endpoint:
    1. Validates the Google OAuth token
    2. Sends the image to OpenAI Vision for analysis
    3. Extracts event details (title, date, time, location)
    4. Creates an event in the user's Google Calendar
    
    Args:
        request: Contains base64 encoded image and Google OAuth access token
        
    Returns:
        Success status, created event details, and status message
    """
    try:
        # Step 1: Validate Google token and get user info
        user_info = await calendar_service.validate_token(request.access_token)
        if not user_info:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired Google access token"
            )
        
        print(f"📸 Processing screenshot for user: {user_info.get('email', 'unknown')}")
        
        # Step 2: Analyze screenshot with OpenAI Vision
        analysis_result = await openai_service.analyze_screenshot(request.image)
        
        if not analysis_result.found_event:
            return AnalyzeScreenshotResponse(
                success=False,
                event_created=None,
                message="No event information found in the screenshot. Please try a clearer image."
            )
        
        event_info = analysis_result.event_info
        print(f"🎯 Found event: {event_info.title} on {event_info.date}")
        
        # Step 3: Create calendar event
        created_event = await calendar_service.create_event(
            access_token=request.access_token,
            event_info=event_info
        )
        
        if not created_event:
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
            calendar_link=created_event.get("htmlLink")
        )
        
        return AnalyzeScreenshotResponse(
            success=True,
            event_created=event_details,
            message=f"Event '{event_info.title}' created successfully!"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Error processing screenshot: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process screenshot: {str(e)}"
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
