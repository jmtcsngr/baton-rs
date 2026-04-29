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

# `irods_default_hash_scheme = MD5` keeps the client aligned with the
# 4.2.7 image's replResc children — without it, one replica gets
# marked stale right after iput because of a checksum-algorithm
# mismatch. Same setting as in `docker/build.sh`. See issue #25.
mkdir -p "$HOME/.irods"
cat > "$HOME/.irods/irods_environment.json" << 'EOF'
{
  "irods_host": "localhost",
  "irods_port": 1247,
  "irods_user_name": "irods",
  "irods_zone_name": "testZone",
  "irods_home": "/testZone/home/irods",
  "irods_default_resource": "replResc",
  "irods_default_hash_scheme": "MD5"
}
EOF
echo "irods" | script -q -c "iinit" /dev/null || true

# Install useful cargo tools
cargo install cargo-nextest cargo-watch
