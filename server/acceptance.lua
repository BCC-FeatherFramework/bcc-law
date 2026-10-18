-- Explicit console acceptance. Uses production handlers/exports and real policy;
-- never impersonates an offline actor, grants roles, edits foreign SQL or pays debt.
local running,serial={},0
local modes={preflight=true,legal=true,finance=true,custody=true,resume=true,cleanup=true}
local function Reporter()
    local counts={passed=0,failed=0,skipped=0}
    local function Line(label,status,detail)
        local key=status=='PASS' and 'passed' or status=='FAIL' and 'failed' or 'skipped'
        counts[key]=counts[key]+1
        print(('[LawAcceptanceTest] %-58s %s%s'):format(label,status,detail and ('  ('..tostring(detail):gsub('%c',' ')..')') or ''))
        return status=='PASS'
    end
    return {
        check=function(label,condition,detail) return Line(label,condition and 'PASS' or 'FAIL',detail) end,
        skip=function(label,detail) return Line(label,'SKIP',detail) end,
        note=function(detail) print('[LawAcceptanceTest] '..detail) end,
        failedCount=function() return counts.failed end,
        done=function() print(('[LawAcceptanceTest] done %d passed, %d failed, %d skipped'):format(counts.passed,counts.failed,counts.skipped)) end
    }
end
local function Session(characterId)
    for _,player in ipairs(GetPlayers()) do
        local source=tonumber(player)
        local result=Law.Call('feather-core','GetSessionContext',source)
        if result.ok and type(result.value)=='table' and Law.Uuid(result.value.characterId)
            and result.value.characterId:lower()==characterId then
            local actor=Law.Actor(source,result.value)
            if actor.ok then return {actor=actor.value,context=result.value,source=source} end
        end
    end
end
local function Identity(characterId)
    local provider=Law.Call('feather-core','GetProvider','character-profile',nil,1)
    local impl=provider.ok and type(provider.value)=='table' and provider.value.implementation
    if type(impl)~='table' or impl.GetIdentity==nil then return Law.Err('character_provider_unavailable','Identity provider unavailable.') end
    local called,result=pcall(impl.GetIdentity,characterId)
    if not called or type(result)~='table' or not result.ok or type(result.value)~='table'
        or type(result.value.characterId)~='string' or result.value.characterId:lower()~=characterId or result.value.status~='active' then
        return Law.Err('character_not_active','Existing active Character UUID required.')
    end
    return result
end
local function Code(result) return type(result)=='table' and tostring(result.code or (result.ok and 'confirmed' or 'invalid_result')) or 'invalid_result' end
local function Route(c,name,p,who)
    who=who or c.a
    if not who or not Law.Current(who.actor) then return Law.Err('session_expired','Actor needs an active session.') end
    local spec=Law.Routes['law.'..name..'.v1']
    if not spec or spec.validate(p)~=true then return Law.Err('invalid_input','Acceptance payload rejected by production validator.') end
    local called,result=pcall(spec.handler,p,who.source,who.context)
    if not called or type(result)~='table' or type(result.ok)~='boolean' then return Law.Err('operation_failed','Unconfirmed acceptance operation.') end
    if not Law.Current(who.actor) then return Law.Err('session_expired','Actor changed; preserve runId.') end
    return result
end
local function Read(c,operation,id,who)
    who=who or c.a
    if not who or not Law.Current(who.actor) then return Law.Err('session_expired','Actor needs an active session.') end
    local result=Law.Call('feather-justice',operation,{actorSource=who.source,recordId=id})
    if not Law.Current(who.actor) then return Law.Err('session_expired','Actor changed.') end
    return result
end
local function Request(c,step,p)
    p=Law.Copy(p or {});p.department=c.department;p.requestId='accept:'..c.runId..':'..step
    return p
end
local function Find(c,step)
    return Route(c,'operations.get',{department=c.department,requestId='accept:'..c.runId..':'..step})
end
local uncertain={operation_failed=true,transaction_failed=true,dependency_unavailable=true,session_expired=true}
local function Write(c,name,step,p)
    local result=Route(c,name,Request(c,step,p))
    if not result.ok and uncertain[result.code] then
        local found=Find(c,step)
        if found.ok then return found end
        c.report.note('unconfirmed '..step..'; preserve runId '..c.runId)
    end
    return result
end
local function Check(c,label,result,predicate)
    local passed=result.ok and (not predicate or predicate(result.value))
    c.report.check(label,passed,not passed and (result.ok and 'unexpected_result' or Code(result)) or nil)
    return passed and result.value or nil
end
local function Setup(c)
    local r=c.report
    r.check('setup: Law ready',Law.Ready())
    r.check('setup: server configuration valid',Law.ValidateConfig())
    local health=Law.Call('feather-justice','GetHealth')
    local caps=Law.Call('feather-justice','GetCapabilities')
    local ready=r.check('setup: Justice ready / Contract 1',health.ok and type(health.value)=='table' and health.value.state=='ready'
        and caps.ok and type(caps.value)=='table' and caps.value.contract==1,not health.ok and Code(health) or nil)
    local ai,bi=Identity(c.actorId),Identity(c.subjectId)
    r.check('setup: A resolves to an active character UUID',ai.ok,not ai.ok and Code(ai) or nil)
    r.check('setup: B resolves to an active character UUID',bi.ok,not bi.ok and Code(bi) or nil)
    c.a,c.b=Session(c.actorId),Session(c.subjectId)
    r.check('setup: A has a current selected Core character',c.a~=nil,not c.a and 'stored active is not an online session' or nil)
    if c.b then r.check('setup: B has a current selected Core character',true)
    else r.skip('setup: B session / interactive privacy checks','B is offline; identity still checked') end
    if not ready or not Law.Ready() or not Law.ValidateConfig() or not ai.ok or not bi.ok or not c.a then return false end
    local d=LawConfig.Departments[c.department]
    if not r.check('setup: department configured',d~=nil) then return false end
    local job=Law.Call('feather-jobs','CheckAssignment',{characterId=c.actorId,jobKey=d.jobKey,minGradeOrdinal=d.minGradeOrdinal,
        dutyState='on_duty',activeOnly=true,employerType=d.employerId and 'organization' or nil,employerId=d.employerId})
    r.check('setup: A on duty / grade / Jobs reader trust',job.ok and type(job.value)=='table' and job.value.matched==true,not job.ok and Code(job) or nil)
    local license=Law.Call('feather-licenses','CheckLicense',{holderType='character',holderId=c.actorId,licenseKey=d.licenseKey})
    r.check('setup: A commission / Licenses reader trust',license.ok and type(license.value)=='table' and license.value.matched==true,not license.ok and Code(license) or nil)
    if license.ok and type(license.value)=='table' and license.value.matched==true then
        r.check('setup: commission scope supported',license.value.scopeVersion==1 and type(license.value.scope)=='table' and next(license.value.scope)==nil)
    else r.skip('setup: commission scope supported',not license.ok and 'license response unavailable; fix its reader/access check first' or 'no matched commission scope to inspect') end
    local jurisdiction=Law.Call('feather-justice','FindJurisdictionByKey',{actorSource=c.a.source,recordKey=d.jurisdictionKey})
    if jurisdiction.ok then c.jurisdictionId=jurisdiction.value.recordId end
    r.check('setup: jurisdiction readable by A',jurisdiction.ok,not jurisdiction.ok and Code(jurisdiction) or nil)
    local access=Law.Access(c.a.source,c.a.context,c.department,'justice.case.view')
    local allowed=r.check('setup: A passes production Law access',access.ok,not access.ok and Code(access) or nil)
    local actions=c.mode=='preflight' and {'justice.case.open','justice.case.update','justice.case.transition',
        'justice.party.view','justice.party.manage','justice.charge.view','justice.charge.propose','justice.charge.file','justice.charge.dispose',
        'justice.warrant.view','justice.warrant.draft','justice.warrant.issue','justice.warrant.recall','justice.warrant.serve',
        'justice.citation.view','justice.citation.issue','justice.citation.cancel','justice.custody.view','justice.custody.book','justice.custody.release'} or {}
    for _,action in ipairs(actions) do
        local policy=Law.Call('feather-core','Authorize',action,{source=c.a.source,subject={resource='bcc-law',jurisdictionId=c.jurisdictionId,departmentKey=c.department}})
        local allowed=policy.ok and type(policy.value)=='table' and policy.value.allowed==true
        local detail=not allowed and (policy.ok and type(policy.value)=='table' and (policy.value.code or 'not_granted') or Code(policy)) or nil
        r.check('policy: '..action,allowed,detail)
    end
    return allowed and jurisdiction.ok
end
local function Case(c)
    local summary='Acceptance fixture for subject '..c.subjectId..'; mode '..c.mode
    local opened=Write(c,'cases.open','case-open',{title='[TEST] Law acceptance '..c.runId,summary=summary})
    local value=Check(c,'cases: create owned test case',opened,function(v) return v.kind=='case' and Law.Uuid(v.recordId) and v.status=='open' end)
    if not value then return false end
    c.case=value
    if not c.report.check('setup: fresh runId (resume/cleanup for existing run)',value.replayed~=true) then c.case=nil;return false end
    c.fresh=true
    c.report.note('case '..value.recordId..'; restart check: LawAcceptanceTest resume '..c.actorId..' '..c.subjectId..' '..c.runId..' '..c.department)
    local replay=Write(c,'cases.open','case-open',{title='[TEST] Law acceptance '..c.runId,summary=summary})
    Check(c,'cases: exact create retry is one case',replay,function(v) return v.recordId==value.recordId and v.replayed==true end)
    local conflict=Write(c,'cases.open','case-open',{title='[TEST] changed payload',summary=summary})
    c.report.check('cases: changed payload refuses reused request ID',not conflict.ok and conflict.code=='idempotency_conflict',Code(conflict))
    local read=Route(c,'cases.get',{department=c.department,caseId=value.recordId})
    Check(c,'cases: read typed current record',read,function(v) return v.recordId==value.recordId and v.kind=='case' end)
    local edited=Write(c,'cases.update','case-update',{caseId=value.recordId,expectedRevision=value.revision,summary=summary..'; updated'})
    local update=Check(c,'cases: summary update increments revision',edited,function(v) return v.revision==value.revision+1 end)
    if update then c.case=update end
    if update then
        local stale=Write(c,'cases.update','case-stale',{caseId=value.recordId,expectedRevision=value.revision,summary='Stale update must not commit'})
        c.report.check('cases: stale revision refused',not stale.ok and stale.code=='revision_conflict',Code(stale))
    else c.report.skip('cases: stale revision refused','successful prior update required') end
    local invalid={department=c.department,caseId=value.recordId,actorCharacterId=c.subjectId}
    local rejected=Route(c,'cases.get',invalid)
    c.report.check('cases: actor identity injection refused',not rejected.ok and rejected.code=='invalid_input',Code(rejected))
    return true
end
local function Party(c)
    local r=c.report
    local testB=false
    if c.b then
        local view=Law.Call('feather-core','Authorize','justice.case.view',{source=c.b.source,subject={resource='bcc-law',jurisdictionId=c.jurisdictionId}})
        local broad=false
        for _,action in ipairs({'justice.case.view_all','justice.case.manage_all'}) do
            local result=Law.Call('feather-core','Authorize',action,{source=c.b.source,subject={resource='bcc-law',jurisdictionId=c.jurisdictionId}})
            broad=broad or (result.ok and type(result.value)=='table' and result.value.allowed==true)
        end
        testB=view.ok and type(view.value)=='table' and view.value.allowed==true and not broad
        if not testB then r.skip('privacy: isolate B membership checks','B lacks view policy or has explicit global override') end
    end
    local function B(label,allowed)
        if not testB then r.skip(label,'B session/scoped view permission required');return end
        local result=Read(c,'GetCase',c.case.recordId,c.b)
        r.check(label,allowed and result.ok or (not allowed and not result.ok and result.code=='not_found'),not result.ok and Code(result) or nil)
    end
    B('privacy: unrelated B cannot read case',false)
    local witness=Write(c,'parties.add','party-witness',{caseId=c.case.recordId,expectedCaseRevision=c.case.revision,subjectCharacterId=c.subjectId,role='witness'})
    local party=Check(c,'parties: record witness UUID',witness,function(v) return v.kind=='party' and v.subjectCharacterId==c.subjectId end)
    if party then
        B('privacy: witness gets no narrative access',false)
        Check(c,'parties: remove witness',Write(c,'parties.remove','party-witness-remove',{caseId=c.case.recordId,recordId=party.recordId,expectedRevision=party.revision}),function(v) return v.status=='removed' end)
    else r.skip('privacy: witness access check','witness add failed') end
    local investigator=Write(c,'parties.add','party-investigator',{caseId=c.case.recordId,expectedCaseRevision=c.case.revision,subjectCharacterId=c.subjectId,role='investigating_officer'})
    local member=Check(c,'parties: add investigating officer UUID',investigator)
    if member then
        B('privacy: active investigator can read case',true)
        Check(c,'parties: revoke investigator',Write(c,'parties.remove','party-investigator-remove',{caseId=c.case.recordId,recordId=member.recordId,expectedRevision=member.revision}),function(v) return v.status=='removed' end)
        B('privacy: removed investigator loses access',false)
    else r.skip('privacy: investigator and revocation checks','membership add failed') end
end
local function Charge(c)
    local definition=Law.Call('feather-justice','RegisterStatute',{requestId='accept:'..c.runId..':statute',reasonCode='law.acceptance.setup',
        recordKey='bcc-law:accept:'..c.runId,jurisdictionId=c.jurisdictionId,title='[TEST] Acceptance statute',description='Acceptance fixture, not a production penal code.'})
    local statute=Check(c,'charges: register isolated test statute',definition)
    if not statute then c.report.skip('charges: propose/file/dispose','definition setup permission required');return end
    local proposed=Write(c,'charges.propose','charge-propose',{caseId=c.case.recordId,expectedCaseRevision=c.case.revision,
        subjectCharacterId=c.subjectId,statuteId=statute.recordId,count=1})
    local charge=Check(c,'charges: propose for subject UUID',proposed,function(v) return v.kind=='charge' and v.status=='proposed' and v.subjectCharacterId==c.subjectId end)
    if not charge then c.report.skip('charges: file/dispose','proposal failed');return end
    Check(c,'charges: statute snapshot frozen in record',Read(c,'GetCharge',charge.recordId),function(v) return v.document.statuteSnapshot.statuteId==statute.recordId and v.document.statuteSnapshot.title==statute.document.title end)
    local filed=Check(c,'charges: file proposed charge',Write(c,'charges.file','charge-file',{caseId=c.case.recordId,recordId=charge.recordId,expectedRevision=charge.revision}),function(v) return v.status=='filed' end)
    if filed then charge=filed end
    Check(c,'charges: withdraw test charge',Write(c,'charges.dispose','charge-withdraw',{caseId=c.case.recordId,recordId=charge.recordId,expectedRevision=charge.revision,status='withdrawn'}),function(v) return v.status=='withdrawn' end)
end
local function Warrant(c,step)
    local draft=Write(c,'warrants.draft',step..'-draft',{caseId=c.case.recordId,expectedCaseRevision=c.case.revision,
        subjectCharacterId=c.subjectId,basisSummary='[TEST] Law acceptance '..c.runId,validForSeconds=300})
    local value=Check(c,step..': draft arrest warrant',draft,function(v) return v.kind=='warrant' and v.status=='draft' end)
    if not value then return nil end
    return Check(c,step..': issue arrest warrant',Write(c,'warrants.issue',step..'-issue',{caseId=c.case.recordId,recordId=value.recordId,expectedRevision=value.revision}),function(v) return v.status=='active' and type(v.expiresAt)=='number' end)
end
local function Warrants(c)
    local w=Warrant(c,'warrant')
    if not w then c.report.skip('warrants: recall and terminal guard','issue failed');return end
    Check(c,'warrants: current active warrant readable',Read(c,'GetWarrant',w.recordId),function(v) return v.status=='active' and v.subjectCharacterId==c.subjectId end)
    local recalled=Check(c,'warrants: recall test warrant',Write(c,'warrants.recall','warrant-recall',{caseId=c.case.recordId,recordId=w.recordId,expectedRevision=w.revision}),function(v) return v.status=='recalled' end)
    if recalled then
        local served=Write(c,'warrants.serve','recalled-serve',{caseId=c.case.recordId,recordId=w.recordId,expectedRevision=recalled.revision})
        c.report.check('warrants: recalled warrant cannot be served',not served.ok and served.code=='invalid_transition',Code(served))
    end
    c.report.skip('warrants: real elapsed expiry','separate timed test; database clock is not changed')
end
local function WaitCitation(c,id,status)
    local started=GetGameTimer()
    repeat
        local result=Read(c,'GetCitation',id)
        if not result.ok then return result end
        if result.value.status==status then return result end
        if status=='cancelled' and result.value.document.cancellationOutcome and result.value.document.cancellationOutcome~='cancelled' then
            return Law.Err('cancellation_rejected','Financial obligation cannot be cancelled.')
        end
        if not Law.Current(c.a.actor) then return Law.Err('session_expired','Actor changed.') end
        Wait(250)
    until GetGameTimer()-started>=20000
    return Law.Err('workflow_pending','Inspect JusticeCitationStatus; keep runId for cleanup.')
end
local function Finance(c)
    local health=Law.Call('feather-contracts','GetHealth')
    if not Check(c,'finance: Contracts ready',health,function(v) return v.state=='ready' end) then c.report.skip('finance: issue/cancel obligation','Contracts unavailable');return end
    local result=Write(c,'citations.issue','citation-issue',{caseId=c.case.recordId,expectedCaseRevision=c.case.revision,
        subjectCharacterId=c.subjectId,amount=1,dueInSeconds=60,basisSummary='[TEST] Law acceptance '..c.runId})
    local citation=Check(c,'finance: request 1 minor-unit test citation',result,function(v) return v.kind=='citation' end)
    if not citation then return end
    c.report.note('citation '..citation.recordId..'; no payment/debit is requested by this suite')
    local issued=Check(c,'finance: Contracts issue confirmed and linked',WaitCitation(c,citation.recordId,'issued'),function(v) return Law.Uuid(v.document.obligationId) end)
    if issued then
        local cancelled=Write(c,'citations.cancel','citation-cancel',{caseId=c.case.recordId,recordId=issued.recordId,expectedRevision=issued.revision})
        if Check(c,'finance: cancellation requested',cancelled) then
            Check(c,'finance: cancellation confirmed by Contracts',WaitCitation(c,citation.recordId,'cancelled'),function(v) return v.document.cancellationOutcome=='cancelled' end)
        end
    end
    c.report.skip('finance: wallet settlement / double-payment','manual /lawfines on disposable staging; no wallet is debited here')
end
local function Custody(c)
    if not c.b then c.report.skip('custody: physical reserve/confirm/release','B must be online at the configured facility');return end
    local facilities=Route(c,'custody.facilities',{department=c.department})
    local key=facilities.ok and facilities.value.items[1] and facilities.value.items[1].key
    if not c.report.check('custody: department facility available',key~=nil,not facilities.ok and Code(facilities) or nil) then return end
    local w=Warrant(c,'custody-warrant');if not w then c.report.skip('custody: physical workflow','test warrant unavailable');return end
    local reservation=Write(c,'custody.reserve','custody-reserve',{caseId=c.case.recordId,warrantId=w.recordId,expectedWarrantRevision=w.revision,facilityKey=key})
    local reserved=Check(c,'custody: server confirms physical booking location',reservation,function(v) return v.status=='booking' and v.subjectCharacterId==c.subjectId end)
    if not reserved then return end
    local held=Check(c,'custody: arrival confirmation enters held state',Write(c,'custody.confirm','custody-confirm',{caseId=c.case.recordId,recordId=reserved.recordId,expectedRevision=reserved.revision}),function(v) return v.status=='held' end)
    if held then
        Check(c,'custody: warrant served with confirmed booking',Read(c,'GetWarrant',w.recordId),function(v) return v.status=='served' end)
        Check(c,'custody: original booking receipt recoverable',Find(c,'custody-reserve'),function(v) return v.recordId==held.recordId and v.status=='booking' end)
        Check(c,'custody: explicit release confirmed',Write(c,'custody.release','custody-release',{caseId=c.case.recordId,recordId=held.recordId,expectedRevision=held.revision}),function(v) return v.status=='released' end)
    end
end
local function RecoverCase(c)
    local found=Find(c,'case-open')
    if not found.ok then c.report.check('resume: original actor case receipt readable',false,Code(found));return false end
    local current=Read(c,'GetCase',found.value.recordId)
    local value=Check(c,'resume: persisted test case / original actor receipt',current,function(v) return v.kind=='case' and v.document.title=='[TEST] Law acceptance '..c.runId end)
    if not value then return false end
    c.case=value
    return true
end
local function Cleanup(c)
    if not c.case then return end
    local r=c.report
    local before,unresolved=r.failedCount(),false
    local function Records(route,label,steps,change)
        local owned={}
        for index,step in ipairs(steps) do
            local found=Find(c,step)
            if found.ok then owned[found.value.recordId]=index
            elseif found.code~='not_found' then unresolved=true;r.check('cleanup: '..label..' receipt readable',false,Code(found)) end
        end
        if not next(owned) then return end
        local page=Route(c,route,{department=c.department,caseId=c.case.recordId})
        if not page.ok then r.check('cleanup: '..label..' readable',false,Code(page));return end
        for _,v in ipairs(page.value.items) do
            if owned[v.recordId] then change(v,owned[v.recordId])
            else unresolved=true;r.skip('cleanup: unrelated '..label..' record retained',v.recordId) end
        end
        if page.value.nextCursor then r.check('cleanup: '..label..' bounded fixture',false,'unexpected extra page; inspect test case') end
    end
    Records('custody.list','custody',{'custody-reserve'},function(v,index)
        if v.status~='released' then Check(c,'cleanup: release test custody',Write(c,'custody.release','clean-u'..index..'-'..v.revision,{caseId=c.case.recordId,recordId=v.recordId,expectedRevision=v.revision}),function(x) return x.status=='released' end) end
    end)
    Records('warrants.list','warrants',{'warrant-draft','custody-warrant-draft'},function(v,index)
        if v.status=='active' then Check(c,'cleanup: recall remaining test warrant',Write(c,'warrants.recall','clean-w'..index..'-'..v.revision,{caseId=c.case.recordId,recordId=v.recordId,expectedRevision=v.revision}),function(x) return x.status=='recalled' end) end
    end)
    Records('charges.list','charges',{'charge-propose'},function(v,index)
        if v.status=='proposed' or v.status=='filed' then Check(c,'cleanup: withdraw remaining test charge',Write(c,'charges.dispose','clean-c'..index..'-'..v.revision,{caseId=c.case.recordId,recordId=v.recordId,expectedRevision=v.revision,status='withdrawn'}),function(x) return x.status=='withdrawn' end) end
    end)
    Records('citations.list','citations',{'citation-issue'},function(v,index)
        if v.status=='pending' then
            local issued=WaitCitation(c,v.recordId,'issued')
            if issued.ok then v=issued.value else r.check('cleanup: pending citation requires recovery',false,v.recordId..'; use cleanup with same runId');return end
        end
        if v.status=='issued' then
            local cancellation=Write(c,'citations.cancel','clean-f'..index..'-'..v.revision,{caseId=c.case.recordId,recordId=v.recordId,expectedRevision=v.revision})
            Check(c,'cleanup: cancel remaining test citation',cancellation)
            if cancellation.ok then Check(c,'cleanup: citation cancellation finalized',WaitCitation(c,v.recordId,'cancelled')) end
        elseif v.status=='cancel_pending' then Check(c,'cleanup: pending cancellation finalized',WaitCitation(c,v.recordId,'cancelled')) end
    end)
    Records('parties.list','parties',{'party-witness','party-investigator'},function(v,index)
        if v.status=='active' then Check(c,'cleanup: remove test party',Write(c,'parties.remove','clean-p'..index..'-'..v.revision,{caseId=c.case.recordId,recordId=v.recordId,expectedRevision=v.revision}),function(x) return x.status=='removed' end) end
    end)
    if unresolved or r.failedCount()>before then r.skip('cleanup: dismiss test case','resolve remaining children, then rerun cleanup');return end
    local current=Read(c,'GetCase',c.case.recordId)
    if not current.ok then r.check('cleanup: current test case readable',false,Code(current));return end
    if current.value.status=='open' or current.value.status=='filed' then
        local closed=Write(c,'cases.transition','case-dismiss',{caseId=c.case.recordId,expectedRevision=current.value.revision,status='dismissed'})
        Check(c,'cleanup: dismiss test case / retain history',closed,function(v) return v.status=='dismissed' end)
    else r.check('cleanup: test case already terminal',current.value.status=='dismissed' or current.value.status=='closed') end
    r.note('test definitions/records remain as auditable history; no SQL deletion, refund or role grant')
end
local function Resume(c)
    if not RecoverCase(c) then return end
    local r=c.report
    for _,spec in ipairs({{'charges.list','charges'},{'warrants.list','warrants'},{'parties.list','parties'},
        {'citations.list','citations'},{'custody.list','custody'}}) do
        local page=Route(c,spec[1],{department=c.department,caseId=c.case.recordId})
        if page.ok and type(page.value.items)=='table' and #page.value.items==0 then
            r.skip('resume: '..spec[2]..' persisted records','no rows in this phase; not proof of persistence')
        else Check(c,'resume: '..spec[2]..' saved records readable',page,function(v)
            if type(v.items)~='table' then return false end
            for _,item in ipairs(v.items) do if not Law.Uuid(item.recordId) or item.caseId~=c.case.recordId then return false end end
            return true
        end) end
        if page.ok then for _,v in ipairs(page.value.items) do r.note(spec[2]..' '..v.recordId..' status='..v.status) end end
    end
    r.skip('resume: client UI/physical custody/financial journal','not demonstrated by record reads')
end
RegisterCommand('LawAcceptanceTest',function(source,args)
    if source~=0 then return end
    args=args or {};local mode=modes[args[1]] and args[1] or 'legal';local offset=modes[args[1]] and 1 or 0
    local a,b=args[offset+1],args[offset+2]
    local runId=mode=='preflight' and 'preflight' or args[offset+3]
    local department=args[offset+(mode=='preflight' and 3 or 4)] or 'new_hanover'
    if not runId and mode~='resume' and mode~='cleanup' then serial=serial+1;runId=os.date('!%Y%m%dT%H%M%S')..'-'..serial end
    local r=Reporter()
    if not Law.Uuid(a) or not Law.Uuid(b) or a:lower()==b:lower() or not Law.Token(runId,20) or not Law.Token(department,48) then
        r.check('usage: two distinct character UUIDs and bounded runId',false)
        r.note('LawAcceptanceTest preflight <A UUID> <B UUID> [department] (read-only)')
        r.note('LawAcceptanceTest [legal|finance|custody|resume|cleanup] <A UUID> <B UUID> [runId] [department]')
        r.note('legal/finance/custody write tagged test records; finance issues then cancels a 1 minor-unit debt; custody requires both at the facility. resume is read-only; cleanup writes.')
        r.done();return
    end
    a,b=a:lower(),b:lower()
    if running[a] then r.check('setup: one acceptance run per actor',false,'already running');r.done();return end
    running[a]=true
    CreateThread(function()
        local c={mode=mode,actorId=a,subjectId=b,department=department,runId=runId,report=r}
        r.note('mode='..mode..' runId='..runId..((mode=='preflight' or mode=='resume') and ' (read-only)' or ''))
        local called=pcall(function()
            if not Setup(c) then r.skip('workflow: cases/parties/charges/warrants','fix setup failures; no fixture writes attempted');return end
            if mode=='preflight' then return end
            if mode=='resume' then Resume(c);return end
            if mode=='cleanup' then if RecoverCase(c) then Cleanup(c) end;return end
            if not Case(c) then r.skip('workflow: parties/charges/warrants','case creation or fresh runId required');return end
            Party(c);Charge(c);Warrants(c)
            if mode=='finance' then Finance(c) else r.skip('finance: issue/cancel/settlement','not requested; use finance mode on disposable staging') end
            if mode=='custody' then Custody(c) else r.skip('custody: physical reserve/confirm/release','not requested; use custody mode with both players at facility') end
        end)
        if not called then r.check('suite: completed without internal exception',false,'unexpected failure; preserve runId') end
        if c.fresh and mode~='resume' and mode~='cleanup' then
            local cleaned=pcall(Cleanup,c)
            if not cleaned then r.check('cleanup: completed without internal exception',false,'run cleanup with the same UUIDs/runId') end
        end
        if c.case then r.note('recovery: LawAcceptanceTest cleanup '..a..' '..b..' '..runId..' '..department) end
        running[a]=nil;r.done()
    end)
end,true)
