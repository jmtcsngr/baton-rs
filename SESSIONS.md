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
- `2026-04-24` — Session 1 completed: JSON data model and stub binaries.
- `2026-04-24` — Session 2 completed: iRODS FFI + RodsConnection (connect, login, reconnect). 4.2.7 flipped experimental (issue #9); auth bypasses clientLogin (issue #10).
- `2026-04-27` — Session 3 completed across three branches: 3a (CLI harness + size/checksum + in-band errors), 3b (avu/acl/replicate/timestamp via rcGenQuery), 3c (contents + best-effort compat test). First real binary on the FFI substrate.
- `2026-04-28` — Session 4 completed across three branches: 4a (extract enrich_with_metadata), 4b (baton-metamod via rcModAVUMetadata), 4c (baton-metaquery with single/multi-AVU + timestamp + ACL + scope). First binary that mutates iRODS state and first that uses the Operator enum from Session 1.
- `2026-04-29` — Session 4.5 completed: C shim landed, bindgen and libclang dropped from the build entirely, iRODS 4.2.7 flipped back to strict (issue #9 closed). Issue #25 (4.2.7 replResc checksum-algorithm divergence) closed by pinning `irods_default_hash_scheme = MD5` in the client environment. New cross-cutting convention: every iRODS API call goes through `shim/ffi_shim.{c,h}` mirrored in `src/ffi.rs`.
- `2026-04-29` — Session 5 started on branch `feat/session-5-get-put`. Split into 5a/5b/5c; up-front decisions on streaming MD5 (client-side on put) and replicate sizing (highest-numbered valid replica). `--connect-time` wiring deferred to 5c.
- `2026-05-01` — Session 5 completed. `baton-get` (inline + `--save`) and `baton-put` (streaming MD5, `--checksum`, `--verify`) landed; replicate-aware sizing wired into `baton-list` for `--size` / `--checksum`; `--connect-time` wired across all five active binaries via the `ReconnectingSession` watchdog (default 600s, min 10s, between-records only — matches upstream). `base64` added as a runtime dep; `md5` promoted from dev-dep to runtime dep. Three follow-up issues opened: #30 (per-record `file` field for renamed local paths), #31 (pluggable `BATON_HASH_SCHEME`), #27 (companion CI matrix for the hash-scheme axis). Session tracked in #28.
- `2026-05-01` — Session 6 completed on branch `feat/session-6-chmod` (8 commits). `baton-chmod` wired with `--recurse`; settled the five gap-analysis questions from Session 5's carry-forward via upstream-source citations. Sixth of seven baton binaries with a real implementation — only `baton-do` (Session 7) remains a stub. `parse_acl_level` extended to accept iRODS 4.3.x's underscore-separated forms (`read_object` / `modify_object`); the gap was undetected before because earlier list-only tests only read default-server ACL state. One follow-up issue opened: #34 (per-grant accumulate-vs-break alternative). Session tracked in #33.
