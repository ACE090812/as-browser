-- Diamond Online: the casino website. SERVER ONLY. Edit freely, then restart as-browser.
--
-- Players sign up with a username and password (one account per character, tied to the character's date of birth for the age
-- check). Money only ever moves between the account here and the character's in-game bank account (Config.account in the main
-- config), never cash. Admins switch betting off, freeze accounts and read the figures in /pcadmin (needs as-computer) or with
-- the exports at the bottom of this file's README section.
Config.casino = {
    name    = 'Diamond Online',
    tagline = 'Play responsibly. 18+ only.',

    -- Minimum age to open an account, read from the character's date of birth.
    minAge = 18,
    -- What to do when the framework has no date of birth for a character: true = refuse sign up, false = let them in.
    requireDob = true,

    -- Deposits and withdrawals (whole money). Deposits come out of the bank account, withdrawals go back into it.
    minDeposit  = 10,
    maxDeposit  = 100000,
    minWithdraw = 1,

    -- Daily deposit limit. Players choose their own between minLimit and maxLimit. Lowering it works at once; raising it takes
    -- limitRaiseHours to apply, so a bad night cannot be undone in a click.
    defaultLimit     = 2000,
    minLimit         = 100,
    maxLimit         = 50000,
    limitRaiseHours  = 24,

    -- Withdrawals are allowed on a frozen account so players can always get their own money back.
    frozenCanWithdraw = true,

    -- Sessions: a signed-in player is signed out after this many minutes without doing anything (0 = never).
    idleMinutes = 60,
    -- Reminder choices offered in settings (minutes). 0 means off. The default for a new account is `reminderDefault`.
    reminderChoices  = { 0, 15, 30, 60, 120 },
    reminderDefault  = 60,

    -- Sign in guard: this many wrong passwords locks the account's sign in for lockMinutes.
    maxFailedLogins = 5,
    lockMinutes     = 10,

    -- Games. `enabled = false` hides a game and refuses its bets. Bets are whole money.
    games = {
        slots     = { enabled = true, levels = { 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000 }, jackpotMinBet = 100 },
        blackjack = { enabled = true, min = 5,  max = 5000 },
        roulette  = { enabled = true, min = 1,  max = 2000, maxTotal = 10000 },   -- max per single bet and for everything placed on one spin
        crash     = { enabled = true, min = 1,  max = 5000, edge = 0.01 },
        poker     = { enabled = true, min = 1,  max = 1000 },
        baccarat  = { enabled = true, min = 5,  max = 5000 },
        hilo      = { enabled = true, min = 1,  max = 2000, edge = 0.04, maxSteps = 12 },
    },

    -- The slots progressive jackpot (Diamond Reels). It starts at `seed`, grows by `contribution` of every Diamond Reels bet and
    -- is paid out when a player gets five jackpot symbols on a line at or above jackpotMinBet.
    jackpot = { seed = 10000, contribution = 0.01 },

    -- Who may freeze accounts besides admins (job names). Used by as-computer's admin tab.
    freezeJobs = {},

    -- Optional Discord webhook for big wins and frozen accounts. Leave empty to switch off.
    webhook = '',
    bigWin  = 25000,   -- a single payout at or above this is posted to the webhook
}
