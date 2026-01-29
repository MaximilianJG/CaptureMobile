"""
OpenAI Vision Service for screenshot analysis.

Uses GPT-4 Vision to analyze screenshots and extract event information.
"""

import os
import json
import base64
from datetime import datetime
from typing import Optional, List

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
                                "text": "Analyze this screenshot thoroughly. Look for ALL calendar-worthy events - there may be multiple events in a single screenshot. Examine the ENTIRE image for context - who is involved (sender names, profiles), what each event is about (subject, purpose), and any relevant details. Extract ALL event information and include meaningful context in the title and description of each. Respond with the JSON format specified."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": base64_image,
                                    "detail": "auto"  # auto is faster, high only needed for tiny text
                                }
                            }
                        ]
                    }
                ],
                max_tokens=2000,  # Increased for multiple events
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
                found_events=False,
                event_count=0,
                events=[],
                raw_text=f"Analysis failed: {str(e)}"
            )
    
    def _get_system_prompt(self) -> str:
        """Get the system prompt for event extraction."""
        # Get current date/time context
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")
        day_of_week = now.strftime("%A")
        current_year = now.year
        
        return f"""You are an expert at analyzing images and extracting calendar-worthy information.

TODAY'S DATE: {today_str} ({day_of_week})
CURRENT YEAR: {current_year}

Your task is to look at screenshots and identify anything that should go on a calendar.

=== WHAT TO LOOK FOR ===
- Events, meetings, appointments, scheduled activities
- DEADLINES ("due by", "closes at", "submit before", "deadline", "last day")
- Reminders about time-sensitive actions
- Reservations, bookings, tickets with dates/times
- Any date + time combination that someone would want to remember

=== EXTRACT THESE DETAILS ===
- Title/subject
- Date (specific or relative like "tomorrow", "next Monday")
- Time (even if phrased as "at 2pm", "by 5pm", "before noon")
- Location if mentioned
- Additional context

=== CONTEXT DISCOVERY ===
Examine the ENTIRE screenshot to gather context, not just the event details:

LOOK FOR:
- WHO: Names, profile pictures, email addresses, usernames, sender info
- WHAT: Subject lines, message content, event purpose, meeting agenda
- WHERE: App name (Messages, WhatsApp, Email, etc.), website, platform
- WHY: Any indication of the meeting's purpose or topic
- SOURCE APP: Identify the app from UI elements, colors, layout, icons

CONTEXTUAL CLUES:
- Message sender name → likely the other attendee
- Email "From:" field → who scheduled/invited
- Chat conversation → may reveal meeting purpose
- Profile names in scheduling apps → attendee names
- Subject lines → meeting topic for title
- Thread context → why the meeting is happening

SOURCE APP DETECTION (set source_app field):
- Green chat bubbles, green header → "WhatsApp"
- Blue chat bubbles (iMessage style) → "iMessage"
- Instagram DM interface → "Instagram"
- Gmail/Google Mail interface → "Gmail"
- Outlook interface → "Outlook"
- LinkedIn messages → "LinkedIn"
- Slack interface → "Slack"
- Teams interface → "Microsoft Teams"
- Calendar app → "Calendar"
- Notes app → "Notes"
- Twitter/X DMs → "Twitter"
- Facebook Messenger → "Messenger"
- Telegram interface → "Telegram"
- If unclear or unknown → null

=== DEADLINE HANDLING ===
Deadlines ARE events! They belong on a calendar. Mark them with is_deadline: true.
- Set is_deadline: true for any deadline, due date, or submission cutoff
- STILL extract the time even for deadlines (e.g., "Due by 5pm" → start_time: "17:00")
- Prefix the title with "Deadline: " (e.g., "Deadline: Project Submission")

Examples:
- "Platform closes at 2pm" → is_deadline: true, start_time: "14:00"
- "Due by 5pm" → is_deadline: true, start_time: "17:00"
- "Submit before midnight" → is_deadline: true, start_time: "23:59"
- "Assignment due Friday" (no time) → is_deadline: true, start_time: null

=== TIMEZONE HANDLING ===
Extract timezone from context and map to standard format:
- "(Paris time)", "(CET)", "(Central European)" → "Europe/Paris"
- "(Berlin time)", "(German time)" → "Europe/Berlin"
- "(London time)", "(GMT)", "(UK time)" → "Europe/London"
- "(EST)", "(Eastern)", "(New York)" → "America/New_York"
- "(PST)", "(Pacific)", "(LA time)" → "America/Los_Angeles"
- If no timezone mentioned → "Europe/Berlin"

=== DATE RULES ===
- Today is {today_str} ({day_of_week})
- "Tomorrow" = the day after {today_str}
- "Next Monday" = the coming Monday after today
- "This weekend" = the upcoming Saturday/Sunday
- Day name only (e.g., "Friday") = NEXT occurrence of that day
- Month + day only (e.g., "March 15") = {current_year}, or {current_year + 1} if passed
- No year specified = assume {current_year}

DATE FORMAT INTERPRETATION (IMPORTANT):
- Default to EUROPEAN format: DD-MM-YYYY or DD/MM/YYYY (day first, then month)
- "07-03-2026" or "07/03/2026" = March 7th, 2026 (NOT July 3rd)
- "15-01-2026" or "15/01/2026" = January 15th, 2026
- Only use US format (MM-DD-YYYY) if the context is clearly American (US locations, US websites)
- When the day number is > 12, it's unambiguous (e.g., "25-12-2026" = December 25th)
- European locations (Paris, Berlin, London, etc.) = use European date format
- If unsure, assume European format since default timezone is Europe/Berlin

=== CONTEXT REASONING ===
After gathering context, reason about what to include:

1. TITLE: Should be descriptive and meaningful. Include:
   - The purpose/topic if clear (e.g., "Coffee with Sarah" not just "Meeting")
   - The person's name if it's a 1:1 (e.g., "Call with John")
   - Context that makes the event recognizable at a glance

2. DESCRIPTION: Include relevant context like:
   - Who suggested/organized it
   - Brief purpose if mentioned
   - Any preparation needed
   - Source app (e.g., "Via WhatsApp message")

3. ATTENDEE: Extract the other person's name if identifiable from:
   - Sender name, profile name, email address, or mention in text

DO NOT include:
- Irrelevant UI elements
- Unrelated messages in the screenshot
- Personal information beyond what's needed for the event

=== MULTIPLE EVENTS ===
Screenshots may contain MULTIPLE calendar-worthy items. Look for ALL of them:
- A list of upcoming appointments or meetings
- Multiple messages about different events in a chat
- Calendar views showing several events
- Emails or messages with multiple dates mentioned
- To-do lists with multiple deadlines
- Event listings or schedules

Return ALL events found as separate items in the events array, not just the first one.

=== OUTPUT FORMAT ===
- Times in 24-hour format (HH:MM)
- Dates in YYYY-MM-DD format
- All dates must be absolute (no relative dates in output)

Respond ONLY with JSON:
{{
    "found_events": true/false,
    "event_count": N,
    "events": [
        {{
            "title": "Descriptive Event Title (include person/purpose)",
            "date": "YYYY-MM-DD",
            "start_time": "HH:MM" or null,
            "end_time": "HH:MM" or null,
            "location": "Location" or null,
            "description": "Relevant context: who organized, purpose, source app" or null,
            "timezone": "Europe/Berlin",
            "is_all_day": true/false,
            "is_deadline": true/false,
            "confidence": 0.0-1.0,
            "attendee_name": "Name of the other person involved" or null,
            "source_app": "WhatsApp/Instagram/Gmail/etc" or null
        }}
    ],
    "raw_text": "Relevant text from the image"
}}

If nothing calendar-worthy is found, set found_events to false and events to an empty array [].
If ONE event is found, event_count should be 1 and events should contain one item.
If MULTIPLE events are found, event_count should match the array length.

Be thorough - if there's a date and time mentioned, it probably belongs on a calendar!"""
    
    def _parse_response(self, result: dict) -> OpenAIAnalysisResult:
        """Parse the OpenAI response into our schema - supports multiple events."""
        found_events = result.get("found_events", False)
        events_data = result.get("events", [])
        raw_text = result.get("raw_text")
        
        parsed_events: List[ExtractedEventInfo] = []
        
        if found_events and events_data:
            for event_info_data in events_data:
                # Date is required - if missing, skip this event
                date = event_info_data.get("date")
                if not date:
                    print("⚠️ No date found in event info - skipping event")
                    continue
                
                # Title fallback
                title = event_info_data.get("title") or "Event"
                
                # Smart is_all_day: if no start_time provided, treat as all-day
                start_time = event_info_data.get("start_time")
                is_all_day = event_info_data.get("is_all_day", False)
                if not start_time and not is_all_day:
                    is_all_day = True
                
                try:
                    event_info = ExtractedEventInfo(
                        title=title,
                        date=date,
                        start_time=start_time,
                        end_time=event_info_data.get("end_time"),
                        location=event_info_data.get("location"),
                        description=event_info_data.get("description"),
                        timezone=event_info_data.get("timezone", "Europe/Berlin"),
                        is_all_day=is_all_day,
                        is_deadline=event_info_data.get("is_deadline", False),
                        confidence=event_info_data.get("confidence", 0.5),
                        attendee_name=event_info_data.get("attendee_name"),
                        source_app=event_info_data.get("source_app"),
                    )
                    parsed_events.append(event_info)
                except Exception as e:
                    print(f"Failed to parse event info: {e}")
                    continue
        
        return OpenAIAnalysisResult(
            found_events=len(parsed_events) > 0,
            event_count=len(parsed_events),
            events=parsed_events,
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
