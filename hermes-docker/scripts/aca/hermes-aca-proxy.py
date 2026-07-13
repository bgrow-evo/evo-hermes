#!/usr/bin/env python3
import asyncio
import os
from aiohttp import ClientSession, web

PROXY_PORT = int(os.environ.get("HERMES_PROXY_PORT", "8080"))
DEFAULT_PORT = int(os.environ.get("HERMES_DEFAULT_TEAMS_PORT", "3978"))
STUDIO_PORT = int(os.environ.get("HERMES_STUDIO_TEAMS_PORT", "3979"))
DEFAULT_PROFILE = os.environ.get("HERMES_PROXY_DEFAULT_PROFILE", "studio")

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


async def health(_request):
    return web.Response(text="ok\n")


def select_backend(path):
    for profile in ("default", "studio"):
        prefix = f"/{profile}"
        if path == prefix:
            return profile, "/"
        if path.startswith(prefix + "/"):
            return profile, path[len(prefix):]
    return DEFAULT_PROFILE, path


async def proxy(request):
    profile, backend_path = select_backend(request.path)
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
    headers["x-forwarded-host"] = request.host
    headers["x-forwarded-proto"] = request.scheme

    body = await request.read()
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
    print(
        "[hermes-aca-proxy] listening on "
        f":{PROXY_PORT}; default=:{DEFAULT_PORT}; studio=:{STUDIO_PORT}; "
        f"bare-route={DEFAULT_PROFILE}",
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
