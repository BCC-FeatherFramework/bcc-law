# BCC Law — masterplan de portare nativă Feather

Data: 2026-10-18. Baseline inspectat: pachetul încărcat `bcc-law` 1.1.0.
Status actualizat: portarea runtime a început cu fundația nativă și integrarea
inițială a dosarelor Justice. Nicio acceptanță live Feather nu este revendicată.
Acest document nu certifică pachetul drept portare completă sau release stabil.

Checkpoint: `bcc-law` 2.0.0-alpha.1 și `feather-justice` 0.1.0-alpha.1 create.
Sursa originală este păstrată separat (vezi `docs/BASELINE.md`); 115 înregistrări
de handler sunt inventariate în `docs/HANDLER_INVENTORY.json`. Configurația propusă
este New Hanover / police / peace_officer, fără înregistrare sau grant automat.
Fundația, sesiunile, filtrele Jobs/Licenses/policy și rutele pentru listare/deschidere
dosar sunt implementate. Restul fazelor din plan rămân deschise. README-ul curent
descrie explicit funcțiile lipsă și pașii de staging; niciun server nu a fost restartat.

Continuare alpha.2: Justice implementează propunerea/depunerea/dispunerea
acuzațiilor cu snapshot istoric și lifecycle-ul mandatelor de arest, inclusiv
expirare verificată la citire/operație. Law are acum 15 rute native, cu verificări
de relație dosar–înregistrare și jurisdicție. Interfața MDT completă, custodia,
sentințele și efectele financiare rămân deschise. Vezi `docs/ALPHA2_CHECKPOINT.md`.

Obiectiv autorizat: păstrarea funcționalităților utile și portarea la Feather,
fără dependențe, structură de compatibilitate sau API-uri VORP/oxmysql. Nu se
construiește un Core fals, un obiect Character de compatibilitate sau un shim
`MySQL` peste `DB`. API-urile și modelele de date se reproiectează nativ.

Referință: [Justice masterplan](https://github.com/FeatherFramework/feather-framework-docs/blob/main/feather-justice/Feather_Justice_Master_Plan.md).
Plan local, creat pentru revizuire; nu este publicat în repository-ul de documentație.
Destinația recomandată la publicare: `bcc-law/BCC_LAW_MASTER_PLAN.md` în
`FeatherFramework/feather-framework-docs`; aici poate rămâne un link ulterior.

## 1. Baseline și constatări verificabile

- Manifestul declară VORP Core/Character/Inventory, oxmysql, vechiul Menu,
  bcc-utils, Society și Mailbox. `server/init.lua` cere și `bcc-job-alerts`,
  fără dependență declarată în manifest.
- Clientul folosește `feather-menu2`, diferit de dependența declarată
  `feather-menu` și de resursa Feather curentă `feather-menu-v2`.
- `client/mdtMenu.lua` și `client/penalcodeMenu.lua` există, dar nu sunt încărcate
  de manifest; UI activ include și un MDT Vue separat. Nu se declară paritate
  pentru fișiere doar pentru că există pe disc.
- `server/server.lua` are 2.961 linii; clientul principal 1.706. Separarea pe
  servicii va urmări responsabilitățile, nu păstrarea unui monolit.
- Există interogări directe în `characters`, `horses`, `bcchousing`,
  `bcc_shops`, `bcc_society`, tabele de ranguri și conturi bancare.
- `controllers/ledger.lua` modifică direct ledger-ul Society și solduri bancare.
  Amenzile mai folosesc și `removeCurrency`; toate aceste trasee se elimină.
- Identitatea persistentă este perechea identificator platformă + personaj numeric.
  Nu corespunde UUID-urilor Character din Feather.
- Există scăderi de timp/muncă declanșate de client (`TakeTime`, `UpdateService`)
  și jailbreak care șterge înregistrarea închisorii. Aceste semantici nu se portă:
  timpul, progresul, evadarea și eliberarea necesită validare server autoritară.
- Probele actuale din dosare sunt în principal înregistrări descriptive;
  nu reprezintă deja un chain-of-custody pentru instanțe Inventory.
- Pachetul nu are repository Git propriu. Nu există branch/tag de baseline
  demonstrat. Licența GPL-3.0 și atribuirea se păstrează.

## 2. Proprietarii datelor

| Concern | Proprietar | Rol BCC Law |
|---|---|---|
| Sesiune, cont, actor curent | Core | Rezolvă identitatea server-side |
| Profil/căutare persoană | Character | Consumă contract public cu limite și autorizare |
| Organizația departamentului | Organizations | Configurează referințe UUID validate |
| Angajare, grade, duty, job activ | Jobs; Society pentru angajările administrate de Society | Citește fapte; cere operații proprietarului |
| Comisie/calificare profesională | Licenses | Verifică prin contract public |
| Puteri de serviciu | Authority prin Core policy | Aplică acțiuni numite și scope de jurisdicție |
| Cod penal, dosare, părți, acuzații, mandate | Justice | Interfață și orchestrare |
| Citări, autoritate de custodie, hotărâri, sentințe | Justice | Coordonează efectele fizice |
| Obligație financiară | Contracts | Afișează și solicită operația legal autorizată |
| Sold, plăți și trezorerie | Economy | Consumă exclusiv API-uri |
| Salarii și fonduri Society | Society + Economy | Un singur traseu de payroll, fără acumulare dublă |
| Iteme, armurerie, confiscări | Inventory; Weapons pentru identitatea/politica armelor | Validează interacțiunea și custodia |
| Proprietăți și interese | Property | Afișează numai rezultate autorizate |
| Cai, căruțe și bărci deținute | Assets | Verifică asset-ul exact, nu doar modelul |
| Acces delegat persistent | Access | Consumă integrarea atunci când este disponibilă |
| Moarte și recuperare | Medical | Suspendă/reevaluează interacțiunile |
| Uși și starea încuietorilor | bcc-doorlocks | Cere operații prin API și păstrează un singur proprietar |
| Interacțiuni, locații, UI, animații, NPC | BCC Law | Proprietar direct |
| Audit transversal | Audit | Publică fapte revizuite prin outbox durabil |

Justice nu deține animații, teleporte sau simularea închisorii. BCC Law nu
deține o a doua bază de dosare sau un al doilea registru de datorii.
Calitatea de angajat nu acordă implicit orice putere juridică; calificarea,
permisiunea, jurisdicția și condițiile domeniului sunt verificări distincte.

## 3. Inventarul funcțional și destinația

| Funcție existentă | Decizie și criteriu de păstrare |
|---|---|
| MDT Vue, dashboard, profil persoană | Păstrăm prezentarea; payload-uri noi, paginate și filtrate pe server |
| Meniuri de teren și controale | Refacem cu exporturile Menu v2; fără adaptor al vechiului Menu |
| Cod penal configurabil/editor | Definiții și revizii Justice; recomandările nu sunt pedepse automate |
| Dosare, suspecți, ofițeri, acuzații, note | Justice; snapshot istoric al infracțiunii și autorului |
| Mandate și închidere mandat | Lifecycle Justice explicit: servit, revocat, expirat etc. |
| Calcul amendă și durată | Propunere calculată server-side; aplicarea cere autoritate și motiv |
| Sentință combinată amendă/închisoare | Hotărâre/sentință Justice + workflow durabil, fără efecte parțiale ascunse |
| Amendă imediată, factură, plata facturii | Citare Justice + obligație Contracts + settlement Economy |
| Item factură | Reprezentare Inventory opțională a obligației, fără valoare monetară autoritară în metadata |
| Jail automat/manual, revenire la conectare | Execution BCC Law legat de custodie/sentință Justice |
| Reducere timp, jailbreak, eliberare | Server autoritar; evadarea nu șterge sentința |
| Community service | Sentință Justice; task-uri, validare și progres fizic BCC Law |
| Cătușe, chei, lockpick, escortă, wagon | Păstrăm mecanicile; ținte apropiate, sesiuni curente, state-machine server |
| Percheziție și confiscare | Inventory + autoritate juridică + restraint verificabil; fără transfer arbitrar din client |
| Armurerie, muniție, commissary | Config server allowlist; Inventory/Weapons; grant idempotent, limite și audit |
| Joburi multiple, duty, payroll, ledger | Jobs/Society/Economy; eliminăm prefixele off și SQL străin |
| Verificare vehicul/mount | Assets și asociere verificabilă entity–asset; hash-ul modelului nu dovedește ownership |
| Uși de secție/celule | Integrare bcc-doorlocks; fără două bucle de control asupra aceleiași uși |
| Badge, blips, NPC, witness, alerte | BCC Law + Toolkit/Notify; lifecycle și cleanup pe owner |
| Scrisori și remindere | Opțional, numai după verificarea providerului Mailbox; nu blochează emiterea datoriei |
| Webhook-uri | Audit/redacție; fără secrete în config shared sau payload client |
| Localizare română/engleză/germană | Migrare în registrul locale Core; păstrăm sensul și traducerile |

Meniurile alternative neîncărcate trebuie clasificate ca înlocuite sau necesare
după inventarul ecranelor. Nu se lasă implementări vechi inactive în produsul final.

## 4. Dependențe și coordonare

Baseline disponibil local: Core, MySQL, Character, Jobs, Organizations, Authority,
Contracts, Economy, Inventory, Weapons, Medical, Property, Assets, Menu v2,
Toolkit, Notify, Audit, Society și Doorlocks. Prezența nu certifică toate API-urile.

- Justice nu este implementat în workspace la această inspecție. Îi cerem
  contractele pe felii: jurisdicții/statute, dosare/părți, acuzații/mandate,
  citări, custodie, sentințe, probe și acces la înregistrări.
- Licenses este în lucru cu alt AI, conform proprietarului. Nu modificăm acel
  domeniu și nu inventăm nume de exporturi. Convenim check-ul calificării,
  issuer authority, status/expiry, offline subjects, readiness și erori.
- Access este la Savsin. Nu duplicăm granturile persistente în BCC Law.
- Character: verificăm existența unei căutări privilegiate paginate, deoarece
  providerul inspectat anterior nu publica `SearchProfiles`. Extinderea aparține Character.
- Society: inventariem exporturile actuale pentru membership, management și
  payroll. Lipsa unui export se rezolvă la owner; nu justifică SQL din BCC Law.
- Evidence: Inventory folosește local ID numeric de item; masterplanul Justice
  presupune UUID. Convenim o referință stabilă versionată înainte de schema linkurilor.
- Assets: nu avem încă dovada unui contract public entity–asset. Verificarea
  ownership-ului unui mount rămâne indisponibilă până se poate stabili identitatea exactă.
- bcc-job-alerts, Mailbox și minigame-urile trebuie inspectate separat. Niciunul
  nu este presupus compatibil doar fiindcă numele începe cu bcc.

Nu adăugăm dependențe circulare Justice–Law sau Core–gameplay. Law așteaptă
bounded readiness a funcțiilor necesare. Modulele opționale indisponibile sunt
ascunse/raportate explicit; acțiunile protejate nu au fallback permisiv.

## 5. Contractul nativ BCC Law — proiectare propusă

- Exporturi operaționale: `GetHealth`, `GetCapabilities`, `AwaitReady`; schema
  exactă se fixează înainte de implementare. Capabilities declară doar funcții sănătoase.
- Rute noi `law.<operation>.v1`, cu `{ ok, value }` sau `{ ok=false, code,
  message, details? }`. Lista exactă se generează din inventarul fiecărui handler.
- NUI primește o listă explicită de operații și snapshot-uri de prezentare;
  nu poate selecta exportul, resursa, actorul sau autoritatea serviciului.
- Actorul vine din sesiunea Core; ținta UUID este intrare validată, niciodată
  dovadă de acces. Source ID este numai adresă de transport.
- Fiecare mutație definește acțiune policy, duty, jurisdicție, calificare,
  grade dacă sunt relevante, target rules, limite, rate limit și idempotency scope.
- Cererile delayed leagă actor session, target session unde este cazul,
  request ID și revision; se reevaluează după yield și înaintea efectului.
- `service unavailable` refuză acțiunea; nu se reutilizează un răspuns pozitiv
  expirat drept autorizare pentru o mutație nouă.
- Textul juridic se afișează ca text sigur; căutările și listele au limite și
  cursori. Dosarele confidențiale sunt filtrate în serviciul autoritar.
- Interacțiunile de teren verifică distanță și stare server-side; tokenurile
  de animație/minigame sunt unice, limitate și nu acordă singure autoritate.

## 6. Persistență și workflow-uri

Tabele BCC Law propuse (nume de lucru): `bcc_law_schema_migrations`,
`bcc_law_operations`, `bcc_law_execution_sessions`, `bcc_law_service_progress`,
`bcc_law_outbox`. Schema și indexurile se finalizează înainte de prima migrare.

Law păstrează doar intent-ul/reconcilierea interacțiunii și execuția gameplay.
Nu păstrează solduri, liste canonice de mandate, datorii sau sentințe concurente
cu proprietarii. Legături: UUID Justice/Contracts/Organizations și referințe
Inventory conforme contractului convenit. Timestamp-uri UTC, migrații checksummed.

Workflow amendă: autoritate + interacțiune → citare Justice → obligație Contracts
→ plata prin Contracts/Economy. Se decide un singur orchestrator pentru emiterea
obligației; Law nu o emite din nou dacă Justice o coordonează deja. Lipsa banilor
lasă datorie legală, nu produce debit direct sau sold negativ.

Workflow sentință: Justice confirmă hotărârea → Law rezervă execuția → livrează
booking/teleport actualei sesiuni → confirmă sau reconciliază rezultatul. Reconnect
reconstruiește din sentința autoritară și progres; nu reîncepe pedeapsa accidental.
Politica timpului offline și cumulul/reducerea sentințelor se decid explicit.

Workflow probe: Inventory confirmă transferul/hold-ul → Justice leagă referința
→ operația Law se finalizează. La rezultat incert se caută operația originală.
Ștergerea/consumarea probelor legate necesită guard sau dispoziție imuabilă,
convenite cu Inventory/Weapons; niciodată SQL peste tabelele lor.

Fiecare workflow are owner de retry, stări pending/confirmed/rejected/unknown,
chei stabile, recuperare după restart și comandă read-only de reconciliere.
Nu declarăm tranzacție atomică peste mai multe resurse. Pierderea reply-ului
nu permite o nouă amendă, plată, armă, reducere de timp sau sentință.

## 7. Schema existentă și cutover

| Sursa actuală | Destinație |
|---|---|
| `bcc_law_penal_codes` | Statute Justice versionate |
| `bcc_law_cases`, `case_suspects`, `case_officers` | Cases și parties Justice |
| `bcc_law_case_charges` | Charges + snapshot infracțiune Justice |
| `bcc_law_case_notes`, `case_evidence` | Note/probe descriptive Justice; nu inventăm iteme fizice |
| `bcc_law_warrants` | Warrants Justice; mapare explicită status open/closed |
| `bcc_law_bills` | Citări Justice + obligații Contracts; plățile istorice au proveniență |
| `bcc_law_jail` | Custodie/sentințe Justice + execuție Law |
| `bcc_law_communityservice` | Sentință Justice + progres Law |
| `bcc_law_mdt_logs` | Istoric protejat/importat; audit nou via outbox/Audit |
| `characters`, Society, Banks, Horses, Housing, Shops SQL | Eliminat; API-uri ale ownerilor |

Înainte de cutover: inventar date reale și backup, alegere clean install sau
import. Nu presupunem că încărcarea folderului înseamnă existența tabelelor.
Un import necesită mapare explicită numeric personaj → UUID, reconciliere de
numere/statusuri/sume și oprirea writerilor vechi. Nu se fac UUID-uri din ID-uri
numerice și nu se șterg datele de producție automat.

Un eventual importator istoric este unealtă separată, exclusă din runtime și
release-ul Feather, astfel încât produsul final nu conține ramuri VORP/oxmysql.
Păstrăm baseline-ul original ca arhivă în afara release-ului; fără repository
upstream verificat nu pretindem branch/tag deja protejat. Nicio operație de
push, arhivare externă sau migrare DB nu este executată prin acest plan.

## 8. Structura țintă

```text
config/                 departamente, jurisdicții, interacțiuni, jail, armurerie
shared/                 results, validation, limite și DTO-uri proprii
server/core/            lifecycle, dependency registry, policy și actor context
server/repositories/    DOAR tabele BCC Law
server/services/        workflows, interactions, custody execution, service tasks
server/routes/          handlers Core expliciți pe funcție
server/migrations/      migrații checksummed BCC Law
server/main.lua         bootstrap restrâns
client/core/            sesiune, readiness, cleanup, transport Core
client/services/        cuffs, escort, transport, jail, tasks, alerts, doors bridge
client/menus/           API nativ Menu v2, fără initiate/RegisterMenu vechi
client/nui/             operații MDT explicite și focus ownership
ui/src/                 Vue MDT și DTO-uri noi
translations/           locale Core
tests/                  contracte, concurență, lifecycle, failure/replay
README.md               instalare, owner config și API public
```

Nu păstrăm directoarele `controllers/jobs.lua`/`ledger.lua` ca adaptoare cu
semnificația veche. Eliminarea lor se face după mutarea funcțiilor necesare.
Build-ul UI trebuie să regenereze `ui/dist`, fără node_modules în release.

## 9. Fazele de implementare și ieșire

| Fază | Livrabil | Criteriu de închidere |
|---|---|---|
| LAW0 — inventar/contract | Feature map, lista tuturor handlerilor, date reale, matrice autoritate | Scop v1 și contractele consumate acceptate; niciun API presupus |
| LAW1 — fundație | Manifest nativ, Core/MySQL, lifecycle, config, locale, diagnostics | Start curat; failed/degraded corect; fără wrapper VORP/oxmysql |
| LAW2 — duty/organizații | Jobs, Licenses, Authority și Society pentru operații deținute de Society | Multi-employer, schimbare duty/rol/calificare și refuzuri testate |
| LAW3 — teren/UI | Toolkit, Menu v2, Notify, cuffs, escort, transport, badge, focus | Două sesiuni reale; distanță, cleanup, moarte, disconnect și restart |
| LAW4 — MDT/Justice | Jurisdicții, statute, dosare, părți, acuzații, mandate | Date doar din Justice; privacy, stale revision și retry testate |
| LAW5 — financiar | Citări, Contracts, Economy, item document, payroll unic | Fără dublă plată/emitere; timeout/restart/offline cu aceleași ID-uri |
| LAW6 — jail/service | Sentințe/custodie Justice, booking și progres server Law | Offline policy, evadare, task replay și eliberare verificate |
| LAW7 — bunuri/probe | Inventory/Weapons, Assets, Property, Doorlocks, Access când disponibil | Custodie și acces corecte; fără SQL străin; transfer/hold/revocare |
| LAW8 — audit/cutover | Producer schemas, outbox, import separat dacă necesar | Recovery/reconciliere, writer unic, inventar legacy zero în produs |
| LAW9 — release | README, pachet runtime, compatibilitate, acceptance report | Instalare curată și upgrade/restart; toate feature-urile declarate demonstrate |

Fazele nu autorizează modificarea implicită a domeniilor lucrate de alți AI.
Blocajele de provider sunt documentate; nu se construiesc substitute locale.
Nu se declară Law portat complet doar pentru că pornește sau se deschide MDT.

## 10. Acceptanță obligatorie

- Static: toate fișierele manifest există, ordinea este verificată, fără dublări;
  nicio referință runtime/config/UI la VORP, oxmysql, bcc-utils, feather-menu2,
  vechiul Menu sau evenimentul de selectare a personajului din framework-ul vechi.
- Nu există identități Steam/charidentifier în DTO-urile noi, prefix off ca job,
  add/removeCurrency, SQL Characters/Society/Banks/Horses sau fallback de tabel bancar.
- Validare syntax/Lua, build UI, result envelopes, rate limits, limite payload,
  paginare, duplicate/conflict, stale session și source reuse.
- Migrare first-run/rerun/checksum/failure; rollback tranzacție; operații
  concurente pe aceeași amendă, probă, sentință și interacțiune.
- Negativ: fără job, off duty, grad insuficient unde este cerut, licență expirată,
  jurisdicție greșită, provider oprit, target la distanță, cerere fabricată din client.
- Jail/service: spam-ul TakeTime/UpdateService nu reduce pedeapsa, jailbreak
  nu o șterge, task completat anterior nu poate fi contabilizat din nou.
- Restart Law/Core/Justice/Inventory și pierdere răspuns după commit: reconciliere,
  fără duplicare și fără succes fals. Medical recovery nu șterge sentința.
- MDT: drepturi pe înregistrare, date sigilate, notes/probe sensibile, text sigur,
  răspuns întârziat după logout, Escape/focus, 1080p/1440p/ultrawide.
- Două persoane: cuffs/escort/search, acces refuzat, mandat/citare, booking,
  confiscare și reconectare; mock-urile nu închid acceptanța nativă/multiplayer.
- Smoke read-only propus: `LawReleaseContractSmokeTest`; fixture-urile care
  modifică date sunt explicit development-only și excluse din release config.
- Raport final: versiuni exacte de dependențe, comenzi, PASS/FAIL, date, limite,
  gates amânate. Nu se reutilizează dovezi VORP ca dovadă Feather.

## 11. Decizii încă deschise

1. Prima jurisdicție și cine administrează statutele; permisiuni officer/judge.
2. Politica mandatelor, arestului fără mandat și motivelor de eliberare.
3. Beneficiarul amenzilor: sistem sau trezorerie de organizație; plăți parțiale
   numai dacă sunt suportate explicit de contractele reale.
4. Timp offline/online, cumulul sentințelor și efectul evadării/community service.
5. Contractul calificărilor Licenses și membership/payroll Society.
6. Dovezi Inventory: identitate, holds, mutare, consum/distrugere și redacție.
7. Clean install versus import; retenție, dosare sigilate și expungement.
8. Consumator independent suplimentar pentru validarea Justice. Modulele MDT/Jail
   din Law oferă scenarii utile, dar nu sunt două resurse independente. Nu creăm
   artificial încă un produs; raportăm separat acest gate din masterplanul Justice.
9. Alerte/Mailbox/minigame: provider compatibil, opționalitate și failure semantics.

## 12. Stadiul curent și următorul pas — alpha.5

LAW1 și integrarea LAW2 există ca implementare nativă; acceptanța live rămâne deschisă.
LAW4 include dosare, participanți, acces pe dosar, acuzații, mandate de arestare și
MDT nativ. Nu echivalează cu închiderea fazei: lipsesc baza reală, concurența,
politicile finale, privacy avansat și sesiunile multiplayer.

Următorul pas: pregătirea instanței staging după `staging/README.md`, apoi testul
cu două personaje și MariaDB. Configurațiile pregătite sunt fragmente neactivate;
Licenses și Access nu au fost modificate. Booking/custodie are acum rezervare, confirmare fizică și eliberare explicită;
plasarea/reconectarea și sentințele rămân separate. Citările au acum integrare durabilă Contracts și plata proprie prin
`/lawfines`; rămân deschise validarea financiară reală și politica finală. Vezi `docs/ALPHA5_CHECKPOINT.md` pentru limitele exacte.
