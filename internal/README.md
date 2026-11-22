# Internal documentation

This folder contains internal documentation that is not part of the image or the user-facing docs.

- **DOCKER-README.md** — Content for the Docker Hub repository description (`hbixu/btop-plus-plus`). Update the version table when releasing new image tags.

## Release checklist

### btop++ update (automated)

1. `./update-btop.sh` — checks for a new btop++ release, builds/pushes the image and updates the version files
2. Review and commit: `git diff`, `git commit -am "Release X.Y.Z: btop++ A.B.C"`, `git tag vX.Y.Z`
3. Paste `internal/DOCKER-README.md` into the Docker Hub repository description

### Other updates (Alpine, ...)

1. `./check-versions.sh` — check for newer Alpine / btop++ versions (and the current ttyd version)
2. Update the `DEFAULT_*` values in `build.sh` (and the defaults/comments in `Dockerfile`)
3. Bump `DEFAULT_VERSION` in `build.sh`
4. Update `CHANGELOG.md`, the version table in `VERSIONS.md` and in `internal/DOCKER-README.md` (ttyd: version shown by `build.sh`)
5. Build and push: `./build.sh --registry docker.io/hbixu --push`
6. Paste `internal/DOCKER-README.md` into the Docker Hub repository description
7. Tag the release: `git tag vX.Y.Z`
