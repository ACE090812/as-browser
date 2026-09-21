-- LS Tickets: events and tickets. SERVER ONLY. Edit freely.
--
-- Players browse events and buy tickets (paid from their bank). A ticket is a code that shows on the "My tickets" page.
-- Jobs listed in `organiserJobs` can create and run their own events and check tickets in at the door. The money is
-- held until the event has ended and is then paid into the organising job's society account (with the same society bank
-- as the parts shop). Cancelling an event refunds every ticket: straight away to players who are online, and the next time
-- they open the site for anyone who is not.
Config.tickets = {
    name    = 'LS Tickets',
    tagline = 'Events, gigs and nights out in Los Santos',
    footer  = { 'Tickets are non-transferable once checked in', 'Cancelled events are refunded in full' },

    -- Jobs that can organise events (create, see sales, check tickets in). minGrade: lowest job grade that may.
    organiserJobs = { 'events' },
    organiserMinGrade = 0,
    -- Jobs that can check in tickets and cancel ANY event (for example a licensing or admin job). Leave empty for none.
    staffJobs = {},

    -- Limits
    maxPerPerson    = 6,        -- tickets one character can hold for one event
    maxActivePerJob = 5,        -- open events one job can have at a time
    maxCapacity     = 500,
    minPrice        = 0,        -- whole pounds; 0 allows free events
    maxPrice        = 5000,
    maxDaysAhead    = 60,       -- how far in advance an event can be created
    minLeadMinutes  = 10,       -- an event must start at least this far in the future when it is created
    maxDurationMinutes = 720,
    historyDays     = 3,        -- finished events stay listed for this many days

    categories = {
        { id = 'music', label = 'Music',        icon = '🎵' },
        { id = 'club',  label = 'Clubs & bars', icon = '🍸' },
        { id = 'sport', label = 'Sport',        icon = '🏁' },
        { id = 'food',  label = 'Food & drink', icon = '🍽️' },
        { id = 'other', label = 'Other',        icon = '🎟️' },
    },

    -- Which society account gets the takings for a job (same idea as Config.parts.accountFor). nil = the job name.
    -- accountFor = function(job) return job end,

    -- Events created for you when the resource starts (only if their key does not exist yet, so restarts never duplicate
    -- them and sold tickets are never touched). startsAt is server local time, 'YYYY-MM-DD HH:MM'. Past events are skipped.
    events = {
        -- {
        --     key = 'halloween-2026', title = 'Halloween Night', venue = 'Vanilla Unicorn', category = 'club', icon = '🎃',
        --     job = 'events', organiser = 'Vanilla Unicorn', startsAt = '2026-10-31 20:00', durationMinutes = 300,
        --     price = 25, capacity = 200, description = 'Costumes encouraged. Doors open at 8pm.',
        -- },
    },
}
