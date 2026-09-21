local APP_ID = Config.app.identifier

-- ---------------------------------------------------------------------------------------------
-- Register the app with sd-phone (again if sd-phone restarts)
-- ---------------------------------------------------------------------------------------------

local function register()
    local resource = GetCurrentResourceName()
    local called, res, err = pcall(function()
        return exports['sd-phone']:addCustomApp({
            identifier  = APP_ID,
            name        = Config.app.name,
            description = Config.app.description,
            defaultApp  = Config.app.defaultApp,
            devices     = Config.app.devices,
            ui          = resource .. '/ui/index.html',
            icon        = 'https://cfx-nui-' .. resource .. '/ui/icon.svg',
        })
    end)
    if not called or res == false then
        print(('[as-browser] could not register the Browser app with sd-phone: %s'):format(tostring(called and (err or res) or res)))
    end
end

CreateThread(function()
    while GetResourceState('sd-phone') ~= 'started' do Wait(500) end
    Wait(500)
    register()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'sd-phone' then SetTimeout(2000, register) end
end)

-- ---------------------------------------------------------------------------------------------
-- NUI <-> server
-- ---------------------------------------------------------------------------------------------

local function ask(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if ok then return res end
    return nil
end

-- The page asks for the language dictionary once at start (see locales/ and README "Languages").
RegisterNUICallback('locale', function(_, cb) cb(LocaleDict()) end)

RegisterNUICallback('sites', function(_, cb)
    cb(ask('as-browser:sites') or {})
end)

RegisterNUICallback('player', function(_, cb)
    cb(ask('as-browser:player') or { name = T('shell.citizen') })
end)

RegisterNUICallback('siteCall', function(data, cb)
    data = data or {}
    cb(ask('as-browser:siteCall', data.domain, data.name, data.data)
        or { ok = false, error = T('shell.noServerResponse') })
end)

RegisterNUICallback('bookmarks:list', function(_, cb) cb(ask('as-browser:bookmarks:list') or {}) end)
RegisterNUICallback('bookmarks:add', function(d, cb)
    d = d or {}
    local ok, err = ask('as-browser:bookmarks:add', d.url, d.title)
    cb({ ok = ok == true, error = err })
end)
RegisterNUICallback('bookmarks:remove', function(d, cb)
    cb({ ok = ask('as-browser:bookmarks:remove', (d or {}).url) == true })
end)
RegisterNUICallback('history:list', function(_, cb) cb(ask('as-browser:history:list') or {}) end)
RegisterNUICallback('history:add', function(d, cb)
    d = d or {}
    cb({ ok = ask('as-browser:history:add', d.url, d.title) == true })
end)
RegisterNUICallback('history:clear', function(_, cb) cb({ ok = ask('as-browser:history:clear') == true }) end)

-- Saving a site login into the phone's Passwords app. Off by default: see the README.
RegisterNUICallback('savePassword', function(d, cb)
    if not Config.passwords.enabled then
        return cb({ ok = false, error = T('shell.saveLoginOff') })
    end
    d = d or {}
    local res = ask('sd-phone:server:accounts:savePassword', {
        app      = Config.passwords.appId,
        username = d.username,
        password = d.password,
        email    = d.email,
    })
    if type(res) == 'table' and res.success == true then return cb({ ok = true }) end
    cb({ ok = false, error = (type(res) == 'table' and (res.message or res.error)) or T('shell.saveLoginFailed') })
end)

-- A site was switched on or off, or another resource added one: tell the open browser.
RegisterNetEvent('as-browser:client:sitesChanged', function()
    pcall(function()
        exports['sd-phone']:sendCustomAppMessage(APP_ID, { action = 'sitesChanged' })
    end)
end)
