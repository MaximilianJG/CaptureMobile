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
        key_path = os.getenv("APNS_KEY_PATH")  # Path to .p8 file
        key_content = os.getenv("APNS_KEY_CONTENT")  # Or base64-encoded key content
        key_id = os.getenv("APNS_KEY_ID")
        team_id = os.getenv("APNS_TEAM_ID")
        self.bundle_id = os.getenv("APNS_BUNDLE_ID", "")
        use_sandbox = os.getenv("APNS_SANDBOX", "true").lower() == "true"
        
        print(f"🔧 Initializing APNs service...")
        print(f"   Key ID: {key_id}")
        print(f"   Team ID: {team_id}")
        print(f"   Bundle ID: {self.bundle_id}")
        print(f"   Sandbox: {use_sandbox}")
        print(f"   Key content length: {len(key_content) if key_content else 0}")
        
        # Determine the key source
        key_source = None
        if key_path and os.path.exists(key_path):
            key_source = key_path
            print(f"📝 Using APNs key from file: {key_path}")
        elif key_content:
            import base64
            try:
                # Check if content is already the raw key (starts with -----BEGIN)
                if key_content.strip().startswith("-----BEGIN"):
                    key_text = key_content.strip()
                    print(f"📝 APNs key provided as raw PEM content")
                else:
                    # Base64 encoded - strip all whitespace and decode
                    cleaned_content = key_content.replace('\n', '').replace('\r', '').replace(' ', '')
                    key_bytes = base64.b64decode(cleaned_content)
                    key_text = key_bytes.decode('utf-8')
                    print(f"📝 APNs key decoded from base64 ({len(key_bytes)} bytes)")
                
                # Validate the key looks correct
                if "-----BEGIN PRIVATE KEY-----" not in key_text:
                    print(f"❌ APNs key doesn't look like a valid .p8 file")
                    print(f"   Key starts with: {key_text[:50]}...")
                    return
                
                # Parse the PEM and re-wrap properly at 64 chars per line
                # This is required by cryptography library
                key_text = key_text.replace('\r\n', '\n').replace('\r', '\n')
                
                # Extract the base64 content between headers
                lines = key_text.strip().split('\n')
                header = lines[0]
                footer = lines[-1]
                
                # Get all the base64 content (everything between header and footer)
                base64_content = ''.join(lines[1:-1])
                # Remove any whitespace from the base64
                base64_content = ''.join(base64_content.split())
                
                print(f"   Base64 content length: {len(base64_content)} chars")
                
                # Re-wrap at exactly 64 characters per line (PEM standard)
                wrapped_lines = [base64_content[i:i+64] for i in range(0, len(base64_content), 64)]
                
                # Reconstruct the PEM file
                pem_lines = [header] + wrapped_lines + [footer]
                key_text = '\n'.join(pem_lines) + '\n'
                
                print(f"   Reconstructed PEM: {len(pem_lines)} lines")
                for i, line in enumerate(pem_lines):
                    print(f"   Line {i+1}: {len(line)} chars")
                
                # Write to a permanent file in /tmp
                key_file_path = "/tmp/apns_auth_key.p8"
                with open(key_file_path, 'w', encoding='ascii', newline='\n') as f:
                    f.write(key_text)
                
                # Set proper permissions
                os.chmod(key_file_path, 0o600)
                
                key_source = key_file_path
                
                # Verify the file content
                with open(key_file_path, 'r') as f:
                    content = f.read()
                    verify_lines = content.strip().split('\n')
                    print(f"✅ APNs key written to {key_file_path}")
                    print(f"   File size: {len(content)} bytes, {len(verify_lines)} lines")
                    print(f"   First line: {verify_lines[0]}")
                    print(f"   Last line: {verify_lines[-1]}")
                
                # Pre-validate the key with cryptography before aioapns uses it
                try:
                    from cryptography.hazmat.primitives.serialization import load_pem_private_key
                    with open(key_file_path, 'rb') as f:
                        key_data = f.read()
                        print(f"🔍 Testing key load with cryptography...")
                        print(f"   Raw bytes: {key_data[:50]}...")
                        print(f"   Raw bytes (hex): {key_data[:50].hex()}")
                        private_key = load_pem_private_key(key_data, password=None)
                        print(f"✅ Key validated with cryptography: {type(private_key).__name__}")
                except Exception as crypto_error:
                    print(f"❌ Cryptography failed to load key: {crypto_error}")
                    import traceback
                    traceback.print_exc()
                    # Continue anyway to see if aioapns handles it differently
                    
            except Exception as e:
                print(f"❌ Failed to process APNS_KEY_CONTENT: {e}")
                import traceback
                traceback.print_exc()
                return
        
        if key_source and key_id and team_id and self.bundle_id:
            try:
                self._client = APNs(
                    key=key_source,
                    key_id=key_id,
                    team_id=team_id,
                    topic=self.bundle_id,
                    use_sandbox=use_sandbox
                )
                env_type = "sandbox" if use_sandbox else "production"
                print(f"✅ APNs client created ({env_type}) for {self.bundle_id}")
            except Exception as e:
                print(f"❌ Failed to initialize APNs client: {e}")
                import traceback
                traceback.print_exc()
                self._client = None
        else:
            missing = []
            if not key_source: missing.append("APNS_KEY_PATH or APNS_KEY_CONTENT")
            if not key_id: missing.append("APNS_KEY_ID")
            if not team_id: missing.append("APNS_TEAM_ID")
            if not self.bundle_id: missing.append("APNS_BUNDLE_ID")
            print(f"⚠️ APNs not configured - missing: {', '.join(missing)}")
    
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
