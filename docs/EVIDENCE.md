# Evidence: collection, links and dispositions (beta.1)

Split of ownership ([Justice integration agreement](../../../[feather]/feather-justice/LAW_INTEGRATION.md)):
Inventory owns the item instances, the private lockers and the transfer and
disposition receipts; Justice owns the evidence links, the destroy guard and the
legal dispositions; Law owns the authority checks, the interaction and the MDT.

## Setup

Inventory's `server/services/law_evidence.lua` creates its tables after Inventory
is ready: `inventory_law_evidence_lockers`, `inventory_law_evidence_receipts` and
`inventory_law_evidence_dispositions`. Configure `LawConfig.Evidence.Lockers`
(the default Valentine locker uses the booking coordinates; review it for your
map; `maxItems` is also the slot limit). Then run the console command
`LawSetupEvidenceLockers` once: it creates or reuses one private `law_evidence`
inventory per locker. It never runs on startup and grants no player access.
`LawEvidenceStatus` shows readiness, the Justice guard, the lockers and any
pending or failed physical step.

## Collection

Case → Evidence → Collect from a person.

1. A judge issues a **seizure** warrant for the person in this case (an arrest or
   search warrant is not seizure authority).
2. The person is restrained and both stand at the locker. The officer enters the
   item id and revision (from the search result), the warrant, the locker and a
   description. The client cannot choose actors, inventories, quantities or metadata.
3. Inventory checks Law's authority before and after the move, under locks, keeps
   the item identity and metadata, checks capacity and the Weapons guard, and
   stores the receipt in the same transaction.
4. Law links the receipt in Justice (`LinkEvidence`, decimal instance id, the
   original subject). While linked, Justice's destroy guard vetoes destroying the item.

Collection and linking are two resources: a failed link leaves a confirmed
transfer pending (`evidence_link_pending`). Retry with the same request ID, or open
"My collection receipts" and link the transfer explicitly at the current case
revision after checking the evidence list. A receipt never moves an item twice.

## Dispositions

Removing a link with a disposition is the permanent legal record (judges only):

| Disposition | Justice | Physical step (Inventory) |
|---|---|---|
| `returned` | link removed with the disposition | the item goes back to the person it was seized from (`ReturnLawEvidence`) |
| `destroyed` | link removed; the guard releases the item | the item is destroyed (`DestroyLawEvidence`) |
| `forfeited` | link removed | none: the item stays in the locker |
| none | link removed | none: the item stays in the locker |

The physical step runs only after Justice confirmed the disposition. Law queues it
durably (`bcc_law_evidence_dispositions`, request ID
`law:evidence:<disposition>:<evidenceLinkId>`), tries it at once and then every 15
seconds. Inventory accepts it only after calling back
`AuthorizeEvidenceOperation('dispose')`, which matches a queued step for that
item and disposition. Each request commits once with its receipt, so retries and
restarts never return or destroy twice. A return checks the recipient's capacity
and the Weapons movement guard; a destroy goes through the normal destroy guards
(another case may still hold the item).

States, shown in the MDT as "Physical step": `pending` (retried: Inventory not
ready, recipient inventory full, transient conflict), `done`, `failed` (needs
staff: item no longer in a locker, unknown recipient, guard refusal). After fixing
the cause, `LawEvidenceRetry <evidenceLinkId>` queues a failed step again with the
same request ID.

## Limits

- Only the collecting officer's receipts are listed.
- The collection receipt is the initial custody record; later third-party moves
  rely on Inventory's own guards and events, not a complete court-ready history.
- A return goes to the recorded subject only; returning to someone else is not offered.

## Tests

`tests/suite/f_evidence.lua` runs the whole flow on a real database with the real
Justice: search, seizure, collection, guard, a forged physical request refused,
returned/destroyed/forfeited, a failed step reported and requeued. Inventory is
mocked at its export boundary there; in game, check a real return into a full
inventory and a weapon item ([acceptance tests](ACCEPTANCE_TESTS.md)).
