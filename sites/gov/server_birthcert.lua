-- Birth certificate pages on the government site. All the logic (fee, records, delivery) lives in the
-- as-birthcert resource; this file passes requests through. If it is not running the pages say so.

local function running()
    return Browser.govScriptOn('birthcert') and GetResourceState('as-birthcert') == 'started'
end

local function NOT_RUNNING() return T('gov.birthcert.notRunning') end

--- Fee, wait, your details, any order in progress, and where you can collect from.
Browser.handler('gov', 'birthcertState', function(src)
    if not running() then return nil, NOT_RUNNING() end
    local ok, state, err = pcall(function() return exports['as-birthcert']:getState(src) end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-birthcert getState failed: %s'):format(tostring(state)))
        return nil, NOT_RUNNING()
    end
    if not state then return nil, err or NOT_RUNNING() end
    return state
end)

--- Pay for and start an order. data = { lockerId = '...' }
Browser.handler('gov', 'birthcertOrder', function(src, data)
    if not running() then return nil, NOT_RUNNING() end
    local ok, res, err = pcall(function()
        return exports['as-birthcert']:order(src, {
            lockerId = data.lockerId ~= nil and tostring(data.lockerId):sub(1, 64) or nil,
        })
    end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-birthcert order failed: %s'):format(tostring(res)))
        return nil, T('gov.err.notCharged')
    end
    if not res then return nil, err or T('gov.birthcert.orderFailed') end
    return res
end)
