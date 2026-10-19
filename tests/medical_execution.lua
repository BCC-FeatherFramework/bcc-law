local exportsMap,checks,caller={},0,'bcc-law'
local current,spawned=true,true
local character='9f37d250-3b6a-4c19-8e72-000000000007'
local session='9f37d250-3b6a-4c19-8e72-000000000017'
local env=setmetatable({},{__index=_G})
local function check(label,v) checks=checks+1;assert(v,label) end
env.Config={medical={enabled=true}}
env.GetInvokingResource=function() return caller end
env.RegisterCommand=function() end
env.MedicalRepository={Get=function() return {characterId=character,lifeState='alive',revision=1} end}
env.exports=setmetatable({['feather-core']={IsSessionCurrent=function(_,source,sid,cid) return current and source==7 and sid==session and cid==character end},
    ['feather-character']={GetMedicalReadySession=function() return {ok=spawned,value={characterId=character,sessionId=session}} end}},
    {__call=function(_,name,fn) exportsMap[name]=fn end})
assert(loadfile('../../[feather]/feather-medical/server/gameplay.lua','t',env))()
env.MedicalGameplay.Ready=function() return true end
local read=exportsMap.ReadLawExecutionCondition
check('Law condition reader returns only bound snapshot',read(7,{characterId=character,sessionId=session}).value.lifeState=='alive')
caller='foreign';check('other resource cannot borrow Law reader',read(7,{characterId=character,sessionId=session}).code=='forbidden');caller='bcc-law'
current=false;check('stale Medical session rejected',read(7,{characterId=character,sessionId=session}).code=='stale_session');current=true
spawned=false;check('Medical reader rejects incomplete Character spawn',read(7,{characterId=character,sessionId=session}).code=='stale_session')
print(('PASS Medical Law condition contract: %d checks (read-only mocks)'):format(checks))
