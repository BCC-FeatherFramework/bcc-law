-- Lifecycle, store migrations, release smoke test, session route and locales.
return function(t)
    local Law = t.Law
    t.check('Law ready on the real Justice contract', Law.Ready(), Law.Health().value.phase)
    local expected, registered = 0, 0
    for _ in pairs(Law.Routes) do expected = expected + 1 end
    for name in pairs(t.rpcs) do if name:sub(1, 4) == 'law.' then registered = registered + 1 end end
    t.check('every Law route registered with Core', registered == expected and expected == 63, registered .. '/' .. expected)
    for name, spec in pairs(t.rpcs) do
        if name:sub(1, 4) == 'law.' then
            t.check(name .. ' requires a character and bounds its payload', spec.options.requireCharacter == true
                and spec.options.maxPayloadBytes <= 8192 and spec.options.maxCalls >= 1)
        end
    end
    local caps = Law.Capabilities().value
    t.check('capabilities: beta.1, doors and alerts, payroll owned elsewhere', caps.version == '2.0.0-beta.1'
        and caps.features.alerts == 1 and caps.features.payroll == 0 and caps.features.statuteEditor == 1)
    t.check('Justice capability document accepted', Law.JusticeContract() ~= nil)

    local rows, sums = Law.Store.Migrations()
    t.check('three Law migrations applied', #rows == 3, #rows)
    t.check('v1 checksum equals the one recorded on the live server',
        sums[1] == '6bb581bd8a1e636e650d974da1c97bbb2112633d3fb9f7d5055d91933fddf033', sums[1])
    for _, row in ipairs(rows) do
        t.check('migration v' .. row.version .. ' checksum recorded', row.checksum == sums[tonumber(row.version)])
    end
    t.check('empty pre-beta delivery table dropped', tonumber(t.sql.value([[SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bcc_law_service_deliveries']])) == 0)
    Law.Store.Start()
    t.check('store start is rerunnable', Law.Store.state == 'ready')

    local smoke = t.command('LawReleaseContractSmokeTest')
    t.check('release smoke test reports routes, Justice release and store', smoke[1] and smoke[1]:find('routes=63/63', 1, true)
        and smoke[1]:find('justice=0.3.0', 1, true) and smoke[1]:find('store=ready', 1, true), smoke[1])

    local session = t.rpc(5, 'law.session.get.v1', {})
    t.check('session returns the account language', session.ok and session.value.locale == 'ro', t.code(session))
    t.check('session lists jail facilities and work tasks', session.ok and #session.value.jailFacilities == 2
        and session.value.serviceTasks[1].key == 'valentine_maintenance')
    t.check('unknown payload fields are refused', t.rpc(5, 'law.session.get.v1', { extra = true }).code == 'invalid_input')
    t.check('no session without a character context', t.rpc(7, 'law.session.get.v1', {}).code == 'session_expired')

    local en, ro = 0, 0
    for _ in pairs(LawLocalesForTests.en) do en = en + 1 end
    for key in pairs(LawLocalesForTests.ro) do ro = ro + 1; t.check('ro key exists in en: ' .. key, LawLocalesForTests.en[key] ~= nil) end
    t.check('English and Romanian have the same keys', en == ro and en > 400, en .. '/' .. ro)
    t.check('translation keeps placeholders', Law.T('ro', 'alert.shots', { area = 'Valentine' }) == 'Focuri de armă lângă Valentine.')
    t.check('unknown language falls back to the default', Law.T('de', 'nav.cases') == 'Cases')
end
