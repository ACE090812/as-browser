-- Vehicle lookups shared by the government portal (checker + tax) and the insurance site.
Vehicles = {}

local framework = Bridge.framework

-- ---------------------------------------------------------------------------------------------
-- Plates
-- ---------------------------------------------------------------------------------------------

--- Plates are compared upper-case with no spaces, because QBCore pads plates with spaces.
function Vehicles.normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    local p = plate:upper():gsub('%s+', '')
    if #p < 1 or #p > 10 or not p:match('^[%w%-]+$') then return nil end
    return p
end

-- ---------------------------------------------------------------------------------------------
-- Where owned vehicles live
-- ---------------------------------------------------------------------------------------------

local function tableCfg()
    local c = Config.vehicleTable
    if not c then
        if framework == 'esx' then
            c = { table = 'owned_vehicles', plate = 'plate', owner = 'owner', model = 'vehicle', mods = 'vehicle' }
        else
            c = { table = 'player_vehicles', plate = 'plate', owner = 'citizenid', model = 'vehicle', mods = 'mods' }
        end
    end
    for _, k in ipairs({ 'table', 'plate', 'owner', 'model', 'mods' }) do
        if type(c[k]) ~= 'string' or not c[k]:match('^[%w_]+$') then
            error(('Config.vehicleTable.%s must be a plain column/table name'):format(k))
        end
    end
    return c
end

local SELECT, COLS
local function selectSql()
    if SELECT then return SELECT, COLS end
    local c = tableCfg()
    SELECT = ('SELECT `%s` AS plate, `%s` AS owner, `%s` AS model, `%s` AS mods FROM `%s`'):format(
        c.plate, c.owner, c.model, c.mods, c.table)
    COLS = c
    return SELECT, c
end

-- ---------------------------------------------------------------------------------------------
-- Model names, brands and categories
-- ---------------------------------------------------------------------------------------------

local function joaat(str)
    str = tostring(str):lower()
    local h = 0
    for i = 1, #str do
        h = (h + str:byte(i)) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = (h ~ (h >> 6)) & 0xFFFFFFFF
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = (h ~ (h >> 11)) & 0xFFFFFFFF
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h
end

local infoByName        -- spawn name -> { brand, name, category, price }
local spawnByHash       -- joaat hash -> spawn name (ESX stores the hash)

local function loadInfo()
    if infoByName then return end
    infoByName, spawnByHash = {}, {}

    if framework == 'qbx' then
        local ok, list = pcall(function() return exports.qbx_core:GetVehiclesByName() end)
        if ok and type(list) == 'table' then
            for spawn, v in pairs(list) do
                infoByName[spawn:lower()] = { brand = v.brand, name = v.name, category = v.category, price = v.price }
            end
        end
    elseif framework == 'qb' then
        local core = Bridge.getQBCore()
        local list = core and core.Shared and core.Shared.Vehicles
        if type(list) == 'table' then
            for spawn, v in pairs(list) do
                infoByName[tostring(spawn):lower()] = { brand = v.brand, name = v.name, category = v.category, price = v.price }
            end
        end
    elseif framework == 'esx' then
        local ok, rows = pcall(function() return MySQL.query.await('SELECT name, model, price, category FROM vehicles') end)
        if ok and type(rows) == 'table' then
            for _, v in ipairs(rows) do
                local spawn = tostring(v.model):lower()
                infoByName[spawn] = { brand = nil, name = v.name, category = v.category, price = v.price }
                spawnByHash[joaat(spawn)] = spawn
            end
        end
    end
end

local function prettify(spawn)
    spawn = tostring(spawn or 'Unknown')
    return (spawn:sub(1, 1):upper() .. spawn:sub(2):lower())
end

local function normCat(c)
    if type(c) ~= 'string' then return nil end
    local s = c:lower():gsub('[%s%-_]', '')
    return s ~= '' and s or nil
end

-- ---------------------------------------------------------------------------------------------
-- Colours (GTA colour index -> a plain colour family)
-- ---------------------------------------------------------------------------------------------

local COLOURS = {
    { 0, 0, 'Black' }, { 1, 10, 'Grey' }, { 11, 12, 'Black' }, { 13, 14, 'Grey' }, { 15, 16, 'Black' },
    { 17, 20, 'Grey' }, { 21, 22, 'Black' }, { 23, 26, 'Grey' }, { 27, 35, 'Red' }, { 36, 36, 'Orange' },
    { 37, 37, 'Gold' }, { 38, 38, 'Orange' }, { 39, 40, 'Red' }, { 41, 41, 'Orange' }, { 42, 42, 'Yellow' },
    { 43, 48, 'Red' }, { 49, 60, 'Green' }, { 61, 87, 'Blue' }, { 88, 89, 'Yellow' }, { 90, 90, 'Brown' },
    { 91, 91, 'Yellow' }, { 92, 92, 'Green' }, { 93, 95, 'Beige' }, { 96, 104, 'Brown' }, { 105, 107, 'Beige' },
    { 108, 110, 'Brown' }, { 111, 112, 'White' }, { 113, 113, 'Beige' }, { 114, 119, 'Brown' },
    { 120, 121, 'Silver' }, { 134, 134, 'White' }, { 135, 137, 'Pink' }, { 138, 138, 'Orange' },
    { 139, 139, 'Green' }, { 140, 141, 'Blue' }, { 142, 142, 'Purple' }, { 143, 143, 'Red' },
    { 144, 144, 'Green' }, { 145, 145, 'Purple' }, { 146, 146, 'Blue' }, { 147, 147, 'Black' },
}

function Vehicles.colourName(idx)
    if type(idx) == 'table' then return 'Custom' end
    idx = tonumber(idx)
    if not idx then return 'Unknown' end
    for i = 1, #COLOURS do
        local r = COLOURS[i]
        if idx >= r[1] and idx <= r[2] then return r[3] end
    end
    return 'Other'
end

-- ---------------------------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------------------------

local classByCategory, exemptSet
local function buildClassMaps()
    if classByCategory then return end
    classByCategory, exemptSet = {}, {}
    for _, cls in ipairs(Config.vehicleClasses) do
        for _, cat in ipairs(cls.categories or {}) do classByCategory[normCat(cat)] = cls end
    end
    for _, cat in ipairs(Config.exemptCategories or {}) do exemptSet[normCat(cat)] = true end
end

function Vehicles.classByKey(key)
    for _, cls in ipairs(Config.vehicleClasses) do if cls.key == key then return cls end end
    return nil
end

--- Returns the class table for a category, or the default class.
function Vehicles.classFor(category)
    buildClassMaps()
    return classByCategory[normCat(category) or ''] or Vehicles.classByKey(Config.defaultClass) or Config.vehicleClasses[1]
end

function Vehicles.isExempt(category)
    buildClassMaps()
    return exemptSet[normCat(category) or ''] == true
end

-- ---------------------------------------------------------------------------------------------
-- Reading vehicle rows
-- ---------------------------------------------------------------------------------------------

local function parseRow(row)
    local mods = row.mods
    if type(mods) == 'string' then
        local ok, t = pcall(json.decode, mods)
        mods = (ok and type(t) == 'table') and t or {}
    elseif type(mods) ~= 'table' then
        mods = {}
    end

    local model = row.model
    if framework == 'esx' then
        local hash = tonumber(mods.model)
        model = hash and spawnByHash[hash & 0xFFFFFFFF] or nil
        if not model then loadInfo(); model = hash and spawnByHash[hash & 0xFFFFFFFF] or 'unknown' end
    end

    return {
        plate  = tostring(row.plate or ''),
        owner  = row.owner,
        model  = tostring(model or 'unknown'):lower(),
        colour = mods.color1,
    }
end

--- Finds a vehicle by registration number. Returns nil when it isn't in the owned vehicles table.
function Vehicles.find(plate)
    local p = Vehicles.normalizePlate(plate)
    if not p then return nil end
    loadInfo()
    local sql, c = selectSql()
    local row = MySQL.single.await(sql .. (' WHERE REPLACE(UPPER(`%s`), " ", "") = ? LIMIT 1'):format(c.plate), { p })
    if not row then return nil end
    local v = parseRow(row)
    v.plateKey = p
    return v
end

--- Every vehicle a character owns.
function Vehicles.ownedBy(identifier)
    if not identifier then return {} end
    loadInfo()
    local sql, c = selectSql()
    local rows = MySQL.query.await(sql .. (' WHERE `%s` = ? LIMIT 100'):format(c.owner), { identifier }) or {}
    local out = {}
    for i = 1, #rows do
        local v = parseRow(rows[i])
        v.plateKey = Vehicles.normalizePlate(v.plate) or v.plate
        out[#out + 1] = v
    end
    return out
end

--- Adds the friendly fields: make, model, colour, class, exemption and price.
function Vehicles.describe(v)
    loadInfo()
    local info = infoByName[v.model] or {}
    local category = normCat(info.category)
    local cls = Vehicles.classFor(category)
    local model = info.name
    if not model or model == '' then model = prettify(v.model) end
    return {
        plate    = v.plate,
        plateKey = v.plateKey,
        make     = info.brand or '',
        model    = model,
        colour   = Vehicles.colourName(v.colour),
        category = category or 'unknown',
        class    = { key = cls.key, label = cls.label },
        exempt   = Vehicles.isExempt(category),
        price    = tonumber(info.price),
    }
end

return Vehicles
