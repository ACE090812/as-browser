-- Printing from the websites (needs the as-printer resource). Every site keeps its own "print" request; they all use the two
-- helpers here, and the page asks for the printer list with the shared request "_print.options" (answered for every site).
--   Browser.printDoc(src, template, data, pick)  -> { pages, seconds, printer }  or  nil, message
--     template  a name from as-printer (invoice, receipt, statement, ticket, vehicle_report, mot_booking ...)
--     data      the template's fields, built on the server from the database, never taken from the page
--     pick      what the player chose in the dialog: { printer, colour, design, letterhead }
-- Set Config.Printing = { enabled = false } in config.lua to switch it off.

local function on() return (Config.Printing == nil or Config.Printing.enabled ~= false) and GetResourceState('as-printer') == 'started' end
function Browser.printUp() return on() end

local function line(s, n)
    s = tostring(s or ''):gsub('%c', ' ')
    return s:sub(1, n)
end

local function pick(data)
    data = type(data) == 'table' and data or {}
    return { printer = line(data.printer, 64), colour = data.colour == true, design = line(data.design, 24), letterhead = line(data.letterhead, 48) }
end
Browser.printPick = pick

--- The shared request: printers within reach plus the designs and letterheads this player may use.
function Browser.printOptions(src)
    if not on() then return { available = false, printers = {}, designs = {}, letterheads = {} } end
    local okP, printers = pcall(function() return exports['as-printer']:nearbyPrinters(src, 50.0) end)
    local okO, opts = pcall(function() return exports['as-printer']:options(src) end)
    opts = okO and type(opts) == 'table' and opts or {}
    return { available = true, printers = okP and type(printers) == 'table' and printers or {}, designs = opts.designs or {}, letterheads = opts.letterheads or {} }
end

function Browser.printDoc(src, template, data, choice)
    if not on() then return nil, T('print.err.off') end
    local ok, res = pcall(function() return exports['as-printer']:printTemplate(src, template, data, pick(choice)) end)
    if not ok or type(res) ~= 'table' then return nil, T('print.err.generic') end
    if not res.ok then return nil, (res.error and tostring(res.error) ~= '') and tostring(res.error) or T('print.err.generic') end
    return { pages = res.pages, seconds = res.seconds, printer = res.printer }
end

--- Money the way the receipts print it: "£1,250".
function Browser.printMoney(n)
    n = math.floor(tonumber(n) or 0)
    local neg = n < 0
    local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (neg and '-' or '') .. (Config.currency or '£') .. s
end
