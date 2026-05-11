#!/usr/bin/env bash
set -euo pipefail

# Build baton-rs and run partisan's pytest suite against it. Mirrors
# `docker/build.sh` for the Rust + iRODS-client bootstrap, then
# layers on a pyenv-managed Python 3.12 (partisan's own preferred
# install path — see `partisan/Dockerfile.dev` /
# `partisan/docker/install_pyenv.sh` at the pinned commit). Wired up
# by `.github/workflows/partisan-tests.yml`.
#
# Lives under `.github/scripts/` (not `docker/`) because it's CI-only
# — `docker/` is reserved for assets that produce shippable images.
#
# The pyenv tree lives at `$PWD/.pyenv-cache/` so the calling
# workflow can persist it via `actions/cache@v4` keyed off this
# script + `.partisan-pin`. First cold run builds Python from source
# (~5 min); subsequent warm runs skip straight to the test step.
#
# Partisan commit comes from `.partisan-pin` at the repo root —
# easier to bump and lets the cache key invalidate automatically
# when we move forward. Recon context lives in the
# `project_partisan_pin.md` memory and in #57 / #49.

PYTHON_VERSION="3.12"
PYENV_RELEASE_VERSION="2.4.16"
PARTISAN_PIN_FILE="${PARTISAN_PIN_FILE:-.partisan-pin}"
PARTISAN_REPO="https://github.com/wtsi-npg/partisan.git"

# Parse the pin file: skip blank / comment lines, take the first
# remaining token. Tolerates the header comment block at the top.
PARTISAN_COMMIT="$(
    grep -v '^[[:space:]]*\(#\|$\)' "$PARTISAN_PIN_FILE" \
        | head -n1 \
        | tr -d '[:space:]'
)"
if [[ -z "$PARTISAN_COMMIT" ]]; then
    echo "no partisan commit in $PARTISAN_PIN_FILE" >&2
    exit 1
fi

# Install Rust (same shape as docker/build.sh).
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path
export PATH="$HOME/.cargo/bin:$PATH"

# Configure iRODS client — same shape as docker/build.sh (see that
# file for the MD5 default-hash-scheme rationale). Duplication is
# intentional: keeps this script self-contained so the unit-tests
# pipeline doesn't need to evolve in lockstep with partisan's needs.
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

# Build baton-rs binaries and put them on PATH so partisan's
# `subprocess.run(["baton-do", ...])` finds the right thing.
cargo build --release
export PATH="$PWD/target/release:$PATH"

# Python build dependencies — same set partisan's own
# `Dockerfile.dev` installs (pyenv builds CPython from source so it
# needs the same package set as a from-source CPython install).
apt-get update
apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git make \
    libbz2-dev libffi-dev libncurses-dev libreadline-dev \
    libssl-dev libsqlite3-dev liblzma-dev zlib1g-dev

# Workspace-relative pyenv root so the calling workflow's
# `actions/cache@v4` step can persist it across runs.
export PYENV_ROOT="$PWD/.pyenv-cache"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

# Two install gates: skip the pyenv install if the cache restored
# the bin dir, and skip the Python build if the cache restored a
# matching interpreter under `versions/`.
if [[ ! -x "$PYENV_ROOT/bin/pyenv" ]]; then
    # Adapted from partisan's `docker/install_pyenv.sh`. We follow
    # `pyenv-installer` HEAD (not SHA-pinned) because the file is
    # tiny and pinning it adds churn for marginal supply-chain win
    # in a CI-only context. Bump PYENV_RELEASE_VERSION to move the
    # installed pyenv forward.
    export PYENV_GIT_TAG="v${PYENV_RELEASE_VERSION}"
    curl -sSL https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer \
        | bash
fi

if ! pyenv versions --bare | grep -q "^${PYTHON_VERSION}\."; then
    MAKE_OPTS="-j$(nproc)" pyenv install "$PYTHON_VERSION"
fi
pyenv global "$PYTHON_VERSION"

# Smoke-check baton-rs is on the subprocess search path before
# partisan tries to spawn it. A missing binary here is much easier
# to debug than a `FileNotFoundError` ~30 tests in.
which baton-do
baton-do --version

# Fetch partisan at the pinned commit and install into an isolated
# venv (keeps partisan + pytest off the pyenv-global site-packages).
git clone "$PARTISAN_REPO" /tmp/partisan
git -C /tmp/partisan checkout "$PARTISAN_COMMIT"

python -m venv /tmp/partisan-venv
# shellcheck source=/dev/null
. /tmp/partisan-venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -e '/tmp/partisan[test]'
pip install --quiet pytest-timeout

# `--timeout=60` fires pytest-timeout on any hang (a few partisan
# tests do real iRODS round-trips; 30 s is too tight). `signal`
# kills the whole process group so a hung baton-do child doesn't
# wedge the run. `-v --tb=short` keeps the CI log readable.
cd /tmp/partisan
pytest --timeout=60 --timeout-method=signal -v --tb=short
