# Perch — branching, versioning and release

Last updated: 20 September 2026.

How a change gets from an idea to a signed download. This is the contract; the
automated version of it lives in `.claude/skills/add-feature/SKILL.md` and runs
when someone asks an agent to add a feature.

---

## The chain

```
feature/<issue>-<slug>
        │  PR, CI green, squash merge
        ▼
      dev ──────────────── integration. Everything lands here first.
        │  version bump + changelog, release PR, merge commit
        ▼
      main ─────────────── released code only. Protected.
        │  annotated tag v<X.Y.Z> pushed
        ▼
   GitHub Release ──────── signed, notarised, stapled .dmg
        │
        ▼
   appcast.xml ─────────── Sparkle. Existing installs update from here.
```

**Nothing is ever committed or pushed directly to `main`.** `main` receives
merges from `dev` and nothing else. Both branches are protected: no direct
pushes, no force pushes, PR required, CI required.

`dev` is never released from. Tags are cut on `main`, because the tag is what
the release workflow builds, and what it builds must be exactly what is
released.

## Branch names

| Prefix | For |
|---|---|
| `feature/<issue>-<slug>` | New functionality |
| `fix/<issue>-<slug>` | Bug fixes |
| `docs/<slug>` | Documentation only |
| `chore/<slug>` | Build, CI, tooling |
| `release/<version>` | Only if a release needs stabilising work |

One thing per branch. A module and a refactor are two branches.

## Versioning

Semantic versioning, pre-1.0 until the Phase 3 checklist in `docs/PLAN.md` is
complete.

| Change | Bump |
|---|---|
| `feat` | minor — `0.3.2` → `0.4.0` |
| `fix`, `perf` | patch — `0.4.0` → `0.4.1` |
| Breaking (`!` / `BREAKING CHANGE:`) | major, or minor while pre-1.0 |
| `docs`, `chore`, `ci`, `test` alone | no release |

The version lives in `project.yml` — `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`. Nowhere else. Never hand-edit the `.xcodeproj`.

## Shipping a feature

1. Branch off current `dev`.
2. Build it. Tests first, IDs from `docs/TEST-PLAN.md`.
3. **Update every document.** `docs/FEATURES.md`, `docs/PLAN.md`,
   `docs/TEST-PLAN.md`, `docs/COMPARISON.md`, `README.md`, `CLAUDE.md` §10,
   `scaffold.sh`, `CHANGELOG.md`.
4. **Update the website.** Demo tab, feature block, comparison row, ticker.
   See `docs/WEBSITE-PLAN.md`.
5. `make lint && make test` — both green, and look at the site before calling
   it done.
6. PR into `dev`. CI green. Squash merge, delete the branch.

A feature is not "done" at step 2. It is done at step 6, with the docs and the
site updated in the same PR. Docs that lag the code are how a project ends up
with a README describing an app that no longer exists.

## Cutting a release

On `dev`:

1. Bump the version in `project.yml`.
2. Move `## Unreleased` in `CHANGELOG.md` to `## [vX.Y.Z] — YYYY-MM-DD`,
   grouped Added / Changed / Fixed / Removed.
3. Re-verify every competitor price and claim repeated in the release notes
   against `docs/COMPARISON.md`. They go stale, and these go public.
4. Run the manual release checklist at the bottom of `docs/TEST-PLAN.md` —
   the hardware and display matrix, the Camera green-light check, and the
   System stats cross-check against Activity Monitor.
5. `chore(release): v<X.Y.Z>`, push `dev`.

Then:

6. Release PR `dev` → `main`. CI green.
7. **Merge commit, not a squash.** `main` keeps the history.
8. Tag on `main`:
   ```bash
   git switch main && git pull --ff-only origin main
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   git switch dev
   ```
9. `.github/workflows/release.yml` fires on the tag: builds, signs, notarises,
   staples, and attaches `Perch-X.Y.Z.dmg` to the GitHub Release.
10. `.github/workflows/pages.yml` regenerates `appcast.xml` and deploys the
    site.

### Steps 8–10 do not work yet

Everything above step 8 runs today. The tag does not, and will not until
Phase 3.2 of `docs/PLAN.md` — `Scripts/release.sh` has never been written,
the repo holds no signing secrets, and Sparkle is not in the app. Pushing a
`v*` tag now fails on the first step of `release.yml` and publishes a Release
with nothing attached. The full gap is issue #25.

Until that closes, a release stops at step 7: version bump and changelog on
`dev`, release PR merged to `main`, and then a `build-X.Y.Z` **pre-release**
carrying the unsigned universal app from CI's `build` job. That job is
deliberately not a release — see the comment above it in `ci.yml` — and
`README.md` says the same thing to users, which is the only reason shipping an
unsigned build is acceptable at all.

## After every release

- [ ] Release page shows the `.dmg`, and it downloads
- [ ] Gatekeeper opens it on a Mac that has never run Perch — no warning
- [ ] `appcast.xml` lists the new version, and an older install actually sees
      the update
- [ ] Website is live and shows the new feature
- [ ] Homebrew cask PR opened (anything above a patch)
- [ ] `CLAUDE.md` §10 session log appended
- [ ] `git switch dev` — nobody is left sitting on `main`

## If a release goes wrong

**Do not delete or move a published tag.** People and Sparkle have already
fetched it. Ship `vX.Y.Z+1` with the fix. Yank the bad release on GitHub by
marking it pre-release and saying why in its notes.

The only exception is a release that failed to publish at all — if
notarisation failed and no artifact was ever attached, delete the tag, fix,
re-tag. Check the run first; never assume.

## Hotfixes

A production bug that cannot wait for `dev`:

```
fix/<issue>-<slug>  branched from main
        │  PR into main, CI green
        ▼
      main  ──→  tag vX.Y.Z+1  ──→  release
        │
        └──→  immediately merged back into dev
```

This is the **only** path that targets `main` in a PR without coming through
`dev`, and it still does not push to `main` directly. Merging back into `dev`
is not optional — skip it and the next release silently reverts the fix.

## Protected branch settings

On GitHub, for both `main` and `dev`:

- Require a pull request before merging
- Require status checks: `lint`, `test (macos-14)`, `test (macos-15)`
- Require branches to be up to date before merging
- Block force pushes
- Block deletions
- Include administrators — the rail is worthless if the maintainer can step
  over it at 1am
