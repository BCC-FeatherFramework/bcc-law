local maximum=9007199254740990
local function Int(n,min,max) return type(n)=='number' and n%1==0 and n>=min and n<=max end
local function Number(n,min,max) return type(n)=='number' and n==n and n>=min and n<=max end
local setup={}
local collectFields={department=true,caseId=true,expectedCaseRevision=true,targetSource=true,warrantId=true,
    itemId=true,itemRevision=true,lockerKey=true,description=true,requestId=true}
local function Payload(p,fields)
    return Law.Fields(p,fields) and Law.Token(p.department,48) and Law.Uuid(p.caseId)
end
local function CollectValid(p,internal)
    local fields=Law.Copy(collectFields)
    if internal then fields.actorSource=true;fields.characterId=true;fields.sessionId=true end
    return Payload(p,fields) and Law.Token(p.requestId,internal and 128 or 64)
        and Int(p.expectedCaseRevision,1,maximum) and Int(p.targetSource,1,65535) and Law.Uuid(p.warrantId)
        and Int(p.itemId,1,maximum) and Int(p.itemRevision,0,maximum) and Law.Token(p.lockerKey,64)
        and (p.description==nil or Law.Text(p.description,1000))
end
function Law.ValidateEvidenceConfig()
    local e=LawConfig.Evidence
    if type(e)~='table' or not Law.Fields(e,{Lockers=true}) or type(e.Lockers)~='table' then return false end
    local count=0
    for key,c in pairs(e.Lockers) do
        count=count+1
        if not Law.Token(key,64) or type(c)~='table' or not Law.Fields(c,{department=true,label=true,x=true,y=true,z=true,radius=true,maxItems=true,maxWeight=true})
            or not LawConfig.Departments[c.department or ''] or not Law.Text(c.label,100)
            or not Number(c.x,-100000,100000) or not Number(c.y,-100000,100000) or not Number(c.z,-10000,10000)
            or not Number(c.radius,0.5,5) or not Int(c.maxItems,1,10000) or not Number(c.maxWeight,1,999999) then return false end
    end
    return count<=32
end
local function CaseAccess(p,source,context,action)
    local actor=Law.Access(source,context,p.department,action);if not actor.ok then return actor end
    local case=Law.Call('feather-justice','GetCase',{actorSource=source,recordId=p.caseId})
    if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
    if not case.ok then return case end
    if type(case.value)~='table' or case.value.jurisdictionId~=actor.value.jurisdictionId then return Law.Err('not_found','Case unavailable.') end
    return actor
end
local function Inventory(operation,p)
    local r=Law.Call('feather-inventory',operation,p)
    if not r.ok and type(r.error)=='table' then return Law.Err(r.error.code,r.error.message) end
    return r
end
local function Internal(p,actor)
    local r=Law.Copy(p);r.actorSource=actor.source;r.characterId=actor.characterId;r.sessionId=actor.sessionId
    if r.caseId then r.caseId=r.caseId:lower() end
    if r.requestId then r.requestId=actor.characterId..':'..r.requestId end
    return r
end
local function ProviderReady()
    local c=Law.Call('feather-justice','GetCapabilities')
    return c.ok and type(c.value)=='table' and c.value.contract==1 and type(c.value.features)=='table'
        and c.value.features.evidenceLinks==1 and c.value.features.evidenceGuard==1
end
function Law.EvidenceAvailable()
    if not Law.Ready() or not ProviderReady() then return false end
    local r=Inventory('GetLawEvidenceCapabilities')
    return r.ok and type(r.value)=='table' and r.value.contract==1 and r.value.state=='ready' and r.value.transfers==1
end
local function CollectAccess(p,source,context)
    local actor=CaseAccess(p,source,context,'justice.evidence.link');if not actor.ok then return actor end
    local field=Law.Access(source,context,p.department,'law.evidence.collect');if not field.ok then return field end
    if not ProviderReady() then return Law.Err('evidence_unavailable','Justice evidence link and guard must be ready.') end
    local target=Law.RestrainedTarget(actor.value,p.targetSource,p.department);if not target.ok then return target end
    local warrant=Law.Call('feather-justice','GetWarrant',{actorSource=source,recordId=p.warrantId})
    if not warrant.ok then return warrant end
    local w=warrant.value
    if type(w)~='table' or w.status~='active' or w.caseId~=p.caseId or w.jurisdictionId~=actor.value.jurisdictionId
        or type(w.subjectCharacterId)~='string' or w.subjectCharacterId:lower()~=target.value.characterId:lower()
        or type(w.document)~='table' or w.document.warrantType~='seizure' then
        return Law.Err('seizure_authority_required','An active seizure warrant for this subject and case is required.')
    end
    local c=LawConfig.Evidence.Lockers[p.lockerKey or '']
    if not c or c.department~=p.department then return Law.Err('locker_unavailable','Locker unavailable for this department.') end
    local ped=GetPlayerPed(source);if not ped or ped==0 then return Law.Err('proximity_required','Locker presence required.') end
    local coords=GetEntityCoords(ped)
    if not coords or not Number(coords.x,-100000,100000) or not Number(coords.y,-100000,100000) or not Number(coords.z,-10000,10000)
        or (coords.x-c.x)^2+(coords.y-c.y)^2+(coords.z-c.z)^2>c.radius^2 then
        return Law.Err('proximity_required','Officer and subject must be at the configured locker.')
    end
    local again=Law.RestrainedTarget(actor.value,p.targetSource,p.department)
    if not again.ok or not Law.Current(actor.value) or not Law.Current(target.value)
        or again.value.sessionId~=target.value.sessionId or again.value.characterId~=target.value.characterId then
        return Law.Err('session_expired','Collection conditions changed.')
    end
    return Law.Ok({actor=actor.value,target=target.value})
end
exports('AuthorizeEvidenceOperation',function(operation,p)
    if GetInvokingResource()~='feather-inventory' then return Law.Err('authorization_denied','Inventory caller required.') end
    if operation=='setup' then
        local key=type(p)=='table' and p.lockerKey
        if not key or not setup[key] or not LawConfig.Evidence.Lockers[key] then return Law.Err('authorization_denied','Explicit console setup required.') end
        return Law.Ok({locker=Law.Copy(LawConfig.Evidence.Lockers[key])})
    end
    if type(p)~='table' or not Int(p.actorSource,1,65535) or not Law.Uuid(p.characterId) or not Law.Uuid(p.sessionId)
        or not Law.Token(p.department,48) or not Law.Uuid(p.caseId) then return Law.Err('invalid_input','Invalid actor/case context.') end
    local context={characterId=p.characterId,sessionId=p.sessionId}
    if operation=='history' then
        local actor=CaseAccess(p,p.actorSource,context,'justice.evidence.view')
        return actor.ok and Law.Ok({actor=actor.value}) or actor
    end
    if operation~='collect' or not CollectValid(p,true) then return Law.Err('invalid_input','Invalid evidence operation.') end
    return CollectAccess(p,p.actorSource,context)
end)
local function LinkReceipt(p,actor,receipt,requestId,expectedRevision)
    if not ProviderReady() then return Law.Err('evidence_link_pending','Collected item awaits Justice evidence readiness. Retain the transfer ID.') end
    local r=Law.Call('feather-justice','LinkEvidence',{actorSource=actor.source,caseId=p.caseId,
        expectedCaseRevision=expectedRevision,requestId=actor.characterId..':'..requestId,
        reasonCode='law.evidence.collected',evidenceType='inventory_item',evidenceRef=('%.0f'):format(receipt.itemId),
        relationship='collected',description=receipt.description,subjectCharacterId=receipt.subjectCharacterId})
    if not Law.Current(actor) then return Law.Err('session_expired','Character changed; retain the transfer ID.') end
    if not r.ok then return {ok=false,code='evidence_link_pending',message='Collection is committed; Justice link needs recovery or a reviewed new link intent.',
        details={transferRequestId=receipt.requestId,linkCode=r.code}} end
    return Law.Ok({transfer=receipt,link=r.value})
end
Law.Routes['law.evidence.collect.v1']={
    validate=function(p) return CollectValid(p,false) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.evidence.link');if not actor.ok then return actor end
        -- Inventory replays a committed receipt before requiring target presence.
        local result=Inventory('CollectLawEvidence',Internal(p,actor.value))
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed; retain the transfer ID.') end
        if not result.ok then return result end
        return LinkReceipt(p,actor.value,result.value,p.requestId..':link',p.expectedCaseRevision)
    end
}
Law.Routes['law.evidence.receipts.v1']={
    validate=function(p) return Payload(p,{department=true,caseId=true,cursor=true}) and (p.cursor==nil or Law.Token(p.cursor,128)) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.evidence.view');if not actor.ok then return actor end
        local r=Inventory('ListLawEvidenceReceipts',Internal(p,actor.value))
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
        return r
    end
}
Law.Routes['law.evidence.attach.v1']={
    validate=function(p) return Payload(p,{department=true,caseId=true,transferRequestId=true,requestId=true,expectedCaseRevision=true})
        and Law.Token(p.transferRequestId,128) and Law.Token(p.requestId,64) and Int(p.expectedCaseRevision,1,maximum) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.evidence.link');if not actor.ok then return actor end
        local receipt=Inventory('GetLawEvidenceReceipt',{actorSource=source,characterId=actor.value.characterId,sessionId=actor.value.sessionId,
            department=p.department,caseId=p.caseId:lower(),requestId=p.transferRequestId})
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
        if not receipt.ok then return receipt end
        return LinkReceipt(p,actor.value,receipt.value,p.requestId,p.expectedCaseRevision)
    end
}
Law.Routes['law.evidence.list.v1']={
    validate=function(p) return Payload(p,{department=true,caseId=true,cursor=true}) and (p.cursor==nil or Law.Uuid(p.cursor)) end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.evidence.view');if not actor.ok then return actor end
        local r=Law.Call('feather-justice','ListCaseEvidence',{actorSource=source,caseId=p.caseId,cursor=p.cursor,limit=25})
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed.') end
        return r
    end
}
Law.Routes['law.evidence.disposition.v1']={
    validate=function(p) return Payload(p,{department=true,caseId=true,recordId=true,expectedRevision=true,disposition=true,requestId=true})
        and Law.Uuid(p.recordId) and Int(p.expectedRevision,1,maximum) and Law.Token(p.requestId,64)
        and ({returned=true,destroyed=true,forfeited=true})[p.disposition or '']==true end,
    handler=function(p,source,context)
        local actor=CaseAccess(p,source,context,'justice.evidence.dispose');if not actor.ok then return actor end
        local r=Law.Call('feather-justice','RecordEvidenceDisposition',{actorSource=source,caseId=p.caseId,recordId=p.recordId,
            expectedRevision=p.expectedRevision,requestId=actor.value.characterId..':'..p.requestId,
            reasonCode='law.evidence.disposition',disposition=p.disposition})
        if not Law.Current(actor.value) then return Law.Err('session_expired','Character changed; retain the request ID.') end
        return r
    end
}
Law.Routes['law.evidence.lockers.v1']={
    validate=function(p) return Law.Fields(p,{department=true}) and Law.Token(p.department,48) end,
    handler=function(p,source,context)
        local actor=Law.Access(source,context,p.department,'justice.evidence.view');if not actor.ok then return actor end
        local items={}
        for key,c in pairs(LawConfig.Evidence.Lockers) do if c.department==p.department then items[#items+1]={key=key,label=c.label} end end
        table.sort(items,function(a,b) return a.key<b.key end)
        return Law.Ok({items=items})
    end
}
RegisterCommand('LawSetupEvidenceLockers',function(source)
    if source~=0 or not Law.Ready() or not Law.ValidateEvidenceConfig() then return end
    for key in pairs(LawConfig.Evidence.Lockers) do
        setup[key]=true
        local r=Inventory('SetupLawEvidenceLocker',{lockerKey=key})
        setup[key]=nil
        print(('[LawSetupEvidenceLockers] locker=%s result=%s'):format(key,r.ok and 'confirmed' or tostring(r.code)))
    end
end,true)
RegisterCommand('LawEvidenceStatus',function(source)
    if source~=0 then return end
    local inventory=Inventory('GetLawEvidenceCapabilities')
    local count=0;for _ in pairs(LawConfig.Evidence.Lockers) do count=count+1 end
    print(('[LawEvidenceStatus] law=%s inventory=%s justiceEvidenceGuard=%s configuredLockers=%d'):format(
        tostring(Law.Ready()),inventory.ok and tostring(inventory.value.state) or tostring(inventory.code),
        tostring(ProviderReady()),count))
end,true)
