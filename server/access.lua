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
Law.PolicyRules={
    ['law.armory.issue']='officer',['law.restraint.manage']='officer',['law.search.inspect']='officer',['law.evidence.collect']='officer',
    ['justice.definition.view']='legal',
    ['justice.case.open']='legal',['justice.case.view']='legal',['justice.case.update']='legal',['justice.case.transition']='legal',
    ['justice.party.view']='legal',['justice.party.manage']='legal',
    ['justice.charge.view']='legal',['justice.charge.propose']='legal',['justice.charge.file']='legal',['justice.charge.dispose']='legal',['justice.charge.amend']='legal',
    ['justice.warrant.view']='legal',['justice.warrant.draft']='legal',['justice.warrant.issue']='legal',['justice.warrant.serve']='legal',['justice.warrant.recall']='legal',['justice.warrant.quash']='legal',
    ['justice.citation.view']='legal',['justice.citation.issue']='officer',['justice.citation.cancel']='legal',
    ['justice.custody.view']='legal',['justice.custody.book']='officer',['justice.custody.release']='legal',
    ['justice.ruling.record']='judicial',['justice.ruling.view']='legal',
    ['justice.sentence.impose']='judicial',['justice.sentence.activate']='judicial',['justice.sentence.modify']='judicial',
    ['justice.sentence.effect']='judicial',['justice.sentence.progress']='legal',['justice.sentence.view']='legal',
    ['justice.evidence.link']='legal',['justice.evidence.dispose']='judicial',['justice.evidence.view']='legal',
    ['justice.record.seal']='judicial',['justice.record.expunge']='judicial',['justice.case.view_sealed']='judicial',
    ['justice.audit.view']='judicial',['justice.status.view']='legal'
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
    if not Law.Current(actor) then return Law.Err('session_expired','Character changed.') end
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
function Law.Access(source, context, departmentKey, action)
    local department=LawConfig.Departments[departmentKey or '']
    if not department then return Law.Err('department_unavailable','Department is not configured.') end
    local actor=Law.QualifiedActor(source,context,departmentKey,Law.PolicyRules[action] or 'officer')
    if not actor.ok then return actor end
    local jurisdiction = Law.Call('feather-justice', 'FindJurisdictionByKey', {
        recordKey = department.jurisdictionKey, actorSource = source
    })
    if not jurisdiction.ok or type(jurisdiction.value) ~= 'table'
        or jurisdiction.value.status ~= 'active' or not Law.Uuid(jurisdiction.value.recordId) then
        return Law.Err('jurisdiction_unavailable', 'Jurisdiction verification is unavailable.')
    end
    Law.PolicyJurisdictions[departmentKey]=jurisdiction.value.recordId
    local policy = Law.Call('feather-core', 'Authorize', action, {
        source = source, subject = { resource = 'bcc-law', jurisdictionId = jurisdiction.value.recordId, departmentKey = departmentKey }
    })
    if not policy.ok then return Law.Err('policy_unavailable', 'Authorization is unavailable.') end
    if type(policy.value) ~= 'table' or policy.value.allowed ~= true then return Law.Err('authorization_denied', 'Not authorized.') end
    if not Law.Current(actor.value) then return Law.Err('session_expired', 'Character changed.') end
    actor.value.jurisdictionId = jurisdiction.value.recordId
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
    if action=='justice.warrant.issue' and (context.subject.warrantType=='search' or context.subject.warrantType=='seizure') then rule='judicial' end
    local jurisdiction=context.subject.jurisdictionId
    for key in pairs(LawConfig.Departments) do
        local scope=action=='justice.definition.view' or (Law.Uuid(jurisdiction) and Law.PolicyJurisdictions[key]==jurisdiction
            and (context.subject.departmentKey==nil or context.subject.departmentKey==key))
        if scope then
            local actor=Law.QualifiedActor(context.source,context,key,rule)
            if actor.ok then return Law.Ok({allowed=true,code='qualified_law_actor'}) end
        end
    end
    return Law.Ok({allowed=false,code='qualification_or_jurisdiction_required'})
end)
