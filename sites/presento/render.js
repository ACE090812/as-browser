/* Presento slide renderer, shared by the site (index.html) and the in-game TV page (tv.html).
   PresentoRender.renderSlide(slide, box, opts) draws a slide (1280 x 720 units) into `box`.
     opts.ph     show placeholder text in empty text boxes (editor only)
     opts.scale  fixed scale; otherwise it follows the box's width
     opts.live   true (or one element id) = draw real video players instead of posters
     opts.muted  force every video muted (TV screens)
*/
(function () {
    function esc(s) {
        return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function tr(key, def) {
        if (typeof window.t !== 'function') return def;
        var v = window.t(key);
        return v === key ? def : v;
    }
    // ------------------------------------------------------------------ slide renderer
    // Draws a slide (1280 x 720 units) into `box`, scaled to the box's width.
    //   opts.ph      show placeholder text in empty text boxes (editor only)
    //   opts.scale   fixed scale (the editor); otherwise it follows the box's width
    var FONTS = {
        sans: '"Segoe UI", Arial, sans-serif', serif: 'Georgia, "Times New Roman", serif',
        mono: 'Consolas, "Courier New", monospace', display: 'Impact, "Arial Black", sans-serif',
        round: '"Trebuchet MS", Verdana, sans-serif',
    };
    function num(v, d) { v = Number(v); return isFinite(v) ? v : d; }
    function safeColor(c, d) { c = String(c || ''); return /^#[0-9a-fA-F]{3,8}$/.test(c) || c === 'transparent' ? c : d; }
    function safeUrl(u) { u = String(u || ''); return /^https:\/\/[^\s"'<>]+$/.test(u) ? u : ''; }
    function place(node, e) {
        node.classList.add('el');
        node.style.left = num(e.x, 0) + 'px'; node.style.top = num(e.y, 0) + 'px';
        node.style.width = num(e.w, 100) + 'px'; node.style.height = num(e.h, 50) + 'px';
        node.style.transform = num(e.rot, 0) ? 'rotate(' + num(e.rot, 0) + 'deg)' : '';
        if (e.opacity != null) node.style.opacity = Math.max(0, Math.min(1, num(e.opacity, 1)));
        node.setAttribute('data-id', e.id || '');
        return node;
    }
    function textNode(e, opts) {
        var d = document.createElement('div');
        d.className = 'txt v-' + (e.valign === 'middle' || e.valign === 'bottom' ? e.valign : 'top');
        d.style.fontFamily = FONTS[e.font] || FONTS.sans;
        d.style.fontSize = num(e.size, 24) + 'px';
        d.style.color = safeColor(e.color, '#1f2937');
        d.style.textAlign = ['left', 'center', 'right', 'justify'].indexOf(e.align) >= 0 ? e.align : 'left';
        if (e.bold) d.style.fontWeight = '700';
        if (e.italic) d.style.fontStyle = 'italic';
        if (e.underline) d.style.textDecoration = 'underline';
        if (e.fill) d.style.background = safeColor(e.fill, 'transparent');
        var inner = document.createElement('div');
        if (e.text) inner.textContent = e.text;
        else if (opts.ph && e.ph) { inner.className = 'ph'; inner.textContent = tr('presento.ph.' + e.ph, ''); }
        d.appendChild(inner);
        return d;
    }
    function shapeNode(e) {
        var d = document.createElement('div');
        d.style.background = safeColor(e.fill, '#4285f4');
        if (num(e.stroke, 0) > 0) d.style.border = num(e.stroke, 0) + 'px solid ' + safeColor(e.strokeColor, '#1f2937');
        if (e.shape === 'ellipse') d.style.borderRadius = '50%';
        else if (e.shape === 'round') d.style.borderRadius = Math.min(40, num(e.h, 50) / 4, num(e.w, 100) / 4) + 'px';
        return d;
    }
    function lineNode(e) {
        var ns = 'http://www.w3.org/2000/svg';
        var w = num(e.w, 100), h = num(e.h, 20), sw = num(e.stroke, 4), y = h / 2, col = safeColor(e.color, '#1f2937');
        var s = document.createElementNS(ns, 'svg');
        s.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
        s.setAttribute('preserveAspectRatio', 'none');
        var l = document.createElementNS(ns, 'line');
        l.setAttribute('x1', 0); l.setAttribute('y1', y); l.setAttribute('x2', e.arrow ? Math.max(0, w - sw * 3) : w); l.setAttribute('y2', y);
        l.setAttribute('stroke', col); l.setAttribute('stroke-width', sw); l.setAttribute('stroke-linecap', e.arrow ? 'butt' : 'round');
        s.appendChild(l);
        if (e.arrow) {
            var a = document.createElementNS(ns, 'polygon');
            a.setAttribute('points', w + ',' + y + ' ' + (w - sw * 4) + ',' + (y - sw * 2) + ' ' + (w - sw * 4) + ',' + (y + sw * 2));
            a.setAttribute('fill', col);
            s.appendChild(a);
        }
        return s;
    }
    function tableNode(e) {
        var tb = document.createElement('table');
        var rows = Array.isArray(e.cells) ? e.cells : [];
        var border = '1px solid ' + safeColor(e.strokeColor, '#9aa0a6');
        rows.forEach(function (r, ri) {
            var tr = tb.insertRow();
            (Array.isArray(r) ? r : []).forEach(function (c) {
                var td = tr.insertCell();
                td.textContent = c == null ? '' : String(c);
                td.style.border = border;
                if (ri === 0) { td.style.background = safeColor(e.headFill, '#e8eaed'); td.style.fontWeight = '700'; }
            });
        });
        tb.style.fontSize = num(e.size, 20) + 'px';
        tb.style.color = safeColor(e.color, '#1f2937');
        return tb;
    }
    function ytThumb(v) { return /^[\w-]{11}$/.test(v || '') ? 'https://img.youtube.com/vi/' + v + '/hqdefault.jpg' : ''; }
    // A video shows as a poster with a play button; opts.live (true, or the element's id) draws the real player.
    function videoNode(e, opts) {
        var live = opts.live === true || (opts.live && opts.live === e.id);
        if (live && e.src === 'youtube' && /^[\w-]{11}$/.test(e.vid || '')) {
            var f = document.createElement('iframe');
            f.src = 'https://www.youtube-nocookie.com/embed/' + e.vid + '?autoplay=1&rel=0&modestbranding=1&playsinline=1' +
                (e.start ? '&start=' + Math.floor(e.start) : '') + (e.muted || opts.muted ? '&mute=1' : '') + (e.loop ? '&loop=1&playlist=' + e.vid : '');
            f.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture');
            f.setAttribute('allowfullscreen', '');
            return f;
        }
        var url = safeUrl(e.url);
        if (live && url) {
            var v = document.createElement('video');
            v.src = url; v.autoplay = true; v.controls = true; v.playsInline = true; v.muted = !!(e.muted || opts.muted); v.loop = !!e.loop;
            if (safeUrl(e.thumb)) v.poster = e.thumb;
            v.style.objectFit = 'contain';
            return v;
        }
        var d = document.createElement('div');
        d.className = 'vid';
        var th = e.src === 'youtube' ? ytThumb(e.vid) : safeUrl(e.thumb);
        if (th) d.style.backgroundImage = 'url("' + th + '")';
        d.innerHTML = '<span class="play"></span><span class="vbadge">' + (e.src === 'youtube' ? 'YouTube' : e.src === 'clip' ? 'ClipZone' : esc(tr('presento.v.video', 'Video'))) + '</span>';
        return d;
    }
    function elNode(e, opts) {
        switch (e && e.type) {
            case 'text': return place(textNode(e, opts), e);
            case 'shape': return place(shapeNode(e), e);
            case 'line': return place(lineNode(e), e);
            case 'table': return place(tableNode(e), e);
            case 'video': return place(videoNode(e, opts || {}), e);
            case 'image': {
                var src = safeUrl(e.src);
                if (!src) return null;
                var img = document.createElement('img'); img.src = src; img.alt = ''; img.draggable = false;
                img.style.objectFit = e.fit === 'contain' ? 'contain' : 'cover';
                return place(img, e);
            }
        }
        return null;
    }
    var RO = window.ResizeObserver ? new ResizeObserver(function (list) {
        list.forEach(function (en) { var s = en.target.__slide, w = en.target.clientWidth; if (s && w) s.style.transform = 'scale(' + (w / 1280) + ')'; });
    }) : null;
    function renderSlide(slide, box, opts) {
        opts = opts || {};
        var s = document.createElement('div');
        s.className = 'slide';
        s.style.background = safeColor(slide && slide.bg, '#ffffff');
        var els = slide && Array.isArray(slide.els) ? slide.els : [];
        els.forEach(function (e) { var n = elNode(e, opts); if (n) s.appendChild(n); });
        box.appendChild(s);
        if (opts.scale) { s.style.transform = 'scale(' + opts.scale + ')'; return s; }
        box.__slide = s;
        if (box.clientWidth) s.style.transform = 'scale(' + (box.clientWidth / 1280) + ')';
        if (RO) RO.observe(box);
        return s;
    }

    window.PresentoRender = {
        renderSlide: renderSlide, elNode: elNode, FONTS: FONTS, num: num, safeColor: safeColor, safeUrl: safeUrl, ytThumb: ytThumb,
    };
})();
