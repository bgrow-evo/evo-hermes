#!/usr/bin/env python3
"""Diagnostic: confirm token + silent refresh work. No side effects."""
import json
import os
import sys
from pathlib import Path

import msal
import requests

TENANT_ID = "1c2caf71-5666-4b98-bffc-ae0da8c4a4db"

def main():
    hermes_home = os.environ.get("HERMES_HOME", "/opt/data")
    profile_dir = Path(hermes_home)
    cache_path = profile_dir / ".graph_user_token_cache.json"

    if not cache_path.exists():
        print(f"Token cache not found: {cache_path}", file=sys.stderr)
        print("Run graph_login.py first.", file=sys.stderr)
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
        print("No cached account found. Run graph_login.py first.", file=sys.stderr)
        return 1

    # Silent refresh (no prompt).
    result = app.acquire_token_silent(
        scopes=["https://graph.microsoft.com/.default"],
        account=accounts[0],
    )

    if "access_token" not in result:
        print("Token refresh failed (re-auth needed).", file=sys.stderr)
        print(result.get("error_description", "Unknown error"), file=sys.stderr)
        return 1

    # Query /me to confirm the token is valid and show who we're logged in as.
    headers = {"Authorization": f"Bearer {result['access_token']}"}
    resp = requests.get("https://graph.microsoft.com/v1.0/me", headers=headers)

    if resp.status_code != 200:
        print(f"Graph /me failed: {resp.status_code}", file=sys.stderr)
        print(resp.text, file=sys.stderr)
        return 1

    user = resp.json()
    print(f"✓ {user.get('displayName', 'Unknown')} <{user.get('userPrincipalName', 'unknown@unknown')}>")
    return 0

if __name__ == "__main__":
    sys.exit(main())
