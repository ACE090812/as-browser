-- Personalised registrations site (LS Plates). SERVER ONLY.
--
-- A personalised plate is something a player OWNS, separate from any vehicle:
--   * buy one and keep it, or put it straight on a vehicle you own,
--   * a vehicle keeps its ORIGINAL registration while a personalised plate is on it. Take the plate off, sell it, or
--     move it to another vehicle and the vehicle gets its original registration back,
--   * the MOT, tax, insurance, history and bookings belong to the vehicle, so they move with it every time the plate
--     changes (as-computer is told through exports['as-computer']:renamePlate),
--   * players sell plates to each other on the marketplace. The buyer pays, the seller is paid (offline too, the
--     money arrives next time they are online) minus the transfer fee.
--
-- Other scripts can listen for the server events
--     AddEventHandler('as-browser:plateChanged', function(oldPlate, newPlate, citizenId, source) end)   a vehicle's registration changed
--     AddEventHandler('as-browser:plateSold', function(plate, sellerCitizenId, buyerCitizenId, price) end)   a plate was sold
-- and use the exports  isPlateReserved(plate)  getPlateInfo(plate)  getOriginalPlate(plate)  getPlayerPlates(citizenId).
-- A vehicle dealer / plate generator should call isPlateReserved so it never hands out a plate a player owns.
Config.plates = {
    name         = 'LS Plates',
    tagline      = 'Personalised registrations for Los Santos',
    authority    = 'Driver and Vehicle Licensing Agency',
    mailFrom     = { name = 'DVLA', email = 'noreply@lsplates.co.uk' },

    minLength    = 2,          -- letters and numbers, not counting spaces
    maxLength    = 8,          -- the game's limit, counting spaces
    allowSpaces  = true,
    -- Price of a NEW plate by number of characters (spaces not counted). Shorter plates are worth more.
    lengthPrices = { [2] = 5000, [3] = 3000, [4] = 1500, [5] = 800, [6] = 400, [7] = 200 },
    defaultPrice = 150,        -- any length not listed above
    -- Optional: a plate that matches one of these Lua patterns costs this instead of the length price.
    -- Patterns match the plate with spaces removed, upper case. Example: all numbers.
    patternPrices = {
        -- { pattern = '^%d+$', price = 5000 },
    },
    assignFee     = 40,        -- charged every time a plate is put on a vehicle (buying it does not include this)
    removeFee     = 0,         -- charged when a plate is taken off a vehicle (the vehicle gets its own registration back)
    cooldownHours = 24,        -- a vehicle cannot have a plate put on it again this soon after the last time (real hours, 0 = no limit)
    maxPlates     = 30,        -- most personalised plates one character can own

    blocked      = { 'FUCK', 'CUNT', 'SHIT', 'NAZI', 'RAPE', 'KKK', 'PAEDO' },   -- plates containing any of these are refused
    reserved     = { 'POLICE', 'SAHP', 'LSPD', 'BCSO', 'EMS', 'ADMIN', 'STAFF' },   -- plates nobody can buy
    -- Only change a vehicle that is stored in a garage (so a spawned car is never changed under a player).
    -- 'auto' resolves to qbx/qbcore's `state` column or esx's `stored` column. Set stateColumn to nil to
    -- turn the check off, or to a specific column name if your garage script keeps its own.
    stateColumn   = 'auto',
    garagedValues = { 1 },
    extraTables   = {
        -- { table = 'vehicle_keys', column = 'plate' },   -- any other table that stores the plate
    },
    onChanged     = nil,       -- optional function(oldPlate, newPlate, citizenId, source) run after a registration changes

    -- ---- Vehicle KEYS -------------------------------------------------------------------------------------------
    -- Item based key scripts (acestudios_vehiclekeys, qbx_vehiclekeys with items, most "keys as items" scripts) store the
    -- plate INSIDE the key item. When a registration changes, every key with the old plate is rewritten to the new one so
    -- it keeps working. Online players' keys are changed through ox_inventory, everything else (offline players, stashes,
    -- gloveboxes, trunks) directly in the inventory tables.
    --   Scripts that keep keys in their own table instead: use extraTables above.
    --   Scripts with no stored plate at all (keys tied to the vehicle entity/netId, or a plate lookup at use time): turn
    --   this off, nothing needs changing.
    keys = {
        enabled           = true,
        item              = 'vehiclekeys',     -- the key item's name (online players only)
        fields            = { 'plate' },       -- metadata fields that hold the plate
        descriptionPrefix = 'Plate: ',         -- text in the item description that is followed by the plate ('' = leave it)
        -- Where inventories are saved. ox_inventory: table 'ox_inventory', column 'data'. qb-inventory keeps them in
        -- `players`.`inventory` and `inventories`.`items`. Tables that do not exist are skipped.
        inventoryTables   = { { table = 'ox_inventory', column = 'data' } },
    },

    -- ---- Vehicles that are temporarily out of `player_vehicles` -----------------------------------------------------------
    -- A car listed on a used-car lot is DELETED from player_vehicles and kept in another table until it sells. Without this,
    -- LS Plates would think the vehicle is gone and release the personalised plate. Plates found in these tables count as
    -- "the vehicle still exists". qbx_vehiclesales uses occasion_vehicles. Tables that do not exist are skipped.
    holdingTables = {
        { table = 'occasion_vehicles', column = 'plate' },
    },

    -- ---- Plate generator (exports['as-browser']:generatePlate) -------------------------------------------------------------
    -- Other scripts can ask for a fresh plate that is not taken, reserved, or owned by a player.
    -- Pattern: 1 = digit, A = letter, . = either, anything else is copied as it is.
    generator = { pattern = '11AAA111', attempts = 100 },

    -- Player to player sales.
    market = {
        enabled     = true,
        feePercent  = 5,        -- the government's transfer fee, taken from the seller's payout (0 = none). It is not paid to anyone.
        minPrice    = 50,
        maxPrice    = 5000000,
        maxListings = 10,       -- most plates one character can have for sale at once
        rows        = 24,       -- listings per page
        payoutAccount = 'bank',
        onSold      = nil,      -- optional function(plate, sellerCitizenId, buyerCitizenId, price)
    },
}
