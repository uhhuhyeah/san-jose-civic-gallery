# Background Queues

San Jose Civic Gallery uses Solid Queue with a small number of purpose-built
queues. The goal is not maximum parallelism; it is predictable isolation so one
kind of slow work cannot block the rest of the source-ingestion pipeline.

Queue workers are configured in `config/queue.yml`. Recurring production tasks
are configured in `config/recurring.yml`.

## Queue Responsibilities

| Queue | Threads | Responsibility |
| --- | ---: | --- |
| `default` | 3 | Normal ingestion, matter reconciliation, attachment imports, and file revalidation |
| `solid_queue_recurring` | 1 | Solid Queue recurring scheduler command jobs and orchestration |
| `generated_summary` | 1 | External model calls for generated attachment summaries |
| `slow_extract` | 1 | PDF text extraction and OCR/subprocess-heavy document work |

## Why These Queues Exist

`default` is the main pipeline queue. It handles many small-to-medium jobs:
syncing recent events, syncing event items, refreshing matters, syncing matter
attachments, downloading source files, and revalidating imported files. It has
more concurrency than the other queues because most of that work is network or
database IO and the app should keep ingesting while some requests wait.

`solid_queue_recurring` is for the recurring scheduler. Keep this queue focused
on orchestration. It is safe for small maintenance commands, but long
application batches should be represented as application jobs on their own
queues. Otherwise a deploy, worker restart, or stale heartbeat can fail the
entire recurring command and make retries harder to reason about.

`generated_summary` isolates AI summary generation. Summary work calls an
external model API, can be slow, can be rate-limited, and may fail for reasons
unrelated to ingestion. Running it on one thread prevents model calls from
consuming the normal ingestion queue or all database connections.

`slow_extract` isolates document text extraction. PDF extraction and OCR can be
CPU-heavy, memory-heavy, or subprocess-heavy. Keeping it single-threaded means a
large scanned document cannot starve normal ingestion, imports, or summary
generation.

## Operational Notes

Recurring summary generation should enqueue `Generated::BackfillAttachmentSummariesJob`
instead of running `Generated::BackfillAttachmentSummaries.call(...)` inline as a
recurring command. The job is idempotent at the service layer: it skips
attachments that already have a successful summary for the configured model and
prompt version unless forced.

When adding a new background job:

- use `default` for ordinary ingestion/import/revalidation work
- use `slow_extract` for expensive local document processing
- use `generated_summary` for model API calls or summary backfills
- avoid putting long application batches directly on `solid_queue_recurring`

When tuning production capacity, account for database connections across all
workers. This app uses database-backed queueing and caching, so adding worker
threads can improve throughput but also increases pressure on the Postgres /
Supabase connection pool.
