-- English text for the LS Weather website (sites/weather). Weather names, advice and regions live in sites/weather/config.lua.
Locales = Locales or {}
Locales['en'] = Locales['en'] or {}

local L = {
    ['weather.name'] = 'LS Weather',
    ['weather.description'] = 'Current weather and the outlook for Los Santos, Blaine County and Mount Chiliad.',
    ['weather.keywords'] = 'weather forecast rain sun storm temperature wind fog snow outlook conditions',
    ['weather.category'] = 'Weather',
    ['weather.now'] = 'Right now',
    ['weather.feelsLike'] = 'Wind %s %s',
    ['weather.humidity'] = 'Humidity %s%%',
    ['weather.wind'] = 'Wind',
    ['weather.humidityLabel'] = 'Humidity',
    ['weather.outlook'] = 'Outlook',
    ['weather.outlookNote'] = 'The outlook is an estimate and can change.',
    ['weather.live'] = 'Live conditions',
    ['weather.estimated'] = 'Estimated conditions',
    ['weather.alert'] = 'Weather warning',
    ['weather.alertLater'] = '%s is expected later. Plan your journey.',
    ['weather.advice'] = 'Driving advice',
    ['weather.error'] = 'The forecast could not be loaded.',
    ['weather.retry'] = 'Try again',
    ['weather.updated'] = 'Updated %s',
}

for k, v in pairs(L) do Locales['en'][k] = v end
