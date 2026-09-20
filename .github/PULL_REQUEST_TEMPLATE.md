## What this changes

<!-- One or two sentences. -->

Closes #

## Type

- [ ] Feature
- [ ] Bug fix
- [ ] Performance
- [ ] Refactor
- [ ] Docs
- [ ] Build / CI

## Screenshots or recording

<!-- Required for anything visual. Before and after if you changed existing UI. -->

## Checklist

- [ ] Targets `dev`, not `main`
- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] Tests reference the case IDs from `docs/TEST-PLAN.md`
- [ ] `PerchCore` still imports neither SwiftUI nor AppKit
- [ ] New module is individually switchable and inert when off
- [ ] Nothing polls; idle CPU unchanged
- [ ] No sampler, timer or capture session outlives the view that owns it
- [ ] No new network request (Weather and the public-IP readout are the only
      two permitted, both off by default — see CLAUDE.md §5.2)
- [ ] Any new permission is requested lazily with a reason shown
- [ ] Checked with a second display attached
- [ ] Checked with Reduce Motion on
- [ ] No new dependency (or it was agreed in an issue first)

## Notes for reviewers

<!-- Anything you are unsure about, or want a second opinion on. -->
