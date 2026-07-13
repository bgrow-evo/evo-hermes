#!/usr/bin/env bash
set -Eeuo pipefail

LIVE_DIR="${HERMES_LIVE_DIR:-/opt/data}"
DEFAULT_PORT="${HERMES_DEFAULT_TEAMS_PORT:-3978}"
STUDIO_PORT="${HERMES_STUDIO_TEAMS_PORT:-3979}"
STUDIO_PROFILE="${HERMES_STUDIO_PROFILE:-studio}"
HERMES_BIN="${HERMES_BIN:-/opt/hermes/.venv/bin/hermes}"

export HERMES_HOME="$LIVE_DIR"
export HOME="$LIVE_DIR"

log() {
  printf '[hermes-aca-config] %s\n' "$*"
}

load_env_file() {
  local path="$1"
  [ -f "$path" ] || return 0

  while IFS='=' read -r key value; do
    case "$key" in
      ""|\#*) continue ;;
      *[!A-Za-z0-9_]* ) continue ;;
    esac
    value="${value%$'\r'}"
    value="${value%\"}"
    value="${value#\"}"
    export "$key=$value"
  done < "$path"
}

set_config() {
  local profile="$1"
  local key="$2"
  local value="$3"

  if [ "$profile" = "default" ]; then
    "$HERMES_BIN" config set "$key" "$value" >/dev/null
  else
    "$HERMES_BIN" -p "$profile" config set "$key" "$value" >/dev/null
  fi
}

update_gateway_state() {
  local path="$1"
  [ -f "$path" ] || return 0

  python - "$path" <<'PY' || true
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["desired_state"] = "running"
data["gateway_state"] = "running"
data["restart_requested"] = False
data["updated_at"] = datetime.now(timezone.utc).isoformat()
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, separators=(",", ":"))
PY
}

fix_live_permissions() {
  chown -R 10000:10000 "$LIVE_DIR" 2>/dev/null || true
  chmod -R a+rwX "$LIVE_DIR" 2>/dev/null || true
}

log "Configuring default Teams gateway on port $DEFAULT_PORT"
load_env_file "$LIVE_DIR/.env"
set_config default "platforms.teams.enabled" "true"
set_config default "platforms.teams.extra.port" "$DEFAULT_PORT"
[ -n "${TEAMS_CLIENT_ID:-}" ] && set_config default "platforms.teams.extra.client_id" "$TEAMS_CLIENT_ID"
[ -n "${TEAMS_CLIENT_SECRET:-}" ] && set_config default "platforms.teams.extra.client_secret" "$TEAMS_CLIENT_SECRET"
[ -n "${TEAMS_TENANT_ID:-}" ] && set_config default "platforms.teams.extra.tenant_id" "$TEAMS_TENANT_ID"

log "Configuring $STUDIO_PROFILE Teams gateway on port $STUDIO_PORT"
set_config "$STUDIO_PROFILE" "platforms.teams.enabled" "true"
set_config "$STUDIO_PROFILE" "platforms.teams.extra.port" "$STUDIO_PORT"
[ -n "${STUDIO_TEAMS_CLIENT_ID:-}" ]     && set_config "$STUDIO_PROFILE" "platforms.teams.extra.client_id"     "$STUDIO_TEAMS_CLIENT_ID"
[ -n "${STUDIO_TEAMS_CLIENT_SECRET:-}" ] && set_config "$STUDIO_PROFILE" "platforms.teams.extra.client_secret" "$STUDIO_TEAMS_CLIENT_SECRET"
[ -n "${STUDIO_TEAMS_TENANT_ID:-}" ]     && set_config "$STUDIO_PROFILE" "platforms.teams.extra.tenant_id"     "$STUDIO_TEAMS_TENANT_ID"

log "Configuring home channels"
[ -n "${TEAMS_HOME_CHANNEL:-}" ]        && set_config default           "platforms.teams.extra.home_channel" "$TEAMS_HOME_CHANNEL"
[ -n "${STUDIO_TEAMS_HOME_CHANNEL:-}" ] && set_config "$STUDIO_PROFILE" "platforms.teams.extra.home_channel" "$STUDIO_TEAMS_HOME_CHANNEL"

update_gateway_state "$LIVE_DIR/gateway_state.json"
update_gateway_state "$LIVE_DIR/profiles/$STUDIO_PROFILE/gateway_state.json"
fix_live_permissions
