---
name: azure-keyvault
description: "Read a secret from the evo Azure Key Vault (kv-hermes-sbx) using the container's managed identity. Use when a task needs a stored credential (API token, vendor password, service key) referenced by secret name. Read-only — secrets are written/rotated by humans via az CLI or the Azure portal."
version: 1.0.0
author: evo
platforms: [linux]
metadata:
  hermes:
    tags: [secrets, azure, key-vault, credentials, evo]
---

# azure-keyvault

Fetch a named secret from **kv-hermes-sbx** via the Azure Container App's
system-assigned managed identity. No token files, no sign-in, no refresh
handling — the platform mints the identity token on demand.

## Usage

```bash
/opt/hermes/.venv/bin/python3 scripts/kv_secret.py --name <secret-name>
# list available secret names (names only, never values):
/opt/hermes/.venv/bin/python3 scripts/kv_secret.py --list
```

The vault URI defaults to `$HERMES_KEYVAULT_URI`
(https://kv-hermes-sbx.vault.azure.net); override with `--vault` only if told to.

## Rules

- **Read-only.** Never attempt to set, delete, or rotate secrets. Writes are a
  human operation (`az keyvault secret set --vault-name kv-hermes-sbx ...`).
- **Never expose secret values** in chat replies, memory files, manifests, cron
  output, logs, or committed files. Use them in-place (env var for a subprocess,
  login form field) and reference them only by secret name.
- A 403 means this container's identity lost vault access; a connection error
  to the identity endpoint means the script is not running inside the container
  app. Both are **blockers** — record and stop, do not retry loops.
- Prefer the vault for durable machine credentials. The Merch Sheet remains the
  live source of truth for vendor DAM logins unless a secret exists for them.
