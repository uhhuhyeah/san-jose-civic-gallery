# Atlas: the design system

Atlas is the design system the public-facing pages run on. It replaces the
earlier `newspaper-shell` styling and unifies the homepage (Pulse), matter
detail and index, meeting detail and index, glossary, and data-health pages.

This doc explains what Atlas is, the decisions behind it, and how to add to it
without breaking the system.

## What Atlas is — and what it isn't

**Atlas** is the *internal* name of the design system: the CSS bundle, the
shared partials, the helper module, the typography stack, the color tokens, the
component vocabulary. It is what contributors talk about when they discuss the
visual layer.

**Pulse** is the *user-facing* name of the homepage section. The treemap of
themes on the homepage is the visualisation of the Pulse — it is not called the
Atlas in user copy. Keep the two separate when writing copy: residents see
"Pulse," contributors read "Atlas" in the code.

The system replaced the previous newspaper-shell design and lives alongside the
broader Rails app. Non-Atlas pages still work — the system is opt-in per page,
not a global override.

## Design principles

Five ideas anchor the system. Future changes should be able to point at one of
these.

1. **Discovery is spatial, not linear.** The Pulse homepage is a treemap rather
   than a list of links so the most-attended theme is *visibly* the biggest
   thing on the page. The matter and meeting pages use a numbered "papers" or
   "agenda" pattern that compresses scanning to the leftmost column.
2. **Serif is voice, sans is data.** Display headings, body copy, editorial
   flourishes, and AI-generated prose use Source Serif 4 (roman — no italic in
   this skin). Numerals at every size, UI labels, and form controls use Inter
   Tight with `font-variant-numeric: tabular-nums`. Codes, dates, and
   meta-strings use JetBrains Mono. A reader should be able to tell at a glance
   what's editorial and what's data.
3. **One accent, carried by flag gold.** San José flag gold lifted for dark
   backgrounds (`#ffb733`, vivid `--atlas-accent` for display/fills; `#e6a64b`,
   `--atlas-accent-deep` for body-size text) is the single accent — used for
   brand mark, primary links, left rules on important cards, editorial em
   flourishes, and the "heating up" signal. Slate (`--atlas-down`) marks
   downward trends; there is deliberately no red/green pair, so trend reading
   never depends on color-vision semantics alone.
4. **Dark navy paper, not white.** Background is `#0a0f1a` — very dark navy,
   not pure black, easier on the eyes. Tiles and date plates sit on a raised
   `--atlas-paper-deep` (`#111826`); hairline `--atlas-rule` (`#283142`) borders
   and 1px grid gaps read as a broadsheet plate. No dot-grain, no contour
   texture, no sepia.
5. **Restrained editorial flourish.** One roman em per heading (serif bold in
   accent gold — no italic), one drop-cap shape (a serif chip prefix `◇` on
   summary labels), one numbered scheme (`01`, `02`, `03`). Add a flourish only
   when it earns its place; pull one when adding another.

## Type system

Three families, self-hosted as variable WOFF2 fonts under `app/assets/fonts/`.
The `@font-face` declarations live at the top of `atlas.css` with
unicode-range subsetting (latin, latin-ext, vietnamese — matching Source
Serif 4's coverage), so browsers fetch only the subsets they actually render.

| Family | Role | Notes |
|---|---|---|
| Source Serif 4 | Display + editorial em flourishes | Variable font, `font-weight: 400 700`. Display weight 400 for h1/h2; `.atlas-em` is roman (not italic), weight 700, in `--atlas-accent-deep`; section-head `h2 .em` overrides to vivid `--atlas-accent`. Replaces the prior Fraunces stack (the Fraunces woff2 files are still vendored but unreferenced — remove in a separate cleanup if desired). |
| Inter Tight | UI sans, all numerals | `font-variant-numeric: tabular-nums` everywhere a number renders. Weight 400-500. The night prototype loads plain "Inter"; the repo keeps Inter Tight (near-identical) to avoid a fourth family. |
| JetBrains Mono | Codes, dates, meta | Used for matter codes (`CC 25-012`), monogram chips, breadcrumbs, mono-caps labels. |

Type tokens are defined as CSS custom properties:

```
--atlas-serif: "Source Serif 4", "Iowan Old Style", Georgia, serif;
--atlas-sans:  "Inter Tight", ui-sans-serif, system-ui, sans-serif;
--atlas-mono:  "JetBrains Mono", ui-monospace, "SFMono-Regular", monospace;
```

Fonts ship with `font-display: swap` so a fallback renders immediately and
swaps in once the variable font loads. Cold-load weight for the latin-only
path is approximately:

| Subset                                | Bytes  |
|---------------------------------------|--------|
| `source-serif-4-roman-latin.woff2`    | 119 KB |
| `inter-tight-roman-latin.woff2`       | 45 KB  |
| `jbm-roman-latin.woff2`               | 31 KB  |
| **Total (latin only, no extended)**   | **~195 KB** |

The serif is roman-only in this skin (no italic fetch), so every Atlas page
lands near ~195 KB rather than pulling a separate italic file.

There are no `<link rel="preload">` hints for the font subsets today — the
browser discovers them from the `@font-face` rules in `atlas.css`. If
first-paint feels slow, preloading the latin subsets in
`_atlas_topbar`'s `content_for :head` block is the lever to reach for.

## Color tokens

All colors live as CSS custom properties on `:root` so they're inert until used.
The full set:

| Token | Hex | Use |
|---|---|---|
| `--atlas-paper` | `#0a0f1a` | Page background, very dark navy (not pure black) |
| `--atlas-paper-deep` | `#111826` | Raised/recessed surfaces: facts strip, search lozenge, tile hover |
| `--atlas-ink` | `#eef1f5` | Primary text, soft off-white |
| `--atlas-ink-soft` | `#c2c9d3` | Body copy / secondary text |
| `--atlas-ink-mute` | `#8b95a4` | Mono-caps labels, eyebrows, tertiary text |
| `--atlas-rule` | `#283142` | Hairline rules, card borders, 1px grid gaps |
| `--atlas-rule-strong` | `#eef1f5` | Masthead + section-head rules (match ink) |
| `--atlas-accent` | `#ffb733` | San José flag gold lifted for dark — display/fills, h2 em, hot sparklines |
| `--atlas-accent-deep` | `#e6a64b` | Text-safe gold for body-size accent text, links, left rules |
| `--atlas-down` | `#7d93ad` | Cool slate for downward trends (no red/green) |
| `--atlas-oxblood` | alias → `--atlas-accent` | Legacy alias kept for backward compat; new code should use `--atlas-accent` |
| `--atlas-oxblood-deep` | alias → `--atlas-accent-deep` | Legacy alias; prefer `--atlas-accent-deep` |
| `--atlas-slate` | alias → `--atlas-down` | Legacy alias; prefer `--atlas-down` |

The whole palette is one accent (flag gold, in two steps for display vs.
text), one downward-trend slate, and grayscale on dark navy. The old
`--atlas-heat*` / `--atlas-sage` / `--atlas-amber` / `--atlas-paper-edge`
tokens were removed in the night refresh — their references were remapped
onto the accent/ink/rule vocabulary. Anything beyond this set requires a
justification — the strength of the system is its narrow vocabulary.

## Component vocabulary

The shared partials live under `app/views/public/shared/_atlas_*.html.erb` and
each renders one Atlas primitive.

| Partial | Use |
|---|---|
| `_atlas_topbar` | Brand wordmark + command-search + primary nav. Single-row masthead with a 2px `--atlas-rule-strong` bottom border. |
| `_atlas_footer` | Mirror disclaimer + nav. |
| `_atlas_section_heading` | Three-column `<title> + <em> + <rule> + <label>` pattern with a `--atlas-rule-strong` bottom border. Use this in place of bare `<h2>` whenever a section starts. |
| `_atlas_date_plate` | Mono date plate on `--atlas-paper-deep` with a serif-bold day number. Four sizes (`:xs`, `:sm`, `:md`, `:lg`). Pass a Date and optional `href:` to make it a link. |
| `_atlas_theme_tile` | The Pulse grid tile — square corners, 1px `--atlas-rule` border on a 1px-gap hairline grid. Sized (`:xl`, `:l`, `:m`, `:s`), trend-tinted (`:up`, `:hot`, `:flat`, `:down`), optionally with a sparkline. Reusable in any sidebar context. |
| `_atlas_body_tile` | Same square shape as the theme tile but with body data (name + acronym chip + count). Used on the meeting page sidebar. |
| `_atlas_summary_card` | Paper-on-paper AI summary card with the accent-deep left rule. Takes summary text, optional key-points list, optional limitations list, optional draft-status note, and the verbatim AI disclaimer. |
| `_atlas_facts_strip` | Horizontal 6-cell facts header used on matter and meeting detail. Takes an array of `{ dt:, dd:, class:, href: }`. |

Helpers (`app/helpers/atlas_helper.rb`):

- `atlas_sparkline_svg(series, aria_label:)` — inline SVG path from a series of
  numbers, currentColor stroke. Renders nil for blank / single-point input.
- `atlas_trend_for(stat)` — maps a `Public::ThemePulse::ThemeStat` to one of
  `:hot`, `:up`, `:flat`, `:down`.
- `atlas_trend_label(stat)` — pill text matching the trend variant.

Service objects:

- `Public::AgendaItemClassifier` — tags each `Civic::EventItem` on a meeting
  agenda as `:substantive`, `:section`, or `:notice` from existing columns.
  See `app/services/public/agenda_item_classifier.rb`.

## CSS architecture

One bundle: `app/assets/stylesheets/atlas.css`. Loaded only on opt-in pages
via `content_for :head` (see "Adding a new page" below) so the existing global
`application.css` is unaffected on non-Atlas pages.

**Scoping:** every Atlas rule sits under a `.atlas-shell` body class. The body
class is set by each Atlas view via `content_for :body_class, "atlas-shell"`.
Existing pages don't set this class, so Atlas styles never fire there. This
isolation is the reason both stylesheets can coexist on the same page without
collision.

**Naming:** components use `.atlas-<component>-<part>` (e.g. `.atlas-summary`,
`.atlas-summary-head`, `.atlas-summary-label`). Variants use BEM-style
`--modifier` (e.g. `.atlas-tile--xl`, `.atlas-chip--sage`).

**File organization:** `atlas.css` is one big file organized into commented
sections in this order:

1. Fonts (`@font-face` declarations)
2. Tokens (`:root` custom properties)
3. Base (`.atlas-shell` body styles, type defaults)
4. Focus + skip-link
5. Topbar / brand / command search / footer
6. Section heading pattern
7. Summary card
8. Facts strip
9. Date plate (with size variants)
10. Tile (theme + body, with size + trend variants)
11. Sparkline SVG
12. Chips (with color variants)
13. Breadcrumb
14. Matter detail page composition
15. Side rail (shared between matter + meeting)
16. Meeting detail page composition
17. Matters index
18. Meetings index
19. Glossary
20. Data health
21. Pulse page composition
22. Animations + reduced motion
23. Responsive (`@media` overrides)
24. Print (`@media print`)

When you add a new component or page, put it in the section that already exists
or add a new section heading at the bottom (before responsive + print).

## Adding a new Atlas page

Five things to remember:

```erb
<% content_for :body_class, "atlas-shell" %>
<% content_for :head do %>
  <%= stylesheet_link_tag "atlas", "data-turbo-track": "reload" %>
<% end %>

<main class="atlas-wrap" id="main">
  <%= render "public/shared/atlas_topbar", active: :pulse %>

  <%# ... your page content using Atlas partials ... %>

  <%= render "public/shared/atlas_footer" %>
</main>
```

1. **`content_for :body_class, "atlas-shell"`** — turns on Atlas styles for
   this page.
2. **`content_for :head { stylesheet_link_tag "atlas" }`** — loads the bundle.
3. **`<main class="atlas-wrap" id="main">`** — the wrap centers content;
   `id="main"` is the skip-link target.
4. **`render "public/shared/atlas_topbar", active: :section_name`** — pass the
   nav-active section so the right tab is highlighted.
5. **`render "public/shared/atlas_footer"`** — closes the page.

In between, compose from the shared partials. If you need a section heading,
use `_atlas_section_heading` with `title:`, `em:`, and `label:` rather than a
bare `<h2>` — the system depends on the three-column pattern.

## Adding a new component

1. **Decide if it's a one-page concern or shared.** Page-specific composition
   (the Pulse treemap layout, the matter "papers" list) lives in the
   page-specific section of `atlas.css`. Reusable primitives (chips, cards,
   tiles) go in the components area near the top.
2. **Name it `.atlas-<thing>`.** Variants take `--modifier`. Use
   `.atlas-shell .atlas-<thing>` as the selector prefix so it's scoped.
3. **If it has logic, extract a partial.** Place under
   `app/views/public/shared/_atlas_<thing>.html.erb`. Document the locals at
   the top with `<%# ... %>`.
4. **Default to tokens.** Don't hard-code colors or sizes; reach for
   `var(--atlas-…)`. Padding/spacing should feel consistent with neighbouring
   components (typically 14–22px on cards, 24–44px between sections).
5. **Test the partial in isolation** on `/dev/atlas-test` (the sandbox renders
   every shared partial with sample data). Add a representative case there
   when you add a new component.

## Accessibility conventions

- **Skip link** is the first focusable element on every page. Lives at the top
  of the layout body (`app/views/layouts/application.html.erb`). Styled by
  `.atlas-skip-link` — sr-only until focused, then slides into the top-left as
  an accent pill. Target is `id="main"` on the page's `<main>`.
- **Focus rings** use the global selector
  `.atlas-shell a:focus-visible, .atlas-shell button:focus-visible, ...` —
  2px gold accent outline with 3px offset. Component-specific focus states (the
  search lozenge, filter inputs) override.
- **Decorative SVGs** carry `aria-hidden="true"`. Meaningful SVGs (sparklines,
  AI-disclaimer triangle) carry `role="img"` and an `aria-label`. Don't ship
  a raw `<svg>` without one of those two.
- **Form labels.** Every input has a visible `<label>` or a `class="sr-only"`
  label. The body filter on Pulse and the search/body filters on Meetings use
  `sr-only` labels because the placeholder already explains the field.
- **Heading hierarchy.** Page H1 → section H2 (`.atlas-section-head h2`) →
  card H3 → sidebar H4. The H3 inside a sidebar tile after a card H4 is a
  minor convention break but screen readers handle it cleanly. If a future
  contributor decides to tidy this, convert rail-card labels from `<h4>` to
  `<p class="atlas-rail-card-label">`.
- **ARIA landmarks.** Top-level regions use semantic elements: `<main>`,
  `<header>`, `<nav>`, `<aside>`, `<footer>`. The Atlas topbar is `<header>`,
  the side rail is `<aside aria-label="About this matter">`, etc.
- **Reduced motion.** A `@media (prefers-reduced-motion: reduce)` block in
  the base section cancels every animation and transition under `.atlas-shell`.
  Don't add transitions outside of components that already have them — the
  reduced-motion override depends on `transition-duration` being settable.

## Print

The print stylesheet lives at the bottom of `atlas.css` under
`@media print {}`. It targets the matter detail and meeting detail pages
specifically — civic researchers print these for annotation.

What it does:

- Hides interactive chrome: topbar, footer, nav, search, sidebar, breadcrumb,
  the Pulse treemap, the calendar strip, the heating-up rail, body / matters /
  meetings filter forms.
- Collapses two-column grids (`.atlas-matter-grid`, `.atlas-mtg-grid`) to
  single-column.
- Expands every `<details>` accordion (extracted text previews, meeting
  notices) so the full record prints.
- Strips background colors and decorative textures.
- Replaces colorful borders with `#999` / `#ccc` greys.
- Appends `(href)` after external (`http://`) links so a printed page stays
  verifiable; in-page anchors and glossary source citations don't show URLs.
- Uses `page-break-inside: avoid` on summary cards and matter rows; matter
  attachments allow breaks if they're long.

`@page { margin: 14mm 16mm }` is set for both A4 and US Letter.

## Testing notes

A few things worth knowing if you write more tests against Atlas pages.

- **Atlas-shell assertion pattern.** A page renders inside the system when
  three things are true: `body.atlas-shell` is present, the atlas stylesheet
  is loaded, and the section heading exists. Most page-level controller tests
  start with:

  ```ruby
  assert_select "body.atlas-shell"
  assert_select "link[rel=stylesheet][href*=atlas]"
  ```

- **CSS `text-transform: uppercase` matters in system tests.** Selenium's
  `innerText` respects CSS text-transform. So `assert_text "Heard at"` fails
  against a label rendered as `"HEARD AT"`. Either assert against the rendered
  casing or use `assert_selector` with a regex.
- **Mono caps eyebrows are uppercased.** Same trick — the source text is
  mixed-case, the rendered text is upper. Affects matter and meeting page
  tests in particular.
- **Collapsed `<details>` content is not "visible"** to Capybara by default.
  Use `assert_selector "...", visible: :all` to find content inside a closed
  accordion.
- **`/dev/atlas-test`** renders every shared partial with sample data and is
  the easiest manual surface for visual review. The route is gated to
  `Rails.env.local?` so it's not reachable in production.
- **Narrow-viewport coverage** is in `test/system/atlas_narrow_viewport_test.rb`
  — Pulse, matter detail, and meeting detail each render at 375×812 with a
  `scrollWidth` overflow check. Add to this file when introducing a new
  primary page.

## Where things live

| Path | Contents |
|---|---|
| `app/assets/stylesheets/atlas.css` | The single CSS bundle. Loaded via `content_for :head` on opt-in pages. |
| `app/assets/fonts/` | Vendored variable WOFF2s for Source Serif 4, Inter Tight, JetBrains Mono (Fraunces files remain but are unreferenced after the night refresh). |
| `app/views/public/shared/_atlas_*.html.erb` | Shared Atlas partials. |
| `app/views/layouts/application.html.erb` | Skip link + `body[class]` content_for + `yield :head` injection point. |
| `app/helpers/atlas_helper.rb` | `atlas_sparkline_svg`, `atlas_trend_for`, `atlas_trend_label`. |
| `app/services/public/agenda_item_classifier.rb` | The :substantive / :section / :notice classifier for meeting agendas. |
| `app/views/dev/atlas_test.html.erb` | Sandbox rendering every shared partial. Local-only route. |
| `test/system/atlas_narrow_viewport_test.rb` | Narrow-viewport coverage on the three primary pages. |
| `test/helpers/atlas_helper_test.rb` | Sparkline + trend helper unit tests. |
| `test/services/public/agenda_item_classifier_test.rb` | Classifier unit tests. |

## When to extend, when to break out

Atlas is designed to be one CSS bundle and a small handful of partials. If you
find yourself reaching for a new color, weight, or component shape that doesn't
already exist, prefer composing existing tokens before adding new ones — the
strength of the system is its narrow vocabulary. If you do need to add, add it
to the section that most resembles your use and document it in this file in
the next contribution.
