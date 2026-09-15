# Durable Topical Landing Pages

## What changed and why

Issue #152 identified that Civic Gallery's topical discovery surface was
exposed only through parameterized listing URLs such as
`/public/matters?theme=housing`. Those pages are functional but lack the
search, sharing, and internal-linking performance of durable human-readable
landing pages. This change adds:

- `/topics` (hub) and `/topics/:slug` (theme leaf)
- `/bodies` (hub) and `/bodies/:slug` (governing body leaf)
- `/years/:year` (year leaf, no hub)

Each leaf page is jurisdiction-scoped, has a unique title and meta
description, emits a canonical URL, and is indexable only when it has
substantive content. Empty variants render `noindex,follow` with no
canonical tag. The existing filtered matters listing at
`/public/matters?theme=housing` now canonicals to its hub page, resolving
the near-duplicate SEO signal.

## Files that carry the change

### New files

| File | Purpose |
|---|---|
| `app/controllers/public/topics_controller.rb` | `/topics` hub and `/topics/:slug` leaf controller. Validates slugs against the jurisdiction's `ThemeTaxonomy` vocabulary, resolves underscore/hyphen mapping, and returns 404 for slugs not in the vocabulary. |
| `app/controllers/public/bodies_controller.rb` | `/bodies` hub and `/bodies/:slug` leaf controller. Bodies have no table: slugs are derived from distinct `civic_events.body_name` values via `parameterize`. Collision rule: alphabetically first name wins. |
| `app/controllers/public/years_controller.rb` | `/years/:year` leaf controller. Accepts years 2000 through next year. Integer parse failure or out-of-range values return 404. |
| `app/views/public/topics/index.html.erb` | Topics hub: lists themes with matter counts as theme tiles. Empty state with `noindex,follow` when no theme has records. |
| `app/views/public/topics/show.html.erb` | Topic leaf: matters (primary-theme first) and meetings whose agendas include themed matters. Contains internal links to matter detail, event detail, filtered listing, and the topics hub. |
| `app/views/public/bodies/index.html.erb` | Bodies hub: lists body names with meeting counts. Empty state with `noindex,follow` when no bodies have records. |
| `app/views/public/bodies/show.html.erb` | Body leaf: meetings and matters for one body. Contains internal links to matter detail, event detail, filtered meeting listing, and the bodies hub. |
| `app/views/public/years/show.html.erb` | Year leaf: meetings and matters dated in that year (matters matched on `agenda_date` or `intro_date`). Contains internal links to matter detail, event detail, and the full listings. |
| `test/controllers/public/topics_controller_test.rb` | 10 tests covering: primary-theme ordering, cross-theme exclusion, internal links, jurisdiction scoping, 404 for unknown slugs, metadata (title/description/canonical/robots), thin-page noindex, HTTPS canonical, cache headers + ETag 304, hub listing, and hub noindex. |
| `test/controllers/public/bodies_controller_test.rb` | 6 tests covering: city council meetings/matters display, jurisdiction scoping, unresolvable slug 404, slug collision resolution, metadata distinctness, HTTPS canonical, cache headers + ETag 304, and hub listing. |
| `test/controllers/public/years_controller_test.rb` | 7 tests covering: year display jurisdiction-scoped, matters with intro_date only, cross-year exclusion, thin-page noindex, non-numeric/implausible year 404s, metadata distinctness, HTTPS canonical, and cache headers + ETag 304. |

### Modified files

| File | What changed |
|---|---|
| `config/routes.rb` | Added `get "topics"`, `get "topics/:slug"`, `get "bodies"`, `get "bodies/:slug"`, and `get "years/:year"` with a `constraints: { year: /\d{4}/ }` guard. All routes point to `Public::` controllers, preserving the shared public cache headers and session-skipping. |
| `app/models/public/cache_version.rb` | Added `topics_index`, `topic_landing`, `bodies_index`, `body_landing`, `year_landing`, and `landing_sitemap` methods. Each follows the existing pattern: `compose` with jurisdiction slug and `data_version`, plus a page-specific discriminator. |
| `app/models/civic/theme_taxonomy.rb` | Added `url_slug_for(slug)` (underscore-to-hyphen) and `slug_from_url(url_slug)` (hyphen-to-underscore) class methods. Centralized the bidirectional mapping so stored slugs (underscored) are never changed. |
| `app/controllers/public/discovery_controller.rb` | Added `SITEMAP_CACHE_TTL`, `landing_sitemap_urls` private method, and `landing_sitemap_rows_for` helper. Makes four cached aggregate queries (theme updated_at, body event updated_at, body matter updated_at, distinct years) and renders only populated leaf URLs. The hub URLs (`/topics`, `/bodies`) are included only when they have at least one populated leaf. Empty/noindexed variants are excluded. |
| `app/views/public/discovery/llms.text.erb` | Added the durable Topics and Bodies hubs to the AI-oriented discovery guide, directing agents to crawlable paths into official matters and meetings. |
| `app/views/public/matters/index.html.erb` | Added a `content_for(:canonical_url)` line that points to the topic hub when a `theme` param is present and `q` is blank. This resolves the near-duplicate SEO signal: a theme-filtered listing canonicals to its hub instead of the unparameterized `/public/matters`. The `?q=` noindex behavior is unchanged. |
| `test/controllers/public/discovery_controller_test.rb` | Extended the cross-jurisdiction sitemap test to assert landing-page URLs are jurisdiction-scoped: San Jose's sitemap includes `topics/public-safety` and `bodies/city-council`; SJUSD's includes `topics/curriculum-instruction` and `bodies/board-of-education`. Asserts empty themes (arts-culture) are excluded. Requires `matter_themes` records on both jurisdictions' fixture matters. |
| `test/controllers/public/matters_controller_test.rb` | Added two tests: (1) `?theme=housing` canonicals to `/topics/housing` with no robots meta, (2) `?q=housing&theme=housing` stays `noindex,follow` with no canonical and `og:url` = the unparameterized path. |

## How to use it

- **Browse topics:** visit `/topics` to see all themes that have at least one
  tagged matter. Click a theme tile to see `/topics/<slug>` (e.g.
  `/topics/public-safety`).
- **Browse bodies:** visit `/bodies` to see all governing bodies that have at
  least one meeting. Click a body tile to see `/bodies/<slug>` (e.g.
  `/bodies/city-council`).
- **Browse years:** navigate directly to `/years/2026` (no hub exists; years
  are discoverable from the sitemap and from meeting pages).
- **Sitemap:** every populated landing page appears in `/sitemap.xml` with its
  latest relevant timestamp. Hubs appear only when they have at least one
  populated leaf.
- **AI discovery:** `/llms.txt` names the Topics and Bodies hubs as stable
  navigation paths into the civic-record corpus. Year leaves remain discoverable
  from the sitemap because there is intentionally no year hub.

## How to verify

Run the full test suite:

```bash
docker compose up -d db
bin/rails test
```

Key test classes and their scope:

- `test/controllers/public/topics_controller_test.rb` — 10 tests
- `test/controllers/public/bodies_controller_test.rb` — 6 tests
- `test/controllers/public/years_controller_test.rb` — 7 tests
- `test/controllers/public/discovery_controller_test.rb` — sitemap inclusion
  and cross-jurisdiction scoping (the existing test was extended)
- `test/controllers/public/matters_controller_test.rb` — canonical behavior
  for theme-filtered listing (2 new tests)

Style check:

```bash
bin/rubocop
```

## Notable design decisions

- **No bodies table.** Bodies are free-text `civic_events.body_name` values.
  Slugs are derived from distinct values at request time via
  `String#parameterize`. If two body names parameterize to the same slug, the
  alphabetically first name wins; the unreachable duplicate remains reachable
  via `/public/meetings?body_name=<name>`.
- **No year hub.** Years are an open, low-value set whose members are
  discoverable from the sitemap and from meeting pages, so only leaf pages
  exist.
- **Canonical, not redirect.** The theme-filtered matters listing canonicals
  to the hub rather than 301-redirecting, because the filtered listing
  still exposes a different view (sort/filter controls, pagination) and some
  users arrive at it directly from internal links that were not repointed.
- **Cached aggregates.** All landing-page queries are inside
  `Rails.cache.fetch` blocks with 5-minute TTLs. The sitemap's landing-page
  rows use a dedicated cache entry so regeneration does not recompute the
  full set of aggregates per request.
- **Jurisdiction-scoped throughout.** Every query uses
  `for_jurisdiction(current_jurisdiction)`. Theme slugs are validated against
  the jurisdiction's `ThemeTaxonomy` vocabulary. Body slugs are reverse-resolved
  against the jurisdiction's distinct body names. Landing-page ETags fold in
  `jurisdiction.data_version`, so a data bump on one host does not invalidate
  another host's cache.
