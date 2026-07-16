#!/usr/bin/env python3
"""One-time device-code sign-in for hermes-ai@evo.com (teams_graph adapter).

Scopes: Chat.ReadWrite (read+send own chats), ChannelMessage.Send (channel
posts for the daily-summary skill), User.Read, offline_access (refresh token).

Cache path: TEAMS_GRAPH_TOKEN_CACHE, default <HERMES_HOME>/.graph_user_token_cache.json.
Run, open https://microsoft.com/devicelogin in a browser, sign in AS
hermes-ai@evo.com with the printed code.
"""
import os
import sys
from pathlib import Path

import msal

TENANT_ID = os.environ.get("TEAMS_GRAPH_TENANT_ID", "1c2caf71-5666-4b98-bffc-ae0da8c4a4db")
SCOPES = [
    "https://graph.microsoft.com/Chat.ReadWrite",
    "https://graph.microsoft.com/ChannelMessage.Send",
    "https://graph.microsoft.com/User.Read",
]


def main():
    client_id = os.environ.get("TEAMS_GRAPH_CLIENT_ID")
    if not client_id:
        print("TEAMS_GRAPH_CLIENT_ID not set", file=sys.stderr)
        return 1

    cache_path = Path(
        os.environ.get("TEAMS_GRAPH_TOKEN_CACHE")
        or Path(os.environ.get("HERMES_HOME", "/opt/data")) / ".graph_user_token_cache.json"
    )

    cache = msal.SerializableTokenCache()
    if cache_path.exists():
        cache.deserialize(cache_path.read_text())

    app = msal.PublicClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{TENANT_ID}",
        token_cache=cache,
    )

    flow = app.initiate_device_flow(scopes=SCOPES)
    if "user_code" not in flow:
        print("Failed to initiate device-code flow.", file=sys.stderr)
        print(flow.get("error_description", "Unknown error"), file=sys.stderr)
        return 1

    print(flow["message"], flush=True)
    result = app.acquire_token_by_device_flow(flow)

    if "access_token" in result:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(cache.serialize())
        try:
            os.chmod(cache_path, 0o600)
        except OSError:
            pass
        who = result.get("id_token_claims", {}).get("preferred_username", "unknown")
        print(f"OK signed in as {who}; cache: {cache_path}")
        return 0

    print("Authentication failed.", file=sys.stderr)
    print(result.get("error_description", "Unknown error"), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
