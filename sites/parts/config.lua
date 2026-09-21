-- Trade parts shop for garages. SERVER ONLY, so nothing here reaches players' machines.
--
-- Mechanics browse the catalogue on the desktop Scout browser (as-computer), pay from their job's society account
-- and the parts are sent with Postal Prime (home delivery or a locker). Tracking is shown on the site itself:
-- the parcel is hidden in the Postal Prime phone app.
--
-- Needs: as-postalprime (with the parts patch), a society bank resource (see `bank`), ox_inventory.
Config.parts = {
    name    = 'LS Parts Direct',
    tagline = 'Trade parts for Los Santos garages',
    logo    = '🔧',

    -- Jobs that may buy. Each job pays from its own society account.
    jobs = { 'mechanic' },

    -- Society account name for a job. Most banking resources use the job name.
    accountFor = function(job) return job end,

    -- Which society bank to use:
    --   'auto'          the first supported one that is started
    --   'renewed'       Renewed-Banking       'qb-banking'   qb-banking
    --   'qb-management' qb-management         'okokbanking'  okokBanking
    --   'fd_banking'    fd_banking            'esx_society'  esx_addonaccount / esx_society
    --   'custom'        fill in the three functions below
    bank = 'renewed',
    -- Record purchases and refunds on the society's transaction list when the bank supports it.
    logTransactions = true,
    custom = {
        -- balance(account) -> number
        -- remove(account, amount, reason) -> true when the money was taken
        -- add(account, amount, reason)
        balance = function(account) return 0 end,
        remove  = function(account, amount, reason) return false end,
        add     = function(account, amount, reason) end,
    },

    -- Trade discount taken off every price (0.15 = 15%). Prices below are the RRP.
    discount = 0.15,

    -- Most one order may cost, by job grade level. 0 = no limit. `boss` applies to the job's bosses.
    limits = {
        default = 2000,
        boss    = 0,
        grades  = { [0] = 500, [1] = 2000 },
    },

    -- Postal Prime delivery. `fee` is charged by this shop (the parcel itself is free for Postal Prime).
    delivery = {
        home   = { enabled = false, fee = 15 },
        locker = { enabled = false, fee = 6 },
        -- Straight to the business: a courier takes the box to the business's door (waypoint / NPC van) and when it is
        -- dropped the parts go into the job's stash. Needs an entry for the job in `businesses` below.
        business = { enabled = true, fee = 10 },
        freeOver = 500,            -- no delivery fee when the parts come to at least this much (0 = never free)
        prepSeconds = 120,         -- time to "pack" the order before it goes to the couriers
        lockerHoldSeconds = 172800,-- a locker parcel not collected within this long is returned and the society refunded
        refundExpired = true,
    },

    -- Where each job's business deliveries go. Only jobs listed here get the "Deliver to our business" option.
    --   label  = shown on the site and in the courier's job
    --   coords = where the courier drops the box (the front of the business, outside the door)
    --   stash  = the ox_inventory stash the parts land in. Use your job's existing stash id and set register = false,
    --            or let Postal Prime register one (register = true, with slots / weight).
    businesses = {
        mechanic = {
            label  = 'Hayes Auto',                                   -- EDIT: your garage
            coords = vec4(-1421.6, -444.1, 35.9, 122.0),             -- EDIT: outside your garage door
            stash  = { id = 'mechanic_parts', label = 'Parts delivery', slots = 100, weight = 500000, register = true },
        },
    },

    refPrefix = 'LSP-',            -- order numbers look like LSP-10042
    maxLines  = 30,                -- different parts in one order
    maxQty    = 20,                -- of one part
    historyRows = 60,              -- orders shown on the Orders page

    -- Footer lines.
    footer = { 'Trade sales only', 'Returns within 7 days, unused parts' },

    categories = {
        { id = 'brakes', label = 'Brakes',              icon = '🛑', desc = 'Pads, discs, fluid' },
        { id = 'engine', label = 'Engine & service',    icon = '⚙️', desc = 'Filters, plugs, belts' },
        { id = 'tyres',  label = 'Tyres & wheels',      icon = '🛞', desc = 'Tyres, bearings, nuts' },
        { id = 'susp',   label = 'Suspension',          icon = '🔩', desc = 'Springs, shocks, bushes' },
        { id = 'elec',   label = 'Electrical',          icon = '🔋', desc = 'Batteries, bulbs, alternators' },
        { id = 'body',   label = 'Body & glass',        icon = '🪟', desc = 'Panels, glass, trim' },
        { id = 'fluids', label = 'Fluids',              icon = '🛢️', desc = 'Oil, coolant, screenwash' },
        { id = 'tools',  label = 'Tools & diagnostics', icon = '🧰', desc = 'Scanners, jacks, wrenches' },
    },

    -- The parts. `item` is the ox_inventory item name the buyer receives (set these to items that exist on
    -- YOUR server, the server console warns about any that don't). `price` is the RRP in whole pounds.
    -- tint 1-8 picks the colour behind the icon. popular = true shows it on the home page.
    items = {
        { id = 'brake_pads',   item = 'brake_pads',   cat = 'brakes', label = 'Ceramic brake pads (front set)',  brand = 'Stoptech',     price = 64,   icon = '🛑', tint = 7, popular = true, fits = 'Most cars and SUVs',     use = 'Brake service',      desc = 'Low-dust ceramic pads with wear indicators. Sold as a front axle set.' },
        { id = 'brake_discs',  item = 'brake_discs',  cat = 'brakes', label = 'Vented brake discs (pair)',       brand = 'Stoptech',     price = 118,  icon = '💿', tint = 6,                 fits = 'Most cars and SUVs',     use = 'Brake service',      desc = 'Vented and coated discs, sold as a pair. Fit with new pads.' },
        { id = 'brake_fluid',  item = 'brake_fluid',  cat = 'brakes', label = 'DOT 4 brake fluid 1L',            brand = 'Hydra',        price = 14,   icon = '🧪', tint = 5,                 fits = 'Universal',              use = 'Brake bleed',        desc = 'High boiling point fluid for a full brake bleed.' },
        { id = 'oil_filter',   item = 'oil_filter',   cat = 'engine', label = 'Oil filter',                      brand = 'Fram Pro',     price = 9,    icon = '🛢️', tint = 3, popular = true, fits = 'Universal (spin-on)',    use = 'Full service',       desc = 'Spin-on filter with anti-drain valve.' },
        { id = 'spark_plugs',  item = 'spark_plugs',  cat = 'engine', label = 'Iridium spark plugs (set of 4)',  brand = 'Nippon',       price = 46,   icon = '⚡', tint = 5,                 fits = '4-cylinder petrol',      use = 'Full service',       desc = 'Long-life iridium plugs. Sold as a set of four.' },
        { id = 'timing_belt',  item = 'timing_belt',  cat = 'engine', label = 'Timing belt kit',                 brand = 'Gates',        price = 139,  icon = '⚙️', tint = 6, popular = true, fits = 'Most petrol and diesel',  use = 'Major service',      desc = 'Belt, tensioner and idler pulley. Do not reuse old parts.' },
        { id = 'clutch_kit',   item = 'clutch_kit',   cat = 'engine', label = 'Performance clutch kit',          brand = 'Exedy',        price = 320,  icon = '🔧', tint = 1,                 fits = 'Manual gearbox',         use = 'Clutch replacement', desc = 'Full clutch kit: plate, cover and release bearing.' },
        { id = 'tyre',         item = 'car_tyre',     cat = 'tyres',  label = 'All-season tyre (each)',          brand = 'Bridgeport',   price = 88,   icon = '🛞', tint = 6, popular = true, fits = 'Universal',              use = 'Tyre fitting',       desc = 'Quiet all-season tyre. Price is per tyre.' },
        { id = 'wheel_hub',    item = 'wheel_hub',    cat = 'tyres',  label = 'Wheel bearing hub',               brand = 'SKF',          price = 72,   icon = '⭕', tint = 2,                 fits = 'Most cars',              use = 'Wheel bearing job',  desc = 'Pre-pressed hub and bearing assembly.' },
        { id = 'coilovers',    item = 'coilovers',    cat = 'susp',   label = 'Coilover kit (set of 4)',         brand = 'Bilstein',     price = 1290, icon = '🔩', tint = 2,                 fits = 'Sports and compacts',    use = 'Suspension upgrade', desc = 'Height-adjustable coilovers with mounts.' },
        { id = 'shocks',       item = 'shock_absorber', cat = 'susp', label = 'Front shock absorber (pair)',     brand = 'Sachs',        price = 154,  icon = '🔩', tint = 8,                 fits = 'Most cars',              use = 'Suspension repair',  desc = 'Gas-charged shocks, sold as a pair.' },
        { id = 'battery',      item = 'car_battery',  cat = 'elec',   label = 'AGM battery 80Ah',                brand = 'Varta',        price = 139,  icon = '🔋', tint = 5, popular = true, fits = 'Most cars and vans',     use = 'Battery replacement',desc = 'Maintenance-free AGM battery, start-stop ready.' },
        { id = 'alternator',   item = 'alternator',   cat = 'elec',   label = 'Alternator (remanufactured)',     brand = 'Bosch',        price = 210,  icon = '⚡', tint = 2,                 fits = 'Most cars',              use = 'Charging fault',     desc = 'Tested reman unit with a 12 month warranty.' },
        { id = 'headlights',   item = 'headlight_bulbs', cat = 'elec', label = 'H7 headlight bulbs (pair)',      brand = 'Lumina',       price = 18,   icon = '💡', tint = 5, popular = true, fits = 'H7 fittings',            use = 'Lighting fault',     desc = 'Bright white bulbs, sold as a pair.' },
        { id = 'windscreen',   item = 'windscreen',   cat = 'body',   label = 'Laminated windscreen',            brand = 'Pilkington',   price = 265,  icon = '🪟', tint = 8,                 fits = 'Most cars',              use = 'Glass replacement',  desc = 'OE quality laminated screen with sensor bracket.' },
        { id = 'body_panel',   item = 'body_panel',   cat = 'body',   label = 'Body repair panel (primed)',      brand = 'Autowerks',    price = 185,  icon = '🚗', tint = 4,                 fits = 'Most cars',              use = 'Collision repair',   desc = 'Primed steel panel ready for paint.' },
        { id = 'engine_oil',   item = 'engine_oil',   cat = 'fluids', label = 'Fully synthetic oil 5L',          brand = 'Castrol Edge', price = 42,   icon = '🛢️', tint = 5, popular = true, fits = 'Universal 5W-30',       use = 'Full service',       desc = 'Fully synthetic 5W-30 for modern engines.' },
        { id = 'coolant',      item = 'coolant',      cat = 'fluids', label = 'Coolant 5L (ready mixed)',        brand = 'Prestone',     price = 19,   icon = '🧊', tint = 2,                 fits = 'Universal',              use = 'Cooling service',    desc = 'Ready-mixed antifreeze and coolant.' },
        { id = 'obd_scanner',  item = 'obd_scanner',  cat = 'tools',  label = 'OBD-II diagnostic scanner',       brand = 'Autel',        price = 249,  icon = '📟', tint = 6, popular = true, fits = 'All post-1996 cars',     use = 'Fault finding',      desc = 'Reads and clears fault codes, live data and freeze frame.' },
        { id = 'trolley_jack', item = 'trolley_jack', cat = 'tools',  label = 'Trolley jack 3 tonne',            brand = 'Sealey',       price = 135,  icon = '🧰', tint = 7,                 fits = 'Workshop',               use = 'Lifting',            desc = 'Low-profile hydraulic jack with a safety valve.' },
    },
}
