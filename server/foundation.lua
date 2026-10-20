local health = { state = 'starting', phase = 'foundation', contract = 1 }
Law.Version = '2.0.0-beta.1'
Law.Epoch = 0
function Law.SetState(state, phase)
    Law.Epoch = Law.Epoch + 1
    Law.PolicyJurisdictions = {}
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
-- The player's Core account language (falls back to LawConfig.DefaultLocale, then English).
function Law.SourceLocale(source)
    local ok, settings = pcall(function() return exports['feather-core']:GetAccountSettings(source) end)
    return Law.Locale(ok and type(settings) == 'table' and settings.ok and type(settings.value) == 'table' and settings.value.locale or nil)
end
function Law.Capabilities()
    local ready = Law.Ready() and 1 or 0
    local function optional(fn) return fn and fn() and 1 or 0 end
    return Law.Ok({ resource = 'bcc-law', contract = 1, version = Law.Version, state = health.state,
        features = { lifecycle = 1, sessions = 1, mdtNui = 1, caseRoutes = ready, partyRoutes = ready,
            chargeRoutes = ready, warrantRoutes = ready, citationRoutes = ready, custodyRoutes = ready,
            courtRoutes = ready, statuteEditor = ready, restraints = ready, escort = ready, finePayments = 1,
            search = optional(Law.SearchAvailable), evidence = optional(Law.EvidenceAvailable),
            jail = optional(Law.ExecutionAvailable), communityService = optional(Law.ExecutionAvailable),
            armory = optional(Law.ArmoryAvailable), doors = optional(Law.DoorsAvailable), alerts = optional(Law.AlertsAvailable),
            -- Owned elsewhere (Law master plan §2): payroll by Society/Jobs/Economy.
            payroll = 0 } })
end
-- Justice must publish the master plan's capability document (contract
-- 'feather.justice', version 1) with every feature Law consumes.
local requiredJustice = { 'cases', 'parties', 'charges', 'warrants', 'citations', 'custody', 'rulings', 'sentences', 'sealing' }
function Law.JusticeContract()
    local justice = Law.Call('feather-justice', 'GetCapabilities')
    if not justice.ok or type(justice.value) ~= 'table' or justice.value.contract ~= 'feather.justice'
        or justice.value.version ~= 1 or type(justice.value.features) ~= 'table' then return nil end
    for _, feature in ipairs(requiredJustice) do
        if justice.value.features[feature] ~= 1 then return nil end
    end
    return justice.value
end
function Law.ValidateConfig()
    if type(LawConfig.Departments) ~= 'table' or type(LawConfig.MaxDepartments) ~= 'number'
        or LawConfig.MaxDepartments % 1 ~= 0 or LawConfig.MaxDepartments < 1 or LawConfig.MaxDepartments > 32 then return false end
    local count = 0
    for key, value in pairs(LawConfig.Departments) do
        count = count + 1
        if not Law.Token(key, 48) or type(value) ~= 'table' or not Law.Text(value.label, 100)
            or not Law.Fields(value, { label=true, jobKey=true, minGradeOrdinal=true, licenseKey=true, jurisdictionKey=true,
                jurisdictionType=true, employerId=true, judicial=true })
            or type(value.jobKey) ~= 'string' or #value.jobKey > 48 or not value.jobKey:match('^[a-z][a-z0-9_]*$')
            or type(value.licenseKey) ~= 'string' or #value.licenseKey > 48 or not value.licenseKey:match('^[a-z][a-z0-9_]*$')
            or not Law.Token(value.jurisdictionKey, 128) or value.jurisdictionKey:sub(1,8) ~= 'bcc-law:'
            or (value.jurisdictionType ~= nil and not Law.Token(value.jurisdictionType, 32))
            or (value.employerId ~= nil and not Law.Uuid(value.employerId))
            or type(value.minGradeOrdinal) ~= 'number' or value.minGradeOrdinal % 1 ~= 0
            or value.minGradeOrdinal < 0 or value.minGradeOrdinal > 1000 then return false end
    end
    for _,department in pairs(LawConfig.Departments) do
        local c=department.judicial
        if c~=nil and (not Law.Fields(c,{jobKey=true,licenseKey=true,minGradeOrdinal=true,employerId=true})
            or type(c.jobKey)~='string' or not c.jobKey:match('^[a-z][a-z0-9_]*$') or #c.jobKey>48
            or type(c.licenseKey)~='string' or not c.licenseKey:match('^[a-z][a-z0-9_]*$') or #c.licenseKey>48
            or type(c.minGradeOrdinal)~='number' or c.minGradeOrdinal%1~=0 or c.minGradeOrdinal<0 or c.minGradeOrdinal>1000
            or (c.employerId~=nil and not Law.Uuid(c.employerId))) then return false end
    end
    return count <= LawConfig.MaxDepartments and Law.ValidateCustodyConfig() and Law.ValidateRestraintsConfig()
        and Law.ValidateEvidenceConfig() and Law.ValidateExecutionConfig() and Law.ValidateArmoryConfig()
        and Law.ValidateStatuteConfig() and Law.ValidateDoorsConfig() and Law.ValidateAlertsConfig()
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
-- Qualification each Justice/Law action needs (feather-admin's qualified mode asks
-- Law through EvaluateActionPolicy). officer = on-duty police + peace-officer
-- commission; judicial = judge assignment + judicial commission; legal = either.
Law.PolicyRules={
    ['law.armory.issue']='officer',['law.restraint.manage']='officer',['law.search.inspect']='officer',['law.evidence.collect']='officer',
    ['justice.definition.view']='legal',['justice.definition.manage']='judicial',
    ['justice.case.open']='legal',['justice.case.view']='legal',['justice.case.update']='legal',['justice.case.transition']='legal',
    ['justice.party.view']='legal',['justice.party.manage']='legal',
    ['justice.charge.view']='legal',['justice.charge.propose']='legal',['justice.charge.file']='legal',
    ['justice.charge.dispose']='legal',['justice.charge.amend']='legal',
    ['justice.warrant.view']='legal',['justice.warrant.draft']='legal',['justice.warrant.issue']='legal',
    ['justice.warrant.serve']='legal',['justice.warrant.recall']='legal',['justice.warrant.quash']='legal',
    ['justice.citation.view']='legal',['justice.citation.issue']='officer',
    ['justice.custody.view']='legal',['justice.custody.record']='officer',['justice.custody.release']='legal',
    ['justice.ruling.record']='judicial',
    ['justice.sentence.impose']='judicial',['justice.sentence.activate']='judicial',['justice.sentence.suspend']='judicial',
    ['justice.sentence.complete']='judicial',['justice.sentence.view']='legal',
    ['justice.evidence.link']='legal',['justice.evidence.view']='legal',
    ['justice.record.seal']='judicial',['justice.record.expunge']='judicial',['justice.case.view_sealed']='judicial',
    ['justice.audit.view']='judicial'
}
Law.PolicyJurisdictions={}
function Law.CheckQualification(actor,profile)
    if type(profile)~='table' then return Law.Err('qualification_required','No qualification profile is configured.') end
    local job = Law.Call('feather-jobs', 'CheckAssignment', {
        characterId = actor.characterId, jobKey = profile.jobKey,
        minGradeOrdinal = profile.minGradeOrdinal, dutyState = 'on_duty', activeOnly = true,
        employerType = profile.employerId and 'organization' or nil, employerId = profile.employerId
    })
    if not job.ok then return Law.Err('jobs_unavailable', 'Job verification is unavailable.') end
    if type(job.value) ~= 'table' or job.value.matched ~= true then return Law.Err('duty_required', 'Authorized active duty required.') end
    local license = Law.Call('feather-licenses', 'CheckLicense', {
        holderType = 'character', holderId = actor.characterId, licenseKey = profile.licenseKey
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
    if actor.source and not Law.Current(actor) then return Law.Err('session_expired','Character changed.') end
    return Law.Ok(true)
end
function Law.QualifiedActor(source,context,departmentKey,rule)
    local department=LawConfig.Departments[departmentKey or '']
    if not department then return Law.Err('department_unavailable','Department is not configured.') end
    local actor=Law.Actor(source,context);if not actor.ok then return actor end
    local primary=rule=='judicial' and department.judicial or department
    local result=Law.CheckQualification(actor.value,primary)
    if not result.ok and rule=='legal' and department.judicial and (result.code=='duty_required' or result.code=='qualification_required') then
        local alternative=Law.CheckQualification(actor.value,department.judicial)
        if alternative.ok then result=alternative end
    end
    if not result.ok then return result end
    return actor
end
-- Jurisdiction ids are read through Justice (GetJurisdiction by key) and cached
-- per department for the current epoch only.
function Law.Jurisdiction(departmentKey, source)
    local department = LawConfig.Departments[departmentKey or '']
    if not department then return Law.Err('department_unavailable', 'Department is not configured.') end
    local jurisdiction = Law.Call('feather-justice', 'GetJurisdiction', { jurisdictionKey = department.jurisdictionKey, actorSource = source })
    if not jurisdiction.ok or type(jurisdiction.value) ~= 'table'
        or jurisdiction.value.status ~= 'active' or not Law.Uuid(jurisdiction.value.jurisdictionId) then
        return Law.Err('jurisdiction_unavailable', 'Jurisdiction verification is unavailable.')
    end
    Law.PolicyJurisdictions[departmentKey] = jurisdiction.value.jurisdictionId
    return Law.Ok(jurisdiction.value.jurisdictionId)
end
function Law.Access(source, context, departmentKey, action)
    local department=LawConfig.Departments[departmentKey or '']
    if not department then return Law.Err('department_unavailable','Department is not configured.') end
    local actor=Law.QualifiedActor(source,context,departmentKey,Law.PolicyRules[action] or 'officer')
    if not actor.ok then return actor end
    local jurisdiction = Law.Jurisdiction(departmentKey, source)
    if not jurisdiction.ok then return jurisdiction end
    local policy = Law.Call('feather-core', 'Authorize', action, {
        source = source, subject = { resource = 'bcc-law', jurisdictionId = jurisdiction.value, departmentKey = departmentKey }
    })
    if not policy.ok then return Law.Err('policy_unavailable', 'Authorization is unavailable.') end
    if type(policy.value) ~= 'table' or policy.value.allowed ~= true then return Law.Err('authorization_denied', 'Not authorized.') end
    if not Law.Current(actor.value) then return Law.Err('session_expired', 'Character changed.') end
    actor.value.jurisdictionId = jurisdiction.value
    actor.value.department = departmentKey
    return actor
end

-- Called only by the installed Core policy provider. This never calls Authorize,
-- and never resolves a jurisdiction through Justice, avoiding a policy cycle.
exports('EvaluateActionPolicy',function(action,context)
    if GetInvokingResource()~='feather-admin' or type(context)~='table'
        or (context.caller~='bcc-law' and context.caller~='feather-justice') or context.system==true
        or type(context.subject)~='table' or context.subject.resource~='bcc-law' then
        return Law.Err('invalid_law_context','Authenticated Law policy context required.')
    end
    local rule=Law.PolicyRules[action]
    if not rule then return Law.Err('unknown_action','Unknown Law action.') end
    local subject=context.subject
    -- Search and seizure warrants, evidence dispositions and judicial sentence
    -- outcomes need judicial qualification even where the base action is legal.
    if action=='justice.warrant.issue' and (subject.warrantType=='search' or subject.warrantType=='seizure') then rule='judicial' end
    if action=='justice.evidence.link' and subject.disposition~=nil then rule='judicial' end
    local jurisdiction=subject.jurisdictionId
    for key in pairs(LawConfig.Departments) do
        local scope=action=='justice.definition.view' or (Law.Uuid(jurisdiction) and Law.PolicyJurisdictions[key]==jurisdiction
            and (subject.departmentKey==nil or subject.departmentKey==key))
        if scope then
            local actor=Law.QualifiedActor(context.source,context,key,rule)
            if actor.ok then return Law.Ok({allowed=true,code='qualified_law_actor'}) end
        end
    end
    return Law.Ok({allowed=false,code='qualification_or_jurisdiction_required'})
end)
