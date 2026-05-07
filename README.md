# baton-rs

A Rust reimplementation of [baton](https://github.com/wtsi-npg/baton), the iRODS
client focused on metadata operations via a single JSON interface.

**Status:** Under active development. See [`PLAN.md`](PLAN.md) for the multi-session
implementation plan and [`SESSIONS.md`](SESSIONS.md) for session progress.

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
that probe `baton-do --version` and parse it as a baton X.Y.Z value
(e.g. [partisan](https://github.com/wtsi-npg/partisan) compares against
expected baton versions). Set `STRICT_BATON_COMPAT=1` (or any non-empty value
— matches `RUST_LOG` / `RUST_BACKTRACE` convention) when running such consumers
against baton-rs.

```sh
$ baton-do --version
0.1.0

$ STRICT_BATON_COMPAT=1 baton-do --version
6.0.0
```

The `STRICT_BATON_COMPAT` toggle is also reserved for future wire-format
compat shims beyond version reporting (parse-error wire shape, partisan-flavoured
checksum-arg aliases, etc.). See
[#58](https://github.com/jmtcsngr/baton-rs/issues/58) for the design and the
release-checklist that gates `BATON_COMPAT_VERSION` bumps.

## License

GPL-2.0 — see [`LICENSE`](LICENSE). Matches upstream baton.
