# Native Law / Justice — alpha.2 checkpoint, 2026-10-18

Versions: BCC Law 2.0.0-alpha.2; Justice 0.1.0-alpha.2.

Delivered:

- Charges with validated subject identity, frozen statute snapshot, bounded
  count, proposal/filing/withdrawal/dismissal and actor/revision policy.
- Arrest-warrant drafts, issue/serve/recall/quash, UTC database deadlines,
  expiry at the exact boundary, and effective active-warrant queries.
- Additive checksummed `002_case_links`; the original `001_records` is unchanged.
- Durable receipt/audit/outbox reuse and actor-bound operation recovery for
  charge/warrant records. Original outcome replay never revives authority.
- 15 typed Law routes. Parent-case, department, jurisdiction and actual child
  relationship are checked independently of client-supplied IDs.
- Core event declaration/restart coverage for thirteen committed fact names.
- Law refuses readiness if the Justice provider lacks charge/warrant features.

Executed offline commands (each from its resource):

| Command / suite | Result |
|---|---|
| Justice `python3 tests/run_lua.py`: records/charges/warrants | 133 assertions PASS |
| Same runner: migration/lifecycle | 15 assertions PASS |
| Law `python3 tests/run_lua.py`: access and legal routes | 100 assertions PASS |
| Same runner: provider lifecycle | 10 assertions PASS |
| Same runner: client and installed Menu v2 schema integration | 16 assertions PASS |

Total 274 assertions PASS, plus parsing of all Lua files in each resource.
Fixtures cover invalid targets, cross-jurisdiction statutes, authorization,
scope mismatches, terminal/stale mutations, exact expiry, historical snapshots,
unknown commits, audit/outbox rollback and source/session fencing. They use a
mock database/provider/network; they do not certify MariaDB locking or live UI.

No live resource was started/restarted, no database was changed and no roles,
service grants, Jobs/Licenses/Authority configuration or remote repository were
modified. The original baseline remains preserved outside the runtime folder.

Open: real MariaDB migrations/concurrency/restart, scoped policy and reader trust,
two-player acceptance, charge/warrant editing UI, parties, citations/Contracts,
custody/sentences, evidence, sealing and retention. A served warrant records a
legal fact only; physical arrest and jail execution are not implemented here.
