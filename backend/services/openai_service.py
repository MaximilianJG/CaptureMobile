"""
OpenAI Vision Service for screenshot analysis.

Uses GPT-4 Vision to analyze screenshots and extract event information.
"""

import os
import json
import base64
from datetime import datetime
from typing import Optional

from openai import AsyncOpenAI

from models.schemas import OpenAIAnalysisResult, ExtractedEventInfo


class OpenAIService:
    """Service for analyzing screenshots using OpenAI Vision API."""
    
    def __init__(self):
        self.client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
        self.model = "gpt-4o"  # GPT-4 with vision capabilities
    
    async def analyze_screenshot(self, base64_image: str) -> OpenAIAnalysisResult:
        """
        Analyze a screenshot to extract event information.
        
        Args:
            base64_image: Base64 encoded image string
            
        Returns:
            OpenAIAnalysisResult with extracted event info
        """
        try:
            # Ensure the base64 string has the proper prefix
            if not base64_image.startswith("data:"):
                base64_image = f"data:image/jpeg;base64,{base64_image}"
            
            # Create the analysis prompt
            system_prompt = self._get_system_prompt()
            
            # Call OpenAI Vision API
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": system_prompt
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "Analyze this screenshot and extract any event information. If you find an event, extract all available details. Respond with the JSON format specified."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": base64_image,
                                    "detail": "high"
                                }
                            }
                        ]
                    }
                ],
                max_tokens=1000,
                response_format={"type": "json_object"}
            )
            
            # Parse the response
            result_text = response.choices[0].message.content
            result_json = json.loads(result_text)
            
            return self._parse_response(result_json)
            
        except Exception as e:
            print(f"OpenAI analysis error: {str(e)}")
            # Return empty result on error
            return OpenAIAnalysisResult(
                found_event=False,
                event_info=None,
                raw_text=f"Analysis failed: {str(e)}"
            )
    
    def _get_system_prompt(self) -> str:
        """Get the system prompt for event extraction."""
        # Get current date/time context
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")
        day_of_week = now.strftime("%A")
        current_year = now.year
        
        return f"""You are an expert at analyzing images and extracting event information from ANY visual source - including messaging apps, emails, posters, invitations, and more.

TODAY'S DATE: {today_str} ({day_of_week})
CURRENT YEAR: {current_year}

Your task is to look at screenshots and identify any calendar events, meetings, appointments, or scheduled activities.

=== MESSAGING APP CONTEXT ===
When analyzing chat/messaging screenshots (WhatsApp, iMessage, Telegram, etc.):
1. IDENTIFY THE CONTACT: Look for the contact name at the top of the chat or in the conversation header. This person should be included in the event title.
2. INFER THE EVENT TYPE: "Let's grab coffee" → Coffee, "dinner?" → Dinner, "meet up" → Meeting
3. BUILD A DESCRIPTIVE TITLE: Combine the activity with the person's name
   - Example: Chat with "Sarah" about "coffee tomorrow" → Title: "Coffee with Sarah"
   - Example: Chat with "Max" about "gym at 6" → Title: "Gym with Max"
4. EXTRACT IMPLICIT DETAILS:
   - "at yours" / "my place" → Location: "[Contact name]'s place" or "My place"
   - "the usual spot" → Note this in description as "usual meeting spot"
   - Emojis can indicate event type: 🍕=food, 🎬=movie, 🏋️=gym, ☕=coffee

=== WHAT TO LOOK FOR ===
- Event titles/names
- Contact/person names (from chat headers, message senders, email recipients)
- Dates (specific dates or relative like "tomorrow", "next Monday", "this Friday")
- Times (start time, end time, or just "evening", "morning", "afternoon")
- Locations (addresses, venue names, "at mine", "your place", links)
- Activity types (dinner, coffee, meeting, call, workout, etc.)

=== TIME INFERENCE ===
When exact times aren't given, make reasonable inferences:
- "morning" → 09:00
- "lunch" → 12:00
- "afternoon" → 14:00
- "evening" / "tonight" → 19:00
- "dinner" → 19:00
- "coffee" / "breakfast" → 09:00
- Just a number like "at 8" → Use context (breakfast=08:00, dinner=20:00)
- If ambiguous, prefer the more likely time based on activity type

=== DATE RULES ===
- Today is {today_str} ({day_of_week})
- "Tomorrow" = the day after {today_str}
- "Next Monday" = the coming Monday after today
- "This weekend" = the upcoming Saturday/Sunday
- "Friday" without qualifier = the NEXT Friday from today
- If only month/day given, use {current_year} unless passed, then {current_year + 1}
- If no year is specified, assume {current_year}

=== TITLE FORMATTING ===
Create human-friendly, descriptive titles:
- Include the OTHER person's name when it's a 1:1 meeting
- Include the activity type
- Good: "Dinner with Max", "Coffee with Sarah", "Call with Mom"
- Bad: "Meeting", "Event", "Appointment"

=== OUTPUT FORMAT ===
- Use 24-hour time format (HH:MM)
- Use YYYY-MM-DD format for dates
- All dates must be absolute (no relative dates in output)

Respond ONLY with a JSON object in this exact format:
{{
    "found_event": true/false,
    "event_info": {{
        "title": "Activity with Person Name",
        "date": "YYYY-MM-DD",
        "start_time": "HH:MM" or null,
        "end_time": "HH:MM" or null,
        "location": "Location" or null,
        "description": "Additional context from conversation" or null,
        "timezone": "Europe/Berlin",
        "is_all_day": true/false,
        "confidence": 0.0-1.0,
        "attendee_name": "Name of other person" or null
    }},
    "raw_text": "Relevant text from the image"
}}

If no event is found, set found_event to false and event_info to null.

Be thorough but accurate - extract the most useful calendar entry possible from the context."""
    
    def _parse_response(self, result: dict) -> OpenAIAnalysisResult:
        """Parse the OpenAI response into our schema."""
        found_event = result.get("found_event", False)
        event_info_data = result.get("event_info")
        raw_text = result.get("raw_text")
        
        event_info = None
        if found_event and event_info_data:
            try:
                event_info = ExtractedEventInfo(
                    title=event_info_data.get("title", "Untitled Event"),
                    date=event_info_data.get("date", ""),
                    start_time=event_info_data.get("start_time"),
                    end_time=event_info_data.get("end_time"),
                    location=event_info_data.get("location"),
                    description=event_info_data.get("description"),
                    timezone=event_info_data.get("timezone", "UTC"),
                    is_all_day=event_info_data.get("is_all_day", False),
                    confidence=event_info_data.get("confidence", 0.5),
                    attendee_name=event_info_data.get("attendee_name")
                )
            except Exception as e:
                print(f"Failed to parse event info: {e}")
                found_event = False
        
        return OpenAIAnalysisResult(
            found_event=found_event,
            event_info=event_info,
            raw_text=raw_text
        )
    
    async def extract_text_only(self, base64_image: str) -> str:
        """
        Extract only the text content from an image without event parsing.
        Useful for debugging or showing users what was detected.
        
        Args:
            base64_image: Base64 encoded image string
            
        Returns:
            Extracted text from the image
        """
        try:
            if not base64_image.startswith("data:"):
                base64_image = f"data:image/jpeg;base64,{base64_image}"
            
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "Extract all visible text from this image. Return just the text, nothing else."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": base64_image,
                                    "detail": "high"
                                }
                            }
                        ]
                    }
                ],
                max_tokens=500
            )
            
            return response.choices[0].message.content
            
        except Exception as e:
            return f"Text extraction failed: {str(e)}"
