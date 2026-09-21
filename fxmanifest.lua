fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-browser'
author 'you'
description 'In-game web browser for sd-phone with built-in websites: server info, Los Santos Government, CoverCompare and Los Santos Careers. Each site can be switched on or off in config.lua.'
version '1.2.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/locale.lua',
    'locales/*.lua',
}

-- Order matters: every site's config.lua loads before any site's server.lua. The per-site config
-- files are SERVER ONLY (they can hold Discord webhook URLs), so they are deliberately not in
-- `files` below and are never sent to players.
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/vehicles.lua',
    'server/main.lua',
    'sites/**/config.lua',
    'sites/**/server.lua',
    'sites/**/server_*.lua',   -- extra server files for a site, e.g. sites/gov/server_passport.lua
}

client_scripts {
    'client/main.lua',
}

-- The browser shell: sd-phone frames this page inside the phone. Websites are separate pages
-- under sites/<name>/ that the shell loads inside itself.
ui_page 'ui/index.html'

-- Only web assets are listed, never .lua, so server configs stay on the server.
files {
    'ui/**/*',
    'sdk/*',
    'sites/**/*.html',
    -- Sites that ship their own images or scripts: add 'sites/**/*.css', 'sites/**/*.js', 'sites/**/*.png' etc.
    -- Never add .lua here, site configs can hold webhooks.
}

dependencies {
    'ox_lib',
    'sd-phone',
    'oxmysql',
}
