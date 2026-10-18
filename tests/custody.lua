return function(t)
    local uuid,check=t.uuid,t.check
    local core,justice=exports['feather-core'],exports['feather-justice']
    local saved={session=core.GetSessionContext,current=core.IsSessionCurrent,warrant=justice.GetWarrant,custody=justice.GetCustody,operation=justice.FindOperation}
    local players,positions,buckets,pedAvailable,targetCurrent,targetIdentity=true,{}, {},true,true,uuid(44)
    local f=LawConfig.Custody.Facilities.valentine
    positions[5]={x=f.x,y=f.y,z=f.z};positions[7]={x=f.x+1,y=f.y,z=f.z}
    buckets[5],buckets[7]=0,0
    GetPlayers=function() return players and {'5','7'} or {'5'} end
    GetPlayerPed=function(source) return pedAvailable and source or 0 end
    GetEntityCoords=function(ped) return positions[ped] end
    GetPlayerRoutingBucket=function(source) return buckets[source] end
    core.GetSessionContext=function(_,source)
        if source==7 then return {ok=true,value={characterId=targetIdentity,sessionId=uuid(67)}} end
        return saved.session(core,source)
    end
    core.IsSessionCurrent=function(_,source,...)
        if source==7 then return targetCurrent end
        return saved.current(core,source,...)
    end
    local childCase=uuid(10)
    justice.GetWarrant=function() return {ok=true,value={recordId=uuid(90),caseId=childCase,jurisdictionId=uuid(3),subjectCharacterId=uuid(44)}} end
    justice.GetCustody=function() return {ok=true,value={recordId=uuid(91),caseId=childCase,jurisdictionId=uuid(3),subjectCharacterId=uuid(44),document={facilityKey='valentine'}}} end
    justice.FindOperation=function(_,p) return {ok=true,value={recordId=uuid(91),kind='custody',caseId=uuid(10),jurisdictionId=uuid(3),requestId=p.requestId}} end
    local function route(name) return t.registered['law.'..name..'.v1'] end
    local function call(name,p) return route(name).handler(p,5,t.context) end
    local function payload() return {department='new_hanover',caseId=uuid(10),warrantId=uuid(90),expectedWarrantRevision=2,facilityKey='valentine',requestId='booking-test'} end
    check('facilities return configured keys',call('custody.facilities',{department='new_hanover'}).value.items[1].key=='valentine')
    local p=payload()
    check('nearby UUID subject booking dispatch',call('custody.reserve',p).ok and t.dispatches[#t.dispatches].operation=='ReserveCustodyBooking')
    check('booking request actor is authenticated',t.dispatches[#t.dispatches].request.actorSource==5 and t.dispatches[#t.dispatches].request.requestId==uuid(1)..':booking-test')
    p.subjectCharacterId=uuid(45);check('booking target cannot be injected',call('custody.reserve',p).code=='invalid_input');p.subjectCharacterId=nil
    p.targetSource=7;check('booking target source cannot be injected',call('custody.reserve',p).code=='invalid_input');p.targetSource=nil
    players=false;check('offline target cannot be booked',call('custody.reserve',p).code=='subject_offline');players=true
    buckets[7]=8;check('cross-instance booking refused',call('custody.reserve',p).code=='interaction_unavailable');buckets[7]=0
    positions[7]={x=f.x+20,y=f.y,z=f.z};check('remote target booking refused',call('custody.reserve',p).code=='booking_location_required')
    positions[5]={x=0,y=0,z=0};positions[7]={x=1,y=0,z=0};check('nearby players outside facility refused',call('custody.reserve',p).code=='booking_location_required')
    positions[5]={x=f.x,y=f.y,z=f.z};positions[7]={x=f.x+1,y=f.y,z=f.z}
    pedAvailable=false;check('missing entity fails closed',call('custody.reserve',p).code=='interaction_unavailable');pedAvailable=true
    positions[7].x=0/0;check('nonfinite entity position fails closed',call('custody.reserve',p).code=='interaction_unavailable');positions[7].x=f.x+1
    targetCurrent=false;check('stale target session refused',call('custody.reserve',p).code=='subject_offline');targetCurrent=true
    targetIdentity=uuid(45);check('source reused by different UUID refused',call('custody.reserve',p).code=='subject_offline');targetIdentity=uuid(44)
    p.facilityKey='unknown';check('unknown facility refused',call('custody.reserve',p).code=='facility_unavailable');p.facilityKey='valentine'
    childCase=uuid(99);check('cross-case warrant refused',call('custody.reserve',p).code=='not_found');childCase=uuid(10)
    local change={department='new_hanover',caseId=uuid(10),recordId=uuid(91),expectedRevision=1,requestId='confirm-test'}
    check('arrival confirmation uses typed Justice API',call('custody.confirm',change).ok and t.dispatches[#t.dispatches].operation=='ConfirmCustodyBooking')
    players=false;check('confirmation requires present target',call('custody.confirm',change).code=='subject_offline')
    check('authorized legal release can happen while subject offline',call('custody.release',change).ok and t.dispatches[#t.dispatches].operation=='ReleaseCustody')
    local recovered=call('operations.get',{department='new_hanover',requestId='booking-test'})
    check('receipt recovery does not require physical presence',recovered.ok and recovered.value.requestId==uuid(1)..':booking-test')
    check('receipt identity cannot be injected',call('operations.get',{department='new_hanover',requestId='booking-test',actorCharacterId=uuid(45)}).code=='invalid_input')
    core.GetSessionContext,core.IsSessionCurrent=saved.session,saved.current
    justice.GetWarrant,justice.GetCustody,justice.FindOperation=saved.warrant,saved.custody,saved.operation
end
