# baton-rs: Rust Reimplementation Plan

A multi-session plan for reimplementing the [wtsi-npg/baton](https://github.com/wtsi-npg/baton) iRODS client in Rust using Claude Code.

---

## Overview

baton is a C client for iRODS focused on metadata operations, exposing a single JSON interface for listing, querying, and updating data objects and collections. Its core programs are `baton-list`, `baton-get`, `baton-put`, `baton-chmod`, `baton-metamod`, `baton-metaquery`, and `baton-do` (a multiplexer for all operations).

This plan reimplements baton in Rust across multiple Claude Code sessions, with CI, container publishing, a Codespaces devcontainer, and Dependabot set up before any Rust code is written.

**Target baton version for parity.** baton 6.x is the reference. This is the current major version at the time of writing and is the version required by partisan 4.x, the main downstream Python consumer. Session 1 should pin the exact 6.x point release being targeted (e.g. 6.0.0) in `SESSIONS.md` so that schema changes in later 6.x releases are explicit decisions rather than silent drift.

**Licensing.** baton is GPL-2.0. baton-rs is a functional reimplementation and does not copy source, but adopting GPL-2.0 (or GPL-3.0) keeps expectations aligned with the existing baton ecosystem. Decide before any public release.

## Key architectural decisions

**iRODS binding strategy.** FFI to the iRODS C API via `bindgen`. This mirrors baton's own approach and is the only practical path for full protocol compatibility with iRODS 4.2.x, 4.3.x, and 5.x.

**JSON library.** `serde_json`, with `serde` derives on all types to match baton's JSON schema exactly.

**CLI argument parsing.** `clap` with derive macros, shared argument groups reused across binaries where possible.

**Project structure.** Single crate with multiple binaries under `src/bin/`. All binaries share the same library code (types, FFI, connection handling), and Cargo builds each file in `src/bin/` as a separate executable automatically. This mirrors how baton itself is organised — one codebase, multiple programs sharing C source files. A workspace split would only be worthwhile if `baton-core` were later published to crates.io as a standalone library for third-party Rust consumers; that decision can be deferred.

**Linking strategy.** Dynamic linking against the iRODS client libraries installed from the iRODS `.deb` packages. The publish container (`ubuntu:22.04`) installs the same iRODS runtime `.deb` packages used at build time, keeping ABI compatibility straightforward. Static musl linking was considered but rejected because it would require rebuilding the iRODS C client libraries for musl, which is not off-the-shelf. If a Debian-based publish image is later required, the path forward is building custom Debian iRODS client packages.

## Repository layout

```
baton-rs/
├── .devcontainer/
│   ├── devcontainer.json
│   └── setup.sh
├── .github/
│   ├── dependabot.yml              # weekly/monthly dependency updates
│   └── workflows/
│       ├── unit-tests.yml          # CI matrix across iRODS versions
│       └── publish.yml             # publish container on tag
├── docker/
│   ├── build.sh                    # build + test script (runs in iRODS dev container)
│   ├── build-release.sh            # release build script
│   └── Dockerfile                  # publish image
├── Cargo.toml                      # single crate manifest
├── build.rs                        # bindgen for iRODS FFI (Session 2 onwards)
├── SESSIONS.md                     # inter-session context for Claude Code
├── src/
│   ├── lib.rs                      # re-exports from modules below
│   ├── types.rs                    # DataObject, Avu, Acl, Replicate, etc.
│   ├── json.rs                     # serde helpers, short-name aliases
│   ├── ffi.rs                      # safe wrappers over bindgen output
│   ├── connection.rs               # RodsConnection, auto-reconnect
│   ├── operations/                 # per-operation logic shared between binaries
│   │   ├── list.rs
│   │   ├── get.rs
│   │   ├── put.rs
│   │   ├── chmod.rs
│   │   ├── metamod.rs
│   │   └── metaquery.rs
│   └── bin/
│       ├── baton-list.rs
│       ├── baton-get.rs
│       ├── baton-put.rs
│       ├── baton-chmod.rs
│       ├── baton-metamod.rs
│       ├── baton-metaquery.rs
│       └── baton-do.rs
└── tests/                          # integration tests (live iRODS required)
    ├── common/
    │   └── mod.rs                  # shared test fixtures
    ├── list.rs
    ├── metaquery.rs
    └── ...
```

Each binary in `src/bin/` is expected to be a thin CLI shell that parses arguments with `clap` and delegates to the matching function in `src/operations/`. This keeps business logic out of binaries and lets it be tested directly from integration tests.

---

## Session plan

| Session | Focus |
|---|---|
| **0** | Infrastructure: CI workflow, publish workflow, Dockerfiles, devcontainer, Dependabot |
| 1 | Crate scaffold + JSON data model + serde types |
| 2 | iRODS FFI layer (bindgen, safe connection wrapper, auto-reconnect) |
| 3 | `baton-list` |
| 4 | `baton-metamod` + `baton-metaquery` |
| 5 | `baton-get` + `baton-put` |
| 6 | `baton-chmod` |
| 7 | `baton-do` multiplexer |
| 8 | Polish: unbuffered output, error JSON format, `--unsafe`, compatibility tests |

---

## Session 0: Infrastructure

The point of doing infrastructure first is that every commit from Session 1 onward is automatically built and tested against real iRODS servers in all supported versions, and every dependency update flows in as a reviewable PR from day one.

### `.github/workflows/unit-tests.yml`

Mirrors baton's own CI matrix directly: iRODS 4.2.7 (Ubuntu 16.04), 4.3.4, and 4.3.5 (Ubuntu 22.04). Uses the `wtsi-npg/build-irods-client-action` action (which we own) to execute the build script inside the matching iRODS client dev container, joined to the iRODS server service container's Docker network.

```yaml
name: "Unit tests"
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    continue-on-error: ${{ matrix.experimental }}

    strategy:
      matrix:
        include:
          - irods: "4.2.7"
            build_image: "ghcr.io/wtsi-npg/ub-16.04-irods-clients-dev-4.2.7:latest"
            server_image: "ghcr.io/wtsi-npg/ub-16.04-irods-4.2.7:latest"
            experimental: false
          - irods: "4.3.4"
            build_image: "ghcr.io/wtsi-npg/ub-22.04-irods-clients-dev-4.3.4:latest"
            server_image: "ghcr.io/wtsi-npg/ub-22.04-irods-4.3.4:latest"
            experimental: false
          - irods: "4.3.5"
            build_image: "ghcr.io/wtsi-npg/ub-22.04-irods-clients-dev-4.3.5:latest"
            server_image: "ghcr.io/wtsi-npg/ub-22.04-irods-4.3.5:latest"
            experimental: false

    services:
      irods-server:
        image: ${{ matrix.server_image }}
        ports:
          - "1247:1247"
          - "20000-20199:20000-20199"
        volumes:
          - /dev/shm:/dev/shm
        options: >-
          --health-cmd "nc -z -v localhost 1247"
          --health-start-period 60s
          --health-interval 10s
          --health-timeout 20s
          --health-retries 6

    steps:
      - name: "Checkout"
        uses: actions/checkout@v4

      - name: "Build and test"
        uses: wtsi-npg/build-irods-client-action@v1.1.1
        with:
          build-image: ${{ matrix.build_image }}
          build-script: docker/build.sh
          docker-network: ${{ job.services.irods-server.network }}

      - name: "Show test log"
        if: ${{ failure() }}
        run: find "$GITHUB_WORKSPACE" -name "*.log" -exec cat {} \;
```

### `docker/build.sh`

Runs inside the iRODS dev container. The iRODS headers and libraries are already present, so we install Rust, configure the iRODS client to reach the service container, and run the test suite.

```bash
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
```

### `.github/workflows/publish.yml`

Triggers on any tag push. Builds release binaries inside the iRODS dev container, then packages them into a publish container image on GHCR.

```yaml
name: "Publish container"
on:
  push:
    tags:
      - "*"

permissions:
  contents: read
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - name: "Checkout"
        uses: actions/checkout@v4

      - name: "Build release binaries"
        uses: wtsi-npg/build-irods-client-action@v1.1.1
        with:
          build-image: ghcr.io/wtsi-npg/ub-22.04-irods-clients-dev-4.3.5:latest
          build-script: docker/build-release.sh
          # docker-network omitted — defaults to "host", no iRODS server needed

      - name: "Log in to GHCR"
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: "Extract Docker metadata"
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=raw,value=latest

      - name: "Build and push"
        uses: docker/build-push-action@v5
        with:
          context: .
          file: docker/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

### `docker/build-release.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --default-toolchain stable --no-modify-path
export PATH="$HOME/.cargo/bin:$PATH"

cargo build --release
```

### `docker/Dockerfile`

Publish image based on `ubuntu:22.04` to match the iRODS dev image used at build time. The iRODS client runtime `.deb` packages provide the libraries baton-rs links against dynamically.

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install iRODS client runtime packages from the official iRODS APT repository.
# The exact version must match the iRODS version the build image compiled against
# (currently 4.3.5 — see the build image referenced in publish.yml).
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc \
      | apt-key add - \
  && echo "deb [arch=amd64] https://packages.irods.org/apt/ $(lsb_release -sc) main" \
      > /etc/apt/sources.list.d/renci-irods.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
       irods-runtime=4.3.5-0~$(lsb_release -sc) \
       irods-icommands=4.3.5-0~$(lsb_release -sc) \
  && rm -rf /var/lib/apt/lists/*

COPY target/release/baton-list       /usr/local/bin/
COPY target/release/baton-get        /usr/local/bin/
COPY target/release/baton-put        /usr/local/bin/
COPY target/release/baton-chmod      /usr/local/bin/
COPY target/release/baton-metamod    /usr/local/bin/
COPY target/release/baton-metaquery  /usr/local/bin/
COPY target/release/baton-do         /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/baton-do"]
```

Verify the iRODS package version exactly matches the one in the build image. Session 0 can confirm this by running `apt-cache policy irods-runtime` inside the build image before finalising.

### `.github/dependabot.yml`

Covers all three dependency ecosystems in the project: Cargo, GitHub Actions, and the publish container's Docker base. Updates are grouped to keep PR volume manageable, and limits prevent a neglected backlog from piling up. Every Dependabot PR automatically runs the full iRODS matrix, so dependency bumps are tested against every supported iRODS version before merge.

```yaml
version: 2
updates:
  - package-ecosystem: "cargo"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    groups:
      # Group patch-level updates to cut PR volume
      cargo-patches:
        update-types: ["patch"]
      # Group related crate families
      serde:
        patterns:
          - "serde"
          - "serde_*"
      clap:
        patterns:
          - "clap"
          - "clap_*"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 3
    groups:
      docker-actions:
        patterns:
          - "docker/*"

  - package-ecosystem: "docker"
    directory: "/docker"
    schedule:
      interval: "monthly"
    open-pull-requests-limit: 2
```

Two notes:

- **bindgen updates may need code changes.** bindgen occasionally changes its output format in ways that require manual fixes in the FFI wrappers. Expect occasional Dependabot PRs on bindgen to fail CI; don't auto-merge them.
- **Grouping is important.** Without it, a single week could easily produce 10+ PRs. The configuration above should yield roughly 2–4 PRs per week in steady state.

### `.devcontainer/devcontainer.json`

Uses the same iRODS dev image as CI, so the Codespace environment is identical to what runs in the matrix. Rust is added on top as a devcontainer feature.

```jsonc
{
  "name": "baton-rs",
  "image": "ghcr.io/wtsi-npg/ub-22.04-irods-clients-dev-4.3.5:latest",

  "features": {
    "ghcr.io/devcontainers/features/rust:1": { "version": "stable" },
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  },

  "postCreateCommand": "bash .devcontainer/setup.sh",

  "customizations": {
    "vscode": {
      "extensions": [
        "rust-lang.rust-analyzer",
        "vadimcn.vscode-lldb",
        "serayuzgur.crates",
        "tamasfe.even-better-toml",
        "ms-azuretools.vscode-docker"
      ],
      "settings": {
        "rust-analyzer.cargo.buildScripts.enable": true,
        "rust-analyzer.check.command": "clippy"
      }
    }
  },

  "forwardPorts": [1247],
  "portsAttributes": {
    "1247": { "label": "iRODS", "onAutoForward": "silent" }
  }
}
```

### `.devcontainer/setup.sh`

Runs after devcontainer features are installed, so `cargo` is already on `PATH` via the rust feature.

```bash
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
```

---

## Session 1: Crate scaffold and JSON data model

Create the single crate with the layout described above. Define all core Rust types in `src/types.rs` and `src/json.rs` with `serde` derives matching baton's JSON schema exactly:

- `IrodsPath`, `DataObject`, `Collection`
- `Avu` (attribute/value/units, with short-form aliases `a`/`v`/`u` via serde `alias`)
- `Acl` (`owner`, `level`, optional `zone`)
- `Replicate` (`checksum`, `location`, `resource`, `number`, `valid`)
- `Timestamp` (`created`/`modified`, optional `replicate`)
- `BatonError` (`code`, `message`)
- Query operator enum (`=`, `like`, `not like`, `in`, `>`, `n>`, `<`, `n<`, `>=`, `n>=`, `<=`, `n<=`)

No iRODS connection in this session. Write unit tests for JSON round-tripping of all types against real example JSON from the baton docs. Create stub `src/bin/*.rs` files that just print "not implemented" — this ensures Cargo builds all expected binaries and the publish Dockerfile's `COPY` lines succeed from the start.

This session runs entirely in CI without needing iRODS to succeed (unit tests only). The integration-test layer can be empty for now.

## Session 2: iRODS FFI layer

Add a `build.rs` that uses `bindgen` against the iRODS C headers (`rodsClient.h`, `dataObjInpOut.h`, etc.) to generate raw bindings. Wrap the raw bindings in a safe Rust API in `src/ffi.rs` and `src/connection.rs`:

- `RodsConnection` with RAII-based connection cleanup (drop impl calls `rcDisconnect`)
- Authentication using the iRODS environment file (matching icommands' `iinit` flow)
- Auto-reconnect logic driven by the `--connect-time` CLI flag
- Error type mapping from iRODS error codes to `BatonError`

Integration tests in `tests/` connect to the live iRODS server and verify basic connect/disconnect/auth flows. CI catches FFI regressions from this point forward. Testing `--connect-time` directly is awkward (it's time-based); plan a separate smaller test that exercises the reconnect path by closing a connection and making another call.

## Session 3: baton-list

Implement listing of collections and data objects in `src/operations/list.rs`, with a thin CLI wrapper in `src/bin/baton-list.rs`. Support all flags: `--avu`, `--acl`, `--checksum`, `--replicate`, `--size`, `--timestamp`, `--contents`. Stream newline-delimited JSON on stdin and stdout.

Validate output compatibility by running both the original baton-list and baton-rs against the same iRODS instance and comparing JSON output on representative inputs. Note: byte-for-byte equality will likely fail due to JSON key ordering; compare parsed JSON structurally instead.

## Session 4: baton-metamod and baton-metaquery

Implement AVU add/remove (`metamod`) and metadata queries (`metaquery`). Query support must include all operators, timestamp range queries, ACL selectors, and the `--obj`/`--coll`/`--zone` scoping flags. Shared query-construction code lives in `src/operations/metaquery.rs` and is reused by `baton-do`.

## Session 5: baton-get and baton-put

Implement download (inline JSON mode and `--save` file mode) and upload. Both must perform streaming MD5 checksum verification against iRODS. Support `--checksum` (compute server-side only) and `--verify` (compute on both sides and compare) for `baton-put`. Handle replicates properly — where a data object has multiple replicates, the size of the latest-numbered replicate is reported.

## Session 6: baton-chmod

Implement ACL modification with `--recurse` support. Map Rust ACL types to iRODS permission levels (`null`, `read`, `write`, `own`).

## Session 7: baton-do multiplexer

Implement the envelope dispatcher in `src/bin/baton-do.rs`, parsing `{"operation": "...", "arguments": {...}, "target": {...}}` and delegating to functions in `src/operations/`. Support all operations including the extras only `baton-do` provides: `checksum`, `move`, `remove`, `mkdir`, `rmdir`. Add `--no-error` mode (in-band JSON error reporting only).

This is the most important binary because it is the entry point used by downstream consumers like [partisan](https://github.com/wtsi-npg/partisan).

## Session 8: Polish and compatibility

- Unbuffered output (`--unbuffered` flushes after each JSON object)
- `--unsafe` relative path mode (reject relative paths by default, matching baton's safety posture)
- Error representation: annotate input JSON with `{"error": {"code": ..., "message": ...}}` on failures, keeping errors associated with their inputs
- Verify `--connect-time` auto-reconnect across all binaries
- Run partisan's test suite against baton-rs by replacing `baton-do` on `PATH` with the Rust binary — this is the definitive functional equivalence check
- Add iRODS 5.x to the CI matrix as `experimental: true` once `ghcr.io/wtsi-npg/ub-*-irods-5.*` server and dev images are available

---

## Things to consider beyond the session plan

**Error handling strategy.** Decide early whether to use `anyhow` (easy but loses type information at boundaries), `thiserror` (more work but better API ergonomics for library users), or a hybrid (`thiserror` in `lib.rs`, `anyhow` in binaries). Recommendation: `thiserror` for the library error types, `anyhow` in `src/bin/*.rs` for terminal error reporting.

**Logging.** baton uses verbose output to stderr controlled by `--verbose` and `--silent`. Use `tracing` or `log` + `env_logger` and wire these flags to the appropriate log levels. Decide in Session 1 so all subsequent sessions use the same approach.

**Async vs sync.** The iRODS C API is blocking. There is no benefit to making baton-rs async — CLI programs with stdin/stdout pipelines are naturally synchronous, and async would only add runtime dependencies. Stay sync.

**Feature flags.** Consider a Cargo feature flag `irods-5` that, when enabled, compiles against iRODS 5.x headers. This lets the same source tree support multiple iRODS major versions without build-time environment variables. Revisit in Session 2 when FFI takes shape.

**Release automation beyond containers.** The current plan only publishes a container on tag. Also consider: a GitHub Release with binary artefacts attached, Debian `.deb` packages if this matches how your infrastructure team deploys tools, or a Homebrew formula for desktop users. None are strictly needed, but they're easy to add once the publish workflow exists.

**Man pages and docs.** baton ships Sphinx-generated man pages and an HTML manual. Decide whether baton-rs reproduces these. `clap` can generate man pages from CLI definitions, which is almost free; full schema documentation is more work and can live in the README initially.

**Backwards compatibility flag.** Consider a `BATON_COMPAT` env var or `--compat` flag to toggle between strict-baton-parity and baton-rs-native behaviour for any place the rewrite might improve things (e.g. better error messages). Probably not needed initially — defer until it is.

**Performance.** baton's original motivation includes being faster than python-irodsclient for large puts. Benchmark baton-rs vs baton on realistic workloads during Session 8. No action needed before that; just don't design choices into FFI that preclude later optimisation (e.g. avoid unnecessary copies on the upload/download paths).

## Prompting strategy for Claude Code

Each session should begin with a short context paste:

> We are reimplementing the baton iRODS client in Rust across multiple sessions. The JSON schema is defined by the baton docs at https://wtsi-npg.github.io/baton/. Here is a summary of what previous sessions completed: [paste SESSIONS.md]. This session's goal is [session N goal]. Here is the relevant schema section for this session: [paste].

Keep `SESSIONS.md` in the repo and update it at the end of every session with a one-paragraph summary of what was completed. Paste it at the start of every new session to restore context.

## Decisions already made

- **Target baton version: 6.x.** See Overview. Exact point release pinned in `SESSIONS.md` during Session 1.
- **License: GPL-2.0.** Matches upstream baton.
- **Rust MSRV: current stable, unpinned.** `rust-version` is not set in `Cargo.toml` — the project tracks whatever `stable` offers. Revisit only if `baton-core` is ever published to crates.io as a library.
- **Linking strategy: dynamic.** Link against iRODS client libraries provided by the iRODS `.deb` packages.
- **Publish image base distro: Ubuntu 22.04.** Matches the build image (`ub-22.04-irods-clients-dev-4.3.5`), so iRODS runtime libraries install cleanly from the same `.deb` packages used at build time. Switching to Debian is possible later but requires rebuilding the iRODS client libraries for Debian — not off the shelf.
- **iRODS 5.x in CI: deferred.** Not in the initial matrix. Add as `experimental: true` in Session 8 once `ghcr.io/wtsi-npg/ub-*-irods-5.*` images are stable.

No remaining open decisions block Session 0.

## Compatibility oracle

Throughout the project, the primary compatibility test is: does [partisan](https://github.com/wtsi-npg/partisan)'s Python test suite pass when `baton-do` on `PATH` is baton-rs? This is the definitive functional equivalence check, since partisan exercises every feature downstream consumers actually use.
