# Alpha.9 checkpoint — 2026-10-19

This is a reviewable development checkpoint, not completed live release acceptance.

## Implemented

65 typed Core routes cover the earlier case/citation/custody workflows plus
warranted restraints/searches, evidence collection/recovery, rulings, seven sentence
types, sentence lifecycle, privacy/history, physical sentence execution and armory.
Justice owns every legal fact. Contracts owns fine/restitution obligations and
payment; Law has no direct money mutation or foreign-domain SQL.

Police actions require a current on-duty assignment, grade and peace-officer
commission. Judicial actions require the configured judge assignment and judicial
commission; Justice additionally enforces record access and judge participation.
Search/seizure warrant issuance requires judicial qualification. There are no
blanket view_all/manage_all grants. Audit additionally requires Admin permission.
The old staff staging mode remains an explicit configuration option.

## Execution and persistence

Law owns checksum-versioned MySQL tables for placement markers, exact community
service delivery intents and daily armory claims. Startup performs its own schema
migration after DB readiness; this has not been executed against the live server.
Justice tables are never read directly.

Custodial time continues offline using Justice UTC status. Current active sentence
status is reread before server placement/release. A persistent Law placement marker
allows restart recovery; only marked occupants still inside their configured prison
are teleported out. Medical recovery/death postpones physical effects. Provider
failure fails closed. Validate facility entrances, exits and radii in config before
live use; map coordinates are provisional defaults.

`/lawstatus` opens own sentence and task status without officer authority. Community
service requires continuous observed, alive, spawned presence at a configured task
for at least 30 seconds. Leaving, session changes or observation gaps cancel the
attempt. Completed tasks queue durable intents. Ambiguous deliveries retry the same
request/revision; unresolved revision conflicts remain review_required rather than
silently rebasing. Offline time never creates service units.

The armory uses server-configured definitions and per-character/station/item UTC-day
quotas. Inventory grants and Weapons issuance use their idempotent owner APIs;
provider receipts and exact request IDs recover uncertain results. Pending claims
reserve their quota. Weapons must independently advertise secure, idempotent,
payload-bound issuance readiness; this change does not enable unfinished provider
runtime flags. Inspect pending claim history in the MDT before retrying.

## Related resources

Inventory adds read-only warranted inspection, private evidence transfers/receipts,
and Law grant trust. Admin adds qualified policy and narrowly scoped Contracts
issue/cancel grants for Justice. Contracts trusts Justice as an issuer. Medical
adds an exclusively Law-readable current-session condition export. Weapons trusts
Law for its existing secure issuance API. No Justice files were changed.

## Verification and remaining gates

Offline Lua checks cover policy, transport, lifecycle, owner API contracts, custody,
search, evidence, court, execution, persistence and armory. Browser checks cover
safe rendering and exact mutation retries. These use mocks and are not real-SQL or
two-player RedM acceptance. No resources were restarted or live records created.

Before release, run schema/restart recovery and provider acceptance on staging,
verify actual job/license/jurisdiction setup, map coordinates, Medical transitions,
two-player isolation, NUI presentation, jail expiry/reconnect and physical inventory
recovery. Physical evidence return/destruction and complete future movement history,
alerts, door integration and payroll gameplay remain outside this checkpoint.
