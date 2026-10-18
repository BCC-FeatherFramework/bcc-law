# LawAcceptanceTest — live console results

`LawAcceptanceTest` reports individual checks in the same style as the Banks
acceptance command: aligned `PASS`, `FAIL`, `SKIP`, followed by
`done N passed, N failed, N skipped`. The numbers reflect that run. A dependency,
policy or cleanup failure is never silently counted as a pass. Empty phases and
unrequested financial/physical tests are explicitly skipped.

After updating files, `restart bcc-law` loads the command. It is console-only.
Use actual Character UUIDs, never numeric character IDs. A must have a selected
online Core character and normal Law access. B must exist as an active Character;
B can be offline for the basic legal suite, but its interactive privacy checks
will be skipped. Custody requires both online and physically at the facility.

## Start with read-only preflight

```text
LawAcceptanceTest preflight <A UUID> <B UUID> [department]
```

It checks resource readiness, UUID identity, current sessions, configured department,
Jobs reader trust / on-duty assignment / grade, Licenses reader trust / commission /
scope, jurisdiction readability and individual player policy actions. It creates no
legal fixture, definition, job, commission, capability or currency.
The installed staging policy recognizes 23 Justice player actions only for an
existing staff owner, reusing `roles.assignment.manage`; it grants no new role.
Reader trust is now configured for Law in Jobs/Licenses. Missing real on-duty
assignments or commissions still fail normally. The fixed Admin Authority catalog
is not expanded. `unknown_action` should disappear for this explicit action list;
`forbidden` means the current character lacks the existing owner entitlement. Database status
`active` does not mean the character is connected: use `LawActiveCharacters` to
choose the actual session. Default department is `new_hanover`.

Preflight does not pretend to evaluate service policy as another resource. Explicit
statute creation and financial operations exercise the real owning broker's policy
when those mutation phases run. Setup failures skip the dependent workflow.

## Legal suite — writes auditable test records

On disposable staging, after fixing preflight:

```text
LawAcceptanceTest <A UUID> <B UUID> [freshRunId] [department]
LawAcceptanceTest legal <A UUID> <B UUID> [freshRunId] [department]
```

Omitting runId generates and prints one; otherwise use a fresh token of at most
20 characters. Mutation keys are scoped to A's character UUID and that runId.
Reusing a previous runId is refused; use resume/cleanup instead. Concurrent runs
for the same A are refused.

The suite uses production Law payload validators and handlers and normal Justice
exports. It derives sessions from Core, never forges an offline actor or bypasses
Jobs/Licenses/policy. It checks:

- Test case creation, exact replay, changed-payload conflict, typed read, summary
  revision, stale edit rejection and actor-payload injection rejection.
- Witness/investigator membership and revocation. B's Justice narrative visibility
  is tested only with a current B session, allowed base view policy and no explicit
  global case override; otherwise those checks are SKIP. These are Justice record
  visibility tests, not proof of B's Jobs/Licenses or full MDT access.
- Isolated immutable test statute, charge proposal, frozen statute snapshot,
  filing and withdrawal.
- Arrest warrant draft, issue, read, recall and refusal to serve a recalled warrant.
  Real elapsed expiry is SKIP here; the database clock is never edited.

Cases/statutes are tagged `[TEST]`. Test parties are removed, active test warrants
recalled, charges withdrawn and the case dismissed when child cleanup succeeds.
Audit history/definitions remain; no foreign SQL deletion or arbitrary refund is
used. Only child UUIDs found in this actor/run's original receipts are changed.
Unrecognized records are retained, and unresolved children keep the case editable
for another cleanup attempt. No automatic role, job, license or balance changes.

## Finance and custody — explicitly selected

```text
LawAcceptanceTest finance <A UUID> <B UUID> [freshRunId] [department]
LawAcceptanceTest custody <A UUID> <B UUID> [freshRunId] [department]
```

These also run the legal suite. Finance requests a real **1 minor-unit** citation
and waits up to 20 seconds for Contracts issuance/link, then cancellation. It does
not pay from B's wallet. Contracts readiness, issuer trust, exact service grants,
supported currency and an existing debtor wallet are needed. Lost replies or
pending workers retain the same citation/run identity. If still pending, output
includes the citation UUID and cleanup instructions; inspect `JusticeCitationStatus`
and rerun cleanup after correcting the cause. A debt already paid/defaulted is
never refunded or falsely marked cancelled by cleanup. Wallet payment/double-pay
and the financial journal remain explicit manual staging checks via `/lawfines`
and Contracts diagnostics, reported SKIP by this suite.

Custody creates its own short-lived test warrant and selects the first configured
facility for the department. Both players must meet the production same-instance,
entity, proximity and booking-location guards. It reserves booking, confirms it,
checks the warrant was served atomically, recovers the original booking receipt,
and releases test custody. A location failure is FAIL, not a fabricated physical
pass; cleanup attempts to recall the remaining test warrant. It does not move a
ped, respawn, create a timed sentence or grant authority.

## Restart inspection and recovery

The initial run prints these exact commands with its UUIDs/runId:

```text
LawAcceptanceTest resume <A UUID> <B UUID> <runId> [department]
LawAcceptanceTest cleanup <A UUID> <B UUID> <runId> [department]
```

Run resume after a resource/server restart to inspect the saved case/receipt and
child records. It is read-only, reports current states and skips empty phases;
record readability alone does not demonstrate client focus, physical placement,
a restart itself or financial journal integrity. A still needs its normal session
and current access. A different actor cannot recover A's scoped receipt.

Cleanup writes only this run's known fixture records and is retryable. Keep the
same UUIDs and runId after uncertain outcomes. It will not delete legal history,
mutate an unrelated record on the test case, or turn failed cleanup into success.

## Offline validation

`python3 tests/run_lua.py` also checks acceptance orchestration against mocked APIs:
read-only modes, summary counts, offline sessions, setup denial, lost create replies,
failed cleanup / retry, unrelated records, finance/custody selection, console and
concurrency guards. Those checks are not live acceptance. No live command was
executed automatically while implementing this runner.
