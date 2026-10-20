local epoch,busy,restrained,escortSource,updatedAt=0,false,false,nil,0
local appliedPed,attachedPed
local function Detach()
    if attachedPed then DetachEntity(attachedPed,true,false);attachedPed=nil end
end
local function Clear()
    Detach()
    if appliedPed and DoesEntityExist(appliedPed) then
        SetEnableHandcuffs(appliedPed,false,false)
        SetPedCanPlayGestureAnims(appliedPed,true)
    end
    DisablePlayerFiring(PlayerId(),false)
    appliedPed=nil
end
local function Reset()
    epoch=epoch+1;busy=false;restrained=false;escortSource=nil;Clear()
end
local function Rpc(operation,payload)
    local ok,r=pcall(function() return exports['feather-core']:CallRPCAsync('law.restraints.'..operation..'.v1',payload,nil,1500) end)
    return ok and type(r)=='table' and r or {ok=false,code='service_unavailable'}
end
CreateThread(function()
    while true do
        local generation=epoch
        local r=Rpc('self',{})
        if generation==epoch then
            if r.ok and type(r.value)=='table' and type(r.value.restrained)=='boolean' then
                restrained=r.value.restrained;escortSource=r.value.escortSource;updatedAt=GetGameTimer()
            else restrained=false;escortSource=nil end
        end
        Wait(1250)
    end
end)
CreateThread(function()
    while true do
        local ped=PlayerPedId()
        if restrained and GetGameTimer()-updatedAt<5000 and not IsPedDeadOrDying(ped,true) then
            if appliedPed~=ped then
                Clear();appliedPed=ped
                SetEnableHandcuffs(ped,true,true)
                SetCurrentPedWeapon(ped,GetHashKey('WEAPON_UNARMED'),true)
                SetPedCanPlayGestureAnims(ped,false)
            end
            DisablePlayerFiring(PlayerId(),true)
            for _,control in ipairs({0xB2F377E8,0xC1989F95,0x07CE1E61,0xF84FA74F,0xCEE12B50,0x8FFC75D6,0xD9D0E1C0,0xDB096B85}) do
                DisableControlAction(0,control,true)
            end
            local officer=escortSource and GetPlayerFromServerId(escortSource) or -1
            local escortPed=officer~=-1 and GetPlayerPed(officer) or 0
            if escortPed~=0 and DoesEntityExist(escortPed) and IsPedOnFoot(escortPed) and IsPedOnFoot(ped)
                and not IsPedDeadOrDying(escortPed,true) then
                if not attachedPed or not IsEntityAttachedToEntity(ped,escortPed) then
                    Detach()
                    AttachEntityToEntity(ped,escortPed,11816,0.54,0.54,0.0,0.0,0.0,0.0,false,false,false,false,2,true,false,false)
                    attachedPed=ped
                end
            else Detach() end
            Wait(0)
        else
            if appliedPed or attachedPed then Clear() end
            Wait(100)
        end
    end
end)
-- /lawcuff <department> <player> <UUID> [custody]: the UUID is an arrest warrant,
-- or with "custody" an unreleased custody record (after the arrest is recorded).
local function Command(operation,args)
    if busy then return end
    local target=tonumber(args[2])
    if not args[1] or not target or (operation=='apply' and not args[3])
        or (operation=='escort' and args[3]~='on' and args[3]~='off') then
        print(Law.T(Law.ClientLocale,'client.restraintUsage'))
        return
    end
    busy=true
    local generation=epoch
    CreateThread(function()
        local p={department=args[1],targetSource=target}
        if operation=='apply' then
            if args[4]=='custody' then p.custodyId=args[3] else p.warrantId=args[3] end
        elseif operation=='escort' then p.enabled=args[3]=='on' end
        local r=Rpc(operation,p)
        if generation~=epoch then return end
        busy=false
        if r.ok then print(Law.T(Law.ClientLocale,'client.confirmed'));return end
        local key='error.'..tostring(r.code)
        local text=Law.T(Law.ClientLocale,key)
        print(Law.T(Law.ClientLocale,'client.failed',{message=text~=key and text or Law.T(Law.ClientLocale,'error.unconfirmed')}))
    end)
end
RegisterCommand('lawcuff',function(_,args) Command('apply',args) end,false)
RegisterCommand('lawuncuff',function(_,args) Command('release',args) end,false)
RegisterCommand('lawescort',function(_,args) Command('escort',args) end,false)
AddEventHandler('Feather:Character:Logout',Reset)
AddEventHandler('onClientResourceStop',function(resource)
    for _,dependency in ipairs({GetCurrentResourceName(),'feather-core','feather-character','feather-jobs','feather-licenses','feather-justice'}) do
        if resource==dependency then Reset();return end
    end
end)
