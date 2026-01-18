"""
Pydantic schemas for request/response validation.
"""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


# ============================================
# Request Schemas
# ============================================

class AnalyzeScreenshotRequest(BaseModel):
    """Request body for screenshot analysis endpoint."""
    image: str = Field(..., description="Base64 encoded image data")
    access_token: str = Field(..., description="Google OAuth access token")


# ============================================
# Response Schemas
# ============================================

class EventDetails(BaseModel):
    """Details of a created calendar event."""
    id: Optional[str] = Field(None, description="Google Calendar event ID")
    title: str = Field(..., description="Event title")
    start_time: str = Field(..., description="Event start time in ISO format")
    end_time: Optional[str] = Field(None, description="Event end time in ISO format")
    location: Optional[str] = Field(None, description="Event location")
    description: Optional[str] = Field(None, description="Event description")
    calendar_link: Optional[str] = Field(None, description="Link to the event in Google Calendar")


class AnalyzeScreenshotResponse(BaseModel):
    """Response from screenshot analysis endpoint."""
    success: bool = Field(..., description="Whether the operation was successful")
    event_created: Optional[EventDetails] = Field(None, description="Details of the created event")
    message: str = Field(..., description="Status message")


class HealthResponse(BaseModel):
    """Response from health check endpoint."""
    status: str = Field(..., description="Service status")
    timestamp: str = Field(..., description="Current server timestamp")


# ============================================
# OpenAI Related Schemas
# ============================================

class ExtractedEventInfo(BaseModel):
    """Event information extracted from screenshot by OpenAI."""
    title: str = Field(..., description="Event title")
    date: str = Field(..., description="Event date (YYYY-MM-DD format)")
    start_time: Optional[str] = Field(None, description="Start time (HH:MM format, 24h)")
    end_time: Optional[str] = Field(None, description="End time (HH:MM format, 24h)")
    location: Optional[str] = Field(None, description="Event location if mentioned")
    description: Optional[str] = Field(None, description="Additional details or notes")
    timezone: Optional[str] = Field("UTC", description="Timezone if mentioned")
    is_all_day: bool = Field(False, description="Whether this is an all-day event")
    confidence: float = Field(..., ge=0.0, le=1.0, description="Confidence score 0-1")
    attendee_name: Optional[str] = Field(None, description="Name of the other person involved")


class OpenAIAnalysisResult(BaseModel):
    """Result from OpenAI screenshot analysis."""
    found_event: bool = Field(..., description="Whether an event was found in the image")
    event_info: Optional[ExtractedEventInfo] = Field(None, description="Extracted event information")
    raw_text: Optional[str] = Field(None, description="Any relevant text extracted from image")
