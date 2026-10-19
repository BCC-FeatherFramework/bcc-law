-- Isolated fixtures exercise real access, route validation, and physical state.
local checks,events,routes,now=0,{}, {},0
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local positions={[5]={x=0,y=0,z=0},[7]={x=1,y=0,z=0}}
local sessions={[5]={characterId=uuid(5),sessionId=uuid(15)},[7]={characterId=uuid(7),sessionId=uuid(17)}}
local duty,policy,status,subject,bucket,alive,hook=true,true,'active',uuid(7),0,true,nil
local env=setmetatable({},{__index=_G})
env.AddEventHandler=function(name,fn) events[name]=fn end
env.CreateThread=function() end
env.GetResourceState=function() return 'started' end
env.GetGameTimer=function() return now end
env.GetPlayerPed=function(source) return source end
env.GetEntityCoords=function(ped) return positions[ped] end
env.GetEntityHealth=function() return alive and 100 or 0 end
env.GetPlayerRoutingBucket=function(source) return source==7 and bucket or 0 end
env.exports=setmetatable({
    ['feather-core']={
        GetSessionContext=function(_,source) return sessions[source] and {ok=true,value=sessions[source]} or {ok=false} end,
        IsSessionCurrent=function(_,source,sid,cid) local s=sessions[source];return s and s.sessionId==sid and s.characterId==cid or false end,
        Authorize=function() return {ok=true,value={allowed=policy}} end,
        RegisterRpc=function(_,name,handler) routes[name]=handler;return {ok=true} end
    },
    ['feather-jobs']={CheckAssignment=function() return {ok=true,value={matched=duty}} end},
    ['feather-licenses']={CheckLicense=function() return {ok=true,value={matched=true,scopeVersion=1,scope={}}} end},
    ['feather-justice']={
        FindJurisdictionByKey=function() return {ok=true,value={status='active',recordId=uuid(30)}} end,
        GetWarrant=function()
            if hook then hook() end
            return {ok=true,value={status=status,subjectCharacterId=subject,jurisdictionId=uuid(30),document={warrantType='arrest'}}}
        end
    }
},{__call=function() end})
for _,path in ipairs({'shared/results.lua','config.lua','server/foundation.lua','server/access.lua','server/routes.lua','server/custody.lua','server/restraints.lua'}) do
    assert(loadfile(path,'t',env))()
end
local L=env.Law;L.SetState('ready','tests')
for name,spec in pairs(L.Routes) do check('register '..name,L.RegisterRoute(name,spec).ok) end
local function call(name,p,source) source=source or 5;return routes['law.restraints.'..name..'.v1'](p,source,sessions[source]) end
local function request() return {department='new_hanover',targetSource=7,warrantId=uuid(80)} end
local function state() return call('self',{},7).value end
check('restraint config valid',L.ValidateRestraintsConfig())
env.LawConfig.Restraints.MaxSeconds=0/0;check('nonfinite timeout denied',not L.ValidateRestraintsConfig());env.LawConfig.Restraints.MaxSeconds=900
check('starts unrestrained',not state().restrained)
local p=request();p.actorSource=7;check('forged actor refused',call('apply',p).code=='invalid_input')
p=request();p.targetSource=5;check('self cuff refused',call('apply',p).code=='proximity_required')
policy=false;check('policy denial prevents cuffs',call('apply',request()).code=='authorization_denied');policy=true
duty=false;check('off duty prevents cuffs',call('apply',request()).code=='duty_required');duty=true
bucket=1;check('different instances refused',call('apply',request()).code=='proximity_required');bucket=0
positions[7].x=100;check('remote cuff refused',call('apply',request()).code=='proximity_required');positions[7].x=1
alive=false;check('dead target refused',call('apply',request()).code=='proximity_required');alive=true
for _,s in ipairs({'draft','expired','served','recalled','quashed'}) do status=s;check(s..' warrant refused',call('apply',request()).code=='arrest_authority_required') end
status='active';subject=uuid(99);check('warrant subject mismatch refused',not call('apply',request()).ok);subject=uuid(7)
local nested
hook=function() hook=nil;nested=call('apply',request()) end
check('initial cuff succeeds',call('apply',request()).ok and state().restrained)
check('concurrent target mutation refused',nested.code=='interaction_busy')
check('duplicate apply returns same desired state',call('apply',request()).ok)
local change={department='new_hanover',targetSource=7,enabled=true}
check('escort starts',call('escort',change).ok and state().escortSource==5)
positions[7].x=8;L.SweepRestraints();check('distance breaks escort but keeps cuffs',state().restrained and state().escortSource==nil);positions[7].x=1
change.enabled=false;check('escort stop is idempotent',call('escort',change).ok and call('escort',change).ok)
local release={department='new_hanover',targetSource=7}
check('release explicit and idempotent',call('release',release).ok and call('release',release).ok and not state().restrained)
hook=function() sessions[7].sessionId=uuid(177) end
check('target session change during warrant read fenced',call('apply',request()).code=='session_expired');hook=nil
check('new session can be restrained explicitly',call('apply',request()).ok)
sessions[7].sessionId=uuid(178);check('old restraint never applies to reused source',not state().restrained)
check('reapply targets current session',call('apply',request()).ok)
status='recalled';L.SweepRestraints();check('warrant revocation clears physical state',not state().restrained);status='active'
call('apply',request());duty=false;L.SweepRestraints();check('duty loss clears physical state',not state().restrained);duty=true
call('apply',request());now=899000;call('apply',request());now=900000;L.SweepRestraints()
check('retries do not extend maximum restraint time',not state().restrained)
call('apply',request());events.onResourceStop('feather-justice');check('dependency stop clears physical registry',not state().restrained)
call('apply',request());env.source=7;events.playerDropped();check('disconnect clears physical registry',not state().restrained)
hook=function() positions[7].x=50 end
check('movement during authority read fenced',not call('apply',request()).ok);hook=nil;positions[7].x=1
print(('PASS Law restraints: %d checks (mock sessions/physics; no RedM acceptance)'):format(checks))
