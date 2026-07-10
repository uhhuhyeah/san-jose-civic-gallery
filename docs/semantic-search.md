# Semantic Search

Semantic search adds embedding-backed discovery to the existing matters search.
It is designed to improve recall for concept queries such as "tenant
protection", "bike lanes", or "affordable housing" when the official record uses
different wording.

This feature is a ranking and discovery aid. It does not replace official
records, extracted text, generated summaries, or the existing Postgres full-text
search. Public results still land on matter pages and keep generated-derived
matches labeled.

## What Exists

Semantic search currently has two shipped pieces:

- Summary embedding backfill: successful `attachment_summary` and
  `event_summary` `Generated::Artifact` rows are embedded into
  `search_embeddings`.
- Query-time matters search: when `SEMANTIC_SEARCH_ENABLED=true`,
  `/public/matters?q=...` embeds the user's query, finds nearby summary
  embeddings, and appends semantic-only matter matches after keyword results.

Extracted-text chunk embeddings are not implemented yet. The full text of PDFs
still participates through the existing keyword search path in
`Documents::ExtractedText`.

## Data Model

Embeddings live in `search_embeddings`, represented by `Search::Embedding`.

Important columns:

- `civic_jurisdiction_id`: keeps search scoped to one public site.
- `source_record_type` / `source_record_id`: the artifact that was embedded,
  currently `Generated::Artifact`.
- `result_record_type` / `result_record_id`: the public record the match should
  return, currently `Civic::Matter` for attachment summaries and `Civic::Event`
  for event summaries.
- `source_kind`: currently `attachment_summary` or `event_summary` for public
  semantic search. The model also allows future `extracted_text_chunk` and
  `matter_themes` rows.
- `content_sha256`: digest of the exact text sent to the embedding model.
- `embedding_model` and `embedding_dimensions`: identify vector compatibility.
- `embedding`: pgvector `vector(1536)`.
- `metadata`: JSON provenance from the source artifact.
- `embedded_at`: when the vector was produced.

The idempotency index is:

```text
source_record_type, source_record_id, source_kind, chunk_index,
embedding_model, content_sha256
```

That means unchanged input for the same source artifact and model reuses the
existing row. If the generated summary content changes, `content_sha256` changes
and a new embedding row can be created without overwriting the old one.

The database requires the `vector` extension. Local development uses the
pgvector-enabled Postgres image in `compose.yaml`; production uses Supabase with
the extension enabled.

## Backfill Pipeline

The summary backfill flow is:

1. `Search::BackfillSummaryEmbeddings` selects succeeded
   `Generated::Artifact` rows of kind `attachment_summary` and `event_summary`.
2. `Search::BuildEmbeddingInput` turns the artifact JSON into structured plain
   text. This is intentionally not raw JSON.
3. `Search::EmbeddingClient` calls the configured OpenAI-compatible embeddings
   endpoint.
4. `Search::UpsertEmbedding` writes or reuses a `Search::Embedding` row.

For `attachment_summary`, the result record is the owning `Civic::Matter`.
For `event_summary`, the result record is the `Civic::Event`; query-time search
then expands that event to its current linked matters through
`Civic::EventItem.current_from_source`.

### Rake Tasks

Dry-run candidate selection:

```bash
bin/rails search:embed_summaries
```

Embed a real batch:

```bash
DRY_RUN=false LIMIT=250 bin/rails search:embed_summaries
```

Force regeneration against already-embedded artifacts:

```bash
DRY_RUN=false FORCE=true LIMIT=25 bin/rails search:embed_summaries
```

Inspect the exact embedding input for one artifact:

```bash
ARTIFACT_ID=123 bin/rails search:embed_artifact
```

When running through Kamal, prefix env vars with `env` so Docker does not try to
execute the variable name as the command:

```bash
kamal app exec --roles web "env DRY_RUN=false LIMIT=250 bin/rails search:embed_summaries"
```

The backfill is safe to run while `SEMANTIC_SEARCH_ENABLED=false`; it only
populates `search_embeddings` and does not alter public search behavior.

## Query-Time Search

`Public::MattersController#index` still starts with the keyword/document search
pipeline:

1. Metadata full-text search on `Civic::Matter.searchable_text`.
2. Latest successful extracted-text keyword matches.
3. Theme filtering, if selected.
4. Short-TTL cached ID lists.

When semantic search is enabled and the query is nonblank, the controller also
calls `Search::SemanticMatterSearch` inside the same cached ID block. Semantic
matches are cached with the existing 5-minute index cache, keyed by the normal
matters cache key plus the semantic config digest.

`Search::SemanticMatterSearch`:

1. Embeds the user's query with `Search::EmbeddingClient`.
2. Searches `Search::Embedding` rows for the current jurisdiction only.
3. Restricts public semantic matching to `attachment_summary` and
   `event_summary`.
4. Uses cosine nearest-neighbor search with `SEMANTIC_SEARCH_MAX_DISTANCE`.
5. Resolves direct matter matches.
6. Resolves event matches to current linked matters.
7. Deduplicates by matter id and keeps the nearest match.

The controller appends semantic-only matter IDs after keyword IDs. Keyword
matches keep their existing order and are not displaced by semantic matches.
When a theme is selected, semantic matches are filtered to matters with that
theme before merging.

If query embedding fails because the API key is missing, the provider times out,
or the provider returns an error, the service logs a warning and returns no
semantic matches. The public page falls back to keyword-only results.

## Public UI

Semantic matches render in the matters index with a "Concept match" label and
an AI-assisted summary notice.

Attachment-summary matches show the attachment name:

```text
Via: Memorandum
```

Event-summary matches show the meeting title:

```text
Via meeting: City Council meeting
```

The UI does not invent a natural-language explanation for why a result matched.
It uses stored provenance from the embedded generated artifact, and the matter
link remains the primary destination for verification against official source
material.

## Configuration

Current environment variables:

| Variable | Default / Current Intent |
| --- | --- |
| `SEMANTIC_SEARCH_API_KEY` | Secret API key for the embeddings provider |
| `SEMANTIC_SEARCH_API_BASE` | `https://api.openai.com/v1` |
| `SEMANTIC_SEARCH_EMBEDDING_MODEL` | `text-embedding-3-small` |
| `SEMANTIC_SEARCH_EMBEDDING_DIMENSIONS` | `1536` |
| `SEMANTIC_SEARCH_TIMEOUT_SECONDS` | `30` |
| `SEMANTIC_SEARCH_MAX_INPUT_CHARS` | `8000`; reserved for input limiting |
| `SEMANTIC_SEARCH_ENABLED` | Enables query-time semantic matches when `true` |
| `SEMANTIC_SEARCH_LIMIT` | Number of semantic matches to merge; default `10` |
| `SEMANTIC_SEARCH_MAX_DISTANCE` | Maximum cosine distance; default `0.7` |

`config/deploy.yml` carries the non-secret production values. The API key is a
Kamal secret.

## Tuning Results

The most important tuning lever is `SEMANTIC_SEARCH_MAX_DISTANCE`.

Lower values are stricter:

- fewer semantic-only results
- less drift
- more chance of missing useful synonym matches

Higher values are broader:

- more semantic-only results
- better recall
- more risk of weakly related matches

Early production smoke tests showed:

- `affordable housing` produced strong matches around `0.50` to `0.54`.
- `bike lanes` produced strong matches around `0.52` to `0.61`.
- `tenant protection` produced excellent top matches around `0.61` to `0.64`,
  with weaker housing-adjacent matches appearing closer to `0.67`.

The default `0.7` is intentionally permissive for observation. If the public UI
feels too broad, try `0.65`. If it still drifts, try `0.62`. After changing
`SEMANTIC_SEARCH_MAX_DISTANCE`, redeploy so web containers get the new value.
The matters index cache key includes the distance setting, so enabled search
results will not collide across distance changes.

`SEMANTIC_SEARCH_LIMIT` controls how many semantic matches can be appended after
keyword results. Lower it if pages feel noisy. Raise it only after checking
latency and result quality.

## Smoke Testing

Service-level smoke test without changing the public flag:

```bash
kamal app exec --roles web "env SEMANTIC_SEARCH_ENABLED=true bin/rails runner 'j = Civic::Jurisdiction.find_by!(slug: \"sanjose\"); results = Search::SemanticMatterSearch.call(query: \"affordable housing\", jurisdiction: j); puts results.first(10).map { |r| [r.matter_id, r.source_kind, r.distance, r.provenance].inspect }'"
```

Good smoke-test queries:

- `affordable housing`
- `tenant protection`
- `bike lanes`
- `rent stabilization`
- `small business displacement`

Also test at least one control query that should not produce many good concept
matches. Watch for semantic drift near the configured max distance.

End-to-end public smoke test:

1. Set `SEMANTIC_SEARCH_ENABLED: "true"` in `config/deploy.yml`.
2. Deploy.
3. Visit `/public/matters?q=...`.
4. Confirm keyword results still appear first.
5. Confirm semantic-only rows have "Concept match" provenance.
6. Confirm theme filters do not leak unrelated semantic matches.

## Maintenance

Run `search:embed_summaries` after a large summary backfill, prompt-version
change, or model change. The task skips already-embedded artifacts unless
`FORCE=true`.

Recurring embedding backfill is not currently scheduled. If semantic search
becomes central to the product, add a recurring job for
`Search::BackfillSummaryEmbeddingsJob` on the `generated_summary` queue, with a
small limit and operator-visible failure counts.

When changing the embedding model or dimensions:

1. Confirm the new model's vector size.
2. Update `SEMANTIC_SEARCH_EMBEDDING_MODEL` and
   `SEMANTIC_SEARCH_EMBEDDING_DIMENSIONS`.
3. Add a new migration before changing the `vector(1536)` column if the
   dimensions change. Do not edit the existing migration.
4. Backfill new embeddings. Existing rows remain useful for audit, but query
   search should be constrained to compatible dimensions/model before mixing
   models in production.

When changing generated-summary prompt versions, no schema change is needed.
New `Generated::Artifact` rows get new embedding rows because their input digest
changes.

When deleting or superseding source artifacts, remember that
`search_embeddings` stores polymorphic source/result references but does not
currently have polymorphic foreign keys. Query-time code relies on result record
types and current event-item links, so stale embeddings should be cleaned up if
they become a real operational issue.

## Current Limitations

- Only generated summaries are embedded.
- Query embeddings are not persisted; warm result pages use the short Rails
  cache, but a cold query calls the embedding provider.
- There is no approximate-nearest-neighbor index yet. Current corpus size is
  small enough for the existing query path. Revisit HNSW/IVFFlat indexes when
  embedding row counts grow materially.
- `SEMANTIC_SEARCH_MAX_INPUT_CHARS` is configured but not yet enforced by
  `Search::EmbeddingClient`.
- There is no dedicated semantic-search admin dashboard or usage report.

## Integrity Rules

- Official civic records remain authoritative.
- Generated summaries are assistive and must stay labeled.
- Semantic matches are ranking signals, not claims.
- Results must remain scoped to `Civic::Jurisdiction`.
- Public UI should link users back to official matter, meeting, and attachment
  records for verification.
