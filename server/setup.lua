-- Explicit console setup only. Startup never creates definitions, grants jobs,
-- issues qualifications or changes policy. Core must authorize the service
-- (feather-admin service policy: ['feather-justice']['bcc-law'] justice.definition.manage).
local function Departments()
    local keys = {}; for key in pairs(LawConfig.Departments) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
RegisterCommand('LawSetupJurisdictions', function(source)
    if source ~= 0 then return end
    if not Law.Ready() or not Law.ValidateConfig() then
        print('[LawSetupJurisdictions] Law dependencies are not ready.'); return
    end
    for _, key in ipairs(Departments()) do
        local department = LawConfig.Departments[key]
        local result = Law.Call('feather-justice', 'RegisterJurisdiction', {
            requestId = 'law-jurisdiction:' .. key .. ':v2', reasonCode = 'law.setup',
            jurisdictionKey = department.jurisdictionKey, label = department.label,
            jurisdictionType = department.jurisdictionType or 'county'
        })
        -- A rerun replays the original request (replayed) or meets the existing key.
        local existing = (result.ok and result.value.replayed == true) or (not result.ok and result.code == 'key_conflict')
        print(('[LawSetupJurisdictions] department=%s result=%s'):format(key,
            existing and 'already_registered' or (result.ok and result.value.jurisdictionId or tostring(result.code))))
    end
end, true)

-- Seeds the configured penal code. Each statute keeps a stable request ID, so a
-- rerun replays; judges revise statutes afterwards in the MDT (Justice ReviseStatute).
local severities = { infraction = true, misdemeanor = true, felony = true }
function Law.ValidateStatuteConfig()
    local seeds = LawConfig.Statutes
    if seeds == nil then return true end
    if type(seeds) ~= 'table' then return false end
    for department, list in pairs(seeds) do
        if not LawConfig.Departments[department] or type(list) ~= 'table' or #list > 200 then return false end
        for _, s in ipairs(list) do
            if type(s) ~= 'table' or type(s.name) ~= 'string' or not s.name:match('^[a-z][a-z0-9_.]*$') or #s.name > 48
                or not Law.Text(s.title, 180) or not Law.Token(s.category, 32) or not severities[s.severityClass or '']
                or (s.description ~= nil and not Law.Text(s.description, 4000)) then return false end
        end
    end
    return true
end
RegisterCommand('LawSetupStatutes', function(source)
    if source ~= 0 then return end
    if not Law.Ready() or not Law.ValidateConfig() then print('[LawSetupStatutes] Law dependencies are not ready.'); return end
    for _, key in ipairs(Departments()) do
        local department = LawConfig.Departments[key]
        local jurisdiction = Law.Call('feather-justice', 'GetJurisdiction', { jurisdictionKey = department.jurisdictionKey })
        if not jurisdiction.ok then
            print(('[LawSetupStatutes] department=%s jurisdiction=%s (run LawSetupJurisdictions first)'):format(key, tostring(jurisdiction.code)))
        else
            local created, existing, failed = 0, 0, 0
            for _, s in ipairs((LawConfig.Statutes or {})[key] or {}) do
                local result = Law.Call('feather-justice', 'RegisterStatute', {
                    requestId = 'law-statute:' .. key .. ':' .. s.name .. ':v1', reasonCode = 'law.setup',
                    jurisdictionId = jurisdiction.value.jurisdictionId, statuteKey = department.jurisdictionKey .. '.' .. s.name,
                    title = s.title, description = s.description, category = s.category, severityClass = s.severityClass,
                    recommendedFine = s.recommendedFine, recommendedCustodySeconds = s.recommendedCustodySeconds })
                if result.ok and result.value.replayed ~= true then created = created + 1
                elseif result.ok or result.code == 'key_conflict' then existing = existing + 1
                else failed = failed + 1; print(('[LawSetupStatutes] %s.%s failed=%s'):format(key, s.name, tostring(result.code))) end
            end
            print(('[LawSetupStatutes] department=%s registered=%d alreadyPresent=%d failed=%d'):format(key, created, existing, failed))
        end
    end
end, true)

-- Characters are selected by UUID; Cfx source is resolved only as transport.
RegisterCommand('LawActiveCharacters',function(source)
    if source~=0 then return end
    local count=0
    for _,player in ipairs(GetPlayers()) do
        local actorSource=tonumber(player)
        local session=Law.Call('feather-core','GetSessionContext',actorSource)
        if session.ok and type(session.value)=='table' and Law.Uuid(session.value.characterId)
            and Law.Uuid(session.value.sessionId) then
            local actor=Law.Actor(actorSource,session.value)
            if actor.ok then
                count=count+1
                print(('[LawActiveCharacters] source=%d characterUUID=%s'):format(actorSource,actor.value.characterId))
            end
        end
    end
    print(('[LawActiveCharacters] activeSessions=%d'):format(count))
end,true)
