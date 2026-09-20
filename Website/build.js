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

await writeFile(path, html)

console.log(
  `site: version=${tag ?? 'unchanged'} ` +
    `stars=${repo?.stargazers_count ?? 'unchanged'} ` +
    `issues=${repo?.open_issues_count ?? 'unchanged'}`,
)
