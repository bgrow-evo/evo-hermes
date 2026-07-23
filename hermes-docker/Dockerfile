# Hermes Agent - evo custom image
#
# Extends the official Nous Research image with the Microsoft Teams SDK
# pre-installed so the gateway never needs to lazy-install at runtime.
#
# Versions are pinned to match what Hermes requests in tools/lazy_deps.py
# (LAZY_DEPS["platform.teams"]). If you upgrade the base image and Hermes
# changes these pins, update them here to match and rebuild.
#
# Build (done automatically by install.ps1 / docker compose):
#   docker compose build --pull
#
# To pin a specific upstream release instead of :latest, set BASE_IMAGE:
#   docker compose build --pull --build-arg BASE_IMAGE=nousresearch/hermes-agent:v1.2.3
#
# Pinned to v2026.7.20 (Hermes 0.19.0). Docker Hub uses the calver tag, not "0.19.0".

ARG BASE_IMAGE=nousresearch/hermes-agent:v2026.7.20
FROM ${BASE_IMAGE}

# Switch to root so we can write into the venv owned by root.
USER root

# Pre-install the Teams SDK into the Hermes virtual environment.
# --no-cache keeps the layer small; uv resolves deps without network at
# import time because the wheels are already on disk.
# msal is intentionally NOT pinned: microsoft-teams-apps==2.0.13.4 requires msal>=1.33.0,
# so we let it resolve transitively (upstream lazy_deps["platform.teams"] pins only the two
# below). UV_NO_PROGRESS/NO_COLOR keep uv's output plain ASCII so `az acr build` log
# streaming doesn't crash on Windows consoles (cp1252) if uv emits Unicode.
RUN UV_NO_PROGRESS=1 NO_COLOR=1 uv pip install --python /opt/hermes/.venv --no-cache \
    "microsoft-teams-apps==2.0.13.4" \
    "aiohttp==3.14.1"

# Image-manipulation tooling for the `studio` profile's photo workflow.
# The studio profile runs its terminal toolset with backend=local, so image
# processing happens inside THIS container. The base image already ships
# python3 + Pillow; we add the CLI utilities the workflow may reach for:
#   imagemagick   - convert/identify/mogrify for ad-hoc edits
#   libvips-tools - fast `vips`/`vipsthumbnail` for large batches
#   webp          - cwebp/dwebp for WebP sources from vendor DAMs
#   zip/unzip     - package PIM-ready output to post to Teams
#   rsync/sqlite3 - ACA standard-storage restore/snapshot wrapper
# Pinned to apt (Debian 13/trixie) so the layer survives image rebuilds.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        imagemagick \
        libvips-tools \
        webp \
        zip \
        unzip \
        curl \
        ca-certificates \
        rsync \
        sqlite3 \
 && rm -rf /var/lib/apt/lists/*

# rclone gives the studio agent access to its own Azure Blob Storage container.
# We install the official binary (NOT the distro package): Debian's rclone is too
# old (v1.60) and only does service-principal auth via a file; inline azureblob
# service-principal creds (client_id/client_secret/tenant) need rclone >= 1.64.
# Credentials live in the volume at /opt/data/profiles/studio/rclone.conf
# (see docs/agent-blob-setup.md), so they survive rebuilds; only the binary is baked.
ARG RCLONE_VERSION=v1.74.3
RUN curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip \
 && unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin \
 && chmod 0755 /usr/local/bin/rclone \
 && rm /tmp/rclone.zip \
 && env -u RCLONE_VERSION /usr/local/bin/rclone version | head -1

# NOTE: profile assets (skills, playbook) are NOT baked into the image.
# The Azure Files share (sthermessbxwu2/hermes-data) is the single source of
# truth for /opt/data — restored on boot, snapshotted every 60s. The repo's
# profiles/ tree is reference material; install changes to the live volume
# deliberately (see docs/hermes-ai-chat-setup.md ops notes).

# Bundled evo skills: synced into EVERY profile's skills/ at boot by the base
# image's skills_sync (so existing and future profiles all get them).
# Layered onto the base image's bundled packs (per-file merge, nothing deleted).
COPY skills /opt/hermes/skills/

# teams_graph: custom platform adapter — Hermes chats as the hermes-ai user
# via delegated Microsoft Graph (no Teams app, no Bot Framework, no threads).
# Baked into the bundled platforms dir so it auto-loads like shipped platforms
# (user plugins under /opt/data/plugins need a plugins.enabled opt-in; bundled
# ones do not). Enablement is still config-gated per profile.
COPY plugins/teams_graph /opt/hermes/plugins/platforms/teams_graph

COPY scripts/aca/hermes-aca-restore.sh /etc/cont-init.d/00-aca-restore
COPY scripts/aca/hermes-aca-configure-profiles.sh /etc/cont-init.d/016-aca-configure-profiles
COPY scripts/aca/hermes-aca-sync.sh /etc/services.d/aca-sync/run
COPY scripts/aca/hermes-aca-proxy.py /usr/local/bin/hermes-aca-proxy
COPY scripts/aca/hermes-aca-proxy.sh /etc/services.d/aca-proxy/run
RUN chmod 0755 \
        /usr/local/bin/hermes-aca-proxy \
        /etc/cont-init.d/00-aca-restore \
        /etc/cont-init.d/016-aca-configure-profiles \
        /etc/services.d/aca-sync/run \
        /etc/services.d/aca-proxy/run

# The s6-overlay init runs as root and switches to the hermes user
# itself, so we do not need an explicit USER instruction here.
