# Version Control

This document describes how application versions and metadata are managed in the image.

## Image Metadata

The Dockerfile supports build arguments for image metadata:

- **VERSION**: Docker image version (default: `1.0.0`)
- **BUILD_DATE**: Build date/time in ISO 8601 format (e.g., `2026-11-22T00:00:00Z`)

These values are stored as OCI (Open Container Initiative) labels in the image for traceability, together with the base image, btop++ and ttyd versions.

## Pinned Versions

The Alpine base image and btop++ are pinned to specific versions to ensure each image build uses exactly the same versions, providing:

- ✅ **Reproducibility**: Consistent builds
- ✅ **Stability**: No surprises with automatic updates
- ✅ **Control**: Updates only when explicitly indicated
- ✅ **Traceability**: Complete metadata with version and build date

### Not pinned: ttyd and tini

ttyd and tini are installed from the Alpine branch of the base image (e.g. `v3.24`) **without a pinned version**:

- Stable Alpine branches only receive bug and security fixes, so the latest version is the safest one
- Alpine removes old package revisions (e.g. `1.7.7-r0` → `1.7.7-r1`), so a pinned `-rN` version would eventually break the build

`build.sh` resolves the latest ttyd version at build time and records it in the image label `org.opencontainers.image.ttyd.version` and in the version history below. To force a specific version: `./build.sh --ttyd-version 1.7.7-r0`.


## Version History

| Release | Alpine | btop++ | ttyd |
|:-------:|--------|--------|------|
| `1.0.0` | `3.24.4` | `1.4.8` | `1.7.7-r0` |

## Application Versions

- **btop++**: Compiled from the official source code (git tag `v<BTOP_VERSION>`) in a separate build stage
  - Repository: https://github.com/aristocratos/btop
  - Releases: https://github.com/aristocratos/btop/releases
- **ttyd**: From Alpine package repository
  - Repository: https://github.com/tsl0922/ttyd
  - Alpine packages: https://pkgs.alpinelinux.org/packages?name=ttyd&branch=v3.24
- **tini**: From Alpine package repository
  - Repository: https://github.com/krallin/tini
  - Alpine packages: https://pkgs.alpinelinux.org/packages?name=tini&branch=v3.24

## Current Versions

Default versions are defined in `build.sh`.

**Note**: ttyd and tini follow the Alpine branch of `ALPINE_VERSION` (currently `v3.24`).

### Base Image Version

The base image version (`ALPINE_VERSION`) specifies which version of the official `alpine` image to use. A full version (e.g. `3.24.4`) is used instead of `3.24` or `latest` for reproducible builds.

- **Docker Hub Tags**: https://hub.docker.com/_/alpine/tags
- **Release notes**: https://alpinelinux.org/releases/

### btop++ Version

Any released tag can be used (without the `v` prefix):

```bash
./build.sh --btop-version 1.4.7
```

Very old versions (e.g. 1.2.x) may not compile with the compiler of recent Alpine releases; use an older `--alpine-version` if needed.

## How to Discover Available Versions

### Method 1: Automated script
```bash
./check-versions.sh          # Linux / macOS / Git Bash
.\check-versions.ps1         # Windows PowerShell
```

The scripts are read-only, do not require Docker, and exit with `1` when newer versions are available. ttyd is shown for information only (not pinned).

### Method 2: Direct Docker command
```bash
docker run --rm alpine:3.24 sh -c "apk update && apk search -v ttyd tini"
```

### Method 3: Websites
- **btop++**: https://github.com/aristocratos/btop/releases
- **ttyd**: https://pkgs.alpinelinux.org/packages?name=ttyd&branch=v3.24
- **tini**: https://pkgs.alpinelinux.org/packages?name=tini&branch=v3.24

## Check Container Versions

```bash
# Image labels
docker inspect btop-plus-plus:latest --format '{{json .Config.Labels}}'

# Inside a running container
docker exec btop btop --version
docker exec btop ttyd --version
docker inspect btop-plus-plus:latest --format '{{ index .Config.Labels "org.opencontainers.image.ttyd.version" }}'
```
