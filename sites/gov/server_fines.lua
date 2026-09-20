-- Fines pages on the government site. The fines, the /fine command and the payments live in the
-- as-fines resource; this file only passes requests through. If it is not running the pages say so.

local function running()
    return GetResourceState('as-fines') == 'started'
end

local NOT_RUNNING = 'Fines are not available right now. Please try again later.'

--- Unpaid fines, the total owed and recently paid ones.
Browser.handler('gov', 'finesState', function(src)
    if not running() then return nil, NOT_RUNNING end
    local ok, state, err = pcall(function() return exports['as-fines']:getState(src) end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-fines getState failed: %s'):format(tostring(state)))
        return nil, NOT_RUNNING
    end
    if not state then return nil, err or NOT_RUNNING end
    return state
end)

--- Pay one fine (data.id) or all of them (data.all = true).
Browser.handler('gov', 'finesPay', function(src, data)
    if not running() then return nil, NOT_RUNNING end
    local req = data.all == true and { all = true } or { id = tonumber(data.id) }
    local ok, res, err = pcall(function() return exports['as-fines']:pay(src, req) end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-fines pay failed: %s'):format(tostring(res)))
        return nil, 'Something went wrong. You have not been charged, please try again.'
    end
    if not res then return nil, err or 'We could not take your payment.' end
    return res
end)
