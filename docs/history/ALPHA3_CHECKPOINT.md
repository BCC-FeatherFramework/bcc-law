# Alpha.3 checkpoint — 2026-10-18

Versions: Law 2.0.0-alpha.3; Justice 0.1.0-alpha.3.

Implemented:
- Typed participant add/remove/list, active slots and retained history, additive
  migration 003, transactional receipts/audit/outbox and two private facts.
- Case creator/participant eligibility on reads, SQL pagination, legal mutations
  and receipt recovery. Defense read-only; witnesses/suspects gain no narrative
  access. Normal operation policy remains mandatory. No default wide overrides.
- 21 bounded native Law RPC routes; case summary/transitions, participant and
  statute routes extend alpha.2's case/charge/arrest-warrant operations.
- Native NUI MDT in Romanian: departments, case creation/details/edit/transition,
  participants, charge proposal/file/dispose and warrant draft/issue/serve/recall/
  quash. Lists paginate. Narrative renders via textContent. Significant changes
  require an in-app confirmation. No legacy Vue endpoints or compatibility shim.
- Single in-flight transport, session epochs, logout/dependency cleanup, retained
  ID/payload retry after unknown results. Retry failures preserve unresolved data.
  Retry state lives only in this open session; close/reopen clears private state.
- Concrete, inactive staging fragments and a two-character/database runbook.
  No shared configs, live database, resource restarts or server.cfg changes.

Offline validation: Lua syntax and suites (Justice 163 + lifecycle 15; Law 121 +
  lifecycle 10 + client transport 10 = 319 assertions); browser logic harness
  checks safe text, stable retry/duplicate protection/rejected retry retention,
  definitive rejection and stale-response fencing; JavaScript syntax checked.
  These use mocked providers, Cfx, JSON fixtures and database. No installed browser
  or RedM session was available for visual/focus acceptance. Real migrations,
  locking/concurrency, native JSON and UI behavior remain staging gates.

Staging is not activated: current Jobs/Licenses lack Law reader trust and current
Admin policy denies Justice actions. The optional owner-only test harness is
not production officer/judge policy and changes Admin catalog counts.

Next: execute the staging runbook and record real evidence. Citation/Contracts,
booking/custody, fines, sentences, cuffs/escort, evidence and remaining police
features stay unimplemented. This is not a finished port or production release.
