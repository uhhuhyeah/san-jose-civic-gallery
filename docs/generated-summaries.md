# Generated Attachment Summaries

Generated summaries are assistive artifacts. They never overwrite
official `Civic::*` records or extracted `Documents::*` text.

## Configuration

The summary client uses an OpenAI-compatible chat completions endpoint.
Configure it with environment variables:

```bash
export GENERATED_SUMMARY_API_KEY=...
export GENERATED_SUMMARY_API_BASE=https://api.openai.com/v1
export GENERATED_SUMMARY_MODEL=gpt-4o-mini
```

For an OpenRouter-style endpoint, point the same client at that API
base and model name:

```bash
export GENERATED_SUMMARY_API_BASE=https://openrouter.ai/api/v1
export GENERATED_SUMMARY_MODEL=provider/model-name
```

Optional controls:

- `GENERATED_SUMMARY_TIMEOUT_SECONDS`: request timeout, default `30`
- `GENERATED_SUMMARY_MAX_INPUT_CHARS`: extracted text sent per request,
  default `18000`

## Dry Run

List candidate attachments without calling a model:

```bash
bin/rails generated:summarize_attachments
```

Limit the batch:

```bash
LIMIT=25 bin/rails generated:summarize_attachments
```

## Generate Summaries

Run generation for the selected batch:

```bash
RUN=true LIMIT=10 bin/rails generated:summarize_attachments
```

The task finds matter attachments with successful extracted text and no
successful generated attachment summary for the configured model and
prompt version.

Use `FORCE=true` to include attachments that already have a summary for
the configured model and prompt version:

```bash
RUN=true FORCE=true LIMIT=10 bin/rails generated:summarize_attachments
```

Each attempt writes a `Generated::Artifact` row with target, source
artifact, model identifier, prompt version, input digest, status,
content, usage metadata, and error details. This keeps provider and
model experiments auditable.

## Provenance and idempotency

`Generated::Artifact` rows are unique per `(target, kind,
model_identifier, prompt_version, input_sha256)`. `input_sha256` hashes
the actual text sent to the model after truncation, so:

- regenerating with the same model, prompt version, and extracted
  content reuses the existing artifact
- changing the model identifier, prompt version, or extracted content
  produces a fresh artifact alongside the old one

`input_metadata` records the source extractor, source file checksum,
the extracted character count, the character count and SHA-256 of the
content actually sent to the model, and a `truncated` flag. When
`truncated` is true, a `…[truncated]` marker is appended to the sent
text so the model can note the cutoff in its `limitations`.

## Known limitations

**Prompt injection.** Extracted text comes from arbitrary public PDFs
and may contain content crafted to manipulate the model. The prompt
wraps the extracted text in `<source_text>` ... `</source_text>` tags
and tells the system prompt that anything inside the tags is data, not
instructions. This raises the bar but is not bulletproof — treat all
generated summaries as assistive, surface them with explicit
"generated" labels in UI, and prefer the underlying official records
for anything load-bearing.

**Response shape is normalized, but not content quality.** The client
rejects responses that aren't JSON or that omit required keys. It stores
`summary`, `key_points`, `limitations`, and `document_status`, coercing
`key_points` and `limitations` into arrays and normalizing
`document_status` to `draft`, `final`, or `unknown`. It does not score
quality. Run small batches and spot-check before scaling.

## Public UI states

Matter attachment pages show generated summaries as an assistive layer
under the official attachment metadata and extracted text preview.

- `Generated summary available`: a successful current
  `attachment_summary` artifact exists for the attachment and prompt
  version. The UI displays the summary, key points, limitations,
  document status when useful, model identifier, and a reminder to
  review the official source document.
- `Generated summary pending`: the attachment has successful extracted
  text but no current successful generated summary. Run
  `RUN=true bin/rails generated:summarize_attachments` to produce it.
- `Generated summary not available`: the source file is not imported,
  extraction has not run, extraction failed, or extraction found no
  usable text.

Failed `Generated::Artifact` rows (status `failed`, e.g. the model call
errored) are not surfaced publicly; the UI treats them the same as
`pending` until a successful artifact exists. Operators see failures
via the rake task output and the artifact rows.

Generated summary content may become an additional search signal later,
especially via tags/topics derived from generated artifacts. Keep that
separate from official-record search and label it as generated-derived
ranking or filtering.
