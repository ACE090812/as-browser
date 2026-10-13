/* Diamond Online: the slots lobby and the six machines. The server decides every spin; this file only draws the result. */
(function () {
    'use strict';
    var esc = DO.esc, $ = DO.$;
    var LINES5 = [[2,2,2,2,2],[1,1,1,1,1],[3,3,3,3,3],[1,2,3,2,1],[3,2,1,2,3],[1,1,2,3,3],[3,3,2,1,1],[2,1,1,1,2],[2,3,3,3,2],[1,2,2,2,3]];
    var LINES3 = [[2,2,2],[1,1,1],[3,3,3],[1,2,3],[3,2,1]];
    function T(t, c) { return { t: t, c: c }; }
    var LOW = { L1: T('9', '#9aa3b0'), L2: T('10', '#7cc4ff'), L3: T('J', '#7be0a4'), L4: T('Q', '#ffb86b') };
    function skin(extra) { var o = {}; Object.keys(LOW).forEach(function (k) { o[k] = LOW[k]; }); Object.keys(extra).forEach(function (k) { o[k] = extra[k]; }); return o; }
    var SKINS = {
        diamond: { grad: 'linear-gradient(160deg,#2a0b4d,#5b21b6)', accent: '#c4b5fd', sym: skin({ L1: T('♣', '#9aa3b0'), L2: T('♦', '#ff8fa3'), L3: T('♥', '#ff6b81'), L4: T('♠', '#cbd5e1'), H1: T('🔔', ''), H2: T('🍀', ''), H3: T('👑', ''), H4: T('💎', ''), W: T('🃏', ''), S: T('⭐', ''), J: T('💠', '') }) },
        gold: { grad: 'linear-gradient(160deg,#4a2a0c,#a0601c)', accent: '#ffd479', sym: skin({ H1: T('🌵', ''), H2: T('🐎', ''), H3: T('🔫', ''), H4: T('🤠', ''), W: T('💰', ''), S: T('🪙', '') }) },
        neptune: { grad: 'linear-gradient(160deg,#052b4a,#0e7490)', accent: '#7ee7ff', sym: skin({ H1: T('🐚', ''), H2: T('🦀', ''), H3: T('🐙', ''), H4: T('🧜', ''), W: T('🔱', ''), S: T('🐠', '') }) },
        pharaoh: { grad: 'linear-gradient(160deg,#3b2a06,#a16207)', accent: '#ffe08a', sym: skin({ H1: T('🐍', ''), H2: T('🪲', ''), H3: T('👁️', ''), H4: T('🏺', ''), W: T('🔺', ''), S: T('🗝️', '') }) },
        dragon: { grad: 'linear-gradient(160deg,#4a0712,#b91c1c)', accent: '#ffd479', sym: skin({ H1: T('🧧', ''), H2: T('🏮', ''), H3: T('🎆', ''), H4: T('🐉', ''), W: T('🌕', ''), S: T('🥮', '') }) },
        neon: { grad: 'linear-gradient(160deg,#07141f,#0a0a2e)', accent: '#ff4fd8', sym: { L1: T('🍒', ''), L2: T('🍋', ''), L3: T('🔔', ''), H1: T('BAR', '#7cc4ff'), H2: T('★', '#ffd479'), H3: T('7', '#ff4f6e'), W: T('WILD', '#ff4fd8') } },
    };
    var NAMES = { L1: 'Nines', L2: 'Tens', L3: 'Jacks', L4: 'Queens' };
    function symHTML(id, k) { var s = (SKINS[id].sym[k]) || T('?', ''); return '<span class="sy' + (s.t.length > 2 && /^[A-Z]/.test(s.t) ? ' txt' : '') + '" style="' + (s.c ? 'color:' + s.c : '') + '">' + s.t + '</span>'; }
    var INFO = function (id) { return DO.S.slots.filter(function (m) { return m.id === id; })[0]; };

    // ------------------------------------------------------------------ lobby
    DO.page(/^\/slots$/, function () {
        var S = DO.S;
        if (S.games.slots === false) { DO.render('<div class="do-wrap"><div class="do-note bad">Slots are closed for now.</div></div>'); return; }
        var h = '<div class="do-wrap"><h2 class="do-h">Slots</h2><p class="sub">Six machines, each with its own theme, paylines and free spins.</p><div class="sl-lobby">';
        S.slots.forEach(function (m) {
            var sk = SKINS[m.id];
            h += '<a class="sl-card" data-go="/slots/' + m.id + '" style="background:' + sk.grad + '"><div class="sl-prev">' + ['H4', 'H3', 'H2'].map(function (k) { return symHTML(m.id, SKINS[m.id].sym[k] ? k : 'H3'); }).join('') + '</div><b>' + esc(m.name) + '</b><small>' + esc(m.theme) + ' · ' + m.reels + ' reels · ' + m.lines + ' lines</small>' +
                (m.jackpot ? '<span class="sl-jpt" id="jp-' + m.id + '">Jackpot ' + DO.money(S.jackpot) + '</span>' : '') + (m.free ? '<span class="sl-tag">Free spins</span>' : '<span class="sl-tag">Classic</span>') + '</a>';
        });
        DO.render(h + '</div></div>');
    });

    // ------------------------------------------------------------------ a machine
    var betIdx = 4;
    DO.page(/^\/slots\/(\w+)$/, function (m) {
        var S = DO.S, id = m[1], info = INFO(id);
        if (!info || S.games.slots === false) { Site.go('/slots'); return; }
        var sk = SKINS[id], levels = S.bets.slots, LINES = info.reels === 3 ? LINES3 : LINES5;
        betIdx = Math.max(0, Math.min(levels.length - 1, betIdx));
        var CELL = 'var(--cell)';
        var root = DO.render('<div class="do-wrap"><div class="do-row"><a class="sub" data-go="/slots">← Slots</a><div class="grow"></div><button class="do-btn ghost sm" id="pt">Paytable</button></div>' +
            '<div class="sl-machine" style="background:' + sk.grad + ';--acc:' + sk.accent + '"><div class="sl-title">' + esc(info.name) + '</div>' + (info.jackpot ? '<div class="sl-jackpot">JACKPOT <b id="jpv">' + DO.money(S.jackpot) + '</b></div>' : '') +
            '<div class="sl-frame"><div class="sl-reels" id="reels" style="--n:' + info.reels + ';--r:' + info.rows + '"></div><div class="sl-banner" id="banner"></div></div>' +
            '<div class="sl-status"><span id="fs"></span><span>Win <b id="win">' + DO.money(0) + '</b></span></div></div>' +
            '<div class="sl-bar"><div class="sl-bet"><button class="do-sm" id="bm">−</button><div><div class="sub small">Bet</div><b id="bet"></b></div><button class="do-sm" id="bp">+</button><button class="do-chip" id="bmax">Max</button></div>' +
            '<button class="do-btn sl-spin" id="spin">SPIN</button><div class="sl-opts"><select id="auto"><option value="0">Autoplay</option><option value="10">10 spins</option><option value="25">25 spins</option><option value="50">50 spins</option><option value="100">100 spins</option></select><label class="do-check" style="margin:0"><input type="checkbox" id="turbo"><span>Turbo</span></label></div></div></div>');
        var reelsEl = $('#reels', root), banner = $('#banner', root);
        var cur = [], busy = false, stopAuto = false, autoLeft = 0;
        function rand() { var keys = Object.keys(sk.sym).filter(function (k) { return k !== 'J' || info.jackpot; }); return keys[Math.floor(Math.random() * keys.length)]; }
        for (var r = 0; r < info.rows; r++) { cur[r] = []; for (var c = 0; c < info.reels; c++) cur[r][c] = rand(); }
        function cell(k, cls) { return '<div class="sl-cell ' + (cls || '') + '">' + symHTML(id, k) + '</div>'; }
        function paint() {
            var h = '';
            for (var c = 0; c < info.reels; c++) { h += '<div class="sl-reel" data-c="' + c + '"><div class="sl-strip">'; for (var r = 0; r < info.rows; r++) h += cell(cur[r][c]); h += '</div></div>'; }
            reelsEl.innerHTML = h;
        }
        paint();
        function bet() { return levels[betIdx]; }
        function drawBet() { $('#bet', root).textContent = DO.money(bet()); }
        drawBet();
        $('#bm').onclick = function () { if (!busy) { betIdx = Math.max(0, betIdx - 1); drawBet(); DO.sfx('click'); } };
        $('#bp').onclick = function () { if (!busy) { betIdx = Math.min(levels.length - 1, betIdx + 1); drawBet(); DO.sfx('click'); } };
        $('#bmax').onclick = function () { if (!busy) { betIdx = levels.length - 1; drawBet(); DO.sfx('click'); } };

        function turbo() { return $('#turbo', root).checked; }
        function spinTo(grid) {
            return new Promise(function (resolve) {
                var t = turbo(), N = t ? 6 : 14, cs = parseFloat(getComputedStyle(reelsEl).getPropertyValue('--cell-px')) || reelsEl.querySelector('.sl-cell').offsetHeight;
                var done = 0; DO.sfx('spin');
                DO.$$('.sl-reel', reelsEl).forEach(function (rl, c) {
                    var strip = $('.sl-strip', rl), h = '';
                    for (var r = 0; r < info.rows; r++) h += cell(grid[r][c]);
                    for (var i = 0; i < N; i++) h += cell(rand());
                    for (r = 0; r < info.rows; r++) h += cell(cur[r][c]);
                    strip.style.transition = 'none'; strip.innerHTML = h; strip.style.transform = 'translateY(' + (-(N + info.rows) * cs) + 'px)'; void strip.offsetHeight;
                    var dur = (t ? 0.28 : 0.8) + c * (t ? 0.06 : 0.2);
                    strip.style.transition = 'transform ' + dur + 's cubic-bezier(.15,.7,.25,1)'; strip.style.transform = 'translateY(0)';
                    DO.later(function () {
                        strip.style.transition = 'none'; strip.style.transform = 'none';
                        var f = ''; for (var r2 = 0; r2 < info.rows; r2++) f += cell(grid[r2][c]); strip.innerHTML = f; DO.sfx('stop');
                        if (++done === info.reels) { cur = grid; resolve(); }
                    }, dur * 1000 + 30);
                });
            });
        }
        function highlight(hits, scatter) {
            DO.$$('.sl-cell', reelsEl).forEach(function (x) { x.classList.remove('win'); });
            var reelsList = DO.$$('.sl-reel', reelsEl);
            function mark(r, c) { var x = DO.$$('.sl-cell', reelsList[c])[r]; if (x) x.classList.add('win'); }
            (hits || []).forEach(function (h) { var line = LINES[h.line - 1]; for (var c = 0; c < h.count; c++) mark(line[c] - 1, c); });
            if (scatter >= 3) for (var r = 0; r < info.rows; r++) for (var c = 0; c < info.reels; c++) if (cur[r][c] === 'S') mark(r, c);
        }
        function countUp(el, to, ms) {
            return new Promise(function (resolve) {
                if (!to) { el.textContent = DO.money(0); resolve(); return; }
                var t0 = performance.now();
                (function step(now) { var p = Math.min(1, (now - t0) / ms); el.textContent = DO.money(Math.round(to * p)); if (p < 1) requestAnimationFrame(step); else resolve(); })(t0);
            });
        }
        function say(html, ms) { banner.innerHTML = html; banner.classList.add('on'); return DO.sleep(ms).then(function () { banner.classList.remove('on'); }); }

        async function play() {
            if (busy) return false;
            var b = bet();
            if (DO.bal() < b) { DO.noFunds(b); return false; }
            if (!(await DO.okToBet(b))) return false;
            busy = true; $('#spin').disabled = true; $('#win').textContent = DO.money(0); $('#fs').textContent = '';
            highlight([], 0);
            var before = DO.bal();
            var r;
            try { r = await Site.call('slots', { machine: id, bet: b }); }
            catch (e) { DO.toast(e.message); busy = false; $('#spin').disabled = false; return false; }
            DO.showBal(before - b);
            await spinTo(r.grid);
            var total = r.baseWin;
            if (r.baseWin) { DO.sfx(r.baseWin >= b * 10 ? 'big' : 'win'); highlight(r.hits, 0); await countUp($('#win'), total, 500); }
            if (r.free && r.free.length) {
                highlight([], r.scatter); await say('<b>' + r.free.length + ' FREE SPINS</b><small>Wins are multiplied' + (info.freeMult === 'ramp' ? ', and the multiplier grows each spin' : ' by ' + info.freeMultBase) + '</small>', turbo() ? 900 : 2200);
                DO.sfx('big'); total += r.scatter >= 3 ? 0 : 0;
                var shownTotal = r.baseWin + (r.scatter >= 3 ? r.win - r.baseWin - (r.freeWin || 0) : 0);
                for (var i = 0; i < r.free.length; i++) {
                    var f = r.free[i];
                    $('#fs').innerHTML = 'Free spin <b>' + (i + 1) + '/' + r.free.length + '</b> · <b>×' + f.mult + '</b>';
                    await spinTo(f.grid);
                    if (f.win) { highlight(f.hits, 0); shownTotal += f.win; DO.sfx('win'); $('#win').textContent = DO.money(shownTotal); await DO.sleep(turbo() ? 250 : 700); }
                    else await DO.sleep(turbo() ? 80 : 250);
                }
                $('#fs').textContent = '';
                await say('<b>FREE SPINS WIN</b><small>' + DO.money(r.freeWin || 0) + '</small>', turbo() ? 900 : 2000);
            } else if (r.scatter >= 3) { /* scatters pay in the base win */ }
            $('#win').textContent = DO.money(r.win);
            if (r.jackpotWon) { DO.sfx('big'); await say('<b>JACKPOT!</b><small>' + DO.money(r.jackpotWon) + '</small>', 3500); }
            if (!r.win) DO.sfx('lose');
            DO.setBal(r.balance);
            if (info.jackpot && r.pool) { DO.S.jackpot = r.pool; var jv = $('#jpv'); if (jv) jv.textContent = DO.money(r.pool); }
            busy = false; $('#spin').disabled = false;
            return r.win >= b * 25 ? 'big' : true;
        }
        async function autoLoop() {
            stopAuto = false;
            while (autoLeft > 0 && !stopAuto) {
                var res = await play(); autoLeft--;
                $('#spin').textContent = 'STOP (' + autoLeft + ')';
                if (!res || res === 'big') break;
                await DO.sleep(turbo() ? 150 : 500);
            }
            autoLeft = 0; stopAuto = false; $('#spin').textContent = 'SPIN'; $('#auto').value = '0';
        }
        $('#spin').onclick = function () {
            if (autoLeft > 0) { stopAuto = true; return; }
            var n = Number($('#auto').value);
            if (n > 0) { autoLeft = n; $('#spin').textContent = 'STOP (' + n + ')'; autoLoop(); } else play();
        };
        DO.onCleanup(function () { stopAuto = true; autoLeft = 0; });
        $('#pt').onclick = function () {
            var pays = info.pays, keys = Object.keys(sk.sym).filter(function (k) { return pays[k] && (k !== 'J' || info.jackpot); });
            keys.sort(function (a, b) { return (pays[b]['3'] || 0) - (pays[a]['3'] || 0); });
            var h = '<h3>' + esc(info.name) + ' paytable</h3><p class="sub small">Pays are multiples of your total bet. ' + info.lines + ' fixed paylines, wins pay from the left. ' + (info.wildMult ? 'A wild in a win doubles it.' : 'Wild stands in for any symbol except the scatter' + (info.jackpot ? ' and the jackpot symbol' : '') + '.') + '</p><table class="do-tab"><tr><th></th><th class="r">3</th>' + (info.reels > 3 ? '<th class="r">4</th><th class="r">5</th>' : '') + '</tr>';
            keys.forEach(function (k) { h += '<tr><td class="ptsym">' + symHTML(id, k) + ' <span class="sub small">' + (k === 'W' ? 'Wild' : k === 'J' ? 'Jackpot' : '') + '</span></td><td class="r">' + pays[k]['3'] + '×</td>' + (info.reels > 3 ? '<td class="r">' + pays[k]['4'] + '×</td><td class="r">' + pays[k]['5'] + '×</td>' : '') + '</tr>'; });
            h += '</table>';
            if (info.free) h += '<p style="margin-top:12px">' + symHTML(id, 'S') + ' <b>Scatter</b>: 3, 4 or 5 anywhere pay ' + info.scatter['3'] + '×, ' + info.scatter['4'] + '×, ' + info.scatter['5'] + '× and start ' + info.free['3'] + ', ' + info.free['4'] + ' or ' + info.free['5'] + ' free spins' + (info.freeMult === 'ramp' ? ' with a multiplier that grows by one each spin.' : ' with every win ×' + info.freeMultBase + '.') + '</p>';
            if (info.jackpot) h += '<p>' + symHTML(id, 'J') + ' <b>Jackpot</b>: five on a line at ' + DO.money(S.bets.jackpotMinBet) + ' or more bet wins the progressive jackpot.</p>';
            h += '<p class="sub small">The biggest win on one spin is capped at 5,000× your bet. Return to player is about 95%.</p><div class="do-row end"><button class="do-btn" data-n>Close</button></div>';
            var mm = DO.modal(h, { wide: false }); $('[data-n]', mm.el).onclick = mm.close;
        };
        document.addEventListener('keydown', onKey); DO.onCleanup(function () { document.removeEventListener('keydown', onKey); });
        function onKey(e) { if (e.code === 'Space' && !/INPUT|SELECT|TEXTAREA/.test((e.target || {}).tagName) && !document.querySelector('.do-modal')) { e.preventDefault(); if (!busy) $('#spin').click(); } }
    });
})();
