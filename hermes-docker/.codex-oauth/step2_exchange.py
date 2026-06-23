"""Codex OAuth — Phase 2: exchange the authorization code for tokens.

Reads the PKCE state written by step1, takes the pasted callback URL as
argv[1], exchanges the code at the OpenAI token endpoint, then persists the
tokens via Hermes's own _save_codex_tokens + updates config.yaml.
"""
import sys
import json
import urllib.parse
from datetime import datetime, timezone

import httpx

CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
TOKEN_URL = "https://auth.openai.com/oauth/token"
RESULT_FILE = "/opt/data/.codex_result.txt"

_lines = []


def log(msg=""):
    print(msg)
    _lines.append(str(msg))
    with open(RESULT_FILE, "w") as fh:
        fh.write("\n".join(_lines) + "\n")


CALLBACK_FILE = "/opt/data/.codex_callback.txt"
with open(CALLBACK_FILE) as fh:
    callback_url = fh.read().strip()

log(f"Read callback URL ({len(callback_url)} chars).")
parsed = urllib.parse.urlparse(callback_url)
qs = urllib.parse.parse_qs(parsed.query)
code = qs.get("code", [""])[0]
state = qs.get("state", [""])[0]

with open("/opt/data/.codex_pkce.json") as fh:
    pkce = json.load(fh)

if not code:
    log("ERROR: no 'code' found in the pasted URL.")
    sys.exit(1)
if state != pkce["state"]:
    log(f"ERROR: state mismatch. expected {pkce['state']!r}, got {state!r}")
    sys.exit(1)

resp = httpx.post(
    TOKEN_URL,
    data={
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": pkce["redirect_uri"],
        "client_id": CLIENT_ID,
        "code_verifier": pkce["verifier"],
    },
    headers={"Content-Type": "application/x-www-form-urlencoded"},
    timeout=30.0,
)

if resp.status_code != 200:
    log(f"ERROR: token exchange returned {resp.status_code}")
    log(resp.text[:2000])
    sys.exit(1)

tok = resp.json()
access_token = tok.get("access_token", "")
refresh_token = tok.get("refresh_token", "")

if not access_token:
    log("ERROR: no access_token in token response.")
    log(json.dumps(tok, indent=2)[:2000])
    sys.exit(1)

log("Token exchange OK.")
log(f"  access_token:  {access_token[:24]}... ({len(access_token)} chars)")
log(f"  refresh_token: {'yes' if refresh_token else 'MISSING'}")

# Persist via Hermes's own helpers so the format + pool sync are correct.
from hermes_cli.auth import _save_codex_tokens, _update_config_for_provider, DEFAULT_CODEX_BASE_URL

last_refresh = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
_save_codex_tokens(
    {"access_token": access_token, "refresh_token": refresh_token},
    last_refresh,
)
config_path = _update_config_for_provider("openai-codex", DEFAULT_CODEX_BASE_URL)

log("")
log("Login successful! Tokens saved to Hermes auth store.")
log(f"  Config updated: {config_path} (model.provider=openai-codex)")
