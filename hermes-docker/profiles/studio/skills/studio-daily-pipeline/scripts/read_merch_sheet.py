#!/usr/bin/env python3
"""Read the evo Merch Sheet (SharePoint list) via Microsoft Graph as hermes-ai.

Replaces the browser path for the Merch Sheet ("redirected to Microsoft
sign-in" under the unattended scheduler). Uses the shared hermes-ai MSAL token
cache with silent refresh — no interaction, no cookies.

Usage:
  read_merch_sheet.py --columns                 # list available columns
  read_merch_sheet.py [--filter TEXT] [--max N] [--format json|csv] [--out PATH]

Requires: delegated Sites.Read.All (admin-consented) on the hermes-ai Entra
client, and hermes-ai having read access to the list itself.
"""
import argparse
import csv
import io
import json
import os
import sys
from pathlib import Path

import msal
import requests

TENANT = os.environ.get("TEAMS_GRAPH_TENANT_ID", "1c2caf71-5666-4b98-bffc-ae0da8c4a4db")
CLIENT_ID = os.environ.get("TEAMS_GRAPH_CLIENT_ID", "8723feb3-bb77-4a0e-9c04-bbde8ec2cf37")
GRAPH = "https://graph.microsoft.com/v1.0"
SITE_HOST = "evogear-my.sharepoint.com"
SITE_PATH = "/personal/hreed_evo_com"
LIST_NAME = "Merch Sheet All"


def get_token() -> str:
    cache_path = Path(
        os.environ.get("TEAMS_GRAPH_TOKEN_CACHE", "/opt/data/.graph_user_token_cache.json")
    )
    cache = msal.SerializableTokenCache()
    cache.deserialize(cache_path.read_text())
    app = msal.PublicClientApplication(
        CLIENT_ID, authority=f"https://login.microsoftonline.com/{TENANT}", token_cache=cache
    )
    accounts = app.get_accounts()
    if not accounts:
        sys.exit("FAIL: no cached hermes-ai account (run graph_login.py)")
    result = app.acquire_token_silent(["https://graph.microsoft.com/.default"], account=accounts[0])
    if not result or "access_token" not in result:
        sys.exit(f"FAIL: token refresh: {(result or {}).get('error_description', 'unknown')[:200]}")
    if cache.has_state_changed:
        try:
            cache_path.write_text(cache.serialize())
        except OSError:
            pass
    return result["access_token"]


def graph_get(token: str, url: str) -> dict:
    r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=60)
    if r.status_code == 403:
        sys.exit(
            "FAIL 403: hermes-ai lacks access to the Merch Sheet list. "
            "Share the list (read) with hermes-ai@evo.com, then retry."
        )
    if r.status_code != 200:
        sys.exit(f"FAIL {r.status_code}: {r.text[:300]}")
    return r.json()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--columns", action="store_true", help="list column names and exit")
    ap.add_argument("--filter", default=None, help="case-insensitive substring match on any field")
    ap.add_argument("--max", type=int, default=0, help="max rows (0 = all)")
    ap.add_argument("--format", choices=["json", "csv"], default="json")
    ap.add_argument("--out", default=None, help="write to file instead of stdout")
    args = ap.parse_args()

    token = get_token()
    site = graph_get(token, f"{GRAPH}/sites/{SITE_HOST}:{SITE_PATH}")
    site_id = site["id"]
    lists = graph_get(token, f"{GRAPH}/sites/{site_id}/lists?$top=100")
    match = [l for l in lists.get("value", []) if l.get("displayName") == LIST_NAME]
    if not match:
        names = [l.get("displayName") for l in lists.get("value", [])]
        sys.exit(f"FAIL: list '{LIST_NAME}' not found. Available: {names}")
    list_id = match[0]["id"]

    rows = []
    url = f"{GRAPH}/sites/{site_id}/lists/{list_id}/items?expand=fields&$top=200"
    while url:
        data = graph_get(token, url)
        for item in data.get("value", []):
            fields = item.get("fields", {})
            fields.pop("@odata.etag", None)
            rows.append(fields)
            if args.max and len(rows) >= args.max:
                url = None
                break
        else:
            url = data.get("@odata.nextLink")
            continue
        break

    if args.columns:
        cols = sorted({k for r in rows[:50] for k in r if not k.startswith("_")})
        print("\n".join(cols))
        return

    if args.filter:
        needle = args.filter.lower()
        rows = [r for r in rows if any(needle in str(v).lower() for v in r.values())]

    if args.format == "csv":
        cols = sorted({k for r in rows for k in r if not k.startswith("_")})
        buf = io.StringIO()
        w = csv.DictWriter(buf, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
        output = buf.getvalue()
    else:
        output = json.dumps(rows, indent=1, default=str)

    if args.out:
        Path(args.out).write_text(output, encoding="utf-8")
        print(f"OK wrote {len(rows)} rows to {args.out}")
    else:
        print(output)


if __name__ == "__main__":
    main()
