# baton-rs

A Rust reimplementation of [baton](https://github.com/wtsi-npg/baton), the iRODS
client focused on metadata operations via a single JSON interface. Targets
wire-compat with upstream baton **6.0.0**.

**Status:** Under active development. The seven binaries are implemented and
exercised against iRODS 4.2.7 / 4.3.4 / 4.3.5 in CI, plus integration runs
against the downstream Python ([partisan](https://github.com/wtsi-npg/partisan))
and Go ([extendo](https://github.com/wtsi-npg/extendo)) consumers. See
[`PLAN.md`](PLAN.md) for the multi-session implementation plan and
[`SESSIONS.md`](SESSIONS.md) for session progress and cross-cutting
conventions.

## Binaries

baton-rs ships seven binaries, mirroring upstream baton 1:1:

| Binary           | Purpose                                                                                          |
|------------------|--------------------------------------------------------------------------------------------------|
| `baton-list`     | List a data object or collection, optionally enriched with size / checksum / AVUs / ACLs / etc.  |
| `baton-get`      | Download a data object — inline (raw UTF-8 in the `data` field) or `--save` (to a local file).   |
| `baton-put`      | Upload a local file to a data object, optionally with server-side checksum / verify.             |
| `baton-chmod`    | Add or remove ACL grants on a data object or collection (optionally recursive).                  |
| `baton-metamod`  | Add or remove AVUs on a data object or collection.                                               |
| `baton-metaquery`| Search the catalog by AVU / timestamp / ACL criteria; returns matching paths.                    |
| `baton-do`       | NDJSON-in / NDJSON-out multiplexer that dispatches to any of the eleven operations.              |

The per-binary CLIs follow upstream baton's flag conventions where they
exist; deviations are called out in each binary's `--help`. All binaries
expose `--version` and respect `--connect-time` for the iRODS-reconnect
watchdog.

## `baton-do` envelope

`baton-do` is the entry point downstream consumers (partisan, extendo) use.
Each input line is a JSON envelope:

```json
{"operation": "list", "target": {"collection": "/zone/home/user/data.fastq"}, "arguments": {"size": true}}
```

Each output line is the same envelope plus exactly one of `result` (on
success) or `error` (in-band annotation). Parse failures emit a
stand-alone `{"error": {...}}` line and the stream continues — see
[issue #37](https://github.com/jmtcsngr/baton-rs/issues/37) for the
documented divergence from upstream's silent-drop behaviour.

**Envelope round-trip fidelity** — top-level fields baton-rs doesn't model
(e.g. extendo's `"ID"` request-response correlation field) are captured on
deserialise and echoed back on the response envelope verbatim. This
matches upstream baton's `print_json(item)` pattern
(`baton/src/operations.c:130-150` — modify input JSON in place, write
the original back). Downstream consumers can add metadata to envelopes
without coordinating schema changes with baton-rs. See the
"Cross-cutting conventions" block in [`SESSIONS.md`](SESSIONS.md).

## Compatibility with upstream baton

baton-rs is wire-compatible with upstream baton 6.0.0 for the success
path and the in-band error path. Known divergences:

- **Parse-error wire shape** — baton-rs emits a stand-alone synthetic
  `{"error": ...}` line; upstream silently drops the unparseable line.
  Documented in [#37](https://github.com/jmtcsngr/baton-rs/issues/37);
  the deviation preserves the 1-input / 1-output NDJSON invariant
  downstream consumers depend on.
- **`Arguments.raw`** — accepted on the wire for upstream-CLI parity but
  a no-op; baton-rs always returns the raw-UTF-8 inline `data` field on
  get.
- **`--single-server`** — accepted but a no-op; baton-rs already reuses
  the same connection across records (subject to `--connect-time`
  recycling).
- **`--zone`** — accepted but a no-op until cross-zone metaquery
  scoping lands ([#77](https://github.com/jmtcsngr/baton-rs/issues/77));
  per-record metaquery `zone` is also dropped at the operations layer
  for now. Local-zone queries are unaffected.
- **Hash scheme** — only MD5 is supported today (matches iRODS's
  default; CI pins `irods_default_hash_scheme = MD5`). SHA2 wiring
  tracked in [#31](https://github.com/jmtcsngr/baton-rs/issues/31) with
  the matrix in [#27](https://github.com/jmtcsngr/baton-rs/issues/27).

## Downstream consumer CI

Two informational workflows run partisan and extendo's own test suites
against freshly-built baton-rs binaries on every PR + every push to
`main`:

- [`.github/workflows/partisan-tests.yml`](.github/workflows/partisan-tests.yml)
  — partisan (Python) test suite via pyenv-managed Python 3.12. Pinned
  via `.github/scripts/partisan-pin`. iRODS 4.3.4 / 4.3.5 only; 4.2.7
  excluded because Python 3.12 needs OpenSSL ≥ 1.1.1 and the 4.2.7
  build image (Ubuntu 16.04) ships OpenSSL 1.0.2.

- [`.github/workflows/extendo-tests.yml`](.github/workflows/extendo-tests.yml)
  — extendo (Go) test suite via Ginkgo. Pinned via
  `.github/scripts/extendo-pin`. All three iRODS versions exercised
  (Go's static tarballs work on every base image).

Both are intentionally **informational long-term** (`continue-on-error: true`):
schema drift, pin bumps, or upstream iRODS quirks shouldn't fail PRs the
baton-rs author can't fix in their own work. Treat a red downstream run as
a signal to investigate, not a merge blocker.

## Version reporting and `STRICT_BATON_COMPAT`

Each binary exposes a `--version` flag that prints a single `<X>.<Y>.<Z>` line
on stdout and exits 0. The reported value depends on the `STRICT_BATON_COMPAT`
environment variable:

| Env var state                          | `--version` reports                                        |
|----------------------------------------|------------------------------------------------------------|
| Unset (or empty string)                | The baton-rs crate version (`Cargo.toml`'s `version`).     |
| Set to any non-empty value             | `BATON_COMPAT_VERSION` (e.g. `6.0.0`) — the upstream baton release baton-rs targets wire-compat with. |

Honest reporting is the default so logs and debugging surfaces aren't misled
about what's actually running. The compat mode exists for downstream consumers
that probe `baton-do --version` and parse it as a baton X.Y.Z value (partisan
compares against expected baton versions). Set `STRICT_BATON_COMPAT=1`
(or any non-empty value — matches `RUST_LOG` / `RUST_BACKTRACE` convention)
when running such consumers against baton-rs.

```sh
$ baton-do --version
1.0.0-alpha.2

$ STRICT_BATON_COMPAT=1 baton-do --version
6.0.0
```

The `STRICT_BATON_COMPAT` toggle is also reserved for future wire-format
compat shims beyond version reporting. See
[#58](https://github.com/jmtcsngr/baton-rs/issues/58) for the design and
the release-checklist that gates `BATON_COMPAT_VERSION` bumps.

## Build and dev

`cargo build --release` produces the seven binaries under `target/release/`.
The crate links dynamically against iRODS's `irods_client` and
`irods_common` libraries (from the `.deb` packages); see
[`docker/build.sh`](docker/build.sh) for the canonical setup script CI uses.

A `.devcontainer` configuration is included for VS Code; see
[`.devcontainer/setup.sh`](.devcontainer/setup.sh).

`Cargo.lock` is gitignored — baton-rs is built from source against
multiple iRODS-client base images and a pinned lockfile would over-
constrain the resolver across them. Reconsider if baton-rs ever becomes
a library consumed by other crates.

## License

GPL-2.0 — see [`LICENSE`](LICENSE). Matches upstream baton.
