# BCC Law — native Feather law gameplay

Version **2.0.0-beta.1**. Law gameplay on top of
[Feather Justice](../../[feather]/feather-justice/README.md) Contract 1 (0.3.0):
the MDT, field interactions, arrest and booking, court, jail and community
service, evidence, armory, alerts and cell doors.

Justice owns every legal record: cases, parties, charges, warrants, citations,
custody, rulings, sentences, evidence links and the penal code. Law owns the
interactions around them: who is standing where, restraints, jail placement,
work units, armory claims, physical evidence steps and alerts. Law keeps only its
own tables and never reads Justice tables (see [master plan](BCC_LAW_MASTER_PLAN.md) §2).

## Requirements

Start order: `feather-mysql`, `feather-core`, `feather-character`, `feather-jobs`,
`feather-licenses`, `feather-contracts`, `feather-inventory`, `feather-justice`,
then `bcc-law`. Optional: `bcc-doorlocks` (cell doors), `feather-weapons` (armory
weapons), `feather-medical` (life state for jail placement).

Owner configuration this resource relies on (already present in the Feather
resources of this server; nothing here grants a role to a player):

| Where | Setting |
|---|---|
| feather-jobs `config.lua` | `Config.Access.trustedReaders['bcc-law']` (duty checks) |
| feather-licenses `config.lua` | `Config.Access.trustedReaders['bcc-law']` (commission checks) |
| feather-contracts `config.lua` | trusted issuer `feather-justice` (fines, restitution) |
| feather-justice `config.lua` | `TrustedResources` and `DefinitionResources` include `bcc-law` |
| feather-admin `configs/law_acceptance_policy.lua` | `mode='qualified'`: Law decides its 40 actions |
| feather-admin `configs/service_policy.lua` | `['feather-justice']['bcc-law']`: `justice.definition.view/manage`, `justice.custody.view`, `justice.sentence.view`, `justice.sentence.complete` |

## Installation

1. `refresh`, then `ensure bcc-law` after its dependencies (or restart the server).
2. Console, once: `LawSetupJurisdictions` — registers `bcc-law:new_hanover` in Justice.
3. Console, once: `LawSetupStatutes` — registers the starter penal code (12 statutes).
4. Console, once per locker: `LawSetupEvidenceLockers` — creates the private evidence lockers in Inventory.
5. Console: `LawReleaseContractSmokeTest` — read-only; expect `ready=true routes=63/63 justice=0.3.0 store=ready`.
6. Console: `LawAcceptanceTest <officerUUID> <subjectUUID>` — expect `0 failed`. Both
   characters may be offline. See [acceptance tests](docs/ACCEPTANCE_TESTS.md).

All setup commands are idempotent: a rerun reports `already_registered` /
`alreadyPresent`. Startup never creates definitions, jobs, commissions or policy.

## Who can do what

Each action has a rule (`Law.PolicyRules` in `server/foundation.lua`); feather-admin
asks Law through `EvaluateActionPolicy` and Justice then checks case membership.

| Rule | Requirement | Examples |
|---|---|---|
| officer | on duty in `police` + valid `peace_officer` commission | restraints, search, evidence collection, arrest/booking, citations, armory |
| judicial | `judge` assignment + `judicial_commission` | rulings, sentences, penal code, sealing/expunging, search/seizure warrants, evidence dispositions |
| legal | either profile | cases, parties, charges, arrest warrants, reading records |

Protected history (`justice.audit.view`) additionally needs the feather-admin
`staff.admin.audit.search` permission. Configure departments, jobs and licenses in
`config.lua` (`Departments`, including the `judicial` profile).

## Player commands

| Command | Who | What |
|---|---|---|
| `/law [department]` | officers, judges | Opens the MDT |
| `/lawstatus` | anyone | Own custody time and community-service units |
| `/lawfines` | anyone | Own fines and payment from the wallet |
| `/lawalert [department] <message>` | anyone | Report to on-duty officers (with your position) |
| `/lawcuff <department> <player> <UUID> [custody]` | officers | Restrain under an arrest warrant (or a custody record) |
| `/lawuncuff <department> <player>`, `/lawescort <department> <player> <on\|off>` | officers | Release / escort |

Shots fired inside a configured area alert on-duty officers automatically.

## Console commands

| Command | Writes? | Purpose |
|---|---|---|
| `LawSetupJurisdictions`, `LawSetupStatutes`, `LawSetupEvidenceLockers` | yes (definitions) | Explicit setup |
| `LawReleaseContractSmokeTest` | no | Version, routes, Justice release, store |
| `LawAcceptanceTest [officerUUID] [subjectUUID]` | Law dev rows, removed after | Readiness, qualification and Law table checks |
| `LawActiveCharacters` | no | UUIDs of characters online right now |
| `LawEvidenceStatus` | no | Lockers and pending/failed physical evidence steps |
| `LawEvidenceRetry <evidenceLinkId>` | yes | Queue a failed physical step again (same request ID) |

## Configuration (`config.lua`, server only)

`DefaultLocale`, `Departments` (job, commission, jurisdiction key, judicial
profile, optional `employerId`), `CaseTypes`, `Statutes` (starter penal code with
advisory ranges), `Armory.Stations`, `Execution` (jail facilities, work tasks),
`Restraints`, `Evidence.Lockers`, `Custody.Facilities` (booking), `Doors.Facilities`
(bcc-doorlocks door IDs per facility; empty by default) and `Alerts` (cooldowns,
blip time, shots-fired areas). The configuration is validated on every readiness
check; an invalid value puts Law in `failed/invalid_config`.

## Languages

English is the default; Romanian is included (`locales/en.lua`, `locales/ro.lua`).
The language follows the player's Core account setting (`feather-core:locale:changed`
while the MDT is open); unknown languages fall back to `DefaultLocale`, then English.
To add a language, copy `locales/en.lua`, translate the values, add the file to
`shared_scripts` in `fxmanifest.lua`. Missing keys fall back to English.

## Data

| Table | Holds |
|---|---|
| `bcc_law_schema_migrations` | Version and checksum of each Law migration |
| `bcc_law_operations` | Operation journal: identifiers, revision and status of confirmed mutations (kept 7 days) |
| `bcc_law_placements` | Jail placement marker per character |
| `bcc_law_service_progress`, `bcc_law_service_tasks` | Community-service units, each counted once |
| `bcc_law_armory_claims` | Armory claims and the daily quota |
| `bcc_law_evidence_dispositions` | Physical return/destruction steps queued after a Justice disposition |

Migrations are versioned and checksummed; version 1 is unchanged from earlier builds.

## Routes

63 routes `law.<group>.<operation>.v1`, all requiring a current character session.
Every mutation takes a client `requestId` (≤64): an exact retry returns the stored
result; a changed payload under the same ID is refused. See [routes](docs/ROUTES.md).

## Tests

```sh
python3 tests/run.py --server-cfg ../../../server.cfg
```

Runs bcc-law together with the real feather-justice on a throwaway MariaDB schema
(`law_test_<pid>`, always dropped): lifecycle and migrations, setup, policy,
arrest → booking → release, court → jail → offline term → release, community
service, search and evidence with physical dispositions, alerts, the penal-code
editor, citations, sealing, the acceptance command and the MDT ↔ client ↔ route
contract. It also runs the client checks (`tests/client/`) and the MDT browser
checks (`tests/ui.cjs`). The two offline test characters are the officer/judge and
the subject; Core, Jobs, Licenses, Contracts, Inventory and the game world are
mocked at their export boundary. In-game checks: [acceptance tests](docs/ACCEPTANCE_TESTS.md).

## Documents

[Master plan](BCC_LAW_MASTER_PLAN.md) · [Beta 1 checkpoint](docs/BETA1_CHECKPOINT.md) ·
[Routes](docs/ROUTES.md) · [Evidence](docs/EVIDENCE.md) · [Acceptance tests](docs/ACCEPTANCE_TESTS.md) ·
[Justice integration agreement](../../[feather]/feather-justice/LAW_INTEGRATION.md) ·
[Original baseline](docs/BASELINE.md) · earlier checkpoints in `docs/history/`.

License: GPL-3.0 (see `LICENSE`).
