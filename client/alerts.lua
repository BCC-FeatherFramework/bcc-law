-- Alerts (Law master plan §3: badge, blips, alerts). On-duty officers get a
-- temporary map blip for each alert the server sends. Citizens report with
-- /lawalert; a shot fired inside a configured area is reported by the shooter's
-- client, and the server checks the real position, the area and the cooldown.
local areas,lastShot,blips,reporting={},0,{},false
local function Rpc(route,payload)
    local ok,r=pcall(function() return exports['feather-core']:CallRPCAsync(route,payload,nil,5000) end)
    return ok and type(r)=='table' and r or {ok=false,code='dependency_unavailable'}
end
local function ClearBlips()
    for blip in pairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    blips={}
end
RegisterNetEvent('bcc-law:client:alert',function(alert)
    if type(alert)~='table' or type(alert.x)~='number' or type(alert.y)~='number' or type(alert.z)~='number' then return end
    local seconds=math.min(math.max(tonumber(alert.seconds) or 60,10),900)
    local blip=Citizen.InvokeNative(0x554D9D53F696D002,1664425300,alert.x,alert.y,alert.z) -- BlipAddForCoords
    SetBlipSprite(blip,28148096,true)
    SetBlipScale(blip,0.2)
    Citizen.InvokeNative(0x9CB1A1623062F402,blip,Law.T(Law.ClientLocale,alert.kind=='shots' and 'alert.blipShots' or 'alert.blipCitizen')) -- SetBlipName
    blips[blip]=true
    SetTimeout(seconds*1000,function()
        if blips[blip] then blips[blip]=nil;if DoesBlipExist(blip) then RemoveBlip(blip) end end
    end)
end)
-- Areas are static server configuration; retry quickly until a character is active.
CreateThread(function()
    while true do
        local r=Rpc('law.alerts.areas.v1',{})
        if r.ok and type(r.value)=='table' and type(r.value.areas)=='table' then areas=r.value.areas end
        Wait(#areas>0 and 600000 or 30000)
    end
end)
CreateThread(function()
    while true do
        if #areas==0 then Wait(1000) else
            local ped=PlayerPedId()
            if IsPedShooting(ped) and GetGameTimer()-lastShot>10000 then
                local p=GetEntityCoords(ped)
                for _,a in ipairs(areas) do
                    if #(p-vector3(a.x,a.y,a.z))<=a.radius then
                        lastShot=GetGameTimer()
                        CreateThread(function() Rpc('law.alerts.shots.v1',{}) end)
                        break
                    end
                end
            end
            Wait(0)
        end
    end
end)
-- /lawalert [department] <message>; with one department the key may be left out.
RegisterCommand('lawalert',function(_,args)
    if reporting then return end
    reporting=true
    CreateThread(function()
        local locale=Law.ClientLocale
        local session=Rpc('law.session.get.v1',{})
        if not session.ok or type(session.value)~='table' then reporting=false;print(Law.T(locale,'client.unavailable'));return end
        local departments,department,first=session.value.departments or {},nil,1
        for _,d in ipairs(departments) do if d.key==args[1] then department,first=d.key,2 end end
        if not department and #departments==1 then department=departments[1].key end
        local message=table.concat(args,' ',first)
        if not department or message=='' then reporting=false;print(Law.T(locale,'client.alertUsage'));return end
        local r=Rpc('law.alerts.citizen.v1',{department=department,message=message:sub(1,200)})
        reporting=false
        if not r.ok then
            local key='error.'..tostring(r.code)
            local text=Law.T(locale,key)
            print(Law.T(locale,'client.failed',{message=text~=key and text or Law.T(locale,'error.unconfirmed')}))
        end
    end)
end,false)
AddEventHandler('Feather:Character:Logout',function() ClearBlips();areas={} end)
AddEventHandler('onClientResourceStop',function(resource)
    if resource==GetCurrentResourceName() or resource=='feather-core' then ClearBlips() end
end)
