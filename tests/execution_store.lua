local checks,migration,markers,deliveries=0,nil,{},{}
local function check(label,v) checks=checks+1;assert(v,label) end
local env=setmetatable({},{__index=_G})
env.CreateThread=function() end
env.DB={value=function(sql,...)
    if sql:find('SHA2',1,true) then return 'reviewed-checksum' end
    if sql:find('schema_migrations',1,true) then return migration end
    local character,sentence=...
    for _,v in pairs(deliveries) do if v.character_id==character and v.sentence_id==sentence and (v.state=='pending' or v.state=='review_required') then return v.request_id end end
end,exec=function(sql,...)
    local a,b,c,d,e=...
    if sql:find('INSERT IGNORE INTO bcc_law_schema_migrations',1,true) then migration=a
    elseif sql:find('INSERT INTO bcc_law_placements',1,true) then markers[a]={character_id=a,sentence_id=b,facility_key=c}
    elseif sql:find('DELETE FROM bcc_law_placements',1,true) then markers[a]=nil
    elseif sql:find('INSERT IGNORE INTO bcc_law_service_deliveries',1,true) then deliveries[a]=deliveries[a] or {request_id=a,character_id=b,sentence_id=c,expected_revision=d,completed_units=e,state='pending'}
    elseif sql:find('UPDATE bcc_law_service_deliveries',1,true) then deliveries[c].state=a;deliveries[c].last_code=b end
end,one=function(_,id) return markers[id] end,query=function()
    local rows={};for _,r in pairs(deliveries) do if r.state=='pending' then rows[#rows+1]=r end end;return rows
end}
env.Law={}
assert(loadfile('server/execution_store.lua','t',env))()
local S=env.Law.ExecutionStore
S.Start();check('first execution migration ready',S.state=='ready' and migration=='reviewed-checksum')
S.Start();check('migration rerun idempotent',S.state=='ready')
migration='changed';check('applied migration checksum change fails closed',not pcall(S.Start));migration='reviewed-checksum'
S.Place('character','sentence','valentine');check('placement persists independent of transport source',S.Get('character').sentence_id=='sentence')
local sentence={recordId='sentence',revision=4,completedUnits=1}
local id=S.Queue('character',sentence);S.Queue('character',sentence)
check('service intent stable across retries',id=='law:service:sentence:2' and #S.Pending()==1)
sentence.revision=7;S.Queue('character',sentence)
check('changed revision cannot overwrite reserved delivery',S.Pending()[1].expected_revision==4)
check('pending delivery blocks new work unit',S.HasOutstanding('character','sentence'))
S.Mark(id,'confirmed',nil);check('confirmed delivery leaves retry queue',#S.Pending()==0 and not S.HasOutstanding('character','sentence'))
S.Clear('character');check('placement cleared after physical release',S.Get('character')==nil)
print(('PASS Law execution persistence: %d checks (DB model; no live migration)'):format(checks))
