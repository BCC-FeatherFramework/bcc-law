local function Number(v,a,b) return type(v)=='number' and v==v and v>=a and v<=b end
function Law.ValidateArmoryConfig()
    local c=LawConfig.Armory
    if type(c)~='table' or type(c.Stations)~='table' then return false end
    local count=0
    for key,s in pairs(c.Stations) do
        count=count+1
        if not Law.Token(key,64) or not LawConfig.Departments[s.department or ''] or not Law.Text(s.label,100)
            or not Number(s.x,-100000,100000) or not Number(s.y,-100000,100000) or not Number(s.z,-10000,10000)
            or not Number(s.radius,0.5,5) or type(s.items)~='table' then return false end
        local items=0
        for itemKey,item in pairs(s.items) do
            items=items+1
            if not Law.Token(itemKey,64) or not Law.Text(item.label,100) or not Number(item.quantity,1,100) or item.quantity%1~=0
                or (item.kind~='item' and item.kind~='weapon')
                or (item.kind=='item' and (not Law.Token(item.itemName,100) or item.definitionId~=nil))
                or (item.kind=='weapon' and (not Law.Token(item.definitionId,64) or item.quantity~=1 or item.itemName~=nil)) then return false end
        end
        if items>32 then return false end
    end
    return count<=32
end
local function WeaponReady()
    if GetResourceState('feather-weapons')~='started' then return false end
    local ok,caps=pcall(function() return exports['feather-weapons']:initiate().GetCapabilities() end)
    return ok and type(caps)=='table' and caps.ready==true and type(caps.features)=='table'
        and caps.features.secureIssuance==true and caps.features.idempotentIssuance==true and caps.features.issuancePayloadBinding==true
end
function Law.ArmoryAvailable()
    if not Law.Ready() or Law.Store.state~='ready' then return false end
    local r=Law.Call('feather-inventory','GetHealth')
    return (r.ok and type(r.value)=='table' and r.value.state=='ready') or WeaponReady()
end
local function Resolve(item)
    if item.kind=='weapon' then
        if not WeaponReady() then return Law.Err('weapons_unavailable','Secure idempotent weapon issuance is unavailable.') end
        return Law.Ok({kind='weapon',definitionId=item.definitionId,quantity=1})
    end
    if GetResourceState('feather-inventory')~='started' then return Law.Err('inventory_unavailable','Inventory unavailable.') end
    local ok,r=pcall(function() return exports['feather-inventory']:initiate().Items.GetDefinitions() end)
    if not ok or type(r)~='table' or not r.ok or type(r.value)~='table' then return Law.Err('inventory_unavailable','Item catalog unavailable.') end
    for _,d in ipairs(r.value) do
        if d.name==item.itemName and d.instance_mode=='stack' and d.type~='weapon' and d.type~='item_weapon' and d.archived_at==nil then
            return Law.Ok({kind='item',definitionId=tonumber(d.id),itemName=d.name,quantity=item.quantity})
        end
    end
    return Law.Err('item_unavailable','Configured ordinary item is unavailable; unique items require their issuer.')
end
local function Payload(p,claim)
    return Law.Fields(p,claim and {department=true,stationKey=true,itemKey=true,requestId=true} or {department=true,stationKey=true})
        and Law.Token(p.department,48) and Law.Token(p.stationKey,64)
        and (not claim or (Law.Token(p.itemKey,64) and Law.Token(p.requestId,64)))
end
local function Access(p,source,context,physical)
    local a=Law.Access(source,context,p.department,'law.armory.issue');if not a.ok then return a end
    local s=LawConfig.Armory.Stations[p.stationKey]
    if not s or s.department~=p.department then return Law.Err('station_unavailable','Armory unavailable for this department.') end
    if physical then
        local ped=GetPlayerPed(source)
        if not ped or ped==0 or GetEntityHealth(ped)<=0 then return Law.Err('proximity_required','Live presence at the armory required.') end
        local pos=GetEntityCoords(ped)
        if not pos or not Number(pos.x,-100000,100000) or not Number(pos.y,-100000,100000) or not Number(pos.z,-10000,10000)
            or (pos.x-s.x)^2+(pos.y-s.y)^2+(pos.z-s.z)^2>s.radius^2 then return Law.Err('proximity_required','Go to the configured armory.') end
    end
    return a
end
Law.Routes['law.armory.stations.v1']={
    validate=function(p) return Law.Fields(p,{department=true}) and Law.Token(p.department,48) end,
    handler=function(p,source,context)
        local a=Law.Access(source,context,p.department,'law.armory.issue');if not a.ok then return a end
        local items={};for key,s in pairs(LawConfig.Armory.Stations) do if s.department==p.department then items[#items+1]={key=key,label=s.label} end end
        table.sort(items,function(a,b) return a.key<b.key end);return Law.Ok({items=items})
    end
}
Law.Routes['law.armory.catalog.v1']={
    validate=function(p) return Payload(p,false) end,
    handler=function(p,source,context)
        local a=Access(p,source,context,false);if not a.ok then return a end
        local items={}
        for key,item in pairs(LawConfig.Armory.Stations[p.stationKey].items) do
            local available=Resolve(item)
            items[#items+1]={key=key,label=item.label,kind=item.kind,quantity=item.quantity,available=available.ok,code=not available.ok and available.code or nil}
        end
        if not Law.Current(a.value) then return Law.Err('session_expired','Character changed.') end
        table.sort(items,function(a,b) return a.key<b.key end);return Law.Ok({items=items,quota='one_per_item_per_utc_day'})
    end
}
Law.Routes['law.armory.claim.v1']={
    validate=function(p) return Payload(p,true) end,
    handler=function(p,source,context)
        if Law.Store.state~='ready' then return Law.Err('not_ready','Durable armory storage unavailable.') end
        local a=Access(p,source,context,false);if not a.ok then return a end
        local actor=a.value
        local requestId=actor.characterId..':'..p.requestId
        local claim=Law.Store.ArmoryGet(requestId)
        if not Law.Current(actor) then return Law.Err('session_expired','Character changed.') end
        if claim and (claim.character_id~=actor.characterId or claim.station_key~=p.stationKey or claim.item_key~=p.itemKey) then
            return Law.Err('idempotency_conflict','Armory intent is bound to different input.')
        end
        if claim and claim.result_json then return Law.Ok(json.decode(claim.result_json)) end
        local item=LawConfig.Armory.Stations[p.stationKey].items[p.itemKey]
        if not item then return Law.Err('item_unavailable','Item is not in this armory.') end
        local spec=Resolve(item);if not spec.ok then return spec end
        local present=Access(p,source,context,true);if not present.ok then return present end
        if not claim then claim=Law.Store.ArmoryReserve(actor,requestId,p.stationKey,p.itemKey,spec.value) end
        if not claim then return Law.Err('quota_exhausted','This item already has a claim for the current UTC day.') end
        if claim.character_id~=actor.characterId or claim.station_key~=p.stationKey or claim.item_key~=p.itemKey then
            return Law.Err('idempotency_conflict','Armory intent is bound to different input.')
        end
        local frozen=json.decode(claim.spec_json)
        for _,key in ipairs({'kind','definitionId','itemName','quantity'}) do
            if frozen[key]~=spec.value[key] then return Law.Err('idempotency_conflict','Armory configuration changed; reconcile the original intent.') end
        end
        present=Access(p,source,context,true);if not present.ok or not Law.Current(actor) then return present.ok and Law.Err('session_expired','Character changed.') or present end
        local result
        if frozen.kind=='item' then
            result=Law.Call('feather-inventory','GrantCharacterItemOnce',{grantId=requestId,characterId=actor.characterId,
                definitionId=frozen.definitionId,itemName=frozen.itemName,quantity=frozen.quantity})
        else
            result=Law.Call('feather-weapons','IssueWeapon',{requestId=requestId,characterId=actor.characterId,
                definitionId=frozen.definitionId,purpose='job_issue'},
                {actorSource=source,actorCharacterId=actor.characterId,characterId=actor.characterId,sessionId=actor.sessionId,reason='job_issue',correlationId=requestId})
        end
        if not result.ok and type(result.error)=='table' then result=Law.Err(result.error.code,result.error.message) end
        if not Law.Current(actor) then return Law.Err('session_expired','Character changed; retain the original claim ID.') end
        if not result.ok then return result end
        Law.Store.ArmoryConfirm(requestId,result.value)
        if not Law.Current(actor) then return Law.Err('session_expired','Character changed; retain the original claim ID.') end
        return result
    end
}
Law.Routes['law.armory.claims.v1']={
    validate=function(p) return Law.Fields(p,{department=true,stationKey=true,cursor=true}) and Law.Token(p.department,48)
        and Law.Token(p.stationKey,64) and (p.cursor==nil or Law.Token(p.cursor,128)) end,
    handler=function(p,source,context)
        if Law.Store.state~='ready' then return Law.Err('not_ready','Durable armory storage unavailable.') end
        local a=Access(p,source,context,false);if not a.ok then return a end
        local rows=Law.Store.ArmoryClaims(a.value.characterId,p.stationKey,p.cursor)
        if not Law.Current(a.value) then return Law.Err('session_expired','Character changed.') end
        local items={}
        for i=1,math.min(#rows,25) do items[i]={requestId=rows[i].request_id:sub(#a.value.characterId+2),
            itemKey=rows[i].item_key,period=rows[i].period_key,pending=tonumber(rows[i].pending)==1} end
        return Law.Ok({items=items,nextCursor=#rows>25 and rows[25].request_id or nil})
    end
}
