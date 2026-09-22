-- LS Bank: online banking. SERVER ONLY. Edit freely.
--
-- This site is the website version of the phone's Wallet (sd-phone). It shares the phone's data: the statement is the phone's
-- transaction log, standing orders are the phone's standing orders (the phone runs them, so they keep working), and invoices
-- are the phone's invoices. Money moves on the framework bank account (Config.account), like every other as-browser site.
--
-- The rules below are a copy of sd-phone's configs/banking.lua. sd-phone's config cannot be read from another resource, so if
-- you change a limit there, change it here too or the two will disagree.
Config.bank = {
    name    = 'LS Bank',
    tagline = 'Online banking for Los Santos',
    footer  = { 'LS Bank is a roleplay bank. Nothing here is real money.', 'Payments to a mobile number arrive straight away.' },

    -- Cosmetic account details shown on the "Account" page. The account number is made up from the character id, so it is
    -- always the same for the same character.
    sortCode = '20-45-71',

    -- Payments
    minSend        = 1,
    maxSend        = 100000000,
    allowAnonymous = true,     -- lets the sender hide their number from the person they pay
    allowOffline   = true,     -- pay a character who is not in the city (credited straight to their framework bank account)
    sendPerMinute  = 20,       -- payments one character may make per minute
    sendPerPayee   = 6,        -- ... to the same number

    -- Standing orders (the phone runs them: this site only creates, edits, pauses and deletes them)
    standingOrders = { enabled = true, maxActive = 10, minAmount = 1, maxAmount = 100000000 },

    -- Person-to-person invoices, and invoices sent by businesses
    invoices = { enabled = true, minAmount = 1, maxAmount = 1000000, maxPending = 10 },
    businessInvoices = true,   -- show and pay invoices that businesses have sent (paid into the business's society account)
    -- Share of a business invoice paid to the employee who raised it (0 to 1), by job. Copy the `commission` values from
    -- sd-phone's configs/services.lua so paying on the website splits the money exactly like paying in the phone does.
    businessCommission = {
        -- mechanic = 0.10,
    },

    -- Which society account gets a business invoice (same idea as Config.parts.accountFor). nil = the job name.
    -- accountFor = function(job) return job end,

    -- Statement
    perPage = 25,

    -- How a payment shows in the phone's Wallet. 'auto' lets sd-phone's own logger write the row (qbx / qb) and adds the
    -- details to it; 'own' writes the row itself (use it if the phone shows nothing for website payments).
    walletLog = 'auto',
}
