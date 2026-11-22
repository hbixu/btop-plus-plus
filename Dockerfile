# Base image version (ARG allows override during build)
# IMPORTANT: Update this version when necessary to ensure reproducible builds
#
# Repository: https://hub.docker.com/_/alpine
#
# To check available versions:
#   - Docker Hub tags: https://hub.docker.com/_/alpine/tags
#   - Or use the script: ./check-versions.sh
#
# Default version (adjust as needed):
# Latest release as of 2026-11-22: 3.24.4
ARG ALPINE_VERSION=3.24.4

# ============================================================================
# Build stage - compiles btop++ from the official source code
# ============================================================================
FROM alpine:${ALPINE_VERSION} AS build

# btop++ version (git tag without the "v" prefix)
# Releases: https://github.com/aristocratos/btop/releases
ARG BTOP_VERSION=1.4.8

RUN apk add --no-cache build-base linux-headers git

RUN git clone --depth 1 --branch "v${BTOP_VERSION}" https://github.com/aristocratos/btop.git /src
WORKDIR /src
RUN make -j"$(nproc)" && \
    make install PREFIX=/usr/local DESTDIR=/out && \
    install -Dm644 LICENSE /out/usr/local/share/licenses/btop/LICENSE && \
    echo "=== btop build info ===" && \
    /out/usr/local/bin/btop --version

# ============================================================================
# Runtime stage
# ============================================================================
FROM alpine:${ALPINE_VERSION}

# Image metadata
ARG BUILD_DATE
ARG VERSION=1.0.0
ARG ALPINE_VERSION
ARG BTOP_VERSION=1.4.8

# ttyd and tini are NOT pinned: the latest version from the Alpine branch is used
# (stable branches only receive fixes, and Alpine removes old package revisions,
# which would break builds with a pinned "-rN" version).
#
# TTYD_VERSION is resolved by build.sh (latest in the Alpine branch at build time)
# so the installed version is recorded in the image labels.
# Empty = latest from Alpine repo (label left empty).
ARG TTYD_VERSION=

# Labels for image metadata
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="btop-plus-plus" \
      org.opencontainers.image.description="btop++ resource monitor accessible from the browser (ttyd) or the terminal" \
      org.opencontainers.image.vendor="hbixu" \
      org.opencontainers.image.authors="hbixu" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.baseimage.name="alpine" \
      org.opencontainers.image.baseimage.version="${ALPINE_VERSION}" \
      org.opencontainers.image.btop.version="${BTOP_VERSION}" \
      org.opencontainers.image.ttyd.version="${TTYD_VERSION}"

# Install runtime dependencies
# - libstdc++/libgcc: C++ runtime required by btop
# - ttyd: serves the terminal over HTTP/WebSocket
# - tini: minimal init (signal forwarding and zombie reaping)
RUN apk add --no-cache \
    libstdc++ \
    libgcc \
    ttyd${TTYD_VERSION:+=$TTYD_VERSION} \
    tini && \
    echo "=== Build Info ===" && \
    echo "Image Version: ${VERSION}" && \
    echo "Build Date: ${BUILD_DATE}" && \
    ttyd --version

COPY --from=build /out/usr/local /usr/local

# Third-party licenses (btop++: Apache-2.0, ttyd: MIT, tini: MIT)
COPY LICENSE /usr/local/share/licenses/btop-plus-plus/LICENSE
COPY third-party-licenses/ttyd-LICENSE /usr/local/share/licenses/ttyd/LICENSE
COPY third-party-licenses/tini-LICENSE /usr/local/share/licenses/tini/LICENSE

# btop needs a UTF-8 locale to draw graphs correctly
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    XDG_CONFIG_HOME=/config \
    PORT=7681 \
    FONT_SIZE=16

# btop configuration (persisted via volume): /config/btop/btop.conf
RUN mkdir -p /config/btop
VOLUME ["/config"]

EXPOSE 7681

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -q --spider "http://127.0.0.1:${PORT}/" || exit 1

# Entrypoint: generates /etc/fstab from the mounted disks so btop shows them,
# and creates the default btop config on first run
COPY root/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
# -W: writable terminal (keyboard input); exiting btop closes the session, reloading the page reopens it
# -s 2: send SIGINT (instead of SIGHUP) to btop when the session closes, so it quits cleanly and saves its config
# -t fontSize: terminal font size in the browser (FONT_SIZE); larger = fewer columns/rows, bigger UI
# (no UTF-8 flag needed: LANG=C.UTF-8 lets btop detect UTF-8; the flag name also changed between versions)
CMD ["sh", "-c", "exec ttyd -W -s 2 -p \"$PORT\" -t titleFixed=btop -t fontSize=\"$FONT_SIZE\" btop"]
