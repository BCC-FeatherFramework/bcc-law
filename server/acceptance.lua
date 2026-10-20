-- LawAcceptanceTest: console-only, nobody needs to be online (character UUIDs).
-- Read-only preflight first; then development checks of Law's own tables on the
-- real database (always cleaned up). Legal workflows themselves are covered by
-- Justice's JusticeAcceptanceTest; player policy, presence and visuals by the
-- two-player in-game checklist in docs/ACCEPTANCE_TESTS.md.
local running=false
local function Reporter()
    local counts={passed=0,failed=0,skipped=0}
    local function Line(label,status,detail)
        local key=status=='PASS' and 'passed' or status=='FAIL' and 'failed' or 'skipped'
        counts[key]=counts[key]+1
        print(('[LawAcceptanceTest] %-62s %s%s'):format(label,status,detail~=nil and ('  ('..tostring(detail):gsub('%c',' ')..')') or ''))
        return status=='PASS'
    end
    return {
        check=function(label,condition,detail) return Line(label,condition and 'PASS' or 'FAIL',not condition and detail or nil) end,
        skip=function(label,detail) return Line(label,'SKIP',detail) end,
        info=function(text) print('[LawAcceptanceTest] INFO '..text) end,
        counts=counts,
        done=function() print(('[LawAcceptanceTest] RESULT %d passed, %d failed, %d skipped'):format(counts.passed,counts.failed,counts.skipped)) end
    }
end
local function Identity(characterId)
    local provider=Law.Call('feather-core','GetProvider','character-profile',nil,1)
    local impl=provider.ok and type(provider.value)=='table' and provider.value.implementation
    if type(impl)~='table' or impl.GetIdentity==nil then return Law.Err('character_provider_unavailable','Identity provider unavailable.') end
    local called,result=pcall(impl.GetIdentity,characterId)
    if not called or type(result)~='table' or not result.ok or type(result.value)~='table' or result.value.status~='active' then
        return Law.Err('character_not_active','Existing active Character UUID required.')
    end
    return result
end
local function Preflight(r)
    r.check('Law ready',Law.Ready(),Law.Health().value.phase)
    r.check('configuration valid',Law.ValidateConfig())
    local justice=Law.JusticeContract()
    r.check("Justice publishes the plan's Contract 1 (feather.justice v1)",justice~=nil)
    r.check('Law store ready',Law.Store.state=='ready',Law.Store.state)
    if Law.Store.state=='ready' then
        local rows,expected=Law.Store.Migrations()
        local ledger={}
        for _,row in ipairs(rows) do ledger[tonumber(row.version)]=row.checksum end
        for version,checksum in pairs(expected) do r.check('Law migration v'..version..' checksum',ledger[version]==checksum,ledger[version] and 'drift' or 'missing') end
    end
    for key,department in pairs(LawConfig.Departments) do
        local jurisdiction=Law.Call('feather-justice','GetJurisdiction',{jurisdictionKey=department.jurisdictionKey})
        if r.check('jurisdiction '..department.jurisdictionKey..' registered',jurisdiction.ok,jurisdiction.code=='not_found'
            and 'run LawSetupJurisdictions' or jurisdiction.code) then
            local statutes=Law.Call('feather-justice','ListStatutes',{jurisdictionId=jurisdiction.value.jurisdictionId,status='active',limit=25})
            r.check('department '..key..' has active statutes',statutes.ok and #statutes.value.items>0,
                statutes.ok and 'run LawSetupStatutes or add statutes in the MDT' or statutes.code)
        end
    end
    r.info(('optional providers: search=%s evidence=%s armory=%s doors=%s jail=%s'):format(tostring(Law.SearchAvailable()),
        tostring(Law.EvidenceAvailable()),tostring(Law.ArmoryAvailable()),tostring(Law.DoorsAvailable()),tostring(Law.ExecutionAvailable())))
end
local function Qualification(r,label,characterId)
    for key,department in pairs(LawConfig.Departments) do
        local officer=Law.CheckQualification({characterId=characterId},department)
        r.info(('%s %s officer=%s'):format(label,key,officer.ok and 'qualified' or tostring(officer.code)))
        if department.judicial then
            local judge=Law.CheckQualification({characterId=characterId},department.judicial)
            r.info(('%s %s judge=%s'):format(label,key,judge.ok and 'qualified' or tostring(judge.code)))
        end
    end
end
-- Development checks of Law's own tables. Keys use a fresh run id and are removed.
local function Store(r,characterId)
    if Law.Store.state~='ready' then return r.skip('Law tables','store not ready') end
    local run='accept-'..tostring(GetGameTimer())..'-'..math.random(1000,9999)
    local key=characterId..':law.test.v1:'..run
    Law.Store.Remember(key,'payload-a',characterId,'law.test.v1',{kind='case',recordId=run,replayed=true})
    local replay=Law.Store.Journal(key,'payload-a',characterId)
    r.check('journal replays a confirmed result',type(replay)=='table' and replay.recordId==run)
    r.check('journal refuses a changed payload under the same ID',Law.Store.Journal(key,'payload-b',characterId)=='conflict')
    r.check('journal is bound to the character',Law.Store.Journal(key,'payload-a','00000000-0000-4000-8000-000000000000')=='conflict')
    local sentenceId=('00000000-0000-4000-8000-%012d'):format(math.random(1,999999))
    local first=Law.Store.CompleteUnit(characterId,sentenceId,2,1)
    local duplicate=Law.Store.CompleteUnit(characterId,sentenceId,2,1)
    local progress=Law.Store.ServiceProgress(sentenceId)
    r.check('a service unit is counted once',first=='active' and duplicate=='active' and progress and progress.completed_units==1)
    r.check('the last unit queues completion',Law.Store.CompleteUnit(characterId,sentenceId,2,2)=='completing')
    -- A placement marker drives jail teleports, so it is only exercised while the
    -- character is offline; an existing marker is restored afterwards.
    if Law.SessionForCharacter(characterId).ok then
        r.skip('jail placement marker','character is online')
    else
        local existing=Law.Store.Get(characterId)
        Law.Store.Place(characterId,sentenceId,'acceptance')
        local marker=Law.Store.Get(characterId)
        r.check('jail placement marker persisted',marker and marker.sentence_id==sentenceId)
        Law.Store.Clear(characterId)
        r.check('jail placement marker cleared',Law.Store.Get(characterId)==nil)
        if existing then Law.Store.Place(characterId,existing.sentence_id,existing.facility_key) end
    end
    -- Cleanup of this run's rows only (development records).
    DB.exec('DELETE FROM bcc_law_operations WHERE journal_key=?',key)
    DB.exec('DELETE FROM bcc_law_service_tasks WHERE sentence_id=?',sentenceId)
    DB.exec('DELETE FROM bcc_law_service_progress WHERE sentence_id=?',sentenceId)
end
-- Jail decision for one character from Justice's authoritative status (no teleport).
local function Execution(r,characterId)
    if not Law.ExecutionAvailable() then return r.skip('jail placement decision','execution unavailable') end
    local custody=Law.Call('feather-justice','GetCustodyStatus',{subjectCharacterId=characterId})
    if not r.check('custody status readable without a player (service mode)',custody.ok,custody.code) then return end
    local s=custody.value.custodialSentence
    local confined=s and s.status=='active' and custody.value.serverTime<s.endsAt
    r.info(('subject %s: confined=%s remaining=%ds custody=%s'):format(characterId,tostring(confined==true),
        confined and math.floor((s.endsAt-custody.value.serverTime)/1000) or 0,custody.value.custody and custody.value.custody.status or 'none'))
    local sentences=Law.Call('feather-justice','ListActiveSentences',{defendantCharacterId=characterId,limit=25})
    r.check('active sentences readable without a player (service mode)',sentences.ok,sentences.code)
end
RegisterCommand('LawAcceptanceTest',function(source,args)
    if source~=0 then return end
    if running then print('[LawAcceptanceTest] already running');return end
    local actorId=args[1] and args[1]:lower()
    local subjectId=args[2] and args[2]:lower()
    if (actorId and not Law.Uuid(actorId)) or (subjectId and not Law.Uuid(subjectId)) then
        print('[LawAcceptanceTest] usage: LawAcceptanceTest [officerUuid] [subjectUuid]');return
    end
    running=true
    local r=Reporter()
    local ok,err=pcall(function()
        print('[LawAcceptanceTest] read-only preflight')
        Preflight(r)
        for label,id in pairs({officer=actorId,subject=subjectId}) do
            if id then
                local identity=Identity(id)
                if r.check(label..' character exists and is active',identity.ok,identity.code) then Qualification(r,label,id) end
            end
        end
        if actorId then
            print('[LawAcceptanceTest] development checks of Law tables (cleaned up)')
            Store(r,actorId)
        else r.skip('Law tables','pass an officer UUID') end
        if subjectId then Execution(r,subjectId) else r.skip('jail placement decision','pass a subject UUID') end
    end)
    running=false
    if not ok then r.check('acceptance completed',false,tostring(err):match('^[^\n]*')) end
    r.done()
end,true)
