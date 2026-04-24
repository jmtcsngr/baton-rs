# SESSIONS.md

Running log of Claude Code sessions on baton-rs. Update this file at the end of every session with a short summary of what was completed, what was deferred, and any decisions made.

Paste the relevant sections at the start of each new session to restore context for Claude Code.

---

## Project constants

These values do not change during normal development. If they do change, note the reason here.

- **Target baton version for parity:** `6.0.0`
- **Reference schema:** <https://wtsi-npg.github.io/baton/>
- **Primary compatibility oracle:** partisan's Python test suite, run with baton-rs's `baton-do` on `PATH`
- **Supported iRODS versions (CI matrix):** 4.2.7, 4.3.4, 4.3.5 _(add 5.0.1 when ready)_
- **License:** `GPL-2.0`
- **Rust MSRV:** current stable, unpinned (no `rust-version` in `Cargo.toml`)
- **Linking strategy:** dynamic (iRODS client libraries from `.deb` packages)
- **Publish image base distro:** `ubuntu:22.04`

---

## Cross-cutting conventions

Conventions adopted during Session 1 that apply to all subsequent sessions. Fill these in at the end of Session 1.

- **Error handling:** `thiserror` in library code (`src/`), `anyhow` in `src/bin/*.rs`
- **Logging:** `tracing` + `tracing-subscriber`, `--verbose` → DEBUG, `--silent` → ERROR (wiring added in Session 3)
- **JSON key ordering:** serde default; structural comparison in compatibility tests (not byte-for-byte)
- **Short-form JSON aliases:** types accept both long (`attribute`/`value`/`units`) and short (`a`/`v`/`u`) forms via serde `alias`; emit long form on serialise

---

## Session log

### Session 0 — Infrastructure

**Status:** completed on 2026-04-24

**Goal:** Stand up CI, publish workflow, Dependabot, devcontainer, and publish Dockerfile. No Rust code written yet; stub Cargo manifest only.

**Completed:**
- `Cargo.toml` stub (name, edition, license; no `[[bin]]` yet)
- `.github/workflows/unit-tests.yml` — iRODS 4.2.7 / 4.3.4 / 4.3.5 matrix, all three green
- `.github/workflows/publish.yml` — publishes to `ghcr.io/jmtcsngr/baton-rs` on tag push
- `.github/dependabot.yml` — Cargo (weekly), GitHub Actions (weekly), Docker (monthly)
- `.devcontainer/devcontainer.json` + `.devcontainer/setup.sh`
- `docker/build.sh`, `docker/build-release.sh`, `docker/Dockerfile`
- `LICENSE` (GPL-2.0, matches upstream baton's COPYING)
- `.gitignore` (Rust `target/` + editor backups)
- `README.md` (minimal landing page)
- CI authentication fixed: user `irods`, `iinit` via `script` pseudo-TTY
- Stubs to unblock CI: empty `src/lib.rs`, placeholder `tests/placeholder.rs` (both replaced in Session 1)

**Deferred / known gaps:**
- `src/lib.rs` is empty; `tests/placeholder.rs` is a single trivial test. Both to be replaced in Session 1.
- Publish workflow has never fired (tag-only trigger). First exercised when Session 8 cuts a release.
- iRODS 5.x not in CI matrix yet (deferred to Session 8 as `experimental: true`).

**Decisions made:**
- Publish image: `ubuntu:22.04` (matches build image, iRODS `.deb` packages install cleanly)
- License: `GPL-2.0` (matches upstream baton)
- Linking: dynamic against iRODS client libraries
- iRODS test credentials: user `irods`, password `irods`, zone `testZone` (per upstream baton CI)

**Open questions for next session:**
- Pin exact baton 6.x point release (e.g. `6.0.0`) in Project constants above
- Decide error handling (`thiserror` in lib, `anyhow` in bins) and logging crate (`tracing` vs `log`)

---

### Session 1 — Crate scaffold and JSON data model

**Status:** in progress

**Goal:** Create the single crate with `src/bin/` stubs and define all JSON types with serde derives matching baton's schema.

**Completed:**
- `<fill in — e.g. types for DataObject, Avu, Acl, Replicate, Timestamp, BatonError>`
- `<JSON round-trip unit tests against baton doc examples>`
- `<stub src/bin/*.rs files so Cargo builds all 7 binaries>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in — especially error handling and logging conventions, copy into Cross-cutting conventions above>`

**Open questions for next session:**
- `<fill in>`

---

### Session 2 — iRODS FFI layer

**Status:** `<not started>`

**Goal:** bindgen against iRODS C headers, safe RodsConnection wrapper, auto-reconnect logic.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in — especially final linking strategy, copy into Project constants above>`

**Open questions for next session:**
- `<fill in>`

---

### Session 3 — baton-list

**Status:** `<not started>`

**Goal:** Full `baton-list` implementation with all flags.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in>`

**Open questions for next session:**
- `<fill in>`

---

### Session 4 — baton-metamod and baton-metaquery

**Status:** `<not started>`

**Goal:** AVU add/remove and metadata queries with all operators, timestamp ranges, ACL selectors.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in>`

**Open questions for next session:**
- `<fill in>`

---

### Session 5 — baton-get and baton-put

**Status:** `<not started>`

**Goal:** Download (inline and `--save`) and upload with streaming MD5 verification. Replicate handling.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in>`

**Open questions for next session:**
- `<fill in>`

---

### Session 6 — baton-chmod

**Status:** `<not started>`

**Goal:** ACL modification with `--recurse` support.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in>`

**Open questions for next session:**
- `<fill in>`

---

### Session 7 — baton-do multiplexer

**Status:** `<not started>`

**Goal:** JSON envelope dispatcher covering list, get, put, chmod, metamod, metaquery, checksum, move, remove, mkdir, rmdir. `--no-error` mode.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in>`

**Open questions for next session:**
- `<fill in>`

---

### Session 8 — Polish and compatibility

**Status:** `<not started>`

**Goal:** `--unbuffered`, `--unsafe`, in-band error JSON, `--connect-time` verification, partisan test-suite pass, add iRODS 5.x to CI.

**Completed:**
- `<fill in>`

**Deferred / known gaps:**
- `<fill in>`

**Decisions made:**
- `<fill in>`

**Open questions for next session:**
- `<fill in>`

---

## Session start template for Claude Code

Paste the following at the start of each session, with the placeholders filled in:

> We are reimplementing the baton iRODS client in Rust across multiple Claude Code sessions. The JSON schema is defined at https://wtsi-npg.github.io/baton/ and we are targeting parity with baton `<exact version from Project constants>`.
>
> **Project constants:** `<paste the Project constants block>`
>
> **Cross-cutting conventions:** `<paste the Cross-cutting conventions block>`
>
> **Previous session summaries:** `<paste the log entries for all completed sessions>`
>
> **This session's goal:** `<paste Session N's Goal line>`
>
> **Relevant schema section for this session:** `<paste the specific section of the baton docs this session needs>`

---

## Changelog for this file

Use this space to record non-trivial changes to the plan itself — e.g. changing the target version, dropping a session, reworking CI.

- `2026-04-23` — SESSIONS.md template created; Project constants filled in (Session 0).
- `2026-04-24` — Session 0 completed: CI green across iRODS 4.2.7/4.3.4/4.3.5 matrix.
