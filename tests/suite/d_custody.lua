-- Field interactions and custody: warrant → restraint → arrest (Justice records the
-- authority) → booking at the facility (doors lock) → release (restraint ends).
return function(t)
    t.LawConfig.Doors.Facilities.valentine = { 12, 13 }
    local case = t.law(5, 'law.cases.open.v1', { title = 'Store theft', summary = 'Goods taken from the general store.' }, true).value
    local function revision() return t.law(5, 'law.cases.get.v1', { caseId = case.caseId }).value.revision end
    local suspect = t.law(5, 'law.parties.add.v1', { caseId = case.caseId, expectedCaseRevision = revision(), partyType = 'character',
        partyIdReference = t.gigi, partyRole = 'suspect' }, true)
    t.check('suspect added to the case', suspect.ok and suspect.value.partyRole == 'suspect', t.code(suspect))
    local draft = t.law(5, 'law.warrants.draft.v1', { caseId = case.caseId, expectedCaseRevision = revision(), subjectCharacterId = t.gigi,
        warrantType = 'arrest', basisSummary = 'Seen leaving with the goods.', validForSeconds = 3600 }, true)
    t.check('arrest warrant drafted', draft.ok and draft.value.status == 'draft', t.code(draft))
    local warrant = t.law(5, 'law.warrants.issue.v1', { caseId = case.caseId, warrantId = draft.value.warrantId,
        expectedRevision = draft.value.revision }, true).value
    t.check('arrest warrant issued', warrant and warrant.status == 'active')
    local active = t.law(5, 'law.warrants.active.v1', { subjectCharacterId = t.gigi })
    t.check('active warrants searchable by subject', active.ok and #active.value.items == 1, t.code(active))

    -- Restraint: legal authority plus physical presence.
    t.place(5, -273.05, 810.97, 119.37); t.place(6, -263.0, 810.97, 119.37)
    local far = t.law(5, 'law.restraints.apply.v1', { targetSource = 6, warrantId = warrant.warrantId })
    t.check('restraint needs the subject nearby', far.code == 'proximity_required', t.code(far))
    t.place(6, -272.05, 810.97, 119.37)
    t.world[6].bucket = 7
    t.check('restraint needs the same instance', t.law(5, 'law.restraints.apply.v1', { targetSource = 6, warrantId = warrant.warrantId }).code == 'proximity_required')
    t.world[6].bucket = 0
    local wrong = t.law(5, 'law.restraints.apply.v1', { targetSource = 6, warrantId = t.uuid(4242) })
    t.check('an unknown warrant gives no authority', not wrong.ok, t.code(wrong))
    local arrestEarly = t.law(5, 'law.custody.arrest.v1', { caseId = case.caseId, targetSource = 6, authorityType = 'warrant',
        authorityId = warrant.warrantId, expectedAuthorityRevision = warrant.revision }, true)
    t.check('arrest needs a restrained subject', arrestEarly.code == 'restraint_required', t.code(arrestEarly))
    local cuffed = t.law(5, 'law.restraints.apply.v1', { targetSource = 6, warrantId = warrant.warrantId })
    t.check('subject restrained under the arrest warrant', cuffed.ok and cuffed.value.restrained == true, t.code(cuffed))
    t.check('subject client sees the restraint', t.rpc(6, 'law.restraints.self.v1', {}).value.restrained == true)
    local escort = t.law(5, 'law.restraints.escort.v1', { targetSource = 6, enabled = true })
    t.check('restraining officer escorts', escort.ok and escort.value.escortSource == 5, t.code(escort))

    -- Arrest: Justice records custody and serves the warrant in one transaction.
    local arrest = t.law(5, 'law.custody.arrest.v1', { caseId = case.caseId, targetSource = 6, authorityType = 'warrant',
        authorityId = warrant.warrantId, expectedAuthorityRevision = warrant.revision }, true)
    t.check('arrest recorded in Justice', arrest.ok and arrest.value.status == 'arrested', t.code(arrest))
    local related = t.law(5, 'law.cases.get.v1', { caseId = case.caseId }).value.related
    t.check('the arrest served the warrant', related.warrant.items[1].status == 'served')
    t.run(4500)
    t.check('restraint continues on the custody record after the warrant was served',
        t.rpc(6, 'law.restraints.self.v1', {}).value.restrained == true)
    local custodyList = t.law(5, 'law.custody.list.v1', { caseId = case.caseId })
    t.check('custody listed for the case', custodyList.ok and #custodyList.value.items == 1, t.code(custodyList))

    -- Booking: officer and subject together at the facility.
    local custody = arrest.value
    local function book(requestId)
        return t.law(5, 'law.custody.book.v1', { caseId = case.caseId, custodyId = custody.custodyId,
            expectedRevision = custody.revision, facilityKey = 'valentine', requestId = requestId }, true)
    end
    t.place(5, -243.0, 810.97, 119.37); t.place(6, -242.0, 810.97, 119.37)
    t.check('booking needs both at the facility', book().code == 'booking_location_required')
    t.place(5, -273.05, 810.97, 119.37); t.place(6, -272.05, 810.97, 119.37)
    local booked = book('book-1')
    t.check('custody booked', booked.ok and booked.value.status == 'booked', t.code(booked))
    t.check('booking locked the cell doors', t.doors[12].locked and t.doors[13].locked)
    t.place(6, -200, 810, 119)
    local replay = book('book-1')
    t.check('an exact retry replays without re-checking presence', replay.ok and replay.value.replayed == true, t.code(replay))

    local release = t.law(5, 'law.custody.release.v1', { caseId = case.caseId, custodyId = custody.custodyId,
        expectedRevision = booked.value.revision, releaseReason = 'bail' }, true)
    t.check('custody released', release.ok and release.value.status == 'released', t.code(release))
    t.run(4500)
    t.check('released custody ends the restraint', t.rpc(6, 'law.restraints.self.v1', {}).value.restrained == false)
    local status = t.service('GetCustodyStatus', { subjectCharacterId = t.gigi })
    t.check('Justice shows no unreleased custody', status.ok and status.value.custody == nil, t.code(status))
    t.LawConfig.Doors.Facilities.valentine = nil
end
