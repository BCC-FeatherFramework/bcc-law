# Evidence collection and recovery — alpha.8

Implements the `LAW_INTEGRATION.md` split: Inventory owns physical instances,
private lockers and transfer receipts; Justice owns evidence links and legal
dispositions; Law owns authorization, interaction and the MDT.

## Setup

Inventory must include `server/services/law_evidence.lua`. After its ordinary
readiness, that module creates its two additive Inventory-owned tables:
`inventory_law_evidence_lockers` and `inventory_law_evidence_receipts`.
Failure leaves evidence operations unavailable. It never runs against the live
server merely because these files were edited.

Configure `LawConfig.Evidence.Lockers` server-side. The proposed Valentine locker
uses the existing booking coordinates; review the actual location for your map.
Limits are 1000 instances / 10000 weight by default. `maxItems` is also the slot
limit, with a hard config bound of 10000. Existing persisted limits cannot be
silently changed by rerunning setup.

Read-only console `LawEvidenceStatus` reports dependency/guard readiness and the
configured locker count; it does not certify setup or live acceptance.

On disposable staging, explicitly run console `LawSetupEvidenceLockers` once
after Law and Inventory are ready. It creates/reuses a private `law_evidence`
inventory for each configured locker. This command **writes storage**, is never
called on startup, and cannot be invoked by a player. No player ACL or public
inventory flag is granted.

The current officer needs duty, commission, case eligibility and the reviewed
`justice.evidence.view/link/dispose` policy actions from Claude's agreement.
Justice's `evidenceLinks` and active `evidenceGuard` must both be available for
new collection/linking. Shared Admin grants remain Claude's responsibility.

## Collection

Open a case → `Probe` → `Colectează de la persoană`.

1. Create and issue a **seizure** warrant for that case and subject. Arrest/search
   warrants do not substitute for seizure authority. The MDT warrant form now
   supports all three types through separate typed routes.
2. Restrain the live subject and bring both players to the configured locker.
   Submit the item ID and current revision from inspection, the seizure warrant,
   locker and description. Clients cannot submit actor/subject UUIDs, inventory
   IDs, arbitrary destinations, quantities or metadata.
3. Inventory validates Law authority and target sessions before and after its
   guarded move, under receipt/inventory/item locks. It preserves the same item
   ID and metadata, bumps its revision, checks current weight/slot capacity,
   honors movement/Weapons guards and records the receipt in the same transaction.
   A weapon instance requires the started Weapons owner and its registered movement
   guard. An equipped/protected weapon may need authoritative unequip first; Law does
   not bypass a Weapons guard or grant a native weapon.
4. Law links the confirmed receipt through Justice `LinkEvidence`, with the
   original subject UUID, decimal instance reference and a stable `:link` intent.
   Collection is not a cross-resource atomic transaction. A failed link leaves
   a confirmed transfer pending; it never moves the item again or reports full
   success. Finish execution of the seizure warrant through its existing
   `Execută` control after the intended collection is complete.

Collection currently happens at the locker, rather than first putting evidence
in the officer's pocket. The target and officer must be alive, restrained/nearby
as appropriate, in the same routing bucket, and within the configured radius.

## Recovery and history

- Retain the same `requestId` and payload after an unknown result. Inventory's
  durable receipt is payload-bound; the transaction's memory cache is not used.
- Exact collection replay recovers its transfer even after the target leaves,
  is released or the resources restart. Actor duty/qualification, current session
  and case access remain required. Changed input under the same ID is a conflict.
- `Istoricul colectărilor mele` lists committed receipts for the current actor,
  case and department, 25 per page. Each records original subject, instance,
  source/destination inventories, locker, revision and creation time. These are
  historical transfer facts, not a claim about the item's present location.
- If the transfer succeeded but the case revision changed before linking, review
  the legal evidence list first. Explicitly acknowledge the recovered transfer,
  then confirm a **new link intent** against the displayed current case revision.
  The existing receipt supplies the item/subject; no second collection occurs.
- Justice rejects duplicate active links. A receipt cannot establish that a
  legal link exists, or authorize another physical action. A missing/deleted
  instance is never recreated from its receipt.

## Dispositions and limits

The MDT records `returned`, `destroyed` or `forfeited` using Justice's disposition
API and current evidence revision. This is a **legal disposition only**; the UI
explicitly confirms that it neither moves nor deletes the item. Physical return,
destruction, inter-locker transfer and forfeiture execution are not implemented
or advertised (`returns=0`, `destruction=0`). Justice's guard remains responsible
for active linked-item destruction, including links from other cases.

The collection receipt is the durable initial custody record. General Inventory
movement continues to use its existing guards and post-commit events; this slice
does not claim a complete court-ready history of every future third-party move.
Only the collecting character's receipts are exposed; delegation/recovery by a
different officer requires a separately reviewed authority path.

## Routes

| Route | Fields besides `department` | Effect |
|---|---|---|
| `law.evidence.lockers.v1` | none | Configured key/label list |
| `law.evidence.collect.v1` | `caseId`, `expectedCaseRevision`, `targetSource`, `warrantId`, `itemId`, `itemRevision`, `lockerKey`, optional `description`, `requestId` | Durable Inventory move, then Justice link |
| `law.evidence.receipts.v1` | `caseId`, optional receipt `cursor` | Current actor's transfer history |
| `law.evidence.attach.v1` | `caseId`, `transferRequestId`, `expectedCaseRevision`, `requestId` | Explicit new link intent for a confirmed transfer |
| `law.evidence.list.v1` | `caseId`, optional UUID `cursor` | Justice evidence page |
| `law.evidence.disposition.v1` | `caseId`, `recordId`, `expectedRevision`, `disposition`, `requestId` | Legal disposition only |

## Required live acceptance

Use a disposable database and two real characters. Verify missing setup/grants,
wrong case/subject/type/status warrant, bucket/distance/duty/license loss, stale
item revision, equipped weapon guards, full locker, simultaneous collections,
rollback and disconnect during a transaction. Drop the reply after collection,
restart and recover the exact receipt. Induce Justice revision conflict, confirm
one physical move, recover and explicitly link. Check safe text, pagination and
that no unrelated character can read receipts. Record a disposition and verify
that it performs no hidden physical deletion or return.

Offline suites use mocked providers and a transaction model. They do not prove
MariaDB locking/DDL or two-player RedM behavior. No live setup command, DB
migration, transfer, legal disposition, grant or resource restart was executed.


Offline verification on 2026-10-19: `python3 tests/run_lua.py` passes 504 checks,
including 29 Inventory transaction-model and 31 Law evidence-authority checks.
`node tests/ui.cjs` and `node --check ui/app.js` pass. The transaction model
covers rollback, guard veto, capacity, session changes, altered payloads, exact
replay after restart/offline and explicit partial-link failure. These are not live
MariaDB concurrency or RedM acceptance results.
