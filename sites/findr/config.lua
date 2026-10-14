-- Findr: the search engine. SERVER ONLY.
Config.findr = {
    name          = 'Findr',
    recentShown   = 8,        -- a character's own recent searches on the home page
    trendingShown = 8,        -- most searched words in the last `trendingDays` days (all players)
    trendingDays  = 7,
    keepLogDays   = 14,       -- searches older than this are deleted
    maxPerTab     = 20,       -- results on one tab
    blocked       = {},       -- words that are never kept in recent or trending lists, e.g. { 'badword' }
}
