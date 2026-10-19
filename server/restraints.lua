-- Physical state only. Justice remains the owner of the warrant and custody.
-- No client events mutate this registry. Explicit desired states make retries safe.
local held, locks = {}, {}
local function Number(n, minimum, maximum)
    return type(n)=='number' and n==n and n>=minimum and n<=maximum
end
function Law.ValidateRestraintsConfig()
    local c=LawConfig.Restraints
    return type(c)=='table' and Law.Fields(c,{InteractionDistance=true,EscortDistance=true,MaxSeconds=true})
        and Number(c.InteractionDistance,0.5,5) and Number(c.EscortDistance,c.InteractionDistance,10)
        and Number(c.MaxSeconds,30,1800) and c.MaxSeconds%1==0
end
local function Session(source)
    local s=Law.Call('feather-core','GetSessionContext',source)
    if not s.ok or type(s.value)~='table' or not Law.Uuid(s.value.characterId) or not Law.Uuid(s.value.sessionId) then
        return Law.Err('subject_offline','A current target character is required.')
    end
    local actor={source=source,characterId=s.value.characterId,sessionId=s.value.sessionId,epoch=Law.Epoch}
    return Law.Current(actor) and Law.Ok(actor) or Law.Err('session_expired','Character changed.')
end
local function Alive(source)
    local ped=GetPlayerPed(source)
    if not ped or ped==0 or GetEntityHealth(ped)<=0 then return nil end
    local p=GetEntityCoords(ped)
    if not p or not Number(p.x,-100000,100000) or not Number(p.y,-100000,100000) or not Number(p.z,-10000,10000) then return nil end
    return p
end
local function Nearby(actor,target,distance)
    if actor.source==target.source then return false end
    local a,b=Alive(actor.source),Alive(target.source)
    if not a or not b or GetPlayerRoutingBucket(actor.source)~=GetPlayerRoutingBucket(target.source) then return false end
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=distance^2
        and Law.Current(actor) and Law.Current(target)
end
local function Same(a,b)
    return a.source==b.source and a.characterId==b.characterId and a.sessionId==b.sessionId and a.epoch==b.epoch
end
function Law.RestrainedTarget(actor,targetSource,department)
    local target=Session(targetSource);if not target.ok then return target end
    local r=held[targetSource]
    if not r or not Same(r.target,target.value) or r.department~=department
        or not Law.Current(r.officer) or GetGameTimer()-r.startedAt>=LawConfig.Restraints.MaxSeconds*1000 then
        return Law.Err('restraint_required','A current Law restraint is required.')
    end
    if not Nearby(actor,target.value,LawConfig.Restraints.InteractionDistance) then
        return Law.Err('proximity_required','Both players must be alive and nearby in the same instance.')
    end
    return target
end
local function Authorized(actor,department,action)
    return Law.Access(actor.source,{characterId=actor.characterId,sessionId=actor.sessionId},department,action)
end
local function Warrant(actor,target,id)
    local r=Law.Call('feather-justice','GetWarrant',{actorSource=actor.source,recordId=id})
    if not r.ok then return r end
    local w=r.value
    if type(w)~='table' or w.status~='active' or w.jurisdictionId~=actor.jurisdictionId
        or type(w.subjectCharacterId)~='string' or w.subjectCharacterId:lower()~=target.characterId:lower()
        or type(w.document)~='table' or w.document.warrantType~='arrest' then
        return Law.Err('arrest_authority_required','An active arrest warrant for this subject is required.')
    end
    return Law.Ok(w)
end
local function Payload(p,fields)
    local allowed={department=true,targetSource=true};for _,field in ipairs(fields) do allowed[field]=true end
    return Law.Fields(p,allowed) and Law.Token(p.department,48)
        and Number(p.targetSource,1,65535) and p.targetSource%1==0
end
local function Locked(source,callback)
    if locks[source] then return Law.Err('interaction_busy','Another interaction is pending.') end
    locks[source]=true
    local ok,result=pcall(callback)
    locks[source]=nil
    return ok and result or Law.Err('interaction_unavailable','Interaction could not be confirmed.')
end
local function Snapshot(record)
    return {restrained=true,escortSource=record.escort and record.officer.source or nil}
end
Law.Routes['law.restraints.self.v1']={
    validate=function(p) return Law.Fields(p,{}) end,
    handler=function(_,source,context)
        local actor=Law.Actor(source,context);if not actor.ok then return actor end
        local r=held[source]
        if r and Same(r.target,actor.value) and Law.Current(r.officer) then return Law.Ok(Snapshot(r)) end
        return Law.Ok({restrained=false})
    end
}
Law.Routes['law.restraints.apply.v1']={
    validate=function(p) return Payload(p,{'warrantId'}) and Law.Uuid(p.warrantId) end,
    handler=function(p,source,context)
        return Locked(p.targetSource,function()
            local actor=Law.Access(source,context,p.department,'law.restraint.manage');if not actor.ok then return actor end
            local target=Session(p.targetSource);if not target.ok then return target end
            if not Nearby(actor.value,target.value,LawConfig.Restraints.InteractionDistance) then
                return Law.Err('proximity_required','Both players must be alive and nearby in the same instance.')
            end
            local warrant=Warrant(actor.value,target.value,p.warrantId);if not warrant.ok then return warrant end
            -- Provider calls may yield: recheck both sessions and physical presence at commit.
            if not Nearby(actor.value,target.value,LawConfig.Restraints.InteractionDistance) then return Law.Err('session_expired','Interaction changed.') end
            local previous=held[p.targetSource]
            if previous and Same(previous.target,target.value) then
                if not Same(previous.officer,actor.value) or previous.warrantId~=p.warrantId then
                    return Law.Err('restraint_conflict','Subject is already restrained by another interaction.')
                end
                return Law.Ok(Snapshot(previous)) -- retry never extends the timeout
            end
            local r={target=target.value,officer=actor.value,department=p.department,warrantId=p.warrantId,
                startedAt=GetGameTimer(),escort=false}
            held[p.targetSource]=r
            return Law.Ok(Snapshot(r))
        end)
    end
}
for _,operation in ipairs({'release','escort'}) do
    Law.Routes['law.restraints.'..operation..'.v1']={
        validate=function(p) return Payload(p,operation=='escort' and {'enabled'} or {})
            and (operation~='escort' or type(p.enabled)=='boolean') end,
        handler=function(p,source,context)
            return Locked(p.targetSource,function()
                local actor=Law.Access(source,context,p.department,'law.restraint.manage');if not actor.ok then return actor end
                local target=Session(p.targetSource);if not target.ok then return target end
                if not Nearby(actor.value,target.value,LawConfig.Restraints.InteractionDistance) then return Law.Err('proximity_required','Both players must be nearby.') end
                local r=held[p.targetSource]
                if not r or not Same(r.target,target.value) then
                    return operation=='release' and Law.Ok({restrained=false}) or Law.Err('restraint_required','Subject must be restrained.')
                end
                if r.department~=p.department then return Law.Err('department_unavailable','Interaction belongs to another department.') end
                if operation=='release' then held[p.targetSource]=nil;return Law.Ok({restrained=false}) end
                if not Same(r.officer,actor.value) then return Law.Err('restraint_conflict','Only the restraining officer can escort this subject.') end
                if p.enabled then
                    local warrant=Warrant(actor.value,target.value,r.warrantId);if not warrant.ok then return warrant end
                end
                if held[p.targetSource]~=r or not Nearby(actor.value,target.value,LawConfig.Restraints.InteractionDistance) then return Law.Err('session_expired','Interaction changed.') end
                r.escort=p.enabled
                return Law.Ok(Snapshot(r))
            end)
        end
    }
end
-- Bounded fail-open physical cleanup; never changes legal custody or a sentence.
function Law.SweepRestraints()
    for source,r in pairs(held) do
        local valid=Law.Current(r.target) and Law.Current(r.officer) and Alive(source) and Alive(r.officer.source)
            and GetGameTimer()-r.startedAt<LawConfig.Restraints.MaxSeconds*1000
        if valid then
            local officer=Authorized(r.officer,r.department,'law.restraint.manage')
            valid=officer.ok and Warrant(officer.value,r.target,r.warrantId).ok
                and Law.Current(r.target) and Law.Current(r.officer)
        end
        if held[source]==r then
            if not valid then held[source]=nil
            elseif r.escort and not Nearby(r.officer,r.target,LawConfig.Restraints.EscortDistance) then r.escort=false end
        end
    end
end
AddEventHandler('playerDropped',function() held[tonumber(source)]=nil end)
AddEventHandler('onResourceStop',function(resource)
    for _,dependency in ipairs({'bcc-law','feather-core','feather-character','feather-jobs','feather-licenses','feather-justice'}) do
        if resource==dependency then held={};return end
    end
end)
CreateThread(function()
    while true do
        local ok=pcall(Law.SweepRestraints)
        if not ok then held={} end
        Wait(2000)
    end
end)
