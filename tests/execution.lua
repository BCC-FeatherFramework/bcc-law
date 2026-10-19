local checks,now,events,db=0,0,{},{}
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local env=setmetatable({},{__index=_G})
assert(loadfile('shared/results.lua','t',env))();assert(loadfile('config.lua','t',env))()
local L=env.Law;L.Routes={};L.Epoch=1
local actor={source=7,characterId=uuid(7),sessionId=uuid(17),epoch=1}
local current,spawned,alive,available=true,true,true,true
local sentence={recordId=uuid(50),revision=1,status='active',endsAt=60000,facilityKey='valentine'}
local service={recordId=uuid(60),revision=1,status='active',units=2,completedUnits=0,taskKey='valentine_maintenance'}
local moves,markers,deliveries={}, {},{}
local position={x=0,y=0,z=100}
local queueCalls,progressCalls=0,0
local onStore,progressResult,latestLegal=nil,nil,nil
local function copy(v) return L.Copy(v) end
L.Ready=function() return true end
L.Current=function(a) return current and a.sessionId==actor.sessionId and a.characterId==actor.characterId and a.epoch==1 end
L.Actor=function(_,ctx) return ctx and ctx.sessionId==actor.sessionId and L.Current(actor) and L.Ok(copy(actor)) or L.Err('session_expired','Stale') end
L.Call=function(resource,op,p)
    if resource=='feather-core' then return L.Ok(copy(actor)) end
    if resource=='feather-character' then return spawned and L.Ok(copy(actor)) or L.Err('not_ready','Not spawned') end
    if op=='GetCapabilities' then return L.Ok({contract=1,features={subjectStatus=1,sentences=1,sentenceProgress=1}}) end
    if not available then return L.Err('dependency_unavailable','Unavailable') end
    if op=='GetSubjectLegalStatus' then
        if latestLegal then latestLegal() end
        return L.Ok({subjectCharacterId=actor.characterId,serverTime=now,custodialSentence=copy(sentence),communityService=service and {copy(service)} or {}})
    end
    if op=='RecordSentenceProgress' then
        progressCalls=progressCalls+1
        check('progress carries no forged player actor',p.actorSource==nil and p.requestId=='law:service:'..uuid(60)..':1')
        return progressResult or L.Ok({})
    end
    error(op)
end
L.ExecutionStore={state='ready',Get=function(id) if onStore then onStore() end;return copy(markers[id]) end,
    Place=function(id,sid,key) markers[id]={sentence_id=sid,facility_key=key} end,
    Clear=function(id) markers[id]=nil end,
    Queue=function(id,s)
        queueCalls=queueCalls+1
        local key='law:service:'..s.recordId..':'..(s.completedUnits+1)
        deliveries[key]=deliveries[key] or {request_id=key,character_id=id,sentence_id=s.recordId,expected_revision=s.revision,completed_units=s.completedUnits+1,state='pending'}
    end,
    HasOutstanding=function(id,sid) for _,v in pairs(deliveries) do if v.character_id==id and v.sentence_id==sid and (v.state=='pending' or v.state=='review_required') then return true end end;return false end,
    Pending=function() local r={};for _,d in pairs(deliveries) do if d.state=='pending' then r[#r+1]=copy(d) end end;return r end,
    Mark=function(id,state,code) deliveries[id].state=state;deliveries[id].last_code=code end}
env.GetGameTimer=function() return now end
env.GetCurrentResourceName=function() return 'bcc-law' end
env.GetResourceState=function(resource) return resource=='feather-medical' and 'missing' or 'started' end
env.GetPlayerPed=function() return 7 end;env.GetEntityHealth=function() return alive and 100 or 0 end
env.GetEntityCoords=function() return copy(position) end
env.SetEntityCoords=function(_,x,y,z) position={x=x,y=y,z=z};moves[#moves+1]=copy(position) end
env.CreateThread=function() end;env.AddEventHandler=function(name,fn) events[name]=fn end
assert(loadfile('server/execution.lua','t',env))()
local function refresh() L.RefreshExecution(7) end
local function own() return L.Routes['law.execution.self.v1'].handler({},7,actor) end
check('execution config valid',L.ValidateExecutionConfig())
local f=env.LawConfig.Execution.Facilities.valentine
local savedExit=copy(f.exit);f.exit=copy(f.entrance);check('release point must be outside confinement',not L.ValidateExecutionConfig());f.exit=savedExit
refresh();check('active sentence places and persists marker',#moves==1 and markers[actor.characterId].sentence_id==uuid(50))
check('own status uses Justice deadline',own().value.confined and own().value.remainingMs==60000)
position.x=position.x+50;now=2000;refresh();check('leaving boundary re-confines without adding time',#moves==2 and own().value.remainingMs==58000)
spawned=false;position={x=0,y=0,z=0};refresh();check('incomplete Character spawn does not teleport',#moves==2);spawned=true
alive=false;refresh();check('death postpones physical effects without clearing marker',#moves==2 and markers[actor.characterId]~=nil);alive=true
available=false;refresh();check('Justice outage does not invent release',#moves==2 and not own().ok);available=true
position=copy(f.entrance);now=60000;refresh();check('offline UTC expiry releases at configured exit',#moves==3 and not own().value.confined)
now=62000;refresh();check('confirmed physical exit clears marker',markers[actor.characterId]==nil)
-- A stored placement from a prior resource lifetime recovers without an in-memory cache.
markers[actor.characterId]={sentence_id=uuid(50),facility_key='valentine'};position=copy(f.entrance);sentence=nil
assert(loadfile('server/execution.lua','t',env))();now=64000;refresh();check('restart recovers expired placement marker',#moves==4)
sentence={recordId=uuid(50),status='active',revision=1,endsAt=100000,facilityKey='unknown'}
refresh();check('unknown facility fails closed without arbitrary teleport',#moves==4 and not own().ok)
sentence={recordId=uuid(50),status='active',revision=1,endsAt=100000,facilityKey='valentine'}
position={x=0,y=0,z=0};onStore=function() current=false end;refresh();check('session change across marker read fences teleport',#moves==4);onStore=nil;current=true
latestLegal=function() sentence=nil end;refresh();check('authority reread prevents stale placement',#moves==4);latestLegal=nil
sentence=nil;markers={};position=copy(env.LawConfig.Execution.Tasks.valentine_maintenance)
local start=L.Routes['law.service.start.v1']
check('service request rejects claimed progress',not start.validate({sentenceId=uuid(60),completedUnits=100}))
check('own active service starts at configured site',start.handler({sentenceId=uuid(60)},7,actor).ok)
for _=1,14 do now=now+2000;refresh() end
check('insufficient observed work creates no unit',queueCalls==0)
now=now+2000;refresh();check('completed live dwell queues one durable intent',queueCalls==1)
L.DeliverServiceProgress();check('confirmed Justice progress completes delivery',progressCalls==1 and deliveries['law:service:'..uuid(60)..':1'].state=='confirmed')
L.DeliverServiceProgress();check('confirmed delivery not submitted twice',progressCalls==1)
start.handler({sentenceId=uuid(60)},7,actor);position.x=position.x+20;now=now+2000;refresh();position=copy(env.LawConfig.Execution.Tasks.valentine_maintenance)
now=now+30000;refresh();check('leaving/reconnect/elapsed time does not fabricate tasks',queueCalls==1)
start.handler({sentenceId=uuid(60)},7,actor);now=now+10000;refresh();check('unobserved server gap interrupts work',queueCalls==1)
position.x=0;check('remote service start refused',start.handler({sentenceId=uuid(60)},7,actor).code=='proximity_required')
local pending=deliveries['law:service:'..uuid(60)..':1'];pending.state='pending'
available=false;L.DeliverServiceProgress();check('provider outage retains pending intent',pending.state=='pending');available=true
progressResult=L.Err('revision_conflict','Changed');service.completedUnits=1;L.DeliverServiceProgress();check('cumulative facts reconcile superseded intent',pending.state=='superseded')
actor.sessionId=uuid(177);check('old snapshot cannot leak through source reuse',not own().ok)
print(('PASS Law jail/service execution: %d checks (mock physics/storage; no live acceptance)'):format(checks))
