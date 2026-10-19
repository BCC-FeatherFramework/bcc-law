Law.ExecutionStore={state='starting'}
local S=Law.ExecutionStore
local definitions={
    [[CREATE TABLE IF NOT EXISTS bcc_law_placements (
        character_id CHAR(36) NOT NULL PRIMARY KEY, sentence_id CHAR(36) NOT NULL,
        facility_key VARCHAR(64) NOT NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]],
    [[CREATE TABLE IF NOT EXISTS bcc_law_service_deliveries (
        request_id VARCHAR(128) NOT NULL PRIMARY KEY, character_id CHAR(36) NOT NULL,
        sentence_id CHAR(36) NOT NULL, expected_revision BIGINT NOT NULL, completed_units INT NOT NULL,
        state VARCHAR(24) NOT NULL DEFAULT 'pending', last_code VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_law_service_retry (state,request_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]],
    [[CREATE TABLE IF NOT EXISTS bcc_law_armory_claims (
        request_id VARCHAR(128) NOT NULL PRIMARY KEY, character_id CHAR(36) NOT NULL,
        station_key VARCHAR(64) NOT NULL,item_key VARCHAR(64) NOT NULL,period_key CHAR(10) NOT NULL,
        spec_json LONGTEXT NOT NULL,result_json LONGTEXT NULL,
        UNIQUE KEY uq_law_armory_quota (character_id,station_key,item_key,period_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]]
}
function S.Start()
    S.state='starting'
    DB.exec([[CREATE TABLE IF NOT EXISTS bcc_law_schema_migrations (
        version INT NOT NULL PRIMARY KEY, checksum CHAR(64) NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]])
    local checksum=DB.value('SELECT SHA2(?,256)',table.concat(definitions,'\n'))
    local previous=DB.value('SELECT checksum FROM bcc_law_schema_migrations WHERE version=1')
    if previous and previous~=checksum then error('Law execution migration checksum mismatch') end
    for _,sql in ipairs(definitions) do DB.exec(sql) end
    DB.exec('INSERT IGNORE INTO bcc_law_schema_migrations (version,checksum) VALUES (1,?)',checksum)
    S.state='ready'
end
function S.ArmoryGet(requestId) return DB.one('SELECT * FROM bcc_law_armory_claims WHERE request_id=?',requestId) end
function S.ArmoryReserve(actor,requestId,stationKey,itemKey,spec)
    local result
    local committed=DB.transaction(function(tx)
        local row=tx.one('SELECT * FROM bcc_law_armory_claims WHERE request_id=? FOR UPDATE',requestId)
        if row then result=row;return true end
        local period=tx.value("SELECT DATE_FORMAT(UTC_TIMESTAMP(),'%Y-%m-%d')")
        tx.exec([[INSERT IGNORE INTO bcc_law_armory_claims
            (request_id,character_id,station_key,item_key,period_key,spec_json) VALUES (?,?,?,?,?,?)]],
            requestId,actor.characterId,stationKey,itemKey,period,json.encode(spec))
        result=tx.one('SELECT * FROM bcc_law_armory_claims WHERE request_id=? FOR UPDATE',requestId)
        return result~=nil
    end)
    return committed and result or nil
end
function S.ArmoryConfirm(requestId,result)
    DB.exec('UPDATE bcc_law_armory_claims SET result_json=? WHERE request_id=?',json.encode(result),requestId)
end
function S.ArmoryClaims(characterId,stationKey,cursor)
    return DB.query([[SELECT request_id,item_key,period_key,result_json IS NULL AS pending FROM bcc_law_armory_claims
        WHERE character_id=? AND station_key=? AND request_id>? ORDER BY request_id LIMIT 26]],characterId,stationKey,cursor or '')
end
function S.Get(characterId) return DB.one('SELECT * FROM bcc_law_placements WHERE character_id=?',characterId) end
function S.Place(characterId,sentenceId,facilityKey)
    DB.exec([[INSERT INTO bcc_law_placements (character_id,sentence_id,facility_key) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE sentence_id=VALUES(sentence_id),facility_key=VALUES(facility_key)]],characterId,sentenceId,facilityKey)
end
function S.Clear(characterId) DB.exec('DELETE FROM bcc_law_placements WHERE character_id=?',characterId) end
function S.Queue(characterId,sentence)
    local units=sentence.completedUnits+1
    local requestId='law:service:'..sentence.recordId..':'..units
    DB.exec([[INSERT IGNORE INTO bcc_law_service_deliveries
        (request_id,character_id,sentence_id,expected_revision,completed_units) VALUES (?,?,?,?,?)]],
        requestId,characterId,sentence.recordId,sentence.revision,units)
    return requestId
end
function S.Pending() return DB.query('SELECT * FROM bcc_law_service_deliveries WHERE state=? ORDER BY request_id LIMIT 25','pending') end
function S.HasOutstanding(characterId,sentenceId)
    return DB.value([[SELECT request_id FROM bcc_law_service_deliveries WHERE character_id=? AND sentence_id=?
        AND state IN ('pending','review_required') LIMIT 1]],characterId,sentenceId)~=nil
end
function S.Mark(requestId,state,code)
    DB.exec('UPDATE bcc_law_service_deliveries SET state=?,last_code=? WHERE request_id=?',state,code,requestId)
end
CreateThread(function()
    while true do
        if DB.awaitReady(30000) then
            local ok=pcall(S.Start)
            if not ok then S.state='failed' end
            return
        end
        Wait(1000)
    end
end)
