#!/usr/bin/env bash
set -euo pipefail

# Install libclang (required by bindgen for FFI generation — Session 2 onward).
# The `clang` driver is installed alongside libclang-dev so libclang can locate
# its own resource directory (fixes "'stddef.h' file not found" on older bases).
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends libclang-dev clang

# Start a local iRODS server sidecar
docker run -d --name irods-server \
  -p 1247:1247 \
  -p 20000-20199:20000-20199 \
  ghcr.io/wtsi-npg/ub-22.04-irods-4.3.5:latest

echo "Waiting for iRODS..."
until nc -z localhost 1247 2>/dev/null; do sleep 2; done
sleep 5
echo "iRODS ready."

mkdir -p "$HOME/.irods"
cat > "$HOME/.irods/irods_environment.json" << 'EOF'
{
  "irods_host": "localhost",
  "irods_port": 1247,
  "irods_user_name": "irods",
  "irods_zone_name": "testZone",
  "irods_home": "/testZone/home/irods",
  "irods_default_resource": "replResc"
}
EOF
echo "irods" | script -q -c "iinit" /dev/null || true

# Install useful cargo tools
cargo install cargo-nextest cargo-watch
