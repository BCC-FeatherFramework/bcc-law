-- Bootstrap housekeeping. Lifecycle and route registration live in routes.lua.
-- The operation journal only needs to outlive a client's retry window.
CreateThread(function()
    while true do
        Wait(3600000)
        if Law.Store.state == 'ready' then pcall(Law.Store.PurgeJournal, 7) end
    end
end)
