# Checkpoint — 2.0.0-beta.1 (2026-10-21)

From alpha.9 (on the Justice 0.2.0 shapes) to beta.1 on Justice Contract 1 0.3.0.
Earlier checkpoints are kept in `docs/history/` and describe superseded APIs.

## What changed

- **Justice 0.3.0.** Every call uses the plan's operation names and flat
  snapshots (`caseId`, `warrantId`, `custodyId`, …), `GetCase{includeRelated}` for
  case-file lists, and the capability document `feather.justice` v1. alpha.9
  parked itself in `degraded/contract_unavailable` on 0.3.0; beta.1 starts.
- **Arrest and custody.** `law.custody.arrest.v1` (restrained subject + an arrest
  warrant or custodial order naming exactly that person → `RecordArrest`, which
  serves the warrant), then booking with both players at the facility and release.
  The restraint moves from the warrant to the custody record after the arrest, so
  serving the warrant does not drop the cuffs. The alpha reserve/confirm routes are gone.
- **Operation journal** (`bcc_law_operations`, migration v2): an exact retry of a
  confirmed mutation returns the stored identifiers/revision/status without
  re-running physical checks; a changed payload under the same ID is refused.
  Narrative is never stored, so an expunge in Justice is not undone by Law.
- **Community service** progress is owned by Law (`bcc_law_service_progress`,
  one row per unit in `bcc_law_service_tasks`); the last unit completes the
  sentence in Justice in service mode. The pre-beta delivery table is dropped only if empty.
- **Penal-code editor** for judges (register/revise/retire statutes with advisory
  fine and custody ranges) and the console seed `LawSetupStatutes` (12 statutes).
- **Destroyed evidence is destroyed physically** through Inventory's existing public
  `DestroyInstances` (queued in migration v3; Inventory itself is not changed).
  Returned items stay in the locker until staff hand them back; forfeited items stay.
  See [evidence](EVIDENCE.md).
- **Doors**: booking and jail placement lock the facility's configured
  bcc-doorlocks doors (doorlocks stays the only owner of door state).
- **Alerts**: `/lawalert`, shots fired inside configured areas, notifications in
  each officer's language and a temporary blip.
- **Languages**: English default and Romanian, by the Core account locale.
- **Policy**: `Law.PolicyRules` uses the 0.3.0 action names (40 actions, the same
  list in feather-admin's `law_acceptance_policy.lua`); search/seizure warrants and
  evidence dispositions need a judge.
- **Tests**: the mock suites were replaced by an integration harness on a real
  database with the real Justice (`tests/run.py`).

## Decisions (owner)

Sentence time continues offline (UTC deadline, 2026-10-19). Clean install, no
import. Payroll belongs to Society/Jobs/Economy.

## Evidence

`python3 tests/run.py --server-cfg ../../../server.cfg` on 2026-10-21:
`PASS bcc-law: 899 checks, 0 failed`, `PASS client MDT transport: 26 checks`,
`PASS Law restraint client: 21 checks`, `PASS MDT browser logic`. Store v1 checksum
equals the value recorded on the live server
(`6bb581bd8a1e636e650d974da1c97bbb2112633d3fb9f7d5055d91933fddf033`).

Live console on the dev server, 2026-10-21: `LawSetupJurisdictions` (jurisdiction
`c3298b30-9a0f-4686-aabe-b97bc4fff18a`), `LawSetupStatutes` registered=12 failed=0,
`LawSetupEvidenceLockers` confirmed, `LawReleaseContractSmokeTest` ready=true
routes=63/63 justice=0.3.0 store=ready, `LawAcceptanceTest <Ion> <Gigi>` 20 passed,
0 failed, 0 skipped. Before the in-game run: the server has the `police` job and the
`peace_officer` license, but no `judge` job or `judicial_commission` license, and the
test characters hold neither profile yet (`duty_required` in the INFO lines).

## Live steps

`refresh`; restart feather-admin and bcc-law, and feather-inventory once more so it runs
its original code again (feather-justice is unchanged and re-registers its evidence
guard by itself after Inventory restarts); then `LawSetupJurisdictions`, `LawSetupStatutes`, `LawSetupEvidenceLockers`,
`LawReleaseContractSmokeTest`, `LawAcceptanceTest <officerUUID> <subjectUUID>`.
Migrations v2 and v3 apply at the first start.

## Open gates

- The two-player in-game run ([acceptance tests](ACCEPTANCE_TESTS.md), level 3).
- Menu v2 field menus, badge/NPC/witness, lockpick/wagon transport (MDT forms and
  commands cover the actions today).
- Mount/vehicle ownership checks (no public Assets entity–asset contract yet),
  Property, Access delegation, Mailbox reminders.
- Licenses scope vocabulary (only an empty version-1 scope is accepted).
- The 1.0.0 freeze, when the owner decides.
