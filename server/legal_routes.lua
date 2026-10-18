local maximumRevision=9007199254740989
local function Integer(value,min,max) return type(value)=='number' and value%1==0 and value>=min and value<=max end
local function Payload(request,fields,mutation)
    local allowed={department=true}
    for _,name in ipairs(fields) do allowed[name]=true end
    if mutation then allowed.requestId=true end
    return Law.Fields(request,allowed) and Law.Token(request.department,48)
        and (not mutation or Law.Token(request.requestId,64))
end
local function CaseAccess(request,source,context,action)
    local actor=Law.Access(source,context,request.department,action)
    if not actor.ok then return actor end
    local case=Law.Call('feather-justice','GetCase',{actorSource=source,recordId=request.caseId})
    if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
    if not case.ok then return case end
    if type(case.value)~='table' or case.value.jurisdictionId~=actor.value.jurisdictionId then
        return Law.Err('not_found','Case is unavailable in this department.')
    end
    return actor
end
local function Dispatch(actor,operation,request)
    local result=Law.Call('feather-justice',operation,request)
    if not Law.Current(actor) then return Law.Err('session_expired','Character changed; retain the original request ID.') end
    return result
end
local function Mutation(request,source,actor,reason)
    return {actorSource=source,requestId=actor.characterId..':'..request.requestId,reasonCode=reason}
end
Law.Routes['law.cases.get.v1']={
    validate=function(p) return Payload(p,{'caseId'},false) and Law.Uuid(p.caseId) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.case.view');if not actor.ok then return actor end
        return Dispatch(actor.value,'GetCase',{actorSource=source,recordId=p.caseId})
    end
}
Law.Routes['law.charges.propose.v1']={
    validate=function(p)
        return Payload(p,{'caseId','expectedCaseRevision','subjectCharacterId','statuteId','count'},true)
            and Law.Uuid(p.caseId) and Law.Uuid(p.subjectCharacterId) and Law.Uuid(p.statuteId)
            and Integer(p.expectedCaseRevision,1,maximumRevision) and Integer(p.count,1,100)
    end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.charge.propose');if not actor.ok then return actor end
        local request=Mutation(p,source,actor.value,'law.charge.propose')
        request.caseId,request.expectedCaseRevision=p.caseId,p.expectedCaseRevision
        request.subjectCharacterId,request.statuteId,request.count=p.subjectCharacterId,p.statuteId,p.count
        return Dispatch(actor.value,'ProposeCharge',request)
    end
}
Law.Routes['law.warrants.draft.v1']={
    validate=function(p)
        return Payload(p,{'caseId','expectedCaseRevision','subjectCharacterId','basisSummary','validForSeconds'},true)
            and Law.Uuid(p.caseId) and Law.Uuid(p.subjectCharacterId) and Integer(p.expectedCaseRevision,1,maximumRevision)
            and Law.Text(p.basisSummary,2000) and Integer(p.validForSeconds,60,2592000)
    end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.warrant.draft');if not actor.ok then return actor end
        local request=Mutation(p,source,actor.value,'law.warrant.draft')
        request.caseId,request.expectedCaseRevision=p.caseId,p.expectedCaseRevision
        request.subjectCharacterId,request.basisSummary=p.subjectCharacterId,p.basisSummary
        request.warrantType,request.validForSeconds='arrest',p.validForSeconds
        return Dispatch(actor.value,'CreateWarrantDraft',request)
    end
}
for _,spec in ipairs({
    {route='law.charges.list.v1',operation='ListCharges',action='justice.charge.view'},
    {route='law.warrants.list.v1',operation='ListCaseWarrants',action='justice.warrant.view'}
}) do
    Law.Routes[spec.route]={
        validate=function(p) return Payload(p,{'caseId','cursor'},false) and Law.Uuid(p.caseId) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
        handler=function(p,source,context)
            local actor=CaseAccess(p,source,context,spec.action);if not actor.ok then return actor end
            return Dispatch(actor.value,spec.operation,{actorSource=source,caseId=p.caseId,
                jurisdictionId=actor.value.jurisdictionId,limit=25,cursor=p.cursor})
        end
    }
end
Law.Routes['law.warrants.active.v1']={
    validate=function(p)
        return Payload(p,{'subjectCharacterId','cursor'},false)
            and (p.subjectCharacterId==nil or Law.Uuid(p.subjectCharacterId)) and (p.cursor==nil or Law.Uuid(p.cursor))
    end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.warrant.view');if not actor.ok then return actor end
        return Dispatch(actor.value,'ListActiveWarrants',{actorSource=source,jurisdictionId=actor.value.jurisdictionId,
            subjectCharacterId=p.subjectCharacterId,cursor=p.cursor,limit=25})
    end
}
for _,spec in ipairs({
    {route='law.charges.file.v1',operation='FileCharge',kind='charge',action='justice.charge.file'},
    {route='law.charges.dispose.v1',operation='DisposeCharge',kind='charge',action='justice.charge.dispose',disposition=true},
    {route='law.warrants.issue.v1',operation='IssueWarrant',kind='warrant',action='justice.warrant.issue'},
    {route='law.warrants.serve.v1',operation='ServeWarrant',kind='warrant',action='justice.warrant.serve'},
    {route='law.warrants.recall.v1',operation='RecallWarrant',kind='warrant',action='justice.warrant.recall'},
    {route='law.warrants.quash.v1',operation='QuashWarrant',kind='warrant',action='justice.warrant.quash'}
}) do
    Law.Routes[spec.route]={
        validate=function(p)
            local fields={'caseId','recordId','expectedRevision'}
            if spec.disposition then fields[#fields+1]='status' end
            return Payload(p,fields,true) and Law.Uuid(p.caseId) and Law.Uuid(p.recordId)
                and Integer(p.expectedRevision,1,maximumRevision)
                and (not spec.disposition or p.status=='withdrawn' or p.status=='dismissed')
        end,
        handler=function(p,source,context)
            local actor=CaseAccess(p,source,context,spec.action);if not actor.ok then return actor end
            local record=Law.Call('feather-justice',spec.kind=='charge' and 'GetCharge' or 'GetWarrant',
                {actorSource=source,recordId=p.recordId})
            if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
            if not record.ok then return record end
            if type(record.value)~='table' or record.value.caseId~=p.caseId
                or record.value.jurisdictionId~=actor.value.jurisdictionId then
                return Law.Err('not_found','Record is unavailable for this case.')
            end
            local request=Mutation(p,source,actor.value,'law.'..spec.kind..'.change')
            request.recordId,request.expectedRevision=p.recordId,p.expectedRevision
            if spec.disposition then request.status=p.status end
            return Dispatch(actor.value,spec.operation,request)
        end
    }
end

for _,spec in ipairs({
    {route='law.parties.list.v1',operation='ListCaseParties',action='justice.party.view',fields={'caseId','cursor'}},
    {route='law.parties.add.v1',operation='AddCaseParty',action='justice.party.manage',fields={'caseId','expectedCaseRevision','subjectCharacterId','role'},mutation=true},
    {route='law.parties.remove.v1',operation='RemoveCaseParty',action='justice.party.manage',fields={'caseId','recordId','expectedRevision'},mutation=true},
    {route='law.cases.update.v1',operation='UpdateCaseSummary',action='justice.case.update',fields={'caseId','expectedRevision','summary'},mutation=true,caseRecord=true},
    {route='law.cases.transition.v1',operation='TransitionCase',action='justice.case.transition',fields={'caseId','expectedRevision','status'},mutation=true,caseRecord=true},
    {route='law.statutes.list.v1',operation='ListStatutes',action='justice.definition.view',fields={'cursor'}}
}) do
    Law.Routes[spec.route]={
        validate=function(p)
            if not Payload(p,spec.fields,spec.mutation) then return false end
            for _,key in ipairs(spec.fields) do
                local value=p[key]
                if key=='cursor' then if value~=nil and not Law.Uuid(value) then return false end
                elseif key=='caseId' or key=='recordId' or key=='subjectCharacterId' then if not Law.Uuid(value) then return false end
                elseif key=='expectedRevision' or key=='expectedCaseRevision' then if not Integer(value,1,maximumRevision) then return false end
                elseif key=='summary' then if not Law.Text(value,4000) then return false end
                elseif key=='role' then if not ({suspect=true,defendant=true,victim=true,witness=true,reporting_officer=true,investigating_officer=true,prosecutor=true,defense_counsel=true,judge=true})[value or ''] then return false end
                elseif key=='status' then if not ({filed=true,closed=true,dismissed=true})[value or ''] then return false end end
            end
            return true
        end,
        handler=function(p,source,context)
            local actor
            if p.caseId then actor=CaseAccess(p,source,context,spec.action) else actor=Law.Access(source,context,p.department,spec.action) end
            if not actor.ok then return actor end
            local request=spec.mutation and Mutation(p,source,actor.value,'law.mdt.change') or {actorSource=source}
            for _,key in ipairs(spec.fields) do request[key]=p[key] end
            if spec.caseRecord then request.recordId,request.caseId=p.caseId,nil end
            if spec.operation=='ListStatutes' then request.jurisdictionId=actor.value.jurisdictionId;request.limit=25 end
            return Dispatch(actor.value,spec.operation,request)
        end
    }
end

Law.Routes['law.citations.list.v1']={
    validate=function(p) return Payload(p,{'caseId','cursor'},false) and Law.Uuid(p.caseId) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.citation.view');if not actor.ok then return actor end
        return Dispatch(actor.value,'ListCaseCitations',{actorSource=source,caseId=p.caseId,cursor=p.cursor,limit=25})
    end
}
Law.Routes['law.citations.issue.v1']={
    validate=function(p)
        return Payload(p,{'caseId','expectedCaseRevision','subjectCharacterId','amount','dueInSeconds','basisSummary'},true)
            and Law.Uuid(p.caseId) and Law.Uuid(p.subjectCharacterId) and Integer(p.expectedCaseRevision,1,maximumRevision)
            and Integer(p.amount,1,1000000000000) and Integer(p.dueInSeconds,60,31536000) and Law.Text(p.basisSummary,2000)
    end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.citation.issue');if not actor.ok then return actor end
        local request=Mutation(p,source,actor.value,'law.citation.issue')
        for _,key in ipairs({'caseId','expectedCaseRevision','subjectCharacterId','amount','dueInSeconds','basisSummary'}) do request[key]=p[key] end
        return Dispatch(actor.value,'RequestCitation',request)
    end
}
Law.Routes['law.citations.cancel.v1']={
    validate=function(p) return Payload(p,{'caseId','recordId','expectedRevision'},true) and Law.Uuid(p.caseId)
        and Law.Uuid(p.recordId) and Integer(p.expectedRevision,1,maximumRevision) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.citation.cancel');if not actor.ok then return actor end
        local citation=Law.Call('feather-justice','GetCitation',{actorSource=source,recordId=p.recordId})
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
        if not citation.ok then return citation end
        if citation.value.caseId~=p.caseId or citation.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Citation unavailable.') end
        local request=Mutation(p,source,actor.value,'law.citation.cancel')
        request.caseId,request.recordId,request.expectedRevision=p.caseId,p.recordId,p.expectedRevision
        return Dispatch(actor.value,'CancelCitation',request)
    end
}
