-- Los Santos Careers: validates an application and posts it to Discord.
local J = Config.jobs
local HOUR = 3600

local function now() return os.time() end

local pages = {}
for _, f in ipairs(J.forms) do
    pages[#pages + 1] = { path = '/apply/' .. f.id, title = f.title, description = f.description,
                          keywords = { 'apply', 'application', 'job', 'career', f.group and f.group:lower() or 'work' } }
end

Browser.defineSite('jobs', {
    title       = J.name,
    description = 'Browse roles in the city and apply.',
    keywords    = { 'jobs', 'careers', 'apply', 'application', 'whitelist', 'staff', 'police', 'lspd', 'sahp', 'fire', 'ems', 'faction', 'work', 'vacancies', 'indeed' },
    category    = 'Jobs',
    icon        = '💼',
    color       = '#0f766e',
    pages       = pages,
})

MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS browser_job_applications (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        form VARCHAR(32) NOT NULL,
        created_at INT NOT NULL,
        KEY idx_cooldown (citizenid, form, created_at)
    )]])
end)

local function findForm(id)
    for _, f in ipairs(J.forms) do if f.id == id then return f end end
    return nil
end

local function isOpen(f)
    return f.open ~= false and type(f.webhook) == 'string' and f.webhook:find('^https://') ~= nil
end

local function cooldownLeft(cid, f)
    local hours = tonumber(f.cooldownHours) or J.cooldownHours or 24
    local last = tonumber(MySQL.scalar.await(
        'SELECT MAX(created_at) FROM browser_job_applications WHERE citizenid = ? AND form = ?', { cid, f.id }))
    if not last then return 0 end
    return math.max(0, last + hours * HOUR - now())
end

--- The form as the page needs it. Never includes the webhook.
local function publicForm(f, cid)
    return {
        id = f.id, title = f.title, icon = f.icon, group = f.group, description = f.description,
        open = isOpen(f), fields = f.fields,
        wait = cid and cooldownLeft(cid, f) or 0,
    }
end

Browser.handler('jobs', 'home', function(src)
    local cid = Bridge.getIdentifier(src)
    local forms, groups, seen = {}, {}, {}
    for _, f in ipairs(J.forms) do
        forms[#forms + 1] = publicForm(f, cid)
        local g = f.group or 'Other'
        if not seen[g] then seen[g] = true; groups[#groups + 1] = g end
    end
    return { name = J.name, tagline = J.tagline, forms = forms, groups = groups, now = now() }
end)

-- ---------------------------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------------------------

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

--- Returns the cleaned answers as a list of { label, value }, or nil plus a message.
local function readAnswers(f, data)
    local given = type(data.answers) == 'table' and data.answers or {}
    local out = {}
    for _, fld in ipairs(f.fields) do
        local raw = given[fld.id]
        local required = fld.required ~= false
        local value

        if fld.type == 'checkbox' then
            if raw ~= true then
                if required then return nil, ('Please tick "%s".'):format(fld.label) end
                value = 'No'
            else
                value = 'Yes'
            end
        elseif fld.type == 'number' then
            local n = tonumber(raw)
            if raw == nil or raw == '' then
                if required then return nil, ('"%s" is required.'):format(fld.label) end
                value = ''
            else
                if not n or n ~= n then return nil, ('"%s" must be a number.'):format(fld.label) end
                n = math.floor(n)
                if fld.min and n < fld.min then return nil, ('"%s" must be at least %d.'):format(fld.label, fld.min) end
                if fld.max and n > fld.max then return nil, ('"%s" must be %d or less.'):format(fld.label, fld.max) end
                value = tostring(n)
            end
        elseif fld.type == 'select' then
            local s = trim(raw)
            if s == '' then
                if required then return nil, ('Choose an answer for "%s".'):format(fld.label) end
                value = ''
            else
                local ok = false
                for _, o in ipairs(fld.options or {}) do if o == s then ok = true end end
                if not ok then return nil, ('Choose a valid answer for "%s".'):format(fld.label) end
                value = s
            end
        else
            local s = trim(raw):gsub('%c', function(c) return (c == '\n') and '\n' or ' ' end)
            if fld.type ~= 'textarea' then s = s:gsub('\n', ' ') end
            if s == '' then
                if required then return nil, ('"%s" is required.'):format(fld.label) end
                value = ''
            else
                if fld.min and #s < fld.min then return nil, ('"%s" needs at least %d characters.'):format(fld.label, fld.min) end
                if fld.max and #s > fld.max then return nil, ('"%s" must be %d characters or fewer.'):format(fld.label, fld.max) end
                value = s
            end
        end

        out[#out + 1] = { label = fld.label, value = value }
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Discord
-- ---------------------------------------------------------------------------------------------

--- Stops pings from applicant text. The role mention we add ourselves is allowed separately.
local function defang(s)
    return (tostring(s):gsub('@', '@\226\128\139'))
end

local function postToDiscord(f, embed, content, roleId)
    local body = { embeds = { embed }, allowed_mentions = { parse = {}, roles = roleId and { roleId } or nil } }
    if content then body.content = content end

    local p = promise.new()
    PerformHttpRequest(f.webhook, function(status)
        p:resolve(status)
    end, 'POST', json.encode(body), { ['Content-Type'] = 'application/json' })
    local status = Citizen.Await(p)
    return type(status) == 'number' and status >= 200 and status < 300, status
end

local function buildEmbed(f, src, cid, answers)
    local fields = {}
    for i = 1, math.min(#answers, 20) do
        local a = answers[i]
        local v = a.value ~= '' and a.value or '-'
        fields[#fields + 1] = { name = a.label:sub(1, 250), value = defang(v):sub(1, 1000), inline = #v <= 40 }
    end

    local discordId = Bridge.getDiscordId(src)
    fields[#fields + 1] = { name = 'Applicant', value = defang(Bridge.getCharacterName(src)), inline = true }
    fields[#fields + 1] = { name = 'Player', value = defang(GetPlayerName(src) or 'Unknown'), inline = true }
    fields[#fields + 1] = { name = 'Discord', value = discordId and ('<@%s>'):format(discordId) or 'Not linked', inline = true }
    fields[#fields + 1] = { name = 'Character ID', value = tostring(cid), inline = true }
    fields[#fields + 1] = { name = 'Server ID', value = tostring(src), inline = true }

    return {
        title = (f.title .. ' - new application'):sub(1, 250),
        color = tonumber(f.color) or 0x7c3aed,
        fields = fields,
        footer = { text = J.name },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
end

-- ---------------------------------------------------------------------------------------------
-- Submitting
-- ---------------------------------------------------------------------------------------------

local busy = {}

local function apply(src, data)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
    local f = findForm(tostring(data.form or ''))
    if not f then return nil, 'That application does not exist.' end
    if not isOpen(f) then return nil, 'Applications for this role are closed right now.' end

    local wait = cooldownLeft(cid, f)
    if wait > 0 then
        return nil, ('You have already applied. You can apply again in %d hour(s).'):format(math.ceil(wait / HOUR))
    end

    local answers, msg = readAnswers(f, data)
    if not answers then return nil, msg end

    local ok, status = postToDiscord(f, buildEmbed(f, src, cid, answers),
        f.mentionRole and ('<@&%s>'):format(f.mentionRole) or nil, f.mentionRole)
    if not ok then
        print(('^5[as-browser]^0 jobs: Discord webhook for "%s" answered %s'):format(f.id, tostring(status)))
        return nil, 'We could not send your application right now. Please try again later.'
    end

    MySQL.insert.await('INSERT INTO browser_job_applications (citizenid, form, created_at) VALUES (?, ?, ?)', { cid, f.id, now() })

    Bridge.sendPhoneMail(src, cid, J.mailFrom,
        ('We received your %s'):format(f.title:lower()),
        ('Hello %s,\n\nThanks for applying. Your %s has been sent to the team and we will be in touch on Discord.\n\nPlease do not send it again.'):format(
            Bridge.getCharacterName(src), f.title:lower()))

    return { form = f.id, title = f.title, sentAt = now() }
end

Browser.handler('jobs', 'apply', function(src, data)
    if busy[src] then return nil, 'Please wait, your last request is still being processed.' end
    busy[src] = true
    local ok, res, err = pcall(apply, src, data)
    busy[src] = nil
    if not ok then error(res, 0) end
    return res, err
end)

Browser.handler('jobs', 'mine', function(src)
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'You are not signed in.' end
    local rows = MySQL.query.await(
        'SELECT form, created_at FROM browser_job_applications WHERE citizenid = ? ORDER BY id DESC LIMIT 30', { cid }) or {}
    local out = {}
    for i = 1, #rows do
        local f = findForm(rows[i].form)
        out[i] = { title = f and f.title or rows[i].form, sentAt = rows[i].created_at }
    end
    return { applications = out }
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)
