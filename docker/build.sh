#!/usr/bin/env bash
set -euo pipefail

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --default-toolchain stable --no-modify-path
export PATH="$HOME/.cargo/bin:$PATH"

# Configure iRODS client. "irods-server" is the service container name,
# resolvable via the shared Docker network.
#
# `irods_default_hash_scheme = MD5` is required for the 4.2.7 matrix
# entry: that image's `replResc` has two children, and if the client
# defaults to a different hash than what the replication resource
# uses, iput's checksum disagrees with the recomputed checksum on one
# replica and iRODS marks it stale. Pinning the client to MD5 keeps
# every replica valid right after iput across all matrix entries.
# See issue #25.
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

# Build and test
cargo build
cargo test --lib              # unit tests (no iRODS needed)
cargo test --test '*'         # integration tests (live iRODS required)
