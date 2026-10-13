-- Diamond Online: the game requests. Every bet is checked, taken from the balance and settled here, never on the page. The maths is in
-- server_engine.lua. A game that has more than one step (blackjack, crash, video poker, higher or lower) is kept in casino_rounds, so
-- closing the browser or losing connection never loses or duplicates a bet.
local C = Casino
local E = Casino.engine
local CFG = Config.casino or {}
local floor = math.floor

local function gcfg(id) return (CFG.games or {})[id] or {} end
local function betIn(id, v)   -- a bet within the game's min and max
    local g = gcfg(id)
    local n = C.whole(v)
    if not n or n < (g.min or 1) then return nil, T('casino.err.minBet', g.min or 1) end
    if g.max and n > g.max then return nil, T('casino.err.maxBet', g.max) end
    return n
end

-- ============================================================================================================================
-- SLOTS
-- ============================================================================================================================
Browser.handler('casino', 'slots', function(src, d)
    return C.guard(src, 'slots', function(s, a)
        local m = E.slots[tostring(d.machine or '')]
        if not m then return nil, T('casino.err.badBet') end
        local bet = C.whole(d.bet)
        local ok = false
        for _, v in ipairs(gcfg('slots').levels or {}) do if v == bet then ok = true end end
        if not ok then return nil, T('casino.err.badBet') end
        local okStake, e = C.stake(a, bet); if not okStake then return nil, e end
        local eligible = m.jackpot and bet >= (tonumber(gcfg('slots').jackpotMinBet) or 100)
        if m.jackpot then C.addJackpot(bet) end
        local r = E.slotSpin(m.id, bet, eligible)
        local win = r.win
        local jackpot = 0
        if r.jackpot then jackpot = C.takeJackpot(); win = win + jackpot end
        C.settle(s, a, 'slots-' .. m.id, bet, win, ('bet %d win %d%s'):format(bet, win, r.free and ' free spins' or ''))
        r.win = win; r.jackpotWon = jackpot; r.balance = a.balance; r.jackpot = nil
        r.pool = C.jackpot()
        return r
    end)
end)

-- ============================================================================================================================
-- BLACKJACK
-- ============================================================================================================================
local function bjHandView(h)
    local t, soft = E.bjTotal(h.cards)
    return { cards = h.cards, bet = h.bet, total = t, soft = soft, done = h.done, doubled = h.doubled, bust = t > 21, surrendered = h.surrendered, blackjack = h.natural }
end

local function bjCan(st, a)
    local h = st.hands[st.active]
    local c = { hit = false, stand = false, double = false, split = false, surrender = false }
    if st.phase ~= 'play' or not h or h.done then return c end
    c.hit, c.stand = true, true
    if #h.cards == 2 then
        c.double = a.balance >= h.bet
        if #st.hands < 4 and not h.aceSplit and E.bjCardValue(h.cards[1]) == E.bjCardValue(h.cards[2]) then c.split = a.balance >= h.bet end
        if #st.hands == 1 and not h.fromSplit then c.surrender = true end
    end
    return c
end

local function bjView(st, a)
    local v = { phase = st.phase, active = st.active, insurance = st.insurance, hands = {}, balance = a.balance, can = bjCan(st, a) }
    for i, h in ipairs(st.hands) do v.hands[i] = bjHandView(h) end
    if st.phase == 'done' then
        v.dealer = st.dealer; v.dealerTotal = E.bjTotal(st.dealer)
        v.results = st.results; v.paid = st.paid; v.wagered = st.wagered
    else
        v.dealer = { st.dealer[1] }; v.dealerHidden = true
        v.dealerTotal = (E.bjTotal({ st.dealer[1] }))
    end
    if st.phase == 'insurance' then v.insuranceCost = floor(st.hands[1].bet / 2) end
    return v
end
E.bjCardValue = E.bjCardValue or function(c) local r = E.rank(c); if r == 1 then return 11 elseif r >= 10 then return 10 else return r end end

local function bjFinish(s, a, st)
    -- dealer plays only if some hand is still alive
    local alive = false
    for _, h in ipairs(st.hands) do local t = E.bjTotal(h.cards); if not h.surrendered and t <= 21 and not h.natural then alive = true end end
    local dealerBJ = E.bjBlackjack(st.dealer)
    if alive and not dealerBJ then E.bjDealerPlay(st.dealer) end
    local dt = E.bjTotal(st.dealer)
    local paid, wagered, results = 0, 0, {}
    for i, h in ipairs(st.hands) do
        local t = E.bjTotal(h.cards)
        wagered = wagered + h.bet
        local back, res = 0, 'lose'
        if h.surrendered then back, res = floor(h.bet / 2), 'surrender'
        elseif h.natural and not dealerBJ then back, res = h.bet + floor(h.bet * 1.5), 'blackjack'
        elseif t > 21 then back, res = 0, 'bust'
        elseif dealerBJ then if h.natural then back, res = h.bet, 'push' else back, res = 0, 'lose' end
        elseif dt > 21 or t > dt then back, res = h.bet * 2, 'win'
        elseif t == dt then back, res = h.bet, 'push'
        end
        paid = paid + back; results[i] = res
    end
    if st.insurance and st.insurance > 0 then
        wagered = wagered + st.insurance
        if dealerBJ then paid = paid + st.insurance * 3 end
    end
    st.phase, st.results, st.paid, st.wagered = 'done', results, paid, wagered
    C.settle(s, a, 'blackjack', wagered, paid, ('hands %d dealer %d'):format(#st.hands, dt))
    C.roundClear(a.cid, 'blackjack')
end

local function bjAdvance(s, a, st)
    -- next hand that is still to play, or the dealer
    for i = st.active, #st.hands do
        local h = st.hands[i]
        if not h.done then
            local t = E.bjTotal(h.cards)
            if t >= 21 then h.done = true else st.active = i; return end
        end
    end
    bjFinish(s, a, st)
end

local function bjPeek(s, a, st)
    -- the dealer looks at the hole card when the up card is an Ace or a ten: a blackjack ends the round now
    if E.bjBlackjack(st.dealer) then return bjFinish(s, a, st) end
    local h = st.hands[1]
    if h.natural then return bjFinish(s, a, st) end
    st.phase = 'play'; st.active = 1
end

Browser.handler('casino', 'bj', function(src, d)
    return C.guard(src, 'blackjack', function(s, a)
        local st = C.roundGet(a.cid, 'blackjack')
        local act = tostring(d.a or '')
        if act == 'state' then return st and bjView(st, a) or { phase = 'none', balance = a.balance } end
        if act == 'deal' then
            if st then return nil, T('casino.err.roundOpen') end
            local bet, e = betIn('blackjack', d.bet); if not bet then return nil, e end
            local ok, e2 = C.stake(a, bet); if not ok then return nil, e2 end
            st = { phase = 'play', active = 1, insurance = 0, dealer = { E.card(), E.card() }, hands = { { cards = { E.card(), E.card() }, bet = bet, done = false } } }
            local h = st.hands[1]
            h.natural = E.bjBlackjack(h.cards)
            if E.rank(st.dealer[1]) == 1 then st.phase = 'insurance'
            elseif E.bjTenValue(st.dealer[1]) then bjPeek(s, a, st)
            elseif h.natural then bjFinish(s, a, st) end
            if st.phase ~= 'done' then C.roundSet(a.cid, 'blackjack', st) end
            return bjView(st, a)
        end
        if not st then return nil, T('casino.err.noRound') end
        if act == 'insure' then
            if st.phase ~= 'insurance' then return nil, T('casino.err.badMove') end
            if d.take then
                local cost = floor(st.hands[1].bet / 2)
                if cost > 0 then
                    local ok, e = C.stake(a, cost); if not ok then return nil, e end
                    st.insurance = cost
                end
            end
            bjPeek(s, a, st)
            if st.phase ~= 'done' then C.roundSet(a.cid, 'blackjack', st) end
            return bjView(st, a)
        end
        if st.phase ~= 'play' then return nil, T('casino.err.badMove') end
        local h = st.hands[st.active]
        if not h or h.done then return nil, T('casino.err.badMove') end
        local can = bjCan(st, a)
        if act == 'hit' and can.hit then
            h.cards[#h.cards + 1] = E.card()
            if E.bjTotal(h.cards) >= 21 then h.done = true; bjAdvance(s, a, st) end
        elseif act == 'stand' and can.stand then
            h.done = true; bjAdvance(s, a, st)
        elseif act == 'double' and can.double then
            local ok, e = C.stake(a, h.bet); if not ok then return nil, e end
            h.bet = h.bet * 2; h.doubled = true
            h.cards[#h.cards + 1] = E.card(); h.done = true; bjAdvance(s, a, st)
        elseif act == 'split' and can.split then
            local ok, e = C.stake(a, h.bet); if not ok then return nil, e end
            local isAce = E.rank(h.cards[1]) == 1
            local second = { cards = { h.cards[2], E.card() }, bet = h.bet, done = false, fromSplit = true, aceSplit = isAce }
            h.cards = { h.cards[1], E.card() }; h.fromSplit = true; h.aceSplit = isAce; h.natural = false
            table.insert(st.hands, st.active + 1, second)
            if isAce then h.done = true; second.done = true end
            bjAdvance(s, a, st)
        elseif act == 'surrender' and can.surrender then
            h.surrendered = true; h.done = true; bjAdvance(s, a, st)
        else
            return nil, T('casino.err.badMove')
        end
        if st.phase ~= 'done' then C.roundSet(a.cid, 'blackjack', st) end
        return bjView(st, a)
    end)
end)

-- ============================================================================================================================
-- ROULETTE
-- ============================================================================================================================
Browser.handler('casino', 'roulette', function(src, d)
    return C.guard(src, 'roulette', function(s, a)
        local g = gcfg('roulette')
        if type(d.bets) ~= 'table' or #d.bets == 0 or #d.bets > 40 then return nil, T('casino.err.badBet') end
        local list, total = {}, 0
        for _, b in ipairs(d.bets) do
            if type(b) ~= 'table' then return nil, T('casino.err.badBet') end
            local amount = C.whole(b.a)
            if not amount or amount < (g.min or 1) then return nil, T('casino.err.minBet', g.min or 1) end
            local set, pay
            if b.k == 'split' then set, pay = E.rouletteSplit(b.v, b.w) else set, pay = E.rouletteBet(tostring(b.k or ''), b.v) end
            if not set then return nil, T('casino.err.badBet') end
            list[#list + 1] = { amount = amount, set = set, pay = pay, k = b.k, v = b.v, w = b.w }
            total = total + amount
        end
        -- the same spot placed twice counts as one chip stack for the maximum
        local per = {}
        for _, b in ipairs(list) do local key = tostring(b.k) .. ':' .. tostring(b.v) .. ':' .. tostring(b.w); per[key] = (per[key] or 0) + b.amount; if per[key] > (g.max or 1e9) then return nil, T('casino.err.maxBet', g.max) end end
        if total > (g.maxTotal or 1e9) then return nil, T('casino.err.maxBet', g.maxTotal) end
        local ok, e = C.stake(a, total); if not ok then return nil, e end
        local n = E.rouletteSpin()
        local paid = 0
        for _, b in ipairs(list) do
            local hit = false
            for _, x in ipairs(b.set) do if x == n then hit = true; break end end
            b.won = hit and b.amount * (b.pay + 1) or 0
            paid = paid + b.won
        end
        C.settle(s, a, 'roulette', total, paid, ('number %d bets %d'):format(n, #list))
        local out = {}
        for i, b in ipairs(list) do out[i] = { k = b.k, v = b.v, w = b.w, a = b.amount, won = b.won } end
        return { number = n, colour = E.rouletteColour(n), bets = out, wagered = total, paid = paid, balance = a.balance }
    end)
end)

-- ============================================================================================================================
-- CRASH
-- ============================================================================================================================
local function crashNow(st)
    local t = GetGameTimer()
    if t < st.startedAt then return nil end   -- the server restarted mid round
    return t - st.startedAt
end

local function crashResolve(s, a, st, cashing)
    local ms = crashNow(st)
    if not ms then   -- server restarted: give the stake back
        C.settle(s, a, 'crash', 0, st.bet, 'refund after restart'); C.adjust(a, 0); C.roundClear(a.cid, 'crash')
        return { refunded = true, balance = a.balance }
    end
    local m = E.crashMultiplier(ms)
    local auto = st.auto
    if auto and st.crashAt >= auto and m >= auto then
        local win = floor(st.bet * auto)
        C.settle(s, a, 'crash', st.bet, win, ('cashed %.2f'):format(auto)); C.roundClear(a.cid, 'crash')
        return { cashed = true, mult = auto, win = win, balance = a.balance, crashAt = st.crashAt }
    end
    if m >= st.crashAt then
        C.settle(s, a, 'crash', st.bet, 0, ('crashed %.2f'):format(st.crashAt)); C.roundClear(a.cid, 'crash')
        return { busted = true, crashAt = st.crashAt, balance = a.balance }
    end
    if cashing then
        local win = floor(st.bet * m)
        C.settle(s, a, 'crash', st.bet, win, ('cashed %.2f'):format(m)); C.roundClear(a.cid, 'crash')
        return { cashed = true, mult = m, win = win, balance = a.balance, crashAt = st.crashAt }
    end
    return { running = true, mult = m, balance = a.balance, bet = st.bet, auto = st.auto, ms = ms }
end

Browser.handler('casino', 'crash', function(src, d)
    return C.guard(src, 'crash', function(s, a)
        local st = C.roundGet(a.cid, 'crash')
        local act = tostring(d.a or '')
        if act == 'start' then
            if st then return nil, T('casino.err.roundOpen') end
            local bet, e = betIn('crash', d.bet); if not bet then return nil, e end
            local auto = tonumber(d.auto)
            if auto and (auto ~= auto or auto < 1.01 or auto > 1000) then auto = nil end
            if auto then auto = floor(auto * 100) / 100 end
            local ok, e2 = C.stake(a, bet); if not ok then return nil, e2 end
            st = { bet = bet, auto = auto, startedAt = GetGameTimer(), crashAt = E.crashPoint(tonumber(gcfg('crash').edge) or 0.01) }
            C.roundSet(a.cid, 'crash', st)
            return { running = true, mult = 1, ms = 0, bet = bet, auto = auto, balance = a.balance }
        end
        if not st then return act == 'state' and { idle = true, balance = a.balance } or nil, act ~= 'state' and T('casino.err.noRound') or nil end
        if act == 'state' then return crashResolve(s, a, st, false) end
        if act == 'cash' then return crashResolve(s, a, st, true) end
        return nil, T('casino.err.badMove')
    end)
end)

-- ============================================================================================================================
-- VIDEO POKER
-- ============================================================================================================================
local pokerNames = { royal = 'Royal flush', straightflush = 'Straight flush', four = 'Four of a kind', fullhouse = 'Full house', flush = 'Flush', straight = 'Straight', three = 'Three of a kind', twopair = 'Two pair', jacks = 'Jacks or better' }
Browser.handler('casino', 'poker', function(src, d)
    return C.guard(src, 'poker', function(s, a)
        local st = C.roundGet(a.cid, 'poker')
        local act = tostring(d.a or '')
        if act == 'state' then
            if st then return { phase = 'draw', cards = st.cards, bet = st.bet, eval = E.pokerEval(st.cards), balance = a.balance } end
            return { phase = 'none', balance = a.balance }
        end
        if act == 'deal' then
            if st then return nil, T('casino.err.roundOpen') end
            local bet, e = betIn('poker', d.bet); if not bet then return nil, e end
            local ok, e2 = C.stake(a, bet); if not ok then return nil, e2 end
            st = { bet = bet, cards = E.pokerDeal() }
            C.roundSet(a.cid, 'poker', st)
            return { phase = 'draw', cards = st.cards, bet = bet, eval = E.pokerEval(st.cards), balance = a.balance }
        end
        if not st then return nil, T('casino.err.noRound') end
        if act == 'draw' then
            local hold = {}
            if type(d.hold) == 'table' then for i = 1, 5 do hold[i] = d.hold[i] == true end end
            local cards = E.pokerDraw(st.cards, hold)
            local hand = E.pokerEval(cards)
            local win = hand and st.bet * E.pokerPays[hand] or 0
            C.settle(s, a, 'poker', st.bet, win, hand or 'no win'); C.roundClear(a.cid, 'poker')
            return { phase = 'done', cards = cards, held = hold, hand = hand, handName = hand and pokerNames[hand] or nil, win = win, bet = st.bet, balance = a.balance }
        end
        return nil, T('casino.err.badMove')
    end)
end)

-- ============================================================================================================================
-- BACCARAT
-- ============================================================================================================================
Browser.handler('casino', 'baccarat', function(src, d)
    return C.guard(src, 'baccarat', function(s, a)
        local g = gcfg('baccarat')
        local b = type(d.bets) == 'table' and d.bets or {}
        local bets, total = {}, 0
        for _, key in ipairs({ 'player', 'banker', 'tie', 'pPair', 'bPair' }) do
            local n = C.whole(b[key]) or 0
            if n < 0 or (n > 0 and n > (g.max or 1e9)) then return nil, T('casino.err.maxBet', g.max) end
            bets[key] = n; total = total + n
        end
        if total < (g.min or 1) then return nil, T('casino.err.minBet', g.min or 1) end
        if bets.player > 0 and bets.banker > 0 then return nil, T('casino.err.baccaratBoth') end
        local ok, e = C.stake(a, total); if not ok then return nil, e end
        local r = E.baccaratDeal()
        local paid = 0
        if r.winner == 'player' then paid = paid + bets.player * 2
        elseif r.winner == 'banker' then paid = paid + bets.banker + floor(bets.banker * 1.95 - bets.banker)
        else paid = paid + bets.player + bets.banker + bets.tie * 9 end
        if r.pPair then paid = paid + bets.pPair * 12 end
        if r.bPair then paid = paid + bets.bPair * 12 end
        C.settle(s, a, 'baccarat', total, paid, ('%s %d-%d'):format(r.winner, r.p, r.b))
        r.bets, r.wagered, r.paid, r.balance = bets, total, paid, a.balance
        return r
    end)
end)

-- ============================================================================================================================
-- HIGHER OR LOWER
-- ============================================================================================================================
local function hiloView(st, a)
    local edge = tonumber(gcfg('hilo').edge) or 0.04
    local rank = E.rank(st.card)
    return { card = st.card, bet = st.bet, steps = st.steps, mult = st.mult, win = floor(st.bet * st.mult), skips = st.skips,
        higher = E.hiloMultiplier(rank, 'higher', edge), lower = E.hiloMultiplier(rank, 'lower', edge),
        higherChance = E.hiloChance(rank, 'higher'), lowerChance = E.hiloChance(rank, 'lower'), balance = a.balance }
end

Browser.handler('casino', 'hilo', function(src, d)
    return C.guard(src, 'hilo', function(s, a)
        local cfg = gcfg('hilo')
        local edge = tonumber(cfg.edge) or 0.04
        local st = C.roundGet(a.cid, 'hilo')
        local act = tostring(d.a or '')
        if act == 'state' then return st and hiloView(st, a) or { idle = true, balance = a.balance } end
        if act == 'start' then
            if st then return nil, T('casino.err.roundOpen') end
            local bet, e = betIn('hilo', d.bet); if not bet then return nil, e end
            local ok, e2 = C.stake(a, bet); if not ok then return nil, e2 end
            st = { bet = bet, card = E.card(), steps = 0, mult = 1, skips = 3 }
            C.roundSet(a.cid, 'hilo', st)
            return hiloView(st, a)
        end
        if not st then return nil, T('casino.err.noRound') end
        if act == 'skip' then
            if st.skips <= 0 then return nil, T('casino.err.badMove') end
            st.skips = st.skips - 1; st.card = E.card()
            C.roundSet(a.cid, 'hilo', st)
            return hiloView(st, a)
        end
        if act == 'cash' then
            if st.steps < 1 then return nil, T('casino.err.badMove') end
            local win = floor(st.bet * st.mult)
            C.settle(s, a, 'hilo', st.bet, win, ('cashed x%.2f after %d'):format(st.mult, st.steps)); C.roundClear(a.cid, 'hilo')
            local v = hiloView(st, a); v.cashed, v.win = true, win; return v
        end
        if act == 'higher' or act == 'lower' then
            local rank = E.rank(st.card)
            local step = E.hiloMultiplier(rank, act, edge)
            if not step then return nil, T('casino.err.badMove') end
            local nxt = E.card()
            local nr = E.rank(nxt)
            local won = (act == 'higher' and nr > rank) or (act == 'lower' and nr < rank)
            if not won then
                C.settle(s, a, 'hilo', st.bet, 0, ('lost after %d'):format(st.steps)); C.roundClear(a.cid, 'hilo')
                return { lost = true, card = nxt, previous = st.card, bet = st.bet, steps = st.steps, balance = a.balance }
            end
            st.previous, st.card, st.steps, st.mult = st.card, nxt, st.steps + 1, floor(st.mult * step * 100) / 100
            if st.steps >= (tonumber(cfg.maxSteps) or 12) then
                local win = floor(st.bet * st.mult)
                C.settle(s, a, 'hilo', st.bet, win, ('cashed x%.2f at the limit'):format(st.mult)); C.roundClear(a.cid, 'hilo')
                local v = hiloView(st, a); v.cashed, v.win, v.limit = true, win, true; return v
            end
            C.roundSet(a.cid, 'hilo', st)
            local v = hiloView(st, a); v.correct, v.previous = true, st.previous; return v
        end
        return nil, T('casino.err.badMove')
    end)
end)
