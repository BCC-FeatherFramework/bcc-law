-- Alerts to on-duty officers (Law master plan §3: badge, blips, alerts). A citizen
-- report (/lawalert) or a shots-fired report in a configured area reaches every
-- currently qualified officer of the department as a notification and a temporary
-- map blip. Positions are read server-side; the client never chooses coordinates.
local lastCitizen,lastArea={},{}
local function Number(v,a,b) return type(v)=='number' and v==v and v>=a and v<=b end
local function Alerts() return type(LawConfig.Alerts)=='table' and LawConfig.Alerts or nil end
function Law.ValidateAlertsConfig()
    local c=Alerts()
    if type(c)~='table' or not Number(c.CitizenCooldownSeconds,10,3600) or not Number(c.MaxMessageLength,10,500)
        or not Number(c.BlipSeconds,10,900) or type(c.ShotsFired)~='table' or type(c.ShotsFired.Areas)~='table'
        or not Number(c.ShotsFired.CooldownSeconds,10,3600) then return false end
    for key,a in pairs(c.ShotsFired.Areas) do
        if not Law.Token(key,64) or not LawConfig.Departments[a.department or ''] or not Law.Text(a.label,100)
            or not Number(a.x,-100000,100000) or not Number(a.y,-100000,100000) or not Number(a.z,-10000,10000)
            or not Number(a.radius,5,2000) then return false end
    end
    return true
end
function Law.AlertsAvailable() return Law.Ready() and Alerts()~=nil end
local function Position(source)
    local ped=GetPlayerPed(source)
    if not ped or ped==0 then return nil end
    local p=GetEntityCoords(ped)
    if not p or not Number(p.x,-100000,100000) or not Number(p.y,-100000,100000) or not Number(p.z,-10000,10000) then return nil end
    return {x=p.x,y=p.y,z=p.z}
end
-- Every online character currently on duty with the department's qualification.
function Law.OnDutyOfficers(departmentKey)
    local department=LawConfig.Departments[departmentKey or '']
    local officers={}
    if not department then return officers end
    for _,player in ipairs(GetPlayers()) do
        local source=tonumber(player)
        local session=Law.Call('feather-core','GetSessionContext',source)
        if session.ok and type(session.value)=='table' and Law.Uuid(session.value.characterId) then
            local actor={source=source,characterId=session.value.characterId,sessionId=session.value.sessionId,epoch=Law.Epoch}
            if Law.Current(actor) and Law.CheckQualification(actor,department).ok then officers[#officers+1]=actor end
        end
    end
    return officers
end
-- Each officer reads the alert in their own account language.
local function Notify(departmentKey,kind,key,vars,position,except)
    local seconds=Alerts().BlipSeconds
    local count=0
    for _,officer in ipairs(Law.OnDutyOfficers(departmentKey)) do
        if officer.source~=except then
            Law.Call('feather-core','SendNotification',{source=officer.source,style='right',
                message=Law.T(Law.SourceLocale(officer.source),key,vars),duration=8000})
            TriggerClientEvent('bcc-law:client:alert',officer.source,{kind=kind,x=position.x,y=position.y,z=position.z,seconds=seconds})
            count=count+1
        end
    end
    return count
end
Law.Routes['law.alerts.citizen.v1']={
    validate=function(p) return Law.Fields(p,{department=true,message=true}) and Law.Token(p.department,48)
        and Law.Text(p.message,(Alerts() or {}).MaxMessageLength or 200) end,
    handler=function(p,source,context)
        local actor=Law.Actor(source,context);if not actor.ok then return actor end
        if not LawConfig.Departments[p.department] then return Law.Err('department_unavailable','Department is not configured.') end
        local now=GetGameTimer()
        local last=lastCitizen[actor.value.characterId]
        if last and now-last<Alerts().CitizenCooldownSeconds*1000 then return Law.Err('rate_limited','Please wait before sending another report.') end
        local position=Position(source);if not position then return Law.Err('interaction_unavailable','Position unavailable.') end
        lastCitizen[actor.value.characterId]=now
        local delivered=Notify(p.department,'citizen','alert.citizen',{message=p.message},position,source)
        Law.Call('feather-core','SendNotification',{source=source,style='right',duration=6000,
            message=Law.T(Law.SourceLocale(source),delivered>0 and 'alert.sent' or 'alert.noOfficers',{count=delivered})})
        return Law.Ok({delivered=delivered})
    end
}
-- The client reports its own shooting; the server checks the shooter's real
-- position against the configured areas and rate-limits each area.
Law.Routes['law.alerts.shots.v1']={
    validate=function(p) return Law.Fields(p,{}) end,
    handler=function(_,source,context)
        local actor=Law.Actor(source,context);if not actor.ok then return actor end
        local c=Alerts().ShotsFired
        if not c.Enabled then return Law.Ok({delivered=0}) end
        local position=Position(source);if not position then return Law.Ok({delivered=0}) end
        for key,area in pairs(c.Areas) do
            if (position.x-area.x)^2+(position.y-area.y)^2+(position.z-area.z)^2<=area.radius^2 then
                -- On-duty officers of the area's department do not report themselves.
                if Law.CheckQualification(actor.value,LawConfig.Departments[area.department]).ok then return Law.Ok({delivered=0}) end
                local now=GetGameTimer()
                if lastArea[key] and now-lastArea[key]<c.CooldownSeconds*1000 then return Law.Ok({delivered=0}) end
                lastArea[key]=now
                return Law.Ok({delivered=Notify(area.department,'shots','alert.shots',{area=area.label},position,source)})
            end
        end
        return Law.Ok({delivered=0})
    end
}
Law.Routes['law.alerts.areas.v1']={
    validate=function(p) return Law.Fields(p,{}) end,
    handler=function(_,source,context)
        local actor=Law.Actor(source,context);if not actor.ok then return actor end
        local c=Alerts().ShotsFired
        local areas={}
        if c.Enabled then for key,a in pairs(c.Areas) do areas[#areas+1]={key=key,x=a.x,y=a.y,z=a.z,radius=a.radius} end end
        return Law.Ok({areas=areas})
    end
}
