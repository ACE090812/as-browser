-- Findr: search for sites (and, once those sites exist, news, marketplace adverts and images). Other sites and resources add results
-- with Browser.findrProvider(tab, fn) or exports['as-browser']:registerSearchProvider(tab, fn):
--     fn(query, limit, source) -> { { title = '...', url = 'lsmarket.co.uk/ad/12', desc = '...', image = 'https://...' (images tab), tag = 'Vehicles' } ... }
-- tab is 'news', 'market' or 'images'.
local FD = Config.findr or {}

Browser.findr = { providers = { news = {}, market = {}, images = {} } }

Browser.defineSite('findr', {
    title       = FD.name or 'Findr',
    description = T('findr.description'),
    keywords    = Browser.words(T('findr.keywords')),
    category    = T('findr.category'),
    icon        = '🔎',
    color       = '#4f46e5',
    engine      = true,
    featured    = true,
})

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_findr_log (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        q VARCHAR(60) NOT NULL,
        at INT NOT NULL,
        KEY idx_findr_cid (citizenid, id),
        KEY idx_findr_q (at, q)
    )]])
end)

function Browser.findrProvider(tab, fn, resource)
    if not Browser.findr.providers[tab] or type(fn) ~= 'function' and type(fn) ~= 'table' then return false end
    Browser.findr.providers[tab][#Browser.findr.providers[tab] + 1] = { fn = fn, resource = resource or GetCurrentResourceName() }
    return true
end
exports('registerSearchProvider', function(tab, fn) return Browser.findrProvider(tab, fn, GetInvokingResource()) end)
AddEventHandler('onResourceStop', function(res)
    for _, list in pairs(Browser.findr.providers) do
        for i = #list, 1, -1 do if list[i].resource == res then table.remove(list, i) end end
    end
end)

local function cleanQuery(q)
    q = tostring(q or ''):gsub('%c', ' '):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    return q:sub(1, 60)
end

local function blocked(q)
    local low = q:lower()
    for _, w in ipairs(FD.blocked or {}) do if low:find(tostring(w):lower(), 1, true) then return true end end
    return false
end

-- ---- scoring: every word must match somewhere; the best field weight counts for each word
local function score(terms, fields)
    local total = 0
    for _, term in ipairs(terms) do
        local best = 0
        for _, f in ipairs(fields) do
            if tostring(f[1] or ''):lower():find(term, 1, true) and f[2] > best then best = f[2] end
        end
        if best == 0 then return 0 end
        total = total + best
    end
    return total
end

local function terms(q)
    local out = {}
    for w in q:lower():gmatch('%S+') do out[#out + 1] = w end
    return out
end

local function siteResults(q, desktop, limit)
    local t = terms(q)
    if #t == 0 then return {} end
    local out = {}
    for _, s in ipairs(Browser.publicSites(desktop)) do
        do
            local sc = score(t, { { s.title, 5 }, { s.domain, 4 }, { table.concat(s.keywords or {}, ' '), 3 }, { s.description, 1 }, { s.category, 1 } })
            if sc > 0 then out[#out + 1] = { title = s.title, url = s.domain, desc = s.description, icon = s.icon, color = s.color, score = sc + 2, kind = 'site' } end
            for _, pg in ipairs(s.pages or {}) do
                local ps = score(t, { { pg.title, 5 }, { table.concat(pg.keywords or {}, ' '), 3 }, { pg.description, 1 } })
                if ps > 0 then out[#out + 1] = { title = pg.title, url = s.domain .. (pg.path or ''), desc = pg.description or s.title, icon = s.icon, color = s.color, score = ps, kind = 'page', site = s.title } end
            end
        end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.title < b.title end)
    while #out > limit do out[#out] = nil end
    return out
end

local function providerResults(tab, q, limit, src)
    local out = {}
    for _, p in ipairs(Browser.findr.providers[tab] or {}) do
        local ok, res = pcall(p.fn, q, limit, src)
        if ok and type(res) == 'table' then
            for _, r in ipairs(res) do
                if type(r) == 'table' and r.title and r.url then
                    out[#out + 1] = { title = tostring(r.title):sub(1, 120), url = tostring(r.url):sub(1, 200), desc = tostring(r.desc or ''):sub(1, 240),
                        image = r.image and tostring(r.image):sub(1, 300) or nil, tag = r.tag and tostring(r.tag):sub(1, 30) or nil }
                end
                if #out >= limit then break end
            end
        end
    end
    return out
end

-- ---- logging and lists
local function logSearch(cid, q)
    if not cid or #q < 2 or blocked(q) then return end
    MySQL.insert('INSERT INTO browser_findr_log (citizenid, q, at) VALUES (?, ?, ?)', { cid, q, os.time() })
end

local function recent(cid, limit)
    if not cid then return {} end
    local rows = MySQL.query.await('SELECT q, MAX(id) AS last FROM browser_findr_log WHERE citizenid = ? GROUP BY q ORDER BY last DESC LIMIT ?', { cid, limit }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.q end
    return out
end

local function trending(limit)
    local since = os.time() - (FD.trendingDays or 7) * 86400
    local rows = MySQL.query.await('SELECT LOWER(q) AS q, COUNT(*) AS n FROM browser_findr_log WHERE at >= ? GROUP BY LOWER(q) ORDER BY n DESC, q ASC LIMIT ?', { since, limit }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.q end
    return out
end

CreateThread(function()
    while true do
        Wait(60 * 60 * 1000)
        MySQL.update('DELETE FROM browser_findr_log WHERE at < ?', { os.time() - (FD.keepLogDays or 14) * 86400 })
    end
end)

Browser.handler('findr', 'home', function(src)
    local cid = Bridge.getIdentifier(src)
    return { name = FD.name or 'Findr', recent = recent(cid, FD.recentShown or 8), trending = trending(FD.trendingShown or 8) }
end)

Browser.handler('findr', 'suggest', function(src, data)
    local q = cleanQuery(data.q):lower()
    if #q < 1 then return { items = {} } end
    local out, seen = {}, {}
    local function add(text, kind)
        local k = text:lower()
        if not seen[k] and #out < 8 then seen[k] = true; out[#out + 1] = { q = text, kind = kind } end
    end
    local cid = Bridge.getIdentifier(src)
    for _, r in ipairs(recent(cid, 30)) do if r:lower():sub(1, #q) == q then add(r, 'recent') end end
    for _, r in ipairs(trending(30)) do if r:sub(1, #q) == q then add(r, 'trending') end end
    for _, s in ipairs(Browser.publicSites(Browser.callDesktop)) do
        if s.title:lower():sub(1, #q) == q then add(s.title, 'site') end
        for _, k in ipairs(s.keywords or {}) do if k:lower():sub(1, #q) == q then add(k, 'word') end end
        for _, pg in ipairs(s.pages or {}) do if (pg.title or ''):lower():sub(1, #q) == q then add(pg.title, 'page') end end
    end
    return { items = out }
end)

Browser.handler('findr', 'search', function(src, data)
    local q = cleanQuery(data.q)
    if q == '' then return { q = '', sites = {}, news = {}, market = {}, images = {} } end
    local cid = Bridge.getIdentifier(src)
    logSearch(cid, q)
    local per = FD.maxPerTab or 20
    return {
        q = q,
        sites  = siteResults(q, Browser.callDesktop == true, per),
        news   = providerResults('news', q, per, src),
        market = providerResults('market', q, per, src),
        images = providerResults('images', q, per, src),
    }
end)

Browser.handler('findr', 'clearRecent', function(src)
    local cid = Bridge.getIdentifier(src)
    if cid then MySQL.update('DELETE FROM browser_findr_log WHERE citizenid = ?', { cid }) end
    return true
end)

Browser.handler('findr', 'removeRecent', function(src, data)
    local cid, q = Bridge.getIdentifier(src), cleanQuery(data.q)
    if cid and q ~= '' then MySQL.update('DELETE FROM browser_findr_log WHERE citizenid = ? AND q = ?', { cid, q }) end
    return true
end)
