local checks,last,current,jurisdiction,childCase=0,nil,true,nil,nil
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local env=setmetatable({},{__index=_G})
assert(loadfile('shared/results.lua','t',env))()
local L=env.Law;L.Routes={};local actor={source=5,characterId=uuid(5),sessionId=uuid(15),jurisdictionId=uuid(30)}
jurisdiction=actor.jurisdictionId;childCase=uuid(40)
L.Access=function() return L.Ok(actor) end;L.Current=function() return current end
L.Call=function(_,op,p)
    if op=='GetCase' then return L.Ok({recordId=p.recordId,jurisdictionId=jurisdiction}) end
    if op=='GetSentence' or op=='GetCharge' then return L.Ok({caseId=childCase,jurisdictionId=jurisdiction,subjectCharacterId=uuid(7)}) end
    last={operation=op,request=p};return L.Ok({recordId=uuid(50),items={}})
end
L.BookingPresence=function() return L.Ok({}) end
assert(loadfile('server/court.lua','t',env))()
local function call(name,p) local r=L.Routes['law.'..name..'.v1'];return r.validate(p) and r.handler(p,5,{}) or L.Err('invalid_input','Invalid') end
local verdict={department='new_hanover',caseId=uuid(40),requestId='verdict-test',expectedCaseRevision=1,
    subjectCharacterId=uuid(7),rulingType='verdict',summary='Court findings',findings={{chargeId=uuid(90),finding='convicted'}}}
check('verdict forwards bounded findings',call('rulings.record',verdict).ok and last.operation=='RecordRuling')
check('verdict actor and intent derived',last.request.actorSource==5 and last.request.requestId==actor.characterId..':verdict-test')
verdict.actorSource=99;check('forged judge rejected',call('rulings.record',verdict).code=='invalid_input');verdict.actorSource=nil
verdict.findings[2]=verdict.findings[1];check('duplicate charge finding rejected',call('rulings.record',verdict).code=='invalid_input');verdict.findings[2]=nil
verdict.findings[1].finding='guilty';check('unsupported verdict finding rejected',call('rulings.record',verdict).code=='invalid_input');verdict.findings[1].finding='convicted'
verdict.rulingType='dismissal';check('dismissal cannot smuggle findings',call('rulings.record',verdict).code=='invalid_input');verdict.findings=nil
check('typed dismissal accepted',call('rulings.record',verdict).ok)
local p={department='new_hanover',caseId=uuid(40),requestId='sentence-test',expectedCaseRevision=1,rulingId=uuid(50),sentenceType='custodial',terms={termSeconds=600,facilityKey='valentine'}}
check('custodial sentence contract forwarded',call('sentences.create',p).ok and last.request.terms.termSeconds==600)
p.terms.endsAt=0;check('client cannot choose authoritative deadline',call('sentences.create',p).code=='invalid_input');p.terms.endsAt=nil
p.terms.termSeconds=1;check('Justice minimum duration respected',call('sentences.create',p).code=='invalid_input');p.terms.termSeconds=600
p.sentenceType='community_service';p.terms={units=5,taskKey='valentine_maintenance'};check('service units bounded and typed',call('sentences.create',p).ok)
p.terms.units=1001;check('excess service units rejected',call('sentences.create',p).code=='invalid_input')
local change={department='new_hanover',caseId=uuid(40),recordId=uuid(50),requestId='change-test',expectedRevision=1}
check('activation reads authoritative child relation',call('sentences.activate',change).ok and last.operation=='ActivateSentence')
childCase=uuid(99);check('cross-case sentence rejected',call('sentences.activate',change).code=='not_found');childCase=uuid(40)
jurisdiction=uuid(99);check('foreign jurisdiction rejected',call('sentences.activate',change).code=='not_found');jurisdiction=actor.jurisdictionId
current=false;check('session change fences court operations',call('rulings.record',verdict).code=='session_expired');current=true
check('history uses actual nonpaginated contract',call('cases.history',{department='new_hanover',caseId=uuid(40)}).ok and last.request.cursor==nil)
check('nested routes declare bounded transport',L.Routes['law.rulings.record.v1'].maxNodes==128 and L.Routes['law.sentences.create.v1'].maxDepth==3)
print(('PASS Law court contracts: %d checks (mock Justice; no live acceptance)'):format(checks))
