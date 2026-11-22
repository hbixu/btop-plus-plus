# btop-plus-plus

Minimal Docker image (Alpine) with **[btop++](https://github.com/aristocratos/btop)**, accessible from the **browser** through [ttyd](https://github.com/tsl0922/ttyd) or from the **terminal**. Shows the host processes, network, disks and sensors.

[![Source](https://img.shields.io/badge/source-GitHub-24292e?style=flat-square&logo=github)](https://github.com/hbixu/btop-plus-plus) ![linux/amd64](https://img.shields.io/badge/linux-amd64-28a745?style=flat-square) ![linux/arm64](https://img.shields.io/badge/linux-arm64-0073ec?style=flat-square)

## Features

- [btop++](https://github.com/aristocratos/btop) compiled from the official source code, at a pinned version
- Web access through [ttyd](https://github.com/tsl0922/ttyd) on a configurable port
- Built-in healthcheck
- Based on the official [Alpine](https://hub.docker.com/_/alpine) image

## Image versions

| Image tag | Alpine | btop++ | ttyd |
|-----------|--------|--------|------|
| `1.0.0`   | `3.24.4` | `1.4.8` | `1.7.7-r0` |

## Quick start

```bash
docker run -d --name btop --pid=host --network=host --privileged \
  -v $(pwd)/config:/config -e PORT=7681 \
  --restart unless-stopped hbixu/btop-plus-plus:latest
```

Open `http://<host>:7681`.

Terminal only:

```bash
docker run --rm -it --pid=host --network=host --privileged hbixu/btop-plus-plus:latest btop
```

## Example docker-compose

```yaml
services:
  btop:
    image: hbixu/btop-plus-plus:latest
    container_name: btop
    pid: host
    network_mode: host
    privileged: true
    environment:
      - PORT=7681
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
      # Disks to show in btop (read-only)
      # - /mnt/data:/mnt/data:ro
    restart: unless-stopped
```

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | No | Web interface (ttyd) port (default: `7681`) |
| `FONT_SIZE` | No | Font size of the web interface (default: `16`) |

## Volumes

| Path | Description |
|------|-------------|
| `/config` | btop configuration (`/config/btop/btop.conf`) |

## Required permissions

| Option | Purpose |
|--------|---------|
| `pid: host` | See the host processes |
| `network_mode: host` | See the host network interfaces |
| `privileged: true` | Sensors/temperatures and hardware metrics |

## Security note

ttyd has **no authentication** by default — do not expose the port to the internet. The container runs as root with the host PID namespace, so host processes can be killed from btop.

## License

Apache-2.0. Bundled software: btop++ (Apache-2.0), ttyd (MIT), tini (MIT).

## Links

- **Source / full documentation:** [GitHub](https://github.com/hbixu/btop-plus-plus)
- **Report issues:** [GitHub Issues](https://github.com/hbixu/btop-plus-plus/issues)
