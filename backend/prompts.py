"""
Editable prompt templates for the OpenAI capture pipeline.

Edit these strings to tune the model's behavior. After editing, redeploy
the backend (Railway) for the changes to take effect.

Template placeholders:
  CLASSIFY_SYSTEM      -> {today}
  EXTRACT_SYSTEM       -> {category}, {title}, {required_fields_line}
  ASSIGN_TAGS_SYSTEM   -> {category}, {title}, {summary}, {tag_list}
"""

# ======================================================================
# Step 1 — Classify category + generate title
# ======================================================================
CLASSIFY_SYSTEM = """You classify user captures into a category and generate a short, specific title.

TODAY: {today}

CATEGORIES (pick exactly one):
- "restaurant" — menus, food photos, dining, restaurant info
- "clothing"   — fashion items, outfits, brands, style
- "event"      — meetings, appointments, concerts, anything with a date/time
- "note"       — general notes, lists, ideas, text info
- "movie"      — movie posters, film recs, cinema listings, TV shows
- "book"       — book covers, reading lists, recommendations
- "other"      — anything else

TITLE RULES:
- Generate a specific, informative title (max 60 chars).
- Include the thing's proper name whenever possible, plus one disambiguating
  detail when it helps recall what the capture is about.
- Good titles:
    "Tantris Munich — dinner Fri 8pm"
    "Nike Air Max 90 White"
    "Dune Part Two — IMAX"
    "Team standup — Mon 9:30"
    "Grocery list — weekend"
- Avoid generic titles like "Restaurant Menu", "Event", "Note", "Photo",
  "Screenshot", "Untitled".
- For notes, summarize the gist in a few specific words rather than quoting
  the first line verbatim.

Respond ONLY with JSON: {{"category":"...","title":"...","confidence":0.0-1.0}}"""


# ======================================================================
# Step 2 — Extract structured fields by category
# ======================================================================
EXTRACT_SYSTEM = """You extract structured data from a capture.
Category: "{category}"  Title: "{title}"

Return a flat JSON object with ONLY the relevant fields listed below.
Include every REQUIRED field (use best inference from the capture).
Include OPTIONAL fields only when you can fill them confidently.
Do NOT invent data that is not supported by the capture.

{required_fields_line}

FIELD MENUS BY CATEGORY:
- restaurant → cuisine, location, price_range, rating, dishes, vibe, reservation_info
- clothing   → brand, item_type, color, size, price, material, store, url
- event      → date (YYYY-MM-DD), start_time (HH:MM 24h), end_time (HH:MM 24h), location, description, organizer, is_all_day (true/false)
- note       → key_info, action_items, people, dates, locations, urls
               (do NOT include the raw note text — it is stored separately)
- movie      → genre, director, year, rating, platform, cast, synopsis
- book       → author, genre, year, isbn, publisher, synopsis, rating
- other      → description

Respond ONLY with JSON."""


# ======================================================================
# Step 3 — Assign tags from the user's library
# ======================================================================
ASSIGN_TAGS_SYSTEM = """You assign tags to a capture from the user's tag library.

Category: "{category}"  Title: "{title}"
Extracted data: {summary}

AVAILABLE TAGS: [{tag_list}]

RULES:
- Pick 1-5 tags from the available list that best describe this capture.
- Only use tags from the available list above. Do not invent new ones.
- Pick fewer tags if only a few are relevant. Quality over quantity.

Respond ONLY with JSON: {{"tags": ["tag1", "tag2", ...]}}"""


# ======================================================================
# Required extraction fields per category.
# Missing / empty keys are backfilled with "not found" after the LLM responds,
# so the UI always has a consistent set of keys to render.
# ======================================================================
REQUIRED_EXTRACTION_FIELDS: dict[str, list[str]] = {
    "restaurant": ["cuisine", "location", "price_range", "rating", "vibe"],
    "clothing":   ["brand", "item_type", "color", "price", "store"],
    "event":      ["date", "start_time", "end_time", "location", "is_all_day"],
    "note":       ["key_info", "action_items"],
    "movie":      ["genre", "director", "year", "platform"],
    "book":       ["author", "genre", "year", "synopsis"],
    "other":      ["description"],
}

NOT_FOUND = "not found"


def required_fields_line(category: str) -> str:
    """Human-readable line inserted into EXTRACT_SYSTEM so the LLM knows
    which keys MUST appear in the response."""
    fields = REQUIRED_EXTRACTION_FIELDS.get(category, [])
    if not fields:
        return "REQUIRED FIELDS: (none specified)"
    return "REQUIRED FIELDS (always include): " + ", ".join(fields)


def fill_required_fields(category: str, result: dict) -> dict:
    """Backfill any required field that is missing or empty with NOT_FOUND."""
    for key in REQUIRED_EXTRACTION_FIELDS.get(category, []):
        value = result.get(key)
        if value is None or value == "" or value == []:
            result[key] = NOT_FOUND
    return result
