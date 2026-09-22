-- LS Bank: online banking, the website version of the phone's Wallet. See sites/bank/config.lua.
--   phone_bank_transactions      the statement (shared with the phone)
--   phone_bank_standing_orders   standing orders (shared; the phone runs them)
--   phone_service_invoices       invoices (shared)
--   phone_settings               phone number and card style
-- This site never creates or changes the shape of those tables, it only reads and writes rows. If sd-phone is not installed
-- (or has not made its tables yet) every page says the bank is not available.
local BK = Config.bank or {}

local function log(fmt, ...) print(('^5[as-browser:bank]^0 ' .. fmt):format(...)) end
local function now() return os.time() end
local function cfgNum(key, default) return tonumber(BK[key]) or default end
local function sub(key) return type(BK[key]) == 'table' and BK[key] or {} end

Browser.defineSite('bank', {
    title       = BK.name or 'LS Bank',
    description = T('bank.description'),
    keywords    = Browser.words(T('bank.keywords')),
    category    = T('bank.category'),
    icon        = '🏦',
    color       = '#0f4c81',
    pages = {
        { path = '/',                 title = BK.name or 'LS Bank', description = T('bank.description'), keywords = Browser.words(T('bank.keywords')) },
        { path = '/transactions',     title = T('bank.page.transactions.title'), description = T('bank.page.transactions.description'), keywords = Browser.words(T('bank.page.transactions.keywords')) },
        { path = '/pay',              title = T('bank.page.pay.title'),          description = T('bank.page.pay.description'),          keywords = Browser.words(T('bank.page.pay.keywords')) },
        { path = '/standing-orders',  title = T('bank.page.standing.title'),     description = T('bank.page.standing.description'),     keywords = Browser.words(T('bank.page.standing.keywords')) },
        { path = '/invoices',         title = T('bank.page.invoices.title'),     description = T('bank.page.invoices.description'),     keywords = Browser.words(T('bank.page.invoices.keywords')) },
        { path = '/account',          title = T('bank.page.account.title'),      description = T('bank.page.account.description'),      keywords = Browser.words(T('bank.page.account.keywords')) },
    },
})

-- ---------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------
local function cut(s, n)
    s = tostring(s or '')
    local len = utf8.len(s)
    if not len then return (s:gsub('[\128-\255]', ''):sub(1, n)) end
    if len <= n then return s end
    return s:sub(1, (utf8.offset(s, n + 1) or (#s + 1)) - 1)
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local function digits(s) return (tostring(s or ''):gsub('%D', '')) end
local function line(s, n) return cut(trim((tostring(s or ''):gsub('[%c]', ' '))), n) end   -- one clean line of text
local function whole(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return math.floor(n)
end
local function money(n)
    local s = tostring(math.floor(math.abs(tonumber(n) or 0)))
    local k
    repeat s, k = s:gsub('^(%d+)(%d%d%d)', '%1,%2') until k == 0
    return (Config.currency or '£') .. s
end
local function account() return Config.account or 'bank' end

local function phone(fn, ...)
    local args = { ... }
    local ok, res = pcall(function() return exports['sd-phone'][fn](exports['sd-phone'], table.unpack(args)) end)
    if ok then return res end
    return nil
end

local function numberOf(cid) return digits(phone('getPhoneNumberByIdentifier', cid, true)) end
local function cidOfNumber(number)
    number = digits(number)
    if number == '' then return nil end
    local cid = phone('getIdentifierByNumber', number)
    if type(cid) == 'string' and cid ~= '' then return cid end
    return nil
end

local walletUp = false
MySQL.ready(function()
    local ok = pcall(function()
        MySQL.query.await('SELECT 1 FROM phone_bank_transactions LIMIT 1')
        MySQL.query.await('SELECT 1 FROM phone_bank_standing_orders LIMIT 1')
        MySQL.query.await('SELECT 1 FROM phone_service_invoices LIMIT 1')
    end)
    walletUp = ok
    if not ok then log("^1sd-phone's Wallet tables were not found^0, so LS Bank will say it is not available. Start sd-phone before as-browser once so it can create them.") end
end)

--- The signed-in character, or nil plus a message.
local function who(src)
    if not walletUp then return nil, T('bank.err.unavailable') end
    local cid = Bridge.getIdentifier(src)
    if not cid or cid == '' then return nil, T('bank.err.generic') end
    return cid
end

local limits = {}
local limitCount = 0
--- true while the character is inside the allowance for `key` (a rolling window in milliseconds).
local function allow(cid, key, windowMs, max)
    local t = GetGameTimer()
    local k = cid .. ':' .. key
    local e = limits[k]
    if not e or t - e.t > windowMs then
        if not e then limitCount = limitCount + 1 end
        e = { t = t, n = 0 }
        limits[k] = e
    end
    e.n = e.n + 1
    if limitCount > 4000 then limits, limitCount = {}, 0 end
    return e.n <= max
end

local busy = {}
local function lock(cid)
    if busy[cid] then return false end
    busy[cid] = true
    SetTimeout(15000, function() busy[cid] = nil end)
    return true
end
local function unlock(cid) busy[cid] = nil end

--- A number for the account page. Made up from the character id, so it never changes and never needs storing.
local function accountNumber(cid)
    local h = 5381
    for i = 1, #cid do h = (h * 33 + cid:byte(i)) % 4294967296 end
    return ('%08d'):format(10000000 + h % 90000000)
end

local CARD_PAIRS = { emerald = true, crimson = true, cobalt = true, navy = true, bronze = true, graphite = true, teal = true, violet = true,
    slate = true, amber = true, rose = true, midnight = true, mint = true, burgundy = true }
local BANK_COLOUR = { fleeca = 'emerald', maze = 'crimson', lombank = 'cobalt', pacific = 'navy', blaine = 'bronze' }
local function cardColour(cid)
    local colour
    pcall(function()
        local row = MySQL.single.await('SELECT card_style FROM phone_settings WHERE citizenid = ? LIMIT 1', { cid })
        local st = row and row.card_style and row.card_style ~= '' and json.decode(row.card_style)
        if type(st) == 'table' then
            colour = CARD_PAIRS[st.color] and st.color or BANK_COLOUR[st.bank]
        end
    end)
    return colour or 'emerald'
end

--- A statement row for the page.
local function txOut(r)
    return {
        id = r.id, label = r.label or '', amount = tonumber(r.amount) or 0, category = r.category or 'transfer',
        at = tonumber(r.created_at) or 0, peer = digits(r.counterparty),
    }
end

--- Writes a line in the phone's Wallet for a movement this site just made. With sd-phone's own logger running (qbx / qb),
--- the money movement has already produced a bare row a moment ago: this finds it and adds the details, so the statement
--- shows one row, exactly as it does for a payment made in the phone. When there is no such row it adds one itself.
local function walletLine(cid, label, amount, category, peer)
    label, peer = cut(label, 120), digits(peer)
    if BK.walletLog ~= 'own' then
        local ok, done = pcall(function()
            local row = MySQL.single.await(
                'SELECT id FROM phone_bank_transactions WHERE citizenid = ? AND amount = ? AND counterparty IS NULL AND created_at >= ? ORDER BY id DESC LIMIT 1',
                { cid, amount, now() - 10 })
            if not row then return false end
            MySQL.update.await('UPDATE phone_bank_transactions SET label = ?, category = ?, counterparty = ? WHERE id = ?',
                { label, category, peer ~= '' and peer or nil, row.id })
            return true
        end)
        if ok and done then return end
    end
    phone('addBankTransaction', cid, { label = label, amount = amount, category = category, counterparty = peer ~= '' and peer or nil })
end

--- Credits a character who is not in the city, by writing their framework bank account directly (like the phone does).
local function creditOffline(cid, amount)
    local fw = Bridge.framework
    local ok, n
    if fw == 'qb' or fw == 'qbx' then
        ok, n = pcall(MySQL.update.await, "UPDATE players SET money = JSON_SET(money, '$.bank', JSON_EXTRACT(money, '$.bank') + ?) WHERE citizenid = ?", { amount, cid })
    elseif fw == 'esx' then
        ok, n = pcall(MySQL.update.await, "UPDATE users SET accounts = JSON_SET(accounts, '$.bank', JSON_EXTRACT(accounts, '$.bank') + ?) WHERE identifier = ?", { amount, cid })
    end
    return ok == true and (tonumber(n) or 0) > 0
end

local function banner(rsrc, body)
    if not rsrc then return end
    TriggerClientEvent('sd-phone:client:notify', rsrc, {
        app = 'bank', appId = 'bank', quietInApp = true, time = 'now',
        titleKey = 'banking.bankTitle', title = 'Bank', body = body,
    })
end

--- Who a payment or invoice is for: a phone number, or the server id of someone online.
--- Returns cid, number, source (source is nil when they are not online) or nil plus a message.
local function recipient(src, cid, data)
    local myNumber = numberOf(cid)
    local rawId = data.serverId
    if rawId ~= nil and trim(rawId) ~= '' then
        local sid = whole(rawId)
        if not sid or sid <= 0 or sid > 65535 then return nil, T('bank.err.noPlayer') end
        if sid == src then return nil, T('bank.err.self') end
        local rcid = Bridge.getIdentifier(sid)
        if not rcid or rcid == '' then return nil, T('bank.err.noPlayer') end
        if rcid == cid then return nil, T('bank.err.self') end
        return rcid, numberOf(rcid), sid
    end
    local number = digits(data.number)
    if number == '' then return nil, T('bank.err.needNumber') end
    if number == myNumber then return nil, T('bank.err.self') end
    local rcid = cidOfNumber(number)
    if not rcid then return nil, T('bank.err.noOwner') end
    if rcid == cid then return nil, T('bank.err.self') end
    return rcid, number, Bridge.findSource(rcid)
end

-- ---------------------------------------------------------------------------------------------
-- overview and statement
-- ---------------------------------------------------------------------------------------------
local function pendingInvoices(cid)
    local personalOn = sub('invoices').enabled ~= false
    local rows = MySQL.query.await("SELECT job FROM phone_service_invoices WHERE target_cid = ? AND status = 'pending'", { cid }) or {}
    local n = 0
    for _, r in ipairs(rows) do
        if (r.job == nil and personalOn) or (r.job ~= nil and BK.businessInvoices ~= false) then n = n + 1 end
    end
    return n
end

local function pageOfTx(cid, o)
    local per = math.max(5, math.min(100, math.floor(cfgNum('perPage', 25))))
    local where, params = { 'citizenid = ?' }, { cid }
    if o.dir == 'in' then where[#where + 1] = 'amount > 0' elseif o.dir == 'out' then where[#where + 1] = 'amount < 0' end
    local q = trim(o.q):gsub('[%%_\\]', ''):sub(1, 40)
    if q ~= '' then
        where[#where + 1] = '(label LIKE ? OR counterparty LIKE ?)'
        params[#params + 1] = '%' .. q .. '%'
        params[#params + 1] = '%' .. (digits(q) ~= '' and digits(q) or q) .. '%'
    end
    local offset = math.max(0, math.min(2000, whole(o.offset) or 0))
    params[#params + 1] = per + 1
    params[#params + 1] = offset
    local rows = MySQL.query.await('SELECT * FROM phone_bank_transactions WHERE ' .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT ? OFFSET ?', params) or {}
    local more = #rows > per
    local out = {}
    for i = 1, math.min(per, #rows) do out[#out + 1] = txOut(rows[i]) end
    return out, more, per
end

Browser.handler('bank', 'init', function(src)
    local cid, err = who(src)
    if not cid then return nil, err end
    local number = numberOf(cid)
    local since = now() - 30 * 86400
    local sums = MySQL.single.await(
        'SELECT SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS money_in, SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS money_out FROM phone_bank_transactions WHERE citizenid = ? AND created_at >= ?',
        { cid, since }) or {}
    local recent = pageOfTx(cid, {})
    local so, inv = sub('standingOrders'), sub('invoices')
    return {
        name = BK.name, tagline = BK.tagline, footer = BK.footer or {}, currency = Config.currency, now = now(),
        me = {
            name = Bridge.getCharacterName(src), number = number, account = accountNumber(cid), sortCode = BK.sortCode or '20-45-71',
            balance = Bridge.getBalance(src, account()), cash = Bridge.getBalance(src, 'cash'), card = cardColour(cid),
        },
        month = { ['in'] = tonumber(sums.money_in) or 0, out = tonumber(sums.money_out) or 0 },
        recent = recent,
        pendingInvoices = pendingInvoices(cid),
        features = {
            anonymous = BK.allowAnonymous ~= false, standing = so.enabled ~= false,
            invoices = inv.enabled ~= false, business = BK.businessInvoices ~= false,
        },
        limits = {
            minSend = math.floor(cfgNum('minSend', 1)), maxSend = math.floor(cfgNum('maxSend', 100000000)),
            standingMax = math.floor(tonumber(so.maxActive) or 10), invoiceMin = math.floor(tonumber(inv.minAmount) or 1),
            invoiceMax = math.floor(tonumber(inv.maxAmount) or 1000000),
        },
    }
end)

Browser.handler('bank', 'balance', function(src)
    local cid, err = who(src)
    if not cid then return nil, err end
    return { balance = Bridge.getBalance(src, account()), cash = Bridge.getBalance(src, 'cash'), pendingInvoices = pendingInvoices(cid) }
end)

Browser.handler('bank', 'transactions', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    data = type(data) == 'table' and data or {}
    local rows, more, per = pageOfTx(cid, data)
    return { transactions = rows, more = more, per = per }
end)

--- People this character has paid, most recent first, for the "pay again" shortcuts.
Browser.handler('bank', 'payees', function(src)
    local cid, err = who(src)
    if not cid then return nil, err end
    local rows = MySQL.query.await(
        "SELECT counterparty, MAX(id) AS last_id FROM phone_bank_transactions WHERE citizenid = ? AND amount < 0 AND counterparty IS NOT NULL AND counterparty <> '' AND category = 'transfer' GROUP BY counterparty ORDER BY last_id DESC LIMIT 6",
        { cid }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { number = digits(r.counterparty) } end
    return { payees = out }
end)

-- ---------------------------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------------------------
Browser.handler('bank', 'pay', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    data = type(data) == 'table' and data or {}

    local amount = whole(data.amount)
    if not amount or amount < math.floor(cfgNum('minSend', 1)) then return nil, T('bank.err.amount') end
    if amount > math.floor(cfgNum('maxSend', 100000000)) then return nil, T('bank.err.tooLarge') end
    local note = line(data.note, 80)
    local anonymous = data.anonymous == true
    if anonymous and BK.allowAnonymous == false then return nil, T('bank.err.anonOff') end

    local rcid, number, rsrc = recipient(src, cid, data)
    if not rcid then return nil, number end
    if number == '' then return nil, T('bank.err.noOwner') end

    if not allow(cid, 'send', 60000, math.floor(cfgNum('sendPerMinute', 20))) or not allow(cid, 'send:' .. number, 60000, math.floor(cfgNum('sendPerPayee', 6))) then
        return nil, T('bank.err.tooMany')
    end
    if not lock(cid) then return nil, T('bank.err.busy') end
    local function done(...) unlock(cid); return ... end

    local balance = Bridge.getBalance(src, account())
    if balance < amount then return done(nil, T('bank.err.funds')) end
    if not rsrc and BK.allowOffline == false then return done(nil, T('bank.err.offline')) end

    local myNumber = numberOf(cid)
    local senderLabel = note ~= '' and note or ('Sent to %s'):format(number)
    local recvTitle = anonymous and 'Anonymous' or ('Received from %s'):format(myNumber)
    local senderPeer = anonymous and '' or myNumber

    if not Bridge.removeMoney(src, account(), amount, senderLabel) then return done(nil, T('bank.err.cantTake')) end
    walletLine(cid, senderLabel, -amount, 'transfer', number)

    local credited
    if rsrc then
        credited = Bridge.addMoney(rsrc, account(), amount, recvTitle)
        if credited then walletLine(rcid, recvTitle, amount, 'transfer', senderPeer) end
    else
        credited = creditOffline(rcid, amount)
        if credited then phone('addBankTransaction', rcid, { label = recvTitle, amount = amount, category = 'transfer', counterparty = senderPeer ~= '' and senderPeer or nil }) end
    end
    if not credited then
        Bridge.addMoney(src, account(), amount, 'Transfer refund')
        walletLine(cid, 'Transfer refund', amount, 'transfer', '')
        return done(nil, T('bank.err.cantReach'))
    end

    if rsrc then
        TriggerClientEvent('sd-phone:client:bankReceived', rsrc, { amount = amount, anonymous = anonymous, from = (not anonymous) and myNumber or nil })
        banner(rsrc, anonymous and ('Someone sent you %s'):format(money(amount)) or ('%s sent you %s'):format(myNumber, money(amount)))
    end

    return done({
        balance = Bridge.getBalance(src, account()), amount = amount, to = number, note = note, at = now(), online = rsrc ~= nil,
    })
end)

--- Checks the recipient before the review step, without moving anything.
Browser.handler('bank', 'check', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    data = type(data) == 'table' and data or {}
    local rcid, number, rsrc = recipient(src, cid, data)
    if not rcid then return nil, number end
    return { number = number, online = rsrc ~= nil, canPay = rsrc ~= nil or BK.allowOffline ~= false }
end)

-- ---------------------------------------------------------------------------------------------
-- standing orders (the phone runs them)
-- ---------------------------------------------------------------------------------------------
local INTERVALS = { daily = true, weekly = true, monthly = true }

local function orderList(cid)
    local rows = MySQL.query.await(
        'SELECT id, recipient, recipient_name, label, amount, run_interval AS every, next_run, active, last_run, last_status FROM phone_bank_standing_orders WHERE citizenid = ? ORDER BY active DESC, next_run ASC',
        { cid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, recipient = r.recipient, name = (r.recipient_name and r.recipient_name ~= '') and r.recipient_name or nil,
            label = r.label, amount = tonumber(r.amount) or 0, every = r.every, nextRun = tonumber(r.next_run) or 0,
            active = r.active == 1 or r.active == true, lastRun = r.last_run and tonumber(r.last_run) or nil, lastStatus = r.last_status,
        }
    end
    return out
end

local function activeOrders(cid)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM phone_bank_standing_orders WHERE citizenid = ? AND active = 1', { cid })) or 0
end

local function orderFields(data)
    local so = sub('standingOrders')
    if so.enabled == false then return nil, T('bank.err.standingOff') end
    local label = line(data.label, 40)
    if label == '' then return nil, T('bank.err.standingLabel') end
    local amount = whole(data.amount)
    if not amount or amount < math.floor(tonumber(so.minAmount) or 1) then return nil, T('bank.err.amount') end
    if amount > math.floor(tonumber(so.maxAmount) or 100000000) then return nil, T('bank.err.tooLarge') end
    local every = tostring(data.every or '')
    if not INTERVALS[every] then return nil, T('bank.err.standingEvery') end
    return { label = label, amount = amount, every = every }
end

Browser.handler('bank', 'standing', function(src)
    local cid, err = who(src)
    if not cid then return nil, err end
    return { orders = orderList(cid), max = math.floor(tonumber(sub('standingOrders').maxActive) or 10), enabled = sub('standingOrders').enabled ~= false }
end)

Browser.handler('bank', 'standingSave', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    data = type(data) == 'table' and data or {}
    local f, ferr = orderFields(data)
    if not f then return nil, ferr end
    local max = math.floor(tonumber(sub('standingOrders').maxActive) or 10)
    local id = whole(data.id) or 0
    local t = now()

    if id > 0 then
        local row = MySQL.single.await('SELECT id, active, next_run FROM phone_bank_standing_orders WHERE id = ? AND citizenid = ?', { id, cid })
        if not row then return nil, T('bank.err.standingGone') end
        local active = data.active ~= false
        local wasActive = row.active == 1 or row.active == true
        if active and not wasActive and activeOrders(cid) >= max then return nil, T('bank.err.standingMax', max) end
        local nextRun = math.floor(tonumber(row.next_run) or t)
        if active and nextRun <= t then nextRun = t + 60 end
        MySQL.update.await('UPDATE phone_bank_standing_orders SET label = ?, amount = ?, run_interval = ?, active = ?, next_run = ? WHERE id = ? AND citizenid = ?',
            { f.label, f.amount, f.every, active and 1 or 0, nextRun, id, cid })
        return { orders = orderList(cid) }
    end

    if not allow(cid, 'standing:create', 3000, 1) then return nil, T('bank.err.slow') end
    local number = digits(data.number)
    if number == '' then return nil, T('bank.err.needNumber') end
    if number == numberOf(cid) then return nil, T('bank.err.self') end
    local rcid = cidOfNumber(number)
    if not rcid then return nil, T('bank.err.noOwner') end
    if rcid == cid then return nil, T('bank.err.self') end
    if activeOrders(cid) >= max then return nil, T('bank.err.standingMax', max) end
    local name = line(data.name, 80)
    if name == '' then
        local rsrc = Bridge.findSource(rcid)
        name = rsrc and Bridge.getCharacterName(rsrc) or ''
    end
    local first = whole(data.firstRun) or 0
    if first <= t then first = t + 3600 end
    if first > t + 366 * 86400 then first = t + 366 * 86400 end
    MySQL.insert.await(
        'INSERT INTO phone_bank_standing_orders (citizenid, recipient, recipient_name, label, amount, run_interval, next_run, active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)',
        { cid, number, name ~= '' and name or nil, f.label, f.amount, f.every, first, t })
    return { orders = orderList(cid) }
end)

Browser.handler('bank', 'standingDelete', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    local id = whole(type(data) == 'table' and data.id) or 0
    local n = id > 0 and MySQL.update.await('DELETE FROM phone_bank_standing_orders WHERE id = ? AND citizenid = ?', { id, cid }) or 0
    if (tonumber(n) or 0) == 0 then return nil, T('bank.err.standingGone') end
    return { orders = orderList(cid) }
end)

-- ---------------------------------------------------------------------------------------------
-- invoices
-- ---------------------------------------------------------------------------------------------
local function code(id) return (tostring(id):gsub('^bill_', '')):sub(1, 6):upper() end
local function newInvoiceId()
    local chars, out = '0123456789abcdef', {}
    for i = 1, 16 do local k = math.random(1, #chars); out[i] = chars:sub(k, k) end
    return 'bill_' .. table.concat(out)
end

local function receivedOut(r)
    local personal = r.job == nil
    return {
        id = r.id, code = code(r.id), personal = personal,
        label = personal and '' or ((r.label and r.label ~= '') and r.label or tostring(r.job)),
        from = personal and digits(r.sender_number) or ((r.sender_name and r.sender_name ~= '') and r.sender_name or ''),
        amount = tonumber(r.amount) or 0, note = r.note or '', status = r.status or 'pending',
        at = tonumber(r.created_at) or 0, paidAt = r.paid_at and tonumber(r.paid_at) or nil,
    }
end
local function sentOut(r)
    return {
        id = r.id, code = code(r.id), to = digits(r.target_number), toName = (r.target_name and r.target_name ~= '') and r.target_name or '',
        amount = tonumber(r.amount) or 0, note = r.note or '', status = r.status or 'pending',
        at = tonumber(r.created_at) or 0, paidAt = r.paid_at and tonumber(r.paid_at) or nil,
    }
end

local function invoiceLists(cid)
    local inv = sub('invoices')
    local personalOn = inv.enabled ~= false
    local received, sent = {}, {}
    for _, r in ipairs(MySQL.query.await("SELECT * FROM phone_service_invoices WHERE target_cid = ? ORDER BY (status = 'pending') DESC, created_at DESC LIMIT 50", { cid }) or {}) do
        local personal = r.job == nil
        if (personal and personalOn) or (not personal and BK.businessInvoices ~= false) then received[#received + 1] = receivedOut(r) end
    end
    if personalOn then
        for _, r in ipairs(MySQL.query.await('SELECT * FROM phone_service_invoices WHERE job IS NULL AND sender_cid = ? ORDER BY created_at DESC LIMIT 50', { cid }) or {}) do
            sent[#sent + 1] = sentOut(r)
        end
    end
    return { received = received, sent = sent, personal = personalOn, business = BK.businessInvoices ~= false, max = math.floor(tonumber(inv.maxPending) or 10) }
end

Browser.handler('bank', 'invoices', function(src)
    local cid, err = who(src)
    if not cid then return nil, err end
    return invoiceLists(cid)
end)

Browser.handler('bank', 'invoiceCreate', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    local inv = sub('invoices')
    if inv.enabled == false then return nil, T('bank.err.invoicesOff') end
    data = type(data) == 'table' and data or {}
    local amount = whole(data.amount)
    if not amount or amount < math.floor(tonumber(inv.minAmount) or 1) then return nil, T('bank.err.amount') end
    if amount > math.floor(tonumber(inv.maxAmount) or 1000000) then return nil, T('bank.err.tooLarge') end
    local tcid, number, tsrc = recipient(src, cid, data)
    if not tcid then return nil, number end
    if number == '' then return nil, T('bank.err.noOwner') end

    local pending = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM phone_service_invoices WHERE job IS NULL AND sender_cid = ? AND status = 'pending'", { cid })) or 0
    if pending >= math.floor(tonumber(inv.maxPending) or 10) then return nil, T('bank.err.tooManyInvoices') end
    local toThem = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM phone_service_invoices WHERE job IS NULL AND sender_cid = ? AND target_cid = ? AND status = 'pending'", { cid, tcid })) or 0
    if toThem >= 8 then return nil, T('bank.err.theyHaveInvoices') end
    if not allow(cid, 'invoice:create', 3600000, 30) then return nil, T('bank.err.tooMany') end

    local note = line(data.note, 140)
    local myNumber = numberOf(cid)
    local targetName = tsrc and Bridge.getCharacterName(tsrc) or nil
    MySQL.insert.await(
        'INSERT INTO phone_service_invoices (id, job, label, sender_cid, sender_name, sender_number, target_cid, target_name, target_number, amount, note, status, created_at) VALUES (?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { newInvoiceId(), cid, Bridge.getCharacterName(src), myNumber, tcid, targetName, number, amount, note ~= '' and note or nil, 'pending', now() })

    if tsrc then
        banner(tsrc, ('%s sent you an invoice for %s.'):format(myNumber, money(amount)))
        TriggerClientEvent('sd-phone:client:services:invoices', tsrc, {})
    end
    return invoiceLists(cid)
end)

Browser.handler('bank', 'invoiceCancel', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    local id = tostring(type(data) == 'table' and data.id or '')
    local row = MySQL.single.await('SELECT * FROM phone_service_invoices WHERE id = ?', { id })
    if not row then return nil, T('bank.err.invoiceGone') end
    if row.job ~= nil or row.sender_cid ~= cid then return nil, T('bank.err.invoiceNotYours') end
    if MySQL.update.await("UPDATE phone_service_invoices SET status = 'cancelled' WHERE id = ? AND status = 'pending'", { id }) < 1 then return nil, T('bank.err.invoiceNotPending') end
    local tsrc = Bridge.findSource(row.target_cid)
    if tsrc then TriggerClientEvent('sd-phone:client:services:invoices', tsrc, {}) end
    return invoiceLists(cid)
end)

local function societyAccount(job)
    local f = Config.parts and Config.parts.accountFor
    return (type(f) == 'function' and f(job)) or job
end

Browser.handler('bank', 'invoicePay', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    local id = tostring(type(data) == 'table' and data.id or '')
    local inv = MySQL.single.await('SELECT * FROM phone_service_invoices WHERE id = ?', { id })
    if not inv then return nil, T('bank.err.invoiceGone') end
    if inv.target_cid ~= cid then return nil, T('bank.err.invoiceNotYours') end
    if inv.status ~= 'pending' then return nil, T('bank.err.invoiceNotPending') end
    local personal = inv.job == nil
    if personal and sub('invoices').enabled == false then return nil, T('bank.err.invoicesOff') end
    if not personal and BK.businessInvoices == false then return nil, T('bank.err.invoicesOff') end
    local amount = math.floor(tonumber(inv.amount) or 0)
    if amount <= 0 then return nil, T('bank.err.generic') end
    if not lock(cid) then return nil, T('bank.err.busy') end
    local function done(...) unlock(cid); return ... end

    if Bridge.getBalance(src, account()) < amount then return done(nil, T('bank.err.funds')) end

    -- pending -> paid first: only one of two racing payments can win, and it happens before any money moves
    if MySQL.update.await("UPDATE phone_service_invoices SET status = 'paid', paid_at = ? WHERE id = ? AND status = 'pending'", { now(), id }) < 1 then
        return done(nil, T('bank.err.invoiceNotPending'))
    end
    local function revert() MySQL.update.await("UPDATE phone_service_invoices SET status = 'pending', paid_at = NULL WHERE id = ? AND status = 'paid'", { id }) end

    local ref = code(id)
    if not Bridge.removeMoney(src, account(), amount, ('Invoice %s'):format(ref)) then revert(); return done(nil, T('bank.err.cantTake')) end
    walletLine(cid, ('Invoice Paid · %s'):format(ref), -amount, 'invoice', inv.sender_number)

    local viaSociety, commission, credited = false, 0, false
    if not personal and PartsBank and PartsBank.name and PartsBank.name() then
        local rate = tonumber((BK.businessCommission or {})[inv.job]) or 0
        if rate < 0 then rate = 0 elseif rate > 1 then rate = 1 end
        local share = math.floor(amount * rate)
        if share < 1 then share = 0 end
        credited = PartsBank.add(societyAccount(inv.job), amount - share, ('Invoice %s from %s'):format(ref, inv.sender_number or ''))
        viaSociety = credited
        if credited and share > 0 then
            local esrc = Bridge.findSource(inv.sender_cid)
            local paid
            if esrc then paid = Bridge.addMoney(esrc, account(), share, ('Commission · %s'):format(ref)) else paid = creditOffline(inv.sender_cid, share) end
            if paid then
                commission = share
                if esrc then walletLine(inv.sender_cid, ('Commission · %s'):format(ref), share, 'income', '')
                else phone('addBankTransaction', inv.sender_cid, { label = ('Commission · %s'):format(ref), amount = share, category = 'income' }) end
            else
                PartsBank.add(societyAccount(inv.job), share, ('Invoice %s from %s'):format(ref, inv.sender_number or ''))
            end
        end
    end
    if not credited then
        local ssrc = Bridge.findSource(inv.sender_cid)
        if ssrc then
            credited = Bridge.addMoney(ssrc, account(), amount, ('Invoice Paid · %s'):format(ref))
            if credited then walletLine(inv.sender_cid, ('Invoice Paid · %s'):format(ref), amount, 'invoice', '') end
        else
            credited = creditOffline(inv.sender_cid, amount)
            if credited then phone('addBankTransaction', inv.sender_cid, { label = ('Invoice Paid · %s'):format(ref), amount = amount, category = 'invoice' }) end
        end
        if credited == nil then credited = false end
    end
    if not credited then
        Bridge.addMoney(src, account(), amount, 'Invoice refund')
        walletLine(cid, 'Invoice refund', amount, 'transfer', '')
        revert()
        return done(nil, T('bank.err.cantReach'))
    end

    local ssrc = Bridge.findSource(inv.sender_cid)
    if ssrc then
        local body = ('%s paid your invoice for %s.'):format(personal and digits(inv.target_number) or (inv.target_name or 'A customer'), money(amount))
        if commission > 0 then body = body .. (' You earned %s commission.'):format(money(commission)) end
        banner(ssrc, body)
        if personal then TriggerClientEvent('sd-phone:client:services:invoices', ssrc, {}) end
    end
    local out = invoiceLists(cid)
    out.balance = Bridge.getBalance(src, account())
    out.paid = { code = ref, amount = amount }
    return done(out)
end)

-- ---------------------------------------------------------------------------------------------
-- printing (as-printer): invoices and the statement. The page only says which one; the text is built here from the database.
-- ---------------------------------------------------------------------------------------------
local function signed(n)
    n = tonumber(n) or 0
    return (n < 0 and '-' or '+') .. money(n)
end

--- data = { id, printer, colour, design, letterhead }: an invoice the character sent or received.
Browser.handler('bank', 'invoicePrint', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    data = type(data) == 'table' and data or {}
    if not allow(cid, 'print', 60000, 10) then return nil, T('bank.err.tooMany') end
    local r = MySQL.single.await('SELECT * FROM phone_service_invoices WHERE id = ?', { tostring(data.id or '') })
    if not r or (r.sender_cid ~= cid and r.target_cid ~= cid) then return nil, T('bank.err.invoiceGone') end
    local personal = r.job == nil
    local from = personal and ((r.sender_name and r.sender_name ~= '') and r.sender_name or digits(r.sender_number)) or ((r.label and r.label ~= '') and r.label or tostring(r.job))
    local to = (r.target_name and r.target_name ~= '') and r.target_name or digits(r.target_number)
    local status = r.status == 'paid' and T('print.statusPaid') or (r.status == 'cancelled' and T('print.statusCancelled') or T('print.statusPending'))
    local note = trim(r.note)
    return Browser.printDoc(src, 'invoice', {
        number = code(r.id), from = from, to = to, date = Browser.date(tonumber(r.created_at) or now()), status = status,
        items = { { desc = note ~= '' and note or T('print.invoiceLine'), qty = 1, amount = money(r.amount) } },
        total = money(r.amount),
    }, data)
end)

--- data = { dir, q, printer, colour, design, letterhead }: the transactions the page is showing (most recent 80).
Browser.handler('bank', 'statementPrint', function(src, data)
    local cid, err = who(src)
    if not cid then return nil, err end
    data = type(data) == 'table' and data or {}
    if not allow(cid, 'print', 60000, 10) then return nil, T('bank.err.tooMany') end
    local where, params = { 'citizenid = ?' }, { cid }
    if data.dir == 'in' then where[#where + 1] = 'amount > 0' elseif data.dir == 'out' then where[#where + 1] = 'amount < 0' end
    local q = trim(data.q):gsub('[%%_\\]', ''):sub(1, 40)
    if q ~= '' then
        where[#where + 1] = '(label LIKE ? OR counterparty LIKE ?)'
        params[#params + 1] = '%' .. q .. '%'
        params[#params + 1] = '%' .. (digits(q) ~= '' and digits(q) or q) .. '%'
    end
    local rows = MySQL.query.await('SELECT * FROM phone_bank_transactions WHERE ' .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT 80', params) or {}
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = { date = Browser.date(tonumber(r.created_at) or now()), label = cut(r.label or '', 60), amount = signed(r.amount) }
    end
    return Browser.printDoc(src, 'statement', {
        holder = Bridge.getCharacterName(src), sortCode = BK.sortCode or '20-45-71', account = accountNumber(cid),
        period = Browser.date(now()), balance = money(Bridge.getBalance(src, account())), rows = list,
    }, data)
end)
