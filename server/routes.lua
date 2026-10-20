Law.Routes = {}
local function DepartmentPayload(payload)
    return Law.Fields(payload, { department = true, cursor = true, status = true }) and Law.Token(payload.department, 48)
        and (payload.cursor == nil or Law.Uuid(payload.cursor)) and (payload.status == nil or Law.Token(payload.status, 24))
end
Law.Routes['law.session.get.v1'] = {
    validate = function(payload) return Law.Fields(payload, {}) end,
    handler = function(_, source, context)
        local actor = Law.Actor(source, context)
        if not actor.ok then return actor end
        local departments = {}
        for key, department in pairs(LawConfig.Departments) do
            departments[#departments + 1] = { key = key, label = department.label }
        end
        table.sort(departments, function(a, b) return a.key < b.key end)
        -- Choices for sentence forms: jail facilities and community-service tasks.
        local facilities, tasks = {}, {}
        for key in pairs(LawConfig.Execution.Facilities) do facilities[#facilities + 1] = key end
        table.sort(facilities)
        for key, task in pairs(LawConfig.Execution.Tasks) do tasks[#tasks + 1] = { key = key, label = task.label } end
        table.sort(tasks, function(a, b) return a.key < b.key end)
        return Law.Ok({ departments = departments, caseTypes = Law.Copy(LawConfig.CaseTypes), locale = Law.SourceLocale(source),
            jailFacilities = facilities, serviceTasks = tasks })
    end
}
Law.Routes['law.cases.list.v1'] = {
    validate = DepartmentPayload,
    handler = function(payload, source, context)
        local actor = Law.Access(source, context, payload.department, 'justice.case.view')
        if not actor.ok then return actor end
        return Law.Dispatch(actor.value, 'ListCases', { actorSource = source, jurisdictionId = actor.value.jurisdictionId,
            status = payload.status, cursor = payload.cursor, limit = 25 })
    end
}
Law.Routes['law.cases.open.v1'] = { mutation = true,
    validate = function(payload)
        return Law.Fields(payload, { department=true, requestId=true, caseType=true, title=true, summary=true, draft=true })
            and Law.Token(payload.department, 48) and Law.Token(payload.requestId, 64)
            and (payload.caseType == nil or Law.Token(payload.caseType, 32)) and (payload.draft == nil or type(payload.draft) == 'boolean')
            and Law.Text(payload.title, 180) and Law.Text(payload.summary, 4000)
    end,
    handler = function(payload, source, context)
        local actor = Law.Access(source, context, payload.department, 'justice.case.open')
        if not actor.ok then return actor end
        return Law.Dispatch(actor.value, 'OpenCase', { actorSource = source, jurisdictionId = actor.value.jurisdictionId,
            requestId = actor.value.characterId .. ':' .. payload.requestId, reasonCode = 'law.case.open',
            caseType = payload.caseType or LawConfig.DefaultCaseType, title = payload.title, summary = payload.summary,
            status = payload.draft and 'draft' or nil })
    end
}

-- One Justice call with session fences before and after (a provider call may yield).
function Law.Dispatch(actor, operation, request)
    if not Law.Current(actor) then return Law.Err('session_expired', 'Character changed.') end
    local result = Law.Call('feather-justice', operation, request)
    if not Law.Current(actor) then return Law.Err('session_expired', 'Character changed; retain the original request ID.') end
    return result
end

-- Canonical, order-independent payload text for the operation journal.
local function Canonical(value, depth)
    if type(value) ~= 'table' then return type(value) .. ':' .. tostring(value) end
    if depth > 6 then error('payload_too_deep') end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local encoded = Canonical(value[key], depth + 1)
        parts[#parts + 1] = #tostring(key) .. ':' .. tostring(key) .. #encoded .. ':' .. encoded
    end
    return '{' .. table.concat(parts, ',') .. '}'
end
Law.Canonical = function(value) return Canonical(value, 1) end
-- A committed result the client may not have received. Only identifiers, revision and
-- status are kept (never narrative), so a Justice expunge is not undone by Law's copy.
local function Minimal(value)
    if type(value) ~= 'table' then return value end
    local keep = {}
    for _, key in ipairs({ 'kind', 'recordId', 'caseId', 'revision', 'status', 'jurisdictionId', 'restrained', 'escortSource' }) do
        keep[key] = value[key]
    end
    return keep
end

function Law.RegisterRoute(name, spec)
    return Law.Call('feather-core', 'RegisterRpc', name, function(payload, source, context)
        if spec.validate(payload) ~= true then return Law.Err('invalid_input', 'Invalid request payload.') end
        -- Exact retries of a mutation the server already confirmed return that result
        -- without re-running physical checks (presence, restraint) that may have changed.
        local journalKey, fingerprint
        if spec.mutation and type(payload.requestId) == 'string' and type(context) == 'table' and Law.Uuid(context.characterId)
            and Law.Store.state == 'ready' then
            journalKey = context.characterId .. ':' .. name .. ':' .. payload.requestId
            fingerprint = Law.Canonical(payload)
            local replay = Law.Store.Journal(journalKey, fingerprint, context.characterId)
            if replay == 'conflict' then return Law.Err('idempotency_conflict', 'Request ID is bound to a different payload.') end
            if replay then return Law.Ok(replay) end
        end
        local ok, result = pcall(spec.handler, payload, source, context)
        if not ok then return Law.Err('operation_failed', 'Operation could not be confirmed; retain the request ID.') end
        if journalKey and type(result) == 'table' and result.ok then
            local stored = Minimal(result.value)
            if type(stored) == 'table' then stored.replayed = true end
            pcall(Law.Store.Remember, journalKey, fingerprint, context.characterId, name, stored)
        end
        return result
    end, { contract = 1, direction = 'client_to_server', requireCharacter = true,
        maxPayloadBytes = 8192, maxDepth = spec.maxDepth or 2, maxNodes = spec.maxNodes or 12, windowMs = 5000, maxCalls = 5,
        validatePayload = spec.validate })
end
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
    local justice = Law.JusticeContract()
    if epoch ~= Law.Epoch then return end
    if not core.ok or type(core.value) ~= 'table' or core.value.contract ~= 1 or not justice then
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
Law.Poll = Poll
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
    local justice = Law.JusticeContract()
    print(('[LawReleaseContractSmokeTest] read-only version=%s ready=%s routes=%d/%d config=%s justice=%s store=%s'):format(
        Law.Version, tostring(Law.Ready()), count, expected, tostring(Law.ValidateConfig()),
        justice and justice.release or 'unavailable', Law.Store.state))
end, true)
