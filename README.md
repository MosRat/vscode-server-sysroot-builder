# vscode-server-sysroot-builder
Build glibc for vscode-server in old systems


## One-line install from GitHub Release

Use the latest release by default:

```bash
curl -fsSL https://raw.githubusercontent.com/MosRat/vscode-server-sysroot-builder/main/scripts/install-release.sh | bash
```

Or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/MosRat/vscode-server-sysroot-builder/main/scripts/install-release.sh | bash
```

Install to a custom directory:

```bash
curl -fsSL https://raw.githubusercontent.com/MosRat/vscode-server-sysroot-builder/main/scripts/install-release.sh | bash -s -- --install-dir "$HOME/.local/vscode-sysroot"
```

Install a specific release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/MosRat/vscode-server-sysroot-builder/main/scripts/install-release.sh | bash -s -- --tag v2026.04.17-1
```

## CI cache

The GitHub Actions workflow uses two caches:

- Docker Buildx layer cache via `cache-from: type=gha` and `cache-to: type=gha,mode=max`
- crosstool-NG source tarball cache via `actions/cache` on `.ct-ng-tarballs`

This reduces repeated package installation, image rebuilds, and upstream source downloads.

## Build locally with cache

```bash
mkdir -p dist .ct-ng-tarballs

docker build -t vscode-server-sysroot-builder .

docker run --rm \
  -v "$PWD/dist:/out" \
  -v "$PWD/.ct-ng-tarballs:/work/tarballs" \
  vscode-server-sysroot-builder

ls -lh dist/
```

The `.ct-ng-tarballs/` directory stores downloaded source tarballs and speeds up repeated builds.

## Automated tag and release

The workflow `.github/workflows/release.yml` builds the Docker image, creates the sysroot tarball, then automatically creates and pushes a tag. If no tag is provided on manual dispatch, it uses a UTC timestamp and run number such as `v2026.04.17-12`. After tagging, it publishes a GitHub Release and uploads the tarball plus SHA256 file as release assets.
