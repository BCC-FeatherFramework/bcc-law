return function(t)
    local uuid,check=t.uuid,t.check
    Law.SetState('ready','legal-tests')
    local function route(name) return assert(t.registered['law.'..name..'.v1']) end
    local function dispatch(name,payload) return route(name).handler(payload,5,t.context) end
    local function latest() return t.dispatches[#t.dispatches] end
    local function mutation(extra)
        local p={department='new_hanover',caseId=uuid(10),requestId='same-request'}
        for k,v in pairs(extra or {}) do p[k]=v end;return p
    end
    local proposed=mutation({expectedCaseRevision=1,subjectCharacterId=uuid(20),statuteId=uuid(21),count=2})
    check('charge payload valid',route('charges.propose').options.validatePayload(proposed))
    check('charge route dispatch',dispatch('charges.propose',proposed).ok)
    check('charge operation typed',latest().operation=='ProposeCharge')
    check('charge actor from session',latest().request.actorSource==5 and latest().request.requestId==uuid(1)..':same-request')
    check('charge parent and statute preserved',latest().request.caseId==uuid(10) and latest().request.statuteId==uuid(21))
    proposed.issuedByCharacterId=uuid(99)
    check('charge issuer injection rejected',dispatch('charges.propose',proposed).code=='invalid_input');proposed.issuedByCharacterId=nil
    proposed.count=101
    check('charge count bound at Law edge',dispatch('charges.propose',proposed).code=='invalid_input');proposed.count=2
    local before=#t.dispatches
    t.caseJurisdiction(uuid(99))
    check('cross-department charge rejected',dispatch('charges.propose',proposed).code=='not_found' and #t.dispatches==before)
    t.caseJurisdiction(uuid(3))
    t.policy(false);check('legal route policy denial',dispatch('charges.propose',proposed).code=='authorization_denied');t.policy(true)
    local draft=mutation({expectedCaseRevision=1,subjectCharacterId=uuid(20),basisSummary='Legal basis',validForSeconds=600})
    check('draft route dispatch',dispatch('warrants.draft',draft).ok and latest().operation=='CreateWarrantDraft')
    check('warrant type chosen server-side',latest().request.warrantType=='arrest')
    draft.warrantType='search';check('client warrant type cannot override',dispatch('warrants.draft',draft).code=='invalid_input');draft.warrantType=nil
    draft.expiresAt=123;check('client cannot inject deadline',dispatch('warrants.draft',draft).code=='invalid_input');draft.expiresAt=nil
    draft.validForSeconds=1;check('warrant minimum lifetime',dispatch('warrants.draft',draft).code=='invalid_input');draft.validForSeconds=600
    for _,spec in ipairs({{'charges.list','ListCharges'},{'warrants.list','ListCaseWarrants'}}) do
        check(spec[1]..' bounded dispatch',dispatch(spec[1],{department='new_hanover',caseId=uuid(10)}).ok
            and latest().operation==spec[2] and latest().request.limit==25 and latest().request.jurisdictionId==uuid(3))
    end
    check('active warrants dispatch',dispatch('warrants.active',{department='new_hanover',subjectCharacterId=uuid(20)}).ok)
    check('active list filters derived',latest().operation=='ListActiveWarrants' and latest().request.jurisdictionId==uuid(3)
        and latest().request.subjectCharacterId==uuid(20))
    check('active list jurisdiction injection refused',dispatch('warrants.active',{department='new_hanover',jurisdictionId=uuid(99)}).code=='invalid_input')
    for _,spec in ipairs({{'charges.file','FileCharge'},{'charges.dispose','DisposeCharge'},
        {'warrants.issue','IssueWarrant'},{'warrants.serve','ServeWarrant'},
        {'warrants.recall','RecallWarrant'},{'warrants.quash','QuashWarrant'}}) do
        local p=mutation({recordId=uuid(30),expectedRevision=2})
        if spec[2]=='DisposeCharge' then p.status='dismissed' end
        check(spec[1]..' transition dispatch',dispatch(spec[1],p).ok and latest().operation==spec[2])
        check(spec[1]..' request context bound',latest().request.actorSource==5
            and latest().request.requestId==uuid(1)..':same-request' and latest().request.expectedRevision==2)
        before=#t.dispatches;t.childCase(uuid(99))
        check(spec[1]..' foreign parent denied',dispatch(spec[1],p).code=='not_found' and #t.dispatches==before)
        t.childCase(uuid(10))
    end
    check('conviction unavailable at Law edge',dispatch('charges.dispose',mutation({recordId=uuid(30),expectedRevision=2,status='convicted'})).code=='invalid_input')
    t.onCall(function(step) if step=='child' then t.current(false) end end)
    check('session changes during child read refused',dispatch('warrants.issue',mutation({recordId=uuid(30),expectedRevision=2})).code=='session_expired')
    t.onCall(nil);t.current(true)
    t.onCall(function(step) if step=='legal' then t.current(false) end end)
    check('late legal mutation reply fenced',dispatch('warrants.draft',draft).code=='session_expired')
    t.onCall(nil);t.current(true)
    local party=mutation({expectedCaseRevision=1,subjectCharacterId=uuid(20),role='investigating_officer'})
    check('party route validates and dispatches',dispatch('parties.add',party).ok and latest().operation=='AddCaseParty')
    check('party issuer derived from session',latest().request.actorSource==5 and latest().request.requestId==uuid(1)..':same-request')
    party.role='superuser';check('unknown participant role rejected',dispatch('parties.add',party).code=='invalid_input');party.role='witness'
    party.jurisdictionId=uuid(99);check('party jurisdiction injection rejected',dispatch('parties.add',party).code=='invalid_input');party.jurisdictionId=nil
    check('participant list route typed',dispatch('parties.list',{department='new_hanover',caseId=uuid(10)}).ok and latest().operation=='ListCaseParties')
    check('participant remove route typed',dispatch('parties.remove',mutation({recordId=uuid(20),expectedRevision=1})).ok and latest().operation=='RemoveCaseParty')
    check('case summary route maps record identity',dispatch('cases.update',mutation({expectedRevision=1,summary='Updated'})).ok
        and latest().operation=='UpdateCaseSummary' and latest().request.recordId==uuid(10) and latest().request.caseId==nil)
    check('case transition rejects invented state',dispatch('cases.transition',mutation({expectedRevision=1,status='convicted'})).code=='invalid_input')
    check('statute page jurisdiction is derived',dispatch('statutes.list',{department='new_hanover'}).ok and latest().operation=='ListStatutes' and latest().request.jurisdictionId==uuid(3))

    local citation=mutation({expectedCaseRevision=1,subjectCharacterId=uuid(44),amount=2500,dueInSeconds=86400,basisSummary='Citation basis'})
    check('citation issue dispatch',dispatch('citations.issue',citation).ok and latest().operation=='RequestCitation')
    check('citation UUID debtor preserved',latest().request.subjectCharacterId==uuid(44) and latest().request.actorSource==5)
    citation.subjectCharacterId=44;check('numeric citation debtor refused',dispatch('citations.issue',citation).code=='invalid_input');citation.subjectCharacterId=uuid(44)
    citation.currency='gold';check('citation currency cannot be chosen by client',dispatch('citations.issue',citation).code=='invalid_input');citation.currency=nil
    citation.creditorId=uuid(99);check('citation creditor cannot be chosen by client',dispatch('citations.issue',citation).code=='invalid_input');citation.creditorId=nil
    check('citation list bounded',dispatch('citations.list',{department='new_hanover',caseId=uuid(10)}).ok and latest().operation=='ListCaseCitations' and latest().request.limit==25)
    check('citation cancellation typed',dispatch('citations.cancel',mutation({recordId=uuid(50),expectedRevision=2})).ok and latest().operation=='CancelCitation')
    t.childCase(uuid(99));check('citation cancellation cross-case refused',dispatch('citations.cancel',mutation({recordId=uuid(50),expectedRevision=2})).code=='not_found');t.childCase(uuid(10))

end
