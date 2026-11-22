# btop-plus-plus

Minimal Docker image (Alpine) with **[btop++](https://github.com/aristocratos/btop)**, accessible from the **browser** through [ttyd](https://github.com/tsl0922/ttyd) or from the **terminal**.

## Features

- ✅ **[btop++](https://github.com/aristocratos/btop)** compiled from the official source code, at a pinned version
- ✅ Web access through **[ttyd](https://github.com/tsl0922/ttyd)**
- ✅ Shows the **host** processes, network interfaces, disks and sensors
- ✅ Built-in healthcheck
- ✅ Multi-platform: `linux/amd64` and `linux/arm64`

## File Structure

```
.
├── Dockerfile
├── docker-compose.yml
├── build.sh                  # Build helper (local / multi-platform + push)
├── check-versions.sh         # Update checker (Linux / macOS / Git Bash)
├── check-versions.ps1        # Update checker (Windows PowerShell)
├── update-btop.sh            # Interactive btop++ update: build/push a new image
├── root/                     # Scripts copied into the image (entrypoint)
├── VERSIONS.md               # Version and build details
├── CHANGELOG.md
├── third-party-licenses/     # Licenses of bundled third-party software
└── config/                   # btop configuration (generated on first run)
```

## Build the image

See **[VERSIONS.md](VERSIONS.md)** for the pinned versions and how to check for newer ones.

```bash
./build.sh --help                                  # See all options
./build.sh                                         # Local build (btop-plus-plus:VERSION and :latest)
./build.sh --btop-version 1.4.7                    # Local build with another btop++ version
./build.sh --registry docker.io/username --push    # Build linux/amd64 + linux/arm64 and push
./update-btop.sh                                   # Check for a new btop++ release, build and push (interactive)
```

btop++ is compiled during the build, so it takes a few minutes (longer for multi-platform builds).

## Configuration

### Environment variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `PORT` | ❌ No | Port of the web interface | `7681` |
| `FONT_SIZE` | ❌ No | Font size of the web interface | `16` |

### Volumes

| Path | Description |
|------|-------------|
| `/config` | btop configuration (`/config/btop/btop.conf`), created on first run |

### Disks

btop only shows the disks mounted in the container. Mount each disk you want to monitor, read-only:

```yaml
volumes:
  - /mnt/data:/mnt/data:ro
```

Mounted disks are detected at startup and listed in the container logs (`btop disk: /mnt/data (ext4)`).

To choose the disks manually instead, set in `btop.conf`:

```ini
use_fstab = False
disks_filter = "/mnt/data"
```

### Required permissions

| Option | Purpose |
|--------|---------|
| `pid: host` | See the host processes |
| `network_mode: host` | See the host network interfaces |
| `privileged: true` | Access sensors/temperatures |

Mounting `/proc`, `/sys` or `/dev` from the host is not needed.

## Usage

### Web (browser)

```bash
docker compose up -d
```

Open `http://<host>:7681`.

Without Compose:
```bash
docker run -d --name btop --pid=host --network=host --privileged \
  -v $(pwd)/config:/config \
  --restart unless-stopped btop-plus-plus:latest
```

### Terminal

```bash
docker run --rm -it --pid=host --network=host --privileged btop-plus-plus:latest btop
```

## Security

- **The web interface has no authentication.** Do not expose it to the internet. To require a password, override the command:
  ```yaml
  command: ["sh", "-c", "exec ttyd -W -s 2 -c user:password -p \"$PORT\" -t titleFixed=btop -t fontSize=\"$FONT_SIZE\" btop"]
  ```
- The container runs as **root** with access to the host processes: they can be killed from btop.

## License

This project is licensed under the **Apache License 2.0** — see the [LICENSE](LICENSE) file.

Bundled third-party software (licenses included in the image under `/usr/local/share/licenses/`):

| Component | License |
|-----------|---------|
| [btop++](https://github.com/aristocratos/btop) | Apache-2.0 |
| [ttyd](https://github.com/tsl0922/ttyd) | MIT |
| [tini](https://github.com/krallin/tini) | MIT |
