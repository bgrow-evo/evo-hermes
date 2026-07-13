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
  printf '[hermes-aca] %s\n' "$*"
}

sync_from_persist() {
  if [ ! -d "$PERSIST_DIR" ]; then
    log "Persistent directory missing: $PERSIST_DIR"
    return 0
  fi

  mkdir -p "$LIVE_DIR"
  log "Restoring data: $PERSIST_DIR -> $LIVE_DIR"
  rsync "${RSYNC_COMMON[@]}" "${RSYNC_EXCLUDES[@]}" "$PERSIST_DIR"/ "$LIVE_DIR"/ || {
    log "WARNING: restore sync failed; continuing with available local data"
  }

  chown -R 10000:10000 "$LIVE_DIR" 2>/dev/null || true
}

backup_sqlite_db() {
  local rel="$1"
  local src="$LIVE_DIR/$rel"
  local dest="$PERSIST_DIR/$rel"
  local tmp

  if [ ! -s "$src" ]; then
    return 0
  fi

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
  if [ ! -d "$PERSIST_DIR" ]; then
    log "Persistent directory missing: $PERSIST_DIR"
    return 0
  fi

  mkdir -p "$PERSIST_DIR"
  log "Snapshotting data: $LIVE_DIR -> $PERSIST_DIR"
  rsync "${RSYNC_COMMON[@]}" "${RSYNC_EXCLUDES[@]}" "$LIVE_DIR"/ "$PERSIST_DIR"/ || {
    log "WARNING: snapshot sync failed"
  }

  backup_sqlite_db "state.db"
  backup_sqlite_db "kanban.db"
  backup_sqlite_db "profiles/$PROFILE_NAME/state.db"
}

sync_loop() {
  while true; do
    sleep "$SYNC_INTERVAL_SECONDS"
    sync_to_persist
  done
}

shutdown() {
  log "Shutdown requested"
  if [ -n "${SYNC_PID:-}" ]; then
    kill "$SYNC_PID" 2>/dev/null || true
    wait "$SYNC_PID" 2>/dev/null || true
  fi
  if [ -n "${HERMES_PID:-}" ]; then
    kill -TERM "$HERMES_PID" 2>/dev/null || true
    wait "$HERMES_PID" 2>/dev/null || true
  fi
  sync_to_persist
}

main() {
  mkdir -p "$LIVE_DIR" "$PERSIST_DIR"
  sync_from_persist

  sync_loop &
  SYNC_PID="$!"

  trap shutdown TERM INT

  log "Starting Hermes: $*"
  "$@" &
  HERMES_PID="$!"
  set +e
  wait "$HERMES_PID"
  local status="$?"
  set -e

  sync_to_persist
  kill "$SYNC_PID" 2>/dev/null || true
  wait "$SYNC_PID" 2>/dev/null || true
  exit "$status"
}

if [ "$#" -eq 0 ]; then
  set -- gateway run
fi

main "$@"
