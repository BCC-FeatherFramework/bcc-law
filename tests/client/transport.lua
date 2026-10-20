-- MDT transport (client/main.lua) with mocked natives; no in-game rendering.
local checks,threads,events,commands,callbacks,messages=0,{},{},{},{},{}
local pending,denied,focused,lastRoute=false,false,false,nil
local function check(label,value) checks=checks+1;assert(value,label) end
local env=setmetatable({},{__index=_G})
env.CreateThread=function(fn) threads[#threads+1]=coroutine.create(fn) end
env.Wait=function() coroutine.yield('wait') end
env.RegisterCommand=function(name,fn) commands[name]=fn end
env.RegisterNUICallback=function(name,fn) callbacks[name]=fn end
env.AddEventHandler=function(name,fn) events[name]=fn end
env.GetCurrentResourceName=function() return 'bcc-law' end
env.SetNuiFocus=function(keyboard,cursor) focused=keyboard and cursor end
env.SendNUIMessage=function(value) messages[#messages+1]=value end
env.print=function() end
env.exports={['feather-core']={CallRPCAsync=function(_,name)
    lastRoute=name
    if pending then coroutine.yield('pending') end
    if denied then return {ok=false,code='authorization_denied'} end
    if name=='core.account.settings.get.v1' then return {ok=true,value={locale='ro'}} end
    if name=='law.session.get.v1' then return {ok=true,value={departments={{key='new_hanover',label='New Hanover'}},locale='ro'}} end
    return {ok=true,value={items={}}}
end}}
for _,file in ipairs({'shared/results.lua','locales/en.lua','locales/ro.lua','client/main.lua'}) do assert(loadfile(file,'t',env))() end
local function resume(co) local ok,err=coroutine.resume(co or threads[#threads]);assert(ok,err) end
resume(threads[1])
check('account language read from Core at start',env.Law.ClientLocale=='ro')
commands.law(0,{'new_hanover'});resume()
local open=messages[#messages]
check('MDT opens after the session response',focused and open.type=='open' and open.mode=='officer' and open.department=='new_hanover')
check('MDT receives the language and its strings',open.locale=='ro' and open.strings['nav.cases']=='Dosare')
local complete=true
for key in pairs(env.LawLocales.en) do if open.strings[key]==nil then complete=false end end
check('every English key reaches the MDT',complete)
local epoch,result=open.epoch
callbacks.request({epoch=epoch,operation='cases.list',payload={department='new_hanover'}},function(r) result=r end);resume()
check('allowlisted operation uses its fixed route',result.ok and lastRoute=='law.cases.list.v1')
callbacks.request({epoch=epoch,operation='custody.arrest',payload={}},function(r) result=r end);resume()
check('custody arrest is allowlisted',lastRoute=='law.custody.arrest.v1')
for _,removed in ipairs({'citations.cancel','custody.reserve','custody.confirm','operations.get','sentences.vacate','evidence.disposition','warrants.search.draft'}) do
    callbacks.request({epoch=epoch,operation=removed,payload={}},function(r) result=r end)
    check('retired operation '..removed..' is refused',result.code=='client_unavailable')
end
callbacks.request({epoch=epoch,operation='arbitrary.export',payload={}},function(r) result=r end)
check('arbitrary operation refused',result.code=='client_unavailable')
callbacks.request({epoch=epoch-1,operation='cases.list',payload={}},function(r) result=r end)
check('stale browser epoch refused',result.code=='client_unavailable')
events['feather-core:locale:changed']('en')
check('language change reaches the open MDT',messages[#messages].type=='locale' and messages[#messages].strings['nav.cases']=='Cases')
pending=true
callbacks.request({epoch=epoch,operation='cases.list',payload={}},function(r) result=r end);local waiting=threads[#threads];resume(waiting)
callbacks.request({epoch=epoch,operation='cases.open',payload={}},function(r) result=r end)
check('concurrent browser requests refused',result.code=='client_unavailable')
events['Feather:Character:Logout']();check('logout releases focus and clears the browser',not focused and messages[#messages].type=='close')
pending=false;resume(waiting)
check('a late reply is fenced after logout',result.code=='session_expired')
pending=true;commands.law(0,{'new_hanover'});local opening=threads[#threads];resume(opening)
events['Feather:Character:Logout']();pending=false;resume(opening)
check('a late opening cannot restore focus',not focused)
denied=true;commands.law(0,{'new_hanover'});resume()
check('a denied session does not open the MDT',not focused)
denied=false;commands.law(0,{'new_hanover'});resume()
events.onClientResourceStop('feather-licenses')
check('a dependency stop closes the MDT',not focused)
commands.lawfines();resume()
check('debtor opens the own-fines view',focused and messages[#messages].mode=='debtor')
local debtorEpoch=messages[#messages].epoch
callbacks.request({epoch=debtorEpoch,operation='debts.settle',payload={obligationId='8f37d250-3b6a-4c19-8e72-000000000032',requestId='payment-test'}},function(r) result=r end);resume()
check('payment uses the Contracts own-wallet route',result.ok and lastRoute=='contracts.obligation.settle.v1')
events.onClientResourceStop('feather-contracts');check('a Contracts stop closes the fines view',not focused)
commands.lawstatus();resume()
check('inmate opens the own-status view',focused and messages[#messages].mode=='inmate')
print(('PASS client MDT transport: %d checks (mock natives; no in-game rendering)'):format(checks))
