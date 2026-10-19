local registered = {}
local dependencies = { 'feather-core', 'feather-character', 'feather-jobs', 'feather-licenses', 'feather-justice' }
local function Poll()
    local epoch = Law.Epoch
    if not Law.ValidateConfig() then
        if Law.Health().value.phase ~= 'invalid_config' then Law.SetState('failed', 'invalid_config') end
        return
    end
    for _, resource in ipairs(dependencies) do
        local health = Law.Call(resource, 'GetHealth')
        if epoch ~= Law.Epoch then return end
        if not health.ok or type(health.value) ~= 'table' or health.value.state ~= 'ready' then
            local phase = 'waiting_for_' .. resource
            if Law.Health().value.phase ~= phase then Law.SetState('degraded', phase) end
            return
        end
    end
    local core = Law.Call('feather-core', 'GetCapabilities')
    local justice = Law.Call('feather-justice', 'GetCapabilities')
    if epoch ~= Law.Epoch then return end
    if not core.ok or type(core.value) ~= 'table' or core.value.contract ~= 1
        or not justice.ok or type(justice.value) ~= 'table' or justice.value.contract ~= 1
        or type(justice.value.features) ~= 'table' or justice.value.features.cases ~= 1
        or justice.value.features.parties ~= 1 or justice.value.features.caseAccess ~= 1
        or justice.value.features.custodyBooking ~= 1 or justice.value.features.citations ~= 1
        or justice.value.features.charges ~= 1 or justice.value.features.warrants ~= 1
        or justice.value.features.rulings~=1 or justice.value.features.sentences~=1
        or justice.value.features.subjectStatus~=1 or justice.value.features.sentenceProgress~=1 then
        if Law.Health().value.phase ~= 'contract_unavailable' then Law.SetState('degraded', 'contract_unavailable') end
        return
    end
    for name, spec in pairs(Law.Routes) do
        if not registered[name] then
            local result = Law.RegisterRoute(name, spec)
            if epoch ~= Law.Epoch then return end
            if not result.ok then
                if Law.Health().value.phase ~= 'route_unavailable' then Law.SetState('degraded', 'route_unavailable') end
                return
            end
            registered[name] = true
        end
    end
    if not Law.Ready() then Law.SetState('ready', 'case_integration_ready') end
end
AddEventHandler('onResourceStop', function(resource)
    if resource == 'feather-core' then registered = {} end
    for _, required in ipairs(dependencies) do
        if resource == required then Law.SetState('degraded', 'dependency_stopped'); return end
    end
end)
CreateThread(function()
    while true do
        local ok = pcall(Poll)
        if not ok and Law.Health().value.phase ~= 'dependency_error' then Law.SetState('degraded', 'dependency_error') end
        Wait(2000)
    end
end)
RegisterCommand('LawReleaseContractSmokeTest', function(source)
    if source ~= 0 then return end
    local count = 0; for _ in pairs(registered) do count = count + 1 end
    local expected=0;for _ in pairs(Law.Routes) do expected=expected+1 end
    print(('[LawReleaseContractSmokeTest] ready=%s routes=%d/%d config=%s'):format(
        tostring(Law.Ready()), count, expected, tostring(Law.ValidateConfig())))
end, true)
