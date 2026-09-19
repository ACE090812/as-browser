-- Los Santos Careers: application forms that post to Discord. SERVER ONLY.
-- Webhook URLs are secrets. They live in this file only, which is never sent to players'
-- machines, and are never given to the page. A form with an empty webhook shows as "Closed".
Config.jobs = {
    name = 'Los Santos Careers',
    tagline = 'Find your next role in the city.',

    -- One application per character per form in this many hours (stops spam and accidental repeats).
    cooldownHours = 24,

    -- Fields are asked in order. type: 'text', 'textarea', 'number', 'select', 'checkbox'.
    -- Optional per field: required (default true), min / max (length for text, value for number),
    -- options (for select), hint.
    forms = {
        {
            id = 'whitelist', title = 'Whitelist application', icon = '📝', group = 'Server',
            description = 'Apply to join the server as a player.',
            webhook = '',                 -- paste your Discord webhook URL here
            color = 0x7c3aed,
            mentionRole = nil,            -- optional Discord role id to ping, e.g. '123456789012345678'
            open = true,
            fields = {
                { id = 'age',        label = 'Your real age',                       type = 'number',   min = 13, max = 99 },
                { id = 'experience', label = 'Roleplay experience',                 type = 'textarea', min = 20, max = 800, hint = 'Other servers, how long, what you enjoyed.' },
                { id = 'character',  label = 'Tell us about your first character',  type = 'textarea', min = 40, max = 1200 },
                { id = 'rules',      label = 'What does "value your life" mean?',   type = 'textarea', min = 20, max = 600 },
                { id = 'heard',      label = 'How did you find the server?',        type = 'text',     max = 120, required = false },
                { id = 'agree',      label = 'I have read and agree to the server rules', type = 'checkbox' },
            },
        },
        {
            id = 'staff', title = 'Staff application', icon = '🛠️', group = 'Server',
            description = 'Help run the city as a moderator.',
            webhook = '', color = 0xdc2626, open = true,
            fields = {
                { id = 'age',        label = 'Your real age',                       type = 'number',   min = 16, max = 99 },
                { id = 'time',       label = 'Hours you can give each week',        type = 'number',   min = 1, max = 100 },
                { id = 'experience', label = 'Moderation experience',               type = 'textarea', min = 20, max = 800 },
                { id = 'why',        label = 'Why do you want to join the team?',   type = 'textarea', min = 40, max = 1000 },
                { id = 'scenario',   label = 'A player breaks the rules in front of you and says it is a joke. What do you do?', type = 'textarea', min = 40, max = 1000 },
                { id = 'agree',      label = 'I understand staff must follow the staff code of conduct', type = 'checkbox' },
            },
        },
        {
            id = 'lspd', title = 'Los Santos Police Department', icon = '🚓', group = 'Emergency services',
            description = 'Join the LSPD as a recruit.',
            webhook = '', color = 0x1d4ed8, open = true,
            fields = {
                { id = 'character', label = 'Character name',                        type = 'text',     min = 3, max = 60 },
                { id = 'phone',     label = 'Phone number',                          type = 'text',     min = 3, max = 20 },
                { id = 'age',       label = 'Character age',                         type = 'number',   min = 18, max = 80 },
                { id = 'history',   label = 'Character background',                  type = 'textarea', min = 40, max = 1000 },
                { id = 'why',       label = 'Why do you want to be a police officer?', type = 'textarea', min = 30, max = 800 },
                { id = 'record',    label = 'Do you have a criminal record in the city?', type = 'select', options = { 'No', 'Yes, minor', 'Yes, serious' } },
            },
        },
        {
            id = 'sahp', title = 'San Andreas Highway Patrol', icon = '🏍️', group = 'Emergency services',
            description = 'Patrol the highways as a trooper.',
            webhook = '', color = 0x0f766e, open = true,
            fields = {
                { id = 'character', label = 'Character name',           type = 'text',     min = 3, max = 60 },
                { id = 'phone',     label = 'Phone number',             type = 'text',     min = 3, max = 20 },
                { id = 'age',       label = 'Character age',            type = 'number',   min = 18, max = 80 },
                { id = 'history',   label = 'Character background',     type = 'textarea', min = 40, max = 1000 },
                { id = 'why',       label = 'Why do you want to join?', type = 'textarea', min = 30, max = 800 },
            },
        },
        {
            id = 'lafd', title = 'Fire and Medical (LAFD / EMS)', icon = '🚒', group = 'Emergency services',
            description = 'Save lives as a firefighter or paramedic.',
            webhook = '', color = 0xea580c, open = true,
            fields = {
                { id = 'character', label = 'Character name',                type = 'text',     min = 3, max = 60 },
                { id = 'phone',     label = 'Phone number',                  type = 'text',     min = 3, max = 20 },
                { id = 'age',       label = 'Character age',                 type = 'number',   min = 18, max = 80 },
                { id = 'role',      label = 'Which role are you applying for?', type = 'select', options = { 'Firefighter', 'Paramedic', 'Either' } },
                { id = 'history',   label = 'Character background',          type = 'textarea', min = 40, max = 1000 },
                { id = 'why',       label = 'Why do you want to join?',      type = 'textarea', min = 30, max = 800 },
            },
        },
        {
            id = 'faction', title = 'Faction application', icon = '🎭', group = 'Civilian',
            description = 'Apply to lead or join an approved faction.',
            webhook = '', color = 0x475569, open = true,
            fields = {
                { id = 'character', label = 'Character name',                type = 'text',     min = 3, max = 60 },
                { id = 'faction',   label = 'Faction name',                  type = 'text',     min = 2, max = 60 },
                { id = 'concept',   label = 'Faction concept and story',     type = 'textarea', min = 60, max = 1500 },
                { id = 'members',   label = 'Who will be in it?',            type = 'textarea', min = 10, max = 600 },
                { id = 'rules',     label = 'Which server rules matter most for your faction?', type = 'textarea', min = 20, max = 600 },
            },
        },
    },

    mailFrom = { name = 'Los Santos Careers', email = 'noreply@lscareers.co.uk' },
}
