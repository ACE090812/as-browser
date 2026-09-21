-- Server Wiki: read-only pages from sites/wiki/config.lua, with search. The page text is rendered by the page (escaped first),
-- so nothing written in a page can run code.
local WK = Config.wiki or {}

Browser.defineSite('wiki', {
    title       = WK.name or 'Server Wiki',
    description = T('wiki.description'),
    keywords    = Browser.words(T('wiki.keywords')),
    category    = T('wiki.category'),
    icon        = '📖',
    color       = '#7c3aed',
    pages       = (function()
        local out = { { path = '/', title = WK.name or 'Server Wiki', description = T('wiki.description'), keywords = Browser.words(T('wiki.keywords')) } }
        for _, p in ipairs(WK.pages or {}) do
            out[#out + 1] = { path = '/p/' .. p.id, title = p.title, description = p.summary or '', keywords = Browser.words((p.title or ''):lower():gsub('%s+', ',')) }
        end
        return out
    end)(),
})

local byId, order = {}, {}
for _, p in ipairs(WK.pages or {}) do
    if type(p.id) == 'string' and p.id:match('^[%w_%-]+$') and #p.id <= 48 and not byId[p.id] then
        byId[p.id] = p
        order[#order + 1] = p
    else
        print(('^5[as-browser:wiki]^0 skipping a page with a bad or repeated id: %s'):format(tostring(p.id)))
    end
end

local function listItem(p)
    return { id = p.id, title = p.title or p.id, category = p.category, summary = p.summary or '', updated = p.updated }
end

local function byUpdated(a, b)
    if (a.updated or '') ~= (b.updated or '') then return (a.updated or '') > (b.updated or '') end
    return (a.title or '') < (b.title or '')
end

local function categories()
    local out, counts = {}, {}
    for _, p in ipairs(order) do counts[p.category or ''] = (counts[p.category or ''] or 0) + 1 end
    for _, c in ipairs(WK.categories or {}) do
        out[#out + 1] = { id = c.id, label = c.label, icon = c.icon or '📄', count = counts[c.id] or 0 }
    end
    return out
end

Browser.handler('wiki', 'index', function(src)
    local featured, recent = {}, {}
    for _, id in ipairs(WK.featured or {}) do if byId[id] then featured[#featured + 1] = listItem(byId[id]) end end
    local sorted = {}
    for _, p in ipairs(order) do sorted[#sorted + 1] = p end
    table.sort(sorted, byUpdated)
    for i = 1, math.min(#sorted, math.max(0, math.floor(tonumber(WK.recentCount) or 5))) do recent[#recent + 1] = listItem(sorted[i]) end
    local all = {}
    for _, p in ipairs(sorted) do all[#all + 1] = listItem(p) end
    return { name = WK.name, tagline = WK.tagline, intro = WK.intro or '', footer = WK.footer or {},
             categories = categories(), featured = featured, recent = recent, pages = all }
end)

Browser.handler('wiki', 'page', function(src, data)
    local id = tostring(data and data.id or '')
    local p = byId[id]
    if not p then return nil, T('wiki.err.notFound') end
    local related = {}
    for _, o in ipairs(order) do
        if o.id ~= p.id and o.category == p.category and #related < 5 then related[#related + 1] = listItem(o) end
    end
    return { page = { id = p.id, title = p.title, category = p.category, summary = p.summary or '', updated = p.updated, body = p.body or '' }, related = related, categories = categories() }
end)

local function snippet(body, word)
    local flat = body:gsub('[%c]+', ' ')
    local at = flat:lower():find(word, 1, true)
    if not at then return flat:sub(1, 140) end
    local from = math.max(1, at - 50)
    return (from > 1 and '…' or '') .. flat:sub(from, at + 90) .. (at + 90 < #flat and '…' or '')
end

Browser.handler('wiki', 'search', function(src, data)
    local q = tostring(data and data.q or ''):lower():sub(1, 60)
    local words = {}
    for w in q:gmatch('%S+') do if #words < 6 then words[#words + 1] = w end end
    if #words == 0 then return { results = {} } end
    local results = {}
    for _, p in ipairs(order) do
        local title, summary, body = (p.title or ''):lower(), (p.summary or ''):lower(), (p.body or ''):lower()
        local score, ok = 0, true
        for _, w in ipairs(words) do
            local s = 0
            if title:find(w, 1, true) then s = s + 6 end
            if summary:find(w, 1, true) then s = s + 3 end
            if body:find(w, 1, true) then s = s + 1 end
            if s == 0 then ok = false break end
            score = score + s
        end
        if ok then
            local item = listItem(p)
            item.snippet = snippet(p.body or '', words[1])
            item.score = score
            results[#results + 1] = item
        end
    end
    table.sort(results, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.title < b.title end)
    while #results > 20 do table.remove(results) end
    return { results = results }
end)
