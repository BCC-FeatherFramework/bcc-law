-- The console acceptance command, run exactly as staff would: two character UUIDs,
-- nobody online for the identity checks (the subject is offline here).
return function(t)
    local saved = t.sessions[6]
    t.sessions[6] = nil
    local lines = t.command('LawAcceptanceTest', { t.ion, t.gigi })
    t.sessions[6] = saved
    local result = lines[#lines] or ''
    for _, line in ipairs(lines) do if os.getenv('LAW_TEST_VERBOSE') or line:find(' FAIL', 1, true) then print('  ' .. line) end end
    t.check('LawAcceptanceTest passes with the two offline characters', result:find(', 0 failed', 1, true) ~= nil, result)
    t.check('it ran the Law table checks', result:find('passed', 1, true) and tonumber(result:match('(%d+) passed')) >= 15, result)
    local leftovers = tonumber(t.sql.value("SELECT COUNT(*) FROM bcc_law_operations WHERE route='law.test.v1'"))
    t.check('acceptance cleans up its development rows', leftovers == 0, leftovers)
    t.check('usage shown for a malformed UUID', t.command('LawAcceptanceTest', { 'not-a-uuid' })[1]:find('usage', 1, true) ~= nil)
    -- With the officer online the placement marker is never touched.
    t.Law.Store.Place(t.ion, t.uuid(4040), 'valentine')
    lines = t.command('LawAcceptanceTest', { t.ion })
    local marker = t.Law.Store.Get(t.ion)
    t.check('an online officer keeps their real placement marker', marker and marker.sentence_id == t.uuid(4040))
    local skipped = false
    for _, line in ipairs(lines) do if line:find('jail placement marker', 1, true) and line:find('SKIP', 1, true) then skipped = true end end
    t.check('the marker check is skipped while the officer is online', skipped)
    t.Law.Store.Clear(t.ion)
end
