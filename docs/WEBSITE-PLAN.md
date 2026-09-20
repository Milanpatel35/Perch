# Perch — website build plan

Last updated: 20 September 2026.
Reference point: notchbay.com (fetched 20 Sep 2026), plus alcove.land and
notchnook.com for motion quality.

The current `index.html` is the v0 prototype: 693 lines, single file, one
interactive island with six tab states. This document is the plan to take it to
v1 — the site that ships on launch day.

---

## 0. The one idea

Every competitor's site shows you a **video of** the notch app. Perch's site
lets you **use** the notch app.

The whole page is built around a single island element that is real, live,
scroll-aware and clickable. You scroll, it changes state. You hover, it
expands. You drag a file onto it, it catches it. You copy something, it says
"copied". By the time a visitor reaches the download button they have already
had the product experience, in the browser, without installing anything.

That is the differentiator, it is achievable in vanilla HTML/CSS/JS, and no
competitor has done it. Everything below serves it.

### A necessary warning before you write any copy

notchbay.com's hero headline is, verbatim:

> Your MacBook notch, finally a Dynamic Island.

That is the exact string sitting in `index.html:291` today. The current
sub-headline and the "See it live" CTA are also close paraphrases of theirs.

**Rewrite all of it before this site goes public.** Perch's entire position is
"the honest, open one"; launching with a competitor's headline copied word for
word is the fastest way to lose that argument on Hacker News, and it is a
trademark/passing-off risk that a free project has no budget to defend. New
headline directions are in §8.

---

## 0.1 Structural study: notchbay.com

Fetched again 20 September 2026, this time reading **structure and
interaction only**. The rule from §0 stands and is worth restating, because
the request to "make it like theirs" will come back: we study how their page
is *built*, never what it *says*. Their words are theirs, and a free project
has no budget to defend a passing-off claim.

Their section order:

1. Fixed header — logo, features, blog, pricing, download
2. Hero — headline, two CTAs (download, and a link to a demo anchor)
3. Social proof — a Product Hunt badge
4. A mockup of the macOS menu bar
5. One-line statement of what it does
6. A grid of differentiators
7. Live activities, explained
8. Four capability blocks, each text plus an icon
9. How it works — four numbered steps
10. FAQ
11. Pricing — one tier, $9 lifetime, plus a free path
12. Final CTA over a full-width image
13. Footer, links grouped by category

**What is actually interactive:** the navigation, the CTAs, two email capture
forms and the FAQ disclosures. Everything else is static. The product is
shown as **screenshots and mockups** — there is no video and no live demo,
and the "see it live" link is an anchor to a static section further down.

### What to take

- **Repeat the download CTA.** Theirs appears in the header, the hero and the
  footer. Ours appears in the header, the hero, the price block and the
  finale, so this one is already done — but it is the right instinct and the
  mid-page gap after the feature blocks is the one place ours goes quiet.
- **Pricing before the final CTA, not as the final CTA.** Theirs sits at 11
  of 13 with a closing section after it. Ours does the same. Keep it.
- **Numbered, progressively disclosed "how it works".** Reduces install
  anxiety. Ours has it; theirs is the better length.

### What not to take

- **A long page that defers everything.** Theirs is notably long and closes
  late. Ours makes its argument — price, source, no account — above the fold,
  because that argument is the product.
- **Static mockups as the demonstration.** This is the gap §0 identified and
  it is still the gap. Their page *tells* you the notch is interactive.
  Ours lets you use it, and now also shows screenshots rendered from the
  app's own views rather than drawn in a design tool.

### Where we are ahead

Two things, and neither is an accident:

1. **The island on our page is real.** Scroll it, hover it, click it.
2. **"What it doesn't do yet".** Nobody in this category publishes their
   gaps. It is the cheapest credibility available and it costs one section.

---

## 1. Information architecture

Sections in order. Every one has a defined job and a defined interaction.

| # | Section | Job | Interaction |
|---|---|---|---|
| 1 | Hero + live Mac | Show, don't tell, in the first 3 seconds | Island auto-demos, then hands control over |
| 2 | Trust strip | Kill the "what's the catch" question immediately | Static ticker |
| 3 | **The scroll-island** | The core: 10 features, one continuous morph | Scroll-driven, pinned |
| 4 | Feature deep-dives | Detail for the 20% who want it | Per-card micro-demos |
| 5 | System stats & Camera | The two things nobody else has | Live browser-data demos |
| 6 | Comparison matrix | Win the shopping comparison | Sticky header, row highlight |
| 7 | Privacy | The second-biggest objection | Network-log visual |
| 8 | How it works | Reduce install anxiety | 4-step, scroll-revealed |
| 9 | Open source | Credibility + contributor funnel | Live GitHub numbers (build-time) |
| 10 | FAQ | Long-tail objections | Native `<details>` |
| 11 | Price | Convert | The `$0` moment |
| 12 | Finale + footer | Second CTA, SEO links | — |

Dropped from the current page: the standalone "stats" section (0 / 10 / $0)
folds into §2 and §11.

---

## 2. The motion system

One set of tokens. Every animation on the site uses them, the same way every
module in the app uses `IslandSpring`. Consistency is what reads as "polished";
variety reads as "template".

```css
:root{
  /* The island's own curve — matches the app's SwiftUI spring.
     response 0.5, damping 0.8, translated to a cubic-bezier. */
  --ease-island: cubic-bezier(.32,.72,0,1);
  --ease-out:    cubic-bezier(.16,1,.3,1);
  --ease-in-out: cubic-bezier(.65,0,.35,1);

  --t-morph: 520ms;   /* island shape change */
  --t-content: 260ms; /* content swap inside the island */
  --t-reveal: 700ms;  /* section entrance */
  --t-micro: 180ms;   /* hover, press, focus */

  --stagger: 60ms;    /* between siblings in a reveal */
}
```

Rules:

1. **The island never uses a linear or ease-in curve.** `--ease-island`, always.
2. **Content crossfades faster than the container morphs.** Text swaps at
   260ms while the shape takes 520ms — that's what makes it feel like one
   object changing rather than two elements swapping.
3. **Nothing animates on load above the fold except the island.** A page where
   everything flies in is a template. One thing moving is a product.
4. **Reveals are once-only.** `IntersectionObserver` with `unobserve()` on
   first fire. Re-animating on scroll-up is a tell that it's a website.
5. **Only `transform`, `opacity`, `filter` and `clip-path` animate.** Anything
   that triggers layout is a bug. The current `index.html` animates `width`,
   `height` and `padding` on `.island` (line 146) — that is layout thrash on
   every frame and must be rebuilt on transforms before the island gets any
   more complex. See §3.2.
6. **Reduced motion is a real path, not a disabled path.** All transforms
   become opacity crossfades, the scroll-island becomes a tab strip, the
   auto-demo does not autoplay. Same information, no movement.

---

## 3. The living island component

This is the piece of engineering the site stands on. Build it first, build it
properly, and every section afterwards is easy.

### 3.1 API

One component, used in five places on the page.

```js
const island = Island.mount('#hero-island', {
  state: 'idle',          // idle | peek | expanded
  activity: 'music',      // which module is presenting
  interactive: true,      // hover and click do things
  autoplay: true,         // cycle through activities until first user input
});

island.present('shelf', { files: 3 });  // morph to a new activity
island.peek('clipboard', 2000);         // peek, then auto-collapse
island.collapse();
```

Internally it is the same state machine the app uses:
`idle → peek → expanded → idle`, with the same priority ordering from
`CLAUDE.md` §3. Keeping the site's model identical to the app's is not
pedantry — it means the demo cannot show behaviour the app doesn't have, which
is exactly the trap every marketing site falls into.

### 3.2 The morph, done correctly

Do **not** animate `width`/`height`. Use a FLIP transform:

1. The island is a fixed-size container (`--island-w`, `--island-h` custom
   properties) with `will-change: transform`.
2. Measure the target content's natural size with the container at `scale(1)`
   and `visibility:hidden` off-screen — or cheaper, hard-code the six known
   target sizes as CSS custom properties per activity, since there are only a
   handful.
3. Animate `transform: scale(sx, sy)` on the container, and the inverse scale
   `scale(1/sx, 1/sy)` on the content wrapper, so text does not stretch.
4. Corner radius: animate `border-radius` — it's cheap and does not reflow.
5. Run content in/out on `opacity` + `translateY(4px)` at `--t-content`, with
   the outgoing content leaving 80ms before the incoming arrives.

Budget: **60fps on an M1 Air in Safari, and 60fps on a 2019 Intel MacBook in
Chrome.** If the second one drops frames, the motion is too ambitious. Profile
this before adding the next feature, not after.

### 3.3 Activity states to implement

Ten, matching the app's P0 modules in `FEATURES.md`:

| Key | Collapsed shows | Expanded shows | Live in browser? |
|---|---|---|---|
| `music` | Artwork + 4-bar visualiser | Scrubber, transport, lyrics line | Simulated |
| `shelf` | File count badge | 3 file rows, drag handles | **Real** — accepts a real drag-drop |
| `clipboard` | Clip count | Searchable list, filter as you type | **Real** — reads your actual paste |
| `focus` | `18:42` countdown | Ring progress, session dots | **Real** — a running timer |
| `calendar` | "Standup in 4m" | Join button, attendee row | Simulated |
| `meeting` | Mic + cam glyphs | Mute / camera / leave controls | Simulated, buttons respond |
| `battery` | `82%` + bolt | Mac + AirPods + mouse rows | **Real** — `navigator.getBattery()` where available |
| `hud` | Volume bar | Volume, brightness, backlight | **Real** — drag to change the bar |
| `camera` | Lens glyph | **Live webcam preview** | **Real** — `getUserMedia`, opt-in |
| `system` | CPU/RAM micro-gauge | 6-tile grid + sparklines | **Real-ish** — see §5 |

"Real" is the whole point. Six of the ten can actually run in a browser. Those
six are what make the page feel like the app instead of a screenshot of it.

---

## 4. Section 3 — the scroll-island (the centrepiece)

The single best thing you can build on this site.

### Behaviour

A tall section (roughly `10 × 100vh`). The Mac mockup **pins** to the centre of
the viewport for the whole scroll. As the user scrolls, the island morphs
through all ten activities, one per viewport-height, with the feature's copy
sliding in beside it.

The user is scrolling through the product's entire feature set while a single
object continuously transforms in front of them. It takes about 12 seconds of
scrolling and communicates more than any feature grid.

### Implementation

Preferred, where supported:

```css
@supports (animation-timeline: view()) {
  .scroll-island-track { view-timeline-name: --track; }
  .island-pin {
    position: sticky; top: 50%;
    animation: island-morph linear;
    animation-timeline: --track;
  }
}
```

Fallback (and the version to write first, since it works everywhere): a single
`IntersectionObserver` with ten sentinel `<div>`s, one per step, each at
`rootMargin: '-50% 0px -50% 0px'` so it fires when it crosses the viewport
centre. On fire, call `island.present(key)`. That is ~30 lines and it is
already smooth, because the island's own transition does the work — you are
only switching state, not driving a frame loop.

**Do not use a scroll event handler.** No `requestAnimationFrame` loop reading
`scrollY`. Both are how these pages end up janky.

### Copy panel

Beside (desktop) or below (mobile) the pinned Mac:

```
01 / 10   NOW PLAYING
Everything that's playing, right where you look.
Artwork, scrubbing, lyrics, AirPlay and the up-next queue —
in the black rectangle you already own.
                                          [ ✓ Free in Perch ]
                                          [ $19.90 in Seam  ]
```

That last pair of lines, on every single step, is the argument. Ten times in a
row the visitor reads "free here, paid there". Pull the competitor prices from
`COMPARISON.md` so there is one source of truth, and keep them accurate —
they change.

### Mobile

Pinning on mobile is where these sections break. Below 840px, drop the pin
entirely: render ten stacked cards, each with its own small island that plays
its morph once when it scrolls into view. Same content, no pinning, no bugs.

---

## 5. Section 5 — the two we own

`FEATURES.md` modules 9 and 10. These get their own section because no
competitor has either, which means this is the only part of the page that is
not a comparison — it is a claim nobody can answer.

### System stats — a live demo with honest limits

The browser cannot read the user's real CPU. Do not fake a number and imply it
is theirs; that is the kind of thing that gets caught and quoted.

Instead, make it a **real-but-local** demo:

- Run an actual load loop in a Web Worker for 3 seconds on a button press
  ("Give it something to chew on"), and graph `performance.now()` frame timing
  and `performance.memory` where exposed. Those *are* real numbers from the
  visitor's machine.
- Label the rest as a demo: `deviceMemory`, `hardwareConcurrency` and
  `navigator.connection` are readable and genuinely theirs — show those with a
  "read from your browser" tag.
- Sparklines: 60 points, SVG `<polyline>`, updated at 1Hz, and the
  interval **clears when the section scrolls out of view**. Demonstrating the
  app's own performance discipline on the site that advertises it is a nice
  touch, and it stops the page burning battery in a background tab.

Caption it plainly: *"In the app this is your real CPU, GPU, memory, disk,
network, temperature and fans. Here it's what a web page is allowed to see."*
Honesty is on-brand and costs nothing.

### Camera — the highest-conversion element on the page

A button: **"Turn on your camera"**. On click, `getUserMedia({video:true})`,
and the visitor's own face appears inside the island mockup, masked to the
notch shape, with the mirror/shape/size controls live.

Seeing your own face inside a notch you are about to install is as close to a
trial as a website gets.

Non-negotiables, or this becomes the worst part of the page instead of the best:

- Never auto-request. A button, always, with the permission explained *before*
  the browser prompt fires.
- A permanent, visible **Stop camera** control.
- `stream.getTracks().forEach(t => t.stop())` on stop, on section-exit, on
  `visibilitychange`, and on `pagehide`. The green light must go off.
- No canvas capture, no upload, no analytics event. State it on the page.
- Full fallback for denial: a looping muted `<video>` of a stock clip, plus
  "No problem — here's what it looks like."

---

## 6. Section 6 — the comparison matrix

This is what notchbay.com does well: a checkable matrix rather than adjectives.
Keep that, and beat it on completeness.

- Eight columns: Perch + the seven, exactly as `COMPARISON.md`.
- The Perch column is sticky-left on mobile and tinted; the header row is
  sticky-top on desktop.
- ~24 rows, grouped: Price & licence / Core modules / Advanced / Platform.
- Hovering a row dims the other rows. Small touch, makes a wide table readable.
- Every cell that says "no" for a competitor gets a `title` with a one-line
  source note, and the whole table is generated at build time from a single
  `data/comparison.json` — which `COMPARISON.md` is also generated from. One
  source, two outputs, no drift.
- A dated line under the table: *"Prices and features checked 20 September
  2026. They change — check the vendor's own page before buying."* Keep this
  accurate. Being the project that quotes competitors fairly is worth more than
  any individual row.

---

## 7. Technical plan

### Stack

**Stay with a static hand-written site. No framework.**

| | |
|---|---|
| Markup | Plain HTML, one file per page |
| Styles | One `site.css`, custom properties, no preprocessor |
| Script | Vanilla ES modules, no bundler |
| Fonts | Inter + JetBrains Mono, self-hosted `.woff2`, `font-display:swap` |
| Icons | Inline SVG sprite |
| Build | A 40-line Node script for the matrix and GitHub numbers |
| Host | GitHub Pages from `Website/`, custom domain, `make site` to serve locally |

Reasons: a marketing page for an app whose selling point is "no Electron, no
bloat" should not ship 180KB of React. It also keeps the contributor barrier at
zero — anyone who can write HTML can fix a typo.

### File layout

Replaces the single `index.html` at the repo root, and matches the `Website/`
directory that `scaffold.sh` already creates.

```
Website/
├── index.html
├── compare.html          # SEO: "perch vs notchnook" etc, one per competitor
├── privacy.html
├── press/                # Kit: logos, screenshots, a 30s loop
├── assets/
│   ├── site.css
│   ├── fonts/
│   ├── img/
│   └── video/
├── js/
│   ├── island.js         # §3 — the component
│   ├── scroll.js         # §4 — sentinels and reveals
│   ├── demos/
│   │   ├── camera.js
│   │   ├── system.js
│   │   ├── clipboard.js
│   │   └── shelf.js
│   └── main.js
├── data/
│   └── comparison.json   # single source for the matrix + COMPARISON.md
└── build.js
```

### Performance budget

Hard numbers. Fail the build if exceeded.

| Metric | Budget |
|---|---|
| HTML + CSS + JS, gzipped, above the fold | < 60KB |
| Total page weight, no video | < 300KB |
| LCP | < 1.2s on a simulated 4G connection |
| CLS | 0. The island is absolutely positioned; nothing shifts |
| INP | < 100ms |
| Lighthouse (all four categories) | ≥ 98 |
| Long tasks during the scroll-island | 0 over 50ms |

Video, if any, is lazy, muted, `playsinline`, `preload="none"`, poster-first,
and never autoplays above the fold.

### Accessibility

Non-negotiable, and doubly so for a project whose README promises a VoiceOver
pass in the app.

- The scroll-island section carries the full feature text in the DOM at all
  times, not injected on scroll. A screen reader gets all ten features by
  reading top to bottom.
- Island state changes announce via a polite `aria-live` region.
- Every demo control is a real `<button>`, keyboard reachable, with a visible
  focus ring (the existing `:focus-visible` rule at `index.html:99` is good —
  keep it).
- `prefers-reduced-motion` path per §2 rule 6.
- Colour contrast ≥ 4.5:1 in both themes. Check `--sub` (`#86868b`) on
  `--card` — at small sizes that is marginal and probably needs to darken.
- Run `accessibility-scan` against the built page before launch, and again
  before any redesign.

### SEO

- One `compare.html?vs=` page per competitor — seven pages targeting
  "perch vs notchnook", "free notchnook alternative", "boring notch
  alternative", "free dynamic island for mac". This is where the traffic
  actually is.
- `SoftwareApplication` JSON-LD with `"price": "0"`. The $0 shows up in the
  search result.
- `FAQPage` JSON-LD from the FAQ section.
- OG image: the island mid-morph, 1200×630, generated at build time.
- Real `<title>` and description per page, sitemap, `robots.txt`.

---

## 8. Copy direction

Replace the borrowed hero (§0). Perch's angle is not "finally a Dynamic
Island" — that is NotchBay's angle and it is already taken. Perch's angle is
**everyone else is charging you for this**.

Candidates:

- *"The notch apps cost $25. This one is the source code."*
- *"Eighteen modules. Zero dollars. Read the code."*
- *"Your notch, fully employed."*
- *"Free, forever, and you can prove it."*

Tone rules for the whole site:

1. **Name the prices.** Vague "others charge" is weak; "$25, or $3/month"
   is an argument. Keep them accurate and dated.
2. **Never rubbish the competitors.** Boring Notch is a good app by people
   doing the same thing for free. Alcove's animation is better than yours will
   be at launch. Saying so is credibility, not weakness, and the audience for
   this page can tell the difference.
3. **No adjectives you cannot demonstrate.** "Smooth" is worthless next to an
   island the visitor can actually drag.
4. **Say what it doesn't do.** No voice typing at 1.0. A "not yet" section
   converts better than silence, because it is the sentence nobody else writes.

---

## 9. Build order

Each step is shippable. Do not start the next one until the current one is at
60fps on the slowest machine you own.

| Step | Work | Days |
|---|---|---|
| 1 | Extract `index.html` into the `Website/` layout; self-host fonts; no behaviour change | 1 |
| 2 | Rewrite `.island` on transforms (§3.2). Ship `island.js` with the ten states | 3 |
| 3 | Hero: auto-demo, then hand over to hover/click | 1 |
| 4 | The scroll-island, `IntersectionObserver` version, desktop | 3 |
| 5 | Mobile stacked-cards fallback + reduced-motion path | 2 |
| 6 | Live demos: camera, then clipboard, then shelf drag-drop, then system | 4 |
| 7 | `comparison.json` + build script + matrix + regenerate `COMPARISON.md` | 2 |
| 8 | Privacy, how-it-works, open-source, FAQ, price, footer | 2 |
| 9 | Seven `compare.html` pages, JSON-LD, OG images, sitemap | 2 | **Pages done** (#18), generated from `data/comparison.json`. JSON-LD, OG images per page and the sitemap are still outstanding. |
| 10 | New copy pass (§8), proofread, every price re-verified | 1 |
| 11 | Perf + a11y pass against the §7 budgets; fix until green | 2 |
| 12 | Press kit, 30-second loop, domain, deploy | 1 |

**24 working days.** Start it during app stage 2.3 — a launch-day scramble
produces a site that looks like a launch-day scramble, and this site is doing
more work than most.

## 10. Definition of done

- [ ] No copy on the page appears on any competitor's site
- [ ] Every competitor price on the page matches `COMPARISON.md` and is dated
- [ ] Island holds 60fps on a 2019 Intel MacBook in Chrome
- [ ] Camera demo releases the device — green light verifiably off — on stop,
      scroll-out, tab-hide and unload
- [ ] All ten features readable by a screen reader with no scrolling required
- [ ] `prefers-reduced-motion: reduce` has zero transforms anywhere
- [ ] Lighthouse ≥ 98 on all four, throttled, on a cold load
- [ ] Zero third-party requests. No fonts CDN, no analytics, no embeds. The
      privacy section is only true if the page itself obeys it
- [ ] Works with JavaScript disabled: all content readable, island static
- [ ] The `$0` is visible without scrolling on a 13" laptop
