# btop-plus-plus

Minimal Docker image (Alpine) with **[btop++](https://github.com/aristocratos/btop)**, the resource monitor, accessible from the **browser** through [ttyd](https://github.com/tsl0922/ttyd) or directly from the **terminal**.

## Features

- ✅ **[btop++](https://github.com/aristocratos/btop)** compiled from the official source code, at a pinned version
- ✅ Web access through **[ttyd](https://github.com/tsl0922/ttyd)** (configurable port)
- ✅ Shows the **host** processes, network interfaces, disks and sensors
- ✅ Built-in healthcheck
- ✅ Multi-platform: `linux/amd64` and `linux/arm64`
- ✅ Based on the official [Alpine](https://hub.docker.com/_/alpine) image

## Requirements

- Docker and Docker Compose installed
- Linux host (btop reads the host's `/proc` and `/sys`)

## File Structure

```
.
├── Dockerfile
├── docker-compose.yml
├── build.sh                  # Build helper (local / multi-platform + push)
├── check-versions.sh         # Update checker (Linux / macOS / Git Bash)
├── check-versions.ps1        # Update checker (Windows PowerShell)
├── VERSIONS.md               # Version and build details
├── CHANGELOG.md
├── third-party-licenses/     # Licenses of bundled third-party software
└── config/                   # btop configuration (generated on first run)
```

## Build the image

For version defaults, version history, pinned components, and how to check for newer versions, see **[VERSIONS.md](VERSIONS.md)**.

**Option 1: Helper script (Recommended)**
```bash
chmod +x build.sh
./build.sh --help  # See all options

# Local build only (tags btop-plus-plus:VERSION and :latest on this machine)
./build.sh

# Local build with a different btop++ version
./build.sh --btop-version 1.4.7

# Build and push to a registry (e.g. Docker Hub; replace 'username' with your Docker Hub username)
# Default: linux/amd64 and linux/arm64
./build.sh --registry docker.io/username --push
```

**Option 2: Direct Docker build (single platform)**
```bash
docker build \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VERSION=1.0.0 \
  --build-arg ALPINE_VERSION=3.24.4 \
  --build-arg BTOP_VERSION=1.4.8 \
  --build-arg TTYD_VERSION=1.7.7-r0 \
  -t btop-plus-plus:1.0.0 .
```

**Notes:**
- btop++ is compiled during the build, so the first build takes a few minutes. Multi-platform builds compile the non-native architecture under QEMU emulation and can take considerably longer.
- Before pushing, authenticate: `docker login`

## Configuration

### Environment variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `PORT` | ❌ No | Port where the web interface (ttyd) listens | `7681` |

In `docker-compose.yml`, `PORT` is read from `BTOP_PORT`, so it can be changed without editing the file:

```bash
BTOP_PORT=5002 docker compose up -d
```

or with a `.env` file next to `docker-compose.yml`:

```env
BTOP_PORT=5002
```

> **Synology DSM (XPEnology):** with the ARPL/RR bootloader, port `7681` is already taken by the bootloader — use another port, e.g. `5002`.

### Volumes

| Path | Description |
|------|-------------|
| `/config` | btop configuration (`/config/btop/btop.conf`), created on first run. It can be edited directly or from btop's options menu (`o` key). |

### Additional disks

btop only shows the disks that are mounted in the container. Mount each disk you want to monitor, read-only:

```yaml
volumes:
  - /mnt/hdd1:/mnt/hdd1:ro
```

### Required permissions

| Option | Purpose |
|--------|---------|
| `pid: host` | See the host processes |
| `network_mode: host` | See the host network interfaces and traffic |
| `privileged: true` | Access sensors/temperatures and hardware metrics (`/sys`, `/dev`) |

There is no need to bind-mount `/proc`, `/sys` or `/dev` from the host:

- `/proc` — with `pid: host`, the container's `/proc` already shows the host processes; CPU and memory (`/proc/stat`, `/proc/meminfo`) are always host-wide, and network counters come from the host because of `network_mode: host`. Mounting the host `/proc` over the container's is discouraged.
- `/sys` — sysfs (sensors, block devices) already reflects the host; `privileged: true` makes it fully accessible.
- `/dev` — `privileged: true` already exposes all host devices.

## Usage

### Web (browser)

After building the image with `build.sh`, start with Docker Compose:

```bash
docker compose up -d

# View logs
docker compose logs -f
```

Open `http://<host>:7681` (or the port set in `BTOP_PORT`). Quitting btop (`q`) closes the session; reload the page to open it again.

Without Compose:
```bash
docker run -d --name btop --pid=host --network=host --privileged \
  -v $(pwd)/config:/config -e PORT=7681 \
  --restart unless-stopped btop-plus-plus:latest
```

### Terminal

```bash
docker run --rm -it --pid=host --network=host --privileged btop-plus-plus:latest btop
```

## Healthcheck

The image includes a healthcheck that verifies the web interface responds on `PORT`. Use `docker ps` to see the status; for details run `docker inspect btop --format '{{json .State.Health}}'`.

## Security

- **ttyd has no authentication by default.** Do not expose the port to the internet; keep it on your local network or put it behind an authenticated reverse proxy. To require a password, override the command:
  ```yaml
  command: ["sh", "-c", "exec ttyd -W -c user:password -p \"$PORT\" btop --utf-force"]
  ```
- The container runs as **root** with `privileged: true` and the host PID namespace: from btop it is possible to send signals to (kill) **host** processes. Remove `privileged: true` if you do not need sensor data.

## License

This project is licensed under the **Apache License 2.0** — see the [LICENSE](LICENSE) file.

The image bundles third-party software under its own licenses (copies included in the image under `/usr/local/share/licenses/`):

| Component | License |
|-----------|---------|
| [btop++](https://github.com/aristocratos/btop) | Apache-2.0 |
| [ttyd](https://github.com/tsl0922/ttyd) | MIT |
| [tini](https://github.com/krallin/tini) | MIT |
