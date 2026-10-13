/* Diamond Online page core: state, requests, routing, header, sound, dialogs. The games add their pages with DO.page(). */
(function () {
    'use strict';
    var esc = Site.esc;
    var DO = window.DO = { S: null, pages: [], cleanups: [], timers: [] };
    DO.esc = esc;

    // ---------------------------------------------------------------- small helpers
    DO.money = function (n) { return Site.money(n); };
    DO.signed = function (n) { n = Math.round(Number(n) || 0); return (n < 0 ? '−' : n > 0 ? '+' : '') + Site.money(Math.abs(n)); };
    DO.$ = function (sel, root) { return (root || document).querySelector(sel); };
    DO.$$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
    DO.el = function (html, cls) { var d = document.createElement('div'); if (cls) d.className = cls; d.innerHTML = html || ''; return d; };
    DO.sleep = function (ms) { return new Promise(function (r) { DO.later(r, ms); }); };
    DO.later = function (fn, ms) { var id = setTimeout(fn, ms); DO.timers.push(id); return id; };
    DO.every = function (fn, ms) { var id = setInterval(fn, ms); DO.timers.push(id); return id; };
    DO.clearTimers = function () { DO.timers.forEach(function (id) { clearTimeout(id); clearInterval(id); }); DO.timers = []; };
    DO.mmss = function (s) { s = Math.max(0, Math.floor(s)); var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s % 60).padStart(2, '0'); };

    // ---------------------------------------------------------------- requests
    DO.call = function (name, data, quiet) {
        return Site.call(name, data || {}).catch(function (e) {
            if (!quiet) DO.toast(e.message);
            if (/sign in|signed out/i.test(e.message || '')) { DO.loadState().then(function () { Site.go('/signin'); }); }
            throw e;
        });
    };
    DO.loadState = function () {
        return Site.call('state').then(function (s) { DO.S = s; DO.drawHeader(); return s; });
    };
    DO.signedIn = function () { return !!(DO.S && DO.S.account); };
    DO.setAccount = function (a) { if (a && DO.S) { DO.S.account = a; DO.drawHeader(); } };
    DO.bal = function () { return DO.S && DO.S.account ? DO.S.account.balance : 0; };
    DO.setBal = function (n) {
        if (DO.S && DO.S.account) { DO.S.account.balance = n; }
        DO.shownBal = n; DO.drawBalance();
    };
    /* the number on show can lag the real balance while a reel is still turning; a game calls DO.showBal(x) then DO.setBal(real) */
    DO.showBal = function (n) { DO.shownBal = n; DO.drawBalance(); };

    // ---------------------------------------------------------------- sound (made with the browser, no files)
    var ac = null;
    function tone(f, d, type, vol, at) {
        try {
            ac = ac || new (window.AudioContext || window.webkitAudioContext)();
            var o = ac.createOscillator(), g = ac.createGain(), t0 = ac.currentTime + (at || 0);
            o.type = type || 'sine'; o.frequency.value = f;
            g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(vol || 0.08, t0 + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t0 + d);
            o.connect(g); g.connect(ac.destination); o.start(t0); o.stop(t0 + d + 0.02);
        } catch (e) { /* no audio */ }
    }
    var FX = {
        click: [[620, .05, 'square', .04]],
        chip: [[900, .04, 'triangle', .07], [1200, .05, 'triangle', .05, .03]],
        card: [[240, .06, 'sawtooth', .04], [180, .05, 'sawtooth', .03, .03]],
        spin: [[200, .08, 'square', .03], [260, .08, 'square', .03, .08], [320, .08, 'square', .03, .16]],
        stop: [[140, .09, 'triangle', .08]],
        win: [[523, .12, 'triangle', .08], [659, .12, 'triangle', .08, .1], [784, .2, 'triangle', .08, .2]],
        big: [[523, .12, 'square', .07], [659, .12, 'square', .07, .1], [784, .12, 'square', .07, .2], [1046, .35, 'square', .07, .3]],
        lose: [[220, .18, 'sawtooth', .05], [165, .3, 'sawtooth', .05, .15]],
        tick: [[1000, .03, 'square', .03]],
        bust: [[180, .35, 'sawtooth', .08], [120, .5, 'sawtooth', .08, .1]],
    };
    DO.sfx = function (n) {
        if (!DO.S || !DO.S.account || !DO.S.account.sound) return;
        (FX[n] || []).forEach(function (a) { tone(a[0], a[1], a[2], a[3], a[4]); });
    };

    // ---------------------------------------------------------------- dialogs and toasts
    DO.toast = function (text) {
        var t = DO.el(esc(text), 'do-toast'); document.body.appendChild(t);
        setTimeout(function () { t.classList.add('out'); setTimeout(function () { t.remove(); }, 400); }, 3600);
    };
    DO.modal = function (html, opts) {
        opts = opts || {};
        var back = DO.el('', 'do-modal'), box = DO.el(html, 'do-box');
        if (opts.wide) box.classList.add('wide');
        back.appendChild(box); document.body.appendChild(back);
        var api = { el: box, close: function () { back.remove(); if (opts.onClose) opts.onClose(); } };
        if (opts.dismiss !== false) back.addEventListener('mousedown', function (e) { if (e.target === back) api.close(); });
        return api;
    };
    DO.confirm = function (title, text, yes, no) {
        return new Promise(function (resolve) {
            var m = DO.modal('<h3>' + esc(title) + '</h3><p class="sub">' + esc(text) + '</p><div class="do-row end"><button class="do-btn ghost" data-n>' + esc(no || 'Cancel') + '</button><button class="do-btn" data-y>' + esc(yes || 'OK') + '</button></div>', { dismiss: false });
            DO.$('[data-y]', m.el).onclick = function () { m.close(); resolve(true); };
            DO.$('[data-n]', m.el).onclick = function () { m.close(); resolve(false); };
        });
    };
    /* games call this before sending a bet; resolves true when the player is happy to go ahead */
    DO.okToBet = function (amount) {
        var a = DO.S && DO.S.account;
        if (a && a.confirmOver > 0 && amount > a.confirmOver) return DO.confirm('Confirm your bet', 'You are about to bet ' + DO.money(amount) + '.', 'Place bet', 'Cancel');
        return Promise.resolve(true);
    };

    // ---------------------------------------------------------------- cards
    var SUITS = ['♣', '♦', '♥', '♠'], RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
    DO.rankOf = function (c) { return c % 13 + 1; };
    DO.card = function (c, cls) {
        if (c === null || c === undefined || c < 0) return '<div class="pc back ' + (cls || '') + '"></div>';
        var s = Math.floor(c / 13), red = s === 1 || s === 2;
        return '<div class="pc ' + (red ? 'red ' : '') + (cls || '') + '"><b>' + RANKS[c % 13] + '</b><i>' + SUITS[s] + '</i><span>' + SUITS[s] + '</span></div>';
    };

    // ---------------------------------------------------------------- reusable bet box
    /* A bet entry: chips that add to the amount, a number box, min and max. Returns { get(), set(n), el, lock(bool) }. */
    DO.betBox = function (host, o) {
        var min = o.min || 1, max = o.max || 1e9, val = Math.max(min, Math.min(max, o.value || o.chips && o.chips[0] || min));
        var chips = o.chips || [1, 5, 25, 100, 500];
        host.innerHTML = '<div class="do-bet"><label class="do-lbl">' + esc(o.label || 'Your bet') + '</label><div class="do-betrow"><button class="do-sm" data-a="half">½</button><input type="number" min="' + min + '" max="' + max + '" value="' + val + '"><button class="do-sm" data-a="dbl">2×</button></div>' +
            '<div class="do-chips">' + chips.map(function (c) { return '<button class="do-chip" data-c="' + c + '">+' + c + '</button>'; }).join('') + '<button class="do-chip max" data-a="max">Max</button></div></div>';
        var inp = DO.$('input', host), locked = false;
        function set(n) { n = Math.max(min, Math.min(max, Math.floor(Number(n) || min))); val = n; inp.value = n; if (o.onChange) o.onChange(n); }
        inp.addEventListener('input', function () { val = Math.floor(Number(inp.value) || 0); if (o.onChange) o.onChange(val); });
        inp.addEventListener('change', function () { set(inp.value); });
        host.addEventListener('click', function (e) {
            var b = e.target.closest('button'); if (!b || locked) return;
            DO.sfx('chip');
            if (b.dataset.c) set(val + Number(b.dataset.c));
            else if (b.dataset.a === 'max') set(Math.min(max, DO.bal() > 0 ? Math.max(min, DO.bal()) : max));
            else if (b.dataset.a === 'half') set(Math.floor(val / 2));
            else if (b.dataset.a === 'dbl') set(val * 2);
        });
        return {
            get: function () { return Math.max(min, Math.min(max, Math.floor(Number(inp.value) || min))); }, set: set,
            lock: function (on) { locked = on; DO.$$('button,input', host).forEach(function (x) { x.disabled = on; }); },
        };
    };

    // ---------------------------------------------------------------- the header
    var root, headEl, mainEl, footEl;
    function nav() {
        var p = Site.route() || '/';
        function a(path, label) { return '<a data-go="' + path + '" class="' + (p === path || (path !== '/' && p.indexOf(path) === 0) ? 'on' : '') + '">' + label + '</a>'; }
        return a('/', 'Games') + a('/history', 'History') + a('/account', 'Account');
    }
    DO.drawHeader = function () {
        if (!headEl) return;
        var S = DO.S || {}, a = S.account;
        headEl.innerHTML = '<a class="do-logo" data-go="/"><span>◆</span>DIAMOND ONLINE</a><nav>' + nav() + '</nav><div class="grow"></div>' +
            (a ? '<div class="do-sess" id="do-sess"></div><div class="do-bal"><span class="lbl">Balance</span><b id="do-bal">' + DO.money(DO.shownBal != null ? DO.shownBal : a.balance) + '</b></div><button class="do-btn sm" data-dep>Deposit</button>'
               : '<a class="do-btn ghost sm" data-go="/signin">Sign in</a><a class="do-btn sm" data-go="/signup">Join now</a>');
        DO.tickSession();
    };
    DO.drawBalance = function () { var b = DO.$('#do-bal'); if (b && DO.S && DO.S.account) b.textContent = DO.money(DO.shownBal != null ? DO.shownBal : DO.S.account.balance); };
    var sessTimer = null, lastRemind = 0;
    DO.tickSession = function () {
        var a = DO.S && DO.S.account, el = DO.$('#do-sess');
        if (!a || !el) return;
        var now = Date.now() / 1000, start = a.session.start || now;
        if (a.showTimer) {
            var net = (a.session.won || 0) - (a.session.wagered || 0);
            el.innerHTML = 'Session ' + DO.mmss(now - start) + ' · <span class="' + (net < 0 ? 'neg' : 'pos') + '">' + DO.signed(net) + '</span>';
            el.style.display = '';
        } else el.style.display = 'none';
        var every = (a.reminder || 0) * 60;
        if (every > 0 && now - Math.max(start, lastRemind) >= every && !DO.remindOpen) DO.remind();
    };
    DO.remind = function () {
        DO.remindOpen = true;
        Site.call('session').then(function (s) {
            var net = s.won - s.wagered, mins = Math.round((Date.now() / 1000 - s.start) / 60);
            var m = DO.modal('<h2 class="do-h">You have been playing for ' + (mins >= 60 ? Math.floor(mins / 60) + ' hour' + (mins >= 120 ? 's' : '') : mins + ' minutes') + '</h2><p class="sub">Take a moment to check how the session is going. Games are paused until you choose.</p>' +
                '<div class="do-trio"><div><span>Wagered</span><b>' + DO.money(s.wagered) + '</b></div><div><span>Won</span><b>' + DO.money(s.won) + '</b></div><div class="' + (net < 0 ? 'neg' : 'pos') + '"><span>Net</span><b>' + DO.signed(net) + '</b></div></div>' +
                '<div class="do-row"><button class="do-btn grow" data-keep>Keep playing</button><button class="do-btn ghost grow" data-back>Back to games</button></div>' +
                '<p class="sub center small">Remind me every ' + DO.S.account.reminder + ' minutes · <a data-go="/account/settings">Change</a></p>', { dismiss: false, onClose: function () { DO.remindOpen = false; lastRemind = Date.now() / 1000; } });
            DO.$('[data-keep]', m.el).onclick = function () { m.close(); };
            DO.$('[data-back]', m.el).onclick = function () { m.close(); Site.go('/'); };
        }).catch(function () { DO.remindOpen = false; });
    };

    DO.depositDialog = function (need) {
        var S = DO.S; if (!S || !S.account) { Site.go('/signin'); return; }
        var a = S.account, left = Math.max(0, a.limit - a.limitUsed);
        var m = DO.modal('<h3>Deposit from your bank</h3><p class="sub">Money moves from your bank account to your Diamond Online balance straight away.' + (need ? ' You need ' + DO.money(need) + ' for that bet.' : '') + '</p>' +
            '<div class="do-meter"><div style="width:' + Math.min(100, Math.round(a.limitUsed / a.limit * 100)) + '%"></div></div><p class="sub small">' + DO.money(a.limitUsed) + ' of your ' + DO.money(a.limit) + ' daily limit used. ' + DO.money(left) + ' left today.</p>' +
            '<div class="do-chips" id="dq">' + [100, 500, 1000, 2500].filter(function (v) { return v <= Math.max(left, 100); }).map(function (v) { return '<button class="do-chip" data-v="' + v + '">' + DO.money(v) + '</button>'; }).join('') + '</div>' +
            '<input type="number" class="do-in" id="damt" min="' + S.rules.minDeposit + '" placeholder="Amount"><p class="do-err" id="derr"></p>' +
            '<div class="do-row end"><button class="do-btn ghost" data-n>Cancel</button><button class="do-btn" data-y>Deposit</button></div>');
        var amt = DO.$('#damt', m.el); if (need) amt.value = Math.min(left, Math.max(need - DO.bal(), S.rules.minDeposit));
        DO.$('#dq', m.el).onclick = function (e) { var b = e.target.closest('button'); if (b) amt.value = b.dataset.v; };
        DO.$('[data-n]', m.el).onclick = m.close;
        DO.$('[data-y]', m.el).onclick = function () {
            var v = Math.floor(Number(amt.value) || 0), b = this; b.disabled = true;
            Site.call('deposit', { amount: v }).then(function (acc) { DO.setAccount(acc); DO.shownBal = null; DO.drawBalance(); m.close(); DO.toast('Deposited ' + DO.money(v) + '.'); DO.sfx('chip'); if (DO.onAccount) DO.onAccount(); })
                .catch(function (e) { DO.$('#derr', m.el).textContent = e.message; b.disabled = false; });
        };
    };
    /* games call this when a bet is refused for lack of funds */
    DO.noFunds = function (need) { DO.depositDialog(need); };

    // ---------------------------------------------------------------- pages and routing
    DO.page = function (re, fn, opts) { DO.pages.push({ re: re, fn: fn, open: opts && opts.open }); };
    DO.render = function (html) { mainEl.innerHTML = html; mainEl.scrollTop = 0; window.scrollTo(0, 0); return mainEl; };
    DO.main = function () { return mainEl; };
    DO.onCleanup = function (fn) { DO.cleanups.push(fn); };

    function route(path) {
        DO.cleanups.forEach(function (f) { try { f(); } catch (e) { /* ignore */ } }); DO.cleanups = [];
        DO.clearTimers(); DO.sessionLoop();
        path = path || '/';
        var hit = null, m;
        DO.pages.forEach(function (p) { if (!hit && (m = path.match(p.re))) hit = { p: p, m: m }; });
        DO.drawHeader();
        if (!hit) { Site.go('/'); return; }
        var proceed = function () {
            if (!hit.p.open && !DO.signedIn()) { DO.gate(path); return; }
            hit.p.fn(hit.m);
        };
        if (!DO.S) { DO.render('<div class="spinner"></div>'); DO.loadState().then(proceed).catch(function (e) { DO.render('<div class="do-wrap"><div class="do-note bad">' + esc(e.message) + '</div></div>'); }); }
        else DO.loadState().then(proceed).catch(proceed);
    }
    DO.sessionLoop = function () {
        if (sessTimer) return;
        sessTimer = setInterval(DO.tickSession, 1000);
    };
    DO.gate = function (path) {
        DO.returnTo = path;
        var S = DO.S;
        DO.render('<div class="do-wrap narrow"><div class="do-panel center"><h2 class="do-h">Sign in to play</h2><p class="sub">' + (S && S.hasAccount ? 'Welcome back. Sign in to your Diamond Online account to continue.' : 'You need a Diamond Online account to play. It takes a minute.') + '</p>' +
            '<div class="do-row"><a class="do-btn grow" data-go="/signin">Sign in</a><a class="do-btn ghost grow" data-go="/signup">Create account</a></div></div></div>');
    };

    DO.start = function () {
        root = document.getElementById('root');
        root.innerHTML = '<div class="do-shell"><header class="do-head"></header><main class="do-main"></main><footer class="do-foot"></footer></div>';
        headEl = DO.$('.do-head', root); mainEl = DO.$('.do-main', root); footEl = DO.$('.do-foot', root);
        footEl.innerHTML = '<span class="age">18+</span><span>Play responsibly. Set a daily deposit limit in your account, use the session reminder, or close your account at any time. Nothing here is real money.</span>';
        root.addEventListener('click', function (e) {
            var g = e.target.closest('[data-go]'); if (g) { e.preventDefault(); Site.go(g.getAttribute('data-go')); return; }
            if (e.target.closest('[data-dep]')) DO.depositDialog();
        });
        Site.onRoute(route);
    };
})();
