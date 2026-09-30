# 0004: Strict CSP and no inline code

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

A **Content Security Policy (CSP)** is a header that tells the browser where a page may load code and styles from. It is one of the strongest defenses against injected code (**cross-site scripting**, XSS). A CSP only helps much if it does not allow `unsafe-inline`, and that requires a page without inline scripts, inline styles, or inline event handlers.

## Decision

- The site has no inline `<script>`, no inline event handlers (such as `onclick=`), and no `style=` attributes. It has no JavaScript at all.
- Nothing is loaded from third parties (no CDNs, web fonts, or analytics).
- `site/staticwebapp.config.json` sets a strict CSP: `default-src 'self'` and `'self'` for scripts, styles, images, fonts, and connections; `object-src 'none'`; `base-uri 'self'`; `form-action 'self'`; `frame-ancestors 'none'`; `upgrade-insecure-requests`. It has no `unsafe-inline`.
- The other security headers are set in the same file. See [security](../security.md#security-headers).

## Consequences

- Injected inline code would be blocked by the browser.
- Any future feature must follow the rules: styles go in `site/css/style.css`, scripts (if ever needed) go in separate files under `site/`.
- Adding a third-party service (such as analytics or embedded videos) would require changing the CSP, and should get its own ADR.
