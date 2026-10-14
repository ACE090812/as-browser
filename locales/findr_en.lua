-- English text for Findr (sites/findr).
Locales = Locales or {}
Locales['en'] = Locales['en'] or {}

local L = {
    ['findr.description'] = 'Search the Los Santos web: sites, news, marketplace adverts and pictures.',
    ['findr.keywords'] = 'findr search engine find look up google web',
    ['findr.category'] = 'Search',
    ['findr.placeholder'] = 'Search Findr or type an address',
    ['findr.search'] = 'Search',
    ['findr.trending'] = 'Trending searches',
    ['findr.recent'] = 'Your recent searches',
    ['findr.clear'] = 'Clear',
    ['findr.remove'] = 'Remove',
    ['findr.results.one'] = '1 result',
    ['findr.results.other'] = '%d results',
    ['findr.tab.all'] = 'All',
    ['findr.tab.sites'] = 'Sites',
    ['findr.tab.news'] = 'News',
    ['findr.tab.market'] = 'Marketplace',
    ['findr.tab.images'] = 'Images',
    ['findr.noResults'] = 'No results for "%s"',
    ['findr.noResultsHint'] = 'Check the spelling, or try different words.',
    ['findr.noTab'] = 'Nothing here for "%s" yet.',
    ['findr.more'] = 'See all %d',
    ['findr.sug.recent'] = 'Recent',
    ['findr.sug.trending'] = 'Trending',
    ['findr.sug.site'] = 'Site',
    ['findr.results.title'] = '%s - Findr',
    ['findr.err.load'] = 'Findr could not search right now. Try again.',
    ['findr.tagline'] = 'Find anything in Los Santos',
}

for k, v in pairs(L) do Locales['en'][k] = v end
