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
        tags: Optional[List[str]] = None,
        content: Optional[str] = None,
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
                "tags": tags or [],
                "content": content,
            }
            result = self.client.table("captures").insert(row).execute()
            if result.data:
                print(f"  [DB] Created capture: {result.data[0]['id'][:8]}...", flush=True)
                return result.data[0]
            return None
        except Exception as e:
            print(f"  [DB] Insert error: {e}", flush=True)
            return None

    def update_capture_content(self, capture_id: str, user_id: str, content: str) -> Optional[Dict[str, Any]]:
        """Update the content field of a capture. Returns the updated record or None."""
        if not self.client:
            return None
        try:
            result = (
                self.client.table("captures")
                .update({"content": content})
                .eq("id", capture_id)
                .eq("user_id", user_id)
                .execute()
            )
            if result.data:
                print(f"  [DB] Updated content for capture: {capture_id[:8]}...", flush=True)
                return result.data[0]
            return None
        except Exception as e:
            print(f"  [DB] Update content error: {e}", flush=True)
            return None

    def update_capture_fields(
        self,
        capture_id: str,
        user_id: str,
        title: str,
        category: str,
        extracted_data: Dict[str, Any],
        tags: List[str],
    ) -> Optional[Dict[str, Any]]:
        """Update AI-derived fields on a capture after reprocessing."""
        if not self.client:
            return None
        try:
            result = (
                self.client.table("captures")
                .update({
                    "capture_title": title,
                    "category": category,
                    "extracted_data": extracted_data,
                    "tags": tags,
                })
                .eq("id", capture_id)
                .eq("user_id", user_id)
                .execute()
            )
            if result.data:
                print(f"  [DB] Reprocessed capture: {capture_id[:8]}...", flush=True)
                return result.data[0]
            return None
        except Exception as e:
            print(f"  [DB] Update fields error: {e}", flush=True)
            return None

    def delete_capture(self, capture_id: str, user_id: str) -> bool:
        """Delete a capture row and its storage object. Returns True on success."""
        if not self.client:
            return False
        try:
            row = (
                self.client.table("captures")
                .select("image_path")
                .eq("id", capture_id)
                .eq("user_id", user_id)
                .execute()
            )
            if not row.data:
                return False

            image_path = row.data[0].get("image_path")

            self.client.table("captures").delete().eq("id", capture_id).eq("user_id", user_id).execute()

            if image_path:
                try:
                    self.client.storage.from_("captures").remove([image_path])
                except Exception as e:
                    print(f"  [Storage] Delete warning: {e}", flush=True)

            print(f"  [DB] Deleted capture: {capture_id[:8]}...", flush=True)
            return True
        except Exception as e:
            print(f"  [DB] Delete error: {e}", flush=True)
            return False

    def get_signed_urls_batch(self, paths: List[str], expires_in: int = 3600) -> Dict[str, Optional[str]]:
        """Generate signed URLs for multiple paths in a single request."""
        if not self.client or not paths:
            return {}
        try:
            results = self.client.storage.from_("captures").create_signed_urls(paths, expires_in)
            url_map: Dict[str, Optional[str]] = {}
            for item in results:
                path = item.get("path", "")
                url = item.get("signedURL") or item.get("signedUrl")
                if path:
                    url_map[path] = url
            return url_map
        except Exception as e:
            print(f"  [Storage] Batch signed URL error: {e}", flush=True)
            return {p: self.get_signed_url(p, expires_in) for p in paths}

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

            image_paths = [cap["image_path"] for cap in captures if cap.get("image_path")]
            url_map = self.get_signed_urls_batch(image_paths) if image_paths else {}

            for cap in captures:
                path = cap.get("image_path")
                cap["image_url"] = url_map.get(path) if path else None

            return captures
        except Exception as e:
            print(f"  [DB] Fetch error: {e}", flush=True)
            return []

    # ------------------------------------------------------------------
    # User Tags
    # ------------------------------------------------------------------

    DEFAULT_TAGS = [
        "Italian", "Sushi", "Brunch", "Cafe", "Fine Dining", "Pizza", "Bar",
        "Concert", "Meeting", "Birthday", "Conference", "Party", "Sports",
        "Action", "Comedy", "Drama", "Documentary", "Thriller", "Sci-Fi",
        "Fiction", "Non-Fiction", "Self-Help", "Biography", "Fantasy",
        "Shoes", "Jacket", "Dress", "Sneakers", "Accessories", "Streetwear",
        "Ideas", "Reminder", "Recipe", "Travel", "Inspiration", "Wishlist",
    ]

    def get_user_tags(self, user_id: str) -> List[Dict[str, Any]]:
        """Fetch all tags for a user; seeds defaults on first access."""
        if not self.client:
            return []
        try:
            result = (
                self.client.table("user_tags")
                .select("*")
                .eq("user_id", user_id)
                .order("name")
                .execute()
            )
            tags = result.data or []
            if not tags:
                tags = self._seed_default_tags(user_id)
            return tags
        except Exception as e:
            print(f"  [Tags] Fetch error: {e}", flush=True)
            return []

    def _seed_default_tags(self, user_id: str) -> List[Dict[str, Any]]:
        """Insert default tags for a new user."""
        if not self.client:
            return []
        try:
            rows = [{"user_id": user_id, "name": t} for t in self.DEFAULT_TAGS]
            result = self.client.table("user_tags").insert(rows).execute()
            print(f"  [Tags] Seeded {len(result.data or [])} defaults for {user_id[:8]}...", flush=True)
            return result.data or []
        except Exception as e:
            print(f"  [Tags] Seed error: {e}", flush=True)
            return []

    def create_user_tag(self, user_id: str, name: str) -> Optional[Dict[str, Any]]:
        """Create a new user tag. Returns the tag or None."""
        if not self.client:
            return None
        try:
            result = (
                self.client.table("user_tags")
                .insert({"user_id": user_id, "name": name})
                .execute()
            )
            if result.data:
                return result.data[0]
            return None
        except Exception as e:
            print(f"  [Tags] Create error: {e}", flush=True)
            return None

    def delete_user_tag(self, tag_id: str, user_id: str) -> bool:
        """Delete a user tag by id."""
        if not self.client:
            return False
        try:
            self.client.table("user_tags").delete().eq("id", tag_id).eq("user_id", user_id).execute()
            return True
        except Exception as e:
            print(f"  [Tags] Delete error: {e}", flush=True)
            return False
