local checks,claims,quota,deliveries=0,{}, {},{}
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local env=setmetatable({},{__index=_G})
assert(loadfile('shared/results.lua','t',env))();assert(loadfile('config.lua','t',env))()
local L=env.Law;L.Routes={}
local actor={source=5,characterId=uuid(5),sessionId=uuid(15)}
local current,qualified,weaponReady,providerReady,period=true,true,false,true,'2026-10-19'
local station=env.LawConfig.Armory.Stations.valentine
local position={x=station.x,y=station.y,z=station.z}
local documents,n={},0
env.json={encode=function(v) n=n+1;local key='document:'..n;documents[key]=L.Copy(v);return key end,decode=function(k) return L.Copy(documents[k]) end}
env.GetResourceState=function() return 'started' end
env.GetPlayerPed=function() return 5 end;env.GetEntityHealth=function() return 100 end
env.GetEntityCoords=function() return position end
L.Ready=function() return true end
L.Current=function() return current end
L.Access=function() return qualified and L.Ok(actor) or L.Err('qualification_required','Denied') end
env.exports={['feather-inventory']={initiate=function() return {Items={GetDefinitions=function() return L.Ok({{id=10,name='water',instance_mode='stack',type='item'}}) end}} end},
    ['feather-weapons']={initiate=function() return {GetCapabilities=function() return {ready=true,features={secureIssuance=weaponReady,idempotentIssuance=weaponReady,issuancePayloadBinding=weaponReady}} end} end}}
local grants=0
L.Call=function(resource,op,p,ctx)
    if op=='GetHealth' then return L.Ok({state='ready'}) end
    if not providerReady then return L.Err('dependency_unavailable','Provider unavailable') end
    grants=grants+1
    local id=p.grantId or p.requestId
    if not deliveries[id] then deliveries[id]={itemId=grants,characterId=p.characterId} end
    if resource=='feather-weapons' then check('weapons use owner issuer and self character',op=='IssueWeapon' and p.definitionId=='revolver_cattleman' and p.purpose=='job_issue' and ctx.actorCharacterId==actor.characterId) end
    return L.Ok(deliveries[id])
end
L.ExecutionStore={state='ready',ArmoryGet=function(id) return claims[id] end,
    ArmoryReserve=function(a,id,key,itemKey,spec)
        local quotaKey=a.characterId..':'..key..':'..itemKey..':'..period
        if claims[id] then return claims[id] end
        if quota[quotaKey] then return nil end
        quota[quotaKey]=true
        claims[id]={request_id=id,character_id=a.characterId,station_key=key,item_key=itemKey,period_key=period,spec_json=env.json.encode(spec)}
        return claims[id]
    end,
    ArmoryConfirm=function(id,result) claims[id].result_json=env.json.encode(result) end,
    ArmoryClaims=function(char,key)
        local rows={};for _,r in pairs(claims) do if r.character_id==char and r.station_key==key then rows[#rows+1]={request_id=r.request_id,item_key=r.item_key,period_key=r.period_key,pending=r.result_json and 0 or 1} end end;return rows
    end}
assert(loadfile('server/armory.lua','t',env))()
local function payload(id,itemKey) return {department='new_hanover',stationKey='valentine',itemKey=itemKey or 'water',requestId=id} end
local function call(op,p) local r=L.Routes['law.armory.'..op..'.v1'];return r.validate(p) and r.handler(p,5,{}) or L.Err('invalid_input','Invalid') end
check('armory config valid',L.ValidateArmoryConfig())
station.items.cattleman.quantity=2;check('weapon quantity cannot exceed one',not L.ValidateArmoryConfig());station.items.cattleman.quantity=1
local p=payload('one');p.characterId=uuid(99);check('target character injection rejected',call('claim',p).code=='invalid_input')
qualified=false;check('unqualified actor cannot claim',not call('claim',payload('one')).ok and grants==0);qualified=true
position.x=position.x+100;check('remote claim denied before reservation',call('claim',payload('one')).code=='proximity_required' and claims[actor.characterId..':one']==nil);position.x=station.x
local r=call('claim',payload('one'));check('ordinary item claim confirmed',r.ok and r.value.characterId==actor.characterId and grants==1)
position.x=position.x+100;check('confirmed receipt replay needs no new physical effect',call('claim',payload('one')).ok and grants==1);position.x=station.x
check('new ID cannot bypass daily quota',call('claim',payload('two')).code=='quota_exhausted' and grants==1)
period='2026-10-20';check('midnight replay stays bound to original intent',call('claim',payload('one')).ok and grants==1 and claims[actor.characterId..':one'].period_key=='2026-10-19')
check('new UTC period permits one distinct allocation',call('claim',payload('two')).ok and grants==2)
check('changed item under same ID conflicts',call('claim',payload('one','cattleman')).code=='idempotency_conflict')
check('native alpha without secure issuance is unavailable',call('claim',payload('weapon','cattleman')).code=='weapons_unavailable')
weaponReady=true;check('ready weapon provider receives typed issuance',call('claim',payload('weapon','cattleman')).ok)
period='2026-10-21';providerReady=false
check('lost/unavailable provider leaves recoverable quota intent',call('claim',payload('pending')).code=='dependency_unavailable' and claims[actor.characterId..':pending']~=nil)
local history=call('claims',{department='new_hanover',stationKey='valentine'});local found=false
for _,item in ipairs(history.value.items) do if item.requestId=='pending' and item.pending then found=true end end
check('pending claim visible by original raw request ID',found)
providerReady=true;check('same pending intent recovers delivery',call('claim',payload('pending')).ok)
current=false;local count=grants;check('session change fences claim',call('claim',payload('stale')).code=='session_expired' and grants==count)
print(('PASS Law armory workflows: %d checks (mock owner APIs/quota store)'):format(checks))
