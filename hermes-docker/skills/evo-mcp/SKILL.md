---
name: evo-mcp
description: "Query the evo data platform through the remote evo-mcp server (SQL Server/EDW/HighJump datasources, schema search, stored procedures) as hermes-ai. Use when a task needs live evo database reads: list datasources/tables, describe schemas, run read-only queries. Wraps the MCP JSON-RPC API with headless auth — do not try to browser-authorize the native MCP integration."
version: 1.0.0
author: evo
platforms: [linux]
metadata:
  hermes:
    tags: [evo, mcp, sql, edw, highjump, data-platform]
---

# evo-mcp

Call tools on the remote evo-mcp server
(https://aca-evo-mcp-public.livelydesert-f18ee3f4.westus2.azurecontainerapps.io/mcp)
authenticated as hermes-ai via the shared token cache. Silent refresh; no
browser, no interactive login.

## Usage

```bash
# discover available tools (names + descriptions)
/opt/hermes/.venv/bin/python3 scripts/evo_mcp.py --list-tools

# call a tool with JSON arguments
/opt/hermes/.venv/bin/python3 scripts/evo_mcp.py --call get_datasources --args '{}'
/opt/hermes/.venv/bin/python3 scripts/evo_mcp.py --call execute_query \
  --args '{"datasource":"sql-edw","query":"SELECT TOP 5 ..."}'
```

## Rules

- **Read-only intent**: prefer list/describe/query tools. Any tool that writes
  to a database requires explicit human approval in the conversation first.
- Auth errors (`token_not_found` / refresh failure) mean the shared hermes-ai
  cache needs a re-login — record as a blocker; do not retry loops.
- Large result sets: constrain queries (TOP N) — chat replies should summarize,
  not dump tables.
- The native Hermes `mcp_servers` integration cannot authorize headlessly
  against this server; this script is the supported path.
