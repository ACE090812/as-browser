-- Diamond Online: the game maths. Pure functions only (no database, no player data) so every rule lives in one place and can be
-- tested on its own. Every function takes the amount in whole money and returns what the games file needs to pay out.
-- Cards are numbers 0-51: rank = id % 13 + 1 (1 = Ace ... 13 = King), suit = id // 13 (0 clubs, 1 diamonds, 2 hearts, 3 spades).
Casino = Casino or {}
local E = {}
Casino.engine = E

local floor, random = math.floor, math.random
local function rnd(n) return random(1, n) end   -- 1..n

function E.rank(c) return c % 13 + 1 end
function E.suit(c) return c // 13 end
function E.card() return random(0, 51) end

local function pick(weights, total)   -- weights = { {key, w}, ... }
    local r = random() * total
    for i = 1, #weights do
        r = r - weights[i][2]
        if r < 0 then return weights[i][1] end
    end
    return weights[#weights][1]
end

-- ============================================================================================================================
-- SLOTS
-- ============================================================================================================================
-- Every machine uses the same engine: a grid of reels x rows, paylines, a wild, scatters that start free spins, and an optional
-- jackpot. A machine is a theme (names and symbols for the page) plus a few numbers. Symbol keys: L1-L4 low, H1-H4 high,
-- W wild, S scatter, J jackpot (only where `jackpot = true`).
local LINES5 = {
    { 2, 2, 2, 2, 2 }, { 1, 1, 1, 1, 1 }, { 3, 3, 3, 3, 3 }, { 1, 2, 3, 2, 1 }, { 3, 2, 1, 2, 3 },
    { 1, 1, 2, 3, 3 }, { 3, 3, 2, 1, 1 }, { 2, 1, 1, 1, 2 }, { 2, 3, 3, 3, 2 }, { 1, 2, 2, 2, 3 },
}
local LINES3 = { { 2, 2, 2 }, { 1, 1, 1 }, { 3, 3, 3 }, { 1, 2, 3 }, { 3, 2, 1 } }

-- Pays are multiples of the bet on ONE line (the bet is split across the lines).
local PAY5 = {
    L1 = { [3] = 5, [4] = 18, [5] = 70 },     L2 = { [3] = 6, [4] = 24, [5] = 95 },
    L3 = { [3] = 7, [4] = 30, [5] = 120 },    L4 = { [3] = 9, [4] = 36, [5] = 165 },
    H1 = { [3] = 14, [4] = 58, [5] = 280 },   H2 = { [3] = 19, [4] = 82, [5] = 470 },
    H3 = { [3] = 28, [4] = 140, [5] = 940 },  H4 = { [3] = 50, [4] = 280, [5] = 1800 },
    W  = { [3] = 50, [4] = 280, [5] = 1800 },
    J  = { [3] = 10, [4] = 80, [5] = 600 },
}
local WEIGHTS5 = { L1 = 13, L2 = 12, L3 = 11, L4 = 10, H1 = 8, H2 = 6.5, H3 = 5, H4 = 3.6, W = 3.2, S = 2.8 }
local SCATTER5 = { [3] = 2, [4] = 8, [5] = 40 }   -- multiples of the whole bet

local PAY3 = {
    L1 = { [3] = 3 }, L2 = { [3] = 5 }, L3 = { [3] = 10 }, H1 = { [3] = 20 }, H2 = { [3] = 50 }, H3 = { [3] = 150 },
}
local WEIGHTS3 = { L1 = 24, L2 = 20, L3 = 16, H1 = 11, H2 = 7, H3 = 3, W = 6 }

E.slots = {
    diamond = { tune = 1.0, id = 'diamond', name = 'Diamond Reels', reels = 5, rows = 3, lines = LINES5, pay = PAY5, weights = WEIGHTS5, scatter = SCATTER5,
        free = { [3] = 10, [4] = 15, [5] = 20 }, freeMult = 'fixed', freeMultBase = 2, jackpot = true, jackpotWeight = 0.5, theme = 'Diamonds' },
    gold = { tune = 0.98, id = 'gold', name = 'Gold Rush Gulch', reels = 5, rows = 3, lines = LINES5, pay = PAY5, weights = WEIGHTS5, scatter = SCATTER5,
        free = { [3] = 10, [4] = 15, [5] = 20 }, freeMult = 'fixed', freeMultBase = 2, theme = 'Wild West' },
    neptune = { tune = 0.79, id = 'neptune', name = 'Neptune\'s Fortune', reels = 5, rows = 3, lines = LINES5, pay = PAY5, weights = WEIGHTS5, scatter = SCATTER5,
        free = { [3] = 8, [4] = 12, [5] = 16 }, freeMult = 'ramp', freeMultBase = 1, theme = 'Ocean' },
    pharaoh = { tune = 0.815, id = 'pharaoh', name = 'Pharaoh\'s Vault', reels = 5, rows = 3, lines = LINES5, pay = PAY5, weights = WEIGHTS5, scatter = SCATTER5,
        free = { [3] = 12, [4] = 16, [5] = 24 }, freeMult = 'fixed', freeMultBase = 3, theme = 'Egypt' },
    dragon = { tune = 0.782, id = 'dragon', name = 'Dragon Lantern', reels = 5, rows = 3, lines = LINES5, pay = PAY5, weights = WEIGHTS5, scatter = SCATTER5,
        free = { [3] = 8, [4] = 12, [5] = 20 }, freeMult = 'ramp', freeMultBase = 1, theme = 'Lunar festival' },
    neon = { tune = 0.692, id = 'neon', name = 'Neon Nights', reels = 3, rows = 3, lines = LINES3, pay = PAY3, weights = WEIGHTS3, wildMult = 2, theme = 'Classic' },
}
E.slotOrder = { 'diamond', 'gold', 'neptune', 'pharaoh', 'dragon', 'neon' }
--- What the page needs to draw the paytable: pays as multiples of the TOTAL bet (the line pays are of one line and include the tuning number).
function E.slotInfo()
    local out = {}
    for _, id in ipairs(E.slotOrder) do
        local m = E.slots[id]
        local pays = {}
        for sym, t in pairs(m.pay) do
            if sym ~= 'J' or m.jackpot then
                pays[sym] = {}
                for n, v in pairs(t) do pays[sym][tostring(n)] = floor(v * (m.tune or 1) / #m.lines * 100 + 0.5) / 100 end
            end
        end
        local free
        if m.free then free = { ['3'] = m.free[3], ['4'] = m.free[4], ['5'] = m.free[5] } end
        local sc
        if m.scatter then sc = { ['3'] = m.scatter[3], ['4'] = m.scatter[4], ['5'] = m.scatter[5] } end
        out[#out + 1] = { id = id, name = m.name, theme = m.theme, reels = m.reels, rows = m.rows, lines = #m.lines, pays = pays, free = free, scatter = sc,
            freeMult = m.freeMult, freeMultBase = m.freeMultBase, jackpot = m.jackpot or false, wildMult = m.wildMult }
    end
    return out
end
E.maxSlotWin = 5000   -- most one spin (free spins included) can pay, as a multiple of the bet

local function slotTable(m)
    if m._tab then return m._tab end
    local t, total = {}, 0
    for k, w in pairs(m.weights) do t[#t + 1] = { k, w }; total = total + w end
    if m.jackpot then t[#t + 1] = { 'J', m.jackpotWeight or 0.5 }; total = total + (m.jackpotWeight or 0.5) end
    table.sort(t, function(a, b) return a[1] < b[1] end)
    m._tab = { list = t, total = total }
    return m._tab
end

local function slotGrid(m)
    local tab, g = slotTable(m), {}
    for r = 1, m.rows do
        g[r] = {}
        for c = 1, m.reels do g[r][c] = pick(tab.list, tab.total) end
    end
    return g
end

-- Wins on the lines of one grid. `lineBet` is what one line stakes. Returns total, list of { line, sym, count, win, cells }.
local function scoreGrid(m, g, lineBet, canJackpot)
    local total, hits, jackpot = 0, {}, false
    for li, line in ipairs(m.lines) do
        local base
        for c = 1, m.reels do
            local s = g[line[c]][c]
            if s ~= 'W' then base = s; break end
        end
        if base ~= 'S' then
            local sym = base or 'W'
            local n = 0
            for c = 1, m.reels do
                local s = g[line[c]][c]
                if s == sym or (s == 'W' and sym ~= 'J') then n = n + 1 else break end
            end
            local pays = m.pay[sym]
            if pays and pays[n] then
                local win = pays[n] * lineBet
                if m.wildMult then
                    for c = 1, n do if g[line[c]][c] == 'W' then win = win * m.wildMult; break end end
                end
                total = total + win
                hits[#hits + 1] = { line = li, sym = sym, count = n, win = floor(win) }
                if sym == 'J' and n == m.reels and canJackpot then jackpot = true end
            end
        end
    end
    return total, hits, jackpot
end

local function scatterCount(m, g)
    local n = 0
    for r = 1, m.rows do for c = 1, m.reels do if g[r][c] == 'S' then n = n + 1 end end end
    return n
end

--- One paid spin. `bet` is the whole stake; `canJackpot` is true when the bet is high enough to win the jackpot.
--- Returns { grid, hits, win, scatter, free = { {grid, hits, win, mult} ... } | nil, jackpot = bool }.
function E.slotSpin(id, bet, canJackpot)
    local m = E.slots[id]; if not m then return nil end
    local lineBet = bet / #m.lines * (m.tune or 1)
    local g = slotGrid(m)
    local win, hits, jp = scoreGrid(m, g, lineBet, canJackpot)
    local out = { grid = g, hits = hits, scatter = 0, jackpot = jp }
    local base = win
    if m.scatter then
        local sc = scatterCount(m, g); out.scatter = sc
        local n = sc > 5 and 5 or sc
        if n >= 3 then
            base = base + m.scatter[n] * bet
            local spins = m.free[n]
            out.free = {}
            local sum = 0
            for i = 1, spins do
                local mult = m.freeMult == 'ramp' and (m.freeMultBase + i - 1) or m.freeMultBase
                local fg = slotGrid(m)
                local w, h, j2 = scoreGrid(m, fg, lineBet, false)
                w = floor(w * mult)
                out.free[i] = { grid = fg, hits = h, win = w, mult = mult }
                sum = sum + w
            end
            out.freeWin = sum
            base = base + sum
        end
    end
    local cap = E.maxSlotWin * bet
    out.win = floor(base)
    if out.win > cap then out.win = cap; out.capped = true end
    out.baseWin = floor(win)
    return out
end

-- ============================================================================================================================
-- BLACKJACK (six decks drawn without tracking, dealer stands on every 17, blackjack pays 3 to 2)
-- ============================================================================================================================
local function bjCardValue(c) local r = E.rank(c); if r == 1 then return 11 elseif r >= 10 then return 10 else return r end end
function E.bjTotal(cards)
    local t, aces = 0, 0
    for _, c in ipairs(cards) do t = t + bjCardValue(c); if E.rank(c) == 1 then aces = aces + 1 end end
    while t > 21 and aces > 0 do t = t - 10; aces = aces - 1 end
    return t, aces > 0   -- total, is soft
end
function E.bjBlackjack(cards) return #cards == 2 and E.bjTotal(cards) == 21 end
function E.bjDealerPlay(cards)   -- draws until 17 or more; returns the cards
    while E.bjTotal(cards) < 17 do cards[#cards + 1] = E.card() end
    return cards
end
local function tenValue(c) return bjCardValue(c) == 10 end
E.bjTenValue = tenValue

-- ============================================================================================================================
-- ROULETTE (European, one zero)
-- ============================================================================================================================
local RED = { [1] = 1, [3] = 1, [5] = 1, [7] = 1, [9] = 1, [12] = 1, [14] = 1, [16] = 1, [18] = 1, [19] = 1, [21] = 1, [23] = 1, [25] = 1, [27] = 1, [30] = 1, [32] = 1, [34] = 1, [36] = 1 }
function E.rouletteColour(n) if n == 0 then return 'green' end return RED[n] and 'red' or 'black' end

--- The numbers a bet covers and what it pays (to one), or nil when the bet is not valid.
function E.rouletteBet(kind, v)
    v = tonumber(v)
    local set, pay = {}, 0
    local function add(...) for _, n in ipairs({ ... }) do set[#set + 1] = n end end
    if kind == 'n' then if not v or v < 0 or v > 36 or v ~= floor(v) then return nil end; add(v); pay = 35
    elseif kind == 'street' then if not v or v < 1 or v > 12 or v ~= floor(v) then return nil end; add(3 * v - 2, 3 * v - 1, 3 * v); pay = 11
    elseif kind == 'line' then if not v or v < 1 or v > 11 or v ~= floor(v) then return nil end; for i = 3 * v - 2, 3 * v + 3 do add(i) end; pay = 5
    elseif kind == 'corner' then if not v or v < 1 or v > 32 or v ~= floor(v) or v % 3 == 0 then return nil end; add(v, v + 1, v + 3, v + 4); pay = 8
    elseif kind == 'red' then for n in pairs(RED) do add(n) end; pay = 1
    elseif kind == 'black' then for n = 1, 36 do if not RED[n] then add(n) end end; pay = 1
    elseif kind == 'odd' then for n = 1, 36, 2 do add(n) end; pay = 1
    elseif kind == 'even' then for n = 2, 36, 2 do add(n) end; pay = 1
    elseif kind == 'low' then for n = 1, 18 do add(n) end; pay = 1
    elseif kind == 'high' then for n = 19, 36 do add(n) end; pay = 1
    elseif kind == 'dozen' then if v ~= 1 and v ~= 2 and v ~= 3 then return nil end; for n = (v - 1) * 12 + 1, v * 12 do add(n) end; pay = 2
    elseif kind == 'col' then if v ~= 1 and v ~= 2 and v ~= 3 then return nil end; for n = v, 36, 3 do add(n) end; pay = 2
    else return nil end
    return set, pay
end
--- A split is sent as { kind = 'split', a = n, b = n }.
function E.rouletteSplit(a, b)
    a, b = tonumber(a), tonumber(b)
    if not a or not b or a ~= floor(a) or b ~= floor(b) or a < 0 or b > 36 then return nil end
    if a > b then a, b = b, a end
    local ok = false
    if a == 0 then ok = (b >= 1 and b <= 3)
    elseif b == a + 3 then ok = true
    elseif b == a + 1 and a % 3 ~= 0 then ok = true end
    if not ok then return nil end
    return { a, b }, 17
end
function E.rouletteSpin() return random(0, 36) end

-- ============================================================================================================================
-- CRASH
-- ============================================================================================================================
E.crashRate = 0.09   -- growth per second: the multiplier is e^(rate x seconds)
function E.crashMultiplier(ms)
    return floor(math.exp(E.crashRate * ms / 1000) * 100) / 100
end
--- Where this round busts. `edge` is the house edge (0.01 = 1%). Never lower than 1.00, never above 1000.
function E.crashPoint(edge)
    local u = random()
    local x = (1 - edge) / (1 - u)
    x = floor(x * 100) / 100
    if x < 1 then x = 1 end
    if x > 1000 then x = 1000 end
    return x
end

-- ============================================================================================================================
-- VIDEO POKER (Jacks or Better, 9/6 pays)
-- ============================================================================================================================
E.pokerPays = { royal = 800, straightflush = 50, four = 25, fullhouse = 9, flush = 6, straight = 4, three = 3, twopair = 2, jacks = 1 }
E.pokerOrder = { 'royal', 'straightflush', 'four', 'fullhouse', 'flush', 'straight', 'three', 'twopair', 'jacks' }
function E.pokerEval(cards)
    local ranks, suits, counts = {}, {}, {}
    for _, c in ipairs(cards) do ranks[#ranks + 1] = E.rank(c); suits[E.suit(c)] = true; counts[E.rank(c)] = (counts[E.rank(c)] or 0) + 1 end
    table.sort(ranks)
    local flush = true; local s0 = E.suit(cards[1]); for _, c in ipairs(cards) do if E.suit(c) ~= s0 then flush = false end end
    local straight = true
    for i = 2, 5 do if ranks[i] ~= ranks[i - 1] + 1 then straight = false end end
    if not straight and ranks[1] == 1 and ranks[2] == 10 and ranks[3] == 11 and ranks[4] == 12 and ranks[5] == 13 then straight = true; ranks.broadway = true end
    local pairs_, three, four, jacksPair = 0, false, false, false
    for r, n in pairs(counts) do
        if n == 4 then four = true elseif n == 3 then three = true elseif n == 2 then pairs_ = pairs_ + 1; if r == 1 or r >= 11 then jacksPair = true end end
    end
    if straight and flush then return ranks.broadway and 'royal' or 'straightflush' end
    if four then return 'four' end
    if three and pairs_ == 1 then return 'fullhouse' end
    if flush then return 'flush' end
    if straight then return 'straight' end
    if three then return 'three' end
    if pairs_ == 2 then return 'twopair' end
    if pairs_ == 1 and jacksPair then return 'jacks' end
    return nil
end
function E.pokerDeal()
    local used, hand = {}, {}
    while #hand < 5 do local c = E.card(); if not used[c] then used[c] = true; hand[#hand + 1] = c end end
    return hand
end
--- Replaces the cards that were not held. `dealt` is the original five; replacements never repeat any of them.
function E.pokerDraw(dealt, hold)
    local used = {}; for _, c in ipairs(dealt) do used[c] = true end
    local out = {}
    for i = 1, 5 do
        if hold[i] then out[i] = dealt[i]
        else
            local c; repeat c = E.card() until not used[c]
            used[c] = true; out[i] = c
        end
    end
    return out
end

-- ============================================================================================================================
-- BACCARAT (punto banco)
-- ============================================================================================================================
local function bacValue(cards) local t = 0; for _, c in ipairs(cards) do local r = E.rank(c); t = t + (r >= 10 and 0 or r) end; return t % 10 end
E.bacValue = bacValue
--- Deals one hand with the standard third card rules. Returns { player = {cards}, banker = {cards}, p = total, b = total, winner = 'player'|'banker'|'tie', pPair, bPair }.
function E.baccaratDeal()
    local P, B = { E.card(), E.card() }, { E.card(), E.card() }
    local pv, bv = bacValue(P), bacValue(B)
    local pPair, bPair = E.rank(P[1]) == E.rank(P[2]), E.rank(B[1]) == E.rank(B[2])
    if pv < 8 and bv < 8 then
        local p3
        if pv <= 5 then p3 = E.card(); P[3] = p3 end
        if not p3 then
            if bv <= 5 then B[3] = E.card() end
        else
            local v = bacValue({ p3 })
            local draw = false
            if bv <= 2 then draw = true
            elseif bv == 3 then draw = v ~= 8
            elseif bv == 4 then draw = v >= 2 and v <= 7
            elseif bv == 5 then draw = v >= 4 and v <= 7
            elseif bv == 6 then draw = v == 6 or v == 7 end
            if draw then B[3] = E.card() end
        end
    end
    pv, bv = bacValue(P), bacValue(B)
    return { player = P, banker = B, p = pv, b = bv, winner = pv > bv and 'player' or (bv > pv and 'banker' or 'tie'), pPair = pPair, bPair = bPair }
end

-- ============================================================================================================================
-- HIGHER OR LOWER
-- ============================================================================================================================
--- Chance (0-1) that the next card is strictly higher or strictly lower than `rank` (Ace low, King high, equal loses).
function E.hiloChance(rank, dir)
    if dir == 'higher' then return (13 - rank) / 13 end
    return (rank - 1) / 13
end
--- What a correct guess multiplies the stake by: fair odds less the house edge, never below 1.01.
function E.hiloMultiplier(rank, dir, edge)
    local p = E.hiloChance(rank, dir)
    if p <= 0 then return nil end
    local m = floor((1 - edge) / p * 100) / 100
    if m < 1.01 then m = 1.01 end
    return m
end

return E
