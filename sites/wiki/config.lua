-- Server Wiki: guides, rules and how-tos. SERVER ONLY. Edit the pages below to match YOUR server, they are examples.
--
-- Page text (`body`) uses a small, safe markup:
--   ## Heading        ### Smaller heading
--   - bullet          1. numbered
--   > a highlighted note
--   **bold**  *italic*  `code`
--   [[page-id]]       link to another wiki page      [[page-id|shown text]]
--   [text](lsgov.co.uk/somewhere)      link to another in-game site (a domain, never a full https:// address)
--   | a | b |         a table; put a line like |---|---| under the first row to make it a header
--   ---               a divider
-- HTML is never run: anything else is shown as plain text.
-- Write each body between [=[ and ]=] (not [[ and ]]) so the [[page-id]] links do not end the text early.
Config.wiki = {
    name    = 'Server Wiki',
    tagline = 'Guides, rules and how things work',
    footer  = { 'Unofficial guides. The server rules always come first.' },

    -- Text on the home page above the categories.
    intro = 'New to the city? Start with the Getting started guide, then look around the categories below.',
    -- Pages shown as "Popular" on the home page (ids from `pages`).
    featured = { 'getting-started', 'jobs-overview', 'driving-and-vehicles' },
    recentCount = 5,          -- "Recently updated" list length on the home page

    categories = {
        { id = 'basics',   label = 'The basics', icon = '🧭' },
        { id = 'jobs',     label = 'Jobs',       icon = '🧰' },
        { id = 'vehicles', label = 'Vehicles',   icon = '🚗' },
        { id = 'rules',    label = 'Rules',      icon = '📜' },
    },

    -- id: letters, numbers, - and _ only. updated: 'YYYY-MM-DD' (shown on the page, newest first on the home page).
    pages = {
        {
            id = 'getting-started', title = 'Getting started', category = 'basics', updated = '2026-09-21',
            summary = 'Your first hour in the city: phone, money, jobs and getting around.',
            body = [=[
Welcome to Los Santos. This is a quick guide to your first hour.

## First steps
1. Open your **phone**. The Browser app opens the in-game websites.
2. Check your bank balance. Your first pay comes from your job.
3. Look at [[jobs-overview|the jobs guide]] and pick something to try.
4. Read the [[rules-summary|rules summary]] before you start roleplaying.

## Handy websites
| Site | What it does |
|---|---|
| [Los Santos Government](lsgov.co.uk) | Licences, vehicle tax, MOT bookings, benefits |
| [LS Plates](lsplates.co.uk) | Personalised number plates |
| [LS Vehicle Check](lsvehiclecheck.co.uk) | History report on any vehicle |
| [LS Weather](lsweather.co.uk) | Current weather and the outlook |
| [LS Tickets](lstickets.co.uk) | Events and tickets |

> Tip: bookmark the sites you use most from the browser menu.
]=],
        },
        {
            id = 'jobs-overview', title = 'Jobs overview', category = 'jobs', updated = '2026-09-18',
            summary = 'How jobs work and where to find work.',
            body = [=[
Jobs are how most players earn. Some jobs are open to everyone and some need an application.

## Finding work
- Browse open roles and apply on [Los Santos Careers](lscareers.co.uk).
- Some jobs are player-run businesses. Ask the owner in the city.
- Unemployed players can claim benefits on the [government site](lsgov.co.uk).

## Working for a business
Your boss sets your grade. Higher grades can do more, such as ordering parts or running events.

See also: [[driving-and-vehicles]].
]=],
        },
        {
            id = 'driving-and-vehicles', title = 'Driving and vehicles', category = 'vehicles', updated = '2026-09-15',
            summary = 'Owning, registering, taxing and looking after a vehicle.',
            body = [=[
Every vehicle has a registration plate. Keep it taxed and, if it needs one, tested.

## Owning a vehicle
- Buy from a dealership or another player.
- Check a used car first with [LS Vehicle Check](lsvehiclecheck.co.uk): owners, plate changes and warnings.
- Vehicle tax and MOT bookings are on [the government site](lsgov.co.uk).

## Personalised plates
You can buy a personalised registration and put it on your vehicle at [LS Plates](lsplates.co.uk). Your vehicle keeps its history.

## Keys
You need the key to lock, unlock and start your vehicle. If you change the plate, your keys update with it.
]=],
        },
        {
            id = 'rules-summary', title = 'Rules summary', category = 'rules', updated = '2026-09-10',
            summary = 'The short version of the server rules. Replace this with your own.',
            body = [=[
> This page is a placeholder. Put your real rules here, or a short version that links to your Discord.

## The short version
1. Treat other players with respect.
2. Stay in character and use common sense.
3. No cheating, exploiting bugs or abusing the economy.
4. Follow instructions from staff.

Questions? See [[contacting-staff]].
]=],
        },
        {
            id = 'contacting-staff', title = 'Contacting staff', category = 'rules', updated = '2026-09-10',
            summary = 'How to get help from the team.',
            body = [=[
If something is broken or someone is breaking the rules, tell staff.

- In the city: use the report command or ask in the help channel.
- Outside the city: open a ticket on the community Discord.

Give your character name, what happened and roughly when.
]=],
        },
    },
}
