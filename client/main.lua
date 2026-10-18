local epoch,opened,opening,busy=0,false,false,false
local operations={}
for _,name in ipairs({'cases.list','cases.open','cases.get','cases.update','cases.transition','charges.list',
    'charges.propose','charges.file','charges.dispose','warrants.list','warrants.active','warrants.draft',
    'warrants.issue','warrants.serve','warrants.recall','warrants.quash','parties.list','parties.add','parties.remove','statutes.list','citations.list','citations.issue','citations.cancel','custody.facilities','custody.list','custody.reserve','custody.confirm','custody.release','operations.get'}) do
    operations[name]='law.'..name..'.v1'
end
operations['debts.list']='contracts.obligations.list.v1'
operations['debts.settle']='contracts.obligation.settle.v1'
local function Close()
    epoch=epoch+1;opened,opening,busy=false,false,false
    SetNuiFocus(false,false);SendNUIMessage({type='close'})
end
RegisterCommand('law',function(_,args)
    if opening then return end
    Close();opening=true
    local generation=epoch
    CreateThread(function()
        local ok,result=pcall(function() return exports['feather-core']:CallRPCAsync('law.session.get.v1',{},nil,10000) end)
        if generation~=epoch then return end
        opening=false
        if not ok or type(result)~='table' or not result.ok then print('[bcc-law] Serviciul nu este disponibil.');return end
        opened=true;SetNuiFocus(true,true)
        SendNUIMessage({type='open',epoch=epoch,departments=result.value.departments,department=args and args[1]})
    end)
end,false)
RegisterCommand('lawfines',function()
    Close();opened=true;SetNuiFocus(true,true)
    SendNUIMessage({type='open',epoch=epoch,mode='debtor',departments={}})
end,false)
RegisterNUICallback('close',function(_,cb) Close();cb({ok=true}) end)
RegisterNUICallback('request',function(data,cb)
    if not opened or busy or type(data)~='table' or data.epoch~=epoch or not operations[data.operation]
        or type(data.payload)~='table' then cb({ok=false,code='client_unavailable'});return end
    busy=true
    local generation=epoch
    CreateThread(function()
        local ok,result=pcall(function()
            return exports['feather-core']:CallRPCAsync(operations[data.operation],data.payload,nil,10000)
        end)
        if generation~=epoch then cb({ok=false,code='session_expired'});return end
        busy=false
        cb(ok and type(result)=='table' and result or {ok=false,code='operation_failed'})
    end)
end)
AddEventHandler('Feather:Character:Logout',Close)
AddEventHandler('onClientResourceStop',function(resource)
    if resource==GetCurrentResourceName() or resource=='feather-core' or resource=='feather-character'
        or resource=='feather-contracts' or resource=='feather-justice' or resource=='feather-jobs' or resource=='feather-licenses' then Close() end
end)
