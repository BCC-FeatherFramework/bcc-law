-- Acceptance-command orchestration tests. API/domain behavior is mocked here;
-- the other suites exercise actual Law handlers and installed Contracts routes.
local checks=0
local function check(label,value) checks=checks+1;assert(value,label) end
local A=os.getenv('FEATHER_TEST_ACTOR_UUID') or 'c6f393fb-5388-4ebe-a8d5-b285d4c77614'
local B=os.getenv('FEATHER_TEST_SUBJECT_UUID') or '6181a137-046a-4239-a110-a362d9561b1b'
local function fixture(options)
    options=options or {}
    local env=setmetatable({},{__index=_G})
    local output,commands,threads,ledger,receipts,writes={},{},{},{},{},0
    local nextId,clock,permission=0,0,true
    local function copy(value) if type(value)~='table' then return value end;local n={};for k,v in pairs(value) do n[k]=copy(v) end;return n end
    local function ok(v) return {ok=true,value=copy(v)} end
    local function err(code) return {ok=false,code=code} end
    local function id() nextId=nextId+1;return ('5b287410-080c-4a75-a4f5-%012x'):format(nextId) end
    local jurisdiction='56f02f1a-39ca-480a-97b2-042e599567f5'
    env.print=function(line) output[#output+1]=line end
    env.GetPlayers=function() return options.offlineA and {'2'} or (options.offlineB and {'1'} or {'1','2'}) end
    env.GetGameTimer=function() return clock end
    env.Wait=function(ms) clock=clock+ms;if options.yield then coroutine.yield() end end
    env.CreateThread=function(fn) threads[#threads+1]=coroutine.create(fn) end
    env.RegisterCommand=function(name,handler) commands[name]=handler end
    assert(loadfile('shared/results.lua','t',env))()
    local L=env.Law
    env.LawConfig={Departments={new_hanover={jobKey='police',minGradeOrdinal=0,licenseKey='peace_officer',jurisdictionKey='bcc-law:new_hanover'}}}
    L.Ready=function() return true end;L.ValidateConfig=function() return true end
    L.Actor=function(source,context) return ok({source=source,characterId=context.characterId,sessionId=context.sessionId}) end
    L.Current=function() return true end
    L.Access=function() return permission and ok({jurisdictionId=jurisdiction}) or err('duty_required') end
    local function snapshot(kind,status,document,caseId,subject)
        local v={recordId=id(),kind=kind,status=status,revision=1,document=document or {},caseId=caseId,subjectCharacterId=subject,jurisdictionId=jurisdiction}
        ledger[v.recordId]=v;return v
    end
    local function currentCase(p) return assert(ledger[p.caseId]) end
    L.Call=function(resource,operation,p,...)
        if operation=='GetHealth' then return ok({state='ready'}) end
        if operation=='GetCapabilities' then return ok({contract=1}) end
        if operation=='GetProvider' then return ok({implementation={GetIdentity=function(character) return ok({characterId=character,status='active'}) end}}) end
        if operation=='GetSessionContext' then return ok({characterId=p==1 and A or B,sessionId=p==1 and A or B}) end
        if operation=='CheckAssignment' then return ok({matched=permission}) end
        if operation=='CheckLicense' and options.licenseDenied then return err('authorization_denied') end
        if operation=='CheckLicense' then return ok({matched=permission,scopeVersion=1,scope={}}) end
        if operation=='FindJurisdictionByKey' then return ok({recordId=jurisdiction,status='active'}) end
        if operation=='Authorize' then return ok({allowed=p~='justice.case.view_all' and p~='justice.case.manage_all' and permission}) end
        if operation=='RegisterStatute' then writes=writes+1;return ok(snapshot('statute','active',{title=p.title})) end
        if operation=='GetCase' then
            local record=ledger[p.recordId]
            if p.actorSource==2 then
                local readable=false
                for _,v in pairs(ledger) do if v.kind=='party' and v.caseId==p.recordId and v.status=='active' and v.document.role=='investigating_officer' then readable=true end end
                if not readable then return err('not_found') end
            end
            return record and ok(record) or err('not_found')
        end
        if operation=='GetWarrant' and options.crashOnWarrantRead then options.crashOnWarrantRead=false;error('injected read failure') end
        if operation=='GetCharge' or operation=='GetWarrant' or operation=='GetCitation' then
            local value=ledger[p.recordId];return value and ok(value) or err('not_found')
        end
        error('unexpected acceptance export '..operation)
    end
    L.Routes={}
    local function route(name,body,read)
        L.Routes['law.'..name..'.v1']={validate=function(p)
            if p.actorCharacterId then return false end
            if p.requestId and not L.Token(p.requestId,64) then return false end
            return true
        end,handler=function(p,source)
            local key=p.requestId and (source==1 and A or B)..':'..p.requestId
            if key and not read and receipts[key] then
                local receipt=receipts[key]
                if receipt.name~=name or receipt.fingerprint~=(p.title or '')..'/'..(p.summary or '')..'/'..(p.recordId or '')..'/'..tostring(p.expectedRevision) then return err('idempotency_conflict') end
                local result=copy(receipt.value);result.replayed=true;return ok(result)
            end
            if not read then writes=writes+1 end
            local result=body(p)
            if key and not read and result.ok then receipts[key]={name=name,fingerprint=(p.title or '')..'/'..(p.summary or '')..'/'..(p.recordId or '')..'/'..tostring(p.expectedRevision),value=copy(result.value)} end
            if options.unknownOpen and name=='cases.open' and result.ok then options.unknownOpen=false;return err('transaction_failed') end
            return result
        end}
    end
    route('operations.get',function(p) local value=receipts[A..':'..p.requestId];return value and ok(value.value) or err('not_found') end,true)
    route('cases.open',function(p) return ok(snapshot('case','open',{title=p.title,summary=p.summary})) end)
    route('cases.get',function(p) return ok(currentCase(p)) end,true)
    route('cases.update',function(p)
        local v=currentCase(p);if v.revision~=p.expectedRevision then return err('revision_conflict') end
        v.revision=v.revision+1;v.document.summary=p.summary;return ok(v)
    end)
    route('cases.transition',function(p)
        local v=currentCase(p);v.status=p.status;v.revision=v.revision+1;return ok(v)
    end)
    route('parties.add',function(p) return ok(snapshot('party','active',{role=p.role},p.caseId,p.subjectCharacterId)) end)
    route('parties.remove',function(p) local v=ledger[p.recordId];v.status='removed';v.revision=v.revision+1;return ok(v) end)
    route('charges.propose',function(p) return ok(snapshot('charge','proposed',{statuteSnapshot={statuteId=p.statuteId,title=ledger[p.statuteId].document.title}},p.caseId,p.subjectCharacterId)) end)
    route('charges.file',function(p) local v=ledger[p.recordId];v.status='filed';v.revision=v.revision+1;return ok(v) end)
    route('charges.dispose',function(p) local v=ledger[p.recordId];v.status=p.status;v.revision=v.revision+1;return ok(v) end)
    route('warrants.draft',function(p) return ok(snapshot('warrant','draft',{},p.caseId,p.subjectCharacterId)) end)
    route('warrants.issue',function(p) local v=ledger[p.recordId];v.status='active';v.revision=v.revision+1;v.expiresAt=clock+300000;return ok(v) end)
    route('warrants.recall',function(p) if options.recallFailure then return err('authorization_denied') end;local v=ledger[p.recordId];v.status='recalled';v.revision=v.revision+1;return ok(v) end)
    route('warrants.serve',function(p) return err('invalid_transition') end)
    route('citations.issue',function(p) return ok(snapshot('citation','issued',{obligationId=id()},p.caseId,p.subjectCharacterId)) end)
    route('citations.cancel',function(p) local v=ledger[p.recordId];v.status='cancelled';v.revision=v.revision+1;v.document.cancellationOutcome='cancelled';return ok(v) end)
    route('custody.facilities',function() return ok({items={{key='valentine',label='Valentine'}}}) end,true)
    route('custody.reserve',function(p)
        if options.remote then return err('booking_location_required') end
        return ok(snapshot('custody','booking',{warrantId=p.warrantId},p.caseId,B))
    end)
    route('custody.confirm',function(p)
        local v=ledger[p.recordId];v.status='held';v.revision=v.revision+1;local w=ledger[v.document.warrantId];w.status='served';w.revision=w.revision+1;return ok(v)
    end)
    route('custody.release',function(p) local v=ledger[p.recordId];v.status='released';v.revision=v.revision+1;return ok(v) end)
    for _,spec in ipairs({{'parties.list','party'},{'charges.list','charge'},{'warrants.list','warrant'},{'citations.list','citation'},{'custody.list','custody'}}) do
        route(spec[1],function(p)
            local items={};for _,v in pairs(ledger) do if v.kind==spec[2] and v.caseId==p.caseId then items[#items+1]=v end end
            return ok({items=items})
        end,true)
    end
    assert(loadfile('server/acceptance.lua','t',env))()
    local function execute(args,source)
        local before=#threads;commands.LawAcceptanceTest(source or 0,args)
        for index=before+1,#threads do while coroutine.status(threads[index])~='dead' do local called,message=coroutine.resume(threads[index]);assert(called,message) end end
    end
    return {env=env,output=output,ledger=ledger,receipts=receipts,execute=execute,writes=function() return writes end,
        permission=function(value) permission=value end,options=options,commands=commands,threads=threads,
        contains=function(pattern) for _,line in ipairs(output) do if line:find(pattern,1,true) then return true end end end,
        summary=function() return output[#output] end,
        clear=function() for i=#output,1,-1 do output[i]=nil end end}
end
local f=fixture()
f.execute({'preflight',A,B})
check('preflight is read-only',f.writes()==0)
check('preflight prints PASS lines and exact tally',f.contains('PASS') and f.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
f.clear();f.execute({A,B,'legal-one'})
check('legal suite reports no manufactured failures',f.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
check('unrequested finance and physical tests are SKIP',f.contains('not requested; use finance') and f.contains('not requested; use custody'))
local caseId
for id,v in pairs(f.ledger) do if v.kind=='case' then caseId=id;check('successful fixture dismissed after cleanup',v.status=='dismissed') end end
check('legal mode moves no money or custody',not f.contains('request 1 minor-unit') and not f.contains('arrival confirmation'))
local before=f.writes();f.clear();f.execute({'resume',A,B,'legal-one'})
check('resume after reload reads durable receipts without writes',f.writes()==before and f.contains('resume: persisted test case'))
f.clear();f.execute({A,B,'legal-one'})
check('reusing a completed runId is refused',f.contains('fresh runId') and f.summary():match('done %d+ passed, %d+ failed, %d+ skipped'))
check('reused run does not mutate existing case status',f.ledger[caseId].status=='dismissed')
local crash=fixture({crashOnWarrantRead=true});crash.execute({A,B,'crashed-run'})
check('unexpected suite failure still attempts guarded cleanup',crash.contains('suite: completed without internal exception') and crash.contains('cleanup: recall remaining test warrant') and crash.contains('cleanup: dismiss test case'))
local denied=fixture();denied.permission(false);denied.execute({A,B,'denied-run'})
check('setup failures prevent all fixture writes',denied.writes()==0 and denied.contains('fix setup failures'))
local missingLicenseReader=fixture({licenseDenied=true});missingLicenseReader.execute({'preflight',A,B})
check('unavailable license response skips dependent scope diagnostic',missingLicenseReader.contains('license response unavailable; fix its reader/access check first') and missingLicenseReader.writes()==0)
local offline=fixture({offlineA=true});offline.execute({'preflight',A,B})
check('stored UUID is not treated as connected actor',offline.writes()==0 and offline.contains('stored active is not an online session'))
local private=fixture({offlineB=true});private.execute({A,B,'offline-b'})
check('offline B privacy checks are skipped, never PASS',private.contains('B is offline') and private.contains('B session/scoped view permission required'))
local lost=fixture({unknownOpen=true});lost.execute({A,B,'unknown-open'})
check('unknown create result recovers original durable request',lost.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
local count=0;for _,v in pairs(lost.ledger) do if v.kind=='case' then count=count+1 end end
check('unknown result creates only one case',count==1)
local broken=fixture({recallFailure=true});broken.execute({A,B,'needs-cleanup'})
local open=false;for _,v in pairs(broken.ledger) do if v.kind=='case' then open=v.status=='open' end end
check('failed cleanup is reported and case stays editable',open and broken.contains('resolve remaining children'))
broken.options.recallFailure=false;broken.clear();broken.execute({'cleanup',A,B,'needs-cleanup'})
check('cleanup rerun uses original records without new fixture',broken.contains('cleanup: recall remaining test warrant') and broken.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
local unrelated=fixture({recallFailure=true});unrelated.execute({A,B,'unrelated'})
local parent;for id,v in pairs(unrelated.ledger) do if v.kind=='case' then parent=id end end
local extra='8ded546b-1687-4b0f-a612-bfb37432bfc2';unrelated.ledger[extra]={recordId=extra,kind='warrant',caseId=parent,status='active',revision=2}
unrelated.options.recallFailure=false;unrelated.clear();unrelated.execute({'cleanup',A,B,'unrelated'})
check('cleanup never changes unrelated records on test case',unrelated.ledger[extra].status=='active' and unrelated.contains('unrelated warrants record retained'))
local money=fixture();money.execute({'finance',A,B,'finance-one'})
check('finance mode confirms cancellation, without wallet APIs',money.contains('finance: cancellation confirmed by Contracts') and money.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
local physical=fixture();physical.execute({'custody',A,B,'custody-one'})
check('custody mode verifies reserve/serve/release',physical.contains('custody: warrant served with confirmed booking') and physical.contains('custody: explicit release confirmed') and physical.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
local remote=fixture({remote=true});remote.execute({'custody',A,B,'remote-one'})
check('physical refusal is a real failure and test warrant cleaned',remote.contains('booking_location_required') and remote.contains('cleanup: recall remaining test warrant'))
local guard=fixture();guard.execute({'preflight','1',B})
check('numeric character identifiers rejected',guard.writes()==0 and guard.contains('usage: two distinct character UUIDs'))
local oldOutput=#guard.output;guard.execute({A,B,'forbidden'},4)
check('acceptance command console-only',#guard.output==oldOutput and guard.writes()==0)
local busy=fixture()
busy.commands.LawAcceptanceTest(0,{'preflight',A,B})
local pendingThreads=#busy.threads
busy.commands.LawAcceptanceTest(0,{'preflight',A,B})
check('concurrent run for same UUID refused without a second thread',#busy.threads==pendingThreads and busy.contains('already running') and busy.writes()==0)
for _,thread in ipairs(busy.threads) do local called,message=coroutine.resume(thread);assert(called,message) end
busy.clear();busy.execute({'preflight',A,B})
check('completed run releases actor lock',busy.summary():match('done %d+ passed, 0 failed, %d+ skipped'))
print(('PASS Law acceptance orchestration: %d checks (mock APIs; not live acceptance)'):format(checks))
