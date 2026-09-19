-- Framework bridge. Same auto-detect pattern as Postal Prime, trimmed to what the sites need:
-- who the player is, their character name, and their bank account.
Bridge = {}

local function detectFramework()
    if Config.framework ~= 'auto' then return Config.framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

Bridge.framework = detectFramework()
local framework = Bridge.framework

local QBCore, qbxExport, ESX

local function ensureCore()
    if framework == 'qb' and not QBCore then
        QBCore = exports['qb-core']:GetCoreObject()
    elseif framework == 'qbx' and not qbxExport then
        qbxExport = exports.qbx_core
    elseif framework == 'esx' and not ESX then
        ESX = exports['es_extended']:getSharedObject()
    end
end
Bridge.ensureCore = ensureCore

function Bridge.getQBCore() ensureCore(); return QBCore end

local function getPlayer(source)
    ensureCore()
    if framework == 'qb' and QBCore then return QBCore.Functions.GetPlayer(source) end
    if framework == 'qbx' and qbxExport then return qbxExport:GetPlayer(source) end
    return nil
end

--- The player's stable character id (citizenid, or the ESX identifier).
function Bridge.getIdentifier(source)
    ensureCore()
    if framework == 'qb' or framework == 'qbx' then
        local p = getPlayer(source)
        return p and p.PlayerData.citizenid or nil
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or nil
    end
    return source and ('standalone:' .. tostring(source)) or nil
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

--- In-character name, never the FiveM/Steam name unless the framework can't give one.
function Bridge.getCharacterName(source)
    ensureCore()
    if framework == 'qb' or framework == 'qbx' then
        local p = getPlayer(source)
        local ci = p and p.PlayerData.charinfo
        if ci and (ci.firstname or ci.lastname) then
            return trim(('%s %s'):format(ci.firstname or '', ci.lastname or ''))
        end
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local ok, name = pcall(function() return xPlayer.getName() end)
            if ok and name and name ~= '' then return name end
        end
    end
    return GetPlayerName(source) or 'Citizen'
end

function Bridge.getBalance(source, account)
    ensureCore()
    if framework == 'qb' or framework == 'qbx' then
        local p = getPlayer(source)
        return p and (p.PlayerData.money[account] or 0) or 0
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        local acc = xPlayer and xPlayer.getAccount(account)
        return acc and acc.money or 0
    end
    return math.huge
end

--- Takes money from an account. Returns true when the full amount was taken.
function Bridge.removeMoney(source, account, amount, reason)
    ensureCore()
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    reason = reason or 'as-browser'
    if framework == 'qb' or framework == 'qbx' then
        local p = getPlayer(source)
        if not p then return false end
        if (p.PlayerData.money[account] or 0) < amount then return false end
        return p.Functions.RemoveMoney(account, amount, reason) == true
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        local acc = xPlayer.getAccount(account)
        if not acc or acc.money < amount then return false end
        xPlayer.removeAccountMoney(account, amount)
        return true
    end
    return true
end

--- Gives money back (used when a purchase fails after the player was charged).
function Bridge.addMoney(source, account, amount, reason)
    ensureCore()
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    reason = reason or 'as-browser-refund'
    if framework == 'qb' or framework == 'qbx' then
        local p = getPlayer(source)
        if not p then return false end
        p.Functions.AddMoney(account, amount, reason)
        return true
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        xPlayer.addAccountMoney(account, amount)
        return true
    end
    return true
end

--- The player's Discord id if the server exposes it, for application embeds.
function Bridge.getDiscordId(source)
    local id = GetPlayerIdentifierByType and GetPlayerIdentifierByType(source, 'discord')
    if id and id ~= '' then return (id:gsub('^discord:', '')) end
    return nil
end


--- Sends a system email to the player's Mail app. Tries the accounts they are signed into, then the
--- accounts registered to the character. If a sender format is refused it tries simpler ones.
--- Anything that goes wrong is printed to the server console.
--- from = { name = 'CoverCompare', email = 'noreply@covercompare.co.uk' }
function Bridge.sendPhoneMail(source, identifier, from, subject, body)
    local ok, err = pcall(function()
        local email
        local live = exports['sd-phone']:getMailAccounts(source)
        if type(live) == 'table' and live[1] then email = live[1].email end
        if not email and identifier then
            local saved = exports['sd-phone']:getMailAddresses(identifier)
            if type(saved) == 'table' and saved[1] then email = saved[1].email end
        end
        if not email then
            print(('^5[as-browser]^0 mail not sent: %s has no email account in the Mail app'):format(tostring(identifier)))
            return
        end

        print(('^5[as-browser]^0 mail: sending "%s" to %s'):format(tostring(subject), email))
        local attempts = { from, from and { name = from.name } or nil, false }
        for i = 1, 3 do
            local sender = attempts[i]
            if sender ~= nil then
                local mail = { to = email, subject = subject, body = body }
                if sender then mail.from = sender end
                local res = exports['sd-phone']:sendMail(mail)
                print(('^5[as-browser]^0 mail: attempt %d -> success=%s delivered=%s'):format(
                    i, tostring(type(res) == 'table' and res.success), tostring(type(res) == 'table' and res.delivered)))
                if type(res) == 'table' and res.delivered and res.delivered > 0 then return end
            end
        end
        print(('^5[as-browser]^0 mail to %s was not delivered by sd-phone'):format(email))
    end)
    if not ok then print(('^5[as-browser]^0 mail failed: %s'):format(tostring(err))) end
end

return Bridge
