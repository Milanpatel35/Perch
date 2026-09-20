# Contributing to Perch

Thanks for being here. Perch only works as a free app if people other than the
maintainers keep it alive, so contributions of every size are wanted — a typo
fix in the README is a real contribution.

Everyone taking part agrees to the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Before you write code

- **Open an issue first** for anything beyond a small fix. It saves you from
  building something that gets rejected on architecture grounds.
- Check [docs/FEATURES.md](docs/FEATURES.md) first — it lists all eighteen
  modules and, for each one, every capability we intend to ship and which
  competitor it is answering. Most feature ideas are already in there with a
  priority attached.
- Check [docs/PLAN.md](docs/PLAN.md) — if your idea is already in a later
  phase, say so in the issue and we can pull it forward.
- Check [docs/COMPARISON.md](docs/COMPARISON.md) — we care whether a feature
  closes a gap with the paid field or is genuinely new.
- New dependencies need agreement in an issue before the PR. The allowed list
  today is Sparkle, KeyboardShortcuts and Defaults.

`good first issue` and `help wanted` labels are kept stocked. Comment on an
issue to claim it; if it goes quiet for two weeks it goes back in the pool.

## Setting up

```bash
git clone https://github.com/<your-username>/perch.git
cd perch
git remote add upstream https://github.com/<org>/perch.git
make bootstrap        # installs xcodegen, swiftlint, swift-format; generates the project
make test             # confirm a green baseline before you change anything
```

Requirements: macOS 13.0+, Xcode 16+, Swift 6.

`Perch.xcodeproj` is generated and gitignored. Edit `project.yml`, then rerun
`make bootstrap`. Never commit the `.xcodeproj`.

## Branches

| Branch | Purpose |
|---|---|
| `main` | Released code only. Protected. Tags are cut from here. |
| `dev` | Integration branch. **All PRs target `dev`.** |
| `feature/<issue>-<slug>` | New functionality |
| `fix/<issue>-<slug>` | Bug fixes |
| `docs/<slug>` | Documentation only |
| `chore/<slug>` | Build, CI, tooling |

```bash
git checkout dev
git pull upstream dev
git checkout -b feature/142-clipboard-pinning
```

Nobody pushes directly to `main` or `dev`. The full chain — how a branch
becomes a signed download — is [RELEASE.md](RELEASE.md).

**A PR is not complete without the docs and the website.** A feature that
changes what Perch does also changes `docs/FEATURES.md`, `README.md`, the
comparison tables and the marketing page. Ship them in the same PR; a reviewer
will ask for them otherwise. `RELEASE.md` § "Shipping a feature" has the list.

## Commits

[Conventional Commits](https://www.conventionalcommits.org). The release
changelog is generated from them, so the prefix matters.

```
feat(clipboard): pin items to the top of history
fix(geometry): correct notch inset on 16-inch M4 Pro
perf(island): stop the media poll timer when collapsed
docs(readme): add Homebrew install step
test(shelf): cover multi-file drop (TC-SHF-007)
chore(ci): cache SPM dependencies
```

Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `chore`, `build`,
`ci`. Breaking changes get a `!` after the scope and a `BREAKING CHANGE:`
footer.

Keep the subject under 72 characters, imperative mood, no trailing period.

### No tool attribution

Commit messages, PR descriptions, changelog entries and release notes credit
**people**, not tools. Do not add `Co-Authored-By:` trailers naming an AI
assistant, "Generated with …" footers, or any equivalent — and do not list an
assistant in `CONTRIBUTORS`, `AUTHORS`, the README or the site footer.

Use whatever tools you like, including AI ones. The commit is still yours: you
chose the approach, you reviewed the diff, and you are the one answering the
bug report. Sign it accordingly.

`Co-Authored-By:` for a **human** pair is welcome and encouraged.

## Pull requests

Before you open one:

```bash
make lint             # must pass
make test             # must pass
```

Then:

1. Rebase on the latest `dev` — we use a linear history, no merge commits from
   your branch.
2. Push and open the PR against `dev`.
3. Fill in the template. Screenshots or a screen recording are effectively
   required for anything visual.
4. Link the issue with `Closes #142`.

**A PR is reviewable when it is one thing.** A clipboard feature and a
refactor of the geometry layer are two PRs.

CI runs lint, unit tests, snapshot tests and a debug build on macOS 14 and 15
runners. All four must be green.

### What reviewers check

- Does `PerchCore` still avoid importing SwiftUI and AppKit?
- Is the new module individually switchable, and is it genuinely inert when off?
- Does anything poll? Idle CPU must stay near 0%.
- Are new permissions requested lazily, with a reason shown to the user?
- Does it behave correctly with two displays and with Reduce Motion on?
- Are the test case IDs from `docs/TEST-PLAN.md` referenced in the test names?
- Does any sampler, timer or capture session outlive the view that owns it?
  This is the usual failure in the Camera and System stats modules.
- Does it add a network request? Only Weather and the public-IP readout may
  ever have one, both off by default. See `CLAUDE.md` §5.2.
- If it touches the website: is any copy on the page also on a competitor's
  page? See `docs/WEBSITE-PLAN.md` §0.

## Full push/pull walkthrough

```bash
# 1. Fork on GitHub, then clone your fork
git clone https://github.com/<your-username>/perch.git
cd perch
git remote add upstream https://github.com/<org>/perch.git

# 2. Start from fresh dev
git fetch upstream
git checkout dev
git reset --hard upstream/dev

# 3. Branch
git checkout -b fix/210-airpods-battery-stale

# 4. Work, then stage and commit
git add Sources/PerchModules/Battery
git commit -m "fix(battery): refresh AirPods level on reconnect"

# 5. Keep up with dev while you work
git fetch upstream
git rebase upstream/dev

# 6. Push
git push -u origin fix/210-airpods-battery-stale

# 7. Open the PR against <org>/perch:dev on GitHub

# 8. After review feedback
git add -A
git commit --fixup HEAD
git rebase -i --autosquash upstream/dev
git push --force-with-lease
```

Use `--force-with-lease`, never bare `--force`.

## Reporting bugs

Include, always:

- macOS version and Mac model (`Apple menu → About This Mac`)
- Perch version
- Display setup — built-in only, external, mirrored, arrangement
- Which modules are enabled
- Steps to reproduce, and a screen recording if it is visual

Notch geometry and multi-display bugs are the most valuable reports we get and
the hardest for us to reproduce. Detail is appreciated.

## Security

Do not open a public issue for a security problem. Email
`security@<domain>` instead. See [SECURITY.md](SECURITY.md).

## Translations

Localisation files live in `Resources/<lang>.lproj/Localizable.strings`. Copy
`en.lproj`, translate the values only, and open a PR titled
`feat(i18n): add <language>`. Keep the keys identical.

## Licence

By contributing you agree your work is licensed under the MIT Licence, the same
as the rest of the project.
