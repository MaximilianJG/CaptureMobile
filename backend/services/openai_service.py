"""
OpenAI Service for capture classification and data extraction.

Two-step pipeline:
  1. classify_category — determine what kind of capture this is + generate a title
  2. extract_data     — pull structured fields based on the category
"""

import os
import json
from datetime import datetime
from typing import Optional

from openai import AsyncOpenAI


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

            system = f"""You classify user captures into a category and generate a short title.

TODAY: {today}

CATEGORIES (pick exactly one):
- "restaurant" — menus, food photos, dining, restaurant info
- "clothing"   — fashion items, outfits, brands, style
- "event"      — meetings, appointments, concerts, anything with a date/time
- "note"       — general notes, lists, ideas, text info
- "movie"      — movie posters, film recs, cinema listings, TV shows
- "book"       — book covers, reading lists, recommendations
- "other"      — anything else

RULES:
- Pick the single best category.
- Generate a concise title (max 60 chars) that names the specific thing,
  e.g. "Tantris Munich" not "Restaurant Menu".

Respond ONLY with JSON: {{"category":"...","title":"...","confidence":0.0-1.0}}"""

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
            system = f"""You extract structured data from a capture.
Category: "{category}"  Title: "{title}"

Return a flat JSON object with ONLY the relevant fields below.
Omit any field you cannot confidently fill.

restaurant → cuisine, location, price_range, rating, dishes, vibe, reservation_info
clothing   → brand, item_type, color, size, price, material, store, url
event      → date (YYYY-MM-DD), start_time (HH:MM 24h), end_time, location, description, organizer, is_all_day
note       → content, tags
movie      → genre, director, year, rating, platform, cast, synopsis
book       → author, genre, year, isbn, publisher, synopsis, rating
other      → description, tags

Respond ONLY with JSON."""

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
            print(f"  [Extract] {len(result)} field(s) for '{category}'", flush=True)
            return result

        except Exception as e:
            print(f"  [Extract] Error: {e}", flush=True)
            return {}

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
