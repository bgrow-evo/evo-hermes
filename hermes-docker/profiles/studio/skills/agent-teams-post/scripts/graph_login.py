#!/usr/bin/env python3
"""One-time device-code sign-in for hermes-ai@evo.com into Microsoft Graph.

Scopes: ChannelMessage.Send (post to Teams channels) + offline_access (refresh token).

The token cache is written to the profile's volume and persists across container restarts.
"""
import json
import os
import sys
from pathlib import Path

import msal

TENANT_ID = "1c2caf71-5666-4b98-bffc-ae0da8c4a4db"

def main():
    hermes_home = os.environ.get("HERMES_HOME", "/opt/data")
    profile_dir = Path(hermes_home)
    cache_path = profile_dir / ".graph_user_token_cache.json"

    # MSAL serializable token cache (automatically persists on write).
    cache = msal.SerializableTokenCache()
    if cache_path.exists():
        with open(cache_path) as f:
            cache.deserialize(f.read())

    app = msal.PublicClientApplication(
        client_id=os.environ.get("TEAMS_GRAPH_CLIENT_ID"),
        authority=f"https://login.microsoftonline.com/{TENANT_ID}",
        token_cache=cache,
    )

    scopes = ["https://graph.microsoft.com/ChannelMessage.Send", "offline_access"]

    # Initiate device-code flow.
    flow = app.initiate_device_flow(scopes=scopes)

    if "user_code" not in flow:
        print("Failed to initiate device-code flow.", file=sys.stderr)
        print(flow.get("error_description", "Unknown error"), file=sys.stderr)
        return 1

    # Print the user-facing message (contains device code + sign-in URL).
    print(flow["message"])

    # Block until the user completes the sign-in.
    result = app.acquire_token_by_device_flow(flow)

    if "access_token" in result:
        # Save the cache (includes the new refresh token).
        with open(cache_path, "w") as f:
            f.write(cache.serialize())
        print(f"✓ Signed in as {result.get('id_token_claims', {}).get('preferred_username', 'unknown')}")
        return 0
    else:
        print("Authentication failed.", file=sys.stderr)
        print(result.get("error_description", "Unknown error"), file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
