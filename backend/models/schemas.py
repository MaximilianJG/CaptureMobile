"""
Pydantic schemas for request/response validation.
"""

from pydantic import BaseModel, Field
from typing import Optional, List
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
    source_app: Optional[str] = Field(None, description="Source app the screenshot was taken from")


class AnalyzeScreenshotResponse(BaseModel):
    """Response from screenshot analysis endpoint."""
    success: bool = Field(..., description="Whether the operation was successful")
    events_created: List[EventDetails] = Field(default_factory=list, description="List of created events")
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
    title: str = Field(..., description="Event title")  # Required
    date: str = Field(..., description="Event date (YYYY-MM-DD format)")  # Required
    start_time: Optional[str] = Field(None, description="Start time (HH:MM format, 24h)")
    end_time: Optional[str] = Field(None, description="End time (HH:MM format, 24h)")
    location: Optional[str] = Field(None, description="Event location if mentioned")
    description: Optional[str] = Field(None, description="Additional details or notes")
    timezone: Optional[str] = Field("Europe/Berlin", description="Timezone if mentioned")
    is_all_day: bool = Field(False, description="Whether this is an all-day event")
    is_deadline: bool = Field(False, description="Whether this is a deadline event")
    confidence: float = Field(default=0.5, ge=0.0, le=1.0, description="Confidence score 0-1")
    attendee_name: Optional[str] = Field(None, description="Name of the other person involved")
    source_app: Optional[str] = Field(None, description="Source app detected from screenshot (e.g., WhatsApp, Instagram)")


class OpenAIAnalysisResult(BaseModel):
    """Result from OpenAI screenshot analysis - supports multiple events."""
    found_events: bool = Field(..., description="Whether any events were found in the image")
    event_count: int = Field(default=0, description="Number of events detected")
    events: List[ExtractedEventInfo] = Field(default_factory=list, description="List of extracted event information")
    raw_text: Optional[str] = Field(None, description="Any relevant text extracted from image")
