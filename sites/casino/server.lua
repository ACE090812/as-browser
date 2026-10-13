-- Diamond Online: the casino website. Accounts, wallet and safety. The games are in server_games.lua, the maths in server_engine.lua,
-- the settings in sites/casino/config.lua.
--   casino_accounts  one account per character: login, balance, limits, settings
--   casino_tx        deposits, withdrawals and other money moves
--   casino_bets      one row per settled bet (wagered and paid), the bet log
--   casino_daily     house figures per day and game
--   casino_rounds    a game in progress (blackjack hand, crash round ...) so it survives a disconnect
--   casino_meta      jackpot pool and the on/off switch
Casino = Casino or {}
local C = Casino
local CFG = Config.casino or {}

local function log(fmt, ...) print(('^5[as-browser:casino]^0 ' .. fmt):format(...)) end

Browser.defineSite('casino', {
    title       = CFG.name or 'Diamond Online',
    description = T('casino.description'),
    keywords    = Browser.words(T('casino.keywords')),
    category    = T('casino.category'),
    icon        = '💎',
    color       = '#7c3aed',
    pages = {
        { path = '/',             title = CFG.name or 'Diamond Online', description = T('casino.description'), keywords = Browser.words(T('casino.keywords')) },
        { path = '/slots',        title = T('casino.page.slots.title'),     description = T('casino.page.slots.description'),     keywords = Browser.words(T('casino.page.slots.keywords')) },
        { path = '/blackjack',    title = T('casino.page.blackjack.title'), description = T('casino.page.blackjack.description'), keywords = Browser.words(T('casino.page.blackjack.keywords')) },
        { path = '/roulette',     title = T('casino.page.roulette.title'),  description = T('casino.page.roulette.description'),  keywords = Browser.words(T('casino.page.roulette.keywords')) },
        { path = '/crash',        title = T('casino.page.crash.title'),     description = T('casino.page.crash.description'),     keywords = Browser.words(T('casino.page.crash.keywords')) },
        { path = '/poker',        title = T('casino.page.poker.title'),     description = T('casino.page.poker.description'),     keywords = Browser.words(T('casino.page.poker.keywords')) },
        { path = '/baccarat',     title = T('casino.page.baccarat.title'),  description = T('casino.page.baccarat.description'),  keywords = Browser.words(T('casino.page.baccarat.keywords')) },
        { path = '/higher-lower', title = T('casino.page.hilo.title'),      description = T('casino.page.hilo.description'),      keywords = Browser.words(T('casino.page.hilo.keywords')) },
        { path = '/account',      title = T('casino.page.account.title'),   description = T('casino.page.account.description'),   keywords = Browser.words(T('casino.page.account.keywords')) },
    },
})

-- ---------------------------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------------------------
local floor = math.floor
local function now() return os.time() end
local function whole(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return floor(n)
end
local function line(s, n) s = tostring(s or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''); return s:sub(1, n) end
local function dayStart(t) local d = os.date('*t', t or now()); d.hour, d.min, d.sec = 0, 0, 0; return os.time(d) end
local function today() return os.date('%Y-%m-%d') end
C.whole, C.now, C.today = whole, now, today

-- SHA-256 (Lua 5.4 integers). The constants are worked out from the primes at load time, so there is no table to mistype.
local K, H0 = {}, {}
do
    local function primes(n) local p, c = {}, 2; while #p < n do local ok = true; for i = 1, #p do if c % p[i] == 0 then ok = false; break end end; if ok then p[#p + 1] = c end; c = c + 1 end; return p end
    local p = primes(64)
    for i = 1, 64 do local x = p[i] ^ (1 / 3); K[i] = floor((x - floor(x)) * 4294967296) end
    for i = 1, 8 do local x = p[i] ^ 0.5; H0[i] = floor((x - floor(x)) * 4294967296) end
end
local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xffffffff end
local function sha256(msg)
    local h = { table.unpack(H0) }
    local len = #msg
    msg = msg .. '\128' .. string.rep('\0', (55 - len) % 64) .. string.pack('>I8', len * 8)
    for chunk = 1, #msg, 64 do
        local w = {}
        for i = 0, 15 do w[i] = string.unpack('>I4', msg, chunk + i * 4) end
        for i = 16, 63 do
            local s0 = rrot(w[i - 15], 7) ~ rrot(w[i - 15], 18) ~ (w[i - 15] >> 3)
            local s1 = rrot(w[i - 2], 17) ~ rrot(w[i - 2], 19) ~ (w[i - 2] >> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff
        end
        local a, b, c, d, e, f, g, hh = table.unpack(h)
        for i = 0, 63 do
            local S1 = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
            local ch = (e & f) ~ ((~e) & g)
            local t1 = (hh + S1 + ch + K[i + 1] + w[i]) & 0xffffffff
            local S0 = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local t2 = (S0 + maj) & 0xffffffff
            hh, g, f, e, d, c, b, a = g, f, e, (d + t1) & 0xffffffff, c, b, a, (t1 + t2) & 0xffffffff
        end
        h[1], h[2], h[3], h[4] = (h[1] + a) & 0xffffffff, (h[2] + b) & 0xffffffff, (h[3] + c) & 0xffffffff, (h[4] + d) & 0xffffffff
        h[5], h[6], h[7], h[8] = (h[5] + e) & 0xffffffff, (h[6] + f) & 0xffffffff, (h[7] + g) & 0xffffffff, (h[8] + hh) & 0xffffffff
    end
    return ('%08x%08x%08x%08x%08x%08x%08x%08x'):format(table.unpack(h))
end
C.sha256 = sha256

local function randomText(n)
    local chars, out = 'abcdef0123456789', {}
    for i = 1, n do local k = math.random(1, #chars); out[i] = chars:sub(k, k) end
    return table.concat(out)
end
local function hashPassword(pw, salt)
    local h = salt .. pw
    for _ = 1, 600 do h = sha256(h .. salt) end
    return h
end

--- Date of birth text -> age in whole years today, or nil when it cannot be read. Understands YYYY-MM-DD, DD/MM/YYYY and DD-MM-YYYY.
function C.ageOf(text)
    text = tostring(text or '')
    local y, m, d = text:match('^(%d%d%d%d)[-/](%d%d?)[-/](%d%d?)')
    if not y then d, m, y = text:match('^(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)') end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    local t = os.date('*t')
    local age = t.year - y
    if t.month < m or (t.month == m and t.day < d) then age = age - 1 end
    return age
end

-- ---------------------------------------------------------------------------------------------
-- database
-- ---------------------------------------------------------------------------------------------
local ready = false
local meta = { jackpot = tonumber((CFG.jackpot or {}).seed) or 10000, jackpotFrac = 0, open = true }

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS casino_accounts (
        cid VARCHAR(64) NOT NULL PRIMARY KEY, username VARCHAR(24) NOT NULL, pass VARCHAR(64) NOT NULL, salt VARCHAR(32) NOT NULL,
        name VARCHAR(80) NOT NULL DEFAULT '', balance BIGINT NOT NULL DEFAULT 0, status VARCHAR(12) NOT NULL DEFAULT 'active',
        daily_limit INT NOT NULL DEFAULT 2000, limit_next INT NULL, limit_next_at INT NULL,
        reminder INT NOT NULL DEFAULT 60, show_timer TINYINT NOT NULL DEFAULT 1, sound TINYINT NOT NULL DEFAULT 1, confirm_over INT NOT NULL DEFAULT 0,
        created INT NOT NULL DEFAULT 0, last_seen INT NOT NULL DEFAULT 0, UNIQUE KEY uq_user (username)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS casino_tx (
        id INT AUTO_INCREMENT PRIMARY KEY, cid VARCHAR(64) NOT NULL, kind VARCHAR(16) NOT NULL, amount BIGINT NOT NULL,
        balance BIGINT NOT NULL DEFAULT 0, at INT NOT NULL, KEY k_cid (cid, at), KEY k_kind (kind, at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS casino_bets (
        id INT AUTO_INCREMENT PRIMARY KEY, cid VARCHAR(64) NOT NULL, game VARCHAR(24) NOT NULL, wagered BIGINT NOT NULL, paid BIGINT NOT NULL,
        detail VARCHAR(255) NOT NULL DEFAULT '', at INT NOT NULL, KEY k_cid (cid, at), KEY k_game (game, at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS casino_daily (
        day DATE NOT NULL, game VARCHAR(24) NOT NULL, wagered BIGINT NOT NULL DEFAULT 0, paid BIGINT NOT NULL DEFAULT 0, bets INT NOT NULL DEFAULT 0,
        PRIMARY KEY (day, game)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS casino_rounds (
        cid VARCHAR(64) NOT NULL, game VARCHAR(24) NOT NULL, state TEXT NOT NULL, PRIMARY KEY (cid, game)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS casino_meta (k VARCHAR(24) NOT NULL PRIMARY KEY, v VARCHAR(64) NOT NULL)]])
    local rows = MySQL.query.await('SELECT k, v FROM casino_meta') or {}
    for _, r in ipairs(rows) do
        if r.k == 'jackpot' then meta.jackpot = tonumber(r.v) or meta.jackpot
        elseif r.k == 'open' then meta.open = r.v ~= '0' end
    end
    ready = true
end)

local function saveMeta(k, v)
    MySQL.update('INSERT INTO casino_meta (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { k, tostring(v) })
end

function C.isOpen() return ready and meta.open end
function C.setOpen(on) meta.open = on and true or false; saveMeta('open', on and '1' or '0') end
function C.jackpot() return floor(meta.jackpot) end
function C.addJackpot(bet)
    local f = (tonumber((CFG.jackpot or {}).contribution) or 0.01) * bet + meta.jackpotFrac
    local whole_ = floor(f); meta.jackpotFrac = f - whole_
    if whole_ > 0 then meta.jackpot = meta.jackpot + whole_; saveMeta('jackpot', meta.jackpot) end
end
function C.takeJackpot()
    local won = floor(meta.jackpot)
    meta.jackpot = tonumber((CFG.jackpot or {}).seed) or 10000; meta.jackpotFrac = 0
    saveMeta('jackpot', meta.jackpot)
    return won
end

-- ---------------------------------------------------------------------------------------------
-- accounts in memory
-- ---------------------------------------------------------------------------------------------
local accounts = {}    -- cid -> row (loaded when the character signs in, kept while they are online)
local sessions = {}    -- src -> { cid, start, wagered, won, seen }
local rounds = {}      -- cid -> game -> state
local fails = {}       -- cid -> { n, until }
local codes = {}       -- cid -> { code, expires, tries }
local lockedBusy = {}

local function loadAccount(cid)
    local a = MySQL.single.await('SELECT * FROM casino_accounts WHERE cid = ? LIMIT 1', { cid })
    return a
end

--- Apply a limit increase that has finished waiting.
local function settleLimit(a)
    if a.limit_next and a.limit_next_at and a.limit_next_at <= now() then
        a.daily_limit, a.limit_next, a.limit_next_at = a.limit_next, nil, nil
        MySQL.update('UPDATE casino_accounts SET daily_limit = ?, limit_next = NULL, limit_next_at = NULL WHERE cid = ?', { a.daily_limit, a.cid })
    end
end

local function depositedToday(cid)
    return tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM casino_tx WHERE cid = ? AND kind = ? AND at >= ?', { cid, 'deposit', dayStart() })) or 0
end

local function persistBalance(a)
    MySQL.update('UPDATE casino_accounts SET balance = ?, last_seen = ? WHERE cid = ?', { a.balance, now(), a.cid })
end

--- Changes a balance (positive or negative). Callers check the funds first.
function C.adjust(a, delta)
    a.balance = a.balance + delta
    persistBalance(a)
end

function C.tx(a, kind, amount)
    MySQL.insert('INSERT INTO casino_tx (cid, kind, amount, balance, at) VALUES (?, ?, ?, ?, ?)', { a.cid, kind, amount, a.balance, now() })
end

-- rounds ----------------------------------------------------------------------------------------
function C.roundGet(cid, game) return rounds[cid] and rounds[cid][game] end
function C.roundSet(cid, game, st)
    rounds[cid] = rounds[cid] or {}
    rounds[cid][game] = st
    MySQL.update('INSERT INTO casino_rounds (cid, game, state) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE state = VALUES(state)', { cid, game, json.encode(st) })
end
function C.roundClear(cid, game)
    if rounds[cid] then rounds[cid][game] = nil end
    MySQL.update('DELETE FROM casino_rounds WHERE cid = ? AND game = ?', { cid, game })
end
local function loadRounds(cid)
    rounds[cid] = {}
    local rows = MySQL.query.await('SELECT game, state FROM casino_rounds WHERE cid = ?', { cid }) or {}
    for _, r in ipairs(rows) do
        local ok, st = pcall(json.decode, r.state)
        if ok and type(st) == 'table' then rounds[cid][r.game] = st end
    end
end

-- ---------------------------------------------------------------------------------------------
-- the signed in player
-- ---------------------------------------------------------------------------------------------
--- Session and account for a request, or nil plus a message. `game` (optional) also checks that game is switched on.
function C.need(src, game)
    if not ready then return nil, T('casino.err.unavailable') end
    local s = sessions[src]
    if not s then return nil, T('casino.err.signin') end
    local a = accounts[s.cid]
    if not a or a.status == 'closed' then sessions[src] = nil; return nil, T('casino.err.signin') end
    local idle = tonumber(CFG.idleMinutes) or 0
    if idle > 0 and now() - s.seen > idle * 60 then sessions[src] = nil; return nil, T('casino.err.timedOut') end
    s.seen = now()
    if game then
        if not meta.open then return nil, T('casino.err.closed') end
        if a.status == 'frozen' then return nil, T('casino.err.frozen') end
        local g = (CFG.games or {})[game]
        if not g or g.enabled == false then return nil, T('casino.err.gameOff') end
    end
    return s, a
end

--- Runs fn(session, account) with the player's account locked so two requests cannot spend the same money.
function C.guard(src, game, fn)
    local s, a = C.need(src, game)
    if not s then return nil, a end
    if lockedBusy[s.cid] then return nil, T('casino.err.busy') end
    lockedBusy[s.cid] = true
    SetTimeout(10000, function() lockedBusy[s.cid] = nil end)
    local ok, r, e = pcall(fn, s, a)
    lockedBusy[s.cid] = nil
    if not ok then log('error in %s: %s', tostring(game), tostring(r)); return nil, T('casino.err.generic') end
    return r, e
end

--- Takes a stake off the balance. Returns true or nil plus a message.
function C.stake(a, amount)
    amount = whole(amount)
    if not amount or amount <= 0 then return nil, T('casino.err.badBet') end
    if a.balance < amount then return nil, T('casino.err.noFunds') end
    C.adjust(a, -amount)
    return true
end

local function money(n) local s = tostring(floor(math.abs(n))); local k; repeat s, k = s:gsub('^(%d+)(%d%d%d)', '%1,%2') until k == 0; return (Config.currency or '£') .. s end

local function hook(text)
    local url = tostring(CFG.webhook or '')
    if url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({ username = CFG.name or 'Diamond Online', content = text }), { ['Content-Type'] = 'application/json' })
end

--- Pays out a settled bet and writes the bet log. `wagered` and `paid` are the totals for the round (paid includes the stake coming back).
function C.settle(s, a, game, wagered, paid, detail)
    wagered, paid = whole(wagered) or 0, whole(paid) or 0
    if paid > 0 then C.adjust(a, paid) end
    s.wagered, s.won = s.wagered + wagered, s.won + paid
    MySQL.insert('INSERT INTO casino_bets (cid, game, wagered, paid, detail, at) VALUES (?, ?, ?, ?, ?, ?)', { a.cid, game, wagered, paid, line(detail, 255), now() })
    MySQL.update([[INSERT INTO casino_daily (day, game, wagered, paid, bets) VALUES (?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE wagered = wagered + VALUES(wagered), paid = paid + VALUES(paid), bets = bets + 1]], { today(), game, wagered, paid })
    if paid >= (tonumber(CFG.bigWin) or 25000) and paid - wagered >= (tonumber(CFG.bigWin) or 25000) / 2 then
        hook(('%s won %s on %s'):format(a.name, money(paid), game))
    end
end

-- ---------------------------------------------------------------------------------------------
-- what the page shows
-- ---------------------------------------------------------------------------------------------
local function gamesList()
    local out = {}
    for id, g in pairs(CFG.games or {}) do out[id] = g.enabled ~= false end
    return out
end

local function publicAccount(a, s)
    settleLimit(a)
    local used = a.depDay == today() and a.depUsed or nil
    if used == nil then used = depositedToday(a.cid); a.depDay, a.depUsed = today(), used end
    return {
        username = a.username, name = a.name, balance = a.balance, status = a.status,
        limit = a.daily_limit, limitUsed = used, limitNext = a.limit_next, limitNextAt = a.limit_next_at,
        reminder = a.reminder, showTimer = a.show_timer == 1, sound = a.sound == 1, confirmOver = a.confirm_over,
        session = { start = s.start, wagered = s.wagered, won = s.won },
    }
end

local function base()
    local g = CFG.games or {}
    return {
        name = CFG.name, tagline = CFG.tagline, open = C.isOpen(), jackpot = C.jackpot(), minAge = CFG.minAge or 18,
        games = gamesList(),
        bets = {
            slots = g.slots and g.slots.levels, jackpotMinBet = g.slots and g.slots.jackpotMinBet,
            blackjack = g.blackjack, roulette = g.roulette, crash = g.crash, poker = g.poker, baccarat = g.baccarat, hilo = g.hilo,
        },
        rules = { minDeposit = CFG.minDeposit, maxDeposit = CFG.maxDeposit, minLimit = CFG.minLimit, maxLimit = CFG.maxLimit, limitRaiseHours = CFG.limitRaiseHours,
                  reminderChoices = CFG.reminderChoices, crashRate = C.engine.crashRate },
        currency = Config.currency,
    }
end

local function openRounds(cid)
    local r = rounds[cid] or {}
    local out = {}
    for game in pairs(r) do out[#out + 1] = game end
    return out
end

Browser.handler('casino', 'state', function(src)
    local d = base()
    local s = sessions[src]
    local a = s and accounts[s.cid]
    if s and a then
        local ok = C.need(src)
        if ok then d.account = publicAccount(a, s); d.open_rounds = openRounds(a.cid) else sessions[src] = nil end
    end
    if not d.account then
        d.canSignUp = true
        local cid = Bridge.getIdentifier(src)
        if cid then
            local row = MySQL.single.await('SELECT username, status FROM casino_accounts WHERE cid = ? LIMIT 1', { cid })
            d.hasAccount = row ~= nil
            d.accountClosed = row ~= nil and row.status == 'closed'
            d.usernameHint = row and row.username or nil
        end
    end
    return d
end)

-- ---------------------------------------------------------------------------------------------
-- sign up, sign in, password
-- ---------------------------------------------------------------------------------------------
local function newSession(src, a)
    sessions[src] = { cid = a.cid, start = now(), wagered = 0, won = 0, seen = now() }
    accounts[a.cid] = a
    a.depDay = nil
    loadRounds(a.cid)
    MySQL.update('UPDATE casino_accounts SET last_seen = ? WHERE cid = ?', { now(), a.cid })
end

local function checkUsername(u)
    u = tostring(u or '')
    if #u < 3 or #u > 20 or not u:match('^[%w_%.]+$') then return nil, T('casino.err.username') end
    return u
end
local function checkPassword(p)
    p = tostring(p or '')
    if #p < 6 or #p > 60 then return nil, T('casino.err.password') end
    return p
end

Browser.handler('casino', 'signup', function(src, d)
    if not ready then return nil, T('casino.err.unavailable') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('casino.err.generic') end
    local existing = MySQL.single.await('SELECT status FROM casino_accounts WHERE cid = ? LIMIT 1', { cid })
    if existing then return nil, existing.status == 'closed' and T('casino.err.closedForever') or T('casino.err.hasAccount') end
    local username, e1 = checkUsername(d.username); if not username then return nil, e1 end
    local pw, e2 = checkPassword(d.password); if not pw then return nil, e2 end
    if tostring(d.confirmAge) ~= 'true' then return nil, T('casino.err.ageConfirm') end
    local dob = Bridge.getBirthdate(src)
    local age = dob and C.ageOf(dob) or nil
    if age == nil then
        if CFG.requireDob ~= false then return nil, T('casino.err.noDob') end
    elseif age < (tonumber(CFG.minAge) or 18) then
        return nil, T('casino.err.tooYoung', tonumber(CFG.minAge) or 18)
    end
    if MySQL.scalar.await('SELECT 1 FROM casino_accounts WHERE username = ? LIMIT 1', { username }) then return nil, T('casino.err.usernameTaken') end
    local salt = randomText(16)
    local a = {
        cid = cid, username = username, pass = hashPassword(pw, salt), salt = salt, name = Bridge.getCharacterName(src) or '', balance = 0, status = 'active',
        daily_limit = tonumber(CFG.defaultLimit) or 2000, reminder = tonumber(CFG.reminderDefault) or 60, show_timer = 1, sound = 1, confirm_over = 0,
        created = now(), last_seen = now(),
    }
    local ok = pcall(function()
        MySQL.insert.await([[INSERT INTO casino_accounts (cid, username, pass, salt, name, balance, status, daily_limit, reminder, show_timer, sound, confirm_over, created, last_seen)
            VALUES (?, ?, ?, ?, ?, 0, 'active', ?, ?, 1, 1, 0, ?, ?)]], { cid, username, a.pass, salt, a.name, a.daily_limit, a.reminder, a.created, a.last_seen })
    end)
    if not ok then return nil, T('casino.err.usernameTaken') end
    newSession(src, a)
    return { ok = true }
end)

Browser.handler('casino', 'signin', function(src, d)
    if not ready then return nil, T('casino.err.unavailable') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('casino.err.generic') end
    local f = fails[cid]
    if f and f.lockedUntil and f.lockedUntil > now() then return nil, T('casino.err.locked', math.ceil((f.lockedUntil - now()) / 60)) end
    local row = MySQL.single.await('SELECT * FROM casino_accounts WHERE username = ? LIMIT 1', { tostring(d.username or '') })
    local good = row and row.cid == cid and row.pass == hashPassword(tostring(d.password or ''), row.salt)
    if not good then
        f = f or { n = 0 }; f.n = f.n + 1
        if f.n >= (tonumber(CFG.maxFailedLogins) or 5) then f.lockedUntil = now() + (tonumber(CFG.lockMinutes) or 10) * 60; f.n = 0 end
        fails[cid] = f
        return nil, T('casino.err.wrongLogin')
    end
    fails[cid] = nil
    if row.status == 'closed' then return nil, T('casino.err.closedForever') end
    newSession(src, row)
    return { ok = true }
end)

Browser.handler('casino', 'signout', function(src)
    sessions[src] = nil
    return { ok = true }
end)

Browser.handler('casino', 'forgot', function(src, d)
    if not ready then return nil, T('casino.err.unavailable') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('casino.err.generic') end
    local row = MySQL.single.await('SELECT cid, username, status FROM casino_accounts WHERE username = ? LIMIT 1', { tostring(d.username or '') })
    -- always answer the same, so the page never confirms whether a username exists
    if row and row.cid == cid and row.status ~= 'closed' then
        if codes[cid] and codes[cid].sentAt and now() - codes[cid].sentAt < 60 then return nil, T('casino.err.codeWait') end
        local code = ('%06d'):format(math.random(0, 999999))
        codes[cid] = { code = code, expires = now() + 600, tries = 0, sentAt = now() }
        Bridge.sendPhoneMail(src, cid, { name = CFG.name or 'Diamond Online', email = 'noreply@diamondonline.co.uk' },
            T('casino.mail.subject'), T('casino.mail.body', code))
    end
    return { sent = true }
end)

Browser.handler('casino', 'reset', function(src, d)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('casino.err.generic') end
    local c = codes[cid]
    if not c or c.expires < now() then return nil, T('casino.err.codeBad') end
    c.tries = c.tries + 1
    if c.tries > 5 then codes[cid] = nil; return nil, T('casino.err.codeBad') end
    if tostring(d.code or '') ~= c.code then return nil, T('casino.err.codeBad') end
    local pw, e = checkPassword(d.password); if not pw then return nil, e end
    local row = MySQL.single.await('SELECT * FROM casino_accounts WHERE username = ? LIMIT 1', { tostring(d.username or '') })
    if not row or row.cid ~= cid or row.status == 'closed' then return nil, T('casino.err.codeBad') end
    local salt = randomText(16)
    MySQL.update.await('UPDATE casino_accounts SET pass = ?, salt = ? WHERE cid = ?', { hashPassword(pw, salt), salt, cid })
    codes[cid] = nil; fails[cid] = nil
    return { ok = true }
end)

Browser.handler('casino', 'password', function(src, d)
    local s, a = C.need(src); if not s then return nil, a end
    local row = loadAccount(a.cid)
    if not row or row.pass ~= hashPassword(tostring(d.old or ''), row.salt) then return nil, T('casino.err.wrongPassword') end
    local pw, e = checkPassword(d.new); if not pw then return nil, e end
    local salt = randomText(16)
    MySQL.update.await('UPDATE casino_accounts SET pass = ?, salt = ? WHERE cid = ?', { hashPassword(pw, salt), salt, a.cid })
    return { ok = true }
end)

-- ---------------------------------------------------------------------------------------------
-- money in and out (only ever the in-game bank account)
-- ---------------------------------------------------------------------------------------------
Browser.handler('casino', 'deposit', function(src, d)
    return C.guard(src, nil, function(s, a)
        if not meta.open then return nil, T('casino.err.closed') end
        if a.status == 'frozen' then return nil, T('casino.err.frozen') end
        local amount = whole(d.amount)
        if not amount or amount < (tonumber(CFG.minDeposit) or 1) then return nil, T('casino.err.minDeposit', money(CFG.minDeposit or 1)) end
        if amount > (tonumber(CFG.maxDeposit) or 100000) then return nil, T('casino.err.maxDeposit', money(CFG.maxDeposit or 100000)) end
        settleLimit(a)
        local used = a.depDay == today() and a.depUsed or depositedToday(a.cid)
        if used + amount > a.daily_limit then return nil, T('casino.err.limit', money(math.max(0, a.daily_limit - used))) end
        if not Bridge.removeMoney(src, Config.account or 'bank', amount, 'casino-deposit') then return nil, T('casino.err.bankFunds') end
        C.adjust(a, amount); C.tx(a, 'deposit', amount)
        a.depDay, a.depUsed = today(), used + amount
        return publicAccount(a, s)
    end)
end)

Browser.handler('casino', 'withdraw', function(src, d)
    return C.guard(src, nil, function(s, a)
        if a.status == 'frozen' and CFG.frozenCanWithdraw == false then return nil, T('casino.err.frozen') end
        if C.roundGet(a.cid, 'blackjack') or C.roundGet(a.cid, 'hilo') or C.roundGet(a.cid, 'poker') or C.roundGet(a.cid, 'crash') then return nil, T('casino.err.roundOpen') end
        local amount = whole(d.amount)
        if not amount or amount < (tonumber(CFG.minWithdraw) or 1) then return nil, T('casino.err.badAmount') end
        if amount > a.balance then return nil, T('casino.err.noFunds') end
        C.adjust(a, -amount)
        if not Bridge.addMoney(src, Config.account or 'bank', amount, 'casino-withdrawal') then
            C.adjust(a, amount)
            return nil, T('casino.err.generic')
        end
        C.tx(a, 'withdraw', -amount)
        return publicAccount(a, s)
    end)
end)

Browser.handler('casino', 'limit', function(src, d)
    local s, a = C.need(src); if not s then return nil, a end
    local amount = whole(d.amount)
    if not amount or amount < (tonumber(CFG.minLimit) or 1) or amount > (tonumber(CFG.maxLimit) or 50000) then
        return nil, T('casino.err.limitRange', money(CFG.minLimit or 1), money(CFG.maxLimit or 50000))
    end
    settleLimit(a)
    if amount <= a.daily_limit then
        a.daily_limit, a.limit_next, a.limit_next_at = amount, nil, nil
        MySQL.update('UPDATE casino_accounts SET daily_limit = ?, limit_next = NULL, limit_next_at = NULL WHERE cid = ?', { amount, a.cid })
    else
        a.limit_next, a.limit_next_at = amount, now() + (tonumber(CFG.limitRaiseHours) or 24) * 3600
        MySQL.update('UPDATE casino_accounts SET limit_next = ?, limit_next_at = ? WHERE cid = ?', { a.limit_next, a.limit_next_at, a.cid })
    end
    return publicAccount(a, s)
end)

Browser.handler('casino', 'settings', function(src, d)
    local s, a = C.need(src); if not s then return nil, a end
    if d.reminder ~= nil then
        local r = whole(d.reminder)
        local ok = false
        for _, v in ipairs(CFG.reminderChoices or { 0, 15, 30, 60, 120 }) do if v == r then ok = true end end
        if not ok then return nil, T('casino.err.badAmount') end
        a.reminder = r
    end
    if d.showTimer ~= nil then a.show_timer = d.showTimer and 1 or 0 end
    if d.sound ~= nil then a.sound = d.sound and 1 or 0 end
    if d.confirmOver ~= nil then local c = whole(d.confirmOver); if c and c >= 0 and c <= 1000000 then a.confirm_over = c end end
    MySQL.update('UPDATE casino_accounts SET reminder = ?, show_timer = ?, sound = ?, confirm_over = ? WHERE cid = ?', { a.reminder, a.show_timer, a.sound, a.confirm_over, a.cid })
    return publicAccount(a, s)
end)

Browser.handler('casino', 'session', function(src)
    local s, a = C.need(src); if not s then return nil, a end
    return { start = s.start, wagered = s.wagered, won = s.won, balance = a.balance }
end)

Browser.handler('casino', 'close', function(src, d)
    return C.guard(src, nil, function(s, a)
        local row = loadAccount(a.cid)
        if not row or row.pass ~= hashPassword(tostring(d.password or ''), row.salt) then return nil, T('casino.err.wrongPassword') end
        for _, g in ipairs({ 'blackjack', 'hilo', 'poker', 'crash' }) do if C.roundGet(a.cid, g) then return nil, T('casino.err.roundOpen') end end
        local out = a.balance
        if out > 0 then
            C.adjust(a, -out)
            if not Bridge.addMoney(src, Config.account or 'bank', out, 'casino-closing-balance') then C.adjust(a, out); return nil, T('casino.err.generic') end
            C.tx(a, 'withdraw', -out)
        end
        a.status = 'closed'
        MySQL.update('UPDATE casino_accounts SET status = ? WHERE cid = ?', { 'closed', a.cid })
        sessions[src] = nil
        return { closed = true, paidOut = out }
    end)
end)

-- history ---------------------------------------------------------------------------------------
Browser.handler('casino', 'history', function(src, d)
    local s, a = C.need(src); if not s then return nil, a end
    local page = math.max(0, whole(d.page) or 0)
    local per = 20
    if d.type == 'money' then
        local rows = MySQL.query.await('SELECT kind, amount, balance, at FROM casino_tx WHERE cid = ? ORDER BY id DESC LIMIT ? OFFSET ?', { a.cid, per + 1, page * per }) or {}
        local more = #rows > per; if more then rows[#rows] = nil end
        return { rows = rows, more = more }
    end
    local rows = MySQL.query.await('SELECT game, wagered, paid, detail, at FROM casino_bets WHERE cid = ? ORDER BY id DESC LIMIT ? OFFSET ?', { a.cid, per + 1, page * per }) or {}
    local more = #rows > per; if more then rows[#rows] = nil end
    return { rows = rows, more = more }
end)

--- Everything for the "copy my history" button: the last 500 lines of each, as CSV text.
Browser.handler('casino', 'export', function(src)
    local s, a = C.need(src); if not s then return nil, a end
    local out = { 'type,time,game_or_kind,wagered_or_amount,paid_or_balance' }
    local tx = MySQL.query.await('SELECT kind, amount, balance, at FROM casino_tx WHERE cid = ? ORDER BY id DESC LIMIT 500', { a.cid }) or {}
    for _, r in ipairs(tx) do out[#out + 1] = ('money,%s,%s,%d,%d'):format(os.date('%Y-%m-%d %H:%M', r.at), r.kind, r.amount, r.balance) end
    local bets = MySQL.query.await('SELECT game, wagered, paid, at FROM casino_bets WHERE cid = ? ORDER BY id DESC LIMIT 500', { a.cid }) or {}
    for _, r in ipairs(bets) do out[#out + 1] = ('bet,%s,%s,%d,%d'):format(os.date('%Y-%m-%d %H:%M', r.at), r.game, r.wagered, r.paid) end
    return { csv = table.concat(out, '\n') }
end)

AddEventHandler('playerDropped', function()
    local src = source
    local s = sessions[src]
    if s then
        local a = accounts[s.cid]
        if a then persistBalance(a) end
        sessions[src] = nil
        SetTimeout(5000, function() local still; for _, x in pairs(sessions) do if x.cid == s.cid then still = true end end; if not still then accounts[s.cid] = nil; rounds[s.cid] = nil end end)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- admin (called by as-computer's /pcadmin Casino tab, or any other resource, through the export)
-- ---------------------------------------------------------------------------------------------
local function dayRange() return today() end
exports('casinoAdmin', function(action, data)
    data = type(data) == 'table' and data or {}
    if not ready then return { ok = false, error = 'not ready' } end
    if action == 'overview' then
        local acc = MySQL.single.await('SELECT COUNT(*) AS n, COALESCE(SUM(balance), 0) AS held FROM casino_accounts WHERE status <> ?', { 'closed' }) or {}
        local games = MySQL.query.await('SELECT game, wagered, paid, bets FROM casino_daily WHERE day = ? ORDER BY game', { dayRange() }) or {}
        local net = 0
        for _, g in ipairs(games) do net = net + (tonumber(g.wagered) or 0) - (tonumber(g.paid) or 0) end
        return { ok = true, open = meta.open, accounts = tonumber(acc.n) or 0, held = tonumber(acc.held) or 0, houseToday = net, jackpot = C.jackpot(), games = games }
    elseif action == 'setOpen' then
        C.setOpen(data.open == true)
        return { ok = true, open = meta.open }
    elseif action == 'accounts' then
        local q = tostring(data.query or ''):gsub('[%%_]', '')
        local rows = MySQL.query.await('SELECT cid, username, name, balance, status, last_seen FROM casino_accounts WHERE username LIKE ? OR name LIKE ? ORDER BY last_seen DESC LIMIT 40', { '%' .. q .. '%', '%' .. q .. '%' }) or {}
        return { ok = true, rows = rows }
    elseif action == 'freeze' then
        local cid = tostring(data.cid or '')
        local status = data.frozen and 'frozen' or 'active'
        MySQL.update.await("UPDATE casino_accounts SET status = ? WHERE cid = ? AND status <> 'closed'", { status, cid })
        if accounts[cid] and accounts[cid].status ~= 'closed' then accounts[cid].status = status end
        return { ok = true, status = status }
    elseif action == 'bets' then
        local rows = MySQL.query.await([[SELECT b.id, b.game, b.wagered, b.paid, b.detail, b.at, a.username, a.name FROM casino_bets b LEFT JOIN casino_accounts a ON a.cid = b.cid
            WHERE (? = '' OR b.game = ?) AND (? = '' OR a.username LIKE ? OR a.name LIKE ?) ORDER BY b.id DESC LIMIT 60]],
            { tostring(data.game or ''), tostring(data.game or ''), tostring(data.query or ''), '%' .. tostring(data.query or ''):gsub('[%%_]', '') .. '%', '%' .. tostring(data.query or ''):gsub('[%%_]', '') .. '%' }) or {}
        return { ok = true, rows = rows }
    end
    return { ok = false, error = 'unknown action' }
end)
