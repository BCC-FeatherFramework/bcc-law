local function Number(v,min,max) return type(v)=='number' and v==v and v>=min and v<=max end
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
local function Payload(p,fields,mutation)
    local allowed={department=true};for _,key in ipairs(fields) do allowed[key]=true end
    if mutation then allowed.requestId=true end
    return Law.Fields(p,allowed) and Law.Token(p.department,48) and (not mutation or Law.Token(p.requestId,64))
end
local function CaseAccess(p,source,context,action)
    local actor=Law.Access(source,context,p.department,action);if not actor.ok then return actor end
    local case=Law.Call('feather-justice','GetCase',{actorSource=source,recordId=p.caseId})
    if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
    if not case.ok then return case end
    if case.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Case unavailable.') end
    return actor
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
local function Coordinates(source)
    local ped=GetPlayerPed(source)
    if not ped or ped==0 then return nil end
    local p=GetEntityCoords(ped)
    if not p or not Number(p.x,-100000,100000) or not Number(p.y,-100000,100000) or not Number(p.z,-10000,10000) then return nil end
    return p
end
local function Distance(a,b) return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
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
local function Mutation(p,actor,reason)
    return {actorSource=actor.source,requestId=actor.characterId..':'..p.requestId,reasonCode=reason,caseId=p.caseId}
end
local function Dispatch(actor,target,operation,request)
    if not Law.Current(actor) or (target and not Law.Current(target)) then return Law.Err('session_expired','Character changed.') end
    local result=Law.Call('feather-justice',operation,request)
    if not Law.Current(actor) or (target and not Law.Current(target)) then return Law.Err('session_expired','Character changed; reuse the original request ID.') end
    return result
end
Law.Routes['law.custody.facilities.v1']={
    validate=function(p) return Payload(p,{},false) end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.custody.view');if not actor.ok then return actor end
        local items={};for key,f in pairs(LawConfig.Custody.Facilities) do if f.department==p.department then items[#items+1]={key=key,label=f.label} end end
        table.sort(items,function(a,b) return a.key<b.key end);return Law.Ok({items=items})
    end
}
Law.Routes['law.custody.list.v1']={
    validate=function(p) return Payload(p,{'caseId','cursor'},false) and Law.Uuid(p.caseId) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.custody.view');if not actor.ok then return actor end
        return Dispatch(actor.value,nil,'ListCaseCustody',{actorSource=source,caseId=p.caseId,cursor=p.cursor,limit=25})
    end
}
Law.Routes['law.custody.reserve.v1']={
    validate=function(p) return Payload(p,{'caseId','warrantId','expectedWarrantRevision','facilityKey'},true) and Law.Uuid(p.caseId)
        and Law.Uuid(p.warrantId) and Number(p.expectedWarrantRevision,1,9007199254740989) and p.expectedWarrantRevision%1==0 and Law.Token(p.facilityKey,64) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.custody.book');if not actor.ok then return actor end
        local warrant=Law.Call('feather-justice','GetWarrant',{actorSource=source,recordId=p.warrantId})
        if not warrant.ok then return warrant end
        if warrant.value.caseId~=p.caseId or warrant.value.jurisdictionId~=actor.value.jurisdictionId or not Law.Uuid(warrant.value.subjectCharacterId) then return Law.Err('not_found','Warrant unavailable.') end
        local target=Presence(actor.value,warrant.value.subjectCharacterId,p.facilityKey,p.department);if not target.ok then return target end
        local request=Mutation(p,actor.value,'law.custody.reserve')
        request.warrantId,request.expectedWarrantRevision,request.facilityKey=p.warrantId,p.expectedWarrantRevision,p.facilityKey
        return Dispatch(actor.value,target.value,'ReserveCustodyBooking',request)
    end
}
for _,spec in ipairs({{route='confirm',operation='ConfirmCustodyBooking',action='justice.custody.book'},
    {route='release',operation='ReleaseCustody',action='justice.custody.release'}}) do
    Law.Routes['law.custody.'..spec.route..'.v1']={
        validate=function(p) return Payload(p,{'caseId','recordId','expectedRevision'},true) and Law.Uuid(p.caseId)
            and Law.Uuid(p.recordId) and Number(p.expectedRevision,1,9007199254740989) and p.expectedRevision%1==0 end,
        handler=function(p,source,context)
            local actor=CaseAccess(p,source,context,spec.action);if not actor.ok then return actor end
            local record=Law.Call('feather-justice','GetCustody',{actorSource=source,recordId=p.recordId})
            if not record.ok then return record end
            if record.value.caseId~=p.caseId or record.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Custody unavailable.') end
            local target
            if spec.route=='confirm' then
                local presence=Presence(actor.value,record.value.subjectCharacterId,record.value.document.facilityKey,p.department)
                if not presence.ok then return presence end;target=presence.value
            end
            local request=Mutation(p,actor.value,'law.custody.'..spec.route)
            request.recordId,request.expectedRevision=p.recordId,p.expectedRevision
            return Dispatch(actor.value,target,spec.operation,request)
        end
    }
end

-- Historical recovery must not require the target to remain online/nearby.
Law.Routes['law.operations.get.v1']={
    validate=function(p) return Payload(p,{'requestId'},false) and Law.Token(p.requestId,64) end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.case.view');if not actor.ok then return actor end
        local result=Law.Call('feather-justice','FindOperation',{actorSource=source,requestId=actor.value.characterId..':'..p.requestId})
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
        if not result.ok then return result end
        if result.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Operation unavailable.') end
        return result
    end
}
