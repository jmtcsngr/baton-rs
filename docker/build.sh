#!/usr/bin/env bash
set -euo pipefail

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
  "irods_user_name": "rods",
  "irods_zone_name": "testZone",
  "irods_authentication_scheme": "native"
}
EOF
echo "rods" | iinit

# Build and test
cargo build
cargo test --lib              # unit tests (no iRODS needed)
cargo test --test '*'         # integration tests (live iRODS required)
