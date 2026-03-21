"""
Notion Agent — autonomous AI agent that uses the Notion REST API directly.
The AI decides what to read, where to write, and how to structure content.
"""

import os
import json
import time
from typing import Optional

import httpx
from openai import AsyncOpenAI

NOTION_API = "https://api.notion.com/v1"
NOTION_VERSION = "2022-06-28"


def _notion_headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Notion-Version": NOTION_VERSION,
        "Content-Type": "application/json",
    }


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "notion_get_block_children",
            "description": "List child blocks (sub-pages, databases, content) of a block or page.",
            "parameters": {
                "type": "object",
                "properties": {
                    "block_id": {"type": "string", "description": "The block/page ID to list children of."},
                },
                "required": ["block_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "notion_search",
            "description": "Search the user's Notion workspace for pages or databases by title.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query text."},
                    "filter_type": {"type": "string", "enum": ["page", "database"], "description": "Filter by object type."},
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "notion_get_database",
            "description": "Retrieve a database's schema (properties/columns) to understand its structure.",
            "parameters": {
                "type": "object",
                "properties": {
                    "database_id": {"type": "string", "description": "The database ID."},
                },
                "required": ["database_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "notion_query_database",
            "description": "Query items in a database, optionally with filters.",
            "parameters": {
                "type": "object",
                "properties": {
                    "database_id": {"type": "string", "description": "The database ID."},
                    "filter": {"type": "object", "description": "Optional Notion filter object."},
                    "page_size": {"type": "integer", "description": "Max results (default 10)."},
                },
                "required": ["database_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "notion_create_page",
            "description": "Create a new page in a database or as a child of another page. For database pages, set properties matching the DB schema. For child pages, set the title. Use 'children' to add content blocks (paragraphs, headings, bullets, etc).",
            "parameters": {
                "type": "object",
                "properties": {
                    "parent_type": {"type": "string", "enum": ["database_id", "page_id"], "description": "Type of parent."},
                    "parent_id": {"type": "string", "description": "The parent database or page ID."},
                    "properties": {"type": "object", "description": "Page properties. For DB pages, match the schema. For child pages, use {\"title\": {\"title\": [{\"text\": {\"content\": \"Page Title\"}}]}}."},
                    "children": {
                        "type": "array",
                        "description": "Content blocks to add to the page body.",
                        "items": {"type": "object"},
                    },
                },
                "required": ["parent_type", "parent_id", "properties"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "notion_append_blocks",
            "description": "Append content blocks (paragraphs, headings, bullets, to-do items, etc.) to an existing page or block.",
            "parameters": {
                "type": "object",
                "properties": {
                    "block_id": {"type": "string", "description": "The page or block ID to append to."},
                    "children": {
                        "type": "array",
                        "description": "Array of block objects to append.",
                        "items": {"type": "object"},
                    },
                },
                "required": ["block_id", "children"],
            },
        },
    },
]


class NotionAgent:
    MAX_TOOL_ROUNDS = 12

    def __init__(self):
        self.client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
        self.model = "gpt-4o"

    async def execute(
        self,
        access_token: str,
        parent_page_id: str,
        content: str,
        source: str = "notes",
    ) -> dict:
        start = time.time()

        def log(msg: str):
            print(f"  [NotionAgent] {msg}", flush=True)

        log(f"Starting (parent_page: {parent_page_id[:12]}..., source: {source})")

        try:
            system_prompt = self._build_system_prompt(parent_page_id, source)
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": content},
            ]

            for round_num in range(1, self.MAX_TOOL_ROUNDS + 1):
                log(f"Round {round_num}/{self.MAX_TOOL_ROUNDS}")

                response = await self.client.chat.completions.create(
                    model=self.model,
                    messages=messages,
                    tools=TOOLS,
                    max_tokens=2000,
                )

                choice = response.choices[0]

                if choice.finish_reason == "stop" or not choice.message.tool_calls:
                    summary = choice.message.content or "Content saved to Notion."
                    elapsed = time.time() - start
                    log(f"Done in {round_num} rounds, {elapsed:.1f}s: {summary[:120]}")
                    return {"success": True, "summary": summary}

                messages.append(choice.message)

                for tool_call in choice.message.tool_calls:
                    fn_name = tool_call.function.name
                    fn_args = json.loads(tool_call.function.arguments)
                    log(f"  {fn_name}({json.dumps(fn_args)[:200]})")

                    result = await self._execute_tool(access_token, fn_name, fn_args, log)

                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": json.dumps(result) if isinstance(result, (dict, list)) else str(result),
                    })

            log("Hit max rounds")
            return {"success": True, "summary": "Content saved to Notion (processing limit reached)."}

        except Exception as e:
            log(f"ERROR: {e}")
            return {"success": False, "summary": f"Failed to save to Notion: {str(e)}"}

    async def _execute_tool(self, token: str, name: str, args: dict, log) -> any:
        headers = _notion_headers(token)

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                if name == "notion_get_block_children":
                    resp = await client.get(
                        f"{NOTION_API}/blocks/{args['block_id']}/children?page_size=100",
                        headers=headers,
                    )

                elif name == "notion_search":
                    body = {"query": args["query"], "page_size": 20}
                    if "filter_type" in args:
                        body["filter"] = {"property": "object", "value": args["filter_type"]}
                    resp = await client.post(f"{NOTION_API}/search", headers=headers, json=body)

                elif name == "notion_get_database":
                    resp = await client.get(
                        f"{NOTION_API}/databases/{args['database_id']}",
                        headers=headers,
                    )

                elif name == "notion_query_database":
                    body = {"page_size": args.get("page_size", 10)}
                    if "filter" in args and args["filter"]:
                        body["filter"] = args["filter"]
                    resp = await client.post(
                        f"{NOTION_API}/databases/{args['database_id']}/query",
                        headers=headers, json=body,
                    )

                elif name == "notion_create_page":
                    body = {
                        "parent": {args["parent_type"]: args["parent_id"]},
                        "properties": args["properties"],
                    }
                    if "children" in args and args["children"]:
                        body["children"] = args["children"]
                    resp = await client.post(f"{NOTION_API}/pages", headers=headers, json=body)

                elif name == "notion_append_blocks":
                    body = {"children": args["children"]}
                    resp = await client.patch(
                        f"{NOTION_API}/blocks/{args['block_id']}/children",
                        headers=headers, json=body,
                    )

                else:
                    return {"error": f"Unknown tool: {name}"}

                result = resp.json()

                if resp.status_code >= 400:
                    log(f"  API error {resp.status_code}: {result.get('message', '')[:100]}")
                    return {"error": result.get("message", f"HTTP {resp.status_code}")}

                return self._compact_result(result)

        except Exception as e:
            log(f"  Tool error: {e}")
            return {"error": str(e)}

    def _compact_result(self, data: dict) -> dict:
        """Trim large Notion API responses to stay within token limits."""
        if "results" in data and isinstance(data["results"], list):
            trimmed = []
            for item in data["results"][:25]:
                compact = {"id": item.get("id"), "type": item.get("type"), "object": item.get("object")}

                if item.get("type") == "child_page":
                    compact["title"] = item.get("child_page", {}).get("title", "")
                elif item.get("type") == "child_database":
                    compact["title"] = item.get("child_database", {}).get("title", "")

                if item.get("object") == "page" and "properties" in item:
                    compact["title"] = self._extract_title(item)
                    compact["properties"] = self._compact_properties(item["properties"])
                elif item.get("object") == "database":
                    compact["title"] = self._extract_plain_text(item.get("title", []))
                    if "properties" in item:
                        compact["schema"] = self._compact_db_schema(item["properties"])

                trimmed.append(compact)
            return {"results": trimmed, "has_more": data.get("has_more", False)}

        if data.get("object") == "database" and "properties" in data:
            return {
                "id": data["id"],
                "object": "database",
                "title": self._extract_plain_text(data.get("title", [])),
                "schema": self._compact_db_schema(data["properties"]),
            }

        if "properties" in data and "id" in data:
            return {
                "id": data["id"],
                "object": data.get("object"),
                "title": self._extract_title(data),
                "properties": self._compact_properties(data["properties"]),
                "url": data.get("url"),
            }

        if "id" in data:
            return {"id": data["id"], "object": data.get("object"), "url": data.get("url")}

        return data

    def _compact_db_schema(self, props: dict) -> dict:
        """Extract database schema with property types and options."""
        schema = {}
        for key, val in props.items():
            prop_type = val.get("type", "")
            entry = {"type": prop_type}

            if prop_type == "select" and "select" in val:
                entry["options"] = [o["name"] for o in val["select"].get("options", [])]
            elif prop_type == "multi_select" and "multi_select" in val:
                entry["options"] = [o["name"] for o in val["multi_select"].get("options", [])]
            elif prop_type == "status" and "status" in val:
                entry["options"] = [o["name"] for o in val["status"].get("options", [])]
                entry["groups"] = [g["name"] for g in val["status"].get("groups", [])]

            schema[key] = entry
        return schema

    def _compact_properties(self, props: dict) -> dict:
        """Compact page property values for display."""
        compact = {}
        for key, val in props.items():
            prop_type = val.get("type", "")
            if prop_type == "title":
                compact[key] = {"type": "title", "value": self._extract_plain_text(val.get("title", []))}
            elif prop_type == "rich_text":
                compact[key] = {"type": "rich_text", "value": self._extract_plain_text(val.get("rich_text", []))}
            elif prop_type == "select":
                sel = val.get("select")
                compact[key] = {"type": "select", "value": sel.get("name") if sel else None}
            elif prop_type == "multi_select":
                compact[key] = {"type": "multi_select", "values": [s["name"] for s in val.get("multi_select", [])]}
            elif prop_type == "status":
                st = val.get("status")
                compact[key] = {"type": "status", "value": st.get("name") if st else None}
            elif prop_type == "checkbox":
                compact[key] = {"type": "checkbox", "value": val.get("checkbox")}
            elif prop_type == "number":
                compact[key] = {"type": "number", "value": val.get("number")}
            elif prop_type == "date":
                compact[key] = {"type": "date", "value": val.get("date")}
            elif prop_type == "url":
                compact[key] = {"type": "url", "value": val.get("url")}
            else:
                compact[key] = {"type": prop_type}
        return compact

    def _extract_plain_text(self, rich_text_array: list) -> str:
        return "".join(t.get("plain_text", "") for t in rich_text_array)

    def _extract_title(self, page: dict) -> str:
        for prop in page.get("properties", {}).values():
            if prop.get("type") == "title":
                return self._extract_plain_text(prop.get("title", []))
        return ""

    def _build_system_prompt(self, parent_page_id: str, source: str) -> str:
        return f"""You are an intelligent Notion organizer. The user sends you quick notes, ideas, tasks, lists, or information. Your job is to save it to the RIGHT place in their Notion workspace — exactly like a human assistant who knows their way around the user's Notion.

PARENT PAGE ID: {parent_page_id}

=== MANDATORY EXPLORATION PHASE ===
You MUST explore before writing. Never create a new page if a matching database or page already exists.

Step 1: Call notion_get_block_children(block_id="{parent_page_id}") to see all children of the parent page.
Step 2: For EVERY child_database you find, call notion_get_database(database_id=...) to read its schema (columns, property types, select options, etc.).
Step 3: Also check child pages — they might contain databases nested inside them. If a child page title seems relevant, explore it too with notion_get_block_children.
Step 4: NOW decide where to put the content based on what you found.

=== DECISION LOGIC ===
- "buy eggs" → Look for a Shopping List / Groceries database → add item there
- "todo: fix the bug" → Look for a Tasks / To-Do database → add item with proper status
- "meeting with John tomorrow 3pm" → This is a calendar event, but if there's a Meetings DB, add it there
- "new idea: plant trees app" → Look for an Ideas / Notes database → add item. If none exists, create a page under parent.
- Multiple items in one note (e.g. "buy eggs, milk, bread") → Create ONE item per list entry in the matching database
- Long-form content → Create a well-structured page with headings and paragraphs

=== WRITING TO DATABASES ===
When you find a matching database:
1. Read its schema carefully (notion_get_database)
2. Map the user's content to the database properties:
   - Title property → main content
   - Status/Select → set appropriate value from existing options
   - Tags/Multi-select → pick relevant existing tags or create new ones
   - Date → if user mentions a date
   - Checkbox → for to-do items
3. Create the page with notion_create_page(parent_type="database_id", parent_id=<db_id>, properties=...)
4. For multiple items, make SEPARATE notion_create_page calls for each

=== PROPERTY FORMAT FOR DATABASE PAGES ===
Title: {{"Name": {{"title": [{{"text": {{"content": "Item text"}}}}]}}}}
Select: {{"Status": {{"select": {{"name": "To Do"}}}}}}
Multi-select: {{"Tags": {{"multi_select": [{{"name": "groceries"}}]}}}}
Checkbox: {{"Done": {{"checkbox": false}}}}
Date: {{"Due": {{"date": {{"start": "2026-03-21"}}}}}}
Rich text: {{"Notes": {{"rich_text": [{{"text": {{"content": "details"}}}}]}}}}

=== CREATING NEW PAGES (only if no database matches) ===
Use notion_create_page(parent_type="page_id", parent_id="{parent_page_id}", properties=..., children=...)

Block types for children:
- Heading: {{"object":"block","type":"heading_2","heading_2":{{"rich_text":[{{"type":"text","text":{{"content":"Title"}}}}]}}}}
- Paragraph: {{"object":"block","type":"paragraph","paragraph":{{"rich_text":[{{"type":"text","text":{{"content":"Text"}}}}]}}}}
- Bullet: {{"object":"block","type":"bulleted_list_item","bulleted_list_item":{{"rich_text":[{{"type":"text","text":{{"content":"Item"}}}}]}}}}
- To-do: {{"object":"block","type":"to_do","to_do":{{"rich_text":[{{"type":"text","text":{{"content":"Task"}}}}],"checked":false}}}}

=== CONSTRAINTS ===
- ONLY write under the parent page or its child databases/pages
- Do NOT delete or modify existing content
- Be thorough: fill in every relevant property the database schema offers
- Prefer existing databases over creating new pages
- If you create multiple items, confirm each one

=== RESPONSE ===
When done, respond with a concise summary:
- What you saved (the content)
- Where you saved it (database name or page title)
- How many items you created
Example: "Added 3 items (eggs, milk, bread) to your Shopping List database."
"""


notion_agent = NotionAgent()
