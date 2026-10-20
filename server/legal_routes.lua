-- Case, party, charge, warrant, statute and citation routes (Law master plan LAW4/LAW5).
-- Each route validates the client payload, checks duty/qualification/policy through
-- Law.Access and calls exactly one Justice Contract 1 operation. Justice enforces
-- record eligibility, jurisdiction scope and invariants.
local maximumRevision=9007199254740989
local function Integer(value,min,max) return type(value)=='number' and value%1==0 and value>=min and value<=max end
local function Payload(request,fields,mutation)
    local allowed={department=true}
    for _,name in ipairs(fields) do allowed[name]=true end
    if mutation then allowed.requestId=true end
    return Law.Fields(request,allowed) and Law.Token(request.department,48)
        and (not mutation or Law.Token(request.requestId,64))
end
Law.RoutePayload=Payload
local function Mutation(request,actor,reason)
    return {actorSource=actor.source,requestId=actor.characterId..':'..request.requestId,reasonCode=reason}
end
Law.Mutation=Mutation
-- Reads the case through Justice and confirms it belongs to the department.
function Law.CaseAccess(p,source,context,action,includeRelated)
    local actor=Law.Access(source,context,p.department,action);if not actor.ok then return actor end
    local case=Law.Dispatch(actor.value,'GetCase',{actorSource=source,caseId=p.caseId,includeRelated=includeRelated or nil})
    if not case.ok then return case end
    if type(case.value)~='table' or case.value.jurisdictionId~=actor.value.jurisdictionId then
        return Law.Err('not_found','Case is unavailable in this department.')
    end
    actor.value.case=case.value
    return actor
end
local roles={suspect=true,defendant=true,victim=true,witness=true,reporting_officer=true,investigating_officer=true,
    prosecutor=true,defense_counsel=true,judge=true}
local warrantTypes={arrest=true,search=true,seizure=true,summons=true}

Law.Routes['law.cases.get.v1']={
    validate=function(p) return Payload(p,{'caseId'},false) and Law.Uuid(p.caseId) end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.case.view');if not actor.ok then return actor end
        local case=Law.Dispatch(actor.value,'GetCase',{actorSource=source,caseId=p.caseId,includeRelated=true})
        if case.ok and (type(case.value)~='table' or case.value.jurisdictionId~=actor.value.jurisdictionId) then
            return Law.Err('not_found','Case is unavailable in this department.')
        end
        return case
    end
}
Law.Routes['law.cases.update.v1']={mutation=true,
    validate=function(p) return Payload(p,{'caseId','expectedRevision','summary','title'},true) and Law.Uuid(p.caseId)
        and Integer(p.expectedRevision,1,maximumRevision) and Law.Text(p.summary,4000) and (p.title==nil or Law.Text(p.title,180)) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.case.update');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.case.update')
        request.caseId,request.expectedRevision,request.summary,request.title=p.caseId,p.expectedRevision,p.summary,p.title
        return Law.Dispatch(actor.value,'UpdateCaseSummary',request)
    end
}
Law.Routes['law.cases.transition.v1']={mutation=true,
    validate=function(p) return Payload(p,{'caseId','expectedRevision','status'},true) and Law.Uuid(p.caseId)
        and Integer(p.expectedRevision,1,maximumRevision)
        and ({open=true,filed=true,pending_hearing=true,closed=true,dismissed=true})[p.status or '']==true end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.case.transition');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.case.transition')
        request.caseId,request.expectedRevision,request.status=p.caseId,p.expectedRevision,p.status
        return Law.Dispatch(actor.value,'TransitionCase',request)
    end
}

-- Parties ----------------------------------------------------------------------------
Law.Routes['law.parties.list.v1']={
    validate=function(p) return Payload(p,{'caseId','cursor','includeRemoved'},false) and Law.Uuid(p.caseId)
        and (p.cursor==nil or Law.Uuid(p.cursor)) and (p.includeRemoved==nil or type(p.includeRemoved)=='boolean') end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.party.view');if not actor.ok then return actor end
        return Law.Dispatch(actor.value,'ListCaseParties',{actorSource=source,caseId=p.caseId,cursor=p.cursor,
            includeRemoved=p.includeRemoved,limit=25})
    end
}
Law.Routes['law.parties.add.v1']={mutation=true,
    validate=function(p) return Payload(p,{'caseId','expectedCaseRevision','partyType','partyIdReference','partyRole'},true)
        and Law.Uuid(p.caseId) and Integer(p.expectedCaseRevision,1,maximumRevision)
        and (p.partyType=='character' or p.partyType=='organization') and Law.Uuid(p.partyIdReference) and roles[p.partyRole or '']==true end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.party.manage');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.party.add')
        for _,key in ipairs({'caseId','expectedCaseRevision','partyType','partyIdReference','partyRole'}) do request[key]=p[key] end
        return Law.Dispatch(actor.value,'AddCaseParty',request)
    end
}
Law.Routes['law.parties.remove.v1']={mutation=true,
    validate=function(p) return Payload(p,{'caseId','partyId','expectedRevision'},true) and Law.Uuid(p.caseId)
        and Law.Uuid(p.partyId) and Integer(p.expectedRevision,1,maximumRevision) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.party.manage');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.party.remove')
        request.partyId,request.expectedRevision=p.partyId,p.expectedRevision
        return Law.Dispatch(actor.value,'RemoveCaseParty',request)
    end
}

-- Charges ----------------------------------------------------------------------------
Law.Routes['law.charges.list.v1']={
    validate=function(p) return Payload(p,{'caseId','cursor'},false) and Law.Uuid(p.caseId) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.charge.view');if not actor.ok then return actor end
        return Law.Dispatch(actor.value,'ListCharges',{actorSource=source,caseId=p.caseId,cursor=p.cursor,limit=25})
    end
}
Law.Routes['law.charges.propose.v1']={mutation=true,
    validate=function(p)
        return Payload(p,{'caseId','expectedCaseRevision','defendantCharacterId','statuteId','count'},true)
            and Law.Uuid(p.caseId) and Law.Uuid(p.defendantCharacterId) and Law.Uuid(p.statuteId)
            and Integer(p.expectedCaseRevision,1,maximumRevision) and Integer(p.count,1,100)
    end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.charge.propose');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.charge.propose')
        for _,key in ipairs({'caseId','expectedCaseRevision','defendantCharacterId','statuteId','count'}) do request[key]=p[key] end
        return Law.Dispatch(actor.value,'ProposeCharge',request)
    end
}
Law.Routes['law.charges.amend.v1']={mutation=true,
    validate=function(p) return Payload(p,{'caseId','chargeId','expectedRevision','statuteId','count'},true) and Law.Uuid(p.caseId)
        and Law.Uuid(p.chargeId) and Integer(p.expectedRevision,1,maximumRevision) and (p.statuteId~=nil or p.count~=nil)
        and (p.statuteId==nil or Law.Uuid(p.statuteId)) and (p.count==nil or Integer(p.count,1,100)) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.charge.amend');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.charge.amend')
        request.chargeId,request.expectedRevision,request.statuteId,request.count=p.chargeId,p.expectedRevision,p.statuteId,p.count
        return Law.Dispatch(actor.value,'AmendCharge',request)
    end
}
for _,spec in ipairs({
    {route='law.charges.file.v1',operation='FileCharge',action='justice.charge.file'},
    {route='law.charges.dispose.v1',operation='DisposeCharge',action='justice.charge.dispose',disposition=true}
}) do
    Law.Routes[spec.route]={mutation=true,
        validate=function(p)
            return Payload(p,{'caseId','chargeId','expectedRevision','disposition'},true) and Law.Uuid(p.caseId) and Law.Uuid(p.chargeId)
                and Integer(p.expectedRevision,1,maximumRevision)
                and ((spec.disposition and (p.disposition=='withdrawn' or p.disposition=='dismissed')) or (not spec.disposition and p.disposition==nil))
        end,
        handler=function(p,source,context)
            local actor=Law.CaseAccess(p,source,context,spec.action);if not actor.ok then return actor end
            local request=Mutation(p,actor.value,'law.charge.change')
            request.chargeId,request.expectedRevision,request.disposition=p.chargeId,p.expectedRevision,p.disposition
            return Law.Dispatch(actor.value,spec.operation,request)
        end
    }
end

-- Warrants ---------------------------------------------------------------------------
Law.Routes['law.warrants.list.v1']={
    validate=function(p) return Payload(p,{'caseId'},false) and Law.Uuid(p.caseId) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.warrant.view',true);if not actor.ok then return actor end
        local related=actor.value.case.related
        return Law.Ok(type(related)=='table' and related.warrant or {items={},truncated=false})
    end
}
Law.Routes['law.warrants.active.v1']={
    validate=function(p)
        return Payload(p,{'subjectCharacterId','cursor'},false)
            and (p.subjectCharacterId==nil or Law.Uuid(p.subjectCharacterId)) and (p.cursor==nil or Law.Uuid(p.cursor))
    end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.warrant.view');if not actor.ok then return actor end
        return Law.Dispatch(actor.value,'ListActiveWarrants',{actorSource=source,jurisdictionId=actor.value.jurisdictionId,
            subjectCharacterId=p.subjectCharacterId,cursor=p.cursor,limit=25})
    end
}
Law.Routes['law.warrants.draft.v1']={mutation=true,
    validate=function(p)
        return Payload(p,{'caseId','expectedCaseRevision','subjectCharacterId','warrantType','basisSummary','validForSeconds'},true)
            and Law.Uuid(p.caseId) and Law.Uuid(p.subjectCharacterId) and Integer(p.expectedCaseRevision,1,maximumRevision)
            and warrantTypes[p.warrantType or '']==true and Law.Text(p.basisSummary,2000) and Integer(p.validForSeconds,60,2592000)
    end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.warrant.draft');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.warrant.draft')
        for _,key in ipairs({'caseId','expectedCaseRevision','subjectCharacterId','warrantType','basisSummary','validForSeconds'}) do request[key]=p[key] end
        return Law.Dispatch(actor.value,'CreateWarrantDraft',request)
    end
}
for _,spec in ipairs({
    {route='issue',operation='IssueWarrant',action='justice.warrant.issue'},
    {route='serve',operation='ServeWarrant',action='justice.warrant.serve'},
    {route='recall',operation='RecallWarrant',action='justice.warrant.recall'},
    {route='quash',operation='QuashWarrant',action='justice.warrant.quash'}
}) do
    Law.Routes['law.warrants.'..spec.route..'.v1']={mutation=true,
        validate=function(p) return Payload(p,{'caseId','warrantId','expectedRevision'},true) and Law.Uuid(p.caseId)
            and Law.Uuid(p.warrantId) and Integer(p.expectedRevision,1,maximumRevision) end,
        handler=function(p,source,context)
            local actor=Law.CaseAccess(p,source,context,spec.action);if not actor.ok then return actor end
            local request=Mutation(p,actor.value,'law.warrant.'..spec.route)
            request.warrantId,request.expectedRevision=p.warrantId,p.expectedRevision
            return Law.Dispatch(actor.value,spec.operation,request)
        end
    }
end

-- Statutes (penal code) -----------------------------------------------------------
Law.Routes['law.statutes.list.v1']={
    validate=function(p) return Payload(p,{'cursor','status'},false) and (p.cursor==nil or Law.Uuid(p.cursor))
        and (p.status==nil or p.status=='active' or p.status=='retired') end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.definition.view');if not actor.ok then return actor end
        return Law.Dispatch(actor.value,'ListStatutes',{actorSource=source,jurisdictionId=actor.value.jurisdictionId,
            status=p.status,cursor=p.cursor,limit=25})
    end
}

-- Citations --------------------------------------------------------------------------
Law.Routes['law.citations.list.v1']={
    validate=function(p) return Payload(p,{'caseId','cursor'},false) and Law.Uuid(p.caseId) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.citation.view');if not actor.ok then return actor end
        return Law.Dispatch(actor.value,'ListCitations',{actorSource=source,caseId=p.caseId,cursor=p.cursor,limit=25})
    end
}
Law.Routes['law.citations.issue.v1']={mutation=true,
    validate=function(p)
        return Payload(p,{'caseId','expectedCaseRevision','subjectCharacterId','statuteId','basisSummary','amount','dueInSeconds'},true)
            and Law.Uuid(p.caseId) and Law.Uuid(p.subjectCharacterId) and Law.Uuid(p.statuteId)
            and Integer(p.expectedCaseRevision,1,maximumRevision) and Law.Text(p.basisSummary,2000)
            and (p.amount==nil)==(p.dueInSeconds==nil)
            and (p.amount==nil or (Integer(p.amount,1,1000000000000) and Integer(p.dueInSeconds,60,31536000)))
    end,
    handler=function(p,source,context)
        local actor=Law.CaseAccess(p,source,context,'justice.citation.issue');if not actor.ok then return actor end
        local request=Mutation(p,actor.value,'law.citation.issue')
        for _,key in ipairs({'caseId','expectedCaseRevision','subjectCharacterId','statuteId','basisSummary','amount','dueInSeconds'}) do request[key]=p[key] end
        return Law.Dispatch(actor.value,'IssueCitation',request)
    end
}
