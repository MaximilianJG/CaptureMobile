"""
Apple Push Notification Service (APNs) integration.

Uses JWT-based authentication with .p8 key file.
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
    """Service for sending Apple Push Notifications using JWT authentication."""
    
    def __init__(self):
        self._client: Optional[Any] = None
        self._initialized: bool = False
        self.bundle_id: str = ""
    
    def _ensure_initialized(self):
        """Lazy initialization - only initialize when first needed."""
        if self._initialized:
            return
        
        self._initialized = True
        
        if not APNS_AVAILABLE:
            print("⚠️ APNs not available - aioapns package not installed")
            return
        
        # Get configuration from environment
        key_id = os.getenv("APNS_KEY_ID")
        team_id = os.getenv("APNS_TEAM_ID")
        self.bundle_id = os.getenv("APNS_BUNDLE_ID", "")
        use_sandbox = os.getenv("APNS_SANDBOX", "true").lower() == "true"
        
        # Get the key - either from file path or content
        key_path = os.getenv("APNS_KEY_PATH")
        key_content = os.getenv("APNS_KEY_CONTENT")
        
        print(f"🔧 Initializing APNs service...")
        print(f"   Key ID: {key_id}")
        print(f"   Team ID: {team_id}")
        print(f"   Bundle ID: {self.bundle_id}")
        print(f"   Sandbox: {use_sandbox}")
        
        # Determine key source
        key_source = self._get_key_source(key_path, key_content)
        
        if not all([key_source, key_id, team_id, self.bundle_id]):
            missing = []
            if not key_source: missing.append("APNS_KEY_PATH or APNS_KEY_CONTENT")
            if not key_id: missing.append("APNS_KEY_ID")
            if not team_id: missing.append("APNS_TEAM_ID")
            if not self.bundle_id: missing.append("APNS_BUNDLE_ID")
            print(f"⚠️ APNs not configured - missing: {', '.join(missing)}")
            return
        
        try:
            self._client = APNs(
                key=key_source,
                key_id=key_id,
                team_id=team_id,
                topic=self.bundle_id,
                use_sandbox=use_sandbox
            )
            env_type = "sandbox" if use_sandbox else "production"
            print(f"✅ APNs client initialized ({env_type})")
        except Exception as e:
            print(f"❌ Failed to initialize APNs client: {e}")
            self._client = None
    
    def _get_key_source(self, key_path: Optional[str], key_content: Optional[str]) -> Optional[str]:
        """
        Get the APNs key source - either a file path or the key content itself.
        
        Supports:
        - File path to .p8 file
        - Base64 encoded key content
        - Raw PEM key content (with escaped newlines)
        """
        # Option 1: Key file path
        if key_path and os.path.exists(key_path):
            print(f"📝 Using APNs key from file: {key_path}")
            return key_path
        
        # Option 2: Key content from environment variable
        if key_content:
            key_text = self._decode_key_content(key_content)
            if not key_text:
                return None
            
            # Write to temp file (aioapns requires a file path)
            key_file = "/tmp/apns_key.p8"
            try:
                with open(key_file, 'w') as f:
                    f.write(key_text)
                os.chmod(key_file, 0o600)
                print(f"📝 APNs key written to temp file")
                return key_file
            except Exception as e:
                print(f"❌ Failed to write APNs key file: {e}")
                return None
        
        return None
    
    def _decode_key_content(self, content: str) -> Optional[str]:
        """Decode key content - handles base64 or raw PEM format."""
        content = content.strip()
        
        # Check if it's already raw PEM format
        if content.startswith("-----BEGIN"):
            # Handle escaped newlines
            key_text = content.replace("\\n", "\n")
            print(f"📝 APNs key provided as raw PEM")
            return key_text
        
        # Try base64 decoding
        try:
            import base64
            decoded = base64.b64decode(content).decode('utf-8')
            if "-----BEGIN PRIVATE KEY-----" in decoded:
                print(f"📝 APNs key decoded from base64")
                return decoded
            else:
                print(f"❌ Decoded content doesn't look like a .p8 key")
                return None
        except Exception as e:
            print(f"❌ Failed to decode APNS_KEY_CONTENT: {e}")
            return None
    
    @property
    def client(self):
        """Get the APNs client, initializing if needed."""
        self._ensure_initialized()
        return self._client
    
    @property
    def is_configured(self) -> bool:
        """Check if APNs is properly configured."""
        self._ensure_initialized()
        return self._client is not None
    
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
            device_token: The APNs device token (64 character hex string)
            title: Notification title
            body: Notification body text
            data: Additional data payload
            
        Returns:
            True if sent successfully, False otherwise
        """
        if not self.client:
            print(f"⚠️ Cannot send push - APNs not configured")
            return False
        
        # Validate device token format
        if not device_token or len(device_token) != 64:
            print(f"❌ Invalid device token length: {len(device_token) if device_token else 0}")
            return False
        
        try:
            payload = {
                "aps": {
                    "alert": {
                        "title": title,
                        "body": body
                    },
                    "sound": "default",
                    "content-available": 1,
                    "mutable-content": 1
                }
            }
            
            if data:
                payload.update(data)
            
            request = NotificationRequest(
                device_token=device_token,
                message=payload,
                push_type=PushType.ALERT
            )
            
            response = await self.client.send_notification(request)
            
            if response.is_successful:
                print(f"✅ Push sent: {title}")
                return True
            else:
                print(f"❌ Push failed: {response.description}")
                # Log specific error for debugging
                if "BadDeviceToken" in str(response.description):
                    print(f"   Token may be invalid or for wrong environment")
                elif "Unregistered" in str(response.description):
                    print(f"   Device has unregistered from push notifications")
                return False
                
        except Exception as e:
            print(f"❌ Push error: {e}")
            return False
    
    async def send_event_created_notification(
        self,
        device_token: str,
        events: list,
    ) -> bool:
        """Send notification when events are successfully created."""
        if not events:
            return False
        
        if len(events) == 1:
            title = "Event Created"
            event = events[0]
            body = event.title if hasattr(event, 'title') else str(event.get('title', 'New Event'))
        else:
            title = f"{len(events)} Events Created"
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
        
        return await self.send_notification(
            device_token=device_token,
            title=title,
            body=body,
            data={"action": "create_events", "events": events_data}
        )
    
    async def send_no_events_notification(self, device_token: str) -> bool:
        """Send notification when no events were found."""
        return await self.send_notification(
            device_token=device_token,
            title="No Events Found",
            body="Couldn't detect events in the screenshot",
            data={"action": "no_events"}
        )
    
    async def send_error_notification(self, device_token: str, error_message: str) -> bool:
        """Send notification when processing failed."""
        truncated = error_message[:100] + "..." if len(error_message) > 100 else error_message
        return await self.send_notification(
            device_token=device_token,
            title="Capture Failed",
            body=truncated,
            data={"action": "error", "error": error_message}
        )


# Global instance
apns_service = APNsService()
