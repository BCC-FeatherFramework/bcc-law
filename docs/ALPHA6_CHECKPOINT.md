# Alpha.6 checkpoint — 2026-10-19

Law version: 2.0.0-alpha.6. Justice files were not changed; its implementation
is being handled separately by Claude. This checkpoint is not full release acceptance.

## Implemented

- Four typed Core routes: own restraint snapshot, apply, release, escort.
  Law now registers 34 routes. There is no client mutation event or client position input.
- Apply requires active duty, commission, `law.restraint.manage`, current actor
  and subject sessions, the same routing bucket, living peds within 3 units,
  and an accessible active Justice arrest warrant matching jurisdiction and subject.
- Apply retries keep the original 15-minute maximum. Escort uses explicit on/off
  state, belongs to the restraining officer, and stops beyond 6 units. Authorized
  nearby officers from the same department can remove cuffs.
- The two-second sweep reevaluates duty, commission, policy, warrant and sessions.
  Revocation, expiry, death, disconnect, timeout or dependency loss clears physical
  restraints. It never changes a custody record, warrant, financial record or sentence.
- Client snapshots use the current authenticated character's own RPC. Logout,
  dependency stop, failed polling or a five-second stale snapshot clears native
  cuffs/firing restrictions/attachment. No remote net event can toggle cuffs.
- MDT `Teren` forms and `/lawcuff`, `/lawuncuff`, `/lawescort` commands. The UI uses
  explicit desired state, without pretending these ephemeral interactions have
  durable legal-operation receipts. Repeat only against the intended current player.
- Admin's existing owner-only staging action allowlist includes
  `law.restraint.manage`. No role assignments or fixed capability catalog changed.

## Sentence policy agreed with the user

Sentence time **continues while offline**. Future placement/reconnect logic must
consume Justice's authoritative UTC deadline and current sentence status. It must
not restart the original duration on reconnect, invent a local legal sentence,
or trust a client's clock/time decrement. Justice still advertises `sentences=0`
in the inspected implementation, so timed jail is not wired to imaginary exports.

The exact sentence/read/execution APIs, expected revisions, operation recovery,
expiry/release authority, concurrency and failure semantics must be supplied by
Justice before Law can implement that consumer. Community service requires its
own authoritative task/progress contract; offline elapsed time must not fabricate
completed tasks.

## Verification and open gates

The Lua suite includes access/physics/retry/session/lifecycle checks and native
client cleanup mocks. Browser checks cover fixed physical routes and exclusion
of durable request IDs from physical state changes. These are offline tests.

Executed 2026-10-19: `python3 tests/run_lua.py` — 389 assertions pass;
`node tests/ui.cjs` — pass; `node --check ui/app.js` — pass. The Lua runner
syntax-checks every resource Lua file before execution. Runtime/config/UI scan
found no legacy framework, legacy menu, direct-currency or numeric-character
identifier references. These results do not include Justice's separate suite.

No database migration, server restart, live grant, staging legal record or financial
change was performed. Two-player RedM acceptance is still required. This slice
does not finish timed jail, service, search/confiscation, evidence, armory, payroll,
alerts, doors, import or production officer/judge policy.

Inventory's `GrantCharacterItemOnce` is available for trusted callers and ordinary
stack items, with durable payload-bound receipts. It rejects unique/weapon items
(`unique_requires_issuer`). Law is not currently trusted for these grants. A full
armory must use Weapons for issued weapons, reviewed stock/limits and recoverable
fulfillment; no direct item/native-weapon grant shortcut was added here.
