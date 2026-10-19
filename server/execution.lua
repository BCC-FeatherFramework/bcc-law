local snapshots,tasks,busy,characters={},{},{},{}
function Law.ExecutionAvailable()
    if not Law.Ready() or Law.ExecutionStore.state~='ready' then return false end
    local r=Law.Call('feather-justice','GetCapabilities')
    return r.ok and type(r.value)=='table' and r.value.contract==1 and type(r.value.features)=='table'
        and r.value.features.subjectStatus==1 and r.value.features.sentences==1 and r.value.features.sentenceProgress==1
end
local function Number(v,a,b) return type(v)=='number' and v==v and v>=a and v<=b end
local function Point(p) return type(p)=='table' and Number(p.x,-100000,100000) and Number(p.y,-100000,100000) and Number(p.z,-10000,10000) end
local function Distance(a,b) return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
function Law.ValidateExecutionConfig()
    local c=LawConfig.Execution
    if type(c)~='table' or not Law.Token(c.DefaultFacility,64) or type(c.Facilities)~='table' or type(c.Tasks)~='table' then return false end
    local count=0
    for key,f in pairs(c.Facilities) do
        count=count+1
        if not Law.Token(key,64) or not Point(f.entrance) or not Point(f.exit) or not Number(f.radius,1,600)
            or Distance(f.entrance,f.exit)<=f.radius^2 then return false end
    end
    if count>32 or not c.Facilities[c.DefaultFacility] then return false end
    count=0
    for key,t in pairs(c.Tasks) do
        count=count+1
        if not Law.Token(key,64) or not Law.Text(t.label,100) or not Point(t) or not Number(t.radius,0.5,5)
            or not Number(t.seconds,30,300) or t.seconds%1~=0 then return false end
    end
    return count<=32
end
local function Same(a,b) return a.characterId==b.characterId and a.sessionId==b.sessionId and a.epoch==b.epoch end
function Law.ExecutionActor(source)
    local context=Law.Call('feather-core','GetSessionContext',source)
    if not context.ok then return context end
    local actor=Law.Actor(source,context.value);if not actor.ok then return actor end
    local spawned=Law.Call('feather-character','GetMedicalReadySession',source)
    if not spawned.ok or not Same(actor.value,{characterId=spawned.value.characterId,sessionId=spawned.value.sessionId,epoch=Law.Epoch}) then
        return Law.Err('not_spawned','Character spawn is not complete.')
    end
    return actor
end
local function Alive(actor)
    local ped=GetPlayerPed(actor.source)
    if not ped or ped==0 or GetEntityHealth(ped)<=0 then return nil end
    local state=GetResourceState('feather-medical')
    if state~='missing' then
        if state~='started' then return nil end
        local ok,health=pcall(function() return exports['feather-medical']:GetHealth() end)
        if not ok or type(health)~='table' then return nil end
        if health.enabled~=false then
            local r=Law.Call('feather-medical','ReadLawExecutionCondition',actor.source,{characterId=actor.characterId,sessionId=actor.sessionId})
            if not r.ok or r.value.lifeState~='alive' then return nil end
        end
    end
    local p=GetEntityCoords(ped)
    return Point(p) and p or nil
end
local function Status(actor)
    local result=Law.Call('feather-justice','GetSubjectLegalStatus',{subjectCharacterId=actor.characterId})
    if not Law.Current(actor) then return Law.Err('session_expired','Character changed.') end
    if not result.ok then return result end
    local v=result.value
    if type(v)~='table' or type(v.subjectCharacterId)~='string' or v.subjectCharacterId:lower()~=actor.characterId:lower()
        or not Number(v.serverTime,0,9007199254740990) or type(v.communityService)~='table' then
        return Law.Err('invalid_legal_status','Justice returned no valid status.')
    end
    return result
end
local function Teleport(actor,p,expectedSentenceId)
    if not Law.Current(actor) or not Alive(actor) then return false end
    local legal=Status(actor);if not legal.ok then return false end
    local s=legal.value.custodialSentence
    local active=s and s.status=='active' and Number(s.endsAt,0,9007199254740990) and legal.value.serverTime<s.endsAt
    if expectedSentenceId then
        if not active or s.recordId~=expectedSentenceId then return false end
    elseif active then return false end
    if not Law.Current(actor) then return false end
    local ped=GetPlayerPed(actor.source)
    SetEntityCoords(ped,p.x,p.y,p.z,false,false,false,false)
    return true
end
local function ServiceTask(actor,status,position)
    local task=tasks[actor.source];if not task then return nil end
    if not Same(task.actor,actor) then tasks[actor.source]=nil;return nil end
    local sentence
    for _,s in ipairs(status.communityService) do if s.recordId==task.sentenceId then sentence=s end end
    if not sentence or sentence.status~='active' or sentence.revision~=task.revision or sentence.completedUnits~=task.completedUnits then
        tasks[actor.source]=nil;return nil
    end
    local cfg=LawConfig.Execution.Tasks[sentence.taskKey]
    if not cfg or not position or Distance(position,cfg)>cfg.radius^2 then tasks[actor.source]=nil;return nil end
    local now=GetGameTimer();local elapsed=now-task.lastAt
    -- Only continuously observed live presence counts, never offline elapsed time.
    if elapsed<0 or elapsed>5000 then tasks[actor.source]=nil;return nil end
    task.elapsed=task.elapsed+elapsed;task.lastAt=now
    if task.elapsed>=cfg.seconds*1000 then
        Law.ExecutionStore.Queue(actor.characterId,sentence)
        tasks[actor.source]=nil
        return {state='delivery_pending'}
    end
    return {state='working',label=cfg.label,remainingMs=cfg.seconds*1000-task.elapsed}
end
function Law.RefreshExecution(source)
    if busy[source] then return end
    busy[source]=true
    local owned
    local ok,err=pcall(function()
        local a=Law.ExecutionActor(source);if not a.ok then snapshots[source]=nil;tasks[source]=nil;return end
        local actor=a.value
        if characters[actor.characterId] then return end
        owned=actor.characterId;characters[owned]=true
        local result=Status(actor);if not result.ok then snapshots[source]=nil;tasks[source]=nil;return end
        local status=result.value
        local position=Alive(actor)
        local sentence=status.custodialSentence
        if sentence and (not Law.Uuid(sentence.recordId) or (sentence.status~='active' and sentence.status~='suspended')
            or (sentence.status=='active' and not Number(sentence.endsAt,0,9007199254740990))) then
            snapshots[source]=nil;tasks[source]=nil;return
        end
        local active=sentence and sentence.status=='active' and status.serverTime<sentence.endsAt
        local marker=Law.ExecutionStore.Get(actor.characterId)
        if not Law.Current(actor) then return end
        if active then
            local key=sentence.facilityKey or LawConfig.Execution.DefaultFacility
            local facility=LawConfig.Execution.Facilities[key]
            if not facility then snapshots[source]=nil;tasks[source]=nil;return end
            if position then
                if not marker or marker.sentence_id~=sentence.recordId or marker.facility_key~=key then
                    Law.ExecutionStore.Place(actor.characterId,sentence.recordId,key)
                end
                if Distance(position,facility.entrance)>facility.radius^2 then Teleport(actor,facility.entrance,sentence.recordId) end
            end
        elseif marker and position then
            local facility=LawConfig.Execution.Facilities[marker.facility_key]
            if facility then
                if Distance(position,facility.entrance)<=facility.radius^2 then Teleport(actor,facility.exit)
                elseif Law.Current(actor) then Law.ExecutionStore.Clear(actor.characterId) end
            end
        end
        if not Law.Current(actor) then return end
        local safe={confined=active==true,remainingMs=active and sentence.endsAt-status.serverTime or 0,
            sentenceId=sentence and sentence.recordId or nil,communityService={}}
        for _,s in ipairs(status.communityService) do
            if s.status=='active' then
                local cfg=LawConfig.Execution.Tasks[s.taskKey]
                safe.communityService[#safe.communityService+1]={recordId=s.recordId,units=s.units,completedUnits=s.completedUnits,
                    taskKey=s.taskKey,label=cfg and cfg.label or s.taskKey,available=cfg~=nil,x=cfg and cfg.x,y=cfg and cfg.y,z=cfg and cfg.z}
            end
        end
        safe.task=ServiceTask(actor,status,position)
        snapshots[source]={actor=actor,value=safe,at=GetGameTimer()}
    end)
    if owned then characters[owned]=nil end
    busy[source]=nil
    if not ok then snapshots[source]=nil;tasks[source]=nil;return Law.Err('execution_unavailable','Physical execution could not be confirmed.') end
    return err
end
function Law.DeliverServiceProgress()
    for _,row in ipairs(Law.ExecutionStore.Pending()) do
        local r=Law.Call('feather-justice','RecordSentenceProgress',{recordId=row.sentence_id,expectedRevision=tonumber(row.expected_revision),
            completedUnits=tonumber(row.completed_units),requestId=row.request_id,reasonCode='law.service.task_completed'})
        if r.ok then Law.ExecutionStore.Mark(row.request_id,'confirmed',nil)
        elseif r.code=='revision_conflict' or r.code=='progress_not_increasing' or r.code=='invalid_transition' then
            -- Do not change the original intent/revision; reconcile cumulative facts.
            local status=Law.Call('feather-justice','GetSubjectLegalStatus',{subjectCharacterId=row.character_id})
            local satisfied=false
            if status.ok then for _,s in ipairs(status.value.communityService or {}) do
                if s.recordId==row.sentence_id and s.completedUnits>=tonumber(row.completed_units) then satisfied=true end
            end end
            Law.ExecutionStore.Mark(row.request_id,satisfied and 'superseded' or 'review_required',r.code)
        end
    end
end
Law.Routes['law.execution.self.v1']={
    validate=function(p) return Law.Fields(p,{}) end,
    handler=function(_,source,context)
        local a=Law.Actor(source,context);if not a.ok then return a end
        local spawned=Law.ExecutionActor(source)
        if not spawned.ok or not Same(a.value,spawned.value) then return Law.Err('not_spawned','Character spawn is not complete.') end
        local r=snapshots[source]
        if not r or not Same(a.value,r.actor) or GetGameTimer()-r.at>5000 then return Law.Err('execution_unavailable','Legal status is unavailable.') end
        local value=Law.Copy(r.value);value.remainingMs=math.max(0,value.remainingMs-(GetGameTimer()-r.at))
        return Law.Ok(value)
    end
}
Law.Routes['law.service.start.v1']={
    validate=function(p) return Law.Fields(p,{sentenceId=true}) and Law.Uuid(p.sentenceId) end,
    handler=function(p,source,context)
        if Law.ExecutionStore.state~='ready' then return Law.Err('not_ready','Execution storage unavailable.') end
        local a=Law.Actor(source,context);if not a.ok then return a end
        local spawned=Law.ExecutionActor(source)
        if not spawned.ok or not Same(a.value,spawned.value) then return Law.Err('not_spawned','Character spawn is not complete.') end
        local status=Status(a.value);if not status.ok then return status end
        local position=Alive(a.value);if not position then return Law.Err('interaction_unavailable','Live character required.') end
        for _,s in ipairs(status.value.communityService) do
            if s.recordId==p.sentenceId and s.status=='active' then
                if Law.ExecutionStore.HasOutstanding(a.value.characterId,s.recordId) then return Law.Err('progress_pending','Previous task delivery needs confirmation or review.') end
                local cfg=LawConfig.Execution.Tasks[s.taskKey]
                if not cfg or Distance(position,cfg)>cfg.radius^2 then return Law.Err('proximity_required','Go to the configured work site.') end
                if not Law.Current(a.value) then return Law.Err('session_expired','Character changed.') end
                tasks[source]={actor=a.value,sentenceId=s.recordId,revision=s.revision,completedUnits=s.completedUnits,lastAt=GetGameTimer(),elapsed=0}
                return Law.Ok({started=true,label=cfg.label,seconds=cfg.seconds})
            end
        end
        return Law.Err('not_found','Active service sentence unavailable.')
    end
}
AddEventHandler('playerDropped',function() snapshots[tonumber(source)]=nil;tasks[tonumber(source)]=nil end)
AddEventHandler('onResourceStop',function(resource)
    for _,r in ipairs({'feather-core','feather-character','feather-justice','feather-medical',GetCurrentResourceName()}) do
        if resource==r then snapshots={};tasks={};return end
    end
end)
CreateThread(function()
    while true do
        if Law.ExecutionAvailable() then
            for _,source in ipairs(GetPlayers()) do
                local target=tonumber(source)
                CreateThread(function() Law.RefreshExecution(target) end)
            end
            pcall(Law.DeliverServiceProgress)
        end
        Wait(2000)
    end
end)
