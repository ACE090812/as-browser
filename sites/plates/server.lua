-- LS Plates: personalised registrations as things a player owns.
--
--   browser_plate_assets    one row per personalised plate: who owns it and, while it is on a vehicle, that vehicle's
--                           ORIGINAL registration (base_key). No base_key = the plate is kept, not on any vehicle.
--   browser_plate_listings  plates for sale on the marketplace (see server_market.lua)
--   browser_plate_sales     finished sales
--   browser_plate_payouts   money owed to a seller (paid straight away when they are online, otherwise next time)
--   browser_plate_log       every fit / remove of a plate on a vehicle, by the vehicle's original registration
--
-- The vehicle owns its records (MOT, tax, insurance, history, bookings). Every time its registration changes, those records
-- are moved to the new registration in the same database transaction, and as-computer is told so its MOT records and
-- garage bookings follow.
local P = Config.plates or {}
local HOUR = 3600

local function cfg(key, default)
    if P[key] == nil then return default end
    return P[key]
end

local function now() return os.time() end
local function trimPlate(p) return (tostring(p or ''):gsub('%s+$', '')) end
local function whole(v, d) return math.floor(tonumber(v) or d or 0) end

Plates = Plates or {}
Plates.x = Plates.x or {}     -- internals shared with server_market.lua
local X = Plates.x

Browser.defineSite('plates', {
    title       = P.name or 'LS Plates',
    description = T('plates.description'),
    keywords    = Browser.words(T('plates.keywords')),
    category    = T('plates.category'),
    icon        = '🔖',
    color       = '#0b3d91',
    pages = {
        { path = '/buy',    title = T('plates.nav.buy'),    description = T('plates.buy.lead'),    keywords = Browser.words(T('plates.keywords')) },
        { path = '/market', title = T('plates.nav.market'), description = T('plates.market.lead'), keywords = Browser.words(T('plates.keywords.market')) },
        { path = '/mine',   title = T('plates.nav.mine'),   description = T('plates.mine.lead'),   keywords = Browser.words(T('plates.keywords.mine')) },
    },
})

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

local function createTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_plate_assets (
        id INT AUTO_INCREMENT PRIMARY KEY,
        plate_key VARCHAR(16) NOT NULL,
        display VARCHAR(16) NOT NULL,
        owner VARCHAR(64) NOT NULL,
        base_key VARCHAR(16) NULL,
        base_display VARCHAR(16) NULL,
        created_at INT NOT NULL,
        UNIQUE KEY uq_plate (plate_key),
        KEY idx_owner (owner),
        KEY idx_base (base_key)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_plate_listings (
        id INT AUTO_INCREMENT PRIMARY KEY,
        asset_id INT NOT NULL,
        seller VARCHAR(64) NOT NULL,
        price INT NOT NULL,
        listed_at INT NOT NULL,
        UNIQUE KEY uq_asset (asset_id),
        KEY idx_seller (seller)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_plate_sales (
        id INT AUTO_INCREMENT PRIMARY KEY,
        plate_key VARCHAR(16) NOT NULL,
        display VARCHAR(16) NOT NULL,
        seller VARCHAR(64) NOT NULL,
        buyer VARCHAR(64) NOT NULL,
        price INT NOT NULL,
        fee INT NOT NULL DEFAULT 0,
        sold_at INT NOT NULL,
        KEY idx_seller (seller, sold_at),
        KEY idx_buyer (buyer, sold_at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_plate_payouts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        cid VARCHAR(64) NOT NULL,
        amount INT NOT NULL,
        note VARCHAR(40) NOT NULL DEFAULT '',
        created_at INT NOT NULL,
        settled TINYINT(1) NOT NULL DEFAULT 0,
        KEY idx_cid (cid, settled)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_plate_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        base_key VARCHAR(16) NOT NULL,
        kind VARCHAR(12) NOT NULL,
        old_display VARCHAR(16) NOT NULL DEFAULT '',
        new_display VARCHAR(16) NOT NULL DEFAULT '',
        cid VARCHAR(64) NOT NULL DEFAULT '',
        price INT NOT NULL DEFAULT 0,
        logged_at INT NOT NULL,
        KEY idx_base (base_key, logged_at)
    )]])
    -- The table the old "buy a plate" service wrote to. Only read once, to bring existing plates over.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS browser_plate_changes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        old_plate VARCHAR(16) NOT NULL,
        old_display VARCHAR(16) NOT NULL,
        new_plate VARCHAR(16) NOT NULL,
        new_display VARCHAR(16) NOT NULL,
        cid VARCHAR(64) NOT NULL,
        price INT NOT NULL DEFAULT 0,
        changed_at INT NOT NULL,
        KEY idx_new (new_plate),
        KEY idx_cid (cid, changed_at)
    )]])
end

local function assetByKey(key)
    return MySQL.single.await('SELECT * FROM browser_plate_assets WHERE plate_key = ?', { key })
end
local function assetById(id)
    id = tonumber(id)
    if not id then return nil end
    return MySQL.single.await('SELECT * FROM browser_plate_assets WHERE id = ?', { id })
end
local function assetByBase(key)
    return MySQL.single.await('SELECT * FROM browser_plate_assets WHERE base_key = ?', { key })
end
local function listingOf(assetId)
    return MySQL.single.await('SELECT * FROM browser_plate_listings WHERE asset_id = ?', { assetId })
end
X.assetByKey, X.assetById, X.assetByBase, X.listingOf = assetByKey, assetById, assetByBase, listingOf

--- Existing personalised plates (bought with the old service, which simply renamed the vehicle) become plates the
--- owner holds, with the vehicle's earlier registration as its original one. Runs at every start; it only adds what is missing.
local function migrateLegacy()
    local rows = MySQL.query.await(
        'SELECT id, old_plate, old_display, new_plate, new_display, cid, price, changed_at FROM browser_plate_changes ORDER BY id') or {}
    if #rows == 0 then return end
    local origin, originDisp, lastDisp, logs = {}, {}, {}, {}
    for _, r in ipairs(rows) do
        local base = origin[r.old_plate] or r.old_plate
        local baseDisp = originDisp[r.old_plate] or r.old_display
        origin[r.old_plate] = nil
        originDisp[r.old_plate] = nil
        origin[r.new_plate] = base
        originDisp[r.new_plate] = baseDisp
        lastDisp[r.new_plate] = r.new_display
        logs[#logs + 1] = { base, r.old_display, r.new_display, r.cid, tonumber(r.price) or 0, tonumber(r.changed_at) or now() }
    end
    local logged = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM browser_plate_log WHERE kind = 'legacy'")) or 0
    if logged == 0 then
        for _, l in ipairs(logs) do
            MySQL.insert.await(
                "INSERT INTO browser_plate_log (base_key, kind, old_display, new_display, cid, price, logged_at) VALUES (?, 'legacy', ?, ?, ?, ?, ?)", l)
        end
    end
    local made = 0
    for newKey, base in pairs(origin) do
        if newKey ~= base and not assetByKey(newKey) then
            local v = Vehicles.find(newKey)
            if v and v.owner ~= nil and tostring(v.owner) ~= '' then
                local ok = pcall(function()
                    MySQL.insert.await(
                        'INSERT INTO browser_plate_assets (plate_key, display, owner, base_key, base_display, created_at) VALUES (?, ?, ?, ?, ?, ?)',
                        { newKey, lastDisp[newKey] or trimPlate(v.plate), tostring(v.owner), base, originDisp[newKey] or base, now() })
                end)
                if ok then made = made + 1 end
            end
        end
    end
    if made > 0 then print(('^5[as-browser]^0 plates: %d existing personalised plates were brought over as plates their owners hold'):format(made)) end
end

MySQL.ready(function()
    createTables()
    local ok, err = pcall(migrateLegacy)
    if not ok then print(('^5[as-browser]^0 plates: bringing existing plates over failed: %s'):format(tostring(err))) end
end)

-- ---------------------------------------------------------------------------------------------
-- Rules and prices
-- ---------------------------------------------------------------------------------------------

--- Tidies what a player typed. Returns the plate as it will be stored ("AB 12" style, upper case, single spaces)
--- and its key (no spaces), or nil plus a reason code: 'empty', 'chars', 'spaces', 'short', 'long'.
function Plates.tidy(input)
    if type(input) ~= 'string' then return nil, 'empty' end
    local s = input:upper():gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if s == '' then return nil, 'empty' end
    if not s:match('^[A-Z0-9 ]+$') then return nil, 'chars' end
    if not cfg('allowSpaces', true) and s:find(' ', 1, true) then return nil, 'spaces' end
    local key = s:gsub(' ', '')
    if #key < (tonumber(cfg('minLength', 2)) or 2) then return nil, 'short' end
    if #s > (tonumber(cfg('maxLength', 8)) or 8) then return nil, 'long' end
    return s, key
end

local function priceFor(key)
    for _, rule in ipairs(cfg('patternPrices', {})) do
        if type(rule.pattern) == 'string' and key:match(rule.pattern) then return tonumber(rule.price) or 0 end
    end
    local byLen = cfg('lengthPrices', {})
    return tonumber(byLen[#key]) or tonumber(cfg('defaultPrice', 150)) or 0
end

local function isBlocked(key)
    for _, w in ipairs(cfg('blocked', {})) do
        if key:find(tostring(w):upper(), 1, true) then return true end
    end
    for _, w in ipairs(cfg('reserved', {})) do
        if key == tostring(w):upper():gsub(' ', '') then return true end
    end
    return false
end

X.isBlocked = isBlocked

--- Whether a registration can be bought right now: true, or false plus 'blocked' / 'taken'.
--- It is taken when a vehicle carries it, a player owns it, or it is the original registration of a vehicle
--- that is wearing a personalised plate (that vehicle gets it back later).
function Plates.availability(key)
    if isBlocked(key) then return false, 'blocked' end
    if Vehicles.find(key) then return false, 'taken' end
    if assetByKey(key) then return false, 'taken' end
    if assetByBase(key) then return false, 'taken' end
    return true
end

--- The registration a vehicle was first given: the plate it wore before a personalised one, or the same plate.
function Plates.identity(key)
    local a = assetByKey(key)
    if a and a.base_key then return a.base_key end
    return key
end

local function reasonText(code)
    local key = 'plates.reason.' .. tostring(code)
    local txt = T(key)
    if txt == key then txt = T('plates.reason.error') end
    return txt
end
local function blockText(code)
    local key = 'plates.block.' .. tostring(code)
    local txt = T(key)
    if txt == key then txt = T('plates.block.error') end
    return txt
end
X.reasonText, X.blockText, X.cfg, X.priceFor, X.trimPlate, X.now = reasonText, blockText, cfg, priceFor, trimPlate, now

local function motResource()
    return (Config.gov and Config.gov.motBooking and Config.gov.motBooking.resource) or 'as-computer'
end

local function siteAddress()
    local c = Config.Sites and Config.Sites.plates
    return c and c.domain or 'lsplates.co.uk'
end
X.siteAddress = siteAddress

-- ---------------------------------------------------------------------------------------------
-- Locks (two players cannot change or buy the same thing at once)
-- ---------------------------------------------------------------------------------------------

local busy = {}
--- lock('p:AB12CDE', 'a:7') returns an unlock function, or nil when any of them is in use.
local function lock(...)
    local keys = { ... }
    for _, k in ipairs(keys) do if busy[k] then return nil end end
    for _, k in ipairs(keys) do busy[k] = true end
    return function() for _, k in ipairs(keys) do busy[k] = nil end end
end
X.lock = lock

-- ---------------------------------------------------------------------------------------------
-- Vehicle checks
-- ---------------------------------------------------------------------------------------------

--- Whether the vehicle is stored, when a garage state column is configured. true when fine or unknown.
local function garaged(plateKey)
    local col = Vehicles.resolveStateColumn(cfg('stateColumn', nil))
    if not col then return true end
    local state, err = Vehicles.column(plateKey, col)
    if err then
        if not P._warned then
            P._warned = true
            print(('^5[as-browser]^0 plates: stateColumn "%s" could not be read from the vehicles table, so vehicles are not checked for being in a garage'):format(tostring(col)))
        end
        return true
    end
    for _, val in ipairs(cfg('garagedValues', { 1 })) do
        if tostring(state) == tostring(val) then return true end
    end
    return false
end

--- Why this vehicle cannot have its registration changed, as a reason code, or nil when it can.
--- `putting` = a plate is being put ON it (the cooldown applies then, not when one is taken off).
local function vehicleBlock(cid, v, d, putting)
    if v.owner ~= cid then return 'notOwner' end
    if d.exempt then return 'exempt' end
    if Browser.vehicleFlag and Browser.vehicleFlag(d.plateKey, 'stolen') then return 'stolen' end
    if putting then
        local hours = tonumber(cfg('cooldownHours', 24)) or 0
        if hours > 0 then
            local last = tonumber(MySQL.scalar.await(
                "SELECT MAX(logged_at) FROM browser_plate_log WHERE base_key = ? AND kind = 'fit'", { Plates.identity(d.plateKey) })) or 0
            if last > 0 and now() - last < hours * HOUR then return 'cooldown' end
        end
    end
    if not garaged(d.plateKey) then return 'notGaraged' end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Keeping ownership straight
-- ---------------------------------------------------------------------------------------------

local function logRow(baseKey, kind, oldDisplay, newDisplay, cid, price)
    return { "INSERT INTO browser_plate_log (base_key, kind, old_display, new_display, cid, price, logged_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
             { baseKey, kind, oldDisplay or '', newDisplay or '', cid or '', whole(price), now() } }
end

--- A plate that is on a vehicle goes with the vehicle. When the vehicle changes hands the plate does too; when the
--- vehicle no longer exists the plate is simply kept by its owner. Runs whenever someone opens the site.
function Plates.sync(cid)
    if not cid then return end
    local owned = Vehicles.ownedBy(cid)
    if #owned > 0 then
        local keys, marks = {}, {}
        for _, v in ipairs(owned) do keys[#keys + 1] = v.plateKey; marks[#marks + 1] = '?' end
        local rows = MySQL.query.await(
            ('SELECT id, plate_key, owner, base_key FROM browser_plate_assets WHERE base_key IS NOT NULL AND plate_key IN (%s)'):format(table.concat(marks, ',')), keys) or {}
        for _, r in ipairs(rows) do
            if r.owner ~= cid then
                MySQL.update.await('UPDATE browser_plate_assets SET owner = ? WHERE id = ? AND base_key IS NOT NULL', { cid, r.id })
                MySQL.insert.await(logRow(r.base_key, 'transfer', '', r.plate_key, cid, 0)[1], logRow(r.base_key, 'transfer', '', r.plate_key, cid, 0)[2])
            end
        end
    end
    local mine = MySQL.query.await('SELECT id, plate_key, base_key FROM browser_plate_assets WHERE owner = ? AND base_key IS NOT NULL', { cid }) or {}
    for _, a in ipairs(mine) do
        local v = Vehicles.find(a.plate_key)
        if not v and X.held and X.held(a.plate_key) then
            -- the car is on a used-car lot (or similar) right now: it still wears the plate
        elseif not v then
            MySQL.update.await('UPDATE browser_plate_assets SET base_key = NULL, base_display = NULL WHERE id = ?', { a.id })
        elseif v.owner ~= cid and v.owner ~= nil then
            MySQL.update.await('UPDATE browser_plate_assets SET owner = ? WHERE id = ? AND base_key IS NOT NULL', { tostring(v.owner), a.id })
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Moving a vehicle's records to its new registration
-- ---------------------------------------------------------------------------------------------

--- Tables that hold the plate as a key (upper case, no spaces). Anything already on the new plate belongs to a
--- vehicle that no longer exists, so it is cleared first.
local function keyTables()
    local list = {
        { 'browser_vehicle_status', 'plate' },
        { 'browser_mot_history', 'plate' },
        { 'browser_mot_reminders', 'plate' },
        { 'browser_vehicle_events', 'plate' },
        { 'browser_vehicle_flags', 'plate' },
        { 'browser_vehicle_owners', 'plate' },
    }
    if Browser.isEnabled('insurance') then list[#list + 1] = { 'browser_insurance_policies', 'plate' } end
    return list
end

local function migration(oldKey, newKey, newDisplay)
    local q = {}
    for _, t in ipairs(keyTables()) do
        q[#q + 1] = { ('DELETE FROM `%s` WHERE `%s` = ?'):format(t[1], t[2]), { newKey } }
        q[#q + 1] = { ('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(t[1], t[2], t[2]), { newKey, oldKey } }
    end
    for _, t in ipairs(cfg('extraTables', {})) do
        local tbl, col = tostring(t.table or ''), tostring(t.column or '')
        if tbl:match('^[%w_]+$') and col:match('^[%w_]+$') then
            q[#q + 1] = { ('UPDATE `%s` SET `%s` = ? WHERE REPLACE(UPPER(`%s`), " ", "") = ?'):format(tbl, col, col), { newDisplay, oldKey } }
        end
    end
    return q
end

local function bankLine(cid, label, amount)
    if not amount or amount == 0 then return end
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, { label = label, amount = amount, category = 'government', counterparty = cfg('authority', 'DVLA') })
    end)
end
X.bankLine = bankLine

local function mail(src, cid, subject, body)
    Bridge.sendPhoneMail(src, cid, cfg('mailFrom', { name = 'DVLA', email = 'noreply@lsplates.co.uk' }), subject, body)
end
X.mail = mail

--- Everything that follows a registration change: as-computer (MOT records and bookings), the vehicle's history,
--- the server event and the optional hook.
local function afterChange(src, cid, oldDisplay, newDisplay)
    local res = motResource()
    if GetResourceState(res) == 'started' then
        local okc, err = pcall(function() return exports[res]:renamePlate(oldDisplay, newDisplay) end)
        if not okc then print(('^5[as-browser]^0 plates: %s:renamePlate failed: %s'):format(res, tostring(err))) end
    end
    if Browser.logVehicleEvent then
        Browser.logVehicleEvent(newDisplay, 'plate_change', T('plates.eventText', oldDisplay, newDisplay))
    end
    if Plates.keysChanged then
        local okk, err = pcall(Plates.keysChanged, oldDisplay, newDisplay)
        if not okk then print(('^5[as-browser]^0 plates: updating vehicle keys failed: %s'):format(tostring(err))) end
    end
    TriggerEvent('as-browser:plateChanged', oldDisplay, newDisplay, cid, src)
    local hook = cfg('onChanged', nil)
    if type(hook) == 'function' then
        local okh, err = pcall(hook, oldDisplay, newDisplay, cid, src)
        if not okh then print(('^5[as-browser]^0 plates: plates.onChanged failed: %s'):format(tostring(err))) end
    end
end

local function vehicleInfo(v, d)
    return { plate = trimPlate(v.plate), plateKey = v.plateKey, make = d.make, model = d.model, colour = d.colour }
end

-- ---------------------------------------------------------------------------------------------
-- Putting a plate on a vehicle / taking it off
-- ---------------------------------------------------------------------------------------------

--- Checks the vehicle a plate is going onto. Returns the vehicle and its description, or nil plus a message.
local function checkTarget(cid, targetKey, assetKey)
    local key = Vehicles.normalizePlate(tostring(targetKey or ''))
    local B = key and Vehicles.find(key)
    if not B or B.owner ~= cid then return nil, blockText('notOwner') end
    local d = Vehicles.describe(B)
    if assetKey and B.plateKey == assetKey then return nil, blockText('already') end
    if assetByKey(B.plateKey) then return nil, blockText('hasCustom') end
    local why = vehicleBlock(cid, B, d, true)
    if why then return nil, blockText(why) end
    return B, d
end
X.checkTarget = checkTarget

--- Takes a plate off the vehicle it is on. The vehicle gets its original registration back and everything that
--- belongs to it moves with it. Returns a result table, or nil plus a message. `charge` = the removal fee applies.
local function doDetach(src, cid, asset, charge)
    if not asset.base_key then return {} end
    local A = Vehicles.find(asset.plate_key)
    if not A and X.held and X.held(asset.plate_key) then return nil, blockText('held') end
    if not A then
        MySQL.update.await('UPDATE browser_plate_assets SET base_key = NULL, base_display = NULL WHERE id = ?', { asset.id })
        return {}
    end
    if A.owner ~= cid then Plates.sync(cid); return nil, blockText('notOwner') end
    local dA = Vehicles.describe(A)
    local why = vehicleBlock(cid, A, dA, false)
    if why then return nil, blockText(why) end
    if Vehicles.find(asset.base_key) then return nil, blockText('baseTaken') end

    local unlock = lock('p:' .. asset.plate_key, 'p:' .. asset.base_key)
    if not unlock then return nil, T('plates.err.busy') end
    local fee = charge and whole(cfg('removeFee', 0)) or 0
    if fee > 0 and not Bridge.removeMoney(src, Config.account, fee, 'personalised-plate-remove') then
        unlock()
        return nil, T('shell.err.insufficientFunds')
    end
    local baseDisplay = asset.base_display or asset.base_key
    local extra = migration(asset.plate_key, asset.base_key, baseDisplay)
    extra[#extra + 1] = { 'UPDATE browser_plate_assets SET base_key = NULL, base_display = NULL WHERE id = ? AND owner = ?', { asset.id, cid } }
    extra[#extra + 1] = logRow(asset.base_key, 'remove', asset.display, baseDisplay, cid, fee)
    local ok = Vehicles.setPlates({ { oldKey = asset.plate_key, newPlate = baseDisplay, owner = cid } }, extra)
    if not ok then
        if fee > 0 then Bridge.addMoney(src, Config.account, fee, 'personalised-plate-refund') end
        unlock()
        return nil, T('plates.err.notCharged')
    end
    afterChange(src, cid, asset.display, baseDisplay)
    unlock()
    if fee > 0 then bankLine(cid, T('plates.bank.remove', asset.display), -fee) end
    return { returned = vehicleInfo({ plate = baseDisplay, plateKey = asset.base_key }, dA), paid = fee }
end
X.doDetach = doDetach

--- Puts a plate on a vehicle. A plate that is on another vehicle is taken off it first (that vehicle gets its original
--- registration back) in the same step.
local function doFit(src, cid, asset, targetKey)
    if asset.owner ~= cid then return nil, blockText('notPlateOwner') end
    if listingOf(asset.id) then return nil, blockText('listed') end
    local B, dB = checkTarget(cid, targetKey, asset.plate_key)
    if not B then return nil, dB end

    local A, dA
    if asset.base_key then
        A = Vehicles.find(asset.plate_key)
        if A then
            if A.owner ~= cid then Plates.sync(cid); return nil, blockText('notOwner') end
            dA = Vehicles.describe(A)
            local whyA = vehicleBlock(cid, A, dA, false)
            if whyA then return nil, blockText(whyA) end
            if Vehicles.find(asset.base_key) then return nil, blockText('baseTaken') end
        elseif X.held and X.held(asset.plate_key) then
            return nil, blockText('held')
        end
    end

    local unlock = lock('p:' .. asset.plate_key, 'p:' .. B.plateKey)
    if not unlock then return nil, T('plates.err.busy') end
    local fee = whole(cfg('assignFee', 0))
    if fee > 0 and not Bridge.removeMoney(src, Config.account, fee, 'personalised-plate-fit') then
        unlock()
        return nil, T('shell.err.insufficientFunds')
    end

    local changes, extra = {}, {}
    local baseDisplay = asset.base_display or asset.base_key
    if A then
        changes[#changes + 1] = { oldKey = asset.plate_key, newPlate = baseDisplay, owner = cid }
        for _, q in ipairs(migration(asset.plate_key, asset.base_key, baseDisplay)) do extra[#extra + 1] = q end
        extra[#extra + 1] = logRow(asset.base_key, 'remove', asset.display, baseDisplay, cid, 0)
    end
    local oldB = trimPlate(B.plate)
    changes[#changes + 1] = { oldKey = B.plateKey, newPlate = asset.display, owner = cid }
    for _, q in ipairs(migration(B.plateKey, asset.plate_key, asset.display)) do extra[#extra + 1] = q end
    extra[#extra + 1] = { 'UPDATE browser_plate_assets SET base_key = ?, base_display = ? WHERE id = ? AND owner = ?', { B.plateKey, oldB, asset.id, cid } }
    extra[#extra + 1] = logRow(B.plateKey, 'fit', oldB, asset.display, cid, fee)

    local ok = Vehicles.setPlates(changes, extra)
    if not ok then
        if fee > 0 then Bridge.addMoney(src, Config.account, fee, 'personalised-plate-refund') end
        unlock()
        return nil, T('plates.err.notCharged')
    end
    if A then afterChange(src, cid, asset.display, baseDisplay) end
    afterChange(src, cid, oldB, asset.display)
    unlock()

    if fee > 0 then bankLine(cid, T('plates.bank.fit', asset.display), -fee) end
    return {
        plate = asset.display, key = asset.plate_key, oldPlate = oldB, paid = fee, now = now(),
        vehicle = vehicleInfo({ plate = oldB, plateKey = B.plateKey }, dB),
        returned = A and vehicleInfo({ plate = baseDisplay, plateKey = asset.base_key }, dA) or nil,
    }
end
X.doFit = doFit

-- ---------------------------------------------------------------------------------------------
-- Requests from the site
-- ---------------------------------------------------------------------------------------------

local function statusOf(a, listing)
    if listing then return 'listed' end
    if a.base_key then return 'fitted' end
    return 'kept'
end

--- The rules, the price list, the player's vehicles and the plates they own.
Browser.handler('plates', 'state', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    if Plates.deliverPayouts then Plates.deliverPayouts(cid, src) end
    Plates.sync(cid)

    local prices = {}
    for len, price in pairs(cfg('lengthPrices', {})) do prices[#prices + 1] = { length = tonumber(len), price = tonumber(price) } end
    table.sort(prices, function(a, b) return a.length < b.length end)

    local owned = Vehicles.ownedBy(cid)
    local byKey, keys, marks = {}, {}, {}
    for i, v in ipairs(owned) do
        if i > 50 then break end
        keys[#keys + 1] = v.plateKey; marks[#marks + 1] = '?'
    end
    if #keys > 0 then
        for _, a in ipairs(MySQL.query.await(('SELECT * FROM browser_plate_assets WHERE plate_key IN (%s)'):format(table.concat(marks, ',')), keys) or {}) do
            byKey[a.plate_key] = a
        end
    end
    local vehicles, vehByKey = {}, {}
    for i, v in ipairs(owned) do
        if i > 50 then break end
        local d = Vehicles.describe(v)
        if not d.exempt then
            local a = byKey[v.plateKey]
            local reason
            if a and a.base_key then reason = blockText('hasCustom') else
                local why = vehicleBlock(cid, v, d, true)
                reason = why and blockText(why) or nil
            end
            local info = vehicleInfo(v, d)
            info.original = a and a.base_display or nil
            info.custom = (a and a.base_key) and { id = a.id, plate = a.display } or nil
            info.canFit = reason == nil
            info.reason = reason
            vehicles[#vehicles + 1] = info
            vehByKey[v.plateKey] = info
        end
    end

    local listings = {}
    for _, l in ipairs(MySQL.query.await('SELECT asset_id, price FROM browser_plate_listings WHERE seller = ?', { cid }) or {}) do listings[l.asset_id] = l end
    local plates = {}
    for _, a in ipairs(MySQL.query.await('SELECT * FROM browser_plate_assets WHERE owner = ? ORDER BY created_at DESC, id DESC LIMIT 200', { cid }) or {}) do
        local l = listings[a.id]
        local st = statusOf(a, l)
        local item = { id = a.id, plate = a.display, key = a.plate_key, status = st, price = l and tonumber(l.price) or nil, since = tonumber(a.created_at) }
        if st == 'fitted' then
            item.original = a.base_display
            item.vehicle = vehByKey[a.plate_key]
        end
        plates[#plates + 1] = item
    end

    local market = cfg('market', {})
    return {
        rules = { min = tonumber(cfg('minLength', 2)) or 2, max = tonumber(cfg('maxLength', 8)) or 8, spaces = cfg('allowSpaces', true) },
        prices = prices, defaultPrice = tonumber(cfg('defaultPrice', 150)) or 0, assignFee = whole(cfg('assignFee', 0)), removeFee = whole(cfg('removeFee', 0)),
        cooldownHours = tonumber(cfg('cooldownHours', 24)) or 0,
        market = { enabled = market.enabled ~= false, feePercent = tonumber(market.feePercent) or 0, minPrice = whole(market.minPrice, 1), maxPrice = whole(market.maxPrice, 5000000),
                   maxListings = whole(market.maxListings, 10) },
        vehicles = vehicles, plates = plates, now = now(),
    }
end)

--- Is this registration free, and what would it cost? data = { plate }
Browser.handler('plates', 'check', function(src, data)
    local display, key = Plates.tidy(tostring(data.plate or ''))
    if not display then return { ok = false, reason = reasonText(key) } end
    local free, why = Plates.availability(key)
    if not free then return { ok = false, plate = display, reason = reasonText(why) } end
    return { ok = true, plate = display, key = key, price = priceFor(key), assignFee = whole(cfg('assignFee', 0)) }
end)

--- Buy a new plate. data = { plate = 'HELLO 1', vehicle = 'AB12CDE' (optional: put it on this vehicle straight away) }
Browser.handler('plates', 'buy', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    Plates.sync(cid)
    local display, key = Plates.tidy(tostring(data.plate or ''))
    if not display then return nil, reasonText(key) end

    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM browser_plate_assets WHERE owner = ?', { cid })) or 0
    if count >= whole(cfg('maxPlates', 30)) then return nil, T('plates.err.tooMany') end

    local vehicleKey = tostring(data.vehicle or '') ~= '' and tostring(data.vehicle) or nil
    if vehicleKey then
        local B, why = checkTarget(cid, vehicleKey, key)
        if not B then return nil, why end
    end

    local unlock = lock('p:' .. key)
    if not unlock then return nil, T('plates.err.busy') end
    local free, reason = Plates.availability(key)
    if not free then unlock(); return nil, reasonText(reason) end

    local price = priceFor(key)
    if price > 0 and not Bridge.removeMoney(src, Config.account, price, 'personalised-plate') then
        unlock()
        return nil, T('shell.err.insufficientFunds')
    end
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT INTO browser_plate_assets (plate_key, display, owner, created_at) VALUES (?, ?, ?, ?)', { key, display, cid, now() })
    end)
    if not ok or not id then
        if price > 0 then Bridge.addMoney(src, Config.account, price, 'personalised-plate-refund') end
        unlock()
        return nil, T('plates.err.notCharged')
    end
    MySQL.insert.await(logRow('', 'buy', '', display, cid, price)[1], logRow('', 'buy', '', display, cid, price)[2])
    unlock()

    bankLine(cid, T('plates.bank.buy', display), -price)
    mail(src, cid, T('plates.mail.buySubject', display),
        T('plates.mail.buyBody', Bridge.getCharacterName(src), display, Config.currency, price, siteAddress()))

    local out = { id = id, plate = display, key = key, paid = price, now = now() }
    if vehicleKey then
        local asset = assetById(id)
        local res, err = doFit(src, cid, asset, vehicleKey)
        if res then
            out.fitted = res
            out.paid = price + (res.paid or 0)
        else
            out.fitError = err
        end
    end
    return out
end)

--- Put an owned plate on a vehicle. data = { asset = id, vehicle = 'AB12CDE' }
Browser.handler('plates', 'fit', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    Plates.sync(cid)
    local asset = assetById(data.asset)
    if not asset or asset.owner ~= cid then return nil, blockText('notPlateOwner') end
    return doFit(src, cid, asset, data.vehicle)
end)

--- Take a plate off its vehicle: the vehicle gets its own registration back and the plate is kept. data = { asset = id }
Browser.handler('plates', 'remove', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    Plates.sync(cid)
    local asset = assetById(data.asset)
    if not asset or asset.owner ~= cid then return nil, blockText('notPlateOwner') end
    if not asset.base_key then return nil, blockText('notFitted') end
    local res, err = doDetach(src, cid, asset, true)
    if not res then return nil, err end
    res.plate = asset.display
    res.now = now()
    return res
end)

-- ---------------------------------------------------------------------------------------------
-- Exports for other resources
-- ---------------------------------------------------------------------------------------------

--- true when a player owns this registration, or a vehicle will get it back as its original one. Vehicle dealers
--- and plate generators should refuse these.
exports('isPlateReserved', function(plate)
    local key = Vehicles.normalizePlate(plate)
    if not key then return false end
    return assetByKey(key) ~= nil or assetByBase(key) ~= nil
end)

--- { plate, owner, onVehicle = 'AB12CDE' (the vehicle's original registration) or nil, listedFor = price or nil } for a
--- personalised plate, or nil when nobody owns it.
exports('getPlateInfo', function(plate)
    local key = Vehicles.normalizePlate(plate)
    local a = key and assetByKey(key)
    if not a then return nil end
    local l = listingOf(a.id)
    return { plate = a.display, owner = a.owner, onVehicle = a.base_display, listedFor = l and tonumber(l.price) or nil }
end)

--- The registration a vehicle was first given: pass the plate it wears now (a personalised one or its own).
exports('getOriginalPlate', function(plate)
    local key = Vehicles.normalizePlate(plate)
    if not key then return nil end
    local a = assetByKey(key)
    return a and a.base_display or plate
end)

--- The personalised plates a character owns: { { plate, onVehicle, listedFor }, ... }
exports('getPlayerPlates', function(citizenId)
    local out = {}
    for _, a in ipairs(MySQL.query.await('SELECT * FROM browser_plate_assets WHERE owner = ? ORDER BY id', { tostring(citizenId or '') }) or {}) do
        local l = listingOf(a.id)
        out[#out + 1] = { plate = a.display, onVehicle = a.base_display, listedFor = l and tonumber(l.price) or nil }
    end
    return out
end)
