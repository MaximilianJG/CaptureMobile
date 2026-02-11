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
    user_id: str = Field(..., description="Apple user ID for rate limiting")


class RegisterDeviceRequest(BaseModel):
    """Request body for device token registration."""
    user_id: str = Field(..., description="Apple user ID")
    device_token: str = Field(..., description="APNs device token")
    is_sandbox: bool = Field(default=False, description="True if this is a debug/sandbox build")


# ============================================
# Response Schemas
# ============================================

class AnalyzeScreenshotResponse(BaseModel):
    """Response from screenshot analysis endpoint - returns events for client to create."""
    success: bool = Field(..., description="Whether events were found")
    events_to_create: List["ExtractedEventInfo"] = Field(default_factory=list, description="Events for client to create locally")
    message: str = Field(..., description="Status message")


class HealthResponse(BaseModel):
    """Response from health check endpoint."""
    status: str = Field(..., description="Service status")
    timestamp: str = Field(..., description="Current server timestamp")


class AsyncAnalyzeResponse(BaseModel):
    """Response from async screenshot analysis endpoint."""
    success: bool = Field(..., description="Whether the job was queued")
    job_id: str = Field(..., description="Job ID to track status")
    message: str = Field(..., description="Status message")


class JobStatusResponse(BaseModel):
    """Response from job status endpoint."""
    job_id: str = Field(..., description="Job ID")
    status: str = Field(..., description="Job status: processing, completed, failed")
    events_to_create: Optional[List["ExtractedEventInfo"]] = Field(None, description="Events if completed")
    error: Optional[str] = Field(None, description="Error message if failed")


# ============================================
# OpenAI Related Schemas
# ============================================

class ExtractedEventInfo(BaseModel):
    """Event information extracted from screenshot by OpenAI."""
    title: str = Field(..., description="Event title")  # Required
    date: str = Field(..., description="Event start date (YYYY-MM-DD format)")  # Required
    end_date: Optional[str] = Field(None, description="Event end date for multi-day events (YYYY-MM-DD format). Only set if different from date.")
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
