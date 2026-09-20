-- Birth certificate pages on the government site. All the logic (fee, records, delivery) lives in the
-- as-birthcert resource; this file passes requests through. If it is not running the pages say so.

local function running()
    return GetResourceState('as-birthcert') == 'started'
end

local NOT_RUNNING = 'Birth certificate orders are not available right now. Please try again later.'

--- Fee, wait, your details, any order in progress, and where you can collect from.
Browser.handler('gov', 'birthcertState', function(src)
    if not running() then return nil, NOT_RUNNING end
    local ok, state, err = pcall(function() return exports['as-birthcert']:getState(src) end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-birthcert getState failed: %s'):format(tostring(state)))
        return nil, NOT_RUNNING
    end
    if not state then return nil, err or NOT_RUNNING end
    return state
end)

--- Pay for and start an order. data = { lockerId = '...' }
Browser.handler('gov', 'birthcertOrder', function(src, data)
    if not running() then return nil, NOT_RUNNING end
    local ok, res, err = pcall(function()
        return exports['as-birthcert']:order(src, {
            lockerId = data.lockerId ~= nil and tostring(data.lockerId):sub(1, 64) or nil,
        })
    end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-birthcert order failed: %s'):format(tostring(res)))
        return nil, 'Something went wrong. You have not been charged, please try again.'
    end
    if not res then return nil, err or 'We could not process your order.' end
    return res
end)
