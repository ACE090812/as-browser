-- Marriage and business registration pages on the government site. The rules, fees, records and
-- certificates live in the as-registry resource; this file only passes requests through.
-- If it is not running the pages say so.

local function running()
    return Browser.govScriptOn('registry') and GetResourceState('as-registry') == 'started'
end

local function NOT_RUNNING() return T('gov.registry.notRunning') end

local function call(name, src, data)
    local ok, a, b = pcall(function() return exports['as-registry'][name](exports['as-registry'], src, data) end)
    if not ok then
        print(('^5[as-browser]^0 gov: as-registry %s failed: %s'):format(name, tostring(a)))
        return nil, T('gov.err.notCharged')
    end
    return a, b
end

local function pass(handler, export, build)
    Browser.handler('gov', handler, function(src, data)
        if not running() then return nil, NOT_RUNNING() end
        local res, err = call(export, src, build and build(data) or nil)
        if not res then return nil, err or NOT_RUNNING() end
        return res
    end)
end

local function str(v, n) return tostring(v or ''):sub(1, n or 80) end

-- Marriage
pass('marriageState',   'marriageState')
pass('marriagePropose', 'marriagePropose', function(d) return { partner = str(d.partner, 60) } end)
pass('marriageRespond', 'marriageRespond', function(d) return { id = tonumber(d.id), accept = d.accept == true } end)
pass('marriageCancel',  'marriageCancel')
pass('marriageCopy',    'marriageCopy')

-- Businesses
pass('businessState',    'businessState')
pass('businessRegister', 'businessRegister', function(d) return { name = str(d.name, 80), type = str(d.type, 40), description = str(d.description, 200) } end)
pass('businessClose',    'businessClose', function(d) return { id = tonumber(d.id) } end)
pass('businessCopy',     'businessCopy', function(d) return { id = tonumber(d.id) } end)
