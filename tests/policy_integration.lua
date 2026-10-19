-- Installed default provider and configs; no live registry, DB, roles or grants.
local checks=0
local function check(label,value) checks=checks+1;assert(value,label) end
local env=setmetatable({Config={}},{__index=_G})
local root='../../[feather]/feather-admin/'
for _,path in ipairs({'configs/permissions.lua','configs/authority_actions.lua','configs/service_policy.lua','configs/law_acceptance_policy.lua'}) do
    assert(loadfile(root..path,'t',env))()
end
check('installed policy uses qualified on-duty actors',env.Config.lawAcceptancePolicy.mode=='qualified')
env.Config.lawAcceptancePolicy.mode='staff' -- regression coverage for explicit staging mode
local catalog=0;for _ in pairs(env.Config.authorityActions) do catalog=catalog+1 end
check('reviewed Admin catalog stays at 90 capabilities',catalog==90)
check('Justice actions not appended to Admin capability definitions',env.Config.permissions['justice.case.open']==nil and env.Config.authorityActions['justice.case.open']==nil)
local evaluate,owner,current,changeDuringCheck,checksOfOwner=true,true,true,false,0
local disabled={}
env.FeatherAdmin={
    IsActionEnabled=function(action) return not disabled[action] end,
    CanUse=function(_,action)
        check('Law gate uses existing owner-only capability',action=='roles.assignment.manage')
        checksOfOwner=checksOfOwner+1
        if changeDuringCheck then current=false end
        return owner
    end
}
env.exports={['feather-core']={
    RegisterPolicyProvider=function(_,_,implementation) evaluate=implementation.Evaluate;return {ok=true,value={}} end,
    IsSessionCurrent=function() return current end
}}
env.print=function() end;env.RegisterCommand=function() end
assert(loadfile(root..'server/services/policy_provider.lua','t',env))()
local character=os.getenv('FEATHER_TEST_ACTOR_UUID') or 'b8c6fcb7-7dc6-42a4-a738-952d717272f3'
local context={source=3,characterId=character,sessionId='f2877bfe-a281-41f5-a56a-aa2a48f813d2',
    caller='bcc-law',subject={resource='bcc-law',jurisdictionId='7c9b797e-a30d-47c4-80ce-9b45c191fe97'}}
local function copy(v) if type(v)~='table' then return v end;local t={};for k,c in pairs(v) do t[k]=copy(c) end;return t end
local actions=0
for action in pairs(env.Config.lawAcceptancePolicy.actions) do
    actions=actions+1
    check('explicit staging action permitted to current owner: '..action,evaluate(action,context).value.allowed)
end
local justiceAdditions=0
for _,action in ipairs({'justice.charge.amend','justice.ruling.record','justice.ruling.view','justice.sentence.impose','justice.sentence.activate','justice.sentence.modify','justice.sentence.effect','justice.sentence.progress','justice.sentence.view','justice.evidence.link','justice.evidence.dispose','justice.evidence.view','justice.record.seal','justice.record.expunge','justice.case.view_sealed','justice.audit.view','justice.status.view'}) do
    if env.Config.lawAcceptancePolicy.actions[action]==true then justiceAdditions=justiceAdditions+1 end
end
check('staging action list bounded by reviewed LAW_INTEGRATION agreement',actions==27+justiceAdditions)
owner=false
check('ordinary player denied even for recognized Justice action',evaluate('justice.case.view',context).value.code=='forbidden')
owner=true
local broker=copy(context);broker.caller='feather-justice'
check('Justice broker can delegate the Law principal',evaluate('justice.case.open',broker).value.allowed)
local foreign=copy(context);foreign.caller='foreign'
check('unrelated broker cannot borrow staging entitlement',evaluate('justice.case.open',foreign).value.code=='invalid_law_context')
foreign=copy(context);foreign.subject.resource='other-law'
check('foreign subject resource denied',evaluate('justice.case.open',foreign).value.code=='invalid_law_context')
foreign=copy(context);foreign.subject.resource=nil
check('missing subject delegation denied',evaluate('justice.case.open',foreign).value.code=='invalid_law_context')
foreign=copy(context);foreign.characterId=nil
check('selected character required',evaluate('justice.case.open',foreign).value.code=='invalid_law_context')
foreign=copy(context);foreign.sessionId=nil
check('session identity required',evaluate('justice.case.open',foreign).value.code=='invalid_law_context')
current=false
check('stale session denied before entitlement lookup',evaluate('justice.case.open',context).value.code=='character_required')
current=true;changeDuringCheck=true
check('session change during owner lookup fenced',evaluate('justice.case.open',context).value.code=='character_required')
current=true;changeDuringCheck=false
check('global view override remains unrecognized',evaluate('justice.case.view_all',context).value.code=='unknown_action')
check('global manage override remains unrecognized',evaluate('justice.case.manage_all',context).value.code=='unknown_action')
disabled['justice.case.open']=true
check('existing action-disable switch respected',evaluate('justice.case.open',context).value.code=='action_disabled')
disabled['justice.case.open']=nil
env.Config.lawAcceptancePolicy.enabled=false
check('staging adapter can be disabled',evaluate('justice.case.open',context).value.code=='unknown_action')
env.Config.lawAcceptancePolicy.enabled=true;env.Config.lawAcceptancePolicy.requiredAdminAction='menu.open'
check('misconfigured non-owner base gate fails closed',evaluate('justice.case.open',context).value.code=='invalid_law_policy')
env.Config.lawAcceptancePolicy.requiredAdminAction='roles.assignment.manage'
local service={source=0,system=true,caller='feather-justice',subject={resource='bcc-law'}}
check('existing exact definition setup service grant preserved',evaluate('justice.definition.manage',service).value.allowed)
check('player staging adapter confers no service case grant',not evaluate('justice.case.open',service).value.allowed)
for _,resource in ipairs({'feather-jobs','feather-licenses'}) do
    local scope=setmetatable({},{__index=_G})
    assert(loadfile('../../[feather]/'..resource..'/config.lua','t',scope))()
    check(resource..' reader trust includes Law',scope.Config.Access.trustedReaders['bcc-law']==true)
    for _,field in ipairs({'trustedRegistrars','trustedAssigners','trustedIssuers','privilegedRegistrars','privilegedAssigners','privilegedIssuers'}) do
        local list=scope.Config.Access[field]
        check(resource..' no elevated Law trust: '..field,type(list)~='table' or list['bcc-law']~=true)
    end
end
print(('PASS installed Law staging policy/reader integration: %d checks (mock Core/Authority; no live grants)'):format(checks))
