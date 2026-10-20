-- Explicit console setup in service mode (feather-admin service policy for bcc-law).
return function(t)
    local lines = t.command('LawSetupJurisdictions')
    t.check('jurisdiction registered without a player', lines[1] and lines[1]:find('department=new_hanover result=%x+%-') ~= nil, lines[1])
    lines = t.command('LawSetupJurisdictions')
    t.check('rerun reports the existing jurisdiction', lines[1] and lines[1]:find('already_registered', 1, true), lines[1])
    lines = t.command('LawSetupStatutes')
    t.check('starter penal code registered', lines[#lines]:find('registered=12 alreadyPresent=0 failed=0', 1, true), lines[#lines])
    lines = t.command('LawSetupStatutes')
    t.check('penal code seed is idempotent', lines[#lines]:find('registered=0 alreadyPresent=12 failed=0', 1, true), lines[#lines])
    local list = t.law(5, 'law.statutes.list.v1', { status = 'active' })
    t.check('officer reads the penal code', list.ok and #list.value.items == 12, t.code(list))
    local theft
    for _, s in ipairs(list.ok and list.value.items or {}) do if s.statuteKey == 'bcc-law:new_hanover.theft.petty' then theft = s end end
    t.check('statute keeps its advisory ranges', theft and theft.metadata.recommendedFine.min == 2500
        and theft.metadata.recommendedCustodySeconds.max == 900)
    local evidence = t.command('LawSetupEvidenceLockers')
    t.check('evidence locker setup goes through Inventory', evidence[1] and evidence[1]:find('locker=valentine result=confirmed', 1, true), evidence[1])
    local cases = t.law(5, 'law.cases.list.v1', {})
    t.check('department resolves its Justice jurisdiction', cases.ok, t.code(cases))
end
