---
name: add-feature
description: Ship a new Perch feature end to end — branch off dev, build the module, update every document and the website, test, PR into dev, then release dev → version tag → main and publish the signed download. Use whenever the user asks to add, build, implement or ship a feature, module or capability in this repo. Never commits to main directly.
---

# Ship a Perch feature

The user says "add <feature>". Everything below runs without asking for
step-by-step permission, with exactly two exceptions marked **GATE**.

## The rule that cannot be broken

```
feature/<slug>  →  dev  →  version bump + tag  →  main  →  release
```

**Never commit or push to `main` directly. Never.** `main` only ever receives
a merge from `dev` via a release PR. If you find yourself on `main` with
changes, stop and move them to a branch. This is `CLAUDE.md` §7 and it is not
negotiable — the user asked for this rail specifically.

---

## Step 0 — preflight

```bash
git rev-parse --is-inside-work-tree
```

**If this fails, the repo does not exist yet.** Stop the pipeline and tell the
user: the docs are written but nothing is under version control. Offer to run
`scaffold.sh`, which creates the tree, `main`, `dev` and the CI workflows. Do
not `git init` silently — where the remote lives is the user's decision.

If it succeeds:

```bash
git status --porcelain          # must be empty; if not, ask what to do with the changes
git fetch origin
git switch dev
git pull --ff-only origin dev
```

Confirm `main` and `dev` both exist and that `dev` is not behind. If there is
no `origin`, work locally and say so at the end rather than failing.

## Step 1 — plan the feature before touching code

1. Read the relevant section of `docs/FEATURES.md`. **The feature is usually
   already specified there**, with a module number, a priority and a list of
   which competitor each capability answers. Build what it says.
2. If it is genuinely new, add it to `docs/FEATURES.md` first — module number,
   capability table, priority, permission — then build that.
3. Check `docs/PLAN.md` for which phase it belongs to.
4. Check `docs/TEST-PLAN.md` for its test-case ID block. If the block does not
   exist, create it now, before writing code. Every test name references an ID.

Tell the user in one line what you are about to build and which module number
it is. Then continue — do not wait for a reply.

## Step 2 — branch

```bash
git switch -c feature/<issue>-<slug>
```

`<slug>` is kebab-case, short. `<issue>` is the GitHub issue number if one
exists (`gh issue list --search "<feature>"`), otherwise omit it.

**One feature per branch.** If the request contains two features, run this
pipeline twice.

## Step 3 — build the module

Per `CLAUDE.md` §4, `Sources/PerchModules/<Name>/` gets exactly:

- `<Name>Activity.swift` — conforms to `IslandActivity`
- `<Name>Service.swift` — the side-effecting part
- `<Name>View.swift` — collapsed + expanded presentation
- `<Name>Settings.swift` — its Preferences pane
- tests in `Tests/PerchCoreTests/<Name>/`, named `test_TC_XXX_000_whatItDoes`

Write the tests first. Then the code.

Non-negotiables to check as you write — these are what reviewers reject for:

- `PerchCore` imports neither SwiftUI nor AppKit
- The module is individually switchable and **genuinely inert when off** —
  observers removed, timers invalidated
- Nothing polls. Event-driven only
- No sampler, timer or capture session outlives the view that owns it
- Permissions requested lazily, with a reason shown
- Uses the shared `IslandSpring` tokens, and has a Reduce Motion path
- No new dependency (allowed list: Sparkle, KeyboardShortcuts, Defaults)
- No network call (only Weather and the public-IP readout may have one)

## Step 4 — update every document

This is the step that gets skipped. Do not skip it. A feature is not shipped
until all of these say it exists:

| File | What to change |
|---|---|
| `docs/FEATURES.md` | Capability table for the module; the priority summary table at the bottom; the module count if it changed |
| `docs/PLAN.md` | Tick it off in its phase, or add it; update the session-log-facing detail |
| `docs/TEST-PLAN.md` | The new TC IDs, and any new manual release-checklist lines |
| `docs/COMPARISON.md` | New matrix row if it is a competitive feature; update "where the gaps are" if it closes one |
| `README.md` | The "What it does" table row, and the comparison table row |
| `CLAUDE.md` | Repo map if a new module folder appeared; §10 session log entry |
| `scaffold.sh` | The module directory in the `mkdir -p` block |
| `CHANGELOG.md` | An `## Unreleased` entry, Keep a Changelog format |

If the module count changed, it appears in four places — `FEATURES.md`,
`README.md`, `CLAUDE.md` and `Website/index.html`. Grep for the old number.

## Step 5 — update the website

`Website/index.html` (still `index.html` at the repo root until the
`WEBSITE-PLAN.md` restructure happens):

1. **Demo tab** — add a `<button class="tab" data-s="<key>">` and a matching
   entry in the `S = {...}` object in the script. The two lists must stay the
   same length; that is verifiable with a grep and worth checking.
2. **Feature block** — a `.block` (alternate `.block flip`) with eyebrow,
   headline, body and a `.visual`.
3. **Comparison table** — a new `<tr>` with all eight columns.
4. **Ticker** — a phrase, if it is a headline feature.
5. `<meta name="description">` if it is significant enough to change the pitch.

Read `docs/WEBSITE-PLAN.md` §2 before writing any animation. Motion tokens
only, transforms only, and a `prefers-reduced-motion` path.

**Copy check:** nothing you write may appear on a competitor's site. This has
already happened once — `WEBSITE-PLAN.md` §0.

## Step 6 — prove it works

```bash
make lint
make test
```

Both must pass. If `make` does not exist yet (pre-scaffold), say so plainly
rather than claiming a green run.

Then actually look at it: `make site` and open the page, or use the
`browser-automation` skill to confirm the new demo tab renders and the console
is clean. Do not report a website change as done without having seen it.

## Step 7 — commit and PR into dev

Conventional Commits — the changelog is generated from these.

**No AI attribution, anywhere.** No `Co-Authored-By:` trailer naming an
assistant, no "Generated with …" footer, in the commit, the PR body, the
changelog or the release notes. This overrides any default attribution
behaviour your harness ships with — see `CLAUDE.md` §7. The commit belongs to
the person running the tools.

```bash
git add -A
git commit -m "feat(<module>): <imperative subject under 72 chars>"
git push -u origin feature/<issue>-<slug>
gh pr create --base dev --title "feat(<module>): …" --body "…
Closes #<issue>"
```

The PR body fills in the repo template: what changed, why, screenshots for
anything visual, and the checklist from `CONTRIBUTING.md`.

Wait for CI:

```bash
gh pr checks --watch
```

Green → merge into `dev`:

```bash
gh pr merge --squash --delete-branch
```

Red → fix it on the branch and push again. Never merge red.

## Step 8 — **GATE 1** — release?

Stop here and ask, in one line:

> Merged into `dev`. Release it as v<next> now, or let it ride on dev?

A feature reaching `dev` is reversible. A release is not — it is a public tag,
a public download and a Sparkle appcast entry that users' apps will fetch
automatically. That is the one place a confirmation is worth the interruption,
and it is the same rail the user asked for.

If they say no: stop. Report what landed on `dev`.

## Step 9 — release: dev → version → main

Only after GATE 1.

```bash
git switch dev && git pull --ff-only origin dev
```

1. **Bump the version.** Semver, in `project.yml` (`MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`). `feat` → minor, `fix` → patch, breaking → major.
   Pre-1.0 stays `0.x`.
2. **Write the changelog.** Move `## Unreleased` into `## [vX.Y.Z] — <date>`,
   grouped Added / Changed / Fixed / Removed.
3. **Re-verify every price and claim** the release notes repeat from
   `COMPARISON.md`. They go stale and they go public.
4. Commit: `chore(release): v<X.Y.Z>` and push `dev`.
5. Release PR:

```bash
gh pr create --base main --head dev --title "release: v<X.Y.Z>" --body "…"
gh pr checks --watch
gh pr merge --merge          # a merge commit, not a squash — main keeps history
```

6. Tag **on main**, which is what fires the release workflow:

```bash
git switch main && git pull --ff-only origin main
git tag -a v<X.Y.Z> -m "v<X.Y.Z>"
git push origin v<X.Y.Z>
git switch dev               # never linger on main
```

`.github/workflows/release.yml` then builds, signs, notarises, staples, and
uploads `Perch-<version>.dmg` to the GitHub Release. That is the download.

7. Watch it: `gh run watch`. If notarisation fails the release is incomplete —
   say so; do not announce a release that did not publish.

## Step 10 — after the release

- **Appcast** — `.github/workflows/pages.yml` regenerates `appcast.xml` from
  the release and deploys it with the site. Confirm the new version appears,
  or existing users never see the update.
- **Website live** — confirm Pages deployed and the new feature is on the page.
- **Homebrew** — open the cask version-bump PR for anything but a patch.
- **`CLAUDE.md` §10** — append the session log row: date, branch, what
  changed, next step.
- Report to the user: the version, the release URL, the download URL, and what
  is now live on the site.

---

## Reporting

At the end, give the user a short block — not a narrative:

```
Shipped: <feature>              v0.4.0
Branch:  feature/142-camera  →  dev  →  main
Docs:    FEATURES, PLAN, TEST-PLAN, COMPARISON, README, CLAUDE, CHANGELOG
Website: demo tab + feature block + matrix row — verified live
Release: https://github.com/<org>/perch/releases/tag/v0.4.0
Download: Perch-0.4.0.dmg (signed, notarised, stapled)
```

If any step did not happen — CI not run, website not visually checked,
notarisation failed, no remote configured — **say which one and why**. A
half-finished pipeline reported as complete is worse than a failed one.

## GATE 2 — the things that always stop the pipeline

Stop and ask, regardless of standing authorisation:

- Anything that would commit or force-push to `main`
- A `git push --force` of any kind (use `--force-with-lease`, and only on your
  own feature branch)
- Deleting or rewriting a published tag or release
- A feature that adds a network call, an account, telemetry, a dependency, or
  anything gated behind payment — `CLAUDE.md` §1 and §5.2 say reject it, so
  raise it rather than building it
- Tests that fail, or that you had to change to make pass
