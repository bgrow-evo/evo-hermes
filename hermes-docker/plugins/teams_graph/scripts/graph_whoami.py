#!/usr/bin/env python3
"""Diagnostic: confirm the shared token cache + silent refresh work. No side effects."""
import os
import sys
from pathlib import Path

import msal
import requests

TENANT_ID = os.environ.get("TEAMS_GRAPH_TENANT_ID", "1c2caf71-5666-4b98-bffc-ae0da8c4a4db")


def main():
    client_id = os.environ.get("TEAMS_GRAPH_CLIENT_ID")
    cache_path = Path(
        os.environ.get("TEAMS_GRAPH_TOKEN_CACHE")
        or Path(os.environ.get("HERMES_HOME", "/opt/data")) / ".graph_user_token_cache.json"
    )
    if not client_id:
        print("TEAMS_GRAPH_CLIENT_ID not set", file=sys.stderr)
        return 1
    if not cache_path.exists():
        print(f"Token cache not found: {cache_path} (run graph_login.py)", file=sys.stderr)
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
        print("Token refresh failed (re-auth needed).", file=sys.stderr)
        print(result.get("error_description", "Unknown error"), file=sys.stderr)
        return 1

    resp = requests.get(
        "https://graph.microsoft.com/v1.0/me",
        headers={"Authorization": f"Bearer {result['access_token']}"},
    )
    if resp.status_code != 200:
        print(f"Graph /me failed: {resp.status_code}\n{resp.text[:300]}", file=sys.stderr)
        return 1
    user = resp.json()
    print(f"OK {user.get('displayName', '?')} <{user.get('userPrincipalName', '?')}>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
