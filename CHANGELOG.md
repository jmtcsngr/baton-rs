# Changelog

All notable changes to baton-rs are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Tag format is bare semver (no `v` prefix) — the git tag matches
`Cargo.toml`'s `version` field byte-for-byte.

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
