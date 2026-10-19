local max=9007199254740990
local function Integer(n,a,b) return type(n)=='number' and n%1==0 and n>=a and n<=b end
local function Fields(p,names,mutation)
    local allowed={department=true,caseId=true};for _,name in ipairs(names) do allowed[name]=true end
    if mutation then allowed.requestId=true end
    return Law.Fields(p,allowed) and Law.Token(p.department,48) and Law.Uuid(p.caseId) and (not mutation or Law.Token(p.requestId,64))
end
function Law.CaseAccess(p,source,context,action)
    local actor=Law.Access(source,context,p.department,action);if not actor.ok then return actor end
    local r=Law.Call('feather-justice','GetCase',{actorSource=source,recordId=p.caseId})
    if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
    if not r.ok then return r end
    if type(r.value)~='table' or r.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Case unavailable.') end
    return actor
end
local function Dispatch(actor,operation,p)
    if not Law.Current(actor) then return Law.Err('session_expired','Character changed.') end
    local r=Law.Call('feather-justice',operation,p)
    if not Law.Current(actor) then return Law.Err('session_expired','Character changed; retain the request ID.') end
    return r
end
local function Request(p,actor)
    return {actorSource=actor.source,requestId=actor.characterId..':'..p.requestId,reasonCode='law.court.action'}
end
local function Findings(f)
    if type(f)~='table' or #f<1 or #f>25 then return false end
    local count,seen=0,{}
    for index,v in pairs(f) do
        count=count+1
        if not Integer(index,1,#f) or not Law.Fields(v,{chargeId=true,finding=true}) or not Law.Uuid(v.chargeId)
            or (v.finding~='convicted' and v.finding~='acquitted') or seen[v.chargeId:lower()] then return false end
        seen[v.chargeId:lower()]=true
    end
    return count==#f
end
local termFields={
    custodial={termSeconds=true,facilityKey=true},probation={termSeconds=true,conditionsSummary=true},
    community_service={units=true,taskKey=true},fine={amount=true,dueInSeconds=true},
    restitution={amount=true,dueInSeconds=true,creditorCharacterId=true},
    license_suspension={licenseKey=true,termSeconds=true},forfeiture={targetType=true,targetReference=true}
}
local function Terms(kind,t)
    if not termFields[kind or ''] or not Law.Fields(t,termFields[kind]) then return false end
    if kind=='custodial' or kind=='probation' then
        return Integer(t.termSeconds,60,31536000) and (kind~='probation' or Law.Text(t.conditionsSummary,2000))
            and (kind~='custodial' or t.facilityKey==nil or Law.Token(t.facilityKey,64))
    elseif kind=='community_service' then return Integer(t.units,1,1000) and Law.Token(t.taskKey,64)
    elseif kind=='fine' or kind=='restitution' then return Integer(t.amount,1,1000000) and Integer(t.dueInSeconds,60,2592000)
        and (kind~='restitution' or Law.Uuid(t.creditorCharacterId))
    elseif kind=='license_suspension' then return Law.Token(t.licenseKey,64) and (t.termSeconds==nil or Integer(t.termSeconds,60,31536000))
    else return ({property=true,asset=true,item=true})[t.targetType or '']==true and Law.Token(t.targetReference,128) end
end
Law.Routes['law.rulings.record.v1']={maxDepth=4,maxNodes=128,
    validate=function(p)
        return Fields(p,{'expectedCaseRevision','subjectCharacterId','rulingType','summary','findings','outcome'},true)
            and Integer(p.expectedCaseRevision,1,max) and Law.Uuid(p.subjectCharacterId) and Law.Text(p.summary,4000)
            and ((p.rulingType=='verdict' and Findings(p.findings) and p.outcome==nil)
                or (p.rulingType=='dismissal' and p.findings==nil and p.outcome==nil)
                or (p.rulingType=='order' and p.findings==nil and Law.Token(p.outcome,64)))
    end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.ruling.record');if not a.ok then return a end
        local q=Request(p,a.value)
        for _,key in ipairs({'caseId','expectedCaseRevision','subjectCharacterId','rulingType','summary','findings','outcome'}) do q[key]=p[key] end
        return Dispatch(a.value,'RecordRuling',q)
    end
}
Law.Routes['law.sentences.create.v1']={maxDepth=3,maxNodes=24,
    validate=function(p) return Fields(p,{'expectedCaseRevision','rulingId','sentenceType','terms'},true)
        and Integer(p.expectedCaseRevision,1,max) and Law.Uuid(p.rulingId) and Terms(p.sentenceType,p.terms) end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.sentence.impose');if not a.ok then return a end
        local q=Request(p,a.value)
        for _,key in ipairs({'caseId','expectedCaseRevision','rulingId','sentenceType','terms'}) do q[key]=p[key] end
        return Dispatch(a.value,'CreateSentence',q)
    end
}
for _,spec in ipairs({{route='rulings',op='ListCaseRulings',action='justice.ruling.view'},
    {route='sentences',op='ListCaseSentences',action='justice.sentence.view'}}) do
    Law.Routes['law.'..spec.route..'.list.v1']={
        validate=function(p) return Fields(p,{'cursor'},false) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
        handler=function(p,source,context)
            local a=Law.CaseAccess(p,source,context,spec.action);if not a.ok then return a end
            return Dispatch(a.value,spec.op,{actorSource=source,caseId=p.caseId,cursor=p.cursor,limit=25})
        end
    }
end
for _,spec in ipairs({{route='activate',op='ActivateSentence',action='justice.sentence.activate'},
    {route='suspend',op='SuspendSentence',action='justice.sentence.modify'},
    {route='resume',op='ResumeSentence',action='justice.sentence.modify'},
    {route='vacate',op='VacateSentence',action='justice.sentence.modify'}}) do
    Law.Routes['law.sentences.'..spec.route..'.v1']={
        validate=function(p) return Fields(p,{'recordId','expectedRevision'},true) and Law.Uuid(p.recordId) and Integer(p.expectedRevision,1,max) end,
        handler=function(p,source,context)
            local a=Law.CaseAccess(p,source,context,spec.action);if not a.ok then return a end
            local record=Law.Call('feather-justice','GetSentence',{actorSource=source,recordId=p.recordId})
            if not Law.Current(a.value) then return Law.Err('session_expired','Character changed.') end
            if not record.ok then return record end
            if record.value.caseId~=p.caseId or record.value.jurisdictionId~=a.value.jurisdictionId then return Law.Err('not_found','Sentence unavailable.') end
            local q=Request(p,a.value);q.recordId,q.expectedRevision=p.recordId,p.expectedRevision
            return Dispatch(a.value,spec.op,q)
        end
    }
end
Law.Routes['law.charges.amend.v1']={
    validate=function(p) return Fields(p,{'recordId','expectedRevision','statuteId','count'},true) and Law.Uuid(p.recordId)
        and Integer(p.expectedRevision,1,max) and (p.statuteId~=nil or p.count~=nil)
        and (p.statuteId==nil or Law.Uuid(p.statuteId)) and (p.count==nil or Integer(p.count,1,100)) end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.charge.amend');if not a.ok then return a end
        local record=Law.Call('feather-justice','GetCharge',{actorSource=source,recordId=p.recordId})
        if not Law.Current(a.value) then return Law.Err('session_expired','Character changed.') end
        if not record.ok then return record end
        if record.value.caseId~=p.caseId or record.value.jurisdictionId~=a.value.jurisdictionId then return Law.Err('not_found','Charge unavailable.') end
        local q=Request(p,a.value);q.recordId,q.expectedRevision,q.statuteId,q.count=p.recordId,p.expectedRevision,p.statuteId,p.count
        return Dispatch(a.value,'AmendCharge',q)
    end
}
for _,spec in ipairs({{route='seal',op='SealCase',action='justice.record.seal'},
    {route='unseal',op='UnsealCase',action='justice.record.seal'},{route='expunge',op='ExpungeCase',action='justice.record.expunge'}}) do
    Law.Routes['law.cases.'..spec.route..'.v1']={
        validate=function(p) return Fields(p,{'expectedRevision'},true) and Integer(p.expectedRevision,1,max) end,
        handler=function(p,source,context)
            local a=Law.CaseAccess(p,source,context,spec.action);if not a.ok then return a end
            local q=Request(p,a.value);q.caseId,q.expectedRevision=p.caseId,p.expectedRevision
            return Dispatch(a.value,spec.op,q)
        end
    }
end
Law.Routes['law.cases.history.v1']={
    validate=function(p) return Fields(p,{},false) end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.audit.view');if not a.ok then return a end
        return Dispatch(a.value,'GetRecordHistory',{actorSource=source,recordId=p.caseId,limit=25})
    end
}
Law.Routes['law.custody.sentence.reserve.v1']={
    validate=function(p) return Fields(p,{'sentenceId','expectedSentenceRevision','facilityKey'},true)
        and Law.Uuid(p.sentenceId) and Integer(p.expectedSentenceRevision,1,max) and Law.Token(p.facilityKey,64) end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.custody.book');if not a.ok then return a end
        local r=Law.Call('feather-justice','GetSentence',{actorSource=source,recordId=p.sentenceId})
        if not r.ok then return r end
        if r.value.caseId~=p.caseId or r.value.jurisdictionId~=a.value.jurisdictionId or not Law.Uuid(r.value.subjectCharacterId) then return Law.Err('not_found','Sentence unavailable.') end
        local target=Law.BookingPresence(a.value,r.value.subjectCharacterId,p.facilityKey,p.department);if not target.ok then return target end
        local q=Request(p,a.value);q.caseId,q.sentenceId,q.expectedSentenceRevision,q.facilityKey=p.caseId,p.sentenceId,p.expectedSentenceRevision,p.facilityKey
        if not Law.Current(target.value) then return Law.Err('session_expired','Subject changed.') end
        return Dispatch(a.value,'ReserveCustodyBooking',q)
    end
}
