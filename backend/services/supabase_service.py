"""
Supabase service — handles Storage uploads and Database writes/reads.

Uses the **service_role** key so it bypasses RLS (server-side only).
"""

import os
import uuid
import base64
from typing import Optional, Dict, Any, List

from supabase import create_client, Client


class SupabaseService:

    def __init__(self):
        url = os.getenv("SUPABASE_URL", "")
        key = os.getenv("SUPABASE_SERVICE_KEY", "")
        if url and key:
            self.client: Client = create_client(url, key)
            print(f"✅ Supabase connected: {url}")
        else:
            self.client = None
            print("⚠️  Supabase not configured (missing SUPABASE_URL or SUPABASE_SERVICE_KEY)")

    # ------------------------------------------------------------------
    # Storage
    # ------------------------------------------------------------------

    def upload_image(self, user_id: str, image_base64: str) -> Optional[str]:
        """Upload base64 JPEG to Storage. Returns the object path or None."""
        if not self.client:
            return None
        try:
            image_bytes = base64.b64decode(image_base64)
            path = f"{user_id}/{uuid.uuid4()}.jpg"
            self.client.storage.from_("captures").upload(
                path=path,
                file=image_bytes,
                file_options={"content-type": "image/jpeg"},
            )
            print(f"  [Storage] Uploaded {len(image_bytes) / 1024:.0f} KB → {path}", flush=True)
            return path
        except Exception as e:
            print(f"  [Storage] Upload error: {e}", flush=True)
            return None

    def get_signed_url(self, path: str, expires_in: int = 3600) -> Optional[str]:
        """Generate a temporary signed URL for a private storage object."""
        if not self.client or not path:
            return None
        try:
            result = self.client.storage.from_("captures").create_signed_url(path, expires_in)
            return result.get("signedURL") or result.get("signedUrl")
        except Exception as e:
            print(f"  [Storage] Signed URL error: {e}", flush=True)
            return None

    # ------------------------------------------------------------------
    # Database
    # ------------------------------------------------------------------

    def create_capture(
        self,
        user_id: str,
        title: str,
        category: str,
        method: str,
        extracted_data: Dict[str, Any],
        image_path: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        """Insert a capture row. Returns the created record or None."""
        if not self.client:
            return None
        try:
            row = {
                "user_id": user_id,
                "capture_title": title,
                "category": category,
                "capture_method": method,
                "extracted_data": extracted_data,
                "image_path": image_path,
            }
            result = self.client.table("captures").insert(row).execute()
            if result.data:
                print(f"  [DB] Created capture: {result.data[0]['id'][:8]}...", flush=True)
                return result.data[0]
            return None
        except Exception as e:
            print(f"  [DB] Insert error: {e}", flush=True)
            return None

    def get_captures(
        self, user_id: str, limit: int = 30, category: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Fetch recent captures for a user, optionally filtered by category."""
        if not self.client:
            return []
        try:
            query = (
                self.client.table("captures")
                .select("*")
                .eq("user_id", user_id)
                .order("time_captured", desc=True)
                .limit(limit)
            )
            if category and category != "all":
                query = query.eq("category", category)

            result = query.execute()
            captures = result.data or []

            for cap in captures:
                if cap.get("image_path"):
                    cap["image_url"] = self.get_signed_url(cap["image_path"])
                else:
                    cap["image_url"] = None

            return captures
        except Exception as e:
            print(f"  [DB] Fetch error: {e}", flush=True)
            return []
