-- Explicit console setup only. Startup never creates definitions, grants jobs,
-- issues qualifications or changes policy. Core must authorize the service.
RegisterCommand('LawSetupJurisdictions', function(source)
    if source ~= 0 then return end
    if not Law.Ready() or not Law.ValidateConfig() then
        print('[LawSetupJurisdictions] Law dependencies are not ready.'); return
    end
    local keys = {}; for key in pairs(LawConfig.Departments) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local department = LawConfig.Departments[key]
        local result = Law.Call('feather-justice', 'RegisterJurisdiction', {
            requestId = 'law-jurisdiction:' .. key .. ':v1', reasonCode = 'law.setup',
            recordKey = department.jurisdictionKey, label = department.label
        })
        print(('[LawSetupJurisdictions] department=%s result=%s'):format(key,
            result.ok and result.value.recordId or tostring(result.code)))
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

RegisterCommand('LawCitationPreflight',function(source,args)
    if source~=0 then return end
    local characterId=args and args[1]
    local department=args and args[2] or 'new_hanover'
    if not Law.Uuid(characterId) or not Law.Token(department,48) then
        print('[LawCitationPreflight] usage: LawCitationPreflight <characterUUID> [department]');return
    end
    for _,player in ipairs(GetPlayers()) do
        local actorSource=tonumber(player)
        local session=Law.Call('feather-core','GetSessionContext',actorSource)
        if session.ok and type(session.value)=='table' and type(session.value.characterId)=='string'
            and session.value.characterId:lower()==characterId:lower() then
            for _,action in ipairs({'justice.citation.view','justice.citation.issue','justice.citation.cancel'}) do
                local result=Law.Access(actorSource,session.value,department,action)
                print(('[LawCitationPreflight] action=%s result=%s'):format(action,result.ok and 'allowed' or tostring(result.code)))
            end
            return
        end
    end
    print('[LawCitationPreflight] character_not_in_active_session')
end,true)
