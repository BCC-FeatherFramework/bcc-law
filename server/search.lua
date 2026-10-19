local function Integer(v) return type(v)=='number' and v%1==0 and v>=1 and v<=9007199254740991 end
function Law.SearchAvailable()
    if not Law.Ready() then return false end
    local inventory=Law.Call('feather-inventory','GetLawSearchCapabilities')
    local justice=Law.Call('feather-justice','GetCapabilities')
    return inventory.ok and type(inventory.value)=='table' and inventory.value.contract==1 and inventory.value.state=='ready'
        and justice.ok and type(justice.value)=='table' and justice.value.contract==1
        and type(justice.value.features)=='table' and justice.value.features.searchWarrants==1
end
local function Validate(p,internal)
    return Law.Fields(p,internal and {department=true,targetSource=true,warrantId=true,cursor=true,actorSource=true,sessionId=true,characterId=true}
        or {department=true,targetSource=true,warrantId=true,cursor=true})
        and Law.Token(p.department,48) and Integer(p.targetSource) and p.targetSource<=65535
        and Law.Uuid(p.warrantId) and (p.cursor==nil or Integer(p.cursor))
        and (not internal or (Integer(p.actorSource) and p.actorSource<=65535 and Law.Uuid(p.sessionId) and Law.Uuid(p.characterId)))
end
local function Access(p,source,context)
    local actor=Law.Access(source,context,p.department,'law.search.inspect');if not actor.ok then return actor end
    local target=Law.RestrainedTarget(actor.value,p.targetSource,p.department);if not target.ok then return target end
    local warrant=Law.Call('feather-justice','GetWarrant',{actorSource=source,recordId=p.warrantId})
    if not warrant.ok then return warrant end
    local w=warrant.value
    if type(w)~='table' or w.status~='active' or w.jurisdictionId~=actor.value.jurisdictionId
        or type(w.subjectCharacterId)~='string' or w.subjectCharacterId:lower()~=target.value.characterId:lower()
        or type(w.document)~='table' or w.document.warrantType~='search' then
        return Law.Err('search_authority_required','An accessible active search warrant for this subject is required.')
    end
    if not Law.Current(actor.value) or not Law.Current(target.value) then return Law.Err('session_expired','Character changed.') end
    local current=Law.RestrainedTarget(actor.value,p.targetSource,p.department)
    if not current.ok or current.value.sessionId~=target.value.sessionId or current.value.characterId~=target.value.characterId then
        return Law.Err('session_expired','Search conditions changed.')
    end
    return Law.Ok({actor=actor.value,target=target.value,warrantRevision=w.revision})
end
-- Inventory calls back before and after reading; no bearer token or ACL grant.
exports('AuthorizeInventorySearch',function(p)
    if GetInvokingResource()~='feather-inventory' then return Law.Err('authorization_denied','Inventory caller required.') end
    if not Validate(p,true) then return Law.Err('invalid_input','Invalid search context.') end
    return Access(p,p.actorSource,{sessionId=p.sessionId,characterId=p.characterId})
end)
Law.Routes['law.search.inspect.v1']={
    validate=function(p) return Validate(p,false) end,
    handler=function(p,source,context)
        local access=Access(p,source,context);if not access.ok then return access end
        local actor,target=access.value.actor,access.value.target
        local result=Law.Call('feather-inventory','InspectLawSearch',{
            actorSource=source,characterId=actor.characterId,sessionId=actor.sessionId,
            department=p.department,targetSource=p.targetSource,warrantId=p.warrantId,cursor=p.cursor
        })
        if not Law.Current(actor) or not Law.Current(target) then return Law.Err('session_expired','Character changed.') end
        -- Inventory contract 2 nests errors; Law's public DTO stays flat.
        if not result.ok and type(result.error)=='table' then return Law.Err(result.error.code,result.error.message) end
        if result.ok and type(result.value)=='table' then result.value.warrantRevision=access.value.warrantRevision end
        return result
    end
}
Law.Routes['law.search.finish.v1']={
    validate=function(p)
        if not Law.Fields(p,{department=true,targetSource=true,warrantId=true,expectedRevision=true,requestId=true}) then return false end
        return Validate({department=p.department,targetSource=p.targetSource,warrantId=p.warrantId},false)
            and Integer(p.expectedRevision) and Law.Token(p.requestId,64)
    end,
    handler=function(p,source,context)
        local authorized=Law.Access(source,context,p.department,'law.search.inspect');if not authorized.ok then return authorized end
        local actor=authorized.value
        local request={actorSource=source,recordId=p.warrantId,expectedRevision=p.expectedRevision,
            requestId=actor.characterId..':'..p.requestId,reasonCode='law.search.execute'}
        local receipt=Law.Call('feather-justice','FindOperation',{actorSource=source,requestId=request.requestId})
        if not Law.Current(actor) then return Law.Err('session_expired','Character changed.') end
        if not receipt.ok and receipt.code~='not_found' then return receipt end
        if receipt.ok and (type(receipt.value)~='table' or receipt.value.jurisdictionId~=actor.jurisdictionId) then
            return Law.Err('not_found','Operation unavailable in this department.')
        end
        if not receipt.ok then
            local access=Access(p,source,context);if not access.ok then return access end
        end
        -- Justice verifies the exact original payload even on historical retry.
        local result=Law.Call('feather-justice','ServeWarrant',request)
        if not Law.Current(actor) then return Law.Err('session_expired','Character changed; retain the request ID.') end
        return result
    end
}
local function WarrantDraft(kind)
return {
    validate=function(p)
        return Law.Fields(p,{department=true,caseId=true,requestId=true,expectedCaseRevision=true,subjectCharacterId=true,basisSummary=true,validForSeconds=true})
            and Law.Token(p.department,48) and Law.Uuid(p.caseId) and Law.Token(p.requestId,64)
            and Integer(p.expectedCaseRevision) and Law.Uuid(p.subjectCharacterId) and Law.Text(p.basisSummary,2000)
            and Integer(p.validForSeconds) and p.validForSeconds>=60 and p.validForSeconds<=2592000
    end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.warrant.draft');if not actor.ok then return actor end
        local capabilities=Law.Call('feather-justice','GetCapabilities')
        if not capabilities.ok or type(capabilities.value)~='table' or capabilities.value.contract~=1
            or type(capabilities.value.features)~='table' or capabilities.value.features[kind..'Warrants']~=1 then
            return Law.Err('search_authority_unavailable','Justice search warrants are unavailable.')
        end
        local case=Law.Call('feather-justice','GetCase',{actorSource=source,recordId=p.caseId})
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
        if not case.ok then return case end
        if type(case.value)~='table' or case.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Case unavailable.') end
        local result=Law.Call('feather-justice','CreateWarrantDraft',{
            actorSource=source,caseId=p.caseId,requestId=actor.value.characterId..':'..p.requestId,
            reasonCode='law.warrant.'..kind..'.draft',expectedCaseRevision=p.expectedCaseRevision,
            subjectCharacterId=p.subjectCharacterId,basisSummary=p.basisSummary,validForSeconds=p.validForSeconds,warrantType=kind
        })
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed; retain the request ID.') end
        return result
    end
}

end
Law.Routes['law.warrants.search.draft.v1']=WarrantDraft('search')
Law.Routes['law.warrants.seizure.draft.v1']=WarrantDraft('seizure')

Law.Routes['law.warrants.summons.draft.v1']=WarrantDraft('summons')
