# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-page marketing/landing site for **Ability and Empowerment Services**, a
person-centered mental health practice in Baltimore, MD. The entire site is one
self-contained file — there is no framework, no build step, and no package manager.

## Architecture

**Everything lives in `index.html` (~4,900 lines).** Markup, the full CSS design
system, and all JavaScript are inline in that one file. There is no bundler and
nothing to compile — open `index.html` in a browser to view the site. Edits are
made directly to `index.html`.

Three inline `<script>` blocks (search for `<script>` without `src`):
- **Intro overlay** (~line 2929): gates a 6.2s intro animation; skipped for
  repeat visitors via `sessionStorage` key `intro_seen`.
- **Main animation runtime** (~line 4039): waits for the deferred CDN libraries,
  then wires up scroll behavior.
- A third trailing block (~line 4904).

**External libraries** are loaded from CDN with `defer` (no local copies):
- `lenis` — smooth scrolling
- `gsap` + `ScrollTrigger` — scroll-driven animation

The main script registers `ScrollTrigger`, routes Lenis through GSAP's ticker so
pinning stays in sync, and gates all motion behind
`prefers-reduced-motion`. Scroll reveals work by toggling an `in-view` class:
`[data-split]` elements get word-by-word reveals, `.fade-up` elements fade in.
Reveals are bidirectional (enter/leave/enterBack/leaveBack) and elements already
in the viewport at init are revealed immediately to avoid above-the-fold content
being stuck invisible — see `isInOrAboveViewport()`. Recent git history shows
this reveal logic has been a repeated source of "stuck invisible" bugs; preserve
the immediate-reveal-if-in-viewport guard and the `end: 'bottom top'` exit timing
when touching it.

### CSS design system

The `<style>` block opens with a `:root` token layer that the whole site builds
on — edit tokens, not scattered values:
- **Color ramps**: `--blue-*` (primary, derived from the logo blue `#3060B0`),
  `--green-*` (secondary, from the logo green `#80E050`), `--cream-*` (warm
  background), `--ink-*` (near-black text), plus accents `--rust`, `--amber`,
  `--plum`. The brand palette is derived from `images/image-abiliti/logo.png`;
  a few dark-section glows / the hand-underline SVG use hardcoded `rgba()`/hex
  versions of these colors rather than the tokens, so grep the literal values if
  you re-tune the palette.
- **Type scale**: `--t-11` … `--t-240` (rem steps). **Spacing**: `--s-1` … `--s-12`.
- **Easings**: `--ease-out`, `--ease-in-out`, `--ease-power`. **Radii**: `--r-sm` … `--r-full`.
- Layout max width: `--maxw` (1360px); `.container` is the standard centered wrapper.

Fonts (Google Fonts): **Fraunces** (display serif, used with variable-font
`font-variation-settings` for opsz/SOFT/WONK), **Inter** (body), **JetBrains
Mono** (eyebrows/labels). The visual identity leans on a library of decorative
"ornament" classes — `.eyebrow`, `.stamp`, `.sticker`, `.roman-ghost`,
`.bracket`, `.hand-underline`, `.drop-cap`, `.marginalia`, `.grain`, etc. Reuse
these rather than inventing new decorative styles.

## Media optimization pipeline

Source images live under `images/`, and decorative videos at the repo root
(`*.mp4`). Two **non-destructive** PowerShell scripts manage optimized variants;
originals are never modified. This pipeline is optional tooling — `index.html`
currently references original `.jpg`/`.png` assets directly.

```powershell
# Generate optimized media (webp/avif derivatives, opt.mp4/webm, posters).
# Requires ffmpeg (+ optional cwebp, avifenc) on PATH. Idempotent.
pwsh ./optimize-media.ps1            # everything
pwsh ./optimize-media.ps1 -DryRun    # preview only
pwsh ./optimize-media.ps1 -Images    # or -Videos, -Force

# Rewrite index.html <img>/<video> tags to use the optimized variants.
# Makes a timestamped index.html backup first; only rewrites tags whose
# optimized siblings actually exist on disk.
pwsh ./rewrite-html.ps1
pwsh ./rewrite-html.ps1 -DryRun
```

See `optimize-media.README.md` for full details (written in French), including
the `<picture>`/`<video>` markup patterns to wire generated files in by hand.

## Conventions

- All copy and ornament content is hand-authored in `index.html`; there is no
  CMS or data layer. Site metadata (address, phone, hours) is duplicated in the
  `MedicalBusiness` JSON-LD block in `<head>` and in the visible markup — keep
  them in sync.
- `*.backup-*` files (created by `rewrite-html.ps1`) and generated media are not
  meant to be committed; the originals are the source of truth.
