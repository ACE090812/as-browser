-- Los Santos Government: vehicle checker, vehicle tax, and placeholder services.
local G = Config.gov
local DAY = 86400

local function now() return os.time() end

-- ---------------------------------------------------------------------------------------------
-- Registration (with a search entry for every service)
-- ---------------------------------------------------------------------------------------------

local function servicePath(s)
    return s.path or ('/s/' .. s.id)
end

--- Whether a custom script is switched on in Config.gov.scripts (missing = on). Council tax and
--- benefits also honour their own `enabled` flag.
local function scriptOn(key)
    if not key then return true end
    if G.scripts and G.scripts[key] == false then return false end
    if key == 'council' and G.council and G.council.enabled == false then return false end
    if key == 'benefits' and G.benefits and G.benefits.enabled == false then return false end
    -- the penalties page is built from the licence and fines scripts: it is on while either one is
    if key == 'penalties' and G.scripts and G.scripts.licence == false and G.scripts.fines == false then return false end
    return true
end
Browser.govScriptOn = scriptOn

local pages = {}
for _, s in ipairs(G.services) do
  if scriptOn(s.requires) then
    pages[#pages + 1] = { path = servicePath(s), title = s.title, description = s.description, keywords = s.keywords }
  end
end

Browser.defineSite('gov', {
    title       = G.name,
    description = T('gov.description'),
    keywords    = Browser.words(T('gov.keywords')),
    category    = T('gov.category'),
    icon        = '🏛️',
    color       = '#0f2a4a',
    pages       = pages,
})

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_vehicle_status (
        plate VARCHAR(16) NOT NULL PRIMARY KEY,
        tax_expiry INT NOT NULL,
        mot_expiry INT NULL,
        mot_status VARCHAR(16) NULL,
        updated_at INT NOT NULL
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_mot_history (
        id INT AUTO_INCREMENT PRIMARY KEY,
        plate VARCHAR(16) NOT NULL,
        tested_at INT NOT NULL,
        passed TINYINT(1) NOT NULL,
        expiry INT NULL,
        details TEXT NULL,
        KEY idx_plate (plate, tested_at)
    )]])
end)

--- Tax and MOT state for a plate. A vehicle the system has not seen before starts taxed for
--- Config.gov.tax.graceDays, so nothing shows as untaxed on the first day.
local function statusRow(plateKey)
    local row = MySQL.single.await(
        'SELECT plate, tax_expiry, mot_expiry, mot_status FROM browser_vehicle_status WHERE plate = ?', { plateKey })
    if row then return row end
    local expiry = now() + G.tax.graceDays * DAY
    MySQL.insert.await('INSERT IGNORE INTO browser_vehicle_status (plate, tax_expiry, updated_at) VALUES (?, ?, ?)',
        { plateKey, expiry, now() })
    return { plate = plateKey, tax_expiry = expiry }
end

local function rateFor(desc)
    return tonumber(G.tax.rates[desc.class.key]) or 0
end

local function taxInfo(desc, row)
    if desc.exempt then return { status = 'exempt' } end
    local expiry = tonumber(row.tax_expiry) or 0
    return { status = expiry > now() and 'taxed' or 'untaxed', expiry = expiry, rate = rateFor(desc) }
end

local function motInfo(row)
    if not G.mot.enabled then return { enabled = false, status = 'not_required' } end
    local expiry = tonumber(row.mot_expiry)
    if expiry and expiry > now() then return { enabled = true, status = 'valid', expiry = expiry } end
    if expiry then return { enabled = true, status = 'expired', expiry = expiry } end
    if row.mot_status == 'failed' then return { enabled = true, status = 'failed' } end
    return { enabled = true, status = 'none' }
end

local function motHistory(plateKey)
    local rows = MySQL.query.await(
        'SELECT tested_at, passed, expiry, details FROM browser_mot_history WHERE plate = ? ORDER BY tested_at DESC LIMIT 15',
        { plateKey }) or {}
    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        out[i] = { testedAt = r.tested_at, passed = r.passed == 1 or r.passed == true, expiry = (tonumber(r.expiry) or 0) > 0 and r.expiry or nil,
                   details = (r.details and r.details ~= '') and r.details or nil }
    end
    return out
end

local function insuranceInfo(plateKey)
    if not G.showInsurance or not Browser.isEnabled('insurance') or not Browser.hooks.insuranceStatus then return nil end
    local ok, res = pcall(Browser.hooks.insuranceStatus, plateKey)
    if not ok or type(res) ~= 'table' then return nil end
    return { status = res.active and 'insured' or 'not_insured', endsAt = res.endsAt }
end

local function trimPlate(p) return (tostring(p):gsub('%s+$', '')) end

-- ---------------------------------------------------------------------------------------------
-- Exports (used by MDT / ANPR / police scripts and the future MOT script)
-- ---------------------------------------------------------------------------------------------

function Browser.api.getVehicleStatus(plate)
    local v = Vehicles.find(plate)
    if not v then return nil end
    local d = Vehicles.describe(v)
    local row = statusRow(d.plateKey)
    local ins = insuranceInfo(d.plateKey)
    return {
        plate = d.plateKey, make = d.make, model = d.model, colour = d.colour,
        class = d.class.label, exempt = d.exempt,
        tax = taxInfo(d, row), mot = motInfo(row),
        insured = ins and ins.status == 'insured' or nil,
    }
end

--- true/false, plus a list of reasons when false ('untaxed', 'no_mot').
function Browser.api.isRoadLegal(plate)
    local s = Browser.api.getVehicleStatus(plate)
    if not s then return nil end
    local reasons = {}
    if s.tax.status == 'untaxed' then reasons[#reasons + 1] = 'untaxed' end
    if not s.exempt and s.mot.enabled and s.mot.status ~= 'valid' then reasons[#reasons + 1] = 'no_mot' end
    return #reasons == 0, reasons
end

function Browser.api.setMotResult(plate, passed, expiry, details)
    local key = Vehicles.normalizePlate(plate)
    if not key then return false, 'Invalid registration number' end
    if not Vehicles.find(key) then return false, 'Vehicle not found' end
    passed = (passed == true or passed == 1)
    expiry = tonumber(expiry)
    if passed and not expiry then return false, 'An expiry time is required when the vehicle passed' end
    statusRow(key)
    MySQL.insert.await('INSERT INTO browser_mot_history (plate, tested_at, passed, expiry, details) VALUES (?, ?, ?, ?, ?)',
        { key, now(), passed and 1 or 0, expiry or 0, details and tostring(details):sub(1, 1000) or '' })
    if passed then
        MySQL.update.await('UPDATE browser_vehicle_status SET mot_expiry = ?, mot_status = ?, updated_at = ? WHERE plate = ?',
            { expiry, 'valid', now(), key })
    else
        MySQL.update.await('UPDATE browser_vehicle_status SET mot_status = ?, updated_at = ? WHERE plate = ?',
            { 'failed', now(), key })
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Requests from the site
-- ---------------------------------------------------------------------------------------------

Browser.handler('gov', 'home', function()
    local services = {}
    for _, s in ipairs(G.services) do
      if scriptOn(s.requires) then
        local svc = {
            id = s.id, title = s.title, description = s.description, category = s.category,
            status = s.status, path = servicePath(s), popular = s.popular == true,
        }
        if s.linkSite then
            local cfg = Config.Sites[s.linkSite]
            if cfg and Browser.isEnabled(s.linkSite) then
                svc.link = cfg.domain
            else
                svc.status = 'placeholder'
            end
        end
        services[#services + 1] = svc
      end
    end
    -- A category with no services in it is not shown (so removing a service can't leave an empty page).
    local used, categories = {}, {}
    for _, s in ipairs(services) do used[s.category] = true end
    for _, c in ipairs(G.categories) do if used[c.id] then categories[#categories + 1] = c end end
    return { name = G.name, categories = categories, services = services, mot = { enabled = G.mot.enabled == true },
             tax = { periodDays = G.tax.periodDays, renewWindowDays = G.tax.renewWindowDays } }
end)

Browser.handler('gov', 'lookup', function(src, data)
    local key = Vehicles.normalizePlate(tostring(data.plate or ''))
    if not key then return nil, T('gov.err.plate') end
    local v = Vehicles.find(key)
    if not v then return { found = false, plate = key, now = now() } end

    local d = Vehicles.describe(v)
    local row = statusRow(d.plateKey)
    local cid = Bridge.getIdentifier(src)
    return {
        found = true, now = now(),
        plate = trimPlate(d.plate), make = d.make, model = d.model, colour = d.colour,
        class = d.class.label, exempt = d.exempt,
        tax = taxInfo(d, row), mot = motInfo(row), motHistory = motHistory(d.plateKey),
        insurance = insuranceInfo(d.plateKey),
        owned = cid ~= nil and v.owner == cid,
    }
end)

Browser.handler('gov', 'myVehicles', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local list = Vehicles.ownedBy(cid)
    local out = {}
    for i = 1, math.min(#list, 50) do
        local d = Vehicles.describe(list[i])
        local row = statusRow(d.plateKey)
        local tax = taxInfo(d, row)
        out[#out + 1] = {
            plate = trimPlate(d.plate), plateKey = d.plateKey, make = d.make, model = d.model, colour = d.colour,
            class = d.class.label, exempt = d.exempt, tax = tax, mot = motInfo(row),
            canRenew = not d.exempt and (tax.expiry - now()) <= G.tax.renewWindowDays * DAY,
        }
    end
    return { vehicles = out, now = now(), periodDays = G.tax.periodDays, renewWindowDays = G.tax.renewWindowDays }
end)

Browser.handler('gov', 'tax', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local key = Vehicles.normalizePlate(tostring(data.plate or ''))
    if not key then return nil, T('gov.err.plate') end

    local v = Vehicles.find(key)
    if not v or v.owner ~= cid then return nil, T('gov.tax.notOwner') end
    local d = Vehicles.describe(v)
    if d.exempt then return nil, T('gov.tax.exempt') end

    local row = statusRow(d.plateKey)
    local current = tonumber(row.tax_expiry) or 0
    local t = now()
    if current - t > G.tax.renewWindowDays * DAY then
        return nil, T('gov.tax.alreadyTaxed', Browser.date(current), G.tax.renewWindowDays)
    end

    local rate = rateFor(d)
    if not Bridge.removeMoney(src, Config.account, rate, 'vehicle-tax') then
        return nil, T('shell.err.insufficientFunds')
    end

    local newExpiry = math.max(current, t) + G.tax.periodDays * DAY
    -- Only succeeds if nobody taxed the vehicle in the meantime, so a double click cannot charge twice.
    local changed = MySQL.update.await(
        'UPDATE browser_vehicle_status SET tax_expiry = ?, updated_at = ? WHERE plate = ? AND tax_expiry = ?',
        { newExpiry, t, d.plateKey, current })
    if not changed or changed < 1 then
        Bridge.addMoney(src, Config.account, rate, 'vehicle-tax-refund')
        return nil, T('gov.err.changed')
    end

    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = T('gov.tax.bankLabel', trimPlate(d.plate)), amount = -rate,
            category = 'government', counterparty = G.name,
        })
    end)

    return { plate = trimPlate(d.plate), amount = rate, expiry = newExpiry, periodDays = G.tax.periodDays, now = t }
end)
