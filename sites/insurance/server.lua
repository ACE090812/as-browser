-- CoverCompare: quote engine and policy purchase.
local I = Config.insurance
local DAY = 86400

local function now() return os.time() end

Browser.defineSite('insurance', {
    title       = I.name,
    description = T('insurance.description'),
    keywords    = Browser.words(T('insurance.keywords')),
    category    = T('insurance.category'),
    icon        = '🛡️',
    color       = '#0b5cad',
    pages = {
        { path = '/quote',    title = T('insurance.page.quote.title'),    description = T('insurance.page.quote.description'),    keywords = Browser.words(T('insurance.page.quote.keywords')) },
        { path = '/policies', title = T('insurance.page.policies.title'), description = T('insurance.page.policies.description'), keywords = Browser.words(T('insurance.page.policies.keywords')) },
    },
})

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_insurance_policies (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ref VARCHAR(16) NOT NULL,
        citizenid VARCHAR(64) NOT NULL,
        plate VARCHAR(16) NOT NULL,
        provider VARCHAR(32) NOT NULL,
        cover VARCHAR(32) NOT NULL,
        usage_type VARCHAR(32) NOT NULL,
        ncd TINYINT NOT NULL DEFAULT 0,
        addons VARCHAR(120) NULL,
        starts_at INT NOT NULL,
        ends_at INT NOT NULL,
        price INT NOT NULL,
        created_at INT NOT NULL,
        UNIQUE KEY uq_ref (ref),
        KEY idx_plate (plate, ends_at),
        KEY idx_owner (citizenid, id)
    )]])
end)

-- ---------------------------------------------------------------------------------------------
-- Lookups
-- ---------------------------------------------------------------------------------------------

local function byId(list, id)
    for i = 1, #list do if list[i].id == id then return list[i] end end
    return nil
end

local function byDays(days)
    days = tonumber(days)
    for i = 1, #I.durations do if I.durations[i].days == days then return I.durations[i] end end
    return nil
end

local function contains(list, v)
    for i = 1, #(list or {}) do if list[i] == v then return true end end
    return false
end

local function trimPlate(p) return (tostring(p):gsub('%s+$', '')) end

--- 0..1, always the same for the same text.
local function steady(text)
    local h = 7
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 1000003 end
    return (h % 1000) / 1000
end

--- The policy that covers a plate right now (the one ending last), if any.
local function policyRow(plateKey)
    return MySQL.single.await(
        'SELECT ref, provider, cover, ends_at FROM browser_insurance_policies WHERE plate = ? AND ends_at > ? AND starts_at <= ? ORDER BY ends_at DESC LIMIT 1',
        { plateKey, now(), now() })
end

--- The last end time of any current or booked policy, used to chain a renewal after it.
local function lastEnd(plateKey)
    return tonumber(MySQL.scalar.await(
        'SELECT MAX(ends_at) FROM browser_insurance_policies WHERE plate = ? AND ends_at > ?', { plateKey, now() }))
end

-- Other sites ask "is this plate insured?" through this hook and export.
function Browser.hooks.insuranceStatus(plateKey)
    local row = policyRow(plateKey)
    if not row then return { active = false } end
    -- row.provider is the provider's id (e.g. "aegis"), not something to show a player directly -
    -- resolve it against the configured provider list for its display name, same lookup byId()
    -- already does everywhere else in this file.
    local providerName = row.provider
    local p = byId(I.providers, row.provider)
    if p and p.name then providerName = p.name end
    return { active = true, endsAt = row.ends_at, provider = providerName }
end

exports('isInsured', function(plate)
    if not Browser.isEnabled('insurance') then return nil end
    local key = Vehicles.normalizePlate(plate)
    if not key then return false end
    local row = policyRow(key)
    return row ~= nil, row and row.ends_at or nil
end)

-- ---------------------------------------------------------------------------------------------
-- Pricing (all of it happens here, the page only shows what it is told)
-- ---------------------------------------------------------------------------------------------

--- Validates the answers and returns them as a table, or nil plus a message.
local function readAnswers(data)
    local cover = byId(I.covers, tostring(data.cover or ''))
    if not cover then return nil, T('insurance.err.chooseCover') end
    local usage = byId(I.usages, tostring(data.usage or ''))
    if not usage then return nil, T('insurance.err.chooseUsage') end
    local dur = byDays(data.days)
    if not dur then return nil, T('insurance.err.chooseDuration') end
    local ncd = math.floor(tonumber(data.ncd) or 0)
    if ncd < 0 or ncd > I.ncd.maxYears then return nil, T('insurance.err.checkNcd') end

    local addons = {}
    if type(data.addons) == 'table' then
        for i = 1, math.min(#data.addons, #I.addons) do
            local a = byId(I.addons, tostring(data.addons[i]))
            if a and not contains(addons, a.id) then addons[#addons + 1] = a.id end
        end
    end
    return { cover = cover, usage = usage, duration = dur, ncd = ncd, addons = addons }
end

local function priceFor(desc, provider, a)
    local base = tonumber(I.weeklyBase[desc.class.key]) or tonumber(I.weeklyBase.standard) or 45
    local weeks = a.duration.days / 7
    local discount = 1 - math.min(a.ncd, I.ncd.maxYears) * I.ncd.perYear
    local jitter = 0.94 + 0.12 * steady(desc.plateKey .. provider.id)
    local core = base * a.cover.mult * a.usage.mult * discount * a.duration.factor * weeks * provider.factor * jitter
    local extras, included = 0, {}
    for i = 1, #a.addons do
        local ad = byId(I.addons, a.addons[i])
        if contains(provider.includes, ad.id) then
            included[#included + 1] = ad.id
        else
            extras = extras + ad.price * weeks
        end
    end
    local total = math.max(5, math.floor(core + extras + 0.5))
    return total, included
end

local function offersFor(desc, a)
    local out = {}
    for i = 1, #I.providers do
        local p = I.providers[i]
        local total, included = priceFor(desc, p, a)
        out[#out + 1] = {
            id = p.id, name = p.name, color = p.color, icon = p.icon, rating = p.rating, blurb = p.blurb,
            features = p.features, excess = p.excess, price = total, included = included,
            perWeek = math.floor(total / (a.duration.days / 7) + 0.5),
        }
    end
    table.sort(out, function(x, y) return x.price < y.price end)
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Page requests
-- ---------------------------------------------------------------------------------------------

Browser.handler('insurance', 'home', function()
    local providers = {}
    for i = 1, #I.providers do
        local p = I.providers[i]
        providers[i] = { id = p.id, name = p.name, color = p.color, icon = p.icon, rating = p.rating, blurb = p.blurb }
    end
    return {
        name = I.name, covers = I.covers, usages = I.usages, durations = I.durations, addons = I.addons,
        ncd = I.ncd, providers = providers, renewWindowDays = I.renewWindowDays,
    }
end)

--- Returns the described vehicle and the owner's identifier, or nil plus a message.
local function ownedVehicle(src, plate)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local key = Vehicles.normalizePlate(tostring(plate or ''))
    if not key then return nil, T('insurance.err.chooseVehicle') end
    local v = Vehicles.find(key)
    if not v or v.owner ~= cid then return nil, T('insurance.err.notOwner') end
    return Vehicles.describe(v), cid
end

Browser.handler('insurance', 'myVehicles', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local out = {}
    local list = Vehicles.ownedBy(cid)
    for i = 1, math.min(#list, 50) do
        local d = Vehicles.describe(list[i])
        local pol = policyRow(d.plateKey)
        out[#out + 1] = {
            plate = trimPlate(d.plate), plateKey = d.plateKey, make = d.make, model = d.model,
            colour = d.colour, class = d.class.label,
            insuredUntil = pol and pol.ends_at or nil,
        }
    end
    return { vehicles = out, now = now() }
end)

Browser.handler('insurance', 'quote', function(src, data)
    local desc, err = ownedVehicle(src, data.plate)
    if not desc then return nil, err end
    local a, msg = readAnswers(data)
    if not a then return nil, msg end
    return {
        plate = trimPlate(desc.plate), make = desc.make, model = desc.model, colour = desc.colour, class = desc.class.label,
        offers = offersFor(desc, a), now = now(),
    }
end)

local busy = {}

local function randomRef()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = {}
    for i = 1, 8 do
        local n = math.random(1, #chars)
        out[i] = chars:sub(n, n)
    end
    return 'CC' .. table.concat(out)
end

local function certificateText(p)
    local lines = {
        T('insurance.cert.title', I.name),
        '',
        T('insurance.cert.ref', p.ref),
        T('insurance.cert.insurer', p.providerName),
        T('insurance.cert.holder', p.holder),
        T('insurance.cert.vehicle', p.vehicle),
        T('insurance.cert.reg', p.plate),
        T('insurance.cert.cover', p.coverLabel),
        T('insurance.cert.use', p.usageLabel),
        T('insurance.cert.start', Browser.datetime(p.startsAt)),
        T('insurance.cert.end', Browser.datetime(p.endsAt)),
        T('insurance.cert.premium', Config.currency .. p.price),
        T('insurance.cert.excess', Config.currency .. p.excess),
    }
    if #p.addonLabels > 0 then lines[#lines + 1] = T('insurance.cert.extras', table.concat(p.addonLabels, ', ')) end
    lines[#lines + 1] = ''
    lines[#lines + 1] = T('insurance.cert.keep')
    return table.concat(lines, '\n')
end

local function buy(src, data)
    local desc, cid = ownedVehicle(src, data.plate)
    if not desc then return nil, cid end
    local a, msg = readAnswers(data)
    if not a then return nil, msg end
    local provider = byId(I.providers, tostring(data.provider or ''))
    if not provider then return nil, T('insurance.err.chooseInsurer') end

    local t = now()
    local finish = lastEnd(desc.plateKey)
    if finish and finish - t > I.renewWindowDays * DAY then
        return nil, T('insurance.err.alreadyInsured', Browser.date(finish), I.renewWindowDays)
    end

    local price = priceFor(desc, provider, a)
    if not Bridge.removeMoney(src, Config.account, price, 'vehicle-insurance') then
        return nil, T('shell.err.insufficientFunds')
    end

    local startsAt = math.max(t, finish or 0)
    local endsAt = startsAt + a.duration.days * DAY
    local ref = randomRef()
    local ok, id = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO browser_insurance_policies (ref, citizenid, plate, provider, cover, usage_type, ncd, addons, starts_at, ends_at, price, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { ref, cid, desc.plateKey, provider.id, a.cover.id, a.usage.id, a.ncd, table.concat(a.addons, ','), startsAt, endsAt, price, t })
    end)
    if not ok or not id then
        Bridge.addMoney(src, Config.account, price, 'vehicle-insurance-refund')
        return nil, T('insurance.err.setupFailed')
    end

    local addonLabels = {}
    for i = 1, #a.addons do addonLabels[#addonLabels + 1] = byId(I.addons, a.addons[i]).label end
    local vehicleName = (('%s %s'):format(desc.make, desc.model):gsub('^%s+', ''))
    local p = {
        ref = ref, providerName = provider.name, holder = Bridge.getCharacterName(src),
        vehicle = vehicleName, plate = trimPlate(desc.plate),
        coverLabel = a.cover.label, usageLabel = a.usage.label, startsAt = startsAt, endsAt = endsAt,
        price = price, excess = provider.excess, addonLabels = addonLabels,
    }

    -- Everything below is a nice-to-have. The policy already exists, so a failure here is ignored.
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = T('insurance.bankLabel', provider.name, p.plate), amount = -price,
            category = 'insurance', counterparty = I.name,
        })
    end)
    pcall(function()
        exports['sd-phone']:createDocument(src, {
            name = T('insurance.docName', p.plate), kind = 'text',
            content = certificateText(p), folder = I.documentFolder, deletable = true,
        })
    end)
    Bridge.sendPhoneMail(src, cid, I.mailFrom,
        T('insurance.mail.subject', provider.name, ref),
        T('insurance.mail.body',
            p.holder, provider.name, p.vehicle, p.plate, p.coverLabel, Browser.datetime(endsAt), Config.currency, price, ref))

    return {
        ref = ref, plate = p.plate, provider = provider.name, cover = a.cover.label, price = price,
        startsAt = startsAt, endsAt = endsAt, excess = provider.excess, now = t,
    }
end

Browser.handler('insurance', 'buy', function(src, data)
    if busy[src] then return nil, T('shell.err.busy') end
    busy[src] = true
    local ok, res, err = pcall(buy, src, data)
    busy[src] = nil
    if not ok then error(res, 0) end
    return res, err
end)

Browser.handler('insurance', 'policies', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local rows = MySQL.query.await(
        'SELECT ref, plate, provider, cover, starts_at, ends_at, price FROM browser_insurance_policies WHERE citizenid = ? ORDER BY id DESC LIMIT 30',
        { cid }) or {}
    local t = now()
    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        local prov, cov = byId(I.providers, r.provider), byId(I.covers, r.cover)
        out[i] = {
            ref = r.ref, plate = r.plate, provider = prov and prov.name or r.provider, cover = cov and cov.label or r.cover,
            startsAt = r.starts_at, endsAt = r.ends_at, price = r.price,
            active = r.ends_at > t and r.starts_at <= t, upcoming = r.starts_at > t,
        }
    end
    return { policies = out, now = t }
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)
