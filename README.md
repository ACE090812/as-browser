# as-browser

An in-game web browser for sd-phone. Players open the Browser app, type an address or search, and visit websites that live inside the game. Every site is a folder in `sites/` and each one can be turned on or off from `config.lua`.

Built-in sites (all fictional, all roleplay):

| Site | Default address | What it does |
| --- | --- | --- |
| serverinfo | `lifeinthe90s.co.uk` | Home page, rules, staff, changelog, Discord link |
| gov | `lsgov.co.uk` | Los Santos Government: check any vehicle, tax your vehicle, passport applications (`as-passport`), driving licence (`as-drivingschool`), council tax, birth certificates (`as-birthcert`), fines (`as-fines`), benefits, marriage and business registration (`as-registry`), MOT booking (needs `as-computer`) |
| insurance | `covercompare.co.uk` | Compare quotes for a vehicle you own and buy cover |
| jobs | `lscareers.co.uk` | Application forms that post to Discord |
| plates | `lsplates.co.uk` | LS Plates: buy, fit, move, take off and sell personalised number plates (see [LS Plates](#ls-plates-lsplatescouk)) |
| vehiclecheck | `lsvehiclecheck.co.uk` | LS Vehicle Check: vehicle history reports in Basic / Standard / Full plans |
| parts | LS Parts Direct | Parts shop for vehicles and mechanics |
| bank | `lsbank.co.uk` | LS Bank: online banking that shares the phone's Wallet (see [LS Bank](#ls-bank-lsbankcouk)) |

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

## MOT booking

`lsgov.co.uk/book-mot` lets players book, change and cancel an MOT at a garage. It needs the `as-computer` resource running: garages, time slots, the fee and the bookings are all set there (`config/apps/booking.lua` and the `booking` table on each location). This resource adds the pages, the bank statement line and the emails (booking confirmed / changed / cancelled, a reminder shortly before, and an "MOT runs out soon" email). Switch it off with `Config.gov.scripts.motbooking = false`; `Config.gov.motBooking` in `sites/gov/config.lua` holds the resource name, sender and `expiryReminderDays`.

## Government site at a glance

Everything on `lsgov.co.uk`. Each service that has its own resource only works while that resource is running; if it is stopped the page says the service is not available and nothing else breaks. The site-side code for each one is a `sites/gov/server_*.lua` file, loaded automatically.

| Service | Page | Backed by | Main settings |
| --- | --- | --- | --- |
| Check a vehicle | `/vehicle-checker` | `as-browser` | `sites/gov/config.lua` |
| Tax a vehicle | `/tax-vehicle` | `as-browser` | `sites/gov/config.lua` (`tax`, `graceDays`, `renewWindowDays`) |
| Passports | `/passport` | `as-passport` | that resource's `config.lua` |
| Driving licence, theory and practical tests, replacement | `/driving-licence` | `as-drivingschool` | `Config.Fees`, `Config.Booking`; `licence` in `sites/gov/config.lua` |
| Council tax | `/council-tax` | `as-browser` | `council` in `sites/gov/config.lua` |
| Birth certificate | `/birth-certificate` | `as-birthcert` | that resource's `config.lua` (price, wait, delivery) |
| Pay a fine | `/pay-fine` | `as-fines` | that resource's `config.lua` (jobs, limits, `/fine`) |
| Benefits | `/benefits` | `as-browser` | `benefits` in `sites/gov/config.lua` |
| Marriage | `/marriage` | `as-registry` | that resource's `config.lua` (`marriage`) |
| Register a business | `/register-business` | `as-registry` | that resource's `config.lua` (`business`) |
| Book an MOT test | `/book-mot` | `as-computer` | `motBooking` in `sites/gov/config.lua`; garages and fee in as-computer |
| Penalty points and fines | `/penalties` | `as-drivingschool` and/or `as-fines` | nothing to set (`scripts.penalties`) |
| Personalised number plates | link to LS Plates (`lsplates.co.uk`) | `as-browser` (+ `as-computer` for MOT records) | `sites/plates/config.lua` |
| Criminal record check (DBS) | `/dbs` | `as-browser` | `dbs` in `sites/gov/config.lua` |
| Vehicle history check | link to LS Vehicle Check (`lsvehiclecheck.co.uk`) | `as-browser` (+ `as-computer` for MOT mileage) | `sites/vehiclecheck/config.lua` |

The home page groups services into categories (Vehicles, Driving, Life, Work, Crime and so on). A category with no services in it is hidden, so Housing does not show until you add a service to it. Services and categories are listed in `sites/gov/config.lua`; set a service's `status = 'placeholder'` (shows "not available yet") or remove it to take it off the site.

### Turning services on and off

Not using one of the custom scripts? Switch it off in `sites/gov/config.lua`, in the `scripts` block near the top:

```lua
scripts = {
    passport  = true,   -- as-passport
    licence   = true,   -- as-drivingschool
    birthcert = true,   -- as-birthcert
    fines     = true,   -- as-fines
    registry  = true,   -- as-registry (marriage and business registration)
    council   = true,   -- built in council tax
    benefits  = true,   -- built in benefits
}
```

Set one to `false` and restart `as-browser`. Its services disappear from the home page, search and categories (a category left with nothing in it is hidden too), its pages stop working, and as-browser never calls that resource. A council or benefits switch set to `false` also stops the bills, payments and phone reminders. Everything else on the site carries on as normal. Each service in `services` has a `requires` key that points at its switch.

### Start order

Postal Prime must be running before the resources that deliver to lockers. `server.cfg`:

```
ensure ox_lib
ensure oxmysql
ensure ox_inventory        # or qb-inventory
ensure sd-phone
ensure as-postalprime
ensure as-browser
ensure as-passport
ensure as-drivingschool
ensure as-birthcert
ensure as-fines
ensure as-registry
```

`as-passport`, `as-drivingschool`, `as-birthcert`, `as-fines` and `as-registry` can start in any order after `as-browser`; the site finds them when a player uses the page. Skip the ones you do not want and their services show as not available.

### First-time setup checklist

1. Put every resource in `resources/[phone]/` (or wherever you keep them), add the `ensure` lines above, then `refresh` and start or restart. A changed `fxmanifest.lua` (new `files{}` entries) always needs `refresh` before the restart.
2. Restart `as-postalprime` once, after updating it, so `createParcel` accepts certificates. Restart `as-browser` after adding or changing any `sites/gov/server_*.lua` file.
3. Add the item definitions for the certificates. Each resource has an `install/` folder with a ready-made `ox_inventory` or `qb-inventory` entry and a PNG:
   - `as-birthcert/install/` for `birth_certificate`
   - `as-registry/install/` for `marriage_certificate` and `business_certificate`
   - passports and the driving licence follow their own resources' READMEs

   Paste the item entries into your inventory's items file and copy the PNGs into the inventory's images folder.
4. Set who can issue fines: `Config.jobs` in `as-fines/config.lua` (default `{ 'police' }`).
5. Set the jobs that can claim benefits (`benefits.jobs`, default `{ 'unemployed' }`) and check the rates.
6. Optional: paste Discord webhooks into `benefits.webhook` and the `webhook` setting of `as-fines`.

### Tables

Created automatically on start. `as-browser`: `browser_*` (including `browser_council_tax`, `browser_council_payments`, `browser_benefits`). `as-birthcert`: `as_birth_certs`. `as-fines`: `as_fines`. `as-registry`: `as_marriages`, `as_businesses`. The driving school's tables are listed in its README (`sql/dvla.sql` is applied on start).

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

### MOT (as-computer, or your own MOT script)

MOT results come from `as-computer`'s MOT Testing Service: with `pushMotResults` on (its default), every finished test is sent here and `Config.gov.mot.enabled = true` (the default in `sites/gov/config.lua`) makes the vehicle checker show MOT status and history. Booking is on `/book-mot` (see MOT booking above).

Using a different MOT script instead? Call this after each test and keep `Config.gov.mot.enabled = true`:

```lua
-- passed (bool), expiry (unix time, required when passed), details (optional text)
exports['as-browser']:setMotResult(plate, true, os.time() + 30 * 86400, 'All clear')
```

No MOT at all (a US server, say): set `Config.gov.mot.enabled = false` and `Config.gov.scripts.motbooking = false`, and remove the "Book an MOT test" service.

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

The government site has a live birth certificate service (`/birth-certificate`): the player orders a copy of their own certificate and can order more copies later. Defaults: £15 from the bank, about 30 minutes wait (`waitSeconds` 1800), delivered to a Postal Prime locker (`delivery.mode = 'locker'`, or `'inventory'` to hand it straight over). The certificate is the `birth_certificate` item; using it shows a parchment "Certificate of Birth" with name, date of birth, place of birth (`placeOfBirth`, default Los Santos) and a certificate number. Everything lives in the separate `as-birthcert` resource (see its README for `Config.price`, `waitSeconds`, `cooldownSeconds` and item names); the site side is `sites/gov/server_birthcert.lua`. If the resource is stopped the pages say it is not available.

For other scripts: `exports['as-birthcert']:hasCertificate(who)`, `getByNumber(number)` (for police or MDT lookups), `getState(source)` and `order(source, data)`. The "Change your name" and "Apply for social housing" placeholders have been removed from the site.

## Fines

The government site has a live fines page (`/pay-fine`): unpaid fines, pay one or all from the bank, and recently paid ones. The fines, the `/fine` command for police and the exports for other scripts live in the separate `as-fines` resource; the site side is `sites/gov/server_fines.lua`. If the resource is stopped the page says it is not available. Police (`Config.jobs`, on duty, `minGrade`) use `/fine [player id] [amount] [reason]` on a nearby player (`maxDistance`) and `/cancelfine [fine number]` (`cancelGrade` and above) to cancel one; the player gets a phone email and the payment shows in their bank statement. Paying one or all takes the money from the bank (a failed or raced payment is refunded).

For other scripts (MDT and so on): `exports['as-fines']:issueFine(who, { amount, reason, issuer })`, `getUnpaid(who)`, `getOwed(who)`, `cancelFine(id)`, `getState(source)` and `pay(source, data)`, where `who` is a server id or citizen id. Events: `as-fines:issued` and `as-fines:paid`. Details and arguments are in the `as-fines` README. Because the Crime category now contains Pay a fine, it shows on the home page.

## Benefits

The government site has a live benefits service (`/benefits`). A character with a qualifying job (`jobs`, default `unemployed`) fills in a short form: age group, where they live, partner, number of children, whether a health condition or disability limits their work, and a declaration that they are looking for work. The answers decide their rate, which is shown as a breakdown before they start the claim. The rate is worked out on the server from `rates` in `sites/gov/config.lua` (basic rate by age, plus housing, partner, per-child and disability amounts, up to `maxTotal`), never taken from the page. A character whose bank balance is over `savingsLimit` (default £16,000, 0 = off) cannot claim.

Once claiming they are paid their rate into the bank for every `intervalMinutes` spent online while they still have a qualifying job. Taking a job pauses the payments and they carry on if the job is lost. They can update their answers (the new rate applies from the next payment) or stop the claim on the site. Time online is counted once a minute and saved, so it survives relogging. The code is `sites/gov/server_benefits.lua`; claims are kept in `browser_benefits` (the `rate` and `answers` columns are added automatically). A claim made before rates existed is paid the lowest rate until the player updates their details.

## Marriage and business registration

Live at `/marriage` and `/register-business`. The rules, fees, records and certificate items live in the separate `as-registry` resource; the site side is `sites/gov/server_registry.lua`. If the resource is stopped the pages say it is not available.

**Marriage.** One player proposes on the site by entering their partner's full character name or server ID (the partner must be online); the partner opens the site and accepts or declines. Proposals expire after `proposalMinutes` (default 60) and can be withdrawn. The proposer needs the fee (`marriage.price`, default £50) in the bank when proposing and is charged when the partner accepts, and both get a `marriage_certificate` item. Extra copies cost `copyPrice` (default £10). A married player cannot propose to someone else. Using the item near another player (`showDistance`, default 3.0) shows it to them, and the card only opens for someone holding a certificate with that number. Ended marriages show an ENDED stamp.

**Register a business.** A player registers a company name, type and short description for `business.price` (default £250) and gets a `business_certificate` item. Names must be unique among active businesses, `maxPerPerson` (default 3) limits how many one character can own, and name and description lengths are limited (`nameMin`, `nameMax`, `descriptionMax`). It is a record only, with no shop or bank account. The owner can close the business on the site (the certificate then shows CLOSED and the name can be used again) and order copies for `copyPrice` (free if the original item could not be handed over). Business types are the `types` list in the config.

For other scripts: `exports['as-registry']:isMarried(who)`, `getSpouse(who)`, `endMarriage(who)` (for a divorce script or staff), `hasBusiness(who)`, `getBusinesses(who)` and `getBusiness(nameOrNumber)`. Events: `as-registry:businessRegistered` and `as-registry:businessClosed`. See the `as-registry` README for the full list and arguments.

## Council tax

The government site has a live council tax service (`/council-tax`). Every home a character owns (or rents, in housing scripts where the renter is the owner) gets a bill every `periodDays`, worked out as a percentage of the home's value (`ratePercent`, kept between `minBill` and `maxBill`; rented homes pay the flat `rentedBill`). A home the system has not seen before starts paid up for `graceDays`. Unpaid bills stack up as arrears, shown on the site and as a phone reminder, and nothing else happens to the player. Paying clears everything due, or the next bill can be paid early inside `payAheadDays`. A new owner never inherits the previous owner's arrears.

Settings are in `sites/gov/config.lua` under `council`. The homes are read from your housing script: `housing = 'auto'` checks for qbx_properties, ps-housing and qb-houses, or set `'custom'` and fill in the table and column names. The console prints which one it found the first time a player opens the page. The code is in `sites/gov/server_council.lua`, and payments are kept in `browser_council_tax` and `browser_council_payments`.

## Driving licence

The government site has a live driving licence service (`/driving-licence`): the player's licence (status, categories, penalty points, test history), booking and paying for theory and practical tests, and ordering a replacement licence (delivered to a Postal Prime locker, like passports). The rules and fees live in the `as-drivingschool` resource (`Config.Fees`, `Config.Booking`); the site only passes requests through and adds the bank statement line and confirmation email (`sites/gov/server_licence.lua`). The resource name and email sender are in `sites/gov/config.lua` under `licence`. If the resource is stopped the pages say the service is not available. MOT is separate: results come from `as-computer` (see MOT above) and booking is `/book-mot`.

## Penalty points and fines

`/penalties` shows the penalty points on the driving licence (from `as-drivingschool`) and the unpaid fines (from `as-fines`) on one page, and pays fines with the same request as `/pay-fine`. If only one of the two resources is running, that half is shown; if neither is, the page says it is unavailable. Nothing to configure. Code: `sites/gov/server_penalties.lua`.

## LS Plates (lsplates.co.uk)

Personalised plates have their own website (`plates` in `Config.Sites`, settings in `sites/plates/config.lua`). A plate is something a player **owns**:

- **Buy** a registration (price by length or pattern, `assignFee` to put it on a vehicle) and put it on a vehicle straight away, or keep it.
- **Fit / move / take off.** While a plate is on a vehicle the vehicle remembers its original registration. Taking the plate off, moving it to another vehicle, or selling it gives the vehicle its original registration back, in the same database transaction.
- **The vehicle keeps its records.** MOT history and status, tax, insurance, vehicle history, reminders and flags are moved to the new registration on every change, and `as-computer` is told (`exports['as-computer']:renamePlate`, needs as-computer 0.5.1+) so its MOT records and garage bookings follow.
- **Marketplace.** A player lists a plate at a price; other players buy it. The buyer pays the asking price, the seller receives it minus `market.feePercent` (default 5%, taken by nobody). Sellers are paid straight away when online, otherwise when they next are (nothing is lost or paid twice). Listing a plate that is on a vehicle takes it off first, and a listed plate cannot be fitted. A buyer can put it on a vehicle at the same time.
- Vehicles must be in a garage (`stateColumn`), not stolen, and can be re-plated once per `cooldownHours` (fitting only, taking a plate off is free).
- Existing personalised plates from the old government service are brought over automatically at start: their owners now own them as plates (the earlier registration becomes the original one).

Other resources can use `exports['as-browser']:isPlateReserved(plate)`, `isPlateAvailable(plate)`, `generatePlate([pattern])`, `getPlateInfo(plate)`, `getOriginalPlate(plate)`, `getPlayerPlates(citizenId)` and `findPlateConflicts()`; the server events `as-browser:plateChanged (oldPlate, newPlate, citizenId, source)` and `as-browser:plateSold (plate, sellerCitizenId, buyerCitizenId, price)`; and the hooks `onChanged` and `market.onSold`. **Read [Working with other scripts](#working-with-other-scripts-keys-dealerships-garages) before you go live**: vehicle keys, dealerships and used-car lots all store plates and need to agree with LS Plates. Tables: `browser_plate_assets`, `browser_plate_listings`, `browser_plate_sales`, `browser_plate_payouts`, `browser_plate_log`.

The government site still lists the service and sends players to LS Plates.

## Working with other scripts (keys, dealerships, garages)

A plate is written in several places: `player_vehicles.plate`, the JSON in `player_vehicles.mods`, and, depending on your scripts, inside **key items**, key tables, garage tables and used-car tables. LS Plates changes `player_vehicles` and its own tables itself. Everything else has to be told. This section covers each kind of script. The examples we tested against are named; every other script is covered by the generic rule underneath.

Which scripts do what is set in `sites/plates/config.lua`. Nothing in this section changes anything until a player changes a plate.

### 0. Which framework? (QBX, QBCore, ESX)

`Config.framework = 'auto'` (in `config.lua`) picks `qbx_core`, then `qb-core`, then `es_extended`. Everything in LS Plates, LS Vehicle Check and the rest of as-browser works on all three; only the names of things differ, and they are chosen for you:

| | QBX / QBCore | ESX |
| --- | --- | --- |
| Owned vehicles table | `player_vehicles` (`plate`, `citizenid`, `mods`) | `owned_vehicles` (`plate`, `owner`, `vehicle`) |
| Plate inside the vehicle's JSON | `mods` | `vehicle` |
| "Vehicle is in a garage" | `state = 1` | `stored = 1` |
| Player id used for ownership | citizenid | ESX identifier |
| Money | `bank` account | `bank` account |

If your server uses different tables or columns, fill in `Config.vehicleTable` in `config.lua`, and set `stateColumn` / `garagedValues` in `sites/plates/config.lua` (`stateColumn = 'auto'` means `state` on QBX/QBCore and `stored` on ESX; a garage script that keeps the state somewhere else needs its own column name, or `nil` to skip the check). Framework specific notes are called out below.

The ESX version is tested with a mock ESX (buying, fitting, taking off, the marketplace, the garage check, keys) the same way as QBCore; it has not been run on a real ESX server.

### 1. Vehicle key scripts

There are two kinds of key script:

| Kind | Example | What you do |
| --- | --- | --- |
| Keys are **items** with the plate in the item's metadata | `acestudios_vehiclekeys`, most "keys as items" scripts | Leave `keys.enabled = true` (the default). LS Plates rewrites the plate in the keys. |
| Keys are rows in **their own table** | many `qb-vehiclekeys` style scripts | Add the table to `extraTables`. |
| Keys do **not store the plate** (tied to the entity, or matched by a lookup at the time you use them) | some client-side key scripts | Nothing to do. Set `keys.enabled = false`. |

**acestudios_vehiclekeys (tested against its code).** Its key is the item `vehiclekeys` (unique) with the metadata `{ plate = 'AB12 CDE', vehicle = 'Sultan', description = 'Sultan\nPlate: AB12 CDE' }` and it matches keys with the exact plate text. So after a plate change the old key would stop working. With the default `keys` settings, LS Plates:

- changes the key of every player who is **online** through `ox_inventory` (`Search` and `SetMetadata`), so their inventory is not overwritten when it next saves;
- changes the keys of everybody else (offline players, stashes, gloveboxes, trunks) in the `ox_inventory` table;
- changes the description line (`Plate: ...`) as well;
- does the same again when the plate is taken off, sold or moved, so keys always match the plate on the car.

Nothing needs to be edited in `acestudios_vehiclekeys` for this. Item keys work the same on ESX as long as your inventory is `ox_inventory` (which ESX supports); the inventory tables above are the ox_inventory ones, so on ESX with the older built-in inventory use `onChanged` instead. Keep its rules in mind: whatever gives keys after buying a car (dealership, garage) must call `GiveKey(src, plate, label)` or `GiveKeys(src, vehicleEntity)` with the plate the car has **now**, and the garage must call `TakeKey` / `RemoveKeys` when a car is stored. Those already work with personalised plates.

```lua
keys = {
    enabled           = true,
    item              = 'vehiclekeys',            -- your key item (only used for online players)
    fields            = { 'plate' },              -- metadata field(s) that hold the plate
    descriptionPrefix = 'Plate: ',                -- text in the description followed by the plate ('' = leave the description alone)
    inventoryTables   = { { table = 'ox_inventory', column = 'data' } },
},
```

**A different key script that uses items.** Set `item` to its item name and `fields` to whichever metadata field holds the plate (`plate`, `vehiclePlate`, ...). If it uses `qb-inventory`, replace `inventoryTables` with `{ { table = 'players', column = 'inventory' }, { table = 'inventories', column = 'items' } }`. Online players are only updated live through `ox_inventory`; with `qb-inventory` the saved inventories are changed, so players who are online should relog after a plate change, or use the `onChanged` hook to call your script's own update.

**A key script with its own table.**

```lua
extraTables = {
    { table = 'vehicle_keys', column = 'plate' },
},
```

**Anything else** (a key script with an export such as `UpdatePlate`): use the hook.

```lua
onChanged = function(oldPlate, newPlate, citizenId, source)
    exports['my_keys']:ChangeKeyPlate(oldPlate, newPlate)
end,
```

Plates in these places are written with the spacing the game shows (`AB12 CDE`). Table lookups ignore spaces and case; item metadata is changed by exact text, so if your key script stores plates without spaces, tell us the format and change `fields`, or use the hook.

### 2. Dealerships and plate generators

Every vehicle dealer needs a plate for the new car. If it generates a random one it can generate one **a player owns** (or one a car will get back), because LS Plates' plates live in `browser_plate_assets`, which no dealer knows about. Fix it in the dealer by refusing those:

```lua
-- in the dealer's random plate loop
repeat
    plate = GeneratePlate()
until not exports['as-browser']:isPlateReserved(plate)
```

or let LS Plates make the plate:

```lua
local plate = exports['as-browser']:generatePlate()           -- pattern from Config.plates.generator.pattern, default 11AAA111
local plate = exports['as-browser']:generatePlate('AA11 AAA') -- 1 = digit, A = letter, . = either, anything else is copied
```

`generatePlate` never returns a personalised plate, an original registration held for a car, a blocked word, a plate a vehicle already wears or a plate in a `holdingTables` table. It returns `nil` if it cannot find one (give up, or try again). `isPlateAvailable(plate)` is the yes/no version, and `isPlateReserved(plate)` only says whether LS Plates owns the plate.

**qbx_vehicles (already patched here).** `qbx_vehicles` builds new cars with `qbx.generateRandomPlate()` and repeats until `doesEntityPlateExist(plate)` says the plate is free; that function only looked in `player_vehicles`. `qbx_vehicles/server/main.lua` has been changed so that `doesEntityPlateExist` (also exported as `DoesPlayerVehiclePlateExist`) additionally asks `isPlateReserved`. This covers `qbx_vehicleshop`, `qbx_vehiclesales` and any script that creates a car with `exports.qbx_vehicles:CreatePlayerVehicle`. If you update `qbx_vehicles`, redo this change (it is 8 lines around `doesEntityPlateExist`), or you will lose the check. The change is safe when as-browser is not running (it checks `GetResourceState`).

**QBCore (`qb-vehicleshop`, `qb-vehiclesales`, `qb-garages`).** The same idea: the dealer builds a random plate and checks `player_vehicles` for a duplicate. Find that check (in `qb-vehicleshop` it is a `GeneratePlate` function in `server/main.lua`) and add `and not exports['as-browser']:isPlateReserved(plate)`. `qb-vehiclesales` uses the same `occasion_vehicles` table as the QBX version, so the default `holdingTables` already covers it.

**ESX (`esx_vehicleshop` and similar).** ESX dealers usually build the plate on the client and ask the server if it is taken (search for `isPlateTaken`, `GeneratePlate`, `GenerateSocietyPlate`). On the server side of that check, also refuse plates where `exports['as-browser']:isPlateReserved(plate)` is true, or have the dealer take its plate from `exports['as-browser']:generatePlate()`. ESX used-car lots differ from script to script; if yours moves cars out of `owned_vehicles`, add its table to `holdingTables`. (These ESX script names are from general knowledge; I have not seen your ESX scripts, so search for the words above.)

**Other frameworks and dealer scripts.** Find where the script chooses the plate (search for `plate =`, `GeneratePlate`, `RandomPlate`, `GenerateVehiclePlate`) and add the `isPlateReserved` check as shown. Each dealer script uses a different name for it. Test-drive and job vehicles that are never saved to the database can keep their random plates (as `qbx_vehicleshop`'s `TEST....` plates do); only cars that are saved matter.

**A plate given out anyway.** If a dealer hands out a plate LS Plates owns, the car ends up with a duplicate plate. Run `plateconflicts` in the server console (or `exports['as-browser']:findPlateConflicts()`); it lists every plate that is worn by a vehicle it should not be, and who owns what. Fix it by hand (change the car's plate in `player_vehicles`, or buy the plate back).

### 3. Used-car lots and other tables that hold vehicles

Some scripts **delete** a car from `player_vehicles` while it is for sale and keep it in another table until it sells or is withdrawn. `qbx_vehiclesales` does exactly this (`occasion_vehicles`). If nothing was done, LS Plates would think the vehicle was scrapped and release its personalised plate while the car still wears it, and the buyer would end up with a plate nobody owns.

`holdingTables` lists these tables. A plate found in one of them counts as "the vehicle still exists": the plate stays on the car, the owner cannot take it off or move it until the car is back (the site says the vehicle is for sale on a lot), and when the car sells, the plate goes with it to the buyer (ownership follows the car the next time either player opens LS Plates).

```lua
holdingTables = {
    { table = 'occasion_vehicles', column = 'plate' },   -- qbx_vehiclesales
    -- { table = 'my_lot_vehicles', column = 'plate' },
},
```

Add any similar table from your own scripts (impound tables that copy the car out of `player_vehicles`, vehicle auctions, repossession tables). A table that does not exist is skipped without an error. A plate can also be for sale twice: once as a plate on the car, once as a listing. LS Plates does not allow selling a plate that is on a lot car.

**Garages.** Garages (`qbx_garages` and others) normally read the plate from `player_vehicles`, so they follow the change with no work (not tested against your garage script; check that a car spawns and stores after a plate change). The plate can only be changed while the car is in a garage (`stateColumn` / `garagedValues`; qbx: `state = 1`). Change these if your garages use different values. If your garage script keeps its own copy of the plate, add that table to `extraTables`.

**Police, MDT and ANPR.** Ask `exports['as-browser']:getOriginalPlate(plate)` for the plate a car was first given, and `getVehicleHistory(plate)` (LS Vehicle Check) for its history under either plate.

### 4. Loose ends, honestly

- **Not tested inside FiveM.** The Lua, the database code and the web pages were run against a mock FiveM and a SQLite copy of the tables (51 tests covering QBCore and ESX, plus a browser test of the pages). Please try each key path on a test server (buy, fit, remove, sell, buy from the market, with a key in the inventory and a key in a glovebox) before you open it to players. The keys are checked against the code of `acestudios_vehiclekeys`, not run with it.
- **Keys changed only when the plate changes here.** If someone changes a plate with a different script, or an admin edits `player_vehicles`, the keys are not updated by LS Plates.
- **Item keys are matched by exact text.** The offline update looks for `"plate":"AB12 CDE"` inside the saved inventory. It is exact, so if your key script stores a different format (no space, lower case), set `fields` or use `onChanged`.
- **`qbx_vehicles` is edited.** It is a third-party resource; see the plate generator note above.

## Criminal record (DBS) checks

`/dbs`: a player pays for a check and gets a certificate that snapshots what is on record that day. Employers use `/dbs/verify` (certificate number + the holder's surname): it says whether the certificate is genuine, its level and result, whether it has expired and whether the record has changed since. It never shows the offences.

Police add convictions with `/addrecord [player id or citizen id] [days until spent, 0 = never] [offence] | [sentence]`, list them with `/viewrecord [id]` and delete with `/removerecord [record number]` (jobs in `policeJobs`, command names in `commands`; the server console can always use them). Scripts can use the exports:

```lua
exports['as-browser']:addCriminalRecord(citizenId, { offence = 'Robbery', sentence = '6 months', notes = 'police only', issuedBy = 'DI Smith', spentDays = 0 })
exports['as-browser']:getCriminalRecords(citizenId)
exports['as-browser']:removeCriminalRecord(recordId)
exports['as-browser']:hasCleanRecord(citizenId, 'basic')   -- e.g. from a job application
```

Levels (`basic` = unspent convictions only, `standard` = all, `enhanced` = all plus police notes), fees, `processingMinutes` (0 = ready at once; otherwise it is finished, and emailed, when the player is online), `validDays` and `defaultSpentDays` are in `dbs` in `sites/gov/config.lua`. Tables: `browser_criminal_records`, `browser_dbs_certificates`.

## LS Vehicle Check (lsvehiclecheck.co.uk)

Vehicle history reports have their own website (`vehiclecheck` in `Config.Sites`, settings in `sites/vehiclecheck/config.lua`). Anyone can check any registration. The free summary shows the vehicle and how many checks need attention; then the player picks a report plan (`plans` in `sites/vehiclecheck/config.lua`: Basic £10, Standard £25, Full history £45 by default, free for the owner when `ownedFree`). Each plan has its own price and its own `includes` list of sections (`flags`, `mot`, `mileage`, `tax`, `insurance`, `owners`, `plates`, `events`, `tests`); add, remove or rename plans freely. The report lists each included check (stolen, written off, impounded, finance, MOT, mileage rollback, number of owners, plate changes, tax, insurance), the events and the MOT tests with mileage. A bought report is saved as a snapshot and can be reopened from the page. A vehicle wearing a personalised plate shows it, together with its original registration; its history, MOT and owners are the same as before the plate went on.

Data comes from what this resource records itself (plate changes, changes of owner, noticed on every lookup and by a sweep of the owned vehicles table every `sweepMinutes`) and from your other scripts:

```lua
exports['as-browser']:setVehicleFlag(plate, 'stolen', true, 'optional note')   -- false clears it. Flags are listed in vehiclecheck.flags
exports['as-browser']:logVehicleEvent(plate, 'accident', 'Text shown on the report')
exports['as-browser']:getVehicleHistory(plate)   -- the whole report as a table, for police / MDT screens
exports['as-browser']:getVehicleFlags(plate)
```

Event and flag wording is in `locales/en.lua` (`gov.history.event.<kind>`, `gov.history.flag.<flag>`); an unknown event kind is shown as its own name. MOT mileage comes from `as-computer` (`getMotRecords`); without it the report uses the MOT results this resource was told about, without mileage. Tables: `browser_vehicle_events`, `browser_vehicle_flags`, `browser_vehicle_owners`, `browser_vehicle_reports` (plate changes come from `browser_plate_log`). The government site still lists the service and sends players here.

## Parts shop (LS Parts Direct)

A trade parts shop for garages, on the desktop browser only (as-computer's Scout). It never shows up in the phone browser, search or bookmarks, and its requests are refused from the phone. Turn it off with `parts = { enabled = false }` in `Config.Sites`, or `/browsersite parts off`.

- Only the jobs in `Config.parts.jobs` (default `mechanic`) can use it. Each job pays from its own society account.
- The society bank is auto-detected (Renewed-Banking, qb-banking, okokBanking, fd_banking, qb-management, esx_society). Set `Config.parts.bank` to pick one, or `'custom'` and fill in `balance`, `remove` and `add` yourself. If none is running, purchases are switched off and the server console says so.
- Everything you would change is in `sites/parts/config.lua`: shop name, categories, every part (`item` is the ox_inventory item the buyer receives, `price` is the RRP), trade discount, per-order limit by job grade, delivery fees, and the free-delivery threshold. The console warns about part items that do not exist in ox_inventory.
- Delivery uses Postal Prime (home delivery to an owned/rented/keyed property, or a locker). It needs the patched `as-postalprime` (`hidden` parcels, home delivery for parcels, `getParcels` and `getDeliveryInfo` exports). The parcel is hidden from the Postal Prime phone app and widget, and its phone notifications are silenced. Tracking, and the locker pickup code, are shown on the shop's own Orders page.
- Every order is saved in `browser_parts_orders` (created automatically). All garage staff see the job's orders; only the buyer sees the pickup code. A locker parcel that is not collected in time is returned and the society is refunded once. Stock is unlimited.
- **Deliver to our business:** instead of a home or locker, the job can have the parts sent to its workshop. The buyer picks "Deliver to our business" at checkout; a Postal Prime courier (a player courier if one is on duty, otherwise the NPC van) takes the box to the coordinates in `Config.parts.businesses.<job>`, and when it is dropped the parts go straight into that job's ox_inventory stash and everyone on the job is notified. `Config.parts.businesses` lists, per job, the `label`, the drop-off `coords` (outside the door) and the `stash` (`id`, and `register = true` with `slots` / `weight` if Postal Prime should create it, or `register = false` to use a stash your job script already registers). A job with no entry there does not get the option. The fee is `Config.parts.delivery.business.fee`, and `delivery.business.enabled = false` switches it off. If the stash is full the parts are not lost: the box stays at the door for staff to take and the job is told. Needs the patched `as-postalprime` with `Config.business.enabled = true`.
- Text is in `locales/en.lua` under `parts.*`.

A site can be marked desktop-only in its `Browser.defineSite` call with `desktopOnly = true`.

## Other scripts checklist

One place that lists what every kind of script needs from you. Each row points at the section with the details. Nothing here changes anything until the matching feature is used.

| Script type | What to do | Details |
| --- | --- | --- |
| **Vehicle keys** (item keys, e.g. `acestudios_vehiclekeys`) | Keep `keys.enabled = true` in `sites/plates/config.lua`; set `keys.item` and `keys.fields` to your key item. | [1. Vehicle key scripts](#1-vehicle-key-scripts) |
| Vehicle keys in their **own table** | Add the table to `extraTables`. | same |
| Keys with **no stored plate** | Set `keys.enabled = false`. | same |
| Any script with its own plate update function | Use the `onChanged` hook in `sites/plates/config.lua`. | same |
| **Dealerships** and plate generators | Refuse plates where `exports['as-browser']:isPlateReserved(plate)` is true, or take plates from `generatePlate()`. `qbx_vehicles` is already patched (the patch is lost when you update it). | [2. Dealerships](#2-dealerships-and-plate-generators) |
| **Used-car lots** and anything that moves cars out of `player_vehicles` | Add their table to `holdingTables` (`occasion_vehicles` is there by default). | [3. Used-car lots](#3-used-car-lots-and-other-tables-that-hold-vehicles) |
| **Garages** | Nothing if they read the plate from `player_vehicles`. Set `stateColumn` / `garagedValues` if your garage state is not `state = 1` (`stored = 1` on ESX). If a garage keeps its own copy of the plate, add that table to `extraTables`. | [Garages](#3-used-car-lots-and-other-tables-that-hold-vehicles) |
| **Impound, police, MDT, ANPR** | `setVehicleFlag(plate, 'impounded' / 'stolen', true)`, `logVehicleEvent`, `getVehicleStatus`, `isRoadLegal`, `getVehicleHistory`, `getOriginalPlate`, `addCriminalRecord` (see below). Personalised plates are refused while a vehicle is impounded or stolen (garage state / stolen flag). | [Police](#for-police-mdt-and-anpr-scripts), [DBS](#criminal-record-dbs-checks), [LS Vehicle Check](#ls-vehicle-check-lsvehiclecheckcouk) |
| **Housing** (council tax) | `housing = 'auto'` finds `qbx_properties`, `ps-housing` or `qb-houses`. Any other script: `housing = 'custom'` and fill in its table and column names. Each new home gets `graceDays` before the first bill. | [Council tax](#council-tax) |
| **Banking / society accounts** | Only the parts shop needs one (Renewed-Banking, qb-banking, okokBanking, fd_banking, qb-management, esx_society, or `'custom'`). Everything else pays from the player's `bank` account and writes a phone bank line. | [Parts shop](#parts-shop-ls-parts-direct) |
| **Inventory** (`ox_inventory` or `qb-inventory`) | Parts shop items must exist in ox_inventory. Certificate items (`birth_certificate`, `marriage_certificate`, `business_certificate`) come from each resource's `install/` folder. Item keys are edited through ox_inventory (live) or the inventory tables (offline). | [First-time setup checklist](#first-time-setup-checklist) |
| **Postal Prime** | Patched `as-postalprime` needed for passports, licences, birth certificates and the parts shop (`createParcel`, `hidden` parcels, `getParcels`, `getDeliveryInfo`). Start it before as-browser. | [Start order](#start-order) |
| **sd-phone** | Needs its exports `getMailAccounts`, `getMailAddresses`, `sendMail`, `addBankTransaction`, `notify` and `createDocument` for mail, bank lines, notifications and saved certificates. These calls are wrapped so a missing one never breaks a purchase: that bank line, notification or document is simply skipped (a mail that cannot be sent is printed in the console). | [Install](#install) |
| **as-computer** (MOT terminal, Scout, bookings, mechanic app) | Start it after as-browser. It feeds MOT results and bookings, and follows plate changes by itself. Needs 0.5.1 or later. | [MOT](#mot-as-computer-or-your-own-mot-script) |
| **Mileage** (`jg-vehiclemileage`) | Optional. `as-computer` reads it; the history check gets mileage from `as-computer`'s MOT records. | as-computer README |
| **Discord / logging** | Webhooks go in the server-only `sites/*/config.lua` files (`jobs`, `benefits.webhook`) and `as-fines`. | [Jobs](#jobs-and-applications) |

Two habits that save trouble:

1. **Find every table that stores a plate.** Run this once on your database and go through the list; every table that is not `player_vehicles` and belongs to a script that holds plates for cars players own (keys, garages, tuning, mileage, trackers, tow, repo) needs `extraTables` or `onChanged`:

   ```sql
   SELECT table_name, column_name FROM information_schema.columns
   WHERE table_schema = DATABASE() AND column_name LIKE '%plate%';
   ```

2. **After a plate change on a test server**, check that the car spawns, its key still opens it, it stores back in the garage, and the vehicle check and the MOT terminal both find it under the new plate. `plateconflicts` in the server console lists any duplicate.

## Weather (lsweather.co.uk)

Current conditions and an 8-step outlook for Los Santos, Blaine County and Mount Chiliad. `Config.weather.source` in `sites/weather/config.lua`: `'globalstate'` reads the live weather from a GlobalState key (`globalStateKeys`, default covers common weather scripts), `'function'` calls your own `Config.weather.current()`, `'simulated'` makes up believable weather, and `'auto'` (default) uses the live value when it finds one and simulates otherwise (the page then says "Estimated conditions"). Also `units` (`C`/`F`), `windUnit`, `stepMinutes`, `forecastSteps`, regional offsets and the per-weather-type table (label, icon, temperature, advice). `showForecast = false` hides the outlook. The outlook is always simulated, so it is an estimate and may not match what your weather script does next.

## Server Wiki (lswiki.co.uk)

Guides and rules, written in `sites/wiki/config.lua`: each page has an `id`, `title`, `category`, `summary`, `updated` and a `body` between `[=[ ... ]=]`. Body markup: `#`/`##` headings, `-` lists, `>` quotes, tables with `|`, `**bold**`, `*italic*`, `[[page-id|label]]` links to other pages and `[text](lsplates.co.uk/path)` links to another in-game site (only in-game domains are linked; everything else is shown as text). Search covers title, summary and body. Five example pages are included; replace them with your own.

## Tickets and Events (lstickets.co.uk)

Jobs in `Config.tickets.organiserJobs` (default `events`, from `organiserMinGrade`) can create events on the site (title, venue, date and time, price, capacity, category); anyone can buy tickets, paid from their bank. `staffJobs` can check tickets in at the door by code. Ticket codes are single use. Limits: `maxPerPerson`, `maxActivePerJob`, `maxCapacity`, price and time limits. Cancelling an event refunds every holder in full (online players immediately, offline players the next time they open the site). After an event ends the takings are paid to the organiser job's society account (uses the same bank detection as the parts shop; set `accountFor` to change the account). Fixed events can be seeded from `Config.tickets.events` (each needs a unique `key` and a future `startsAt`). Tables `browser_events`, `browser_tickets`, `browser_ticket_refunds` are created automatically. Not tested in game.

## LS Bank (lsbank.co.uk)

A full online-banking website for the same money the phone's Wallet app shows. It is a separate design (navy header, tabs, statements, a three-step payment with a review screen), not a copy of the phone app.

- **Accounts:** balance, cash in hand, money in and out over 30 days, the player's card (colour taken from their phone's card style), recent transactions, and an account page with a made-up account number and the sort code (`sortCode` in `sites/bank/config.lua`).
- **Statements:** every row in `phone_bank_transactions`, searchable, filtered in / out, grouped by day, paged.
- **Pay and transfer:** to a phone number (online or offline) or a nearby player's server ID, optionally anonymous. Recent payees are one tap away.
- **Standing orders:** create, edit, pause, resume and delete. The phone's own scheduler runs them, so they behave exactly like ones made in the phone.
- **Invoices:** pay invoices sent to you (personal, and business invoices which go to the society account, with commission), send your own, cancel unpaid ones.

**Shares the phone's data.** It reads and writes sd-phone's own tables (`phone_bank_transactions`, `phone_bank_standing_orders`, `phone_service_invoices`, `phone_settings`), so anything done here shows in the phone and the other way round. sd-phone must have started once so those tables exist; until then the site says it is not available. Money moves on the framework bank account (`Config.account`), like the other sites. Banking resources that keep balances in their own tables (wasabi, okok and similar) are not supported for personal accounts.

**Limits are mirrored, not read.** One resource cannot read another's config, so `sites/bank/config.lua` repeats sd-phone's banking limits (standing-order maximum, invoice amounts and pending limit, business commission per company). If you change them in sd-phone's `configs/banking.lua`, change them there too. `walletLog = 'own'` makes the site write every statement row itself instead of tidying the phone's automatic one (use it if the phone does not log framework bank changes).

Switch it off with `Config.Sites.bank.enabled = false`; text is in `locales/lsbank_en.lua`. Tested against a mock of sd-phone (`test/test_bank.py`, `test/run_ui_bank.py`); not yet tried in game.

## Printing (needs `as-printer`)

With the `as-printer` resource running, the sites show a **Print** button next to documents the player owns: MOT booking confirmations (`lsgov.co.uk`), tickets (`lstickets.co.uk`), invoices and the statement (`lsbank.co.uk`), vehicle history reports (`lsvehiclecheck.co.uk`), parts orders (`lspartsdirect.co.uk`) and number plate sales and purchases (`lsplates.co.uk`). Without `as-printer` the buttons stay hidden. To switch printing off anyway, add `Config.Printing = { enabled = false }` to `config.lua`.

The player picks a printer within 50 metres, colour or black and white, and a letterhead. The page only sends which document it means. **The text is built on the server from the database** (`server/printing.lua` and the `*Print` requests in each site's server file), so a player cannot print a forged invoice or ticket. MOT booking confirmations and tickets cannot be copied on the printer. Supplies, zones and the tray are all set in `as-printer`.

For your own site: add a request that builds the document and calls `Browser.printDoc(src, 'invoice', data, requestData)` (templates: `invoice`, `receipt`, `statement`, `ticket`, `vehicle_report`, `mot_booking`, `mot_certificate`), then put `<button data-print="yourRequest" data-pd='{"id":1}'>Print</button>` in the page. `Site.print(name, data)` opens the dialog from your own code.

## Adding your own site

1. Copy `sites/_template` to `sites/mysite`.
2. Rename `server.example.lua` to `server.lua` (and `config.example.lua` to `config.lua` if you need settings), and change the key from `example` to `mysite`.
3. Add a line to `Config.Sites` in `config.lua`: `mysite = { enabled = true, domain = 'mysite.co.uk' }`.
4. Edit `index.html`.

Pages include `/sdk/site.css` and `/sdk/site.js`, which give you `Site.call`, `Site.go`, `Site.title`, `Site.copy` and more. Read the top of `sdk/site.js` for the full list. Use `t()` and `data-i18n` for your page text so it can be translated (see Languages below). The page only talks to the server through `Site.call(name, data)`, and your `Browser.handler` decides what to allow, so always check the data you get.

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

## Languages

All text the scripts show (the browser shell, the built-in sites, emails, notifications, receipts and error messages) lives in `locales/en.lua`. English is the only language shipped, and the wording is the default.

**Switch language:** set `Config.locale = 'de'` (or any code) in `config.lua` and restart the resource. Nothing else changes.

**Add a language:**

1. Copy `locales/en.lua` to `locales/de.lua`.
2. Change `Locales['en']` to `Locales['de']` and translate the values only. Keep every key, and keep every `%s` / `%d` placeholder in the same order.
3. Keys marked `-- (html)` are inserted into pages as HTML, so keep their `<b>...</b>` tags.
4. Set `Config.locale = 'de'`.

A key missing from your file falls back to English, so you can translate a little at a time. `shell.months`, `shell.dateFmt` and `shell.dateTimeFmt` control the month names and order in emails and receipts. `shell.dateLocale` and `sdk.dateLocale` (for example `de-DE`) control how the pages format dates, times and money.

**Not in the locale files.** Text you edit as content stays in the config files, so translate it there yourself: the `sites/*/config.lua` files (site names and taglines, job listings and forms, insurance providers, covers, add-ons and labels, government categories, service titles, descriptions and keywords, benefit and council settings, the server-info rules, staff, changelog and Discord text), mail-from names, and `documentFolder`. Also not translated: server console logs (`print`), and the short developer error strings the exports return to other scripts (for example `registerSite` returning `Invalid domain`). Errors from other resources (`as-passport`, `as-fines` and so on) pass through as they are written there.

**Writing your own site.** `sdk/site.js` loads the dictionary for you, so a site page can use it straight away:

- `t('my.key', value, ...)` returns the text for a key. Extra arguments fill `%s` / `%d` in order. A missing key returns the key itself.
- `data-i18n="my.key"` on an element (or `data-i18n-placeholder`, `data-i18n-title`, `data-i18n-aria-label`) is filled automatically once the language has loaded. Keep the English text in the markup as the default. Call `applyI18n(element)` after you add such elements yourself.
- `Site.onRoute` waits for the dictionary, so `t()` is safe inside it. Code that runs at load time, before the first route, should wait for `Site.onReady(fn)`.
- Server handlers use `T('my.key', value, ...)` the same way, for example for the errors you return to the page.
- Add your keys to `locales/en.lua` under your own prefix (`sites/_template` uses `example.`). Use one key per full sentence and separate `.one` / `.other` keys for plurals; never build a sentence from translated pieces.
- A site added from another resource only receives the `as-browser` dictionary. Keep that resource's own text in its own files, or in the page.

## Saving logins to Passwords (optional)

sd-phone's Passwords app only accepts a fixed list of app ids and has no public export, so saving a login from a website needs a small edit to sd-phone: add `'browser'` to the list of accepted app ids (`ALL_APPS`) in its Passwords code. Then set `Config.passwords.enabled = true` in `config.lua`. Until then `Site.saveLogin` does nothing and sites should not rely on it.

## Files

- `config.lua` shared settings (sent to players, no secrets)
- `sites/*/config.lua` server-only site settings and secrets
- `server/` framework bridge, vehicle lookups, site registry
- `client/` phone app registration
- `ui/` the browser shell (tabs, address bar, search, bookmarks, history)
- `sdk/` the toolkit every site page uses
- `shared/locale.lua` the `T()` text helper (client and server)
- `locales/en.lua` every piece of text the scripts show (copy it to add a language)
- `sites/` the websites
- `sites/gov/config.lua` government services, categories, tax, council tax, benefits and licence settings
- `sites/gov/server_*.lua` one file per gov service (`passport`, `licence`, `council`, `birthcert`, `fines`, `benefits`, `registry`)
- `sites/plates/` LS Plates: `config.lua`, `server.lua` (ownership, fitting), `server_market.lua` (marketplace and payouts), `server_integrations.lua` (keys, lots, generator, conflicts), `index.html`
- `sites/vehiclecheck/` LS Vehicle Check: `config.lua` (plans, flags), `server.lua` (history, reports), `index.html`
- `sites/parts/` the parts shop (`config.lua` catalogue and rules, `server.lua` orders, `server_bank.lua` society bank, `index.html` the page)

## Related resources

| Resource | What it does |
| --- | --- |
| `as-postalprime` | Lockers and parcel delivery used by passports, licences, birth certificates and the parts shop |
| `as-passport` | Passport applications |
| `as-drivingschool` | Driving licence, theory and practical tests, penalty points (no MOT) |
| `as-birthcert` | Birth certificates |
| `as-fines` | Fines, `/fine` command, pay on the gov site |
| `as-registry` | Marriage and business registration and certificates |