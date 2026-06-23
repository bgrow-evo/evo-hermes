"""Verify the saved Codex credentials resolve and can authenticate."""
RESULT = "/opt/data/.codex_smoke.txt"
out = []


def log(m=""):
    print(m)
    out.append(str(m))
    with open(RESULT, "w") as fh:
        fh.write("\n".join(out) + "\n")


try:
    from hermes_cli.auth import resolve_codex_runtime_credentials

    creds = resolve_codex_runtime_credentials()
    key = creds.get("api_key", "")
    base = creds.get("base_url", "")
    log(f"resolve OK: api_key={len(key)} chars, base_url={base}")
except Exception as exc:
    log(f"resolve FAILED: {type(exc).__name__}: {exc}")
    raise SystemExit(1)

# Minimal authenticated request against the Codex backend.
import httpx
import base64
import json as _json

# Decode JWT claims to confirm the account-id is present.
try:
    payload_b64 = key.split(".")[1] + "=" * (-len(key.split(".")[1]) % 4)
    claims = _json.loads(base64.urlsafe_b64decode(payload_b64))
    auth_claim = claims.get("https://api.openai.com/auth", {})
    log(f"chatgpt_account_id: {auth_claim.get('chatgpt_account_id')}")
    log(f"chatgpt_plan_type: {auth_claim.get('chatgpt_plan_type')}")
except Exception as exc:
    log(f"JWT decode note: {exc}")

from agent.auxiliary_client import _codex_cloudflare_headers

headers = _codex_cloudflare_headers(key)
headers["Content-Type"] = "application/json"
headers["Authorization"] = f"Bearer {key}"
try:
    resp = httpx.post(
        f"{base}/responses",
        headers=headers,
        json={
            "model": "gpt-5.5",
            "instructions": "You are a test probe. Answer concisely.",
            "input": [
                {"role": "user", "content": "Reply with exactly: codex-ok"}
            ],
            "store": False,
            "stream": True,
        },
        timeout=60.0,
    )
    log(f"HTTP {resp.status_code}")
    body = resp.text
    log(body[:1200])
except Exception as exc:
    log(f"request FAILED: {type(exc).__name__}: {exc}")
    raise SystemExit(1)
