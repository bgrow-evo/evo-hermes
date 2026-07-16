"""
Microsoft Teams chat adapter for Hermes Agent — runs as a licensed *user*
(hermes-ai@evo.com) via delegated Microsoft Graph, not as a Bot Framework app.

Why: Teams channels are structurally threaded and bot replies require a
published Teams app. Chat surfaces (1:1 DM, group chat) are flat/inline, and a
licensed user needs no app at all — mirroring the Nextcloud Talk operating
model (bot user account, poll rooms, post as user).

How it works:
  - One-time device-code sign-in as hermes-ai mints a refresh token cached at
    ``TEAMS_GRAPH_TOKEN_CACHE`` (shared, on the persisted volume).
  - The adapter polls each configured chat every ``poll_seconds`` via
    ``GET /chats/{id}/messages`` (delegated Chat.ReadWrite — the user's own
    chats; NOT the metered tenant-wide getAllMessages APIs).
  - Replies post inline as hermes-ai via ``POST /chats/{id}/messages``.
  - ``dm_mode: all`` additionally discovers 1:1 chats every ~60s so a plain
    DM to hermes-ai just works (enable on exactly one profile).

Configuration in config.yaml::

    platforms:
      teams_graph:
        enabled: true
        extra:
          client_id: "<entra-public-client-app-id>"
          tenant_id: "<tenant-id>"
          token_cache: /opt/data/.graph_user_token_cache.json
          chats: "19:...@thread.v2,19:...@thread.v2"
          dm_mode: none            # "all" on exactly one profile
          poll_seconds: 3
          allowed_users: []        # AAD object IDs or UPNs

Or via env (overrides config.yaml): TEAMS_GRAPH_CLIENT_ID,
TEAMS_GRAPH_TENANT_ID, TEAMS_GRAPH_TOKEN_CACHE, TEAMS_GRAPH_CHATS,
TEAMS_GRAPH_DM_MODE, TEAMS_GRAPH_POLL_SECONDS, TEAMS_GRAPH_ALLOWED_USERS,
TEAMS_GRAPH_ALLOW_ALL_USERS, TEAMS_GRAPH_HOME_CHAT.
"""

import asyncio
import html as html_mod
import json
import logging
import os
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

from gateway.platforms.base import (
    BasePlatformAdapter,
    SendResult,
    MessageEvent,
    MessageType,
)
from gateway.config import Platform

GRAPH = "https://graph.microsoft.com/v1.0"
SCOPES = ["https://graph.microsoft.com/.default"]
# Teams chat messages cap at ~28KB of HTML; stay comfortably under.
MAX_HTML_BYTES = 25000
DM_DISCOVERY_INTERVAL = 60.0


# ---------------------------------------------------------------------------
# Token helper (sync msal wrapped in to_thread by the adapter)
# ---------------------------------------------------------------------------

class _TokenBroker:
    """Silent-only MSAL token source backed by the shared serializable cache.

    Never initiates interactive auth: on ``interaction_required`` the adapter
    goes fatal with a clear message — the documented fix is re-running the
    device-code login (scripts/graph_login.py).

    The cache file is SHARED between the default and studio gateway processes
    (and survives revision swaps via the sync loop). AAD rotates the refresh
    token on redemption, so a sibling process (or a replaced replica) can leave
    our in-memory copy stale. Two defenses:
      - reload the file whenever its mtime changes (cheap stat per acquire);
      - on a silent-refresh failure, force one reload-from-disk and retry
        before raising, so a token refreshed elsewhere (including an operator
        re-running graph_login + reseeding the file) is picked up live,
        without a process restart.
    """

    def __init__(self, client_id: str, tenant_id: str, cache_path: str):
        self.client_id = client_id
        self.tenant_id = tenant_id
        self.cache_path = Path(cache_path)
        self._app = None
        self._cache = None
        self._loaded_mtime = None
        self._lock = __import__("threading").Lock()

    def _file_mtime(self):
        try:
            return self.cache_path.stat().st_mtime
        except OSError:
            return None

    def _ensure_app(self, force: bool = False):
        import msal

        mtime = self._file_mtime()
        if self._app is not None and not force and mtime == self._loaded_mtime:
            return
        self._cache = msal.SerializableTokenCache()
        if self.cache_path.exists():
            self._cache.deserialize(self.cache_path.read_text())
        self._app = msal.PublicClientApplication(
            client_id=self.client_id,
            authority=f"https://login.microsoftonline.com/{self.tenant_id}",
            token_cache=self._cache,
        )
        self._loaded_mtime = mtime

    def _try_silent(self):
        accounts = self._app.get_accounts()
        if not accounts:
            return None
        return self._app.acquire_token_silent(SCOPES, account=accounts[0])

    def acquire(self) -> str:
        """Return a bearer token or raise RuntimeError with a stable code."""
        with self._lock:
            self._ensure_app()
            result = self._try_silent()
            if not result or "access_token" not in result:
                # A sibling process may have rotated the refresh token and
                # written a newer cache — reload from disk and retry once.
                self._ensure_app(force=True)
                result = self._try_silent()
            if not result:
                raise RuntimeError(
                    "token_not_found: no usable cached account — run graph_login.py"
                )
            if "access_token" not in result:
                err = result.get("error", "unknown")
                desc = result.get("error_description", "")
                raise RuntimeError(f"token_refresh_failed ({err}): {desc[:200]}")
            # Persist rotated refresh tokens. Atomic replace; last writer wins —
            # siblings pick the newer file up via the mtime check above.
            if self._cache.has_state_changed:
                tmp = self.cache_path.with_suffix(".tmp")
                tmp.write_text(self._cache.serialize())
                os.chmod(tmp, 0o600)
                tmp.replace(self.cache_path)
                self._loaded_mtime = self._file_mtime()
            return result["access_token"]


# ---------------------------------------------------------------------------
# HTML <-> text helpers
# ---------------------------------------------------------------------------

_TAG_RE = re.compile(r"<[^>]+>")
_BR_RE = re.compile(r"<br\s*/?>|</p>|</div>", re.IGNORECASE)


def html_to_text(content: str) -> str:
    """Flatten Teams chat HTML into plain text for the agent."""
    text = _BR_RE.sub("\n", content or "")
    text = _TAG_RE.sub("", text)
    return html_mod.unescape(text).strip()


def markdown_to_teams_html(text: str) -> str:
    """Best-effort markdown -> the small HTML subset Teams chat renders.

    Escapes everything first, then rebuilds code blocks, inline code,
    bold/italic, links, and newlines.
    """
    placeholder = {}

    def stash(m, kind):
        key = f"\x00{kind}{len(placeholder)}\x00"
        placeholder[key] = m
        return key

    # Pull code out before escaping so its content is preserved verbatim.
    blocks: List[str] = []
    def _block(m):
        blocks.append(m.group(1))
        return stash(f"<pre>{html_mod.escape(blocks[-1])}</pre>", "B")
    text = re.sub(r"```[a-zA-Z0-9_+-]*\n?(.*?)```", _block, text, flags=re.DOTALL)

    inlines: List[str] = []
    def _inline(m):
        inlines.append(m.group(1))
        return stash(f"<code>{html_mod.escape(inlines[-1])}</code>", "I")
    text = re.sub(r"`([^`\n]+)`", _inline, text)

    text = html_mod.escape(text)

    # Links / images -> anchors (escaped already, so match escaped chars).
    text = re.sub(r"!?\[([^\]]*)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', text)
    # Bold then italic.
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<i>\1</i>", text)
    # Headers -> bold lines.
    text = re.sub(r"(?m)^#{1,6}\s*(.+)$", r"<b>\1</b>", text)

    text = text.replace("\n", "<br>")

    for key, val in placeholder.items():
        text = text.replace(html_mod.escape(key), val).replace(key, val)
    return text


def chunk_html(content: str, limit: int = MAX_HTML_BYTES) -> List[str]:
    """Split rendered HTML on <br> boundaries so each POST stays under limit."""
    if len(content.encode("utf-8")) <= limit:
        return [content]
    chunks: List[str] = []
    current = ""
    for part in content.split("<br>"):
        candidate = f"{current}<br>{part}" if current else part
        if len(candidate.encode("utf-8")) > limit and current:
            chunks.append(current)
            current = part
        else:
            current = candidate
    if current:
        chunks.append(current)
    return chunks or [content[: limit // 2]]


# ---------------------------------------------------------------------------
# Adapter
# ---------------------------------------------------------------------------

class TeamsGraphAdapter(BasePlatformAdapter):
    """Poll-based Teams chat adapter acting as the hermes-ai user."""

    def __init__(self, config, **kwargs):
        platform = Platform("teams_graph")
        super().__init__(config=config, platform=platform)

        extra = getattr(config, "extra", {}) or {}
        self.client_id = os.getenv("TEAMS_GRAPH_CLIENT_ID") or extra.get("client_id", "")
        self.tenant_id = os.getenv("TEAMS_GRAPH_TENANT_ID") or extra.get("tenant_id", "")
        self.cache_path = (
            os.getenv("TEAMS_GRAPH_TOKEN_CACHE")
            or extra.get("token_cache")
            or "/opt/data/.graph_user_token_cache.json"
        )
        try:
            self.poll_seconds = float(
                os.getenv("TEAMS_GRAPH_POLL_SECONDS") or extra.get("poll_seconds", 3)
            )
        except (TypeError, ValueError):
            self.poll_seconds = 3.0
        self.poll_seconds = max(1.0, self.poll_seconds)

        chats_raw = os.getenv("TEAMS_GRAPH_CHATS") or extra.get("chats", "")
        if isinstance(chats_raw, list):
            self.chat_ids = [c.strip() for c in chats_raw if c and str(c).strip()]
        else:
            self.chat_ids = [c.strip() for c in str(chats_raw).split(",") if c.strip()]

        self.dm_mode = (
            os.getenv("TEAMS_GRAPH_DM_MODE") or str(extra.get("dm_mode", "none"))
        ).strip().lower()

        allowed_raw = os.getenv("TEAMS_GRAPH_ALLOWED_USERS") or extra.get("allowed_users", "")
        if isinstance(allowed_raw, list):
            allowed = allowed_raw
        else:
            allowed = str(allowed_raw).split(",")
        self._allowed_lower = {str(u).strip().lower() for u in allowed if str(u).strip()}
        self._allow_all = (
            os.getenv("TEAMS_GRAPH_ALLOW_ALL_USERS") or str(extra.get("allow_all_users", ""))
        ).strip().lower() in {"1", "true", "yes"}

        self._broker = _TokenBroker(self.client_id, self.tenant_id, self.cache_path)
        self._session = None  # aiohttp.ClientSession (bound to the gateway loop)
        self._session_loop = None  # loop that owns self._session
        self._poll_task: Optional[asyncio.Task] = None
        self._me_id: Optional[str] = None
        # chat_id -> {"watermark": iso-ts, "type": "dm"|"group", "name": str}
        self._chats: Dict[str, Dict[str, Any]] = {}
        self._state_path = Path(
            os.getenv("TEAMS_GRAPH_STATE_FILE")
            or extra.get("state_file")
            or Path(os.environ.get("HERMES_HOME", "/opt/data")) / ".teams_graph_state.json"
        )
        self._last_dm_discovery = 0.0

    @property
    def name(self) -> str:
        return "Teams (hermes-ai)"

    # ── Graph plumbing ────────────────────────────────────────────────────

    async def _token(self) -> str:
        return await asyncio.to_thread(self._broker.acquire)

    async def _graph(self, method: str, path: str, **kwargs) -> Any:
        """One Graph call with auth + 429 backoff. Raises on non-2xx.

        aiohttp sessions are event-loop-bound. The gateway loop owns
        ``self._session`` (poll loop + normal replies), but cron/tool
        deliveries await ``adapter.send()`` from the agent turn's OWN loop —
        reusing the shared session there raises "Timeout context manager
        should be used inside a task". Detect the foreign loop and use an
        ephemeral per-call session instead.
        """
        import aiohttp

        loop = asyncio.get_running_loop()
        ephemeral = None
        if self._session is not None and self._session_loop is loop:
            session = self._session
        elif self._session is None and self._session_loop in (None, loop):
            self._session = aiohttp.ClientSession()
            self._session_loop = loop
            session = self._session
        else:
            ephemeral = aiohttp.ClientSession()
            session = ephemeral

        url = path if path.startswith("http") else f"{GRAPH}{path}"
        try:
            for attempt in range(4):
                token = await self._token()
                headers = {"Authorization": f"Bearer {token}"}
                async with session.request(method, url, headers=headers, **kwargs) as resp:
                    if resp.status == 429:
                        retry = float(resp.headers.get("Retry-After", 2 ** (attempt + 1)))
                        logger.warning("teams_graph: 429 on %s — backing off %.0fs", path, retry)
                        await asyncio.sleep(min(retry, 60))
                        continue
                    if resp.status in (200, 201):
                        return await resp.json()
                    if resp.status == 204:
                        return None
                    body = (await resp.text())[:400]
                    raise RuntimeError(f"graph {method} {path} -> {resp.status}: {body}")
            raise RuntimeError(f"graph {method} {path}: throttled after retries")
        finally:
            if ephemeral is not None:
                await ephemeral.close()

    # ── State persistence ─────────────────────────────────────────────────

    def _load_state(self) -> Dict[str, str]:
        try:
            return json.loads(self._state_path.read_text()).get("watermarks", {})
        except Exception:
            return {}

    def _save_state(self) -> None:
        try:
            data = {"watermarks": {cid: info.get("watermark", "") for cid, info in self._chats.items()}}
            tmp = self._state_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(data))
            tmp.replace(self._state_path)
        except Exception as e:
            logger.warning("teams_graph: state save failed: %s", e)

    # ── Connection lifecycle ──────────────────────────────────────────────

    async def connect(self, **kwargs) -> bool:
        # kwargs absorbs gateway-passed flags like ``is_reconnect``.
        if not self.client_id or not self.tenant_id:
            self._set_fatal_error(
                "config_missing",
                "TEAMS_GRAPH_CLIENT_ID and TEAMS_GRAPH_TENANT_ID must be set",
                retryable=False,
            )
            return False
        if not self.chat_ids and self.dm_mode != "all":
            self._set_fatal_error(
                "config_missing",
                "TEAMS_GRAPH_CHATS is empty and dm_mode is not 'all' — nothing to poll",
                retryable=False,
            )
            return False

        try:
            me = await self._graph("GET", "/me")
            self._me_id = me.get("id")
            logger.info(
                "teams_graph: signed in as %s <%s>",
                me.get("displayName"), me.get("userPrincipalName"),
            )
        except Exception as e:
            msg = str(e)
            # Always retryable: a missing/stale cache file can appear later
            # (operator re-login + sync pull) and the broker reloads it from
            # disk — the gateway's reconnect backoff is the recovery path.
            # (A non-retryable fatal here left adapters permanently dead when
            # they booted seconds before the cache landed.)
            logger.error("teams_graph: auth failed: %s", msg)
            self._set_fatal_error("auth_failed", msg, retryable=True)
            return False

        saved = self._load_state()
        for cid in self.chat_ids:
            await self._register_chat(cid, saved.get(cid))

        self._poll_task = asyncio.create_task(self._poll_loop())
        self._mark_connected()
        logger.info(
            "teams_graph: polling %d chat(s) every %.0fs (dm_mode=%s)",
            len(self._chats), self.poll_seconds, self.dm_mode,
        )
        return True

    async def _register_chat(self, chat_id: str, saved_watermark: Optional[str] = None) -> None:
        """Add a chat to the poll set, seeding its watermark to 'now' so we
        never replay history on first boot (saved watermark wins on restart)."""
        info: Dict[str, Any] = {"watermark": saved_watermark or "", "type": "group", "name": chat_id}
        try:
            chat = await self._graph("GET", f"/chats/{chat_id}")
            info["type"] = "dm" if chat.get("chatType") == "oneOnOne" else "group"
            info["name"] = chat.get("topic") or chat_id
        except Exception as e:
            logger.warning("teams_graph: could not describe chat %s: %s", chat_id[:24], e)
        if not info["watermark"]:
            try:
                top = await self._graph("GET", f"/chats/{chat_id}/messages?$top=1")
                vals = top.get("value") or []
                info["watermark"] = vals[0]["createdDateTime"] if vals else "1970-01-01T00:00:00Z"
            except Exception:
                info["watermark"] = datetime.utcnow().isoformat() + "Z"
        self._chats[chat_id] = info

    async def disconnect(self, **kwargs) -> None:
        self._mark_disconnected()
        if self._poll_task and not self._poll_task.done():
            self._poll_task.cancel()
            try:
                await self._poll_task
            except asyncio.CancelledError:
                pass
        if self._session is not None:
            try:
                await self._session.close()
            except Exception:
                pass
            self._session = None
            self._session_loop = None
        self._save_state()

    # ── Poll loop ─────────────────────────────────────────────────────────

    async def _poll_loop(self) -> None:
        consecutive_errors = 0
        try:
            while True:
                try:
                    if self.dm_mode == "all" and (time.monotonic() - self._last_dm_discovery) > DM_DISCOVERY_INTERVAL:
                        await self._discover_dms()
                        self._last_dm_discovery = time.monotonic()
                    for chat_id in list(self._chats.keys()):
                        await self._poll_chat(chat_id)
                    consecutive_errors = 0
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    consecutive_errors += 1
                    msg = str(e)
                    if "token_not_found" in msg or "invalid_grant" in msg or "interaction" in msg.lower():
                        # Retryable: recovery = re-login + cache reseed, which the
                        # broker picks up from disk on the reconnect path.
                        logger.error("teams_graph: auth dead — device-code re-login needed: %s", msg)
                        self._set_fatal_error("auth_expired", msg, retryable=True)
                        await self._notify_fatal_error()
                        return
                    logger.warning("teams_graph: poll error (%d): %s", consecutive_errors, msg)
                    if consecutive_errors >= 10:
                        self._set_fatal_error("poll_failed", msg, retryable=True)
                        await self._notify_fatal_error()
                        return
                await asyncio.sleep(self.poll_seconds)
        except asyncio.CancelledError:
            raise

    async def _discover_dms(self) -> None:
        """Find 1:1 chats hermes-ai is in and add them to the poll set."""
        data = await self._graph(
            "GET", "/me/chats?$filter=chatType eq 'oneOnOne'&$top=50"
        )
        for chat in data.get("value", []):
            cid = chat.get("id")
            if cid and cid not in self._chats:
                logger.info("teams_graph: discovered DM chat %s", cid[:24])
                await self._register_chat(cid)
                self._save_state()

    async def _poll_chat(self, chat_id: str) -> None:
        info = self._chats[chat_id]
        data = await self._graph("GET", f"/chats/{chat_id}/messages?$top=15")
        messages = data.get("value", [])
        watermark = info.get("watermark", "")
        fresh = [
            m for m in messages
            if m.get("createdDateTime", "") > watermark and m.get("messageType") == "message"
        ]
        if not fresh:
            return
        # Advance watermark past everything fetched (including our own /
        # system messages) so nothing replays.
        info["watermark"] = max(m.get("createdDateTime", watermark) for m in messages) or watermark
        self._save_state()

        for m in sorted(fresh, key=lambda m: m.get("createdDateTime", "")):
            await self._handle_graph_message(chat_id, info, m)

    async def _handle_graph_message(self, chat_id: str, info: Dict[str, Any], m: Dict[str, Any]) -> None:
        frm = (m.get("from") or {}).get("user") or {}
        user_id = frm.get("id") or ""
        user_name = frm.get("displayName") or "unknown"
        if not user_id or user_id == self._me_id:
            return  # our own message or app/system message

        # Allowlist: AAD object id or UPN-ish display match.
        if not self._allow_all and self._allowed_lower:
            if user_id.lower() not in self._allowed_lower and user_name.lower() not in self._allowed_lower:
                logger.debug("teams_graph: ignoring unauthorized sender %s", user_id[:12])
                return

        body = m.get("body") or {}
        text = body.get("content") or ""
        if (body.get("contentType") or "").lower() == "html":
            text = html_to_text(text)
        text = text.strip()

        attachments = m.get("attachments") or []
        att_lines = [
            f"[attachment: {a.get('name') or a.get('contentType', 'file')}] {a.get('contentUrl') or ''}".strip()
            for a in attachments
            if a.get("contentUrl") or a.get("name")
        ]
        if att_lines:
            text = (text + "\n" + "\n".join(att_lines)).strip()
        if not text:
            return

        if not self._message_handler:
            return

        source = self.build_source(
            chat_id=chat_id,
            chat_name=info.get("name") or chat_id,
            chat_type=info.get("type", "group"),
            user_id=user_id,
            user_name=user_name,
            message_id=m.get("id"),
        )
        event = MessageEvent(
            text=text,
            message_type=MessageType.TEXT,
            source=source,
            message_id=m.get("id"),
            raw_message=m,
            timestamp=datetime.now(),
        )
        await self.handle_message(event)

    # ── Sending ───────────────────────────────────────────────────────────

    async def send(
        self,
        chat_id: str,
        content: str,
        reply_to: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ):
        html = markdown_to_teams_html(content)
        message_id = None
        try:
            for chunk in chunk_html(html):
                resp = await self._graph(
                    "POST",
                    f"/chats/{chat_id}/messages",
                    json={"body": {"contentType": "html", "content": chunk}},
                )
                message_id = (resp or {}).get("id") or message_id
                # Our own message shows up in the next poll; watermark logic
                # skips it via the from-user check, but advance eagerly to
                # keep the fetch window small.
                info = self._chats.get(chat_id)
                if info and resp and resp.get("createdDateTime"):
                    info["watermark"] = max(info.get("watermark", ""), resp["createdDateTime"])
            return SendResult(success=True, message_id=message_id)
        except Exception as e:
            logger.error("teams_graph: send to %s failed: %s", chat_id[:24], e)
            return SendResult(success=False, error=str(e))

    async def send_typing(self, chat_id: str, metadata=None) -> None:
        """Graph v1.0 exposes no typing signal for user chat posts — no-op."""
        return None

    async def get_chat_info(self, chat_id: str) -> Dict[str, Any]:
        info = self._chats.get(chat_id)
        if info:
            return {"name": info.get("name", chat_id), "type": info.get("type", "group")}
        try:
            chat = await self._graph("GET", f"/chats/{chat_id}")
            return {
                "name": chat.get("topic") or chat_id,
                "type": "dm" if chat.get("chatType") == "oneOnOne" else "group",
            }
        except Exception:
            return {"name": chat_id, "type": "group"}


# ---------------------------------------------------------------------------
# Standalone send (cron delivery when the gateway isn't in-process)
# ---------------------------------------------------------------------------

async def _standalone_send(
    pconfig,
    chat_id: str,
    message: str,
    *,
    thread_id: Optional[str] = None,
    media_files: Optional[List[str]] = None,
    force_document: bool = False,
) -> Dict[str, Any]:
    """One-shot chat post using the shared token cache (deliver=teams_graph)."""
    extra = getattr(pconfig, "extra", {}) or {}
    client_id = os.getenv("TEAMS_GRAPH_CLIENT_ID") or extra.get("client_id", "")
    tenant_id = os.getenv("TEAMS_GRAPH_TENANT_ID") or extra.get("tenant_id", "")
    cache_path = (
        os.getenv("TEAMS_GRAPH_TOKEN_CACHE")
        or extra.get("token_cache")
        or "/opt/data/.graph_user_token_cache.json"
    )
    target = chat_id or os.getenv("TEAMS_GRAPH_HOME_CHAT") or (extra.get("home_channel") or {}).get("chat_id", "")
    if not (client_id and tenant_id and target):
        return {"error": "teams_graph standalone send: client/tenant/chat not configured"}

    broker = _TokenBroker(client_id, tenant_id, cache_path)
    try:
        token = await asyncio.to_thread(broker.acquire)
    except Exception as e:
        return {"error": f"teams_graph standalone send: auth failed: {e}"}

    import aiohttp

    html = markdown_to_teams_html(message)
    message_id = None
    async with aiohttp.ClientSession() as session:
        for chunk in chunk_html(html):
            async with session.post(
                f"{GRAPH}/chats/{target}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={"body": {"contentType": "html", "content": chunk}},
            ) as resp:
                if resp.status not in (200, 201):
                    body = (await resp.text())[:300]
                    return {"error": f"teams_graph standalone send: {resp.status}: {body}"}
                message_id = (await resp.json()).get("id") or message_id
    return {"success": True, "message_id": message_id or str(int(time.time() * 1000))}


# ---------------------------------------------------------------------------
# Plugin registration
# ---------------------------------------------------------------------------

def check_requirements() -> bool:
    """msal + aiohttp are baked into the evo image; env decides readiness."""
    return bool(os.getenv("TEAMS_GRAPH_CLIENT_ID") and os.getenv("TEAMS_GRAPH_TENANT_ID"))


def validate_config(config) -> bool:
    extra = getattr(config, "extra", {}) or {}
    client_id = os.getenv("TEAMS_GRAPH_CLIENT_ID") or extra.get("client_id", "")
    tenant_id = os.getenv("TEAMS_GRAPH_TENANT_ID") or extra.get("tenant_id", "")
    return bool(client_id and tenant_id)


def is_connected(config) -> bool:
    return validate_config(config)


def _env_enablement() -> Optional[dict]:
    """Seed PlatformConfig.extra from env so env-only setups register."""
    client_id = os.getenv("TEAMS_GRAPH_CLIENT_ID", "").strip()
    tenant_id = os.getenv("TEAMS_GRAPH_TENANT_ID", "").strip()
    if not (client_id and tenant_id):
        return None
    seed: dict = {"client_id": client_id, "tenant_id": tenant_id}
    for env_name, key in (
        ("TEAMS_GRAPH_CHATS", "chats"),
        ("TEAMS_GRAPH_DM_MODE", "dm_mode"),
        ("TEAMS_GRAPH_POLL_SECONDS", "poll_seconds"),
        ("TEAMS_GRAPH_TOKEN_CACHE", "token_cache"),
    ):
        value = os.getenv(env_name, "").strip()
        if value:
            seed[key] = value
    home = os.getenv("TEAMS_GRAPH_HOME_CHAT", "").strip()
    if home:
        seed["home_channel"] = {
            "chat_id": home,
            "name": os.getenv("TEAMS_GRAPH_HOME_CHAT_NAME", home),
        }
    return seed


def register(ctx):
    """Plugin entry point: called by the Hermes plugin system."""
    ctx.register_platform(
        name="teams_graph",
        label="Teams (hermes-ai user)",
        adapter_factory=lambda cfg: TeamsGraphAdapter(cfg),
        check_fn=check_requirements,
        validate_config=validate_config,
        is_connected=is_connected,
        required_env=["TEAMS_GRAPH_CLIENT_ID", "TEAMS_GRAPH_TENANT_ID"],
        install_hint="msal + aiohttp (already baked into the evo image)",
        env_enablement_fn=_env_enablement,
        cron_deliver_env_var="TEAMS_GRAPH_HOME_CHAT",
        standalone_sender_fn=_standalone_send,
        allowed_users_env="TEAMS_GRAPH_ALLOWED_USERS",
        allow_all_env="TEAMS_GRAPH_ALLOW_ALL_USERS",
        max_message_length=0,  # adapter chunks HTML itself
        emoji="👤",
        pii_safe=False,
        allow_update_command=True,
        platform_hint=(
            "You are chatting on Microsoft Teams as the hermes-ai user in a "
            "flat (non-threaded) chat. Markdown support is limited — bold, "
            "italic, inline code, code blocks, and links render; tables do "
            "not. Keep responses conversational."
        ),
    )
