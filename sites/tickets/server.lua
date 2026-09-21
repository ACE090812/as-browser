-- LS Tickets: events, tickets, check-in and refunds. See sites/tickets/config.lua.
--   browser_events          the events (created by organiser jobs on the site, or seeded from the config)
--   browser_tickets         one row per ticket (code, holder, used_at, void)
--   browser_ticket_refunds  refunds owed to players who were offline when an event was cancelled
local TK = Config.tickets or {}

local function log(fmt, ...) print(('^5[as-browser:tickets]^0 ' .. fmt):format(...)) end
local function now() return os.time() end
local function cfgNum(key, default) return tonumber(TK[key]) or default end

Browser.defineSite('tickets', {
    title       = TK.name or 'LS Tickets',
    description = T('tickets.description'),
    keywords    = Browser.words(T('tickets.keywords')),
    category    = T('tickets.category'),
    icon        = '🎟️',
    color       = '#db2777',
    pages = {
        { path = '/',          title = TK.name or 'LS Tickets', description = T('tickets.description'), keywords = Browser.words(T('tickets.keywords')) },
        { path = '/tickets',   title = T('tickets.page.mine.title'),     description = T('tickets.page.mine.description'),     keywords = Browser.words(T('tickets.page.mine.keywords')) },
        { path = '/organise',  title = T('tickets.page.organise.title'), description = T('tickets.page.organise.description'), keywords = Browser.words(T('tickets.page.organise.keywords')) },
    },
})

-- ---------------------------------------------------------------------------------------------
-- Database (utf8mb4: event titles and icons contain emoji)
-- ---------------------------------------------------------------------------------------------

local CHARSET = ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'

local seeded = false
MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_events (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ckey VARCHAR(64) NULL,
        title VARCHAR(80) NOT NULL,
        venue VARCHAR(80) NOT NULL DEFAULT '',
        description VARCHAR(1000) NOT NULL DEFAULT '',
        icon VARCHAR(16) NOT NULL DEFAULT '',
        category VARCHAR(24) NOT NULL DEFAULT 'other',
        job VARCHAR(48) NOT NULL DEFAULT '',
        organiser VARCHAR(80) NOT NULL DEFAULT '',
        creator_cid VARCHAR(64) NOT NULL DEFAULT '',
        starts_at INT NOT NULL,
        ends_at INT NOT NULL,
        price INT NOT NULL DEFAULT 0,
        capacity INT NOT NULL,
        sold INT NOT NULL DEFAULT 0,
        status VARCHAR(12) NOT NULL DEFAULT 'open',
        paid_out TINYINT NOT NULL DEFAULT 0,
        created_at INT NOT NULL,
        UNIQUE KEY uq_ckey (ckey),
        KEY idx_start (starts_at),
        KEY idx_job (job, status)
    )]] .. CHARSET)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_tickets (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_id INT NOT NULL,
        cid VARCHAR(64) NOT NULL,
        buyer_name VARCHAR(80) NOT NULL DEFAULT '',
        code VARCHAR(12) NOT NULL,
        price INT NOT NULL DEFAULT 0,
        bought_at INT NOT NULL,
        used_at INT NULL,
        void TINYINT NOT NULL DEFAULT 0,
        UNIQUE KEY uq_code (code),
        KEY idx_event (event_id),
        KEY idx_cid (cid, event_id)
    )]] .. CHARSET)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_ticket_refunds (
        id INT AUTO_INCREMENT PRIMARY KEY,
        cid VARCHAR(64) NOT NULL,
        amount INT NOT NULL,
        note VARCHAR(120) NOT NULL DEFAULT '',
        created_at INT NOT NULL,
        KEY idx_cid (cid)
    )]] .. CHARSET)
    seeded = true
end)

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

local CATS = {}
for _, c in ipairs(TK.categories or {}) do CATS[c.id] = c end

local function inList(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

--- 'YYYY-MM-DD HH:MM' or 'YYYY-MM-DDTHH:MM' (server local time) -> unix time, or nil.
local function parseTime(s)
    if type(s) ~= 'string' then return nil end
    local y, mo, d, h, mi = s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d)')
    if not y then return nil end
    y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
    if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 then return nil end
    return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = 0 })
end

--- Cuts to n characters without splitting a multi-byte character; strips control characters.
local function clean(s, n)
    s = tostring(s or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local len = utf8.len(s)
    if not len then return '' end
    if len > n then s = s:sub(1, (utf8.offset(s, n + 1) or (#s + 1)) - 1) end
    return s
end
local function cleanLong(s, n)
    s = tostring(s or ''):gsub('[\0-\8\11\12\14-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local len = utf8.len(s)
    if not len then return '' end
    if len > n then s = s:sub(1, (utf8.offset(s, n + 1) or (#s + 1)) - 1) end
    return s
end

local function whole(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    return math.max(lo, math.min(hi, v))
end

local function role(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil end
    local jg = Bridge.getJobGrade(src)
    local staff = jg ~= nil and inList(TK.staffJobs, jg.name)
    local organiser = jg ~= nil and inList(TK.organiserJobs, jg.name) and (tonumber(jg.grade) or 0) >= (tonumber(TK.organiserMinGrade) or 0)
    return { cid = cid, jg = jg, job = jg and jg.name or '', isOrganiser = organiser or staff, isStaff = staff }
end

local function accountOf(job)
    local f = TK.accountFor
    return (type(f) == 'function' and f(job)) or job
end

local ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function newCode()
    local t = {}
    for i = 1, 8 do
        local n = math.random(1, #ALPHABET)
        t[i] = ALPHABET:sub(n, n)
    end
    return table.concat(t, '', 1, 4) .. '-' .. table.concat(t, '', 5, 8)
end
local function normCode(s)
    return (tostring(s or ''):upper():gsub('[^A-Z0-9]', ''))
end
local function fmtCode(raw) return raw:sub(1, 4) .. '-' .. raw:sub(5, 8) end

local function credit(account, amount, note)
    if amount <= 0 then return true end
    if PartsBank and PartsBank.name and PartsBank.name() then return PartsBank.add(account, amount, note) ~= false end
    log('no society bank found, %d for %s was not paid out (%s)', amount, tostring(account), note)
    return false
end

-- Refunds owed to a character; paid the next time they use the site (or straight away when online).
local function payRefunds(src, cid)
    local rows = MySQL.query.await('SELECT id, amount FROM browser_ticket_refunds WHERE cid = ?', { cid }) or {}
    local total = 0
    for _, r in ipairs(rows) do
        -- claim the row first, so two requests can never pay the same refund twice
        local n = MySQL.update.await('DELETE FROM browser_ticket_refunds WHERE id = ?', { r.id })
        if n and n > 0 then
            if Bridge.addMoney(src, Config.account or 'bank', r.amount, T('tickets.refundNote')) then
                total = total + r.amount
            else
                MySQL.insert.await('INSERT INTO browser_ticket_refunds (cid, amount, note, created_at) VALUES (?, ?, ?, ?)', { cid, r.amount, 'retry', now() })
            end
        end
    end
    return total
end

local function eventRow(e, mine)
    return {
        id = e.id, title = e.title, venue = e.venue, description = e.description, icon = e.icon ~= '' and e.icon or (CATS[e.category] and CATS[e.category].icon) or '🎟️',
        category = e.category, organiser = e.organiser, startsAt = e.starts_at, endsAt = e.ends_at,
        price = e.price, capacity = e.capacity, left = math.max(0, e.capacity - e.sold), status = e.status,
        mine = mine and mine[e.id] or 0,
    }
end

-- ---------------------------------------------------------------------------------------------
-- Seed events from the config
-- ---------------------------------------------------------------------------------------------

CreateThread(function()
    while not seeded do Wait(200) end
    for _, ev in ipairs(TK.events or {}) do
        local key = type(ev.key) == 'string' and ev.key:sub(1, 64) or nil
        local starts = parseTime(ev.startsAt)
        if key and starts and starts > now() then
            local exists = MySQL.scalar.await('SELECT id FROM browser_events WHERE ckey = ?', { key })
            if not exists then
                local cat = CATS[ev.category] and ev.category or 'other'
                MySQL.insert.await(
                    'INSERT INTO browser_events (ckey, title, venue, description, icon, category, job, organiser, creator_cid, starts_at, ends_at, price, capacity, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    { key, clean(ev.title, 80), clean(ev.venue, 80), cleanLong(ev.description, 1000), clean(ev.icon, 8), cat, tostring(ev.job or ''):sub(1, 48),
                      clean(ev.organiser or ev.venue or '', 80), '', starts, starts + whole(ev.durationMinutes or 180, 15, 10080) * 60,
                      whole(ev.price, 0, 100000), whole(ev.capacity, 1, 5000), now() })
            end
        elseif key then
            log('config event "%s" was skipped (no valid future startsAt)', key)
        end
    end
end)

-- Takings are paid to the organiser's society once the event has ended (nothing is paid for a cancelled event).
CreateThread(function()
    while true do
        Wait(60000)
        if seeded then
            local rows = MySQL.query.await("SELECT id, title, job FROM browser_events WHERE status = 'open' AND paid_out = 0 AND ends_at < ?", { now() }) or {}
            for _, e in ipairs(rows) do
                local claimed = MySQL.update.await('UPDATE browser_events SET paid_out = 1 WHERE id = ? AND paid_out = 0', { e.id })
                if claimed and claimed > 0 then
                    local sum = MySQL.scalar.await('SELECT COALESCE(SUM(price), 0) FROM browser_tickets WHERE event_id = ? AND void = 0', { e.id }) or 0
                    if e.job ~= '' and sum > 0 then credit(accountOf(e.job), sum, ('%s: %s'):format(TK.name or 'Tickets', e.title)) end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Public pages
-- ---------------------------------------------------------------------------------------------

local function myTicketCounts(cid)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT event_id, COUNT(*) AS n FROM browser_tickets WHERE cid = ? AND void = 0 GROUP BY event_id', { cid }) or {}) do
        out[r.event_id] = r.n
    end
    return out
end

Browser.handler('tickets', 'init', function(src)
    local r = role(src)
    if not r then return nil, T('tickets.err.generic') end
    local refunded = payRefunds(src, r.cid)
    local since = now() - math.floor(cfgNum('historyDays', 3)) * 86400
    local rows = MySQL.query.await(
        "SELECT * FROM browser_events WHERE status = 'open' AND ends_at > ? ORDER BY starts_at ASC, id ASC LIMIT 100", { since }) or {}
    local mine = myTicketCounts(r.cid)
    local events = {}
    for _, e in ipairs(rows) do events[#events + 1] = eventRow(e, mine) end
    local cats = {}
    for _, c in ipairs(TK.categories or {}) do cats[#cats + 1] = { id = c.id, label = c.label, icon = c.icon } end
    return {
        name = TK.name, tagline = TK.tagline, footer = TK.footer or {},
        categories = cats, events = events, now = now(), refunded = refunded, currency = Config.currency,
        me = { canOrganise = r.isOrganiser, isStaff = r.isStaff, job = r.job },
        limits = { maxPerPerson = math.floor(cfgNum('maxPerPerson', 6)) },
    }
end)

Browser.handler('tickets', 'event', function(src, data)
    local r = role(src)
    if not r then return nil, T('tickets.err.generic') end
    local id = math.floor(tonumber(data and data.id) or 0)
    local e = MySQL.single.await('SELECT * FROM browser_events WHERE id = ?', { id })
    if not e then return nil, T('tickets.err.notFound') end
    return { event = eventRow(e, myTicketCounts(r.cid)), now = now() }
end)

local placing = {}

Browser.handler('tickets', 'buy', function(src, data)
    local r = role(src)
    if not r then return nil, T('tickets.err.generic') end
    if placing[r.cid] then return nil, T('tickets.err.busy') end
    local id = math.floor(tonumber(data and data.id) or 0)
    local qty = math.floor(tonumber(data and data.qty) or 0)
    local maxPer = math.floor(cfgNum('maxPerPerson', 6))
    if qty < 1 or qty > maxPer then return nil, T('tickets.err.qty', maxPer) end

    placing[r.cid] = true
    SetTimeout(15000, function() placing[r.cid] = nil end)
    local function done(...) placing[r.cid] = nil; return ... end

    local e = MySQL.single.await('SELECT * FROM browser_events WHERE id = ?', { id })
    if not e then return done(nil, T('tickets.err.notFound')) end
    if e.status ~= 'open' then return done(nil, T('tickets.err.cancelled')) end
    if e.ends_at <= now() then return done(nil, T('tickets.err.over')) end

    local have = MySQL.scalar.await('SELECT COUNT(*) FROM browser_tickets WHERE cid = ? AND event_id = ? AND void = 0', { r.cid, id }) or 0
    if have + qty > maxPer then return done(nil, T('tickets.err.limit', maxPer)) end

    -- reserve the seats first: this only succeeds while there is room, so two buyers can never oversell
    local reserved = MySQL.update.await(
        "UPDATE browser_events SET sold = sold + ? WHERE id = ? AND status = 'open' AND sold + ? <= capacity", { qty, id, qty })
    if not reserved or reserved < 1 then return done(nil, T('tickets.err.soldOut')) end
    local function release() MySQL.update.await('UPDATE browser_events SET sold = sold - ? WHERE id = ?', { qty, id }) end

    local total = e.price * qty
    if total > 0 and not Bridge.removeMoney(src, Config.account or 'bank', total, ('%s: %s'):format(TK.name or 'Tickets', e.title)) then
        release()
        return done(nil, T('tickets.err.funds', (Config.currency or '£') .. total))
    end

    local name = Bridge.getCharacterName(src) or ''
    local codes = {}
    for i = 1, qty do
        local inserted
        for _ = 1, 8 do
            local code = newCode()
            local ok, res = pcall(MySQL.insert.await, 'INSERT INTO browser_tickets (event_id, cid, buyer_name, code, price, bought_at) VALUES (?, ?, ?, ?, ?, ?)',
                { id, r.cid, name:sub(1, 80), code, e.price, now() })
            if ok and res then inserted = code break end
        end
        if not inserted then
            -- could not finish: void what was made, give the money back and release the seats
            for _, c in ipairs(codes) do MySQL.update.await('DELETE FROM browser_tickets WHERE code = ?', { c }) end
            Bridge.addMoney(src, Config.account or 'bank', total, T('tickets.refundNote'))
            release()
            return done(nil, T('tickets.err.generic'))
        end
        codes[#codes + 1] = inserted
    end
    return done({ codes = codes, total = total, title = e.title })
end)

Browser.handler('tickets', 'mine', function(src)
    local r = role(src)
    if not r then return nil, T('tickets.err.generic') end
    local refunded = payRefunds(src, r.cid)
    local rows = MySQL.query.await([[SELECT t.code, t.price, t.used_at, t.void, e.id AS event_id, e.title, e.venue, e.icon, e.category, e.starts_at, e.ends_at, e.status
        FROM browser_tickets t JOIN browser_events e ON e.id = t.event_id WHERE t.cid = ? AND t.void = 0
        ORDER BY e.starts_at DESC, t.id DESC LIMIT 100]], { r.cid }) or {}
    local out = {}
    for _, t in ipairs(rows) do
        out[#out + 1] = {
            code = t.code, price = t.price, used = t.used_at ~= nil, eventId = t.event_id, title = t.title, venue = t.venue,
            icon = (t.icon ~= '' and t.icon) or (CATS[t.category] and CATS[t.category].icon) or '🎟️',
            startsAt = t.starts_at, endsAt = t.ends_at, status = t.status,
        }
    end
    return { tickets = out, refunded = refunded, now = now() }
end)

-- ---------------------------------------------------------------------------------------------
-- Organisers
-- ---------------------------------------------------------------------------------------------

local function mayManage(r, e)
    return r.isStaff or (r.isOrganiser and e.job == r.job)
end

Browser.handler('tickets', 'organise', function(src)
    local r = role(src)
    if not (r and r.isOrganiser) then return nil, T('tickets.err.notOrganiser') end
    local rows
    if r.isStaff then
        rows = MySQL.query.await('SELECT * FROM browser_events ORDER BY starts_at DESC LIMIT 60') or {}
    else
        rows = MySQL.query.await('SELECT * FROM browser_events WHERE job = ? ORDER BY starts_at DESC LIMIT 60', { r.job }) or {}
    end
    local out = {}
    for _, e in ipairs(rows) do
        local row = eventRow(e)
        row.sold = e.sold
        row.checkedIn = MySQL.scalar.await('SELECT COUNT(*) FROM browser_tickets WHERE event_id = ? AND void = 0 AND used_at IS NOT NULL', { e.id }) or 0
        row.revenue = e.price * e.sold
        row.paidOut = e.paid_out == 1
        out[#out + 1] = row
    end
    return { events = out, now = now(), job = r.jg and r.jg.label or r.job }
end)

Browser.handler('tickets', 'create', function(src, data)
    local r = role(src)
    if not (r and r.isOrganiser) then return nil, T('tickets.err.notOrganiser') end
    data = type(data) == 'table' and data or {}

    local title = clean(data.title, 80)
    if #title < 3 then return nil, T('tickets.err.title') end
    local venue = clean(data.venue, 80)
    if venue == '' then return nil, T('tickets.err.venue') end
    local starts = parseTime(data.startsAt)
    local lead = math.floor(cfgNum('minLeadMinutes', 10)) * 60
    if not starts or starts < now() + lead then return nil, T('tickets.err.start', math.floor(cfgNum('minLeadMinutes', 10))) end
    if starts > now() + math.floor(cfgNum('maxDaysAhead', 60)) * 86400 then return nil, T('tickets.err.tooFar', math.floor(cfgNum('maxDaysAhead', 60))) end
    local dur = whole(data.durationMinutes, 15, math.floor(cfgNum('maxDurationMinutes', 720)))
    local price = whole(data.price, math.floor(cfgNum('minPrice', 0)), math.floor(cfgNum('maxPrice', 5000)))
    local capacity = whole(data.capacity, 1, math.floor(cfgNum('maxCapacity', 500)))
    local cat = CATS[tostring(data.category or '')] and data.category or 'other'

    local jobName = r.job
    local active = MySQL.scalar.await("SELECT COUNT(*) FROM browser_events WHERE job = ? AND status = 'open' AND ends_at > ?", { jobName, now() }) or 0
    if active >= math.floor(cfgNum('maxActivePerJob', 5)) then return nil, T('tickets.err.tooMany', math.floor(cfgNum('maxActivePerJob', 5))) end

    local id = MySQL.insert.await(
        'INSERT INTO browser_events (title, venue, description, icon, category, job, organiser, creator_cid, starts_at, ends_at, price, capacity, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { title, venue, cleanLong(data.description, 1000), clean(data.icon, 8), cat, jobName, clean(r.jg and r.jg.label or jobName, 80), r.cid,
          starts, starts + dur * 60, price, capacity, now() })
    if not id then return nil, T('tickets.err.generic') end
    return { id = id }
end)

Browser.handler('tickets', 'cancel', function(src, data)
    local r = role(src)
    if not (r and r.isOrganiser) then return nil, T('tickets.err.notOrganiser') end
    local id = math.floor(tonumber(data and data.id) or 0)
    local e = MySQL.single.await('SELECT * FROM browser_events WHERE id = ?', { id })
    if not e or not mayManage(r, e) then return nil, T('tickets.err.notFound') end
    if e.status ~= 'open' then return nil, T('tickets.err.cancelled') end

    -- flip the status first (only once), so a second click cannot refund twice
    local n = MySQL.update.await("UPDATE browser_events SET status = 'cancelled' WHERE id = ? AND status = 'open'", { id })
    if not n or n < 1 then return nil, T('tickets.err.cancelled') end

    -- Money is held until the event ends, so it is refunded from what buyers paid: one refund row per buyer.
    local rows = MySQL.query.await('SELECT cid, SUM(price) AS amount FROM browser_tickets WHERE event_id = ? AND void = 0 GROUP BY cid', { id }) or {}
    MySQL.update.await('UPDATE browser_tickets SET void = 1 WHERE event_id = ?', { id })
    local refunded = 0
    for _, row in ipairs(rows) do
        if row.amount and row.amount > 0 then
            MySQL.insert.await('INSERT INTO browser_ticket_refunds (cid, amount, note, created_at) VALUES (?, ?, ?, ?)', { row.cid, row.amount, e.title:sub(1, 100), now() })
            refunded = refunded + row.amount
            local online = Bridge.findSource(row.cid)
            if online then payRefunds(online, row.cid) end
        end
    end
    return { refunded = refunded, holders = #rows }
end)

Browser.handler('tickets', 'checkin', function(src, data)
    local r = role(src)
    if not (r and r.isOrganiser) then return nil, T('tickets.err.notOrganiser') end
    local raw = normCode(data and data.code)
    if #raw ~= 8 then return nil, T('tickets.err.badCode') end
    local code = fmtCode(raw)
    local t = MySQL.single.await([[SELECT t.id, t.buyer_name, t.used_at, t.void, e.id AS event_id, e.title, e.job, e.status, e.ends_at
        FROM browser_tickets t JOIN browser_events e ON e.id = t.event_id WHERE t.code = ?]], { code })
    if not t then return nil, T('tickets.err.noTicket') end
    if not mayManage(r, { job = t.job }) then return nil, T('tickets.err.otherEvent') end
    if t.void == 1 or t.status ~= 'open' then return nil, T('tickets.err.voidTicket') end
    if t.used_at then return nil, T('tickets.err.used', Browser.datetime(t.used_at)) end
    -- claim it: only one check-in can win, even if two door staff scan at once
    local n = MySQL.update.await('UPDATE browser_tickets SET used_at = ? WHERE id = ? AND used_at IS NULL AND void = 0', { now(), t.id })
    if not n or n < 1 then return nil, T('tickets.err.used', Browser.datetime(now())) end
    local inside = MySQL.scalar.await('SELECT COUNT(*) FROM browser_tickets WHERE event_id = ? AND used_at IS NOT NULL AND void = 0', { t.event_id }) or 0
    return { title = t.title, holder = t.buyer_name, inside = inside }
end)
