-- CoverCompare (insurance comparison) site. SERVER ONLY, so nothing here reaches players' machines.
-- Roleplay only: a policy is a record plus a certificate in Files and a confirmation in Mail. It does
-- not change how the game treats the vehicle unless another script reads the hook / export.
Config.insurance = {
    name = 'CoverCompare',

    -- Price of one week of cover for a vehicle class (keys match Config.vehicleClasses).
    weeklyBase = {
        motorcycle = 30,
        small      = 35,
        standard   = 45,
        commercial = 60,
        sports     = 70,
        super      = 110,
    },

    -- Levels of cover. `mult` multiplies the weekly base.
    covers = {
        { id = 'third_party', label = 'Third party',                     description = 'Covers damage and injury you cause to others.',                         mult = 1.00 },
        { id = 'tpft',        label = 'Third party, fire and theft',     description = 'Third party plus cover if your vehicle is stolen or catches fire.',     mult = 1.25 },
        { id = 'comprehensive', label = 'Comprehensive',                 description = 'Everything above plus repairs to your own vehicle after an accident.',  mult = 1.60 },
    },

    usages = {
        { id = 'social',   label = 'Social, domestic and pleasure', mult = 1.00 },
        { id = 'commuting', label = 'Commuting',                    mult = 1.15 },
        { id = 'business', label = 'Business use',                  mult = 1.40 },
    },

    -- Years without a claim: each year takes `perYear` off the price, up to `maxYears`.
    ncd = { maxYears = 5, perYear = 0.06 },

    -- Longer policies get a cheaper price per week.
    durations = {
        { days = 7,  label = '1 week',   factor = 1.00 },
        { days = 14, label = '2 weeks',  factor = 0.97 },
        { days = 30, label = '30 days',  factor = 0.92 },
    },

    -- Optional extras. `price` is per week. A provider that already includes one hides it.
    addons = {
        { id = 'breakdown', label = 'Breakdown cover',   description = 'Roadside help if you break down.',     price = 8 },
        { id = 'legal',     label = 'Legal expenses',    description = 'Help with legal costs after a claim.',  price = 5 },
        { id = 'courtesy',  label = 'Courtesy vehicle',  description = 'A replacement while yours is repaired.', price = 10 },
    },

    -- A vehicle can be insured again when its current policy has this many days or fewer left.
    renewWindowDays = 3,

    -- `factor` moves a provider's prices up or down. A small steady difference per plate is added
    -- on top so the same vehicle always gets the same quotes but providers do not tie.
    providers = {
        { id = 'albion',    name = 'Albion Assurance',  color = '#0b5cad', icon = '🛡️', rating = 4.6, factor = 1.06, excess = 150,
          blurb = 'A trusted name for careful drivers.',      features = { 'Free breakdown cover' }, includes = { 'breakdown' } },
        { id = 'thames',    name = 'Thames & Co Direct', color = '#1d8a5f', icon = '🚦', rating = 4.2, factor = 0.97, excess = 250,
          blurb = 'Simple cover at a fair price.',            features = { '24 hour claims line' }, includes = {} },
        { id = 'bulldog',   name = 'Bulldog Cover',      color = '#b3261e', icon = '🐶', rating = 3.9, factor = 0.90, excess = 400,
          blurb = 'The cheapest way to stay legal.',          features = { 'Lowest price guarantee' }, includes = {} },
        { id = 'coastline', name = 'Coastline Mutual',   color = '#7a3ea8', icon = '🌊', rating = 4.8, factor = 1.14, excess = 100,
          blurb = 'Premium protection with all the extras.',   features = { 'Courtesy vehicle included', 'Legal expenses included' }, includes = { 'courtesy', 'legal' } },
    },

    -- Certificates are saved to this folder in the Files app, confirmations go to the player's Mail.
    documentFolder = 'Insurance',
    mailFrom = { name = 'CoverCompare', email = 'noreply@covercompare.co.uk' },
}
