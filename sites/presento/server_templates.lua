-- Presento starter templates, shown under "Start a new presentation". Edit, remove or add your own.
-- Every slide goes through the same cleaning as a slide saved from the editor, so only known fields survive.
-- Canvas is 1280 x 720. `theme` should be one of the page's theme keys (default, dark, police, medical,
-- corporate, bold, retro, paper) so new slides added later match. `nameKey` is a locale key (locales/presento_en.lua).

local function tx(o)
    o.type = 'text'; o.rot = 0
    o.font = o.font or 'sans'; o.size = o.size or 26
    o.align = o.align or 'left'; o.valign = o.valign or 'top'
    o.text = o.text or ''
    return o
end
local function box(o) o.type = 'shape'; o.rot = 0; o.shape = o.shape or 'rect'; o.stroke = o.stroke or 0; return o end
local function grid(o)
    o.type = 'table'; o.rot = 0; o.size = o.size or 22
    return o
end
local function rows(head, n)
    local out = { head }
    for r = 2, n do
        local row = {}
        for c = 1, #head do row[c] = '' end
        out[r] = row
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Police shift briefing
-- ---------------------------------------------------------------------------------------------
local PB = { bg = '#0b1f44', t = '#ffffff', b = '#cfd8e8', a = '#3d8bfd', card = '#13306a' }
local police = {
    key = 'police', nameKey = 'presento.tpl.police', theme = 'police',
    slides = {
        { bg = PB.bg, els = {
            box({ x = 0, y = 0, w = 26, h = 720, fill = PB.a }),
            tx({ x = 100, y = 230, w = 1080, h = 120, text = 'Shift Briefing', ph = 'title', size = 68, bold = true, color = PB.t, valign = 'middle' }),
            tx({ x = 100, y = 360, w = 1080, h = 60, text = 'Los Santos Police Department · Day shift', ph = 'subtitle', size = 28, color = PB.b }),
            tx({ x = 100, y = 610, w = 800, h = 50, text = 'Briefing officer:', size = 22, color = PB.b }),
        } },
        { bg = PB.bg, trans = 'fade', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Overview', ph = 'title', size = 46, bold = true, color = PB.t, valign = 'middle' }),
            box({ x = 80, y = 150, w = 120, h = 6, fill = PB.a }),
            tx({ x = 80, y = 190, w = 1120, h = 460, ph = 'body', size = 30, color = PB.b,
                text = '• Current threat level:\n• Incidents since last shift:\n• Areas of focus:\n• Weather and traffic:\n• Anything else to know:' }),
        } },
        { bg = PB.bg, trans = 'fade', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Be on the lookout', ph = 'title', size = 46, bold = true, color = PB.t, valign = 'middle' }),
            box({ x = 80, y = 170, w = 540, h = 470, shape = 'round', fill = PB.card }),
            tx({ x = 110, y = 195, w = 480, h = 420, size = 26, color = PB.b, anim = 'fade', step = 1,
                text = 'Suspect\n\nName:\nDescription:\nLast seen:\nWanted for:' }),
            box({ x = 660, y = 170, w = 540, h = 470, shape = 'round', fill = PB.card }),
            tx({ x = 690, y = 195, w = 480, h = 420, size = 26, color = PB.b, anim = 'fade', step = 2,
                text = 'Vehicle\n\nMake and model:\nColour:\nPlate:\nLast seen:' }),
        } },
        { bg = PB.bg, trans = 'fade', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Assignments', ph = 'title', size = 46, bold = true, color = PB.t, valign = 'middle' }),
            grid({ x = 80, y = 180, w = 1120, h = 440, color = '#ffffff', headFill = PB.a, strokeColor = '#3b5a8f',
                cells = rows({ 'Unit', 'Callsign', 'Area', 'Notes' }, 6) }),
        } },
        { bg = PB.bg, trans = 'zoom', els = {
            tx({ x = 100, y = 260, w = 1080, h = 130, text = 'Questions?', ph = 'title', size = 72, bold = true, color = PB.t, align = 'center', valign = 'middle' }),
            tx({ x = 100, y = 400, w = 1080, h = 60, text = 'Stay safe out there.', size = 30, color = PB.b, align = 'center' }),
        } },
    },
}

-- ---------------------------------------------------------------------------------------------
-- Business pitch
-- ---------------------------------------------------------------------------------------------
local CO = { bg = '#f5f6f8', t = '#1d2a3a', b = '#46505e', a = '#e8742a' }
local pitch = {
    key = 'pitch', nameKey = 'presento.tpl.pitch', theme = 'corporate',
    slides = {
        { bg = CO.bg, els = {
            tx({ x = 110, y = 220, w = 1060, h = 130, text = 'Your company name', ph = 'title', font = 'serif', size = 64, bold = true, color = CO.t, valign = 'bottom' }),
            box({ x = 110, y = 368, w = 160, h = 8, fill = CO.a }),
            tx({ x = 110, y = 395, w = 1060, h = 60, text = 'Business proposal', ph = 'subtitle', size = 30, color = CO.b }),
        } },
        { bg = CO.bg, trans = 'slide', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'The problem', ph = 'title', font = 'serif', size = 46, bold = true, color = CO.t, valign = 'middle' }),
            tx({ x = 80, y = 180, w = 1120, h = 460, ph = 'body', size = 30, color = CO.b,
                text = '• What is going wrong for your customers today?\n• Who does it affect?\n• What does it cost them?' }),
        } },
        { bg = CO.bg, trans = 'slide', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Our solution', ph = 'title', font = 'serif', size = 46, bold = true, color = CO.t, valign = 'middle' }),
            box({ x = 80, y = 180, w = 12, h = 420, fill = CO.a }),
            tx({ x = 120, y = 180, w = 1080, h = 460, ph = 'body', size = 30, color = CO.b, anim = 'left', step = 1,
                text = 'What you offer and why it is better.\n\n• Benefit one\n• Benefit two\n• Benefit three' }),
        } },
        { bg = CO.bg, trans = 'slide', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Prices', ph = 'title', font = 'serif', size = 46, bold = true, color = CO.t, valign = 'middle' }),
            grid({ x = 80, y = 180, w = 1120, h = 300, color = CO.t, headFill = '#f6d2b8', strokeColor = '#c9ced6',
                cells = { { 'Package', 'What you get', 'Price' }, { 'Basic', '', '' }, { 'Standard', '', '' }, { 'Premium', '', '' } } }),
        } },
        { bg = CO.bg, trans = 'fade', els = {
            tx({ x = 110, y = 200, w = 1060, h = 110, text = 'Get in touch', ph = 'title', font = 'serif', size = 60, bold = true, color = CO.t, valign = 'middle' }),
            tx({ x = 110, y = 330, w = 1060, h = 200, size = 30, color = CO.b, text = 'Phone:\nEmail:\nFind us:' }),
        } },
    },
}

-- ---------------------------------------------------------------------------------------------
-- EMS training
-- ---------------------------------------------------------------------------------------------
local MD = { bg = '#f4fbfb', t = '#0f5257', b = '#35565a', a = '#d93a3a' }
local ems = {
    key = 'ems', nameKey = 'presento.tpl.ems', theme = 'medical',
    slides = {
        { bg = MD.bg, els = {
            box({ x = 1030, y = 90, w = 50, h = 150, fill = MD.a }),
            box({ x = 980, y = 140, w = 150, h = 50, fill = MD.a }),
            tx({ x = 100, y = 250, w = 1080, h = 120, text = 'EMS Training', ph = 'title', size = 66, bold = true, color = MD.t, valign = 'middle' }),
            tx({ x = 100, y = 380, w = 1080, h = 60, text = 'Pillbox Medical Centre', ph = 'subtitle', size = 30, color = MD.b }),
        } },
        { bg = MD.bg, trans = 'fade', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Learning objectives', ph = 'title', size = 46, bold = true, color = MD.t, valign = 'middle' }),
            tx({ x = 80, y = 180, w = 1120, h = 460, ph = 'body', size = 30, color = MD.b,
                text = 'By the end of this session you will be able to:\n\n• \n• \n• ' }),
        } },
        { bg = MD.bg, trans = 'fade', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Procedure', ph = 'title', size = 46, bold = true, color = MD.t, valign = 'middle' }),
            tx({ x = 80, y = 180, w = 1120, h = 110, size = 30, color = MD.b, anim = 'up', step = 1, text = '1.  Check the scene is safe' }),
            tx({ x = 80, y = 290, w = 1120, h = 110, size = 30, color = MD.b, anim = 'up', step = 2, text = '2.  Check for a response' }),
            tx({ x = 80, y = 400, w = 1120, h = 110, size = 30, color = MD.b, anim = 'up', step = 3, text = '3.  Airway, breathing, circulation' }),
            tx({ x = 80, y = 510, w = 1120, h = 110, size = 30, color = MD.b, anim = 'up', step = 4, text = '4.  Treat and transport' }),
        } },
        { bg = MD.bg, trans = 'fade', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Kit checklist', ph = 'title', size = 46, bold = true, color = MD.t, valign = 'middle' }),
            grid({ x = 80, y = 180, w = 1120, h = 420, color = MD.t, headFill = '#cdeaea', strokeColor = '#9cc5c5',
                cells = rows({ 'Item', 'Quantity', 'Checked' }, 7) }),
        } },
        { bg = MD.bg, trans = 'zoom', els = {
            tx({ x = 100, y = 270, w = 1080, h = 130, text = 'Questions and practice', ph = 'title', size = 60, bold = true, color = MD.t, align = 'center', valign = 'middle' }),
        } },
    },
}

-- ---------------------------------------------------------------------------------------------
-- Event announcement
-- ---------------------------------------------------------------------------------------------
local RT = { bg = '#2b1055', t = '#ff5fd2', b = '#7ef9ff', a = '#ffe45e' }
local event = {
    key = 'event', nameKey = 'presento.tpl.event', theme = 'retro',
    slides = {
        { bg = RT.bg, els = {
            box({ x = 1000, y = -80, w = 360, h = 360, shape = 'ellipse', fill = '#4a1a8a' }),
            box({ x = -100, y = 520, w = 300, h = 300, shape = 'ellipse', fill = '#3b1675' }),
            tx({ x = 100, y = 220, w = 1080, h = 150, text = 'EVENT NAME', ph = 'title', font = 'display', size = 96, color = RT.t, align = 'center', valign = 'middle' }),
            tx({ x = 100, y = 390, w = 1080, h = 60, text = 'Date · Time · Place', ph = 'subtitle', font = 'round', size = 32, color = RT.b, align = 'center' }),
        } },
        { bg = RT.bg, trans = 'zoom', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = "What's on", ph = 'title', font = 'display', size = 54, color = RT.t, valign = 'middle' }),
            tx({ x = 80, y = 180, w = 1120, h = 460, ph = 'body', font = 'round', size = 32, color = RT.b,
                text = '• Live music\n• Food and drink\n• Prizes\n• ' }),
        } },
        { bg = RT.bg, trans = 'zoom', els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Line-up', ph = 'title', font = 'display', size = 54, color = RT.t, valign = 'middle' }),
            grid({ x = 80, y = 180, w = 1120, h = 400, color = '#ffffff', headFill = '#6b2fb3', strokeColor = '#6b2fb3',
                cells = rows({ 'Time', 'Act' }, 6) }),
        } },
        { bg = RT.bg, trans = 'zoom', els = {
            tx({ x = 100, y = 230, w = 1080, h = 120, text = 'Tickets', ph = 'title', font = 'display', size = 80, color = RT.a, align = 'center', valign = 'middle' }),
            tx({ x = 100, y = 370, w = 1080, h = 60, text = 'Get yours at lstickets.co.uk', font = 'round', size = 34, color = RT.b, align = 'center' }),
        } },
    },
}

-- ---------------------------------------------------------------------------------------------
-- Team meeting
-- ---------------------------------------------------------------------------------------------
local DF = { bg = '#ffffff', t = '#1f2937', b = '#4b5563', a = '#ff7a1a' }
local meeting = {
    key = 'meeting', nameKey = 'presento.tpl.meeting', theme = 'default',
    slides = {
        { bg = DF.bg, els = {
            tx({ x = 120, y = 250, w = 1040, h = 130, text = 'Team meeting', ph = 'title', size = 60, bold = true, color = DF.t, align = 'center', valign = 'middle' }),
            tx({ x = 120, y = 390, w = 1040, h = 60, text = 'Date', ph = 'subtitle', size = 28, color = '#6b7280', align = 'center' }),
        } },
        { bg = DF.bg, els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Agenda', ph = 'title', size = 44, bold = true, color = DF.t, valign = 'middle' }),
            tx({ x = 80, y = 180, w = 1120, h = 460, ph = 'body', size = 30, color = DF.b, text = '1.  Updates\n2.  Problems and ideas\n3.  Actions\n4.  Any other business' }),
        } },
        { bg = DF.bg, els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Updates', ph = 'title', size = 44, bold = true, color = DF.t, valign = 'middle' }),
            tx({ x = 80, y = 180, w = 1120, h = 460, ph = 'body', size = 30, color = DF.b, text = '• \n• \n• ' }),
        } },
        { bg = DF.bg, els = {
            tx({ x = 80, y = 50, w = 1120, h = 100, text = 'Actions', ph = 'title', size = 44, bold = true, color = DF.t, valign = 'middle' }),
            grid({ x = 80, y = 180, w = 1120, h = 400, color = DF.t, headFill = '#ffe3cf', strokeColor = '#d6d9de',
                cells = rows({ 'Action', 'Owner', 'Due' }, 6) }),
        } },
    },
}

PresentoTemplates = { police, pitch, ems, event, meeting }
