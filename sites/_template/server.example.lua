-- Step 3 of adding a site. Copy to sites/<yourname>/server.lua and rename the site key below.
-- The key must also be added to Config.Sites in config.lua, with a domain and enabled = true.

Browser.defineSite('example', {
    title       = 'Example Site',
    description = 'One line about what the site does. Shown in search results.',
    keywords    = { 'example', 'demo', 'template' },   -- words that should find this site
    category    = 'General',
    icon        = '🌐',
    color       = '#2563eb',
    pages = {                                           -- extra pages that appear in search
        { path = '/about', title = 'About', description = 'About this site', keywords = { 'info' } },
    },
})

-- A request the page can make with Site.call('hello', {...}).
-- Return a value to answer, or return nil plus a message to show an error.
-- Always check the data: it comes from the player's machine.
Browser.handler('example', 'hello', function(src, data)
    local name = tostring(data.name or ''):sub(1, 40)
    if name == '' then return nil, 'Tell us your name.' end
    return { message = ('%s, %s!'):format((Config.example and Config.example.greeting) or 'Hello', name) }
end)
