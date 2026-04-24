#!/usr/bin/env bash
set -euo pipefail

# Install libclang (required by bindgen for FFI generation — Session 2 onward).
apt-get update -y
apt-get install -y --no-install-recommends libclang-dev

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --default-toolchain stable --no-modify-path
export PATH="$HOME/.cargo/bin:$PATH"

# Configure iRODS client. "irods-server" is the service container name,
# resolvable via the shared Docker network.
export HOME="${HOME:-/root}"
mkdir -p "$HOME/.irods"
cat > "$HOME/.irods/irods_environment.json" << 'EOF'
{
  "irods_host": "irods-server",
  "irods_port": 1247,
  "irods_user_name": "irods",
  "irods_zone_name": "testZone",
  "irods_home": "/testZone/home/irods",
  "irods_default_resource": "replResc"
}
EOF
nc -z -v irods-server 1247
echo "irods" | script -q -c "iinit" /dev/null

# Build and test
cargo build
cargo test --lib              # unit tests (no iRODS needed)
cargo test --test '*'         # integration tests (live iRODS required)
