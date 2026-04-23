#!/usr/bin/env bash
set -euo pipefail

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
  "irods_user_name": "rods",
  "irods_zone_name": "testZone",
  "irods_authentication_scheme": "native"
}
EOF
echo "rods" | iinit || true

# Install useful cargo tools
cargo install cargo-nextest cargo-watch
