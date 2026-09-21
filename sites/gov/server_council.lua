-- Council tax on the government site. Reads each character's homes from the housing script, keeps
-- one "paid until" date per home, and lets the player pay what is due. Unpaid bills are only shown as
-- arrears (on the website and as a phone reminder), nothing else happens to the player.
--
-- Settings are in Config.gov.council (sites/gov/config.lua).
local C = Config.gov.council
if not C or C.enabled == false or Config.gov.scripts and Config.gov.scripts.council == false then return end

local DAY = 86400
local function now() return os.time() end
local function log(fmt, ...) print(('^5[as-browser]^0 council: ' .. fmt):format(...)) end

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_council_tax (
        property_key VARCHAR(96) NOT NULL PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        paid_until INT NOT NULL,
        updated_at INT NOT NULL
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_council_payments (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        property_key VARCHAR(96) NOT NULL,
        label VARCHAR(120) NOT NULL,
        periods INT NOT NULL,
        amount INT NOT NULL,
        paid_at INT NOT NULL,
        KEY idx_owner (citizenid, paid_at)
    )]])
end)

-- ---------------------------------------------------------------------------------------------
-- Finding a character's homes
-- ---------------------------------------------------------------------------------------------

--- A piece of text as a quoted SQL string (the "Property" fallback name comes from the locale).
local function sqlText(s)
    return "'" .. (tostring(s):gsub('\\', '\\\\'):gsub("'", "''")) .. "'"
end

local function ident(s)
    return type(s) == 'string' and s:match('^[%w_]+$') and s or nil
end

local function columnsOf(tbl)
    local rows = MySQL.query.await(
        'SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tbl }) or {}
    local set = {}
    for i = 1, #rows do set[rows[i].c] = true end
    return set
end

local function hasAll(set, cols)
    for _, c in ipairs(cols) do if not set[c] then return false end end
    return true
end

-- Each candidate returns an adapter { id, sql } or nil. `sql` selects id, name, value, rented for the
-- homes of one character (one ? for the character id).
local candidates = {}

candidates['qbx_properties'] = { resource = 'qbx_properties', build = function()
    local cols = columnsOf('properties')
    if not hasAll(cols, { 'id', 'owner', 'price' }) then return nil end
    local name = cols.property_name and 'property_name' or ("CONCAT(%s, ' ', id)"):format(sqlText(T('gov.council.property')))
    local rented = cols.rent_interval and '(rent_interval IS NOT NULL)' or '0'
    return { id = 'qbx', sql = ('SELECT id AS id, %s AS name, price AS value, %s AS rented FROM properties WHERE owner = ?'):format(name, rented) }
end }

candidates['ps-housing'] = { resource = 'ps-housing', build = function()
    local cols = columnsOf('properties')
    if not hasAll(cols, { 'property_id', 'owner_citizenid', 'price' }) then return nil end
    local name = cols.street and ('COALESCE(street, %s)'):format(sqlText(T('gov.council.property'))) or sqlText(T('gov.council.property'))
    return { id = 'ps', sql = ('SELECT property_id AS id, CONCAT(%s, \' \', property_id) AS name, price AS value, 0 AS rented FROM properties WHERE owner_citizenid = ?'):format(name) }
end }

candidates['qb-houses'] = { resource = 'qb-houses', build = function()
    local owned, houses = columnsOf('player_houses'), columnsOf('houselocations')
    if not hasAll(owned, { 'house', 'citizenid' }) or not hasAll(houses, { 'name' }) then return nil end
    local label = houses.label and 'COALESCE(h.label, h.name)' or 'h.name'
    local price = houses.price and 'h.price' or '0'
    return { id = 'qbh', sql = ('SELECT h.name AS id, %s AS name, %s AS value, 0 AS rented FROM player_houses p JOIN houselocations h ON h.name = p.house WHERE p.citizenid = ?'):format(label, price) }
end }

candidates['custom'] = { build = function()
    local c = C.custom or {}
    local tbl, idc, owner, namec, valuec = ident(c.table), ident(c.idColumn), ident(c.ownerColumn), ident(c.nameColumn), ident(c.valueColumn)
    if not (tbl and idc and owner and namec and valuec) then
        log('the custom housing settings are incomplete (table, idColumn, ownerColumn, nameColumn, valueColumn)')
        return nil
    end
    local cols = columnsOf(tbl)
    if not hasAll(cols, { idc, owner, namec, valuec }) then
        log('the custom housing table "%s" does not have all of those columns', tbl)
        return nil
    end
    local rentc = ident(c.rentColumn)
    local rented = (rentc and cols[rentc]) and ('(`%s` IS NOT NULL AND `%s` <> \'\' AND `%s` <> \'0\')'):format(rentc, rentc, rentc) or '0'
    return { id = 'custom', sql = ('SELECT `%s` AS id, `%s` AS name, `%s` AS value, %s AS rented FROM `%s` WHERE `%s` = ?'):format(idc, namec, valuec, rented, tbl, owner) }
end }

local adapter, lastTry = nil, 0

local function getAdapter()
    if adapter then return adapter end
    local t = now()
    if t - lastTry < 60 then return nil end
    lastTry = t

    local order
    if C.housing == 'auto' or C.housing == nil then
        order = { 'qbx_properties', 'ps-housing', 'qb-houses' }
    else
        order = { C.housing }
    end

    -- Prefer a housing script that is running, then any one whose tables exist.
    for pass = 1, 2 do
        for _, name in ipairs(order) do
            local cand = candidates[name]
            if cand and (pass == 2 or not cand.resource or GetResourceState(cand.resource) == 'started') then
                local ok, found = pcall(cand.build)
                if ok and found then
                    adapter = found
                    log('reading homes with the "%s" housing settings', name)
                    return adapter
                end
            end
        end
        if #order == 1 then break end
    end
    log('no housing script found: council tax cannot list homes. Set Config.gov.council.housing in sites/gov/config.lua')
    return nil
end

--- The character's homes as { key, name, value, rented }.
local function homesOf(cid)
    local a = getAdapter()
    if not a then return nil end
    local ok, rows = pcall(function() return MySQL.query.await(a.sql, { cid }) end)
    if not ok then
        log('reading homes failed: %s', tostring(rows))
        return nil
    end
    local out = {}
    for i = 1, math.min(#(rows or {}), 50) do
        local r = rows[i]
        out[#out + 1] = {
            key = a.id .. ':' .. tostring(r.id), name = tostring(r.name or T('gov.council.property')):sub(1, 80),
            value = tonumber(r.value) or 0, rented = r.rented == 1 or r.rented == true,
        }
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- What each home owes
-- ---------------------------------------------------------------------------------------------

local function periodSeconds() return math.max(1, C.periodDays or 7) * DAY end

local function billFor(home)
    if home.rented then return math.max(0, math.floor(C.rentedBill or 0)) end
    local amount = math.floor((home.value or 0) * (C.ratePercent or 0) / 100 + 0.5)
    amount = math.max(C.minBill or 0, amount)
    if (C.maxBill or 0) > 0 then amount = math.min(C.maxBill, amount) end
    return amount
end

--- The stored "paid until" date. A home the system has not met yet, or one that now belongs to somebody
--- else, starts paid up for graceDays, so a new owner never inherits the last owner's arrears.
local function paidUntil(home, cid)
    local row = MySQL.single.await('SELECT citizenid, paid_until FROM browser_council_tax WHERE property_key = ?', { home.key })
    if row and row.citizenid == cid then return tonumber(row.paid_until) or now() end
    local t = now()
    local start = t + (C.graceDays or 7) * DAY
    MySQL.update.await(
        'INSERT INTO browser_council_tax (property_key, citizenid, paid_until, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE citizenid = VALUES(citizenid), paid_until = VALUES(paid_until), updated_at = VALUES(updated_at)',
        { home.key, cid, start, t })
    return start
end

local function assess(home, cid)
    local t, period = now(), periodSeconds()
    local until_ = paidUntil(home, cid)
    local due = 0
    if t >= until_ then due = math.floor((t - until_) / period) + 1 end
    local payable = due
    if payable == 0 and (until_ - t) <= (C.payAheadDays or 0) * DAY then payable = 1 end
    payable = math.min(payable, math.max(1, C.maxPeriods or 26))
    local amount = billFor(home)
    local status = 'paid'
    if due == 1 then status = 'due' elseif due > 1 then status = 'arrears' end
    return {
        key = home.key, name = home.name, value = home.value, rented = home.rented,
        amount = amount, paidUntil = until_, periodsDue = due, owed = due * amount, status = status,
        payPeriods = payable, payAmount = payable * amount, canPay = payable > 0 and amount > 0,
    }
end

-- ---------------------------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------------------------

Browser.handler('gov', 'councilState', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local homes = homesOf(cid)
    if not homes then return nil, T('gov.council.unavailable') end

    local out, owed = {}, 0
    for i = 1, #homes do
        local a = assess(homes[i], cid)
        out[#out + 1] = a
        owed = owed + a.owed
    end
    return { homes = out, owed = owed, periodDays = C.periodDays or 7, authority = C.authority, now = now() }
end)

Browser.handler('gov', 'councilHistory', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local rows = MySQL.query.await(
        'SELECT label, periods, amount, paid_at FROM browser_council_payments WHERE citizenid = ? ORDER BY id DESC LIMIT 40', { cid }) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = { label = rows[i].label, periods = rows[i].periods, amount = rows[i].amount, paidAt = rows[i].paid_at }
    end
    return { payments = out }
end)

-- ---------------------------------------------------------------------------------------------
-- Paying
-- ---------------------------------------------------------------------------------------------

local busy = {}

local function discordLog(fields)
    if type(C.webhook) ~= 'string' or not C.webhook:find('^https://') then return end
    local out = {}
    for _, f in ipairs(fields) do
        local v = tostring(f[2]):gsub('@', '@\226\128\139')
        out[#out + 1] = { name = f[1], value = v:sub(1, 200), inline = true }
    end
    PerformHttpRequest(C.webhook, function() end, 'POST', json.encode({
        embeds = { { title = T('gov.discord.councilTitle'), color = 0x0f766e, fields = out, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'), footer = { text = 'as-browser' } } },
        allowed_mentions = { parse = {} },
    }), { ['Content-Type'] = 'application/json' })
end

local function pay(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local key = tostring(data.key or '')
    if #key > 96 then return nil, T('gov.council.homeNotFound') end

    local homes = homesOf(cid)
    if not homes then return nil, T('gov.council.unavailable') end
    local home
    for i = 1, #homes do if homes[i].key == key then home = homes[i] end end
    if not home then return nil, T('gov.council.notOwner') end

    local a = assess(home, cid)
    if not a.canPay then
        return nil, T('gov.council.nothingToPay', Browser.date(a.paidUntil - (C.payAheadDays or 0) * DAY))
    end

    local total = a.payAmount
    if not Bridge.removeMoney(src, Config.account, total, 'council-tax') then
        return nil, T('shell.err.insufficientFunds')
    end

    local newUntil = a.paidUntil + a.payPeriods * periodSeconds()
    -- Only succeeds if nothing else moved the date, so a double click can never charge twice.
    local changed = MySQL.update.await(
        'UPDATE browser_council_tax SET paid_until = ?, updated_at = ? WHERE property_key = ? AND citizenid = ? AND paid_until = ?',
        { newUntil, now(), home.key, cid, a.paidUntil })
    if not changed or changed < 1 then
        Bridge.addMoney(src, Config.account, total, 'council-tax-refund')
        return nil, T('gov.err.changed')
    end

    MySQL.insert.await(
        'INSERT INTO browser_council_payments (citizenid, property_key, label, periods, amount, paid_at) VALUES (?, ?, ?, ?, ?, ?)',
        { cid, home.key, home.name, a.payPeriods, total, now() })

    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = T('gov.council.bankLabel', home.name), amount = -total, category = 'government', counterparty = C.authority,
        })
    end)

    local name = Bridge.getCharacterName(src)
    Bridge.sendPhoneMail(src, cid, C.mailFrom, T('gov.council.mailSubject', home.name),
        T('gov.council.mailBody', name, home.name, a.payPeriods, Config.currency, total, Browser.date(newUntil)))
    discordLog({ { T('gov.discord.character'), name }, { T('gov.discord.citizenId'), cid }, { T('gov.discord.property'), home.name }, { T('gov.discord.periods'), a.payPeriods }, { T('gov.discord.paid'), Config.currency .. total } })

    return { name = home.name, periods = a.payPeriods, amount = total, paidUntil = newUntil, now = now() }
end

Browser.handler('gov', 'councilPay', function(src, data)
    if busy[src] then return nil, T('shell.err.busy') end
    busy[src] = true
    local ok, res, err = pcall(pay, src, data)
    busy[src] = nil
    if not ok then error(res, 0) end
    return res, err
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

-- ---------------------------------------------------------------------------------------------
-- Phone reminder for players in arrears
-- ---------------------------------------------------------------------------------------------

local reminded = {}

CreateThread(function()
    local hours = tonumber(C.notifyHours) or 0
    if hours <= 0 then return end
    Wait(120000)
    while true do
        pcall(function()
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                local cid = src and Bridge.getIdentifier(src)
                if cid and (not reminded[cid] or now() - reminded[cid] >= hours * 3600) then
                    local homes = homesOf(cid)
                    local owed = 0
                    for i = 1, #(homes or {}) do
                        local a = assess(homes[i], cid)
                        if a.periodsDue >= 2 then owed = owed + a.owed end
                    end
                    if owed > 0 then
                        reminded[cid] = now()
                        pcall(function()
                            exports['sd-phone']:notify(src, {
                                app = 'as-browser', appId = 'as-browser', title = T('gov.council.reminderTitle'),
                                body = T('gov.council.reminderBody', Config.currency, owed), time = 'now',
                            })
                        end)
                    end
                end
            end
        end)
        Wait(600000)
    end
end)
