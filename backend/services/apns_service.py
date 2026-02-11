"""
Apple Push Notification Service (APNs) integration.

Uses direct HTTP/2 requests with JWT authentication.
No dependency on aioapns - simpler and more reliable.
"""

import os
import time
import base64
from typing import Optional, Dict, Any

import httpx
import jwt


class APNsService:
    """Service for sending Apple Push Notifications using JWT authentication."""
    
    # APNs endpoints
    SANDBOX_URL = "https://api.sandbox.push.apple.com"
    PRODUCTION_URL = "https://api.push.apple.com"
    
    def __init__(self):
        self._initialized: bool = False
        self._key_id: Optional[str] = None
        self._team_id: Optional[str] = None
        self._private_key: Optional[str] = None
        self._bundle_id: str = ""
        self._use_sandbox: bool = True
        self._token: Optional[str] = None
        self._token_timestamp: float = 0
    
    def _ensure_initialized(self):
        """Lazy initialization - only initialize when first needed."""
        if self._initialized:
            return
        
        self._initialized = True
        
        # Get configuration from environment
        self._key_id = os.getenv("APNS_KEY_ID")
        self._team_id = os.getenv("APNS_TEAM_ID")
        self._bundle_id = os.getenv("APNS_BUNDLE_ID", "")
        self._use_sandbox = os.getenv("APNS_SANDBOX", "true").lower() == "true"
        
        # Get the key content
        key_path = os.getenv("APNS_KEY_PATH")
        key_content = os.getenv("APNS_KEY_CONTENT")
        
        print(f"🔧 Initializing APNs service...")
        print(f"   Key ID: {self._key_id}")
        print(f"   Team ID: {self._team_id}")
        print(f"   Bundle ID: {self._bundle_id}")
        print(f"   Sandbox: {self._use_sandbox}")
        
        # Load the private key
        self._private_key = self._load_private_key(key_path, key_content)
        
        if not all([self._private_key, self._key_id, self._team_id, self._bundle_id]):
            missing = []
            if not self._private_key: missing.append("APNS_KEY_PATH or APNS_KEY_CONTENT")
            if not self._key_id: missing.append("APNS_KEY_ID")
            if not self._team_id: missing.append("APNS_TEAM_ID")
            if not self._bundle_id: missing.append("APNS_BUNDLE_ID")
            print(f"⚠️ APNs not configured - missing: {', '.join(missing)}")
        else:
            env_type = "sandbox" if self._use_sandbox else "production"
            print(f"✅ APNs service initialized ({env_type})")
    
    def _load_private_key(self, key_path: Optional[str], key_content: Optional[str]) -> Optional[str]:
        """Load the private key from file or environment variable."""
        
        # Option 1: Key file path
        if key_path and os.path.exists(key_path):
            try:
                with open(key_path, 'r') as f:
                    key = f.read()
                print(f"📝 APNs key loaded from file: {key_path}")
                return key
            except Exception as e:
                print(f"❌ Failed to read key file: {e}")
                return None
        
        # Option 2: Key content from environment variable
        if key_content:
            key_content = key_content.strip()
            
            # Check if it's base64 encoded
            if not key_content.startswith("-----BEGIN"):
                try:
                    decoded = base64.b64decode(key_content).decode('utf-8')
                    if "-----BEGIN PRIVATE KEY-----" in decoded:
                        print(f"📝 APNs key decoded from base64")
                        return decoded
                except Exception as e:
                    print(f"❌ Failed to decode base64 key: {e}")
                    return None
            else:
                # Raw PEM content (handle escaped newlines)
                key = key_content.replace("\\n", "\n")
                print(f"📝 APNs key loaded from environment")
                return key
        
        return None
    
    def _get_auth_token(self) -> Optional[str]:
        """Get or refresh the JWT authentication token."""
        # Token is valid for 1 hour, refresh every 50 minutes
        if self._token and (time.time() - self._token_timestamp) < 3000:
            return self._token
        
        if not all([self._private_key, self._key_id, self._team_id]):
            return None
        
        try:
            now = int(time.time())
            payload = {
                "iss": self._team_id,
                "iat": now
            }
            headers = {
                "alg": "ES256",
                "kid": self._key_id
            }
            
            self._token = jwt.encode(
                payload,
                self._private_key,
                algorithm="ES256",
                headers=headers
            )
            self._token_timestamp = now
            print(f"🔑 APNs JWT token generated")
            return self._token
            
        except Exception as e:
            print(f"❌ Failed to generate JWT token: {e}")
            return None
    
    @property
    def is_configured(self) -> bool:
        """Check if APNs is properly configured."""
        self._ensure_initialized()
        return all([self._private_key, self._key_id, self._team_id, self._bundle_id])
    
    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        data: Optional[Dict[str, Any]] = None,
        use_sandbox: bool = False
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
        self._ensure_initialized()
        
        if not self.is_configured:
            print(f"⚠️ Cannot send push - APNs not configured")
            return False
        
        # Validate device token format
        if not device_token or len(device_token) != 64:
            print(f"❌ Invalid device token length: {len(device_token) if device_token else 0}")
            return False
        
        # Get auth token
        auth_token = self._get_auth_token()
        if not auth_token:
            print(f"❌ Failed to get APNs auth token")
            return False
        
        # Build payload
        payload = {
            "aps": {
                "alert": {
                    "title": title,
                    "body": body
                },
                "sound": "default",
                "content-available": 1,
                "mutable-content": 1,
                "interruption-level": "time-sensitive"
            }
        }
        
        if data:
            payload.update(data)
        
        # Build URL based on per-device sandbox flag
        base_url = self.SANDBOX_URL if use_sandbox else self.PRODUCTION_URL
        url = f"{base_url}/3/device/{device_token}"
        
        # Headers
        headers = {
            "authorization": f"bearer {auth_token}",
            "apns-topic": self._bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10"
        }
        
        try:
            async with httpx.AsyncClient(http2=True) as client:
                response = await client.post(
                    url,
                    json=payload,
                    headers=headers,
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    print(f"✅ Push sent: {title}")
                    return True
                else:
                    error_body = response.text
                    try:
                        error_json = response.json()
                        reason = error_json.get("reason", "Unknown")
                    except:
                        reason = error_body or f"HTTP {response.status_code}"
                    
                    print(f"❌ Push failed: {reason}")
                    
                    # Log helpful hints for common errors
                    if "BadDeviceToken" in reason:
                        print(f"   Device token may be invalid or for wrong environment")
                    elif "Unregistered" in reason:
                        print(f"   Device has unregistered from push notifications")
                    elif "ExpiredProviderToken" in reason:
                        print(f"   JWT token expired - will refresh")
                        self._token = None
                    
                    return False
                    
        except Exception as e:
            print(f"❌ Push error: {e}")
            return False
    
    async def send_event_created_notification(
        self,
        device_token: str,
        events: list,
        job_id: str,
        use_sandbox: bool = False,
    ) -> bool:
        """Send notification when events are successfully extracted.
        
        Only sends the job_id in the payload (not the full events data)
        to stay well within Apple's 4KB APNS payload limit.
        The iOS app fetches full event data via /job-status/{job_id}.
        """
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
        
        return await self.send_notification(
            device_token=device_token,
            title=title,
            body=body,
            data={"action": "create_events", "job_id": job_id},
            use_sandbox=use_sandbox,
        )
    
    async def send_no_events_notification(self, device_token: str, job_id: str = "", use_sandbox: bool = False) -> bool:
        """Send notification when no events were found."""
        return await self.send_notification(
            device_token=device_token,
            title="No Events Found",
            body="Couldn't detect events in the screenshot",
            data={"action": "no_events", "job_id": job_id},
            use_sandbox=use_sandbox,
        )
    
    async def send_error_notification(self, device_token: str, error_message: str, job_id: str = "", use_sandbox: bool = False) -> bool:
        """Send notification when processing failed."""
        truncated = error_message[:100] + "..." if len(error_message) > 100 else error_message
        return await self.send_notification(
            device_token=device_token,
            title="Capture Failed",
            body=truncated,
            data={"action": "error", "error": error_message, "job_id": job_id},
            use_sandbox=use_sandbox,
        )


# Global instance
apns_service = APNsService()
