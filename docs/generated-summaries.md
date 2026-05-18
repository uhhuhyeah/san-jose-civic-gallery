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
content, and error details. This keeps provider and model experiments
auditable.
