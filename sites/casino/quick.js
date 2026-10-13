/* Diamond Online: crash, video poker and higher or lower. */
(function () {
    'use strict';
    var esc = DO.esc, $ = DO.$;
    function off(id, name) { if (DO.S.games[id] === false) { DO.render('<div class="do-wrap"><div class="do-note bad">' + name + ' is closed for now.</div></div>'); return true; } return false; }

    // ================================================================== crash
    var crashHist = [], lastCrash = { bet: 10, auto: '' };
    DO.page(/^\/crash$/, function () {
        if (off('crash', 'Crash')) return;
        var cfg = DO.S.bets.crash, rate = DO.S.rules.crashRate;
        var root = DO.render('<div class="do-wrap"><h2 class="do-h">Crash</h2><p class="sub">Place a bet and watch the multiplier climb. Cash out before it crashes. Set an auto cash out and it happens for you.</p>' +
            '<div class="cr-stage"><canvas id="cv" width="900" height="360"></canvas><div class="cr-mult" id="mult">1.00×</div><div class="cr-info" id="info"></div></div><div class="cr-hist" id="hist"></div>' +
            '<div class="do-panel cr-ctl"><div class="grow"><div id="bb"></div></div><div class="grow"><label class="do-lbl">Auto cash out at (optional)</label><input type="number" id="auto" step="0.1" min="1.01" placeholder="e.g. 2.00" value="' + lastCrash.auto + '"></div><div class="cr-go"><button class="do-btn" id="go">Place bet</button></div></div></div>');
        var cv = $('#cv', root), ctx = cv.getContext('2d'), mult = $('#mult', root), info = $('#info', root), go = $('#go', root);
        var bb = DO.betBox($('#bb', root), { min: cfg.min, max: cfg.max, value: lastCrash.bet, chips: [1, 10, 50, 100, 500] });
        var running = false, t0 = 0, bet = 0, ended = null, raf = 0, pollId = 0, busy = false, auto = null;
        function m(ms) { return Math.floor(Math.exp(rate * ms / 1000) * 100) / 100; }
        function drawHist() { $('#hist', root).innerHTML = crashHist.slice(0, 16).map(function (x) { return '<span class="cr-h ' + (x >= 2 ? 'hi' : '') + '">' + x.toFixed(2) + '×</span>'; }).join(''); }
        drawHist();
        function draw(ms, crashed) {
            var W = cv.width, H = cv.height; ctx.clearRect(0, 0, W, H);
            var cur = m(ms), maxM = Math.max(2, cur * 1.15), maxT = Math.max(8000, ms * 1.1);
            ctx.strokeStyle = 'rgba(255,255,255,.07)'; ctx.lineWidth = 1;
            for (var i = 1; i < 5; i++) { var yy = H - (H - 30) * (i / 5); ctx.beginPath(); ctx.moveTo(0, yy); ctx.lineTo(W, yy); ctx.stroke(); }
            ctx.beginPath(); ctx.lineWidth = 4; ctx.strokeStyle = crashed ? '#ff8fa3' : '#f2d27a';
            for (var s = 0; s <= 60; s++) { var t = ms * s / 60, x = 20 + (W - 40) * (t / maxT), y = H - 20 - (H - 50) * ((Math.exp(rate * t / 1000) - 1) / (maxM - 1)); if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); }
            ctx.stroke();
        }
        function setMult(v, cls) { mult.textContent = v.toFixed(2) + '×'; mult.className = 'cr-mult' + (cls ? ' ' + cls : ''); }
        function loop() {
            if (!running) return;
            var ms = performance.now() - t0, cur = m(ms); setMult(cur); draw(ms, false);
            if (auto && cur >= auto) { /* the server cashes out for us on the next poll */ }
            raf = requestAnimationFrame(loop);
        }
        function finish(r) {
            running = false; cancelAnimationFrame(raf); clearInterval(pollId); busy = false;
            go.textContent = 'Place bet'; go.disabled = false; go.classList.remove('cash'); bb.lock(false); $('#auto', root).disabled = false;
            if (r.crashAt) { crashHist.unshift(r.crashAt); drawHist(); }
            if (r.busted) { setMult(r.crashAt, 'bust'); draw(performance.now() - t0, true); info.innerHTML = '<span class="neg">Crashed at ' + r.crashAt.toFixed(2) + '×. You lost ' + DO.money(bet) + '.</span>'; DO.sfx('bust'); }
            else if (r.cashed) { setMult(r.mult, 'win'); info.innerHTML = '<span class="pos">Cashed out at ' + r.mult.toFixed(2) + '× and won ' + DO.money(r.win - bet) + '.</span>' + (r.crashAt ? ' <span class="sub small">It crashed at ' + r.crashAt.toFixed(2) + '×.</span>' : ''); DO.sfx(r.mult >= 5 ? 'big' : 'win'); }
            else if (r.refunded) info.textContent = 'The round was refunded.';
            DO.setBal(r.balance);
        }
        function poll() {
            Site.call('crash', { a: 'state' }).then(function (r) {
                if (r.busted || r.cashed || r.refunded) finish(r);
                else if (r.running && r.ms !== undefined) t0 = performance.now() - r.ms;
            }).catch(function () {});
        }
        function begin(ms, b, a) {
            running = true; bet = b; auto = a; t0 = performance.now() - ms; bb.lock(true); $('#auto', root).disabled = true; ended = null;
            go.textContent = 'Cash out'; go.classList.add('cash'); go.disabled = false; info.textContent = 'Bet ' + DO.money(b) + (a ? ' · auto at ' + a.toFixed(2) + '×' : '');
            setMult(1); loop(); clearInterval(pollId); pollId = setInterval(poll, 700); DO.onCleanup(function () { running = false; cancelAnimationFrame(raf); clearInterval(pollId); });
        }
        go.onclick = async function () {
            if (busy) return;
            if (running) {
                busy = true; go.disabled = true;
                try { finish(await Site.call('crash', { a: 'cash' })); } catch (e) { DO.toast(e.message); busy = false; go.disabled = false; }
                return;
            }
            var b = bb.get(), a = Number($('#auto', root).value) || null;
            if (DO.bal() < b) { DO.noFunds(b); return; }
            if (!(await DO.okToBet(b))) return;
            busy = true; go.disabled = true; lastCrash = { bet: b, auto: a || '' };
            try { var r = await Site.call('crash', { a: 'start', bet: b, auto: a }); DO.setBal(r.balance); busy = false; DO.sfx('chip'); begin(0, b, r.auto); }
            catch (e) { DO.toast(e.message); busy = false; go.disabled = false; }
        };
        draw(0, false);
        Site.call('crash', { a: 'state' }).then(function (r) {
            DO.setBal(r.balance);
            if (r.running) { go.disabled = false; begin(r.ms, r.bet, r.auto); } else if (r.busted || r.cashed) { bet = lastCrash.bet; finish(r); }
        }).catch(function () {});
    });

    // ================================================================== video poker
    var PAYS = [['royal', 'Royal flush', 800], ['straightflush', 'Straight flush', 50], ['four', 'Four of a kind', 25], ['fullhouse', 'Full house', 9], ['flush', 'Flush', 6], ['straight', 'Straight', 4], ['three', 'Three of a kind', 3], ['twopair', 'Two pair', 2], ['jacks', 'Jacks or better', 1]];
    var lastPoker = 10;
    DO.page(/^\/poker$/, function () {
        if (off('poker', 'Video Poker')) return;
        var cfg = DO.S.bets.poker, busy = false, hold = [false, false, false, false, false], cards = null, phase = 'none', bet = lastPoker, evalNow = null, result = null;
        var root = DO.render('<div class="do-wrap"><h2 class="do-h">Video Poker</h2><p class="sub">Jacks or Better. Deal, hold the cards you want, then draw once.</p><div class="vp"><div class="vp-pay" id="pay"></div><div class="grow"><div class="vp-cards" id="cards"></div><div id="vmsg" class="do-note" style="display:none"></div><div class="do-panel"><div id="bb"></div><div class="do-row"><button class="do-btn grow" id="vgo">Deal</button></div></div></div></div></div>');
        var bb = DO.betBox($('#bb', root), { min: cfg.min, max: cfg.max, value: bet, chips: [1, 5, 10, 50, 100], onChange: function (n) { lastPoker = n; } });
        function draw() {
            $('#pay', root).innerHTML = '<table class="do-tab">' + PAYS.map(function (p) { var on = (evalNow === p[0] && phase === 'draw') || (result && result.hand === p[0]); return '<tr class="' + (on ? 'hl' : '') + '"><td>' + p[1] + '</td><td class="r">' + p[2] + '×</td></tr>'; }).join('') + '</table>';
            var h = '';
            for (var i = 0; i < 5; i++) { h += '<div class="vp-slot' + (hold[i] ? ' held' : '') + '" data-i="' + i + '">' + (cards ? DO.card(cards[i], 'big') : DO.card(-1, 'big')) + '<div class="vp-hold">' + (phase === 'draw' && hold[i] ? 'HELD' : '') + '</div></div>'; }
            $('#cards', root).innerHTML = h;
            $('#vgo', root).textContent = phase === 'draw' ? 'Draw' : 'Deal';
            bb.lock(phase === 'draw');
        }
        draw();
        $('#cards', root).addEventListener('click', function (e) { var s = e.target.closest('[data-i]'); if (!s || phase !== 'draw' || busy) return; var i = Number(s.dataset.i); hold[i] = !hold[i]; DO.sfx('click'); draw(); });
        $('#vgo', root).onclick = async function () {
            if (busy) return; busy = true; var btn = this; btn.disabled = true;
            try {
                if (phase === 'draw') {
                    var r = await Site.call('poker', { a: 'draw', hold: hold });
                    cards = r.cards; phase = 'done'; result = r; evalNow = null; draw();
                    var m = $('#vmsg', root); m.style.display = ''; m.className = 'do-note ' + (r.win ? 'good' : '');
                    m.innerHTML = r.win ? '<b>' + esc(r.handName) + '</b> · Paid ' + DO.money(r.win) : 'No win this time.';
                    DO.sfx(r.win ? (r.win >= r.bet * 9 ? 'big' : 'win') : 'lose'); DO.setBal(r.balance);
                } else {
                    var b = bb.get(); if (DO.bal() < b) { DO.noFunds(b); busy = false; btn.disabled = false; return; }
                    if (!(await DO.okToBet(b))) { busy = false; btn.disabled = false; return; }
                    var r2 = await Site.call('poker', { a: 'deal', bet: b });
                    hold = [false, false, false, false, false]; cards = r2.cards; phase = 'draw'; evalNow = r2.eval; result = null; $('#vmsg', root).style.display = 'none'; bet = b; DO.sfx('card'); draw(); DO.setBal(r2.balance);
                }
            } catch (e) { DO.toast(e.message); }
            busy = false; btn.disabled = false;
        };
        Site.call('poker', { a: 'state' }).then(function (r) { DO.setBal(r.balance); if (r.phase === 'draw') { cards = r.cards; phase = 'draw'; evalNow = r.eval; bet = r.bet; draw(); } }).catch(function () {});
    });

    // ================================================================== higher or lower
    var lastHilo = 10;
    DO.page(/^\/higher-lower$/, function () {
        if (off('hilo', 'Higher or Lower')) return;
        var cfg = DO.S.bets.hilo, busy = false, st = null, trail = [];
        var root = DO.render('<div class="do-wrap"><h2 class="do-h">Higher or Lower</h2><p class="sub">Is the next card higher or lower? Aces are low, kings high, and a matching card loses. Each right call raises your multiplier: cash out whenever you like.</p><div id="hl"></div></div>');
        var host = $('#hl', root);
        function render(msg) {
            var h = '';
            if (!st) {
                h = '<div class="hl-table"><div class="hl-card">' + DO.card(-1, 'big') + '</div></div>' + (msg || '') + '<div class="do-panel"><div id="bb"></div><div class="do-row"><button class="do-btn grow" id="start">Deal</button></div></div>';
            } else {
                h = '<div class="hl-table"><div class="hl-trail">' + trail.slice(-5).map(function (c) { return DO.card(c, 'sm'); }).join('') + '</div><div class="hl-card">' + DO.card(st.card, 'big') + '</div>' +
                    '<div class="hl-info"><div><span class="sub small">Streak</span><b>' + st.steps + '</b></div><div><span class="sub small">Multiplier</span><b>' + st.mult.toFixed(2) + '×</b></div><div><span class="sub small">Cash out now</span><b>' + DO.money(st.win) + '</b></div></div></div>' + (msg || '') +
                    '<div class="do-row hl-act"><button class="do-btn grow" data-a="higher"' + (st.higher ? '' : ' disabled') + '>Higher' + (st.higher ? ' · ×' + st.higher.toFixed(2) + ' (' + Math.round(st.higherChance * 100) + '%)' : '') + '</button><button class="do-btn grow" data-a="lower"' + (st.lower ? '' : ' disabled') + '>Lower' + (st.lower ? ' · ×' + st.lower.toFixed(2) + ' (' + Math.round(st.lowerChance * 100) + '%)' : '') + '</button></div>' +
                    '<div class="do-row"><button class="do-btn ghost grow" data-a="skip"' + (st.skips > 0 ? '' : ' disabled') + '>Skip card (' + st.skips + ' left)</button><button class="do-btn ghost grow" data-a="cash"' + (st.steps > 0 ? '' : ' disabled') + '>Cash out ' + DO.money(st.win) + '</button></div>';
            }
            host.innerHTML = h;
            if (!st) {
                var bb = DO.betBox($('#bb', host), { min: cfg.min, max: cfg.max, value: lastHilo, chips: [1, 10, 50, 100, 500], onChange: function (n) { lastHilo = n; } });
                $('#start', host).onclick = async function () {
                    var b = bb.get(); if (DO.bal() < b) { DO.noFunds(b); return; } if (!(await DO.okToBet(b))) return;
                    try { trail = []; st = await Site.call('hilo', { a: 'start', bet: b }); lastHilo = b; DO.setBal(st.balance); DO.sfx('card'); render(); } catch (e) { DO.toast(e.message); }
                };
            }
        }
        host.addEventListener('click', async function (e) {
            var b = e.target.closest('[data-a]'); if (!b || b.disabled || busy || !st) return; busy = true;
            try {
                var r = await Site.call('hilo', { a: b.dataset.a });
                if (r.lost) { DO.sfx('lose'); DO.setBal(r.balance); var bet = r.bet; trail.push(st.card); st = null; render('<div class="do-note bad"><b>Wrong.</b> The card was ' + DO.card(r.card, 'sm') + ' You lost ' + DO.money(bet) + '.</div>'); }
                else if (r.cashed) { DO.sfx(r.win >= st.bet * 5 ? 'big' : 'win'); DO.setBal(r.balance); var w = r.win; st = null; render('<div class="do-note good"><b>Cashed out ' + DO.money(w) + '</b>' + (r.limit ? ' (streak limit reached)' : '') + '</div>'); }
                else { if (b.dataset.a !== 'skip' && r.previous !== undefined) { trail.push(r.previous); DO.sfx('win'); } else DO.sfx('card'); st = r; DO.setBal(r.balance); render(); }
            } catch (err) { DO.toast(err.message); }
            busy = false;
        });
        Site.call('hilo', { a: 'state' }).then(function (r) { DO.setBal(r.balance); if (!r.idle) st = r; render(); }).catch(function () { render(); });
    });
})();
