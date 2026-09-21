-- LS Weather: current conditions and a short forecast. SERVER ONLY. Edit freely.
--
-- Where the "now" weather comes from (Config.weather.source):
--   'auto'        use whatever your weather script publishes (see globalStateKeys), else a simulated forecast
--   'globalstate' read GlobalState[<key>] (qb-weathersync, Renewed-Weathersync, cd_easytime and most others publish one)
--   'function'    call Config.weather.current() below, it returns a GTA weather name such as 'RAIN'
--   'simulated'   no weather script: a believable forecast that is the same for every player and changes over time
-- The forecast for LATER hours is always an outlook worked out here (weather scripts do not publish their plans), so it
-- is shown as "outlook". Set showForecast = false to show only the current conditions.
Config.weather = {
    name    = 'LS Weather',
    tagline = 'Forecasts for Los Santos and Blaine County',
    footer  = { 'Forecasts are a guide only', 'Weather changes quickly on the coast' },

    units    = 'C',            -- 'C' or 'F' (use 'F' and windUnit = 'mph' for a US server)
    windUnit = 'mph',          -- 'mph' or 'kmh'

    source = 'auto',
    globalStateKeys = { 'weather', 'currentWeather', 'Weather' },
    -- current = function() return GlobalState.myWeather end,   -- for source = 'function'

    showForecast = true,
    stepMinutes  = 60,         -- real minutes between forecast slots (and how often the simulated weather can change)
    forecastSteps = 8,         -- slots shown
    seed = 20260921,           -- change it to get a different simulated pattern

    -- Places on the tab bar. tempOffset is added to the temperature (in your `units`), wind to the wind speed.
    regions = {
        { id = 'ls',       label = 'Los Santos',      tempOffset = 0,  wind = 0 },
        { id = 'blaine',   label = 'Blaine County',   tempOffset = -2, wind = 3 },
        { id = 'mountain', label = 'Mount Chiliad',   tempOffset = -8, wind = 10 },
    },

    -- Every GTA weather type. temp / wind / humidity are ranges in Celsius / mph / percent (temperatures are converted when
    -- units = 'F'). `severe = true` shows a warning banner. `weight` is how often the simulated weather picks it.
    types = {
        EXTRASUNNY = { label = 'Sunny',            icon = '☀️', temp = { 24, 34 }, wind = { 2, 8 },   humidity = { 25, 45 }, weight = 5, advice = 'Hot and dry. Take water and keep to the shade.' },
        CLEAR      = { label = 'Clear',            icon = '🌤️', temp = { 18, 27 }, wind = { 2, 10 },  humidity = { 35, 55 }, weight = 6, advice = 'Good driving conditions.' },
        CLOUDS     = { label = 'Cloudy',           icon = '⛅', temp = { 15, 23 }, wind = { 5, 14 },  humidity = { 45, 65 }, weight = 4, advice = 'Dry but overcast.' },
        OVERCAST   = { label = 'Overcast',         icon = '☁️', temp = { 13, 20 }, wind = { 6, 16 },  humidity = { 55, 75 }, weight = 3, advice = 'Grey skies, rain is possible later.' },
        CLEARING   = { label = 'Clearing',         icon = '🌦️', temp = { 14, 21 }, wind = { 6, 15 },  humidity = { 60, 80 }, weight = 2, advice = 'Roads may still be wet.' },
        RAIN       = { label = 'Rain',             icon = '🌧️', temp = { 11, 18 }, wind = { 8, 20 },  humidity = { 75, 92 }, weight = 3, advice = 'Wet roads. Slow down and leave a bigger gap.' },
        THUNDER    = { label = 'Thunderstorm',     icon = '⛈️', temp = { 12, 19 }, wind = { 15, 35 }, humidity = { 80, 95 }, weight = 1, severe = true, advice = 'Storm warning. Avoid driving if you can.' },
        SMOG       = { label = 'Smog',             icon = '🌫️', temp = { 20, 30 }, wind = { 0, 5 },   humidity = { 40, 60 }, weight = 1, advice = 'Poor air quality. Take care outdoors.' },
        FOGGY      = { label = 'Fog',              icon = '🌁', temp = { 8, 15 },  wind = { 0, 6 },   humidity = { 88, 99 }, weight = 1, severe = true, advice = 'Fog warning. Low visibility, use your lights.' },
        NEUTRAL    = { label = 'Settled',          icon = '🌥️', temp = { 16, 24 }, wind = { 3, 10 },  humidity = { 45, 65 }, weight = 1, advice = 'Calm and settled.' },
        SNOW       = { label = 'Snow',             icon = '🌨️', temp = { -4, 2 },  wind = { 5, 15 },  humidity = { 70, 90 }, weight = 0, severe = true, advice = 'Snow on the roads. Drive carefully.' },
        BLIZZARD   = { label = 'Blizzard',         icon = '❄️', temp = { -10, -2 }, wind = { 25, 50 }, humidity = { 80, 95 }, weight = 0, severe = true, advice = 'Blizzard warning. Do not travel.' },
        SNOWLIGHT  = { label = 'Light snow',       icon = '🌨️', temp = { -2, 4 },  wind = { 3, 12 },  humidity = { 65, 85 }, weight = 0, advice = 'Light snow, slippery in places.' },
        XMAS       = { label = 'Snow',             icon = '❄️', temp = { -3, 3 },  wind = { 3, 10 },  humidity = { 65, 85 }, weight = 0, advice = 'Snow on the ground.' },
        HALLOWEEN  = { label = 'Eerie',            icon = '🌫️', temp = { 8, 14 },  wind = { 4, 12 },  humidity = { 70, 90 }, weight = 0, advice = 'A spooky night.' },
    },
}
