-- Execute the real Inventory export against a transactional model. Physics,
-- guards and database I/O are controlled; rollback restores all persisted rows.
local checks,api,caller=0,{},'bcc-law'
local function copy(v) if type(v)~='table' then return v end;local r={};for k,c in pairs(v) do r[k]=copy(c) end;return r end
local function check(label,v) checks=checks+1;assert(v,label) end
local function uuid(n) return ('9f37d250-3b6a-4c19-8e72-%012x'):format(n) end
local function encode(v)
    if type(v)~='table' then return type(v)..':'..tostring(v) end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local parts={};for _,k in ipairs(keys) do parts[#parts+1]=encode(k)..'='..encode(v[k]) end;return '{'..table.concat(parts,';')..'}'
end
local documents={}
local env=setmetatable({},{__index=_G})
env.json={encode=function(v) local s=encode(v);documents[s]=copy(v);return s end,decode=function(s) assert(documents[s],'invalid document');return copy(documents[s]) end}
env.Result={Ok=function(v) return {ok=true,value=v} end,Err=function(c,m) return {ok=false,error={code=c,message=m}} end}
local function Err(c) return env.Result.Err(c,c) end
env.CreateThread=function() end;env.Wait=function() end
env.GetInvokingResource=function() return caller end
env.GetResourceState=function() return 'started' end
env.InventoryReadiness={state='ready'}
local actor={source=5,characterId=uuid(5),sessionId=uuid(15),epoch=1}
local target={source=7,characterId=uuid(7),sessionId=uuid(17),epoch=1}
local allowed,present,guard,late,authCalls=true,true,true,nil,0
local lockerConfig={department='new_hanover',label='Evidence',maxItems=2,maxWeight=10}
env.exports=setmetatable({['bcc-law']={AuthorizeEvidenceOperation=function(_,op)
    authCalls=authCalls+1
    if late then late(op,authCalls) end
    if not allowed then return {ok=false,code='authorization_denied'} end
    if op=='setup' then return {ok=true,value={locker=copy(lockerConfig)}} end
    if op=='collect' and not present then return {ok=false,code='subject_offline'} end
    return {ok=true,value={actor=copy(actor),target=copy(target)}}
end}},{__call=function(_,name,fn) api[name]=fn end})
local db,moves
local function reset()
    db={receipts={},lockers={},inventories={[10]={id=10,character_id=target.characterId,location='character',is_public=0}},
        items={[20]={id=20,inventoryId=10,revision=3,definition={name='test_item',weight=2},metadata={serialNumber='original'}}},nextId=100}
    moves=0;allowed,present,guard,late=true,true,true,nil;authCalls=0
end
reset()
local function query(sql,p)
    if sql:find('INSERT IGNORE INTO inventory_law_evidence_lockers',1,true) then
        if not db.lockers[p[1]] then db.lockers[p[1]]={locker_key=p[1],inventory_id=0,department_key=p[2],max_items=p[3],max_weight=p[4]} end;return {}
    elseif sql:find('SELECT * FROM inventory_law_evidence_lockers',1,true) then return db.lockers[p[1]] and {copy(db.lockers[p[1]])} or {}
    elseif sql:find('INSERT INTO inventory (',1,true) then
        db.nextId=db.nextId+1;db.inventories[db.nextId]={id=db.nextId,location='law_evidence',is_public=0};return {{id=db.nextId}}
    elseif sql:find('UPDATE inventory_law_evidence_lockers',1,true) then db.lockers[p[2]].inventory_id=p[1];return {}
    elseif sql:find('INSERT IGNORE INTO inventory_law_evidence_receipts',1,true) then
        if not db.receipts[p[1]] then db.receipts[p[1]]={request_id=p[1],actor_character_id=p[2],department_key=p[3],case_id=p[4],fingerprint=p[5]} end;return {}
    elseif sql:find('SELECT * FROM inventory_law_evidence_receipts',1,true) then return db.receipts[p[1]] and {copy(db.receipts[p[1]])} or {}
    elseif sql:find('SELECT id FROM inventory WHERE character_id',1,true) then return {{id=10}}
    elseif sql:find('SELECT id,location,is_public,owner_character_id,character_id',1,true) then return {copy(db.inventories[p[1]]),copy(db.inventories[p[2]])}
    elseif sql:find('SELECT ii.id,ii.slot_index,i.weight',1,true) then
        local rows={};for _,item in pairs(db.items) do if item.inventoryId==p[1] then rows[#rows+1]={id=item.id,slot_index=item.slot,weight=item.definition.weight} end end;return rows
    elseif sql:find('UPDATE inventory_law_evidence_receipts',1,true) then db.receipts[p[2]].result_json=p[1];return {}
    elseif sql:find('SELECT request_id,result_json,created_at',1,true) then
        local rows={};for id,row in pairs(db.receipts) do if row.actor_character_id==p[1] and row.department_key==p[2] and row.case_id==p[3] and id>p[4] then rows[#rows+1]=copy(row) end end
        table.sort(rows,function(a,b) return a.request_id<b.request_id end);return rows
    end
    error('Unhandled SQL: '..sql)
end
env.DB={exec=function() end,query=query}
env.TransactionAPI={Transaction=function(_,callback)
    local original,moved=copy(db),0
    local tx={query=query}
    function tx:GetItemForUpdate(id) return db.items[id] and env.Result.Ok(copy(db.items[id])) or Err('not_found') end
    function tx:MoveInstance(id,destination,slot)
        if not guard then return Err('guard_denied') end
        db.items[id].inventoryId=destination;db.items[id].slot=slot;db.items[id].revision=db.items[id].revision+1;moved=moved+1
        return env.Result.Ok(true)
    end
    local ok,r=pcall(callback,tx)
    if not ok or not r.ok then db=original;return ok and r or Err('transaction_failed') end
    moves=moves+moved;return r
end}
assert(loadfile('../../[feather]/feather-inventory/server/services/law_evidence.lua','t',env))()
env.LawEvidenceAPI.Start()
local function setup() return api.SetupLawEvidenceLocker({lockerKey='valentine'}) end
local function request() return {requestId=actor.characterId..':collect-1',characterId=actor.characterId,sessionId=actor.sessionId,actorSource=5,
    department='new_hanover',caseId=uuid(30),warrantId=uuid(80),targetSource=7,itemId=20,itemRevision=3,lockerKey='valentine',expectedCaseRevision=1,description='Description'} end
local function code(r) return not r.ok and r.error.code end
local r=setup();check('locker explicitly created',r.ok and r.value.inventoryId==101)
check('setup reuses existing locker',setup().value.inventoryId==101 and db.nextId==101)
lockerConfig.maxItems=3;check('changed persistent limits rejected',code(setup())=='locker_conflict');lockerConfig.maxItems=2
caller='foreign';check('foreign collection rejected',code(api.CollectLawEvidence(request()))=='authorization_denied');caller='bcc-law'
allowed=false;check('no actor authority means no transfer',not api.CollectLawEvidence(request()).ok and moves==0);allowed=true
present=false;check('offline target blocks first transfer',not api.CollectLawEvidence(request()).ok and db.receipts[request().requestId]==nil);present=true
local p=request();p.itemRevision=2;check('stale revision rolls back receipt',code(api.CollectLawEvidence(p))=='revision_conflict' and db.receipts[p.requestId]==nil)
db.items[20].inventoryId=99;check('changed ownership rejected',code(api.CollectLawEvidence(request()))=='revision_conflict');db.items[20].inventoryId=10
guard=false;check('weapon/move guard veto rolls back',code(api.CollectLawEvidence(request()))=='guard_denied' and db.items[20].inventoryId==10 and moves==0);guard=true
db.items[20].definition.type='item_weapon'
check('weapon collection fails without owning movement guard',code(api.CollectLawEvidence(request()))=='weapons_unavailable')
env.GuardsAPI={HasRegisteredMoveGuard=function() return true end}
check('ready weapon guard allows ordinary guarded path',api.CollectLawEvidence(request()).ok and moves==1)
-- Roll the fixture back to an uncollected ordinary item for the recovery cases.
reset();setup()
r=api.CollectLawEvidence(request());check('collection commits one move and receipt',r.ok and moves==1 and db.receipts[p.requestId].result_json~=nil)
check('instance identity and metadata preserved',db.items[20].id==20 and db.items[20].revision==4 and db.items[20].metadata.serialNumber=='original')
check('receipt preserves original subject and inventories',r.value.subjectCharacterId==target.characterId and r.value.fromInventoryId==10 and r.value.toInventoryId==101)
present=false;check('historical replay works offline',api.CollectLawEvidence(request()).ok and moves==1);present=true
local duplicate=request();duplicate.requestId=actor.characterId..':different-intent'
check('new intent cannot recollect already moved instance',code(api.CollectLawEvidence(duplicate))=='revision_conflict' and moves==1)
p=request();p.description='Changed';check('changed intent conflicts before movement',code(api.CollectLawEvidence(p))=='idempotency_conflict' and moves==1)
local receiptRequest={requestId=request().requestId,actorSource=5,characterId=actor.characterId,sessionId=actor.sessionId,department='new_hanover',caseId=uuid(30)}
check('read-only receipt recovery',api.GetLawEvidenceReceipt(receiptRequest).value.itemId==20)
receiptRequest.characterId=uuid(55);check('another character cannot recover receipt',code(api.GetLawEvidenceReceipt(receiptRequest))=='not_found');receiptRequest.characterId=actor.characterId
check('history lists committed transfers',#api.ListLawEvidenceReceipts(receiptRequest).value.items==1)
-- Simulated restart discards exports and local state, retaining persisted rows.
assert(loadfile('../../[feather]/feather-inventory/server/services/law_evidence.lua','t',env))();env.LawEvidenceAPI.Start()
present=false;check('restart replay does not move again',api.CollectLawEvidence(request()).ok and moves==1);present=true
reset();setup();local old=copy(db.items[20]);authCalls=0
late=function(op,n) if op=='collect' and n==4 then present=false end end
check('authority loss after move rolls back item and receipt',not api.CollectLawEvidence(request()).ok and db.items[20].inventoryId==old.inventoryId and db.receipts[request().requestId]==nil and moves==0)
late=nil;present=true
authCalls=0;late=function(op,n) if op=='collect' and n==3 then target.sessionId=uuid(999) end end
check('target session reuse before move rejects collection',not api.CollectLawEvidence(request()).ok and moves==0)
late=nil;target.sessionId=uuid(17)
db.inventories[101].is_public=1
check('locker visibility change prevents collection',code(api.CollectLawEvidence(request()))=='locker_unavailable' and moves==0)
db.inventories[101].is_public=0
db.items[21]={id=21,inventoryId=101,revision=0,slot=1,definition={weight=9}}
check('weight limit checked under locks',code(api.CollectLawEvidence(request()))=='capacity_exceeded' and moves==0)
db.items[21].definition.weight=1;db.items[22]={id=22,inventoryId=101,revision=0,slot=2,definition={weight=1}}
check('slot capacity prevents overfill',code(api.CollectLawEvidence(request()))=='capacity_exceeded' and moves==0)
db.items[22]=nil;db.items[21].slot=2
r=api.CollectLawEvidence(request());check('free slot holes reused',r.ok and db.items[20].slot==1)
env.InventoryReadiness.state='failed';check('capabilities stop advertising ready on Inventory failure',api.GetLawEvidenceCapabilities().value.state~='ready');check('Inventory failure blocks operations',code(api.CollectLawEvidence(request()))=='not_ready')
print(('PASS Inventory evidence collection: %d checks (transaction model; no live DB acceptance)'):format(checks))
