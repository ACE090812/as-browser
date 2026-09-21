-- LS Weather: what the weather is now and a short outlook. See sites/weather/config.lua.
local W = Config.weather or {}

Browser.defineSite('weather', {
    title       = W.name or 'LS Weather',
    description = T('weather.description'),
    keywords    = Browser.words(T('weather.keywords')),
    category    = T('weather.category'),
    icon        = '🌦️',
    color       = '#0284c7',
    pages       = {
        { path = '/', title = W.name or 'LS Weather', description = T('weather.description'), keywords = Browser.words(T('weather.keywords')) },
    },
})

local function types() return W.types or {} end
local function step() return math.max(1, math.floor(tonumber(W.stepMinutes) or 60)) * 60 end

--- Cheap deterministic hash -> 0..1, so every player (and every server tick) sees the same simulated weather.
local function rnd(a, b, c)
    a, b, c = math.floor(a or 0), math.floor(b or 0), math.floor(c or 0)
    local h = ((a or 0) * 374761393 + (b or 0) * 668265263 + (c or 0) * 2147483647 + (tonumber(W.seed) or 0) * 1274126177) % 4294967296
    h = ((h ~ (h >> 13)) * 1274126177) % 4294967296
    h = (h ~ (h >> 16)) % 4294967296
    return h / 4294967296
end

local function pickType(slot)
    -- weather holds for 2 to 4 slots at a time, so it does not flicker between every hour
    local block = math.floor(slot / 3)
    local list, total = {}, 0
    for name, t in pairs(types()) do
        local w = tonumber(t.weight) or 0
        if w > 0 then list[#list + 1] = { name = name, w = w }; total = total + w end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    if total == 0 then return 'CLEAR' end
    local r, acc = rnd(block, 7, 1) * total, 0
    for _, e in ipairs(list) do
        acc = acc + e.w
        if r <= acc then return e.name end
    end
    return list[#list].name
end

local function normalise(v)
    if type(v) == 'table' then v = v.weather or v.type or v.name or v.current end
    if type(v) ~= 'string' then return nil end
    v = v:upper():gsub('%s+', '')
    return types()[v] and v or nil
end

--- The weather right now and whether it came from a weather script (true) or was worked out here (false).
local function currentType()
    local src = W.source or 'auto'
    if src == 'function' and type(W.current) == 'function' then
        local ok, v = pcall(W.current)
        local n = ok and normalise(v) or nil
        if n then return n, true end
    elseif src == 'auto' or src == 'globalstate' then
        for _, key in ipairs(W.globalStateKeys or { 'weather' }) do
            local ok, v = pcall(function() return GlobalState[key] end)
            local n = ok and normalise(v) or nil
            if n then return n, true end
        end
    end
    return pickType(math.floor(os.time() / step())), false
end

local function lerp(a, b, t) return a + (b - a) * t end
local function inRange(r, t) r = r or { 0, 0 }; return lerp(r[1] or 0, r[2] or r[1] or 0, t) end

local function conditions(typeName, at, region, slot, isNow)
    local t = types()[typeName] or types().CLEAR or {}
    local hour = tonumber(os.date('%H', at)) + tonumber(os.date('%M', at)) / 60
    local day = (math.sin((hour - 9) / 24 * 2 * math.pi) + 1) / 2                      -- warmest mid-afternoon, coolest before dawn
    local temp = inRange(t.temp, day * 0.85 + rnd(slot, 3, 1) * 0.15) + (tonumber(region.tempOffset) or 0)
    if (W.units or 'C') == 'F' then temp = temp * 9 / 5 + 32 end
    local wind = inRange(t.wind, rnd(slot, 5, 2)) + (tonumber(region.wind) or 0)
    if (W.windUnit or 'mph') == 'kmh' then wind = wind * 1.609 end
    return {
        at = at, now = isNow or nil, type = typeName, label = t.label or typeName, icon = t.icon or '🌡️',
        temp = math.floor(temp + 0.5), wind = math.max(0, math.floor(wind + 0.5)),
        humidity = math.floor(inRange(t.humidity, rnd(slot, 9, 3)) + 0.5),
        severe = t.severe == true or nil, advice = t.advice,
    }
end

local function regionById(id)
    local first
    for _, r in ipairs(W.regions or {}) do
        first = first or r
        if r.id == id then return r end
    end
    return first or { id = 'ls', label = 'Los Santos', tempOffset = 0, wind = 0 }
end

Browser.handler('weather', 'forecast', function(src, data)
    local region = regionById(tostring(data and data.region or ''))
    local now = os.time()
    local slot0 = math.floor(now / step())
    local typeNow, live = currentType()
    local cur = conditions(typeNow, now, region, slot0 * 7 + (tonumber(region.tempOffset) or 0) * 3, true)

    local outlook = {}
    if W.showForecast ~= false then
        for i = 1, math.min(24, math.max(0, math.floor(tonumber(W.forecastSteps) or 8))) do
            local slot = slot0 + i
            outlook[#outlook + 1] = conditions(pickType(slot), slot * step(), region, slot * 7 + (tonumber(region.tempOffset) or 0) * 3)
        end
    end

    local regions = {}
    for _, r in ipairs(W.regions or {}) do regions[#regions + 1] = { id = r.id, label = r.label } end
    local alert
    if cur.severe then alert = cur.advice end
    for _, o in ipairs(outlook) do
        if o.severe and not alert then alert = T('weather.alertLater', o.label) break end
    end

    return {
        name = W.name, tagline = W.tagline, footer = W.footer or {},
        units = W.units or 'C', windUnit = W.windUnit or 'mph',
        region = region.id, regions = regions, live = live,
        now = cur, outlook = outlook, alert = alert, showForecast = W.showForecast ~= false,
    }
end)
