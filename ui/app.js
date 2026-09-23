/* as-browser shell: tabs, address bar, search, bookmarks, history.
   Websites are separate pages (sites/<name>/index.html) loaded in an iframe. A site talks to this shell
   with postMessage through sdk/site.js, and the shell talks to the server. */
(function () {
    'use strict';

    var RESOURCE = 'as-browser';
    var DEV = !window.invokeNative;                 // true when opened outside FiveM (testing)
    var IS_NUI = /^cfx-nui-/.test(location.host);
    var MAX_TABS = 6;

    // ------------------------------------------------------------------ language
    // English text stays in index.html / the code as the default; loadLocale() fetches the chosen language
    // (Config.locale, see locales/) from the client script and applyI18n() swaps it in. Keep this block in
    // sync with sdk/site.js, which does the same for the website pages.
    var I18N = {};
    function t(key) {
        var s = Object.prototype.hasOwnProperty.call(I18N, key) ? I18N[key] : key;
        var args = Array.prototype.slice.call(arguments, 1), i = 0;
        return String(s).replace(/%[sd]/g, function () { return i < args.length ? args[i++] : ''; });
    }
    function applyI18n(root) {
        root = root || document;
        root.querySelectorAll('[data-i18n]').forEach(function (el) { if (I18N[el.dataset.i18n] != null) el.textContent = t(el.dataset.i18n); });
        ['placeholder', 'title', 'aria-label'].forEach(function (a) {
            root.querySelectorAll('[data-i18n-' + a + ']').forEach(function (el) {
                var k = el.getAttribute('data-i18n-' + a); if (I18N[k] != null) el.setAttribute(a, t(k));
            });
        });
    }

    var state = {
        sites: [], byDomain: {}, sitesOk: true,
        tabs: [], activeId: null,
        bookmarks: [],
        theme: 'light',
        phoneTheme: 'light',                        // last theme pushed by sd-phone
        themeOverride: null,                        // 'light' | 'dark' | null (null = match phone)
        textSize: 'normal',                         // 'small' | 'normal' | 'large'
        currency: '£',
        locale: {},                                 // the dictionary, also handed to website pages
    };
    var TEXT_SCALES = { small: 0.88, normal: 1, large: 1.18 };
    var nextTabId = 1;

    // ------------------------------------------------------------------ helpers

    function $(id) { return document.getElementById(id); }

    function h(tag, props, kids) {
        var el = document.createElement(tag);
        if (props) {
            Object.keys(props).forEach(function (k) {
                var v = props[k];
                if (v === null || v === undefined || v === false) return;
                if (k === 'class') el.className = v;
                else if (k === 'text') el.textContent = v;
                else if (k === 'html') el.innerHTML = v;
                else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
                else el.setAttribute(k, v === true ? '' : v);
            });
        }
        (kids || []).forEach(function (c) {
            if (c === null || c === undefined || c === false) return;
            el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
        });
        return el;
    }

    var I = {
        back: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>',
        fwd: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>',
        star: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9 6.8 19.7l1-5.9L3.5 9.7l5.9-.8z"/></svg>',
        starOn: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9 6.8 19.7l1-5.9L3.5 9.7l5.9-.8z"/></svg>',
        menu: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
        reload: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v5h-5"/></svg>',
        lock: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
        search: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>',
        x: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    };

    // ------------------------------------------------------------------ server calls

    function api(event, data) {
        if (typeof window.fetchNui === 'function') {
            return Promise.resolve(window.fetchNui(event, data || {})).catch(function () { return undefined; });
        }
        return fetch('https://' + RESOURCE + '/' + event, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then(function (r) { return r.json(); }).catch(function () { return undefined; });
    }

    function loadLocale() {
        return api('locale').then(function (d) {
            if (d && typeof d === 'object') I18N = d;
            applyI18n();
            state.locale = I18N;
        });
    }

    function loadSites() {
        return api('sites').then(function (list) {
            state.sitesOk = Array.isArray(list);
            state.sites = state.sitesOk ? list : [];
            state.byDomain = {};
            state.sites.forEach(function (s) { state.byDomain[String(s.domain).toLowerCase()] = s; });
        });
    }

    function loadBookmarks() {
        return api('bookmarks:list').then(function (list) { state.bookmarks = Array.isArray(list) ? list : []; });
    }

    // ------------------------------------------------------------------ URLs

    function parse(url) {
        url = String(url || 'about:newtab');
        if (url.indexOf('about:') === 0) {
            var rest = url.slice(6), qi = rest.indexOf('?');
            var name = qi < 0 ? rest : rest.slice(0, qi);
            var q = {};
            if (qi >= 0) new URLSearchParams(rest.slice(qi + 1)).forEach(function (v, k) { q[k] = v; });
            return { kind: 'about', name: name || 'newtab', q: q };
        }
        var m = url.match(/^([^\/#?]+)(.*)$/);
        var host = (m ? m[1] : url).toLowerCase().replace(/^www\./, '');
        var path = (m && m[2]) || '/';
        if (path.charAt(0) !== '/') path = '/' + path;
        return { kind: 'site', host: host, path: path, site: state.byDomain[host] || null };
    }

    function displayUrl(url) {
        var p = parse(url);
        if (p.kind === 'about') return '';
        return p.host + (p.path === '/' ? '' : p.path);
    }

    function resolveInput(text) {
        var q = String(text || '').trim();
        if (!q) return 'about:newtab';
        var s = q.replace(/^https?:\/\//i, '').replace(/^www\./i, '');
        var host = s.split(/[\/#?]/)[0].toLowerCase();
        if (state.byDomain[host]) return host + s.slice(host.length);
        if (/^[a-z0-9-]+(\.[a-z0-9-]+)+(\/\S*)?$/i.test(s)) return 'about:error?e=notfound&u=' + encodeURIComponent(host);
        return 'about:search?q=' + encodeURIComponent(q);
    }

    function frameUrl(site, path) {
        var base = IS_NUI ? 'https://cfx-nui-' + site.resource + '/' : '/';
        return base + site.page + '#' + path;
    }

    // ------------------------------------------------------------------ tabs

    function activeTab() {
        for (var i = 0; i < state.tabs.length; i++) if (state.tabs[i].id === state.activeId) return state.tabs[i];
        return null;
    }

    function currentUrl(tab) { return tab.hist[tab.idx]; }

    function newTab(url, activate) {
        var tab = {
            id: nextTabId++, hist: [url || 'about:newtab'], idx: 0, title: t('shell.newTab'),
            el: h('div', { class: 'tabview' }), frame: null, frameDomain: null, loading: false,
            histTimer: null, loadTimer: null,
        };
        $('viewport').appendChild(tab.el);
        state.tabs.push(tab);
        if (activate !== false) activateTab(tab, true);
        return tab;
    }

    function activateTab(tab, render) {
        state.activeId = tab.id;
        state.tabs.forEach(function (t) { t.el.classList.toggle('active', t === tab); });
        if (render && !tab.rendered) { tab.rendered = true; show(tab); } else { chrome(); persist(); }
    }

    function closeTab(tab) {
        var i = state.tabs.indexOf(tab);
        if (i < 0) return;
        destroyFrame(tab);
        clearTimeout(tab.histTimer); clearTimeout(tab.loadTimer);
        tab.el.remove();
        state.tabs.splice(i, 1);
        if (!state.tabs.length) { newTab('about:newtab', true); return; }
        if (state.activeId === tab.id) activateTab(state.tabs[Math.min(i, state.tabs.length - 1)], true);
        else { chrome(); persist(); }
    }

    function go(tab, url, opts) {
        opts = opts || {};
        if (opts.replace) {
            tab.hist[tab.idx] = url;
        } else {
            tab.hist = tab.hist.slice(0, tab.idx + 1);
            tab.hist.push(url);
            tab.idx = tab.hist.length - 1;
        }
        show(tab, opts);
    }

    function step(tab, delta) {
        var next = tab.idx + delta;
        if (next < 0 || next >= tab.hist.length) return;
        tab.idx = next;
        show(tab, {});
    }

    // ------------------------------------------------------------------ frames (websites)

    function destroyFrame(tab) {
        if (tab.frame) { tab.frame.remove(); tab.frame = null; tab.frameDomain = null; }
        setLoading(tab, false);
    }

    function setLoading(tab, on) {
        clearTimeout(tab.loadTimer);
        tab.loading = on;
        if (on) tab.loadTimer = setTimeout(function () { tab.loading = false; chrome(); }, 6000);
        chrome();
    }

    function toFrame(tab, msg) {
        if (!tab.frame || !tab.frame.contentWindow) return;
        msg.__asb = 1;
        try { tab.frame.contentWindow.postMessage(msg, '*'); } catch (e) { /* frame gone */ }
    }

    function ensureFrame(tab, p, opts) {
        if (tab.frame && tab.frameDomain === p.host) {
            if (!opts.fromSite) toFrame(tab, { type: 'route', path: p.path });
            return;
        }
        destroyFrame(tab);
        tab.el.innerHTML = '';
        tab.el.style.overflowY = 'hidden';
        var f = h('iframe', { class: 'siteframe', src: frameUrl(p.site, p.path), title: p.site.title, allow: 'fullscreen', allowfullscreen: true });
        tab.el.appendChild(f);
        tab.frame = f;
        tab.frameDomain = p.host;
        setLoading(tab, true);
    }

    function queueHistory(tab) {
        clearTimeout(tab.histTimer);
        tab.histTimer = setTimeout(function () {
            var p = parse(currentUrl(tab));
            if (p.kind !== 'site') return;
            api('history:add', { url: displayUrl(currentUrl(tab)) || p.host, title: tab.title });
        }, 900);
    }

    // ------------------------------------------------------------------ rendering a tab

    function show(tab, opts) {
        opts = opts || {};
        tab.rendered = true;
        var url = currentUrl(tab);
        var p = parse(url);

        if (p.kind === 'site' && !p.site) {
            url = 'about:error?e=notfound&u=' + encodeURIComponent(p.host);
            tab.hist[tab.idx] = url;
            p = parse(url);
        }

        if (p.kind === 'about') {
            destroyFrame(tab);
            tab.el.innerHTML = '';
            tab.el.style.overflowY = 'auto';
            var built = buildAbout(tab, p);
            tab.title = built.title;
            tab.el.appendChild(built.el);
            tab.el.scrollTop = 0;
        } else {
            tab.title = p.site.title;
            ensureFrame(tab, p, opts);
            queueHistory(tab);
        }
        chrome();
        persist();
    }

    function chrome() {
        var tab = activeTab();
        if (!tab) return;
        var url = currentUrl(tab);
        var p = parse(url);
        var input = $('urlInput');
        if (document.activeElement !== input) input.value = displayUrl(url);
        $('lockIcon').innerHTML = p.kind === 'site' ? I.lock : '';
        $('backBtn').disabled = tab.idx <= 0;
        $('fwdBtn').disabled = tab.idx >= tab.hist.length - 1;
        var marked = p.kind === 'site' && isBookmarked(displayUrl(url));
        $('starBtn').disabled = p.kind !== 'site';
        $('starBtn').classList.toggle('starred', marked);
        $('starBtn').innerHTML = marked ? I.starOn : I.star;
        $('tabCount').textContent = String(state.tabs.length);
        $('progress').classList.toggle('on', !!tab.loading);
        $('reloadBtn').style.visibility = p.kind === 'site' ? 'visible' : 'hidden';
    }

    // ------------------------------------------------------------------ native pages

    function siteTile(s, cls) {
        var ico = h('div', { class: 'ico', text: s.icon || '🌐' });
        ico.style.background = s.color || '';
        return ico;
    }

    function siteForUrl(url) { return parse(url).site; }

    function searchBox(tab, value) {
        var input = h('input', { type: 'text', placeholder: t('shell.searchPlaceholder'), value: value || '', autocapitalize: 'off', spellcheck: 'false' });
        var submit = function () { go(tab, resolveInput(input.value)); };
        input.addEventListener('keydown', function (e) { if (e.key === 'Enter') submit(); });
        return h('div', { class: 'searchbox' }, [input, h('button', { text: t('shell.search'), onclick: submit })]);
    }

    function siteRow(tab, s) {
        return h('button', { class: 'row', onclick: function () { go(tab, s.domain); } }, [
            siteTile(s),
            h('div', { class: 'txt' }, [
                h('div', { class: 't', text: s.title }),
                h('div', { class: 'u', text: s.domain }),
                h('div', { class: 'd', text: s.description || '' }),
            ]),
        ]);
    }

    function pageNewTab(tab) {
        var page = h('div', { class: 'page' });
        page.appendChild(h('h1', { text: t('shell.browser') }));
        page.appendChild(searchBox(tab, ''));

        if (state.bookmarks.length) {
            page.appendChild(h('h2', { text: t('shell.favourites') }));
            var tiles = h('div', { class: 'tiles' });
            state.bookmarks.slice(0, 8).forEach(function (b) {
                var site = siteForUrl(b.url);
                var ico = h('div', { class: 'ico', text: site ? site.icon : '🔖' });
                if (site) ico.style.background = site.color;
                tiles.appendChild(h('button', { class: 'tile', onclick: function () { go(tab, b.url); } }, [
                    ico, h('div', { class: 'lbl', text: b.title || b.url }),
                ]));
            });
            page.appendChild(tiles);
        }

        if (!state.sitesOk) {
            page.appendChild(h('div', { class: 'empty' }, [
                h('div', { class: 'big', text: '📡' }),
                h('div', { text: t('shell.offline') }),
            ]));
        } else if (!state.sites.length) {
            page.appendChild(h('div', { class: 'empty' }, [
                h('div', { class: 'big', text: '🌐' }),
                h('div', { text: t('shell.noSites') }),
            ]));
        } else {
            var groups = {};
            state.sites.forEach(function (s) { var cat = s.category || t('shell.categoryFallback'); (groups[cat] = groups[cat] || []).push(s); });
            Object.keys(groups).sort().forEach(function (cat) {
                page.appendChild(h('h2', { text: cat }));
                page.appendChild(h('div', { class: 'rows' }, groups[cat].map(function (s) { return siteRow(tab, s); })));
            });
        }
        return { el: page, title: t('shell.newTab') };
    }

    function score(terms, fields) {
        var total = 0;
        for (var i = 0; i < terms.length; i++) {
            var best = 0;
            for (var j = 0; j < fields.length; j++) {
                if (String(fields[j][0] || '').toLowerCase().indexOf(terms[i]) >= 0 && fields[j][1] > best) best = fields[j][1];
            }
            if (!best) return 0;
            total += best;
        }
        return total;
    }

    function searchAll(q) {
        var terms = String(q || '').toLowerCase().split(/\s+/).filter(Boolean);
        var out = [];
        if (!terms.length) return out;
        state.sites.forEach(function (s) {
            var sc = score(terms, [[s.title, 5], [s.domain, 4], [(s.keywords || []).join(' '), 3], [s.description, 1], [s.category, 1]]);
            if (sc > 0) out.push({ site: s, title: s.title, url: s.domain, desc: s.description, score: sc + 2 });
            (s.pages || []).forEach(function (pg) {
                var ps = score(terms, [[pg.title, 5], [(pg.keywords || []).join(' '), 3], [pg.description, 1]]);
                if (ps > 0) out.push({ site: s, title: pg.title, url: s.domain + pg.path, desc: pg.description || s.title, score: ps });
            });
        });
        out.sort(function (a, b) { return b.score - a.score; });
        return out.slice(0, 25);
    }

    function pageSearch(tab, q) {
        var page = h('div', { class: 'page' });
        page.appendChild(searchBox(tab, q));
        var results = searchAll(q);
        if (!results.length) {
            page.appendChild(h('div', { class: 'empty' }, [
                h('div', { class: 'big', text: '🔍' }),
                h('div', { text: t('shell.noResults', q) }),
                h('div', { class: 'sub', text: t('shell.noResultsHint') }),
            ]));
        } else {
            page.appendChild(h('h2', { text: results.length === 1 ? t('shell.results.one', results.length) : t('shell.results.other', results.length) }));
            page.appendChild(h('div', { class: 'rows' }, results.map(function (r) {
                return h('button', { class: 'row', onclick: function () { go(tab, r.url); } }, [
                    siteTile(r.site),
                    h('div', { class: 'txt' }, [
                        h('div', { class: 't', text: r.title }),
                        h('div', { class: 'u', text: r.url }),
                        h('div', { class: 'd', text: r.desc || '' }),
                    ]),
                ]);
            })));
        }
        return { el: page, title: q ? t('shell.searchTitle', q) : t('shell.search') };
    }

    function pageBookmarks(tab) {
        var page = h('div', { class: 'page' });
        page.appendChild(h('h1', { text: t('shell.bookmarks') }));
        var host = h('div');
        page.appendChild(host);
        var render = function () {
            host.innerHTML = '';
            if (!state.bookmarks.length) {
                host.appendChild(h('div', { class: 'empty' }, [
                    h('div', { class: 'big', text: '☆' }),
                    h('div', { text: t('shell.noBookmarks') }),
                    h('div', { class: 'sub', text: t('shell.noBookmarksHint') }),
                ]));
                return;
            }
            host.appendChild(h('div', { class: 'rows' }, state.bookmarks.map(function (b) {
                var site = siteForUrl(b.url);
                return h('div', { class: 'row' }, [
                    h('button', { class: 'row', style: 'border:0;padding:0;background:none;flex:1', onclick: function () { go(tab, b.url); } }, [
                        siteTile(site || { icon: '🔖' }),
                        h('div', { class: 'txt' }, [h('div', { class: 't', text: b.title || b.url }), h('div', { class: 'u', text: b.url })]),
                    ]),
                    h('button', { class: 'x', 'aria-label': t('shell.remove'), html: I.x, onclick: function () { removeBookmark(b.url).then(render); } }),
                ]);
            })));
        };
        render();
        return { el: page, title: t('shell.bookmarks') };
    }

    function fmtTime(ts) {
        var d = new Date(ts * 1000);
        return isNaN(d) ? '' : d.toLocaleDateString(t('shell.dateLocale'), { day: 'numeric', month: 'short' }) + ', ' + d.toLocaleTimeString(t('shell.dateLocale'), { hour: '2-digit', minute: '2-digit' });
    }

    function pageHistory(tab) {
        var page = h('div', { class: 'page' });
        var head = h('div', { class: 'toprow' }, [h('h1', { text: t('shell.history') })]);
        page.appendChild(head);
        var host = h('div', {}, [h('div', { class: 'empty', text: t('shell.loading') })]);
        page.appendChild(host);
        api('history:list').then(function (rows) {
            host.innerHTML = '';
            rows = Array.isArray(rows) ? rows : [];
            if (!rows.length) {
                host.appendChild(h('div', { class: 'empty' }, [h('div', { class: 'big', text: '🕘' }), h('div', { text: t('shell.historyEmpty') })]));
                return;
            }
            head.appendChild(h('button', {
                class: 'linkbtn', text: t('shell.clear'),
                onclick: function () { api('history:clear').then(function () { show(tab); }); },
            }));
            host.appendChild(h('div', { class: 'rows' }, rows.map(function (r) {
                var site = siteForUrl(r.url);
                return h('button', { class: 'row', onclick: function () { go(tab, r.url); } }, [
                    siteTile(site || { icon: '🌐' }),
                    h('div', { class: 'txt' }, [
                        h('div', { class: 't', text: r.title || r.url }),
                        h('div', { class: 'u', text: r.url }),
                        h('div', { class: 'd', text: fmtTime(r.visitedAt) }),
                    ]),
                ]);
            })));
        });
        return { el: page, title: t('shell.history') };
    }

    function pageError(tab, q) {
        var page = h('div', { class: 'page' });
        var unreachable = q.e === 'offline';
        page.appendChild(h('div', { class: 'empty' }, [
            h('div', { class: 'big', text: unreachable ? '📡' : '🧭' }),
            h('h1', { text: unreachable ? t('shell.cantConnect') : t('shell.siteNotFound') }),
            h('div', { class: 'sub', text: unreachable
                ? t('shell.networkDown')
                : t('shell.addressNotFound', q.u || t('shell.thatAddress')) }),
            h('button', { class: 'pill', text: q.u ? t('shell.searchForIt') : t('shell.goStartPage'), onclick: function () {
                go(tab, q.u ? 'about:search?q=' + encodeURIComponent(q.u) : 'about:newtab');
            } }),
        ]));
        return { el: page, title: t('shell.siteNotFound') };
    }

    function buildAbout(tab, p) {
        switch (p.name) {
            case 'search': return pageSearch(tab, p.q.q || '');
            case 'bookmarks': return pageBookmarks(tab);
            case 'history': return pageHistory(tab);
            case 'settings': return pageSettings(tab);
            case 'error': return pageError(tab, p.q);
            default: return pageNewTab(tab);
        }
    }

    // ------------------------------------------------------------------ settings

    function segRow(options, current, onPick) {
        return h('div', { class: 'segrow' }, options.map(function (o) {
            return h('button', {
                class: 'seg' + (o.value === current ? ' on' : ''),
                text: o.label,
                onclick: function () { onPick(o.value); },
            });
        }));
    }

    function pageSettings(tab) {
        var page = h('div', { class: 'page' });
        page.appendChild(h('h1', { text: t('shell.settings') }));

        var body = h('div');
        page.appendChild(body);

        function render() {
            body.innerHTML = '';
            body.appendChild(h('h2', { text: t('shell.appearance') }));
            body.appendChild(segRow([
                { value: null, label: t('shell.matchPhone') },
                { value: 'light', label: t('shell.light') },
                { value: 'dark', label: t('shell.dark') },
            ], state.themeOverride, function (v) { setThemeOverride(v); render(); }));

            body.appendChild(h('h2', { text: t('shell.textSize') }));
            body.appendChild(segRow([
                { value: 'small', label: t('shell.small') },
                { value: 'normal', label: t('shell.normal') },
                { value: 'large', label: t('shell.large') },
            ], state.textSize, function (v) { applyTextSize(v); render(); }));

            body.appendChild(h('h2', { text: t('shell.privacy') }));
            body.appendChild(h('div', { class: 'rows' }, [
                h('button', { class: 'row', onclick: function () {
                    api('history:clear').then(function () { toast(t('shell.historyCleared')); });
                } }, [h('div', { class: 'txt' }, [h('div', { class: 't', text: t('shell.clearHistory') })])]),
                h('button', { class: 'row', onclick: function () {
                    state.bookmarks.slice().forEach(function (b) { removeBookmark(b.url); });
                    toast(t('shell.bookmarksCleared'));
                } }, [h('div', { class: 'txt' }, [h('div', { class: 't', text: t('shell.clearBookmarks') })])]),
            ]));
        }
        render();
        return { el: page, title: t('shell.settings') };
    }

    // ------------------------------------------------------------------ bookmarks

    function isBookmarked(url) {
        for (var i = 0; i < state.bookmarks.length; i++) if (state.bookmarks[i].url === url) return true;
        return false;
    }

    function removeBookmark(url) {
        state.bookmarks = state.bookmarks.filter(function (b) { return b.url !== url; });
        chrome();
        return api('bookmarks:remove', { url: url });
    }

    function toggleBookmark() {
        var tab = activeTab();
        if (!tab) return;
        var url = displayUrl(currentUrl(tab));
        if (!url) return;
        if (isBookmarked(url)) {
            removeBookmark(url).then(function () { toast(t('shell.bookmarkRemoved')); });
            return;
        }
        state.bookmarks.unshift({ url: url, title: tab.title });
        chrome();
        api('bookmarks:add', { url: url, title: tab.title }).then(function (res) {
            if (res && res.ok) { toast(t('shell.bookmarked')); return; }
            state.bookmarks = state.bookmarks.filter(function (b) { return b.url !== url; });
            chrome();
            toast((res && res.error) || t('shell.bookmarkFailed'));
        });
    }

    // ------------------------------------------------------------------ overlays

    var toastTimer;
    function toast(msg) {
        var el = $('toast');
        el.textContent = msg;
        el.classList.add('on');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { el.classList.remove('on'); }, 2200);
    }

    function openTabs() {
        renderTabs();
        $('tabsOverlay').classList.add('on');
    }
    function closeTabs() { $('tabsOverlay').classList.remove('on'); }

    function renderTabs() {
        $('tabsTitle').textContent = state.tabs.length === 1 ? t('shell.tab.one', state.tabs.length) : t('shell.tab.other', state.tabs.length);
        var grid = $('tabsGrid');
        grid.innerHTML = '';
        state.tabs.forEach(function (tab) {
            var url = currentUrl(tab);
            var p = parse(url);
            var site = p.kind === 'site' ? p.site : null;
            var ico = h('div', { class: 'ico', text: site ? site.icon : '🌐' });
            if (site) ico.style.background = site.color;
            grid.appendChild(h('div', { class: 'tabcard' + (tab.id === state.activeId ? ' active' : ''), onclick: function () {
                activateTab(tab, true); closeTabs();
            } }, [
                ico,
                h('div', { class: 'tt', text: tab.title || t('shell.newTab') }),
                h('div', { class: 'tu', text: displayUrl(url) || t('shell.startPage') }),
                h('button', { class: 'close', 'aria-label': t('shell.closeTab'), html: I.x, onclick: function (e) {
                    e.stopPropagation(); closeTab(tab); if (state.tabs.length) renderTabs();
                } }),
            ]));
        });
        $('newTabBtn').style.visibility = state.tabs.length >= MAX_TABS ? 'hidden' : 'visible';
    }

    function openSheet() {
        var sheet = $('sheet');
        sheet.innerHTML = '';
        var item = function (label, fn, cls) {
            sheet.appendChild(h('button', { class: cls || '', text: label, onclick: function () { closeSheet(); fn(); } }));
        };
        var tab = activeTab();
        item(t('shell.newTab'), function () { addBlankTab(); });
        item(t('shell.bookmarks'), function () { go(tab, 'about:bookmarks'); });
        item(t('shell.history'), function () { go(tab, 'about:history'); });
        item(t('shell.startPage'), function () { go(tab, 'about:newtab'); });
        item(t('shell.settings'), function () { go(tab, 'about:settings'); });
        item(t('shell.closeThisTab'), function () { closeTab(tab); }, 'danger');
        $('scrim').classList.add('on');
        sheet.classList.add('on');
    }
    function closeSheet() { $('scrim').classList.remove('on'); $('sheet').classList.remove('on'); }

    function addBlankTab() {
        if (state.tabs.length >= MAX_TABS) { toast(t('shell.tabLimit', MAX_TABS)); return; }
        newTab('about:newtab', true);
    }

    // ------------------------------------------------------------------ messages from websites

    function reply(tab, id, ok, payload) {
        var msg = { type: 'reply', id: id, ok: ok };
        if (ok) msg.data = payload; else msg.error = payload;
        toFrame(tab, msg);
    }

    function copyText(text) {
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).catch(function () {}); }
        } catch (e) { /* fall through */ }
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); } catch (e) { /* ignore */ }
        ta.remove();
    }

    function onFrameMessage(ev) {
        var d = ev.data;
        if (!d || d.__asb !== 1) return;
        var tab = null;
        for (var i = 0; i < state.tabs.length; i++) {
            if (state.tabs[i].frame && state.tabs[i].frame.contentWindow === ev.source) { tab = state.tabs[i]; break; }
        }
        if (!tab) return;
        var domain = tab.frameDomain;

        switch (d.type) {
            case 'hello':
                setLoading(tab, false);
                toFrame(tab, {
                    type: 'init', theme: state.theme, textScale: TEXT_SCALES[state.textSize] || 1, domain: domain, currency: state.currency,
                    path: parse(currentUrl(tab)).path, title: tab.title,
                });
                break;

            case 'call':
                api('siteCall', { domain: domain, name: d.name, data: d.data || {} }).then(function (res) {
                    if (res && res.ok) reply(tab, d.id, true, res.data);
                    else reply(tab, d.id, false, (res && res.error) || t('shell.noServerResponse'));
                });
                break;

            case 'locale':
                reply(tab, d.id, true, state.locale);
                break;

            case 'player':
                api('player').then(function (res) { reply(tab, d.id, !!res, res || t('shell.noResponse')); });
                break;

            case 'path': {
                var path = String(d.path || '/');
                if (path.charAt(0) !== '/') path = '/' + path;
                if (path.length > 120 || /\s/.test(path)) break;
                var cur = parse(currentUrl(tab));
                if (cur.host !== domain || cur.path !== path) go(tab, domain + path, { fromSite: true });
                break;
            }

            case 'title':
                tab.title = String(d.title || '').slice(0, 80) || tab.title;
                if ($('tabsOverlay').classList.contains('on')) renderTabs();
                break;

            case 'open':
                go(tab, resolveInput(String(d.url || '')));
                break;

            case 'notify':
                if (typeof window.SendNotification === 'function') {
                    try { window.SendNotification({ title: String(d.title || ''), content: String(d.content || '') }); } catch (e) { /* ignore */ }
                } else {
                    toast(String(d.title || d.content || ''));
                }
                break;

            case 'saveLogin':
                api('savePassword', { username: d.username, password: d.password, email: d.email }).then(function (res) {
                    reply(tab, d.id, !!(res && res.ok), (res && res.ok) ? true : ((res && res.error) || t('shell.saveLoginFailed')));
                });
                break;

            case 'input':
                if (typeof window.ToggleInput === 'function') {
                    try { window.ToggleInput(!!d.focus); } catch (e) { /* ignore */ }
                }
                break;

            case 'copy':
                copyText(String(d.text || ''));
                toast(t('shell.copied'));
                reply(tab, d.id, true, true);
                break;

            case 'back':
                step(tab, -1);
                break;
        }
    }

    // ------------------------------------------------------------------ theme + persistence

    function applyEffectiveTheme() {
        state.theme = (state.themeOverride || state.phoneTheme) === 'dark' ? 'dark' : 'light';
        document.body.setAttribute('data-theme', state.theme);
        state.tabs.forEach(function (tab) { toFrame(tab, { type: 'theme', theme: state.theme }); });
    }
    function applyPhoneTheme(theme) {
        state.phoneTheme = theme === 'dark' ? 'dark' : 'light';
        applyEffectiveTheme();
    }
    function setThemeOverride(override) {
        state.themeOverride = (override === 'dark' || override === 'light') ? override : null;
        applyEffectiveTheme();
        persistPrefs();
    }

    function applyTextSize(size) {
        state.textSize = TEXT_SCALES[size] ? size : 'normal';
        var scale = TEXT_SCALES[state.textSize];
        document.documentElement.style.setProperty('--ts', scale);
        state.tabs.forEach(function (tab) { toFrame(tab, { type: 'textsize', scale: scale }); });
        persistPrefs();
    }

    function persistPrefs() {
        if (typeof window.SetStorage !== 'function') return;
        try { window.SetStorage('prefs', { themeOverride: state.themeOverride, textSize: state.textSize }); } catch (e) { /* storage unavailable */ }
    }
    function restorePrefs() {
        var get = typeof window.GetStorage === 'function' ? window.GetStorage('prefs', null) : Promise.resolve(null);
        return Promise.resolve(get).catch(function () { return null; }).then(function (saved) {
            if (saved && typeof saved === 'object') {
                if (saved.themeOverride === 'dark' || saved.themeOverride === 'light') state.themeOverride = saved.themeOverride;
                if (TEXT_SCALES[saved.textSize]) state.textSize = saved.textSize;
            }
            applyEffectiveTheme();
            document.documentElement.style.setProperty('--ts', TEXT_SCALES[state.textSize]);
        });
    }

    function persist() {
        if (typeof window.SetStorage !== 'function') return;
        try {
            window.SetStorage('session', {
                urls: state.tabs.map(currentUrl).map(function (u) { return String(u).slice(0, 150); }),
                active: state.tabs.indexOf(activeTab()),
            });
        } catch (e) { /* storage unavailable */ }
    }

    function restoreSession() {
        var get = typeof window.GetStorage === 'function' ? window.GetStorage('session', null) : Promise.resolve(null);
        return Promise.resolve(get).catch(function () { return null; }).then(function (saved) {
            if (saved && Array.isArray(saved.urls) && saved.urls.length) {
                saved.urls.slice(0, MAX_TABS).forEach(function (u) { newTab(String(u), false); });
                var idx = Math.max(0, Math.min(saved.active | 0, state.tabs.length - 1));
                activateTab(state.tabs[idx], true);
            } else {
                newTab('about:newtab', true);
            }
        });
    }

    function refreshSites() {
        return Promise.all([loadSites(), loadBookmarks()]).then(function () {
            state.tabs.forEach(function (tab) {
                var p = parse(currentUrl(tab));
                var stale = p.kind === 'site' && !p.site;
                var overview = p.kind === 'about' && (p.name === 'newtab' || p.name === 'search');
                if (tab.rendered && (stale || overview)) show(tab);
            });
            chrome();
        });
    }

    // ------------------------------------------------------------------ start up

    function bindUi() {
        $('backBtn').innerHTML = I.back;
        $('fwdBtn').innerHTML = I.fwd;
        $('starBtn').innerHTML = I.star;
        $('menuBtn').innerHTML = I.menu;
        $('reloadBtn').innerHTML = I.reload;

        $('backBtn').addEventListener('click', function () { var t = activeTab(); if (t) step(t, -1); });
        $('fwdBtn').addEventListener('click', function () { var t = activeTab(); if (t) step(t, 1); });
        $('starBtn').addEventListener('click', toggleBookmark);
        $('menuBtn').addEventListener('click', openSheet);
        $('tabBtn').addEventListener('click', openTabs);
        $('tabsDoneBtn').addEventListener('click', closeTabs);
        $('newTabBtn').addEventListener('click', function () { closeTabs(); addBlankTab(); });
        $('scrim').addEventListener('click', closeSheet);
        $('reloadBtn').addEventListener('click', function () {
            var t = activeTab();
            if (!t) return;
            destroyFrame(t);
            show(t);
        });

        var input = $('urlInput');
        input.addEventListener('focus', function () { setTimeout(function () { input.select(); }, 0); });
        input.addEventListener('blur', chrome);
        input.addEventListener('keydown', function (e) {
            if (e.key === 'Enter') {
                var t = activeTab();
                if (t) go(t, resolveInput(input.value));
                input.blur();
            } else if (e.key === 'Escape') {
                input.blur();
            }
        });

        window.addEventListener('message', function (ev) {
            var d = ev.data;
            if (d && typeof d === 'object' && d.__asb === 1) return onFrameMessage(ev);
            if (d && d.action === 'sitesChanged') refreshSites();
            if (d && d.action === 'sd-phone:theme' && d.theme) applyPhoneTheme(d.theme);
        });
    }

    function start() {
        document.documentElement.style.visibility = 'visible';
        document.body.style.visibility = 'visible';
        bindUi();

        var settings = typeof window.GetSettings === 'function' ? Promise.resolve(window.GetSettings()).catch(function () { return null; }) : Promise.resolve(null);
        settings.then(function (s) {
            var theme = s && (s.theme || (s.display && s.display.theme));
            if (theme) applyPhoneTheme(theme);
        });
        if (typeof window.OnSettingsChange === 'function') {
            window.OnSettingsChange(function (s) {
                var theme = s && (s.theme || (s.display && s.display.theme));
                if (theme) applyPhoneTheme(theme);
            });
        }
        if (typeof window.useNuiEvent === 'function') window.useNuiEvent('sitesChanged', refreshSites);

        restorePrefs();
        Promise.all([loadLocale(), loadSites(), loadBookmarks()]).then(restoreSession);
    }

    function whenReady() {
        return new Promise(function (resolve) {
            if (window.componentsLoaded) return resolve();
            var poll = setInterval(function () { if (window.componentsLoaded) { clearInterval(poll); resolve(); } }, 50);
            window.addEventListener('message', function (e) { if (e.data === 'componentsLoaded') { clearInterval(poll); resolve(); } });
        });
    }

    if (DEV) start(); else whenReady().then(start);
})();
