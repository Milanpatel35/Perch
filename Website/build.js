#!/usr/bin/env node
/**
 * The site's only build step.
 *
 * It injects numbers that would otherwise go stale — the version, and the
 * repository's own counts — into `index.html` before Pages publishes it.
 *
 * Build time, not run time, and that is the whole point. The page claims
 * Perch makes no network requests and that nothing about you leaves your
 * Mac; a site that phones GitHub from the visitor's browser to render a star
 * count would be contradicting itself in the same breath (WEBSITE-PLAN §7).
 *
 * Every lookup degrades. If GitHub is rate-limiting, or there is no token, or
 * the network is down, the placeholder keeps whatever it already said and the
 * build succeeds. A marketing page must not fail to publish because a star
 * count was unavailable.
 */

import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const REPO = process.env.PERCH_REPO ?? 'Milanpatel35/Perch'

/** Reads MARKETING_VERSION out of project.yml — the one place it lives. */
async function version() {
  try {
    const yaml = await readFile(join(here, '..', 'project.yml'), 'utf8')
    return yaml.match(/MARKETING_VERSION:\s*"([^"]+)"/)?.[1] ?? null
  } catch {
    return null
  }
}

async function repository() {
  const headers = { accept: 'application/vnd.github+json' }
  if (process.env.GH_TOKEN) headers.authorization = `Bearer ${process.env.GH_TOKEN}`

  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}`, { headers })
    if (!response.ok) return null
    return await response.json()
  } catch {
    return null
  }
}

/** Replaces the text inside `<span data-gh="key">…</span>`. */
function inject(html, key, value) {
  if (value === null || value === undefined) return html
  const pattern = new RegExp(
    `(<span data-gh="${key}"[^>]*>)([\\s\\S]*?)(</span>)`,
    'g',
  )
  return html.replace(pattern, `$1${value}$3`)
}

const path = join(here, 'index.html')
let html = await readFile(path, 'utf8')

const [tag, repo] = await Promise.all([version(), repository()])

html = inject(html, 'version', tag)

// The download link, from the same single source as the version.
//
// It used to be the build tag typed into the markup by hand, which meant it
// pointed at the *previous* release for as long as nobody noticed — and
// nobody notices a link that still works, it just hands you an old app.
// Derived here, so it cannot be forgotten at release time. No network:
// `version()` reads project.yml.
if (tag) {
  html = html.replace(
    /releases\/download\/build-[\d.]+\/Perch-[\d.]+-unsigned\.zip/g,
    `releases/download/build-${tag}/Perch-${tag}-unsigned.zip`,
  )
}
html = inject(html, 'stars', repo?.stargazers_count)
html = inject(html, 'forks', repo?.forks_count)
html = inject(html, 'issues', repo?.open_issues_count)

// The count alone reads badly at both ends: "0 open issues" tells a would-be
// contributor there is nothing to do, and a bare number tells them nothing
// about whether any of it is approachable.
const issues = repo?.open_issues_count
if (issues !== undefined) {
    html = inject(
        html,
        'issuesPhrase',
        issues === 0
            ? 'no open issues right now'
            : `${issues} open issue${issues === 1 ? '' : 's'}`,
    )
}

// Shared by the home page's matrix and the seven per-competitor pages, and
// declared up here because `const` does not hoist — the matrix below is
// written before the pages are, and would otherwise reach it in its
// temporal dead zone.
const escape = (value) =>
  String(value).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])

// ---------------------------------------------------------------------
// The home page's matrix, from the same file the seven pages use.
//
// It used to be hand-written HTML sitting next to a JSON file that claimed
// to be its source. They agreed, but only because somebody kept them
// agreeing — and the first row added to one and not the other would have
// been the end of that. Adding the battery row is what found it.
// ---------------------------------------------------------------------

function matrixRows(data) {
  return data.capabilities
    .map((capability, index) => {
      const cells = data.apps
        .map((app) => {
          const value = app.values[index]
          const classes = [app.us ? 'us' : '', value === '\u2014' ? 'n' : app.us ? 'y' : '']
          const attribute = classes.filter(Boolean).join(' ')
          return `<td${attribute ? ` class="${attribute}"` : ''}>${escape(value)}</td>`
        })
        .join('')
      return `            <tr><th scope="row">${escape(capability)}</th>${cells}</tr>`
    })
    .join('\n')
}

const matrix = await comparison()
if (matrix) {
  html = html.replace(
    /(<tbody data-comparison>)[\s\S]*?(<\/tbody>)/,
    (_, open, close) => `${open}\n${matrixRows(matrix)}\n          ${close}`,
  )
}

await writeFile(path, html)

// ---------------------------------------------------------------------
// The per-competitor pages (#18, WEBSITE-PLAN §9 step 9).
//
// Generated from data/comparison.json rather than written by hand, so the
// matrix on the home page and seven separate pages cannot drift apart —
// which they would, the first time a price changed.
//
// Every page names something the competitor does better. That is not
// politeness, it is §8 rule 2: the audience for these pages can tell the
// difference between an argument and a sales sheet, and the moment one of
// these reads like a sales sheet nobody believes the rest of the site.
// ---------------------------------------------------------------------

async function comparison() {
  try {
    return JSON.parse(await readFile(join(here, 'data', 'comparison.json'), 'utf8'))
  } catch {
    return null
  }
}

function comparePage(data, app) {
  const perch = data.apps.find((a) => a.us)
  const rows = data.capabilities
    .map((capability, index) => {
      const ours = perch.values[index]
      const theirs = app.values[index]
      return `        <tr>
          <th scope="row">${escape(capability)}</th>
          <td class="us">${escape(ours)}</td>
          <td>${escape(theirs)}</td>
        </tr>`
    })
    .join('\n')

  const checked = new Date(data.checked).toLocaleDateString('en-GB', {
    day: 'numeric', month: 'long', year: 'numeric',
  })

  return `<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#f5f5f7">
<title>Perch vs ${escape(app.name)} | Perch</title>
<meta name="description" content="An honest, feature-by-feature comparison of Perch and ${escape(app.name)} — including what ${escape(app.name)} does better.">
<link rel="canonical" href="https://milanpatel35.github.io/Perch/compare-${app.id}.html">
<link rel="icon" type="image/svg+xml" href="assets/img/perch-mark.svg">
<link rel="stylesheet" href="assets/site.css">
</head>
<body>

<header>
  <div class="wrap">
    <div class="navbar">
      <a class="brand" href="index.html"><img src="assets/img/perch-mark.svg" alt="" width="28" height="28">Perch</a>
      <nav class="navlinks">
        <a href="index.html#features">Features</a>
        <a href="index.html#compare">Compare</a>
        <a href="index.html#source">Source</a>
        <a href="index.html#price">Price</a>
      </nav>
      <a class="pillbtn" href="index.html#price">Download</a>
    </div>
  </div>
</header>

<main>
<section class="sec">
  <div class="wrap">
    <p class="eyebrow">Compare</p>
    <h1>Perch and ${escape(app.name)}</h1>
    <p class="lead">
      Checked against ${escape(app.name)}'s own site on ${escape(checked)}.
      Prices move; if this page disagrees with theirs, theirs is right and
      <a href="https://github.com/Milanpatel35/Perch/issues/new">this is a bug</a>.
    </p>

    <div class="grid3">
      <div class="card">
        <h2>What ${escape(app.name)} does better</h2>
        <p>${escape(app.credit)}</p>
      </div>
      <div class="card">
        <h2>Where Perch differs</h2>
        <p>${escape(app.difference)}</p>
      </div>
      <div class="card">
        <h2>The honest summary</h2>
        <p>Perch is free and the source is public, so you can check every row of this table yourself. That is the whole argument.</p>
      </div>
    </div>

    <div class="tablecard" style="margin-top:34px">
      <div class="scroller" tabindex="0" role="region" aria-label="Perch compared with ${escape(app.name)}">
      <table>
        <thead><tr>
          <th scope="col"><span class="sr-only">Capability</span></th>
          <th scope="col" class="us">Perch</th>
          <th scope="col">${escape(app.name)}</th>
        </tr></thead>
        <tbody>
${rows}
        </tbody>
      </table>
      </div>
    </div>

    <p class="srcmeta">
      <a href="index.html#compare">All eight compared</a> ·
      ${app.site ? `<a href="${escape(app.site)}">${escape(app.name)}'s own site</a> · ` : ''}
      <a href="https://github.com/Milanpatel35/Perch/blob/dev/docs/COMPARISON.md">The long version</a>
    </p>
  </div>
</section>
</main>

</body>
</html>
`
}

const data = await comparison()
if (data) {
  const others = data.apps.filter((app) => !app.us)
  await Promise.all(
    others.map((app) =>
      writeFile(join(here, `compare-${app.id}.html`), comparePage(data, app))),
  )
  console.log(`site: wrote ${others.length} comparison pages`)
}

console.log(
  `site: version=${tag ?? 'unchanged'} ` +
    `stars=${repo?.stargazers_count ?? 'unchanged'} ` +
    `issues=${repo?.open_issues_count ?? 'unchanged'}`,
)
