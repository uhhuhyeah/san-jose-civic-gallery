# Plan: Durable topical landing pages for civic themes, bodies, and years (Issue #152)

## Goal

Add crawlable, indexable landing pages at `/topics/:slug`, `/bodies/:slug`, and `/years/:year`
(plus `/topics` and `/bodies` index hubs) that act as internal-link hubs into matters, meetings,
and source records, per jurisdiction, without breaking existing `/public/matters` filters or
metadata behavior.

## Decisions (made so the builder does not have to)

1. **Ship all three surfaces** (topics, bodies, years). AC 1 names all three.
2. **Three controllers**, not one: `Public::TopicsController`, `Public::BodiesController`,
   `Public::YearsController`. Each maps to one resource and one view directory, matching the
   existing one-controller-per-page layout (`GlossaryController`, `DataController`,
   `RoundupsController`). A single LandingsController would mix three unrelated query shapes.
3. **Index pages exist for `/topics` and `/bodies`** (they are the crawl path into the leaves and
   double as the hub directories). **No `/years` index**: years are an open, low-value set; year
   leaves are reachable via the sitemap and from meeting pages. State this in the PR body.
4. **URL slug mapping is centralized on `Civic::ThemeTaxonomy`** as new module functions
   (Trap 2). Stored slugs do not change.
5. **Empty-but-valid pages render `noindex,follow` with NO canonical** (AC 5 option A), rather
   than 404. Invalid slugs (not in the jurisdiction vocabulary, unresolvable body slug, bad year)
   return 404. Sitemap includes only populated landing pages.
6. **Trap 5 resolution: canonical, not redirect.** A theme-filtered `/public/matters?theme=X`
   (with no `q`) stays 200 and indexable but emits
   `content_for(:canonical_url) { topic_url(url_slug) }` pointing at the hub. Rationale: the
   filter UI and ~8 existing internal link sites keep working unchanged, and a 301 would break
   the in-app theme-filter UX (dropdown, banner links). Internal links are NOT repointed in this
   PR; say so in the PR body. `?q=` behavior (noindex, no canonical, og:url unparameterized) is
   untouched.

## Files to create

### Routes — `config/routes.rb` (edit)

Follow the `glossary` / `data` / `roundups` precedent: root-level paths, `Public::` controllers,
with a short comment explaining the controller lives in `Public::` for cache-header/session
behavior. Place after the `roundups` routes:

```ruby
# Durable topical landing pages (issue #152). Root-level paths for
# discoverability; controllers stay in Public:: so they keep the shared
# public cache headers and session-skipping.
get "topics", to: "public/topics#index", as: :topics
get "topics/:slug", to: "public/topics#show", as: :topic
get "bodies", to: "public/bodies#index", as: :bodies
get "bodies/:slug", to: "public/bodies#show", as: :body
get "years/:year", to: "public/years#show", as: :year, constraints: { year: /\d{4}/ }
```

The year constraint makes `/years/abc` a routing 404; `/years/1700` passes the constraint and is
range-checked in the controller.

### Slug helpers — `app/models/civic/theme_taxonomy.rb` (edit, additive only)

Add two module functions and nothing else:

```ruby
# URL-safe form of a stored slug. Stored slugs keep underscores; public URLs
# use hyphens (issue #152). Bidirectional and total over both alphabets.
def url_slug_for(slug)
  slug.to_s.tr("_", "-")
end

def slug_from_url(url_slug)
  url_slug.to_s.tr("-", "_")
end
```

Do not edit the vocabularies, `valid_slug?`, or `label_for`.

### `app/controllers/public/topics_controller.rb` (new)

```ruby
module Public
  class TopicsController < ApplicationController
    def index
      return unless stale?(etag: Public::CacheVersion.topics_index(jurisdiction: current_jurisdiction), public: true)
      @themes = cached_populated_themes  # [{slug:, url_slug:, label:, matter_count:}], only count > 0
    end

    def show
      @theme = Civic::ThemeTaxonomy.slug_from_url(params[:slug])
      head :not_found and return unless Civic::ThemeTaxonomy.valid_slug?(@theme, current_jurisdiction)
      @theme_label = Civic::ThemeTaxonomy.label_for(@theme, current_jurisdiction)
      return unless stale?(etag: Public::CacheVersion.topic_landing(slug: @theme, jurisdiction: current_jurisdiction), public: true)
      @matters = cached_topic_matters      # rank-1-first ordering, limit 50, includes(:attachments, :themes)
      @meetings = cached_topic_meetings    # events having agenda items joined to these matters, recent_first, limit ~10
      @empty = @matters.empty?
    end
  end
end
```

- All scopes `.for_jurisdiction(current_jurisdiction)`.
- Matters query mirrors `MattersController#matter_ids_for`'s theme branch: `joins(:themes).where(civic_matter_themes: { theme_slug: @theme }).order(Arel.sql("civic_matter_themes.rank ASC")).recent_first`.
- Meetings: `Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).joins(event_items: :matter).where(civic_matters: { id: <matter ids subquery> }).distinct.recent_first.limit(10)` — verify association names against `Civic::Event`/`Civic::EventItem` before writing.
- Wrap aggregates in `Rails.cache.fetch([<cache version>, "..."], expires_in: 5.minutes)` exactly like `MattersController#cached_index_ids` / `MeetingsController#cached_filter_options`.
- `index` shows only populated themes (count > 0) so the hub never links to a noindex page.

### `app/controllers/public/bodies_controller.rb` (new)

- `index`: cached distinct body names for the jurisdiction (same query as
  `MeetingsController#cached_filter_options`'s `body_options`:
  `Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).where.not(body_name: [nil, ""]).distinct.order(:body_name).pluck(:body_name)`),
  each paired with `body_name.parameterize` for the URL.
- `show`:
  - Reverse-resolve: pluck the same jurisdiction-scoped distinct list, find
    `name.parameterize == params[:slug]`. **Collision rule**: if two body names parameterize to
    the same slug, the alphabetically first name wins (the list is `order(:body_name)`, so
    `find` is deterministic); the unreachable duplicate still works via
    `/public/meetings?body_name=...`. Document this in a comment.
  - No match → `head :not_found`.
  - `@events` = current_from_source events with that `body_name`, recent_first, limit ~25;
    `@matters` = matters with that `body_name` (matters also carry a free-text `body_name`
    column — verify on `Civic::Matter`), recent_first, limit 50. Both jurisdiction-scoped,
    cached under the landing cache version.

### `app/controllers/public/years_controller.rb` (new)

- `show` only. `params[:year]` arrives as a 4-digit string (route constraint). Convert with
  `Integer(params[:year], 10)`; `head :not_found` unless within
  `2000..(Date.current.year + 1)` (San Jose Legistar data does not predate 2000; the +1 covers
  pre-published agendas for next year).
- `@events` = events with `event_date` in that year, `@matters` = matters with `agenda_date`
  (fall back to `intro_date` via OR, or just `agenda_date` — check which column the matters
  index treats as primary; `recent_first` ordering uses both) in that year. Jurisdiction-scoped,
  cached, limit 50/25.
- `@empty` when both are empty → view sets `noindex,follow`.

### `app/models/public/cache_version.rb` (edit, additive)

Add in the existing style (all keyed on `jurisdiction.slug` + `jurisdiction.data_version`):

```ruby
def topics_index(jurisdiction:)
  compose("public/topics-index/v1", jurisdiction.slug, jurisdiction.data_version)
end

def topic_landing(slug:, jurisdiction:)
  compose("public/topic/v1", jurisdiction.slug, slug, jurisdiction.data_version)
end

def bodies_index(jurisdiction:)       # same pattern
def body_landing(slug:, jurisdiction:) # same pattern
def year_landing(year:, jurisdiction:) # same pattern
```

### Views (new) — all under `app/views/public/`

Copy the metadata block pattern from `matters/index.html.erb:1-6` verbatim. Every page:
`body_class "atlas-shell"`, the `atlas` stylesheet in `content_for :head`,
`render "public/shared/atlas_topbar", active: :matters` (no new topbar states; an unrecognized
symbol is explicitly acceptable per the issue notes), and `render "public/shared/atlas_footer"`.
Reuse `_atlas_section_heading`, `_atlas_theme_tile`, `_atlas_body_tile`, `_atlas_date_plate`
where they fit; read those partials before writing markup.

- `topics/index.html.erb`: title "Topics", description built from
  `current_jurisdiction.short_name` / `civic_subject`. Grid of theme tiles linking to
  `topic_path(theme[:url_slug])`. If `@themes` empty, set `noindex,follow`.
- `topics/show.html.erb`:
  - `content_for(:title) { "#{@theme_label} records" }` (must be unique per slug; include the
    label).
  - `content_for(:description) { "...#{@theme_label} matters and meetings from #{current_jurisdiction.short_name} #{current_jurisdiction.governing_bodies_phrase}..." }` — must differ
    from `default_description`. Copy must be jurisdiction-generic (no literal "San Jose"/"city
    council") and descriptive, not editorial (source-first posture: say what records exist, not
    what the body decided).
  - `content_for(:robots) { "noindex,follow" } if @empty` — and then NO canonical (the layout
    already suppresses canonical when robots contains noindex; do not set `canonical_url`
    yourself on any landing page, the helper default `request.base_url + request.path` is
    exactly right).
  - Body: matters list (reuse the row markup shape from matters/index, simplified), meetings
    list, plus a link to `public_matters_path(theme: @theme)` ("view all in Matters") and to
    `topics_path`. At least one link to a specific matter and one to a specific event when
    records exist.
- `bodies/index.html.erb`: tiles linking `body_path(name.parameterize)`.
- `bodies/show.html.erb`: title `"#{@body_name} records"`, meetings + matters sections, link to
  `public_meetings_path(body_name: @body_name)` and `public_matters_path`.
- `years/show.html.erb`: title `"#{@year} records"`, events grouped by month if trivial
  (otherwise flat recent_first list), matters list, links to
  `public_meetings_path(year: @year)` — verify that param exists in MeetingsController
  (`year_options` suggests it does) before linking; otherwise link plain `public_meetings_path`.

### Sitemap — `app/controllers/public/discovery_controller.rb` (edit)

Extend `static_sitemap_urls` (keep the name; it already emits `[url, timestamp]` pairs and nil
timestamps are allowed by `sitemap.xml.erb`):

- Append `topics_url` and `bodies_url` with `Date.current`.
- Append one entry per **populated** topic: `topic_url(Civic::ThemeTaxonomy.url_slug_for(slug))`,
  timestamp `Civic::Matter.for_jurisdiction(current_jurisdiction).joins(:themes).where(civic_matter_themes: { theme_slug: slug }).maximum(:updated_at)` — compute all counts/timestamps in
  as few queries as possible (one `group(:theme_slug).maximum(:updated_at)` over the
  jurisdiction's matter_themes join), inside a `Rails.cache.fetch` keyed on
  `Public::CacheVersion.events_index(jurisdiction:)`-style version, `expires_in: 5.minutes`.
- Append one per distinct body name: `body_url(name.parameterize)`.
- Append one per distinct populated year from `Civic::Event...pluck` of
  `date_trunc('year', event_date)` or Ruby-side `distinct.pluck(:event_date).map(&:year).uniq` —
  choose the cheaper after checking table size patterns used elsewhere; nil timestamps are fine.
- Everything jurisdiction-scoped. Empty topics (count 0) are excluded by construction.
- Do NOT change the `last_modified` / `stale?` logic at the top of `sitemap` — leave the 304
  path intact (issue Trap 6).

### Matters index metadata — `app/views/public/matters/index.html.erb` (edit, one line)

At the top, after the existing robots line, add:

```erb
<% content_for(:canonical_url) { topic_url(Civic::ThemeTaxonomy.url_slug_for(@theme)) } if @theme && @query.blank? %>
```

This is the chosen Trap 5 handling. When `@query` is present the robots `noindex` already
suppresses the canonical tag, so the existing `?q=` assertions keep passing. Do not touch any
search/filter logic in `MattersController`.

## Tests to create/extend

Only fixture file present is `civic_jurisdictions.yml`; existing public controller tests build
records in `setup` — mirror `test/controllers/public/discovery_controller_test.rb` and
`matters_controller_test.rb` for factories/setup style, `host! SANJOSE_HOST` / `host! SJUSD_HOST`
constants, and assertion style. Check how those tests create `Civic::Matter`, `Civic::Event`,
`Civic::MatterTheme` records and reuse their helpers verbatim.

New: `test/controllers/public/topics_controller_test.rb`, `bodies_controller_test.rb`,
`years_controller_test.rb`. Extend: `discovery_controller_test.rb` (sitemap),
`matters_controller_test.rb` (theme canonical).

Map each test to an acceptance criterion:

1. topics#show on sanjose: 200, lists fixture matters tagged `public_safety`, rank-1 first
   (create two matters, ranks 1 and 2, assert order with `assert_select` on row order or
   response body index positions).
2. `GET /topics/public-safety` on sjusd → 404. `GET /topics/curriculum-instruction` → 200 on
   sjusd, 404 on sanjose.
3. `/topics/not-a-real-theme` → 404 on both hosts.
4. Populated topic page: `assert_select "title"` unique vs another topic's title;
   `meta[name=description]` present and not `jurisdiction.default_description`;
   `link[rel=canonical][href$="/topics/public-safety"]`; `assert_select "meta[name=robots]", 0`.
5. Valid-but-empty topic (e.g. `arts-culture` with no tagged matters): 200,
   `meta[name=robots][content="noindex,follow"]` present AND
   `assert_select "link[rel=canonical]", 0`. Both halves.
6. With `X-Forwarded-Proto: https` header: canonical and `og:url` start with `https://`. Copy
   the existing forwarded-proto assertion from `discovery_controller_test.rb`.
7. bodies#show: create events `body_name: "City Council"` in sanjose and a same-named event in
   sjusd; assert sanjose host renders only sanjose records, sjusd host only sjusd records (or
   404 if no such body there). Also assert slug reverse-resolution: `/bodies/city-council`.
8. years#show: records dated 2026 render for current jurisdiction only; empty year →
   noindex + no canonical; `/years/abc` → 404 (routing), `/years/1700` → 404 (controller), both
   not 500.
9. Each landing page: `assert_select "a[href=?]", public_matters_path(...)` at least one, and
   `a[href=?]` to a specific `public_matter_path(matter)` / `public_event_path(event)`.
10. Sitemap: extend the existing cross-jurisdiction sitemap test — sanjose sitemap includes
    populated topic/body/year URLs and excludes the empty topic's URL; sjusd sitemap includes
    SJUSD landing pages and contains no `/topics/public-safety` etc.
11. `GET /public/matters?theme=housing`: 200, canonical href is the `/topics/housing` URL, no
    robots meta. (Chosen option: canonical.)
12. `GET /public/matters?q=housing`: `noindex,follow`, no canonical, og:url is
    `http://<host>/public/matters`. Keep the existing assertions passing.
13. Each landing page: `Cache-Control` includes `public, max-age=300, s-maxage=7200,
    stale-while-revalidate=60`, no `Set-Cookie` header, and a second GET with
    `HTTP_IF_NONE_MATCH` set to the first response's ETag returns 304.

## Traps restated (from issue context; all apply)

- Controllers MUST be `module Public` — `ApplicationController` gates session-skip and the
  shared Cache-Control header on `controller_path.start_with?("public/")`. A top-level
  controller silently loses caching and emits Set-Cookie.
- Every query `.for_jurisdiction(current_jurisdiction)`. This is the highest-blast-radius bug
  class here.
- Theme URL slugs are hyphenated; stored slugs underscored. Use only the new
  `url_slug_for`/`slug_from_url` helpers.
- Jurisdiction copy via `short_name`, `site_title`, `civic_subject`, `governing_bodies_phrase`,
  `kind_noun`, `all_scope_label` — never literal "San Jose" or "city council".
- `content_for(:robots)` containing `noindex` makes the layout omit the canonical tag; never set
  `canonical_url` on a noindexed variant.
- Do NOT touch `llms.text.erb` (open issue #153), `robots.txt`, `test_helper.rb`
  (`parallelize(workers: 1)`), any migration (none needed), the ThemeTaxonomy vocabularies, or
  the matters search pipeline.
- Sitemap timestamps must be Time/Date/nil, never String (`timestamp.to_date.iso8601` is called
  in the template).

## Out of scope

- Repointing the ~8 existing `public_matters_path(theme: ...)` internal link sites (mention in
  PR body as follow-up).
- A `/years` index page, llms.txt changes, robots.txt changes, any new gems, any migration.
- New atlas topbar `active:` states and new stylesheet work beyond reusing existing atlas
  partials/classes.

## Verification

```bash
docker compose up -d db
bin/rails test test/controllers/public/topics_controller_test.rb \
  test/controllers/public/bodies_controller_test.rb \
  test/controllers/public/years_controller_test.rb \
  test/controllers/public/discovery_controller_test.rb \
  test/controllers/public/matters_controller_test.rb
bin/rails test          # full suite
bin/rubocop             # rails-omakase; two-space indent
```

If Postgres is unreachable, per AGENTS.md ask the user to start Docker rather than declaring
tests blocked.

## PR body checklist

- Note the canonical-over-redirect choice for `?theme=` (AC 11) and why.
- Note internal theme links were not repointed (follow-up).
- Note the body-slug collision rule.
- Note topics/bodies indexes exist, `/years` index intentionally does not.
- Note no migration, no dependency changes; SEO/trust effects: new indexable hubs, empty
  variants noindexed, sitemap extended per jurisdiction.
- No em dashes anywhere in code comments, docs, or the PR body.
