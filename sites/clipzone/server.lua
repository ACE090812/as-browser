-- ClipZone: lore-friendly video site. Players link a clip they've hosted elsewhere, other players watch,
-- like, comment and subscribe, and the uploader can claim a one-off payout once a video crosses a view
-- milestone. Views only ever count once per (video, character), so payouts can't be farmed by refreshing.

local CZ = Config.clipzone or {}

Browser.defineSite('clipzone', {
    title       = 'ClipZone',
    description = T('clipzone.description'),
    keywords    = Browser.words(T('clipzone.keywords')),
    category    = T('clipzone.siteCategory'),
    icon        = '📹',
    color       = '#ff0033',
    pages = {
        { path = '/upload',     title = 'Upload a clip',  description = 'Share a clip on ClipZone', keywords = { 'upload', 'clip' } },
        { path = '/leaderboard', title = 'Leaderboard',   description = 'Top channels and videos on ClipZone', keywords = { 'leaderboard', 'top' } },
    },
})

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clipzone_channels (
            citizenid  VARCHAR(64) NOT NULL PRIMARY KEY,
            name       VARCHAR(60) NOT NULL,
            bio        VARCHAR(300) NOT NULL DEFAULT '',
            avatar     VARCHAR(300) NOT NULL DEFAULT '',
            banner     VARCHAR(300) NOT NULL DEFAULT '',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clipzone_videos (
            id             INT AUTO_INCREMENT PRIMARY KEY,
            citizenid      VARCHAR(64) NOT NULL,
            title          VARCHAR(120) NOT NULL,
            description    VARCHAR(1000) NOT NULL DEFAULT '',
            category       VARCHAR(32) NOT NULL,
            video_url      VARCHAR(300) NOT NULL,
            thumb_url      VARCHAR(300) NOT NULL DEFAULT '',
            views          INT NOT NULL DEFAULT 0,
            likes          INT NOT NULL DEFAULT 0,
            paid_tier      INT NOT NULL DEFAULT 0,
            removed        TINYINT(1) NOT NULL DEFAULT 0,
            removed_reason VARCHAR(200) DEFAULT NULL,
            created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            KEY idx_channel (citizenid),
            KEY idx_category (category, removed)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clipzone_views (
            video_id   INT NOT NULL,
            citizenid  VARCHAR(64) NOT NULL,
            viewed_at  INT NOT NULL,
            PRIMARY KEY (video_id, citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clipzone_likes (
            video_id   INT NOT NULL,
            citizenid  VARCHAR(64) NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (video_id, citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clipzone_comments (
            id          INT AUTO_INCREMENT PRIMARY KEY,
            video_id    INT NOT NULL,
            citizenid   VARCHAR(64) NOT NULL,
            author_name VARCHAR(60) NOT NULL,
            body        VARCHAR(500) NOT NULL,
            created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            KEY idx_video (video_id, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clipzone_subs (
            subscriber_cid VARCHAR(64) NOT NULL,
            channel_cid    VARCHAR(64) NOT NULL,
            created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (subscriber_cid, channel_cid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

-- ---------------------------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------------------------

local function clean(s, max)
    s = tostring(s or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, max or 200)
end

--- Zero-width-joins '@' so text we forward to Discord (titles, names) can never ping anyone.
local function defang(s) return (tostring(s or ''):gsub('@', '@\226\128\139')) end

local function categoryIds()
    local out = {}
    for _, c in ipairs(CZ.categories or {}) do out[c.id] = true end
    return out
end
local CATS = categoryIds()

--- https link from an allowed host, or nil. Empty string is always allowed (clears the field).
local function hostOk(url)
    if type(url) ~= 'string' then return nil end
    if url == '' then return '' end
    if #url > 300 or not url:match('^https://[%w%-%.]+[/%w%-%._~:%?#%[%]@!%$&%*%+,;=%%]*$') then return nil end
    local host = url:match('^https://([^/:%?#]+)')
    local hosts = CZ.allowedHosts
    if type(hosts) ~= 'table' or #hosts == 0 then return url end
    for _, h in ipairs(hosts) do
        if h:sub(1, 2) == '*.' then
            local dom = h:sub(3)
            if host == dom or host:sub(-(#dom + 1)) == '.' .. dom then return url end
        elseif host == h then
            return url
        end
    end
    return nil
end

local function tiers() return CZ.payoutTiers or {} end

--- The row for the highest unclaimed tier a video qualifies for, or nil.
local function nextTier(video)
    local best, bestIdx
    for i, tr in ipairs(tiers()) do
        if i > (video.paid_tier or 0) and (video.views or 0) >= (tonumber(tr.views) or 0) then
            best, bestIdx = tr, i
        end
    end
    return best, bestIdx
end

-- ---------------------------------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------------------------------

local function ensureChannel(src, cid)
    local row = MySQL.single.await('SELECT citizenid, name, bio, avatar, banner FROM clipzone_channels WHERE citizenid = ?', { cid })
    if row then return row end
    local name = clean(Bridge.getCharacterName(src) or T('clipzone.defaultChannel'), 60)
    if name == '' then name = T('clipzone.defaultChannel') end
    MySQL.insert.await('INSERT INTO clipzone_channels (citizenid, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE name = name', { cid, name })
    return { citizenid = cid, name = name, bio = '', avatar = '', banner = '' }
end

local function subCount(cid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM clipzone_subs WHERE channel_cid = ?', { cid }) or 0
end

local function isSubbed(me, cid)
    if not me then return false end
    return (MySQL.scalar.await('SELECT 1 FROM clipzone_subs WHERE subscriber_cid = ? AND channel_cid = ?', { me, cid }) or 0) == 1
end

local function channelViews(cid)
    return MySQL.scalar.await('SELECT COALESCE(SUM(views),0) FROM clipzone_videos WHERE citizenid = ? AND removed = 0', { cid }) or 0
end

local function publicChannel(row, me)
    return {
        id = row.citizenid, name = row.name, bio = row.bio or '', avatar = row.avatar or '', banner = row.banner or '',
        subs = subCount(row.citizenid), totalViews = channelViews(row.citizenid),
        isMine = me ~= nil and me == row.citizenid, isSubscribed = isSubbed(me, row.citizenid),
    }
end

-- ---------------------------------------------------------------------------------------------
-- Video listing helpers
-- ---------------------------------------------------------------------------------------------

local FEED_SELECT = [[
    SELECT v.id, v.title, v.category, v.thumb_url AS thumbUrl, v.views, v.likes, v.citizenid,
           v.created_at AS createdAt, c.name AS channelName
    FROM clipzone_videos v LEFT JOIN clipzone_channels c ON c.citizenid = v.citizenid
    WHERE v.removed = 0
]]

Browser.handler('clipzone', 'home', function(src, data)
    local cat = tostring(data.category or '')
    if cat ~= '' and not CATS[cat] then cat = '' end

    local trending = MySQL.query.await(FEED_SELECT .. (cat ~= '' and ' AND v.category = ? ' or '') ..
        ' ORDER BY v.views DESC, v.id DESC LIMIT 12', cat ~= '' and { cat } or {}) or {}
    local latest = MySQL.query.await(FEED_SELECT .. (cat ~= '' and ' AND v.category = ? ' or '') ..
        ' ORDER BY v.id DESC LIMIT 24', cat ~= '' and { cat } or {}) or {}

    return {
        categories = CZ.categories or {},
        trending = trending, latest = latest,
    }
end)

Browser.handler('clipzone', 'search', function(src, data)
    local q = clean(data.q, 60):lower()
    if q == '' then return { results = {} } end
    local rows = MySQL.query.await(FEED_SELECT .. ' AND LOWER(v.title) LIKE ? ORDER BY v.views DESC LIMIT 20', { '%' .. q .. '%' }) or {}
    return { results = rows }
end)

Browser.handler('clipzone', 'leaderboard', function(src)
    local topChannels = MySQL.query.await([[
        SELECT c.citizenid AS id, c.name, COALESCE(SUM(v.views),0) AS totalViews,
               (SELECT COUNT(*) FROM clipzone_subs s WHERE s.channel_cid = c.citizenid) AS subs
        FROM clipzone_channels c LEFT JOIN clipzone_videos v ON v.citizenid = c.citizenid AND v.removed = 0
        GROUP BY c.citizenid, c.name ORDER BY totalViews DESC LIMIT 10
    ]]) or {}
    local topVideos = MySQL.query.await(FEED_SELECT .. ' ORDER BY v.views DESC LIMIT 10') or {}
    return { channels = topChannels, videos = topVideos }
end)

-- ---------------------------------------------------------------------------------------------
-- Watching a video
-- ---------------------------------------------------------------------------------------------

local function videoById(id)
    return MySQL.single.await('SELECT * FROM clipzone_videos WHERE id = ? AND removed = 0', { id })
end

Browser.handler('clipzone', 'video', function(src, data)
    local id = tonumber(data.id)
    if not id then return nil, T('clipzone.err.notFound') end
    local cid = Bridge.getIdentifier(src)
    local v = videoById(id)
    if not v then return nil, T('clipzone.err.notFound') end

    -- one unique view per character per video, ever - counted here rather than trusted from the page.
    if cid then
        local inserted = MySQL.insert.await(
            'INSERT IGNORE INTO clipzone_views (video_id, citizenid, viewed_at) VALUES (?, ?, ?)',
            { id, cid, os.time() })
        if inserted and inserted > 0 then
            MySQL.update.await('UPDATE clipzone_videos SET views = views + 1 WHERE id = ?', { id })
            v.views = v.views + 1
        end
    end

    local channelRow = MySQL.single.await('SELECT citizenid, name, bio, avatar, banner FROM clipzone_channels WHERE citizenid = ?', { v.citizenid })
        or { citizenid = v.citizenid, name = T('clipzone.unknownChannel'), bio = '', avatar = '', banner = '' }

    local comments = MySQL.query.await(
        'SELECT id, author_name AS authorName, body, created_at AS createdAt FROM clipzone_comments WHERE video_id = ? ORDER BY id DESC LIMIT 100', { id }) or {}
    local liked = cid and (MySQL.scalar.await('SELECT 1 FROM clipzone_likes WHERE video_id = ? AND citizenid = ?', { id, cid }) or 0) == 1 or false
    local related = MySQL.query.await(FEED_SELECT .. ' AND v.category = ? AND v.id != ? ORDER BY v.views DESC LIMIT 8', { v.category, id }) or {}
    local tr, trIdx = nil, nil
    if cid and cid == v.citizenid then tr, trIdx = nextTier(v) end

    return {
        video = { id = v.id, title = v.title, description = v.description, category = v.category, videoUrl = v.video_url,
                  thumb = v.thumb_url, views = v.views, likes = v.likes, createdAt = v.created_at, liked = liked, isMine = cid == v.citizenid },
        channel = publicChannel(channelRow, cid),
        comments = comments, related = related,
        payout = tr and { amount = tr.amount, tier = trIdx, views = tr.views } or nil,
    }
end)

Browser.handler('clipzone', 'like', function(src, data)
    local id = tonumber(data.id)
    local cid = Bridge.getIdentifier(src)
    if not id or not cid then return nil, T('clipzone.err.notFound') end
    if not videoById(id) then return nil, T('clipzone.err.notFound') end
    local existing = MySQL.scalar.await('SELECT 1 FROM clipzone_likes WHERE video_id = ? AND citizenid = ?', { id, cid })
    if existing then
        MySQL.update.await('DELETE FROM clipzone_likes WHERE video_id = ? AND citizenid = ?', { id, cid })
        MySQL.update.await('UPDATE clipzone_videos SET likes = GREATEST(0, likes - 1) WHERE id = ?', { id })
    else
        MySQL.insert.await('INSERT IGNORE INTO clipzone_likes (video_id, citizenid) VALUES (?, ?)', { id, cid })
        MySQL.update.await('UPDATE clipzone_videos SET likes = likes + 1 WHERE id = ?', { id })
    end
    local likes = MySQL.scalar.await('SELECT likes FROM clipzone_videos WHERE id = ?', { id }) or 0
    return { liked = not existing, likes = likes }
end)

local commentBucket = {}
Browser.handler('clipzone', 'comment', function(src, data)
    local id = tonumber(data.id)
    local cid = Bridge.getIdentifier(src)
    if not id or not cid then return nil, T('clipzone.err.notFound') end
    if not videoById(id) then return nil, T('clipzone.err.notFound') end
    local body = clean(data.body, CZ.maxCommentLength or 300)
    if body == '' then return nil, T('clipzone.err.emptyComment') end

    local now = GetGameTimer()
    local b = commentBucket[src]
    if not b or now - b.start > 60000 then b = { start = now, count = 0 }; commentBucket[src] = b end
    b.count = b.count + 1
    if b.count > (CZ.maxCommentsPerMin or 6) then return nil, T('clipzone.err.slowDown') end

    local name = clean(Bridge.getCharacterName(src) or T('clipzone.anon'), 60)
    local commentId = MySQL.insert.await('INSERT INTO clipzone_comments (video_id, citizenid, author_name, body) VALUES (?, ?, ?, ?)',
        { id, cid, name, body })
    return { comment = { id = commentId, authorName = name, body = body, createdAt = os.date('%Y-%m-%d %H:%M:%S') } }
end)
AddEventHandler('playerDropped', function() commentBucket[source] = nil end)

Browser.handler('clipzone', 'report', function(src, data)
    local id = tonumber(data.id)
    if not id then return nil, T('clipzone.err.notFound') end
    local v = videoById(id)
    if not v then return nil, T('clipzone.err.notFound') end
    local reason = clean(data.reason, 200)
    if reason == '' then return nil, T('clipzone.err.reportReason') end
    if type(CZ.reportWebhook) == 'string' and CZ.reportWebhook:find('^https://') then
        PerformHttpRequest(CZ.reportWebhook, function() end, 'POST', json.encode({
            embeds = { {
                title = T('clipzone.embed.reportTitle'),
                color = 0xf59e0b,
                fields = {
                    { name = T('clipzone.embed.video'), value = ('#%d - %s'):format(v.id, defang(v.title)):sub(1, 250), inline = false },
                    { name = T('clipzone.embed.reporter'), value = defang(Bridge.getCharacterName(src) or T('clipzone.anon')), inline = true },
                    { name = T('clipzone.embed.reason'), value = defang(reason):sub(1, 500), inline = false },
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            } },
        }), { ['Content-Type'] = 'application/json' })
    end
    return { ok = true }
end)

-- ---------------------------------------------------------------------------------------------
-- Channels: viewing, editing, subscribing
-- ---------------------------------------------------------------------------------------------

Browser.handler('clipzone', 'channel', function(src, data)
    local id = clean(data.id, 64)
    local me = Bridge.getIdentifier(src)
    if id == '' then id = me end
    if not id then return nil, T('clipzone.err.notFound') end
    local row = MySQL.single.await('SELECT citizenid, name, bio, avatar, banner FROM clipzone_channels WHERE citizenid = ?', { id })
    if not row then
        if me == id then row = ensureChannel(src, me) else return nil, T('clipzone.err.notFound') end
    end
    local videos = MySQL.query.await(FEED_SELECT .. ' AND v.citizenid = ? ORDER BY v.id DESC LIMIT 60', { id }) or {}
    return { channel = publicChannel(row, me), videos = videos }
end)

local CHANNEL_SPEC = {
    name   = function(v) v = clean(v, 60); if v ~= '' then return v end end,
    bio    = function(v) return clean(v, 300) end,
    avatar = hostOk,
    banner = hostOk,
}
Browser.handler('clipzone', 'channelUpdate', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('clipzone.err.notSignedIn') end
    ensureChannel(src, cid)
    local sets, vals = {}, {}
    for k, f in pairs(CHANNEL_SPEC) do
        if data[k] ~= nil then
            local val = f(data[k])
            if val == nil then return nil, T('clipzone.err.badField', k) end
            sets[#sets + 1] = k .. ' = ?'
            vals[#vals + 1] = val
        end
    end
    if #sets == 0 then return nil, T('clipzone.err.nothingToSave') end
    vals[#vals + 1] = cid
    MySQL.update.await('UPDATE clipzone_channels SET ' .. table.concat(sets, ', ') .. ' WHERE citizenid = ?', vals)
    local row = MySQL.single.await('SELECT citizenid, name, bio, avatar, banner FROM clipzone_channels WHERE citizenid = ?', { cid })
    return { channel = publicChannel(row, cid) }
end)

Browser.handler('clipzone', 'subscribe', function(src, data)
    local target = clean(data.id, 64)
    local me = Bridge.getIdentifier(src)
    if not me or target == '' then return nil, T('clipzone.err.notFound') end
    if target == me then return nil, T('clipzone.err.selfSub') end
    local existing = MySQL.scalar.await('SELECT 1 FROM clipzone_subs WHERE subscriber_cid = ? AND channel_cid = ?', { me, target })
    if existing then
        MySQL.update.await('DELETE FROM clipzone_subs WHERE subscriber_cid = ? AND channel_cid = ?', { me, target })
    else
        MySQL.insert.await('INSERT IGNORE INTO clipzone_subs (subscriber_cid, channel_cid) VALUES (?, ?)', { me, target })
    end
    return { subscribed = not existing, subs = subCount(target) }
end)

-- ---------------------------------------------------------------------------------------------
-- Uploading
-- ---------------------------------------------------------------------------------------------

local uploadBucket = {}
local function uploadsToday(cid)
    local since = os.time() - 86400
    return MySQL.scalar.await('SELECT COUNT(*) FROM clipzone_videos WHERE citizenid = ? AND UNIX_TIMESTAMP(created_at) > ?', { cid, since }) or 0
end

local function postUploadWebhook(src, v)
    if type(CZ.uploadWebhook) ~= 'string' or not CZ.uploadWebhook:find('^https://') then return end
    PerformHttpRequest(CZ.uploadWebhook, function() end, 'POST', json.encode({
        embeds = { {
            title = T('clipzone.embed.uploadTitle'),
            description = defang(v.title):sub(1, 250),
            color = 0xff0033,
            fields = {
                { name = T('clipzone.embed.channel'), value = defang(Bridge.getCharacterName(src) or T('clipzone.anon')), inline = true },
                { name = T('clipzone.embed.category'), value = v.category, inline = true },
            },
            thumbnail = v.thumb_url ~= '' and { url = v.thumb_url } or nil,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

Browser.handler('clipzone', 'upload', function(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('clipzone.err.notSignedIn') end
    ensureChannel(src, cid)

    local now = GetGameTimer()
    local b = uploadBucket[src]
    if not b or now - b.start > 5000 then b = { start = now, count = 0 }; uploadBucket[src] = b end
    b.count = b.count + 1
    if b.count > 2 then return nil, T('clipzone.err.slowDown') end

    if uploadsToday(cid) >= (CZ.maxVideosPerDay or 5) then return nil, T('clipzone.err.tooManyUploads') end

    local title = clean(data.title, CZ.maxTitleLength or 100)
    if title == '' then return nil, T('clipzone.err.needTitle') end
    local description = clean(data.description, CZ.maxDescLength or 600)
    local category = tostring(data.category or '')
    if not CATS[category] then return nil, T('clipzone.err.badCategory') end
    local videoUrl = hostOk(data.videoUrl)
    if not videoUrl or videoUrl == '' then return nil, T('clipzone.err.badVideoUrl') end
    local thumbUrl = hostOk(data.thumbUrl)
    if thumbUrl == nil then return nil, T('clipzone.err.badThumbUrl') end

    local id = MySQL.insert.await(
        'INSERT INTO clipzone_videos (citizenid, title, description, category, video_url, thumb_url) VALUES (?, ?, ?, ?, ?, ?)',
        { cid, title, description, category, videoUrl, thumbUrl })
    postUploadWebhook(src, { title = title, category = category, thumb_url = thumbUrl })
    return { id = id }
end)
AddEventHandler('playerDropped', function() uploadBucket[source] = nil end)

-- ---------------------------------------------------------------------------------------------
-- Payouts
-- ---------------------------------------------------------------------------------------------

Browser.handler('clipzone', 'claimPayout', function(src, data)
    local id = tonumber(data.id)
    local cid = Bridge.getIdentifier(src)
    if not id or not cid then return nil, T('clipzone.err.notFound') end
    local v = videoById(id)
    if not v or v.citizenid ~= cid then return nil, T('clipzone.err.notYours') end
    local tr, idx = nextTier(v)
    if not tr then return nil, T('clipzone.err.noPayout') end
    MySQL.update.await('UPDATE clipzone_videos SET paid_tier = ? WHERE id = ? AND paid_tier < ?', { idx, id, idx })
    Bridge.addMoney(src, Config.account, tr.amount, T('clipzone.embed.payoutReason', v.title))
    return { amount = tr.amount, tier = idx }
end)

-- ---------------------------------------------------------------------------------------------
-- Moderation: /clipzone remove <id> [reason...] | /clipzone restore <id>
-- Needs: add_ace group.admin command.clipzone allow   (or run from the server console)
-- ---------------------------------------------------------------------------------------------

local function postRemoveWebhook(v, staffName, reason)
    if type(CZ.removeWebhook) ~= 'string' or not CZ.removeWebhook:find('^https://') then return end
    PerformHttpRequest(CZ.removeWebhook, function() end, 'POST', json.encode({
        embeds = { {
            title = T('clipzone.embed.removeTitle'),
            color = 0xdc2626,
            fields = {
                { name = T('clipzone.embed.video'), value = ('#%d - %s'):format(v.id, defang(v.title)):sub(1, 250), inline = false },
                { name = T('clipzone.embed.staff'), value = defang(staffName), inline = true },
                { name = T('clipzone.embed.reason'), value = reason ~= '' and defang(reason):sub(1, 500) or T('clipzone.embed.noReason'), inline = false },
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

local function reply(src, msg)
    if src == 0 then print(('^5[as-browser:clipzone]^0 %s'):format(msg))
    else TriggerClientEvent('ox_lib:notify', src, { title = 'ClipZone', description = msg, type = 'inform' }) end
end

RegisterCommand('clipzone', function(src, args)
    local action, idArg = args[1], args[2]
    if action ~= 'remove' and action ~= 'restore' then
        return reply(src, 'Usage: /clipzone remove <id> [reason] | /clipzone restore <id>')
    end
    local id = tonumber(idArg)
    if not id then return reply(src, 'Give a video id.') end
    local v = MySQL.single.await('SELECT id, title, citizenid FROM clipzone_videos WHERE id = ?', { id })
    if not v then return reply(src, ('No video #%d.'):format(id)) end

    if action == 'remove' then
        local reason = clean(table.concat(args, ' ', 3), 200)
        MySQL.update.await('UPDATE clipzone_videos SET removed = 1, removed_reason = ? WHERE id = ?', { reason ~= '' and reason or nil, id })
        postRemoveWebhook(v, src == 0 and 'Console' or (GetPlayerName(src) or ('#' .. src)), reason)
        reply(src, ('Removed video #%d (%s).'):format(id, v.title))
    else
        MySQL.update.await('UPDATE clipzone_videos SET removed = 0, removed_reason = NULL WHERE id = ?', { id })
        reply(src, ('Restored video #%d (%s).'):format(id, v.title))
    end
end, true)
