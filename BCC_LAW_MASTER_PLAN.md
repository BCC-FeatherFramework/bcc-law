# BCC Law — native Feather porting master plan

Date: 2026-10-18 (status updated 2026-10-20). Baseline inspected: the uploaded
`bcc-law` 1.1.0 package. Current state: **2.0.0-beta.1** on Feather Justice
Contract 1 (0.3.0); see [§12](#12-status--200-beta1-2026-10-20). This document
does not certify the package as a complete port or a stable release; the 1.0.0
freeze happens only when the owner decides.

Authorized goal: keep the useful functionality and port it to Feather, without
VORP/oxmysql dependencies, compatibility structure or APIs. No fake Core, no
compatibility Character object and no `MySQL` shim over `DB` are built. APIs and
data models are redesigned natively.

Reference: [Justice master plan](https://github.com/FeatherFramework/feather-framework-docs/blob/main/feather-justice/Feather_Justice_Master_Plan.md).
This plan is local and kept for review; it is not published in the documentation
repository. Recommended destination when published: `bcc-law/BCC_LAW_MASTER_PLAN.md`
in `FeatherFramework/feather-framework-docs`; a link can then replace this copy.

## 1. Baseline and verifiable findings (2026-10-18)

- The manifest declared VORP Core/Character/Inventory, oxmysql, the old Menu,
  bcc-utils, Society and Mailbox. `server/init.lua` also required `bcc-job-alerts`
  without declaring it in the manifest.
- The client used `feather-menu2`, different from the declared `feather-menu`
  dependency and from the current Feather resource `feather-menu-v2`.
- `client/mdtMenu.lua` and `client/penalcodeMenu.lua` existed but were not loaded
  by the manifest; the active UI also included a separate Vue MDT. Parity is not
  claimed for files only because they exist on disk.
- `server/server.lua` had 2,961 lines and the main client 1,706. The split follows
  responsibilities, not the old monolith.
- There were direct queries into `characters`, `horses`, `bcchousing`, `bcc_shops`,
  `bcc_society`, rank tables and bank accounts.
- `controllers/ledger.lua` changed the Society ledger and bank balances directly.
  Fines also used `removeCurrency`; all of these paths are removed.
- Persistent identity was the pair platform identifier + numeric character, which
  does not match Feather Character UUIDs.
- Time and work reductions were triggered by the client (`TakeTime`,
  `UpdateService`), and a jailbreak deleted the jail record. These semantics are
  not ported: time, progress, escape and release need authoritative server checks.
- Case evidence was mostly descriptive records, not a chain of custody for
  Inventory instances.
- The package had no Git repository of its own and no proven baseline branch or
  tag. The GPL-3.0 license and attribution are kept.

## 2. Data owners

| Concern | Owner | BCC Law role |
|---|---|---|
| Session, account, current actor | Core | Resolves identity on the server |
| Person profile and search | Character | Consumes a public, bounded, authorized contract |
| Department organization | Organizations | Configures validated UUID references |
| Employment, grades, duty, active job | Jobs; Society for Society-managed employment | Reads facts; asks the owner for operations |
| Commission / professional qualification | Licenses | Verifies through a public contract |
| Service powers | Authority through Core policy | Applies named actions and jurisdiction scope |
| Penal code, cases, parties, charges, warrants | Justice | Interface and orchestration |
| Citations, custody authority, rulings, sentences | Justice | Coordinates the physical effects |
| Financial obligation | Contracts | Shows it and requests the legally authorized operation |
| Balances, payments and treasury | Economy | Consumed only through APIs |
| Salaries and Society funds | Society + Economy | One payroll path, no double accrual |
| Items, armory, seizures | Inventory; Weapons for weapon identity and policy | Validates the interaction and custody |
| Properties and interests | Property | Shows authorized results only |
| Owned horses, wagons and boats | Assets | Verifies the exact asset, not just the model |
| Persistent delegated access | Access | Consumes the integration when available |
| Death and recovery | Medical | Suspends / re-evaluates interactions |
| Doors and lock state | bcc-doorlocks | Requests operations through its API, one owner |
| Interactions, locations, UI, animations, NPCs | BCC Law | Direct owner |
| Cross-cutting audit | Audit | Publishes reviewed facts through a durable outbox |

Justice owns no animations, teleports or jail simulation. BCC Law owns no second
case database and no second debt ledger. Being employed does not by itself grant
every legal power; qualification, permission, jurisdiction and domain conditions
are separate checks.

## 3. Feature inventory and destination

| Existing feature | Decision and keep criterion |
|---|---|
| Vue MDT, dashboard, person profile | Keep the presentation; new payloads, paginated and filtered on the server |
| Field menus and controls | Rebuilt with Menu v2 exports; no adapter for the old Menu |
| Configurable penal code / editor | Justice definitions and revisions; recommendations are never automatic punishments |
| Cases, suspects, officers, charges, notes | Justice; historical snapshot of the offence and the author |
| Warrants and closing a warrant | Explicit Justice lifecycle: served, recalled, expired, etc. |
| Fine and duration calculation | Server-calculated proposal; applying it needs authority and a reason |
| Combined fine / jail sentence | Justice ruling/sentence + durable workflow, no hidden partial effects |
| Instant fine, bill, bill payment | Justice citation + Contracts obligation + Economy settlement |
| Bill item | Optional Inventory representation of the obligation, without authoritative money in metadata |
| Automatic/manual jail, return on connect | BCC Law execution tied to Justice custody/sentence |
| Time reduction, jailbreak, release | Server-authoritative; escape never deletes the sentence |
| Community service | Justice sentence; BCC Law tasks, validation and physical progress |
| Cuffs, keys, lockpick, escort, wagon | Keep the mechanics; nearby targets, current sessions, server state machine |
| Search and seizure | Inventory + legal authority + verifiable restraint; no arbitrary transfer from the client |
| Armory, ammunition, commissary | Server allowlist config; Inventory/Weapons; idempotent grant, limits and audit |
| Multiple jobs, duty, payroll, ledger | Jobs/Society/Economy; remove the "off" prefixes and foreign SQL |
| Vehicle/mount check | Assets and a verifiable entity–asset link; a model hash does not prove ownership |
| Station / cell doors | bcc-doorlocks integration; never two control loops over one door |
| Badge, blips, NPCs, witness, alerts | BCC Law + Toolkit/Notify; lifecycle and cleanup by the owner |
| Letters and reminders | Optional, only after the Mailbox provider is verified; never blocks issuing the debt |
| Webhooks | Audit/redaction; no secrets in shared config or client payloads |
| Romanian/English/German localization | Migrate to locale tables; keep the meaning and translations |

Alternative menus that were not loaded must be classified as replaced or needed
after the screen inventory. Old inactive implementations are not left in the final product.

## 4. Dependencies and coordination

Baseline available locally: Core, MySQL, Character, Jobs, Organizations, Authority,
Contracts, Economy, Inventory, Weapons, Medical, Property, Assets, Menu v2, Toolkit,
Notify, Audit, Society and Doorlocks. Presence does not certify every API.

- Justice was not implemented in the workspace at that inspection. Its contracts
  were requested in slices: jurisdictions/statutes, cases/parties,
  charges/warrants, citations, custody, sentences, evidence and record access.
- Licenses is worked on by another maintainer. That domain is not modified and no
  export names are invented. Agree the qualification check, issuer authority,
  status/expiry, offline subjects, readiness and errors.
- Access belongs to SavSin. Persistent grants are not duplicated in BCC Law.
- Character: verify a privileged paginated search exists; the provider inspected
  earlier did not publish `SearchProfiles`. Extending it belongs to Character.
- Society: inventory the current exports for membership, management and payroll.
  A missing export is solved with the owner; it never justifies SQL from BCC Law.
- Evidence: Inventory uses a local numeric item ID while the Justice master plan
  assumes a UUID. Agree a stable versioned reference before the link schema.
- Assets: there is no proof yet of a public entity–asset contract. Mount ownership
  checks stay unavailable until the exact identity can be established.
- bcc-job-alerts, Mailbox and the minigames are inspected separately. None is
  assumed compatible because its name starts with bcc.

No circular Justice–Law or Core–gameplay dependencies. Law waits with bounded
readiness for the functions it needs. Unavailable optional modules are hidden or
reported explicitly; protected actions have no permissive fallback.

## 5. Native BCC Law contract — proposed design

- Operational exports: `GetHealth`, `GetCapabilities`, `AwaitReady`; the exact
  schema is fixed before implementation. Capabilities declare only healthy functions.
- New routes `law.<operation>.v1`, returning `{ ok, value }` or
  `{ ok=false, code, message, details? }`. The exact list follows the handler inventory.
- The NUI receives an explicit list of operations and presentation snapshots; it
  cannot choose the export, the resource, the actor or the service authority.
- The actor comes from the Core session; a target UUID is validated input, never
  proof of access. A source ID is only a transport address.
- Each mutation defines its policy action, duty, jurisdiction, qualification,
  grades where relevant, target rules, limits, rate limit and idempotency scope.
- Delayed requests bind the actor session, the target session where relevant, the
  request ID and the revision; they are re-evaluated after a yield and before the effect.
- `service unavailable` refuses the action; an expired positive answer is never
  reused as authorization for a new mutation.
- Legal text is shown as safe text; searches and lists have limits and cursors.
  Confidential cases are filtered in the authoritative service.
- Field interactions check distance and state on the server; animation/minigame
  tokens are single-use, limited, and never grant authority by themselves.

## 6. Persistence and workflows

Proposed BCC Law tables (working names): `bcc_law_schema_migrations`,
`bcc_law_operations`, `bcc_law_execution_sessions`, `bcc_law_service_progress`,
`bcc_law_outbox`. The schema and indexes are finalized before the first migration.

Law keeps only the intent/reconciliation of an interaction and the gameplay
execution. It keeps no balances, canonical warrant lists, debts or sentences that
compete with their owners. Links: Justice/Contracts/Organizations UUIDs and
Inventory references following the agreed contract. UTC timestamps, checksummed migrations.

Fine workflow: authority + interaction → Justice citation → Contracts obligation →
payment through Contracts/Economy. A single orchestrator issues the obligation;
Law does not issue it again when Justice already coordinates it. Missing money
leaves a legal debt; it never produces a direct debit or a negative balance.

Sentence workflow: Justice confirms the ruling → Law reserves the execution →
delivers booking/teleport to the current session → confirms or reconciles the
result. A reconnect rebuilds from the authoritative sentence and progress; it never
restarts the punishment by accident. The offline time policy and the
cumulation/reduction of sentences are decided explicitly.

Evidence workflow: Inventory confirms the transfer/hold → Justice links the
reference → the Law operation completes. On an uncertain result the original
operation is looked up. Deleting or consuming linked evidence needs a guard or an
immutable disposition, agreed with Inventory/Weapons; never SQL over their tables.

Every workflow has a retry owner, pending/confirmed/rejected/unknown states, stable
keys, recovery after a restart and a read-only reconciliation command. No atomic
transaction across several resources is claimed. A lost reply never allows a new
fine, payment, weapon, time reduction or sentence.

## 7. Existing schema and cutover

| Current source | Destination |
|---|---|
| `bcc_law_penal_codes` | Versioned Justice statutes |
| `bcc_law_cases`, `case_suspects`, `case_officers` | Justice cases and parties |
| `bcc_law_case_charges` | Justice charges + offence snapshot |
| `bcc_law_case_notes`, `case_evidence` | Descriptive Justice notes/evidence; no physical items invented |
| `bcc_law_warrants` | Justice warrants; explicit open/closed status mapping |
| `bcc_law_bills` | Justice citations + Contracts obligations; historical payments keep provenance |
| `bcc_law_jail` | Justice custody/sentences + Law execution |
| `bcc_law_communityservice` | Justice sentence + Law progress |
| `bcc_law_mdt_logs` | Protected/imported history; new audit through outbox/Audit |
| `characters`, Society, Banks, Horses, Housing, Shops SQL | Removed; owners' APIs |

Before cutover: inventory the real data and back it up, choose a clean install or
an import. Loading the folder does not mean the tables exist. An import needs an
explicit numeric character → UUID mapping, reconciliation of numbers, statuses and
amounts, and stopping the old writers. UUIDs are never made from numeric IDs and
production data is never deleted automatically.

Any historical importer is a separate tool, excluded from the runtime and the
Feather release, so the final product has no VORP/oxmysql branches. The original
baseline is kept as an archive outside the release; without a verified upstream
repository no protected branch or tag is claimed. This plan performs no push,
external archive or DB migration.

**Decision (2026-10-20):** clean install. No historical import; the old tables
are not read.

## 8. Target structure

```text
config/                 departments, jurisdictions, interactions, jail, armory
shared/                 results, validation, limits and own DTOs
server/core/            lifecycle, dependency registry, policy and actor context
server/repositories/    ONLY BCC Law tables
server/services/        workflows, interactions, custody execution, service tasks
server/routes/          explicit Core handlers per feature
server/migrations/      checksummed BCC Law migrations
server/main.lua         narrow bootstrap
client/core/            session, readiness, cleanup, Core transport
client/services/        cuffs, escort, transport, jail, tasks, alerts, doors bridge
client/menus/           native Menu v2 API, no old initiate/RegisterMenu
client/nui/             explicit MDT operations and focus ownership
ui/src/                 Vue MDT and new DTOs
translations/           locales
tests/                  contracts, concurrency, lifecycle, failure/replay
README.md               installation, owner config and public API
```

The `controllers/jobs.lua` / `ledger.lua` folders are not kept as adapters with
the old meaning; they are removed after the needed functions moved.
The UI build must regenerate `ui/dist`, without node_modules in the release.

**Implemented layout (beta.1):** flat by responsibility — `server/foundation.lua`
(lifecycle, actor, policy), `server/routes.lua` (route registration and journal),
`server/store.lua` (the only module touching Law tables, versioned migrations),
one file per feature (`legal_routes`, `custody`, `restraints`, `search`,
`evidence`, `court`, `execution`, `armory`, `doors`, `alerts`, `setup`,
`acceptance`), `locales/` for translations and a dependency-free MDT in `ui/`
(no build step). Field interactions are MDT forms and chat commands; Menu v2 field
menus remain open (§12).

## 9. Implementation phases and exit criteria

| Phase | Deliverable | Exit criterion |
|---|---|---|
| LAW0 — inventory/contract | Feature map, list of all handlers, real data, authority matrix | v1 scope and consumed contracts accepted; no assumed API |
| LAW1 — foundation | Native manifest, Core/MySQL, lifecycle, config, locale, diagnostics | Clean start; correct failed/degraded; no VORP/oxmysql wrapper |
| LAW2 — duty/organizations | Jobs, Licenses, Authority and Society for Society-owned operations | Multi-employer; duty/role/qualification changes and refusals tested |
| LAW3 — field/UI | Toolkit, Menu v2, Notify, cuffs, escort, transport, badge, focus | Two real sessions; distance, cleanup, death, disconnect and restart |
| LAW4 — MDT/Justice | Jurisdictions, statutes, cases, parties, charges, warrants | Data only from Justice; privacy, stale revision and retry tested |
| LAW5 — financial | Citations, Contracts, Economy, document item, single payroll | No double payment/issue; timeout/restart/offline with the same IDs |
| LAW6 — jail/service | Justice sentences/custody, booking and Law server progress | Offline policy, escape, task replay and release verified |
| LAW7 — property/evidence | Inventory/Weapons, Assets, Property, Doorlocks, Access when available | Correct custody and access; no foreign SQL; transfer/hold/revocation |
| LAW8 — audit/cutover | Producer schemas, outbox, separate import if needed | Recovery/reconciliation, single writer, zero legacy inventory in the product |
| LAW9 — release | README, runtime package, compatibility, acceptance report | Clean install and upgrade/restart; every declared feature demonstrated |

The phases do not implicitly authorize changing domains worked on by other
maintainers. Provider blockers are documented; no local substitutes are built.
Law is not declared fully ported only because it starts or the MDT opens.

## 10. Mandatory acceptance

- Static: every manifest file exists, the order is verified, no duplicates; no
  runtime/config/UI reference to VORP, oxmysql, bcc-utils, feather-menu2, the old
  Menu or the old framework's character-selection event.
- No Steam/charidentifier identities in the new DTOs, no "off" job prefix, no
  add/removeCurrency, no Characters/Society/Banks/Horses SQL and no bank-table fallback.
- Lua syntax, UI build, result envelopes, rate limits, payload limits, pagination,
  duplicates/conflicts, stale session and source reuse.
- Migration first run/rerun/checksum/failure; transaction rollback; concurrent
  operations on the same fine, evidence, sentence and interaction.
- Negative: no job, off duty, insufficient grade where required, expired license,
  wrong jurisdiction, stopped provider, distant target, fabricated client request.
- Jail/service: spamming TakeTime/UpdateService does not reduce the punishment, a
  jailbreak does not delete it, a task completed earlier cannot be counted again.
- Restart of Law/Core/Justice/Inventory and a reply lost after commit:
  reconciliation, no duplicates and no false success. Medical recovery does not
  delete the sentence.
- MDT: per-record rights, sealed data, sensitive notes/evidence, safe text, late
  reply after logout, Escape/focus, 1080p/1440p/ultrawide.
- Two people: cuffs/escort/search, refused access, warrant/citation, booking,
  seizure and reconnect; mocks do not close native/multiplayer acceptance.
- Read-only smoke test: `LawReleaseContractSmokeTest`; fixtures that change data
  are explicitly development-only and excluded from the release config.
- Final report: exact dependency versions, commands, PASS/FAIL, data, limits,
  postponed gates. VORP evidence is never reused as Feather evidence.

## 11. Decisions

1. First jurisdiction and statute administration: **decided** — `bcc-law:new_hanover`
   (county), registered by console; judges manage the penal code in the MDT.
   Officer = on-duty `police` + `peace_officer`; judge = `judge` + `judicial_commission`.
2. Warrant policy, arrest without a warrant, release reasons: **decided** — arrest
   needs an active arrest warrant or an active custodial order; Justice lawful
   exceptions stay disabled (Justice team decision 5). Search and seizure warrants
   are issued by judges. Release reasons are a fixed list in the MDT.
3. Fine beneficiary: system creditor through Contracts (Justice), restitution to
   the named character. Partial payments only if Contracts supports them explicitly.
4. User decision 2026-10-19: sentence time **continues offline**, using the
   authoritative Justice UTC deadline. Escape does not change the sentence (the
   subject is returned to the cell). Cumulation: one active custodial sentence per
   character (Justice). Community service counts only units observed on site.
5. Licenses qualification contract: empty version-1 scope only, until Licenses
   publishes a scope vocabulary. Payroll belongs to Society/Jobs/Economy; Law has none.
6. Inventory evidence: instance IDs as decimal strings; a Justice destroy guard while
   linked. After the Justice disposition record, Law destroys a `destroyed` item
   through Inventory's public `DestroyInstances`; `returned` items are handed back by
   staff. Inventory itself is not changed for this (owner decision 2026-10-21).
7. Clean install (no import); sealed cases and expungement through Justice.
8. Additional independent consumer for validating Justice: reported separately as a
   Justice gate; not created artificially here.
9. Alerts: built on Core notifications and native blips; Mailbox reminders and
   minigames stay optional and are not implemented.

## 12. Status — 2.0.0-beta.1 (2026-10-20)

bcc-law consumes Justice Contract 1 0.3.0 exactly (operation names, flat
snapshots, capability document `feather.justice` v1). The MDT and all texts are in
English with a Romanian translation, chosen by the player's Core account language.

| Phase | State | Evidence and remaining gate |
|---|---|---|
| LAW0 | Done | Handler inventory (`docs/HANDLER_INVENTORY.json`), owners table, consumed contracts |
| LAW1 | Done | Native manifest, bounded readiness, config validation, locales, smoke test |
| LAW2 | Done (beta) | Jobs duty + Licenses commission per action (officer / judge / either); multi-employer through `employerId`; Society payroll owned elsewhere |
| LAW3 | Implemented | Restraint, escort, search, alerts, blips; MDT forms and commands. Open: Menu v2 field menus, badge/NPC, two-player in-game acceptance |
| LAW4 | Done (beta) | Cases, parties, charges, warrants, statutes, penal-code editor, sealing/expunging, history; real-DB tests |
| LAW5 | Done (beta) | Warnings and fines through Justice + Contracts; own-wallet payment (`/lawfines`). Payroll: owned by Society/Jobs |
| LAW6 | Done (beta) | Arrest → booking → release; UTC jail placement and return after escape; offline term; community-service units → Justice |
| LAW7 | Done (beta) | Evidence collection, Justice link and guard, physical destruction after the disposition (returns by staff); armory; doors through bcc-doorlocks. Open: Assets/Property checks (no public contract), Access |
| LAW8 | Partly | Operation journal and reconciliation commands; no import (decision 7). Audit outbox stays with Justice events |
| LAW9 | Partly | README and acceptance report written; live console acceptance passed on the dev server (2026-10-21, 20/0/0); the in-game two-player run and the owner's 1.0.0 decision remain |

Tests: `python3 tests/run.py --server-cfg ../../../server.cfg` runs Law and the
real Justice on a scratch MariaDB schema (899 checks, two offline characters as
officer/judge and subject), the client checks and the MDT browser checks. See
[docs/BETA1_CHECKPOINT.md](docs/BETA1_CHECKPOINT.md) and
[docs/ACCEPTANCE_TESTS.md](docs/ACCEPTANCE_TESTS.md).
