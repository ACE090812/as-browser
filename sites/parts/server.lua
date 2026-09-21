-- Trade parts shop (LS Parts Direct): catalogue, checkout and order tracking.
-- Bought with the job's society account, delivered by Postal Prime (hidden from the phone app, tracked here).
-- Desktop only: it is registered as a desktop-only site, so the phone browser never lists or opens it.
local P = Config.parts

local function log(fmt, ...) print(('^5[as-browser:parts]^0 ' .. fmt):format(...)) end
local function now() return os.time() end

Browser.defineSite('parts', {
    title       = P.name,
    description = T('parts.description'),
    keywords    = Browser.words(T('parts.keywords')),
    category    = T('parts.siteCategory'),
    icon        = P.logo or '🔧',
    color       = '#ffb703',
    desktopOnly = true,
    pages = {
        { path = '/orders',   title = T('parts.page.orders.title'),   description = T('parts.page.orders.description'),   keywords = Browser.words(T('parts.page.orders.keywords')) },
        { path = '/basket',   title = T('parts.page.basket.title'),   description = T('parts.page.basket.description'),   keywords = Browser.words(T('parts.page.basket.keywords')) },
    },
})

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_parts_orders (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ref VARCHAR(24) NOT NULL,
        citizenid VARCHAR(64) NOT NULL,
        buyer_name VARCHAR(80) NOT NULL,
        job VARCHAR(48) NOT NULL,
        account VARCHAR(64) NOT NULL,
        items TEXT NOT NULL,
        subtotal INT NOT NULL,
        fee INT NOT NULL DEFAULT 0,
        total INT NOT NULL,
        delivery VARCHAR(8) NOT NULL,
        dest_label VARCHAR(120) NOT NULL DEFAULT '',
        status VARCHAR(12) NOT NULL DEFAULT 'pending',
        pp_id VARCHAR(40) NULL,
        created_at INT NOT NULL,
        updated_at INT NOT NULL,
        UNIQUE KEY uq_ref (ref),
        KEY idx_job (job, id),
        KEY idx_buyer (citizenid, id)
    ) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    -- Tables made by an earlier version used the database default (often not utf8mb4), and the part icons are
    -- emoji, so saving an order failed with "Incorrect string value". Convert once when needed.
    pcall(function()
        local row = MySQL.single.await(
            "SELECT TABLE_COLLATION AS c FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'browser_parts_orders'")
        if row and row.c and not tostring(row.c):find('^utf8mb4') then
            MySQL.query.await('ALTER TABLE browser_parts_orders CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
            log('converted browser_parts_orders to utf8mb4 (was %s)', tostring(row.c))
        end
    end)
end)

-- ---------------------------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------------------------

local ITEMS, ITEM_LIST, CATEGORIES = {}, {}, {}

local function unit(price)
    return math.max(0, math.floor((tonumber(price) or 0) * (1 - (tonumber(P.discount) or 0)) + 0.5))
end

do
    local cats = {}
    for _, c in ipairs(P.categories or {}) do
        cats[c.id] = true
        CATEGORIES[#CATEGORIES + 1] = { id = c.id, label = c.label, icon = c.icon, desc = c.desc }
    end
    for _, it in ipairs(P.items or {}) do
        if type(it.id) ~= 'string' or it.id == '' or ITEMS[it.id] then
            log('^1skipping a part with a missing or duplicate id^0 (%s)', tostring(it.id))
        elseif not cats[it.cat] then
            log('^1skipping "%s": unknown category "%s"^0', it.id, tostring(it.cat))
        elseif type(it.item) ~= 'string' or it.item == '' then
            log('^1skipping "%s": no item name (the ox_inventory item)^0', it.id)
        else
            ITEMS[it.id] = it
            ITEM_LIST[#ITEM_LIST + 1] = {
                id = it.id, cat = it.cat, label = it.label, brand = it.brand or '', price = it.price, trade = unit(it.price),
                icon = it.icon or '📦', tint = tonumber(it.tint) or 6, popular = it.popular == true,
                fits = it.fits or '', use = it.use or '', desc = it.desc or '',
            }
        end
    end
end

-- Warn about item names that do not exist in ox_inventory, so a typo in the config shows up at start.
CreateThread(function()
    Wait(9000)
    if GetResourceState('ox_inventory') ~= 'started' then return end
    local missing = {}
    for _, it in pairs(ITEMS) do
        local ok, def = pcall(function() return exports.ox_inventory:Items(it.item) end)
        if not ok or not def then missing[#missing + 1] = it.item end
    end
    table.sort(missing)
    if #missing > 0 then
        log('^3%d shop item(s) do not exist in ox_inventory^0 (buyers would get nothing): %s', #missing, table.concat(missing, ', '))
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Who is buying
-- ---------------------------------------------------------------------------------------------

local JOBS = {}
for _, j in ipairs(P.jobs or {}) do JOBS[j] = true end

--- cid, jobGrade for a mechanic allowed to use the shop; nil when not allowed.
local function actor(src)
    local cid = Bridge.getIdentifier(src)
    local jg = Bridge.getJobGrade(src)
    if not cid or not jg or not JOBS[jg.name] then return nil end
    return cid, jg
end

local function limitFor(jg)
    local l = P.limits or {}
    if jg.isBoss then return tonumber(l.boss) or 0 end
    local g = l.grades and l.grades[jg.grade]
    if g ~= nil then return tonumber(g) or 0 end
    return tonumber(l.default) or 0
end

local function accountOf(jg)
    local f = P.accountFor
    return (type(f) == 'function' and f(jg.name)) or jg.name
end

local function money(n) return ('%s%d'):format(Config.currency or '£', n) end

local lastPostalWarn = 0
local function postalUp()
    local st = GetResourceState('as-postalprime')
    if st == 'started' then return true end
    local now = GetGameTimer and GetGameTimer() or 0
    if now - lastPostalWarn > 60000 or lastPostalWarn == 0 then
        lastPostalWarn = now
        log('as-postalprime state is "%s" (needs "started"). Run: ensure as-postalprime (start order: as-lockerprops, sd-phone, as-postalprime, as-browser) and check the console for its start errors.', tostring(st))
    end
    return false
end

local function deliveryInfo(cid)
    if not postalUp() then return nil end
    local ok, info = pcall(function() return exports['as-postalprime']:getDeliveryInfo(cid) end)
    if not ok or type(info) ~= 'table' then
        log('as-postalprime getDeliveryInfo failed: %s (is the parts patch installed in as-postalprime?)', tostring(info))
        return nil
    end
    return info
end

-- ---------------------------------------------------------------------------------------------
-- init: everything the page needs to draw itself
-- ---------------------------------------------------------------------------------------------

local function storeInfo()
    return { name = P.name, tagline = P.tagline, logo = P.logo or '🔧', footer = P.footer or {}, discount = tonumber(P.discount) or 0 }
end

--- This job's business drop-off from the config, or nil (no entry = no business delivery for the job).
local function businessFor(jobName)
    local b = P.businesses and P.businesses[jobName]
    -- coords may be a vec4 (a userdata in FiveM, so type() is not 'table') or a plain { x, y, z, w } table
    if type(b) ~= 'table' or b.coords == nil or tonumber(b.coords.x) == nil or type(b.stash) ~= 'table' or not b.stash.id then return nil end
    return b
end

Browser.handler('parts', 'init', function(src)
    local cid, jg = actor(src)
    if not cid then return { allowed = false, store = storeInfo() } end

    local di = deliveryInfo(cid)
    local d = P.delivery or {}
    local home = { enabled = false, fee = 0, properties = {} }
    local locker = { enabled = false, fee = 0, lockers = {} }
    local business = { enabled = false, fee = 0, label = '' }
    if di then
        local b = businessFor(jg.name)
        business.enabled = d.business ~= nil and d.business.enabled == true and b ~= nil and di.business ~= nil and di.business.enabled == true
        business.fee = d.business and tonumber(d.business.fee) or 0
        business.label = b and b.label or ''
        home.enabled = d.home and d.home.enabled == true and di.home and di.home.enabled == true
        home.fee = d.home and tonumber(d.home.fee) or 0
        home.properties = (di.home and di.home.properties) or {}
        locker.enabled = d.locker and d.locker.enabled == true and #(di.lockers or {}) > 0
        locker.fee = d.locker and tonumber(d.locker.fee) or 0
        locker.lockers = di.lockers or {}
    end

    local bal = PartsBank.balance(accountOf(jg))
    return {
        allowed    = true,
        store      = storeInfo(),
        categories = CATEGORIES,
        items      = ITEM_LIST,
        me         = { name = Bridge.getCharacterName(src), job = jg.label, grade = jg.gradeLabel, isBoss = jg.isBoss },
        account    = { label = jg.label, balance = bal, ready = PartsBank.name() ~= nil },
        limit      = limitFor(jg),
        delivery   = { home = home, locker = locker, business = business, freeOver = tonumber(d.freeOver) or 0, postal = di ~= nil },
        limits     = { maxQty = P.maxQty or 20, maxLines = P.maxLines or 30 },
    }
end)

-- ---------------------------------------------------------------------------------------------
-- order: place an order
-- ---------------------------------------------------------------------------------------------

local placing = {}   -- cid -> true while an order is being placed (blocks a double click)

local PP_ERRORS = {
    busy = 'parts.err.busy', bad_property = 'parts.err.badProperty', bad_locker = 'parts.err.badLocker',
    home_unavailable = 'parts.err.homeUnavailable',
    business_unavailable = 'parts.err.businessUnavailable', bad_dropoff = 'parts.err.businessUnavailable',
}

Browser.handler('parts', 'order', function(src, data)
    local cid, jg = actor(src)
    if not cid then return nil, T('parts.err.notAllowed') end
    if not PartsBank.name() then return nil, T('parts.err.noBank') end
    if not postalUp() then return nil, T('parts.err.noPostal') end
    if placing[cid] then return nil, T('parts.err.busyOrder') end
    if type(data.items) ~= 'table' then return nil, T('parts.err.emptyBasket') end

    -- Lines: rebuilt from the config, so a modified page can never change a price.
    local ids = {}
    for id in pairs(data.items) do ids[#ids + 1] = tostring(id) end
    table.sort(ids)
    if #ids == 0 then return nil, T('parts.err.emptyBasket') end
    if #ids > (P.maxLines or 30) then return nil, T('parts.err.tooManyLines') end

    local lines, parcelItems, subtotal = {}, {}, 0
    for _, id in ipairs(ids) do
        local it = ITEMS[id]
        local qty = math.floor(tonumber(data.items[id]) or 0)
        if not it then return nil, T('parts.err.gone') end
        if qty < 1 then return nil, T('parts.err.emptyBasket') end
        if qty > (P.maxQty or 20) then return nil, T('parts.err.tooMany', P.maxQty or 20, it.label) end
        local price = unit(it.price)
        subtotal = subtotal + price * qty
        lines[#lines + 1] = { id = it.id, label = it.label, icon = it.icon or '📦', qty = qty, price = price }
        parcelItems[#parcelItems + 1] = { item = it.item, label = it.label, icon = it.icon or '📦', qty = qty }
    end

    -- Delivery
    local d = P.delivery or {}
    local method = data.delivery
    if method ~= 'home' and method ~= 'locker' and method ~= 'business' then return nil, T('parts.err.pickDelivery') end
    if not (d[method] and d[method].enabled) then return nil, T('parts.err.pickDelivery') end
    local di = deliveryInfo(cid)
    if not di then return nil, T('parts.err.noPostal') end

    local destLabel, propertyKey, lockerId, dropoff
    if method == 'business' then
        local b = businessFor(jg.name)
        if not (b and di.business and di.business.enabled) then return nil, T('parts.err.businessUnavailable') end
        destLabel = b.label or jg.label
        dropoff = { key = jg.name, job = jg.name, label = destLabel, coords = { x = b.coords.x, y = b.coords.y, z = b.coords.z, w = b.coords.w or 0.0 }, stash = b.stash }
    elseif method == 'home' then
        if not (di.home and di.home.enabled) then return nil, T('parts.err.homeUnavailable') end
        propertyKey = tostring(data.propertyKey or '')
        for _, p in ipairs(di.home.properties or {}) do
            if p.key == propertyKey then destLabel = p.label break end
        end
        if not destLabel then return nil, T('parts.err.badProperty') end
    else
        lockerId = tostring(data.lockerId or '')
        for _, l in ipairs(di.lockers or {}) do
            if l.id == lockerId then destLabel = l.label break end
        end
        if not destLabel then return nil, T('parts.err.badLocker') end
    end

    local fee = tonumber(d[method].fee) or 0
    if (tonumber(d.freeOver) or 0) > 0 and subtotal >= d.freeOver then fee = 0 end
    local total = subtotal + fee

    local limit = limitFor(jg)
    if limit > 0 and total > limit then return nil, T('parts.err.overLimit', money(limit)) end

    placing[cid] = true
    SetTimeout(20000, function() placing[cid] = nil end)   -- never leave a buyer locked out if something goes wrong
    local account = accountOf(jg)
    local name = Bridge.getCharacterName(src)
    local stamp = now()

    local insOk, rowId = pcall(MySQL.insert.await,
        'INSERT INTO browser_parts_orders (ref, citizenid, buyer_name, job, account, items, subtotal, fee, total, delivery, dest_label, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { 'T' .. GetGameTimer() .. math.random(1000, 9999), cid, name:sub(1, 80), jg.name, account, json.encode(lines),
          subtotal, fee, total, method, destLabel:sub(1, 120), 'pending', stamp, stamp })
    if not insOk or not rowId then
        if not insOk then log('saving the order failed: %s', tostring(rowId)) end
        placing[cid] = nil
        return nil, T('parts.err.generic')
    end
    local ref = (P.refPrefix or 'LSP-') .. (10000 + rowId)
    MySQL.update.await('UPDATE browser_parts_orders SET ref = ? WHERE id = ?', { ref, rowId })

    local function abort(message)
        MySQL.update.await('DELETE FROM browser_parts_orders WHERE id = ?', { rowId })
        placing[cid] = nil
        return nil, message
    end

    if not PartsBank.remove(account, total, ('%s %s'):format(P.name, ref)) then
        return abort(T('parts.err.noFunds', jg.label))
    end

    local okCall, ok, err, ppId = pcall(function()
        return exports['as-postalprime']:createParcel(cid, {
            ref = ref, sender = P.name, hidden = true,
            delivery = method, propertyKey = propertyKey, lockerId = lockerId, dropoff = dropoff,
            prepSeconds = d.prepSeconds or 120, expireSeconds = d.lockerHoldSeconds or 172800,
            items = parcelItems,
        })
    end)
    if not okCall or not ok then
        PartsBank.add(account, total, ('%s %s refund'):format(P.name, ref))
        if not okCall then log('createParcel failed: %s (is the parts patch installed in as-postalprime?)', tostring(ok)) end
        return abort(T(PP_ERRORS[err or ''] or 'parts.err.generic'))
    end

    MySQL.update.await("UPDATE browser_parts_orders SET status = 'placed', pp_id = ?, updated_at = ? WHERE id = ?", { ppId and tostring(ppId) or nil, now(), rowId })
    placing[cid] = nil
    return { ref = ref, total = total }
end)

-- ---------------------------------------------------------------------------------------------
-- Orders and tracking
-- ---------------------------------------------------------------------------------------------

local STEP = { preparing = 0, waiting = 1, collecting = 2, out = 2, ready = 3, delivered = 3, collected = 4 }

local function refund(row, why)
    if P.delivery and P.delivery.refundExpired == false then return end
    PartsBank.add(row.account, row.total, ('%s %s %s'):format(P.name, row.ref, why or 'refund'))
end

--- Marks an order collected. Safe to call more than once.
local function markCollected(ref)
    MySQL.update.await("UPDATE browser_parts_orders SET status = 'collected', updated_at = ? WHERE ref = ? AND status = 'placed'", { now(), ref })
end

--- Marks an uncollected parcel as returned and refunds the society exactly once.
local function markReturned(ref)
    local row = MySQL.single.await("SELECT ref, account, total FROM browser_parts_orders WHERE ref = ? AND status = 'placed'", { ref })
    if not row then return end
    local changed = MySQL.update.await("UPDATE browser_parts_orders SET status = 'returned', updated_at = ? WHERE ref = ? AND status = 'placed'", { now(), ref })
    if changed and changed > 0 then refund(row, 'returned') end
end

local function ours(ref)
    local prefix = P.refPrefix or 'LSP-'
    return type(ref) == 'string' and ref:sub(1, #prefix) == prefix
end

AddEventHandler('as-postalprime:parcelCollected', function(cid, ref) if ours(ref) then markCollected(ref) end end)
AddEventHandler('as-postalprime:parcelExpired', function(cid, ref) if ours(ref) then markReturned(ref) end end)

Browser.handler('parts', 'orders', function(src)
    local cid, jg = actor(src)
    if not cid then return nil, T('parts.err.notAllowed') end

    local rows = MySQL.query.await(
        "SELECT ref, citizenid, buyer_name, items, subtotal, fee, total, delivery, dest_label, status, created_at FROM browser_parts_orders WHERE job = ? AND status <> 'pending' ORDER BY id DESC LIMIT ?",
        { jg.name, P.historyRows or 60 }) or {}

    -- Live Postal Prime status for parcels still on their way, one lookup per buyer.
    local live = {}
    if postalUp() then
        for _, r in ipairs(rows) do
            if r.status == 'placed' and not live[r.citizenid] then
                local ok, list = pcall(function() return exports['as-postalprime']:getParcels(r.citizenid, P.refPrefix or 'LSP-') end)
                local map = {}
                if ok and type(list) == 'table' then for _, p in ipairs(list) do map[p.ref] = p end end
                live[r.citizenid] = map
            end
        end
    end

    local out = {}
    for _, r in ipairs(rows) do
        local status, step, code, courier, deliveredBy = r.status, 0, nil, nil, nil
        local pp = live[r.citizenid] and live[r.citizenid][r.ref]
        if status == 'placed' and pp then
            if pp.status == 'collected' then
                markCollected(r.ref); status = 'collected'
            elseif pp.status == 'expired' then
                markReturned(r.ref); status = 'returned'
            else
                step = STEP[pp.status] or 0
                courier, deliveredBy = pp.courier, pp.deliveredBy
                if r.citizenid == cid then code = pp.code end
            end
        elseif status == 'placed' then
            status = 'unknown'
        end
        if status == 'collected' then step = 4 end

        local ok, items = pcall(json.decode, r.items)
        out[#out + 1] = {
            ref = r.ref, buyer = r.buyer_name, mine = r.citizenid == cid,
            items = ok and items or {}, subtotal = r.subtotal, fee = r.fee, total = r.total,
            delivery = r.delivery, dest = r.dest_label, state = status, step = step,
            code = code, courier = courier, deliveredBy = deliveredBy, createdAt = r.created_at,
        }
    end
    return { orders = out }
end)
