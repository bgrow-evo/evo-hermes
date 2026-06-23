"""Codex OAuth — Phase 1: build the authorization-code (PKCE) login URL.

Runs inside the Hermes container. Writes the PKCE verifier/state to
/opt/data/.codex_pkce.json and prints the URL for the user to open.
"""
import secrets
import hashlib
import base64
import json
import urllib.parse

CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
REDIRECT_URI = "http://localhost:1455/auth/callback"

verifier = secrets.token_urlsafe(64)
challenge = (
    base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
    .decode()
    .rstrip("=")
)
state = secrets.token_urlsafe(32)

params = {
    "response_type": "code",
    "client_id": CLIENT_ID,
    "redirect_uri": REDIRECT_URI,
    "scope": "openid profile email offline_access",
    "code_challenge": challenge,
    "code_challenge_method": "S256",
    "id_token_add_organizations": "true",
    "codex_cli_simplified_flow": "true",
    "state": state,
}

url = "https://auth.openai.com/oauth/authorize?" + urllib.parse.urlencode(params)

with open("/opt/data/.codex_pkce.json", "w") as fh:
    json.dump(
        {"verifier": verifier, "state": state, "redirect_uri": REDIRECT_URI}, fh
    )

print(url)
