-- BCC Law persistence: only Law's own tables (Law master plan §6). Justice tables
-- are never read here. Migrations are versioned and checksummed; DDL is rerunnable.
Law.Store={state='starting'}
local S=Law.Store
-- Version 1 must stay byte-identical: its checksum is recorded on installed servers.
local version1={
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
-- Version 2: operation journal (master plan §6 `bcc_law_operations`) and Law-owned
-- community-service progress; Justice completes the sentence at the last unit.
local version2={
    [[CREATE TABLE IF NOT EXISTS bcc_law_operations (
        journal_key VARCHAR(240) NOT NULL PRIMARY KEY, character_id CHAR(36) NOT NULL,
        route VARCHAR(64) NOT NULL, payload_hash CHAR(64) NOT NULL, result_json TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_law_operations_age (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]],
    [[CREATE TABLE IF NOT EXISTS bcc_law_service_progress (
        sentence_id CHAR(36) NOT NULL PRIMARY KEY, character_id CHAR(36) NOT NULL,
        units INT NOT NULL, completed_units INT NOT NULL DEFAULT 0,
        state VARCHAR(16) NOT NULL DEFAULT 'active', last_code VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        KEY ix_law_service_state (state, sentence_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]],
    [[CREATE TABLE IF NOT EXISTS bcc_law_service_tasks (
        task_id VARCHAR(100) NOT NULL PRIMARY KEY, sentence_id CHAR(36) NOT NULL, character_id CHAR(36) NOT NULL,
        unit INT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_law_service_tasks (sentence_id, unit)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]]
}
-- Version 3: physical evidence dispositions queued after Justice recorded them.
local version3={
    [[CREATE TABLE IF NOT EXISTS bcc_law_evidence_dispositions (
        evidence_link_id CHAR(36) NOT NULL PRIMARY KEY, case_id CHAR(36) NOT NULL, item_id BIGINT NOT NULL,
        disposition VARCHAR(16) NOT NULL, recipient_character_id CHAR(36) NULL,
        state VARCHAR(16) NOT NULL DEFAULT 'pending', attempts INT NOT NULL DEFAULT 0, last_code VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        KEY ix_law_evidence_disposition_state (state, evidence_link_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]]
}
local migrations={{version=1,ddl=version1},{version=2,ddl=version2},{version=3,ddl=version3}}
local function Apply(migration)
    local checksum=DB.value('SELECT SHA2(?,256)',table.concat(migration.ddl,'\n'))
    local previous=DB.value('SELECT checksum FROM bcc_law_schema_migrations WHERE version=?',migration.version)
    if previous and previous~=checksum then error('Law migration '..migration.version..' checksum mismatch') end
    if previous then return end
    for _,sql in ipairs(migration.ddl) do DB.exec(sql) end
    DB.exec('INSERT IGNORE INTO bcc_law_schema_migrations (version,checksum) VALUES (?,?)',migration.version,checksum)
end
function S.Start()
    S.state='starting'
    DB.exec([[CREATE TABLE IF NOT EXISTS bcc_law_schema_migrations (
        version INT NOT NULL PRIMARY KEY, checksum CHAR(64) NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]])
    for _,migration in ipairs(migrations) do Apply(migration) end
    -- The pre-beta delivery-intent table is replaced by service progress; it is
    -- dropped only when empty, never with pending intents in it.
    local present=DB.value("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='bcc_law_service_deliveries'")
    if tonumber(present)==1 and tonumber(DB.value('SELECT COUNT(*) FROM bcc_law_service_deliveries'))==0 then
        DB.exec('DROP TABLE bcc_law_service_deliveries')
    end
    S.state='ready'
end
function S.Migrations()
    local rows=DB.query('SELECT version,checksum FROM bcc_law_schema_migrations ORDER BY version')
    local expected={}
    for _,migration in ipairs(migrations) do expected[migration.version]=DB.value('SELECT SHA2(?,256)',table.concat(migration.ddl,'\n')) end
    return rows,expected
end

-- Operation journal ------------------------------------------------------------------
function S.Journal(key,fingerprint,characterId)
    local row=DB.one('SELECT character_id, payload_hash=SHA2(?,256) AS same, result_json FROM bcc_law_operations WHERE journal_key=?',fingerprint,key)
    if not row then return nil end
    if row.character_id~=characterId or tonumber(row.same)~=1 then return 'conflict' end
    local ok,value=pcall(json.decode,row.result_json)
    return ok and value or nil
end
function S.Remember(key,fingerprint,characterId,route,result)
    DB.exec([[INSERT IGNORE INTO bcc_law_operations (journal_key,character_id,route,payload_hash,result_json)
        VALUES (?,?,?,SHA2(?,256),?)]],key,characterId,route,fingerprint,json.encode(result or {}))
end
function S.PurgeJournal(days)
    DB.exec('DELETE FROM bcc_law_operations WHERE created_at<TIMESTAMPADD(DAY,-?,CURRENT_TIMESTAMP) LIMIT 1000',days)
end

-- Armory --------------------------------------------------------------------------------
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

-- Jail placement markers ------------------------------------------------------------
function S.Get(characterId) return DB.one('SELECT * FROM bcc_law_placements WHERE character_id=?',characterId) end
function S.Place(characterId,sentenceId,facilityKey)
    DB.exec([[INSERT INTO bcc_law_placements (character_id,sentence_id,facility_key) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE sentence_id=VALUES(sentence_id),facility_key=VALUES(facility_key)]],characterId,sentenceId,facilityKey)
end
function S.Clear(characterId) DB.exec('DELETE FROM bcc_law_placements WHERE character_id=?',characterId) end

-- Community service progress ------------------------------------------------------
-- Task rows are keyed by sentence and unit number, so a unit is counted once
-- even when a completion is retried or two attempts finish together.
function S.ServiceProgress(sentenceId)
    local row=DB.one('SELECT * FROM bcc_law_service_progress WHERE sentence_id=?',sentenceId)
    if not row then return nil end
    row.units,row.completed_units=tonumber(row.units),tonumber(row.completed_units)
    return row
end
function S.CompleteUnit(characterId,sentenceId,units,unit)
    local state
    DB.transaction(function(tx)
        tx.exec([[INSERT INTO bcc_law_service_progress (sentence_id,character_id,units) VALUES (?,?,?)
            ON DUPLICATE KEY UPDATE sentence_id=sentence_id]],sentenceId,characterId,units)
        local progress=tx.one('SELECT * FROM bcc_law_service_progress WHERE sentence_id=? FOR UPDATE',sentenceId)
        if progress.character_id~=characterId or progress.state~='active' then state=progress.state;return true end
        tx.exec('INSERT IGNORE INTO bcc_law_service_tasks (task_id,sentence_id,character_id,unit) VALUES (?,?,?,?)',
            sentenceId..':'..unit,sentenceId,characterId,unit)
        local done=tonumber(tx.value('SELECT COUNT(*) FROM bcc_law_service_tasks WHERE sentence_id=?',sentenceId))
        state=done>=tonumber(progress.units) and 'completing' or 'active'
        tx.exec('UPDATE bcc_law_service_progress SET completed_units=?,state=? WHERE sentence_id=?',math.min(done,tonumber(progress.units)),state,sentenceId)
        return true
    end)
    return state
end
function S.ServiceCompleting(limit)
    return DB.query("SELECT * FROM bcc_law_service_progress WHERE state='completing' ORDER BY sentence_id LIMIT ?",limit or 25)
end
function S.ServiceMark(sentenceId,state,code)
    DB.exec('UPDATE bcc_law_service_progress SET state=?,last_code=? WHERE sentence_id=?',state,code,sentenceId)
end

-- Physical evidence dispositions ------------------------------------------------
function S.DispositionQueue(linkId,caseId,itemId,disposition,recipientId)
    DB.exec([[INSERT IGNORE INTO bcc_law_evidence_dispositions (evidence_link_id,case_id,item_id,disposition,recipient_character_id)
        VALUES (?,?,?,?,?)]],linkId,caseId,itemId,disposition,recipientId)
end
function S.Disposition(linkId) return DB.one('SELECT * FROM bcc_law_evidence_dispositions WHERE evidence_link_id=?',linkId) end
function S.DispositionsPending(limit)
    return DB.query("SELECT * FROM bcc_law_evidence_dispositions WHERE state='pending' ORDER BY updated_at,evidence_link_id LIMIT ?",limit or 25)
end
function S.DispositionsByState(state,limit)
    return DB.query('SELECT * FROM bcc_law_evidence_dispositions WHERE state=? ORDER BY updated_at DESC LIMIT ?',state,limit or 25)
end
function S.DispositionMark(linkId,state,code)
    DB.exec('UPDATE bcc_law_evidence_dispositions SET state=?,last_code=?,attempts=attempts+1 WHERE evidence_link_id=?',state,code,linkId)
end
function S.DispositionRetry(linkId)
    return tonumber(DB.exec("UPDATE bcc_law_evidence_dispositions SET state='pending',last_code=NULL WHERE evidence_link_id=? AND state='failed'",linkId)) or 0
end

CreateThread(function()
    while true do
        if DB.awaitReady(30000) then
            local ok,err=pcall(S.Start)
            if not ok then
                S.state='failed'
                print('[bcc-law] event=store.failed reason='..tostring(type(err)=='table' and err.code or err):match('^[^\n]*'):sub(1,160))
            end
            return
        end
        Wait(1000)
    end
end)
