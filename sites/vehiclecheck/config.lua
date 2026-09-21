-- Vehicle Check site (vehicle history reports). SERVER ONLY.
--
-- A paid report on any registration number, like a used-car history check. Scripts feed it with
--     exports['as-browser']:logVehicleEvent(plate, 'accident', 'Text shown on the report')
--     exports['as-browser']:setVehicleFlag(plate, 'stolen', true, 'optional note')   (false clears it)
--     exports['as-browser']:getVehicleHistory(plate)   for police / MDT screens
-- Plate changes, and every change of owner, are recorded by this resource itself. The history belongs to the VEHICLE:
-- it carries on unchanged when a personalised plate is put on or taken off.
Config.vehiclecheck = {
    name          = 'LS Vehicle Check',
    tagline       = 'Know what you are buying',
    authority     = 'Los Santos Vehicle Records',
    mailFrom      = { name = 'Vehicle Records', email = 'noreply@lsvehiclecheck.co.uk' },
    ownedFree     = true,       -- the owner reads their own vehicle's report for free (any plan)
    -- The report plans a player can buy. Each has its own price and its own list of sections (`includes`).
    -- Sections: flags (stolen, written off, impounded, finance), mot, mileage, tax, insurance, owners, plates, events, tests.
    -- Add, remove or reorder plans freely. `popular = true` highlights one. Names and descriptions are content: edit them here.
    plans = {
        { id = 'basic',    name = 'Basic check',    price = 10, description = 'Is it safe to buy? Stolen, written off, impounded and finance records.',
          includes = { 'flags' } },
        { id = 'standard', name = 'Standard check', price = 25, description = 'Basic, plus MOT, mileage, tax and insurance.', popular = true,
          includes = { 'flags', 'mot', 'mileage', 'tax', 'insurance' } },
        { id = 'full',     name = 'Full history',   price = 45, description = 'Everything: owners, plate changes, every event and every MOT test.',
          includes = { 'flags', 'mot', 'mileage', 'tax', 'insurance', 'owners', 'plates', 'events', 'tests' } },
    },
    manyOwners    = 4,          -- more owners than this is shown as a warning
    maxEvents     = 40,         -- most events listed on a report
    trackOwners   = true,       -- notice when a vehicle changes owner (checked whenever it is looked up, and by a sweep)
    sweepMinutes  = 15,         -- how often the sweep reads the owned vehicles table (0 = no sweep, only on lookups)
    -- The record flags. A flag is set with setVehicleFlag. severity: 'fail' shows red, 'warn' amber.
    -- The text for each comes from locales/en.lua (gov.history.flag.<id>).
    flags = {
        { id = 'stolen',      severity = 'fail' },
        { id = 'written_off', severity = 'fail' },
        { id = 'impounded',   severity = 'warn' },
        { id = 'finance',     severity = 'warn' },
    },
}
