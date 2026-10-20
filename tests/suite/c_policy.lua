-- Qualified policy (duty + commission), judicial rules, audit and the operation journal.
return function(t)
    local function open(source, title, requestId)
        return t.law(source, 'law.cases.open.v1', { title = title, summary = 'Summary.', requestId = requestId }, true)
    end
    local case = open(5, 'Policy case')
    t.check('qualified officer opens a case', case.ok and case.value.status == 'open', t.code(case))
    t.check('a citizen without duty is refused', open(6, 'Citizen').code == 'duty_required')
    t.jobs[t.ion].police = false
    local judge = open(5, 'Judge only')
    t.check('legal actions accept the judicial profile', judge.ok, t.code(judge))
    t.jobs[t.ion].judge = false
    t.check('off duty everywhere is refused', open(5, 'Nobody').code == 'duty_required')
    t.jobs[t.ion].police, t.jobs[t.ion].judge = true, true
    t.licenses[t.ion].peace_officer, t.licenses[t.ion].judicial_commission = false, false
    t.check('a missing commission is refused', open(5, 'No license').code == 'qualification_required')
    t.licenses[t.ion].peace_officer, t.licenses[t.ion].judicial_commission = true, true

    t.jobs[t.ion].judge = false
    local statute = t.law(5, 'law.statutes.register.v1', { statuteName = 'test.only', title = 'Test', category = 'test',
        severityClass = 'infraction' }, true)
    t.check('penal code management needs the judicial profile', statute.code == 'duty_required', t.code(statute))
    t.jobs[t.ion].judge = true

    local direct = t.invoke('some-resource', 'bcc-law', 'EvaluateActionPolicy', 'justice.case.view',
        { caller = 'bcc-law', source = 5, subject = { resource = 'bcc-law' } })
    t.check('policy export answers only feather-admin', not direct.ok and direct.code == 'invalid_law_context')

    local history = t.law(5, 'law.cases.history.v1', { caseId = case.value.caseId })
    t.check('protected history needs administrator audit authority', history.code == 'authorization_denied', t.code(history))
    t.adminAudit[t.ion] = true
    history = t.law(5, 'law.cases.history.v1', { caseId = case.value.caseId })
    local facts = {}
    for _, item in ipairs(history.ok and history.value.items or {}) do facts[item.fact] = true end
    t.check('judge with audit authority reads the history', history.ok and facts['justice.case.opened.v1'] == true,
        history.ok and json.encode(history.value.items[1]) or t.code(history))

    -- Operation journal: exact retry, changed payload, other character.
    local first = open(5, 'Journal', 'journal-1')
    local replay = open(5, 'Journal', 'journal-1')
    t.check('exact retry replays the confirmed result', replay.ok and replay.value.replayed == true
        and replay.value.caseId == first.value.caseId, t.code(replay))
    t.check('the journal keeps identifiers and state only', replay.ok and replay.value.title == nil and replay.value.summary == nil)
    t.check('a changed payload under the same ID is refused', open(5, 'Changed', 'journal-1').code == 'idempotency_conflict')
    local count = tonumber(t.sql.value("SELECT COUNT(*) FROM justice_cases WHERE title='Journal'"))
    t.check('Justice holds exactly one case for the request', count == 1, count)

    local stale = t.rpcs['law.cases.list.v1'].handler({ department = 'new_hanover' }, 5, { characterId = t.ion, sessionId = t.uuid(999) })
    t.check('a stale session context is refused', stale.code == 'session_expired', t.code(stale))
    t.check('an unknown department is refused', t.law(5, 'law.cases.list.v1', { department = 'west_elizabeth' }).code == 'department_unavailable')
    local other = t.law(5, 'law.cases.get.v1', { caseId = t.uuid(12345) })
    -- Justice decides policy before lookup: an unknown id reveals nothing.
    t.check('an unknown case reveals nothing', other.code == 'authorization_denied' or other.code == 'not_found', t.code(other))
end
