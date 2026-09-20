# as-browser

An in-game web browser for sd-phone. Players open the Browser app, type an address or search, and visit websites that live inside the game. Every site is a folder in `sites/` and each one can be turned on or off from `config.lua`.

Built-in sites (all fictional, all roleplay):

| Site | Default address | What it does |
| --- | --- | --- |
| serverinfo | `lifeinthe90s.co.uk` | Home page, rules, staff, changelog, Discord link |
| gov | `lsgov.co.uk` | Los Santos Government: check any vehicle, tax your vehicle, passport applications (`as-passport`), driving licence, council tax, birth certificates (`as-birthcert`), fines (`as-fines`), benefits, marriage and business registration (`as-registry`), placeholder for MOT |
| insurance | `covercompare.co.uk` | Compare quotes for a vehicle you own and buy cover |
| jobs | `lscareers.co.uk` | Application forms that post to Discord |

## Install

1. Put the `as-browser` folder in `resources/[phone]/`.
2. Start it after `ox_lib`, `oxmysql` and `sd-phone`:

   ```
   ensure ox_lib
   ensure oxmysql
   ensure sd-phone
   ensure as-browser
   ```

3. Let admins use the on/off command (optional):

   ```
   add_ace group.admin command.browsersite allow
   ```

4. Open `sites/jobs/config.lua` and paste a Discord webhook URL into each form you want open. A form without a webhook shows as "Closed".
5. Edit the placeholder text in `sites/serverinfo/config.lua` (rules, staff, changelog, Discord invite).

Tables are created automatically, all starting with `browser_`.

## Turning sites on and off

`config.lua`, then `Config.Sites`. Set `enabled = false` and the site disappears from search, bookmarks and the address bar. Change `domain` to change the address.

Live, without a restart (lasts until the next restart):

```
/browsersite gov off
/browsersite gov on
/browsersite            (lists every site and its state)
```

## Vehicles, tax and insurance

The vehicle checker, tax and insurance all read your owned vehicles table. It is detected from your framework (`player_vehicles` for qbx/qb, `owned_vehicles` for ESX). If yours is different, fill in `Config.vehicleTable` in `config.lua`.

A vehicle's class (motorcycle, compact, sports and so on) comes from its category in your vehicle list. Tax rates are set per class in `sites/gov/config.lua`, insurance base prices per class in `sites/insurance/config.lua`. Motorcycles start at 25. The other rates are suggestions.

Tax lasts 7 days. A vehicle the system has not seen before starts taxed for `graceDays`, so nothing is untaxed on day one. A vehicle can be taxed again once it has `renewWindowDays` or fewer days left.

### MOT (for your MOT script)

The MOT is off until your script exists. When it does, call this after each test and set `Config.gov.mot.enabled = true` in `sites/gov/config.lua`:

```lua
-- passed (bool), expiry (unix time, required when passed), details (optional text)
exports['as-browser']:setMotResult(plate, true, os.time() + 30 * 86400, 'All clear')
```

The vehicle checker then shows MOT status and history, and the MOT booking page can be pointed at your script.

### For police, MDT and ANPR scripts

```lua
local status = exports['as-browser']:getVehicleStatus('AB12CDE')
-- { plate, make, model, colour, class, exempt, tax = { status, expiry, rate }, mot = { enabled, status, expiry }, insured }

local legal, reasons = exports['as-browser']:isRoadLegal('AB12CDE')
-- true, or false with { 'untaxed', 'no_mot' }

local insured, endsAt = exports['as-browser']:isInsured('AB12CDE')
```

These return `nil` when the matching site is switched off.

## Insurance

Roleplay only. Buying a policy takes the price from the bank account, saves a certificate to Files, sends a confirmation to Mail and adds a bank receipt to the phone. Providers, prices, covers and extras are all in `sites/insurance/config.lua`. Prices are worked out on the server.

## Jobs and applications

Forms are defined in `sites/jobs/config.lua`. Webhook URLs stay in that server-only file and are never sent to the page. Each character can send one application per form every 24 hours (`cooldownHours`). Applicant text cannot ping anyone. Set `mentionRole` on a form to ping one Discord role.

## Passports

The government site has a live passport service (`/passport`): choose a type, pick a Postal Prime locker, pay, and follow the application. All the logic is in the separate `as-passport` resource, and the pages only work while it is running (otherwise they say passports are not available). The website side is `sites/gov/server_passport.lua`. Any `sites/<name>/server_*.lua` file is loaded after all the `server.lua` files, so a site can be split into several server files.

## Birth certificates

The government site has a live birth certificate service (`/birth-certificate`): the player orders a copy of their own certificate (£15, about 30 minutes, picked Postal Prime locker) and can order more copies later. Everything lives in the separate `as-birthcert` resource; the site side is `sites/gov/server_birthcert.lua`. If the resource is stopped the pages say it is not available. The "Change your name" and "Apply for social housing" placeholders were removed. Categories with no services in them are no longer shown on the home page, so the Housing and Crime categories are hidden until you add a service to them.

## Fines

The government site has a live fines page (`/pay-fine`): unpaid fines, pay one or all from the bank, and recently paid ones. The fines, the `/fine` command for police and the exports for other scripts live in the separate `as-fines` resource; the site side is `sites/gov/server_fines.lua`. If the resource is stopped the page says it is not available.

## Benefits

The government site has a live benefits service (`/benefits`). A character with a qualifying job (`jobs`, default `unemployed`) starts a claim on the site, and is then paid `amount` into the bank for every `intervalMinutes` they spend online while they still qualify. Taking a job pauses the payments and they carry on if the job is lost; the player can stop the claim on the site. Settings are in `sites/gov/config.lua` under `benefits`; the code is `sites/gov/server_benefits.lua` and claims are kept in `browser_benefits`. Time online is counted once a minute and saved, so it survives relogging.

## Marriage and business registration

Live at `/marriage` and `/register-business`. The rules, fees, records and certificate items live in the separate `as-registry` resource; the site side is `sites/gov/server_registry.lua`.

## Council tax

The government site has a live council tax service (`/council-tax`). Every home a character owns (or rents, in housing scripts where the renter is the owner) gets a bill every `periodDays`, worked out as a percentage of the home's value (`ratePercent`, kept between `minBill` and `maxBill`; rented homes pay the flat `rentedBill`). A home the system has not seen before starts paid up for `graceDays`. Unpaid bills stack up as arrears, shown on the site and as a phone reminder, and nothing else happens to the player. Paying clears everything due, or the next bill can be paid early inside `payAheadDays`. A new owner never inherits the previous owner's arrears.

Settings are in `sites/gov/config.lua` under `council`. The homes are read from your housing script: `housing = 'auto'` checks for qbx_properties, ps-housing and qb-houses, or set `'custom'` and fill in the table and column names. The console prints which one it found the first time a player opens the page. The code is in `sites/gov/server_council.lua`, and payments are kept in `browser_council_tax` and `browser_council_payments`.

## Driving licence

The government site has a live driving licence service (`/driving-licence`): the player's licence (status, categories, penalty points, test history), booking and paying for theory and practical tests, and ordering a replacement licence (delivered to a Postal Prime locker, like passports). The rules and fees live in the `as-drivingschool` resource (`Config.Fees`, `Config.Booking`); the site only passes requests through and adds the bank statement line and confirmation email (`sites/gov/server_licence.lua`). The resource name and email sender are in `sites/gov/config.lua` under `licence`. If the resource is stopped the pages say the service is not available. MOT results from that script show up in the vehicle checker through `setMotResult`; booking an MOT on the site is not part of this service (`mot.enabled` stays `false`).

## Adding your own site

1. Copy `sites/_template` to `sites/mysite`.
2. Rename `server.example.lua` to `server.lua` (and `config.example.lua` to `config.lua` if you need settings), and change the key from `example` to `mysite`.
3. Add a line to `Config.Sites` in `config.lua`: `mysite = { enabled = true, domain = 'mysite.co.uk' }`.
4. Edit `index.html`.

Pages include `/sdk/site.css` and `/sdk/site.js`, which give you `Site.call`, `Site.go`, `Site.title`, `Site.copy` and more. Read the top of `sdk/site.js` for the full list. The page only talks to the server through `Site.call(name, data)`, and your `Browser.handler` decides what to allow, so always check the data you get.

### Sites from another resource

A separate resource can add a site without touching this one:

```lua
exports['as-browser']:registerSite({
    domain = 'example.co.uk', title = 'Example', description = '...', keywords = { 'example' },
    ui = 'my-resource/html/index.html',   -- must be listed in that resource's `files`
})
exports['as-browser']:registerHandler('example.co.uk', 'hello', function(src, data) return { ok = true } end)
```

The page should load `https://cfx-nui-as-browser/sdk/site.js` and `.css`. The site is removed when that resource stops.

## Saving logins to Passwords (optional)

sd-phone's Passwords app only accepts a fixed list of app ids and has no public export, so saving a login from a website needs a small edit to sd-phone: add `'browser'` to the list of accepted app ids (`ALL_APPS`) in its Passwords code. Then set `Config.passwords.enabled = true` in `config.lua`. Until then `Site.saveLogin` does nothing and sites should not rely on it.

## Files

- `config.lua` shared settings (sent to players, no secrets)
- `sites/*/config.lua` server-only site settings and secrets
- `server/` framework bridge, vehicle lookups, site registry
- `client/` phone app registration
- `ui/` the browser shell (tabs, address bar, search, bookmarks, history)
- `sdk/` the toolkit every site page uses
- `sites/` the websites
