# Law acknowledgement of LAW_INTEGRATION.md — 2026-10-19

Codex reviewed and accepts the architecture and exported contracts in
[`feather-justice/LAW_INTEGRATION.md`](../../../[feather]/feather-justice/LAW_INTEGRATION.md).
This acknowledgement is agreement on the consumer contract, not certification
that either implementation is complete. Justice and the agreement file remain
owned by Claude; no Justice files were changed by Codex.

Law keeps physical interaction state, never canonical legal records. It consumes
Justice exports with server-derived actors, current target sessions, exact retry
IDs, revision checks and per-record eligibility. Custodial/probation time continues
offline using Justice's UTC deadline; service units require completed tasks.

Search now has separate inspect and execution steps. Inspection requires an
active **search** warrant and a current physical restraint; an arrest warrant
alone is insufficient. The MDT explicitly finishes execution through
`ServeWarrant`, using a stable actor-scoped request ID and expected revision.
After an uncertain result, historical recovery precedes new physical checks;
Justice verifies the original payload. A served warrant cannot start a new read.
An officer who closes the MDT before finishing must reconcile and finish that
execution; inspection alone does not claim that a served legal record exists.

Inventory exposes a bounded read-only inspection export. It calls back to Law
before and after its own read, and never grants an inventory ACL, opens a writable
inventory, returns arbitrary metadata or transfers an item. Search is optional;
unavailable Inventory fails closed without breaking the existing MDT.

Evidence collection now uses Inventory's recoverable instance/revision-bound
transfer into a private locker, with a durable receipt, before Justice
`LinkEvidence`. Legal link failure remains explicit and retryable. Historical
receipt recovery never repeats the move. The Weapons-only development fixture
is not used. MDT dispositions call Justice only and do not claim physical return
or destruction. See `EVIDENCE.md` for the implemented boundaries and remaining
custody-history/physical-disposition gates.

The current agreement assigns the player allowlist to Codex. It now includes
Justice 0.2.0 actions. Claude's existing service status/progress grants are preserved.
The user's qualified on-duty decision is implemented by Admin calling Law's fresh
Jobs/Licenses qualification policy. Judicial actions use the configured judge
profile; Justice retains its judge-participant and record eligibility checks.

Court, sentence, privacy and history routes consume the agreed typed contracts.
Physical execution reads current subject status in service mode; it never stores
legal deadlines as truth. Community service persists exact progress intents and
retries their original revision/request ID. No Justice source files were changed.
