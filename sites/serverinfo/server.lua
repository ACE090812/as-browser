Browser.defineSite('serverinfo', {
    title       = 'Life In The 90s',
    description = 'Server rules, the staff team, the changelog and our Discord link.',
    keywords    = { 'rules', 'rulebook', 'staff', 'team', 'changelog', 'updates', 'discord', 'server', 'info', 'help', 'support' },
    category    = 'Server',
    icon        = '📖',
    color       = '#7c3aed',
    pages = {
        { path = '/rules',     title = 'Server rules',  description = 'The rulebook for the city.',          keywords = { 'rulebook', 'roleplay', 'law', 'ban' } },
        { path = '/staff',     title = 'Staff team',    description = 'Meet the people who run the server.', keywords = { 'admin', 'moderator', 'owner', 'support' } },
        { path = '/changelog', title = 'Changelog',     description = 'What is new on the server.',          keywords = { 'updates', 'patch', 'version', 'news' } },
        { path = '/discord',   title = 'Discord',       description = 'Join the community Discord.',         keywords = { 'invite', 'community' } },
    },
})

Browser.handler('serverinfo', 'info', function()
    return Config.serverinfo
end)
