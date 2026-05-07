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
- **iRODS FFI strategy:** all iRODS API calls go through `shim/ffi_shim.{c,h}` (compiled by `cc` into a static library and linked alongside `irods_client` / `irods_common`). The Rust crate sees only the hand-written mirror in `src/ffi.rs` — no bindgen, no libclang. Adopted in Session 4.5 (issue #9). Adding a new iRODS API means declaring it in both `shim/ffi_shim.h` and `src/ffi.rs`, and writing the implementation in `shim/ffi_shim.c`.

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

**Status:** completed on 2026-04-24

**Goal:** Create the single crate with `src/bin/` stubs and define all JSON types with serde derives matching baton's schema.

**Completed:**
- Pinned target baton version `6.0.0` in Project constants
- Cross-cutting conventions recorded (error handling, logging, JSON ordering, short-form aliases)
- `Cargo.toml` dependencies: `serde` (derive), `serde_json`, `thiserror`
- `src/types.rs` — `IrodsPath`, `DataObject`, `Collection`, `Avu`, `Acl`, `AclLevel`, `Replicate`, `Timestamp`, `Operator`
- `src/error.rs` — `BatonError` (`thiserror`-derived, matches baton's in-band error JSON shape)
- `src/lib.rs` — re-exports the data model and the error type
- Unit tests: JSON round-trip for every type, including AVU short-form / long-form and all 12 query operators
- `src/bin/*.rs` — stub binaries for all 7 baton commands (`baton-list`, `baton-get`, `baton-put`, `baton-chmod`, `baton-metamod`, `baton-metaquery`, `baton-do`)

**Deferred / known gaps:**
- `contents` field on `Collection` not yet modelled — it's a mixed `DataObject` / `Collection` array and needs an untagged enum. Added in Session 3 when `baton-list --contents` first needs it.
- `clap`, `anyhow`, `tracing`, `tracing-subscriber` dependencies not yet added — pulled into `Cargo.toml` in Session 3 when the first real binary wires them up.
- `tests/placeholder.rs` still present; removed when real integration tests arrive (Session 3+).

**Decisions made:**
- Pin baton 6.0.0 as the parity target (only 6.x release as of 2025-09-02).
- Error handling: `thiserror` in library code; `anyhow` in `src/bin/*.rs` (applied from Session 3).
- Logging: `tracing` + `tracing-subscriber`; wiring deferred to Session 3.
- JSON conventions: serde default key order; structural comparison in compatibility tests.
- Short-form aliases: serde `alias` attribute; emit long form (`attribute`/`value`/`units`) on serialise.

**Open questions for next session:**
- Confirm exact iRODS headers to bindgen against (`rodsClient.h` as the top-level entry point). Handled in Session 2.
- Feature-flag strategy for iRODS 4.x vs 5.x headers — revisit once FFI takes shape.

---

### Session 2 — iRODS FFI layer

**Status:** completed on 2026-04-24

**Goal:** bindgen against iRODS C headers, safe RodsConnection wrapper, auto-reconnect logic.

**Completed:**
- `build.rs` — bindgen generates raw FFI bindings from `wrapper.h` (which includes `rodsClient.h`) into `$OUT_DIR/bindings.rs` at build time; not committed to the repo.
- Narrow bindgen allowlist: `rcConnect`, `rcDisconnect`, `clientLogin`, `clientLoginWithPassword`, `getRodsEnv`, `obfGetPw`, `rErrMsg`, `rodsErrorName`; types `rcComm_t`, `rodsEnv`, `rErrMsg_t`; constant families `CAT_*`, `SYS_*`, `AUTH_*`, `USER_*`.
- `docker/build.sh` and `.devcontainer/setup.sh` install `libclang-dev` + `clang` (bindgen needs both libclang and the driver-provided resource directory).
- Link directives emit `-l irods_client -l irods_common` (both required; splitting uncovered in debugging).
- `src/ffi.rs` — `pub(crate)` module that includes the generated bindings. Not part of the public crate API.
- `src/connection.rs::RodsConnection` — RAII wrapper over `rcComm_t *`:
  - `connect_from_env()` opens the TCP connection via `getRodsEnv` + `rcConnect`.
  - `login_from_auth_file()` authenticates by chaining `obfGetPw` (reads `.irodsA`) + `clientLoginWithPassword` (legacy native handshake). Deliberately bypasses `clientLogin` — see issue #10.
  - `reconnect()` does disconnect + fresh connect + re-login in place.
  - `Drop` calls `rcDisconnect` (null-safe; sets pointer to null after).
  - `!Send` + `!Sync` by default from the raw-pointer field.
- `src/error.rs::BatonError` gains `from_irods(code)` and `from_irods_with_context(code, ctx)` that resolve the symbolic iRODS name via `rodsErrorName`. Connection-layer error paths use these.
- Integration tests in `tests/`: `connection.rs`, `auth.rs`, `error.rs`, `reconnect.rs`. `tests/placeholder.rs` removed.
- CI matrix: 4.3.4 and 4.3.5 strict and green. 4.2.7 flipped to `experimental: true` (libclang 3.8 on Ubuntu 16.04 too old for bindgen 0.71 — see issue #9).

**Deferred / known gaps:**
- `clientLogin` is still in the bindgen allowlist but unused, bypassed by the `obfGetPw` + `clientLoginWithPassword` path. Left in for a near-zero-cost re-enable if a future iRODS server image registers `AUTHENTICATE_CLIENT_AN` (API 110000). Rationale captured in issue #10.
- Auto-reconnect driven by `--connect-time` — Session 3+ wires the time trigger; the `RodsConnection::reconnect` primitive is ready.
- `clap`, `anyhow`, `tracing`, `tracing-subscriber` still deferred to Session 3.
- Non-native auth schemes (PAM, GSI, Kerberos) — add sibling methods only when first needed.
- 4.2.7 CI remains experimental until Session 4.5, when the C shim lands (issue #9).

**Decisions made:**
- Linking: dynamic against `libirods_client` + `libirods_common` from the iRODS `.deb` packages.
- Bindings generated at build time, not committed — keeps bindings matched to whichever iRODS version is installed in the current CI matrix entry.
- Authentication: legacy native path via `obfGetPw` + `clientLoginWithPassword` rather than `clientLogin`, because 4.3.x `clientLogin` unconditionally probes API 110000 which the test-server image doesn't register. Full context in issue #10.
- Error enrichment: use iRODS's own `rodsErrorName` at `BatonError` construction time rather than maintaining a Rust match table. Auto-picks up new codes on bindgen rebuild.
- Test coverage: only `-305111` / `USER_SOCK_CONNECT_ERR` is asserted by exact name in unit tests — the one code we've directly observed. Other known codes come along for the ride via the general `from_irods` path.
- `RodsConnection` is `!Send`/`!Sync` by default (from the raw pointer) — matches iRODS's thread-per-connection model.

**Open questions for next session:**
- Which `clap` pattern for shared flags across binaries — derive macros with a `common_args` struct re-used via `#[command(flatten)]`, or arg groups? Revisit when the first binary goes in.
- `tracing` wiring: how verbose should the default level be (INFO vs WARN)? `--verbose` and `--silent` are still the plan.
- Add `Collection.contents` (mixed-item enum) early in Session 3 — it's the first place `baton-list --contents` pushes back on our current type layout.

---

### Session 3 — baton-list

**Status:** completed on 2026-04-27

**Goal:** Full `baton-list` implementation with all flags.

**Completed (split across three branches: 3a, 3b, 3c):**
- **Dependencies:** `clap`, `anyhow`, `tracing`, `tracing-subscriber` added to `Cargo.toml`. First time these land — they're the binary-side foundation for every subsequent operation.
- **`src/bin/baton-list.rs`** — full CLI: clap parses every Session 3 flag, tracing initialises to stderr (`RUST_LOG` > `--verbose`/`--silent` > default INFO), main loop opens one `RodsConnection` per invocation and dispatches each input line through `list_one_annotated`.
- **`src/operations/list.rs`** — first per-operation module. `list_one(conn, target, opts) -> Result<Target, BatonError>` for programmatic use; `list_one_annotated` wraps it for the binary's continue-on-error stream.
- **`Target` enum** (untagged serde) — `DataObject` vs `Collection` distinguished by presence of `data_object`. `Target::path()` joins for stat input; `Target::set_error` for in-band error annotation.
- **`Item` type alias = `Target`** — same JSON shape, used in `Collection.contents`. `Vec<Item>` and `Vec<Target>` interoperate freely.
- **`DataObject`/`Collection` extensions** — both gained an optional `error: Option<BatonError>` field; `Collection` gained `contents: Option<Vec<Item>>`.
- **Flags wired** — `--size`/`--checksum` from `rcObjStat`; `--avu`/`--acl`/`--replicate`/`--timestamp` via shared `rcGenQuery` helpers (`new_query_inp` / `add_select` / `add_where` / `run_query` / `sql_escape`); `--contents` via two queries merged into `Vec<Item>`. Per-replica timestamp fan-out (one `created` + one `modified` entry per replica) matches baton's emission shape.
- **In-band error annotation** — bad inputs get `{"error": {"code": ..., "message": ...}}` and the stream continues. JSON-parse errors at the binary level stay fail-fast.
- **FFI expansion (`build.rs`)** — adds `rcObjStat`/`freeRodsObjStat`/`rcGenQuery`/`addInxIval`/`addInxVal`/`clearGenQueryInp`/`freeGenQueryOut` plus `dataObjInp_t`/`rodsObjStat_t`/`objType_t`/`genQueryInp_t`/`genQueryOut_t`/`sqlResult_t`/`inxIvalPair_t`/`inxValPair_t` types and the full `COL_*` column-constant family. No new link libraries.
- **`RodsConnection::stat` and `RodsConnection::query`** — new methods. `query()` is `pub(crate)` because `genQueryInp_t` itself is crate-internal.
- **Compatibility test** — `tests/compat_baton.rs` runs both upstream `baton-list` and our binary on the same NDJSON, compares parsed JSON structurally on key fields. Skips cleanly when upstream not on PATH (current state in CI/devcontainer). Definitive equivalence still scoped to Session 8 (partisan).
- **15+ integration tests** in `tests/list.rs` covering each flag against live iRODS — `iput -K` / `imeta add` / `ichmod` / `imkdir` for staging, `IrodsCleanup` (now `irm -r -f`) / `AvuCleanup` drop guards for teardown.

**Deferred / known gaps:**
- **iRODS catalog-column naming inconsistency.** 4.3.5's bindings mix long-form (`COL_DATA_REPL_NUM`, `COL_DATA_ACCESS_NAME`, `COL_DATA_USER_NAME`) and short-form (`COL_D_DATA_CHECKSUM`, `COL_D_RESC_NAME`, `COL_D_REPL_STATUS`) prefixes for related columns. Comments at the call sites prevent future "tidy-up" attempts that would re-break the build.
- **Collection vs data-object ACL queries need different user-name columns.** `COL_USER_NAME`/`COL_USER_ZONE` join via the data-access path; collections need `COL_COLL_USER_NAME`/`COL_COLL_USER_ZONE`. Caught in CI; would have leaked silently if we'd shipped without that.
- **`CAT_NO_ROWS_FOUND` not in bindings** despite `CAT_.*` allowlist. Hardcoded to `-808000` at the single callsite; the constant lives behind a header `wrapper.h` doesn't reach.
- **`clearGenQueryInp` declared with `void *` parameter** — bindgen reflects that faithfully; cast through `*mut _` at the call site.
- **`--contents` is non-recursive** — matches baton. Recursive walking would need its own design and isn't in any planned session.
- **Compat test is best-effort** — currently a no-op in this dev image. Real cross-implementation testing arrives via partisan in Session 8.
- **iRODS access strings vary across server versions** — `parse_acl_level` accepts both compact (`read`) and verbose (`read object`) forms; unknown values surface as errors so a future iRODS that adds new levels is loud rather than silent.

**Decisions made:**
- **`Item = Target` (alias, not duplicate enum)** — same on-the-wire shape; aliasing avoids parallel maintenance.
- **`--contents` and `--replicate` ignore the wrong-target flag silently** — matches baton's behaviour. `--contents` on a data object and `--replicate` on a collection are no-ops, not errors.
- **In-band error annotation uses the existing `BatonError` type** — no schema-level changes beyond adding the optional `error` field.
- **NDJSON input parsing stays fail-fast** — we can only annotate inputs we managed to parse. Malformed JSON crashes the stream by design.
- **iRODS unit-less AVUs (`""` from server) fold to `units: None`** — matches baton's JSON shape. Same treatment for empty `zone` on ACL entries.
- **iRODS replica `valid` is derived from `COL_D_REPL_STATUS == "1"`** — anything else (mid-write, marked-stale, ...) folds to `false`.
- **Test assertions on iRODS state pin shape, not exact values.** Replica counts, exact timestamps, and specific ACL owners vary by server policy — every test that touches those checks for the invariants that actually matter, not a specific catalog snapshot.

**Open questions for next session (Session 4 — baton-metamod + baton-metaquery):**
- AVU add/remove flow: which `rcMod*` API does `imeta add -d` use, and does it require any of the same iRODS auth-quirk handling we hit with `clientLogin`?
- The `Operator` enum from Session 1 finally gets used. Does it need any per-version normalisation across iRODS 4.3.x?
- `baton-metaquery` returns search results — likely reuses much of `operations::list::list_one`'s output formatting; consider extracting a shared "decorate this Target with flag-requested fields" helper.

---

### Session 4 — baton-metamod and baton-metaquery

**Status:** completed on 2026-04-28

**Goal:** AVU add/remove and metadata queries with all operators, timestamp ranges, ACL selectors.

**Completed (split across three branches: 4a, 4b, 4c):**
- **4a — shared decoration helper.** Extracted `EnrichOptions { avu, acl, replicate, timestamp }` and `pub fn enrich_with_metadata(conn, &mut Target, &EnrichOptions)` from `operations::list::list_one`. Front-loaded so 4c could decorate query results without duplicating the per-flag dispatch. `list_one`'s body simplified to `stat → apply size/checksum → enrich_with_metadata → handle contents`. Behaviour-preserving — no integration tests changed.
- **4b — `baton-metamod`.** First binary that mutates iRODS state.
  - Schema: `MetamodInput { collection, data_object?, operation: MetamodOperation, avus, error }` plus the lowercase-serialised `MetamodOperation { Add, Rm }`. Sibling of `Target` rather than a wrapper, since flattening an untagged enum into a struct fights serde.
  - FFI: `rcModAVUMetadata` + `modAVUMetadataInp_t` (stringly-typed `arg0..arg9` layout: operation / target-type-flag / path / attribute / value / units).
  - `RodsConnection::mod_avu(operation, &target, &avu)` hides that layout behind a typed Rust API; CStrings drop after the call returns.
  - `operations::metamod::{metamod_one, metamod_one_annotated}` + the `baton-metamod` binary CLI. Per-input operation lives in the JSON envelope so a single stream can mix adds and removes. Empty `avus` is a successful no-op.
  - `tests/metamod.rs` covers add+rm on data objects, add on collections, the in-band error path, and the empty-vec no-op.
- **4c — `baton-metaquery`.** First binary that reads-only the catalog.
  - Schema: `AvuQuery { attribute, value, units?, operator (default Equals) }`, `TimestampQuery { created?, modified?, operator }`, `AccessQuery { owner, level, zone? }`, `MetaqueryInput { avus, timestamps, access, collection?, zone? }`. `Operator` enum gained `Default` (variant `Equals`) so query inputs can omit the operator and serde fills it in.
  - `operations/metaquery.rs` translates each criterion into iRODS `genQueryInp_t` WHERE conditions:
    - AVU: `META_DATA_*` / `META_COLL_*` columns with the operator-prefixed value literal.
    - Timestamps: `D_CREATE_TIME` / `D_MODIFY_TIME` (data) and `COLL_*` (collections), zero-padded epoch values passed through.
    - ACL: `(owner, level [, zone])` with the `read object` / `modify object` translation; data-object path joins via `COL_USER_*`, collection path via `COL_COLL_USER_*` (the same split that bit us in 3b).
    - Multi-AVU criteria run as per-AVU subqueries with `HashSet` intersection on the result paths — iRODS's genQuery doesn't naturally express metadata self-joins, so chaining `META_*_ATTR_NAME` constraints in one query asks for an impossible single AVU row.
  - `baton-metaquery` binary: clap-parsed `--obj` / `--coll` scoping, plus the same per-flag output decoration `baton-list` exposes (`--size`/`--checksum`/`--avu`/`--acl`/`--replicate`/`--timestamp`). Per-result decoration is best-effort — any per-result failure annotates `error` and the stream continues; query-construction failures still propagate.
  - `tests/metaquery.rs` covers AVU `=` and `like`, empty-input short-circuit, timestamp range (matching + future-epoch exclude), ACL selector (positive + negative with a PID-suffixed bogus user that's verified non-existent via `iquest`), and multi-AVU intersection (one obj has both AVUs, one has only one — assert both in/out behaviours).
- **Genquery helpers shared.** `new_query_inp` / `add_select` / `add_where` / `run_query` / `sql_escape` / `QUERY_PAGE_SIZE` in `operations::list` flipped to `pub(crate)` so `metaquery` can reuse them without a parallel implementation. Stayed in `list.rs` (no churn for the existing fetchers).

**Deferred / known gaps:**
- **`zone` scoping in `MetaqueryInput`** is parsed and accepted but not yet wired into the query — iRODS's default genQuery is local-zone only; cross-zone querying needs a different API entry point (`zone-hint` plumbing or `rcGenQuery`-with-zone-route).
- **`Operator::In` value handling**: `condition_for` passes through unescaped on the assumption that the caller has already formatted the parenthesised list (`('a','b','c')`). Documented but not validated.
- **Multi-AVU subqueries fan out as N round-trips**, not one. Acceptable for typical search-by-AVU sizes; if performance bites under load, look at iRODS specific queries (`rcSpecificQuery`) which can express the self-join in a single call.
- **`baton-metaquery` reads NDJSON**: each line is a separate query, results are concatenated with no per-query delimiter on stdout. Callers correlating multiple queries in one invocation have to know how many results each produces. Adding a per-query delimiter line would be a Session 8 polish item if it ever matters.
- **Auth schemes other than native** (PAM/GSI/Kerberos) — still on hold; the `clientLogin` workaround in #10 only ever matters if a future session adds those.

**Decisions made:**
- **Session split into 4a/4b/4c**, with 4a as a behaviour-preserving extract before either binary's body grows. Pattern worked for Session 3 too; keeping it.
- **Per-input operation in `MetamodInput`** rather than a CLI flag — matches baton, lets one stream mix adds and removes.
- **`MetamodInput` is a sibling of `Target`, not a wrapper.** Flattening Target via `#[serde(flatten)]` on an untagged enum fights serde's resolution rules; a focused struct with a `target()` accessor is cheaper.
- **Multi-AVU = result intersection**, not a single complex query. Documented in the metaquery doc comment with the "what's wrong with the chained-WHERE alternative" rationale, so future readers don't try to "simplify" it.
- **`Operator` enum gains `Default = Equals`.** The query types use it via `#[serde(default)]` so callers can omit the operator field and get the most common case for free.
- **Per-result decoration in `baton-metaquery` matches `baton-list`'s flag set.** Sharing `enrich_with_metadata` made this a one-liner; without 4a it would have been ~40 lines of duplication.
- **`iuserinfo` is unreliable for existence checks**; switched to `iquest` after the live test caught a false-positive. Captured in the test helper's doc comment so the next person doesn't relearn it.

**Open questions for next session (Session 5 — baton-get + baton-put):**
- Streaming MD5 verification — does iRODS expose an incremental hash API on the put path, or do we compute server-side after the put completes? Affects how `--verify` is wired.
- Replicate handling: which replica's size to report when a data object has multiple replicas with different sizes (mid-replication state)? PLAN.md says "size of the latest-numbered replicate"; need to confirm against baton's behaviour.
- Long-running put/get implies the `--connect-time` reconnect primitive from Session 2 finally has a real consumer. Wire the time check into the put/get loop, or leave it manual?

---

### Session 4.5 — C shim and libclang isolation (issue #9)

**Status:** completed on 2026-04-29

**Goal:** Replace the bindgen-against-iRODS-headers approach with a hand-written FFI mirror of a thin C shim, so libclang isn't in the build path at all and the iRODS 4.2.7 CI entry can return to strict mode.

**Completed (single branch `feat/session-4.5-c-shim`, ~10 commits):**
- **`shim/ffi_shim.{h,c}`** — version-agnostic C surface over the iRODS client. Opaque types (`shim_rods_conn_t`, `shim_query_t`, `shim_query_result_t`), POD distillations (`shim_env_t`, `shim_stat_t`), the symbolic catalog-column enum (`shim_col_t`, 24 values), and 17 functions covering connect / login / stat / genQuery / AVU mod / error name. The shim's `.c` is the only translation unit that `#include`s `<rodsClient.h>`.
- **Hand-written `src/ffi.rs`** — directly mirrors `shim/ffi_shim.h`. Replaces the bindgen pipeline entirely. With this in place, libclang is no longer invoked at any point in the build.
- **`build.rs`** — bindgen removed; only `cc` compiles the shim into `libbaton_rs_shim.a` and emits link directives for `irods_client` / `irods_common`. `wrapper.h` deleted.
- **`Cargo.toml`** — `bindgen` build-dependency dropped. Only `cc` remains.
- **Subsystem migrations (one commit per subsystem on the branch):**
  - **Connection lifecycle.** `shim_open` / `shim_close` / `shim_get_env` replace `rcConnect` / `rcDisconnect` / `getRodsEnv`. `RodsConnection.conn` becomes `*mut shim_rods_conn`.
  - **Auth.** `shim_get_password` / `shim_login_password` replace direct `obfGetPw` / `clientLoginWithPassword`. Password buffer zeroed on every return path now (was only on success).
  - **Stat.** `shim_stat` builds the `dataObjInp_t`, calls `rcObjStat`, copies fields, and frees the iRODS allocation internally — Rust never sees `dataObjInp_t` / `rodsObjStat_t`.
  - **General query.** Opaque builder + result. `GenQuery::new` / `add_select` / `add_where`, then `RodsConnection::query(&mut GenQuery)` returns `Vec<Vec<String>>`. Pagination and `CAT_NO_ROWS_FOUND` absorption live inside `shim_query_exec`.
  - **Metamod.** `shim_mod_avu` takes the AVU pieces as named arguments and builds `modAVUMetadataInp_t` internally — Rust no longer reaches into `arg0..arg9`.
  - **Error names.** `shim_error_name` wraps `rodsErrorName` (always passes NULL for the unused sub-error name).
- **`docker/build.sh` / `.devcontainer/setup.sh`** — `libclang-dev` and `clang` apt installs removed. Both scripts also pin `irods_default_hash_scheme = MD5` in the iRODS environment so the 4.2.7 image's replResc children agree on checksum algorithm and don't mark replicas stale (issue #25).
- **CI matrix** — 4.2.7's `experimental: true` flipped back to `false`. All three matrix entries (4.2.7, 4.3.4, 4.3.5) are strict and green.
- **Defensive hardening (audit pass):**
  - `shim_query_exec` now frees `*out` on the `CAT_NO_ROWS_FOUND` and `status < 0` paths if iRODS ever sets it — guards a future regression in the client lib.
  - `login_from_auth_file` zeros the password buffer on every return path, including `shim_get_password` failure (was previously only after a successful login attempt).
- **Test surface kept stable.** Every Session 2/3/4 integration test passes unchanged on all three iRODS versions. The `list_data_object_with_replicate` assertion was tightened from "r0 valid" to "all replicas valid" — strictly stronger than the original form, made possible by the issue #25 hash-scheme fix.

**Deferred / known gaps:**
- **iRODS 5.x in CI** still deferred to Session 8 — not in #9's scope.
- **The `clientLogin` workaround (issue #10)** is unaffected — auth still goes through the legacy native path via `shim_login_password`.
- **End-to-end test for `sql_escape`** with a single-quote in a path. The unit test in `src/operations/list.rs` covers the function in isolation; an end-to-end through genQuery would be incremental signal. Nice-to-have for Session 8 polish.

**Decisions made:**
- **Hand-written FFI rather than committed bindgen output.** Tried bindgen-with-narrow-allowlist first, but bindgen 0.71 / clang-sys 1.8.1 require libclang ≥ 5.0 at runtime (calls `clang_getTranslationUnitTargetInfo`) and the iRODS 4.2.7 CI image ships only 3.8. Even with the shim narrowing what bindgen would *parse*, bindgen still has to *run* — so removing it entirely was the only way to keep 4.2.7 strict. The shim's surface is small (17 functions) and stable, so manual upkeep is cheap.
- **`shim_col_t` enum, not raw integers.** Catalog column indices live as a shim-side enum; the shim translates each value to the iRODS `COL_*` numeric at runtime. Keeps the iRODS macros (and the `<rodsGenQuery.h>` header that defines them) on the C side.
- **Single branch, incremental subsystem migration.** Each subsystem moved behind the shim in its own commit, with the not-yet-migrated subsystems casting `*mut shim_rods_conn` back to `*mut rcComm_t` until their turn. Made each commit individually verifiable in the devcontainer.
- **Issue #25 fix scope.** The 4.2.7 image's replResc divergence is a client-side configuration issue; pinning `irods_default_hash_scheme = MD5` in the client environment is sufficient — no upstream image change needed. (Confirmed with Keith.)
- **`Cargo.lock` is still not tracked.** Surfaced during the audit; left alone pending an explicit decision next session. Convention says binary crates should commit it.

**Open questions for next session (Session 5 — baton-get + baton-put):**
- (carried from Session 4) Streaming MD5 verification — does iRODS expose an incremental hash API on the put path, or do we compute server-side after the put completes?
- (carried from Session 4) Replicate handling: which replica's size to report when a data object has multiple replicas with different sizes (mid-replication state)?
- (carried from Session 4) Long-running put/get gives `RodsConnection::reconnect` its first real consumer — wire `--connect-time` into the loop or leave it manual?
- New: when a Session 5 operation needs an iRODS API the shim doesn't yet expose, the now-explicit pattern is: declare in `shim/ffi_shim.h`, implement in `shim/ffi_shim.c`, mirror in `src/ffi.rs`. No build-system changes required.

---

### Session 5 — baton-get and baton-put

**Status:** completed on 2026-05-01

**Goal:** Download (inline and `--save`) and upload with streaming MD5 verification. Replicate handling.

**Plan:** split into 5a / 5b / 5c, mirroring Session 3 / 4.
- **5a — operations skeleton + `baton-get` inline mode.** Read a data object end-to-end, base64-encode, return on the JSON output's `data` field. No `--save`, no put.
- **5b — `baton-get --save` + `baton-put` (streaming MD5).** File-system I/O on both sides; client-side incremental MD5 on the put path; server-side checksum requested via `rcDataObjChksum`; `--checksum` (server only) and `--verify` (client+server compare) flags. Replicate-aware sizing: report the size of the highest-numbered *valid* replica.
- **5c — `--connect-time` reconnect decision + finalise.** Decide once we can see realistic transfer durations whether to wire the time check into the put/get loop or leave it manual; finalise SESSIONS.md and the changelog.

**Decisions fixed up front:**
- **Streaming MD5 on put.** Compute MD5 client-side as bytes are streamed through `rcDataObjWrite`, request a server-side checksum via `rcDataObjChksum`, compare for `--verify`. For `--checksum`-only, skip the client-side hash. Avoids reading the input file twice.
- **Replicate sizing rule.** Mirror upstream baton: report the size of the highest-numbered replica with `DATA_REPL_STATUS = 1` (a "good" replica). Decision captured in code in 5b alongside the implementation.

**Completed (single working branch `feat/session-5-get-put`, 26 commits):**

- **Shim surface** (`shim/ffi_shim.{h,c}`, mirrored in `src/ffi.rs`) — read primitives (`shim_data_obj_open` / `_read` / `_close`, `SHIM_OPEN_READ`), write primitives (`shim_data_obj_write`, `SHIM_OPEN_WRITE`), checksum primitive (`shim_data_obj_checksum`), and `SHIM_COL_DATA_SIZE` for replicate-aware catalog queries. Every addition follows the convention adopted in Session 4.5 (declare-implement-mirror).
- **Connection layer** (`src/connection.rs`) — `OpenMode { Read, Write }`, public `open_data_object` / `read_data_object` / `write_data_object` / `close_data_object` / `checksum_data_object` methods, `ReconnectingSession` watchdog wrapper, `parse_connect_time` clap value parser, `DEFAULT_CONNECT_TIME_SECS` (600) / `MIN_CONNECT_TIME_SECS` (10) constants.
- **`operations::get`** — `get_one` / `get_one_annotated` with two modes: inline (base64 in the output `data` field) and `--save` (streams to `<input.directory>/<input.data_object>` on disk, omits `data`). Collection inputs are an error. 64 KiB chunked read loop; `fsync` after the save completes. Per-record `directory` field on `DataObject` matches upstream baton's wire shape.
- **`operations::put`** (new module) — `put_one` / `put_one_annotated` streaming a local file up to iRODS via `OpenMode::Write`. `--checksum` populates the output digest from `rcDataObjChksum` after close. `--verify` additionally hashes bytes client-side and compares — pure-function helpers `checksums_match` (prefix-stripping + case-insensitive bool) and `verify_checksum` (Result-wrapping the comparison) carry the unhappy-path logic so it's unit-testable without driving real iRODS. `--verify` implies `--checksum` on the output. `SHIM_OPEN_WRITE` is `O_WRONLY | O_CREAT | O_TRUNC` — overwrite-on-collision matches `iput -f`.
- **`operations::list`** — replicate-aware sizing: when `--size` or `--checksum` is on, query the catalog for `(repl_num, size, checksum, status)`, pick the highest-numbered valid replica's values. `pick_canonical_replica` extracted as a pure function for unit-testing. Falls back to the existing `rcObjStat` values when no replica has `status == 1`.
- **Types** (`src/types.rs`) — `DataObject.data: Option<String>` (base64 inline content) and `DataObject.directory: Option<String>` (per-record save destination). All struct literals across the crate and integration tests grew the new fields.
- **Binaries** — `baton-put` wired from the Session 1 stub; `baton-get` grew `--save`. All five active binaries (`baton-list`, `baton-get`, `baton-put`, `baton-metamod`, `baton-metaquery`) gained `--connect-time / -c <seconds>` (default 600, min 10) wired through `ReconnectingSession`. The watchdog only fires *between* records, mirroring upstream's pthread-based design but without the pthread (Rust's NDJSON loop is single-threaded synchronous). `baton-chmod` and `baton-do` remain Session 1 stubs awaiting their sessions.
- **CI matrix** stayed green at every push across 4.2.7 / 4.3.4 / 4.3.5. No matrix changes.
- **Dependencies** — `base64 = "0.22"` added as a runtime dep (5a). `md5 = "0.7"` added in 5b's `--checksum` cross-check tests as a `[dev-dependencies]` entry, then promoted to a runtime dep in 5b's `--verify` commit. `Cargo.lock` formally gitignored (decision from the Session 4.5 audit, surfaced again here and acted on).
- **Tests** — extensive integration coverage: get inline (full byte-range, empty file, multi-chunk, 30 MB stress, sequential, recovery, three chunk-boundary sizes ±1, special characters in path); get save (round-trip, multi-chunk, missing directory, missing destination, overwrite); put (round-trip, multi-chunk, overwrite, empty file, sequential, recovery, missing inputs, collection input); --checksum (populates field, matches independent MD5, post-overwrite reflects new bytes); --verify (clean upload, multi-chunk); reconnect (zero-threshold force-reconnect, conventional-threshold no-op). Unit tests cover `pick_canonical_replica` (6 cases), `checksums_match` / `verify_checksum` (8 cases), and the `--connect-time` threshold logic (5 cases).

**Deferred / known gaps:**

- **Per-record `file` field** on `DataObject` for renamed local paths in `--save` / `baton-put`. Upstream baton resolves `<directory>/<file>` first, falling back to `<directory>/<data_object>`; we currently do only the fallback. Real wire-format compat gap, intentionally out-of-scope. Tracked as #30.
- **Pluggable hash-scheme support** (`BATON_HASH_SCHEME`). MD5 stays the only client-side scheme. iRODS 4.x server default for `default_hash_scheme` is actually SHA256 — upstream baton fails `--verify` on default-config zones. baton-rs has the chance to do better than baton here once compat is in. Implementation tracked as #31; companion CI matrix as #27. Both blocked on full baton functional compat (Session 8).
- **Upstream CLI-flag gap** — baton has many flags we don't yet expose: `--unsafe`, `--unbuffered`, `--no-clobber`, `--file`, `--buffer-size`, `--raw` (get), `--wlock`, `--single-server`, `--redirect` (put). Plus `--avu` / `--acl` / `--size` / `--timestamp` on `baton-get` (we have these on `baton-list` and they reuse `enrich_with_metadata`). All Session 8 polish — bulk pass rather than one-off additions.
- **iRODS 5.x in CI matrix** — still deferred to Session 8.
- **Path-traversal hardening** on `--save` — current behaviour mirrors upstream's `make_file_path`; deviating would be a deliberate Session 8 decision.
- **Reconnect-failure-path test** — hard to fault-inject without a test-only shim hook. The contract is documented as fail-fast in `ReconnectingSession::maybe_reconnect`; defer the test to Session 8 if the path becomes load-bearing.

**Decisions made:**

- **Per-record `directory` field on `DataObject`** for the `--save` and put destinations. Modelled flat on the existing struct rather than as a wrapping envelope, because that matches upstream baton's wire shape exactly (`{collection, data_object, directory}`).
- **`--checksum` and `--verify` are mutually exclusive at the CLI** via clap's `conflicts_with`. Matches upstream's documented surface: `--verify` is a strict superset (it computes server-side too), so passing both has no useful meaning.
- **`--verify` implies `--checksum` on the output.** Once we've fetched the server digest for the comparison there's no reason to drop it on the floor.
- **`--connect-time` wired in 5c rather than deferred** to Session 8. The implementation turned out small (`ReconnectingSession` + 5 binary wiring sites) and the alternative was leaving the binaries with no auto-reconnect for an indeterminate time. Default 600s, min 10s — matches upstream `baton.h:34` / `operations.c:77-83` exactly. Between-records-only semantics (no mid-stream preemption) also match upstream.
- **MD5 is an integrity claim, not a security claim.** Documented in `operations::put`'s module doc. The threat model for `--verify` is detecting accidental corruption (network, disk) by an honest client / server, not adversarial collisions. SHA2 path is gated on #31 / #27 landing.
- **`--verify` mismatch leaves bytes on the server.** Matches upstream — the binary doesn't auto-clean failed verifies. The user gets a `BatonError` carrying both digests and decides.
- **Path traversal in `--save` / `baton-put` mirrors upstream baton.** No `..` rejection, no symlink protection on `File::create`. Threat model: operator-trusted input. Hardening would deviate from upstream.
- **Replicate-aware sizing applies to both `--size` and `--checksum`** together. The mental model is "the canonical state of this data object" — size and checksum should describe the same replica.
- **`pick_canonical_replica` extracted as a pure function** so the selection rule (skip non-status-1, pick max repl_num, silently skip unparseable rows) is unit-testable without driving real iRODS.
- **`Cargo.lock` formally gitignored.** The crate is treated as a library — gitignoring the lockfile lets downstream consumers' lockfiles drive resolution. Decision from Session 4.5's audit, formalised here.
- **`md5` crate** chosen for client-side hashing (small, simple `Context::new` / `consume` / `compute` API). Pluggable scheme work (#31) will likely swap to RustCrypto's `md-5` + `sha2` behind the `digest::Digest` trait — that's the substantive piece.

**Open questions for next session (Session 6 — baton-chmod):**

- iRODS API for ACL modification — is there a single `rcModAccessControl` call, or do permission grants/revokes need to be composed? A new shim primitive is almost certainly needed.
- `--recurse` semantics: depth-first / breadth-first; serial through one connection; how does the per-input failure annotation interact with partial recursion?
- Inheritance: how do iRODS's inherit-bit semantics map onto the JSON model? Is it part of an ACL entry or a separate flag?
- Owner-zone defaulting: input ACL records may omit `zone`; does baton infer from server's local zone, or require explicit?

---

### Session 6 — baton-chmod

**Status:** completed on 2026-05-01

**Goal:** ACL modification with `--recurse` support. Single binary, single working branch `feat/session-6-chmod`. Settled the five open questions from Session 5 via an upstream gap-analysis pass before any code landed (issue #33).

**Completed (8 commits):**

- **Shim primitive** (`shim/ffi_shim.{h,c}`, mirrored in `src/ffi.rs`) — `shim_mod_access_control` wrapping `rcModAccessControl`. Builds the `modAccessControlInp_t` internally; takes path / level / user / zone / recursive flag. NULL or empty zone resolves to the server's local zone (matches upstream's `parseUserName`-driven behaviour). One call per (path, user, level) tuple; multi-grant ACL lists iterate.
- **`AclLevel::as_irods_str`** (`src/types.rs`) — bare lowercase strings (`"null"` / `"read"` / `"write"` / `"own"`) the iRODS C API wants, distinct from the serde JSON representation. Pinned to upstream's exact set (`baton/src/query.h:52-55`); anything outside surfaces as `CAT_INVALID_ARGUMENT` server-side.
- **`RodsConnection::mod_access_control`** — typed wrapper composing CStrings for path / level / user / zone, delegating to the shim, error-wrapping any non-zero return. Mirrors `mod_avu`'s shape from Session 4b.
- **`operations::chmod`** (`src/operations/chmod.rs`, new module) — `ChmodOptions { recursive: bool }`, `chmod_one`, `chmod_one_annotated`. Iterates `target.access[]` and dispatches one shim call per entry. Empty / absent access is a no-op success; output echoes the input. `recursive` masked to `false` for data-object targets client-side. **Breaks on the first failing entry** within an `access[]` array — matches upstream baton (`baton/src/operations.c:420`); accumulate-instead-of-break alternative tracked in #34.
- **`baton-chmod` binary** wired from the Session 1 stub. Same NDJSON harness as the other binaries: `--recurse / -r`, `--connect-time / -c`, `--verbose / -v`, `--silent`. Per-input failures annotate the `error` field and the stream continues. baton-chmod was the sixth of seven baton binaries to gain its real implementation; only `baton-do` (Session 7) remains a stub.
- **`parse_acl_level` 4.3.x fix** (`src/operations/list.rs`) — extended to accept iRODS 4.3.x's underscore-separated forms (`read_object`, `modify_object`) alongside the existing compact (`read`) and 4.2.x verbose (`read object`) forms. Surfaced by Session 6's chmod tests on 4.3.4 — earlier list-only tests didn't trip the gap because they only read the default-server ACL state, which uses the verbose form. Covered by an extended unit test.
- **`--recurse` footgun documentation** in both the binary's clap help (`baton-chmod --help`) and the `operations::chmod` module doc — server-side walk has no client-side ceiling, matching upstream baton (and iRODS itself, which has no max-depth bound). Surfaced by the pre-PR audit; surfacing it in code so reviewers and users don't have to deduce it from the absence of recursion logic.
- **Tests** — 10 integration tests in `tests/chmod.rs` (grant `read` to `public` group with zone-defaulting, null-revoke, multi-ACL with second-wins, missing user / missing path annotated errors, `--recurse` on a populated collection covering parent + sub-collection + child data object, empty access no-op for both `Some(vec![])` and `None`, **break-on-first-failure** load-bearing pin, recovery-after-error on same connection, data-object target with `recursive=true` to pin the client-side mask + echo byte-equality). Verification goes through `list_one --acl` rather than parsing `ils -A` — the well-tested ACL reader is the right oracle for "what's recorded right now".
- **Audit pass** — pre-PR sweep across consistency, dependencies, security, docs, and test coverage. Findings either fixed (date bumps, missing data-object test, echo-pin) or flagged for future sessions (pre-existing `tracing` direct-dep unused, sequential-good-then-good test deemed skippable since recovery covers the surface).

**Deferred / known gaps:**

- **Accumulate-instead-of-break for per-grant errors in `access[]` arrays.** Tracked as #34. baton-rs currently mirrors baton's `goto finally` semantics for upstream-compat parity. Worth revisiting once full functional compat is in place and downstream feedback (partisan) flags the silent-skip behaviour as confusing.
- **No sequential good-then-good chmod test on the same connection.** Recovery-after-error test exercises bad-then-good; explicit good-then-good was deemed redundant with the recovery coverage. Symmetry argument with put / get tests; revisit if a regression surfaces.
- **Explicit `zone` value never exercised** on input. All chmod tests omit `zone` and rely on local-zone defaulting; the test container is single-zone so `Some("testZone")` is server-side equivalent. Genuine gap, requires a multi-zone fixture (Session 8 polish or later).
- **`tracing = "0.1"` is an unused direct dep** in `Cargo.toml`. Pre-existing from Session 1 scaffold; only `tracing_subscriber` is actually `use`d. Either drop the entry or wire `tracing::instrument` in a later session. Not a Session 6 regression.
- Inherited-from-earlier deferrals stay in scope for later sessions: per-record `file` field (#30), pluggable `BATON_HASH_SCHEME` (#31, #27), iRODS 5.x in CI (Session 8), upstream CLI-flag gap (`--unsafe` / `--unbuffered` / `--no-clobber` / `--file` / `--buffer-size`, plus `--avu` / `--acl` / `--size` / `--timestamp` on `baton-get` — Session 8).

**Decisions made:**

All five gap-analysis questions from Session 5's carry-forward were settled with citations to upstream baton's source (recorded in #33):

- **API shape** — one `rcModAccessControl` call per (path, owner, level). No batching, no diff. Mirrors `baton/src/baton.c:746`.
- **Recursion** — set `recursiveFlag = 1` and let the iCAT walk server-side. baton-rs does no client-side traversal. Matches `baton/src/baton.c:729`.
- **Inheritance** — not exposed in v1. baton itself doesn't expose it (`grep -rn inherit baton/src/` is empty). Document as a future baton-rs extension if ever needed.
- **Owner-zone defaulting** — `zone: Option<String>` on input; `None` becomes a NULL pointer to the shim, which forwards as empty-string to iRODS, which resolves to the local zone. No client-side `getRodsEnv` probe. Matches `baton/src/baton.c:786-791`.
- **`AclLevel` variants** — keep the existing four (`null` / `read` / `write` / `own`). serde already rejects anything else.
- **Per-array failure handling** — break on first failure (option a, the upstream-compat default). Accumulate-instead-of-break tracked in #34 for a future session.
- **`--recurse` server-side ceiling** — none, matching upstream. Documented in code rather than guarded.

Implementation-detail choices:

- **`AclLevel::as_irods_str` returns bare strings** rather than relying on `serde_json::to_string` (which would JSON-quote). Cleaner separation between the on-the-wire JSON shape and the iRODS C API contract.
- **`pick_canonical_replica`-style extraction not needed for chmod** — the per-entry loop is simple enough that a pure-function helper would be over-engineering. Loop sits inside `chmod_one`.
- **Verification through `list_one --acl`** rather than `ils -A` parsing — keeps test assertions out-of-process-free and exercises baton-rs's own ACL reader as a side effect.
- **`parse_acl_level` extended in `operations::list`**, not in a new shim primitive. The fix is purely about catalog-string-string parsing on the Rust side; the shim doesn't need to know about iRODS-version-specific catalog spellings.

**Open questions for next session (Session 7 — baton-do multiplexer):**

- **JSON envelope shape.** PLAN.md specifies `{"operation": "...", "arguments": {...}, "target": {...}}`. Confirm against upstream baton-do's actual input shape — does `arguments` carry the per-operation flags (`recursive`, `save`, `checksum`, `verify`, etc.) or is there a different convention?
- **Dispatch mechanism.** Function-pointer table, `match` on a `Operation` enum, or a trait? Affects how easily new operations slot in (the extra ones below).
- **Extra operations baton-do exposes that we don't have yet:** `checksum` (server-side digest on an existing object — needs `rcDataObjChksum` exposed differently), `move` (`rcDataObjRename` / `rcCollRename`), `remove` (`rcDataObjUnlink` / `rcRmColl`), `mkdir` (`rcCollCreate`), `rmdir` (`rcRmColl` again, possibly with different flags). Each needs a new shim primitive.
- **`--no-error` mode** — upstream baton-do's "in-band JSON errors only" flag. We already have annotated wrappers for every operation; how does `--no-error` differ? Does it suppress the process-level `Err` and only emit annotated JSON, even on parse / IO failures?
- **Compat is the load-bearing concern** — `baton-do` is what partisan calls. The wire format and dispatch table need to match upstream byte-for-byte.

---

### Session 7 — baton-do multiplexer

**Status:** completed on 2026-05-06

**Goal:** JSON envelope dispatcher covering list, get, put, chmod, metamod, metaquery, checksum, move, remove, mkdir, rmdir (11 operations). `--no-error` mode. Single working branch `feat/session-7-baton-do`. Split internally into 7a (new shim primitives + 5 new operations) and 7b (envelope types + dispatcher + binary + tests), with a 7c pre-PR audit pass.

**Completed (18 commits):**

7a — five new operations needed by baton-do:

- **Path-management shim primitives** (`shim/ffi_shim.{h,c}`, mirrored in `src/ffi.rs`) — `shim_data_obj_chksum` (server-side digest, wraps `rcDataObjChksum`), `shim_coll_create` / `shim_coll_remove` (collection lifecycle, wrap `rcCollCreate` / `rcRmColl`), `shim_data_obj_unlink` (data-object delete, wraps `rcDataObjUnlink`), `shim_data_obj_rename` / `shim_coll_rename` (rename / move, wrap `rcDataObjRename` / `rcCollRename`). Force / recursive / verify flags exposed where upstream's struct bitfields demand them.
- **`RodsConnection` typed wrappers** (`src/connection.rs`) for each new shim primitive. Same shape as the Session 6 `mod_access_control` wrapper: build CStrings client-side, dispatch through the shim, error-wrap any non-zero return.
- **`operations::checksum`** — `ChecksumOptions { force: bool, verify: bool, all: bool }`, `checksum_one`, `checksum_one_annotated`. `force` forces re-compute; `verify` cross-checks against the catalog-recorded digest after compute; `all` distributes per-replica when the object has multiple. Wire-compat with upstream's `--checksum` / `--verify` semantics.
- **`operations::mkdir`** — `MkdirOptions { recursive: bool }`, `mkdir_one`, `mkdir_one_annotated`. `recursive` creates intermediate collections (`recursiveOpr` flag on `rcCollCreate`).
- **`operations::rmdir`** — `RmdirOptions { recursive: bool, force: bool }`, `rmdir_one`, `rmdir_one_annotated`. `recursive` walks server-side; `force` skips the trash. Empty / absent collection annotates `error` rather than panicking.
- **`operations::rm`** — `RmOptions { force: bool }`, `rm_one`, `rm_one_annotated`. `force` skips the trash for data-object delete (matches `iRODS`'s `forceFlag`). Collections fall through to `rmdir` semantics rather than failing.
- **`operations::mv`** — `MvOptions {}` (no flags exposed), `mv_one`, `mv_one_annotated`. `arguments.path` carries the destination; missing it surfaces a clear `arguments.path required` error before any iRODS call. Same path is used by both data objects and collections — `rcDataObjRename` / `rcCollRename` differentiate server-side.
- **Tests** — Per-operation integration test suites (`tests/checksum.rs`, `tests/mkdir.rs`, `tests/rmdir.rs`, `tests/rm.rs`, `tests/mv.rs`, ~10 tests each) covering happy path, recursive / force / verify, missing-path annotation, recovery-after-error on the same connection, and echo-equality (where applicable). 7a closed with a post-7a audit cleanup pass (commits `31cb65e`, `76c9ac3`) bumping doc dates, filling missing recovery-after-error tests, and pinning echo equality.

7b — envelope, dispatcher, binary, integration tests:

- **`BatonDoEnvelope` / `BatonDoOutput` / `Operation` / `Arguments` / `OperationResult` / `EnvelopeTarget`** (`src/types.rs`) — full JSON wire shape with custom `Deserialize` driving the operation-discriminated target split. `EnvelopeTarget::Standard(Target)` for non-metaquery operations; `EnvelopeTarget::Query(MetaqueryInput)` for metaquery (carries `AvuQuery` / `TimestampQuery` / `AccessQuery` operator fields and the top-level `zone` scope). `Arguments` accepts both long and short forms (`object`/`o`, `collection`/`coll`, etc.); short-form aliases match upstream baton-do exactly. `BatonDoOutput` inlines envelope fields rather than `#[serde(flatten)]` — flatten doesn't compose with custom `Deserialize`. Constructor helpers `new_standard` / `new_metaquery` keep test code clean.
- **`operations::baton_do::dispatch_one`** — top-level dispatcher. `match` on `envelope.operation` (11 arms, one per operation; the `Operation` enum is closed and unknown discriminators are rejected by serde at envelope-deserialise time, surfacing as parse-error lines via the binary's NDJSON loop). Each non-metaquery arm pulls a `Target` via `expect_standard`; metaquery arm pulls a `MetaqueryInput` via `as_metaquery_input`. Per-op `*_one_annotated` calls; per-op error annotations are pulled from `Target.error` / `*Input.error` to envelope-level `BatonDoOutput.error` per upstream's `add_error_value` behaviour (`baton/src/operations.c:129-136`). Helpers `list_options_from_arguments` / `metaquery_flags_from_arguments` / `decoration_options_from_arguments` map `Arguments` onto each operation's typed options.
- **`operations::metaquery::decorate_result` + `DecorationOptions`** (extracted from `baton-metaquery` binary into the operations module) — shared between `baton-metaquery` and `baton-do`'s metaquery path so per-result decoration semantics live in one place.
- **`baton-do` binary** (`src/bin/baton-do.rs`) — clap-driven NDJSON loop. Args: `--file` / stdin input, `--connect-time` / `-c`, `--no-error`, `--unbuffered`, `--verbose` / `--silent` / `--debug` (mirrors upstream's `-v` / `--silent` / `--debug`), `--zone` / `-z` (accepted-but-ignored, warns; per-record metaquery `zone` is the supported way), `--single-server` (accepted-but-no-op; baton-rs already reuses connections). Per-input failures annotate `error` and the stream continues. Parse failures emit a stand-alone `{"error": {...}}` line and the stream continues — documented divergence from upstream's parse-error wire shape, tracked as #37. Connection-level failures are fail-fast. `ReconnectingSession` watchdog wired in for `--connect-time`. Exit code: 1 if any per-input error occurred (suppressed by `--no-error`), 0 otherwise.
- **`tests/baton_do_dispatch.rs`** — live-connection dispatch routing tests (4 tests) covering list-with-size routing, metaquery-with-operator → `OperationResult::Multiple`, metaquery + size decoration through the dispatcher, and `mv` arguments-validation.
- **`tests/baton_do_binary.rs`** — full binary-level integration coverage (16 tests) spawning the compiled `baton-do` via `env!("CARGO_BIN_EXE_baton-do")`. One test per operation (list / get / put / chmod / metamod / metaquery / checksum / mkdir / rmdir / remove / move) exercising the full clap → NDJSON → deserialiser → dispatcher → operations layer pipeline. Plus five binary-only tests: `--no-error` exit-code suppression, parse-failure stand-alone error line, unknown-operation-discriminator stand-alone error line, `--file` reading from disk, and multi-record stream dispatch in one invocation.
- **iRODS 4.2.7 compat fix** (`b13514a`) — `binary_dispatches_mkdir` / `_rmdir` post-conditions used `ils -d` to check path existence, but 4.2.7's `ils` doesn't accept `-d` (4.3.x-only). Replaced with plain `ils <path>` which exits 0 / non-zero on existing / missing paths on both versions.

7c — pre-PR audit:

- **Date / consistency / security / dependency / docs / test sweep** across the full branch diff (22 files, ~4700 LOC). Done in three passes (consistency + docs, security threat-model, test coverage), each landing as its own commit:
  - **Date headers** (`87d6712`) — bumped four stale `Last modified` headers in files touched by `be05a32` (the mid-7b metaquery wire-shape redesign). Stale-comment scan found no surviving references to the pre-redesign shape; issue cross-references (#36, #37, #25, #27, #30, #31) all still open; public-API surface confirms only `dispatch_one` is `pub` with helpers private.
  - **Doc fixes** (`b6982cb`) — corrected two doc-vs-code mismatches surfaced by the audit. `baton-do --zone`'s docstring claimed per-record metaquery `zone` was "the supported way to scope a query to a zone", but `operations::metaquery` actually drops `input.zone` at v1; rewritten to state the v1 limitation honestly. `Arguments.raw`'s comment said `save / raw: baton-get modes`, but only `save` is consulted; documented as accepted-but-no-op alongside `single_server` and `redirect`.
  - **Coverage tests** (`b3d1a40`) — added five unit tests in `src/types.rs::tests` pinning the `BatonDoEnvelope` custom-`Deserialize` error branches (missing `operation`, missing `target`, unknown operation discriminator, duplicate `operation` key, target-shape-mismatch for a standard op) plus one binary-level integration test (`unknown_operation_discriminator_is_annotated_and_stream_continues`) that exercises the visitor's enum-variant rejection path — distinct from the lexical-JSON parse-failure path already covered.
- Security audit found no exploitable issues; dependency review confirmed no new direct deps added in 7b/7c (carry-forward `tracing = "0.1"` direct-but-unused already noted in Session 6's deferred list); test-coverage review's deferrable findings (mixed-success-and-error stream test, boundary-input tests, defensive-error-branch unit tests, naming inconsistency `Operation::Move`/`Remove` vs modules `mv`/`rm`, `*_one_annotated` boilerplate consolidation) all carried forward to Session 8 — see Deferred / known gaps below.

**Deferred / known gaps:**

- **Parse-error wire shape divergence** — baton-rs emits `{"error": {...}}` on a malformed input line; upstream baton-do attempts to echo the input alongside the error, but the input was unparseable so the echo is itself ill-defined in upstream. Tracked as #37 and called out in `baton-do.rs`'s module doc + the parse-error code path.
- **Cross-zone metaquery scoping is not supported in v1.** `baton-do --zone` and the per-record `MetaqueryInput.zone` field are both currently dropped at the operations layer (`src/operations/metaquery.rs:588-590`); queries run against the local zone only. Wiring zone through requires a different iRODS API and is deferred to Session 8. Per-AVU `AccessQuery.zone` (the user-zone in an ACL filter) **is** wired and tested.
- **`--single-server` is accepted but a no-op.** Upstream uses it to suppress its own per-record reconnect; baton-rs already reuses the same connection across records (subject to `--connect-time` recycling). Kept so scripts that pass it to upstream don't fail here.
- **`Arguments.raw` is accepted but a no-op.** Upstream's raw-bytes get mode; baton-rs always returns the inline base64 representation. Documented in `Arguments`'s field-level doc.
- **No multi-record-with-mixed-success-and-iRODS-error stream test.** Each test stream is either all-success or single-record-failure. The `--no-error` and parse-failure tests exercise the multi-line-with-error path adjacently; symmetry argument applies, revisit if regressions surface.
- **Naming inconsistency**: wire / `Operation::Move` ↔ Rust module `mv`; wire / `Operation::Remove` ↔ Rust module `rm`. All other operation pairs match. Either rename modules to `move` / `remove` (`r#move`) or rename `Operation` variants — touches API surface so deferred to Session 8.
- **`*_one_annotated` boilerplate**: five new operations modules (`checksum` / `mkdir` / `rmdir` / `rm` / `mv`) repeat the same 7-line `let fallback = target.clone(); match X(...) { Ok(t) => t, Err(err) => { fallback.set_error(err); fallback }}` pattern. A shared helper would collapse five copies. Refactor deferred to Session 8.
- **No explicit `--connect-time` recycling test on baton-do.** `ReconnectingSession` is unit-tested in Session 5c; the binary just wires it in. End-to-end recycling test would need a long-running stream and is deferred to Session 8.
- Inherited deferrals stay in scope for later sessions: per-record `file` field (#30), pluggable `BATON_HASH_SCHEME` (#31, #27), iRODS 5.x in CI (Session 8), accumulate-instead-of-break per-grant errors (#34), upstream CLI-flag gap (`--unsafe` / `--unbuffered` / `--no-clobber` / `--file` / `--buffer-size`, plus `--avu` / `--acl` / `--size` / `--timestamp` on `baton-get` — Session 8).

**Decisions made:**

The five open questions from Session 6's carry-forward were settled:

- **JSON envelope shape** — `{"operation", "target", "arguments", "result"|"error"}` matches PLAN.md and upstream byte-for-byte. The non-trivial detail is that `target` is operation-discriminated: standard `Target` for ten operations, richer `MetaqueryInput` (with operator-bearing `AvuQuery` / `TimestampQuery` / `AccessQuery`) for metaquery. Implemented as an `EnvelopeTarget` enum with custom `Deserialize` reading the operation field first. Best-effort mapping would silently drop operators and zone — wire-compat gap not acceptable.
- **Dispatch mechanism** — `match` on `Operation` enum in `dispatch_one`. Function-pointer table was considered and rejected: the per-op signatures diverge enough (some take `MetaqueryInput`, most take `Target`; per-op options differ) that a uniform fn-pointer signature would force erasure that costs more than the explicit `match` saves. Trait-based dispatch would add ceremony without reducing surface.
- **Extra operations** — five added (`checksum`, `move`, `remove`, `mkdir`, `rmdir`). Each gets a new shim primitive plus an `operations::` module. All five reuse the `*_one` / `*_one_annotated` pattern from earlier sessions.
- **`--no-error` mode** — process-exit-code suppression only. Per-input error annotations are still emitted in-band on stdout regardless. Matches upstream's behaviour: the in-band annotation is the "no error" channel, the process exit code is what `--no-error` mutes.
- **Compat** — wire format and dispatch table match upstream byte-for-byte for the success path and the in-band error path. One documented divergence on the parse-error wire shape (#37); accepted as a divergence rather than a regression because the upstream behaviour echoes unparseable input.

Implementation-detail choices:

- **`#[serde(flatten)]` rejected for `BatonDoOutput`.** Custom `Deserialize` on `BatonDoEnvelope` doesn't compose with flatten — serde's flatten machinery requires the inner type's deserialiser to operate on a content map rather than a freshly-driven map. Inlining the fields keeps the wire-format identical and the deserialiser explicit.
- **`expect_standard` defensive wrapper** in the dispatcher — converts the `EnvelopeTarget::Query` shape into an internal error in the non-metaquery arms. Can't happen with the custom deserialiser, but cheap insurance against future code changes.
- **`decorate_result` extracted into `operations::metaquery`** rather than duplicated in the dispatcher — shared with the `baton-metaquery` binary; per-result decoration semantics live in one place.
- **Parse-error path emits stand-alone error line, not BatonDoOutput.** No envelope means we can't build a full `BatonDoOutput`; emitting `{"error": {...}}` and continuing is the closest behaviour to upstream that's well-defined. Documented in the binary's module doc and tracked in #37.
- **`--zone` and `--single-server` accepted-but-no-op** rather than rejected. Scripts that pass them to upstream baton-do shouldn't fail when invoking baton-rs; `--zone` warns, `--single-server` debug-logs.
- **`env!("CARGO_BIN_EXE_baton-do")`** for binary-level integration tests — same pattern used by the other binaries' compat tests, no `assert_cmd` dep.

**Open questions for next session (Session 8 — Polish and compatibility):**

- **iRODS 5.x in CI.** Add a fourth matrix entry. Likely a few shim adjustments (auth probe, query API changes); scope unknown until the matrix run.
- **`--unsafe` / `--unbuffered` / `--no-clobber` / `--file` / `--buffer-size` flag gap.** None of these are wired in any binary today. `--unbuffered` is the most likely to be load-bearing for partisan; the others are quality-of-life.
- **`--avu` / `--acl` / `--size` / `--timestamp` on `baton-get`** — upstream supports decoration on get; baton-rs's `baton-get` only emits the path. Probably a `decorate_result` reuse exercise.
- **Partisan test-suite pass.** End-to-end validation against the downstream consumer that drives the wire-format compat requirement. Likely surfaces edge cases the per-binary tests miss.
- **`tracing = "0.1"` direct dep.** Either drop or wire `tracing::instrument` for span-based connection-context logging.

---

### Session 8 — Polish and compatibility

**Status:** in progress (8a / 8b / 8c merged; 8d planned post-recon).

**Goal (post-recon):** Close the wire-compat gaps that block downstream consumers, then validate end-to-end against the partisan (Python) and extendo (Go) test suites. Originally framed around CLI-flag parity (`--unbuffered` / `--unsafe` / etc.); after a recon pass against five wtsi-npg repos (see #39 update on 2026-05-07) those flags were re-classified as not partisan/extendo-blocking and pushed to a future session. iRODS 5.x compatibility moved to its own tracking issue (#40).

**Completed sub-sessions:**

- **8a — housekeeping & deferred-test closure** (PR #41, merged 2026-05-06). `Annotatable` trait + `annotate_failure` helper collapse nine `*_one_annotated` functions across the operations layer; boundary-input tests (spaces / unicode / deep nesting); mixed-success-and-iRODS-error stream test; end-to-end `--connect-time` recycle test on `baton-do`. The "drop unused `tracing` direct dep" carry-forward from Session 6 dissolved — `tracing::warn!` / `debug!` are genuinely used in `baton-do.rs` since 7b.
- **8b — `Operation::Move` → `Mv`, `Remove` → `Rm` rename** (PR #43, merged 2026-05-06). Restores the variant-↔-module pairing across all 11 operations (`Mv` ↔ `mv`, `Rm` ↔ `rm`, matching the `Mkdir`/`Rmdir` abbreviation pattern). Wire format preserved via explicit `#[serde(rename = "move"/"remove")]` attributes (the original `#[serde(rename_all = "lowercase")]` would otherwise have changed the wire form).
- **8c — `baton-get` decoration parity** (PR #45, merged 2026-05-06). Six decoration flags (`--avu` / `--acl` / `--size` / `--checksum` / `--replicate` / `--timestamp`) wired into `baton-get` via the shared `decorate_result` helper extracted in 7b. Skip-on-error guard added to `decorate_result` so an errored get isn't masked by a follow-up stat. New `Target::has_error()` accessor.

**Pending sub-sessions (post-recon plan, see #39):**

- **8d — wire-compat gaps for partisan/extendo:** per-record `file` field on `DataObject` (#30), `checksum` operation args naming (`{calculate, recalculate, verify}` vs `{force, verify}` — needs upstream-source check), `baton-do --server-version` for health checks, `force` / `verify` threaded through the `get` op.
- **8e — cross-zone metaquery scoping** + **accumulate-instead-of-break for chmod** (#34). Lower partisan-blocking urgency; optionally bundled with 8d.
- **8f — partisan / extendo test-suite validation.** Run their suites against baton-rs binaries, surface anything missed.

**Deferred / known gaps:**

- **CLI-flag parity** (`--unbuffered` / `--unsafe` / `--no-clobber` / `--file` / `--buffer-size`) — re-classified post-recon as not partisan/extendo-blocking; deferred to a future session.
- **iRODS 5.x compatibility** — separate tracking issue (#40).
- **Pluggable `BATON_HASH_SCHEME`** (#27, #31) — stays deferred unless 8f surfaces a partisan fixture that needs SHA2.

**Decisions made (so far):**

- **`Operation::Move`/`Remove` rename direction**: rename the Rust variants (option A) rather than the modules (option B). Keeps `r#move` / `r#remove` raw-identifier ugliness out of the codebase; wire format stays the same via per-variant `#[serde(rename)]`.
- **`baton-get` decoration scope**: all six DecorationOptions fields rather than only the four (`--avu` / `--acl` / `--size` / `--timestamp`) listed in #39. Matches `baton-list` parity at no extra implementation cost.
- **`tracing` direct dep stays** — used in `baton-do.rs` since 7b. The Session 6 carry-forward was stale.
- **Recon-driven re-prioritisation** (2026-05-07): partisan and extendo both target only `baton-do`, which means the CLI-flag-parity work is not on the partisan critical path. Real partisan-blocking gaps are at the wire-format level (see #39 update).

**Open questions (carried into 8d):**

- **`checksum` args naming**: does upstream baton accept both `{calculate, recalculate}` and `{force}` as aliases, or do partisan and extendo each tolerate the other's spelling? Needs upstream-source check before settling baton-rs's Arguments shape.
- **`force` semantics on `get`**: partisan sends `{force, save, verify, redirect}` for `--save`-style get; what does upstream baton do with `force` on a get? (Likely "overwrite local file if it exists".)

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
- `2026-04-24` — Session 1 completed: JSON data model and stub binaries.
- `2026-04-24` — Session 2 completed: iRODS FFI + RodsConnection (connect, login, reconnect). 4.2.7 flipped experimental (issue #9); auth bypasses clientLogin (issue #10).
- `2026-04-27` — Session 3 completed across three branches: 3a (CLI harness + size/checksum + in-band errors), 3b (avu/acl/replicate/timestamp via rcGenQuery), 3c (contents + best-effort compat test). First real binary on the FFI substrate.
- `2026-04-28` — Session 4 completed across three branches: 4a (extract enrich_with_metadata), 4b (baton-metamod via rcModAVUMetadata), 4c (baton-metaquery with single/multi-AVU + timestamp + ACL + scope). First binary that mutates iRODS state and first that uses the Operator enum from Session 1.
- `2026-04-29` — Session 4.5 completed: C shim landed, bindgen and libclang dropped from the build entirely, iRODS 4.2.7 flipped back to strict (issue #9 closed). Issue #25 (4.2.7 replResc checksum-algorithm divergence) closed by pinning `irods_default_hash_scheme = MD5` in the client environment. New cross-cutting convention: every iRODS API call goes through `shim/ffi_shim.{c,h}` mirrored in `src/ffi.rs`.
- `2026-04-29` — Session 5 started on branch `feat/session-5-get-put`. Split into 5a/5b/5c; up-front decisions on streaming MD5 (client-side on put) and replicate sizing (highest-numbered valid replica). `--connect-time` wiring deferred to 5c.
- `2026-05-01` — Session 5 completed. `baton-get` (inline + `--save`) and `baton-put` (streaming MD5, `--checksum`, `--verify`) landed; replicate-aware sizing wired into `baton-list` for `--size` / `--checksum`; `--connect-time` wired across all five active binaries via the `ReconnectingSession` watchdog (default 600s, min 10s, between-records only — matches upstream). `base64` added as a runtime dep; `md5` promoted from dev-dep to runtime dep. Three follow-up issues opened: #30 (per-record `file` field for renamed local paths), #31 (pluggable `BATON_HASH_SCHEME`), #27 (companion CI matrix for the hash-scheme axis). Session tracked in #28.
- `2026-05-01` — Session 6 completed on branch `feat/session-6-chmod` (8 commits). `baton-chmod` wired with `--recurse`; settled the five gap-analysis questions from Session 5's carry-forward via upstream-source citations. Sixth of seven baton binaries with a real implementation — only `baton-do` (Session 7) remains a stub. `parse_acl_level` extended to accept iRODS 4.3.x's underscore-separated forms (`read_object` / `modify_object`); the gap was undetected before because earlier list-only tests only read default-server ACL state. One follow-up issue opened: #34 (per-grant accumulate-vs-break alternative). Session tracked in #33.
- `2026-05-06` — Session 7 completed on branch `feat/session-7-baton-do` (18 commits across 7a / 7b / 7c). `baton-do` wired with the full clap surface; 11-arm dispatcher in `operations::baton_do`; `BatonDoEnvelope` / `BatonDoOutput` / `EnvelopeTarget` with operation-discriminated custom Deserialize; `decorate_result` extracted into the operations layer for reuse. Five new operations + shim primitives (`checksum` / `mkdir` / `rmdir` / `rm` / `mv`). One documented divergence on parse-error wire shape (#37). Session tracked in #36.
- `2026-05-06` — Sessions 8a / 8b / 8c completed (PRs #41 / #43 / #45). 8a closed deferred-test gaps and extracted the shared `annotate_failure` helper across nine operations; 8b renamed `Operation::Move`/`Remove` to `Mv`/`Rm` for variant-↔-module consistency (wire format preserved); 8c wired six decoration flags into `baton-get`. Session 8 tracked in #39; iRODS 5.x pulled out into a separate sink (#40).
- `2026-05-07` — Session 8 plan re-prioritised post-recon. Reconned five wtsi-npg downstream consumers (partisan, extendo, npg-irods-python, npg_irods, valet, perl-irods-wrap); confirmed `baton-do` is the universal entry point and identified four wire-compat gaps that block partisan/extendo (per-record `file` field, `checksum` args naming, `--server-version` health-check flag, `force`/`verify` threading on `get`). CLI-flag parity (`--unbuffered` etc.) deferred to a future session — not on the partisan critical path. 8d / 8e / 8f re-scoped accordingly. Recon details in #39 update of 2026-05-07.
