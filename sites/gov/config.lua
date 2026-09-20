-- Los Santos Government site. SERVER ONLY.
Config.gov = {
    name = 'Los Santos Government',

    -- Vehicle tax. Rates are per period and are set per vehicle class key (see Config.vehicleClasses).
    tax = {
        periodDays      = 7,    -- how long one payment lasts (real days)
        graceDays       = 7,    -- a vehicle the system has not seen before starts taxed for this long
        renewWindowDays = 7,    -- a vehicle can be taxed again once it has this many days or fewer left
        rates = {
            motorcycle = 25,
            small      = 40,    -- suggested, change to taste
            standard   = 55,    -- suggested
            commercial = 90,    -- suggested
            sports     = 75,    -- suggested
            super      = 120,   -- suggested
        },
    },

    -- MOT. Off until the MOT script exists: the checker shows "Not required yet" and the MOT booking
    -- page says "opens soon". When your MOT script is ready it calls
    --     exports['as-browser']:setMotResult(plate, passed, expiryUnixTime, 'notes')
    -- for each test, then set enabled = true.
    mot = { enabled = false },

    -- Council tax on homes. Needs a housing script (see `housing` below). Every home owned (or rented,
    -- for scripts where the renter is the owner) gets a bill each period. Unpaid bills stack up as
    -- arrears on the website and in a phone notification: nothing else happens to the player.
    council = {
        enabled       = true,
        authority     = 'Los Santos Council',
        periodDays    = 7,        -- one bill every this many real days
        graceDays     = 7,        -- a home the system has not seen before is paid up for this long
        payAheadDays  = 3,        -- the next bill can be paid this many days before it is due
        maxPeriods    = 26,       -- most bills that can be paid in one go
        -- The bill is a percentage of the home's value, kept between minBill and maxBill.
        ratePercent   = 0.02,     -- 0.02 means a 250,000 home pays 50 a period
        minBill       = 5,
        maxBill       = 500,
        rentedBill    = 10,       -- a rented home has no value to work from, so it pays this flat amount
        notifyHours   = 6,        -- how often a player in arrears is reminded on their phone (0 = never)
        mailFrom      = { name = 'Los Santos Council', email = 'noreply@lsgov.co.uk' },
        webhook       = '',       -- optional Discord log of payments
        -- Which housing script to read homes from: 'auto', 'qbx_properties', 'ps-housing', 'qb-houses'
        -- or 'custom' (then fill in `custom` below).
        housing = 'auto',
        custom = {
            table       = 'properties',   -- table with one row per home
            idColumn    = 'id',
            ownerColumn = 'owner',        -- holds the character id
            nameColumn  = 'name',         -- what the home is called
            valueColumn = 'price',        -- what it is worth (used for the percentage)
            rentColumn  = nil,            -- optional: a column that is not empty when the home is rented
        },
    },

    -- Driving licence pages (need the as-drivingschool resource; fees and test booking are set in its config.lua).
    licence = {
        resource  = 'as-drivingschool',
        authority = 'Driver and Vehicle Licensing Agency',
        mailFrom  = { name = 'DVLA', email = 'noreply@lsgov.co.uk' },
    },

    -- Benefits (Jobseeker's Allowance style). A character with one of the `jobs` claims on the website,
    -- and is then paid `amount` into the bank for every `intervalMinutes` they spend online while they
    -- still have one of those jobs. Taking a job pauses the payments, and they carry on if the job is lost.
    benefits = {
        enabled         = true,
        authority       = 'Los Santos Department for Work and Pensions',
        amount          = 75,
        intervalMinutes = 60,
        jobs            = { 'unemployed' },
        mailFrom        = { name = 'Department for Work and Pensions', email = 'noreply@lsgov.co.uk' },
        webhook         = '',       -- optional Discord log of claims and stops
    },

    -- Show "Insured / Not insured" on the vehicle checker when the CoverCompare site is on.
    showInsurance = true,

    categories = {
        { id = 'driving',   title = 'Driving and transport',           description = 'Vehicle tax, MOT, driving licences',     icon = '🚗' },
        { id = 'passports', title = 'Passports, travel and living abroad', description = 'Passports and travel documents',    icon = '🛂' },
        { id = 'money',     title = 'Money and tax',                   description = 'Council tax and other bills',            icon = '💷' },
        { id = 'benefits',  title = 'Benefits',                        description = 'Support you may be able to claim',       icon = '🤝' },
        { id = 'life',      title = 'Births, deaths, marriages and care', description = 'Birth and marriage certificates',     icon = '📜' },
        { id = 'housing',   title = 'Housing and local services',      description = 'Social housing and your council',        icon = '🏠' },
        { id = 'work',      title = 'Working, jobs and pensions',      description = 'Find a job, register a business',        icon = '💼' },
        { id = 'crime',     title = 'Crime, justice and the law',      description = 'Pay fines and penalty notices',  icon = '⚖️' },
    },

    -- status: 'live' works now, 'placeholder' shows "not available yet" until you build it.
    -- Live services need a `path` the page handles. `linkSite` sends the player to another site of
    -- yours (a key from Config.Sites); if that site is off the service shows as not available.
    services = {
        { id = 'vehicle-checker', title = 'Check vehicle information', category = 'driving', status = 'live', path = '/vehicle-checker', popular = true,
          description = 'Enter a registration number to see a vehicle\'s tax and MOT status.',
          keywords = { 'plate', 'number plate', 'registration', 'dvla', 'mot', 'tax', 'check', 'vehicle' } },
        { id = 'tax-vehicle', title = 'Tax your vehicle', category = 'driving', status = 'live', path = '/tax-vehicle', popular = true,
          description = 'Pay vehicle tax for a vehicle you own.',
          keywords = { 'road tax', 'ved', 'renew', 'pay', 'car', 'bike' } },
        { id = 'book-mot', title = 'Book an MOT test', category = 'driving', status = 'placeholder',
          description = 'Book a test for your vehicle.', keywords = { 'mot', 'test', 'booking', 'garage' } },
        -- Needs the as-drivingschool resource running.
        { id = 'driving-licence', title = 'Driving licence and tests', category = 'driving', status = 'live', path = '/driving-licence', popular = true,
          description = 'See your licence and penalty points, book your theory and practical tests, or replace a lost licence.',
          keywords = { 'licence', 'license', 'driving test', 'theory', 'practical', 'provisional', 'points', 'penalty', 'replace', 'lost' } },

        -- Needs the as-passport resource running. Prices, waiting time and delivery are set in as-passport/config.lua.
        { id = 'passport', title = 'Apply for a passport', category = 'passports', status = 'live', path = '/passport', popular = true,
          description = 'Apply for, replace or renew your passport. It is delivered to a Postal Prime locker.',
          keywords = { 'passport', 'travel', 'renew', 'replace', 'lost', 'id', 'identity', 'photo' } },

        { id = 'council-tax', title = 'Pay your council tax', category = 'money', status = 'live', path = '/council-tax', popular = true,
          description = 'Pay council tax for your home and see any arrears.',
          keywords = { 'bill', 'council', 'pay', 'home', 'house', 'property', 'arrears', 'rates' } },

        { id = 'benefits-claim', title = 'Claim benefits', category = 'benefits', status = 'live', path = '/benefits', popular = true,
          description = 'Claim jobseeker support while you are out of work, and see your payments.',
          keywords = { 'universal credit', 'jobseeker', 'support', 'dole', 'unemployed', 'allowance', 'claim' } },

        -- Needs the as-birthcert resource running.
        { id = 'birth-certificate', title = 'Order a birth certificate', category = 'life', status = 'live', path = '/birth-certificate',
          description = 'Order a copy of your birth certificate, delivered to a Postal Prime locker.', keywords = { 'certificate', 'birth', 'copy', 'born' } },

        -- Needs the as-fines resource running.
        { id = 'pay-fine', title = 'Pay a fine', category = 'crime', status = 'live', path = '/pay-fine', popular = true,
          description = 'See and pay fines and penalty notices.', keywords = { 'fine', 'penalty', 'ticket', 'speeding', 'police', 'pay', 'notice' } },

        -- Needs the as-registry resource running.
        { id = 'marriage', title = 'Get married', category = 'life', status = 'live', path = '/marriage',
          description = 'Propose to your partner, and get your marriage certificate.', keywords = { 'marriage', 'marry', 'wedding', 'married', 'certificate', 'spouse' } },
        { id = 'register-business', title = 'Register a business', category = 'work', status = 'live', path = '/register-business',
          description = 'Register a business name and get a certificate of registration.', keywords = { 'business', 'company', 'register', 'trading', 'self employed', 'shop' } },

        { id = 'find-job', title = 'Find a job', category = 'work', status = 'live', linkSite = 'jobs', popular = true,
          description = 'Browse jobs and apply through Los Santos Careers.', keywords = { 'jobs', 'careers', 'apply', 'work', 'application' } },

    },
}
