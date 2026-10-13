/* Diamond Online: home, sign up, sign in, password reset, account and history pages. */
(function () {
    'use strict';
    var esc = DO.esc, $ = DO.$;

    // ------------------------------------------------------------------ home
    var TILES = [
        ['slots', '/slots', 'Slots', 'Six machines, free spins and a jackpot', 'linear-gradient(135deg,#7c3aed,#db2777)', '🎰'],
        ['blackjack', '/blackjack', 'Blackjack', 'Beat the dealer to 21. Pays 3 to 2', 'linear-gradient(135deg,#065f46,#10b981)', '🃏'],
        ['roulette', '/roulette', 'Roulette', 'European wheel, one zero', 'linear-gradient(135deg,#991b1b,#ef4444)', '🎡'],
        ['crash', '/crash', 'Crash', 'Cash out before it crashes', 'linear-gradient(135deg,#1d4ed8,#06b6d4)', '🚀'],
        ['poker', '/poker', 'Video Poker', 'Jacks or Better, 9/6 pays', 'linear-gradient(135deg,#92400e,#f59e0b)', '♠️'],
        ['baccarat', '/baccarat', 'Baccarat', 'Player, Banker or Tie', 'linear-gradient(135deg,#312e81,#6366f1)', '🀡'],
        ['hilo', '/higher-lower', 'Higher or Lower', 'Build a streak, cash out any time', 'linear-gradient(135deg,#701a75,#d946ef)', '↕️'],
    ];
    DO.tiles = TILES;
    DO.page(/^\/$/, function () {
        var S = DO.S, a = S.account;
        var jp = S.jackpot;
        var h = '<div class="do-wrap">' + (S.open ? '' : '<div class="do-note bad">Betting is closed at the moment. You can still withdraw your balance.</div>') +
            '<div class="do-hero"><div><div class="do-kick">Progressive jackpot · Diamond Reels</div><div class="do-jp" id="jp">' + DO.money(jp) + '</div><div class="sub">Five diamonds on a line at ' + DO.money(S.bets.jackpotMinBet) + ' or more wins the lot.</div></div>' +
            (a ? '<div class="do-lim"><span class="sub small">Daily deposit limit</span><div class="do-meter"><div style="width:' + Math.min(100, Math.round(a.limitUsed / a.limit * 100)) + '%"></div></div><span class="sub small">' + DO.money(a.limitUsed) + ' of ' + DO.money(a.limit) + ' used</span></div>'
               : '<div class="do-row"><a class="do-btn" data-go="/signup">Join now</a><a class="do-btn ghost" data-go="/signin">Sign in</a></div>') + '</div>' +
            '<h3>All games</h3><div class="do-tiles">';
        TILES.forEach(function (t) {
            var on = S.games[t[0]] !== false;
            h += '<a class="do-tile' + (on ? '' : ' off') + '" data-go="' + (on ? t[1] : '/') + '" style="background:' + t[4] + '"><span class="ic">' + t[5] + '</span><b>' + t[2] + '</b><small>' + (on ? t[3] : 'Closed for now') + '</small></a>';
        });
        DO.render(h + '</div></div>');
        // let the jackpot tick up a little between visits for show: it only ever moves toward the real number
        var shown = jp * 0.995; DO.every(function () { shown = Math.min(jp, shown + (jp - shown) * 0.2 + 1); var j = $('#jp'); if (j) j.textContent = DO.money(Math.floor(shown)); }, 120);
        DO.every(function () { DO.call('state', null, true).then(function (s) { jp = s.jackpot; }).catch(function () {}); }, 15000);
    }, { open: true });

    // ------------------------------------------------------------------ sign up and sign in
    function after() { var to = DO.returnTo; DO.returnTo = null; DO.shownBal = null; Site.go(to && to !== '/signin' && to !== '/signup' ? to : '/'); }
    DO.page(/^\/signup$/, function () {
        if (DO.signedIn()) { Site.go('/'); return; }
        var S = DO.S;
        if (S.hasAccount) { DO.render('<div class="do-wrap narrow"><div class="do-panel center"><h2 class="do-h">You already have an account</h2><p class="sub">' + (S.accountClosed ? 'It was closed and cannot be reopened.' : 'Your username is <b>' + esc(S.usernameHint) + '</b>.') + '</p>' + (S.accountClosed ? '' : '<a class="do-btn" data-go="/signin">Sign in</a>') + '</div></div>'); return; }
        DO.render('<div class="do-wrap narrow"><div class="do-panel"><h2 class="do-h">Create your account</h2><p class="sub">One account per character. We check your age against your character\'s date of birth: you must be ' + S.minAge + ' or over.</p>' +
            '<label class="do-lbl">Username</label><input type="text" id="u" maxlength="20" autocomplete="off"><label class="do-lbl">Password</label><input type="password" id="p" maxlength="60"><label class="do-lbl">Repeat password</label><input type="password" id="p2" maxlength="60">' +
            '<label class="do-check"><input type="checkbox" id="age"><span>I confirm I am ' + S.minAge + ' or over and I understand gambling can be harmful. I can set a daily deposit limit and close my account at any time.</span></label>' +
            '<p class="do-err" id="err"></p><button class="do-btn" style="width:100%" id="go">Create account</button><p class="sub center small" style="margin-top:12px">Already a member? <a data-go="/signin">Sign in</a></p></div></div>');
        $('#go').onclick = function () {
            var b = this, err = $('#err'); err.textContent = '';
            if ($('#p').value !== $('#p2').value) { err.textContent = 'The passwords do not match.'; return; }
            b.disabled = true;
            Site.call('signup', { username: $('#u').value, password: $('#p').value, confirmAge: $('#age').checked ? 'true' : 'false' })
                .then(function () { return DO.loadState(); }).then(function () { DO.toast('Welcome to Diamond Online.'); after(); })
                .catch(function (e) { err.textContent = e.message; b.disabled = false; });
        };
    }, { open: true });

    DO.page(/^\/signin$/, function () {
        if (DO.signedIn()) { Site.go('/'); return; }
        var S = DO.S;
        DO.render('<div class="do-wrap narrow"><div class="do-panel"><h2 class="do-h">Sign in</h2>' +
            '<label class="do-lbl">Username</label><input type="text" id="u" maxlength="20" value="' + esc(S.usernameHint || '') + '" autocomplete="off"><label class="do-lbl">Password</label><input type="password" id="p" maxlength="60">' +
            '<p class="do-err" id="err"></p><button class="do-btn" style="width:100%" id="go">Sign in</button>' +
            '<p class="sub center small" style="margin-top:12px"><a data-go="/forgot">Forgotten your password?</a><br>New here? <a data-go="/signup">Create an account</a></p></div></div>');
        function go() {
            var b = $('#go'), err = $('#err'); err.textContent = ''; b.disabled = true;
            Site.call('signin', { username: $('#u').value, password: $('#p').value }).then(function () { return DO.loadState(); }).then(after)
                .catch(function (e) { err.textContent = e.message; b.disabled = false; });
        }
        $('#go').onclick = go; $('#p').addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); });
    }, { open: true });

    DO.page(/^\/forgot$/, function () {
        DO.render('<div class="do-wrap narrow"><div class="do-panel"><h2 class="do-h">Reset your password</h2><p class="sub">We email a 6 digit code to your character\'s Mail app.</p>' +
            '<label class="do-lbl">Username</label><input type="text" id="u" maxlength="20"><p class="do-err" id="err"></p><button class="do-btn" style="width:100%" id="send">Send me a code</button>' +
            '<div id="step2" style="display:none"><div class="do-note good" style="margin-top:14px">If that username is yours, a code is on its way. Check your Mail app.</div><label class="do-lbl">Code</label><input type="text" id="c" maxlength="6" inputmode="numeric"><label class="do-lbl">New password</label><input type="password" id="p" maxlength="60"><p class="do-err" id="err2"></p><button class="do-btn" style="width:100%" id="set">Set new password</button></div>' +
            '<p class="sub center small" style="margin-top:12px"><a data-go="/signin">Back to sign in</a></p></div></div>');
        $('#send').onclick = function () {
            var b = this; $('#err').textContent = ''; b.disabled = true;
            Site.call('forgot', { username: $('#u').value }).then(function () { $('#step2').style.display = ''; DO.later(function () { b.disabled = false; }, 8000); })
                .catch(function (e) { $('#err').textContent = e.message; b.disabled = false; });
        };
        $('#set').onclick = function () {
            var b = this; $('#err2').textContent = ''; b.disabled = true;
            Site.call('reset', { username: $('#u').value, code: $('#c').value, password: $('#p').value }).then(function () { DO.toast('Password changed. Sign in with it now.'); Site.go('/signin'); })
                .catch(function (e) { $('#err2').textContent = e.message; b.disabled = false; });
        };
    }, { open: true });

    // ------------------------------------------------------------------ history
    function histPage(root, type, page) {
        var host = $('#hist', root);
        host.innerHTML = '<div class="spinner"></div>';
        Site.call('history', { type: type, page: page }).then(function (d) {
            var rows = d.rows || [], h = '<table class="do-tab">';
            if (type === 'money') {
                h += '<tr><th>When</th><th>What</th><th class="r">Amount</th><th class="r">Balance</th></tr>';
                rows.forEach(function (r) { h += '<tr><td>' + Site.datetime(r.at) + '</td><td>' + (r.kind === 'deposit' ? 'Deposit' : 'Withdrawal') + '</td><td class="r ' + (r.amount < 0 ? 'neg' : 'pos') + '">' + DO.signed(r.amount) + '</td><td class="r">' + DO.money(r.balance) + '</td></tr>'; });
            } else {
                h += '<tr><th>When</th><th>Game</th><th class="r">Bet</th><th class="r">Paid</th><th class="r">Result</th></tr>';
                rows.forEach(function (r) { var n = r.paid - r.wagered; h += '<tr><td>' + Site.datetime(r.at) + '</td><td>' + esc(String(r.game).replace('slots-', 'slots: ')) + '</td><td class="r">' + DO.money(r.wagered) + '</td><td class="r">' + DO.money(r.paid) + '</td><td class="r ' + (n < 0 ? 'neg' : n > 0 ? 'pos' : '') + '">' + DO.signed(n) + '</td></tr>'; });
            }
            if (!rows.length) h += '<tr><td colspan="5" class="sub center">Nothing here yet.</td></tr>';
            h += '</table><div class="do-row end">' + (page > 0 ? '<button class="do-btn ghost sm" id="hp">Newer</button>' : '') + (d.more ? '<button class="do-btn ghost sm" id="hn">Older</button>' : '') + '</div>';
            host.innerHTML = h;
            if ($('#hp', host)) $('#hp', host).onclick = function () { histPage(root, type, page - 1); };
            if ($('#hn', host)) $('#hn', host).onclick = function () { histPage(root, type, page + 1); };
        }).catch(function (e) { host.innerHTML = '<div class="do-note bad">' + esc(e.message) + '</div>'; });
    }
    DO.page(/^\/history$/, function () {
        var root = DO.render('<div class="do-wrap"><h2 class="do-h">History</h2><div class="do-row"><button class="do-chip on" data-t="bets">Bets</button><button class="do-chip" data-t="money">Deposits and withdrawals</button><div class="grow"></div><button class="do-btn ghost sm" id="copy">Copy as a file</button></div><div class="do-panel" style="margin-top:12px" id="hist"></div></div>');
        var type = 'bets';
        DO.$$('[data-t]', root).forEach(function (b) { b.onclick = function () { type = b.dataset.t; DO.$$('[data-t]', root).forEach(function (x) { x.classList.toggle('on', x === b); }); histPage(root, type, 0); }; });
        $('#copy').onclick = function () { Site.call('export').then(function (d) { return Site.copy(d.csv); }).then(function () { DO.toast('Copied. Paste it into a note or a file.'); }).catch(function (e) { DO.toast(e.message); }); };
        histPage(root, type, 0);
    });

    // ------------------------------------------------------------------ account
    var TABS = [['', 'Balance and limits'], ['settings', 'Play settings'], ['password', 'Password'], ['close', 'Close account']];
    function toggle(id, on) { return '<span class="do-tg' + (on ? ' on' : '') + '" data-tg="' + id + '"><i></i></span>'; }
    DO.page(/^\/account(?:\/(\w+))?$/, function (m) {
        var tab = m[1] || '', S = DO.S, a = S.account, R = S.rules;
        var side = '<div class="do-side">' + TABS.map(function (t) { return '<a data-go="/account' + (t[0] ? '/' + t[0] : '') + '" class="' + (t[0] === tab ? 'on' : '') + '">' + t[1] + '</a>'; }).join('') + '<a data-go="/history">Betting history</a><a id="so">Sign out</a></div>';
        var body = '';
        if (tab === '') {
            var left = Math.max(0, a.limit - a.limitUsed);
            body = '<div class="do-panel"><div class="sub small">Your balance</div><div class="do-bigbal">' + DO.money(a.balance) + '</div><div class="do-row"><button class="do-btn" data-dep>Deposit</button><button class="do-btn ghost" id="wd">Withdraw to bank</button></div></div>' +
                '<div class="do-panel"><h3>Daily deposit limit</h3><div class="do-meter"><div style="width:' + Math.min(100, Math.round(a.limitUsed / a.limit * 100)) + '%"></div></div><p class="sub">' + DO.money(a.limitUsed) + ' of ' + DO.money(a.limit) + ' used today. ' + DO.money(left) + ' left.</p>' +
                (a.limitNext ? '<div class="do-note">Your limit goes up to ' + DO.money(a.limitNext) + ' on ' + Site.datetime(a.limitNextAt) + '.</div>' : '') +
                '<div class="do-row"><input type="number" id="lim" style="max-width:200px" min="' + R.minLimit + '" max="' + R.maxLimit + '" value="' + a.limit + '"><button class="do-btn ghost" id="setlim">Change limit</button></div><p class="sub small">Lowering your limit works straight away. Raising it takes ' + R.limitRaiseHours + ' hours to apply. Between ' + DO.money(R.minLimit) + ' and ' + DO.money(R.maxLimit) + '.</p><p class="do-err" id="lerr"></p></div>' +
                '<div class="do-panel"><h3>Recent activity</h3><div id="hist"></div></div>';
        } else if (tab === 'settings') {
            var opts = R.reminderChoices.map(function (v) { return '<option value="' + v + '"' + (v === a.reminder ? ' selected' : '') + '>' + (v ? 'Every ' + v + ' min' : 'Off') + '</option>'; }).join('');
            body = '<div class="do-panel"><h3>Play settings</h3>' +
                '<div class="do-set"><div class="grow"><b>Session reminder</b><div class="sub small">A pop-up with your wagered, won and net totals.</div></div><select id="rem" style="max-width:150px">' + opts + '</select></div>' +
                '<div class="do-set"><div class="grow"><b>Show session timer and net total in the header</b><div class="sub small">Always visible while you play.</div></div>' + toggle('showTimer', a.showTimer) + '</div>' +
                '<div class="do-set"><div class="grow"><b>Sound</b><div class="sub small">Win, lose and spin sounds.</div></div>' + toggle('sound', a.sound) + '</div>' +
                '<div class="do-set"><div class="grow"><b>Confirm bets over a set amount</b><div class="sub small">Ask before placing a bigger bet. 0 turns this off.</div></div><input type="number" id="conf" style="max-width:110px" min="0" value="' + a.confirmOver + '"></div></div>' +
                '<div class="do-panel"><h3>Your data</h3><div class="do-set"><div class="grow"><b>Copy your history</b><div class="sub small">Every deposit, withdrawal and bet as text you can paste.</div></div><button class="do-btn ghost sm" id="exp">Copy</button></div></div>';
        } else if (tab === 'password') {
            body = '<div class="do-panel"><h3>Change password</h3><label class="do-lbl">Current password</label><input type="password" id="o"><label class="do-lbl">New password</label><input type="password" id="n"><p class="do-err" id="perr"></p><button class="do-btn" id="pw">Change password</button></div>';
        } else if (tab === 'close') {
            body = '<div class="do-panel" style="border-color:#6a1f2a;background:#2a0f14"><h3 style="color:#ffb3bf">Close my account</h3><p class="sub">Your balance of ' + DO.money(a.balance) + ' is sent to your bank first. After that the account is closed and cannot be reopened.</p><label class="do-lbl">Your password</label><input type="password" id="cp"><p class="do-err" id="cerr"></p><button class="do-btn bad" id="cl">Close account</button></div>';
        }
        var root = DO.render('<div class="do-wrap"><h2 class="do-h">My account</h2><div class="do-acc">' + side + '<div class="grow">' + body + '</div></div></div>');
        $('#so', root).onclick = function () { Site.call('signout').then(function () { return DO.loadState(); }).then(function () { Site.go('/'); }); };
        function refresh() { DO.loadState().then(function () { DO.shownBal = null; DO.drawBalance(); accountFn(m); }); }
        DO.onAccount = function () { if ($('#hist')) refresh(); };
        if (tab === '') {
            histPage(root, 'money', 0);
            $('#wd').onclick = function () {
                var mm = DO.modal('<h3>Withdraw to your bank</h3><p class="sub">You have ' + DO.money(a.balance) + '. It goes straight into your bank account.</p><input type="number" id="wamt" min="1" max="' + a.balance + '" value="' + a.balance + '"><p class="do-err" id="werr"></p><div class="do-row end"><button class="do-btn ghost" data-n>Cancel</button><button class="do-btn" data-y>Withdraw</button></div>');
                $('[data-n]', mm.el).onclick = mm.close;
                $('[data-y]', mm.el).onclick = function () { var b = this; b.disabled = true; Site.call('withdraw', { amount: Number($('#wamt', mm.el).value) }).then(function (acc) { DO.setAccount(acc); mm.close(); DO.toast('Withdrawn to your bank.'); refresh(); }).catch(function (e) { $('#werr', mm.el).textContent = e.message; b.disabled = false; }); };
            };
            $('#setlim').onclick = function () { Site.call('limit', { amount: Number($('#lim').value) }).then(function (acc) { DO.setAccount(acc); refresh(); }).catch(function (e) { $('#lerr').textContent = e.message; }); };
        }
        if (tab === 'settings') {
            function save(d) { Site.call('settings', d).then(function (acc) { DO.setAccount(acc); }).catch(function (e) { DO.toast(e.message); }); }
            $('#rem').onchange = function () { save({ reminder: Number(this.value) }); };
            $('#conf').onchange = function () { save({ confirmOver: Number(this.value) }); };
            DO.$$('[data-tg]', root).forEach(function (t) { t.onclick = function () { var on = !t.classList.contains('on'); t.classList.toggle('on', on); var d = {}; d[t.dataset.tg] = on; save(d); }; });
            $('#exp').onclick = function () { Site.call('export').then(function (d) { return Site.copy(d.csv); }).then(function () { DO.toast('Copied.'); }).catch(function (e) { DO.toast(e.message); }); };
        }
        if (tab === 'password') $('#pw').onclick = function () { Site.call('password', { old: $('#o').value, new: $('#n').value }).then(function () { DO.toast('Password changed.'); $('#o').value = ''; $('#n').value = ''; $('#perr').textContent = ''; }).catch(function (e) { $('#perr').textContent = e.message; }); };
        if (tab === 'close') $('#cl').onclick = function () {
            DO.confirm('Close your account?', 'This cannot be undone.', 'Close account', 'Keep it').then(function (ok) {
                if (!ok) return;
                Site.call('close', { password: $('#cp').value }).then(function (d) { return DO.loadState().then(function () { DO.toast(d.paidOut ? DO.money(d.paidOut) + ' sent to your bank. Your account is closed.' : 'Your account is closed.'); Site.go('/'); }); }).catch(function (e) { $('#cerr').textContent = e.message; });
            });
        };
    });
    var accountFn = DO.pages[DO.pages.length - 1].fn;
})();
