-- Alerts to on-duty officers, the penal-code editor, citations, sealing and expunging.
return function(t)
    -- Alerts: Ion is on duty (account language Romanian); Gigi is a citizen.
    t.place(5, -281, 793, 118); t.place(6, -270, 800, 118)
    local function last(source)
        for index = #t.notifications, 1, -1 do if t.notifications[index].source == source then return t.notifications[index] end end
    end
    local report = t.rpc(6, 'law.alerts.citizen.v1', { department = 'new_hanover', message = 'Someone is breaking into the bank.' })
    t.check('citizen report reaches the on-duty officer', report.ok and report.value.delivered == 1, t.code(report))
    t.check('the officer reads it in their language', (last(5) or {}).message == 'Sesizare cetățean: Someone is breaking into the bank.', (last(5) or {}).message)
    t.check('the reporter is told it arrived', (last(6) or {}).message == 'Your report reached 1 officer(s).', (last(6) or {}).message)
    local blip = t.clientEvents[#t.clientEvents]
    t.check('the officer client gets a blip at the reporter', blip.name == 'bcc-law:client:alert' and blip.source == 5
        and blip.payload.kind == 'citizen' and blip.payload.x == -270 and blip.payload.seconds == 120)
    t.check('citizen reports have a cooldown', t.rpc(6, 'law.alerts.citizen.v1', { department = 'new_hanover', message = 'Again.' }).code == 'rate_limited')
    t.check('control characters are refused', t.rpc(6, 'law.alerts.citizen.v1', { department = 'new_hanover', message = 'a\1b' }).code == 'invalid_input')
    local shots = t.rpc(6, 'law.alerts.shots.v1', {})
    t.check('shots fired in Valentine are reported', shots.ok and shots.value.delivered == 1, t.code(shots))
    t.check('shots alert in the officer language', (last(5) or {}).message == 'Focuri de armă lângă Valentine.', (last(5) or {}).message)
    t.check('each area has a cooldown', t.rpc(6, 'law.alerts.shots.v1', {}).value.delivered == 0)
    t.run(61000)
    t.check('on-duty officers do not report their own shots', t.rpc(5, 'law.alerts.shots.v1', {}).value.delivered == 0)
    t.place(6, 2000, 2000, 50)
    t.check('shots outside the configured areas are ignored', t.rpc(6, 'law.alerts.shots.v1', {}).value.delivered == 0)
    local areas = t.rpc(6, 'law.alerts.areas.v1', {})
    t.check('clients receive the shots-fired areas', areas.ok and #areas.value.areas == 1 and areas.value.areas[1].radius == 120)
    t.jobs[t.ion].police = false
    t.run(121000)
    report = t.rpc(6, 'law.alerts.citizen.v1', { department = 'new_hanover', message = 'Anyone there?' })
    t.check('with nobody on duty the report is not delivered', report.ok and report.value.delivered == 0)
    t.check('the reporter is told nobody is on duty', (last(6) or {}).message:find('No officer is on duty', 1, true) ~= nil)
    t.jobs[t.ion].police = true

    -- Penal-code editor (judges).
    local fraud = t.law(5, 'law.statutes.register.v1', { statuteName = 'fraud', title = 'Fraud', category = 'property', severityClass = 'felony',
        recommendedFine = { min = 5000, max = 20000 }, recommendedCustodySeconds = { min = 600, max = 1800 } }, true)
    t.check('judge registers a statute under the department key', fraud.ok and fraud.value.statuteKey == 'bcc-law:new_hanover.fraud', t.code(fraud))
    local revised = t.law(5, 'law.statutes.revise.v1', { statuteId = fraud.value.statuteId, expectedRevision = fraud.value.revision,
        title = 'Fraud and forgery', recommendedFine = { min = 5000, max = 25000 } }, true)
    t.check('judge revises it (new definition version)', revised.ok and revised.value.title == 'Fraud and forgery'
        and revised.value.definitionVersion == 2 and revised.value.metadata.recommendedFine.max == 25000, t.code(revised))
    t.check('a malformed statute name is refused', t.law(5, 'law.statutes.register.v1', { statuteName = 'Bad Name', title = 'X',
        category = 'x', severityClass = 'felony' }, true).code == 'invalid_input')
    t.check('an inverted range is refused', t.law(5, 'law.statutes.register.v1', { statuteName = 'inverted', title = 'X', category = 'x',
        severityClass = 'felony', recommendedFine = { min = 10, max = 5 } }, true).code == 'invalid_input')
    local retired = t.law(5, 'law.statutes.revise.v1', { statuteId = fraud.value.statuteId, expectedRevision = revised.value.revision, status = 'retired' }, true)
    t.check('judge retires a statute', retired.ok and retired.value.status == 'retired', t.code(retired))
    local active = t.law(5, 'law.statutes.list.v1', { status = 'active' }).value.items
    local listed = false
    for _, s in ipairs(active) do if s.statuteId == fraud.value.statuteId then listed = true end end
    t.check('retired statutes leave the active list', not listed)

    -- Citations: a warning and a fine (Contracts obligation).
    local case = t.law(5, 'law.cases.open.v1', { title = 'Disorder', summary = 'Fight outside the saloon.' }, true).value
    local function revision(id) return t.law(5, 'law.cases.get.v1', { caseId = id }).value.revision end
    local disorder
    for _, s in ipairs(active) do if s.statuteKey == 'bcc-law:new_hanover.disorderly_conduct' then disorder = s end end
    local warning = t.law(5, 'law.citations.issue.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId),
        subjectCharacterId = t.gigi, statuteId = disorder.statuteId, basisSummary = 'Verbal warning.' }, true)
    t.check('a citation without an amount is a warning', warning.ok and warning.value.status == 'issued' and warning.value.amount == nil, t.code(warning))
    local fine = t.law(5, 'law.citations.issue.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId),
        subjectCharacterId = t.gigi, statuteId = disorder.statuteId, basisSummary = 'Fined.', amount = 2500, dueInSeconds = 604800 }, true)
    t.check('a fine starts pending its payment obligation', fine.ok and fine.value.status == 'pending', t.code(fine))
    t.J.ProcessWorkflows()
    local citations = t.law(5, 'law.citations.list.v1', { caseId = case.caseId })
    local issued
    for _, c in ipairs(citations.ok and citations.value.items or {}) do if c.amount == 2500 then issued = c end end
    t.check('Justice issued the Contracts obligation', issued and issued.status == 'issued' and t.obligations[issued.contractsObligationId] ~= nil,
        issued and issued.status)

    -- Sealing (judges; closed or dismissed cases), view_sealed, unsealing and expunging.
    local private = t.law(5, 'law.cases.open.v1', { title = 'Private matter', summary = 'Sensitive narrative.' }, true).value
    local dismissed = t.law(5, 'law.cases.transition.v1', { caseId = private.caseId, expectedRevision = private.revision, status = 'dismissed' }, true)
    t.check('case dismissed', dismissed.ok and dismissed.value.status == 'dismissed', t.code(dismissed))
    local sealed = t.law(5, 'law.cases.seal.v1', { caseId = private.caseId, expectedRevision = dismissed.value.revision }, true)
    t.check('judge seals the dismissed case', sealed.ok and sealed.value.status == 'sealed', t.code(sealed))
    t.jobs[t.ion].judge = false
    t.check('a sealed case is hidden from officers', t.law(5, 'law.cases.get.v1', { caseId = private.caseId }).code ~= 'ok'
        and not t.law(5, 'law.cases.get.v1', { caseId = private.caseId }).ok)
    t.jobs[t.ion].judge = true
    local visible = t.law(5, 'law.cases.get.v1', { caseId = private.caseId })
    t.check('a judge with sealed-record access reads it', visible.ok and visible.value.status == 'sealed', t.code(visible))
    local unsealed = t.law(5, 'law.cases.unseal.v1', { caseId = private.caseId, expectedRevision = visible.value.revision }, true)
    t.check('unseal restores the previous status', unsealed.ok and unsealed.value.status == 'dismissed', t.code(unsealed))
    local resealed = t.law(5, 'law.cases.seal.v1', { caseId = private.caseId, expectedRevision = unsealed.value.revision }, true).value
    local expunged = t.law(5, 'law.cases.expunge.v1', { caseId = private.caseId, expectedRevision = resealed.revision }, true)
    t.check('judge expunges the sealed case', expunged.ok, t.code(expunged))
    local after = t.law(5, 'law.cases.get.v1', { caseId = private.caseId })
    t.check('the narrative is replaced permanently', after.ok and after.value.summary == '[expunged]', after.ok and after.value.summary)
    local open = t.law(5, 'law.cases.seal.v1', { caseId = case.caseId, expectedRevision = revision(case.caseId) }, true)
    t.check('an open case cannot be sealed', open.code == 'case_open', t.code(open))
end
