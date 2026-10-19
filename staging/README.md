# Staging setup — current Law/Justice integration

Reference fragments are not loaded by Law. Current workspace configs now include
Law reader trust in Jobs/Licenses, the exact Justice definition-setup service grant,
and an owner-only staging policy in Admin. No live services were restarted and no
player roles, job assignments, commissions, balances or legal records were changed
by these configuration edits. Financial service/issuer fragments remain optional.

1. Use a separate FXServer and disposable MariaDB schema. Start native Core,
   MySQL, Character, Authority/Admin, Jobs and Licenses with their normal
   dependencies, then Justice and Law. Do not start legacy Law writers.
2. Confirm Jobs and Licenses `Config.Access.trustedReaders['bcc-law']=true`.
   Current workspace includes both entries. No registrar/assigner/issuer privilege
   is granted to Law by reader trust.
3. Admin loads `configs/law_acceptance_policy.lua` server-side. Its explicit Justice
   actions require the existing owner-only `roles.assignment.manage` entitlement,
   authenticated bcc-law/Justice callers, delegated `bcc-law` subject, and a current
   selected Core character. It creates no role/capability grants and does not change
   the fixed 90-action Admin catalog or migration IDs. No `view_all/manage_all` is
   enabled. Keep this staging adapter separate from final officer/judge authority;
   set `Config.lawAcceptancePolicy.enabled=false` to disable it. Do not append the
   deprecated `admin-player-policy.lua` to Admin permissions.
4. Through the existing supported Jobs and Licenses workflows, provision:
   `police`, grade ordinal >=0, active on-duty assignments; `peace_officer`
   character licenses with explicitly empty version-1 scope for both testers.
   No fixture here creates or overwrites those definitions or assignments.
5. Console `LawSetupJurisdictions` explicitly creates the configured
   `bcc-law:new_hanover` jurisdiction through Justice. Reusing it is idempotent.
   Statute setup is an explicit server-side Justice `RegisterStatute` call
   by `bcc-law`, using the jurisdiction UUID, a `bcc-law:` recordKey,
   stable requestId/reasonCode/title/description. The MDT reads those definitions;
   it does not fabricate a penal code. No client definition-write route exists.
6. Run `JusticeContractSmokeTest` and `LawReleaseContractSmokeTest`; readiness
   means provider/route contracts, not successful policy or multiplayer acceptance.
7. Both testers run `/law new_hanover`. A creates a case; B sees no private case.
   A adds B as `investigating_officer`; B can read/update with ordinary policy.
   A removes B; B loses case, charge, warrant and receipt access immediately.
   Repeat with `defense_counsel` (read only) and `witness` (no narrative access).
8. Create, file and withdraw a charge; create/issue/serve another warrant;
   separately check recall, quash, expiry and stale revisions. Confirm actions
   do not imply custody, conviction or financial effects. Test >25 accessible
   cases and inaccessible rows between pages. Test both screen sizes and Escape.
9. Simulate lost replies, duplicate requests, two concurrent edits, logout,
   dependency restart, DB loss and reconnect. Unknown mutations retain one
   request ID in the open MDT's retry control; never recreate the operation
   with a new ID while the first result is unresolved. Browser retry state is
   session memory only: reopening/logout clears narrative and retry state;
   after that, reconcile records/receipts server-side before issuing again.

Production remains gated on a reviewed action/role/jurisdiction policy provider
and real database + two-character acceptance. The default Admin policy is staff
based and ignores jurisdiction subjects; these fragments do not change that.
Final officer, prosecutor and judge powers are still a product decision.
Do not apply these test grants to production or enable global case overrides.

## Alpha.4 citation/fine checks (UUID characters)

- Apply the new inactive `contracts-issuer.lua` fragment to the disposable Contracts
  copy. The installed owner-only adapter recognizes citation player actions. The service
  fragment supplies exact Contracts issue/cancel grants to `feather-justice`. Do not grant Law Economy access.
- Start Contracts with its normal Economy trust/configuration and enabled client
  routes. Justice can remain ready while Contracts is absent; citation work will
  remain pending and `JusticeCitationStatus` exposes the reason.
- Use **actual character UUIDs** from the staging characters; random example UUIDs
  do not provision Character identities. Give the debtor an existing dollar wallet
  funded through the supported staging Economy workflow. No test grants money.
- Console: `JusticeCitationStatus`, then
  `LawCitationPreflight <officerCharacterUUID> new_hanover`. The officer must be in
  an active session. This command accepts UUIDs, not numeric character IDs. Its
  results cover department/policy checks; membership on a specific case is separate.
- Officer `/law new_hanover`: open a case, choose Citări / amenzi, enter the debtor's
  UUID, 1 minor unit and a due period >=60 seconds. Confirm. Initially pending; reload
  after the worker pass and verify exactly one linked obligation UUID.
- Debtor `/lawfines`: verify amount/currency/status, pay from their own wallet, then
  reload. This **moves real staging money** to the configured system sink. An unrelated
  character must not see or pay that debtor's obligation through their own session.
- Create a separate citation and cancel it; verify the financial obligation is also
  cancelled. Try cancelling the paid citation: the legal cancellation must be rejected,
  with no refund. Do not infer payment state solely from the legal `issued` label.
- Exercise insufficient funds, duplicate/exact retry, lost issuance/payment/cancel
  reply, resource restart, unavailable Contracts and concurrent pay/cancel. Original
  retry IDs must be preserved; verify Contracts/Economy reconciliation and journals.
- No automatic live fixture or monetary seeding command was installed. Run offline:
  `python3 tests/run_lua.py` and `node tests/ui.cjs` from Law; run Justice's Lua runner
  from its resource too. Neither command suite touches the live database.

## Alpha.5 booking/custody (existing UUIDs)

Offline suites can use the read-only database UUID selection without any live writes:

```sh
python3 '[feather]/feather-justice/tests/run_lua.py' --character-fixture /tmp/feather-law-custody-fixture.json
python3 '[bcc]/bcc-law/tests/run_lua.py' --character-fixture /tmp/feather-law-custody-fixture.json
```

Run these from the resources root. Fixture contains only three character UUIDs,
kept outside the resources; they are used for mocked actor/subject/other contexts.
If the temporary file is absent, omit the option for generated UUID fixtures.
No numeric character IDs are used as persistent identities.

On disposable staging, the installed owner-only adapter recognizes the three
custody actions. Confirmation also requires `justice.warrant.serve`.
No additional reader or writer privilege in Character is necessary.

1. Console: `JusticeContractSmokeTest` (custody=1), `LawReleaseContractSmokeTest`
   (routes=44/44). They are read-only diagnostics, not gameplay acceptance.
2. Use two actual logged-in characters. Create/issue a staging arrest warrant
   for the subject UUID. Grant the officer the normal assignment/commission and
   case eligibility. Bring both to the configured `valentine` facility through
   gameplay. Default coordinates: -273.05, 810.97, 119.37; both within 10 units,
   within 3 units of one another and in the same routing bucket.
3. `/law new_hanover` → case → Booking / custodie → reserve by warrant UUID and
   current revision → confirm arrival. These actions write staging legal records;
   confirmation must atomically produce held custody and a served warrant.
4. Verify missing/expired/recalled warrants, duplicate subject holds across cases,
   stale revisions, off-duty/no commission/policy, source reuse, logout, remote
   positions, other instances, unknown facility and absent/invalid peds all deny.
5. Drop a reply, then leave/disconnect the subject. Retry must recover the original
   receipt before trying another physical action. Restart must retain booking/hold.
6. Explicit release must preserve history, free the active slot and retain the
   served warrant. Withdraw an unconfirmed booking: warrant must remain unserved.
   Release while offline changes only the legal record, not spawn or position.

No automatic jail placement or countdown exists in alpha.5. Do not treat the
booking record as a completed sentence or assume a jail gate/door was unlocked.
Real database concurrency and physical behavior remain unverified until these steps
run. No sentence/offline-time policy was chosen on the live server.

## Banks-style acceptance output

After `restart bcc-law`, use `LawAcceptanceTest preflight <A UUID> <B UUID>` for
read-only per-check PASS/FAIL/SKIP and a final tally. Fix failed setup checks first.
`LawAcceptanceTest <A UUID> <B UUID> [freshRunId]` runs the legal fixture and guarded
cleanup. Finance and physical custody require their explicit modes; resume is
read-only and cleanup is retryable. See [full command reference](../docs/ACCEPTANCE_TESTS.md).
These commands exercise real APIs when you invoke them; the offline runner alone
still does not demonstrate live database, financial or two-player acceptance.


## Alpha.6 physical restraints

Use two live staging characters. The officer needs the existing job/commission,
case access, and the explicit `law.restraint.manage` action (recognized by the
installed owner-only Admin staging adapter). Issue a fresh arrest warrant for
the subject through Justice. A served/expired/recalled warrant cannot apply cuffs.

1. Within 3 units in the same bucket, use MDT `Teren` or
   `/lawcuff new_hanover <subject source> <warrant UUID>`. Check only that subject
   becomes restrained. A duplicate apply must not toggle or extend the timeout.
2. `/lawescort new_hanover <subject source> on`, then `off`; repeat each command.
   Check movement/attachment, missing streamed officer, mounted players and
   distance beyond 6 units. Escort stops; cuffs remain until explicitly released
   or the server sweep's cleanup conditions occur.
3. `/lawuncuff new_hanover <subject source>`, repeat; verify idempotent release.
   Try self, distant/dead/cross-instance targets, wrong warrant subject, inactive
   warrant, missing duty/commission/policy and another department.
4. Recall the warrant, leave duty, die, disconnect/reconnect, reuse a source or
   stop a dependency. Verify physical state clears and no old session inherits it.
   Interrupt replies: client native state clears after at most its five-second
   snapshot lease. Confirm resource stop removes cuffs and attachment immediately.
5. Verify no legal custody/warrant/sentence record changed as a side effect of
   physical cleanup. Booking confirmation serves the warrant; subsequent physical
   cleanup must not be mistaken for legal release or timed jail completion.

These steps have not been run in RedM by this implementation. The offline suite
uses mocked physics and does not demonstrate multiplayer native behavior.


## Alpha.8 evidence

The module does not create live lockers until explicitly requested. Follow
[Evidence setup and acceptance](../docs/EVIDENCE.md): review server-only locker
config, await Inventory/Justice evidence readiness, then console
`LawSetupEvidenceLockers` on disposable staging. Use two real current characters
and an active seizure warrant. Validate transfer/receipt/link as separate facts,
including an interrupted reply and a failed link after committed collection.
Disposition controls record legal decisions only; no physical return or destruction
is implemented. These live steps were not executed during the code changes.
