# BCC Law routes (2.0.0-beta.1)

All 63 routes are Core RPC routes named `law.<group>.<operation>.v1`. Each needs a
current character session; officer routes also take `department` (a configured
key). Unknown fields are refused (`invalid_input`). Limits: 8192 bytes, five calls
per five seconds per route; rulings, sentences and statutes allow deeper payloads.

**\*** marks a mutation: it takes `requestId` (1–64, from the client). Law passes
`<characterUUID>:<requestId>` to Justice and keeps the confirmed result in its
operation journal (identifiers, revision and status only), so an exact retry gets
the stored result (`replayed=true`) without re-running physical checks, and a
changed payload under the same ID gets `idempotency_conflict`.

Policy actions and their rule (officer / judicial / legal): [README](../README.md#who-can-do-what).

## Session and cases

| Route | Payload | Policy | Justice |
|---|---|---|---|
| `law.session.get.v1` | `{}` | current character | — returns departments, case types, locale, jail facilities, work tasks |
| `law.cases.list.v1` | `status?`, `cursor?` | `justice.case.view` | `ListCases` (department jurisdiction) |
| `law.cases.open.v1` \* | `caseType?`, `title`, `summary`, `draft?` | `justice.case.open` | `OpenCase` |
| `law.cases.get.v1` | `caseId` | `justice.case.view` | `GetCase` with the related index |
| `law.cases.update.v1` \* | `caseId`, `expectedRevision`, `summary`, `title?` | `justice.case.update` | `UpdateCaseSummary` |
| `law.cases.transition.v1` \* | `caseId`, `expectedRevision`, `status` | `justice.case.transition` | `TransitionCase` |
| `law.parties.list.v1` | `caseId`, `cursor?`, `includeRemoved?` | `justice.party.view` | `ListCaseParties` |
| `law.parties.add.v1` \* | `caseId`, `expectedCaseRevision`, `partyType`, `partyIdReference`, `partyRole` | `justice.party.manage` | `AddCaseParty` |
| `law.parties.remove.v1` \* | `caseId`, `partyId`, `expectedRevision` | `justice.party.manage` | `RemoveCaseParty` |

## Charges, statutes and citations

| Route | Payload | Policy | Justice |
|---|---|---|---|
| `law.charges.list.v1` | `caseId`, `cursor?` | `justice.charge.view` | `ListCharges` |
| `law.charges.propose.v1` \* | `caseId`, `expectedCaseRevision`, `defendantCharacterId`, `statuteId`, `count` | `justice.charge.propose` | `ProposeCharge` |
| `law.charges.amend.v1` \* | `caseId`, `chargeId`, `expectedRevision`, `statuteId?`, `count?` | `justice.charge.amend` | `AmendCharge` |
| `law.charges.file.v1` \* | `caseId`, `chargeId`, `expectedRevision` | `justice.charge.file` | `FileCharge` |
| `law.charges.dispose.v1` \* | … + `disposition` (`withdrawn`/`dismissed`) | `justice.charge.dispose` | `DisposeCharge` |
| `law.statutes.list.v1` | `status?`, `cursor?` | `justice.definition.view` | `ListStatutes` |
| `law.statutes.register.v1` \* | `statuteName`, `title`, `category`, `severityClass`, `description?`, `recommendedFine?`, `recommendedCustodySeconds?` | `justice.definition.manage` | `RegisterStatute` (key `<jurisdictionKey>.<statuteName>`) |
| `law.statutes.revise.v1` \* | `statuteId`, `expectedRevision`, any field above, `status?` | `justice.definition.manage` | `GetStatute` + `ReviseStatute` |
| `law.citations.list.v1` | `caseId`, `cursor?` | `justice.citation.view` | `ListCitations` |
| `law.citations.issue.v1` \* | `caseId`, `expectedCaseRevision`, `subjectCharacterId`, `statuteId`, `basisSummary`, `amount?` + `dueInSeconds?` | `justice.citation.issue` | `IssueCitation` (no amount = warning) |

## Warrants

| Route | Payload | Policy | Justice |
|---|---|---|---|
| `law.warrants.list.v1` | `caseId` | `justice.warrant.view` | `GetCase` related warrants |
| `law.warrants.active.v1` | `subjectCharacterId?`, `cursor?` | `justice.warrant.view` | `ListActiveWarrants` |
| `law.warrants.draft.v1` \* | `caseId`, `expectedCaseRevision`, `subjectCharacterId`, `warrantType`, `basisSummary`, `validForSeconds` | `justice.warrant.draft` | `CreateWarrantDraft` |
| `law.warrants.issue.v1` \* | `caseId`, `warrantId`, `expectedRevision` | `justice.warrant.issue` (judicial for search and seizure) | `IssueWarrant` |
| `law.warrants.serve.v1` / `recall` / `quash` \* | same | `justice.warrant.serve` / `recall` / `quash` | `ServeWarrant` / `RecallWarrant` / `QuashWarrant` |

## Field, custody and search

| Route | Payload | Policy | Effect |
|---|---|---|---|
| `law.restraints.self.v1` | `{}` | current character | own restraint/escort state (client poll) |
| `law.restraints.apply.v1` | `targetSource`, `warrantId` xor `custodyId` | `law.restraint.manage` | restrains a nearby subject named by an active arrest warrant or unreleased custody |
| `law.restraints.release.v1` | `targetSource` | `law.restraint.manage` | releases |
| `law.restraints.escort.v1` | `targetSource`, `enabled` | `law.restraint.manage` | escort by the restraining officer |
| `law.custody.facilities.v1` | `{}` | `justice.custody.view` | booking facilities of the department |
| `law.custody.list.v1` | `caseId` | `justice.custody.view` | `GetCase` related custody |
| `law.custody.arrest.v1` \* | `caseId`, `targetSource`, `authorityType` (`warrant`/`judicial_order`), `authorityId`, `expectedAuthorityRevision` | `justice.custody.record` | subject must be restrained and named by the authority → `RecordArrest`; the restraint then rests on the custody record |
| `law.custody.book.v1` \* | `caseId`, `custodyId`, `expectedRevision`, `facilityKey` | `justice.custody.record` | officer and subject together at the facility → `BookCustody`; locks the facility doors |
| `law.custody.release.v1` \* | `caseId`, `custodyId`, `expectedRevision`, `releaseReason` | `justice.custody.release` | `ReleaseCustody` |
| `law.search.inspect.v1` | `targetSource`, `warrantId`, `cursor?` | `law.search.inspect` | read-only Inventory page of a restrained subject named by an active search warrant |
| `law.search.finish.v1` \* | `targetSource`, `warrantId`, `expectedRevision` | `law.search.inspect` | `ServeWarrant` |

## Evidence

| Route | Payload | Policy | Effect |
|---|---|---|---|
| `law.evidence.lockers.v1` | `{}` | `justice.evidence.view` | lockers of the department |
| `law.evidence.collect.v1` \* | `caseId`, `expectedCaseRevision`, `targetSource`, `warrantId`, `itemId`, `itemRevision`, `lockerKey`, `description?` | `justice.evidence.link` + `law.evidence.collect` | Inventory moves the instance to the locker (receipt) → `LinkEvidence` |
| `law.evidence.receipts.v1` | `caseId`, `cursor?` | `justice.evidence.view` | own collection receipts |
| `law.evidence.attach.v1` \* | `caseId`, `transferRequestId`, `expectedCaseRevision` | `justice.evidence.link` | links a confirmed transfer (recovery) |
| `law.evidence.list.v1` | `caseId`, `cursor?` | `justice.evidence.view` | `ListCaseEvidence` incl. removed links, with `physicalState` |
| `law.evidence.remove.v1` \* | `caseId`, `evidenceLinkId`, `expectedRevision`, `disposition?` | `justice.evidence.link` (judicial with a disposition) | `RemoveEvidenceLink`; `destroyed` queues the destruction, `returned` is handed back by staff ([evidence](EVIDENCE.md)) |

## Court and records

| Route | Payload | Policy | Justice |
|---|---|---|---|
| `law.rulings.record.v1` \* | `caseId`, `expectedCaseRevision`, `rulingType`, `summary`, `subjectCharacterId?`, `findings` (verdict) or `outcome` (order) | `justice.ruling.record` | `RecordRuling` |
| `law.rulings.list.v1` | `caseId` | `justice.case.view` | related rulings |
| `law.sentences.list.v1` | `caseId` | `justice.sentence.view` | related sentences |
| `law.sentences.create.v1` \* | `caseId`, `expectedCaseRevision`, `rulingId`, `sentenceType`, `terms` | `justice.sentence.impose` | `CreateSentence` |
| `law.sentences.activate.v1` \* | `caseId`, `sentenceId`, `expectedRevision` | `justice.sentence.activate` | `ActivateSentence` (also resumes) |
| `law.sentences.suspend.v1` \* | same | `justice.sentence.suspend` | `SuspendSentence` |
| `law.sentences.complete.v1` \* | … + `outcome` (`served`/`vacated`/`commuted`), `effectReference?` | `justice.sentence.complete` | `CompleteSentence` |
| `law.cases.seal.v1` / `unseal` \* | `caseId`, `expectedRevision` | `justice.record.seal` | `SealCase` / `UnsealCase` |
| `law.cases.expunge.v1` \* | same | `justice.record.expunge` | `ExpungeRecord` |
| `law.cases.history.v1` | `caseId` | `justice.audit.view` + admin audit permission | `GetRecordHistory` |

## Own status, armory and alerts

| Route | Payload | Policy | Effect |
|---|---|---|---|
| `law.execution.self.v1` | `{}` | spawned character | own custody time and community service |
| `law.service.start.v1` | `sentenceId` | spawned character at the work site | starts a work unit (observed on site) |
| `law.armory.stations.v1` / `catalog` | `stationKey` (catalog) | `law.armory.issue` | stations and items |
| `law.armory.claim.v1` | `stationKey`, `itemKey`, `requestId` | `law.armory.issue`, at the station | one claim per item per UTC day; Inventory/Weapons idempotent grant |
| `law.armory.claims.v1` | `stationKey`, `cursor?` | `law.armory.issue` | own claims, for recovery |
| `law.alerts.citizen.v1` | `department`, `message` | current character, cooldown | notifies on-duty officers with a blip at the reporter |
| `law.alerts.shots.v1` | `{}` | current character | server checks position, area and cooldown |
| `law.alerts.areas.v1` | `{}` | current character | shots-fired areas for the client |

Fines are paid by the debtor through Contracts' own routes
(`contracts.obligations.list.v1`, `contracts.obligation.settle.v1`), which the MDT
uses in `/lawfines`.
