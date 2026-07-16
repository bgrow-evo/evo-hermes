#!/usr/bin/env python3
import asyncio
import hashlib
import json
import os
from aiohttp import ClientSession, web

PROXY_PORT = int(os.environ.get("HERMES_PROXY_PORT", "8080"))
DEFAULT_PORT = int(os.environ.get("HERMES_DEFAULT_TEAMS_PORT", "3978"))
STUDIO_PORT = int(os.environ.get("HERMES_STUDIO_TEAMS_PORT", "3979"))
DEFAULT_PROFILE = os.environ.get("HERMES_PROXY_DEFAULT_PROFILE", "studio")
ROUTES_FILE = os.environ.get("HERMES_TEAMS_PROFILE_ROUTES", "/opt/data/teams-profile-routes.yaml")
UNKNOWN_ROUTE_POLICY = os.environ.get("HERMES_TEAMS_ROUTE_UNKNOWN_POLICY", "deny").lower()

ROUTES = {
    "default": DEFAULT_PORT,
    "studio": STUDIO_PORT,
}

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
}


def _load_jsonish_routes(path):
    if not path or not os.path.exists(path):
        return {}

    with open(path, "r", encoding="utf-8") as f:
        text = f.read().strip()
    if not text:
        return {}

    # The generated route file is JSON, which is also valid YAML. Keeping the file
    # extension as .yaml leaves room for Hermes-native YAML later without adding
    # PyYAML to this tiny proxy.
    return json.loads(text)


def _env_route_registry():
    tenant_id = os.environ.get("TEAMS_TENANT_ID") or os.environ.get("STUDIO_TEAMS_TENANT_ID")
    routes = []
    for name, profile, channel in (
        ("hermes-admin", "default", os.environ.get("TEAMS_HOME_CHANNEL")),
        ("studio-photo-processing", "studio", os.environ.get("STUDIO_TEAMS_HOME_CHANNEL")),
    ):
        if tenant_id and channel:
            routes.append(
                {
                    "name": name,
                    "tenant_id": tenant_id,
                    "conversation_id": channel,
                    "channel_id": channel,
                    "profile": profile,
                    "home": True,
                    "respond_without_mention": True,
                }
            )
    return {
        "version": 1,
        "default_policy": UNKNOWN_ROUTE_POLICY,
        "allowed_tenants": [tenant_id] if tenant_id else [],
        "routes": routes,
    }


def load_route_registry():
    try:
        registry = _load_jsonish_routes(ROUTES_FILE)
        fallback = _env_route_registry()
        if not registry or (not registry.get("routes") and fallback.get("routes")):
            if registry and not registry.get("routes"):
                print("[hermes-aca-proxy] route file has no routes; using env fallback", flush=True)
            registry = fallback
    except Exception as exc:
        print(f"[hermes-aca-proxy] route file load failed: {type(exc).__name__}: {exc}", flush=True)
        registry = _env_route_registry()

    by_conversation = {}
    by_channel = {}
    for route in registry.get("routes", []):
        profile = route.get("profile")
        tenant_id = route.get("tenant_id")
        conversation_id = route.get("conversation_id")
        channel_id = route.get("channel_id")
        if profile not in ROUTES or not tenant_id:
            continue
        if conversation_id:
            key = (tenant_id, conversation_id)
            if key in by_conversation:
                raise RuntimeError(f"duplicate Teams conversation route: {tenant_id}/{conversation_id}")
            by_conversation[key] = route
        if channel_id:
            key = (tenant_id, channel_id)
            if key in by_channel:
                raise RuntimeError(f"duplicate Teams channel route: {tenant_id}/{channel_id}")
            by_channel[key] = route

    return {
        "raw": registry,
        "by_conversation": by_conversation,
        "by_channel": by_channel,
    }


async def health(_request):
    return web.Response(text="ok\n")


def _tenant_id(activity):
    channel_data = activity.get("channelData") or {}
    tenant = channel_data.get("tenant") or {}
    conversation = activity.get("conversation") or {}
    return tenant.get("id") or channel_data.get("tenantId") or conversation.get("tenantId")


def _conversation_id(activity):
    return (activity.get("conversation") or {}).get("id")


def _channel_id(activity):
    channel_data = activity.get("channelData") or {}
    channel = channel_data.get("channel") or {}
    return channel.get("id") or channel_data.get("channelId") or channel_data.get("teamsChannelId")


def _team_id(activity):
    team = (activity.get("channelData") or {}).get("team") or {}
    return team.get("id")


def _is_teams_activity(path, content_type):
    return path.endswith("/api/messages") and "json" in (content_type or "").lower()


def _hash(value):
    if not value:
        return "-"
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def resolve_activity_route(app, activity):
    tenant_id = _tenant_id(activity)
    conversation_id = _conversation_id(activity)
    channel_id = _channel_id(activity)
    registry = app["route_registry"]

    route = None
    if tenant_id and conversation_id:
        route = registry["by_conversation"].get((tenant_id, conversation_id))
    if route is None and tenant_id and channel_id:
        route = registry["by_channel"].get((tenant_id, channel_id))
    return route, tenant_id, conversation_id, channel_id, _team_id(activity)


def select_backend(path):
    for profile in ("default", "studio"):
        prefix = f"/{profile}"
        if path == prefix:
            return profile, "/"
        if path.startswith(prefix + "/"):
            return profile, path[len(prefix):]
    return DEFAULT_PROFILE, path


async def proxy(request):
    body = await request.read()
    profile, backend_path = select_backend(request.path)
    route = None
    tenant_id = None
    conversation_id = None
    channel_id = None
    team_id = None

    if _is_teams_activity(request.path, request.headers.get("content-type")) and body:
        try:
            activity = json.loads(body.decode("utf-8"))
            route, tenant_id, conversation_id, channel_id, team_id = resolve_activity_route(request.app, activity)
        except Exception as exc:
            print(f"[hermes-aca-proxy] Teams route parse failed: {type(exc).__name__}: {exc}", flush=True)
            route = None

        if route is not None:
            profile = route["profile"]
            backend_path = "/api/messages"
            print(
                "[hermes-aca-proxy] Teams route "
                f"name={route.get('name')} profile={profile} "
                f"tenant={_hash(tenant_id)} conversation={_hash(conversation_id)} "
                f"channel={_hash(channel_id)}",
                flush=True,
            )
        elif UNKNOWN_ROUTE_POLICY == "deny":
            print(
                "[hermes-aca-proxy] Teams route denied "
                f"tenant={_hash(tenant_id)} conversation={_hash(conversation_id)} "
                f"channel={_hash(channel_id)}",
                flush=True,
            )
            return web.Response(status=403, text="Teams route not configured\n")

    port = ROUTES.get(profile)
    if port is None:
        return web.Response(status=404, text=f"Unknown profile: {profile}\n")

    target = f"http://127.0.0.1:{port}{backend_path}"
    if request.query_string:
        target += "?" + request.query_string

    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in HOP_BY_HOP
    }
    headers["x-hermes-profile"] = profile
    if route is not None:
        headers["x-hermes-route-name"] = route.get("name", "")
        headers["x-hermes-route-profile"] = route.get("profile", "")
    if tenant_id:
        headers["x-hermes-tenant-id"] = tenant_id
    if conversation_id:
        headers["x-hermes-conversation-id"] = conversation_id
    if channel_id:
        headers["x-hermes-channel-id"] = channel_id
    if team_id:
        headers["x-hermes-team-id"] = team_id
    headers["x-forwarded-host"] = request.host
    headers["x-forwarded-proto"] = request.scheme

    session = request.app["client"]
    async with session.request(
        request.method,
        target,
        data=body,
        headers=headers,
        allow_redirects=False,
    ) as response:
        response_headers = {
            key: value
            for key, value in response.headers.items()
            if key.lower() not in HOP_BY_HOP
        }
        return web.Response(
            status=response.status,
            headers=response_headers,
            body=await response.read(),
        )


async def on_startup(app):
    app["client"] = ClientSession()
    app["route_registry"] = load_route_registry()
    route_count = len(app["route_registry"]["raw"].get("routes", []))
    print(
        "[hermes-aca-proxy] listening on "
        f":{PROXY_PORT}; default=:{DEFAULT_PORT}; studio=:{STUDIO_PORT}; "
        f"bare-route={DEFAULT_PROFILE}; teams-routes={route_count}; "
        f"unknown-policy={UNKNOWN_ROUTE_POLICY}",
        flush=True,
    )


async def on_cleanup(app):
    await app["client"].close()


def main():
    app = web.Application(client_max_size=50 * 1024**2)
    app.router.add_get("/healthz", health)
    app.router.add_route("*", "/{tail:.*}", proxy)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    web.run_app(app, host="0.0.0.0", port=PROXY_PORT)


if __name__ == "__main__":
    main()
