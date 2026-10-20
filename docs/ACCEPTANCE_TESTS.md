# Acceptance tests (beta.1)

Three levels. Only the last needs players online.

## 1. Automated (no server, no players)

```sh
cd resources/[bcc]/bcc-law
python3 tests/run.py --server-cfg ../../../server.cfg
```

Real MariaDB (scratch schema `law_test_<pid>`, dropped afterwards), real
feather-justice and bcc-law code, real feather-admin policy configuration. The two
offline test characters play the officer/judge (Ion `18477168-bfe5-11f1-8fad-020133902301`)
and the subject (Gigi `a2cf3f23-c0dc-11f1-8fad-020133902301`); nobody connects.
Expected: `PASS bcc-law: … 0 failed`, plus the client and MDT browser PASS lines.

## 2. Live console (server running, players may be offline)

After `refresh` and a restart of feather-admin, feather-inventory and bcc-law (their
configuration or code changed; feather-justice is unchanged):

```text
LawSetupJurisdictions        -> department=new_hanover result=<uuid> (or already_registered)
LawSetupStatutes             -> registered=12 alreadyPresent=0 failed=0 (rerun: registered=0 alreadyPresent=12)
LawSetupEvidenceLockers      -> locker=valentine result=confirmed
LawReleaseContractSmokeTest  -> ready=true routes=63/63 config=true justice=0.3.0 store=ready
LawAcceptanceTest 18477168-bfe5-11f1-8fad-020133902301 a2cf3f23-c0dc-11f1-8fad-020133902301
                             -> RESULT n passed, 0 failed
```

`LawAcceptanceTest` checks readiness, the Justice capability document, the Law
migration checksums (v1–v3), the jurisdiction and its statutes, both characters
exist, their officer/judge qualification (shown as INFO), the operation journal,
service-unit counting, the jail placement marker (only while the officer is
offline) and the service-mode custody/sentence reads. Its development rows are
removed afterwards. Legal workflows themselves are covered by Justice's
`JusticeAcceptanceTest` and by level 1.

## 3. In game (two players)

Player A: on duty as `police` with `peace_officer`, and also `judge` with
`judicial_commission` (or a second judge character). Player B: a citizen.
These are what the automated tests cannot prove (rendering, natives, real
Inventory/doorlocks/notification providers).

| # | Step | Expected |
|---|---|---|
| 1 | A: `/law` | MDT opens in A's account language; Esc closes and releases focus |
| 2 | A changes the account language in Core while the MDT is open | texts switch without reopening |
| 3 | A: new case, add B as suspect, draft + issue an arrest warrant | warrant active |
| 4 | A next to B: Field → Restrain (warrant) | B is cuffed; cannot fire or sprint |
| 5 | A: escort on, walk | B follows; escort off detaches |
| 6 | A: Custody → Record arrest (B's server id) | custody `arrested`, warrant `served`, B stays cuffed |
| 7 | Both at the Valentine booking point: Book | custody `booked`; configured cell doors lock |
| 8 | Judge: file charge, case → filed, verdict, custodial sentence, activate | B is moved into the cell |
| 9 | B walks out of the cell | B is returned to the entrance |
| 10 | B disconnects; wait past the term; B reconnects | B is moved out (term ran offline) |
| 11 | Community service: B at the task site, `/lawstatus` → Start a unit | a unit counts only after the full time on site; the last unit completes the sentence |
| 12 | Search warrant (judge) → Field → Search | read-only list of B's items; Finish serves the warrant |
| 13 | Seizure warrant → Evidence → Collect at the locker | item moves to the locker and is linked |
| 14 | Judge: disposition "returned" | the item is back in B's inventory (try once with B's inventory full: stays pending, then completes after space is freed and `LawEvidenceRetry`) |
| 15 | Disposition "destroyed" on another item | the item disappears |
| 16 | B: `/lawalert Help at the bank` | A gets a notification in A's language and a blip at B for 2 minutes; B sees a confirmation |
| 17 | B fires a weapon in Valentine | A gets "shots fired" once per minute; A firing does not alert |
| 18 | Citation with a fine → B: `/lawfines` → Pay | payment confirmed by Contracts |
| 19 | Judge: close a case, seal it; A without the judge profile | the case is no longer visible to A |
| 20 | A goes off duty, opens `/law` | every action refused with "must be on duty" |
| 21 | Armory at Valentine: claim the water ration twice | second claim refused (daily quota) |

Report the run with the exact resource versions (`LawReleaseContractSmokeTest`,
`JusticeContractSmokeTest`), date, PASS/FAIL per step and any postponed step.
