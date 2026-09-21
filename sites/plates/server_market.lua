-- LS Plates marketplace: players sell personalised plates to each other.
--
-- Listing a plate that is on a vehicle takes it off first (the vehicle gets its original registration back).
-- The buyer pays the asking price. The seller receives it minus the transfer fee, straight away when they are online,
-- otherwise the next time they are (browser_plate_payouts is claimed row by row before money is paid, so a payout
-- can never be paid twice).
local X = Plates.x
local cfg, now, whole = X.cfg, X.now, function(v, d) return math.floor(tonumber(v) or d or 0) end

local function M(key, default)
    local m = cfg('market', {})
    if m[key] == nil then return default end
    return m[key]
end

local function enabled() return M('enabled', true) ~= false end

local function feeOf(price)
    local pct = tonumber(M('feePercent', 0)) or 0
    if pct <= 0 then return 0 end
    return math.floor(price * pct / 100)
end

-- ---------------------------------------------------------------------------------------------
-- Paying sellers
-- ---------------------------------------------------------------------------------------------

--- Pays out what a character is owed. `src` is their server id (they must be online).
function Plates.deliverPayouts(cid, src)
    if not cid or not src then return 0 end
    local rows = MySQL.query.await('SELECT id, amount, note FROM browser_plate_payouts WHERE cid = ? AND settled = 0 ORDER BY id', { cid }) or {}
    local total = 0
    for _, r in ipairs(rows) do
        local claimed = MySQL.update.await('UPDATE browser_plate_payouts SET settled = 1 WHERE id = ? AND settled = 0', { r.id })
        if claimed == 1 then
            local ok = Bridge.addMoney(src, M('payoutAccount', 'bank'), tonumber(r.amount) or 0, 'personalised-plate-sale')
            if ok then
                total = total + (tonumber(r.amount) or 0)
                X.bankLine(cid, T('plates.bank.sale', r.note), tonumber(r.amount) or 0)
            else
                MySQL.update.await('UPDATE browser_plate_payouts SET settled = 0 WHERE id = ?', { r.id })
            end
        end
    end
    return total
end

CreateThread(function()
    Wait(20000)
    while true do
        local ok, err = pcall(function()
            local due = MySQL.query.await('SELECT DISTINCT cid FROM browser_plate_payouts WHERE settled = 0') or {}
            for _, r in ipairs(due) do
                local src = Bridge.findSource(r.cid)
                if src then Plates.deliverPayouts(r.cid, src) end
            end
            -- listings whose plate is no longer the seller's, or is back on a vehicle, cannot be bought
            MySQL.update.await([[DELETE FROM browser_plate_listings WHERE NOT EXISTS (SELECT 1 FROM browser_plate_assets a
                WHERE a.id = browser_plate_listings.asset_id AND a.base_key IS NULL AND a.owner = browser_plate_listings.seller)]])
        end)
        if not ok then print(('^5[as-browser]^0 plates: payout sweep failed: %s'):format(tostring(err))) end
        Wait(30000)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Requests from the site
-- ---------------------------------------------------------------------------------------------

--- Put a plate up for sale. data = { asset = id, price = n }
Browser.handler('plates', 'list', function(src, data)
    if not enabled() then return nil, T('plates.err.marketOff') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    Plates.sync(cid)
    local asset = X.assetById(data.asset)
    if not asset or asset.owner ~= cid then return nil, X.blockText('notPlateOwner') end
    if X.listingOf(asset.id) then return nil, X.blockText('listed') end

    local price = whole(data.price)
    local lo, hi = whole(M('minPrice', 1), 1), whole(M('maxPrice', 5000000), 5000000)
    if price < lo or price > hi then
        return nil, T('plates.err.price', Config.currency, lo, Config.currency, hi)
    end
    local n = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM browser_plate_listings WHERE seller = ?', { cid })) or 0
    if n >= whole(M('maxListings', 10), 10) then return nil, T('plates.err.tooManyListings', whole(M('maxListings', 10), 10)) end

    local unlock = X.lock('a:' .. asset.id)
    if not unlock then return nil, T('plates.err.busy') end
    asset = X.assetById(asset.id)
    if not asset or asset.owner ~= cid or X.listingOf(asset.id) then unlock(); return nil, X.blockText('notPlateOwner') end

    local returned
    if asset.base_key then
        local res, err = X.doDetach(src, cid, asset, false)
        if not res then unlock(); return nil, err end
        returned = res.returned
    end
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT INTO browser_plate_listings (asset_id, seller, price, listed_at) VALUES (?, ?, ?, ?)',
            { asset.id, cid, price, now() })
    end)
    unlock()
    if not ok or not id then return nil, T('plates.err.notListed') end
    return { id = id, plate = asset.display, price = price, returned = returned, fee = feeOf(price), receive = price - feeOf(price) }
end)

--- Take a plate off sale. data = { asset = id }
Browser.handler('plates', 'unlist', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local asset = X.assetById(data.asset)
    if not asset then return nil, X.blockText('notPlateOwner') end
    local n = MySQL.update.await('DELETE FROM browser_plate_listings WHERE asset_id = ? AND seller = ?', { asset.id, cid })
    if n ~= 1 then return nil, T('plates.err.notListedNow') end
    return { plate = asset.display }
end)

--- Plates for sale. data = { q = search, sort = 'new'|'low'|'high'|'short', page = n }
Browser.handler('plates', 'market', function(src, data)
    if not enabled() then return nil, T('plates.err.marketOff') end
    local cid = Bridge.getIdentifier(src)
    local q = tostring(data.q or ''):upper():gsub('[^A-Z0-9]', '')
    if #q > 8 then q = q:sub(1, 8) end
    local order = ({ new = 'l.listed_at DESC, l.id DESC', low = 'l.price ASC, l.id ASC', high = 'l.price DESC, l.id ASC',
                     short = 'LENGTH(a.plate_key) ASC, l.price ASC' })[tostring(data.sort or 'new')] or 'l.listed_at DESC, l.id DESC'
    local perPage = math.max(1, whole(M('rows', 24), 24))
    local page = math.max(1, whole(data.page, 1))
    local where = 'a.base_key IS NULL AND a.owner = l.seller'
    local params = {}
    if q ~= '' then where = where .. ' AND a.plate_key LIKE ?'; params[#params + 1] = '%' .. q .. '%' end
    local total = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM browser_plate_listings l JOIN browser_plate_assets a ON a.id = l.asset_id WHERE ' .. where, params)) or 0
    params[#params + 1] = perPage
    params[#params + 1] = (page - 1) * perPage
    local rows = MySQL.query.await(
        'SELECT l.id, l.price, l.listed_at, l.seller, a.display FROM browser_plate_listings l JOIN browser_plate_assets a ON a.id = l.asset_id WHERE '
        .. where .. ' ORDER BY ' .. order .. ' LIMIT ? OFFSET ?', params) or {}
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = { id = r.id, plate = r.display, price = tonumber(r.price), listedAt = tonumber(r.listed_at), mine = cid ~= nil and r.seller == cid }
    end
    return { listings = list, total = total, page = page, pages = math.max(1, math.ceil(total / perPage)),
             feePercent = tonumber(M('feePercent', 0)) or 0, now = now() }
end)

--- One listing. data = { id }. { listing = nil } when it is gone.
Browser.handler('plates', 'listing', function(src, data)
    if not enabled() then return nil, T('plates.err.marketOff') end
    local cid = Bridge.getIdentifier(src)
    local r = MySQL.single.await(
        'SELECT l.id, l.price, l.seller, a.display FROM browser_plate_listings l JOIN browser_plate_assets a ON a.id = l.asset_id WHERE l.id = ? AND a.base_key IS NULL AND a.owner = l.seller',
        { whole(data.id) })
    if not r then return { listing = nil } end
    return { listing = { id = r.id, plate = r.display, price = tonumber(r.price), mine = cid ~= nil and r.seller == cid } }
end)

--- Buy a listed plate. data = { listing = id, price = the price the buyer saw, vehicle = 'AB12CDE' (optional: fit it now) }
Browser.handler('plates', 'buyListing', function(src, data)
    if not enabled() then return nil, T('plates.err.marketOff') end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    Plates.sync(cid)
    local listing = MySQL.single.await('SELECT * FROM browser_plate_listings WHERE id = ?', { whole(data.listing) })
    if not listing then return nil, T('plates.err.gone') end
    local asset = X.assetById(listing.asset_id)
    if not asset or asset.owner ~= listing.seller or asset.base_key then return nil, T('plates.err.gone') end
    if listing.seller == cid then return nil, T('plates.err.ownListing') end
    local price = whole(listing.price)
    if data.price ~= nil and whole(data.price) ~= price then return nil, T('plates.err.priceChanged', Config.currency, price) end

    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM browser_plate_assets WHERE owner = ?', { cid })) or 0
    if count >= whole(cfg('maxPlates', 30), 30) then return nil, T('plates.err.tooMany') end

    local vehicleKey = tostring(data.vehicle or '') ~= '' and tostring(data.vehicle) or nil
    if vehicleKey then
        local B, why = X.checkTarget(cid, vehicleKey, asset.plate_key)
        if not B then return nil, why end
    end

    local unlock = X.lock('a:' .. asset.id, 'p:' .. asset.plate_key)
    if not unlock then return nil, T('plates.err.busy') end

    if price > 0 and not Bridge.removeMoney(src, Config.account, price, 'personalised-plate-purchase') then
        unlock()
        return nil, T('shell.err.insufficientFunds')
    end
    local function refund()
        if price > 0 then Bridge.addMoney(src, Config.account, price, 'personalised-plate-refund') end
    end

    -- claim the listing (only one buyer can delete it), then move the plate
    local claimed = MySQL.update.await('DELETE FROM browser_plate_listings WHERE id = ? AND asset_id = ? AND price = ?', { listing.id, asset.id, price })
    if claimed ~= 1 then refund(); unlock(); return nil, T('plates.err.gone') end
    local moved = MySQL.update.await(
        'UPDATE browser_plate_assets SET owner = ? WHERE id = ? AND owner = ? AND base_key IS NULL', { cid, asset.id, listing.seller })
    if moved ~= 1 then
        refund()
        MySQL.insert.await('INSERT INTO browser_plate_listings (asset_id, seller, price, listed_at) VALUES (?, ?, ?, ?)',
            { asset.id, listing.seller, price, tonumber(listing.listed_at) or now() })
        unlock()
        return nil, T('plates.err.gone')
    end

    local fee = feeOf(price)
    local payout = price - fee
    local q = {
        { 'INSERT INTO browser_plate_sales (plate_key, display, seller, buyer, price, fee, sold_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          { asset.plate_key, asset.display, listing.seller, cid, price, fee, now() } },
    }
    if payout > 0 then
        q[#q + 1] = { 'INSERT INTO browser_plate_payouts (cid, amount, note, created_at, settled) VALUES (?, ?, ?, ?, 0)',
                      { listing.seller, payout, asset.display, now() } }
    end
    local okTx, res = pcall(MySQL.transaction.await, q)
    if not okTx or res == false then
        -- last resort: pay the seller directly so money is never lost
        local sSrc = Bridge.findSource(listing.seller)
        if payout > 0 then
            if sSrc then Bridge.addMoney(sSrc, M('payoutAccount', 'bank'), payout, 'personalised-plate-sale')
            else pcall(MySQL.insert.await, 'INSERT INTO browser_plate_payouts (cid, amount, note, created_at, settled) VALUES (?, ?, ?, ?, 0)',
                { listing.seller, payout, asset.display, now() }) end
        end
        print(('^5[as-browser]^0 plates: could not record the sale of %s'):format(asset.display))
    end
    unlock()

    X.bankLine(cid, T('plates.bank.purchase', asset.display), -price)
    local sSrc = Bridge.findSource(listing.seller)
    if sSrc then
        Plates.deliverPayouts(listing.seller, sSrc)
        X.mail(sSrc, listing.seller, T('plates.mail.soldSubject', asset.display),
            T('plates.mail.soldBody', asset.display, Config.currency, price, Config.currency, fee, Config.currency, payout, X.siteAddress()))
    end
    X.mail(src, cid, T('plates.mail.boughtSubject', asset.display),
        T('plates.mail.boughtBody', Bridge.getCharacterName(src), asset.display, Config.currency, price, X.siteAddress()))

    TriggerEvent('as-browser:plateSold', asset.display, listing.seller, cid, price)
    local hook = M('onSold', nil)
    if type(hook) == 'function' then
        local okh, err = pcall(hook, asset.display, listing.seller, cid, price)
        if not okh then print(('^5[as-browser]^0 plates: market.onSold failed: %s'):format(tostring(err))) end
    end

    local out = { plate = asset.display, id = asset.id, paid = price, now = now() }
    if vehicleKey then
        local fresh = X.assetById(asset.id)
        local r, err = X.doFit(src, cid, fresh, vehicleKey)
        if r then out.fitted = r; out.paid = price + (r.paid or 0) else out.fitError = err end
    end
    return out
end)

--- Sales and purchases of the signed-in character, and what is still owed to them.
Browser.handler('plates', 'activity', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    Plates.deliverPayouts(cid, src)
    local out = {}
    for _, s in ipairs(MySQL.query.await(
        'SELECT display, seller, buyer, price, fee, sold_at FROM browser_plate_sales WHERE seller = ? OR buyer = ? ORDER BY id DESC LIMIT 30', { cid, cid }) or {}) do
        local sold = s.seller == cid
        out[#out + 1] = { plate = s.display, kind = sold and 'sold' or 'bought', price = tonumber(s.price), fee = sold and tonumber(s.fee) or 0, at = tonumber(s.sold_at) }
    end
    local owed = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM browser_plate_payouts WHERE cid = ? AND settled = 0', { cid })) or 0
    return { items = out, owed = owed, now = now() }
end)
