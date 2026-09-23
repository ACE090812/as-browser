/* Site SDK: include this in every website page.
     <link rel="stylesheet" href="/sdk/site.css">
     <script src="/sdk/site.js"></script>
   (A site added from another resource uses https://cfx-nui-as-browser/sdk/site.js and .css.)

   Site.call(name, data)   ask the site's server handler; resolves the result, rejects with an Error
   Site.player()           resolves { name } for the character browsing
   Site.route()            current page path, e.g. "/vehicle-checker/AB12CDE"
   Site.onRoute(fn)        fn(path) runs at start and whenever the page changes (back, forward, links)
   Site.go(path)           change page inside this site (adds a history entry)
   Site.open(url)          go to another site, e.g. Site.open('lsgov.co.uk/tax-vehicle')
   Site.title(text)        set the tab / history title
   Site.notify({title, content})   phone notification
   Site.copy(text)         copy to the clipboard
   Site.canPrint()  promise of true when printing is set up
   Site.print(name, data, {title})   print dialog, then Site.call(name, data + { printer, colour, letterhead }); the site's handler prints with Browser.printDoc
   Site.saveLogin({username, password, email})   save to the Passwords app (needs the sd-phone edit)
   Site.onTheme(fn)        fn('light'|'dark'); the page also gets data-theme on <html>
   Site.esc / Site.money / Site.date / Site.datetime   small helpers

   Languages: the shell hands every page the language dictionary (Config.locale, locales/*.lua) before
   the page draws anything, so a page only needs
     t(key)                     text for a locale key (extra arguments fill %s / %d in order); a missing key returns the key
     applyI18n(root)            fills elements that carry a data-i18n attribute (also data-i18n-placeholder / -title / -aria-label)
     Site.onReady(fn)           fn() runs once the dictionary has arrived (Site.onRoute waits for it too)
   Keep the English text in the markup as the default, and add the same key to locales/en.lua.
*/
(function () {
    'use strict';

    var pending = {};
    var seq = 0;
    var route = null;
    var routeCbs = [];
    var themeCbs = [];
    var Site = window.Site = { theme: 'light', domain: '', currency: '£' };

    // ---------------------------------------------------------------- language

    var I18N = window.I18N = {};
    var ready = false;
    var readyCbs = [];

    window.t = function (key) {
        var s = Object.prototype.hasOwnProperty.call(I18N, key) ? I18N[key] : key;
        var args = Array.prototype.slice.call(arguments, 1), i = 0;
        return String(s).replace(/%[sd]/g, function () { return i < args.length ? args[i++] : ''; });
    };
    window.applyI18n = function (root) {
        root = root || document;
        root.querySelectorAll('[data-i18n]').forEach(function (el) { if (I18N[el.dataset.i18n] != null) el.textContent = window.t(el.dataset.i18n); });
        ['placeholder', 'title', 'aria-label'].forEach(function (a) {
            root.querySelectorAll('[data-i18n-' + a + ']').forEach(function (el) {
                var k = el.getAttribute('data-i18n-' + a); if (I18N[k] != null) el.setAttribute(a, window.t(k));
            });
        });
    };
    var t = window.t;
    // (The three SDK errors below keep an English fallback for the moment before the dictionary arrives.)

    function dateLocale() { return I18N['sdk.dateLocale'] ? t('sdk.dateLocale') : 'en-GB'; }

    function whenReady() {
        if (ready) return;
        ready = true;
        window.applyI18n();
        readyCbs.forEach(function (cb) { try { cb(); } catch (e) { console.error(e); } });
        readyCbs = [];
        setTimeout(fireRoute, 0);
    }
    Site.onReady = function (cb) {
        if (ready) setTimeout(cb, 0); else readyCbs.push(cb);
    };

    function post(msg) {
        msg.__asb = 1;
        try { window.parent.postMessage(msg, '*'); } catch (e) { /* not framed */ }
    }

    function request(type, payload) {
        return new Promise(function (resolve, reject) {
            if (window.parent === window) { reject(new Error(I18N['sdk.notFramed'] ? t('sdk.notFramed') : 'Open this site in the Browser app.')); return; }
            var id = ++seq;
            var timer = setTimeout(function () {
                delete pending[id];
                reject(new Error(I18N['sdk.timeout'] ? t('sdk.timeout') : 'The request timed out. Please try again.'));
            }, 20000);
            pending[id] = { resolve: resolve, reject: reject, timer: timer };
            var msg = { type: type, id: id };
            Object.keys(payload || {}).forEach(function (k) { msg[k] = payload[k]; });
            post(msg);
        });
    }

    // ---------------------------------------------------------------- routing

    function normalize(path) {
        path = String(path || '/');
        if (path.charAt(0) !== '/') path = '/' + path;
        return path;
    }

    function currentRoute() { return normalize(location.hash.replace(/^#/, '') || '/'); }

    function fireRoute() {
        if (!ready) return;     // the first draw waits for the dictionary (see whenReady)
        routeCbs.forEach(function (cb) { try { cb(route); } catch (e) { console.error(e); } });
    }

    function setRoute(path, notify) {
        path = normalize(path);
        if (path === route) return;
        route = path;
        try { history.replaceState(null, '', '#' + path); } catch (e) { location.hash = path; }
        fireRoute();
        if (notify) post({ type: 'path', path: path });
    }

    Site.route = function () { return route; };
    Site.go = function (path) { setRoute(path, true); };
    Site.onRoute = function (cb) {
        routeCbs.push(cb);
        if (ready) setTimeout(function () { try { cb(route); } catch (e) { console.error(e); } }, 0);
    };

    // ---------------------------------------------------------------- talking to the shell

    Site.call = function (name, data) { return request('call', { name: name, data: data || {} }); };
    Site.player = function () { return request('player'); };
    Site.saveLogin = function (login) {
        login = login || {};
        return request('saveLogin', { username: login.username, password: login.password, email: login.email });
    };
    Site.copy = function (text) { return request('copy', { text: String(text) }); };

    // ---------------------------------------------------------------- printing (needs the as-printer resource)
    // Site.print(name, data)  opens the print dialog (printer within range, colour or black and white, letterhead) and then calls the
    // site's own request `name` with data plus { printer, colour, design, letterhead }. Resolves { pages, seconds, printer }, or null
    // if the player cancelled. The site's handler builds the document on the server (Browser.printDoc in server/printing.lua).
    function tx(key, def) { return I18N[key] != null ? t(key) : def; }
    Site.print = function (name, data, o) {
        o = o || {};
        return new Promise(function (resolve) {
            var host = document.createElement('div');
            host.className = 'asb-print';
            document.body.appendChild(host);
            var esc = Site.esc, closed = false;
            function close(v) { if (closed) return; closed = true; host.remove(); resolve(v); }
            function box(title, body, buttons) {
                host.innerHTML = '<div class="asb-print-box" role="dialog"><h3>' + esc(title) + '</h3><div class="asb-print-body">' + body + '</div><div class="asb-print-foot"></div></div>';
                var foot = host.querySelector('.asb-print-foot');
                buttons.forEach(function (b) {
                    var el = document.createElement('button');
                    el.type = 'button'; el.className = b.primary ? 'btn' : 'btn ghost'; el.textContent = b.label;
                    el.addEventListener('click', b.run);
                    foot.appendChild(el);
                });
            }
            function message(text, bad) {
                box(tx('print.title', 'Print'), '<div class="' + (bad ? 'notice bad' : 'notice good') + '">' + esc(text) + '</div>', [{ label: tx('print.ok', 'OK'), primary: true, run: function () { close(null); } }]);
            }
            box(tx('print.title', 'Print'), '<div class="spinner"></div><div class="muted">' + esc(tx('print.looking', 'Looking for printers nearby…')) + '</div>', [{ label: tx('print.cancel', 'Cancel'), run: function () { close(null); } }]);
            Site.call('_print.options').then(function (d) {
                if (closed) return;
                if (!d || !d.available) { message(tx('print.off', 'Printing is not available.'), true); return; }
                if (!(d.printers || []).length) { message(tx('print.none', 'There is no printer within range. Move closer to one.'), true); return; }
                var first = null;
                var popts = d.printers.map(function (p) {
                    var bad = !p.allowed || p.paper <= 0 || p.black <= 0;
                    if (!bad && !first) first = p.key;
                    return '<option value="' + esc(p.key) + '"' + (bad ? ' disabled' : '') + '>' + esc(p.label + ' · ' + Math.round(p.distance) + ' m · ' +
                        (p.allowed ? t('print.levels', p.paper, p.black, p.colour) : tx('print.restricted', 'restricted'))) + '</option>';
                }).join('');
                var lopts = '<option value="">' + esc(tx('print.noLetterhead', 'None')) + '</option>' + (d.letterheads || []).map(function (x) { return '<option value="' + esc(x.id) + '">' + esc(x.label) + '</option>'; }).join('');
                var dopts = o.design === false ? '' : (d.designs || []).map(function (x) { return '<option value="' + esc(x.id) + '">' + esc(x.label) + '</option>'; }).join('');
                box((o.title ? tx('print.title', 'Print') + ' — ' + o.title : tx('print.title', 'Print')),
                    '<div class="field"><label>' + esc(tx('print.printer', 'Printer')) + '</label><select id="asb-pr-printer">' + popts + '</select></div>' +
                    '<div class="field"><label>' + esc(tx('print.mode', 'Colour')) + '</label><select id="asb-pr-colour"><option value="0">' + esc(tx('print.bw', 'Black and white')) + '</option><option value="1">' + esc(tx('print.colour', 'Colour')) + '</option></select></div>' +
                    (o.letterhead === false ? '' : '<div class="field"><label>' + esc(tx('print.letterhead', 'Letterhead')) + '</label><select id="asb-pr-letter">' + lopts + '</select></div>'),
                    [{ label: tx('print.go', 'Print'), primary: true, run: function () {
                        var body = {};
                        Object.keys(data || {}).forEach(function (k) { body[k] = data[k]; });
                        body.printer = host.querySelector('#asb-pr-printer').value;
                        body.colour = host.querySelector('#asb-pr-colour').value === '1';
                        var l = host.querySelector('#asb-pr-letter'); body.letterhead = l ? l.value : '';
                        box(tx('print.title', 'Print'), '<div class="spinner"></div>', []);
                        Site.call(name, body).then(function (r) {
                            r = r || {};
                            message(t('print.sent', r.printer || tx('print.printer', 'Printer'), r.seconds || 0), false);
                        }, function (e) { message(e.message, true); });
                    } }, { label: tx('print.cancel', 'Cancel'), run: function () { close(null); } }]);
                if (first) host.querySelector('#asb-pr-printer').value = first;
            }, function (e) { message(e.message, true); });
        });
    };
    // Site.canPrint().then(function (yes) { ... })  true when the as-printer resource is running; pages show their Print button only then
    var canPrintP = null;
    Site.canPrint = function () {
        if (!canPrintP) canPrintP = Site.call('_print.options').then(function (d) { return !!(d && d.available); }, function () { return false; });
        return canPrintP;
    };
    Site.open = function (url) { post({ type: 'open', url: String(url) }); };
    Site.back = function () { post({ type: 'back' }); };
    Site.notify = function (n) { n = n || {}; post({ type: 'notify', title: n.title, content: n.content }); };
    Site.title = function (t) {
        t = String(t || '');
        if (t) document.title = t;
        post({ type: 'title', title: t });
    };

    // ---------------------------------------------------------------- theme

    function setTheme(t) {
        Site.theme = t === 'dark' ? 'dark' : 'light';
        document.documentElement.setAttribute('data-theme', Site.theme);
        themeCbs.forEach(function (cb) { try { cb(Site.theme); } catch (e) { console.error(e); } });
    }
    Site.onTheme = function (cb) { themeCbs.push(cb); };

    // ---------------------------------------------------------------- text size
    // The shell's Settings > Text size choice is broadcast here as a CSS scale (0.88 / 1 / 1.18) and applied
    // as --ts on <html>. sdk/site.css multiplies its own font-sizes by it, so every page gets it for free.
    function setTextScale(n) {
        n = Number(n) || 1;
        document.documentElement.style.setProperty('--ts', n);
    }

    // ---------------------------------------------------------------- helpers

    Site.esc = function (s) {
        return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    };
    Site.money = function (n) {
        n = Number(n) || 0;
        return Site.currency + n.toLocaleString(dateLocale(), { maximumFractionDigits: 0 });
    };
    Site.date = function (ts) {
        var d = new Date(Number(ts) * 1000);
        return isNaN(d) ? '' : d.toLocaleDateString(dateLocale(), { day: 'numeric', month: 'short', year: 'numeric' });
    };
    Site.datetime = function (ts) {
        var d = new Date(Number(ts) * 1000);
        return isNaN(d) ? '' : d.toLocaleDateString(dateLocale(), { day: 'numeric', month: 'short', year: 'numeric' }) +
            ', ' + d.toLocaleTimeString(dateLocale(), { hour: '2-digit', minute: '2-digit' });
    };

    // ---------------------------------------------------------------- messages from the shell

    window.addEventListener('message', function (ev) {
        if (ev.source !== window.parent) return;
        var d = ev.data;
        if (!d || d.__asb !== 1) return;

        if (d.type === 'reply') {
            var p = pending[d.id];
            if (!p) return;
            delete pending[d.id];
            clearTimeout(p.timer);
            if (d.ok) p.resolve(d.data); else p.reject(new Error(d.error || (I18N['sdk.error'] ? t('sdk.error') : 'Something went wrong.')));
        } else if (d.type === 'init') {
            Site.domain = d.domain || '';
            Site.currency = d.currency || Site.currency;
            setTheme(d.theme);
            setTextScale(d.textScale);
            if (d.path) setRoute(d.path, false);
        } else if (d.type === 'route') {
            setRoute(d.path, false);
        } else if (d.type === 'theme') {
            setTheme(d.theme);
        } else if (d.type === 'textsize') {
            setTextScale(d.scale);
        } else if (d.type === 'snapshot') {
            snapshot(d.id, Number(d.w) || 640);
        }
    });

    // ---------------------------------------------------------------- snapshots
    // as-computer's live monitor view asks the page for a picture of what is on screen (about once a second
    // while someone uses the computer). html-to-image is loaded the first time it is needed.
    var SDK_BASE = (document.currentScript && document.currentScript.src || '/sdk/site.js').replace(/site\.js(\?.*)?$/, '');
    var h2i = null, snapBusy = false;
    var PLACEHOLDER = 'data:image/gif;base64,R0lGODlhAQABAIAAAMzMzAAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw==';
    function loadH2i() {
        if (h2i) return h2i;
        h2i = new Promise(function (resolve, reject) {
            if (window.htmlToImage) return resolve(window.htmlToImage);
            var sc = document.createElement('script');
            sc.src = SDK_BASE + 'html-to-image.js';
            sc.onload = function () { resolve(window.htmlToImage); };
            sc.onerror = function () { h2i = null; reject(new Error('no html-to-image')); };
            document.head.appendChild(sc);
        });
        return h2i;
    }
    function snapshot(id, w) {
        if (snapBusy) return post({ type: 'snapshot', id: id, data: null });
        snapBusy = true;
        var vw = window.innerWidth, vh = window.innerHeight, sy = window.scrollY || 0;
        var bg = getComputedStyle(document.body).backgroundColor || '#ffffff';
        loadH2i().then(function (lib) {
            return lib.toJpeg(document.body, {
                width: vw, height: vh, canvasWidth: Math.round(w), canvasHeight: Math.round(w * vh / vw), pixelRatio: 1,
                quality: 0.6, skipFonts: true, cacheBust: false, imagePlaceholder: PLACEHOLDER, backgroundColor: bg,
                style: { margin: '0', transform: 'translateY(' + (-sy) + 'px)', transformOrigin: '0 0', minHeight: vh + 'px' },
                filter: function (n) {
                    if (n.nodeType !== 1) return true;
                    if (n.tagName === 'IFRAME') return false;
                    var rs = n.getClientRects();
                    if (!rs.length) return false;                              // not displayed
                    var r = n.getBoundingClientRect();
                    return r.bottom >= 0 && r.top <= vh && r.right >= 0 && r.left <= vw;   // off screen
                },
            });
        }).then(function (data) { post({ type: 'snapshot', id: id, data: data }); }, function () { post({ type: 'snapshot', id: id, data: null }); })
            .then(function () { snapBusy = false; });
    }

    // ---------------------------------------------------------------- print buttons
    // Any element with data-print="requestName" (and data-pd='{"id":1}' for its data, data-ptitle for the dialog title) becomes a
    // print button: hidden until as-printer is running, and it opens Site.print when clicked. Nothing else to wire up in a page.
    document.addEventListener('click', function (e) {
        var b = e.target.closest && e.target.closest('[data-print]');
        if (!b || b.disabled) return;
        e.preventDefault();
        var data = {};
        try { data = JSON.parse(b.getAttribute('data-pd') || '{}') || {}; } catch (x) { data = {}; }
        Site.print(b.getAttribute('data-print'), data, { title: b.getAttribute('data-ptitle') || '' });
    });
    function markPrint() { Site.canPrint().then(function (yes) { if (yes) document.documentElement.classList.add('can-print'); }); }
    Site.onReady(markPrint);

    // ---------------------------------------------------------------- game keyboard capture
    // The phone turns game controls off while a text field has focus. The shell can't see inside
    // this page, so tell it when a field gains or loses focus.

    function isField(el) {
        return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable);
    }
    document.addEventListener('focusin', function (e) { if (isField(e.target)) post({ type: 'input', focus: true }); });
    document.addEventListener('focusout', function (e) { if (isField(e.target)) post({ type: 'input', focus: false }); });

    // ---------------------------------------------------------------- start

    route = currentRoute();
    function loadLocale() {
        // Ask the shell for the dictionary. If it is late, framed badly or missing, draw in English.
        var done = false;
        var finish = function () { if (!done) { done = true; whenReady(); } };
        var timer = setTimeout(finish, 4000);
        request('locale').then(function (d) {
            if (d && typeof d === 'object') { I18N = window.I18N = d; }
            clearTimeout(timer); finish();
        }).catch(function () { clearTimeout(timer); finish(); });
    }
    function hello() { post({ type: 'hello' }); loadLocale(); }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', hello);
    else hello();
})();
