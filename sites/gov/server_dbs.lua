-- Criminal record (DBS) checks on the government site.
--   * Police add convictions with the commands in Config.gov.dbs.commands, or a script calls the exports below.
--   * A player pays for a check on the website and gets a certificate (a snapshot of what was on record that day).
--   * An employer checks a certificate on the "verify" page with its number and the holder's surname.
-- Levels, fees, how long a check takes and which jobs may add records are in config.lua (Config.gov.dbs).
local D = Config.gov.dbs or {}
local DAY = 86400

local function cfg(key, default)
    if D[key] == nil then return default end
    return D[key]
end

local function now() return os.time() end
local function running() return Browser.govScriptOn('dbs') end

local function siteAddress()
    local c = Config.Sites and Config.Sites.gov
    return c and c.domain or 'lsgov.co.uk'
end

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_criminal_records (
        id INT AUTO_INCREMENT PRIMARY KEY,
        cid VARCHAR(64) NOT NULL,
        offence VARCHAR(160) NOT NULL,
        sentence VARCHAR(160) NOT NULL DEFAULT '',
        notes VARCHAR(400) NOT NULL DEFAULT '',
        issued_by VARCHAR(80) NOT NULL DEFAULT '',
        date INT NOT NULL,
        spent_days INT NOT NULL DEFAULT 0,
        KEY idx_cid (cid)
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_dbs_certificates (
        id INT AUTO_INCREMENT PRIMARY KEY,
        number VARCHAR(20) NOT NULL,
        cid VARCHAR(64) NOT NULL,
        name VARCHAR(80) NOT NULL,
        level VARCHAR(24) NOT NULL,
        fee INT NOT NULL DEFAULT 0,
        status VARCHAR(12) NOT NULL DEFAULT 'processing',
        applied_at INT NOT NULL,
        ready_at INT NOT NULL,
        issued_at INT NULL,
        expires_at INT NULL,
        result VARCHAR(10) NULL,
        snapshot MEDIUMTEXT NULL,
        UNIQUE KEY uq_number (number),
        KEY idx_cid (cid, id)
    )]])
end)

-- ---------------------------------------------------------------------------------------------
-- Levels
-- ---------------------------------------------------------------------------------------------

local function levelDefs()
    local list = cfg('levels', nil)
    if type(list) ~= 'table' or #list == 0 then
        list = { { id = 'basic', fee = 100, includes = 'unspent' }, { id = 'standard', fee = 200, includes = 'all' }, { id = 'enhanced', fee = 350, includes = 'notes' } }
    end
    return list
end

local function findLevel(id)
    for _, l in ipairs(levelDefs()) do if l.id == id then return l end end
    return nil
end

local function levelLabel(l)
    if l.label then return l.label end
    local key = 'gov.dbs.level.' .. l.id
    local txt = T(key)
    return txt ~= key and txt or l.id
end

local function levelDesc(l)
    if l.description then return l.description end
    local key = 'gov.dbs.level.' .. l.id .. '.desc'
    local txt = T(key)
    return txt ~= key and txt or ''
end

-- ---------------------------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------------------------

local function isSpent(row, t)
    local days = tonumber(row.spent_days) or 0
    return days > 0 and t >= (tonumber(row.date) or 0) + days * DAY
end

local function rowsFor(cid)
    return MySQL.query.await(
        'SELECT id, offence, sentence, notes, issued_by, date, spent_days FROM browser_criminal_records WHERE cid = ? ORDER BY date DESC, id DESC LIMIT ?',
        { cid, tonumber(cfg('maxRecordsShown', 30)) or 30 }) or {}
end

--- The records a certificate of this level would show today.
local function included(cid, level)
    local t = now()
    local out = {}
    for _, r in ipairs(rowsFor(cid)) do
        local spent = isSpent(r, t)
        if level.includes ~= 'unspent' or not spent then
            local entry = { offence = r.offence, sentence = r.sentence, date = tonumber(r.date), spent = spent, by = r.issued_by }
            if level.includes == 'notes' and r.notes and r.notes ~= '' then entry.notes = r.notes end
            out[#out + 1] = entry
        end
    end
    return out
end

--- Adds a conviction. data = { offence, sentence, notes, issuedBy, spentDays, date }. Returns the record id, or false plus a reason.
local function addRecord(cid, data)
    if type(cid) ~= 'string' or cid == '' then return false, 'Unknown character' end
    if type(data) ~= 'table' then return false, 'No record given' end
    local offence = tostring(data.offence or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 160)
    if offence == '' then return false, 'An offence is required' end
    local spent = tonumber(data.spentDays)
    if spent == nil then spent = tonumber(cfg('defaultSpentDays', 30)) or 0 end
    return MySQL.insert.await(
        'INSERT INTO browser_criminal_records (cid, offence, sentence, notes, issued_by, date, spent_days) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { cid, offence, tostring(data.sentence or ''):gsub('%c', ' '):sub(1, 160), tostring(data.notes or ''):gsub('%c', ' '):sub(1, 400),
          tostring(data.issuedBy or ''):gsub('%c', ' '):sub(1, 80), tonumber(data.date) or now(), math.max(0, math.floor(spent)) })
end

exports('addCriminalRecord', function(cid, data) return (addRecord(cid, data)) end)
exports('removeCriminalRecord', function(id)
    local n = MySQL.update.await('DELETE FROM browser_criminal_records WHERE id = ?', { tonumber(id) })
    return n ~= nil and n > 0
end)
exports('getCriminalRecords', function(cid)
    local out, t = {}, now()
    if type(cid) ~= 'string' then return out end
    for _, r in ipairs(rowsFor(cid)) do
        out[#out + 1] = { id = r.id, offence = r.offence, sentence = r.sentence, notes = r.notes, issuedBy = r.issued_by, date = tonumber(r.date), spent = isSpent(r, t) }
    end
    return out
end)
--- true when nothing would show on a certificate of that level (default: the first level).
exports('hasCleanRecord', function(cid, levelId)
    local level = findLevel(levelId) or levelDefs()[1]
    if type(cid) ~= 'string' then return false end
    return #included(cid, level) == 0
end)

-- ---------------------------------------------------------------------------------------------
-- Certificates
-- ---------------------------------------------------------------------------------------------

local function newNumber()
    for _ = 1, 20 do
        local n = ('DBS%09d'):format(math.random(0, 999999999))
        if not MySQL.scalar.await('SELECT 1 FROM browser_dbs_certificates WHERE number = ?', { n }) then return n end
    end
    return ('DBS%09d'):format(now() % 1000000000)
end

--- Fills in the snapshot of a certificate that is ready. Sends the "ready" email when the player is online.
local function issue(row, src)
    local level = findLevel(row.level) or levelDefs()[1]
    local recs = included(row.cid, level)
    local t = now()
    local validDays = tonumber(cfg('validDays', 30)) or 0
    local result = #recs == 0 and 'clear' or 'records'
    MySQL.update.await(
        "UPDATE browser_dbs_certificates SET status = 'issued', issued_at = ?, expires_at = ?, result = ?, snapshot = ? WHERE id = ? AND status = 'processing'",
        { t, validDays > 0 and (t + validDays * DAY) or 0, result, json.encode({ records = recs }), row.id })
    if src then
        Bridge.sendPhoneMail(src, row.cid, cfg('mailFrom', { name = 'DBS', email = 'noreply@lsgov.co.uk' }), T('gov.dbs.readySubject'),
            T('gov.dbs.readyBody', row.name, row.number, levelLabel(level), T('gov.dbs.result.' .. result), siteAddress()))
    end
end

local function finalise(cid, src)
    local due = MySQL.query.await("SELECT * FROM browser_dbs_certificates WHERE cid = ? AND status = 'processing' AND ready_at <= ?", { cid, now() }) or {}
    for _, row in ipairs(due) do issue(row, src) end
end

local function publicCert(row, full)
    local level = findLevel(row.level)
    local t = now()
    local exp = tonumber(row.expires_at)
    local out = {
        id = row.id, number = row.number, name = row.name, level = row.level, levelLabel = level and levelLabel(level) or row.level,
        status = row.status, appliedAt = tonumber(row.applied_at), readyAt = tonumber(row.ready_at),
        issuedAt = tonumber(row.issued_at), expiresAt = (exp and exp > 0) and exp or nil, expired = exp ~= nil and exp > 0 and exp <= t,
        result = row.result,
    }
    if full and row.snapshot and row.snapshot ~= '' then
        local ok, snap = pcall(json.decode, row.snapshot)
        if ok and type(snap) == 'table' then out.records = snap.records or {} end
    end
    return out
end

Browser.handler('gov', 'dbsState', function(src)
    if not running() then return nil, T('gov.dbs.off') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    finalise(cid, src)
    local levels = {}
    for _, l in ipairs(levelDefs()) do
        levels[#levels + 1] = { id = l.id, label = levelLabel(l), description = levelDesc(l), fee = tonumber(l.fee) or 0 }
    end
    local certs = {}
    for _, row in ipairs(MySQL.query.await('SELECT * FROM browser_dbs_certificates WHERE cid = ? ORDER BY id DESC LIMIT 20', { cid }) or {}) do
        certs[#certs + 1] = publicCert(row, false)
    end
    return { levels = levels, certs = certs, processingMinutes = tonumber(cfg('processingMinutes', 0)) or 0,
             validDays = tonumber(cfg('validDays', 30)) or 0, now = now() }
end)

--- data = { level = 'basic' }
Browser.handler('gov', 'dbsApply', function(src, data)
    if not running() then return nil, T('gov.dbs.off') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local level = findLevel(tostring(data.level or ''))
    if not level then return nil, T('gov.dbs.err.level') end
    finalise(cid, src)
    if MySQL.scalar.await("SELECT 1 FROM browser_dbs_certificates WHERE cid = ? AND status = 'processing' LIMIT 1", { cid }) then
        return nil, T('gov.dbs.err.pending')
    end
    local fee = tonumber(level.fee) or 0
    if fee > 0 and not Bridge.removeMoney(src, Config.account, fee, 'dbs-check') then
        return nil, T('shell.err.insufficientFunds')
    end
    local t = now()
    local minutes = tonumber(cfg('processingMinutes', 0)) or 0
    local name = Bridge.getCharacterName(src)
    local number = newNumber()
    local id = MySQL.insert.await(
        "INSERT INTO browser_dbs_certificates (number, cid, name, level, fee, status, applied_at, ready_at) VALUES (?, ?, ?, ?, ?, 'processing', ?, ?)",
        { number, cid, name, level.id, fee, t, t + minutes * 60 })
    if not id then
        if fee > 0 then Bridge.addMoney(src, Config.account, fee, 'dbs-check-refund') end
        return nil, T('gov.err.notCharged')
    end
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = T('gov.dbs.bankLabel', levelLabel(level)), amount = -fee, category = 'government', counterparty = cfg('authority', 'DBS'),
        })
    end)
    if minutes <= 0 then
        finalise(cid, src)
    else
        Bridge.sendPhoneMail(src, cid, cfg('mailFrom', { name = 'DBS', email = 'noreply@lsgov.co.uk' }), T('gov.dbs.receivedSubject'),
            T('gov.dbs.receivedBody', name, levelLabel(level), Config.currency, fee, minutes, siteAddress()))
    end
    local row = MySQL.single.await('SELECT * FROM browser_dbs_certificates WHERE id = ?', { id })
    local out = publicCert(row, true)
    out.paid = fee
    return out
end)

--- One of the player's own certificates, with everything on it. data = { number }
Browser.handler('gov', 'dbsCertificate', function(src, data)
    if not running() then return nil, T('gov.dbs.off') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    finalise(cid, src)
    local number = tostring(data.number or ''):upper():gsub('[^%w]', '')
    local row = MySQL.single.await('SELECT * FROM browser_dbs_certificates WHERE number = ? AND cid = ?', { number, cid })
    if not row then return nil, T('gov.dbs.err.notFound') end
    return publicCert(row, true)
end)

--- For an employer: is this certificate real? data = { number, surname }. A wrong number and a wrong surname
--- get the same answer, so certificate numbers cannot be probed.
Browser.handler('gov', 'dbsVerify', function(src, data)
    if not running() then return nil, T('gov.dbs.off') end
    local number = tostring(data.number or ''):upper():gsub('[^%w]', '')
    local surname = tostring(data.surname or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if number == '' or surname == '' then return nil, T('gov.dbs.err.verifyInput') end
    local row = MySQL.single.await("SELECT * FROM browser_dbs_certificates WHERE number = ? AND status = 'issued'", { number })
    local match = false
    if row then
        for word in tostring(row.name):lower():gmatch('%S+') do
            if word == surname then match = true end
        end
    end
    if not match then return { valid = false } end
    local cert = publicCert(row, true)
    local level = findLevel(row.level) or levelDefs()[1]
    local nowCount = #included(row.cid, level)
    local then_ = cert.records and #cert.records or 0
    return {
        valid = true, name = cert.name, level = cert.level, levelLabel = cert.levelLabel, issuedAt = cert.issuedAt,
        expiresAt = cert.expiresAt, expired = cert.expired, result = cert.result, changed = nowCount ~= then_,
    }
end)

-- Certificates that finish while the player is online are issued (and emailed) by this loop.
CreateThread(function()
    Wait(20000)
    while true do
        if running() and (tonumber(cfg('processingMinutes', 0)) or 0) > 0 then
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                local cid = src and Bridge.getIdentifier(src)
                if cid then pcall(finalise, cid, src) end
            end
        end
        Wait(60000)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Police commands
-- ---------------------------------------------------------------------------------------------

local function reply(src, text, kind)
    if src == 0 then print(('^5[as-browser]^0 %s'):format(text)); return end
    TriggerClientEvent('ox_lib:notify', src, { title = T('gov.dbs.cmd.title'), description = text, type = kind or 'inform', duration = 8000 })
end

local function mayUse(src)
    if src == 0 then return true end
    local job = Bridge.getJob(src)
    if not job then return false end
    for _, j in ipairs(cfg('policeJobs', { 'police' })) do
        if job.name == j then return true end
    end
    return false
end

--- A server id (a player who is online) or a character id (works for anyone).
local function targetCid(arg)
    if not arg or arg == '' then return nil end
    local id = tonumber(arg)
    if id and GetPlayerName(id) then return Bridge.getIdentifier(id) end
    if id then return nil end
    return arg
end

local function command(kind, handler)
    local name = (cfg('commands', {}) or {})[kind]
    if type(name) ~= 'string' or name == '' then return end
    RegisterCommand(name, function(src, args)
        if not mayUse(src) then return reply(src, T('gov.dbs.cmd.noAccess'), 'error') end
        handler(src, args)
    end, false)
end

command('add', function(src, args)
    local cid = targetCid(args[1])
    if not cid then return reply(src, T('gov.dbs.cmd.addUsage'), 'error') end
    local text = table.concat(args, ' ', 3)
    local offence, sentence = text:match('^(.-)%s*|%s*(.*)$')
    if not offence then offence, sentence = text, '' end
    local spentDays = tonumber(args[2])
    if not spentDays or offence == '' then return reply(src, T('gov.dbs.cmd.addUsage'), 'error') end
    local by = src == 0 and T('gov.dbs.cmd.console') or Bridge.getCharacterName(src)
    local id, err = addRecord(cid, { offence = offence, sentence = sentence, issuedBy = by, spentDays = spentDays })
    if not id then return reply(src, tostring(err), 'error') end
    reply(src, T('gov.dbs.cmd.added', id), 'success')
end)

command('view', function(src, args)
    local cid = targetCid(args[1])
    if not cid then return reply(src, T('gov.dbs.cmd.viewUsage'), 'error') end
    local rows = rowsFor(cid)
    if #rows == 0 then return reply(src, T('gov.dbs.cmd.none'), 'inform') end
    local t, lines = now(), {}
    for i, r in ipairs(rows) do
        if i > 6 then lines[#lines + 1] = '...'; break end
        lines[#lines + 1] = ('#%d %s%s'):format(r.id, r.offence, isSpent(r, t) and (' (' .. T('gov.dbs.spent') .. ')') or '')
    end
    reply(src, table.concat(lines, '\n'), 'inform')
end)

command('remove', function(src, args)
    local id = tonumber(args[1])
    if not id then return reply(src, T('gov.dbs.cmd.removeUsage'), 'error') end
    local n = MySQL.update.await('DELETE FROM browser_criminal_records WHERE id = ?', { id })
    if n and n > 0 then reply(src, T('gov.dbs.cmd.removed', id), 'success') else reply(src, T('gov.dbs.cmd.noSuchRecord'), 'error') end
end)
