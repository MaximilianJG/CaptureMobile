"""
Notion MCP Agent — runs Notion MCP server as subprocess, bridges tools to AI model,
autonomous multi-turn loop. The AI decides what to read, where to write, and how to
structure content in the user's Notion workspace.
"""

import os
import json
import asyncio
import time
from typing import Optional

from openai import AsyncOpenAI


class NotionMCPAgent:
    """
    Spawns a Notion MCP server subprocess with the user's access token,
    discovers all available tools, and runs an autonomous AI agent loop.
    """

    MAX_TOOL_ROUNDS = 15

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
        """
        Run the Notion agent: spawn MCP server, discover tools, let the AI
        autonomously explore and write to the user's Notion workspace.

        Returns: {"success": bool, "summary": str}
        """
        start = time.time()

        def log(msg: str):
            print(f"  [NotionAgent] {msg}", flush=True)

        log(f"Starting (parent_page: {parent_page_id[:12]}..., source: {source})")

        proc = None
        try:
            proc = await self._spawn_mcp_server(access_token)
            tools = await self._discover_tools(proc, log)

            if not tools:
                log("No tools discovered from MCP server")
                return {"success": False, "summary": "Failed to connect to Notion MCP server."}

            log(f"Discovered {len(tools)} MCP tools")
            openai_tools = self._mcp_tools_to_openai(tools)

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
                    tools=openai_tools if openai_tools else None,
                    max_tokens=2000,
                )

                choice = response.choices[0]

                if choice.finish_reason == "stop" or not choice.message.tool_calls:
                    summary = choice.message.content or "Content saved to Notion."
                    elapsed = time.time() - start
                    log(f"Done in {round_num} rounds, {elapsed:.1f}s: {summary[:100]}")
                    return {"success": True, "summary": summary}

                messages.append(choice.message)

                for tool_call in choice.message.tool_calls:
                    tool_name = tool_call.function.name
                    tool_args = json.loads(tool_call.function.arguments)
                    log(f"  Tool call: {tool_name}({json.dumps(tool_args)[:200]})")

                    result = await self._call_mcp_tool(proc, tool_name, tool_args, log)

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

        finally:
            if proc:
                await self._shutdown(proc)

    async def _spawn_mcp_server(self, access_token: str) -> asyncio.subprocess.Process:
        env = {**os.environ, "OPENAI_API_KEY": "", "NOTION_API_KEY": access_token}
        proc = await asyncio.create_subprocess_exec(
            "npx", "-y", "@notionhq/notion-mcp-server",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )
        return proc

    async def _discover_tools(self, proc, log) -> list:
        """Send MCP initialize + tools/list and return the tool definitions."""
        init_msg = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "capture-backend", "version": "1.0.0"},
            },
        }
        init_resp = await self._send_rpc(proc, init_msg)
        if not init_resp:
            log("MCP initialize failed")
            return []

        notify = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        proc.stdin.write((json.dumps(notify) + "\n").encode())
        await proc.stdin.drain()

        tools_msg = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        tools_resp = await self._send_rpc(proc, tools_msg)
        if not tools_resp or "result" not in tools_resp:
            log("MCP tools/list failed")
            return []

        return tools_resp["result"].get("tools", [])

    async def _call_mcp_tool(self, proc, tool_name: str, arguments: dict, log) -> any:
        msg = {
            "jsonrpc": "2.0",
            "id": 100,
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": arguments},
        }
        resp = await self._send_rpc(proc, msg)
        if not resp:
            return {"error": "MCP tool call timed out"}

        if "error" in resp:
            log(f"  Tool error: {resp['error']}")
            return {"error": resp["error"]}

        result = resp.get("result", {})
        content_parts = result.get("content", [])
        texts = [c.get("text", "") for c in content_parts if c.get("type") == "text"]
        combined = "\n".join(texts) if texts else json.dumps(result)

        try:
            return json.loads(combined)
        except (json.JSONDecodeError, TypeError):
            return combined

    async def _send_rpc(self, proc, message: dict, timeout: float = 30.0) -> Optional[dict]:
        payload = json.dumps(message) + "\n"
        proc.stdin.write(payload.encode())
        await proc.stdin.drain()

        try:
            line = await asyncio.wait_for(proc.stdout.readline(), timeout=timeout)
            if not line:
                return None
            return json.loads(line.decode().strip())
        except (asyncio.TimeoutError, json.JSONDecodeError):
            return None

    async def _shutdown(self, proc):
        try:
            proc.stdin.close()
            proc.terminate()
            await asyncio.wait_for(proc.wait(), timeout=5.0)
        except Exception:
            proc.kill()

    def _mcp_tools_to_openai(self, mcp_tools: list) -> list:
        """Convert MCP tool definitions to OpenAI function calling format."""
        openai_tools = []
        for tool in mcp_tools:
            schema = tool.get("inputSchema", {"type": "object", "properties": {}})
            openai_tools.append({
                "type": "function",
                "function": {
                    "name": tool["name"],
                    "description": tool.get("description", ""),
                    "parameters": schema,
                },
            })
        return openai_tools

    def _build_system_prompt(self, parent_page_id: str, source: str) -> str:
        return f"""You are a Notion assistant that saves user content to their Notion workspace.

PARENT PAGE ID: {parent_page_id}
SOURCE: {source}

INSTRUCTIONS:
1. First, explore the parent page structure by listing its children (sub-pages and databases).
2. Understand what databases exist, what their schemas/properties are.
3. Based on the user's content, decide the best place to save it:
   - If you find a relevant database (e.g. a Tasks DB for todos, a Shopping List DB for groceries, a Notes DB for notes), add items there with properly filled properties.
   - If no matching database exists, create a well-structured new page under the parent page.
   - For lists of items (todos, shopping), prefer creating individual database items if a matching DB exists.
4. Fill in ALL relevant fields/properties. Be thorough — use titles, descriptions, tags, dates, etc.
5. Structure content cleanly with headings, bullet points, and paragraphs as appropriate.

CONSTRAINTS:
- ONLY write under the parent page (ID: {parent_page_id}). Do not write elsewhere.
- Do NOT delete or modify existing content unless the user explicitly asks.
- If you're unsure where to put something, create a new page under the parent.

When done, respond with a brief summary of what you created and where."""


notion_agent = NotionMCPAgent()
