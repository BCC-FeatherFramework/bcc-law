local checks,threads,events,commands,callbacks,messages=0,{},{},{},{},{}
local pending,denied,focused,lastRoute=false,false,false,nil
local function check(label,value) checks=checks+1;assert(value,label) end
CreateThread=function(fn) threads[#threads+1]=coroutine.create(fn) end
RegisterCommand=function(name,fn) commands[name]=fn end
RegisterNUICallback=function(name,fn) callbacks[name]=fn end
AddEventHandler=function(name,fn) events[name]=fn end
GetCurrentResourceName=function() return 'bcc-law' end
SetNuiFocus=function(keyboard,cursor) focused=keyboard and cursor end
SendNUIMessage=function(value) messages[#messages+1]=value end
exports['feather-core'].CallRPCAsync=function(_,name,payload)
    lastRoute=name
    if pending then coroutine.yield('pending') end
    if denied then return {ok=false,code='authorization_denied'} end
    if name=='law.session.get.v1' then return {ok=true,value={departments={{key='new_hanover',label='New Hanover'}}}} end
    return {ok=true,value={items={}}}
end
dofile('client/main.lua')
local function resume(index) local ok,err=coroutine.resume(threads[index]);assert(ok,err) end
commands.law(0,{'new_hanover'});resume(1)
check('native MDT opens after session response',focused and messages[#messages].type=='open')
local epoch=messages[#messages].epoch
local result
callbacks.request({epoch=epoch,operation='cases.list',payload={department='new_hanover'}},function(r) result=r end);resume(2)
check('allowlisted operation uses fixed RPC',result.ok and lastRoute=='law.cases.list.v1')
callbacks.request({epoch=epoch,operation='arbitrary.export',payload={}},function(r) result=r end)
check('arbitrary operation rejected',result.code=='client_unavailable')
callbacks.request({epoch=epoch-1,operation='cases.list',payload={}},function(r) result=r end)
check('stale browser epoch rejected',result.code=='client_unavailable')
pending=true
callbacks.request({epoch=epoch,operation='cases.list',payload={}},function(r) result=r end);resume(3)
callbacks.request({epoch=epoch,operation='cases.open',payload={}},function(r) result=r end)
check('concurrent browser requests refused',result.code=='client_unavailable')
events['Feather:Character:Logout']();check('logout releases focus and clears browser',not focused and messages[#messages].type=='close')
pending=false;resume(3)
check('late RPC is fenced after logout',result.code=='session_expired')
pending=true;commands.law(0,{'new_hanover'});resume(4)
events['Feather:Character:Logout']();pending=false;resume(4)
check('late opening cannot restore focus',not focused and messages[#messages].type=='close')
denied=true;commands.law(0,{'new_hanover'});resume(5)
check('denied session does not open MDT',not focused)
denied=false;commands.law(0,{'new_hanover'});resume(6)
events.onClientResourceStop('feather-licenses')
check('dependency stop closes MDT',not focused)
commands.lawfines()
check('debtor opens own fine interface without officer setup',focused and messages[#messages].mode=='debtor')
local debtorEpoch=messages[#messages].epoch
callbacks.request({epoch=debtorEpoch,operation='debts.list',payload={role='debtor',limit=25}},function(r) result=r end);resume(7)
check('debtor list uses Contracts own-character route',result.ok and lastRoute=='contracts.obligations.list.v1')
callbacks.request({epoch=debtorEpoch,operation='debts.settle',payload={obligationId='8f37d250-3b6a-4c19-8e72-000000000032',requestId='payment-test'}},function(r) result=r end);resume(8)
check('debtor payment uses Contracts own-wallet route',result.ok and lastRoute=='contracts.obligation.settle.v1')
events.onClientResourceStop('feather-contracts');check('Contracts stop closes fine interface',not focused)
print(('PASS Law native MDT transport: %d checks (mock Cfx; no in-game rendering acceptance)'):format(checks))
