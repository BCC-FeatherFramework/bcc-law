-- Court and execution: charge → verdict → custodial sentence → jail placement →
-- the term keeps running offline → release; community service units → Justice.
return function(t)
    t.LawConfig.Doors.Facilities.valentine = { 12, 13 }
    local statutes = t.law(5, 'law.statutes.list.v1', { status = 'active' }).value.items
    local theft
    for _, s in ipairs(statutes) do if s.statuteKey == 'bcc-law:new_hanover.theft.petty' then theft = s end end
    local function revision(caseId) return t.law(5, 'law.cases.get.v1', { caseId = caseId }).value.revision end
    -- A case with Ion as judge and Gigi as defendant, one filed charge and a guilty verdict.
    local function convicted(title)
        local case = t.law(5, 'law.cases.open.v1', { title = title, summary = 'Court case.' }, true).value
        for _, party in ipairs({ { t.ion, 'judge' }, { t.gigi, 'defendant' } }) do
            t.law(5, 'law.parties.add.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId), partyType = 'character',
                partyIdReference = party[1], partyRole = party[2] }, true)
        end
        local charge = t.law(5, 'law.charges.propose.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId),
            defendantCharacterId = t.gigi, statuteId = theft.statuteId, count = 1 }, true).value
        local filed = t.law(5, 'law.charges.file.v1', { caseId = case.caseId, chargeId = charge.chargeId, expectedRevision = charge.revision }, true).value
        -- Verdicts need the case itself filed (or pending a hearing).
        t.law(5, 'law.cases.transition.v1', { caseId = case.caseId, expectedRevision = revision(case.caseId), status = 'filed' }, true)
        local verdict = t.law(5, 'law.rulings.record.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId),
            subjectCharacterId = t.gigi, rulingType = 'verdict', summary = 'Guilty as charged.',
            findings = { { chargeId = filed.chargeId, finding = 'convicted' } } }, true)
        return case, charge, filed, verdict
    end
    local case, charge, filed, verdict = convicted('Theft trial')
    t.check('charge keeps the statute snapshot', charge.statuteSnapshot.title == 'Petty theft')
    t.check('charge filed', filed.status == 'filed')
    t.check('guilty verdict recorded', verdict.ok and verdict.value.rulingType == 'verdict', t.code(verdict))
    t.check('verdict adjudicates the case', t.law(5, 'law.cases.get.v1', { caseId = case.caseId }).value.status == 'adjudicated')
    local rulings = t.law(5, 'law.rulings.list.v1', { caseId = case.caseId })
    t.check('rulings listed', rulings.ok and #rulings.value.items == 1, t.code(rulings))
    t.jobs[t.ion].judge = false
    local officerRuling = t.law(5, 'law.rulings.record.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId),
        rulingType = 'order', outcome = 'bail_set', summary = 'Bail.' }, true)
    t.check('rulings need the judicial profile', officerRuling.code == 'duty_required', t.code(officerRuling))
    t.jobs[t.ion].judge = true

    -- Custodial sentence and jail placement.
    local created = t.law(5, 'law.sentences.create.v1', { caseId = case.caseId, expectedCaseRevision = revision(case.caseId),
        rulingId = verdict.value.rulingId, sentenceType = 'custodial', terms = { termSeconds = 600, facilityKey = 'valentine' } }, true)
    t.check('custodial sentence created', created.ok and created.value.status == 'pending', t.code(created))
    local sentence = t.law(5, 'law.sentences.activate.v1', { caseId = case.caseId, sentenceId = created.value.sentenceId,
        expectedRevision = created.value.revision }, true)
    t.check('custodial sentence active', sentence.ok and sentence.value.status == 'active', t.code(sentence))
    t.doors[12].locked, t.doors[13].locked = false, false
    t.place(6, 100, 100, 100)
    t.run(2500)
    local g = t.world[6]
    t.check('subject placed at the jail entrance', math.abs(g.x + 273.05) < 0.01 and math.abs(g.y - 810.97) < 0.01, g.x .. ',' .. g.y)
    t.check('placement locked the cell doors', t.doors[12].locked and t.doors[13].locked)
    t.check('placement marker stored', t.Law.Store.Get(t.gigi) ~= nil)
    local mine = t.rpc(6, 'law.execution.self.v1', {})
    t.check('subject sees the remaining term', mine.ok and mine.value.confined == true and mine.value.remainingMs > 590000, t.code(mine))
    t.place(6, -200, 810, 119)
    t.run(2100)
    t.check('leaving the cell is undone', math.abs(t.world[6].x + 273.05) < 0.01)

    -- Offline: the UTC deadline keeps running; Justice completes the term.
    local saved = t.sessions[6]
    t.sessions[6] = nil
    t.ago('justice_sentences', 'ends_at', 'sentence_id', created.value.sentenceId, 1000)
    t.check('Justice completes the term at its deadline while the subject is offline', t.J.SweepSentences() == 1)
    t.sessions[6] = saved
    t.run(2100)
    t.check('on return the released subject leaves the cell', math.abs(t.world[6].x + 276.76) < 0.01, t.world[6].x)
    t.run(2100)
    t.check('placement marker cleared', t.Law.Store.Get(t.gigi) == nil)
    local done = t.service('GetSentence', { sentenceId = created.value.sentenceId })
    t.check('sentence completed as served', done.ok and done.value.status == 'completed' and done.value.outcome == 'served', t.code(done))

    -- Community service: two units on site; the last one completes the sentence in Justice.
    local case2, _, _, verdict2 = convicted('Vandalism trial')
    local service = t.law(5, 'law.sentences.create.v1', { caseId = case2.caseId, expectedCaseRevision = revision(case2.caseId),
        rulingId = verdict2.value.rulingId, sentenceType = 'community_service', terms = { units = 2, taskKey = 'valentine_maintenance' } }, true)
    t.check('community service sentence created', service.ok, t.code(service))
    t.law(5, 'law.sentences.activate.v1', { caseId = case2.caseId, sentenceId = service.value.sentenceId, expectedRevision = service.value.revision }, true)
    t.place(6, 0, 0, 0)
    t.check('a unit cannot start away from the work site', t.rpc(6, 'law.service.start.v1', { sentenceId = service.value.sentenceId }).code == 'proximity_required')
    t.place(6, -280.0, 810.0, 119.37)
    local start = t.rpc(6, 'law.service.start.v1', { sentenceId = service.value.sentenceId })
    t.check('first unit starts at the work site', start.ok and start.value.seconds == 30, t.code(start))
    t.run(10000)
    t.place(6, -270.0, 810.0, 119.37)
    t.run(3000)
    t.place(6, -280.0, 810.0, 119.37)
    t.run(30000)
    t.check('leaving the site interrupts the unit', (t.Law.Store.ServiceProgress(service.value.sentenceId) or { completed_units = 0 }).completed_units == 0)
    start = t.rpc(6, 'law.service.start.v1', { sentenceId = service.value.sentenceId })
    t.run(32000)
    local progress = t.Law.Store.ServiceProgress(service.value.sentenceId)
    t.check('one unit counted after 30 seconds on site', progress and progress.completed_units == 1, progress and progress.completed_units)
    start = t.rpc(6, 'law.service.start.v1', { sentenceId = service.value.sentenceId })
    t.check('second unit starts', start.ok, t.code(start))
    t.run(36000)
    local completed = t.service('GetSentence', { sentenceId = service.value.sentenceId })
    t.check('the last unit completes the sentence in Justice', completed.ok and completed.value.status == 'completed'
        and completed.value.outcome == 'served', completed.ok and completed.value.status or t.code(completed))
    t.check('progress row marked completed', t.Law.Store.ServiceProgress(service.value.sentenceId).state == 'completed')
    t.check('a finished sentence offers no more units', t.rpc(6, 'law.service.start.v1', { sentenceId = service.value.sentenceId }).code == 'not_found')

    -- Suspend/resume and judge-only outcomes.
    local case3, _, _, verdict3 = convicted('Probation hearing')
    local probation = t.law(5, 'law.sentences.create.v1', { caseId = case3.caseId, expectedCaseRevision = revision(case3.caseId),
        rulingId = verdict3.value.rulingId, sentenceType = 'probation', terms = { termSeconds = 86400, conditionsSummary = 'Report weekly.' } }, true).value
    local p1 = t.law(5, 'law.sentences.activate.v1', { caseId = case3.caseId, sentenceId = probation.sentenceId, expectedRevision = probation.revision }, true).value
    local p2 = t.law(5, 'law.sentences.suspend.v1', { caseId = case3.caseId, sentenceId = probation.sentenceId, expectedRevision = p1.revision }, true)
    t.check('judge suspends a sentence', p2.ok and p2.value.status == 'suspended', t.code(p2))
    local p3 = t.law(5, 'law.sentences.activate.v1', { caseId = case3.caseId, sentenceId = probation.sentenceId, expectedRevision = p2.value.revision }, true)
    t.check('activate resumes a suspended sentence', p3.ok and p3.value.status == 'active', t.code(p3))
    local p4 = t.law(5, 'law.sentences.complete.v1', { caseId = case3.caseId, sentenceId = probation.sentenceId,
        expectedRevision = p3.value.revision, outcome = 'commuted' }, true)
    t.check('judge commutes a sentence', p4.ok and p4.value.status == 'completed' and p4.value.outcome == 'commuted', t.code(p4))
    local list = t.law(5, 'law.sentences.list.v1', { caseId = case3.caseId })
    t.check('sentences listed from the case file', list.ok and #list.value.items == 1, t.code(list))
    t.LawConfig.Doors.Facilities.valentine = nil
end
