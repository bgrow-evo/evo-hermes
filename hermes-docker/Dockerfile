# Hermes Agent — evo custom image
#
# Extends the official Nous Research image with the Microsoft Teams SDK
# pre-installed so the gateway never needs to lazy-install at runtime.
#
# Versions are pinned to match what Hermes requests in tools/lazy_deps.py
# (LAZY_DEPS["platform.teams"]).  If you upgrade the base image and Hermes
# changes these pins, update them here to match and rebuild.
#
# Build (done automatically by install.ps1 / docker compose):
#   docker compose build --pull
#
# To pin a specific upstream release instead of :latest, set BASE_IMAGE:
#   docker compose build --pull --build-arg BASE_IMAGE=nousresearch/hermes-agent:v1.2.3

ARG BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${BASE_IMAGE}

# Switch to root so we can write into the venv owned by root.
USER root

# Pre-install the Teams SDK into the Hermes virtual environment.
# --no-cache keeps the layer small; uv resolves deps without network at
# import time because the wheels are already on disk.
RUN uv pip install --python /opt/hermes/.venv --no-cache \
    "microsoft-teams-apps==2.0.13.4" \
    "aiohttp==3.13.4"

# Image-manipulation tooling for the `studio` profile's photo workflow.
# The studio profile runs its terminal toolset with backend=local, so image
# processing happens inside THIS container. The base image already ships
# python3 + Pillow; we add the CLI utilities the workflow may reach for:
#   imagemagick   — convert/identify/mogrify for ad-hoc edits
#   libvips-tools — fast `vips`/`vipsthumbnail` for large batches
#   webp          — cwebp/dwebp for WebP sources from vendor DAMs
#   zip/unzip     — package PIM-ready output to post to Teams
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
 && rm -rf /var/lib/apt/lists/*

# rclone gives the studio agent access to its own Azure Blob Storage container.
# We install the official binary (NOT the distro package): Debian's rclone is too
# old (v1.60) and only does service-principal auth via a file; inline azureblob
# service-principal creds (client_id/client_secret/tenant) need rclone >= 1.64.
# Credentials live in the volume at /opt/data/profiles/studio/rclone.conf
# (see docs/agent-blob-setup.md), so they survive rebuilds; only the binary is baked.
ARG RCLONE_VERSION=v1.74.3
RUN curl -fsSL "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip \
 && unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin \
 && chmod 0755 /usr/local/bin/rclone \
 && rm /tmp/rclone.zip \
 && /usr/local/bin/rclone version | head -1

# The s6-overlay init runs as root and switches to the hermes user
# itself, so we do not need an explicit USER instruction here.
