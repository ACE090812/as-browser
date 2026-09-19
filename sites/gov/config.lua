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

    -- Show "Insured / Not insured" on the vehicle checker when the CoverCompare site is on.
    showInsurance = true,

    categories = {
        { id = 'driving',   title = 'Driving and transport',           description = 'Vehicle tax, MOT, driving licences',     icon = '🚗' },
        { id = 'passports', title = 'Passports, travel and living abroad', description = 'Passports and travel documents',    icon = '🛂' },
        { id = 'money',     title = 'Money and tax',                   description = 'Council tax and other bills',            icon = '💷' },
        { id = 'benefits',  title = 'Benefits',                        description = 'Support you may be able to claim',       icon = '🤝' },
        { id = 'life',      title = 'Births, deaths, marriages and care', description = 'Certificates and changes of name',     icon = '📜' },
        { id = 'housing',   title = 'Housing and local services',      description = 'Social housing and your council',        icon = '🏠' },
        { id = 'work',      title = 'Working, jobs and pensions',      description = 'Find a job and workplace rights',        icon = '💼' },
        { id = 'crime',     title = 'Crime, justice and the law',      description = 'Report a crime and contact the police',  icon = '⚖️' },
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
        { id = 'driving-licence', title = 'Apply for a driving licence', category = 'driving', status = 'placeholder',
          description = 'Apply for, renew or replace a driving licence.', keywords = { 'licence', 'license', 'driving test', 'provisional' } },

        -- Needs the as-passport resource running. Prices, waiting time and delivery are set in as-passport/config.lua.
        { id = 'passport', title = 'Apply for a passport', category = 'passports', status = 'live', path = '/passport', popular = true,
          description = 'Apply for, replace or renew your passport. It is delivered to a Postal Prime locker.',
          keywords = { 'passport', 'travel', 'renew', 'replace', 'lost', 'id', 'identity', 'photo' } },

        { id = 'council-tax', title = 'Pay your council tax', category = 'money', status = 'placeholder',
          description = 'Pay or set up council tax for your home.', keywords = { 'bill', 'council', 'pay' } },

        { id = 'benefits-claim', title = 'Claim benefits', category = 'benefits', status = 'placeholder',
          description = 'Check what support you can claim.', keywords = { 'universal credit', 'jobseeker', 'support', 'dole' } },

        { id = 'birth-certificate', title = 'Order a birth certificate', category = 'life', status = 'placeholder',
          description = 'Order a copy of a birth certificate.', keywords = { 'certificate', 'birth', 'copy' } },
        { id = 'change-name', title = 'Change your name', category = 'life', status = 'placeholder',
          description = 'Change your name on your records.', keywords = { 'name', 'deed poll', 'marriage' } },

        { id = 'social-housing', title = 'Apply for social housing', category = 'housing', status = 'placeholder',
          description = 'Join the housing list.', keywords = { 'housing', 'council house', 'home', 'rent' } },

        { id = 'find-job', title = 'Find a job', category = 'work', status = 'live', linkSite = 'jobs', popular = true,
          description = 'Browse jobs and apply through Los Santos Careers.', keywords = { 'jobs', 'careers', 'apply', 'work', 'application' } },

        { id = 'contact-police', title = 'Contact the police', category = 'crime', status = 'placeholder',
          description = 'Report a crime or get in touch.', keywords = { 'report', 'crime', 'lspd', '999', '101' } },
    },
}
