# Pulse: Theme Tagging and Trends

Pulse surfaces which civic topics the city's bodies have been focused on lately,
and which are *heating up*, rather than just which appear most often. It answers
a different question than search ("find topic X") or meeting browsing ("what was
on this agenda").

It is built from two pieces:

1. A **theme classifier** that tags each `Civic::Matter` with one or more themes
   from a fixed vocabulary.
2. A **trend aggregation** (`Public::ThemePulse`) that counts how often each
   theme's matters appear on agendas over time.

Like generated summaries, theme tags are **assistive, model-derived metadata**.
They never modify official `Civic::*` records.

## Data model

Theme tags live in two layers, by design:

- **`generated_artifacts`** (`kind: "matter_themes"`, target `Civic::Matter`) is
  the source of truth and audit trail. Each classification is one row, unique
  per `(target, kind, model_identifier, prompt_version, input_sha256)`, exactly
  like attachment summaries. Old prompt versions are kept, not overwritten.
- **`civic_matter_themes`** is a normalized projection that the trend query
  reads. Columns: `civic_matter_id`, `theme_slug`, `rank`, `source_artifact_id`,
  `confidence` (currently unused), timestamps. It exists because aggregating
  `GROUP BY theme` over a date window against jsonb arrays in the artifacts table
  would be slow; the projection is indexed for it.

On every successful classification, the service overwrites the matter's
projection rows to exactly the model's output and stamps `source_artifact_id`.
So the projection always reflects the latest run; the artifacts table retains
history.

### Rank matters

Themes are stored in the order the model returns them, most central first, as a
1-based `rank`. **Rank 1 is the matter's primary theme.** The pulse counts
appearances on the primary theme only (`Civic::MatterTheme.primary`), which keeps
weaker secondary tags from inflating the rankings. The full multi-label set
(`by_rank`) is still available for display and filtering.

## Classifier

The vocabulary is `Civic::ThemeTaxonomy`: a per-jurisdiction registry of closed
theme lists (slug + label), `SANJOSE` (~17 city themes) and `SJUSD` (16
school-district themes), resolved by a matter's jurisdiction (`themes_for`,
`slugs_for`, `valid_slug?`, `label_for`, defaulting to the city list for
unknown/nil). The model may only choose from its jurisdiction's list. Editing a
list requires bumping that jurisdiction's prompt version (below), which re-tags
only that jurisdiction's matters; the same slug may appear in more than one list
without collision because slugs are validated per jurisdiction.

The classification pipeline mirrors `Generated::SummarizeMatterAttachment`:

- `Generated::Prompts::MatterThemesBase`: the shared prompt mechanics (user
  prompt, input hashing, truncation). Per-jurisdiction subclasses supply a
  VERSION, the jurisdiction's taxonomy, and the system prompt:
  `MatterThemesV1` (city, `matter_themes_v5`) and `SjusdMatterThemesV1`
  (`sjusd_matter_themes_v1`, school-district boundaries). Each embeds its
  jurisdiction's taxonomy, asks for the primary subject(s) only (capped at two),
  and returns strict `{ "themes": [...] }` JSON. Untrusted source text is wrapped
  in `<source_text>` tags.
- `Generated::ThemesClient`: an OpenAI-compatible client. It is
  taxonomy-agnostic (it does not know the matter), so it only validates the
  response shape and stringifies the returned values; filtering against the
  vocabulary is the service's job. It reuses `GENERATED_SUMMARY_API_KEY` /
  `GENERATED_SUMMARY_API_BASE`, with themes-specific `GENERATED_THEMES_MODEL`,
  `GENERATED_THEMES_TIMEOUT_SECONDS`, and `GENERATED_THEMES_MAX_INPUT_CHARS`.
- `Generated::ClassifyMatterThemes`: the service. It resolves the prompt and
  version by the matter's jurisdiction (`PROMPTS_BY_JURISDICTION`) and filters
  the model's returned slugs against that jurisdiction's vocabulary (dropping
  unknown slugs, normalizing case, de-duplicating, preserving order). Source
  text is the matter's attachment summaries, falling back to extracted text,
  then to the matter's title/file alone. It writes the artifact and syncs the
  projection (with rank). Because `prompt_version` is part of the artifact
  idempotency key and is resolved per jurisdiction, city and SJUSD
  classifications never collide.

### Procedural skip

Some matters are procedural containers (minutes approvals, agenda reviews,
closed-session agendas, ceremonial items, travel authorizations). The model
tends to tag these by the content they *reference* (a closed session "about"
litigation), which is wrong. So the service **skips the model entirely** for
them and records an empty theme set:

- by `matter_type_name` for clean procedural types (see
  `ClassifyMatterThemes::PROCEDURAL_MATTER_TYPES`), and
- by title pattern for travel authorizations, which are not their own type.

Mixed types that contain both substantive and procedural items (Consent Agenda,
Reports to Committee, Rules Committee, Strategic Support) are deliberately *not*
skipped.

## Trend aggregation

`Public::ThemePulse` produces three views over a window (default: the current
quarter, `13.weeks`):

- **`stats`**: every theme in the jurisdiction's vocabulary with its
  current-window appearances, prior-window appearances, per-meeting rates,
  `lift` (current rate / prior rate), and a `surging` flag. Themes with no
  appearances still appear with zeros, so the front page can render the full
  taxonomy.
- **`heating_up`**: a sorted, filtered slice of `stats` ranked by momentum.
  Rate is appearances per meeting, so the comparison stays fair when the two
  windows hold different numbers of meetings (recess) or when comparing a
  single body. A theme needs at least `DEFAULT_MIN_APPEARANCES` (3)
  current-window appearances to qualify, so a single agenda item can't spike
  it. Themes with real activity now and none last quarter are flagged
  `surging` and sort first.
- **`quarterly_series(buckets: 4)`**: a multi-bucket time series per theme
  (oldest bucket first, current bucket last) used to draw sparklines on the
  homepage. Bucket boundaries align with `stats`' current/prior windows so the
  last bucket equals the current-window appearance count exactly. Four
  quarters is the spec; production has ~7.3 years of San Jose history and ~2
  years of SJUSD history, so no jurisdiction needs leading-empty padding.

It accepts `body_name` (nil = citywide rollup) and only counts
`current_from_source` events and event items.

The data is also inspectable from the CLI via the rake task below.

## The homepage

The Pulse page is the site homepage (`root` -> `Public::PulseController#show`).
After the Atlas redesign (see `docs/atlas.md`), the page composes the Pulse
data into a spatial front door: the resident who is *just curious* should be
able to wander it the way they'd wander a map, while the power user still has
search and per-body filters. The composition, top to bottom:

- **The Pulse treemap** (centerpiece): every theme in the jurisdiction's
  vocabulary as a sized, tinted tile. Tile size is driven by
  `current_appearances` (XL/L/M/S buckets — top 1, next 2, next 8, rest); tile
  tint is driven by `lift` (heat for >100%, oxblood for >10%, slate for steady,
  muted for down). Each tile carries a sparkline drawn from
  `quarterly_series` and links to `/public/matters?theme=<slug>`. The treemap
  is both the visualisation of attention *and* the topic wayfinding primitive —
  what used to be a chip bar of every theme is now the spatial map itself.
  Per-body filter sits below the hero and re-scopes the whole treemap.
- **What's heating up**: the top movers (`heating_up.first(4)`) as four
  editorial cards with bigger sparklines. Same data as the treemap's
  heat-tinted tiles, just pulled out for emphasis.
- **In session**: the few most recent matters that already carry a non-empty
  generated summary, newest agendas first, rendered as a numbered editorial
  list. This surfaces the product's actual output (an AI summary of a real
  matter) on the front page rather than only describing the capability.
  Summaries are read from existing `attachment_summary` artifacts; the module
  never triggers a new generation. The representative summary per matter comes
  from `matter_summary_preview`, which filters preloaded artifacts in Ruby to
  avoid an N+1.
- **The calendar**: a horizontally scrolling strip of the latest meetings —
  date plate, body name, agenda/minutes status chips. Links to the meeting
  detail page.
- **Monthly roundup CTA**: a single block pointing at `/roundups`.
- **The ledger**: four headline stats — meetings ingested, **matters heard**
  (the count of `civic_event_items` with a `civic_matter_id`, *not* raw agenda
  items), distinct matters, document extractions. The "matters heard" framing
  was chosen over "agenda items" because roughly 73% of EventItems are
  procedural rows (notices, ADA boilerplate, Levine Act, etc.) that inflate
  the total without informing residents.

Two technical invariants worth preserving:

- **Conditional GET stays cheap.** Every per-module query runs in
  `load_homepage_context` or `load_atlas`, after the `stale?(etag:)` check. A
  matching `If-None-Match` returns 304 before any of them fire, so a
  conditional request never probes `generated_artifacts`,
  `document_extracted_texts`, or `civic_matter_themes`. A controller test pins
  this; keep new modules behind the same gate.
- **The cache key is inline.** Conditional GET and per-module fragment caching
  use a key built in the controller (`public/pulse-homepage/v3`, keyed on
  jurisdiction, date, body filter, window, spark bucket count, and a 10-minute
  TTL bucket), not `Public::CacheVersion.pulse` (removed). Bump the version
  suffix (`v3` → `v4`) when changing the cache contract.

## Operating it

Tag matters (dry-run lists candidates; `RUN=true` calls the model):

```bash
bin/rails generated:classify_matter_themes                        # dry run, all jurisdictions
RUN=true LIMIT=150 bin/rails generated:classify_matter_themes
RUN=true FORCE=true LIMIT=150 bin/rails generated:classify_matter_themes
RUN=true JURISDICTION=sjusd LIMIT=50 bin/rails generated:classify_matter_themes  # scope to one jurisdiction
```

Candidates are selected newest-agendized first, so a re-tag after a prompt change
converges on the most pulse-relevant matters first. The backfill skips matters
that already succeeded for the current model and prompt version (resolved per
jurisdiction), so an unscoped run also picks up any jurisdiction's unclassified
matters; pass `JURISDICTION=<slug>` to scope a controlled run.

Inspect the result before any UI exists (defaults to the city; pass
`JURISDICTION=<slug>` for another):

```bash
bin/rails pulse:preview                          # all-time, sanjose
WEEKS=13 bin/rails pulse:preview                 # window appearances to last 13 weeks
SAMPLES=5 bin/rails pulse:preview                # sample matters per theme
JURISDICTION=sjusd bin/rails pulse:preview       # the SJUSD vocabulary
```

The preview prints, per theme: total tagged matters, **Primary** (rank 1) count,
and primary-based **Appearances** in the window. Track the primary/appearances
columns; total "tagged" intentionally plateaus below 100% because procedural
items classify to empty.

Production batches enqueue `Generated::BackfillMatterThemesJob` on the dedicated
`generated_summary` Solid Queue worker (the same one summaries use). It can be
scheduled in `config/recurring.yml` alongside the summary backfill; it is
skip-safe to run repeatedly.

### Re-tagging after a change

Bumping a jurisdiction's prompt VERSION (`MatterThemesV1::VERSION` for the city,
`SjusdMatterThemesV1::VERSION` for SJUSD), or editing that jurisdiction's
taxonomy, makes that jurisdiction's matters candidates again. The next backfill
runs re-classify against the new prompt and overwrite the projection; the change
is scoped to that jurisdiction, never the other. The previous version's
artifacts remain as history. To confirm a sweep is complete, count that
jurisdiction's matters lacking a current-version artifact (city shown):

```bash
bin/rails runner 'j = Civic::Jurisdiction.find_by!(slug: "sanjose"); puts Civic::Matter.for_jurisdiction(j).where.not(id: Generated::Artifact.where(kind: "matter_themes", prompt_version: Generated::Prompts::MatterThemesV1::VERSION, status: "succeeded").select(:target_id)).count'
```

When that prints `0`, the sweep is done.

## How the tagging got here (and its limits)

Tag quality was tuned across five prompt versions against real San Jose agenda
data. Each pass fixed the named problem and exposed the next, which is worth
knowing before you tune further:

- **v1** over-tagged: procedural minutes pulled every topic discussed in the
  meeting, and Budget & Finance became a catch-all.
- **v2** added "primary subject only," a theme cap, and an empty result for
  procedural items. Budget shrank; ceremonial special-event items then inflated
  Public Safety / Arts via incidental association, and litigation settlements had
  no home.
- **v3** added the Legal & Litigation theme and a ceremonial-item rule.
- **v4** dropped the cap to two, extended the anti-catch-all rule to Economic
  Development, and added the `rank` column so the pulse could rank on the primary
  theme. This is what tamed the catch-alls in the rankings.
- **v5** added the structural procedural skip (by matter type and travel-auth
  title) plus boundary rules (traffic safety → Transportation; energy →
  Utilities; program funding → the program, not Budget).

The recurring lesson: **the model classifies procedural containers by the
substantive content they reference, and prompt wording alone cannot reliably beat
that.** The structural skip exists because of it.

Known residual noise we chose not to chase:

- Broad recurring "Status Report" / "Annual Report" items survey a whole program
  area and pick up two loosely related themes.
- A few items still land in an arguable theme (some traffic-safety matters in
  Public Safety).

These are steady-state and expected to wash out in the trend-based `heating_up`
metric, which compares a theme against its own baseline rather than ranking by
absolute volume. They are not worth further prompt tuning.

Other limits, same spirit as generated summaries:

- **Prompt injection.** Source text is arbitrary public PDF content. The prompt
  treats anything inside `<source_text>` tags as data, which raises the bar but
  is not bulletproof. Treat tags as assistive.
- **No quality scoring.** The client validates JSON shape and the service
  enforces taxonomy membership, but neither judges whether the tag is *correct*.
  Spot-check with `pulse:preview` (per jurisdiction via `JURISDICTION=<slug>`)
  after any change.
