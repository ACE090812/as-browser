-- Presento: slide decks (Google Slides style). Desktop only, so it opens in Scout on as-computer and
-- never in the phone browser. Decks belong to the character (citizenid).
--
-- Phase 1: home page (Recent / My presentations / Shared with me, search, folders), create, rename,
-- move, copy, delete. Phase 2: the editor (slides are saved one at a time, see saveSlide / order).
-- Phase 3: phone Photos (sd-phone's getPhotos export) and video: YouTube, ClipZone clips, phone videos.
-- Phase 4: themes, starter templates (server_templates.lua), slide transitions, click animations. Present
-- mode is all in the page.
-- Phase 5: sharing (by name or character id, viewer/editor), a view link, one editor at a time (a lock the
-- page keeps alive) and version history (a snapshot per editing session, the last few kept).
-- Phase 7: casting to in-game TVs placed with as-computer's /placeprops menu (see castStart below).
-- Import: a public Google Slides link becomes a new deck, one picture per slide (importGoogle below).
--
-- Slide format (one row per slide in presento_slides, JSON in `data`, `sid` = the slide's own id).
-- The canvas is 1280 x 720 units:
--   { bg = '#ffffff', els = { { id, type = 'text'|'shape'|'line'|'image'|'table', x, y, w, h, rot, ... } } }
-- Every slide the page sends goes through cleanSlide(), which rebuilds it from known fields only.

local P = Config.presento or {}
local LIMIT = P.listLimit or 60

Browser.defineSite('presento', {
    title       = P.name or 'Presento',
    description = T('presento.description'),
    keywords    = Browser.words(T('presento.keywords')),
    category    = T('presento.siteCategory'),
    icon        = '📊',
    color       = '#ff7a1a',
    desktopOnly = true,
})

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_folders (
            id         INT AUTO_INCREMENT PRIMARY KEY,
            citizenid  VARCHAR(64) NOT NULL,
            name       VARCHAR(60) NOT NULL,
            created_at INT NOT NULL,
            KEY idx_owner (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_decks (
            id          VARCHAR(16) NOT NULL PRIMARY KEY,
            citizenid   VARCHAR(64) NOT NULL,
            owner_name  VARCHAR(80) NOT NULL DEFAULT '',
            title       VARCHAR(120) NOT NULL,
            folder_id   INT NULL,
            theme       VARCHAR(32) NOT NULL DEFAULT 'default',
            slide_count INT NOT NULL DEFAULT 0,
            thumb       MEDIUMTEXT NULL,
            created_at  INT NOT NULL,
            updated_at  INT NOT NULL,
            lock_cid    VARCHAR(64) NULL,
            lock_name   VARCHAR(80) NULL,
            lock_at     INT NULL,
            KEY idx_owner (citizenid, updated_at),
            KEY idx_folder (folder_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_slides (
            id       INT AUTO_INCREMENT PRIMARY KEY,
            deck_id  VARCHAR(16) NOT NULL,
            sid      VARCHAR(16) NULL,
            position INT NOT NULL,
            data     MEDIUMTEXT NOT NULL,
            KEY idx_deck (deck_id, position),
            UNIQUE KEY uq_sid (deck_id, sid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- Phase 1 tables had no `sid` column: add it and give the old slides one.
    local hasSid = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'presento_slides' AND COLUMN_NAME = 'sid']])
    if (tonumber(hasSid) or 0) == 0 then
        MySQL.query.await('ALTER TABLE presento_slides ADD COLUMN sid VARCHAR(16) NULL AFTER deck_id')
        MySQL.query.await('ALTER TABLE presento_slides ADD UNIQUE KEY uq_sid (deck_id, sid)')
    end
    MySQL.update.await("UPDATE presento_slides SET sid = CONCAT('s', id) WHERE sid IS NULL")
    -- Links a deck may use even though their host isn't in imageHosts: photos and videos picked from
    -- the player's own phone. The server looks them up in sd-phone, the page never supplies them.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_media (
            id         INT AUTO_INCREMENT PRIMARY KEY,
            deck_id    VARCHAR(16) NOT NULL,
            url        VARCHAR(500) NOT NULL,
            created_at INT NOT NULL,
            KEY idx_deck (deck_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_shares (
            deck_id    VARCHAR(16) NOT NULL,
            citizenid  VARCHAR(64) NOT NULL,
            name       VARCHAR(80) NOT NULL DEFAULT '',
            role       VARCHAR(8) NOT NULL DEFAULT 'viewer',
            created_at INT NOT NULL,
            PRIMARY KEY (deck_id, citizenid),
            KEY idx_cid (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- Phase 5: `via` = 'direct' (added by the owner) or 'link' (opened the view link; removed when the link is turned off).
    local hasVia = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'presento_shares' AND COLUMN_NAME = 'via']])
    if (tonumber(hasVia) or 0) == 0 then
        MySQL.query.await("ALTER TABLE presento_shares ADD COLUMN via VARCHAR(8) NOT NULL DEFAULT 'direct'")
    end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_links (
            deck_id    VARCHAR(16) NOT NULL PRIMARY KEY,
            token      VARCHAR(24) NOT NULL,
            created_at INT NOT NULL,
            UNIQUE KEY uq_token (token)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_versions (
            id          INT AUTO_INCREMENT PRIMARY KEY,
            deck_id     VARCHAR(16) NOT NULL,
            theme       VARCHAR(32) NOT NULL DEFAULT 'default',
            slide_count INT NOT NULL DEFAULT 0,
            slides      MEDIUMTEXT NOT NULL,
            saved_by    VARCHAR(80) NOT NULL DEFAULT '',
            created_at  INT NOT NULL,
            KEY idx_deck (deck_id, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

local function now() return os.time() end

local function str(v, max)
    local s = tostring(v or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, max or 100)
end

local function me(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil end
    return cid, Bridge.getCharacterName(src)
end

local function validId(id)
    return type(id) == 'string' and #id >= 6 and #id <= 16 and id:match('^%w+$') ~= nil
end

local ID_CHARS = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function newDeckId()
    for _ = 1, 10 do
        local out = {}
        for i = 1, 10 do
            local n = math.random(1, #ID_CHARS)
            out[i] = ID_CHARS:sub(n, n)
        end
        local id = table.concat(out)
        if not MySQL.scalar.await('SELECT 1 FROM presento_decks WHERE id = ?', { id }) then return id end
    end
    return nil
end

--- The deck plus this character's role on it ('owner' | 'editor' | 'viewer'), or nil when they can't see it.
local function access(deckId, cid)
    if not validId(deckId) then return nil end
    local d = MySQL.single.await('SELECT * FROM presento_decks WHERE id = ?', { deckId })
    if not d then return nil end
    if d.citizenid == cid then return d, 'owner' end
    local role = MySQL.scalar.await('SELECT role FROM presento_shares WHERE deck_id = ? AND citizenid = ?', { deckId, cid })
    if role == 'editor' or role == 'viewer' then return d, role end
    return nil
end

local function decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

local function thumbFor(slideJson)
    if type(slideJson) ~= 'string' or #slideJson > (P.maxThumbBytes or 8192) then return nil end
    return slideJson
end

local function pub(d, role)
    return {
        id = d.id, title = d.title, owner = d.owner_name, folder = d.folder_id, slides = d.slide_count,
        theme = d.theme, created = d.created_at, updated = d.updated_at, role = role or d.role,
        thumb = decode(d.thumb),
    }
end

local function countDecks(cid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM presento_decks WHERE citizenid = ?', { cid }) or 0
end

local function canMakeDeck(cid)
    local max = P.maxDecks or 0
    if max > 0 and countDecks(cid) >= max then return false, T('presento.err.tooManyDecks', max) end
    return true
end

local function ownFolder(cid, folderId)
    folderId = tonumber(folderId)
    if not folderId then return nil end
    local ok = MySQL.scalar.await('SELECT 1 FROM presento_folders WHERE id = ? AND citizenid = ?', { folderId, cid })
    return ok and folderId or false
end

--- A new deck starts with one title slide. Placeholder text (ph) is drawn by the page, never stored as text.
local function titleSlide()
    return {
        bg = '#ffffff',
        els = {
            { id = 'e1', type = 'text', x = 120, y = 250, w = 1040, h = 130, rot = 0, text = '', ph = 'title',
              font = 'sans', size = 56, bold = true, color = '#1f2937', align = 'center', valign = 'middle' },
            { id = 'e2', type = 'text', x = 120, y = 390, w = 1040, h = 70, rot = 0, text = '', ph = 'subtitle',
              font = 'sans', size = 26, color = '#6b7280', align = 'center', valign = 'top' },
        },
    }
end

-- ---------------------------------------------------------------------------------------------
-- Slide cleaning: everything the page sends is rebuilt from known fields, clamped and capped.
-- ---------------------------------------------------------------------------------------------

local function num(v, lo, hi, d)
    v = tonumber(v)
    if not v or v ~= v then return d end
    if v < lo then v = lo elseif v > hi then v = hi end
    return math.floor(v * 10 + 0.5) / 10
end

local function color(c, d)
    c = tostring(c or '')
    if c == 'transparent' or c:match('^#%x%x%x$') or c:match('^#%x%x%x%x%x%x$') or c:match('^#%x%x%x%x%x%x%x%x$') then return c end
    return d
end

local function oneOf(v, list, d)
    for _, x in ipairs(list) do if v == x then return v end end
    return d
end

local function text(v, max)
    return (tostring(v or ''):gsub('[%z\1-\8\11-\31]', '')):sub(1, max)
end

local function smallId(v, d)
    if type(v) == 'string' and #v >= 1 and #v <= 16 and v:match('^%w+$') then return v end
    return d
end

--- https://host/... where host is in `list` ('*.example.com' allows every sub-domain).
local function hostAllowed(url, list)
    if type(url) ~= 'string' or #url > 500 or url:find('[%s"\'<>]') then return false end
    local host = url:match('^https://([^/%?#:]+)')
    if not host then return false end
    host = host:lower()
    for _, h in ipairs(list or {}) do
        h = tostring(h):lower()
        if h:sub(1, 2) == '*.' then
            local base = h:sub(3)
            if host == base or host:sub(-(#base + 1)) == '.' .. base then return true end
        elseif host == h then
            return true
        end
    end
    return false
end

-- sd-phone Photos (public export getPhotos, same as as-computer's Files app; nothing in sd-phone is edited)
local function phoneRes()
    if P.phonePhotos == false then return nil end
    local r = P.phoneResource or 'sd-phone'
    if GetResourceState(r) ~= 'started' then return nil end
    return r
end

local function phonePhotos(src, limit)
    local r = phoneRes()
    if not r then return nil end
    local ok, list = pcall(function() return exports[r]:getPhotos(src, { limit = limit or 60 }) end)
    if not ok or type(list) ~= 'table' then return nil end
    local out = {}
    for _, ph in ipairs(list) do
        if type(ph) == 'table' and ph.id ~= nil and type(ph.url) == 'string' and #ph.url <= 500 and ph.url:match('^https://[^%s"\'<>]+$') then
            out[#out + 1] = { id = tostring(ph.id), url = ph.url, isVideo = ph.isVideo == true, timestamp = math.floor(tonumber(ph.timestamp) or 0) }
        end
    end
    return out
end

--- ClipZone clip by id (only live ones), cached for one save.
local function clipById(ctx, id)
    id = tonumber(id)
    if not id or not Browser.isEnabled('clipzone') then return nil end
    ctx.clips = ctx.clips or {}
    if ctx.clips[id] == nil then
        local ok, row = pcall(function()
            return MySQL.single.await('SELECT id, title, video_url, thumb_url FROM clipzone_videos WHERE id = ? AND removed = 0', { id })
        end)
        ctx.clips[id] = ok and row or false
    end
    return ctx.clips[id] or nil
end

local function cleanEl(e, i, ctx)
    if type(e) ~= 'table' then return nil end
    ctx = ctx or {}
    local ty = oneOf(e.type, { 'text', 'shape', 'line', 'image', 'table', 'video' }, nil)
    if not ty then return nil end
    local o = {
        id = smallId(e.id, 'e' .. i), type = ty,
        x = num(e.x, -1280, 2560, 0), y = num(e.y, -720, 1440, 0),
        w = num(e.w, 4, 4000, 100), h = num(e.h, 2, 4000, 50), rot = num(e.rot, -360, 360, 0),
    }
    if e.opacity ~= nil then o.opacity = num(e.opacity, 0, 1, 1) end
    o.anim = oneOf(e.anim, { 'fade', 'left', 'right', 'up', 'zoom' }, nil)
    if o.anim then o.step = math.floor(num(e.step, 1, 20, 1)) end

    if ty == 'text' then
        o.text = text(e.text, P.maxTextLength or 2000)
        o.ph = oneOf(e.ph, { 'title', 'subtitle', 'body' }, nil)
        o.font = oneOf(e.font, { 'sans', 'serif', 'mono', 'display', 'round' }, 'sans')
        o.size = num(e.size, 6, 300, 24)
        o.color = color(e.color, '#1f2937')
        o.align = oneOf(e.align, { 'left', 'center', 'right', 'justify' }, 'left')
        o.valign = oneOf(e.valign, { 'top', 'middle', 'bottom' }, 'top')
        if e.bold == true then o.bold = true end
        if e.italic == true then o.italic = true end
        if e.underline == true then o.underline = true end
        if e.fill then o.fill = color(e.fill, nil) end
    elseif ty == 'shape' then
        o.shape = oneOf(e.shape, { 'rect', 'round', 'ellipse' }, 'rect')
        o.fill = color(e.fill, '#4285f4')
        o.stroke = num(e.stroke, 0, 40, 0)
        o.strokeColor = color(e.strokeColor, '#1f2937')
    elseif ty == 'line' then
        o.color = color(e.color, '#1f2937')
        o.stroke = num(e.stroke, 1, 40, 4)
        if e.arrow == true then o.arrow = true end
    elseif ty == 'image' then
        if type(e.src) ~= 'string' then return nil end
        if not hostAllowed(e.src, P.imageHosts) and not (ctx.trusted and ctx.trusted[e.src]) then return nil end
        o.src = e.src
        o.fit = oneOf(e.fit, { 'cover', 'contain' }, 'cover')
    elseif ty == 'table' then
        local cells, rows = {}, type(e.cells) == 'table' and e.cells or {}
        local maxR, maxC = P.maxTableRows or 12, P.maxTableCols or 8
        for r = 1, math.min(#rows, maxR) do
            local row = type(rows[r]) == 'table' and rows[r] or {}
            local out = {}
            for c = 1, math.min(math.max(#row, 1), maxC) do out[c] = text(row[c], 300) end
            cells[r] = out
        end
        if #cells == 0 then return nil end
        o.cells = cells
        o.size = num(e.size, 6, 120, 20)
        o.color = color(e.color, '#1f2937')
        o.headFill = color(e.headFill, '#e8eaed')
        o.strokeColor = color(e.strokeColor, '#9aa0a6')
    elseif ty == 'video' then
        o.src = oneOf(e.src, { 'youtube', 'clip', 'file' }, nil)
        if o.src == 'youtube' then
            if type(e.vid) ~= 'string' or not e.vid:match('^[%w_%-]+$') or #e.vid ~= 11 then return nil end
            o.vid = e.vid
            o.start = math.floor(num(e.start, 0, 86400, 0))
        elseif o.src == 'clip' then
            local c = clipById(ctx, e.clip)
            if not c then return nil end
            o.clip, o.url, o.thumb, o.title = c.id, c.video_url, c.thumb_url, text(c.title, 120)
        elseif o.src == 'file' then
            if type(e.url) ~= 'string' or not (ctx.trusted and ctx.trusted[e.url]) then return nil end
            o.url = e.url
        else
            return nil
        end
        if e.muted == true then o.muted = true end
        if e.loop == true then o.loop = true end
    end
    return o
end

local function cleanSlide(s, ctx)
    if type(s) ~= 'table' then return nil end
    local els, src = {}, type(s.els) == 'table' and s.els or {}
    local max = P.maxElements or 80
    for i = 1, math.min(#src, max) do
        local e = cleanEl(src[i], i, ctx)
        if e then els[#els + 1] = e end
    end
    return { bg = color(s.bg, '#ffffff'), els = els, trans = oneOf(s.trans, { 'fade', 'slide', 'zoom' }, nil) }
end

local function newSid()
    local out = { 's' }
    for i = 2, 10 do
        local n = math.random(1, #ID_CHARS)
        out[i] = ID_CHARS:sub(n, n)
    end
    return table.concat(out)
end

local function refreshDeck(deckId)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM presento_slides WHERE deck_id = ?', { deckId }) or 0
    local first = MySQL.scalar.await('SELECT data FROM presento_slides WHERE deck_id = ? ORDER BY position LIMIT 1', { deckId })
    MySQL.update.await('UPDATE presento_decks SET slide_count = ?, thumb = ?, updated_at = ? WHERE id = ?', { count, thumbFor(first), now(), deckId })
end

local function editableDeck(src, deckId)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d, role = access(deckId, cid)
    if not d then return nil, T('presento.err.notFound') end
    if role == 'viewer' then return nil, T('presento.err.noEdit') end
    return d, role
end

-- ---------------------------------------------------------------------------------------------
-- One editor at a time. The editor page calls `lock` when it opens and every lockBeat seconds; a lock
-- older than lockSeconds is free again. Anything that changes slides needs the lock (writableDeck).
-- ---------------------------------------------------------------------------------------------

local LOCK_TTL = P.lockSeconds or 60
local lockHolders = {}   -- source -> { [deckId] = true }

local function lockFresh(d)
    return d.lock_cid ~= nil and d.lock_at ~= nil and (now() - (tonumber(d.lock_at) or 0)) < LOCK_TTL
end

local function takeLock(src, d, cid, name)
    MySQL.update.await('UPDATE presento_decks SET lock_cid = ?, lock_name = ?, lock_at = ? WHERE id = ?', { cid, str(name, 80), now(), d.id })
    lockHolders[src] = lockHolders[src] or {}
    lockHolders[src][d.id] = true
end

local function writableDeck(src, deckId)
    local d, role = editableDeck(src, deckId)
    if not d then return nil, role end
    local cid, name = me(src)
    if lockFresh(d) and d.lock_cid ~= cid then return nil, T('presento.err.lockedBy', d.lock_name or '?') end
    if d.lock_cid ~= cid or (now() - (tonumber(d.lock_at) or 0)) > 10 then takeLock(src, d, cid, name) end
    return d, role
end

-- ---------------------------------------------------------------------------------------------
-- Version history: a copy of every slide, taken when an editing session starts and ends, and every
-- versionEvery seconds while someone keeps editing. Only taken when something changed since the last one.
-- ---------------------------------------------------------------------------------------------

local function snapshot(deckId, who, force)
    local d = MySQL.single.await('SELECT updated_at, theme FROM presento_decks WHERE id = ?', { deckId })
    if not d then return false end
    local last = tonumber(MySQL.scalar.await('SELECT MAX(created_at) FROM presento_versions WHERE deck_id = ?', { deckId })) or 0
    if not force and last > 0 and (tonumber(d.updated_at) or 0) <= last then return false end
    local rows = MySQL.query.await('SELECT data FROM presento_slides WHERE deck_id = ? ORDER BY position', { deckId }) or {}
    if #rows == 0 then return false end
    local parts = {}
    for i, r in ipairs(rows) do parts[i] = r.data end
    MySQL.insert.await('INSERT INTO presento_versions (deck_id, theme, slide_count, slides, saved_by, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        { deckId, d.theme or 'default', #rows, '[' .. table.concat(parts, ',') .. ']', str(who, 80), now() })
    MySQL.update.await([[DELETE FROM presento_versions WHERE deck_id = ? AND id NOT IN
        (SELECT id FROM (SELECT id FROM presento_versions WHERE deck_id = ? ORDER BY id DESC LIMIT ?) t)]], { deckId, deckId, P.maxVersions or 10 })
    return true
end

local function releaseLock(src, deckId)
    local d = MySQL.single.await('SELECT id, lock_cid, lock_name FROM presento_decks WHERE id = ?', { deckId })
    if d and d.lock_cid then
        snapshot(deckId, d.lock_name or '')
        MySQL.update.await('UPDATE presento_decks SET lock_cid = NULL, lock_name = NULL, lock_at = NULL WHERE id = ? AND lock_cid = ?', { deckId, d.lock_cid })
    end
    if lockHolders[src] then lockHolders[src][deckId] = nil end
end

AddEventHandler('playerDropped', function()
    local src = source
    local held = lockHolders[src]
    lockHolders[src] = nil
    if not held then return end
    for deckId in pairs(held) do
        local d = MySQL.single.await('SELECT lock_name FROM presento_decks WHERE id = ?', { deckId })
        snapshot(deckId, d and d.lock_name or '')
        MySQL.update.await('UPDATE presento_decks SET lock_cid = NULL, lock_name = NULL, lock_at = NULL WHERE id = ?', { deckId })
    end
end)

local DECK_COLS = 'd.id, d.citizenid, d.owner_name, d.title, d.folder_id, d.theme, d.slide_count, d.thumb, d.created_at, d.updated_at'

local function likeArg(q)
    return '%' .. q:gsub('[%%_\\]', '\\%0') .. '%'
end

-- ---------------------------------------------------------------------------------------------
-- Home
-- ---------------------------------------------------------------------------------------------

--- data = { view = 'recent'|'mine'|'shared', folder = id|nil, q = 'search' }
Browser.handler('presento', 'home', function(src, data)
    local cid, name = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end

    local view = data.view
    if view ~= 'mine' and view ~= 'shared' then view = 'recent' end
    local q = str(data.q, 60):lower()
    local folderId = tonumber(data.folder)

    local owned  = 'SELECT ' .. DECK_COLS .. ", 'owner' AS role FROM presento_decks d WHERE d.citizenid = ?"
    local shared = 'SELECT ' .. DECK_COLS .. ' , s.role AS role FROM presento_decks d JOIN presento_shares s ON s.deck_id = d.id WHERE s.citizenid = ?'

    local rows, folder
    if q ~= '' then
        local like = likeArg(q)
        rows = MySQL.query.await(
            '(' .. owned .. ' AND LOWER(d.title) LIKE ?) UNION ALL (' .. shared .. ' AND LOWER(d.title) LIKE ?) ORDER BY updated_at DESC LIMIT ?',
            { cid, like, cid, like, LIMIT })
    elseif view == 'shared' then
        rows = MySQL.query.await(shared .. ' ORDER BY d.updated_at DESC LIMIT ?', { cid, LIMIT })
    elseif view == 'mine' then
        if folderId then
            folder = MySQL.single.await('SELECT id, name FROM presento_folders WHERE id = ? AND citizenid = ?', { folderId, cid })
            if not folder then return nil, T('presento.err.folderNotFound') end
            rows = MySQL.query.await(owned .. ' AND d.folder_id = ? ORDER BY d.updated_at DESC', { cid, folderId })
        else
            rows = MySQL.query.await(owned .. ' AND d.folder_id IS NULL ORDER BY d.updated_at DESC', { cid })
        end
    else
        rows = MySQL.query.await('(' .. owned .. ') UNION ALL (' .. shared .. ') ORDER BY updated_at DESC LIMIT ?', { cid, cid, LIMIT })
    end

    local decks = {}
    for i, r in ipairs(rows or {}) do decks[i] = pub(r) end

    local folders = MySQL.query.await([[
        SELECT f.id, f.name, (SELECT COUNT(*) FROM presento_decks d WHERE d.folder_id = f.id) AS count
        FROM presento_folders f WHERE f.citizenid = ? ORDER BY f.name
    ]], { cid }) or {}

    local templates = {}
    for i, tpl in ipairs(PresentoTemplates or {}) do
        templates[i] = { key = tpl.key, name = T(tpl.nameKey or tpl.key), slide = tpl.slides and tpl.slides[1] or nil }
    end

    return { me = name, view = view, q = q, folder = folder, folders = folders, decks = decks, templates = templates, canImport = P.importGoogle ~= false }
end)

-- ---------------------------------------------------------------------------------------------
-- Decks
-- ---------------------------------------------------------------------------------------------

local function templateByKey(key)
    for _, tpl in ipairs(PresentoTemplates or {}) do
        if tpl.key == key then return tpl end
    end
    return nil
end

local function validTheme(key)
    return type(key) == 'string' and #key <= 32 and key:match('^[%w_%-]+$') ~= nil
end

--- data = { title, folder, template = key|nil }
Browser.handler('presento', 'create', function(src, data)
    local cid, name = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local ok, err = canMakeDeck(cid)
    if not ok then return nil, err end

    local folder = ownFolder(cid, data.folder)
    if folder == false then return nil, T('presento.err.folderNotFound') end

    local id = newDeckId()
    if not id then return nil, T('shell.err.generic') end
    local title = str(data.title, P.maxTitleLength or 100)
    if title == '' then title = T('presento.untitled') end

    local slides, theme = { json.encode(titleSlide()) }, 'default'
    local tpl = data.template and templateByKey(data.template)
    if tpl then
        slides = {}
        for i = 1, math.min(#tpl.slides, P.maxSlides or 50) do
            local clean = cleanSlide(tpl.slides[i], {})
            if clean then slides[#slides + 1] = json.encode(clean) end
        end
        if #slides == 0 then slides = { json.encode(titleSlide()) } end
        theme = validTheme(tpl.theme) and tpl.theme or 'default'
        if str(data.title, 5) == '' then title = str(T(tpl.nameKey or tpl.key), P.maxTitleLength or 100) end
    end

    local t = now()
    MySQL.insert.await(
        'INSERT INTO presento_decks (id, citizenid, owner_name, title, folder_id, theme, slide_count, thumb, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { id, cid, str(name, 80), title, folder, theme, #slides, thumbFor(slides[1]), t, t })
    for i, sl in ipairs(slides) do
        MySQL.insert.await('INSERT INTO presento_slides (deck_id, sid, position, data) VALUES (?, ?, ?, ?)', { id, newSid(), i, sl })
    end
    return { id = id }
end)

--- data = { id } -> the deck and all its slides.
Browser.handler('presento', 'open', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d, role = access(data.id, cid)
    if not d then return nil, T('presento.err.notFound') end
    local rows = MySQL.query.await('SELECT sid, data FROM presento_slides WHERE deck_id = ? ORDER BY position', { d.id }) or {}
    local slides = {}
    for i, r in ipairs(rows) do slides[i] = { sid = r.sid, data = decode(r.data) or { bg = '#ffffff', els = {} } } end
    local deck = pub(d, role)
    deck.thumb = nil
    if lockFresh(d) and d.lock_cid ~= cid then deck.lockedBy = d.lock_name or '?' end
    return {
        deck = deck, slides = slides,
        cfg = {
            maxSlides = P.maxSlides or 50, maxElements = P.maxElements or 80, maxSlideBytes = P.maxSlideBytes or 15000,
            maxTableRows = P.maxTableRows or 12, maxTableCols = P.maxTableCols or 8, imageHosts = P.imageHosts or {},
            phone = phoneRes() ~= nil, clipzone = Browser.isEnabled('clipzone'),
            lockBeat = P.lockBeat or 20,
            cast = P.cast ~= false and GetResourceState(P.castResource or 'as-computer') == 'started',
        },
    }
end)

--- data = { id, sid, data = slide } - saves one slide (new or changed). Positions come from `order`.
Browser.handler('presento', 'saveSlide', function(src, data)
    local d, err = writableDeck(src, data.id)
    if not d then return nil, err end
    local sid = smallId(data.sid, nil)
    if not sid then return nil, T('shell.err.badRequest') end
    local trusted = {}
    for _, r in ipairs(MySQL.query.await('SELECT url FROM presento_media WHERE deck_id = ?', { d.id }) or {}) do trusted[r.url] = true end
    local slide = cleanSlide(data.data, { trusted = trusted })
    if not slide then return nil, T('shell.err.badRequest') end
    local encoded = json.encode(slide)
    if #encoded > (P.maxSlideBytes or 15000) + 2000 then return nil, T('presento.err.slideTooBig') end

    local exists = MySQL.scalar.await('SELECT position FROM presento_slides WHERE deck_id = ? AND sid = ?', { d.id, sid })
    if exists then
        MySQL.update.await('UPDATE presento_slides SET data = ? WHERE deck_id = ? AND sid = ?', { encoded, d.id, sid })
        if tonumber(exists) == 1 then
            MySQL.update.await('UPDATE presento_decks SET thumb = ?, updated_at = ? WHERE id = ?', { thumbFor(encoded), now(), d.id })
        else
            MySQL.update.await('UPDATE presento_decks SET updated_at = ? WHERE id = ?', { now(), d.id })
        end
    else
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM presento_slides WHERE deck_id = ?', { d.id }) or 0
        if count >= (P.maxSlides or 50) then return nil, T('presento.err.tooManySlides', P.maxSlides or 50) end
        local pos = (MySQL.scalar.await('SELECT MAX(position) FROM presento_slides WHERE deck_id = ?', { d.id }) or 0) + 1
        MySQL.insert.await('INSERT INTO presento_slides (deck_id, sid, position, data) VALUES (?, ?, ?, ?)', { d.id, sid, pos, encoded })
        refreshDeck(d.id)
    end
    return true
end)

--- data = { id, sids = { ... } } - the deck's slide order. Slides not in the list are deleted.
Browser.handler('presento', 'order', function(src, data)
    local d, err = writableDeck(src, data.id)
    if not d then return nil, err end
    local sids = type(data.sids) == 'table' and data.sids or {}
    if #sids < 1 or #sids > (P.maxSlides or 50) then return nil, T('shell.err.badRequest') end

    local rows = MySQL.query.await('SELECT sid FROM presento_slides WHERE deck_id = ?', { d.id }) or {}
    local have, keep = {}, {}
    for _, r in ipairs(rows) do have[r.sid] = true end
    for i, sid in ipairs(sids) do
        if type(sid) ~= 'string' or not have[sid] or keep[sid] then return nil, T('presento.err.outOfSync') end
        keep[sid] = i
    end
    for sid in pairs(have) do
        if not keep[sid] then MySQL.update.await('DELETE FROM presento_slides WHERE deck_id = ? AND sid = ?', { d.id, sid }) end
    end
    for sid, pos in pairs(keep) do
        MySQL.update.await('UPDATE presento_slides SET position = ? WHERE deck_id = ? AND sid = ?', { pos, d.id, sid })
    end
    refreshDeck(d.id)
    return true
end)

--- data = { id, theme } - owner or editor. The page restyles the slides itself and saves them as usual.
Browser.handler('presento', 'setTheme', function(src, data)
    local d, err = writableDeck(src, data.id)
    if not d then return nil, err end
    if not validTheme(data.theme) then return nil, T('shell.err.badRequest') end
    MySQL.update.await('UPDATE presento_decks SET theme = ? WHERE id = ?', { data.theme, d.id })
    return true
end)

--- data = { id, title } - owner or editor.
Browser.handler('presento', 'rename', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d, role = access(data.id, cid)
    if not d then return nil, T('presento.err.notFound') end
    if role == 'viewer' then return nil, T('presento.err.noEdit') end
    local title = str(data.title, P.maxTitleLength or 100)
    if title == '' then return nil, T('presento.err.needName') end
    MySQL.update.await('UPDATE presento_decks SET title = ?, updated_at = ? WHERE id = ?', { title, now(), d.id })
    return { title = title }
end)

--- data = { id, folder } - owner only; folder nil = back to My presentations.
Browser.handler('presento', 'move', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d, role = access(data.id, cid)
    if not d then return nil, T('presento.err.notFound') end
    if role ~= 'owner' then return nil, T('presento.err.notOwner') end
    local folder = ownFolder(cid, data.folder)
    if folder == false then return nil, T('presento.err.folderNotFound') end
    MySQL.update.await('UPDATE presento_decks SET folder_id = ? WHERE id = ?', { folder, d.id })
    return true
end)

--- data = { id } - anyone who can see a deck can copy it into their own presentations.
Browser.handler('presento', 'copy', function(src, data)
    local cid, name = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d = access(data.id, cid)
    if not d then return nil, T('presento.err.notFound') end
    local ok, err = canMakeDeck(cid)
    if not ok then return nil, err end

    local id = newDeckId()
    if not id then return nil, T('shell.err.generic') end
    local t = now()
    local title = str(T('presento.copyOf', d.title), P.maxTitleLength or 100)
    MySQL.insert.await(
        'INSERT INTO presento_decks (id, citizenid, owner_name, title, folder_id, theme, slide_count, thumb, created_at, updated_at) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)',
        { id, cid, str(name, 80), title, d.theme, d.slide_count, d.thumb, t, t })
    MySQL.query.await('INSERT INTO presento_slides (deck_id, sid, position, data) SELECT ?, sid, position, data FROM presento_slides WHERE deck_id = ?', { id, d.id })
    MySQL.query.await('INSERT INTO presento_media (deck_id, url, created_at) SELECT ?, url, ? FROM presento_media WHERE deck_id = ?', { id, t, d.id })
    return { id = id }
end)

--- data = { id } - owner only. Gone straight away, for everyone it was shared with too.
Browser.handler('presento', 'delete', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d, role = access(data.id, cid)
    if not d then return nil, T('presento.err.notFound') end
    if role ~= 'owner' then return nil, T('presento.err.notOwner') end
    MySQL.update.await('DELETE FROM presento_slides WHERE deck_id = ?', { d.id })
    MySQL.update.await('DELETE FROM presento_shares WHERE deck_id = ?', { d.id })
    MySQL.update.await([[DELETE a FROM presento_assets a WHERE a.deck_id = ? AND NOT EXISTS
        (SELECT 1 FROM presento_media m WHERE m.deck_id <> ? AND m.url LIKE CONCAT('%/', a.id, '.svg'))]], { d.id, d.id })
    MySQL.update.await('DELETE FROM presento_media WHERE deck_id = ?', { d.id })
    MySQL.update.await('DELETE FROM presento_links WHERE deck_id = ?', { d.id })
    MySQL.update.await('DELETE FROM presento_versions WHERE deck_id = ?', { d.id })
    MySQL.update.await('DELETE FROM presento_decks WHERE id = ?', { d.id })
    return true
end)

--- data = { id } - someone it was shared with drops it from their list.
Browser.handler('presento', 'leave', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    if not validId(data.id) then return nil, T('presento.err.notFound') end
    MySQL.update.await('DELETE FROM presento_shares WHERE deck_id = ? AND citizenid = ?', { data.id, cid })
    return true
end)

-- ---------------------------------------------------------------------------------------------
-- Media: phone Photos and ClipZone
-- ---------------------------------------------------------------------------------------------

--- data = { id = deck } -> this character's phone photos and videos (newest first).
Browser.handler('presento', 'phoneList', function(src, data)
    local d, err = editableDeck(src, data.id)
    if not d then return nil, err end
    local list = phonePhotos(src, P.phoneLimit or 60)
    if not list then return nil, T('presento.err.phoneOff') end
    return { photos = list }
end)

--- data = { id = deck, photo = photo id } -> { url, isVideo }. The link is looked up in sd-phone and
--- remembered for this deck, so saveSlide accepts it even when its host isn't in imageHosts.
Browser.handler('presento', 'phoneAttach', function(src, data)
    local d, err = editableDeck(src, data.id)
    if not d then return nil, err end
    local list = phonePhotos(src, 200)
    if not list then return nil, T('presento.err.phoneOff') end
    for _, ph in ipairs(list) do
        if ph.id == tostring(data.photo) then
            if not MySQL.scalar.await('SELECT 1 FROM presento_media WHERE deck_id = ? AND url = ?', { d.id, ph.url }) then
                MySQL.insert.await('INSERT INTO presento_media (deck_id, url, created_at) VALUES (?, ?, ?)', { d.id, ph.url, now() })
            end
            return { url = ph.url, isVideo = ph.isVideo }
        end
    end
    return nil, T('presento.err.photoGone')
end)

--- data = { q } -> ClipZone clips to put on a slide (the player's own first, then the most watched).
Browser.handler('presento', 'clips', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    if not Browser.isEnabled('clipzone') then return nil, T('presento.err.clipzoneOff') end
    local q = str(data.q, 60):lower()
    local sql = [[SELECT v.id, v.title, v.thumb_url AS thumb, v.video_url AS url, v.views, COALESCE(c.name, '') AS channel
        FROM clipzone_videos v LEFT JOIN clipzone_channels c ON c.citizenid = v.citizenid WHERE v.removed = 0]]
    local args = {}
    if q ~= '' then sql = sql .. ' AND LOWER(v.title) LIKE ?'; args[#args + 1] = likeArg(q) end
    sql = sql .. ' ORDER BY (v.citizenid = ?) DESC, v.views DESC, v.id DESC LIMIT 30'
    args[#args + 1] = cid
    local ok, rows = pcall(function() return MySQL.query.await(sql, args) end)
    if not ok then return nil, T('presento.err.clipzoneOff') end
    return { clips = rows or {} }
end)

-- ---------------------------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------------------------

--- In-character name for a character id, online or not. nil when nobody has that id.
local function lookupName(cid)
    local online = Bridge.findSource(cid)
    if online then return Bridge.getCharacterName(online) end
    local fw = Bridge.framework
    local ok, name = pcall(function()
        if fw == 'qb' or fw == 'qbx' then
            local ci = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', { cid })
            local t = type(ci) == 'string' and json.decode(ci) or ci
            return type(t) == 'table' and ((t.firstname or '') .. ' ' .. (t.lastname or '')) or nil
        elseif fw == 'esx' then
            return MySQL.scalar.await("SELECT CONCAT(firstname, ' ', lastname) FROM users WHERE identifier = ?", { cid })
        end
    end)
    if ok and type(name) == 'string' and name:match('%S') then return str(name, 80) end
    return nil
end

--- Characters matching a name (online first, then offline) or an exact character id.
local function searchPeople(q, skip)
    local out, seen = {}, {}
    local function add(cid, name, online)
        if cid and not seen[cid] and not skip[cid] and #out < 12 then
            seen[cid] = true
            out[#out + 1] = { cid = cid, name = name, online = online }
        end
    end
    local ql = q:lower()
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        local cid = s and Bridge.getIdentifier(s)
        if cid then
            local nm = Bridge.getCharacterName(s) or ''
            if nm:lower():find(ql, 1, true) or cid:lower() == ql then add(cid, nm, true) end
        end
    end
    if q:match('^[%w:_%-]+$') and #q >= 3 then
        for _, try in ipairs({ q, q:upper() }) do
            local nm = lookupName(try)
            if nm then add(try, nm, Bridge.findSource(try) ~= nil) break end
        end
    end
    if #out < 12 and #q >= 3 then
        local fw = Bridge.framework
        local ok, rows = pcall(function()
            if fw == 'qb' or fw == 'qbx' then
                return MySQL.query.await([[SELECT citizenid, CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) AS name
                    FROM players WHERE LOWER(CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')))) LIKE ? LIMIT 12]], { likeArg(ql) })
            elseif fw == 'esx' then
                return MySQL.query.await("SELECT identifier AS citizenid, CONCAT(firstname, ' ', lastname) AS name FROM users WHERE LOWER(CONCAT(firstname, ' ', lastname)) LIKE ? LIMIT 12", { likeArg(ql) })
            end
        end)
        if ok and type(rows) == 'table' then
            for _, r in ipairs(rows) do add(r.citizenid, str(r.name, 80), Bridge.findSource(r.citizenid) ~= nil) end
        end
    end
    return out
end

local function ownerDeck(src, deckId)
    local cid, name = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d, role = access(deckId, cid)
    if not d then return nil, T('presento.err.notFound') end
    if role ~= 'owner' then return nil, T('presento.err.notOwner') end
    return d, cid, name
end

local function shareState(d)
    return {
        people = MySQL.query.await('SELECT citizenid AS cid, name, role, via FROM presento_shares WHERE deck_id = ? ORDER BY name', { d.id }) or {},
        link = MySQL.scalar.await('SELECT token FROM presento_links WHERE deck_id = ?', { d.id }),
        owner = d.owner_name,
    }
end

local function validCid(v) return type(v) == 'string' and #v >= 1 and #v <= 64 and v:match('^[%w:_%-]+$') ~= nil end

local function tellShared(cid, ownerName, d, role)
    local tsrc = Bridge.findSource(cid)
    if not tsrc then return end
    TriggerClientEvent('ox_lib:notify', tsrc, {
        title = P.name or 'Presento', type = 'inform',
        description = T('presento.n.shared', ownerName, d.title, T('presento.role.' .. role)),
    })
    if P.shareMail then
        local site = Browser.sites.presento
        Bridge.sendPhoneMail(tsrc, cid, { name = P.name or 'Presento', email = 'noreply@' .. (site and site.domain or 'presento.co.uk') },
            T('presento.n.mailSubject', d.title), T('presento.n.mailBody', ownerName, d.title, site and site.domain or 'presento.co.uk'))
    end
end

--- data = { id } - owner only.
Browser.handler('presento', 'shareList', function(src, data)
    local d, err = ownerDeck(src, data.id)
    if not d then return nil, err end
    return shareState(d)
end)

--- data = { id, q } -> people to add (never the owner or anyone already on the list).
Browser.handler('presento', 'shareFind', function(src, data)
    local d, cid = ownerDeck(src, data.id)
    if not d then return nil, cid end
    local q = str(data.q, 40)
    if #q < 2 then return { people = {} } end
    local skip = { [cid] = true }
    for _, r in ipairs(MySQL.query.await('SELECT citizenid FROM presento_shares WHERE deck_id = ?', { d.id }) or {}) do skip[r.citizenid] = true end
    return { people = searchPeople(q, skip) }
end)

--- data = { id, cid, role = 'viewer'|'editor' }
Browser.handler('presento', 'shareAdd', function(src, data)
    local d, cid, name = ownerDeck(src, data.id)
    if not d then return nil, cid end
    if not validCid(data.cid) or data.cid == cid then return nil, T('presento.err.personNotFound') end
    local role = oneOf(data.role, { 'viewer', 'editor' }, 'viewer')
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM presento_shares WHERE deck_id = ?', { d.id }) or 0
    if count >= (P.maxShares or 50) then return nil, T('presento.err.tooManyShares', P.maxShares or 50) end
    local target = lookupName(data.cid)
    if not target then return nil, T('presento.err.personNotFound') end
    MySQL.insert.await([[INSERT INTO presento_shares (deck_id, citizenid, name, role, via, created_at) VALUES (?, ?, ?, ?, 'direct', ?)
        ON DUPLICATE KEY UPDATE role = VALUES(role), name = VALUES(name), via = 'direct']], { d.id, data.cid, target, role, now() })
    tellShared(data.cid, name, d, role)
    return shareState(d)
end)

--- data = { id, cid, role }
Browser.handler('presento', 'shareRole', function(src, data)
    local d, err = ownerDeck(src, data.id)
    if not d then return nil, err end
    if not validCid(data.cid) then return nil, T('shell.err.badRequest') end
    local role = oneOf(data.role, { 'viewer', 'editor' }, nil)
    if not role then return nil, T('shell.err.badRequest') end
    MySQL.update.await("UPDATE presento_shares SET role = ?, via = 'direct' WHERE deck_id = ? AND citizenid = ?", { role, d.id, data.cid })
    return shareState(d)
end)

--- data = { id, cid }
Browser.handler('presento', 'shareRemove', function(src, data)
    local d, err = ownerDeck(src, data.id)
    if not d then return nil, err end
    if not validCid(data.cid) then return nil, T('shell.err.badRequest') end
    MySQL.update.await('DELETE FROM presento_shares WHERE deck_id = ? AND citizenid = ?', { d.id, data.cid })
    return shareState(d)
end)

--- data = { id, on } - the view link. Turning it off also removes everyone who got in through it.
Browser.handler('presento', 'linkSet', function(src, data)
    local d, err = ownerDeck(src, data.id)
    if not d then return nil, err end
    if data.on then
        if not MySQL.scalar.await('SELECT 1 FROM presento_links WHERE deck_id = ?', { d.id }) then
            local tok
            for _ = 1, 10 do
                local out = {}
                for i = 1, 14 do local n = math.random(1, #ID_CHARS); out[i] = ID_CHARS:sub(n, n) end
                tok = table.concat(out)
                if not MySQL.scalar.await('SELECT 1 FROM presento_links WHERE token = ?', { tok }) then break end
            end
            MySQL.insert.await('INSERT INTO presento_links (deck_id, token, created_at) VALUES (?, ?, ?)', { d.id, tok, now() })
        end
    else
        MySQL.update.await('DELETE FROM presento_links WHERE deck_id = ?', { d.id })
        MySQL.update.await("DELETE FROM presento_shares WHERE deck_id = ? AND via = 'link'", { d.id })
    end
    return shareState(d)
end)

--- data = { token } -> { id }. Opening a view link puts the deck in "Shared with me" as view only.
Browser.handler('presento', 'linkOpen', function(src, data)
    local cid, name = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local tok = data.token
    if type(tok) ~= 'string' or #tok > 24 or not tok:match('^%w+$') then return nil, T('presento.err.linkOff') end
    local deckId = MySQL.scalar.await('SELECT deck_id FROM presento_links WHERE token = ?', { tok })
    if not deckId then return nil, T('presento.err.linkOff') end
    local d = access(deckId, cid)
    if not d then
        MySQL.insert.await("INSERT IGNORE INTO presento_shares (deck_id, citizenid, name, role, via, created_at) VALUES (?, ?, ?, 'viewer', 'link', ?)",
            { deckId, cid, str(name, 80), now() })
    end
    return { id = deckId }
end)

-- ---------------------------------------------------------------------------------------------
-- Edit lock
-- ---------------------------------------------------------------------------------------------

--- data = { id } -> { ok = true } or { ok = false, by = name }. Called on open and every lockBeat seconds.
Browser.handler('presento', 'lock', function(src, data)
    local d, err = editableDeck(src, data.id)
    if not d then return nil, err end
    local cid, name = me(src)
    local fresh = lockFresh(d)
    if fresh and d.lock_cid ~= cid then return { ok = false, by = d.lock_name or '?' } end
    if not fresh or d.lock_cid ~= cid then
        snapshot(d.id, d.lock_name or name)            -- a new editing session: keep what was there before it
    else
        local last = tonumber(MySQL.scalar.await('SELECT MAX(created_at) FROM presento_versions WHERE deck_id = ?', { d.id })) or 0
        if now() - last >= (P.versionEvery or 600) then snapshot(d.id, name) end
    end
    takeLock(src, d, cid, name)
    return { ok = true }
end)

--- data = { id } - leaving the editor.
Browser.handler('presento', 'unlock', function(src, data)
    local cid = me(src)
    if not cid or not validId(data.id) then return true end
    local holder = MySQL.scalar.await('SELECT lock_cid FROM presento_decks WHERE id = ?', { data.id })
    if holder == cid then releaseLock(src, data.id) end
    return true
end)

-- ---------------------------------------------------------------------------------------------
-- Version history
-- ---------------------------------------------------------------------------------------------

--- data = { id } -> saved versions, newest first.
Browser.handler('presento', 'versions', function(src, data)
    local d, err = editableDeck(src, data.id)
    if not d then return nil, err end
    return {
        versions = MySQL.query.await('SELECT id, saved_by AS `by`, created_at AS `at`, slide_count AS slides FROM presento_versions WHERE deck_id = ? ORDER BY id DESC', { d.id }) or {},
    }
end)

--- data = { id, vid } -> that version's slides, for the preview.
Browser.handler('presento', 'versionGet', function(src, data)
    local d, err = editableDeck(src, data.id)
    if not d then return nil, err end
    local row = MySQL.single.await('SELECT slides, theme FROM presento_versions WHERE id = ? AND deck_id = ?', { tonumber(data.vid) or 0, d.id })
    if not row then return nil, T('presento.err.versionGone') end
    return { slides = decode(row.slides) or {}, theme = row.theme }
end)

--- data = { id, vid } - puts that version back. What was there is kept as a version first, so it can be undone.
Browser.handler('presento', 'versionRestore', function(src, data)
    local d, err = writableDeck(src, data.id)
    if not d then return nil, err end
    local _, name = me(src)
    local row = MySQL.single.await('SELECT slides, theme FROM presento_versions WHERE id = ? AND deck_id = ?', { tonumber(data.vid) or 0, d.id })
    local list = row and decode(row.slides)
    if type(list) ~= 'table' or #list == 0 then return nil, T('presento.err.versionGone') end
    snapshot(d.id, name)
    local trusted = {}
    for _, r in ipairs(MySQL.query.await('SELECT url FROM presento_media WHERE deck_id = ?', { d.id }) or {}) do trusted[r.url] = true end
    local ctx = { trusted = trusted }
    local clean = {}
    for i = 1, math.min(#list, P.maxSlides or 50) do
        local sl = cleanSlide(list[i], ctx)
        if sl then clean[#clean + 1] = json.encode(sl) end
    end
    if #clean == 0 then return nil, T('presento.err.versionGone') end
    MySQL.update.await('DELETE FROM presento_slides WHERE deck_id = ?', { d.id })
    for i, sl in ipairs(clean) do
        MySQL.insert.await('INSERT INTO presento_slides (deck_id, sid, position, data) VALUES (?, ?, ?, ?)', { d.id, newSid(), i, sl })
    end
    MySQL.update.await('UPDATE presento_decks SET theme = ? WHERE id = ?', { row.theme or 'default', d.id })
    refreshDeck(d.id)
    return true
end)

-- ---------------------------------------------------------------------------------------------
-- Import from Google Slides. Works for decks shared as "Anyone with the link can view": the server reads
-- the deck's page ids from Google's public embed page, checks each slide's PNG export exists, and makes a
-- new deck with one full-size picture per slide (the picture is Google's export link, so it stays
-- sharp and needs no upload). Runs in the background; the page polls importStatus.
-- ---------------------------------------------------------------------------------------------

local imports = {}   -- cid -> { state = 'working'|'done'|'error', checked, found, id, err, at }

local function httpGet(url)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body, headers)
        p:resolve({ status = tonumber(status) or 0, body = type(body) == 'string' and body or '', headers = type(headers) == 'table' and headers or {} })
    end, 'GET', '', { ['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36' })
    return Citizen.Await(p)
end

local function header(h, name)
    for k, v in pairs(h) do if tostring(k):lower() == name then return tostring(v) end end
    return ''
end

local function googleDeckId(url)
    if type(url) ~= 'string' or #url > 500 then return nil end
    return url:match('docs%.google%.com/presentation/d/([%w_%-]+)')
end

local function exportUrl(gid, pid)
    return ('https://docs.google.com/presentation/d/%s/export/png?pageid=%s'):format(gid, pid)
end

-- Shapes Google uses for slide ids: p, p1, g1a2b3c4d5_0_12, SLIDES_API12345_0 ...
local PAGE_SHAPES = { '^p%d*$', '^g%x+_%d+_%d+$', '^g%x+_%d+$', '^SLIDES_API%d+_%d+$', '^[%a][%w]*_%d+_%d+$' }

local function collectIds(body, out, seen)
    local function add(c)
        if seen[c] or #c > 64 then return end
        for _, pat in ipairs(PAGE_SHAPES) do
            if c:match(pat) then seen[c] = true; out[#out + 1] = c; return end
        end
    end
    -- The viewer's data lists the slides in order as quoted ids; "#slide=id.x" links (the slide the owner
    -- last looked at) come after so they can't jump the queue.
    for c in body:gmatch('"([%w_]+)"') do add(c) end
    for c in body:gmatch('id%.([%w_]+)') do add(c) end
end

local function slideExists(gid, pid)
    local r = httpGet(exportUrl(gid, pid))
    if r.status == 200 then return true end
    if r.status >= 300 and r.status < 400 then
        return header(r.headers, 'location'):find('googleusercontent', 1, true) ~= nil
    end
    return false
end

local function importLog(fmt, ...) if P.importDebug then print(('^5[presento import]^0 ' .. fmt):format(...)) end end

-- ---------------------------------------------------------------------------------------------
-- Editable import. Google's per-slide SVG export holds the real text and picture links. The server:
--   * keeps a "background" copy of each slide with the text and linked pictures removed (shapes, lines,
--     gradients, charts, pasted-in pictures stay) and serves it from this server's own web address;
--   * hands the page a slimmed copy (no drawing paths) in chunks, so the page can lay the SVG out in a hidden
--     element and read exact positions, fonts and colours of every text line and picture.
-- The page then builds normal Presento slides (background picture + text boxes + images) and saves them.
-- ---------------------------------------------------------------------------------------------

local ASSET_ROUTE = '/presento/a/'

local function assetBase()
    if P.assetBaseUrl and P.assetBaseUrl ~= '' then return (P.assetBaseUrl:gsub('/+$', '')) end
    local base = GetConvar('web_baseUrl', '')
    if base == '' then return nil end
    if not base:match('^https?://') then base = 'https://' .. base end
    return base:gsub('/+$', '') .. '/' .. GetCurrentResourceName()
end

local function assetUrl(id)
    local base = assetBase()
    return base and (base .. ASSET_ROUTE .. id .. '.svg') or nil
end

local function newAssetId()
    local out = {}
    for i = 1, 20 do local n = math.random(1, #ID_CHARS); out[i] = ID_CHARS:sub(n, n) end
    return table.concat(out)
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS presento_assets (
            id         VARCHAR(24) NOT NULL PRIMARY KEY,
            deck_id    VARCHAR(16) NULL,
            mime       VARCHAR(40) NOT NULL DEFAULT 'image/svg+xml',
            body       MEDIUMTEXT NOT NULL,
            created_at INT NOT NULL,
            KEY idx_deck (deck_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- imports that were never finished
    MySQL.update.await('DELETE FROM presento_assets WHERE deck_id IS NULL AND created_at < ?', { os.time() - 86400 })
end)

-- The background images, for the players' game (and the TV page) to load. Only ids, nothing else.
Browser.httpRoute(ASSET_ROUTE, function(req, res, rest)
    local id = rest:match('^(%w+)%.svg$')
    if not id or #id > 24 then res.writeHead(404); return res.send('') end
    local row = MySQL.single.await('SELECT mime, body FROM presento_assets WHERE id = ?', { id })
    if not row then res.writeHead(404); return res.send('') end
    res.writeHead(200, { ['Content-Type'] = row.mime, ['Cache-Control'] = 'public, max-age=604800', ['Access-Control-Allow-Origin'] = '*' })
    res.send(row.body)
end)

local function isRemote(tag)
    local href = tag:match('href="([^"]*)"') or tag:match("href='([^']*)'") or ''
    return href:match('^https?://') ~= nil
end

--- The slide without its text and linked pictures (and anything that could run in a browser).
local function backgroundSvg(svg)
    svg = svg:gsub('<script.-</script>', ''):gsub('<foreignObject.-</foreignObject>', '')
    svg = svg:gsub('%son%a+%s*=%s*"[^"]*"', '')
    svg = svg:gsub('<text[%s>].-</text>', '')
    svg = svg:gsub('<image[^>]-/>', function(tag) return isRemote(tag) and '' or tag end)
    svg = svg:gsub('(<image[^>]*>)(.-</image>)', function(open, rest) return isRemote(open) and '' or open .. rest end)
    return svg
end

--- The slide for the page to read: drawing paths dropped (except clip shapes, which crop pictures), pasted-in
--- pictures dropped (they stay in the background).
local function readerSvg(svg)
    local function clean(chunk)
        chunk = chunk:gsub('<path[^>]-/>', ''):gsub('<path[^>]*>.-</path>', '')
        chunk = chunk:gsub('<image[^>]-/>', function(tag) return isRemote(tag) and tag or '' end)
        return (chunk:gsub('<script.-</script>', ''))
    end
    local out, pos = {}, 1
    while true do
        local a, b = svg:find('<clipPath.-</clipPath>', pos)
        if not a then out[#out + 1] = clean(svg:sub(pos)) break end
        out[#out + 1] = clean(svg:sub(pos, a - 1))
        out[#out + 1] = svg:sub(a, b)
        pos = b + 1
    end
    return table.concat(out)
end

local function prepareEditable(gid, pages, title, job)
    job.title, job.gid, job.slides, job.links, job.assets = title, gid, {}, {}, {}
    local base = assetBase()
    for i, pid in ipairs(pages) do
        job.checked = i
        local r = httpGet(('https://docs.google.com/presentation/d/%s/export/svg?pageid=%s'):format(gid, pid))
        importLog('svg %s -> %d (%d bytes)', pid, r.status, #r.body)
        local slide = { png = exportUrl(gid, pid) }
        if r.status == 200 and r.body:find('<svg', 1, true) then
            local svg = r.body
            if base then
                local id = newAssetId()
                MySQL.insert.await('INSERT INTO presento_assets (id, mime, body, created_at) VALUES (?, ?, ?, ?)', { id, 'image/svg+xml', backgroundSvg(svg), now() })
                slide.bg = assetUrl(id)
                job.assets[#job.assets + 1] = id
            end
            slide.svg = readerSvg(svg)
            for href in svg:gmatch('href="(https://[^"]+)"') do
                if #href <= 500 then job.links[href:gsub('&amp;', '&')] = true end
            end
        end
        job.slides[i] = slide
        job.found = i
    end
    job.state = 'ready'
end

local IMPORT_CHUNK = 12000

--- data = { slide, part } -> { parts, text, bg, png } : one piece of a slide's SVG for the page to read.
Browser.handler('presento', 'importPart', function(src, data)
    local cid = me(src)
    local job = cid and imports[cid]
    if not job or job.state ~= 'ready' then return nil, T('presento.err.importNone') end
    local s = job.slides[tonumber(data.slide) or 0]
    if not s then return nil, T('shell.err.badRequest') end
    local svg = s.svg or ''
    local parts = math.max(1, math.ceil(#svg / IMPORT_CHUNK))
    local part = math.max(1, math.min(parts, math.floor(tonumber(data.part) or 1)))
    return { parts = parts, text = svg:sub((part - 1) * IMPORT_CHUNK + 1, part * IMPORT_CHUNK), bg = s.bg, png = s.png }
end)

--- data = { folder } -> { id }: an empty deck the page then fills with saveSlide / order. The imported links
--- (backgrounds and Google picture links) are remembered for it so those slides save.
Browser.handler('presento', 'importCreate', function(src, data)
    local cid, name = me(src)
    local job = cid and imports[cid]
    if not job or job.state ~= 'ready' then return nil, T('presento.err.importNone') end
    if job.deck then return { id = job.deck } end
    local folder = ownFolder(cid, data.folder)
    if folder == false then folder = nil end
    local id = newDeckId()
    if not id then return nil, T('shell.err.generic') end
    local t = now()
    MySQL.insert.await(
        'INSERT INTO presento_decks (id, citizenid, owner_name, title, folder_id, theme, slide_count, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)',
        { id, cid, str(name, 80), job.title or T('presento.untitled'), folder, 'default', t, t })
    local urls = {}
    for _, s in ipairs(job.slides) do
        if s.bg then urls[#urls + 1] = s.bg end
        if s.png then urls[#urls + 1] = s.png end
    end
    for href in pairs(job.links) do urls[#urls + 1] = href end
    for _, u in ipairs(urls) do
        MySQL.insert.await('INSERT INTO presento_media (deck_id, url, created_at) VALUES (?, ?, ?)', { id, u, t })
    end
    for _, a in ipairs(job.assets) do
        MySQL.update.await('UPDATE presento_assets SET deck_id = ? WHERE id = ?', { id, a })
    end
    job.deck = id
    return { id = id }
end)

--- The page finished filling the deck (or gave up): forget the import.
Browser.handler('presento', 'importDone', function(src)
    local cid = me(src)
    if cid then imports[cid] = nil end
    return true
end)

local function runImport(src, cid, name, gid, folder, job)
    -- 1. the public pages that list the slides (first one that works wins, the rest add missing ids)
    local ids, seen, title, public = {}, {}, nil, false
    for _, path in ipairs({ '/embed?start=false&loop=false', '/htmlpresent', '/preview' }) do
        local r = httpGet('https://docs.google.com/presentation/d/' .. gid .. path)
        importLog('%s -> %d (%d bytes)', path, r.status, #r.body)
        if r.status == 200 and not r.body:find('ServiceLogin', 1, true) then
            public = true
            title = title or r.body:match('<title>(.-)</title>')
            collectIds(r.body, ids, seen)
        end
        if #ids > 0 and path ~= '/embed?start=false&loop=false' then break end
    end
    if not public then job.state, job.err = 'error', T('presento.err.importPrivate'); return end
    importLog('%d candidate ids', #ids)

    -- 2. keep the ids that really are slides, in page order
    local max = P.maxSlides or 50
    local pages = {}
    for i = 1, math.min(#ids, max * 4) do
        job.checked = i
        if slideExists(gid, ids[i]) then
            pages[#pages + 1] = ids[i]
            job.found = #pages
            if #pages >= max then break end
        end
    end
    importLog('%d slides found', #pages)
    if #pages == 0 then job.state, job.err = 'error', T('presento.err.importNone'); return end

    -- 3. the deck
    title = str((title or ''):gsub('%s*%-%s*Google [%w%s]+$', ''):gsub('&amp;', '&'):gsub('&#39;', "'"):gsub('&quot;', '"'), P.maxTitleLength or 100)
    if title == '' then title = T('presento.untitled') end
    if job.mode == 'editable' then return prepareEditable(gid, pages, title, job) end
    local id = newDeckId()
    if not id then job.state, job.err = 'error', T('shell.err.generic'); return end
    local t = now()
    local slides = {}
    for i, pid in ipairs(pages) do
        slides[i] = json.encode({ bg = '#000000', els = { { id = 'e1', type = 'image', src = exportUrl(gid, pid), fit = 'contain', x = 0, y = 0, w = 1280, h = 720, rot = 0 } } })
    end
    MySQL.insert.await(
        'INSERT INTO presento_decks (id, citizenid, owner_name, title, folder_id, theme, slide_count, thumb, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { id, cid, str(name, 80), title, folder, 'dark', #slides, thumbFor(slides[1]), t, t })
    for i, sl in ipairs(slides) do
        MySQL.insert.await('INSERT INTO presento_slides (deck_id, sid, position, data) VALUES (?, ?, ?, ?)', { id, newSid(), i, sl })
        MySQL.insert.await('INSERT INTO presento_media (deck_id, url, created_at) VALUES (?, ?, ?)', { id, exportUrl(gid, pages[i]), t })
    end
    job.state, job.id = 'done', id
end

--- data = { url, folder } -> starts an import in the background. Poll importStatus.
Browser.handler('presento', 'importGoogle', function(src, data)
    local cid, name = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    if P.importGoogle == false then return nil, T('presento.err.importOff') end
    local gid = googleDeckId(data.url)
    if not gid then return nil, T('presento.err.importLink') end
    local ok, err = canMakeDeck(cid)
    if not ok then return nil, err end
    local folder = ownFolder(cid, data.folder)
    if folder == false then return nil, T('presento.err.folderNotFound') end
    local cur = imports[cid]
    if cur and (cur.state == 'working' or cur.state == 'ready') and os.time() - cur.at < 300 then return nil, T('presento.err.importBusy') end
    local job = { state = 'working', checked = 0, found = 0, at = os.time(), mode = data.mode == 'editable' and 'editable' or 'pictures' }
    imports[cid] = job
    CreateThread(function()
        local fine, e = pcall(runImport, src, cid, name, gid, folder, job)
        if not fine then
            print(('^1[presento import] failed: %s^0'):format(tostring(e)))
            job.state, job.err = 'error', T('shell.err.generic')
        end
    end)
    return { started = true }
end)

Browser.handler('presento', 'importStatus', function(src)
    local cid = me(src)
    local job = cid and imports[cid]
    if not job then return { state = 'none' } end
    local out = { state = job.state, checked = job.checked, found = job.found, id = job.id, err = job.err, mode = job.mode }
    if job.state == 'ready' then
        out.slides = #job.slides
        out.hasBg = job.assets and #job.assets > 0 or false
    elseif job.state ~= 'working' then
        imports[cid] = nil
    end
    return out
end)

-- ---------------------------------------------------------------------------------------------
-- Casting to TVs. The TVs, who may use them and what they show live in as-computer (server/placement.lua);
-- this side only checks the player may see the deck and hands over its slides.
-- ---------------------------------------------------------------------------------------------

local function castRes()
    local r = P.castResource or 'as-computer'
    if P.cast == false or GetResourceState(r) ~= 'started' then return nil end
    return r
end

local function castCall(fn, ...)
    local r = castRes()
    if not r then return nil, T('presento.err.castOff') end
    local args = { ... }
    local ok, res, err = pcall(function() return exports[r][fn](exports[r], table.unpack(args)) end)
    if not ok then return nil, T('presento.err.castOff') end
    if res == nil or res == false then return nil, err or T('shell.err.generic') end
    return res
end

--- -> { tvs = { { id, label, dist, busy, mine } } } within reach of the player that their job may use.
Browser.handler('presento', 'castTargets', function(src)
    local list, err = castCall('tvNearby', src)
    if not list then return nil, err end
    return { tvs = list }
end)

--- data = { id = deck, tv, slide, step } - show a deck on a TV. Anyone who can open the deck may cast it.
Browser.handler('presento', 'castStart', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local d = access(data.id, cid)
    if not d then return nil, T('presento.err.notFound') end
    local rows = MySQL.query.await('SELECT data FROM presento_slides WHERE deck_id = ? ORDER BY position', { d.id }) or {}
    local slides = {}
    for i, r in ipairs(rows) do slides[i] = decode(r.data) or { bg = '#000000', els = {} } end
    if #slides == 0 then return nil, T('presento.err.notFound') end
    return castCall('tvCast', src, tonumber(data.tv), { id = d.id, title = d.title }, slides, tonumber(data.slide) or 1, tonumber(data.step) or 0)
end)

--- data = { tv, slide, step } - the presenter moved on.
Browser.handler('presento', 'castGo', function(src, data)
    return castCall('tvGo', src, tonumber(data.tv), tonumber(data.slide) or 1, tonumber(data.step) or 0)
end)

--- data = { tv }
Browser.handler('presento', 'castStop', function(src, data)
    return castCall('tvStop', src, tonumber(data.tv))
end)

-- ---------------------------------------------------------------------------------------------
-- Folders (one level, personal)
-- ---------------------------------------------------------------------------------------------

Browser.handler('presento', 'folderCreate', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local name = str(data.name, P.maxFolderName or 40)
    if name == '' then return nil, T('presento.err.needName') end
    local max = P.maxFolders or 50
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM presento_folders WHERE citizenid = ?', { cid }) or 0
    if max > 0 and count >= max then return nil, T('presento.err.tooManyFolders', max) end
    local id = MySQL.insert.await('INSERT INTO presento_folders (citizenid, name, created_at) VALUES (?, ?, ?)', { cid, name, now() })
    return { id = id, name = name }
end)

Browser.handler('presento', 'folderRename', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local folder = ownFolder(cid, data.id)
    if not folder then return nil, T('presento.err.folderNotFound') end
    local name = str(data.name, P.maxFolderName or 40)
    if name == '' then return nil, T('presento.err.needName') end
    MySQL.update.await('UPDATE presento_folders SET name = ? WHERE id = ?', { name, folder })
    return { name = name }
end)

Browser.handler('presento', 'folderDelete', function(src, data)
    local cid = me(src)
    if not cid then return nil, T('presento.err.noCharacter') end
    local folder = ownFolder(cid, data.id)
    if not folder then return nil, T('presento.err.folderNotFound') end
    MySQL.update.await('UPDATE presento_decks SET folder_id = NULL WHERE folder_id = ? AND citizenid = ?', { folder, cid })
    MySQL.update.await('DELETE FROM presento_folders WHERE id = ?', { folder })
    return true
end)

