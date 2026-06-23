"""Inspect the saved Codex tokens in the Hermes auth store."""
import json
import os

path = "/opt/data/auth.json"
if not os.path.isfile(path):
    print("auth.json NOT FOUND at", path)
    raise SystemExit(0)

with open(path) as fh:
    data = json.load(fh)

prov = data.get("providers", {}).get("openai-codex", {})
print("openai-codex present:", bool(prov))
tokens = prov.get("tokens", {}) if isinstance(prov, dict) else {}
print("has access_token:", bool(tokens.get("access_token")))
print("has refresh_token:", bool(tokens.get("refresh_token")))
print("last_refresh:", prov.get("last_refresh"))
print("auth_mode:", prov.get("auth_mode"))
