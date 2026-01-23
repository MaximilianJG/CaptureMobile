"""
Google Calendar Service for event creation.

Uses the Google Calendar API to create events in the user's calendar.
"""

import os
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

import httpx
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from models.schemas import ExtractedEventInfo


class GoogleCalendarService:
    """Service for interacting with Google Calendar API."""
    
    def __init__(self):
        self.client_id = os.getenv("GOOGLE_CLIENT_ID")
    
    async def validate_token(self, access_token: str) -> Optional[Dict[str, Any]]:
        """
        Validate a Google OAuth access token and get user info.
        
        Args:
            access_token: Google OAuth access token
            
        Returns:
            User info dict if valid, None otherwise
        """
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    "https://www.googleapis.com/oauth2/v3/userinfo",
                    headers={"Authorization": f"Bearer {access_token}"}
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    print(f"Token validation failed: {response.status_code}")
                    return None
                    
        except Exception as e:
            print(f"Token validation error: {str(e)}")
            return None
    
    async def create_event(
        self,
        access_token: str,
        event_info: ExtractedEventInfo
    ) -> Optional[Dict[str, Any]]:
        """
        Create an event in the user's Google Calendar.
        
        Args:
            access_token: Google OAuth access token
            event_info: Extracted event information
            
        Returns:
            Created event data if successful, None otherwise
        """
        try:
            # Create credentials from access token
            credentials = Credentials(token=access_token)
            
            # Build the Calendar API service
            service = build("calendar", "v3", credentials=credentials)
            
            # Build the event body
            event_body = self._build_event_body(event_info)
            
            # Create the event
            event = service.events().insert(
                calendarId="primary",
                body=event_body
            ).execute()
            
            print(f"✅ Event created: {event.get('htmlLink')}")
            return event
            
        except HttpError as e:
            print(f"Calendar API error: {str(e)}")
            return None
        except Exception as e:
            print(f"Error creating event: {str(e)}")
            return None
    
    def _build_event_body(self, event_info: ExtractedEventInfo) -> Dict[str, Any]:
        """
        Build the Google Calendar event body from extracted info.
        
        Args:
            event_info: Extracted event information
            
        Returns:
            Event body dict for Google Calendar API
        """
        event_body: Dict[str, Any] = {
            "summary": event_info.title,
        }
        
        # Add description if available
        if event_info.description:
            event_body["description"] = event_info.description
            
        # Add location if available
        if event_info.location:
            event_body["location"] = event_info.location
        
        # Handle date/time
        timezone = event_info.timezone or "UTC"
        
        # Special handling for deadline events
        if event_info.is_deadline:
            # Deadlines are always all-day events
            event_body["start"] = {
                "date": event_info.date,
                "timeZone": timezone,
            }
            event_body["end"] = {
                "date": event_info.date,
                "timeZone": timezone,
            }
            
            # Add deadline time to description if available
            if event_info.start_time:
                deadline_time_str = self._format_time_24h(event_info.start_time)
                deadline_note = f"⏰ Deadline: {deadline_time_str}"
                if event_body.get("description"):
                    event_body["description"] = f"{deadline_note}\n\n{event_body['description']}"
                else:
                    event_body["description"] = deadline_note
            
            # Add reminder 1 day before for deadline events
            event_body["reminders"] = {
                "useDefault": False,
                "overrides": [
                    {"method": "popup", "minutes": 1440}  # 1 day = 1440 minutes
                ]
            }
        elif event_info.is_all_day:
            # Regular all-day event
            event_body["start"] = {
                "date": event_info.date,
                "timeZone": timezone,
            }
            event_body["end"] = {
                "date": event_info.date,
                "timeZone": timezone,
            }
        else:
            # Timed event
            start_datetime = self._build_datetime(
                event_info.date,
                event_info.start_time,
                timezone
            )
            
            if event_info.end_time:
                end_datetime = self._build_datetime(
                    event_info.date,
                    event_info.end_time,
                    timezone
                )
            else:
                # Default to 1 hour duration if no end time
                end_datetime = self._add_duration(start_datetime, hours=1)
            
            event_body["start"] = {
                "dateTime": start_datetime,
                "timeZone": timezone,
            }
            event_body["end"] = {
                "dateTime": end_datetime,
                "timeZone": timezone,
            }
        
        # Add a note that this was created by Capture
        note = "\n\n---\nCreated by Capture"
        if event_body.get("description"):
            event_body["description"] += note
        else:
            event_body["description"] = note.strip()
        
        return event_body
    
    def _build_datetime(
        self,
        date_str: str,
        time_str: Optional[str],
        timezone: str
    ) -> str:
        """
        Build an ISO datetime string.
        
        Args:
            date_str: Date in YYYY-MM-DD format
            time_str: Time in HH:MM format (optional)
            timezone: Timezone string
            
        Returns:
            ISO formatted datetime string
        """
        if time_str:
            return f"{date_str}T{time_str}:00"
        else:
            # Default to 9:00 AM if no time specified
            return f"{date_str}T09:00:00"
    
    def _add_duration(self, datetime_str: str, hours: int = 1) -> str:
        """
        Add duration to a datetime string.
        
        Args:
            datetime_str: ISO datetime string
            hours: Number of hours to add
            
        Returns:
            New ISO datetime string
        """
        try:
            dt = datetime.fromisoformat(datetime_str)
            dt += timedelta(hours=hours)
            return dt.isoformat()
        except:
            # If parsing fails, just return the original with hour incremented
            return datetime_str
    
    def _format_time_24h(self, time_str: str) -> str:
        """
        Format time in 24-hour format for display.
        
        Args:
            time_str: Time in HH:MM format (24h)
            
        Returns:
            Time in 24-hour format (e.g., "23:59")
        """
        try:
            hour, minute = map(int, time_str.split(":"))
            return f"{hour:02d}:{minute:02d}"
        except:
            return time_str
    
    async def list_calendars(self, access_token: str) -> list:
        """
        List user's calendars (useful for debugging).
        
        Args:
            access_token: Google OAuth access token
            
        Returns:
            List of calendar summaries
        """
        try:
            credentials = Credentials(token=access_token)
            service = build("calendar", "v3", credentials=credentials)
            
            calendar_list = service.calendarList().list().execute()
            return [
                {
                    "id": cal.get("id"),
                    "summary": cal.get("summary"),
                    "primary": cal.get("primary", False)
                }
                for cal in calendar_list.get("items", [])
            ]
            
        except Exception as e:
            print(f"Error listing calendars: {str(e)}")
            return []
    
    async def get_upcoming_events(
        self,
        access_token: str,
        max_results: int = 10
    ) -> list:
        """
        Get upcoming events from user's calendar.
        
        Args:
            access_token: Google OAuth access token
            max_results: Maximum number of events to return
            
        Returns:
            List of upcoming events
        """
        try:
            credentials = Credentials(token=access_token)
            service = build("calendar", "v3", credentials=credentials)
            
            now = datetime.utcnow().isoformat() + "Z"
            
            events_result = service.events().list(
                calendarId="primary",
                timeMin=now,
                maxResults=max_results,
                singleEvents=True,
                orderBy="startTime"
            ).execute()
            
            return events_result.get("items", [])
            
        except Exception as e:
            print(f"Error getting events: {str(e)}")
            return []
