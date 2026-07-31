# Changelog

All notable changes to baton-rs are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Tag format is bare semver (no `v` prefix) — the git tag matches
`Cargo.toml`'s `version` field byte-for-byte.

## [1.1.0] — 2026-07-31

### Added

- Connection recovery: on a connection-level error mid-stream, baton-rs
  rebuilds the connection before the next record so the rest of the
  stream survives, instead of reusing the dropped connection ([#108]).
  The record in flight when the connection dropped is annotated in-band
  and not retried.

[1.1.0]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.1.0
[#108]: https://github.com/jmtcsngr/baton-rs/issues/108

## [1.0.2] — 2026-07-30

### Added

- `publish.yml` manifest pre-flight check ([#93]).

[1.0.2]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.0.2
[#93]: https://github.com/jmtcsngr/baton-rs/issues/93

## [1.0.2-alpha.1] — 2026-07-30

Pre-release to validate the new `publish.yml` manifest pre-flight step
([#93]) against a real tag push before it ships in the next stable patch.

### Added

- `publish.yml` now runs `cargo verify-project` and `cargo metadata`
  before the build step, failing fast on a broken manifest ([#93]).

[1.0.2-alpha.1]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.0.2-alpha.1
[#93]: https://github.com/jmtcsngr/baton-rs/issues/93

## [1.0.1] — 2026-07-24

### Fixed

- `extendo-tests.yml` no longer runs on tag pushes ([#110]).

[1.0.1]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.0.1
[#110]: https://github.com/jmtcsngr/baton-rs/issues/110

## [1.0.0] — 2026-07-23

First stable release. Full wire-compat with upstream baton 6.1.0
across all seven binaries, continuously validated against partisan
and extendo.

### Notes

- Known limitations, documented rather than fixed: cross-zone
  metaquery scoping ([#77]) and hash schemes beyond MD5 ([#31],
  matrix in [#27]).

[1.0.0]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.0.0
[#77]: https://github.com/jmtcsngr/baton-rs/issues/77
[#31]: https://github.com/jmtcsngr/baton-rs/issues/31
[#27]: https://github.com/jmtcsngr/baton-rs/issues/27

## [1.0.0-alpha.2] — 2026-05-14

### Changed

- **Container entrypoint pattern aligned with upstream baton.**
  Dropped `ENTRYPOINT ["/usr/local/bin/baton-do"]` in favour of
  `CMD ["/bin/bash"]` and no entrypoint, matching upstream's dev image
  convention. Callers that relied on `docker run image --version` or
  `singularity run docker://image --version` need to switch to an
  explicit invocation — e.g. `docker run image baton-do --version` or
  `singularity exec docker://image baton-do --version`.
- Container runs as non-root `appuser` (UID/GID 1000). Under
  singularity the host user takes over; under plain `docker run` the
  container runs unprivileged.
- Container default locale set to `en_GB.UTF-8`; `TZ` set to
  `Etc/UTC`.
- iRODS runtime version parameterised via `ARG IRODS_VERSION` (default
  `4.3.5`). Override at build time only if rebuilding against a
  matched custom binary set.
- APT repo signing key migrated from the deprecated `apt-key add`
  pattern to `gpg --dearmor` + `signed-by=` keyring under
  `/etc/apt/keyrings/`. No user-visible change.

[1.0.0-alpha.2]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.0.0-alpha.2

## [1.0.0-alpha.1] — 2026-05-13

First public preview. Wire-compatible with upstream
[baton](https://github.com/wtsi-npg/baton) 6.0.0 for the success path
and the in-band error path; documented divergences are listed in the
README.

### Added

- Seven binaries mirroring upstream baton 1:1: `baton-list`,
  `baton-get`, `baton-put`, `baton-chmod`, `baton-metamod`,
  `baton-metaquery`, `baton-do`.
- `baton-do` NDJSON-in / NDJSON-out multiplexer dispatching to the
  eleven operations. Envelope round-trip fidelity: unknown top-level
  fields (e.g. extendo's `ID` request-response correlation field) are
  captured on deserialise and echoed back on the response verbatim.
- `STRICT_BATON_COMPAT` env var: honest version reporting by default
  (the baton-rs crate version), upstream `BATON_COMPAT_VERSION`
  (`6.0.0`) when set. Lets downstream consumers parsing `--version`
  as a baton X.Y.Z continue to work without baton-rs lying in logs
  about what is actually running.
- CI matrix exercises iRODS 4.2.7 / 4.3.4 / 4.3.5 for both unit and
  integration tests.
- Informational compat workflows running partisan (Python) and
  extendo (Go) test suites against freshly-built baton-rs binaries on
  every PR and every push to `main`.
- Container distribution via `ghcr.io/jmtcsngr/baton-rs` — Ubuntu
  22.04 base, iRODS 4.3.5 runtime, `baton-do` as entrypoint.
- `cargo audit` workflow (informational): runs against the resolved
  dep tree on every PR and push to `main`.

### Notes

- This is an **alpha**. Wire-compat is exercised but not yet declared
  stable; downstream consumers should pin to a specific tag rather
  than tracking `:latest` (which does not move for prerelease tags
  anyway).
- `Cargo.lock` is intentionally gitignored — baton-rs is built from
  source against multiple iRODS-client base images and a pinned
  lockfile would over-constrain the resolver across them.
- Only the MD5 hash scheme is supported on the iRODS-client side
  today. Pluggable hash-scheme support is tracked in #31, the matrix
  in #27.

[1.0.0-alpha.1]: https://github.com/jmtcsngr/baton-rs/releases/tag/1.0.0-alpha.1
