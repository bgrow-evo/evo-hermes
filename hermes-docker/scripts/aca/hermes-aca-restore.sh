#!/usr/bin/env bash
set -Eeuo pipefail

LIVE_DIR="${HERMES_LIVE_DIR:-/opt/data}"
PERSIST_DIR="${HERMES_PERSIST_DIR:-/mnt/hermes-persist}"

RSYNC_EXCLUDES=(
  --exclude ".cache/"
  --exclude "__pycache__/"
  --exclude "*.lock"
  --exclude "*.pid"
  --exclude "*.tmp"
  --exclude "*.db-wal"
  --exclude "*.db-shm"
  --exclude "lazy-packages/"
  --exclude "logs/gateways/"
)

RSYNC_COMMON=(
  -rL
  --delete
  --no-perms
  --no-owner
  --no-group
  --omit-dir-times
  --no-times
)

log() {
  printf '[hermes-aca-restore] %s\n' "$*"
}

fix_auth_permissions() {
  local path
  for path in "$LIVE_DIR/auth.json" "$PERSIST_DIR/auth.json"; do
    if [ -f "$path" ]; then
      chown 10000:10000 "$path" 2>/dev/null || true
      chmod 0600 "$path" 2>/dev/null || true
    fi
  done
}

mkdir -p "$LIVE_DIR" "$PERSIST_DIR"

if [ -d "$PERSIST_DIR" ]; then
  log "Restoring data: $PERSIST_DIR -> $LIVE_DIR"

  # Pre-create the directory skeleton (workaround for Azure Files SMB + rsync directory-creation issue).
  rsync -r --include='*/' --exclude='*' "${RSYNC_EXCLUDES[@]}" \
    --no-perms --no-owner --no-group --omit-dir-times --no-times \
    "$PERSIST_DIR"/ "$LIVE_DIR"/ 2>/dev/null || true

  # Main transfer with bounded retry.
  attempt=0
  max_attempts=3
  while [ $attempt -lt $max_attempts ]; do
    if rsync "${RSYNC_COMMON[@]}" "${RSYNC_EXCLUDES[@]}" "$PERSIST_DIR"/ "$LIVE_DIR"/; then
      break
    fi
    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
      log "restore sync attempt $attempt failed, retrying in 2s..."
      sleep 2
    fi
  done

  if [ $attempt -ge $max_attempts ]; then
    log "WARNING: restore sync failed after $max_attempts attempts; continuing with available local data"
  fi
fi

chown -R 10000:10000 "$LIVE_DIR" 2>/dev/null || true
fix_auth_permissions
