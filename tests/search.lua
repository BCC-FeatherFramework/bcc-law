local checks,registered,invoking,reads=0,{},'bcc-law',0
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local actor={source=5,characterId=uuid(5),sessionId=uuid(15),epoch=1,jurisdictionId=uuid(30)}
local target={source=7,characterId=uuid(7),sessionId=uuid(17),epoch=1}
local policy,restrained,current,status,kind,subject=true,true,true,'active','search',uuid(7)
local beforeRead,afterRead,support,receipt=nil,nil,true,false
local env=setmetatable({},{__index=_G})
assert(loadfile('shared/results.lua','t',env))()
local L=env.Law;L.Routes={}
L.Access=function() return policy and L.Ok(L.Copy(actor)) or L.Err('authorization_denied','Denied') end
L.Current=function() return current end
L.RestrainedTarget=function() return restrained and L.Ok(L.Copy(target)) or L.Err('restraint_required','Restrained target required') end
L.Call=function(resource,operation,p)
    if resource=='feather-inventory' then
        local old=invoking;invoking='bcc-law';local r=registered.InspectLawSearch(p);invoking=old;return r
    end
    if operation=='GetWarrant' then return L.Ok({status=status,subjectCharacterId=subject,jurisdictionId=uuid(30),revision=2,document={warrantType=kind}}) end
    if operation=='GetCapabilities' then return L.Ok({contract=1,features={searchWarrants=support and 1 or 0}}) end
    if operation=='GetCase' then return L.Ok({jurisdictionId=uuid(30)}) end
    if operation=='FindOperation' then return receipt and L.Ok({jurisdictionId=uuid(30)}) or L.Err('not_found','Missing') end
    if operation=='ServeWarrant' then check('search execution uses stable actor-scoped intent',p.requestId==actor.characterId..':finish-test' and p.expectedRevision==2);return L.Ok({recordId=p.recordId}) end
    if operation=='CreateWarrantDraft' then check('search type derived server side',p.warrantType=='search');return L.Ok({recordId=uuid(70)}) end
    error(operation)
end
env.GetInvokingResource=function() return invoking end
env.GetResourceState=function() return 'started' end
env.exports=setmetatable({['bcc-law']={AuthorizeInventorySearch=function(_,p)
    local old=invoking;invoking='feather-inventory';local r=registered.AuthorizeInventorySearch(p);invoking=old;return r
end}},{__call=function(_,name,fn) registered[name]=fn end})
env.Result={Ok=L.Ok,Err=function(code,message) return {ok=false,error={code=code,message=message}} end};env.InventoryReadiness={state='ready'}
env.DB={query=function(_,args)
    reads=reads+1
    check('query uses server target UUID',args[1]==target.characterId)
    if beforeRead then beforeRead() end
    local rows={}
    for i=1,26 do rows[i]={id=(args[2] or 0)+i,row_revision=2,name='item',display_name='<img onerror=x>',metadata={secret=true}} end
    if afterRead then afterRead() end
    return rows
end}
assert(loadfile('server/search.lua','t',env))()
assert(loadfile('../../[feather]/feather-inventory/server/services/law_search.lua','t',env))()
local route=L.Routes['law.search.inspect.v1']
local function request() return {department='new_hanover',targetSource=7,warrantId=uuid(80)} end
local function call(p) if not route.validate(p) then return L.Err('invalid_input','Invalid') end;return route.handler(p,5,{characterId=actor.characterId,sessionId=actor.sessionId}) end
check('search payload accepted',route.validate(request()))
local p=request();p.actorSource=99;check('actor injection rejected',not route.validate(p))
p=request();p.cursor=0/0;check('nonfinite cursor rejected',not route.validate(p))
p=request();p.targetSource=0;check('invalid source rejected',not route.validate(p))
local r=call(request());check('bounded snapshot uses 25 instances',r.ok and #r.value.items==25 and r.value.nextCursor==25)
check('metadata and inventory header are withheld',r.value.items[1].metadata==nil and r.value.inventoryId==nil)
p=request();p.cursor=25;r=call(p);check('next page uses exclusive cursor',r.ok and r.value.items[1].instanceId==26)
policy=false;local before=reads;check('policy denial avoids inventory read',not call(request()).ok and reads==before);policy=true
restrained=false;check('unrestrained subject refused',call(request()).code=='restraint_required');restrained=true
kind='arrest';check('arrest warrant does not authorize search',call(request()).code=='search_authority_required');kind='search'
status='recalled';check('recalled warrant refused',not call(request()).ok);status='active'
subject=uuid(99);check('wrong warrant subject refused',not call(request()).ok);subject=uuid(7)
afterRead=function() current=false end;check('logout during query discards snapshot',not call(request()).ok);afterRead=nil;current=true
afterRead=function() restrained=false end;check('uncuff during query discards snapshot',not call(request()).ok);afterRead=nil;restrained=true
afterRead=function() status='expired' end;check('warrant expires during read',not call(request()).ok);afterRead=nil;status='active'
afterRead=function() target.sessionId=uuid(999) end;check('source reuse after query discards snapshot',not call(request()).ok);afterRead=nil
invoking='foreign';check('foreign caller cannot inspect',not registered.InspectLawSearch({}).ok)
check('foreign caller cannot borrow search authority',not registered.AuthorizeInventorySearch({}).ok);invoking='bcc-law'
env.InventoryReadiness.state='failed';check('inventory failure flattens its nested error',call(request()).code=='not_ready');env.InventoryReadiness.state='ready'
local finish=L.Routes['law.search.finish.v1'];local execution={department='new_hanover',targetSource=7,warrantId=uuid(80),requestId='finish-test',expectedRevision=2}
check('search execution payload typed',finish.validate(execution));check('search explicitly serves its warrant',finish.handler(execution,5,{}).ok)
receipt=true;status='served';restrained=false
check('committed search retry survives served warrant and released target',finish.handler(execution,5,{}).ok);receipt=false;status='active';restrained=true
local draft=L.Routes['law.warrants.search.draft.v1']
p={department='new_hanover',caseId=uuid(1),requestId='search-test',expectedCaseRevision=1,subjectCharacterId=uuid(7),basisSummary='Basis',validForSeconds=600}
check('typed search draft accepted',draft.validate(p) and draft.handler(p,5,{}).ok)
support=false;check('older Justice fails search draft closed',draft.handler(p,5,{}).code=='search_authority_unavailable')
print(('PASS Law/Inventory read-only search: %d checks (mock policy/DB; no live acceptance)'):format(checks))
