# Alpha.7 — read-only search, 2026-10-19

37 typed Law routes. New: `law.search.inspect.v1`,
`law.search.finish.v1`, `law.warrants.search.draft.v1`.

- Inspect payload: `{ department, targetSource, warrantId, cursor? }`.
  Returns up to 25 item instances with ID, revision, definition name and label;
  numeric exclusive cursor. No item metadata, inventory UUID or writable access.
- Finish: same target/department/warrant, plus `expectedRevision`, `requestId`;
  records execution through Justice `ServeWarrant`. Retry the exact same intent.
- Search draft takes the same fields as the arrest draft, but derives `search`
  server-side and checks Justice's `searchWarrants` capability.
- Server checks duty, license, policy, active search warrant/subject/jurisdiction,
  restraint, living nearby peds, bucket and both sessions. Inventory reauthorizes
  before and after its SELECT; changed authority/session discards the result.
- MDT: create a search warrant in the case warrant form, issue it with normal
  authority, then `Teren` → search → explicitly finish execution. Subsequent
  inspection with the now-served warrant is refused.
- `GetCapabilities().value.features.search` requires ready Inventory's new
  `GetLawSearchCapabilities` contract and Justice `searchWarrants=1`.

No evidence collection, transfer, locker, deletion or chain-of-custody claim.
See [contract acknowledgement and remaining evidence gate](JUSTICE_INTEGRATION_REVIEW.md).

Verification: Lua mock suite, browser logic and JS syntax. No DB mutation, live
search, resource restart, role assignment or financial change was performed.
Live staging still needs search/serve/retry, source reuse, movement/uncuff/duty
loss during reads, pagination, other buckets and two-player native acceptance.
