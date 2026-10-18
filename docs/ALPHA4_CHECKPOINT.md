# Alpha.4 checkpoint — 2026-10-18

Justice 0.1.0-alpha.4 / Law 2.0.0-alpha.4 adds the citation/fine integration slice.

- Typed citation request/read/list/cancel, active-subject UUID checks, parent
  revision and participant eligibility, bounded server-configured financial terms.
- Additive migration 004 and durable Contracts draft/issue/cancel workflow;
  external idempotency keys survive restarts and missing replies. No foreign SQL.
- 24 native Law RPC routes, MDT citation forms, and `/lawfines` using the installed
  Contracts own-character routes. No officer-target debit or forced collection.
- Read-only `JusticeCitationStatus` and UUID-based `LawCitationPreflight`.
- Inactive staging fragments for Contracts issuer trust and exact service grants.
  Shared Contracts/Admin/Jobs/Licenses configs and running server are untouched.

Offline checks: Justice 248 + lifecycle 15; Law 137 + lifecycle 10 + client 14 +
installed Contracts route identity 12 = **436 Lua assertions**. Character fixtures
are UUIDs, including v4 UUIDs and numeric/legacy identity rejection tests. Cfx source
IDs are transport only. Installed Contracts type normalization and route code are
exercised with mocked persistence/settlement. Browser logic verifies scoped debtor
payloads, unknown-payment retry retention and generation fencing. JavaScript syntax,
manifest files and native runtime dependency checks are also performed.

This does not demonstrate real money movement, Cfx JSON, MariaDB locks/migrations,
or multiplayer UI behavior. Those are staging acceptance gates. The current system
sink and terms are proposed configuration; final fine/judicial policy is still open.
Legal issuance and Contracts payment status remain separate. No appeals, tariff
calculation, default enforcement, refunds, custody, booking or sentences are added.

Follow `../staging/README.md` plus its alpha.4 section. Next implementation slice:
booking/custody after the citation staging checks, without inventing jail/offline
sentence rules or a second copy of Contracts/Economy state.
