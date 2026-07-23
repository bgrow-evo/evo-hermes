#!/usr/bin/env python3
"""Call the remote evo-mcp server (MCP JSON-RPC over streamable HTTP) as hermes-ai.

Auth: silent MSAL from the shared hermes-ai token cache (same broker pattern as
the teams_graph adapter). The native Hermes mcp_servers integration cannot
authorize headlessly against this server; this script is the supported path.

Usage:
  evo_mcp.py --list-tools
  evo_mcp.py --call <tool-name> --args '<json-object>'
"""
import argparse
import json
import os
import sys
from pathlib import Path

import msal
import requests

TENANT = os.environ.get("TEAMS_GRAPH_TENANT_ID", "1c2caf71-5666-4b98-bffc-ae0da8c4a4db")
CLIENT_ID = os.environ.get("TEAMS_GRAPH_CLIENT_ID", "8723feb3-bb77-4a0e-9c04-bbde8ec2cf37")
MCP_URL = os.environ.get(
    "EVO_MCP_URL",
    "https://aca-evo-mcp-public.livelydesert-f18ee3f4.westus2.azurecontainerapps.io/mcp",
)
MCP_SCOPE = "api://ecbff0f1-4ac8-45c9-8365-50c16bc76881/access_as_user"
PROTOCOL = "2025-06-18"


def get_token() -> str:
    cache_path = Path(
        os.environ.get("TEAMS_GRAPH_TOKEN_CACHE", "/opt/data/.graph_user_token_cache.json")
    )
    if not cache_path.exists():
        sys.exit("FAIL token_not_found: shared hermes-ai cache missing — run graph_login.py")
    cache = msal.SerializableTokenCache()
    cache.deserialize(cache_path.read_text())
    app = msal.PublicClientApplication(
        CLIENT_ID, authority=f"https://login.microsoftonline.com/{TENANT}", token_cache=cache
    )
    accounts = app.get_accounts()
    if not accounts:
        sys.exit("FAIL token_not_found: no cached hermes-ai account")
    result = app.acquire_token_silent([MCP_SCOPE], account=accounts[0])
    if not result or "access_token" not in result:
        sys.exit(f"FAIL token_refresh: {(result or {}).get('error_description', 'unknown')[:200]}")
    if cache.has_state_changed:
        try:
            cache_path.write_text(cache.serialize())
        except OSError:
            pass
    return result["access_token"]


def parse_response(resp: requests.Response) -> dict:
    """Handle both plain-JSON and SSE-framed MCP responses."""
    ctype = resp.headers.get("content-type", "")
    if "text/event-stream" in ctype:
        for line in resp.text.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        sys.exit(f"FAIL: no data frame in SSE response: {resp.text[:200]}")
    return resp.json()


class Session:
    def __init__(self):
        self.token = get_token()
        self.session_id = None
        self._id = 0

    def rpc(self, method: str, params: dict | None = None, notification: bool = False) -> dict | None:
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        body: dict = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            body["params"] = params
        if not notification:
            self._id += 1
            body["id"] = self._id
        r = requests.post(MCP_URL, headers=headers, json=body, timeout=180)
        if r.status_code in (401, 403):
            sys.exit(f"FAIL {r.status_code}: MCP auth rejected — hermes-ai access/blocker.")
        if r.status_code == 202:  # accepted notification
            return None
        if r.status_code != 200:
            sys.exit(f"FAIL {r.status_code}: {r.text[:300]}")
        if not self.session_id and "mcp-session-id" in r.headers:
            self.session_id = r.headers["mcp-session-id"]
        if notification:
            return None
        data = parse_response(r)
        if "error" in data:
            sys.exit(f"FAIL rpc {method}: {json.dumps(data['error'])[:300]}")
        return data.get("result", {})

    def initialize(self):
        self.rpc(
            "initialize",
            {
                "protocolVersion": PROTOCOL,
                "capabilities": {},
                "clientInfo": {"name": "hermes-evo-mcp-skill", "version": "1.0"},
            },
        )
        self.rpc("notifications/initialized", {}, notification=True)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--list-tools", action="store_true")
    g.add_argument("--call", metavar="TOOL")
    ap.add_argument("--args", default="{}", help="JSON object of tool arguments")
    args = ap.parse_args()

    s = Session()
    s.initialize()

    if args.list_tools:
        result = s.rpc("tools/list", {})
        for t in result.get("tools", []):
            desc = (t.get("description") or "").split("\n")[0][:110]
            print(f"{t['name']}: {desc}")
        return

    try:
        tool_args = json.loads(args.args)
    except json.JSONDecodeError as e:
        sys.exit(f"FAIL: --args is not valid JSON: {e}")
    result = s.rpc("tools/call", {"name": args.call, "arguments": tool_args})
    if result.get("isError"):
        sys.exit(f"FAIL tool error: {json.dumps(result)[:500]}")
    for item in result.get("content", []):
        if item.get("type") == "text":
            print(item.get("text", ""))
        else:
            print(json.dumps(item))


if __name__ == "__main__":
    main()
