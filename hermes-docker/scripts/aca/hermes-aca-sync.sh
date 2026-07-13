#!/usr/bin/env bash
set -Eeuo pipefail

LIVE_DIR="${HERMES_LIVE_DIR:-/opt/data}"
PERSIST_DIR="${HERMES_PERSIST_DIR:-/mnt/hermes-persist}"
SYNC_INTERVAL_SECONDS="${HERMES_SYNC_INTERVAL_SECONDS:-60}"
PROFILE_NAME="${HERMES_PROFILE:-studio}"

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
  printf '[hermes-aca-sync] %s\n' "$*"
}

backup_sqlite_db() {
  local rel="$1"
  local src="$LIVE_DIR/$rel"
  local dest="$PERSIST_DIR/$rel"
  local tmp

  [ -s "$src" ] || return 0
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "/tmp/hermes-db-backup.XXXXXX")"
  if sqlite3 "$src" ".backup '$tmp'"; then
    cp "$tmp" "$dest.tmp"
    mv "$dest.tmp" "$dest"
  else
    log "WARNING: sqlite backup failed: $rel"
  fi
  rm -f "$tmp"
}

sync_to_persist() {
  [ -d "$PERSIST_DIR" ] || {
    log "Persistent directory missing: $PERSIST_DIR"
    return 0
  }

  mkdir -p "$PERSIST_DIR"
  log "Snapshotting data: $LIVE_DIR -> $PERSIST_DIR"

  # Pre-create the directory skeleton so mkstemp() never hits a missing parent.
  # Workaround for Azure Files SMB + rsync directory-creation issue: force every
  # directory node to exist via a cheap, file-free rsync pass before file transfer.
  # This works around a persistent mkstemp failure on the first attempt.
  rsync -r --include='*/' --exclude='*' "${RSYNC_EXCLUDES[@]}" \
    --no-perms --no-owner --no-group --omit-dir-times --no-times \
    "$LIVE_DIR"/ "$PERSIST_DIR"/ 2>/dev/null || true

  # Main transfer with bounded retry: try up to 3 times, 2 second sleep between attempts.
  local attempt=0
  local max_attempts=3
  while [ $attempt -lt $max_attempts ]; do
    if rsync "${RSYNC_COMMON[@]}" "${RSYNC_EXCLUDES[@]}" "$LIVE_DIR"/ "$PERSIST_DIR"/; then
      break
    fi
    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
      log "snapshot sync attempt $attempt failed, retrying in 2s..."
      sleep 2
    fi
  done

  if [ $attempt -ge $max_attempts ]; then
    log "ERROR: snapshot sync failed after $max_attempts attempts"
  fi

  backup_sqlite_db "state.db"
  backup_sqlite_db "kanban.db"
  backup_sqlite_db "profiles/$PROFILE_NAME/state.db"
}

trap 'sync_to_persist; exit 0' TERM INT

while true; do
  sleep "$SYNC_INTERVAL_SECONDS" &
  wait "$!" || true
  sync_to_persist
done
