-- LS Vehicle Check: a report on any registration number (owners, plate changes, stolen / written-off flags, MOT mileage),
-- like a used-car history check. Also keeps the records behind it:
--   browser_vehicle_events   things that happened to a vehicle (owner changes, plate changes, flags, anything a script logs)
--   browser_vehicle_flags    stolen / written off / impounded / finance ... set by police or other scripts
--   browser_vehicle_owners   who owns each vehicle, so a change of owner is noticed
--   browser_vehicle_reports  reports players bought (a snapshot, so it never changes after purchase)
-- A vehicle's records are stored under its CURRENT registration. LS Plates moves them to the new registration whenever a
-- personalised plate is put on or taken off, so the history (and MOT) always stays with the vehicle.
local H = Config.vehiclecheck or {}
local DAY = 86400

local function cfg(key, default)
    if H[key] == nil then return default end
    return H[key]
end

local function now() return os.time() end
local function trimPlate(p) return (tostring(p):gsub('%s+$', '')) end

Browser.defineSite('vehiclecheck', {
    title       = H.name or 'LS Vehicle Check',
    description = T('vc.description'),
    keywords    = Browser.words(T('vc.keywords')),
    category    = T('vc.category'),
    icon        = '🔎',
    color       = '#0f766e',
    pages       = {
        { path = '/', title = H.name or 'LS Vehicle Check', description = T('gov.history.lead'), keywords = Browser.words(T('vc.keywords')) },
    },
})

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_vehicle_events (
        id INT AUTO_INCREMENT PRIMARY KEY,
        plate VARCHAR(16) NOT NULL,
        kind VARCHAR(32) NOT NULL,
        text VARCHAR(300) NOT NULL DEFAULT '',
        at INT NOT NULL,
        KEY idx_plate (plate, at)
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_vehicle_flags (
        plate VARCHAR(16) NOT NULL,
        flag VARCHAR(24) NOT NULL,
        note VARCHAR(200) NOT NULL DEFAULT '',
        set_at INT NOT NULL,
        PRIMARY KEY (plate, flag)
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_vehicle_owners (
        plate VARCHAR(16) NOT NULL PRIMARY KEY,
        owner VARCHAR(64) NOT NULL,
        owners INT NOT NULL DEFAULT 1,
        since INT NOT NULL
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_vehicle_reports (
        id INT AUTO_INCREMENT PRIMARY KEY,
        cid VARCHAR(64) NOT NULL,
        plate VARCHAR(16) NOT NULL,
        created_at INT NOT NULL,
        paid INT NOT NULL DEFAULT 0,
        data MEDIUMTEXT NOT NULL,
        KEY idx_cid (cid, id)
    )]])
end)

-- ---------------------------------------------------------------------------------------------
-- Events and flags (used by this resource, and by other scripts through the exports)
-- ---------------------------------------------------------------------------------------------

--- Adds a line to a vehicle's history. kind is a short word ('accident', 'owner_change', ...): the text shown for it
--- comes from locales/en.lua (gov.history.event.<kind>) when that key exists, otherwise the kind itself.
function Browser.logVehicleEvent(plate, kind, text)
    local key = Vehicles.normalizePlate(plate)
    kind = tostring(kind or ''):gsub('[^%w_]', ''):sub(1, 32)
    if not key or kind == '' then return false end
    MySQL.insert.await('INSERT INTO browser_vehicle_events (plate, kind, text, at) VALUES (?, ?, ?, ?)',
        { key, kind, tostring(text or ''):gsub('%c', ' '):sub(1, 300), now() })
    return true
end

local function flagDef(id)
    for _, f in ipairs(cfg('flags', {})) do if f.id == id then return f end end
    return nil
end

--- The flag row ({ flag, note, set_at }) when set, otherwise nil.
function Browser.vehicleFlag(key, flag)
    return MySQL.single.await('SELECT flag, note, set_at FROM browser_vehicle_flags WHERE plate = ? AND flag = ?', { key, flag })
end

--- Sets or clears a flag. Returns true, or false plus a reason.
function Browser.setVehicleFlag(plate, flag, on, note)
    local key = Vehicles.normalizePlate(plate)
    if not key then return false, 'Invalid registration number' end
    flag = tostring(flag or '')
    if not flagDef(flag) then return false, 'Unknown flag' end
    local existing = Browser.vehicleFlag(key, flag)
    note = tostring(note or ''):gsub('%c', ' '):sub(1, 200)
    if on == true or on == 1 then
        if existing then
            MySQL.update.await('UPDATE browser_vehicle_flags SET note = ?, set_at = ? WHERE plate = ? AND flag = ?', { note, now(), key, flag })
        else
            MySQL.insert.await('INSERT INTO browser_vehicle_flags (plate, flag, note, set_at) VALUES (?, ?, ?, ?)', { key, flag, note, now() })
            Browser.logVehicleEvent(key, 'flag_set', T('gov.history.flag.' .. flag))
        end
    else
        if existing then
            MySQL.update.await('DELETE FROM browser_vehicle_flags WHERE plate = ? AND flag = ?', { key, flag })
            Browser.logVehicleEvent(key, 'flag_cleared', T('gov.history.flag.' .. flag))
        end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Owners: a change of owner is a line in the history and counts as another owner
-- ---------------------------------------------------------------------------------------------

local function noteOwner(key, owner)
    if not cfg('trackOwners', true) or not owner or owner == '' then return end
    local row = MySQL.single.await('SELECT owner, owners FROM browser_vehicle_owners WHERE plate = ?', { key })
    if not row then
        MySQL.insert.await('INSERT INTO browser_vehicle_owners (plate, owner, owners, since) VALUES (?, ?, 1, ?)', { key, tostring(owner), now() })
    elseif row.owner ~= tostring(owner) then
        MySQL.update.await('UPDATE browser_vehicle_owners SET owner = ?, owners = owners + 1, since = ? WHERE plate = ?', { tostring(owner), now(), key })
        Browser.logVehicleEvent(key, 'owner_change', '')
    end
end

local function ownerCount(key)
    local n = MySQL.scalar.await('SELECT owners FROM browser_vehicle_owners WHERE plate = ?', { key })
    return tonumber(n)
end

--- Reads the whole owned vehicles table in pages and notes every owner. New vehicles are added in batches.
local function ownerSweep()
    if not cfg('trackOwners', true) then return end
    local known = {}
    for _, r in ipairs(MySQL.query.await('SELECT plate, owner FROM browser_vehicle_owners') or {}) do known[r.plate] = r.owner end
    local fresh, offset, size = {}, 0, 1000
    while true do
        local page = Vehicles.page(offset, size)
        for _, v in ipairs(page) do
            local key = Vehicles.normalizePlate(tostring(v.plate or ''))
            local owner = v.owner ~= nil and tostring(v.owner) or nil
            if key and owner and owner ~= '' then
                local was = known[key]
                if was == nil then
                    fresh[#fresh + 1] = { key, owner }
                    known[key] = owner
                elseif was ~= owner then
                    noteOwner(key, owner)
                    known[key] = owner
                end
            end
        end
        if #page < size then break end
        offset = offset + size
        Wait(0)
    end
    local t = now()
    for i = 1, #fresh, 200 do
        local marks, args = {}, {}
        for j = i, math.min(i + 199, #fresh) do
            marks[#marks + 1] = '(?, ?, 1, ?)'
            args[#args + 1] = fresh[j][1]; args[#args + 1] = fresh[j][2]; args[#args + 1] = t
        end
        MySQL.query.await('INSERT IGNORE INTO browser_vehicle_owners (plate, owner, owners, since) VALUES ' .. table.concat(marks, ', '), args)
        Wait(0)
    end
end

CreateThread(function()
    local minutes = tonumber(cfg('sweepMinutes', 15)) or 0
    if minutes <= 0 or not cfg('trackOwners', true) then return end
    Wait(45000)
    while true do
        local ok, err = pcall(ownerSweep)
        if not ok then print(('^5[as-browser]^0 vehiclecheck: owner sweep failed: %s'):format(tostring(err))) end
        Wait(minutes * 60000)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- The report
-- ---------------------------------------------------------------------------------------------

local function motResource()
    return (Config.gov and Config.gov.motBooking and Config.gov.motBooking.resource) or 'as-computer'
end

--- MOT tests for a plate, newest first. as-computer's records carry the mileage; without it the tests this resource
--- was told about (no mileage) are used.
local function motTests(key)
    local res = motResource()
    if GetResourceState(res) == 'started' then
        local ok, r = pcall(function() return exports[res]:getMotRecords(key) end)
        if ok and type(r) == 'table' and type(r.records) == 'table' then
            local out = {}
            for i, x in ipairs(r.records) do
                out[i] = { testedAt = tonumber(x.testedAt), passed = x.passed == true, expiry = tonumber(x.expiresAt),
                           mileage = tonumber(x.mileage), unit = x.unit, location = x.location }
            end
            return out
        end
    end
    local rows = MySQL.query.await(
        'SELECT tested_at, passed, expiry FROM browser_mot_history WHERE plate = ? ORDER BY tested_at DESC LIMIT 30', { key }) or {}
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = { testedAt = tonumber(r.tested_at), passed = r.passed == 1 or r.passed == true,
                   expiry = (tonumber(r.expiry) or 0) > 0 and tonumber(r.expiry) or nil }
    end
    return out
end

--- Looks for a mileage that goes down from one test to the next.
local function mileageCheck(tests)
    local readings = {}
    for i = #tests, 1, -1 do   -- oldest first
        local x = tests[i]
        if x.mileage and x.mileage > 0 and x.testedAt then readings[#readings + 1] = x end
    end
    if #readings < 2 then return { status = 'info' } end
    for i = 2, #readings do
        if readings[i].mileage < readings[i - 1].mileage and readings[i].unit == readings[i - 1].unit then
            return { status = 'fail', at = readings[i].testedAt, from = readings[i - 1].mileage, to = readings[i].mileage, unit = readings[i].unit }
        end
    end
    return { status = 'pass', first = readings[1].mileage, last = readings[#readings].mileage, unit = readings[#readings].unit }
end

local function eventLabel(kind)
    local key = 'gov.history.event.' .. kind
    local txt = T(key)
    if txt == key then return kind end
    return txt
end

local function unitText(u)
    if not u or u == '' then return T('gov.history.unit.miles') end
    local key = 'gov.history.unit.' .. tostring(u)
    local txt = T(key)
    return txt ~= key and txt or tostring(u)
end

--- Builds the whole report for a vehicle that exists. `d` is Vehicles.describe(v).
local function buildReport(key, d)
    local status = Browser.api.getVehicleStatus and Browser.api.getVehicleStatus(key) or nil
    local checks = {}
    local function add(id, label, st, detail) checks[#checks + 1] = { id = id, label = label, status = st, detail = detail } end

    -- flags
    local flagRows = MySQL.query.await('SELECT flag, note, set_at FROM browser_vehicle_flags WHERE plate = ?', { key }) or {}
    local flagMap = {}
    for _, r in ipairs(flagRows) do flagMap[r.flag] = r end
    for _, f in ipairs(cfg('flags', {})) do
        local r = flagMap[f.id]
        local label = T('gov.history.flag.' .. f.id)
        if r then
            local note = (r.note and r.note ~= '') and (' ' .. r.note) or ''
            add('flag_' .. f.id, label, f.severity == 'warn' and 'warn' or 'fail', T('gov.history.flagSet', Browser.date(tonumber(r.set_at))) .. note)
        else
            add('flag_' .. f.id, label, 'pass', T('gov.history.flagClear'))
        end
    end

    -- MOT
    local tests = motTests(key)
    if status and status.mot and status.mot.enabled then
        local m = status.mot
        if m.status == 'valid' then add('mot', T('gov.history.check.mot'), 'pass', T('gov.history.mot.valid', Browser.date(m.expiry)))
        elseif m.status == 'expired' then add('mot', T('gov.history.check.mot'), 'fail', T('gov.history.mot.expired', Browser.date(m.expiry)))
        elseif m.status == 'failed' then add('mot', T('gov.history.check.mot'), 'fail', T('gov.history.mot.failed'))
        else add('mot', T('gov.history.check.mot'), 'warn', T('gov.history.mot.none')) end
    end

    -- mileage
    local mc = mileageCheck(tests)
    if mc.status == 'fail' then
        add('mileage', T('gov.history.check.mileage'), 'fail', T('gov.history.mileage.dropped', Browser.date(mc.at), math.floor(mc.from), math.floor(mc.to), unitText(mc.unit)))
    elseif mc.status == 'pass' then
        add('mileage', T('gov.history.check.mileage'), 'pass', T('gov.history.mileage.ok', math.floor(mc.first), math.floor(mc.last), unitText(mc.unit)))
    else
        add('mileage', T('gov.history.check.mileage'), 'info', T('gov.history.mileage.notEnough'))
    end

    -- owners and plates
    local owners = cfg('trackOwners', true) and ownerCount(key) or nil
    if owners then
        local st = (owners - 1) > (tonumber(cfg('manyOwners', 4)) or 4) and 'warn' or 'pass'
        add('owners', T('gov.history.check.owners'), st, owners == 1 and T('gov.history.owners.one') or T('gov.history.owners.other', owners))
    end
    local previous, current = {}, nil
    do
        -- The vehicle keeps its original registration (base) while a personalised plate is fitted, so its plate history is
        -- everything recorded against that original registration.
        local base = key
        local a = Plates and Plates.x and Plates.x.assetByKey(key)
        if a and a.base_key then
            base = a.base_key
            current = { plate = a.display, original = a.base_display or a.base_key }
        end
        local changes = MySQL.query.await(
            "SELECT kind, old_display, new_display, logged_at FROM browser_plate_log WHERE base_key = ? AND kind IN ('fit', 'legacy') ORDER BY logged_at ASC, id ASC", { base }) or {}
        for _, c in ipairs(changes) do
            previous[#previous + 1] = { plate = c.old_display, to = c.new_display, at = tonumber(c.logged_at) }
        end
    end
    if current then
        add('plates', T('gov.history.check.plates'), 'info', T('vc.plates.personalised', current.plate, current.original))
    elseif #previous > 0 then
        add('plates', T('gov.history.check.plates'), 'info', #previous == 1 and T('vc.plates.wore.one') or T('vc.plates.wore.other', #previous))
    else
        add('plates', T('gov.history.check.plates'), 'pass', T('gov.history.plates.never'))
    end

    -- tax and insurance
    if status then
        if status.exempt then add('tax', T('gov.history.check.tax'), 'info', T('gov.history.tax.exempt'))
        elseif status.tax.status == 'taxed' then add('tax', T('gov.history.check.tax'), 'pass', T('gov.history.tax.taxed', Browser.date(status.tax.expiry)))
        else add('tax', T('gov.history.check.tax'), 'warn', T('gov.history.tax.untaxed')) end
        if status.insured ~= nil then
            add('insurance', T('gov.history.check.insurance'), status.insured and 'pass' or 'warn',
                status.insured and T('gov.history.insurance.yes') or T('gov.history.insurance.no'))
        end
    end

    -- events
    local rows = MySQL.query.await('SELECT kind, text, at FROM browser_vehicle_events WHERE plate = ? ORDER BY at DESC, id DESC LIMIT ?',
        { key, tonumber(cfg('maxEvents', 40)) or 40 }) or {}
    local events = {}
    for i, r in ipairs(rows) do events[i] = { kind = r.kind, label = eventLabel(r.kind), text = r.text or '', at = tonumber(r.at) } end

    local verdict, issues = 'pass', 0
    for _, c in ipairs(checks) do
        if c.status == 'fail' then verdict = 'fail'; issues = issues + 1
        elseif c.status == 'warn' then if verdict ~= 'fail' then verdict = 'warn' end; issues = issues + 1 end
    end

    return {
        plate = trimPlate(d.plate), key = key, at = now(),
        vehicle = { make = d.make, model = d.model, colour = d.colour, class = d.class.label },
        verdict = verdict, issues = issues, checks = checks, owners = owners,
        previousPlates = previous, personalised = current, events = events, tests = tests,
    }
end

--- For police / MDT screens and other scripts: the full report, no payment. nil when the vehicle does not exist.
function Browser.api.getVehicleHistory(plate)
    local v = Vehicles.find(plate)
    if not v then return nil end
    local d = Vehicles.describe(v)
    noteOwner(d.plateKey, v.owner)
    return buildReport(d.plateKey, d)
end

-- ---------------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------------

exports('logVehicleEvent', function(plate, kind, text) return Browser.logVehicleEvent(plate, kind, text) end)
exports('setVehicleFlag', function(plate, flag, on, note) return (Browser.setVehicleFlag(plate, flag, on, note)) end)
exports('getVehicleFlags', function(plate)
    local key = Vehicles.normalizePlate(plate)
    if not key then return {} end
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT flag, note, set_at FROM browser_vehicle_flags WHERE plate = ?', { key }) or {}) do
        out[#out + 1] = { flag = r.flag, note = r.note, at = tonumber(r.set_at) }
    end
    return out
end)
exports('getVehicleHistory', function(plate) return Browser.api.getVehicleHistory(plate) end)

-- ---------------------------------------------------------------------------------------------
-- Requests from the site
-- ---------------------------------------------------------------------------------------------

local function bankLine(cid, label, amount)
    if amount == 0 then return end
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, { label = label, amount = amount, category = 'government', counterparty = cfg('authority', 'Vehicle Records') })
    end)
end

local function siteAddress()
    local c = Config.Sites and Config.Sites.vehiclecheck
    return c and c.domain or 'lsvehiclecheck.co.uk'
end

local SECTIONS = { 'flags', 'mot', 'mileage', 'tax', 'insurance', 'owners', 'plates', 'events', 'tests' }

--- The plans from the config, cleaned up. Falls back to one full plan when none is set.
local function plans()
    local out = {}
    for _, p in ipairs(cfg('plans', {})) do
        if type(p.id) == 'string' and p.id ~= '' and type(p.includes) == 'table' then
            local inc = {}
            for _, want in ipairs(SECTIONS) do
                for _, has in ipairs(p.includes) do if has == want then inc[#inc + 1] = want; break end end
            end
            out[#out + 1] = { id = p.id, name = tostring(p.name or p.id), description = tostring(p.description or ''),
                              price = math.max(0, math.floor(tonumber(p.price) or 0)), includes = inc, popular = p.popular == true }
        end
    end
    if #out == 0 then
        out[1] = { id = 'full', name = T('vc.plan.default'), description = '', price = 25, includes = SECTIONS, popular = false }
    end
    return out
end

local function planById(id)
    for _, p in ipairs(plans()) do if p.id == id then return p end end
    return nil
end

--- What a plan costs this player for this vehicle.
local function feeFor(cid, v, plan)
    local price = plan.price
    if price > 0 and cfg('ownedFree', true) and cid and v.owner == cid then return 0 end
    return price
end

local function planList(cid, v)
    local out = {}
    for _, p in ipairs(plans()) do
        out[#out + 1] = { id = p.id, name = p.name, description = p.description, popular = p.popular, includes = p.includes,
                          price = p.price, fee = v and feeFor(cid, v, p) or p.price }
    end
    return out
end

--- Cuts a full report down to what a plan includes.
local function applyPlan(rep, plan)
    local has = {}
    for _, s in ipairs(plan.includes) do has[s] = true end
    local checks, verdict, issues = {}, 'pass', 0
    for _, c in ipairs(rep.checks) do
        local section = c.id:match('^flag_') and 'flags' or c.id
        if has[section] then
            checks[#checks + 1] = c
            if c.status == 'fail' then verdict = 'fail'; issues = issues + 1
            elseif c.status == 'warn' then if verdict ~= 'fail' then verdict = 'warn' end; issues = issues + 1 end
        end
    end
    local out = {}
    for k, v in pairs(rep) do out[k] = v end
    out.checks, out.verdict, out.issues = checks, verdict, issues
    if not has.plates then out.previousPlates = {}; out.personalised = nil end
    if not has.events then out.events = {} end
    if not has.tests then out.tests = {} end
    if not has.owners then out.owners = nil end
    local locked = {}
    for _, s in ipairs(SECTIONS) do if not has[s] then locked[#locked + 1] = s end end
    out.plan = { id = plan.id, name = plan.name }
    out.sections = plan.includes
    out.locked = locked
    return out
end

local function findMine(cid, key)
    return MySQL.single.await('SELECT id, created_at FROM browser_vehicle_reports WHERE cid = ? AND plate = ? ORDER BY id DESC LIMIT 1', { cid, key })
end

--- The plate form and the player's reports.
Browser.handler('vehiclecheck', 'state', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local rows = MySQL.query.await('SELECT id, plate, created_at, data FROM browser_vehicle_reports WHERE cid = ? ORDER BY id DESC LIMIT 20', { cid }) or {}
    local list = {}
    for i, r in ipairs(rows) do
        local ok, data = pcall(json.decode, r.data)
        list[i] = { id = r.id, plate = (ok and type(data) == 'table' and data.plate) or trimPlate(r.plate), at = tonumber(r.created_at),
                    plan = ok and type(data) == 'table' and data.plan and data.plan.name or nil,
                    verdict = ok and type(data) == 'table' and data.verdict or 'pass', issues = ok and type(data) == 'table' and data.issues or 0 }
    end
    return { plans = planList(cid, nil), ownedFree = cfg('ownedFree', true), reports = list, now = now() }
end)

--- The free summary for one registration number. data = { plate }
Browser.handler('vehiclecheck', 'lookup', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local key = Vehicles.normalizePlate(tostring(data.plate or ''))
    if not key then return nil, T('vc.err.plate') end
    local v = Vehicles.find(key)
    if not v then return { found = false, plate = key } end
    local d = Vehicles.describe(v)
    noteOwner(d.plateKey, v.owner)
    local rep = buildReport(d.plateKey, d)
    local mine = findMine(cid, d.plateKey)
    return {
        found = true, plate = trimPlate(d.plate), key = d.plateKey,
        make = d.make, model = d.model, colour = d.colour, class = d.class.label,
        checks = #rep.checks, issues = rep.issues, plans = planList(cid, v), owned = v.owner == cid,
        reportId = mine and mine.id or nil, reportAt = mine and tonumber(mine.created_at) or nil,
    }
end)

--- Buy (or, for the owner, open) a report. data = { plate, plan = plan id }
Browser.handler('vehiclecheck', 'buy', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local key = Vehicles.normalizePlate(tostring(data.plate or ''))
    if not key then return nil, T('vc.err.plate') end
    local v = Vehicles.find(key)
    if not v then return nil, T('gov.history.notFound') end
    local plan = planById(tostring(data.plan or ''))
    if not plan then return nil, T('vc.err.plan') end
    local d = Vehicles.describe(v)
    local fee = feeFor(cid, v, plan)
    if fee > 0 and not Bridge.removeMoney(src, Config.account, fee, 'vehicle-history') then
        return nil, T('shell.err.insufficientFunds')
    end
    noteOwner(d.plateKey, v.owner)
    local ok, rep = pcall(buildReport, d.plateKey, d)
    if not ok then
        print(('^5[as-browser]^0 vehiclecheck: report failed: %s'):format(tostring(rep)))
        if fee > 0 then Bridge.addMoney(src, Config.account, fee, 'vehicle-history-refund') end
        return nil, T('vc.err.notCharged')
    end
    rep = applyPlan(rep, plan)
    rep.paid = fee
    local id = MySQL.insert.await('INSERT INTO browser_vehicle_reports (cid, plate, created_at, paid, data) VALUES (?, ?, ?, ?, ?)',
        { cid, d.plateKey, now(), fee, json.encode(rep) })
    rep.id = id
    bankLine(cid, T('gov.history.bankLabel', rep.plate), -fee)
    if fee > 0 then
        Bridge.sendPhoneMail(src, cid, cfg('mailFrom', { name = 'Vehicle Records', email = 'noreply@lsvehiclecheck.co.uk' }), T('gov.history.mailSubject', rep.plate),
            T('gov.history.mailBody', Bridge.getCharacterName(src), rep.plate, rep.issues, siteAddress()))
    end
    return rep
end)

--- Open one of the player's own saved reports. data = { id }
Browser.handler('vehiclecheck', 'report', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local row = MySQL.single.await('SELECT id, data FROM browser_vehicle_reports WHERE id = ? AND cid = ?', { tonumber(data.id), cid })
    if not row then return nil, T('gov.history.reportMissing') end
    local ok, rep = pcall(json.decode, row.data)
    if not ok or type(rep) ~= 'table' then return nil, T('gov.history.reportMissing') end
    rep.id = row.id
    return rep
end)

-- ---------------------------------------------------------------------------------------------
-- printing (as-printer): one of the player's own saved reports. data = { id, printer, colour, design, letterhead }
-- ---------------------------------------------------------------------------------------------
Browser.handler('vehiclecheck', 'reportPrint', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local row = MySQL.single.await('SELECT id, data, created_at FROM browser_vehicle_reports WHERE id = ? AND cid = ?', { tonumber(data.id), cid })
    if not row then return nil, T('gov.history.reportMissing') end
    local ok, rep = pcall(json.decode, row.data)
    if not ok or type(rep) ~= 'table' then return nil, T('gov.history.reportMissing') end
    local byId, notes = {}, {}
    for _, c in ipairs(rep.checks or {}) do
        byId[c.id] = c
        if c.id ~= 'mot' and c.id ~= 'mileage' and c.id ~= 'owners' and c.id ~= 'plates' then
            notes[#notes + 1] = ('%s: %s%s'):format(c.label or c.id, c.detail or '', c.status == 'fail' and ' (!)' or '')
        end
    end
    local function detail(id) return byId[id] and byId[id].detail or T('print.motNone') end
    local v = rep.vehicle or {}
    local stolen, wo = byId.flag_stolen, byId.flag_written_off
    return Browser.printDoc(src, 'vehicle_report', {
        plan = rep.plan and rep.plan.name or '', plate = rep.plate, model = ('%s %s'):format(v.make or '', v.model or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        colour = v.colour, owners = rep.owners, plateChanges = tostring(#(rep.previousPlates or {})),
        mot = detail('mot'), mileage = detail('mileage'),
        stolen = stolen and (stolen.status == 'pass' and T('print.stolenNo') or T('print.stolenYes')) or nil,
        writtenOff = wo and (wo.status == 'pass' and T('print.stolenNo') or T('print.stolenYes')) or nil,
        date = Browser.date(tonumber(row.created_at) or now()), notes = notes,
    }, data)
end)
