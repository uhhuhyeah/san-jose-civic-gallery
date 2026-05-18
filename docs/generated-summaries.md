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

For an OpenRouter-style endpoint, keep the application setting name
provider-neutral: put the active provider key in
`GENERATED_SUMMARY_API_KEY`, then point the same client at that API base
and model name:

```bash
export GENERATED_SUMMARY_API_KEY=...
export GENERATED_SUMMARY_API_BASE=https://openrouter.ai/api/v1
export GENERATED_SUMMARY_MODEL=openai/gpt-4o-mini
```

Use direct OpenAI by default for fewer routing variables. Use
OpenRouter when provider-level spend caps, model comparison, or easier
fallback testing are more important than minimizing provider layers.
Generated artifacts record `model_identifier`, prompt version, input
digest, usage metadata, and status either way.

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

## Local model evaluation

Use `script/evaluate_generated_summaries` to compare model output
without writing `Generated::Artifact` rows. The script loads `.env.local`,
uses the same attachment summary prompt, and writes JSON and Markdown
reports to `tmp/generated_summary_evals/`.

Dry-run the selected attachments without calling a model:

```bash
LIMIT=5 script/evaluate_generated_summaries
```

Call the configured model:

```bash
RUN=true LIMIT=3 EVAL_MODEL=openai/gpt-4o-mini script/evaluate_generated_summaries
```

For OpenRouter, set `OPENROUTER_API_KEY` in `.env.local` and pass an
OpenRouter model id with `EVAL_MODEL`. When `EVAL_MODEL` and
`OPENROUTER_API_KEY` are both present, the script uses OpenRouter even
if `.env.local` also contains `GENERATED_SUMMARY_API_KEY`. You can also
set `EVAL_PROVIDER=openrouter` explicitly. The script defaults the API
base to `https://openrouter.ai/api/v1` for OpenRouter runs.

Useful controls:

- `ATTACHMENT_IDS=1,2,3`: evaluate specific attachments
- `FORCE=true`: include attachments that already have successful
  summaries for the selected model and prompt
- `EVAL_MAX_INPUT_CHARS=18000`: override prompt truncation
- `EVAL_TIMEOUT_SECONDS=60`: override request timeout
- `EVAL_INPUT_USD_PER_1M` and `EVAL_OUTPUT_USD_PER_1M`: optionally
  estimate cost from returned token usage

### Evaluation notes: 2026-05-18

We ran a one-document OpenRouter evaluation against attachment `23`
(`26-578`, First Amendment to the Brown Marketing Strategies/CENTRIC
consultant agreement). Full JSON and Markdown reports were written under
`tmp/generated_summary_evals/` and are intentionally not committed.

Models tested:

- `openai/gpt-4o-mini`
- `openai/gpt-4o`
- `deepseek/deepseek-chat-v3.1`
- `deepseek/deepseek-v4-flash`
- `qwen/qwen3-235b-a22b-2507`
- `google/gemini-3.1-flash-lite`
- `moonshotai/kimi-k2.6`

Outcome:

- Keep `openai/gpt-4o-mini` as the default baseline for now. It
  produced clean JSON, correctly handled draft status, and was cheap
  enough for expected summary batches.
- `deepseek/deepseek-chat-v3.1` produced a strong summary with useful
  limitations, but was slower and cost roughly twice the tested
  `gpt-4o-mini` run.
- `deepseek/deepseek-v4-flash` was cheaper than `gpt-4o-mini` and
  detailed, but its summary did not explicitly say the document appeared
  to be a draft even though `document_status` was `draft`. Keep it as a
  candidate for broader testing, not the default.
- `google/gemini-3.1-flash-lite` was fast and clean but produced a
  thinner summary.
- `openai/gpt-4o` was much more expensive without a clear quality gain
  on this sample.
- `moonshotai/kimi-k2.6` produced the most detailed output, but was too
  slow and expensive for default batch use.
- `qwen/qwen3-235b-a22b-2507` failed during this run because the
  endpoint returned malformed JSON.

Decision:

- Keep production defaulted to direct OpenAI `gpt-4o-mini` for fewer
  provider-routing variables.
- Keep the production client provider-neutral through
  `GENERATED_SUMMARY_API_BASE`, `GENERATED_SUMMARY_API_KEY`, and
  `GENERATED_SUMMARY_MODEL`.
- Use OpenRouter primarily for local model evaluation and optional future
  fallback testing.

### QA notes: 2026-05-18

We ran the production summary task locally with direct OpenAI
`gpt-4o-mini` against the only attachment in the local database with an
imported source file and successful extracted text:

```bash
RUN=true LIMIT=10 bin/rails generated:summarize_attachments
```

The initial `attachment_summary_v2` output surfaced two quality issues:

- The model returned `document_status: draft`, but the summary text did
  not explicitly say the document appeared to be a draft.
- The model treated an unfilled consultant name-change placeholder as if
  a completed name change had occurred.

The prompt was tightened and bumped to `attachment_summary_v3` so future
artifacts are distinct. The v3 prompt now requires draft language in the
summary itself and tells the model to treat blank fields, underscore
lines, bracketed placeholders, and unfilled form options as missing
information rather than completed facts.
