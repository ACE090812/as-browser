-- Presento: slide decks in the style of Google Slides. SERVER ONLY - never sent to players.
-- Desktop only: it opens in Scout on as-computer and never in the phone browser.
Config.presento = {
    name = 'Presento',

    -- Per-character limits. 0 = no limit.
    maxDecks        = 0,
    maxFolders      = 50,
    maxSlides       = 50,      -- slides in one deck
    maxTitleLength  = 100,     -- deck title
    maxFolderName   = 40,

    -- How many decks the home page lists at once (Recent / Shared with me / search results).
    listLimit       = 60,

    -- The first slide is stored as a small preview for the home page cards. A slide bigger than this
    -- (bytes of JSON) gets no preview and shows the deck's icon instead.
    maxThumbBytes   = 8192,

    -- Editor limits. A slide is saved on its own, so one slide (as JSON) must stay under maxSlideBytes
    -- and that must stay below Config.maxPayloadBytes in as-browser/config.lua (16384 by default).
    maxSlideBytes   = 15000,
    maxElements     = 80,      -- things on one slide
    maxTextLength   = 2000,    -- characters in one text box
    maxTableRows    = 12,
    maxTableCols    = 8,

    -- Sharing, editing and history.
    maxShares       = 50,      -- people one presentation can be shared with
    shareMail       = true,    -- also send a phone email when someone online is given access (sd-phone Mail)
    lockSeconds     = 60,      -- one editor at a time: a lock is free again this long after the editor's page stops answering
    lockBeat        = 20,      -- how often the open editor renews its lock (seconds, keep well under lockSeconds)
    maxVersions     = 10,      -- saved versions kept per presentation (version history)
    versionEvery    = 600,     -- while someone keeps editing, save a version at most this often (seconds)

    -- Import from Google Slides (home page > Google Slides). The deck must be shared as "Anyone with the
    -- link can view". Each slide becomes a full-size picture loaded from Google. Set importDebug = true to
    -- print what the server finds if an import fails.
    importGoogle    = true,
    importDebug     = false,
    -- "Editable" imports keep each slide's shapes/charts as a background picture served from this server's own
    -- web address (FiveM's web_baseUrl, e.g. https://name-abc123.users.cfx.re). Set this only if that is not
    -- available, to the public address of this resource, e.g. 'https://my.domain/as-browser'.
    assetBaseUrl    = nil,

    -- Phone Photos: players can put photos and videos from sd-phone's Photos app on a slide. Those links
    -- are looked up on the server (exports['sd-phone']:getPhotos), so their host doesn't need to be in imageHosts.
    phonePhotos     = true,
    phoneResource   = 'sd-phone',
    phoneLimit      = 60,      -- newest photos shown in the picker

    -- Images are pasted as links and must come from one of these hosts. '*.example.com' allows every
    -- sub-domain. Add whatever your community uses.
    imageHosts = {
        'cdn.discordapp.com', 'media.discordapp.net', 'i.imgur.com', '*.fivemanage.com',
    },
}
