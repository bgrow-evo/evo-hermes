#!/usr/bin/env bash
set -Eeuo pipefail

# s6 cont-init scripts do NOT inherit the container's env by default — ACA-injected
# vars (TEAMS_*, HERMES_*) live in /run/s6/container_environment as one-file-per-var.
# Without this, the script logged "credentials incomplete" and wrote an empty route
# file at startup even though runtime services saw the env fine. Source it first.
if [ -d /run/s6/container_environment ]; then
  for _envf in /run/s6/container_environment/*; do
    [ -f "$_envf" ] || continue
    _name="$(basename "$_envf")"
    case "$_name" in *[!A-Za-z0-9_]*) continue ;; esac
    export "$_name=$(cat "$_envf")"
  done
  unset _envf _name
fi

LIVE_DIR="${HERMES_LIVE_DIR:-/opt/data}"
PERSIST_DIR="${HERMES_PERSIST_DIR:-/mnt/hermes-persist}"
DEFAULT_PORT="${HERMES_DEFAULT_TEAMS_PORT:-3978}"
STUDIO_PORT="${HERMES_STUDIO_TEAMS_PORT:-3979}"
STUDIO_PROFILE="${HERMES_STUDIO_PROFILE:-studio}"
HERMES_BIN="${HERMES_BIN:-/opt/hermes/.venv/bin/hermes}"
TEAMS_SHARED_APP="${HERMES_TEAMS_SHARED_APP:-1}"
TEAMS_PROFILE_ROUTES="${HERMES_TEAMS_PROFILE_ROUTES:-$LIVE_DIR/teams-profile-routes.yaml}"

# Model applied to both profiles. gpt-5.6-terra is the balanced coding tier on the
# openai-codex OAuth route (NOT "gpt-5.6-codex-terra" — the -codex suffix was retired
# at 5.6). Override with HERMES_MODEL_DEFAULT if `hermes models` reports a different id.
MODEL_DEFAULT="${HERMES_MODEL_DEFAULT:-gpt-5.6-terra}"
MODEL_PROVIDER="${HERMES_MODEL_PROVIDER:-openai-codex}"
MODEL_BASE_URL="${HERMES_MODEL_BASE_URL:-https://chatgpt.com/backend-api/codex}"

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
  mkdir -p "$(dirname "$path")"

  python - "$path" <<'PY' || true
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
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

  local path
  for path in "$LIVE_DIR/auth.json" "$PERSIST_DIR/auth.json"; do
    if [ -f "$path" ]; then
      chown 10000:10000 "$path" 2>/dev/null || true
      chmod 0600 "$path" 2>/dev/null || true
    fi
  done
}

write_teams_routes() {
  python - "$TEAMS_PROFILE_ROUTES" <<'PY' || true
import json
import os
import sys

path = sys.argv[1]
tenant_id = os.environ.get("TEAMS_TENANT_ID") or os.environ.get("STUDIO_TEAMS_TENANT_ID")
routes = []

def add(name, profile, conversation_id, home):
    if not tenant_id or not conversation_id:
        return
    routes.append({
        "name": name,
        "tenant_id": tenant_id,
        "conversation_id": conversation_id,
        "team_id": os.environ.get(f"{name.upper().replace('-', '_')}_TEAM_ID"),
        "channel_id": conversation_id,
        "profile": profile,
        "home": home,
        "respond_without_mention": True,
    })

add("hermes-admin", "default", os.environ.get("TEAMS_HOME_CHANNEL"), True)
add("studio-photo-processing", "studio", os.environ.get("STUDIO_TEAMS_HOME_CHANNEL"), True)

data = {
    "version": 1,
    "default_policy": os.environ.get("HERMES_TEAMS_ROUTE_UNKNOWN_POLICY", "deny"),
    "allowed_tenants": [tenant_id] if tenant_id else [],
    "profile_homes": {
        route["profile"]: route["name"]
        for route in routes
        if route.get("home")
    },
    "routes": routes,
}

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  chown 10000:10000 "$TEAMS_PROFILE_ROUTES" 2>/dev/null || true
  chmod 0644 "$TEAMS_PROFILE_ROUTES" 2>/dev/null || true
  log "Wrote Teams profile routes to $TEAMS_PROFILE_ROUTES"
}

log "Configuring default Teams gateway on port $DEFAULT_PORT"
load_env_file "$LIVE_DIR/.env"
set_config default "platforms.teams.enabled" "true"
set_config default "platforms.teams.extra.port" "$DEFAULT_PORT"
[ -n "${TEAMS_CLIENT_ID:-}" ] && set_config default "platforms.teams.extra.client_id" "$TEAMS_CLIENT_ID"
[ -n "${TEAMS_CLIENT_SECRET:-}" ] && set_config default "platforms.teams.extra.client_secret" "$TEAMS_CLIENT_SECRET"
[ -n "${TEAMS_TENANT_ID:-}" ] && set_config default "platforms.teams.extra.tenant_id" "$TEAMS_TENANT_ID"
if [ -z "${TEAMS_CLIENT_ID:-}" ] || [ -z "${TEAMS_CLIENT_SECRET:-}" ] || [ -z "${TEAMS_TENANT_ID:-}" ]; then
  log "WARNING: default Teams credentials incomplete (client_id=$([ -n "${TEAMS_CLIENT_ID:-}" ] && printf yes || printf no), client_secret=$([ -n "${TEAMS_CLIENT_SECRET:-}" ] && printf yes || printf no), tenant_id=$([ -n "${TEAMS_TENANT_ID:-}" ] && printf yes || printf no))"
fi

log "Configuring $STUDIO_PROFILE Teams gateway on port $STUDIO_PORT"
if [ "$TEAMS_SHARED_APP" = "1" ] || [ "$TEAMS_SHARED_APP" = "true" ]; then
  log "Using shared Teams app credentials for $STUDIO_PROFILE"
  [ -n "${TEAMS_CLIENT_ID:-}" ]     && STUDIO_TEAMS_CLIENT_ID="$TEAMS_CLIENT_ID"
  [ -n "${TEAMS_CLIENT_SECRET:-}" ] && STUDIO_TEAMS_CLIENT_SECRET="$TEAMS_CLIENT_SECRET"
  [ -n "${TEAMS_TENANT_ID:-}" ]     && STUDIO_TEAMS_TENANT_ID="$TEAMS_TENANT_ID"
fi
set_config "$STUDIO_PROFILE" "platforms.teams.enabled" "true"
set_config "$STUDIO_PROFILE" "platforms.teams.extra.port" "$STUDIO_PORT"
[ -n "${STUDIO_TEAMS_CLIENT_ID:-}" ]     && set_config "$STUDIO_PROFILE" "platforms.teams.extra.client_id"     "$STUDIO_TEAMS_CLIENT_ID"
[ -n "${STUDIO_TEAMS_CLIENT_SECRET:-}" ] && set_config "$STUDIO_PROFILE" "platforms.teams.extra.client_secret" "$STUDIO_TEAMS_CLIENT_SECRET"
[ -n "${STUDIO_TEAMS_TENANT_ID:-}" ]     && set_config "$STUDIO_PROFILE" "platforms.teams.extra.tenant_id"     "$STUDIO_TEAMS_TENANT_ID"
if [ -z "${STUDIO_TEAMS_CLIENT_ID:-}" ] || [ -z "${STUDIO_TEAMS_CLIENT_SECRET:-}" ] || [ -z "${STUDIO_TEAMS_TENANT_ID:-}" ]; then
  log "WARNING: studio Teams credentials incomplete (client_id=$([ -n "${STUDIO_TEAMS_CLIENT_ID:-}" ] && printf yes || printf no), client_secret=$([ -n "${STUDIO_TEAMS_CLIENT_SECRET:-}" ] && printf yes || printf no), tenant_id=$([ -n "${STUDIO_TEAMS_TENANT_ID:-}" ] && printf yes || printf no))"
fi

log "Configuring home channels"
[ -n "${TEAMS_HOME_CHANNEL:-}" ]        && set_config default           "platforms.teams.extra.home_channel" "$TEAMS_HOME_CHANNEL"
[ -n "${STUDIO_TEAMS_HOME_CHANNEL:-}" ] && set_config "$STUDIO_PROFILE" "platforms.teams.extra.home_channel" "$STUDIO_TEAMS_HOME_CHANNEL"
write_teams_routes

# ── teams_graph: chat adapter running as the hermes-ai user (no app, no threads) ──
# Shared identity (client/tenant/token-cache) may arrive via container env; the
# per-profile chat routing MUST live in each profile's config.yaml because both
# gateway processes share the container env. Adapter precedence: env > extra.
if [ -n "${TEAMS_GRAPH_CLIENT_ID:-}" ] && [ -n "${TEAMS_GRAPH_TENANT_ID:-}" ]; then
  log "Configuring teams_graph (hermes-ai user chat) on both profiles"
  for _p in default "$STUDIO_PROFILE"; do
    set_config "$_p" "platforms.teams_graph.enabled" "true"
    set_config "$_p" "platforms.teams_graph.extra.client_id" "$TEAMS_GRAPH_CLIENT_ID"
    set_config "$_p" "platforms.teams_graph.extra.tenant_id" "$TEAMS_GRAPH_TENANT_ID"
    set_config "$_p" "platforms.teams_graph.extra.token_cache" "${TEAMS_GRAPH_TOKEN_CACHE:-$LIVE_DIR/.graph_user_token_cache.json}"
    set_config "$_p" "platforms.teams_graph.extra.poll_seconds" "${TEAMS_GRAPH_POLL_SECONDS:-3}"
    # Same human allowlist for both profiles (AAD object IDs / UPNs).
    _graph_allowed="${TEAMS_GRAPH_ALLOWED_USERS:-${TEAMS_ALLOWED_USERS:-}}"
    if [ -n "$_graph_allowed" ]; then
      set_config "$_p" "platforms.teams_graph.extra.allowed_users" "$_graph_allowed"
    fi
  done
  # default profile: Hermes Admin group chat + all 1:1 DMs with hermes-ai
  set_config default "platforms.teams_graph.extra.chats" "${HERMES_ADMIN_CHAT_ID:-}"
  set_config default "platforms.teams_graph.extra.dm_mode" "all"
  [ -n "${HERMES_ADMIN_CHAT_ID:-}" ] && set_config default "platforms.teams_graph.extra.home_channel.chat_id" "$HERMES_ADMIN_CHAT_ID"
  # studio profile: Studio Photo group chat only. Without a chat ID there is
  # nothing to poll (dm_mode=none), so keep the platform off until the group
  # chat exists — avoids a noisy fatal adapter on the studio gateway.
  if [ -n "${STUDIO_CHAT_ID:-}" ]; then
    set_config "$STUDIO_PROFILE" "platforms.teams_graph.extra.chats" "$STUDIO_CHAT_ID"
    set_config "$STUDIO_PROFILE" "platforms.teams_graph.extra.dm_mode" "none"
    set_config "$STUDIO_PROFILE" "platforms.teams_graph.extra.home_channel.chat_id" "$STUDIO_CHAT_ID"
  else
    set_config "$STUDIO_PROFILE" "platforms.teams_graph.enabled" "false"
    log "teams_graph disabled on $STUDIO_PROFILE (STUDIO_CHAT_ID unset)"
  fi

  # disco profile (migrated from OpenClaw): only configured when its profile
  # home exists on the volume AND its chat is wired. Data-engineer agent,
  # gpt-5.6-sol on the shared codex OAuth, "Disco Engineer" group chat only.
  if [ -d "$LIVE_DIR/profiles/disco" ]; then
    # Legacy Bot Framework adapter would auto-enable from TEAMS_* env and
    # collide with the default gateway's port 3978 — keep it off explicitly.
    set_config disco "platforms.teams.enabled" "false"
    set_config disco "platforms.teams_graph.extra.client_id" "$TEAMS_GRAPH_CLIENT_ID"
    set_config disco "platforms.teams_graph.extra.tenant_id" "$TEAMS_GRAPH_TENANT_ID"
    set_config disco "platforms.teams_graph.extra.token_cache" "${TEAMS_GRAPH_TOKEN_CACHE:-$LIVE_DIR/.graph_user_token_cache.json}"
    set_config disco "platforms.teams_graph.extra.poll_seconds" "${TEAMS_GRAPH_POLL_SECONDS:-3}"
    [ -n "$_graph_allowed" ] && set_config disco "platforms.teams_graph.extra.allowed_users" "$_graph_allowed"
    if [ -n "${DISCO_CHAT_ID:-}" ]; then
      set_config disco "platforms.teams_graph.enabled" "true"
      set_config disco "platforms.teams_graph.extra.chats" "$DISCO_CHAT_ID"
      set_config disco "platforms.teams_graph.extra.dm_mode" "none"
      set_config disco "platforms.teams_graph.extra.home_channel.chat_id" "$DISCO_CHAT_ID"
    else
      set_config disco "platforms.teams_graph.enabled" "false"
      log "teams_graph disabled on disco (DISCO_CHAT_ID unset)"
    fi
    set_config disco "model.default" "${DISCO_MODEL_DEFAULT:-gpt-5.6-sol}"
    set_config disco "model.provider" "$MODEL_PROVIDER"
    set_config disco "model.base_url" "$MODEL_BASE_URL"
    set_config disco "compression.codex_gpt55_autoraise" "false"
    # evo-mcp access is via the bundled `evo-mcp` skill (headless hermes-ai
    # auth). The native mcp_servers integration is NOT configured: its OAuth
    # provider requires an interactive browser flow and parks the server at
    # every boot. Scrub any leftover config from earlier attempts.
    python - "$LIVE_DIR/profiles/disco/config.yaml" <<'PY' || true
import sys, yaml
p = sys.argv[1]
try:
    with open(p) as f:
        cfg = yaml.safe_load(f) or {}
except FileNotFoundError:
    sys.exit(0)
if cfg.pop("mcp_servers", None) is not None:
    with open(p, "w") as f:
        yaml.safe_dump(cfg, f, default_flow_style=False, sort_keys=False)
    print("[hermes-aca-config] removed legacy mcp_servers config from disco")
PY
    update_gateway_state "$LIVE_DIR/profiles/disco/gateway_state.json"
    log "Configured disco profile (model=${DISCO_MODEL_DEFAULT:-gpt-5.6-sol})"
  fi
else
  log "teams_graph not configured (TEAMS_GRAPH_CLIENT_ID/TENANT_ID unset)"
fi

# Restore the shared token cache from durable storage if the live copy is
# missing (EmptyDir starts blank each revision; the sync loop persists it).
_cache_live="${TEAMS_GRAPH_TOKEN_CACHE:-$LIVE_DIR/.graph_user_token_cache.json}"
_cache_persist="$PERSIST_DIR/$(basename "$_cache_live")"
if [ ! -f "$_cache_live" ] && [ -f "$_cache_persist" ]; then
  cp "$_cache_persist" "$_cache_live"
  chown 10000:10000 "$_cache_live" 2>/dev/null || true
  chmod 0600 "$_cache_live" 2>/dev/null || true
  log "Restored Graph token cache from durable storage"
fi

log "Setting model to $MODEL_DEFAULT on $MODEL_PROVIDER and disabling gpt-5.5 autoraise (both profiles)"
set_config default           "model.default" "$MODEL_DEFAULT"
set_config "$STUDIO_PROFILE"  "model.default" "$MODEL_DEFAULT"
set_config default           "model.provider" "$MODEL_PROVIDER"
set_config "$STUDIO_PROFILE"  "model.provider" "$MODEL_PROVIDER"
set_config default           "model.base_url" "$MODEL_BASE_URL"
set_config "$STUDIO_PROFILE"  "model.base_url" "$MODEL_BASE_URL"
# codex_gpt55_autoraise only fires for gpt-5.5 on codex-OAuth; moot on 5.6 but set false
# so the repeating "auto-compaction raised to 85%" notice never returns.
set_config default           "compression.codex_gpt55_autoraise" "false"
set_config "$STUDIO_PROFILE"  "compression.codex_gpt55_autoraise" "false"

update_gateway_state "$LIVE_DIR/gateway_state.json"
update_gateway_state "$LIVE_DIR/profiles/$STUDIO_PROFILE/gateway_state.json"
fix_live_permissions
