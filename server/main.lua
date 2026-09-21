-- as-browser server: site registry, request routing, bookmarks, history and the admin command.
-- Each site under sites/<name>/ describes itself with Browser.defineSite() and answers page
-- requests with Browser.handler(). Other resources can add sites with the registerSite export.

Browser = {
    sites    = {},   -- key -> site record
    handlers = {},   -- key -> { requestName -> function(source, data) }
    byDomain = {},   -- domain -> key
    hooks    = {},   -- cross-site hooks, e.g. Browser.hooks.insuranceStatus(plate)
    api      = {},   -- functions behind the public exports (getVehicleStatus, ...)
}

local RESOURCE = GetCurrentResourceName()
local DOMAIN_PATTERN = '^[a-z0-9][a-z0-9%-]*%.[a-z0-9%.%-]*[a-z0-9]$'

local function log(fmt, ...) print(('^5[as-browser]^0 ' .. fmt):format(...)) end

-- ---------------------------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_bookmarks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        url VARCHAR(200) NOT NULL,
        title VARCHAR(100) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_bookmark (citizenid, url)
    )]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_history (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        url VARCHAR(200) NOT NULL,
        title VARCHAR(100) NOT NULL,
        visited_at INT NOT NULL,
        KEY idx_history (citizenid, id)
    )]])
end)

-- ---------------------------------------------------------------------------------------------
-- Site registry
-- ---------------------------------------------------------------------------------------------

local function clean(s, max)
    s = tostring(s or ''):gsub('[%c]', ' ')
    return s:sub(1, max)
end

--- Turns a translated, comma separated keyword list ("rules, staff, team") into a Lua list. Used for
--- the search keywords of the built-in sites, so a translation can add words people would type.
function Browser.words(text)
    local out = {}
    for w in tostring(text or ''):gmatch('[^,]+') do
        local word = w:gsub('^%s+', ''):gsub('%s+$', '')
        if word ~= '' then out[#out + 1] = word end
    end
    return out
end

--- Date text for emails, receipts and errors: "05 Sep 2026" (month names and order come from the locale).
function Browser.date(ts)
    local month = Browser.words(T('shell.months'))[tonumber(os.date('%m', ts))] or os.date('%b', ts)
    return T('shell.dateFmt', os.date('%d', ts), month, os.date('%Y', ts))
end

--- The same with the time: "05 Sep 2026 14:30".
function Browser.datetime(ts)
    return T('shell.dateTimeFmt', Browser.date(ts), os.date('%H:%M', ts))
end

--- Called by each built-in site's server.lua. The on/off switch and address come from
--- Config.Sites[key] in config.lua.
function Browser.defineSite(key, def)
    local cfg = Config.Sites and Config.Sites[key]
    if not cfg then
        log('site "%s" has no entry in Config.Sites, so it is switched off', key)
        return nil
    end
    local domain = tostring(cfg.domain or def.domain or ''):lower()
    if not domain:match(DOMAIN_PATTERN) then
        log('site "%s" has an invalid domain "%s", so it is switched off', key, domain)
        return nil
    end
    local site = {
        key         = key,
        domain      = domain,
        title       = cfg.title or def.title or key,
        description = def.description or '',
        keywords    = def.keywords or {},
        category    = def.category or T('shell.categoryGeneral'),
        icon        = def.icon or '🌐',
        color       = def.color or '#2563eb',
        resource    = RESOURCE,
        page        = def.page or ('sites/' .. key .. '/index.html'),
        pages       = def.pages or {},
        featured    = def.featured ~= false,
        desktopOnly = def.desktopOnly == true,   -- only reachable from a desktop browser (as-computer's Scout), never the phone
        enabled     = cfg.enabled ~= false,
        external    = false,
    }
    Browser.sites[key] = site
    Browser.byDomain[domain] = key
    Browser.handlers[key] = Browser.handlers[key] or {}
    return site
end

--- Registers a request a site page can make with Site.call(name, data).
--- fn(source, data) returns a result, or nil plus an error message to refuse.
function Browser.handler(key, name, fn)
    Browser.handlers[key] = Browser.handlers[key] or {}
    Browser.handlers[key][name] = fn
end

local function publicSite(s)
    return {
        domain = s.domain, title = s.title, description = s.description, keywords = s.keywords,
        category = s.category, icon = s.icon, color = s.color, resource = s.resource,
        page = s.page, pages = s.pages, featured = s.featured,
    }
end

function Browser.publicSites(desktop)
    local out = {}
    for _, s in pairs(Browser.sites) do
        if s.enabled and (desktop or not s.desktopOnly) then out[#out + 1] = publicSite(s) end
    end
    table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
    return out
end

local function siteByDomain(domain)
    domain = tostring(domain or ''):lower():gsub('^www%.', '')
    local key = Browser.byDomain[domain]
    return key and Browser.sites[key] or nil, key
end

--- Splits "lsgov.co.uk/tax-vehicle" into host and path.
local function splitUrl(url)
    if type(url) ~= 'string' or #url > 200 then return nil end
    url = url:gsub('^https?://', ''):gsub('^www%.', '')
    local host, path = url:match('^([^/#?]+)(.*)$')
    if not host then return nil end
    return host:lower(), path
end

--- A URL is valid when it points at an enabled site. Returns it normalised, or nil.
local function validUrl(url)
    local host, path = splitUrl(url)
    if not host then return nil end
    local site = siteByDomain(host)
    if not site or not site.enabled then return nil end
    if #path > 120 or path:find('[%c%s]') then return nil end
    return host .. path, site
end

-- Public helpers other server code can use.
function Browser.isEnabled(key) local s = Browser.sites[key]; return s ~= nil and s.enabled end

function Browser.setEnabled(key, on)
    local s = Browser.sites[key]
    if not s then return false end
    s.enabled = on and true or false
    TriggerClientEvent('as-browser:client:sitesChanged', -1)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Callbacks. Every callback below is also reachable from other server resources through the
-- `handle` export, so a desktop browser (as-computer's Scout) can use the same sites, bookmarks and history.
-- ---------------------------------------------------------------------------------------------

local callbacks = {}
local desktopCallbacks = {}   -- same callbacks, but for a desktop browser: desktop-only sites are visible and reachable
local function registerCb(name, fn)
    callbacks[name] = fn
    lib.callback.register(name, fn)
end

-- ---------------------------------------------------------------------------------------------
-- Requests from site pages
-- ---------------------------------------------------------------------------------------------

local buckets = {}

local function rateAllowed(src, key)
    local cfg = Config.rateLimit or { calls = 20, seconds = 5 }
    local id = src .. ':' .. key
    local now = GetGameTimer()
    local b = buckets[id]
    if not b or now - b.start > cfg.seconds * 1000 then
        b = { start = now, count = 0 }
        buckets[id] = b
    end
    b.count = b.count + 1
    return b.count <= cfg.calls
end

AddEventHandler('playerDropped', function()
    local prefix = tostring(source) .. ':'
    for id in pairs(buckets) do
        if id:sub(1, #prefix) == prefix then buckets[id] = nil end
    end
end)

registerCb('as-browser:sites', function()
    return Browser.publicSites(false)
end)
desktopCallbacks['as-browser:sites'] = function()
    return Browser.publicSites(true)
end

registerCb('as-browser:player', function(src)
    return { name = Bridge.getCharacterName(src) }
end)

local function siteCall(desktop, src, domain, name, data)
    local site, key = siteByDomain(domain)
    if not site or not site.enabled then return { ok = false, error = T('shell.err.siteUnavailable') } end
    if site.desktopOnly and not desktop then return { ok = false, error = T('shell.err.desktopOnly') } end
    if type(name) ~= 'string' or #name > 48 then return { ok = false, error = T('shell.err.badRequest') } end
    local handler = Browser.handlers[key] and Browser.handlers[key][name]
    if not handler then return { ok = false, error = T('shell.err.unknownRequest') } end
    if not rateAllowed(src, key) then return { ok = false, error = T('shell.err.tooManyRequests') } end

    if data ~= nil then
        if type(data) ~= 'table' then return { ok = false, error = T('shell.err.badRequest') } end
        local encoded = json.encode(data)
        if #encoded > (Config.maxPayloadBytes or 16384) then return { ok = false, error = T('shell.err.tooLarge') } end
    end

    local ok, result, err = pcall(handler, src, data or {})
    if not ok then
        log('handler %s/%s failed: %s', key, name, tostring(result))
        return { ok = false, error = T('shell.err.generic') }
    end
    if result == nil and err then return { ok = false, error = tostring(err) } end
    return { ok = true, data = result }
end

registerCb('as-browser:siteCall', function(src, domain, name, data)
    return siteCall(false, src, domain, name, data)
end)
desktopCallbacks['as-browser:siteCall'] = function(src, domain, name, data)
    return siteCall(true, src, domain, name, data)
end

-- ---------------------------------------------------------------------------------------------
-- Bookmarks and history (per character)
-- ---------------------------------------------------------------------------------------------

registerCb('as-browser:bookmarks:list', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return {} end
    return MySQL.query.await('SELECT url, title FROM browser_bookmarks WHERE citizenid = ? ORDER BY id DESC', { cid }) or {}
end)

registerCb('as-browser:bookmarks:add', function(src, url, title)
    local cid = Bridge.getIdentifier(src)
    local norm = validUrl(url)
    if not cid or not norm then return false end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM browser_bookmarks WHERE citizenid = ?', { cid }) or 0
    if count >= (Config.limits.bookmarks or 60) then return false, T('shell.err.tooManyBookmarks') end
    MySQL.insert.await(
        'INSERT INTO browser_bookmarks (citizenid, url, title) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE title = VALUES(title)',
        { cid, norm, clean(title, 100) })
    return true
end)

registerCb('as-browser:bookmarks:remove', function(src, url)
    local cid = Bridge.getIdentifier(src)
    if not cid or type(url) ~= 'string' then return false end
    MySQL.update.await('DELETE FROM browser_bookmarks WHERE citizenid = ? AND url = ?', { cid, url:sub(1, 200) })
    return true
end)

registerCb('as-browser:history:list', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return {} end
    return MySQL.query.await(
        'SELECT url, title, visited_at AS visitedAt FROM browser_history WHERE citizenid = ? ORDER BY id DESC LIMIT ?',
        { cid, Config.limits.history or 100 }) or {}
end)

registerCb('as-browser:history:add', function(src, url, title)
    local cid = Bridge.getIdentifier(src)
    local norm = validUrl(url)
    if not cid or not norm then return false end
    local now = os.time()
    local last = MySQL.single.await('SELECT url, visited_at FROM browser_history WHERE citizenid = ? ORDER BY id DESC LIMIT 1', { cid })
    if last and last.url == norm and now - last.visited_at < 30 then return true end
    MySQL.insert.await('INSERT INTO browser_history (citizenid, url, title, visited_at) VALUES (?, ?, ?, ?)',
        { cid, norm, clean(title, 100), now })
    local keep = Config.limits.history or 100
    MySQL.update.await(
        'DELETE FROM browser_history WHERE citizenid = ? AND id NOT IN (SELECT id FROM (SELECT id FROM browser_history WHERE citizenid = ? ORDER BY id DESC LIMIT ?) t)',
        { cid, cid, keep })
    return true
end)

registerCb('as-browser:history:clear', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return false end
    MySQL.update.await('DELETE FROM browser_history WHERE citizenid = ?', { cid })
    return true
end)

-- ---------------------------------------------------------------------------------------------
-- Admin command: /browsersite <site> on|off
-- ---------------------------------------------------------------------------------------------

local function reply(src, msg)
    if src == 0 then
        log('%s', msg)
    else
        TriggerClientEvent('ox_lib:notify', src, { title = T('shell.cmd.title'), description = msg, type = 'inform' })
    end
end

RegisterCommand('browsersite', function(src, args)
    local key, mode = args[1], args[2]
    if not key then
        local names = {}
        for k, s in pairs(Browser.sites) do names[#names + 1] = ('%s (%s)'):format(k, s.enabled and 'on' or 'off') end
        table.sort(names)
        return reply(src, T('shell.cmd.usage', table.concat(names, ', ')))
    end
    local site = Browser.sites[key]
    if not site then return reply(src, T('shell.cmd.noSite', key)) end
    if mode ~= 'on' and mode ~= 'off' then return reply(src, T('shell.cmd.sayOnOff')) end
    Browser.setEnabled(key, mode == 'on')
    reply(src, T('shell.cmd.now', site.domain, mode))
end, true)

-- ---------------------------------------------------------------------------------------------
-- Exports for other resources
-- ---------------------------------------------------------------------------------------------

--- Lets another resource add its own site. def = { domain, title, description, keywords, category,
--- icon, color, ui = 'my-resource/path/to/index.html', pages = {...} }. The page must be listed in
--- that resource's `files`, and the page should load https://cfx-nui-as-browser/sdk/site.js.
exports('registerSite', function(def)
    local invoking = GetInvokingResource()
    if type(def) ~= 'table' or not invoking then return false, 'Invalid site' end
    local domain = tostring(def.domain or ''):lower()
    if not domain:match(DOMAIN_PATTERN) then return false, 'Invalid domain' end
    if Browser.byDomain[domain] then return false, 'Domain already in use' end
    local ui = tostring(def.ui or '')
    if ui:sub(1, #invoking + 1) ~= invoking .. '/' or ui:find('%.%.') then
        return false, 'ui must be a path inside the calling resource'
    end
    local key = 'ext:' .. domain
    Browser.sites[key] = {
        key = key, domain = domain, title = clean(def.title or domain, 60),
        description = clean(def.description, 200), keywords = def.keywords or {},
        category = clean(def.category or T('shell.categoryGeneral'), 40), icon = clean(def.icon or '🌐', 8),
        color = clean(def.color or '#2563eb', 16), resource = invoking,
        page = ui:sub(#invoking + 2), pages = def.pages or {}, featured = def.featured ~= false,
        enabled = true, external = true,
    }
    Browser.byDomain[domain] = key
    Browser.handlers[key] = {}
    TriggerClientEvent('as-browser:client:sitesChanged', -1)
    return true
end)

exports('registerHandler', function(domain, name, fn)
    local invoking = GetInvokingResource()
    local site, key = siteByDomain(domain)
    if not site or not site.external or site.resource ~= invoking then return false end
    if type(name) ~= 'string' or type(fn) ~= 'function' and type(fn) ~= 'table' then return false end
    Browser.handlers[key][name] = fn
    return true
end)

exports('unregisterSite', function(domain)
    local invoking = GetInvokingResource()
    local site, key = siteByDomain(domain)
    if not site or not site.external or site.resource ~= invoking then return false end
    Browser.sites[key], Browser.handlers[key], Browser.byDomain[site.domain] = nil, nil, nil
    TriggerClientEvent('as-browser:client:sitesChanged', -1)
    return true
end)

AddEventHandler('onResourceStop', function(res)
    local changed = false
    for key, site in pairs(Browser.sites) do
        if site.external and site.resource == res then
            Browser.sites[key], Browser.handlers[key], Browser.byDomain[site.domain] = nil, nil, nil
            changed = true
        end
    end
    if changed then TriggerClientEvent('as-browser:client:sitesChanged', -1) end
end)

-- For other resources' desktop browsers: exports['as-browser']:handle('as-browser:siteCall', source, domain, name, data)
-- The calling resource passes the real player source; only callbacks registered above can be reached.
exports('handle', function(name, src, ...)
    local fn = desktopCallbacks[name] or callbacks[name]
    if not fn or type(src) ~= 'number' then return nil end
    return fn(src, ...)
end)

--- Language dictionary + currency, so a desktop shell can hand the same text to the site pages.
exports('shellInfo', function()
    return { dict = LocaleDict(), currency = Config.currency or '£' }
end)

exports('isSiteEnabled', function(domain)
    local site = siteByDomain(domain)
    return site ~= nil and site.enabled
end)

-- Vehicle status exports for MDT / ANPR / police scripts and for the future MOT script.
-- They answer only while the government site is switched on.
exports('getVehicleStatus', function(plate)
    if Browser.api.getVehicleStatus and Browser.isEnabled('gov') then return Browser.api.getVehicleStatus(plate) end
    return nil
end)

exports('isRoadLegal', function(plate)
    if Browser.api.isRoadLegal and Browser.isEnabled('gov') then return Browser.api.isRoadLegal(plate) end
    return nil
end)

--- For the MOT script: setMotResult(plate, passed, expiry, details)
--- expiry is a unix timestamp (seconds) when passed, details is free text (optional).
exports('setMotResult', function(plate, passed, expiry, details)
    if Browser.api.setMotResult then return Browser.api.setMotResult(plate, passed, expiry, details) end
    return false, 'The government site is not running'
end)

CreateThread(function()
    Wait(1500)
    local on, off = {}, {}
    for _, s in pairs(Browser.sites) do
        if s.enabled then on[#on + 1] = s.domain else off[#off + 1] = s.domain end
    end
    table.sort(on); table.sort(off)
    log('framework: %s | sites on: %s | sites off: %s', Bridge.framework,
        #on > 0 and table.concat(on, ', ') or 'none', #off > 0 and table.concat(off, ', ') or 'none')
end)
