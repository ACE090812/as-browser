Browser.defineSite('serverinfo', {
    title       = 'Life In The 90s',
    description = T('serverinfo.description'),
    keywords    = Browser.words(T('serverinfo.keywords')),
    category    = T('serverinfo.category'),
    icon        = '📖',
    color       = '#7c3aed',
    pages = {
        { path = '/rules',     title = T('serverinfo.page.rules.title'),     description = T('serverinfo.page.rules.description'),     keywords = Browser.words(T('serverinfo.page.rules.keywords')) },
        { path = '/staff',     title = T('serverinfo.page.staff.title'),     description = T('serverinfo.page.staff.description'),     keywords = Browser.words(T('serverinfo.page.staff.keywords')) },
        { path = '/changelog', title = T('serverinfo.page.changelog.title'), description = T('serverinfo.page.changelog.description'), keywords = Browser.words(T('serverinfo.page.changelog.keywords')) },
        { path = '/discord',   title = T('serverinfo.page.discord.title'),   description = T('serverinfo.page.discord.description'),   keywords = Browser.words(T('serverinfo.page.discord.keywords')) },
    },
})

Browser.handler('serverinfo', 'info', function()
    return Config.serverinfo
end)
