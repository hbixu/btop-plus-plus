# Changelog

All notable changes to this project will be documented in this file.


## [1.0.0] - 2026-11-22

### Added
- Initial release
- btop++ `1.4.8` compiled from the official source code
- Web access through ttyd (`PORT`, default `7681`; `FONT_SIZE`, default `16`)
- Alpine `3.24.4` base image; ttyd (`1.7.7-r0`) and tini from the Alpine branch (not pinned)
- Built-in healthcheck
- Mounted disks (e.g. `/volume1`) are detected at startup and shown once in btop's disks panel (nested mounts and duplicate devices are ignored)
- Default btop config file created on first run; settings are saved when the browser session closes
- `build.sh` (local / multi-platform build and push) and `check-versions.sh` / `check-versions.ps1`

---

## Types of Changes

- **Added**: for new features
- **Changed**: for changes in existing functionality
- **Deprecated**: for soon-to-be removed features
- **Removed**: for now removed features
- **Fixed**: for any bug fixes
- **Security**: for vulnerability fixes
