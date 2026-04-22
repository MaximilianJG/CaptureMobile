"""
OpenAI Service for capture classification and data extraction.

Three-step pipeline:
  1. classify_category — determine what kind of capture this is + generate a title
  2. extract_data     — pull structured fields based on the category
  3. assign_tags      — pick relevant tags from the user's tag library

All prompt text lives in `backend/prompts.py` for easy editing.
"""

import os
import json
from datetime import datetime
from typing import Optional, List

from openai import AsyncOpenAI

from prompts import (
    CLASSIFY_SYSTEM,
    EXTRACT_SYSTEM,
    ASSIGN_TAGS_SYSTEM,
    required_fields_line,
    fill_required_fields,
)


class OpenAIService:

    def __init__(self):
        self.client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
        self.model = "gpt-4o"

    # ------------------------------------------------------------------
    # Step 1 — Classify
    # ------------------------------------------------------------------

    async def classify_category(
        self,
        base64_image: Optional[str] = None,
        text: Optional[str] = None,
        source: str = "screenshot",
    ) -> dict:
        """Return {"category": str, "title": str, "confidence": float}."""
        try:
            today = datetime.now().strftime("%Y-%m-%d")
            system = CLASSIFY_SYSTEM.format(today=today)

            user_content = self._build_user_content(
                text=text,
                base64_image=base64_image,
                prefix=f"Classify this capture (source: {source}).",
            )

            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_content},
                ],
                max_tokens=150,
                response_format={"type": "json_object"},
            )

            result = json.loads(response.choices[0].message.content)

            valid = ("restaurant", "clothing", "event", "note", "movie", "book", "other")
            category = result.get("category", "other")
            if category not in valid:
                category = "other"

            title = result.get("title", "Untitled Capture")[:80]
            confidence = float(result.get("confidence", 0.5))

            print(f"  [Classify] {category} — \"{title}\" ({confidence:.0%})", flush=True)
            return {"category": category, "title": title, "confidence": confidence}

        except Exception as e:
            print(f"  [Classify] Error: {e}", flush=True)
            return {"category": "other", "title": "Untitled Capture", "confidence": 0.1}

    # ------------------------------------------------------------------
    # Step 2 — Extract
    # ------------------------------------------------------------------

    async def extract_data(
        self,
        base64_image: Optional[str] = None,
        text: Optional[str] = None,
        category: str = "other",
        title: str = "",
    ) -> dict:
        """Return a flat dict of extracted fields (shape varies by category)."""
        try:
            system = EXTRACT_SYSTEM.format(
                category=category,
                title=title,
                required_fields_line=required_fields_line(category),
            )

            user_content = self._build_user_content(
                text=text,
                base64_image=base64_image,
                prefix="Extract structured data from this capture.",
                detail="high",
            )

            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_content},
                ],
                max_tokens=1000,
                response_format={"type": "json_object"},
            )

            result = json.loads(response.choices[0].message.content)
            if not isinstance(result, dict):
                result = {}

            result = fill_required_fields(category, result)

            print(f"  [Extract] {len(result)} field(s) for '{category}'", flush=True)
            return result

        except Exception as e:
            print(f"  [Extract] Error: {e}", flush=True)
            return fill_required_fields(category, {})

    # ------------------------------------------------------------------
    # Step 3 — Assign Tags
    # ------------------------------------------------------------------

    async def assign_tags(
        self,
        available_tags: List[str],
        category: str,
        title: str,
        extracted_data: dict,
        base64_image: Optional[str] = None,
        text: Optional[str] = None,
    ) -> List[str]:
        """Pick 1-5 tags from the user's available tag library."""
        if not available_tags:
            return []
        try:
            tag_list = ", ".join(f'"{t}"' for t in available_tags)
            summary = json.dumps(extracted_data, default=str)[:500]

            system = ASSIGN_TAGS_SYSTEM.format(
                category=category,
                title=title,
                summary=summary,
                tag_list=tag_list,
            )

            user_content = self._build_user_content(
                text=text,
                base64_image=base64_image,
                prefix="Assign relevant tags to this capture.",
                detail="low",
            )

            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_content},
                ],
                max_tokens=200,
                response_format={"type": "json_object"},
            )

            result = json.loads(response.choices[0].message.content)
            tags = [t for t in result.get("tags", []) if t in available_tags]
            print(f"  [Tags] Assigned {len(tags)} tag(s): {tags}", flush=True)
            return tags

        except Exception as e:
            print(f"  [Tags] Error: {e}", flush=True)
            return []

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _build_user_content(
        text: Optional[str],
        base64_image: Optional[str],
        prefix: str,
        detail: str = "low",
    ) -> list:
        parts: list = []

        if text:
            parts.append({"type": "text", "text": f"{prefix}\n\n{text}"})
        else:
            parts.append({"type": "text", "text": prefix})

        if base64_image:
            url = (
                base64_image
                if base64_image.startswith("data:")
                else f"data:image/jpeg;base64,{base64_image}"
            )
            parts.append({"type": "image_url", "image_url": {"url": url, "detail": detail}})

        return parts
