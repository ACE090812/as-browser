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
            if (d.path) setRoute(d.path, false);
        } else if (d.type === 'route') {
            setRoute(d.path, false);
        } else if (d.type === 'theme') {
            setTheme(d.theme);
        }
    });

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
