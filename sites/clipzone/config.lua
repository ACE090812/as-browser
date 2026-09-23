-- ClipZone: a lore-friendly video site. Players upload a link to a clip they've hosted elsewhere (Discord
-- CDN, Streamable, fivemanage, etc. - never the file itself, same approach as as-computer's Files app), and
-- earn an in-game payout once a video crosses view milestones. SERVER ONLY - never sent to players.
Config.clipzone = {
    -- Links to real videos and thumbnails must come from one of these hosts. Add whatever your community
    -- actually uses. '*.example.com' allows every sub-domain.
    allowedHosts = { 'cdn.discordapp.com', 'media.discordapp.net', 'streamable.com', '*.fivemanage.com' },

    -- Per-character limits.
    maxTitleLength   = 100,
    maxDescLength    = 600,
    maxCommentLength = 300,
    maxVideosPerDay  = 5,     -- uploads per character per rolling 24h
    maxCommentsPerMin = 6,

    -- Category chips shown on the Home feed and the upload form.
    categories = {
        { id = 'stunts',   label = 'Stunts & driving' },
        { id = 'rp',       label = 'Roleplay moments' },
        { id = 'crime',    label = 'Heists & chases' },
        { id = 'funny',    label = 'Funny clips' },
        { id = 'music',    label = 'Music & events' },
        { id = 'other',    label = 'Other' },
    },

    -- View payouts. A video's uploader can claim the biggest tier they've reached, once, per video, from
    -- their own channel page. `views` is UNIQUE viewers (one view counted per character per video, ever),
    -- so payouts can't be farmed by refreshing. Paid from Config.account (as-browser/config.lua).
    payoutTiers = {
        { views = 50,   amount = 150 },
        { views = 200,  amount = 500 },
        { views = 500,  amount = 1200 },
        { views = 1500, amount = 3000 },
        { views = 5000, amount = 8000 },
    },

    -- Optional Discord logs. Leave blank to turn a log off. Never sent to players.
    uploadWebhook = '',   -- new video uploads
    reportWebhook = '',   -- viewer reports (moderation queue)
    removeWebhook = '',   -- staff removals (/clipzone remove)
}
