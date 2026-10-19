# BCC Law — native Feather development build

Version 2.0.0-alpha.9. This is a native implementation slice, **not the
complete police resource**. Do not deploy it as a replacement for a working
police system. The original uploaded package and UI are preserved outside this
resource; see [baseline location](docs/BASELINE.md).

Implemented: bounded lifecycle/readiness, current-session identity, allowlisted
Core routes, active-duty/grade/qualification/policy checks, owner-scoped Justice
case listing/creation, charge and arrest-warrant routes, participant operations, record access checks, a native MDT, durable citation obligations and own-wallet fine payment. No compatibility
API or foreign-domain SQL is used.

Warrant-backed cuffs and escort are available through the MDT's `Teren` tab or
`/lawcuff <department> <player source> <arrest warrant UUID>`,
`/lawuncuff <department> <player source>`,
`/lawescort <department> <player source> <on|off>`.
Both players must be nearby and alive, with a current character session.
The explicit `law.restraint.manage` policy action is required in addition to
duty/qualification; the installed Admin adapter checks qualified, on-duty police. These interactions do not create legal custody.
See [restraint behavior and limits](docs/ALPHA6_CHECKPOINT.md).

Not implemented yet: the remaining police gameplay,
physical evidence return/destruction, payroll, alerts, doors, or historical data import. Unimplemented gameplay capabilities remain disabled. The original locations, translations and UI
remain in the backup for the next porting slices.

## Dependencies and staging

Required: feather-core, feather-character, feather-jobs, feather-licenses,
feather-justice. Law and Justice additionally require feather-mysql.
Use coordinated compatible versions, with Core/MySQL before their consumers.
Run `refresh` before starting the new manifests. No running resources were restarted; `server.cfg` was not edited.

`config.lua` is server-only. Proposed initial defaults are `new_hanover`, job
`police`, commission `peace_officer`, jurisdiction key `bcc-law:new_hanover`.
They do not create a job or commission and grant no authority. When departments
are tied to different organizations, set their actual `employerId` values.
The Law reader currently requires an empty version-1 license scope. A nonempty
or unknown scope fails closed until its vocabulary is agreed with Licenses.

Before positive gameplay acceptance:

1. Verify `bcc-law` reader trust in Jobs and Licenses; current workspace includes it.
   Do not grant registrar/assigner/issuer privileges just for reading.
2. Register the real police job/grades through Society/Jobs, and define/issue the
   required commission through Licenses. Configuration trust does not create either.
3. Admin's server-only `configs/law_acceptance_policy.lua` recognizes the explicit
   Justice actions using fresh duty, grade and commission checks. Police powers
   require qualified on-duty police; judicial powers require the configured judge
   assignment and judicial commission. Justice also enforces case eligibility and
   judge participation. Audit history additionally requires Admin audit permission.
   No fixed Admin catalog entries or player-role assignments are changed.
4. Explicit definition setup uses source 0 and `justice.definition.manage`.
   With the existing Admin service-policy provider, the principal is
   `Config.servicePolicy['feather-justice']['bcc-law']`. Add only the reviewed
   definition action there, and ensure that action is enabled by that provider.
   A service grant never substitutes for player authorization.
5. Run `LawSetupJurisdictions` in the server console after dependencies are
   ready. This command **writes definitions** and reuses stable request IDs.
   It is never executed on startup. Label changes require a future versioned
   definition-update operation, not reuse of the existing receipt with new data.
6. Use `JusticeContractSmokeTest` and `LawReleaseContractSmokeTest` for read-only
   diagnostics. They report readiness, not blanket release acceptance.
7. With a valid on-duty, active assignment and commission, `/law new_hanover`
   opens the MDT: case creation/details/summary/transitions, participants, charges,
   arrest warrants and paginated lists. Escape closes it and releases focus.

Missing trust, policy, jurisdiction, duty or commission returns a rejection;
there is no permissive fallback and no setup performed against the live server.

## Current routes

All routes require an active Core character session. No route accepts an actor
identity or jurisdiction from the client. Rate: five calls per five seconds per
route; payload limit 8192 bytes, depth 2, nodes 12 by default; ruling findings use bounded deeper limits.

| Route | Payload | Result |
|---|---|---|
| `law.session.get.v1` | `{}` | Configured department keys and labels; no personal IDs |
| `law.cases.list.v1` | `{ department, cursor? }` | Justice case page, maximum 25 |
| `law.cases.open.v1` | `{ department, requestId, title, summary }` | Committed case or an error envelope |

Alpha.9 exposes 65 routes, including parties, case edits/transitions, statute lists, citations, custody, restraints and operation recovery. See [legal route fields and required policy](docs/LEGAL_ROUTES.md).
The MDT uses only these typed server routes. See [alpha.5 checkpoint](docs/ALPHA5_CHECKPOINT.md).

Open requests are scoped to the authenticated character; `requestId` is at most
64 characters. After an unknown result, reuse the **same ID and payload**.
Changing character, department, title or summary is not an exact retry.

## Verification

From this resource: `python3 tests/run_lua.py`. Requires Python and the Lua 5.4
shared library. Run `node tests/ui.cjs` for browser logic checks and `node --check ui/app.js` for JavaScript syntax.
Tests use mocked Core/domain/network calls, not a live database or RedM session.
The runner syntax-checks every Lua file in the resource before execution.

Live work still required: provider grants, real migrations/transactions and
restart recovery, two-player access isolation, focus/visual acceptance and the
remaining gameplay port. See [masterplan](BCC_LAW_MASTER_PLAN.md).

Staging fragments and acceptance steps: [staging/README.md](staging/README.md).
Participant roles and case access: [Justice participants](../../[feather]/feather-justice/PARTICIPANTS.md).

Citation/fine API and limits: [Justice citations](../../[feather]/feather-justice/CITATIONS.md).
Commands: `/lawfines`, console `JusticeCitationStatus`, and console
`LawCitationPreflight <characterUUID> [department]`. Contracts is optional for the
base case resource but required for citation issuance and payment; start it before
Justice/Law for financial testing. Its client routes must be enabled for `/lawfines`.

Alpha.5 adds manual custody booking/confirmation/release with server-side location
guards; [custody API and limits](../../[feather]/feather-justice/CUSTODY.md). Alpha.9 adds separate sentence-based physical execution; manual booking alone
does not create a sentence.

The agreed sentence policy is **elapsed time continues while offline**. Reconnect
uses the authoritative Justice deadline through the implemented sentence contract. The physical restraint timeout is separate from any legal sentence.

If preflight reports `character_not_in_active_session`, console-only
`LawActiveCharacters` lists UUIDs of currently selected Core characters. Stored
Character status `active` does not mean a player is connected. The diagnostic
prints UUID and transport source only; it creates no session or role.

Live checks with aligned PASS/FAIL/SKIP and a final tally:
`LawAcceptanceTest preflight <A UUID> <B UUID>` is read-only;
`LawAcceptanceTest <A UUID> <B UUID> [freshRunId]` writes tagged legal test records.
Separate `finance`, `custody`, `resume` and `cleanup` modes are documented in
[acceptance commands](docs/ACCEPTANCE_TESTS.md). No job/license/policy bypass exists.


Read-only warranted searches are available in `Teren`. Inventory must include
`server/services/law_search.lua`; Justice must support search warrants. Each page
rechecks the officer, target, restraint, warrant and proximity. Explicitly finish
the search to serve the warrant. No writable inventory access or confiscation is
granted. See [search checkpoint](docs/ALPHA7_CHECKPOINT.md) and
[Law acknowledgement of Claude's agreement](docs/JUSTICE_INTEGRATION_REVIEW.md).


Alpha.8 adds private evidence lockers, durable instance-preserving collection
receipts, Justice evidence links, explicit recovery and legal disposition controls.
Use case → `Probe`. Review [evidence setup, recovery and limitations](docs/EVIDENCE.md)
before explicitly running console `LawSetupEvidenceLockers` on staging. Physical
returns/destruction and complete custody history for future external moves remain
open. No live lockers, migrations, collections or dispositions were performed.

Alpha.9 adds court rulings, all seven sentence forms, privacy controls, UTC jail
placement/release, observed community service and a durable daily-quota armory.
Use `/lawstatus` for your own sentence/task status. Review
[the current checkpoint](docs/ALPHA9_CHECKPOINT.md) for configuration, persistence,
provider requirements and the remaining live acceptance gates.
