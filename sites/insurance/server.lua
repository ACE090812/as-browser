-- CoverCompare: quote engine and policy purchase.
local I = Config.insurance
local DAY = 86400

local function now() return os.time() end

Browser.defineSite('insurance', {
    title       = I.name,
    description = 'Compare car and bike insurance quotes and buy cover in minutes.',
    keywords    = { 'insurance', 'cover', 'quote', 'compare', 'car insurance', 'vehicle', 'premium', 'policy', 'third party', 'comprehensive', 'gocompare' },
    category    = 'Insurance',
    icon        = '🛡️',
    color       = '#0b5cad',
    pages = {
        { path = '/quote',    title = 'Get a quote',   description = 'Compare insurance quotes for your vehicle.', keywords = { 'quote', 'compare', 'price' } },
        { path = '/policies', title = 'My policies',   description = 'See your insurance policies and certificates.', keywords = { 'policy', 'certificate', 'renew' } },
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
    return { active = true, endsAt = row.ends_at }
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
    if not cover then return nil, 'Choose a level of cover.' end
    local usage = byId(I.usages, tostring(data.usage or ''))
    if not usage then return nil, 'Choose how you use the vehicle.' end
    local dur = byDays(data.days)
    if not dur then return nil, 'Choose how long you want cover for.' end
    local ncd = math.floor(tonumber(data.ncd) or 0)
    if ncd < 0 or ncd > I.ncd.maxYears then return nil, 'Check your no claims years.' end

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
    if not cid then return nil, 'You are not signed in.' end
    local key = Vehicles.normalizePlate(tostring(plate or ''))
    if not key then return nil, 'Choose a vehicle.' end
    local v = Vehicles.find(key)
    if not v or v.owner ~= cid then return nil, 'You can only insure a vehicle you own.' end
    return Vehicles.describe(v), cid
end

Browser.handler('insurance', 'myVehicles', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
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
        (I.name .. ' - Certificate of motor insurance'),
        '',
        'Policy reference: ' .. p.ref,
        'Insurer: ' .. p.providerName,
        'Policyholder: ' .. p.holder,
        'Vehicle: ' .. p.vehicle,
        'Registration: ' .. p.plate,
        'Cover: ' .. p.coverLabel,
        'Use: ' .. p.usageLabel,
        'Start: ' .. os.date('%d %b %Y %H:%M', p.startsAt),
        'End: ' .. os.date('%d %b %Y %H:%M', p.endsAt),
        'Premium paid: ' .. Config.currency .. p.price,
        'Excess: ' .. Config.currency .. p.excess,
    }
    if #p.addonLabels > 0 then lines[#lines + 1] = 'Extras: ' .. table.concat(p.addonLabels, ', ') end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Keep this certificate safe. Roleplay use only.'
    return table.concat(lines, '\n')
end

local function buy(src, data)
    local desc, cid = ownedVehicle(src, data.plate)
    if not desc then return nil, cid end
    local a, msg = readAnswers(data)
    if not a then return nil, msg end
    local provider = byId(I.providers, tostring(data.provider or ''))
    if not provider then return nil, 'Choose an insurer.' end

    local t = now()
    local finish = lastEnd(desc.plateKey)
    if finish and finish - t > I.renewWindowDays * DAY then
        return nil, ('This vehicle is already insured until %s. You can buy new cover in the last %d days.'):format(
            os.date('%d %b %Y', finish), I.renewWindowDays)
    end

    local price = priceFor(desc, provider, a)
    if not Bridge.removeMoney(src, Config.account, price, 'vehicle-insurance') then
        return nil, 'You do not have enough money in your bank account.'
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
        return nil, 'We could not set up your policy. You have not been charged, please try again.'
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
            label = ('%s insurance %s'):format(provider.name, p.plate), amount = -price,
            category = 'insurance', counterparty = I.name,
        })
    end)
    pcall(function()
        exports['sd-phone']:createDocument(src, {
            name = ('Insurance certificate %s'):format(p.plate), kind = 'text',
            content = certificateText(p), folder = I.documentFolder, deletable = true,
        })
    end)
    Bridge.sendPhoneMail(src, cid, I.mailFrom,
        ('Your %s policy %s'):format(provider.name, ref),
        ('Hello %s,\n\nThanks for buying cover with %s.\n\nVehicle: %s (%s)\nCover: %s\nValid until: %s\nPaid: %s%d\nReference: %s\n\nYour certificate has been saved in your Files app.'):format(
            p.holder, provider.name, p.vehicle, p.plate, p.coverLabel, os.date('%d %b %Y %H:%M', endsAt), Config.currency, price, ref))

    return {
        ref = ref, plate = p.plate, provider = provider.name, cover = a.cover.label, price = price,
        startsAt = startsAt, endsAt = endsAt, excess = provider.excess, now = t,
    }
end

Browser.handler('insurance', 'buy', function(src, data)
    if busy[src] then return nil, 'Please wait, your last request is still being processed.' end
    busy[src] = true
    local ok, res, err = pcall(buy, src, data)
    busy[src] = nil
    if not ok then error(res, 0) end
    return res, err
end)

Browser.handler('insurance', 'policies', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
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
