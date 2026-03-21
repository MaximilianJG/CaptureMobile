"""
Per-user Notion token and page storage.
Uses a JSON file for persistence (upgrade to DB later if needed).
"""

import os
import json
from typing import Optional, Dict, Any
from pydantic import BaseModel

STORE_PATH = os.path.join(os.path.dirname(__file__), "..", "notion_users.json")


class NotionUserData(BaseModel):
    access_token: str
    workspace_name: Optional[str] = None
    workspace_id: Optional[str] = None
    parent_page_id: Optional[str] = None
    parent_page_title: Optional[str] = None


def _load_store() -> Dict[str, Any]:
    if not os.path.exists(STORE_PATH):
        return {}
    with open(STORE_PATH, "r") as f:
        return json.load(f)


def _save_store(data: Dict[str, Any]):
    with open(STORE_PATH, "w") as f:
        json.dump(data, f, indent=2)


def get_user(user_id: str) -> Optional[NotionUserData]:
    store = _load_store()
    raw = store.get(user_id)
    if raw is None:
        return None
    return NotionUserData(**raw)


def save_user(user_id: str, data: NotionUserData):
    store = _load_store()
    store[user_id] = data.model_dump()
    _save_store(store)


def delete_user(user_id: str):
    store = _load_store()
    store.pop(user_id, None)
    _save_store(store)


def user_has_notion(user_id: str) -> bool:
    return get_user(user_id) is not None
