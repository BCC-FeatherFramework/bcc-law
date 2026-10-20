-- Arrest, booking and release (Justice master plan: "BCC Law identifies active
-- warrant or lawful exception → Justice records arrest/custody authority → BCC Law
-- performs restraint and transport → booking → Justice records release").
local maximumRevision=9007199254740989
local function Number(v,min,max) return type(v)=='number' and v==v and v>=min and v<=max end
local function Integer(v,min,max) return type(v)=='number' and v%1==0 and v>=min and v<=max end
function Law.ValidateCustodyConfig()
    local c=LawConfig.Custody
    if type(c)~='table' or not Number(c.InteractionDistance,0.5,10) or type(c.Facilities)~='table' then return false end
    local count=0
    for key,f in pairs(c.Facilities) do
        count=count+1
        if not Law.Token(key,64) or type(f)~='table' or not Law.Fields(f,{label=true,department=true,x=true,y=true,z=true,radius=true})
            or not Law.Text(f.label,100) or not LawConfig.Departments[f.department or '']
            or not Number(f.x,-100000,100000) or not Number(f.y,-100000,100000) or not Number(f.z,-10000,10000)
            or not Number(f.radius,1,25) then return false end
    end
    return count<=32
end
local function Target(characterId)
    for _,player in ipairs(GetPlayers()) do
        local source=tonumber(player)
        local session=Law.Call('feather-core','GetSessionContext',source)
        if session.ok and type(session.value)=='table' and Law.Uuid(session.value.characterId)
            and session.value.characterId:lower()==characterId:lower() and Law.Uuid(session.value.sessionId) then
            local actor={source=source,characterId=session.value.characterId,sessionId=session.value.sessionId,epoch=Law.Epoch}
            if Law.Current(actor) then return Law.Ok(actor) end
        end
    end
    return Law.Err('subject_offline','Subject must have a current character session.')
end
Law.SessionForCharacter=Target
local function Coordinates(source)
    local ped=GetPlayerPed(source)
    if not ped or ped==0 then return nil end
    local p=GetEntityCoords(ped)
    if not p or not Number(p.x,-100000,100000) or not Number(p.y,-100000,100000) or not Number(p.z,-10000,10000) then return nil end
    return p
end
local function Distance(a,b) return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
-- Officer and subject together at the department's configured booking facility.
local function Presence(actor,subjectId,facilityKey,department)
    local f=LawConfig.Custody.Facilities[facilityKey or '']
    if not f or f.department~=department then return Law.Err('facility_unavailable','Booking facility is not configured for this department.') end
    if actor.characterId:lower()==subjectId:lower() then return Law.Err('self_booking_denied','Officer cannot book their own character.') end
    local target=Target(subjectId);if not target.ok then return target end
    if type(GetPlayerRoutingBucket)~='function' or GetPlayerRoutingBucket(actor.source)~=GetPlayerRoutingBucket(target.value.source) then
        return Law.Err('interaction_unavailable','Players are not in the same instance.')
    end
    local a,b=Coordinates(actor.source),Coordinates(target.value.source)
    if not a or not b then return Law.Err('interaction_unavailable','Player positions are unavailable.') end
    if Distance(a,b)>LawConfig.Custody.InteractionDistance^2 or Distance(a,f)>f.radius^2 or Distance(b,f)>f.radius^2 then
        return Law.Err('booking_location_required','Officer and subject must be together at the configured booking facility.')
    end
    if not Law.Current(actor) or not Law.Current(target.value) then return Law.Err('session_expired','Character changed.') end
    return target
end
Law.BookingPresence=Presence

Law.Routes['law.custody.facilities.v1']={
    validate=function(p) return Law.RoutePayload(p,{},false) end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.custody.view');if not actor.ok then return actor end
        local items={};for key,f in pairs(LawConfig.Custody.Facilities) do if f.department==p.department then items[#items+1]={key=key,label=f.label} end end
        table.sort(items,function(a,b) return a.key<b.key end);return Law.Ok({items=items})
    end
}
Law.Routes['law.custody.list.v1']={
    validate=function(p) return Law.RoutePayload(p,{'caseId'},false) and Law.Uuid(p.caseId) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.custody.view',true);if not actor.ok then return actor end
        local related=actor.value.case.related
        return Law.Ok(type(related)=='table' and related.custody or {items={},truncated=false})
    end
}
-- Arrest: the subject must already be restrained (by any qualified officer) and
-- nearby; the authority must name exactly that character in this case.
Law.Routes['law.custody.arrest.v1']={mutation=true,
    validate=function(p) return Law.RoutePayload(p,{'caseId','targetSource','authorityType','authorityId','expectedAuthorityRevision'},true)
        and Law.Uuid(p.caseId) and Integer(p.targetSource,1,65535) and (p.authorityType=='warrant' or p.authorityType=='judicial_order')
        and Law.Uuid(p.authorityId) and Integer(p.expectedAuthorityRevision,1,maximumRevision) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.custody.record');if not actor.ok then return actor end
        local target=Law.RestrainedTarget(actor.value,p.targetSource,p.department);if not target.ok then return target end
        local subjectId
        if p.authorityType=='warrant' then
            local warrant=Law.Dispatch(actor.value,'GetWarrant',{actorSource=source,warrantId=p.authorityId})
            if not warrant.ok then return warrant end
            local w=warrant.value
            if w.caseId~=p.caseId or w.warrantType~='arrest' or w.status~='active' then return Law.Err('arrest_authority_required','An active arrest warrant of this case is required.') end
            subjectId=w.subjectCharacterId
        else
            local sentence=Law.Dispatch(actor.value,'GetSentence',{actorSource=source,sentenceId=p.authorityId})
            if not sentence.ok then return sentence end
            local s=sentence.value
            if s.caseId~=p.caseId or s.sentenceType~='custodial' or s.status~='active' then return Law.Err('arrest_authority_required','An active custodial sentence of this case is required.') end
            subjectId=s.defendantCharacterId
        end
        if type(subjectId)~='string' or subjectId:lower()~=target.value.characterId:lower() then
            return Law.Err('arrest_authority_required','The authority names a different person.')
        end
        local request=Law.Mutation(p,actor.value,'law.custody.arrest')
        request.caseId,request.authorityType,request.authorityId,request.expectedAuthorityRevision=p.caseId,p.authorityType,p.authorityId,p.expectedAuthorityRevision
        local result=Law.Dispatch(actor.value,'RecordArrest',request)
        -- From now on the custody record, not the (served) warrant, authorizes the restraint.
        if result.ok and type(result.value)=='table' then Law.SetRestraintCustody(p.targetSource,result.value.custodyId) end
        return result
    end
}
Law.Routes['law.custody.book.v1']={mutation=true,
    validate=function(p) return Law.RoutePayload(p,{'caseId','custodyId','expectedRevision','facilityKey'},true) and Law.Uuid(p.caseId)
        and Law.Uuid(p.custodyId) and Integer(p.expectedRevision,1,maximumRevision) and Law.Token(p.facilityKey,64) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.custody.record');if not actor.ok then return actor end
        local record=Law.Dispatch(actor.value,'GetCustodyStatus',{actorSource=source,custodyId=p.custodyId})
        if not record.ok then return record end
        if record.value.caseId~=p.caseId then return Law.Err('not_found','Custody unavailable in this case.') end
        local target=Presence(actor.value,record.value.subjectCharacterId,p.facilityKey,p.department);if not target.ok then return target end
        local request=Law.Mutation(p,actor.value,'law.custody.book')
        request.custodyId,request.expectedRevision,request.facilityKey=p.custodyId,p.expectedRevision,p.facilityKey
        local result=Law.Dispatch(actor.value,'BookCustody',request)
        if result.ok then pcall(Law.LockFacility,p.facilityKey) end
        return result
    end
}
Law.Routes['law.custody.release.v1']={mutation=true,
    validate=function(p) return Law.RoutePayload(p,{'caseId','custodyId','expectedRevision','releaseReason'},true) and Law.Uuid(p.caseId)
        and Law.Uuid(p.custodyId) and Integer(p.expectedRevision,1,maximumRevision) and Law.Token(p.releaseReason,64) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.custody.release');if not actor.ok then return actor end
        local request=Law.Mutation(p,actor.value,'law.custody.release')
        request.custodyId,request.expectedRevision,request.releaseReason=p.custodyId,p.expectedRevision,p.releaseReason
        return Law.Dispatch(actor.value,'ReleaseCustody',request)
    end
}
