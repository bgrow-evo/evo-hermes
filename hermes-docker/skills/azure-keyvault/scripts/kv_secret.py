#!/usr/bin/env python3
"""Read a secret from Azure Key Vault via the ACA managed identity.

Token source: the container app's identity endpoint (IDENTITY_ENDPOINT +
IDENTITY_HEADER env vars, injected by Azure) — no files, no MSAL, no refresh
management. Read-only by design.

Usage:
  kv_secret.py --name <secret-name> [--vault https://...vault.azure.net]
  kv_secret.py --list
"""
import argparse
import os
import sys

import requests

RESOURCE = "https://vault.azure.net"


def get_msi_token() -> str:
    endpoint = os.environ.get("IDENTITY_ENDPOINT")
    header = os.environ.get("IDENTITY_HEADER")
    if not endpoint or not header:
        sys.exit(
            "FAIL: managed-identity endpoint not available "
            "(IDENTITY_ENDPOINT/IDENTITY_HEADER unset — not running in the container app?)"
        )
    r = requests.get(
        endpoint,
        params={"api-version": "2019-08-01", "resource": RESOURCE},
        headers={"X-IDENTITY-HEADER": header},
        timeout=15,
    )
    if r.status_code != 200:
        sys.exit(f"FAIL: identity token request -> {r.status_code}: {r.text[:200]}")
    return r.json()["access_token"]


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--name", help="secret name to fetch")
    g.add_argument("--list", action="store_true", help="list secret NAMES only")
    ap.add_argument(
        "--vault",
        default=os.environ.get("HERMES_KEYVAULT_URI", "https://kv-hermes-sbx.vault.azure.net"),
    )
    args = ap.parse_args()
    vault = args.vault.rstrip("/")

    token = get_msi_token()
    headers = {"Authorization": f"Bearer {token}"}

    if args.list:
        names = []
        url = f"{vault}/secrets?api-version=7.4&maxresults=25"
        while url:
            r = requests.get(url, headers=headers, timeout=30)
            if r.status_code != 200:
                sys.exit(f"FAIL {r.status_code}: {r.text[:200]}")
            data = r.json()
            names += [s["id"].rsplit("/", 1)[-1] for s in data.get("value", [])]
            url = data.get("nextLink")
        print("\n".join(sorted(names)) or "(vault is empty)")
        return

    r = requests.get(f"{vault}/secrets/{args.name}?api-version=7.4", headers=headers, timeout=30)
    if r.status_code == 403:
        sys.exit("FAIL 403: container identity lacks 'Key Vault Secrets User' on the vault — blocker.")
    if r.status_code == 404:
        sys.exit(f"FAIL 404: secret '{args.name}' not found (kv_secret.py --list for names).")
    if r.status_code != 200:
        sys.exit(f"FAIL {r.status_code}: {r.text[:200]}")
    print(r.json()["value"])


if __name__ == "__main__":
    main()
