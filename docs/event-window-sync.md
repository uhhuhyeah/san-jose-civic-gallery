# Event Window Sync

Use event window sync when you need to reconcile a bounded source window
instead of polling the latest `$top` events.

The default recent sync intentionally does **not** mark older local
events missing. It only sees a sliding window and cannot prove that
older records disappeared from Legistar.

Event window sync is different: it fetches all events for one body and
date range, pages with `$top` / `$skip`, persists current source rows,
and marks previously seen local events in that same window as missing
when they are absent from the fresh source response.

Run it with an explicit half-open date range:

```bash
START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
```

Useful options:

```bash
BODY_NAME="City Council" START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
PAGE_SIZE=50 START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
SYNC_EVENT_ITEMS=off START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
```

Options are environment variables:

- `START_DATE`: inclusive start date, required, `YYYY-MM-DD`.
- `END_DATE`: exclusive end date, required, `YYYY-MM-DD`.
- `BODY_NAME`: Legistar event body name. Default: `City Council`.
- `PAGE_SIZE`: page size for `$top` / `$skip`. Default: `100`.
- `SYNC_EVENT_ITEMS`: `deferred`, `inline`, or `off`. Default:
  `deferred`.

Use half-open ranges so adjacent runs do not overlap:

```text
2026-05-01 <= EventDate < 2026-06-01
2026-06-01 <= EventDate < 2026-07-01
```
