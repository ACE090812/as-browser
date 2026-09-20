-- Benefits on the government site. A character claims once; while they are online and still have a
-- qualifying job (Config.gov.benefits.jobs) they are paid into their bank every `intervalMinutes`.
-- Taking a job pauses payments, losing it starts them again. Stopping the claim ends it.
--
-- Settings are in Config.gov.benefits (sites/gov/config.lua).
local B = Config.gov.benefits
if not B or B.enabled == false then return end

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
-- Pages
-- ---------------------------------------------------------------------------------------------

local function jobsText()
    local names = {}
    for _, n in ipairs(B.jobs or {}) do names[#names + 1] = n end
    return table.concat(names, ', ')
end

Browser.handler('gov', 'benefitsState', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
    local ok, job = qualifies(src)
    local row = rowOf(cid)
    local claiming = row ~= nil and row.status == 'active'
    local state = {
        currency = Config.currency, amount = B.amount, intervalMinutes = B.intervalMinutes, authority = B.authority,
        eligible = ok, jobLabel = job and job.label or nil, claiming = claiming, now = now(),
    }
    if row then
        state.claimedAt, state.payments, state.totalPaid, state.lastPaidAt = row.claimed_at, row.payments, row.total_paid, row.last_paid_at
        if claiming then
            state.paused = not ok
            state.minutesToNext = math.max(1, math.ceil((intervalSeconds() - (row.progress or 0)) / 60))
        else
            state.stoppedAt = row.stopped_at
        end
    end
    return state
end)

Browser.handler('gov', 'benefitsClaim', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
    local ok, job = qualifies(src)
    if not ok then
        return nil, ('You can only claim while you are out of work. Your current job is %s.'):format(job and job.label or 'unknown')
    end
    local row = rowOf(cid)
    if row and row.status == 'active' then return nil, 'You are already claiming.' end
    local t = now()
    if row then
        -- claiming again keeps the history but starts a fresh wait
        MySQL.update.await("UPDATE browser_benefits SET status = 'active', claimed_at = ?, stopped_at = NULL, progress = 0 WHERE citizenid = ?", { t, cid })
    else
        MySQL.insert.await('INSERT INTO browser_benefits (citizenid, status, claimed_at) VALUES (?, ?, ?)', { cid, 'active', t })
    end
    local name = Bridge.getCharacterName(src)
    Bridge.sendPhoneMail(src, cid, B.mailFrom, 'Your benefits claim has started',
        ('Hello %s,\n\nYour claim has started. You will be paid %s%d into your bank account for every %d minutes you are online while you are out of work.\n\nIf you take a job your payments pause, and they start again if you lose it. You can stop your claim at any time on lsgov.co.uk.'):format(
            name, Config.currency, B.amount, B.intervalMinutes))
    discordLog('Benefits claim started', 0x2563eb, { { 'Character', name }, { 'Citizen ID', cid } })
    return { started = t, amount = B.amount, intervalMinutes = B.intervalMinutes }
end)

Browser.handler('gov', 'benefitsStop', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
    local row = rowOf(cid)
    if not row or row.status ~= 'active' then return nil, 'You are not claiming.' end
    MySQL.update.await("UPDATE browser_benefits SET status = 'stopped', stopped_at = ?, progress = 0 WHERE citizenid = ?", { now(), cid })
    discordLog('Benefits claim stopped', 0xdc2626, { { 'Character', Bridge.getCharacterName(src) }, { 'Citizen ID', cid } })
    return { stopped = true }
end)

-- ---------------------------------------------------------------------------------------------
-- Payments: one pass a minute over the players who are online
-- ---------------------------------------------------------------------------------------------

local TICK = 60

local function payOut(src, cid, row)
    local amount = math.floor(tonumber(B.amount) or 0)
    if amount <= 0 then return end
    if not Bridge.addMoney(src, Config.account or 'bank', amount, 'benefits') then return false end
    local t = now()
    MySQL.update.await(
        "UPDATE browser_benefits SET progress = 0, last_paid_at = ?, payments = payments + 1, total_paid = total_paid + ? WHERE citizenid = ?",
        { t, amount, cid })
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = 'Benefits payment', amount = amount, category = 'government', counterparty = B.authority,
        })
    end)
    pcall(function()
        exports['sd-phone']:notify(src, {
            app = 'as-browser', appId = 'as-browser', title = 'Benefits paid',
            body = ('%s%d has been paid into your bank account.'):format(Config.currency, amount), time = 'now',
        })
    end)
    return true
end

--- One pass. Exposed for testing through the export below.
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
    log('%s%d every %d minutes online for jobs: %s', Config.currency, B.amount, B.intervalMinutes, jobsText())
end)
