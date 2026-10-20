-- MDT ↔ client ↔ server contract: every operation the MDT sends is in the client
-- allowlist, and every allowlisted operation maps to a registered route.
return function(t)
    local client = io.open('client/main.lua'):read('a')
    local operations = {}
    for group, names in client:gmatch("Routes%('([%w]+)',(%b{})%)") do
        for name in names:gmatch("'([%w_]+)'") do operations[group .. '.' .. name] = 'law.' .. group .. '.' .. name .. '.v1' end
    end
    operations['debts.list'], operations['debts.settle'] = 'contracts.obligations.list.v1', 'contracts.obligation.settle.v1'
    for operation, route in pairs(operations) do
        if route:sub(1, 4) == 'law.' then t.check('client operation ' .. operation .. ' has a server route', t.rpcs[route] ~= nil, route) end
    end
    local used = {}
    local app = io.open('ui/app.js'):read('a')
    for operation in app:gmatch("api%('([%w%.]+)'") do used[operation] = true end
    -- Template literals: api(`warrants.${op}`) and similar.
    for _, op in ipairs({ 'warrants.issue', 'warrants.serve', 'warrants.recall', 'warrants.quash', 'restraints.apply', 'restraints.release',
        'restraints.escort', 'sentences.activate', 'sentences.suspend', 'sentences.complete', 'cases.seal', 'cases.unseal', 'cases.expunge' }) do
        used[op] = true
    end
    for operation in pairs(used) do t.check('MDT operation ' .. operation .. ' is allowlisted', operations[operation] ~= nil) end
    local registered = 0
    for name in pairs(t.rpcs) do
        if name:sub(1, 4) == 'law.' and name ~= 'law.session.get.v1' and not name:find('^law%.alerts%.') then
            local operation = name:match('^law%.(.+)%.v1$')
            t.check('route ' .. name .. ' reachable from the client', operations[operation] ~= nil
                or operation == 'restraints.self' or operation == 'execution.self' and operations['execution.self'] ~= nil)
            registered = registered + 1
        end
    end
    t.check('contract covers the registered routes', registered >= 58, registered)
end
