# Alpha.5 checkpoint — 2026-10-18

Versions: Law 2.0.0-alpha.5 / Justice 0.1.0-alpha.5.

- Read three active character UUIDs from MariaDB with an explicitly read-only
  transaction. Private `/tmp` fixture passes them into the offline suites. No
  character, custody, warrant, balance or shared configuration was changed live.
- Typed custody reservation, physical-arrival confirmation and explicit release;
  one active subject slot; additive migration 005. Confirmation serves the arrest
  warrant atomically with custody and transactional audit/outbox/receipt.
- Law server guards UUID target session, physical facility proximity, same instance,
  source reuse and finite positions. No client coordinates/target IDs are accepted.
- Native MDT custody view/forms and receipt recovery that works after target logout
  or departure, while preserving actor ownership, case access and department scope.
- 30 typed Law RPC routes. Staging grants updated as inactive fragments only.

Validation with the database-derived UUID fixture: Justice 278 + lifecycle 15;
Law 169 + lifecycle 10 + client 14 + installed Contracts identity 12 = **498 Lua
assertions**. Browser logic also verifies historical custody receipt recovery and
retention of uncertain payment IDs. JavaScript syntax/manifests/native scan pass.
Actual MariaDB custody writes, locking and Cfx physical acceptance were not run.

This implements custody records and manual booking confirmation, not timed jail.
No teleport, respawn, restraints, sentence, automatic release/offline reduction,
community service or warrantless booking is added. A player must be brought to the
configured facility. `jail=0` remains accurate. Next: staging validation and the
reviewed placement/reconnect + sentence lifecycle, respecting Character ownership.

Acceptance-command follow-up: `LawAcceptanceTest` now emits per-check PASS/FAIL/SKIP
and a final tally. It provides read-only preflight/resume, a tagged legal fixture,
explicit finance/custody modes and scoped retryable cleanup. No live acceptance
command was executed during implementation. Offline total is now 525 assertions,
including 25 orchestration checks; both generated and database-derived UUID fixtures
pass. See `ACCEPTANCE_TESTS.md` for commands, permissions, writes and limits.

Live-preflight integration follow-up: Jobs/Licenses configs now trust Law as a
reader only. Admin loads a narrow owner-only staging policy for the 23 explicit
Justice player actions, checking Core-authenticated broker/principal and current
session before/after the existing `roles.assignment.manage` entitlement. The fixed
90-capability Admin catalog and its migration IDs are untouched; global case
view/manage overrides remain unrecognized. Law explicitly delegates its resource
principal in policy context. No roles, on-duty assignments or commissions are
created. Missing commission data now skips the dependent scope diagnostic.
Offline total: 608 assertions, including 82 installed policy/config integration
checks and 26 acceptance orchestration checks. Runtime restarts and live preflight
are still performed by the operator; no live acceptance was run by the agent.
