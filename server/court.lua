-- Court: rulings, sentences, privacy, history and the penal-code editor
-- (Law master plan LAW4/LAW6; Justice Contract 1 ruling/sentence/record-access operations).
local max=9007199254740990
local function Integer(n,a,b) return type(n)=='number' and n%1==0 and n>=a and n<=b end
local function Fields(p,names,mutation)
    local allowed={department=true,caseId=true};for _,name in ipairs(names) do allowed[name]=true end
    if mutation then allowed.requestId=true end
    return Law.Fields(p,allowed) and Law.Token(p.department,48) and Law.Uuid(p.caseId) and (not mutation or Law.Token(p.requestId,64))
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
    else return ({property=true,asset=true,item=true})[t.targetType or '']==true and Law.Token(t.targetReference,64) end
end
local function Related(kind)
    return function(p,source,context)
        local a=Law.CaseAccess(p,source,context,kind=='ruling' and 'justice.case.view' or 'justice.sentence.view',true)
        if not a.ok then return a end
        local related=a.value.case.related
        return Law.Ok(type(related)=='table' and related[kind] or {items={},truncated=false})
    end
end

Law.Routes['law.rulings.record.v1']={mutation=true,maxDepth=4,maxNodes=128,
    validate=function(p)
        return Fields(p,{'expectedCaseRevision','subjectCharacterId','rulingType','summary','findings','outcome'},true)
            and Integer(p.expectedCaseRevision,1,max) and (p.subjectCharacterId==nil or Law.Uuid(p.subjectCharacterId)) and Law.Text(p.summary,4000)
            and ((p.rulingType=='verdict' and p.subjectCharacterId~=nil and Findings(p.findings) and p.outcome==nil)
                or (p.rulingType=='dismissal' and p.findings==nil and p.outcome==nil)
                or (p.rulingType=='order' and p.findings==nil and Law.Token(p.outcome,64)))
    end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.ruling.record');if not a.ok then return a end
        local q=Law.Mutation(p,a.value,'law.court.ruling')
        for _,key in ipairs({'caseId','expectedCaseRevision','subjectCharacterId','rulingType','summary','findings','outcome'}) do q[key]=p[key] end
        return Law.Dispatch(a.value,'RecordRuling',q)
    end
}
Law.Routes['law.rulings.list.v1']={validate=function(p) return Fields(p,{},false) end,handler=Related('ruling')}
Law.Routes['law.sentences.list.v1']={validate=function(p) return Fields(p,{},false) end,handler=Related('sentence')}
Law.Routes['law.sentences.create.v1']={mutation=true,maxDepth=3,maxNodes=24,
    validate=function(p) return Fields(p,{'expectedCaseRevision','rulingId','sentenceType','terms'},true)
        and Integer(p.expectedCaseRevision,1,max) and Law.Uuid(p.rulingId) and Terms(p.sentenceType,p.terms) end,
    handler=function(p,source,context)
        local a=Law.CaseAccess(p,source,context,'justice.sentence.impose');if not a.ok then return a end
        local q=Law.Mutation(p,a.value,'law.court.sentence')
        for _,key in ipairs({'caseId','expectedCaseRevision','rulingId','sentenceType','terms'}) do q[key]=p[key] end
        return Law.Dispatch(a.value,'CreateSentence',q)
    end
}
-- Activate also resumes a suspended sentence; complete carries served, vacated or commuted.
for _,spec in ipairs({{route='activate',op='ActivateSentence',action='justice.sentence.activate'},
    {route='suspend',op='SuspendSentence',action='justice.sentence.suspend'},
    {route='complete',op='CompleteSentence',action='justice.sentence.complete',complete=true}}) do
    Law.Routes['law.sentences.'..spec.route..'.v1']={mutation=true,
        validate=function(p)
            return Fields(p,{'sentenceId','expectedRevision','outcome','effectReference'},true) and Law.Uuid(p.sentenceId) and Integer(p.expectedRevision,1,max)
                and ((spec.complete and ({served=true,vacated=true,commuted=true})[p.outcome or '']==true
                        and (p.effectReference==nil or Law.Token(p.effectReference,128)))
                    or (not spec.complete and p.outcome==nil and p.effectReference==nil))
        end,
        handler=function(p,source,context)
            local a=Law.CaseAccess(p,source,context,spec.action);if not a.ok then return a end
            local q=Law.Mutation(p,a.value,'law.court.sentence.'..spec.route)
            q.sentenceId,q.expectedRevision,q.outcome,q.effectReference=p.sentenceId,p.expectedRevision,p.outcome,p.effectReference
            return Law.Dispatch(a.value,spec.op,q)
        end
    }
end
for _,spec in ipairs({{route='seal',op='SealCase',action='justice.record.seal'},
    {route='unseal',op='UnsealCase',action='justice.record.seal'},{route='expunge',op='ExpungeRecord',action='justice.record.expunge'}}) do
    Law.Routes['law.cases.'..spec.route..'.v1']={mutation=true,
        validate=function(p) return Fields(p,{'expectedRevision'},true) and Integer(p.expectedRevision,1,max) end,
        handler=function(p,source,context)
            -- A sealed case is only readable with view_sealed, so check the department via the policy action itself.
            local a=Law.Access(source,context,p.department,spec.action);if not a.ok then return a end
            local q=Law.Mutation(p,a.value,'law.court.'..spec.route)
            q.caseId,q.expectedRevision=p.caseId,p.expectedRevision
            return Law.Dispatch(a.value,spec.op,q)
        end
    }
end
Law.Routes['law.cases.history.v1']={
    validate=function(p) return Fields(p,{},false) end,
    handler=function(p,source,context)
        local a=Law.Access(source,context,p.department,'justice.audit.view');if not a.ok then return a end
        return Law.Dispatch(a.value,'GetRecordHistory',{actorSource=source,recordId=p.caseId,limit=50})
    end
}

-- Penal code editor: statutes are Justice definitions; recommended ranges advise
-- officers and judges and never apply a punishment automatically.
local severities={infraction=true,misdemeanor=true,felony=true}
local function Range(r,maximum)
    return r==nil or (type(r)=='table' and Law.Fields(r,{min=true,max=true}) and Integer(r.min,0,maximum) and Integer(r.max,r.min or 0,maximum))
end
local function StatuteFields(p,revise)
    return (p.title==nil and revise or Law.Text(p.title,180)) and (p.description==nil or Law.Text(p.description,4000))
        and (p.category==nil and revise or Law.Token(p.category,32)) and (p.severityClass==nil and revise or severities[p.severityClass]==true)
        and Range(p.recommendedFine,1000000000) and Range(p.recommendedCustodySeconds,31536000)
        and (p.status==nil or p.status=='active' or p.status=='retired')
end
Law.Routes['law.statutes.register.v1']={mutation=true,maxDepth=3,maxNodes=24,
    validate=function(p) return Law.Fields(p,{department=true,requestId=true,statuteName=true,title=true,description=true,category=true,
            severityClass=true,recommendedFine=true,recommendedCustodySeconds=true})
        and Law.Token(p.department,48) and Law.Token(p.requestId,64) and type(p.statuteName)=='string'
        and p.statuteName:match('^[a-z][a-z0-9_.]*$')~=nil and #p.statuteName<=48 and StatuteFields(p,false) end,
    handler=function(p,source,context)
        local a=Law.Access(source,context,p.department,'justice.definition.manage');if not a.ok then return a end
        local department=LawConfig.Departments[p.department]
        local q=Law.Mutation(p,a.value,'law.statute.register')
        q.jurisdictionId,q.statuteKey=a.value.jurisdictionId,department.jurisdictionKey..'.'..p.statuteName
        for _,key in ipairs({'title','description','category','severityClass','recommendedFine','recommendedCustodySeconds'}) do q[key]=p[key] end
        return Law.Dispatch(a.value,'RegisterStatute',q)
    end
}
Law.Routes['law.statutes.revise.v1']={mutation=true,maxDepth=3,maxNodes=24,
    validate=function(p) return Law.Fields(p,{department=true,requestId=true,statuteId=true,expectedRevision=true,title=true,description=true,
            category=true,severityClass=true,recommendedFine=true,recommendedCustodySeconds=true,status=true})
        and Law.Token(p.department,48) and Law.Token(p.requestId,64) and Law.Uuid(p.statuteId) and Integer(p.expectedRevision,1,max)
        and StatuteFields(p,true) end,
    handler=function(p,source,context)
        local a=Law.Access(source,context,p.department,'justice.definition.manage');if not a.ok then return a end
        local statute=Law.Dispatch(a.value,'GetStatute',{actorSource=source,statuteId=p.statuteId})
        if not statute.ok then return statute end
        if statute.value.jurisdictionId~=a.value.jurisdictionId then return Law.Err('not_found','Statute unavailable in this department.') end
        local q=Law.Mutation(p,a.value,'law.statute.revise')
        for _,key in ipairs({'statuteId','expectedRevision','title','description','category','severityClass','recommendedFine',
            'recommendedCustodySeconds','status'}) do q[key]=p[key] end
        return Law.Dispatch(a.value,'ReviseStatute',q)
    end
}
