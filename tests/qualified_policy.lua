local checks,registered,evaluate=0,{},nil
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local officer,judge,commission,current,admin,scope=true,false,true,true,false,{}
local actor={source=5,characterId=uuid(5),sessionId=uuid(15)}
local env=setmetatable({},{__index=_G})
env.GetResourceState=function() return 'started' end
env.GetGameTimer=function() return 0 end
local invoking='feather-admin'
env.GetInvokingResource=function() return invoking end
local function context(caller,subject) return {source=5,characterId=actor.characterId,sessionId=actor.sessionId,caller=caller,subject=subject} end
local findCalls=0
local changeDuringLicense=false
env.exports=setmetatable({
    ['feather-core']={GetSessionContext=function() return {ok=true,value=actor} end,IsSessionCurrent=function() return current end,
        Authorize=function(_,action,p) return evaluate(action,context('bcc-law',p.subject)) end},
    ['feather-jobs']={CheckAssignment=function(_,p) return {ok=true,value={matched=(p.jobKey=='police' and officer or p.jobKey=='judge' and judge)}} end},
    ['feather-licenses']={CheckLicense=function(_,p)
        if changeDuringLicense then current=false end
        return {ok=true,value={matched=commission and (p.licenseKey=='peace_officer' and officer or p.licenseKey=='judicial_commission' and judge),scopeVersion=1,scope=scope}}
    end},
    ['feather-justice']={FindJurisdictionByKey=function()
        findCalls=findCalls+1
        local allowed=evaluate('justice.definition.view',context('feather-justice',{resource='bcc-law'}))
        return allowed.value.allowed and {ok=true,value={recordId=uuid(30),status='active'}} or {ok=false,code='authorization_denied'}
    end}
},{__call=function(_,name,fn) registered[name]=fn end})
for _,path in ipairs({'shared/results.lua','config.lua','server/foundation.lua','server/access.lua'}) do assert(loadfile(path,'t',env))() end
local L=env.Law;L.SetState('ready','test')
local provider=setmetatable({Config={}},{__index=_G})
local root='../../[feather]/feather-admin/'
for _,path in ipairs({'configs/permissions.lua','configs/service_policy.lua','configs/law_acceptance_policy.lua'}) do assert(loadfile(root..path,'t',provider))() end
provider.FeatherAdmin={IsActionEnabled=function() return true end,CanUse=function(_,action)
    check('qualified policy asks staff only for protected audit',action=='staff.admin.audit.search')
    return admin
end}
provider.exports={['feather-core']={IsSessionCurrent=function() return current end,RegisterPolicyProvider=function(_,_,implementation) evaluate=implementation.Evaluate;return {ok=true} end},
    ['bcc-law']={EvaluateActionPolicy=function(_,action,ctx) return registered.EvaluateActionPolicy(action,ctx) end}}
provider.print=function() end;provider.RegisterCommand=function() end
assert(loadfile(root..'server/services/policy_provider.lua','t',provider))()
check('qualified nonstaff officer can access legal work',L.Access(5,actor,'new_hanover','justice.case.view').ok)
check('definition bootstrap does not recurse into Justice',findCalls==1)
check('qualified officer can restrain',L.Access(5,actor,'new_hanover','law.restraint.manage').ok)
officer=false;check('off-duty actor has no staff fallback',not L.Access(5,actor,'new_hanover','justice.case.view').ok);officer=true
commission=false;check('expired/missing commission denies',not L.Access(5,actor,'new_hanover','justice.case.view').ok);commission=true
check('police commission grants no judicial ruling power',not L.Access(5,actor,'new_hanover','justice.ruling.record').ok)
local ctx=context('feather-justice',{resource='bcc-law',jurisdictionId=uuid(30),warrantType='search'})
check('search warrant issuance requires judicial commission',not evaluate('justice.warrant.issue',ctx).value.allowed)
judge=true;officer=false
check('qualified judge can use court without police job',L.Access(5,actor,'new_hanover','justice.ruling.record').ok)
check('qualified judge can authorize typed search warrant',evaluate('justice.warrant.issue',ctx).value.allowed)
check('judicial commission grants no field restraint power',not L.Access(5,actor,'new_hanover','law.restraint.manage').ok)
ctx.subject.jurisdictionId=uuid(99);check('unconfigured jurisdiction denied',not evaluate('justice.warrant.issue',ctx).value.allowed);ctx.subject.jurisdictionId=uuid(30)
ctx.caller='foreign';check('foreign broker denied',not evaluate('justice.warrant.issue',ctx).value.allowed);ctx.caller='feather-justice'
ctx.subject.resource='other';check('foreign principal denied',not evaluate('justice.warrant.issue',ctx).value.allowed);ctx.subject.resource='bcc-law'
check('protected audit additionally requires administrator entitlement',not evaluate('justice.audit.view',ctx).value.allowed)
admin=true;check('qualified administrator judge can audit',evaluate('justice.audit.view',ctx).value.allowed);admin=false
check('no global legal manage bypass granted',not evaluate('justice.case.manage_all',ctx).value.allowed)
scope={unknown=true};check('unknown qualification scope fails closed',not evaluate('justice.warrant.issue',ctx).value.allowed);scope={}
changeDuringLicense=true;check('session changes during license check deny',not evaluate('justice.warrant.issue',ctx).value.allowed);changeDuringLicense=false;current=true
local service={source=0,system=true,caller='feather-justice',subject={resource='bcc-law'}}
check('explicit safe status service grant preserved',evaluate('justice.status.view',service).value.allowed)
check('explicit service progress grant preserved',evaluate('justice.sentence.progress',service).value.allowed)
check('service role does not grant player judicial operations',not evaluate('justice.ruling.record',service).value.allowed)
print(('PASS qualified Law/Admin policy: %d checks (real policy modules, mocked facts)'):format(checks))
