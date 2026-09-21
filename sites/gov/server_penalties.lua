-- Penalty points and fines on one page. The points come from the driving licence script and the unpaid fines from
-- as-fines; whichever of the two is running is shown. Paying a fine uses the same request as the "Pay a fine" page
-- (finesPay in server_fines.lua).
local function licenceResource()
    return (Config.gov.licence and Config.gov.licence.resource) or 'as-drivingschool'
end

local function licenceOn()
    return Browser.govScriptOn('licence') and GetResourceState(licenceResource()) == 'started'
end

local function finesOn()
    return Browser.govScriptOn('fines') and GetResourceState('as-fines') == 'started'
end

Browser.handler('gov', 'penaltiesState', function(src)
    if not Browser.govScriptOn('penalties') then return nil, T('gov.penalties.notRunning') end
    local out = { now = os.time() }

    if licenceOn() then
        local ok, sum = pcall(function() return exports[licenceResource()]:getLicenceSummary(src) end)
        if ok and type(sum) == 'table' then
            out.licence = {
                type = sum.type, suspended = sum.suspended == true, points = tonumber(sum.points) or 0,
                maxPoints = tonumber(sum.maxPoints) or 12, penalties = sum.penalties or {},
            }
        elseif not ok then
            print(('^5[as-browser]^0 gov: %s getLicenceSummary failed: %s'):format(licenceResource(), tostring(sum)))
        end
    end

    if finesOn() then
        local ok, state = pcall(function() return exports['as-fines']:getState(src) end)
        if ok and type(state) == 'table' then
            out.fines = { fines = state.fines or {}, paid = state.paid or {}, owed = tonumber(state.owed) or 0 }
        elseif not ok then
            print(('^5[as-browser]^0 gov: as-fines getState failed: %s'):format(tostring(state)))
        end
    end

    if not out.licence and not out.fines then return nil, T('gov.penalties.notRunning') end
    return out
end)
