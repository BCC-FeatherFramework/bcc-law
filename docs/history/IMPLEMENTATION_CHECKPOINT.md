# Native Law / Justice checkpoint — 2026-10-18

Runtime versions: BCC Law 2.0.0-alpha.1; Justice 0.1.0-alpha.1.

Offline validation executed:

| Command / suite | Result |
|---|---|
| Justice `python3 tests/run_lua.py`: legal-record transaction suite | 52 checks PASS |
| Same runner: migrations and lifecycle | 13 checks PASS |
| Law `python3 tests/run_lua.py`: access and route suite | 36 checks PASS |
| Same runner: provider lifecycle and registration races | 8 checks PASS |
| Same runner: client and real installed Menu v2 schemas | 16 checks PASS |

Total: 125 explicit assertions passed. Both runners also parse every Lua file
in their own resource using the installed Lua 5.4 shared library. No Lua runtime
or package was installed. Mock database transactions exercise rollback, receipts,
lost commit replies and actor changes; they do not establish actual MariaDB
locking, DDL behavior or Cfx JSON/networking. Expected error messages in the
client negative cases do not indicate a failed suite.

Static checks passed: manifest file paths, license presence, whitespace, absence
of prohibited framework/database compatibility references in runtime Lua.
The original uploaded source remains intact outside the runtime folder; the
exact path is recorded in BASELINE.md. No server restart, live database write,
role grant, change to other domains, commit, push or remote publication occurred.

Ready for source review and staging preparation, not production acceptance.
The new resource does not yet reproduce all original Law features. Legal
definitions, current qualification/job facts and Core policy must be configured
and validated before case access can succeed in game. Existing capabilities
explicitly advertise absent police/legal features as zero.
