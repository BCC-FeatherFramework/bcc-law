-- Restraint client (client/restraints.lua) with mocked natives; no RedM acceptance.
local checks,threads,events,commands,now=0,{},{},{},0
local cuffed,firing,attached=false,false,false
local response={ok=true,value={restrained=true,escortSource=5}}
local env=setmetatable({},{__index=_G})
local function check(label,v) checks=checks+1;assert(v,label) end
env.CreateThread=function(fn) threads[#threads+1]=coroutine.create(fn) end
env.Wait=function() coroutine.yield() end
env.AddEventHandler=function(name,fn) events[name]=fn end
env.RegisterCommand=function(name,fn) commands[name]=fn end
env.GetCurrentResourceName=function() return 'bcc-law' end
env.GetGameTimer=function() return now end
env.PlayerPedId=function() return 70 end
env.PlayerId=function() return 7 end
env.DoesEntityExist=function(ped) return ped~=0 end
env.SetEnableHandcuffs=function(_,value) cuffed=value end
env.SetPedCanPlayGestureAnims=function() end
env.DisablePlayerFiring=function(player,value) check('firing native receives player index',player==7);firing=value end
env.SetCurrentPedWeapon=function() end
env.GetHashKey=function() return 0 end
env.DisableControlAction=function() end
env.IsPedDeadOrDying=function() return false end
env.GetPlayerFromServerId=function(id) return id==5 and 50 or -1 end
env.GetPlayerPed=function(id) return id==50 and 500 or 0 end
env.IsPedOnFoot=function() return true end
env.IsEntityAttachedToEntity=function() return attached end
env.AttachEntityToEntity=function() attached=true end
env.DetachEntity=function() attached=false end
env.exports={['feather-core']={CallRPCAsync=function() return response end}}
local printed={}
env.print=function(line) printed[#printed+1]=line end
for _,file in ipairs({'shared/results.lua','locales/en.lua','locales/ro.lua'}) do assert(loadfile(file,'t',env))() end
env.Law.ClientLocale='ro'
assert(loadfile('client/restraints.lua','t',env))()
local function resume(n) local ok,err=coroutine.resume(threads[n]);assert(ok,err) end
resume(1);resume(2)
check('server snapshot applies cuffs and escort',cuffed and firing and attached)
response={ok=true,value={restrained=true}};resume(1);resume(2)
check('escort stop detaches without uncuffing',cuffed and not attached)
now=5001;resume(2)
check('expired snapshot lease releases native state',not cuffed and not firing and not attached)
resume(1);resume(2);check('fresh snapshot reapplies cuffs',cuffed)
events['Feather:Character:Logout']();check('logout releases all physical state',not cuffed and not firing and not attached)
resume(1);resume(2);events.onClientResourceStop('feather-jobs')
check('dependency stop releases physical state',not cuffed and not firing)
response={ok=false,code='not_ready'};resume(1);resume(2)
check('rejected poll keeps client unrestrained',not cuffed)
check('field command bindings available',commands.lawcuff and commands.lawuncuff and commands.lawescort)
commands.lawcuff(0,{})
check('usage is printed in the player language',printed[#printed]:find('departament',1,true)~=nil)
local sent
env.exports['feather-core'].CallRPCAsync=function(_,route,payload) sent={route=route,payload=payload};return {ok=false,code='restraint_conflict'} end
commands.lawcuff(0,{'new_hanover','6','8f37d250-3b6a-4c19-8e72-000000000001','custody'});resume(#threads)
check('custody form sends the custody record',sent.route=='law.restraints.apply.v1' and sent.payload.custodyId and sent.payload.warrantId==nil)
check('errors are printed in the player language',printed[#printed]:find('imobilizată',1,true)~=nil)
print(('PASS Law restraint client: %d checks (mock natives; no RedM acceptance)'):format(checks))
