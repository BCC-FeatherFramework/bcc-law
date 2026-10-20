-- MDT transport. The browser can only name an operation from this fixed list; each
-- maps to one versioned server route. Text comes from locales/*.lua in the player's
-- Core account language (feather-core:locale:changed keeps it current).
local epoch,opened,opening,busy=0,false,false,false
local operations={}
local function Routes(group,names)
    for _,name in ipairs(names) do operations[group..'.'..name]='law.'..group..'.'..name..'.v1' end
end
Routes('cases',{'list','open','get','update','transition','seal','unseal','expunge','history'})
Routes('parties',{'list','add','remove'})
Routes('charges',{'list','propose','amend','file','dispose'})
Routes('warrants',{'list','active','draft','issue','serve','recall','quash'})
Routes('statutes',{'list','register','revise'})
Routes('citations',{'list','issue'})
Routes('custody',{'facilities','list','arrest','book','release'})
Routes('rulings',{'list','record'})
Routes('sentences',{'list','create','activate','suspend','complete'})
Routes('evidence',{'collect','receipts','attach','list','remove','lockers'})
Routes('restraints',{'apply','release','escort'})
Routes('search',{'inspect','finish'})
Routes('armory',{'stations','catalog','claim','claims'})
Routes('execution',{'self'})
Routes('service',{'start'})
operations['debts.list']='contracts.obligations.list.v1'
operations['debts.settle']='contracts.obligation.settle.v1'

Law.ClientLocale='en'
-- English is the base; the chosen language overrides the keys it translates.
local function Strings(lang)
    local strings={}
    for key,text in pairs(LawLocales.en) do strings[key]=text end
    for key,text in pairs(LawLocales[lang] or {}) do strings[key]=text end
    return strings
end
local function SetLocale(lang)
    local chosen=Law.Locale(lang)
    if chosen==Law.ClientLocale then return end
    Law.ClientLocale=chosen
    if opened then SendNUIMessage({type='locale',locale=chosen,strings=Strings(chosen)}) end
end
AddEventHandler('feather-core:locale:changed',SetLocale)
CreateThread(function()
    for _=1,10 do
        local ok,r=pcall(function() return exports['feather-core']:CallRPCAsync('core.account.settings.get.v1',{},nil,5000) end)
        if ok and type(r)=='table' and r.ok and type(r.value)=='table' then SetLocale(r.value.locale);return end
        Wait(3000)
    end
end)

local function Close()
    epoch=epoch+1;opened,opening,busy=false,false,false
    SetNuiFocus(false,false);SendNUIMessage({type='close'})
end
-- officer = MDT; inmate = own legal status; debtor = own fines.
local function Open(mode,department)
    if opening then return end
    Close();opening=true
    local generation=epoch
    CreateThread(function()
        local ok,result=pcall(function() return exports['feather-core']:CallRPCAsync('law.session.get.v1',{},nil,10000) end)
        if generation~=epoch then return end
        opening=false
        if not ok or type(result)~='table' or not result.ok or type(result.value)~='table' then
            print(Law.T(Law.ClientLocale,'client.unavailable'));return
        end
        Law.ClientLocale=Law.Locale(result.value.locale)
        opened=true;SetNuiFocus(true,true)
        SendNUIMessage({type='open',epoch=epoch,mode=mode,department=department,session=result.value,
            locale=Law.ClientLocale,strings=Strings(Law.ClientLocale)})
    end)
end
RegisterCommand('law',function(_,args) Open('officer',args and args[1]) end,false)
RegisterCommand('lawstatus',function() Open('inmate') end,false)
RegisterCommand('lawfines',function() Open('debtor') end,false)
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
