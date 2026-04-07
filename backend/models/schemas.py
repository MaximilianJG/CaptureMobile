"""
Pydantic schemas for request/response validation.
"""

from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List


class CaptureRequest(BaseModel):
    """Request body for the capture endpoint."""
    image: Optional[str] = Field(None, description="Base64 encoded image data")
    text: Optional[str] = Field(None, description="Free-form text (notes)")
    user_id: str = Field(..., description="Supabase user UUID")
    source: str = Field("notes", description="Capture source: 'notes', 'camera', or 'screenshot'")


class CaptureData(BaseModel):
    """A capture record returned from the database."""
    id: str
    capture_title: str
    category: str
    capture_method: str
    time_captured: str
    extracted_data: Dict[str, Any] = {}
    image_url: Optional[str] = None
    tags: List[str] = []


class AsyncCaptureResponse(BaseModel):
    """Response from async capture endpoint."""
    success: bool
    job_id: str
    message: str


class JobStatusResponse(BaseModel):
    """Response from job status endpoint."""
    job_id: str
    status: str
    capture: Optional[CaptureData] = None
    error: Optional[str] = None


class HealthResponse(BaseModel):
    """Response from health check endpoint."""
    status: str
    timestamp: str


class RegisterDeviceRequest(BaseModel):
    """Request body for device token registration."""
    user_id: str = Field(..., description="Supabase user UUID")
    device_token: str = Field(..., description="APNs device token")
    is_sandbox: bool = Field(default=False, description="True if this is a debug/sandbox build")


class CreateTagRequest(BaseModel):
    """Request body for creating a user tag."""
    user_id: str = Field(..., description="Supabase user UUID")
    name: str = Field(..., description="Tag name")


class TagData(BaseModel):
    """A user tag record."""
    id: str
    user_id: str
    name: str
