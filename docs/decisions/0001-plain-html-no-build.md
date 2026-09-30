# 0001: Plain HTML and CSS, no build step

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

The site is a small personal page: a name, a short intro, and a few links. Many sites use a framework or static site generator, which needs a **build step** (a tool that turns source files into the final HTML). That adds dependencies, which need updates and can carry security problems.

## Decision

Write the site by hand as plain HTML and CSS in `site/`. No framework, no build step, no JavaScript, no package manager.

## Consequences

- The files in `site/` are exactly what gets deployed. Nothing to install or build.
- No dependencies to update and a very small attack surface.
- Easy to preview locally (see the [runbook](../runbook.md#preview)).
- Shared parts (such as the `<head>`) are repeated in `index.html` and `404.html`. That is fine for two pages. If the site grows a lot, this decision can be revisited.
