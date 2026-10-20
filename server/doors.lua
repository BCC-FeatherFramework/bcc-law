-- Facility doors through bcc-doorlocks (Law master plan: one owner per door).
-- Law never toggles doors in a loop; it only asks doorlocks to lock a facility's
-- configured cell doors when a subject is booked or placed in jail.
local function Facilities() return type(LawConfig.Doors)=='table' and LawConfig.Doors.Facilities or nil end
function Law.ValidateDoorsConfig()
    local facilities=Facilities()
    if type(facilities)~='table' then return false end
    for key,doors in pairs(facilities) do
        if not Law.Token(key,64) or (not LawConfig.Custody.Facilities[key] and not LawConfig.Execution.Facilities[key])
            or type(doors)~='table' or #doors>32 then return false end
        for _,id in ipairs(doors) do if type(id)~='number' or id%1~=0 or id<1 then return false end end
    end
    return true
end
function Law.DoorsAvailable()
    local facilities=Facilities()
    return GetResourceState('bcc-doorlocks')=='started' and type(facilities)=='table' and next(facilities)~=nil
end
function Law.LockFacility(facilityKey)
    local doors=(Facilities() or {})[facilityKey or '']
    if not doors or GetResourceState('bcc-doorlocks')~='started' then return 0 end
    local ok,api=pcall(function() return exports['bcc-doorlocks']:getDoorLocksAPI() end)
    if not ok or type(api)~='table' then return 0 end
    local locked=0
    for _,id in ipairs(doors) do
        local found,door=pcall(function() return api:GetDoorById(id) end)
        if found and type(door)=='table' then
            local isLocked=pcall(function() return door:IsLocked() end) and door.locked
            if not isLocked then
                if pcall(function() door:UpdateLockStatus(true) end) then locked=locked+1 end
            end
        end
    end
    return locked
end
