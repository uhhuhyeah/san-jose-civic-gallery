# Multi-Jurisdiction Architecture (SJUSD)

Civic Gallery began as a single-tenant app: San Jose city government records
from Legistar, served at `sanjose.civicgallery.org`. It now also hosts San José
Unified School District board records from Simbli (eBoardSolutions) at
`sjusd.civicgallery.org`, in the **same** Rails monolith, Postgres database,
Solid Queue install, and Active Storage blob store.

This doc records the architectural changes that made a second jurisdiction
possible and, more importantly, the deliberate tradeoffs and tech debt taken on
to ship it. It is not a step-by-step playbook for a third jurisdiction; see
"What generalizes vs what is source-specific" at the end for that orientation.

## Jurisdiction boundary

`source_system` (e.g. `legistar.sanjose`, `simbli.sjusd`) identifies the upstream
adapter. It is necessary but not sufficient to express the public product
boundary, so a first-class `Civic::Jurisdiction` was added:

- `civic_jurisdictions` table: `slug`, `name`, `kind` (`city`, `school_district`,
  ...), `primary_host`, optional `source_system_default`. Seeded with `sanjose`
  and `sjusd`.
- `civic_jurisdiction_id` foreign key on the four public civic tables
  (`civic_events`, `civic_event_items`, `civic_matters`,
  `civic_matter_attachments`). The `JurisdictionScoped` concern adds the
  association, derives the jurisdiction from `source_system` on validation, and
  provides a `for_jurisdiction` scope.
- `ingestion_source_snapshots` deliberately does **not** carry the FK. It is the
  highest-volume, ingestion-internal table, and jurisdiction is derivable from
  its existing `source_system` column. Generated/extracted records likewise
  derive jurisdiction through their target/source associations rather than
  carrying their own column.

The public read path resolves the active jurisdiction from the request host:
`ApplicationController#current_jurisdiction` maps `request.host` to a
`Civic::Jurisdiction.primary_host`, falling back to the default (`sanjose`) for
unknown hosts (localhost, IP, previews), so development and single-host behavior
are unchanged. Public controllers, cache versions, and Data Health are all
scoped by `current_jurisdiction`.

## Generic source identity

The original schema was Legistar-shaped: `legistar_event_id`,
`legistar_matter_id`, etc. were `NOT NULL` and uniqueness was
`(source_system, legistar_*_id)`. A Simbli row could not be inserted under those
constraints. The generalization:

- Added generic `source_*_id` **string** columns (`source_event_id`,
  `source_event_item_id`, `source_matter_id`, `source_attachment_id`). Uniqueness
  moved to `(source_system, source_*_id)`.
- The `SourceIdentified` concern declares a row's generic + legacy identity and
  validates the generic id plus `source_system`.
- The `legistar_*_id` columns were kept (now nullable) and backfilled into the
  generic columns, rather than dropped in the same change. Removing them is
  deferred cleanup.

String ids (not bigint) were chosen so the column matches
`ingestion_source_snapshots.source_id`, survives non-numeric future sources, and
can hold a **composite** natural key. Simbli's public interface does not expose a
globally unique id for an attachment or item, so durable identity is composite:

- `source_event_id` = `"#{S}:#{MID}"`
- `source_event_item_id` = `"#{S}:#{MID}:#{item_id}"`
- `source_attachment_id` = `"#{S}:#{MID}:#{AID}"` (matches the
  `Attachment.aspx?S=&MID=&AID=` URL)

Ephemeral, session-scoped Simbli tokens (`sct`, `endid`, `enmid`, ...) are never
persisted as identity; they are valid only for one browser session and are
re-derived each sync. Durable identity uses the stable numeric ids (`MID`,
agenda item `ID`, `AID`).

SJUSD has no Legistar-style "matter" concept, so the adapter creates one
**synthetic** `Civic::Matter` per agenda item with substantive content or
attachments, keyed by a collision-proof `matter_file` of the form
`SJUSD-<mid>-<itemid>`. This lets the existing attachment, extraction, summary,
and Pulse machinery work with minimal branching, at the cost of slightly
stretching the "matter" concept.

## Host-scoped UI and per-jurisdiction copy

The design system is shared; the copy is jurisdiction-aware. `Civic::Jurisdiction`
exposes a small presentation API (`short_name`, `site_title`, `tagline`,
`default_description`, `all_scope_label`, `governing_bodies_phrase`,
`civic_subject`, `source_host`, `ingestion_source_label`), keyed off `kind` so a
future jurisdiction of the same kind needs no new branches. The topbar, footer,
Pulse, meetings/matters/events pages, and page metadata all read from it, so the
SJUSD host never reads as San Jose city government.

Two areas are genuinely jurisdiction-specific **content**, not label swaps, and
are rendered from per-jurisdiction partials selected by `current_jurisdiction`:

- the civics **glossary** (`app/views/public/glossary/_sanjose.html.erb` vs
  `_sjusd.html.erb`, with a shared `_shared_terms` partial). The city content is
  preserved verbatim; the SJUSD glossary covers Board of Education concepts and
  cites the SJUSD board page, CSBA, and the Brown Act.
- the Data Health **"About this page"** source detail
  (`_sources_sanjose` vs `_sources_sjusd`).

## Per-jurisdiction themes and Pulse

The Pulse theme vocabulary is per-jurisdiction by design: a city and a school
district frame their work around different topics.

- `Civic::ThemeTaxonomy` is a registry (`SANJOSE`, `SJUSD`) resolved by a matter's
  jurisdiction. The same slug may appear in more than one list because slugs are
  validated per jurisdiction.
- `Generated::ClassifyMatterThemes` resolves the prompt **and its VERSION** by
  jurisdiction (`PROMPTS_BY_JURISDICTION`: `MatterThemesV1` for the city,
  `SjusdMatterThemesV1` for SJUSD, both extending `MatterThemesBase`). Because
  `prompt_version` is part of the `generated_artifacts` idempotency key, the two
  jurisdictions' classifications never collide, and editing one taxonomy
  re-tags only that jurisdiction.
- `Generated::ThemesClient` is taxonomy-agnostic (it does not know the matter);
  filtering returned slugs against the vocabulary is the service's job.
- `Public::ThemePulse`, `MattersController`, and `DataHealth::Snapshot` all
  resolve labels and the current prompt version per jurisdiction.

The shared classification pipeline writes the artifact and its
`civic_matter_themes` projection **atomically**, adopts a concurrently-written
artifact on a unique-key race instead of inserting a duplicate, and never
downgrades a succeeded artifact to failed. This was added after the SJUSD
backfill exposed a latent concurrency bug (see Tradeoffs).

## Simbli ingestion: the browser worker

Unlike Legistar's open HTTP API, Simbli is a third-party vendor platform behind
Incapsula anti-bot protection. Plain Ruby HTTP from the VPS receives the
Incapsula interstitial; a real browser does not.

- The reverse-engineered interface contract is
  `SB_MeetingListing.aspx` -> `ViewMeeting.aspx` -> `GetItemsTreeDTO` (agenda) ->
  `GetSupportingDocuments` -> `Attachment.aspx?S=&AID=&MID=`.
- `lib/simbli/fetch.mjs` is a small Node + Playwright (Chromium) script that
  drives that flow and emits JSON. The Ruby `Simbli::Client` shells out to it via
  `Open3` behind an injectable seam, so `Ingestion::Simbli::SyncMeeting` consumes
  a normal Ruby object and tests inject a fake.
- The jobs image installs Node + Playwright + Chromium. Browser work runs on a
  dedicated low-concurrency `simbli_ingestion` queue (one thread) so it never
  runs parallel browsers or competes with the city's HTTP ingestion.
- An Incapsula/anti-bot interstitial is treated as a hard, recorded failure, not
  an empty-but-successful result, so a block never reads as "no new meetings"
  and silently drops data.
- A daily recurring job discovers and re-syncs recent meetings with a small
  limit; the historical backfill was a one-off manual run.

## Attachments: manual recovery only (SJUSD)

Incapsula tolerates metadata fetches from the VPS but returns HTTP 403 on
attachment PDF downloads. So for SJUSD we **do not attempt automated downloads**
(a doomed 403 round-trip per attachment would waste requests and flood the
operator worklist). Instead:

- Attachment metadata and the original `Attachment.aspx` URL are stored, and the
  public UI links to the source (the `simbli.eboardsolutions.com` host is on the
  `official_source_url` allowlist).
- `attachments:needs_manual_upload JURISDICTION=sjusd` lists fileless attachments
  on demand via the jurisdiction-scoped `awaiting_file` scope (no recorded error,
  excludes anything already manually imported), and `attachments:manual_upload`
  attaches a recovered PDF and enqueues extraction. Both are source-agnostic.

The consequence is that SJUSD document intelligence (extracted text, AI
summaries) stays sparse until an operator selectively recovers PDFs. Meeting,
agenda, matter, and source-link coverage is complete; document-derived signal is
opt-in.

## Deployment

`kamal-proxy` serves both hosts from one VPS via a `proxy.hosts` array with a
per-host Let's Encrypt certificate (chosen over Cloudflare-terminated TLS for
simplicity and no new dependency). Both hosts sit behind Cloudflare; the `/data`
Cloudflare Cache Rule is path-based and covers both hosts because Cloudflare
keys its cache per host.

## Tradeoffs and tech debt

These were taken on knowingly. They are listed so a future maintainer
understands the shape of the debt before deciding whether to pay it down.

- **Two-language browser seam.** The Node + Playwright script and a larger jobs
  image are deliberate, boundaried debt. The spike proved the Node/Playwright
  path against Incapsula; rewriting that fragile anti-bot logic in Ruby
  (`playwright-ruby-client`, Ferrum, Selenium) would reintroduce risk on the
  hardest part. The debt is isolated behind `Simbli::Client`, so repayment is
  swapping the client internals, not unpicking it from the domain, and it may
  never need paying.

- **100% manual attachment recovery for SJUSD.** PDFs cannot be fetched from the
  VPS (Incapsula 403). There is no automated path; document intelligence depends
  on an operator running the manual-upload flow. This is the same human-in-the-
  loop tooling already used for occasionally-blocked Legistar downloads, now
  generalized, but for SJUSD it is the rule rather than the exception.

- **Unsanctioned vendor source.** Simbli/eBoardSolutions is a third-party platform
  with active anti-bot protection. The records are public, but the access path is
  not sanctioned the way Legistar's open feed is. Stay a polite, low-rate guest
  (conservative cadence, small limits), prefer an official channel if one ever
  appears, and revisit if the vendor signals objection.

- **Synthetic matters.** SJUSD has no native "matter," so we mint one per agenda
  item. It keeps the shared pipeline working but means "matter" is a slightly
  looser concept across jurisdictions.

- **Retained Legistar columns.** `legistar_*_id` columns remain (nullable)
  alongside the generic `source_*_id` columns. Dropping them is deferred until
  all call sites are confirmed migrated.

- **Let's Encrypt behind Cloudflare.** Per-host LE issuance requires the host to
  be DNS-only (grey cloud) during the ACME challenge, because the Cloudflare
  proxy terminates TLS and the challenge cannot reach the origin otherwise.
  Renewals (~60 days) hit the same wall. The standing options are to briefly
  grey-cloud for issuance/renewal or to move to Cloudflare-terminated TLS
  (`ssl: false`), which is deferred.

- **Shared classification concurrency.** Theme classification is a shared,
  skip-aware pipeline, so the unscoped recurring backfill auto-classifies any
  jurisdiction's unclassified matters. The first large SJUSD run exposed a race
  on the artifact idempotency key (two processes classifying the same matter)
  that also downgraded good artifacts to failed. It is fixed (atomic persist,
  adopt-on-race, no-downgrade), but note two operational facts: `kamal app exec`
  without `--roles` fans out to **both** the web and jobs containers (run one-off
  rake with `--roles web`), and the recurring job can overlap a manual run
  (now harmless).

## What generalizes vs what is source-specific

For orientation, not as a recipe:

- **Generalizes (no per-jurisdiction code):** the jurisdiction model and host
  scoping, generic source identity, the presentation API keyed off `kind`, the
  per-jurisdiction taxonomy/prompt registry, the manual-upload tooling, and the
  attachment/extraction/summary pipeline.
- **Source-specific (new code per source):** an ingestion adapter (HTTP client or
  browser script) and its parsers, the identity scheme for that source, the
  glossary and Data Health source partials, and the taxonomy + prompt for that
  jurisdiction. A non-Legistar, non-Simbli source also needs its own outbound
  trust/runtime story.
