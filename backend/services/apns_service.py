"""
Apple Push Notification Service (APNs) integration.

Sends push notifications to iOS devices when screenshot processing completes.
"""

import os
from typing import Optional, Dict, Any

# APNs client (optional - only used if configured)
try:
    from aioapns import APNs, NotificationRequest, PushType
    APNS_AVAILABLE = True
except ImportError:
    APNS_AVAILABLE = False
    print("⚠️ aioapns not installed - push notifications disabled")


class APNsService:
    """Service for sending Apple Push Notifications."""
    
    def __init__(self):
        self.client: Optional[Any] = None
        self.bundle_id: str = ""
        
        if not APNS_AVAILABLE:
            print("⚠️ APNs not available - aioapns package not installed")
            return
        
        # Get configuration from environment
        key_path = os.getenv("APNS_KEY_PATH")  # Path to .p8 file
        key_content = os.getenv("APNS_KEY_CONTENT")  # Or base64-encoded key content
        key_id = os.getenv("APNS_KEY_ID")
        team_id = os.getenv("APNS_TEAM_ID")
        self.bundle_id = os.getenv("APNS_BUNDLE_ID", "")
        use_sandbox = os.getenv("APNS_SANDBOX", "true").lower() == "true"
        
        # Determine the key source
        key_source = None
        if key_path and os.path.exists(key_path):
            key_source = key_path
        elif key_content:
            import base64
            import tempfile
            try:
                # Check if content is already the raw key (starts with -----BEGIN)
                if key_content.strip().startswith("-----BEGIN"):
                    # Raw key content provided directly
                    key_text = key_content.strip()
                    print(f"📝 APNs key provided as raw PEM content")
                else:
                    # Base64 encoded - strip all whitespace and decode
                    cleaned_content = key_content.replace('\n', '').replace('\r', '').replace(' ', '')
                    key_bytes = base64.b64decode(cleaned_content)
                    key_text = key_bytes.decode('utf-8')
                    print(f"📝 APNs key decoded from base64")
                
                # Validate the key looks correct
                if "-----BEGIN PRIVATE KEY-----" not in key_text:
                    print(f"❌ APNs key doesn't look like a valid .p8 file")
                    print(f"   Key starts with: {key_text[:50]}...")
                else:
                    # Write to temp file
                    temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.p8', delete=False)
                    temp_file.write(key_text)
                    temp_file.close()
                    key_source = temp_file.name
                    print(f"✅ APNs key written to temp file")
            except Exception as e:
                print(f"❌ Failed to process APNS_KEY_CONTENT: {e}")
                import traceback
                traceback.print_exc()
        
        if key_source and key_id and team_id and self.bundle_id:
            try:
                self.client = APNs(
                    key=key_source,
                    key_id=key_id,
                    team_id=team_id,
                    topic=self.bundle_id,
                    use_sandbox=use_sandbox
                )
                env_type = "sandbox" if use_sandbox else "production"
                print(f"✅ APNs configured ({env_type}) for {self.bundle_id}")
            except Exception as e:
                print(f"❌ Failed to initialize APNs: {e}")
                self.client = None
        else:
            missing = []
            if not key_source: missing.append("APNS_KEY_PATH or APNS_KEY_CONTENT")
            if not key_id: missing.append("APNS_KEY_ID")
            if not team_id: missing.append("APNS_TEAM_ID")
            if not self.bundle_id: missing.append("APNS_BUNDLE_ID")
            print(f"⚠️ APNs not configured - missing: {', '.join(missing)}")
    
    @property
    def is_configured(self) -> bool:
        """Check if APNs is properly configured."""
        return self.client is not None
    
    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        data: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Send a push notification to an iOS device.
        
        Args:
            device_token: The APNs device token
            title: Notification title
            body: Notification body text
            data: Additional data payload (will be included in userInfo)
            
        Returns:
            True if sent successfully, False otherwise
        """
        if not self.client:
            print(f"⚠️ Cannot send push - APNs not configured")
            return False
        
        try:
            # Build the notification payload
            payload = {
                "aps": {
                    "alert": {
                        "title": title,
                        "body": body
                    },
                    "sound": "default",
                    "content-available": 1,  # Enable background processing
                    "mutable-content": 1     # Allow notification service extension
                }
            }
            
            # Add custom data to the payload
            if data:
                payload.update(data)
            
            request = NotificationRequest(
                device_token=device_token,
                message=payload,
                push_type=PushType.ALERT
            )
            
            response = await self.client.send_notification(request)
            
            if response.is_successful:
                print(f"✅ Push notification sent: {title}")
                return True
            else:
                print(f"❌ Push notification failed: {response.description}")
                return False
                
        except Exception as e:
            print(f"❌ Error sending push notification: {e}")
            return False
    
    async def send_event_created_notification(
        self,
        device_token: str,
        events: list,
    ) -> bool:
        """
        Send a notification when events are successfully created.
        
        Args:
            device_token: The APNs device token
            events: List of ExtractedEventInfo objects
            
        Returns:
            True if sent successfully, False otherwise
        """
        if not events:
            return False
        
        # Build title and body
        if len(events) == 1:
            title = "Event Created"
            body = events[0].title if hasattr(events[0], 'title') else str(events[0].get('title', 'New Event'))
        else:
            title = f"{len(events)} Events Created"
            # Get first event title
            first_title = events[0].title if hasattr(events[0], 'title') else str(events[0].get('title', 'Event'))
            body = f"{first_title} and {len(events) - 1} more"
        
        # Convert events to dict for payload
        events_data = []
        for event in events:
            if hasattr(event, 'model_dump'):
                events_data.append(event.model_dump())
            elif hasattr(event, 'dict'):
                events_data.append(event.dict())
            else:
                events_data.append(event)
        
        data = {
            "action": "create_events",
            "events": events_data
        }
        
        return await self.send_notification(device_token, title, body, data)
    
    async def send_no_events_notification(self, device_token: str) -> bool:
        """Send a notification when no events were found in the screenshot."""
        return await self.send_notification(
            device_token=device_token,
            title="No Events Found",
            body="Couldn't detect events in the screenshot",
            data={"action": "no_events"}
        )
    
    async def send_error_notification(self, device_token: str, error_message: str) -> bool:
        """Send a notification when processing failed."""
        # Truncate error message if too long
        truncated_error = error_message[:100] + "..." if len(error_message) > 100 else error_message
        
        return await self.send_notification(
            device_token=device_token,
            title="Capture Failed",
            body=truncated_error,
            data={"action": "error", "error": error_message}
        )


# Global instance
apns_service = APNsService()
