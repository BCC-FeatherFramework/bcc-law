Law.Routes = {}
local function DepartmentPayload(payload)
    return Law.Fields(payload, { department = true, cursor = true }) and Law.Token(payload.department, 48)
        and (payload.cursor == nil or Law.Uuid(payload.cursor))
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
        return Law.Ok({ departments = departments })
    end
}
Law.Routes['law.cases.list.v1'] = {
    validate = DepartmentPayload,
    handler = function(payload, source, context)
        local actor = Law.Access(source, context, payload.department, 'justice.case.view')
        if not actor.ok then return actor end
        local result = Law.Call('feather-justice', 'ListCases', {
            actorSource = source, jurisdictionId = actor.value.jurisdictionId, cursor = payload.cursor, limit = 25
        })
        if not Law.Current(actor.value) then return Law.Err('session_expired', 'Character changed.') end
        return result
    end
}
Law.Routes['law.cases.open.v1'] = {
    validate = function(payload)
        return Law.Fields(payload, { department=true, requestId=true, title=true, summary=true })
            and Law.Token(payload.department, 48) and Law.Token(payload.requestId, 64)
            and Law.Text(payload.title, 180) and Law.Text(payload.summary, 4000)
    end,
    handler = function(payload, source, context)
        local actor = Law.Access(source, context, payload.department, 'justice.case.open')
        if not actor.ok then return actor end
        local result = Law.Call('feather-justice', 'OpenCase', {
            actorSource = source, jurisdictionId = actor.value.jurisdictionId,
            requestId = actor.value.characterId .. ':' .. payload.requestId,
            reasonCode = 'law.case.open', title = payload.title, summary = payload.summary
        })
        -- The durable request identity is retained even if the caller leaves
        -- after commit. Recovery must use the same ID, not create another case.
        if not Law.Current(actor.value) then return Law.Err('session_expired', 'Character changed; reuse the same request ID.') end
        return result
    end
}
function Law.RegisterRoute(name, spec)
    return Law.Call('feather-core', 'RegisterRpc', name, function(payload, source, context)
        if spec.validate(payload) ~= true then return Law.Err('invalid_input', 'Invalid request payload.') end
        local ok, result = pcall(spec.handler, payload, source, context)
        if not ok then return Law.Err('operation_failed', 'Operation could not be confirmed; retain the request ID.') end
        return result
    end, { contract = 1, direction = 'client_to_server', requireCharacter = true,
        maxPayloadBytes = 8192, maxDepth = spec.maxDepth or 2, maxNodes = spec.maxNodes or 12, windowMs = 5000, maxCalls = 5,
        validatePayload = spec.validate })
end
