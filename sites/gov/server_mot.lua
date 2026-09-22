-- MOT booking pages on the government site. Garages, time slots, the fee and the bookings themselves live in the
-- as-computer resource (config/apps/booking.lua); this file passes requests through and adds the phone side
-- (bank statement line, emails). If as-computer is not running the pages say so.
local M = Config.gov.motBooking or {
    resource = 'as-computer', authority = 'DVSA', mailFrom = { name = 'DVSA', email = 'noreply@lsgov.co.uk' }, expiryReminderDays = 3,
}

local function running()
    return Browser.govScriptOn('motbooking') and GetResourceState(M.resource) == 'started'
end

local function NOT_RUNNING() return T('gov.mot.notRunning') end

local function call(name, ...)
    local args = { ... }
    local ok, res = pcall(function() return exports[M.resource][name](exports[M.resource], table.unpack(args)) end)
    if not ok then
        print(('^5[as-browser]^0 gov: %s:%s failed: %s'):format(M.resource, name, tostring(res)))
        return nil
    end
    return res
end

--- as-computer answers with a table, or { error = 'reason' }. Turns a failure into text for the player.
local function failure(res)
    if type(res) ~= 'table' then return NOT_RUNNING() end
    local key = 'gov.mot.err.' .. tostring(res.error or 'error')
    local txt = T(key)
    if txt == key then txt = T('gov.mot.err.error') end
    return txt
end

local function trimPlate(p) return (tostring(p):gsub('%s+$', '')) end

local function siteAddress()
    local cfg = Config.Sites and Config.Sites.gov
    return cfg and cfg.domain or 'lsgov.co.uk'
end

local function whenText(b) return Browser.date(b.slotTs) .. ' ' .. b.time end

local function bankLine(cid, label, amount)
    if amount == 0 then return end
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, { label = label, amount = amount, category = 'government', counterparty = M.authority })
    end)
end

--- Bookings, garages and the rules, in one go.
Browser.handler('gov', 'motState', function(src)
    if not running() then return nil, NOT_RUNNING() end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local cfg = call('bookingConfig')
    if type(cfg) ~= 'table' then return nil, NOT_RUNNING() end
    if not cfg.enabled then return nil, T('gov.mot.err.disabled') end
    local mine = call('bookingMine', cid)
    if type(mine) ~= 'table' then return nil, NOT_RUNNING() end
    return { config = cfg, upcoming = mine.upcoming or {}, past = mine.past or {}, now = os.time() }
end)

--- Free times for one garage. data = { garage = 'id' }
Browser.handler('gov', 'motSlots', function(src, data)
    if not running() then return nil, NOT_RUNNING() end
    local res = call('bookingAvailability', tostring(data.garage or ''))
    if type(res) ~= 'table' or res.error then return nil, failure(res) end
    return res
end)

--- Book and pay. data = { plate, garage, date, time }
Browser.handler('gov', 'motBook', function(src, data)
    if not running() then return nil, NOT_RUNNING() end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local key = Vehicles.normalizePlate(tostring(data.plate or ''))
    if not key then return nil, T('gov.err.plate') end
    local v = Vehicles.find(key)
    if not v or v.owner ~= cid then return nil, T('gov.mot.err.notOwner') end
    local d = Vehicles.describe(v)

    -- reserve the slot first, so two people cannot pay for the same one
    local held = call('bookingHold', {
        cid = cid, name = Bridge.getCharacterName(src), plate = trimPlate(d.plate),
        vehicle = ('%s %s'):format(d.make or '', d.model or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        garage = tostring(data.garage or ''), date = tostring(data.date or ''), time = tostring(data.time or ''),
    })
    if type(held) ~= 'table' or held.error then return nil, failure(held) end

    local fee = tonumber(held.fee) or 0
    if fee > 0 and not Bridge.removeMoney(src, Config.account, fee, 'mot-booking') then
        call('bookingRelease', held.id)
        return nil, T('shell.err.insufficientFunds')
    end
    if call('bookingConfirm', held.id) ~= true then
        if fee > 0 then Bridge.addMoney(src, Config.account, fee, 'mot-booking-refund') end
        call('bookingRelease', held.id)
        return nil, T('gov.mot.err.error')
    end

    bankLine(cid, T('gov.mot.bankLabel', held.plate), -fee)
    local cfg = call('bookingConfig') or {}
    Bridge.sendPhoneMail(src, cid, M.mailFrom, T('gov.mot.bookedSubject'),
        T('gov.mot.bookedBody', Bridge.getCharacterName(src), held.plate, held.garageName, whenText(held), Config.currency, fee, siteAddress(), cfg.cancelMinutes or 60))
    held.paid = fee
    held.status = 'booked'
    held.canCancel = (held.slotTs or 0) - os.time() >= (cfg.cancelMinutes or 60) * 60
    return held
end)

--- Cancel and get the fee back. data = { id }
Browser.handler('gov', 'motCancel', function(src, data)
    if not running() then return nil, NOT_RUNNING() end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local res = call('bookingCancel', cid, tonumber(data.id))
    if type(res) ~= 'table' or res.error then return nil, failure(res) end

    local refund = tonumber(res.refund) or 0
    if refund > 0 and not Bridge.addMoney(src, Config.account, refund, 'mot-booking-refund') then
        print(('^5[as-browser]^0 gov: could not refund %d for MOT booking %s to %s'):format(refund, tostring(data.id), cid))
    end
    local b = res.booking
    bankLine(cid, T('gov.mot.refundLabel', b.plate), refund)
    Bridge.sendPhoneMail(src, cid, M.mailFrom, T('gov.mot.cancelledSubject'),
        T('gov.mot.cancelledBody', Bridge.getCharacterName(src), b.plate, whenText(b), Config.currency, refund))
    return { booking = b, refund = refund }
end)

--- Move to another garage / time, keeping what was paid. data = { id, garage, date, time }
Browser.handler('gov', 'motMove', function(src, data)
    if not running() then return nil, NOT_RUNNING() end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local b = call('bookingMove', cid, tonumber(data.id), tostring(data.garage or ''), tostring(data.date or ''), tostring(data.time or ''))
    if type(b) ~= 'table' or b.error then return nil, failure(b) end
    Bridge.sendPhoneMail(src, cid, M.mailFrom, T('gov.mot.movedSubject'),
        T('gov.mot.movedBody', Bridge.getCharacterName(src), b.plate, b.garageName, whenText(b)))
    return b
end)

-- ---------------------------------------------------------------------------------------------
-- Emails: a reminder shortly before a booking, and when an MOT is about to run out
-- ---------------------------------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_mot_reminders (
        plate VARCHAR(16) NOT NULL PRIMARY KEY,
        expiry INT NOT NULL
    )]])
end)

local function playerByCid(cid)
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if s and Bridge.getIdentifier(s) == cid then return s end
    end
    return nil
end

local function bookingReminders()
    local due = call('bookingDueReminders')
    if type(due) ~= 'table' or due.error then return end
    for _, b in ipairs(due) do
        local src = playerByCid(b.cid)
        if src then
            Bridge.sendPhoneMail(src, b.cid, M.mailFrom, T('gov.mot.reminderSubject'),
                T('gov.mot.reminderBody', b.name or T('shell.citizen'), b.plate, b.garageName, b.time))
            call('bookingMarkReminded', b.id)
        end
    end
end

local function expiryReminders()
    local days = tonumber(M.expiryReminderDays) or 0
    if days <= 0 or not (Config.gov.mot and Config.gov.mot.enabled) then return end
    local t = os.time()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local cid = src and Bridge.getIdentifier(src)
        if cid then
            local booked = {}
            local mine = call('bookingMine', cid)
            for _, b in ipairs(type(mine) == 'table' and mine.upcoming or {}) do
                booked[tostring(b.plate):upper():gsub('[^A-Z0-9]', '')] = true
            end
            for _, v in ipairs(Vehicles.ownedBy(cid)) do
                local d = Vehicles.describe(v)
                if not d.exempt and not booked[d.plateKey] then
                    local row = MySQL.single.await('SELECT mot_expiry FROM browser_vehicle_status WHERE plate = ?', { d.plateKey })
                    local exp = row and tonumber(row.mot_expiry) or 0
                    if exp > 0 and exp - t <= days * 86400 then
                        local sent = tonumber(MySQL.scalar.await('SELECT expiry FROM browser_mot_reminders WHERE plate = ?', { d.plateKey })) or 0
                        if sent ~= exp then
                            local plate = trimPlate(d.plate)
                            if exp > t then
                                Bridge.sendPhoneMail(src, cid, M.mailFrom, T('gov.mot.expirySoonSubject', plate),
                                    T('gov.mot.expirySoonBody', Bridge.getCharacterName(src), plate, Browser.date(exp), siteAddress()))
                            else
                                Bridge.sendPhoneMail(src, cid, M.mailFrom, T('gov.mot.expiredSubject', plate),
                                    T('gov.mot.expiredBody', Bridge.getCharacterName(src), plate, Browser.date(exp), siteAddress()))
                            end
                            MySQL.insert.await('INSERT INTO browser_mot_reminders (plate, expiry) VALUES (?, ?) ON DUPLICATE KEY UPDATE expiry = VALUES(expiry)',
                                { d.plateKey, exp })
                        end
                    end
                end
            end
        end
    end
end

CreateThread(function()
    Wait(30000)
    local n = 0
    while true do
        if running() then
            pcall(bookingReminders)
            if n % 5 == 0 then pcall(expiryReminders) end   -- every 5 minutes
        end
        n = n + 1
        Wait(60000)
    end
end)

--- Print a booking confirmation (as-printer). data = { id, printer, colour, design, letterhead }. Cannot be copied.
Browser.handler('gov', 'motPrint', function(src, data)
    if not running() then return nil, NOT_RUNNING() end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, T('shell.err.notSignedIn') end
    local mine = call('bookingMine', cid)
    if type(mine) ~= 'table' then return nil, NOT_RUNNING() end
    local want, found = tonumber(data.id), nil
    for _, list in ipairs({ mine.upcoming or {}, mine.past or {} }) do
        for _, b in ipairs(list) do if tonumber(b.id) == want then found = b end end
    end
    if not found then return nil, T('print.err.notFound') end
    local money = Browser.printMoney(found.fee)
    return Browser.printDoc(src, 'mot_booking', {
        reference = 'MOT-' .. tostring(found.id), plate = trimPlate(found.plate), model = found.vehicle, station = found.garageName,
        date = Browser.date(found.slotTs), time = found.time .. (found.endTime and (' – ' .. found.endTime) or ''), fee = money,
        status = found.status == 'booked' and T('print.statusBooked') or T('print.statusCancelledBooking'),
    }, data)
end)
