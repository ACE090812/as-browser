-- English text for the Server Wiki website (sites/wiki). The pages themselves live in sites/wiki/config.lua.
Locales = Locales or {}
Locales['en'] = Locales['en'] or {}

local L = {
    ['wiki.name'] = 'Server Wiki',
    ['wiki.description'] = 'Guides, rules and how-tos for the server. Search for anything.',
    ['wiki.keywords'] = 'wiki guide guides help rules how to new player tutorial faq documentation',
    ['wiki.category'] = 'Reference',
    ['wiki.search'] = 'Search the wiki',
    ['wiki.searchGo'] = 'Search',
    ['wiki.popular'] = 'Popular guides',
    ['wiki.recent'] = 'Recently updated',
    ['wiki.categories'] = 'Browse by topic',
    ['wiki.pages.one'] = '%d page',
    ['wiki.pages.other'] = '%d pages',
    ['wiki.updated'] = 'Updated %s',
    ['wiki.related'] = 'More in this topic',
    ['wiki.results'] = 'Results for "%s"',
    ['wiki.noResults'] = 'Nothing matches that. Try a different word.',
    ['wiki.home'] = 'Wiki home',
    ['wiki.allPages'] = 'All pages',
    ['wiki.err.notFound'] = 'That page does not exist.',
    ['wiki.err.load'] = 'The wiki could not be loaded.',
}

for k, v in pairs(L) do Locales['en'][k] = v end
