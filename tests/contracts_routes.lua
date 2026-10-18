-- Exercise the installed Contracts route module with UUID session identities.
-- Settlement/Economy are mocked; this proves routing/identity, not money movement.
local checks,routes,listed,settlement=0,{},nil,nil
local function check(label,value) checks=checks+1;assert(value,label) end
local debtor=os.getenv('FEATHER_TEST_SUBJECT_UUID') or '09d34d7a-8385-4f40-9b9f-d90c698c9f1f'
local other=os.getenv('FEATHER_TEST_OTHER_UUID') or 'e0c07bc4-daa2-4329-9fdc-6ad84d6fb14b'
local obligation='0aeb8b93-76d2-4ab9-b459-20522c39d59c'
local session='b51be88a-a85e-42d9-b231-75116723b885'
local current=true
local env=setmetatable({},{__index=_G})
env.Config={ClientRoutes={enabled=true},Limits={maximumClientRequestIdLength=64}}
env.GetCurrentResourceName=function() return 'feather-contracts' end
env.ContractsLogging={Create=function() return {Error=function() end} end}
env.exports={['feather-core']={
    IsSessionCurrent=function(_,source,sid,character) return current and source==19 and sid==session and (character==debtor or character==other) end,
    RegisterContractRPC=function(_,name,handler,options) routes[name]={handler=handler,options=options};return {ok=true,value={}} end
}}
local root='../../[feather]/feather-contracts/'
assert(loadfile(root..'shared/results.lua','t',env))()
assert(loadfile(root..'server/services/validation.lua','t',env))()
env.ContractsFoundation={RequireReady=function() return {ok=true,value={}} end}
env.ContractsObligationRepository={ClientView=function(value) return value end,
    ListParty=function(options) listed=options;return {ok=true,value={items={},nextCursor=nil}} end,
    Get=function() return {ok=true,value={obligationId=obligation,status='issued',debtor={type='character',id=debtor},creditor={type='system'}}} end}
env.ContractsObligations={ValidateListOptions=function(p) return {ok=true,value=p} end}
env.ContractsSettlement={SettleObligation=function(p,context,owner,client)
    settlement={context=context,owner=owner,client=client}
    if context.actorCharacterId~=debtor then return {ok=false,code='forbidden'} end
    return {ok=true,value={obligationId=p.obligationId}}
end}
assert(loadfile(root..'server/services/routes.lua','t',env))()
check('actual Contracts routes register',env.ContractsRoutes.Register().ok)
local ctx={characterId=debtor,sessionId=session,accountId='9e9dc061-c0dc-45f5-a8c7-7850e61cf96b'}
local list=routes['contracts.obligations.list.v1']
check('own debt list routes require session',list.options.requireCharacter)
check('own list works with UUID actor',list.handler({role='debtor'},19,ctx).ok)
check('own list derives character UUID from session',listed.partyId==debtor and listed.partyType=='character' and listed.excludeDrafts)
local pay=routes['contracts.obligation.settle.v1']
local payload={obligationId=obligation,requestId='same-payment'}
check('bounded payment request valid',pay.options.validatePayload(payload))
check('client payer injection rejected',not pay.options.validatePayload({obligationId=obligation,requestId='same-payment',actorCharacterId=other}))
check('payment context bound to UUID debtor',pay.handler(payload,19,ctx).ok and settlement.context.actorCharacterId==debtor)
check('payment retry ID namespaced by character UUID',settlement.context.receiptRequestId==debtor..':same-payment')
check('Contracts owns client settlement',settlement.owner=='feather-contracts' and settlement.client)
ctx.characterId=other
check('other character cannot settle debtor wallet',not pay.handler(payload,19,ctx).ok)
check('other character cannot read obligation',routes['contracts.obligation.get.v1'].handler({obligationId=obligation},19,ctx).code=='obligation_not_found')
current=false;check('expired session cannot pay',pay.handler(payload,19,ctx).code=='character_required')
print(('PASS installed Contracts route identity: %d checks (UUID fixtures; settlement mocked)'):format(checks))
