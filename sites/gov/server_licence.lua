-- Driving licence pages on the government site. All the rules, fees and records live in the
-- as-drivingschool resource; this file passes requests through and adds the phone side (bank
-- statement line, confirmation email). If the resource is not running the pages say so.
local L = Config.gov.licence or { resource = 'as-drivingschool', authority = 'DVLA', mailFrom = { name = 'DVLA', email = 'noreply@lsgov.co.uk' } }

local NOT_RUNNING = 'Driving licence services are not available right now. Please try again later.'

local function running()
    return GetResourceState(L.resource) == 'started'
end

local function call(name, ...)
    local args = { ... }
    local ok, a, b = pcall(function() return exports[L.resource][name](exports[L.resource], table.unpack(args)) end)
    if not ok then
        print(('^5[as-browser]^0 gov: %s:%s failed: %s'):format(L.resource, name, tostring(a)))
        return nil, NOT_RUNNING
    end
    return a, b
end

--- The licence, the fees and what can be booked, in one go.
Browser.handler('gov', 'licenceState', function(src)
    if not running() then return nil, NOT_RUNNING end
    local summary, err = call('getLicenceSummary', src)
    if not summary then return nil, err or NOT_RUNNING end
    local booking, err2 = call('getBookingState', src)
    if not booking then return nil, err2 or NOT_RUNNING end
    return { licence = summary, booking = booking, now = os.time() }
end)

--- Book and pay for a test. data = { kind = 'theory' | 'practical', category = 'B' }
Browser.handler('gov', 'licenceBook', function(src, data)
    if not running() then return nil, NOT_RUNNING end
    local kind = tostring(data.kind or '')
    local category = data.category ~= nil and tostring(data.category):sub(1, 10) or ''
    local res, err = call('bookTest', src, kind, category)
    if not res then return nil, err or 'We could not book your test.' end

    local cid = Bridge.getIdentifier(src)
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = res.label, amount = -res.price, category = 'government', counterparty = L.authority,
        })
    end)
    local lower = res.label:sub(1, 1):lower() .. res.label:sub(2)
    local centre = (function() local b = call('getBookingState', src); return b and b.centre or 'the driving centre' end)()
    Bridge.sendPhoneMail(src, cid, L.mailFrom, ('Your %s is booked'):format(lower),
        ('Hello %s,\n\nYour %s is booked and paid for (%s%d).\n\nGo to %s to take it. Your booking is used up when you take the test, so if you fail you will need to book again.'):format(
            Bridge.getCharacterName(src), lower, Config.currency, res.price, centre))
    res.centre = centre
    return res
end)

--- Order a replacement licence. data = { lockerId = '...' }. Delivered by as-drivingschool (Postal Prime locker).
Browser.handler('gov', 'licenceReplace', function(src, data)
    if not running() then return nil, NOT_RUNNING end
    local lockerId = data.lockerId ~= nil and tostring(data.lockerId):sub(1, 64) or nil
    local res, err = call('replaceLicence', src, { lockerId = lockerId })
    if not res then return nil, err or 'We could not order your replacement licence.' end

    local cid = Bridge.getIdentifier(src)
    pcall(function()
        exports['sd-phone']:addBankTransaction(cid, {
            label = 'Replacement driving licence', amount = -res.fee, category = 'government', counterparty = L.authority,
        })
    end)
    Bridge.sendPhoneMail(src, cid, L.mailFrom, 'We have received your replacement licence order',
        ('Hello %s,\n\nWe have received your order for a replacement driving licence and your payment of %s%d. Your old licence has been cancelled.\n\nIt will be ready at %s%s We will email you when it has been sent.'):format(
            Bridge.getCharacterName(src), Config.currency, res.fee, os.date('%d %b %Y %H:%M', res.readyAt),
            res.lockerLabel and ((' and sent to ' .. res.lockerLabel .. '.')) or ' and added to your inventory.'))
    return res
end)
