#!/usr/bin/env python3
"""List the chats hermes-ai@evo.com is a member of (IDs for route config).

Prints chat id, type, topic/members. Use the ids for TEAMS_GRAPH_CHATS /
STUDIO_TEAMS_GRAPH_CHATS / TEAMS_GRAPH_HOME_CHAT. No side effects.
"""
import os
import sys
from pathlib import Path

import msal
import requests

TENANT_ID = os.environ.get("TEAMS_GRAPH_TENANT_ID", "1c2caf71-5666-4b98-bffc-ae0da8c4a4db")
GRAPH = "https://graph.microsoft.com/v1.0"


def main():
    client_id = os.environ.get("TEAMS_GRAPH_CLIENT_ID")
    cache_path = Path(
        os.environ.get("TEAMS_GRAPH_TOKEN_CACHE")
        or Path(os.environ.get("HERMES_HOME", "/opt/data")) / ".graph_user_token_cache.json"
    )
    if not client_id or not cache_path.exists():
        print("Need TEAMS_GRAPH_CLIENT_ID + token cache (run graph_login.py first)", file=sys.stderr)
        return 1

    cache = msal.SerializableTokenCache()
    cache.deserialize(cache_path.read_text())
    app = msal.PublicClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{TENANT_ID}",
        token_cache=cache,
    )
    accounts = app.get_accounts()
    if not accounts:
        print("No cached account. Run graph_login.py.", file=sys.stderr)
        return 1
    result = app.acquire_token_silent(["https://graph.microsoft.com/.default"], account=accounts[0])
    if "access_token" not in result:
        print("Token refresh failed (re-run graph_login.py).", file=sys.stderr)
        return 1

    headers = {"Authorization": f"Bearer {result['access_token']}"}
    url = f"{GRAPH}/me/chats?$expand=members&$top=50"
    while url:
        resp = requests.get(url, headers=headers)
        if resp.status_code != 200:
            print(f"{resp.status_code}: {resp.text[:300]}", file=sys.stderr)
            return 1
        data = resp.json()
        for chat in data.get("value", []):
            members = ", ".join(
                m.get("displayName") or "?" for m in chat.get("members", [])
            )
            print(f"{chat.get('chatType', '?'):10}  {chat['id']}")
            print(f"{'':10}  topic={chat.get('topic') or '-'}  members=[{members}]")
        url = data.get("@odata.nextLink")
    return 0


if __name__ == "__main__":
    sys.exit(main())
