-- bcc-law integration tests on a real MariaDB scratch schema (see tests/run.py).
-- Real code: bcc-law and feather-justice, loaded as two resources with their own
-- environments and exports, plus the feather-admin policy configuration. Mocked at
-- their export boundary: Core (sessions, policy broker, RPC registry,
-- notifications), Character, Jobs, Licenses, Contracts, Inventory, Organizations,
-- bcc-doorlocks and the game world (players, positions, teleports).
local checks, failures = 0, 0
local JUSTICE = '../../[feather]/feather-justice/'
local ADMIN = '../../[feather]/feather-admin/'

-- JSON (objects, arrays, strings, numbers, booleans) -------------------------
json = {}
local function escape(s)
    return (s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format('\\u%04x', c:byte())
    end))
end
function json.encode(v)
    local t = type(v)
    if t == 'nil' then return 'null' elseif t == 'boolean' then return tostring(v)
    elseif t == 'number' then return (math.type(v) == 'integer' or v % 1 == 0) and string.format('%d', v) or string.format('%.17g', v)
    elseif t == 'string' then return '"' .. escape(v) .. '"' end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n > 0 and #v == n then
        local parts = {}
        for i = 1, #v do parts[i] = json.encode(v[i]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys, parts = {}, {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. escape(k) .. '":' .. json.encode(v[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
end
function json.decode(s)
    if type(s) ~= 'string' then return nil end
    local i = 1
    local function ws() i = s:find('[^ \t\r\n]', i) or #s + 1 end
    local value
    local function str()
        i = i + 1
        local out = {}
        while true do
            local c = s:sub(i, i)
            if c == '"' then i = i + 1; break end
            if c == '\\' then
                local n = s:sub(i + 1, i + 1)
                if n == 'u' then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = ({ n = '\n', r = '\r', t = '\t', b = '\b', f = '\f' })[n] or n; i = i + 2 end
            else out[#out + 1] = c; i = i + 1 end
        end
        return table.concat(out)
    end
    function value()
        ws()
        local c = s:sub(i, i)
        if c == '{' then
            i = i + 1; local o = {}; ws()
            if s:sub(i, i) == '}' then i = i + 1; return o end
            while true do ws(); local k = str(); ws(); i = i + 1; o[k] = value(); ws(); local d = s:sub(i, i); i = i + 1; if d == '}' then return o end end
        elseif c == '[' then
            i = i + 1; local a = {}; ws()
            if s:sub(i, i) == ']' then i = i + 1; return a end
            while true do a[#a + 1] = value(); ws(); local d = s:sub(i, i); i = i + 1; if d == ']' then return a end end
        elseif c == '"' then return str()
        elseif s:sub(i, i + 3) == 'true' then i = i + 4; return true
        elseif s:sub(i, i + 4) == 'false' then i = i + 5; return false
        elseif s:sub(i, i + 3) == 'null' then i = i + 4; return nil
        else
            local number = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
            i = i + #number
            return math.tointeger(tonumber(number)) or tonumber(number)
        end
    end
    return value()
end

-- Database through the bridge (one connection: Law and Justice share the schema) ---
local function Run(sql, ...)
    local packed, parts = table.pack(...), {}
    for index = 1, packed.n do parts[index] = json.encode(packed[index]) end
    local response = json.decode(__db('{"conn":1,"sql":' .. json.encode(sql) .. ',"params":[' .. table.concat(parts, ',') .. ']}'))
    if not response.ok then error({ code = 'QUERY_FAILED', message = response.error }, 0) end
    return response.rows or {}, response.affected
end
local function Api()
    local api = {}
    function api.query(sql, ...) return (Run(sql, ...)) end
    function api.one(sql, ...) return (Run(sql, ...))[1] end
    function api.value(sql, ...)
        local row = (Run(sql, ...))[1]
        if not row then return nil end
        local _, value = next(row)
        return value
    end
    function api.exec(sql, ...) local _, affected = Run(sql, ...); return affected or 0 end
    return api
end
DB = Api()
DB.isReady = function() return true end
DB.awaitReady = function() return true end
local depth = 0
function DB.transaction(callback)
    depth = depth + 1
    if depth > 1 then depth = depth - 1; error({ code = 'NESTED_TRANSACTION', message = 'nested transaction' }, 0) end
    Run('START TRANSACTION')
    local ok, result = pcall(callback, Api())
    if not ok or result ~= true then
        Run('ROLLBACK'); depth = depth - 1
        if not ok then error(result, 0) end
        return false
    end
    Run('COMMIT'); depth = depth - 1
    return true
end

-- Scheduler with virtual time: CreateThread queues like FXServer (the thread starts
-- on the next tick, after every file loaded); Wait inside a thread parks it until
-- its wake time; t.run(ms) advances the clock and runs every thread that is due.
local now, threads = 1000, {}
GetGameTimer = function() return now end
CreateThread = function(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = now } end
Wait = function(ms)
    local co, main = coroutine.running()
    local thread
    for _, th in ipairs(threads) do if th.co == co then thread = th end end
    if main or not thread then now = now + (ms or 0); return end
    coroutine.yield(math.max(tonumber(ms) or 0, 1))
end
local function Step(target)
    while true do
        local due
        for _, th in ipairs(threads) do
            if not th.dead and th.wake <= now and (not due or th.wake < due.wake) then due = th end
        end
        if due then
            local ok, slept = coroutine.resume(due.co)
            if not ok then due.dead = true; error(slept, 0) end
            if coroutine.status(due.co) == 'dead' then due.dead = true else due.wake = now + (tonumber(slept) or 1) end
        else
            local nextWake
            for _, th in ipairs(threads) do if not th.dead and (not nextWake or th.wake < nextWake) then nextWake = th.wake end end
            if not nextWake or nextWake > target then now = math.max(now, target); return end
            now = nextWake
        end
    end
end

-- Resources, exports and the invoking-resource stack ----------------------------
local resources, mocks, invoking = {}, {}, {}
GetInvokingResource = function() return invoking[#invoking] end
local function Invoke(caller, target, name, ...)
    local fn = mocks[target] and mocks[target][name] or (resources[target] and resources[target].exports[name])
    if not fn then error(('No such export %s in resource %s'):format(tostring(name), target), 0) end
    invoking[#invoking + 1] = caller
    local results = table.pack(pcall(fn, ...))
    invoking[#invoking] = nil
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end
local function Exports(caller)
    return setmetatable({}, {
        __call = function(_, name, fn) resources[caller].exports[name] = fn end,
        __index = function(_, target)
            return setmetatable({}, { __index = function(_, name)
                return function(_, ...) return Invoke(caller, target, name, ...) end
            end })
        end })
end
local commands, events, output = {}, {}, nil
local function Resource(name)
    local env = setmetatable({}, { __index = _G })
    resources[name] = { env = env, exports = {} }
    env.exports = Exports(name)
    env.GetCurrentResourceName = function() return name end
    env.RegisterCommand = function(command, fn) commands[command] = fn end
    env.AddEventHandler = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
    env.print = function(...)
        local parts = table.pack(...)
        for i = 1, parts.n do parts[i] = tostring(parts[i]) end
        local line = table.concat(parts, ' ')
        if output then output[#output + 1] = line else print(line) end
    end
    return env
end
local function Load(env, path) assert(loadfile(path, 't', env))() end
local started = {}
GetResourceState = function(name)
    if started[name] ~= nil then return started[name] and 'started' or 'stopped' end
    return (resources[name] or mocks[name]) and 'started' or 'missing'
end

-- Characters: the two offline test characters (UUIDs only; nobody connects).
local ION = '18477168-bfe5-11f1-8fad-020133902301'
local GIGI = 'a2cf3f23-c0dc-11f1-8fad-020133902301'
local function uuid(n) return ('8f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local characters = { [ION] = 'active', [GIGI] = 'active' }
-- Simulated sessions (server ids 5 and 6) with positions in the world.
local sessions = {
    [5] = { characterId = ION, accountId = uuid(91), sessionId = uuid(92), locale = 'ro' },
    [6] = { characterId = GIGI, accountId = uuid(93), sessionId = uuid(94), locale = 'en' }
}
local world = { [5] = { x = 0, y = 0, z = 0, health = 200, bucket = 0 }, [6] = { x = 1, y = 0, z = 0, health = 200, bucket = 0 } }
local teleports, clientEvents, notifications = {}, {}, {}
GetPlayers = function()
    local list = {}
    for source in pairs(sessions) do list[#list + 1] = tostring(source) end
    table.sort(list)
    return list
end
GetPlayerName = function(source) return sessions[tonumber(source)] and ('player' .. source) or nil end
GetPlayerPed = function(source) return world[tonumber(source)] and tonumber(source) + 1000 or 0 end
GetEntityCoords = function(ped)
    local p = world[ped - 1000]
    return p and { x = p.x, y = p.y, z = p.z } or nil
end
GetEntityHealth = function(ped) local p = world[ped - 1000]; return p and p.health or 0 end
GetPlayerRoutingBucket = function(source) return (world[tonumber(source)] or {}).bucket or 0 end
SetEntityCoords = function(ped, x, y, z)
    local p = world[ped - 1000]
    p.x, p.y, p.z = x, y, z
    teleports[#teleports + 1] = { source = ped - 1000, x = x, y = y, z = z }
end
TriggerClientEvent = function(name, source, payload) clientEvents[#clientEvents + 1] = { name = name, source = source, payload = payload } end

-- Policy: feather-admin's real configuration, applied as its provider does.
local adminEnv = setmetatable({ Config = {} }, { __index = _G })
Load(adminEnv, ADMIN .. 'configs/service_policy.lua')
Load(adminEnv, ADMIN .. 'configs/law_acceptance_policy.lua')
local servicePolicy, lawPolicy = adminEnv.Config.servicePolicy, adminEnv.Config.lawAcceptancePolicy
local adminAudit = {}
local function Decision(allowed, code) return { ok = true, value = { allowed = allowed == true, code = code } } end
local function Authorize(action, context)
    local caller = invoking[#invoking]
    local subject = type(context) == 'table' and context.subject or nil
    if context.source == 0 then
        local grants = servicePolicy[caller] and type(subject) == 'table' and servicePolicy[caller][subject.resource]
        return Decision(type(grants) == 'table' and grants[action] == true, 'service')
    end
    local s = sessions[context.source]
    if not s or not lawPolicy.actions[action] then return Decision(false, 'unknown_action') end
    if action == 'justice.audit.view' and not adminAudit[s.characterId] then return Decision(false, 'forbidden') end
    local delegated = { source = context.source, accountId = s.accountId, characterId = s.characterId, sessionId = s.sessionId,
        caller = caller, subject = subject, system = false }
    local result = Invoke('feather-admin', 'bcc-law', 'EvaluateActionPolicy', action, delegated)
    if type(result) ~= 'table' or not result.ok then return Decision(false, 'law_policy_unavailable') end
    return Decision(result.value.allowed, result.value.code)
end

local rpcs, published = {}, {}
mocks['feather-core'] = {
    GetHealth = function() return { ok = true, value = { state = 'ready' } } end,
    AwaitReady = function() return { ok = true, value = { state = 'ready' } } end,
    GetCapabilities = function() return { ok = true, value = { contract = 1 } } end,
    DeclareEvent = function() return { ok = true, value = {} } end,
    PublishEvent = function(name, payload) published[#published + 1] = { name = name, payload = payload }; return { ok = true, value = {} } end,
    SubscribeEvent = function() return { ok = true, value = { token = 'test' } } end,
    GetSessionContext = function(source)
        local s = sessions[source]
        if not s then return { ok = false, code = 'not_found' } end
        return { ok = true, value = { characterId = s.characterId, accountId = s.accountId, sessionId = s.sessionId } }
    end,
    IsSessionCurrent = function(source, sessionId, characterId)
        local s = sessions[source]
        return s ~= nil and s.sessionId == sessionId and s.characterId == characterId
    end,
    Authorize = Authorize,
    GetProvider = function()
        return { ok = true, value = { implementation = { GetIdentity = function(id)
            if not characters[id] then return { ok = false, code = 'not_found' } end
            return { ok = true, value = { characterId = id, status = characters[id] } }
        end } } }
    end,
    RegisterRpc = function(name, handler, options) rpcs[name] = { handler = handler, options = options }; return { ok = true, value = {} } end,
    SendNotification = function(request) notifications[#notifications + 1] = request; return { ok = true, value = {} } end,
    GetAccountSettings = function(source)
        local s = sessions[source]
        return s and { ok = true, value = { locale = s.locale } } or { ok = false, code = 'not_found' }
    end
}
mocks['feather-character'] = {
    GetHealth = function() return { ok = true, value = { state = 'ready' } } end,
    GetMedicalReadySession = function(source)
        local s = sessions[source]
        return s and { ok = true, value = { characterId = s.characterId, sessionId = s.sessionId } } or { ok = false, code = 'not_spawned' }
    end
}
-- Jobs and Licenses: Ion is an on-duty police officer and a judge; Gigi has neither.
local jobs = { [ION] = { police = true, judge = true } }
local licenses = { [ION] = { peace_officer = true, judicial_commission = true } }
mocks['feather-jobs'] = {
    GetHealth = function() return { ok = true, value = { state = 'ready' } } end,
    CheckAssignment = function(r)
        return { ok = true, value = { matched = (jobs[r.characterId] or {})[r.jobKey] == true and r.dutyState == 'on_duty' } }
    end
}
mocks['feather-licenses'] = {
    GetHealth = function() return { ok = true, value = { state = 'ready' } } end,
    CheckLicense = function(r)
        return { ok = true, value = { matched = (licenses[r.holderId] or {})[r.licenseKey] == true, scopeVersion = 1, scope = {} } }
    end
}
local obligations, drafts, serial = {}, {}, 0
local function copy(v) if type(v) ~= 'table' then return v end local c = {} for k, x in pairs(v) do c[k] = copy(x) end return c end
mocks['feather-contracts'] = {
    RegisterObligationType = function(definition) return { ok = true, value = { typeKey = definition.typeKey } } end,
    CreateDraft = function(p)
        if drafts[p.requestId] then return { ok = true, value = copy(obligations[drafts[p.requestId]]) } end
        serial = serial + 1
        local id = uuid(5000 + serial)
        obligations[id] = { obligationId = id, obligationType = p.obligationType, issuerResource = 'feather-justice', issuer = p.issuer,
            debtor = p.debtor, creditor = p.creditor, amount = p.amount, currency = p.currency, dueInSeconds = p.dueInSeconds,
            referenceType = p.referenceType, referenceId = p.referenceId, status = 'draft', requiresAcceptance = false,
            debtorMaySettle = true, issuerMaySettle = false, debtorMayDispute = false }
        drafts[p.requestId] = id
        return { ok = true, value = copy(obligations[id]) }
    end,
    IssueObligation = function(p)
        local o = obligations[p.obligationId]; if o.status == 'draft' then o.status = 'issued' end
        return { ok = true, value = copy(o) }
    end,
    CancelObligation = function(p) local o = obligations[p.obligationId]; o.status = 'cancelled'; return { ok = true, value = copy(o) } end,
    GetObligation = function(p) return obligations[p.obligationId] and { ok = true, value = copy(obligations[p.obligationId]) } or { ok = false, code = 'obligation_not_found' } end
}
mocks['feather-organizations'] = { GetOrganization = function() return { ok = false, code = 'organization_not_found' } end }
-- bcc-doorlocks: doors 12 and 13 exist and start unlocked.
local doors = {}
for _, id in ipairs({ 12, 13 }) do
    doors[id] = { id = id, locked = false, IsLocked = function(self) return self.locked end,
        UpdateLockStatus = function(self, value) self.locked = value end }
end
mocks['bcc-doorlocks'] = { getDoorLocksAPI = function()
    return { GetDoorById = function(_, id) return doors[id] end }
end }

-- Inventory: instances owned by characters or lockers; guards registered by Justice.
local items = { [501] = { name = 'evidence_knife', owner = GIGI, revision = 3 }, [502] = { name = 'evidence_letter', owner = GIGI, revision = 1 } }
local guards, receipts, dispositions, full = {}, {}, {}, {}
local function InvErr(code, message) return { ok = false, error = { code = code, message = message or code } } end
local function LawAuth(name, ...) return Invoke('feather-inventory', 'bcc-law', name, ...) end
mocks['feather-inventory'] = {
    initiate = function() return {
        Instances = { GetInstance = function(id)
            if items[id] then return { ok = true, value = { id = id, definition = { name = items[id].name } } } end
            return { ok = false, error = { code = 'not_found' } }
        end },
        Guards = { RegisterDestroyGuard = function(name, fn) guards[name] = fn; return { ok = true, value = true } end,
            UnregisterDestroyGuard = function(name) guards[name] = nil end } } end,
    GetHealth = function() return { ok = true, value = { state = 'ready' } } end,
    GetLawSearchCapabilities = function() return { ok = true, value = { contract = 1, state = 'ready', readOnly = true, maxPageSize = 25 } } end,
    InspectLawSearch = function(request)
        local access = LawAuth('AuthorizeInventorySearch', request)
        if not access.ok then return InvErr('authorization_denied') end
        local list = {}
        for id, item in pairs(items) do
            if item.owner == access.value.target.characterId then list[#list + 1] = { instanceId = id, revision = item.revision, itemName = item.name, label = item.name } end
        end
        table.sort(list, function(a, b) return a.instanceId < b.instanceId end)
        return { ok = true, value = { items = list } }
    end,
    GetLawEvidenceCapabilities = function() return { ok = true, value = { contract = 1, state = 'ready', transfers = 1, receipts = 1,
        lockerSetup = 1, returns = 1, destruction = 1 } } end,
    SetupLawEvidenceLocker = function(p)
        local access = LawAuth('AuthorizeEvidenceOperation', 'setup', p)
        return access.ok and { ok = true, value = { lockerKey = p.lockerKey } } or InvErr('authorization_denied')
    end,
    CollectLawEvidence = function(p)
        local stored = receipts[p.requestId]
        if stored then return { ok = true, value = copy(stored) } end
        local access = LawAuth('AuthorizeEvidenceOperation', 'collect', p)
        if not access.ok then return InvErr(access.code) end
        local item = items[p.itemId]
        if not item or item.owner ~= access.value.target.characterId or item.revision ~= p.itemRevision then return InvErr('revision_conflict') end
        item.owner, item.revision = 'locker:' .. p.lockerKey, item.revision + 1
        local value = { requestId = p.requestId, actorCharacterId = p.characterId, subjectCharacterId = access.value.target.characterId,
            caseId = p.caseId, department = p.department, itemId = p.itemId, itemRevision = item.revision, itemName = item.name,
            lockerKey = p.lockerKey, description = p.description }
        receipts[p.requestId] = value
        return { ok = true, value = copy(value) }
    end,
    GetLawEvidenceReceipt = function(p)
        return receipts[p.requestId] and { ok = true, value = copy(receipts[p.requestId]) } or InvErr('not_found')
    end,
    ListLawEvidenceReceipts = function(p)
        local list = {}
        for id, r in pairs(receipts) do if r.caseId == p.caseId then list[#list + 1] = { requestId = id, receipt = copy(r), createdAt = 'now' } end end
        return { ok = true, value = { items = list } }
    end,
    ReturnLawEvidence = function(p)
        if dispositions[p.requestId] then return { ok = true, value = copy(dispositions[p.requestId]) } end
        local access = LawAuth('AuthorizeEvidenceOperation', 'dispose', { evidenceLinkId = p.evidenceLinkId, itemId = p.itemId, disposition = 'returned' })
        if not access.ok then return InvErr('authorization_denied') end
        local item = items[p.itemId]
        if not item then return InvErr('not_found') end
        if not tostring(item.owner):find('^locker:') then return InvErr('not_in_locker') end
        if full[p.recipientCharacterId] then return InvErr('inventory_full', 'Inventory has no available slots.') end
        item.owner, item.revision = p.recipientCharacterId, item.revision + 1
        dispositions[p.requestId] = { requestId = p.requestId, itemId = p.itemId, action = 'returned', recipientCharacterId = p.recipientCharacterId }
        return { ok = true, value = copy(dispositions[p.requestId]) }
    end,
    DestroyLawEvidence = function(p)
        if dispositions[p.requestId] then return { ok = true, value = copy(dispositions[p.requestId]) } end
        local access = LawAuth('AuthorizeEvidenceOperation', 'dispose', { evidenceLinkId = p.evidenceLinkId, itemId = p.itemId, disposition = 'destroyed' })
        if not access.ok then return InvErr('authorization_denied') end
        for _, guard in pairs(guards) do
            if guard({ id = p.itemId }) == false then return InvErr('denied', 'Removal blocked by a guard.') end
        end
        items[p.itemId] = nil
        dispositions[p.requestId] = { requestId = p.requestId, itemId = p.itemId, action = 'destroyed' }
        return { ok = true, value = copy(dispositions[p.requestId]) }
    end
}
started['feather-medical'], started['feather-weapons'] = nil, nil

-- Load feather-justice, then bcc-law, in manifest order ----------------------------
local justiceEnv = Resource('feather-justice')
Load(justiceEnv, JUSTICE .. 'config.lua')
for file in io.open(JUSTICE .. 'fxmanifest.lua'):read('a'):match('server_scripts%s*(%b{})'):gmatch("'(server/[%w_]+%.lua)'") do
    Load(justiceEnv, JUSTICE .. file)
end
local J = justiceEnv.Justice
J.Migrate()
J.State('ready', 'tests')
J.ReloadEvidenceIndex()
J.InstallEvidenceGuard()

local lawEnv = Resource('bcc-law')
local manifest = io.open('fxmanifest.lua'):read('a')
for file in manifest:match('shared_scripts%s*(%b{})'):gmatch("'([%w_/]+%.lua)'") do Load(lawEnv, file) end
for file in manifest:match('server_scripts%s*(%b{})'):gmatch("'([%w_/]+%.lua)'") do Load(lawEnv, file) end
local Law = lawEnv.Law
LawLocalesForTests = lawEnv.LawLocales
Step(now + 10)

-- Test context ---------------------------------------------------------------
local t = { ion = ION, gigi = GIGI, uuid = uuid, J = J, Law = Law, LawConfig = lawEnv.LawConfig, sessions = sessions, world = world,
    jobs = jobs, licenses = licenses, items = items, full = full, doors = doors, teleports = teleports, clientEvents = clientEvents,
    notifications = notifications, rpcs = rpcs, adminAudit = adminAudit, obligations = obligations, sql = Api(), published = published }
function t.check(label, condition, detail)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print('FAIL ' .. t.suite .. ': ' .. label .. (detail ~= nil and (' (' .. tostring(detail) .. ')') or ''))
    end
    return condition
end
function t.code(result) return type(result) ~= 'table' and tostring(result) or result.ok and 'ok' or tostring(result.code) end
local requestSerial = 0
function t.rid() requestSerial = requestSerial + 1; return 'req-' .. requestSerial end
-- A client RPC from a simulated player, as Core would deliver it.
function t.rpc(source, route, payload, mutation)
    local spec = assert(rpcs[route], 'route ' .. route)
    payload = payload or {}
    if mutation and payload.requestId == nil then payload.requestId = t.rid() end
    local s = sessions[source]
    return spec.handler(payload, source, s and { characterId = s.characterId, sessionId = s.sessionId } or nil)
end
-- Officer routes carry the department.
function t.law(source, route, payload, mutation)
    payload = payload or {}
    payload.department = payload.department or 'new_hanover'
    return t.rpc(source, route, payload, mutation)
end
function t.command(name, args)
    output = {}
    local ok, err = pcall(assert(commands[name], 'command ' .. name), 0, args or {}, '')
    local lines = output
    output = nil
    if not ok then error(err, 0) end
    return lines
end
function t.run(ms) Step(now + ms) end
function t.place(source, x, y, z) local p = world[source]; p.x, p.y, p.z = x, y, z end
function t.ago(tableName, column, idColumn, id, ms)
    t.sql.exec('UPDATE ' .. tableName .. ' SET ' .. column .. '=? WHERE ' .. idColumn .. '=?', J.Repo.Now(DB.value) - ms, id)
end
function t.service(name, request) return Invoke('bcc-law', 'feather-justice', name, request) end
function t.invoke(caller, target, name, ...) return Invoke(caller, target, name, ...) end

local suites = {}
local listing = io.popen('ls tests/suite/*.lua 2>/dev/null')
-- a_ and b_ (lifecycle and setup) always run: later suites need the jurisdiction and statutes.
for path in listing:lines() do
    if __suite == '' or path:find(__suite, 1, true) or path:find('/[ab]_') then suites[#suites + 1] = path end
end
listing:close()
table.sort(suites)
for _, path in ipairs(suites) do
    t.suite = path:match('([%w_]+)%.lua$')
    local before = checks
    local ok, err = pcall(dofile(path), t)
    if not ok then
        failures = failures + 1
        print('FAIL ' .. t.suite .. ': aborted: ' .. tostring(type(err) == 'table' and (tostring(err.code) .. ' ' .. tostring(err.message)) or err))
    end
    print(('suite %-14s %d checks'):format(t.suite, checks - before))
end
print(('%s bcc-law: %d checks, %d failed (real MariaDB and Justice, mocked dependencies)'):format(failures == 0 and 'PASS' or 'FAIL', checks, failures))
if failures > 0 then error('tests failed', 0) end
