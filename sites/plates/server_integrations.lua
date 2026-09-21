-- LS Plates: hooks for OTHER scripts (vehicle keys, dealerships, used-car lots, plate generators).
-- See the README section "Working with other scripts".
local P = Config.plates or {}
Plates = Plates or {}
local X = Plates.x
local Vehicles = Vehicles

local function norm(p) return (tostring(p or ''):upper():gsub('%s+', '')) end
local function ident(s) return tostring(s or ''):match('^[%w_]+$') ~= nil end

-- ---------------------------------------------------------------------------------------------
-- Vehicles sitting in another table (used-car lots)
-- ---------------------------------------------------------------------------------------------

--- true when a vehicle wearing this plate is held in one of Config.plates.holdingTables.
function X.held(key)
    for _, t in ipairs(P.holdingTables or {}) do
        local tbl, col = tostring(t.table or ''), tostring(t.column or 'plate')
        if ident(tbl) and ident(col) then
            local ok, row = pcall(function()
                return MySQL.scalar.await(('SELECT 1 FROM `%s` WHERE REPLACE(UPPER(`%s`), " ", "") = ? LIMIT 1'):format(tbl, col), { key })
            end)
            if ok and row then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Vehicle keys
-- ---------------------------------------------------------------------------------------------

--- Rewrites every key that carries the old plate so it carries the new one.
function Plates.keysChanged(oldPlate, newPlate)
    local K = P.keys
    if type(K) ~= 'table' or K.enabled == false then return end
    local oldT, newT = tostring(oldPlate or ''):gsub('%s+$', ''), tostring(newPlate or ''):gsub('%s+$', '')
    if oldT == '' or newT == '' or oldT == newT then return end
    local oldKey = norm(oldT)
    local fields = K.fields or { 'plate' }
    local prefix = tostring(K.descriptionPrefix or '')

    -- 1) offline players, stashes, gloveboxes, trunks: the saved inventory
    for _, t in ipairs(K.inventoryTables or {}) do
        local tbl, col = tostring(t.table or ''), tostring(t.column or '')
        if ident(tbl) and ident(col) then
            local function swap(from, to)
                pcall(function()
                    MySQL.update.await(('UPDATE `%s` SET `%s` = REPLACE(`%s`, ?, ?) WHERE INSTR(`%s`, ?) > 0'):format(tbl, col, col, col), { from, to, from })
                end)
            end
            for _, f in ipairs(fields) do
                swap('"' .. f .. '":' .. json.encode(oldT), '"' .. f .. '":' .. json.encode(newT))
            end
            if prefix ~= '' then swap(prefix .. oldT .. '"', prefix .. newT .. '"') end
        end
    end

    -- 2) players who are online: their inventory is in memory and would overwrite the change when it saves
    if GetResourceState('ox_inventory') ~= 'started' then return end
    local item = K.item
    if not item or item == '' then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ok, slots = pcall(function() return exports.ox_inventory:Search(src, 'slots', item) end)
        if ok and type(slots) == 'table' then
            for _, slot in ipairs(slots) do
                local md = slot.metadata
                if type(md) == 'table' then
                    local hit = false
                    for _, f in ipairs(fields) do
                        if md[f] ~= nil and norm(md[f]) == oldKey then md[f] = newT; hit = true end
                    end
                    if hit then
                        if prefix ~= '' and type(md.description) == 'string' then
                            local a, b = md.description:find(prefix .. oldT, 1, true)
                            if a then md.description = md.description:sub(1, a - 1) .. prefix .. newT .. md.description:sub(b + 1) end
                        end
                        pcall(function() exports.ox_inventory:SetMetadata(src, slot.slot, md) end)
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Dealers and plate generators
-- ---------------------------------------------------------------------------------------------

--- true when a plate is free to give to a new vehicle: it is not a personalised plate, not something a vehicle will
--- get back as its own registration, not a reserved word, and no vehicle already has it.
local function available(plate)
    local key = Vehicles.normalizePlate(plate)
    if not key then return false end
    if X.assetByKey(key) or X.assetByBase(key) then return false end
    if Vehicles.find(key) then return false end
    if X.held(key) then return false end
    return true
end

local function random(pattern)
    local out = {}
    for c in tostring(pattern):gmatch('.') do
        if c == '1' then out[#out + 1] = tostring(math.random(0, 9))
        elseif c == 'A' then out[#out + 1] = string.char(math.random(65, 90))
        elseif c == '.' then
            if math.random(1, 2) == 1 then out[#out + 1] = tostring(math.random(0, 9)) else out[#out + 1] = string.char(math.random(65, 90)) end
        else out[#out + 1] = c end
    end
    return table.concat(out)
end

--- Free to give out? (not the same as "valid for a player to buy": this ignores length prices, blocked words etc.)
exports('isPlateAvailable', function(plate) return available(plate) end)

--- A fresh plate that is available. Pass a pattern to override Config.plates.generator.pattern.
exports('generatePlate', function(pattern)
    local G = P.generator or {}
    pattern = pattern or G.pattern or '11AAA111'
    for _ = 1, tonumber(G.attempts) or 100 do
        local plate = random(pattern)
        if available(plate) and not X.isBlocked(norm(plate)) then return plate end
    end
    return nil
end)

--- Vehicles whose plate clashes with a personalised plate: a dealer or generator gave out something a player owns.
--- Returns { { plate = 'HELLO 1', kind = 'duplicate', owner = 'CIDA', vehicleOwner = 'CIDB' }, ... }
function Plates.conflicts()
    local out = {}
    for _, a in ipairs(MySQL.query.await('SELECT plate_key, display, owner, base_key FROM browser_plate_assets') or {}) do
        local v = Vehicles.find(a.plate_key)
        if v and a.base_key == nil then
            out[#out + 1] = { plate = a.display, kind = 'wornWithoutBeingFitted', owner = a.owner, vehicleOwner = tostring(v.owner) }
        end
        if a.base_key then
            local o = Vehicles.find(a.base_key)
            if o then out[#out + 1] = { plate = a.display, kind = 'originalTaken', owner = a.owner, vehicleOwner = tostring(o.owner), original = a.base_key } end
        end
    end
    return out
end
exports('findPlateConflicts', function() return Plates.conflicts() end)

RegisterCommand('plateconflicts', function(source)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command') then return end
    local list = Plates.conflicts()
    print(('^5[as-browser]^0 %d plate conflict(s)'):format(#list))
    for _, c in ipairs(list) do
        print(('  %s  %s  owner=%s  vehicle owner=%s  %s'):format(c.plate, c.kind, c.owner, c.vehicleOwner, c.original or ''))
    end
end, true)
