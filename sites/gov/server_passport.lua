-- Passport pages on the government site. All the logic (prices, records, delivery) lives in the
-- as-passport resource; this file only passes requests through so the website works with it.
-- If as-passport is not running, the pages say so instead of breaking.

local function passportRunning()
    return GetResourceState('as-passport') == 'started'
end

local NOT_RUNNING = 'Passport applications are not available right now. Please try again later.'

--- What the player can apply for, what they hold, and any application in progress.
Browser.handler('gov', 'passportState', function(src)
    if not passportRunning() then return nil, NOT_RUNNING end
    local ok, state, err = pcall(function() return exports['as-passport']:getState(src) end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-passport getState failed: %s'):format(tostring(state)))
        return nil, NOT_RUNNING
    end
    if not state then return nil, err or NOT_RUNNING end
    return state
end)

--- Pay for and start an application. data = { type = 'standard', lockerId = '...' }
Browser.handler('gov', 'passportApply', function(src, data)
    if not passportRunning() then return nil, NOT_RUNNING end
    local ok, res, err = pcall(function()
        return exports['as-passport']:apply(src, {
            type = tostring(data.type or ''), lockerId = data.lockerId ~= nil and tostring(data.lockerId) or nil,
        })
    end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-passport apply failed: %s'):format(tostring(res)))
        return nil, 'Something went wrong. You have not been charged, please try again.'
    end
    if not res then return nil, err or 'We could not process your application.' end
    return res
end)
