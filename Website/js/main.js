/**
 * Page wiring.
 *
 * Vanilla ES modules, no bundler (docs/WEBSITE-PLAN.md §7). Everything here
 * is progressive: the page reads and converts perfectly well with this file
 * blocked, which is the test a marketing site for an offline-first app ought
 * to pass.
 */

import { createIsland } from "./island.js";

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function setUpIsland() {
    const island = document.getElementById("island");
    const row = document.getElementById("row");
    if (!island || !row) return;

    const controller = createIsland({
        island,
        row,
        tabs: Array.from(document.querySelectorAll(".tab")),
        live: document.getElementById("island-live"),
    });

    controller.paint("music");

    // The hero demonstrates itself once, then hands over. With Reduce Motion
    // on it simply starts open — the information, without the performance.
    if (prefersReducedMotion) {
        controller.open(true);
    } else {
        window.setTimeout(() => controller.open(true), 700);
    }
}

function setUpTicker() {
    const ticker = document.getElementById("ticker");
    // Doubled so the loop has somewhere to scroll to. Skipped entirely under
    // Reduce Motion, where the CSS holds it still and a second copy would
    // just be the same words twice.
    if (ticker && !prefersReducedMotion) ticker.innerHTML += ticker.innerHTML;
}

function setUpCopyButtons() {
    document.querySelectorAll("[data-copy]").forEach((button) => {
        button.addEventListener("click", async () => {
            const original = button.textContent;
            try {
                await navigator.clipboard.writeText(button.dataset.copy);
                button.textContent = "Copied";
            } catch {
                // Clipboard access is refused in plenty of ordinary
                // situations — an insecure origin, a locked-down browser.
                // Tell the visitor what to press instead of failing silently.
                button.textContent = "Press ⌘C";
            }
            window.setTimeout(() => {
                button.textContent = original;
            }, 1500);
        });
    });
}

setUpIsland();
setUpTicker();
setUpCopyButtons();
