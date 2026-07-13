#!/usr/bin/env python3
"""Post a message to a Teams channel via delegated Microsoft Graph."""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import msal
import requests

TENANT_ID = "1c2caf71-5666-4b98-bffc-ae0da8c4a4db"

def main():
    parser = argparse.ArgumentParser(description="Post a message to a Teams channel.")
    parser.add_argument("--text", help="Plain text message to send")
    parser.add_argument("--html", help="HTML-formatted message to send")
    parser.add_argument("--test", action="store_true", help="Send an obvious test message")
    parser.add_argument("--team-id", help="Override Team ID from env TEAMS_GRAPH_TEAM_ID")
    parser.add_argument("--channel-id", help="Override Channel ID from env TEAMS_GRAPH_CHANNEL_ID")
    args = parser.parse_args()

    team_id = args.team_id or os.environ.get("TEAMS_GRAPH_TEAM_ID")
    channel_id = args.channel_id or os.environ.get("TEAMS_GRAPH_CHANNEL_ID")

    if not team_id or not channel_id:
        print("Team ID and Channel ID required (set TEAMS_GRAPH_TEAM_ID / TEAMS_GRAPH_CHANNEL_ID or pass --team-id / --channel-id)", file=sys.stderr)
        return 1

    hermes_home = os.environ.get("HERMES_HOME", "/opt/data")
    profile_dir = Path(hermes_home)
    cache_path = profile_dir / ".graph_user_token_cache.json"

    if not cache_path.exists():
        print(f"Token cache not found: {cache_path}", file=sys.stderr)
        return 1

    cache = msal.SerializableTokenCache()
    with open(cache_path) as f:
        cache.deserialize(f.read())

    app = msal.PublicClientApplication(
        client_id=os.environ.get("TEAMS_GRAPH_CLIENT_ID"),
        authority=f"https://login.microsoftonline.com/{TENANT_ID}",
        token_cache=cache,
    )

    accounts = app.get_accounts()
    if not accounts:
        print("No cached account found.", file=sys.stderr)
        return 1

    # Silent refresh.
    result = app.acquire_token_silent(
        scopes=["https://graph.microsoft.com/.default"],
        account=accounts[0],
    )

    if "access_token" not in result:
        print("Token refresh failed (re-auth needed).", file=sys.stderr)
        return 1

    # Compose message.
    if args.test:
        timestamp = datetime.now(timezone.utc).isoformat()
        content = f"✅ Hermes Studio Graph-post test — {timestamp}"
        content_type = "text"
    elif args.html:
        content = args.html
        content_type = "html"
    elif args.text:
        content = args.text
        content_type = "text"
    else:
        print("Provide --text, --html, or --test", file=sys.stderr)
        return 1

    # POST to Graph.
    url = f"https://graph.microsoft.com/v1.0/teams/{team_id}/channels/{channel_id}/messages"
    headers = {
        "Authorization": f"Bearer {result['access_token']}",
        "Content-Type": "application/json",
    }
    payload = {
        "body": {
            "content": content,
            "contentType": content_type,
        }
    }

    resp = requests.post(url, headers=headers, json=payload)

    if resp.status_code not in (200, 201):
        print(f"POST failed: {resp.status_code}", file=sys.stderr)
        print(resp.text, file=sys.stderr)
        return 1

    print(f"✓ Message posted to {team_id}/{channel_id}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
