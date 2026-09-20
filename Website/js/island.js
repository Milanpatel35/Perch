/**
 * The island component.
 *
 * Every competitor's site shows you a video of the notch app. This one lets
 * you use it (docs/WEBSITE-PLAN.md §0) — so the island on this page is a real
 * element with real states, not a screen recording.
 *
 * States are data, not markup. Each one is exactly what the app's own
 * `IslandActivity` carries: a title, a subtitle, something on the right while
 * collapsed, and something extra once it opens.
 */

/** @typedef {{ tint: string, title: string, subtitle: string, trailing: string, expanded: string }} IslandState */

/** @type {Record<string, IslandState>} */
export const STATES = {
    music: {
        tint: "linear-gradient(145deg,#fa709a,#fee140)",
        title: "Midnight City",
        subtitle: "M83 — Hurry Up, We're Dreaming",
        trailing: '<div class="eq"><b></b><b></b><b></b><b></b></div>',
        expanded: '<div class="bar"><i style="width:38%"></i></div>',
    },
    meet: {
        tint: "linear-gradient(145deg,#2af598,#009efd)",
        title: "Standup in 4 min",
        subtitle: "Google Meet · 6 attendees",
        trailing: '<span class="tag g">Join</span>',
        expanded: '<div class="l2">Mute, camera and leave stay up here once you are in.</div>',
    },
    shelf: {
        tint: "linear-gradient(145deg,#4facfe,#2b78e4)",
        title: "3 files held",
        subtitle: "Q3-contract.pdf, logo.svg, notes.md",
        trailing: '<span class="tag">Drop</span>',
        expanded: '<div class="l2">Drag them out anywhere. They survive app switches.</div>',
    },
    clip: {
        tint: "linear-gradient(145deg,#a770ef,#f6d365)",
        title: "Copied",
        subtitle: "github.com/Milanpatel35/Perch",
        trailing: '<span class="tag">142</span>',
        expanded: '<div class="l2">142 clips in history. Search, pin, paste.</div>',
    },
    focus: {
        tint: "linear-gradient(145deg,#f7971e,#ffd200)",
        title: "18:42 left",
        subtitle: "Deep work · session 3 of 4",
        trailing: '<span class="tag a">Focus</span>',
        expanded: '<div class="bar"><i style="width:26%"></i></div>',
    },
    batt: {
        tint: "linear-gradient(145deg,#8e9297,#c9ccd1)",
        title: "AirPods Pro",
        subtitle: "Left 82% · Right 79% · Case 44%",
        trailing: '<span class="tag">82%</span>',
        expanded: '<div class="l2">Mac, AirPods, mouse, keyboard and trackpad in one place.</div>',
    },
    cam: {
        tint: "linear-gradient(145deg,#2b2b30,#4a4a52)",
        title: "Camera",
        subtitle: "Standup starts in 40 seconds",
        trailing: '<span class="tag g">Live</span>',
        expanded:
            '<div class="l2">Fires by itself before a meeting. Nobody else builds this past a plain mirror.</div>',
    },
    sys: {
        tint: "linear-gradient(145deg,#30cfd0,#330867)",
        title: "CPU 46% · RAM 11.2 GB",
        subtitle: "Net ↓ 4.1 MB/s · 62°C · fans 2,100 rpm",
        trailing: '<span class="tag a">46%</span>',
        expanded: '<div class="bar"><i style="width:46%"></i></div>',
    },
};

const escapeHTML = (value) =>
    String(value).replace(
        /[&<>"']/g,
        (character) =>
            ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character],
    );

/**
 * Wires up the island in the hero.
 *
 * @param {{ island: HTMLElement, row: HTMLElement, tabs: HTMLElement[], live?: HTMLElement }} elements
 */
export function createIsland({ island, row, tabs, live }) {
    let current = null;

    function paint(key) {
        const state = STATES[key];
        if (!state) return;
        current = key;

        // Titles and subtitles are escaped; the trailing and expanded
        // fragments are markup this file owns. Nothing here ever renders a
        // string that came from the page or the URL.
        row.innerHTML =
            `<div class="thumb" style="background:${state.tint}"></div>` +
            `<div class="meta"><div class="l1">${escapeHTML(state.title)}</div>` +
            `<div class="l2">${escapeHTML(state.subtitle)}</div>` +
            `<div class="extra">${state.expanded}</div></div>` +
            state.trailing;

        // Announced politely rather than assertively: the island changing
        // state is information, not an interruption (WEBSITE-PLAN §7).
        if (live) live.textContent = `${state.title}. ${state.subtitle}`;
    }

    function open(isOpen) {
        island.classList.toggle("open", isOpen);
        island.setAttribute("aria-expanded", String(isOpen));
    }

    tabs.forEach((tab) => {
        tab.addEventListener("click", () => {
            tabs.forEach((other) => other.setAttribute("aria-pressed", "false"));
            tab.setAttribute("aria-pressed", "true");
            paint(tab.dataset.s);
            open(true);
        });
    });

    island.addEventListener("click", () => open(!island.classList.contains("open")));
    island.addEventListener("keydown", (event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        open(!island.classList.contains("open"));
    });

    return { paint, open, get state() { return current; } };
}
