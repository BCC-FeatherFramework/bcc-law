-- Search and evidence: search warrant → read-only search → served; seizure warrant
-- → collection into the locker → Justice link (destroy guard) → dispositions:
-- destroyed (Inventory's public DestroyInstances), returned (stays in the locker
-- until staff hand it back), forfeited (stays).
return function(t)
    t.items[503] = { name = 'evidence_coin', owner = t.gigi, revision = 0 }
    local case = t.law(5, 'law.cases.open.v1', { title = 'Smuggling', summary = 'Contraband suspected.' }, true).value
    local function revision() return t.law(5, 'law.cases.get.v1', { caseId = case.caseId }).value.revision end
    local function warrant(kind)
        local draft = t.law(5, 'law.warrants.draft.v1', { caseId = case.caseId, expectedCaseRevision = revision(), subjectCharacterId = t.gigi,
            warrantType = kind, basisSummary = 'Informant statement.', validForSeconds = 7200 }, true).value
        return t.law(5, 'law.warrants.issue.v1', { caseId = case.caseId, warrantId = draft.warrantId, expectedRevision = draft.revision }, true), draft
    end
    t.jobs[t.ion].judge = false
    local denied = warrant('search')
    t.check('search warrants are issued only by a judge', denied.code == 'authorization_denied', t.code(denied))
    t.jobs[t.ion].judge = true
    local search = warrant('search').value
    local arrest = warrant('arrest').value
    local seizure = warrant('seizure').value
    t.check('judge issues search, arrest and seizure warrants', search and arrest and seizure and seizure.status == 'active')

    t.place(5, -273.05, 810.97, 119.37); t.place(6, -272.05, 810.97, 119.37)
    t.check('search needs a restrained subject', t.law(5, 'law.search.inspect.v1', { targetSource = 6, warrantId = search.warrantId }).code == 'restraint_required')
    t.law(5, 'law.restraints.apply.v1', { targetSource = 6, warrantId = arrest.warrantId })
    t.check('an arrest warrant is no search authority', t.law(5, 'law.search.inspect.v1', { targetSource = 6, warrantId = arrest.warrantId }).code == 'search_authority_required')
    local inspect = t.law(5, 'law.search.inspect.v1', { targetSource = 6, warrantId = search.warrantId })
    t.check('search shows the subject inventory read-only', inspect.ok and #inspect.value.items == 3 and inspect.value.warrantRevision == search.revision, t.code(inspect))
    local finish = t.law(5, 'law.search.finish.v1', { targetSource = 6, warrantId = search.warrantId, expectedRevision = inspect.value.warrantRevision }, true)
    t.check('finishing the search serves the warrant', finish.ok and finish.value.status == 'served', t.code(finish))

    local function collect(itemId, itemRevision)
        return t.law(5, 'law.evidence.collect.v1', { caseId = case.caseId, expectedCaseRevision = revision(), targetSource = 6,
            warrantId = seizure.warrantId, itemId = itemId, itemRevision = itemRevision, lockerKey = 'valentine', description = 'Seized item.' }, true)
    end
    t.place(5, -263.05, 810.97, 119.37); t.place(6, -262.05, 810.97, 119.37)
    t.check('collection needs the officer at the locker', collect(501, 3).code == 'proximity_required')
    t.place(5, -273.05, 810.97, 119.37); t.place(6, -272.05, 810.97, 119.37)
    local knife = collect(501, 3)
    t.check('item collected into the locker and linked', knife.ok and knife.value.link.status == 'active', t.code(knife))
    t.check('collected item moved to the locker', t.items[501].owner == 'locker:valentine')
    local letter = collect(502, 1)
    local coin = collect(503, 0)
    t.check('more items collected', letter.ok and coin.ok, t.code(letter) .. '/' .. t.code(coin))
    local guard = t.J.InstallEvidenceGuard and t.J.EvidenceGuardActive()
    t.check('Justice protects linked items from destruction', guard == true)

    local function link(itemId)
        for _, item in ipairs(t.law(5, 'law.evidence.list.v1', { caseId = case.caseId }).value.items) do
            if item.evidenceId == tostring(itemId) then return item end
        end
    end

    local function dispose(itemId, disposition, judge)
        t.jobs[t.ion].judge = judge ~= false
        local item = link(itemId)
        local result = t.law(5, 'law.evidence.remove.v1', { caseId = case.caseId, evidenceLinkId = item.evidenceLinkId,
            expectedRevision = item.revision, disposition = disposition }, true)
        t.jobs[t.ion].judge = true
        return result
    end
    t.check('a disposition needs a judge', dispose(501, 'returned', false).code == 'authorization_denied')
    local returned = dispose(501, 'returned')
    t.check('returned disposition recorded in Justice', returned.ok and returned.value.disposition == 'returned' and returned.value.status == 'removed', t.code(returned))
    t.run(16000)
    t.check('a returned item stays in the locker until staff hand it back', t.items[501].owner == 'locker:valentine')
    t.check('no automatic step is queued for a return', t.Law.Store.Disposition(link(501).evidenceLinkId) == nil)
    t.check('the MDT shows the return as a staff step', link(501).physicalState == 'manual', link(501).physicalState)
    local destroyed = dispose(502, 'destroyed')
    t.check('destroyed disposition recorded', destroyed.ok, t.code(destroyed))
    t.run(100)
    t.check('the destroyed item no longer exists (Inventory public DestroyInstances)', t.items[502] == nil)
    t.check('the destroy step is shown as done', link(502).physicalState == 'done', link(502).physicalState)
    local forfeited = dispose(503, 'forfeited')
    t.check('forfeited disposition recorded', forfeited.ok, t.code(forfeited))
    t.run(16000)
    t.check('a forfeited item stays in the locker', t.items[503] and t.items[503].owner == 'locker:valentine')
    t.check('no physical step is queued for a forfeiture', t.Law.Store.Disposition(link(503).evidenceLinkId) == nil)
    local rows = t.sql.value("SELECT COUNT(*) FROM bcc_law_evidence_dispositions WHERE state='done'")
    t.check('one destroy step completed exactly once', tonumber(rows) == 1, rows)
    local status = t.command('LawEvidenceStatus')
    t.check('evidence status reports no pending or failed steps', status[1]:find('dispositionsPending=0 dispositionsFailed=0', 1, true), status[1])

    -- An item that already left the locker is never destroyed: staff attention, then requeue.
    t.items[504] = { name = 'evidence_watch', owner = t.gigi, revision = 2 }
    t.check('another item collected', collect(504, 2).ok)
    t.items[504].owner = t.gigi
    t.check('destroyed disposition for the watch recorded', dispose(504, 'destroyed').ok)
    t.run(100)
    local stuck = t.Law.Store.Disposition(link(504).evidenceLinkId)
    t.check('an item outside the lockers fails the destroy step', stuck.state == 'failed' and stuck.last_code == 'denied' and t.items[504] ~= nil,
        stuck.state .. '/' .. tostring(stuck.last_code))
    t.items[504].owner = 'locker:valentine'
    local retry = t.command('LawEvidenceRetry', { link(504).evidenceLinkId })
    t.check('staff can queue a failed step again', retry[1]:find('requeued=true', 1, true), retry[1])
    t.run(100)
    t.check('the requeued destroy completes once the item is back in the locker', t.items[504] == nil
        and t.Law.Store.Disposition(link(504).evidenceLinkId).state == 'done')
    local unknown = t.uuid(777000)
    t.Law.Store.DispositionQueue(unknown, case.caseId, 99999, 'destroyed', nil)
    t.run(16000)
    t.check('an item that is already gone counts as destroyed', t.Law.Store.Disposition(unknown).state == 'done'
        and t.Law.Store.Disposition(unknown).last_code == 'already_absent')
    t.sql.exec('DELETE FROM bcc_law_evidence_dispositions WHERE evidence_link_id=?', unknown)

    local receipts = t.law(5, 'law.evidence.receipts.v1', { caseId = case.caseId })
    t.check('own collection receipts listed', receipts.ok and #receipts.value.items == 4, t.code(receipts))
    t.law(5, 'law.restraints.release.v1', { targetSource = 6 })
end
