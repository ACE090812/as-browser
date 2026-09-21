-- Los Santos Government site. SERVER ONLY.
Config.gov = {
    name = 'Los Santos Government',

    -- Which of your custom scripts the government site uses. Set one to false if you do not run that
    -- script (or want its service off): its service disappears from the home page, search and the
    -- categories, and its pages stop working. Nothing else is affected. Change needs a restart of as-browser.
    scripts = {
        passport   = true,   -- as-passport          Apply for a passport
        licence    = true,   -- as-drivingschool     Driving licence and tests (resource name: licence.resource below)
        motbooking = true,   -- as-computer          Book an MOT test at a garage (garages, times and fee are set in as-computer's config/apps/booking.lua)
        birthcert  = true,   -- as-birthcert         Order a birth certificate
        fines      = true,   -- as-fines             Pay a fine
        penalties  = true,   -- built in             Penalty points and fines in one place (shows what is available: needs licence and/or fines)
        dbs        = true,   -- built in             Criminal record (DBS) checks
        registry   = true,   -- as-registry          Get married, register a business
        council    = true,   -- built in             Council tax (same as council.enabled)
        benefits   = true,   -- built in             Claim benefits (same as benefits.enabled)
    },

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
    mot = { enabled = true },  -- fed by mot-dui (UKC OS MOT terminal) after every test

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

    -- MOT booking pages (need the as-computer resource running; garages, slots and the fee are set there).
    motBooking = {
        resource           = 'as-computer',
        authority          = 'Driver and Vehicle Standards Agency',
        mailFrom           = { name = 'DVSA', email = 'noreply@lsgov.co.uk' },
        expiryReminderDays = 3,   -- email the owner when their MOT runs out within this many days (or has run out). 0 = off
    },

    -- Driving licence pages (need the as-drivingschool resource; fees and test booking are set in its config.lua).
    licence = {
        resource  = 'as-drivingschool',
        authority = 'Driver and Vehicle Licensing Agency',
        mailFrom  = { name = 'DVLA', email = 'noreply@lsgov.co.uk' },
    },

    -- Benefits (Jobseeker's Allowance style). A character with one of the `jobs` fills in a short form on the
    -- website; their answers work out their rate. They are then paid that rate into the bank for every
    -- `intervalMinutes` they spend online while they still have one of those jobs. Taking a job pauses the
    -- payments, and they carry on if the job is lost. They can update their answers or stop at any time.
    benefits = {
        enabled         = true,
        authority       = 'Los Santos Department for Work and Pensions',
        intervalMinutes = 60,
        jobs            = { 'unemployed' },
        savingsLimit    = 16000,    -- no claim if their bank balance is over this (0 = no check)
        -- The rate for each payment is built from the form answers, in pounds:
        rates = {
            age18to24  = 60,        -- basic rate, aged 18 to 24
            age25plus  = 75,        -- basic rate, aged 25 or over
            partner    = 30,        -- extra when they live with a partner
            housing    = { rent = 25, own = 10, family = 0, homeless = 15 },   -- extra by where they live
            perChild   = 20,        -- extra for each child they look after
            maxChildren = 3,        -- most children counted
            disability = 30,        -- extra when a health condition or disability limits the work they can do
            maxTotal   = 250,       -- a payment is never more than this
        },
        mailFrom        = { name = 'Department for Work and Pensions', email = 'noreply@lsgov.co.uk' },
        webhook         = '',       -- optional Discord log of claims and stops
    },

    -- Penalty points and fines page. Nothing to set: it shows the licence points from `licence` and the unpaid
    -- fines from as-fines, and whichever of the two resources is running.

    -- Personalised number plates now live on their own site (LS Plates, sites/plates/config.lua).

    -- Criminal record (DBS) checks. Police add convictions with the commands below (or your scripts call the exports
    --     exports['as-browser']:addCriminalRecord(citizenId, { offence = '...', sentence = '...', notes = '...', issuedBy = '...', spentDays = 30 })
    --     exports['as-browser']:getCriminalRecords(citizenId)   removeCriminalRecord(id)   hasCleanRecord(citizenId, 'basic')
    -- ) and a player pays for a certificate on the website. Employers check a certificate on the verify page.
    dbs = {
        authority    = 'Disclosure and Barring Service',
        mailFrom     = { name = 'DBS', email = 'noreply@lsgov.co.uk' },
        -- includes: 'unspent' = only convictions that are not yet spent, 'all' = every conviction, 'notes' = every conviction plus police notes
        levels = {
            { id = 'basic',    fee = 100, includes = 'unspent' },
            { id = 'standard', fee = 200, includes = 'all' },
            { id = 'enhanced', fee = 350, includes = 'notes' },
        },
        processingMinutes = 0,      -- how long a check takes. 0 = the certificate is ready straight away
        validDays         = 30,     -- how long a certificate can be verified for (real days, 0 = forever)
        defaultSpentDays  = 30,     -- a conviction becomes "spent" this long after it was given (0 = never)
        policeJobs        = { 'police' },   -- jobs that may use the commands (the server console always can)
        commands = { add = 'addrecord', view = 'viewrecord', remove = 'removerecord' },   -- set one to nil to switch it off
        maxRecordsShown   = 30,
    },

    -- Vehicle history reports now live on their own site (LS Vehicle Check, sites/vehiclecheck/config.lua).

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
        { id = 'crime',     title = 'Crime, justice and the law',      description = 'Pay fines, criminal record checks',  icon = '⚖️' },
    },

    -- status: 'live' works now, 'placeholder' shows "not available yet" until you build it.
    -- `requires` ties a service to a switch in `scripts` above. Live services need a `path` the page handles. `linkSite` sends the player to another site of
    -- yours (a key from Config.Sites); if that site is off the service shows as not available.
    services = {
        { id = 'vehicle-checker', title = 'Check vehicle information', category = 'driving', status = 'live', path = '/vehicle-checker', popular = true,
          description = 'Enter a registration number to see a vehicle\'s tax and MOT status.',
          keywords = { 'plate', 'number plate', 'registration', 'dvla', 'mot', 'tax', 'check', 'vehicle' } },
        { id = 'tax-vehicle', title = 'Tax your vehicle', category = 'driving', status = 'live', path = '/tax-vehicle', popular = true,
          description = 'Pay vehicle tax for a vehicle you own.',
          keywords = { 'road tax', 'ved', 'renew', 'pay', 'car', 'bike' } },
        -- Needs the as-computer resource running (the garages' computers).
        { id = 'book-mot', requires = 'motbooking', title = 'Book an MOT test', category = 'driving', status = 'live', path = '/book-mot', popular = true,
          description = 'Book, change or cancel an MOT test for a vehicle you own, at a garage of your choice.',
          keywords = { 'mot', 'test', 'booking', 'garage', 'book', 'cancel', 'change', 'reminder' } },
        -- Needs the as-drivingschool resource running.
        { id = 'driving-licence', requires = 'licence', title = 'Driving licence and tests', category = 'driving', status = 'live', path = '/driving-licence', popular = true,
          description = 'See your licence and penalty points, book your theory and practical tests, or replace a lost licence.',
          keywords = { 'licence', 'license', 'driving test', 'theory', 'practical', 'provisional', 'points', 'penalty', 'replace', 'lost' } },

        -- Penalty points and unpaid fines together (uses as-drivingschool and/or as-fines, whichever is running).
        { id = 'penalties', requires = 'penalties', title = 'Penalty points and fines', category = 'driving', status = 'live', path = '/penalties', popular = true,
          description = 'See the penalty points on your licence and any unpaid fines, and pay them.',
          keywords = { 'penalty', 'points', 'fine', 'endorsement', 'speeding', 'licence', 'ban', 'disqualified', 'pay' } },
        { id = 'personalised-plates', title = 'Buy a personalised number plate', category = 'driving', status = 'live', linkSite = 'plates',
          description = 'Choose a registration number for a vehicle you own.',
          keywords = { 'plate', 'number plate', 'registration', 'personalised', 'private', 'custom', 'reg' } },
        { id = 'vehicle-history', title = 'Vehicle history check', category = 'driving', status = 'live', linkSite = 'vehiclecheck',
          description = 'Check a used vehicle before you buy: owners, plate changes, stolen or written-off records and MOT mileage.',
          keywords = { 'history', 'used car', 'stolen', 'written off', 'owners', 'mileage', 'clocked', 'check', 'buy', 'carvertical' } },

        -- Needs the as-passport resource running. Prices, waiting time and delivery are set in as-passport/config.lua.
        { id = 'passport', requires = 'passport', title = 'Apply for a passport', category = 'passports', status = 'live', path = '/passport', popular = true,
          description = 'Apply for, replace or renew your passport. It is delivered to a Postal Prime locker.',
          keywords = { 'passport', 'travel', 'renew', 'replace', 'lost', 'id', 'identity', 'photo' } },

        { id = 'council-tax', requires = 'council', title = 'Pay your council tax', category = 'money', status = 'live', path = '/council-tax', popular = true,
          description = 'Pay council tax for your home and see any arrears.',
          keywords = { 'bill', 'council', 'pay', 'home', 'house', 'property', 'arrears', 'rates' } },

        { id = 'benefits-claim', requires = 'benefits', title = 'Claim benefits', category = 'benefits', status = 'live', path = '/benefits', popular = true,
          description = 'Claim jobseeker support while you are out of work, and see your payments.',
          keywords = { 'universal credit', 'jobseeker', 'support', 'dole', 'unemployed', 'allowance', 'claim' } },

        -- Needs the as-birthcert resource running.
        { id = 'birth-certificate', requires = 'birthcert', title = 'Order a birth certificate', category = 'life', status = 'live', path = '/birth-certificate',
          description = 'Order a copy of your birth certificate, delivered to a Postal Prime locker.', keywords = { 'certificate', 'birth', 'copy', 'born' } },

        -- Needs the as-fines resource running.
        { id = 'pay-fine', requires = 'fines', title = 'Pay a fine', category = 'crime', status = 'live', path = '/pay-fine', popular = true,
          description = 'See and pay fines and penalty notices.', keywords = { 'fine', 'penalty', 'ticket', 'speeding', 'police', 'pay', 'notice' } },

        { id = 'dbs', requires = 'dbs', title = 'Request a criminal record check (DBS)', category = 'crime', status = 'live', path = '/dbs', popular = true,
          description = 'Get a DBS certificate for a job, or check the certificate an applicant gives you.',
          keywords = { 'dbs', 'criminal record', 'background check', 'disclosure', 'barring', 'conviction', 'certificate', 'police check', 'employer', 'verify' } },

        -- Needs the as-registry resource running.
        { id = 'marriage', requires = 'registry', title = 'Get married', category = 'life', status = 'live', path = '/marriage',
          description = 'Propose to your partner, and get your marriage certificate.', keywords = { 'marriage', 'marry', 'wedding', 'married', 'certificate', 'spouse' } },
        { id = 'register-business', requires = 'registry', title = 'Register a business', category = 'work', status = 'live', path = '/register-business',
          description = 'Register a business name and get a certificate of registration.', keywords = { 'business', 'company', 'register', 'trading', 'self employed', 'shop' } },

        { id = 'find-job', title = 'Find a job', category = 'work', status = 'live', linkSite = 'jobs', popular = true,
          description = 'Browse jobs and apply through Los Santos Careers.', keywords = { 'jobs', 'careers', 'apply', 'work', 'application' } },

    },
}
