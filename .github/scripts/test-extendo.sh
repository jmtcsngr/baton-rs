#!/usr/bin/env bash
set -exuo pipefail

# Build baton-rs and run extendo's Ginkgo suite against it.
# Mirrors `docker/build.sh` for the Rust + iRODS-client bootstrap,
# then layers on a Go toolchain (extendo's preferred install
# path — see `extendo/Dockerfile.dev` at the pinned commit).
# Wired up by `.github/workflows/extendo-tests.yml`.
#
# Lives under `.github/scripts/` (not `docker/`) because it's
# CI-only — `docker/` is reserved for assets that produce
# shippable images.
#
# The Go install + GOPATH live at `$PWD/.go-cache/` so the
# calling workflow can persist them via `actions/cache@v4` keyed
# off this script + `.github/scripts/extendo-pin`. First cold
# run downloads the Go tarball + ginkgo + module deps; subsequent
# warm runs skip straight to the test step.
#
# Extendo commit comes from `.github/scripts/extendo-pin` —
# easier to bump than a constant here, and lets the workflow's
# cache key invalidate automatically when we move forward. Recon
# context lives in issue #76.

# Go version — keep in step with extendo's `go.mod` toolchain
# line. Go's tarball is statically linked; works on the Ubuntu
# 16.04 build image used for the iRODS 4.2.7 leg (unlike pyenv,
# which couldn't build Python 3.12's `_ssl` against the old
# OpenSSL there).
GO_VERSION="1.24.1"
EXTENDO_PIN_FILE="${EXTENDO_PIN_FILE:-.github/scripts/extendo-pin}"
EXTENDO_REPO="https://github.com/wtsi-npg/extendo.git"

# Parse the pin file: skip blank / comment lines, take the first
# remaining token. Tolerates the header comment block at the top.
EXTENDO_COMMIT="$(
    grep -v '^[[:space:]]*\(#\|$\)' "$EXTENDO_PIN_FILE" \
        | head -n1 \
        | tr -d '[:space:]'
)"
if [[ -z "$EXTENDO_COMMIT" ]]; then
    echo "no extendo commit in $EXTENDO_PIN_FILE" >&2
    exit 1
fi

# Install Rust (same shape as docker/build.sh).
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path
export PATH="$HOME/.cargo/bin:$PATH"

# Configure iRODS client — same shape as docker/build.sh (see
# that file for the MD5 default-hash-scheme rationale).
# Duplication is intentional: keeps this script self-contained
# so the unit-tests pipeline doesn't need to evolve in lockstep
# with extendo's needs.
export HOME="${HOME:-/root}"
mkdir -p "$HOME/.irods"
cat > "$HOME/.irods/irods_environment.json" << 'EOF'
{
  "irods_host": "irods-server",
  "irods_port": 1247,
  "irods_user_name": "irods",
  "irods_zone_name": "testZone",
  "irods_home": "/testZone/home/irods",
  "irods_default_resource": "replResc",
  "irods_default_hash_scheme": "MD5"
}
EOF
nc -z -v irods-server 1247
echo "irods" | script -q -c "iinit" /dev/null

# Build baton-rs binaries and put them on PATH so extendo's
# subprocess.run-equivalents (`exec.Command("baton-do", ...)`)
# find the right thing.
cargo build --release
export PATH="$PWD/target/release:$PATH"

# Extendo, like partisan, parses `baton-do --version` to
# determine the wire shape. Switch baton-rs into strict-compat
# mode so it reports the upstream baton release we target wire
# parity with (see SESSIONS.md, #58).
export STRICT_BATON_COMPAT=1

# Workspace-relative Go root + GOPATH so the calling workflow's
# `actions/cache@v4` step can persist them across runs.
export GO_CACHE_ROOT="$PWD/.go-cache"
export GOROOT="$GO_CACHE_ROOT/go"
export GOPATH="$GO_CACHE_ROOT/gopath"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

# Install gate: skip the Go tarball download + extract if a
# matching toolchain is already in place (warm cache).
if [[ ! -x "$GOROOT/bin/go" ]] || [[ "$(${GOROOT}/bin/go version 2>/dev/null | awk '{print $3}')" != "go${GO_VERSION}" ]]; then
    rm -rf "$GOROOT"
    mkdir -p "$GO_CACHE_ROOT"
    curl -sSL -o "$GO_CACHE_ROOT/go.tar.gz" \
        "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    tar -C "$GO_CACHE_ROOT" -xzf "$GO_CACHE_ROOT/go.tar.gz"
    rm "$GO_CACHE_ROOT/go.tar.gz"
fi
mkdir -p "$GOPATH"

go version

# Fetch extendo at the pinned commit and build / test from there.
git clone "$EXTENDO_REPO" /tmp/extendo
git -C /tmp/extendo checkout "$EXTENDO_COMMIT"

# Resolve module deps + install ginkgo. `go install` honours the
# GOPATH we set above, so the ginkgo binary lands at
# `$GOPATH/bin/ginkgo` and gets re-used from cache on subsequent
# runs.
cd /tmp/extendo
go mod download
go install github.com/onsi/ginkgo/v2/ginkgo

# Smoke-check baton-rs is on the subprocess search path before
# extendo tries to spawn it. A missing binary here is much
# easier to debug than an exec error ~30 tests in.
which baton-do
baton-do --version

# Mirrors extendo's own `make test` target plus three diagnostics
# adjustments for CI:
#   -r                       recursively walk test suites
#   --race                   enable the Go race detector
#   -v                       print each spec name as it runs
#                            (default is a dot-per-test summary
#                            which makes a hang invisible)
#   --timeout=10m            bound the whole suite. Without this
#                            Ginkgo's default is one hour, so a
#                            hung spec would tie up the runner
#                            until GitHub Actions' job-level
#                            timeout fires instead.
#   --poll-progress-after=30s
#   --poll-progress-interval=15s
#                            if a spec sits longer than 30 s, dump
#                            the goroutine stacks so we can see
#                            *where* the hang is — repeated every
#                            15 s after the first dump. The suite
#                            normally completes in under a minute,
#                            so 30 s on a single spec is already
#                            suspicious.
ginkgo -r --race -v \
    --timeout=10m \
    --poll-progress-after=30s --poll-progress-interval=15s
