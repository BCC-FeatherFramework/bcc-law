local checks, threads, events, commands, registrations = 0, {}, {}, {}, 0
local states, healthStates, race = {}, {}, false
local supportsWarrants=true
local function check(label,value) checks=checks+1;assert(value,label) end
CreateThread=function(fn) threads[#threads+1]=coroutine.create(fn) end
Wait=function() coroutine.yield('wait') end
AddEventHandler=function(name,fn) events[name]=fn end
RegisterCommand=function(name,fn) commands[name]=fn end
GetResourceState=function(resource) return states[resource] or 'started' end
for _,resource in ipairs({'feather-core','feather-character','feather-jobs','feather-licenses','feather-justice'}) do
    exports[resource]=exports[resource] or {}
    exports[resource].GetHealth=function() return {ok=true,value={state=healthStates[resource] or 'ready'}} end
end
exports['feather-core'].GetCapabilities=function() return {ok=true,value={contract=1}} end
exports['feather-justice'].GetCapabilities=function() return {ok=true,value={contract=1,features={rulings=1,sentences=1,subjectStatus=1,sentenceProgress=1,cases=1,custodyBooking=1,citations=1,parties=1,caseAccess=1,charges=1,warrants=supportsWarrants and 1 or 0}}} end
exports['feather-core'].RegisterRpc=function()
    registrations=registrations+1
    if race then race=false;events.onResourceStop('feather-core') end
    return {ok=true,value={}}
end
Law.SetState('starting','test')
dofile('server/main.lua')
local function resume() local ok,err=coroutine.resume(threads[1]);assert(ok,err) end
resume();check('ready after registration',Law.Ready() and registrations==65)
supportsWarrants=false;resume();check('older Justice blocks new legal routes',not Law.Ready())
supportsWarrants=true;resume();check('compatible Justice recovers without duplicate registration',Law.Ready() and registrations==65)
healthStates['feather-jobs']='failed';resume()
check('Jobs loss degrades Law',not Law.Ready() and Law.Health().value.phase=='waiting_for_feather-jobs')
healthStates['feather-jobs']='ready';resume()
check('Jobs recovery keeps Core registrations',Law.Ready() and registrations==65)
events.onResourceStop('feather-core');race=true;resume()
check('Core stop during registration fences readiness',not Law.Ready() and registrations==66)
resume();check('fresh Core registrations recover',Law.Ready() and registrations==131)
states['feather-justice']='stopped';events.onResourceStop('feather-justice');resume()
check('Justice outage blocks Law',not Law.Ready())
states['feather-justice']='started';resume();check('Justice recovery succeeds',Law.Ready())
check('diagnostic command available',type(commands.LawReleaseContractSmokeTest)=='function')
print(('PASS Law lifecycle: %d checks (mock provider lifecycle)'):format(checks))
