local checks,exposed,commands=0,{},{}
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local env=setmetatable({},{__index=_G})
assert(loadfile('shared/results.lua','t',env))();assert(loadfile('config.lua','t',env))()
local L=env.Law;L.Routes={}
local actor={source=5,characterId=uuid(5),sessionId=uuid(15),epoch=1,jurisdictionId=uuid(30)}
local target={source=7,characterId=uuid(7),sessionId=uuid(17),epoch=1}
local allowed,current,restrained,ready,linkAllowed,inventoryAllowed=true,true,true,true,true,true
local status,kind,subject,warrantCase='active','seizure',target.characterId,uuid(40)
local jurisdiction,linkRequest,lastInventory=actor.jurisdictionId,nil,nil
local locker=env.LawConfig.Evidence.Lockers.valentine
local coords={x=locker.x,y=locker.y,z=locker.z}
env.GetPlayerPed=function() return 5 end;env.GetEntityCoords=function() return coords end
local caller='feather-inventory';env.GetInvokingResource=function() return caller end
env.exports=setmetatable({},{__call=function(_,name,fn) exposed[name]=fn end})
env.RegisterCommand=function(name,fn) commands[name]=fn end;env.print=function() end
L.Ready=function() return true end
L.Access=function() return allowed and L.Ok(L.Copy(actor)) or L.Err('authorization_denied','Denied') end
L.Current=function() return current end
L.RestrainedTarget=function() return restrained and L.Ok(L.Copy(target)) or L.Err('restraint_required','Denied') end
local transfer={requestId=actor.characterId..':collect-test',caseId=uuid(40),subjectCharacterId=target.characterId,itemId=20,itemName='test_item',description='Description'}
L.Call=function(resource,operation,p)
    if resource=='feather-inventory' then
        lastInventory={operation=operation,request=p}
        if operation=='GetLawEvidenceCapabilities' then return L.Ok({contract=1,state='ready',transfers=1}) end
        if not inventoryAllowed then return {ok=false,error={code='guard_denied',message='Blocked'}} end
        if operation=='CollectLawEvidence' or operation=='GetLawEvidenceReceipt' then return L.Ok(L.Copy(transfer)) end
        if operation=='SetupLawEvidenceLocker' then return exposed.AuthorizeEvidenceOperation('setup',p) end
        return L.Ok({items={}})
    end
    if operation=='GetCapabilities' then return L.Ok({contract=1,features={evidenceLinks=ready and 1 or 0,evidenceGuard=ready and 1 or 0}}) end
    if operation=='GetCase' then return L.Ok({recordId=uuid(40),jurisdictionId=jurisdiction}) end
    if operation=='GetWarrant' then return L.Ok({status=status,caseId=warrantCase,subjectCharacterId=subject,jurisdictionId=jurisdiction,document={warrantType=kind}}) end
    if operation=='LinkEvidence' then linkRequest=p;return linkAllowed and L.Ok({recordId=uuid(99),caseId=uuid(40)}) or L.Err('revision_conflict','Changed') end
    if operation=='RecordEvidenceDisposition' then return L.Ok({recordId=p.recordId,status='disposed'}) end
    if operation=='ListCaseEvidence' then return L.Ok({items={}}) end
    error(operation)
end
assert(loadfile('server/evidence.lua','t',env))()
local function payload() return {department='new_hanover',caseId=uuid(40),expectedCaseRevision=1,targetSource=7,warrantId=uuid(80),itemId=20,itemRevision=3,lockerKey='valentine',description='Description',requestId='collect-test'} end
local function internal() local p=payload();p.actorSource=5;p.characterId=actor.characterId;p.sessionId=actor.sessionId;p.requestId=actor.characterId..':'..p.requestId;return p end
local function auth() return exposed.AuthorizeEvidenceOperation('collect',internal()) end
local function call(name,p) local r=L.Routes['law.evidence.'..name..'.v1'];return r.validate(p) and r.handler(p,5,{}) or L.Err('invalid_input','Invalid') end
check('evidence config valid',L.ValidateEvidenceConfig())
locker.radius=0/0;check('invalid locker coordinates/radius denied',not L.ValidateEvidenceConfig());locker.radius=3
check('configured locker proximity accepted',auth().ok)
coords.x=coords.x+10;check('remote locker rejected',auth().code=='proximity_required');coords.x=locker.x
restrained=false;check('unrestrained subject rejected',auth().code=='restraint_required');restrained=true
for _,w in ipairs({'arrest','search','summons'}) do kind=w;check(w..' is not seizure authority',auth().code=='seizure_authority_required') end;kind='seizure'
status='served';check('served seizure warrant rejected',auth().code=='seizure_authority_required');status='active'
subject=uuid(77);check('wrong seizure subject rejected',auth().code=='seizure_authority_required');subject=target.characterId
warrantCase=uuid(77);check('cross-case seizure rejected',auth().code=='seizure_authority_required');warrantCase=uuid(40)
ready=false;check('missing evidence guard blocks collection',auth().code=='evidence_unavailable');ready=true
caller='foreign';check('foreign callback caller rejected',auth().code=='authorization_denied');caller='feather-inventory'
allowed=false;check('missing officer policy rejected',auth().code=='authorization_denied');allowed=true
current=false;check('changed session rejected',auth().code=='session_expired');current=true
local p=payload();p.actorSource=99;check('client actor injection refused',call('collect',p).code=='invalid_input')
p=payload();p.itemRevision=-1;check('invalid revision refused',call('collect',p).code=='invalid_input')
local r=call('collect',payload())
check('collection links confirmed transfer',r.ok and r.value.transfer.itemId==20 and r.value.link.recordId==uuid(99))
check('collection derives subject from receipt',linkRequest.subjectCharacterId==target.characterId and linkRequest.evidenceRef=='20')
check('link intent stable and actor-scoped',linkRequest.requestId==actor.characterId..':collect-test:link')
check('Inventory request actor bound',lastInventory.request.characterId==actor.characterId and lastInventory.request.sessionId==actor.sessionId)
linkAllowed=false;r=call('collect',payload());check('link failure explicitly preserves collected state',r.code=='evidence_link_pending' and r.details.linkCode=='revision_conflict');linkAllowed=true
restrained=false;check('historical transfer replay does not need target presence in Law',call('collect',payload()).ok);restrained=true
inventoryAllowed=false;check('nested Inventory guard error normalized',call('collect',payload()).code=='guard_denied');inventoryAllowed=true
local attach={department='new_hanover',caseId=uuid(40),transferRequestId=transfer.requestId,requestId='new-link-intent',expectedCaseRevision=2}
check('explicit fresh link intent accepts confirmed transfer',call('attach',attach).ok and linkRequest.expectedCaseRevision==2 and linkRequest.requestId==actor.characterId..':new-link-intent')
local before=lastInventory
r=call('disposition',{department='new_hanover',caseId=uuid(40),recordId=uuid(99),expectedRevision=1,requestId='dispose',disposition='returned'})
check('legal disposition does not call Inventory',r.ok and lastInventory==before)
check('locker list exposes only label/key',call('lockers',{department='new_hanover'}).value.items[1].x==nil)
check('setup requires explicit console invocation',not exposed.AuthorizeEvidenceOperation('setup',{lockerKey='valentine'}).ok)
commands.LawSetupEvidenceLockers(5);check('player cannot set up lockers',not exposed.AuthorizeEvidenceOperation('setup',{lockerKey='valentine'}).ok)
commands.LawSetupEvidenceLockers(0);check('console setup uses owner export',lastInventory.operation=='SetupLawEvidenceLocker')
check('setup authorization removed afterward',not exposed.AuthorizeEvidenceOperation('setup',{lockerKey='valentine'}).ok)
print(('PASS Law evidence routes/authority: %d checks (mock providers; no live acceptance)'):format(checks))
