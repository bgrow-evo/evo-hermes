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
  # Graph token cache is seeded into the share out-of-band (az storage file
  # upload) BEFORE the live copy exists — keep --delete from wiping it. It is
  # still persisted, via the explicit copy in sync_to_persist below.
  --exclude ".graph_user_token_cache.json"
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

  # Graph token cache: excluded from the rsync above so an out-of-band share
  # seed can never be --delete'd. Sync it explicitly, newest-wins in BOTH
  # directions:
  #  - persist newer (operator re-ran graph_login + uploaded) -> pull to live;
  #    the adapter's mtime-reload picks it up without a restart.
  #  - live newer (adapter rotated the refresh token) -> push to persist.
  _gc_live="$LIVE_DIR/.graph_user_token_cache.json"
  _gc_persist="$PERSIST_DIR/.graph_user_token_cache.json"
  # Identical content -> nothing to do (prevents the mtime ping-pong where each
  # copy direction makes the destination "newer" for the next cycle).
  if [ -f "$_gc_live" ] && [ -f "$_gc_persist" ] && cmp -s "$_gc_live" "$_gc_persist"; then
    :
  elif [ -f "$_gc_persist" ] && { [ ! -f "$_gc_live" ] || [ "$_gc_persist" -nt "$_gc_live" ]; }; then
    cp "$_gc_persist" "$_gc_live.tmp" && mv "$_gc_live.tmp" "$_gc_live" \
      && chown 10000:10000 "$_gc_live" 2>/dev/null; chmod 0600 "$_gc_live" 2>/dev/null
    log "Pulled newer Graph token cache from durable storage"
  elif [ -f "$_gc_live" ] && { [ ! -f "$_gc_persist" ] || [ "$_gc_live" -nt "$_gc_persist" ]; }; then
    cp "$_gc_live" "$_gc_persist.tmp" 2>/dev/null && mv "$_gc_persist.tmp" "$_gc_persist" \
      || log "WARNING: graph token cache persist copy failed"
  fi
}

trap 'sync_to_persist; exit 0' TERM INT

while true; do
  sleep "$SYNC_INTERVAL_SECONDS" &
  wait "$!" || true
  sync_to_persist
done
