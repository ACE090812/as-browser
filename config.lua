-- This file is sent to players (shared script). Never put webhooks, keys or anything secret in it.
-- Each site has its own SERVER-ONLY config in sites/<name>/config.lua for content and secrets.
Config = {}

-- Language: any file in locales/ (locales/en.lua = English). Copy en.lua to add a language.
Config.locale = 'en'

-- 'auto' detects qbx_core / qb-core / es_extended and falls back to 'standalone'.
-- Standalone has no real bank accounts, so every payment succeeds.
Config.framework = 'auto'

-- How the browser shows up on the phone.
Config.app = {
    identifier  = 'as-browser',
    name        = 'Browser',
    description = 'Browse the Los Santos web.',
    defaultApp  = true,        -- true = pre-installed on every phone, false = App Store download
    devices     = 'phone',     -- phone only
}

-- ---------------------------------------------------------------------------------------------
-- WEBSITES. One line per site. `enabled = false` and the site is never registered: it disappears
-- from search, bookmarks and the address bar and shows "site not found".
-- `domain` is the address players type. Change it to whatever you like.
--
-- Switch a site on or off without restarting the resource (admin, lasts until the next restart):
--     /browsersite gov off
--     /browsersite gov on
-- The command needs:  add_ace group.admin command.browsersite allow   (or run it from the console)
-- ---------------------------------------------------------------------------------------------
Config.Sites = {
    serverinfo = { enabled = true, domain = 'lifeinthe90s.co.uk' },  -- home page, rules, staff, changelog
    gov        = { enabled = true, domain = 'lsgov.co.uk' },         -- Los Santos Government
    insurance  = { enabled = true, domain = 'covercompare.co.uk' },  -- roleplay car insurance comparison
    jobs       = { enabled = true, domain = 'lscareers.co.uk' },     -- jobs and applications
    plates     = { enabled = true, domain = 'lsplates.co.uk' },        -- personalised number plates: buy, fit, sell to other players
    vehiclecheck = { enabled = true, domain = 'lsvehiclecheck.co.uk' }, -- vehicle history reports (owners, plate changes, MOT mileage, stolen / written off)
    parts      = { enabled = true, domain = 'lspartsdirect.co.uk' }, -- trade parts shop for garages (desktop browser only, paid from the job's society account)
    weather    = { enabled = true, domain = 'lsweather.co.uk' },      -- current weather and an outlook, per region (reads your weather script)
    wiki       = { enabled = true, domain = 'lswiki.co.uk' },         -- server wiki: guides and rules, edited in sites/wiki/config.lua
    tickets    = { enabled = true, domain = 'lstickets.co.uk' },      -- events and tickets: players buy, organiser jobs run events and check people in
}

-- Symbol shown next to prices. Money is always whole numbers.
Config.currency = '£'

-- Account that every payment is taken from.
Config.account = 'bank'

-- ---------------------------------------------------------------------------------------------
-- VEHICLES. Used by the vehicle checker, vehicle tax and insurance.
-- Leave `vehicleTable` nil to use the default for your framework:
--   qbx / qb  -> player_vehicles (plate, citizenid, vehicle, mods)
--   esx       -> owned_vehicles  (plate, owner, vehicle)
-- If your server keeps owned vehicles somewhere else, fill this in:
--   { table = 'player_vehicles', plate = 'plate', owner = 'citizenid', model = 'vehicle', mods = 'mods' }
-- ---------------------------------------------------------------------------------------------
Config.vehicleTable = nil

-- Vehicle classes. Tax rates and insurance base prices are set per class key in the gov and
-- insurance site configs. A vehicle's class comes from its category in your framework's vehicle
-- list (qbx/qb: shared vehicles, esx: the `vehicles` table).
Config.vehicleClasses = {
    { key = 'motorcycle', label = 'Motorcycle',        categories = { 'motorcycles' } },
    { key = 'small',      label = 'Compact or saloon', categories = { 'compacts', 'sedans' } },
    { key = 'standard',   label = 'Standard',          categories = { 'coupes', 'muscle', 'sportsclassics', 'suvs', 'offroad', 'vans' } },
    { key = 'sports',     label = 'Sports',            categories = { 'sports' } },
    { key = 'super',      label = 'Supercar',          categories = { 'super' } },
    { key = 'commercial', label = 'Commercial',        categories = { 'commercial', 'utility', 'industrial', 'service' } },
}
-- Used when a vehicle's category is missing or not listed above.
Config.defaultClass = 'standard'
-- Categories that never pay tax or need insurance.
Config.exemptCategories = { 'cycles', 'boats', 'helicopters', 'planes', 'trains', 'emergency', 'military', 'openwheel' }

-- ---------------------------------------------------------------------------------------------
-- SAFETY
-- ---------------------------------------------------------------------------------------------
-- A player can make at most `calls` requests per `seconds` to any one site.
Config.rateLimit = { calls = 20, seconds = 5 }
-- Largest request a site page may send to the server, in bytes of JSON.
Config.maxPayloadBytes = 16384
-- Per-character limits.
Config.limits = { bookmarks = 60, history = 100 }

-- ---------------------------------------------------------------------------------------------
-- PASSWORDS APP (optional, off by default)
-- sd-phone's Passwords vault only accepts a fixed list of app ids, so saving a login from a site
-- needs a one-line edit to sd-phone. See the README section "Saving logins to Passwords".
-- ---------------------------------------------------------------------------------------------
Config.passwords = { enabled = false, appId = 'browser' }
