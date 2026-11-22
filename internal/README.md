# Internal documentation

This folder is **not synced to GitHub** (the sync workflow excludes it).

| File | Description |
|------|-------------|
| `DOCKER-README.md` | Docker Hub repository description (`hbixu/btop-plus-plus`). Update the version table on each release. |
| `update-btop.sh` | Checks for a new btop++ release, builds/pushes the image and updates the version files. |
| `release.sh` | Commits, tags and pushes a release from `main`. |

## Release workflow

The `develop` branch is for work in progress. Releases are prepared and created on `main`.

**1. Merge `develop` into `main`** (if there is work to release): pull request on Gitea, or `git switch main && git merge develop`

**2. On `main`, prepare the release**

- New btop++ version:
  ```bash
  ./internal/update-btop.sh   # checks for a new btop++ release, builds and pushes the image, updates the version files
  ```
- Other changes (Alpine, scripts, documentation): bump `DEFAULT_VERSION` in `build.sh`, add an entry to `CHANGELOG.md` (and to the version tables in `VERSIONS.md` and `internal/DOCKER-README.md`), then build and push the image:
  ```bash
  ./build.sh --registry docker.io/hbixu --push
  ```

**3. Release**

```bash
./internal/release.sh   # commits the changes, creates the tag vX.Y.Z and pushes main + tag
```

**4. Bring the release back to `develop`**

```bash
git switch develop && git merge main && git push
```

Pushing a tag to Gitea triggers the sync to GitHub and creates the release on Gitea and GitHub, with the notes from `CHANGELOG.md` and the versions table from `VERSIONS.md` (see [.gitea/README.md](../.gitea/README.md)). After a release, update the Docker Hub description with [DOCKER-README.md](DOCKER-README.md).
