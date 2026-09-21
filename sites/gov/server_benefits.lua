-- Benefits on the government site. The player fills in a short form; their answers decide their rate
-- (Config.gov.benefits.rates). While they are online and still have a qualifying job
-- (Config.gov.benefits.jobs) they are paid that rate into their bank every `intervalMinutes`.
-- Taking a job pauses payments, losing it starts them again. Stopping the claim ends it.
--
-- The rate is always worked out here on the server from the answers, never taken from the page.
local B = Config.gov.benefits
if not B or B.enabled == false or Config.gov.scripts and Config.gov.scripts.benefits == false then return end
local R = B.rates

local function now() return os.time() end
local function log(fmt, ...) print(('^5[as-browser]^0 benefits: ' .. fmt):format(...)) end

local function intervalSeconds() return math.max(60, math.floor((tonumber(B.intervalMinutes) or 60) * 60)) end

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_benefits (
        citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
        status VARCHAR(10) NOT NULL DEFAULT 'active',
        claimed_at INT NOT NULL,
        stopped_at INT NULL,
        progress INT NOT NULL DEFAULT 0,
        last_paid_at INT NULL,
        payments INT NOT NULL DEFAULT 0,
        total_paid INT NOT NULL DEFAULT 0
    )]])
    MySQL.query('ALTER TABLE browser_benefits ADD COLUMN IF NOT EXISTS rate INT NOT NULL DEFAULT 0')
    MySQL.query('ALTER TABLE browser_benefits ADD COLUMN IF NOT EXISTS answers VARCHAR(400) NULL')
end)

local function rowOf(cid)
    return MySQL.single.await('SELECT * FROM browser_benefits WHERE citizenid = ?', { cid })
end

local function qualifies(src)
    local job = Bridge.getJob(src)
    if not job then return false, nil end
    for _, name in ipairs(B.jobs or {}) do
        if name == job.name then return true, job end
    end
    return false, job
end

local function discordLog(title, color, fields)
    if type(B.webhook) ~= 'string' or not B.webhook:find('^https://') then return end
    local out = {}
    for _, f in ipairs(fields) do
        out[#out + 1] = { name = f[1], value = tostring(f[2]):gsub('@', '@\226\128\139'):sub(1, 200), inline = true }
    end
    PerformHttpRequest(B.webhook, function() end, 'POST', json.encode({
        embeds = { { title = title, color = color, fields = out, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'), footer = { text = 'as-browser benefits' } } },
        allowed_mentions = { parse = {} },
    }), { ['Content-Type'] = 'application/json' })
end

-- ---------------------------------------------------------------------------------------------
-- The form: answers -> rate
-- ---------------------------------------------------------------------------------------------

local HOUSING_ORDER = { 'rent', 'own', 'family', 'homeless' }
local HOUSING_OK = { rent = true, own = true, family = true, homeless = true }

local function housingLabel(id)
    if id == 'rent' then return T('gov.benefits.housing.rent') end
    if id == 'own' then return T('gov.benefits.housing.own') end
    if id == 'family' then return T('gov.benefits.housing.family') end
    if id == 'homeless' then return T('gov.benefits.housing.homeless') end
end

local function housingOptions()
    local out = {}
    for _, id in ipairs(HOUSING_ORDER) do
        if R.housing and R.housing[id] ~= nil then out[#out + 1] = { id = id, label = housingLabel(id) } end
    end
    return out
end

--- Checks the answers and works out the rate. Returns { rate, lines = { { label, amount } }, answers } or nil, reason.
local function assess(a)
    if type(a) ~= 'table' then return nil, T('gov.benefits.err.fillIn') end
    if a.age ~= 'age18to24' and a.age ~= 'age25plus' then return nil, T('gov.benefits.err.age') end
    if not (R.housing and R.housing[a.housing] ~= nil) or not HOUSING_OK[a.housing] then return nil, T('gov.benefits.err.housing') end
    if type(a.partner) ~= 'boolean' then return nil, T('gov.benefits.err.partner') end
    if type(a.disability) ~= 'boolean' then return nil, T('gov.benefits.err.disability') end
    local children = math.floor(tonumber(a.children) or -1)
    if children < 0 or children > 20 then return nil, T('gov.benefits.err.children') end
    if a.looking ~= true then return nil, T('gov.benefits.err.looking') end

    local lines = {}
    local function add(label, amount)
        amount = math.floor(tonumber(amount) or 0)
        if amount > 0 then lines[#lines + 1] = { label = label, amount = amount } end
    end
    add(a.age == 'age18to24' and T('gov.benefits.line.rate1824') or T('gov.benefits.line.rate25'), R[a.age])
    add(housingLabel(a.housing), R.housing[a.housing])
    if a.partner then add(T('gov.benefits.line.partner'), R.partner) end
    local counted = math.min(children, R.maxChildren or 3)
    if counted > 0 then add(counted == 1 and T('gov.benefits.line.child.one', counted) or T('gov.benefits.line.child.other', counted), counted * (R.perChild or 0)) end
    if a.disability then add(T('gov.benefits.line.disability'), R.disability) end

    local total = 0
    for _, l in ipairs(lines) do total = total + l.amount end
    local capped = false
    if R.maxTotal and total > R.maxTotal then total, capped = R.maxTotal, true end
    return {
        rate = total, lines = lines, capped = capped,
        answers = { age = a.age, housing = a.housing, partner = a.partner, children = children, disability = a.disability, looking = true },
    }
end

local function savingsProblem(src)
    local limit = tonumber(B.savingsLimit) or 0
    if limit > 0 and Bridge.getBalance(src, Config.account or 'bank') > limit then
        return T('gov.benefits.err.savings', Config.currency, limit)
    end
end

--- Answers -> assessment for a player, including the checks that depend on the player.
local function assessFor(src, answers)
    local ok, job = qualifies(src)
    if not ok then
        return nil, T('gov.benefits.err.hasJob', job and job.label or T('gov.benefits.unknownJob'))
    end
    local res, err = assess(answers)
    if not res then return nil, err end
    local why = savingsProblem(src)
    if why then return nil, why end
    return res
end

local function decode(text)
    if type(text) ~= 'string' or text == '' then return nil end
    local ok, v = pcall(json.decode, text)
    return ok and type(v) == 'table' and v or nil
end

-- ---------------------------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------------------------

local function jobsText()
    local names = {}
    for _, n in ipairs(B.jobs or {}) do names[#names + 1] = n end
    return table.concat(names, ', ')
end

Browser.handler('gov', 'benefitsState', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local ok, job = qualifies(src)
    local row = rowOf(cid)
    local claiming = row ~= nil and row.status == 'active'
    local state = {
        currency = Config.currency, intervalMinutes = B.intervalMinutes, authority = B.authority,
        eligible = ok, jobLabel = job and job.label or nil, claiming = claiming, now = now(),
        form = { housing = housingOptions(), maxChildren = R.maxChildren or 3, savingsLimit = B.savingsLimit },
        minRate = math.min(R.age18to24 or 0, R.age25plus or 0), maxRate = R.maxTotal,
    }
    if row then
        state.claimedAt, state.payments, state.totalPaid, state.lastPaidAt = row.claimed_at, row.payments, row.total_paid, row.last_paid_at
        state.answers = decode(row.answers)
        local res = state.answers and assess(state.answers)
        state.rate = (row.rate or 0) > 0 and row.rate or (res and res.rate) or 0
        state.lines = res and res.lines or nil
        if claiming then
            state.paused = not ok
            state.minutesToNext = math.max(1, math.ceil((intervalSeconds() - (row.progress or 0)) / 60))
        else
            state.stoppedAt = row.stopped_at
        end
    end
    return state
end)

--- Works out the rate without starting anything. data = { answers = { age, housing, partner, children, disability, looking } }
Browser.handler('gov', 'benefitsAssess', function(src, data)
    local res, err = assessFor(src, data.answers)
    if not res then return nil, err end
    return { rate = res.rate, lines = res.lines, capped = res.capped, maxTotal = R.maxTotal, intervalMinutes = B.intervalMinutes }
end)

Browser.handler('gov', 'benefitsClaim', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local row = rowOf(cid)
    if row and row.status == 'active' then return nil, T('gov.benefits.err.alreadyClaiming') end
    local res, err = assessFor(src, data.answers)
    if not res then return nil, err end
    local t = now()
    local answers = json.encode(res.answers)
    if row then
        -- claiming again keeps the history but starts a fresh wait
        MySQL.update.await("UPDATE browser_benefits SET status = 'active', claimed_at = ?, stopped_at = NULL, progress = 0, rate = ?, answers = ? WHERE citizenid = ?",
            { t, res.rate, answers, cid })
    else
        MySQL.insert.await('INSERT INTO browser_benefits (citizenid, status, claimed_at, rate, answers) VALUES (?, ?, ?, ?, ?)', { cid, 'active', t, res.rate, answers })
    end
    local name = Bridge.getCharacterName(src)
    Bridge.sendPhoneMail(src, cid, B.mailFrom, T('gov.benefits.mailSubject'),
        T('gov.benefits.mailBody', name, Config.currency, res.rate, B.intervalMinutes))
    discordLog(T('gov.discord.benefitsStarted'), 0x2563eb, { { T('gov.discord.character'), name }, { T('gov.discord.citizenId'), cid }, { T('gov.discord.rate'), Config.currency .. res.rate } })
    return { started = t, rate = res.rate, lines = res.lines, intervalMinutes = B.intervalMinutes }
end)

--- Change the answers of a claim that is running. The new rate applies from the next payment.
Browser.handler('gov', 'benefitsUpdate', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local row = rowOf(cid)
    if not row or row.status ~= 'active' then return nil, T('gov.benefits.err.notClaiming') end
    local res, err = assessFor(src, data.answers)
    if not res then return nil, err end
    MySQL.update.await('UPDATE browser_benefits SET rate = ?, answers = ? WHERE citizenid = ?', { res.rate, json.encode(res.answers), cid })
    discordLog(T('gov.discord.benefitsUpdated'), 0xf59e0b, { { T('gov.discord.character'), Bridge.getCharacterName(src) }, { T('gov.discord.citizenId'), cid }, { T('gov.discord.rate'), Config.currency .. res.rate } })
    return { rate = res.rate, lines = res.lines }
end)

Browser.handler('gov', 'benefitsStop', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local row = rowOf(cid)
    if not row or row.status ~= 'active' then return nil, T('gov.benefits.err.notClaiming') end
    MySQL.update.await("UPDATE browser_benefits SET status = 'stopped', stopped_at = ?, progress = 0 WHERE citizenid = ?", { now(), cid })
    discordLog(T('gov.discord.benefitsStopped'), 0xdc2626, { { T('gov.discord.character'), Bridge.getCharacterName(src) }, { T('gov.discord.citizenId'), cid } })
    return { stopped = true }
end)

-- ---------------------------------------------------------------------------------------------
-- Payments: one pass a minute over the players who are online
-- ---------------------------------------------------------------------------------------------

local TICK = 60

local function payOut(src, cid, row)
    local amount = math.floor(tonumber(row.rate) or 0)
    if amount <= 0 then
        -- a claim from before rates existed: work it out from the saved answers, or use the lowest rate
        local res = assess(decode(row.answers))
        amount = res and res.rate or math.floor(math.min(R.age18to24 or 0, R.age25plus or 0))
    end
    if amount <= 0 then return end
    if not Bridge.addMoney(src, Config.account or 'bank', amount, 'benefits') then return false end
    local t = now()
    MySQL.update.await(
        "UPDATE browser_benefits SET progress = 0, last_paid_at = ?, payments = payments + 1, total_paid = total_paid + ? WHERE citizenid = ?",
        { t, amount, cid })
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = T('gov.benefits.bankLabel'), amount = amount, category = 'government', counterparty = B.authority,
        })
    end)
    pcall(function()
        exports['sd-phone']:notify(src, {
            app = 'as-browser', appId = 'as-browser', title = T('gov.benefits.paidTitle'),
            body = T('gov.benefits.paidBody', Config.currency, amount), time = 'now',
        })
    end)
    return true
end

--- One pass. Exposed for testing.
local function tick()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local cid = src and Bridge.getIdentifier(src)
        if cid then
            local row = rowOf(cid)
            if row and row.status == 'active' and qualifies(src) then
                local progress = (row.progress or 0) + TICK
                if progress >= intervalSeconds() then
                    if not payOut(src, cid, row) then
                        MySQL.update.await('UPDATE browser_benefits SET progress = ? WHERE citizenid = ?', { progress, cid })
                    end
                else
                    MySQL.update.await('UPDATE browser_benefits SET progress = ? WHERE citizenid = ?', { progress, cid })
                end
            end
        end
    end
end
Browser.benefitsTick = tick

CreateThread(function()
    Wait(TICK * 1000)
    while true do
        local ok, err = pcall(tick)
        if not ok then log('payment pass failed: %s', tostring(err)) end
        Wait(TICK * 1000)
    end
end)

CreateThread(function()
    Wait(3000)
    log('rates %s%d to %s%d every %d minutes online, for jobs: %s', Config.currency, math.min(R.age18to24, R.age25plus), Config.currency, R.maxTotal or 0, B.intervalMinutes, jobsText())
end)
