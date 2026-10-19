local registered, caller, checks = {}, 'bcc-law', 0
local function uuid(number)
    local key=({[1]='ACTOR',[44]='SUBJECT',[45]='OTHER'})[number]
    return (key and os.getenv('FEATHER_TEST_'..key..'_UUID')) or ('8f37d250-3b6a-4c19-8e72-%012x'):format(number)
end
local context={characterId=uuid(1),sessionId=uuid(2)}
local current,job,license,policy,jurisdiction,available=true,true,true,true,true,true
local licenseScope={}
local onCall, lastOpen
local caseJurisdiction,childCase=uuid(3),uuid(10)
local legalDispatches={}
exports=setmetatable({
    ['feather-core']={
        GetSessionContext=function() return {ok=true,value={characterId=context.characterId,sessionId=context.sessionId}} end,
        IsSessionCurrent=function() return current end,
        Authorize=function() return {ok=true,value={allowed=policy}} end,
        RegisterRpc=function(_,name,handler,options) registered[name]={handler=handler,options=options};return {ok=true,value={}} end
    },
    ['feather-jobs']={CheckAssignment=function(_,request)
        assert(request.characterId==context.characterId and request.jobKey=='police')
        assert(request.activeOnly==true and request.dutyState=='on_duty')
        if onCall then onCall('jobs') end
        return {ok=true,value={matched=job}}
    end},
    ['feather-licenses']={CheckLicense=function(_,request)
        assert(request.holderType=='character' and request.holderId==context.characterId and request.licenseKey=='peace_officer')
        if onCall then onCall('license') end
        return {ok=true,value={matched=license,scopeVersion=1,scope=licenseScope}}
    end},
    ['feather-justice']={
        FindJurisdictionByKey=function(_,request)
            assert(request.recordKey=='bcc-law:new_hanover' and request.actorSource==5)
            return jurisdiction and {ok=true,value={recordId=uuid(3),status='active'}} or {ok=false,code='not_found'}
        end,
        ListCases=function(_,request)
            assert(request.actorSource==5 and request.jurisdictionId==uuid(3) and request.limit==25)
            if onCall then onCall('list') end
            return {ok=true,value={items={}}}
        end,
        OpenCase=function(_,request)
            lastOpen=request
            if onCall then onCall('open') end
            return {ok=true,value={recordId=uuid(4)}}
        end,
        GetCase=function(_,request)
            if onCall then onCall('case') end
            return {ok=true,value={recordId=request.recordId,jurisdictionId=caseJurisdiction}}
        end,
        GetCitation=function() return {ok=true,value={caseId=childCase,jurisdictionId=caseJurisdiction}} end,
        GetCharge=function()
            if onCall then onCall('child') end
            return {ok=true,value={caseId=childCase,jurisdictionId=caseJurisdiction}}
        end,
        GetWarrant=function()
            if onCall then onCall('child') end
            return {ok=true,value={caseId=childCase,jurisdictionId=caseJurisdiction}}
        end
    }
},{__call=function(_,name,handler) registered[name]=handler end})
GetResourceState=function() return available and 'started' or 'stopped' end
GetGameTimer=function() return 0 end
dofile('shared/results.lua');dofile('config.lua');dofile('server/foundation.lua')
AddEventHandler=function() end;CreateThread=function() end;RegisterCommand=function() end
dofile('server/access.lua');dofile('server/routes.lua');dofile('server/legal_routes.lua');dofile('server/custody.lua');dofile('server/restraints.lua');dofile('server/search.lua');dofile('server/evidence.lua');dofile('server/court.lua');dofile('server/execution_store.lua');dofile('server/execution.lua');dofile('server/armory.lua');Law.SetState('ready','tests')
for _,name in ipairs({'ProposeCharge','CreateWarrantDraft','ListCharges','ListCaseWarrants','ListActiveWarrants',
    'AddCaseParty','RemoveCaseParty','ListCaseParties','UpdateCaseSummary','TransitionCase','ListStatutes','RequestCitation','CancelCitation','ListCaseCitations','ReserveCustodyBooking','ConfirmCustodyBooking','ReleaseCustody','ListCaseCustody',
    'FileCharge','DisposeCharge','IssueWarrant','ServeWarrant','RecallWarrant','QuashWarrant'}) do
    exports['feather-justice'][name]=function(_,request)
        legalDispatches[#legalDispatches+1]={operation=name,request=request}
        if onCall then onCall('legal') end
        return {ok=true,value={recordId=uuid(30),items={}}}
    end
end
local function check(label,value) checks=checks+1;assert(value,label) end
check('default config valid',Law.ValidateConfig())
local department=LawConfig.Departments.new_hanover
department.minGradeOrdinal=0/0;check('nonfinite config refused',not Law.ValidateConfig());department.minGradeOrdinal=0
department.untrusted=true;check('unknown config fields refused',not Law.ValidateConfig());department.untrusted=nil
check('unknown department denied',Law.Access(5,context,'foreign','justice.case.view').code=='department_unavailable')
check('forged source refused',Law.Actor(-1,context).code=='unauthenticated')
check('old session refused',Law.Actor(5,{characterId=context.characterId,sessionId=uuid(9)}).code=='session_expired')
job=false;check('off duty refused',Law.Access(5,context,'new_hanover','justice.case.view').code=='duty_required');job=true
license=false;check('missing commission refused',Law.Access(5,context,'new_hanover','justice.case.view').code=='qualification_required');license=true
licenseScope={jurisdictionId=uuid(99)}
check('unknown commission scope refused',Law.Access(5,context,'new_hanover','justice.case.view').code=='qualification_scope_unsupported');licenseScope={}
jurisdiction=false;check('missing jurisdiction refused',Law.Access(5,context,'new_hanover','justice.case.view').code=='jurisdiction_unavailable');jurisdiction=true
policy=false;check('policy denial',Law.Access(5,context,'new_hanover','justice.case.view').code=='authorization_denied');policy=true
onCall=function(step) if step=='license' then current=false end end
check('session changes during provider read refused',Law.Access(5,context,'new_hanover','justice.case.view').code=='session_expired')
onCall=nil;current=true
check('configured authorized access',Law.Access(5,context,'new_hanover','justice.case.view').ok)
available=false;check('provider stopped refused',not Law.Access(5,context,'new_hanover','justice.case.view').ok);available=true
local count=0
for name,spec in pairs(Law.Routes) do
    local registration=Law.RegisterRoute(name,spec);check('route registered '..name,registration.ok);count=count+1
    check('requires character '..name,registered[name].options.requireCharacter==true)
end
check('only native allowlisted routes',count==65)
local list=registered['law.cases.list.v1']
check('client jurisdiction injection denied',not list.options.validatePayload({department='new_hanover',jurisdictionId=uuid(8)}))
check('bad cursor denied',not list.options.validatePayload({department='new_hanover',cursor='invalid'}))
check('own session exposes no account identities',registered['law.session.get.v1'].handler({},5,context).value.characterId==nil)
check('list resolves server jurisdiction',list.handler({department='new_hanover'},5,context).ok)
local open=registered['law.cases.open.v1']
local request={department='new_hanover',requestId='request-1',title='Title',summary='Summary'}
check('case route valid',open.options.validatePayload(request))
check('case creation dispatch',open.handler(request,5,context).ok)
check('actor identity derived',lastOpen.actorSource==5 and lastOpen.jurisdictionId==uuid(3))
check('request key character bound',lastOpen.requestId==context.characterId..':request-1')
check('reason code not chosen by client',lastOpen.reasonCode=='law.case.open')
request.actorSource=6;check('actor spoof refused',open.handler(request,5,context).code=='invalid_input');request.actorSource=nil
onCall=function(step) if step=='open' then current=false end end
check('postcommit stale reply fenced',open.handler(request,5,context).code=='session_expired');current=true;onCall=nil
onCall=function(step) if step=='list' then Law.SetState('degraded','stop') end end
check('generation change fences response',list.handler({department='new_hanover'},5,context).code=='session_expired');onCall=nil
check('degraded route refused',list.handler({department='new_hanover'},5,context).code=='not_ready')
local caps=registered.GetCapabilities().value
check('future gameplay not advertised',caps.features.jail==0 and caps.features.warrants==0 and caps.features.restraints==0)
check('invalid timeout refused',registered.AwaitReady(0/0).code=='invalid_input')
dofile('tests/legal_routes.lua')({registered=registered,context=context,uuid=uuid,check=check,
    dispatches=legalDispatches,policy=function(value) policy=value end,
    caseJurisdiction=function(value) caseJurisdiction=value end,childCase=function(value) childCase=value end,
    onCall=function(value) onCall=value end,current=function(value) current=value end})
dofile('tests/custody.lua')({uuid=uuid,check=check,registered=registered,context=context,dispatches=legalDispatches})
local setupCommands,preflightLogs,enumerations={},{},0
RegisterCommand=function(name,handler) setupCommands[name]=handler end
GetPlayers=function() enumerations=enumerations+1;return {'5'} end
dofile('server/setup.lua')
local originalPrint=print
print=function(value) preflightLogs[#preflightLogs+1]=value end
setupCommands.LawCitationPreflight(0,{uuid(1),'new_hanover'})
print=originalPrint
check('UUID preflight resolves session and checks three actions',#preflightLogs==3 and preflightLogs[1]:find('result=allowed',1,true)~=nil)
local activeLogs={}
print=function(value) activeLogs[#activeLogs+1]=value end
setupCommands.LawActiveCharacters(0)
print=originalPrint
check('active characters diagnostic returns current UUID not stored profile status',#activeLogs==2 and activeLogs[1]:find('characterUUID='..uuid(1),1,true)~=nil and activeLogs[2]:find('activeSessions=1',1,true)~=nil)
local activeLogCount=#activeLogs
print=function(value) activeLogs[#activeLogs+1]=value end
setupCommands.LawActiveCharacters(5)
print=originalPrint
check('active UUID diagnostic is console-only',#activeLogs==activeLogCount)
local beforeEnumeration=enumerations
print=function(value) preflightLogs[#preflightLogs+1]=value end
setupCommands.LawCitationPreflight(0,{'1','new_hanover'})
setupCommands.LawCitationPreflight(5,{uuid(1),'new_hanover'})
print=originalPrint
check('preflight refuses numeric identity and non-console callers',enumerations==beforeEnumeration)
print(('PASS Law: %d checks (mock services; no live acceptance)'):format(checks))
dofile('tests/restraints.lua')
dofile('tests/restraints_client.lua')
dofile('tests/search.lua')
dofile('tests/evidence_inventory.lua')
dofile('tests/evidence.lua')
dofile('tests/court.lua')
dofile('tests/execution.lua')
dofile('tests/execution_store.lua')
dofile('tests/armory.lua')
dofile('tests/medical_execution.lua')
dofile('tests/lifecycle.lua')
dofile('tests/client.lua')
dofile('tests/contracts_routes.lua')
dofile('tests/acceptance.lua')
dofile('tests/policy_integration.lua')

dofile('tests/qualified_policy.lua')
