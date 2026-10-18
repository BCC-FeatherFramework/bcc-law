local health = { state = 'starting', phase = 'foundation', contract = 1 }
Law.Epoch = 0
function Law.SetState(state, phase)
    Law.Epoch = Law.Epoch + 1
    health.state, health.phase = state, phase
end
function Law.Ready() return health.state == 'ready' end
function Law.Call(resource, operation, ...)
    if GetResourceState(resource) ~= 'started' then return Law.Err('dependency_unavailable', 'Service unavailable.') end
    local provider, args = exports[resource], table.pack(...)
    local ok, result = pcall(function() return provider[operation](provider, table.unpack(args, 1, args.n)) end)
    if not ok or type(result) ~= 'table' or type(result.ok) ~= 'boolean' then
        return Law.Err('dependency_unavailable', 'Service returned no valid result.')
    end
    return result
end
function Law.Health() return Law.Ok(Law.Copy(health)) end
function Law.Capabilities()
    return Law.Ok({ resource = 'bcc-law', contract = 1, version = '2.0.0-alpha.5', state = health.state,
        features = { lifecycle = 1, sessions = 1, caseRoutes = Law.Ready() and 1 or 0,
            mdtNui = 1, partyRoutes = Law.Ready() and 1 or 0, custodyRoutes = Law.Ready() and 1 or 0, restraints = 0, jail = 0, communityService = 0,
            chargeRoutes = Law.Ready() and 1 or 0, warrantRoutes = Law.Ready() and 1 or 0,
            citationRoutes = Law.Ready() and 1 or 0, finePayments = 1, fines = 1, warrants = 0, evidence = 0, armory = 0, payroll = 0 } })
end
function Law.ValidateConfig()
    if type(LawConfig.Departments) ~= 'table' or type(LawConfig.MaxDepartments) ~= 'number'
        or LawConfig.MaxDepartments % 1 ~= 0 or LawConfig.MaxDepartments < 1 or LawConfig.MaxDepartments > 32 then return false end
    local count = 0
    for key, value in pairs(LawConfig.Departments) do
        count = count + 1
        if not Law.Token(key, 48) or type(value) ~= 'table' or not Law.Text(value.label, 100)
            or not Law.Fields(value, { label=true, jobKey=true, minGradeOrdinal=true, licenseKey=true, jurisdictionKey=true, employerId=true })
            or type(value.jobKey) ~= 'string' or #value.jobKey > 48 or not value.jobKey:match('^[a-z][a-z0-9_]*$')
            or type(value.licenseKey) ~= 'string' or #value.licenseKey > 48 or not value.licenseKey:match('^[a-z][a-z0-9_]*$')
            or not Law.Token(value.jurisdictionKey, 128) or value.jurisdictionKey:sub(1,8) ~= 'bcc-law:'
            or (value.employerId ~= nil and not Law.Uuid(value.employerId))
            or type(value.minGradeOrdinal) ~= 'number' or value.minGradeOrdinal % 1 ~= 0
            or value.minGradeOrdinal < 0 or value.minGradeOrdinal > 1000 then return false end
    end
    return count <= LawConfig.MaxDepartments and Law.ValidateCustodyConfig()
end
exports('GetHealth', Law.Health)
exports('GetCapabilities', Law.Capabilities)
exports('AwaitReady', function(timeoutMs)
    timeoutMs = timeoutMs == nil and 30000 or timeoutMs
    if type(timeoutMs) ~= 'number' or timeoutMs % 1 ~= 0 or timeoutMs < 0 or timeoutMs > 60000 then
        return Law.Err('invalid_input', 'Invalid readiness timeout.')
    end
    local started = GetGameTimer()
    repeat
        if Law.Ready() then return Law.Health() end
        if GetGameTimer() - started >= timeoutMs then return Law.Err('not_ready', 'Law is not ready.') end
        Wait(50)
    until false
end)
