# TODO

## Performance

- `Ingestion::SyncEventItemsForEvent` currently performs an N+1 Matter sync for linked items.
  - Current behavior: for each `EventItem` with `EventItemMatterId`, the sync performs a separate Matter fetch.
  - Why it is acceptable for now: the current slice is focused on correctness and provenance, not throughput.
  - Likely follow-up: skip Matter fetches when the local record is fresh enough, batch downstream attachment/history work, or separate Matter refresh into its own queue.
