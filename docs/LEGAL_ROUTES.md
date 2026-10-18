# Native legal routes — 2.0.0-alpha.2

Law now registers 15 routes in total. All require an active Core character,
validated payload, active on-duty assignment, the configured qualification and
the named policy action. Department determines jurisdiction server-side. Legal
subjects are client-selected UUID inputs validated by Justice, never identities
trusted as authority. There is no arbitrary export/endpoint selector.

| New route | Payload after `department` | Dispatch |
|---|---|---|
| `law.cases.get.v1` | `caseId` | `GetCase` |
| `law.charges.propose.v1` | `requestId`, `caseId`, `expectedCaseRevision`, `subjectCharacterId`, `statuteId`, `count` | `ProposeCharge` |
| `law.charges.list.v1` | `caseId`, `cursor?` | `ListCharges` |
| `law.charges.file.v1` | `requestId`, `caseId`, `recordId`, `expectedRevision` | `FileCharge` |
| `law.charges.dispose.v1` | previous row + `status` (`withdrawn`/`dismissed`) | `DisposeCharge` |
| `law.warrants.draft.v1` | `requestId`, `caseId`, `expectedCaseRevision`, `subjectCharacterId`, `basisSummary`, `validForSeconds` | `CreateWarrantDraft` |
| `law.warrants.list.v1` | `caseId`, `cursor?` | `ListCaseWarrants` |
| `law.warrants.active.v1` | `subjectCharacterId?`, `cursor?` | `ListActiveWarrants` |
| `law.warrants.issue.v1` | `requestId`, `caseId`, `recordId`, `expectedRevision` | `IssueWarrant` |
| `law.warrants.serve.v1` | same as previous row | `ServeWarrant` |
| `law.warrants.recall.v1` | same as previous row | `RecallWarrant` |
| `law.warrants.quash.v1` | same as previous row | `QuashWarrant` |

Draft type is fixed server-side to arrest. Client-selected issuers, deadlines,
jurisdictions, status overrides or arbitrary fields are rejected. Every related
mutation checks both parent case and actual child relationship before dispatch;
Justice then independently validates the transaction and authorization. Case
routes additionally need `justice.case.view`; transitions need their record's
view action as well as their mutation action. The policy action list is in
Justice LEGAL_RECORDS.md. Configure those actions explicitly with intended roles
and jurisdiction scope; no permission grants were added by this code change.

Existing request limits remain: 8192 bytes, depth 2, nodes 12, five calls per
five seconds per route. Lists request 25 items. Mutation request IDs are scoped
to the authenticated character and must be reused after uncertain outcomes.
Session/generation changes fence late replies after yielding provider calls.

The native case list remains read-only. Complete charge/warrant MDT screens,
physical arrests and custody are not yet implemented; `chargeRoutes` and
`warrantRoutes` advertise the API integration, while the full `warrants`
gameplay capability remains zero. Law requires Justice alpha.2's charge and
warrant features and refuses readiness with an older provider.
