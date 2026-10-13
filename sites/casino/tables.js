/* Diamond Online: the table games, blackjack, roulette and baccarat. */
(function () {
    'use strict';
    var esc = DO.esc, $ = DO.$;
    function off(id, name) { if (DO.S.games[id] === false) { DO.render('<div class="do-wrap"><div class="do-note bad">' + name + ' is closed for now.</div></div>'); return true; } return false; }

    /* a row of chip values to pick from; returns { get() } */
    DO.chipBar = function (host, values, def) {
        var cur = def || values[0];
        host.innerHTML = values.map(function (v) { return '<button class="do-chip' + (v === cur ? ' on' : '') + '" data-v="' + v + '">' + DO.money(v) + '</button>'; }).join('');
        host.onclick = function (e) { var b = e.target.closest('button'); if (!b) return; cur = Number(b.dataset.v); DO.$$('button', host).forEach(function (x) { x.classList.toggle('on', x === b); }); DO.sfx('chip'); };
        return { get: function () { return cur; } };
    };

    // ================================================================== blackjack
    var lastBJ = 25;
    DO.page(/^\/blackjack$/, function () {
        if (off('blackjack', 'Blackjack')) return;
        var cfg = DO.S.bets.blackjack, root = DO.render('<div class="do-wrap"><h2 class="do-h">Blackjack</h2><p class="sub">Dealer stands on all 17s. Blackjack pays 3 to 2. Double on any two cards, split up to four hands, insurance and surrender offered.</p><div class="bj" id="bj"></div></div>');
        var host = $('#bj', root), busy = false;

        function handHTML(h, i, v) {
            var tag = h.surrendered ? 'Surrendered' : h.bust ? 'Bust' : h.blackjack ? 'Blackjack' : '';
            var res = v.results && v.results[i];
            var cls = 'bj-hand' + (v.phase === 'play' && i === v.active - 1 ? ' active' : '') + (res === 'win' || res === 'blackjack' ? ' won' : res === 'lose' || res === 'bust' ? ' lost' : '');
            return '<div class="' + cls + '"><div class="bj-cards">' + h.cards.map(function (c) { return DO.card(c); }).join('') + '</div><div class="bj-tot">' + (h.soft && h.total <= 21 ? 'Soft ' : '') + h.total + (tag ? ' · ' + tag : '') + '</div><div class="bj-bet">Bet ' + DO.money(h.bet) + (res ? ' · <b>' + res + '</b>' : '') + '</div></div>';
        }
        function render(v) {
            DO.setBal(v.balance);
            var playing = v.phase === 'play' || v.phase === 'insurance';
            var h = '';
            if (v.phase && v.phase !== 'none') {
                h += '<div class="bj-table"><div class="bj-dealer"><div class="sub small">Dealer ' + (v.dealerHidden ? '' : '· ' + v.dealerTotal) + '</div><div class="bj-cards">' + v.dealer.map(function (c) { return DO.card(c); }).join('') + (v.dealerHidden ? DO.card(-1) : '') + '</div></div>' +
                    '<div class="bj-hands">' + v.hands.map(function (x, i) { return handHTML(x, i, v); }).join('') + '</div></div>';
            } else h += '<div class="bj-table empty"><div class="sub">Place your bet to deal.</div></div>';
            if (v.phase === 'done') {
                var net = v.paid - v.wagered;
                h += '<div class="do-note ' + (net > 0 ? 'good' : net < 0 ? 'bad' : '') + '"><b>' + (net > 0 ? 'You won ' + DO.money(net) : net < 0 ? 'You lost ' + DO.money(-net) : 'Push') + '</b> · ' + DO.money(v.paid) + ' paid back on ' + DO.money(v.wagered) + ' bet</div>';
            }
            if (v.phase === 'insurance') {
                h += '<div class="do-panel"><b>Dealer shows an Ace. Insurance?</b><p class="sub small">Costs ' + DO.money(v.insuranceCost) + ' and pays 2 to 1 if the dealer has blackjack.</p><div class="do-row"><button class="do-btn" data-ins="1">Take insurance</button><button class="do-btn ghost" data-ins="0">No thanks</button></div></div>';
            } else if (v.phase === 'play') {
                var c = v.can;
                h += '<div class="do-row bj-act"><button class="do-btn" data-a="hit"' + (c.hit ? '' : ' disabled') + '>Hit</button><button class="do-btn" data-a="stand"' + (c.stand ? '' : ' disabled') + '>Stand</button><button class="do-btn ghost" data-a="double"' + (c.double ? '' : ' disabled') + '>Double</button><button class="do-btn ghost" data-a="split"' + (c.split ? '' : ' disabled') + '>Split</button><button class="do-btn ghost" data-a="surrender"' + (c.surrender ? '' : ' disabled') + '>Surrender</button></div>';
            } else {
                h += '<div class="do-panel bj-bet-panel"><div id="bb"></div><div class="do-row"><button class="do-btn grow" id="deal">Deal</button></div></div>';
            }
            host.innerHTML = h;
            if (!playing) {
                var bb = DO.betBox($('#bb', host), { min: cfg.min, max: cfg.max, value: lastBJ, chips: [5, 25, 100, 500], onChange: function (n) { lastBJ = n; } });
                $('#deal', host).onclick = async function () {
                    var b = bb.get(); if (DO.bal() < b) { DO.noFunds(b); return; }
                    if (!(await DO.okToBet(b))) return; lastBJ = b; act({ a: 'deal', bet: b });
                };
            }
        }
        async function act(d) {
            if (busy) return; busy = true;
            try { var v = await Site.call('bj', d); DO.sfx(d.a === 'deal' ? 'card' : v.phase === 'done' ? (v.paid > v.wagered ? 'win' : 'lose') : 'card'); render(v); }
            catch (e) { DO.toast(e.message); }
            busy = false;
        }
        host.addEventListener('click', function (e) {
            var b = e.target.closest('button'); if (!b || b.disabled) return;
            if (b.dataset.a) act({ a: b.dataset.a });
            if (b.dataset.ins) act({ a: 'insure', take: b.dataset.ins === '1' });
        });
        Site.call('bj', { a: 'state' }).then(function (v) { render(v.phase ? v : { phase: 'none', balance: v.balance }); }).catch(function (e) { DO.toast(e.message); });
    });

    // ================================================================== roulette
    var WHEEL = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26];
    var RED = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];
    function colourOf(n) { return n === 0 ? 'green' : RED.indexOf(n) >= 0 ? 'red' : 'black'; }
    var rouletteHistory = [];
    DO.page(/^\/roulette$/, function () {
        if (off('roulette', 'Roulette')) return;
        var cfg = DO.S.bets.roulette, bets = {}, order = [], busy = false, lastBets = null;
        var h = '<div class="do-wrap"><h2 class="do-h">Roulette</h2><div class="rl-top"><div class="rl-wheelbox"><div class="rl-wheel" id="wheel"></div><div class="rl-ball" id="ball"><i></i></div><div class="rl-res" id="rres">—</div></div><div class="grow"><div class="rl-hist" id="rh"></div><div id="rmsg" class="do-note" style="display:none"></div><div class="do-panel"><div class="sub small">Chip</div><div class="do-chips" id="chips"></div><div class="do-row" style="margin-top:12px"><div>Total bet <b id="rtot">' + DO.money(0) + '</b></div><div class="grow"></div><button class="do-btn ghost sm" id="rundo">Undo</button><button class="do-btn ghost sm" id="rclear">Clear</button><button class="do-btn ghost sm" id="rrep">Repeat</button><button class="do-btn" id="rspin">Spin</button></div></div></div></div>' +
            '<div class="rl-board" id="board"></div><p class="sub small">Click a number for a straight bet. Click the lines between numbers for splits, streets, corners and six lines. Max ' + DO.money(cfg.max) + ' per spot and ' + DO.money(cfg.maxTotal) + ' per spin.</p></div>';
        var root = DO.render(h), chips = DO.chipBar($('#chips', root), [1, 5, 25, 100, 500], 5);

        // wheel
        var step = 360 / 37, grad = [];
        WHEEL.forEach(function (n, i) { grad.push((colourOf(n) === 'green' ? '#0f8a4a' : colourOf(n) === 'red' ? '#c62828' : '#17171a') + ' ' + (i * step) + 'deg ' + ((i + 1) * step) + 'deg'); });
        var wheel = $('#wheel', root), ball = $('#ball', root);
        wheel.style.background = 'conic-gradient(' + grad.join(',') + ')';
        wheel.innerHTML = WHEEL.map(function (n, i) { return '<span style="transform:rotate(' + ((i + .5) * step) + 'deg) translateY(-98px) rotate(' + (-(i + .5) * step) + 'deg)">' + n + '</span>'; }).join('') + '<div class="rl-hub"></div>';
        function drawHist() { $('#rh', root).innerHTML = rouletteHistory.slice(0, 14).map(function (n) { return '<span class="rl-n ' + colourOf(n) + '">' + n + '</span>'; }).join(''); }
        drawHist();

        // board
        var b = '<div class="rl-grid"><div class="rl-zero" data-k="n" data-v="0"><span class="num">0</span><i class="hs r1" data-k="split" data-v="0" data-w="3"></i><i class="hs r2" data-k="split" data-v="0" data-w="2"></i><i class="hs r3" data-k="split" data-v="0" data-w="1"></i></div>';
        for (var row = 0; row < 3; row++) for (var c = 1; c <= 12; c++) {
            var n = 3 * c - row, hs = '';
            if (c < 12) hs += '<i class="hs right" data-k="split" data-v="' + n + '" data-w="' + (n + 3) + '"></i>';
            if (row > 0) hs += '<i class="hs top" data-k="split" data-v="' + n + '" data-w="' + (n + 1) + '"></i>';
            if (row > 0 && c < 12) hs += '<i class="hs corner" data-k="corner" data-v="' + n + '"></i>';
            if (row === 2) { hs += '<i class="hs bottom" data-k="street" data-v="' + c + '"></i>'; if (c < 12) hs += '<i class="hs bcorner" data-k="line" data-v="' + c + '"></i>'; }
            b += '<div class="rl-num ' + colourOf(n) + '" data-k="n" data-v="' + n + '" style="grid-column:' + (c + 1) + ';grid-row:' + (row + 1) + '"><span class="num">' + n + '</span>' + hs + '</div>';
        }
        for (row = 0; row < 3; row++) b += '<div class="rl-out" data-k="col" data-v="' + (3 - row) + '" style="grid-column:14;grid-row:' + (row + 1) + '">2:1</div>';
        [['1st 12', 1], ['2nd 12', 2], ['3rd 12', 3]].forEach(function (d, i) { b += '<div class="rl-out" data-k="dozen" data-v="' + d[1] + '" style="grid-column:' + (2 + i * 4) + '/span 4;grid-row:4">' + d[0] + '</div>'; });
        [['1-18', 'low', ''], ['Even', 'even', ''], ['Red', 'red', 'red'], ['Black', 'black', 'black'], ['Odd', 'odd', ''], ['19-36', 'high', '']].forEach(function (d, i) { b += '<div class="rl-out ' + d[2] + '" data-k="' + d[1] + '" style="grid-column:' + (2 + i * 2) + '/span 2;grid-row:5">' + d[0] + '</div>'; });
        $('#board', root).innerHTML = b + '</div>';

        function key(k, v, w) { return k + ':' + (v === undefined ? '' : v) + ':' + (w === undefined ? '' : w); }
        function redraw() {
            DO.$$('.chipmark', root).forEach(function (x) { x.remove(); });
            var total = 0;
            Object.keys(bets).forEach(function (kk) {
                var bt = bets[kk]; total += bt.a;
                var sel = '#board [data-k="' + bt.k + '"]' + (bt.v !== undefined ? '[data-v="' + bt.v + '"]' : '') + (bt.w !== undefined ? '[data-w="' + bt.w + '"]' : '');
                var host = $(sel, root); if (!host) return;
                var m = document.createElement('em'); m.className = 'chipmark'; m.textContent = bt.a >= 1000 ? Math.round(bt.a / 100) / 10 + 'k' : bt.a; host.appendChild(m);
            });
            $('#rtot', root).textContent = DO.money(total);
            return total;
        }
        function total() { return Object.keys(bets).reduce(function (s, k) { return s + bets[k].a; }, 0); }
        $('#board', root).addEventListener('click', function (e) {
            if (busy) return;
            var t = e.target.closest('[data-k]'); if (!t) return;
            var k = t.dataset.k, v = t.dataset.v !== undefined ? Number(t.dataset.v) : undefined, w = t.dataset.w !== undefined ? Number(t.dataset.w) : undefined;
            var amt = chips.get(), kk = key(k, v, w), cur = bets[kk] ? bets[kk].a : 0;
            if (cur + amt > cfg.max) { DO.toast('The most on one spot is ' + DO.money(cfg.max) + '.'); return; }
            if (total() + amt > cfg.maxTotal) { DO.toast('The most on one spin is ' + DO.money(cfg.maxTotal) + '.'); return; }
            bets[kk] = { k: k, v: v, w: w, a: cur + amt }; order.push(kk); DO.sfx('chip'); redraw();
        });
        $('#rundo', root).onclick = function () { if (busy) return; var kk = order.pop(); if (!kk || !bets[kk]) return; var bt = bets[kk], amt = chips.get(); bt.a -= Math.min(bt.a, amt); if (bt.a <= 0) delete bets[kk]; redraw(); };
        $('#rclear', root).onclick = function () { if (busy) return; bets = {}; order = []; redraw(); };
        $('#rrep', root).onclick = function () { if (busy || !lastBets) return; bets = JSON.parse(JSON.stringify(lastBets)); order = Object.keys(bets); redraw(); };
        $('#rspin', root).onclick = async function () {
            if (busy) return; var tot = total(); if (!tot) { DO.toast('Place a bet first.'); return; }
            if (tot < cfg.min) { DO.toast('The smallest bet is ' + DO.money(cfg.min) + '.'); return; }
            if (DO.bal() < tot) { DO.noFunds(tot); return; }
            if (!(await DO.okToBet(tot))) return;
            busy = true; var btn = this; btn.disabled = true;
            var payload = Object.keys(bets).map(function (k) { var x = bets[k]; return { k: x.k, v: x.v, w: x.w, a: x.a }; });
            var before = DO.bal(), r;
            try { r = await Site.call('roulette', { bets: payload }); } catch (e) { DO.toast(e.message); busy = false; btn.disabled = false; return; }
            DO.showBal(before - tot); lastBets = JSON.parse(JSON.stringify(bets));
            $('#rmsg', root).style.display = 'none'; $('#rres', root).textContent = '…'; DO.sfx('spin');
            var idx = WHEEL.indexOf(r.number), target = 360 * 6 + (idx + .5) * step;
            ball.style.transition = 'none'; ball.style.transform = 'rotate(0deg)'; wheel.style.transition = 'none'; wheel.style.transform = 'rotate(0deg)'; void ball.offsetWidth;
            ball.style.transition = 'transform 4.2s cubic-bezier(.1,.6,.15,1)'; ball.style.transform = 'rotate(' + target + 'deg)';
            wheel.style.transition = 'transform 4.2s cubic-bezier(.1,.6,.15,1)'; wheel.style.transform = 'rotate(-720deg)';
            await DO.sleep(4400);
            DO.sfx(r.paid > 0 ? (r.paid >= r.wagered * 5 ? 'big' : 'win') : 'lose');
            $('#rres', root).innerHTML = '<span class="rl-n ' + r.colour + '">' + r.number + '</span>';
            rouletteHistory.unshift(r.number); drawHist();
            var net = r.paid - r.wagered, m = $('#rmsg', root); m.style.display = ''; m.className = 'do-note ' + (net > 0 ? 'good' : net < 0 ? 'bad' : '');
            m.innerHTML = '<b>' + r.number + ' ' + r.colour + '</b> · ' + (net > 0 ? 'You won ' + DO.money(net) : net < 0 ? 'You lost ' + DO.money(-net) : 'Break even') + ' (paid ' + DO.money(r.paid) + ')';
            DO.setBal(r.balance); bets = {}; order = []; redraw(); busy = false; btn.disabled = false;
        };
    });

    // ================================================================== baccarat
    var bacHist = [];
    DO.page(/^\/baccarat$/, function () {
        if (off('baccarat', 'Baccarat')) return;
        var cfg = DO.S.bets.baccarat, busy = false, bets = { player: 0, banker: 0, tie: 0, pPair: 0, bPair: 0 };
        var ZONES = [['player', 'Player', 'pays 1 to 1'], ['tie', 'Tie', 'pays 8 to 1'], ['banker', 'Banker', 'pays 0.95 to 1'], ['pPair', 'Player pair', 'pays 11 to 1'], ['bPair', 'Banker pair', 'pays 11 to 1']];
        var root = DO.render('<div class="do-wrap"><h2 class="do-h">Baccarat</h2><p class="sub">Punto banco. Closest to 9 wins. A Player or Banker bet pushes on a tie. Banker wins pay 5% commission.</p>' +
            '<div class="bc-table"><div class="bc-side"><div class="sub small">Player <b id="pt"></b></div><div class="bc-cards" id="pc"></div></div><div class="bc-side"><div class="sub small">Banker <b id="bt"></b></div><div class="bc-cards" id="bcards"></div></div></div><div id="bmsg" class="do-note" style="display:none"></div>' +
            '<div class="bc-zones" id="zones"></div><div class="do-panel"><div class="sub small">Chip</div><div class="do-chips" id="chips"></div><div class="do-row" style="margin-top:12px"><div>Total <b id="btot">' + DO.money(0) + '</b></div><div class="grow"></div><button class="do-btn ghost sm" id="bclear">Clear</button><button class="do-btn" id="bdeal">Deal</button></div></div><div class="bc-road" id="road"></div></div>');
        var chips = DO.chipBar($('#chips', root), [5, 25, 100, 500, 1000], 25);
        function drawZones() {
            $('#zones', root).innerHTML = ZONES.map(function (z) { return '<button class="bc-zone ' + z[0] + (bets[z[0]] ? ' has' : '') + '" data-z="' + z[0] + '"><b>' + z[1] + '</b><small>' + z[2] + '</small>' + (bets[z[0]] ? '<em>' + DO.money(bets[z[0]]) + '</em>' : '') + '</button>'; }).join('');
            $('#btot', root).textContent = DO.money(Object.keys(bets).reduce(function (s, k) { return s + bets[k]; }, 0));
            $('#road', root).innerHTML = bacHist.slice(0, 24).map(function (w) { return '<span class="bc-dot ' + w + '">' + w[0].toUpperCase() + '</span>'; }).join('');
        }
        drawZones();
        $('#zones', root).addEventListener('click', function (e) {
            if (busy) return; var z = e.target.closest('[data-z]'); if (!z) return; var k = z.dataset.z, amt = chips.get();
            if (bets[k] + amt > cfg.max) { DO.toast('The most on one spot is ' + DO.money(cfg.max) + '.'); return; }
            if (k === 'player') bets.banker = 0; if (k === 'banker') bets.player = 0;
            bets[k] += amt; DO.sfx('chip'); drawZones();
        });
        $('#bclear', root).onclick = function () { if (busy) return; Object.keys(bets).forEach(function (k) { bets[k] = 0; }); drawZones(); };
        $('#bdeal', root).onclick = async function () {
            if (busy) return; var tot = Object.keys(bets).reduce(function (s, k) { return s + bets[k]; }, 0);
            if (tot < cfg.min) { DO.toast('The smallest bet is ' + DO.money(cfg.min) + '.'); return; }
            if (DO.bal() < tot) { DO.noFunds(tot); return; }
            if (!(await DO.okToBet(tot))) return;
            busy = true; var btn = this; btn.disabled = true;
            var before = DO.bal(), r;
            try { r = await Site.call('baccarat', { bets: bets }); } catch (e) { DO.toast(e.message); busy = false; btn.disabled = false; return; }
            DO.showBal(before - tot);
            $('#bmsg', root).style.display = 'none'; var P = $('#pc', root), B = $('#bcards', root); P.innerHTML = ''; B.innerHTML = ''; $('#pt', root).textContent = ''; $('#bt', root).textContent = '';
            var seq = [[P, r.player[0]], [B, r.banker[0]], [P, r.player[1]], [B, r.banker[1]], [P, r.player[2]], [B, r.banker[2]]];
            for (var i = 0; i < seq.length; i++) { if (seq[i][1] === undefined || seq[i][1] === null) continue; seq[i][0].insertAdjacentHTML('beforeend', DO.card(seq[i][1])); DO.sfx('card'); await DO.sleep(450); }
            $('#pt', root).textContent = r.p; $('#bt', root).textContent = r.b;
            await DO.sleep(400);
            var net = r.paid - r.wagered, m = $('#bmsg', root); m.style.display = ''; m.className = 'do-note ' + (net > 0 ? 'good' : net < 0 ? 'bad' : '');
            m.innerHTML = '<b>' + (r.winner === 'tie' ? 'Tie' : r.winner === 'player' ? 'Player wins' : 'Banker wins') + ' ' + r.p + ' to ' + r.b + '</b>' + (r.pPair ? ' · Player pair' : '') + (r.bPair ? ' · Banker pair' : '') + ' · ' + (net > 0 ? 'You won ' + DO.money(net) : net < 0 ? 'You lost ' + DO.money(-net) : 'Break even');
            DO.sfx(net > 0 ? 'win' : net < 0 ? 'lose' : 'click');
            bacHist.unshift(r.winner); DO.setBal(r.balance);
            Object.keys(bets).forEach(function (k) { bets[k] = r.bets[k] || 0; }); drawZones();   // the same bets stay on the table to repeat
            busy = false; btn.disabled = false;
        };
    });
})();
