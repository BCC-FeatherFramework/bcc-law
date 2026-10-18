function Law.Actor(source, context)
    if not Law.Ready() then return Law.Err('not_ready', 'Law is not ready.') end
    if type(source) ~= 'number' or source % 1 ~= 0 or source < 1 or source > 65535 then
        return Law.Err('unauthenticated', 'A connected player is required.')
    end
    local epoch = Law.Epoch
    local session = Law.Call('feather-core', 'GetSessionContext', source)
    if not session.ok or type(session.value) ~= 'table' or not Law.Uuid(session.value.characterId)
        or not Law.Uuid(session.value.sessionId) or not context
        or context.sessionId ~= session.value.sessionId or context.characterId ~= session.value.characterId then
        return Law.Err('session_expired', 'Active character required.')
    end
    local actor = { source = source, characterId = session.value.characterId,
        sessionId = session.value.sessionId, epoch = epoch }
    if not Law.Current(actor) then return Law.Err('session_expired', 'Character changed.') end
    return Law.Ok(actor)
end
function Law.Current(actor)
    if not Law.Ready() or actor.epoch ~= Law.Epoch then return false end
    local ok, current = pcall(function()
        return exports['feather-core']:IsSessionCurrent(actor.source, actor.sessionId, actor.characterId)
    end)
    return ok and current == true
end
function Law.Access(source, context, departmentKey, action)
    local department = LawConfig.Departments[departmentKey or '']
    if not department then return Law.Err('department_unavailable', 'Department is not configured.') end
    local actor = Law.Actor(source, context)
    if not actor.ok then return actor end
    local job = Law.Call('feather-jobs', 'CheckAssignment', {
        characterId = actor.value.characterId, jobKey = department.jobKey,
        minGradeOrdinal = department.minGradeOrdinal, dutyState = 'on_duty', activeOnly = true,
        employerType = department.employerId and 'organization' or nil, employerId = department.employerId
    })
    if not job.ok then return Law.Err('jobs_unavailable', 'Job verification is unavailable.') end
    if type(job.value) ~= 'table' or job.value.matched ~= true then return Law.Err('duty_required', 'Authorized active duty required.') end
    local license = Law.Call('feather-licenses', 'CheckLicense', {
        holderType = 'character', holderId = actor.value.characterId, licenseKey = department.licenseKey
    })
    if not license.ok then return Law.Err('licenses_unavailable', 'Qualification verification is unavailable.') end
    if type(license.value) ~= 'table' or license.value.matched ~= true then
        return Law.Err('qualification_required', 'A valid qualification is required.')
    end
    -- Scope vocabulary is owned by Licenses. Until its jurisdiction contract
    -- is agreed, only an explicitly empty version-1 scope is understood here.
    if license.value.scopeVersion ~= 1 or type(license.value.scope) ~= 'table' then
        return Law.Err('licenses_unavailable', 'Qualification scope is unavailable.')
    end
    if next(license.value.scope) ~= nil then
        return Law.Err('qualification_scope_unsupported', 'This qualification scope is not supported yet.')
    end
    local jurisdiction = Law.Call('feather-justice', 'FindJurisdictionByKey', {
        recordKey = department.jurisdictionKey, actorSource = source
    })
    if not jurisdiction.ok or type(jurisdiction.value) ~= 'table'
        or jurisdiction.value.status ~= 'active' or not Law.Uuid(jurisdiction.value.recordId) then
        return Law.Err('jurisdiction_unavailable', 'Jurisdiction verification is unavailable.')
    end
    local policy = Law.Call('feather-core', 'Authorize', action, {
        source = source, subject = { resource = 'bcc-law', jurisdictionId = jurisdiction.value.recordId, departmentKey = departmentKey }
    })
    if not policy.ok then return Law.Err('policy_unavailable', 'Authorization is unavailable.') end
    if type(policy.value) ~= 'table' or policy.value.allowed ~= true then return Law.Err('authorization_denied', 'Not authorized.') end
    if not Law.Current(actor.value) then return Law.Err('session_expired', 'Character changed.') end
    actor.value.jurisdictionId = jurisdiction.value.recordId
    return actor
end
