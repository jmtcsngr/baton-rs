# Releasing baton-rs

Repeatable procedure for cutting a baton-rs release. Each step is
either a command to run or a check to make — designed to be followed
verbatim. One-time setup (Actions allowlist, GHCR repo creation,
branch protection) is out of scope; see git history of the first
release if you need to redo any of it.

## 1. Decide the version

baton-rs follows [Semantic Versioning 2.0.0](https://semver.org/).
**Tag format is bare semver, no `v` prefix.** The tag matches
`Cargo.toml`'s `version` field byte-for-byte — which simplifies
"does the tag match the manifest?" pre-publish checks to a literal
grep.

| Release type      | Tag              |
|-------------------|------------------|
| Alpha             | `1.0.0-alpha.0`  |
| Beta              | `1.0.0-beta.1`   |
| Release candidate | `1.0.0-rc.1`     |
| Stable            | `1.0.0`          |
| Patch             | `1.0.1`          |

`:latest` in GHCR is gated on non-prerelease tags (those without a
`-`). Alphas, betas, and rcs never move `:latest`.

## 2. Pre-release checks (every release)

Run through this checklist in order. Do not proceed to step 3 until
every item is green or has a tracking issue.

- [ ] **Local main is current.** `git checkout main && git pull --ff-only`.
- [ ] **All relevant PRs merged.** Confirm nothing intended for this
      release is still open.
- [ ] **Unit-tests workflow green on `main`** for all three iRODS
      matrix entries:
      `gh run list --workflow=unit-tests.yml --branch=main --limit=1`.
- [ ] **`cargo audit` workflow on `main` clean**, or any advisory is
      acknowledged in the CHANGELOG entry for this release:
      `gh run list --workflow=cargo-audit.yml --branch=main --limit=1`.
- [ ] **Partisan compat workflow on `main`.** Any failures are traced
      to known issues. Informational long-term — green is preferred
      but not blocking.
- [ ] **Extendo compat workflow on `main`.** Same standard.
- [ ] **`BATON_COMPAT_VERSION` is current.** `src/version.rs:38`
      still matches the latest upstream baton release this release
      claims wire-compat with. Check
      <https://github.com/wtsi-npg/baton/releases>; bump in a
      separate PR if it moved.
- [ ] **Dockerfile / build-image iRODS pin agree.**
      `docker/Dockerfile`'s `irods-runtime=` and `irods-icommands=`
      version must match the iRODS version of the build image
      referenced in `.github/workflows/publish.yml`'s build step.
      Mismatches produce a runtime image that cannot load the
      binaries.
- [ ] **Downstream pins reviewed.** `.github/scripts/partisan-pin`
      and `.github/scripts/extendo-pin` still point at the SHAs you
      want this release tested against. Bump only if needed; record
      the decision in the CHANGELOG.

## 3. Update the repo

One PR off `main` titled `release: <version>`. Touched files:

- [ ] **`Cargo.toml`** — bump `version`.
- [ ] **`README.md`** — bump the `$ baton-do --version` example in
      the *Version reporting and `STRICT_BATON_COMPAT`* section.
- [ ] **`CHANGELOG.md`** — prepend a new entry. Date is the day you
      open the PR (`YYYY-MM-DD`). Follow
      [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
      sections are `### Added` / `### Changed` / `### Deprecated` /
      `### Removed` / `### Fixed` / `### Security` / `### Notes`.
      Add a footnote link at the bottom:
      `[X.Y.Z]: https://github.com/jmtcsngr/baton-rs/releases/tag/X.Y.Z`.

Sanity check — confirm no stale version strings exist outside the
expected places:

```sh
grep -rn "<old-version>" \
  --include='*.rs' --include='*.toml' --include='*.md' \
  --include='*.yml' . | grep -v '^./CHANGELOG.md'
```

The grep should return nothing once Cargo.toml and README are
updated (CHANGELOG retains older entries by design).

Open the PR, wait for unit-tests CI green, merge.

## 4. Tag and push

```sh
git checkout main
git pull --ff-only
git tag -a <version> -m "<version> release"
git push origin <version>
```

The tag triggers `.github/workflows/publish.yml`, which builds release
binaries in the iRODS-clients-dev container, then builds and pushes
the runtime image to `ghcr.io/jmtcsngr/baton-rs` with these tags:

- Always: `<version>` (e.g. `1.0.0-alpha.0`).
- Non-prerelease only: `<major>.<minor>` (e.g. `1.0`) and `latest`.

Watch the run:

```sh
gh run watch
```

## 5. Verify the container

```sh
docker pull ghcr.io/jmtcsngr/baton-rs:<version>
docker run --rm ghcr.io/jmtcsngr/baton-rs:<version> --version
# Expected output: <version>
```

For a stable release also verify the moving tags:

```sh
docker pull ghcr.io/jmtcsngr/baton-rs:<major>.<minor>
docker pull ghcr.io/jmtcsngr/baton-rs:latest
docker run --rm ghcr.io/jmtcsngr/baton-rs:latest --version
# Expected output: <version>
```

If verification fails, **do not delete the tag** — see step 7. Cut
the next patch with the fix.

## 6. Create the GitHub Release

Pushing a tag creates the git tag, not a Release object. Create the
Release manually so the CHANGELOG entry is surfaced on the project's
Releases page:

```sh
gh release create <version> \
  --title <version> \
  --notes-file - \
  $(grep -q -- '-' <<< '<version>' && echo --prerelease) <<EOF
$(awk '/^## \['"$VERSION"'\]/{p=1;next} /^## \[/{p=0} p' CHANGELOG.md)
EOF
```

Or via the web UI: open
<https://github.com/jmtcsngr/baton-rs/releases/new?tag=><version>,
paste the CHANGELOG section into the body, tick **Set as a
pre-release** if the tag contains a `-`, and publish.

## 7. Roll-back

Do not delete or move a published tag. A broken release stays in
history; cut `<version>+1` with the fix and verify per steps 4–5.

`:latest` is gated on non-prerelease, so an alpha cannot poison the
canonical latest pointer. For a broken stable release, the previous
stable tag remains pullable and the next patch's publish will
overwrite `:latest` once it succeeds.

## What's NOT in this doc

- **One-time setup** — Actions allowlist, GHCR repo creation, branch
  protection rules. See git history of the initial release.
- **Crates.io publication** — baton-rs is binary-only and is not
  currently published to the registry.
- **Cross-zone or wire-shape compat shims** — those gate on
  `STRICT_BATON_COMPAT`; see issue #58 for the design and the
  per-feature release checklist that maps onto it.
