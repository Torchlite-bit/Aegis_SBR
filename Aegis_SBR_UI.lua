-- ============================================================
-- Aegis_SBR_UI  -  shared configuration window framework
-- Turtle WoW 1.12 frame API. Builds the window shell and profile
-- management, then delegates the class specific body to the active
-- module via M:BuildBody(ui, frame) and M:RefreshBody(ui, buf).
-- ============================================================

Aegis_SBR_UI = { built = false, loading = false, editing = nil, buf = nil, openDD = nil }

local CORE = Aegis_SBR
local function MOD() return Aegis_SBR.active end


local COL = {
    gold  = {1.0, 0.82, 0.0}, white = {1.0, 1.0, 1.0},
    green = {0.3, 1.0, 0.3},  red = {1.0, 0.35, 0.35}, grey = {0.55, 0.55, 0.55},
}

-- ------------------------------------------------------------
-- Skin: flat dark palette + bundled fonts (Phase 1 of the redesign).
-- PAL drives every surface; the class colour is the accent. Fonts ship in
-- the addon's Fonts\ folder (PT Sans Narrow, OFL) and fall back to the
-- client's default face if the folder is missing, so text can never vanish.
-- ------------------------------------------------------------
local PAL = {
    bg    = {0.055, 0.059, 0.071, 0.97},  -- window base
    panel = {0.088, 0.096, 0.116, 1.0},   -- section cards / popups
    line  = {0.15,  0.165, 0.196, 1.0},   -- 1px hairlines
    ink   = {0.91,  0.90,  0.88},         -- primary text
    mute  = {0.55,  0.56,  0.60},         -- secondary text
}
local FONT_REG  = "Interface\\AddOns\\Aegis_SBR\\Fonts\\PTSansNarrow.ttf"
local FONT_BOLD = "Interface\\AddOns\\Aegis_SBR\\Fonts\\PTSansNarrow-Bold.ttf"
local FONT_FALLBACK = "Fonts\\FRIZQT__.TTF"

-- Apply a bundled font; if the file is missing/unloadable the set silently
-- fails (GetFont keeps the old path), so we re-set the stock font at the
-- wanted size instead.
local function SetFontSafe(fs, bold, size)
    if not fs or not fs.SetFont then return end
    local path = bold and FONT_BOLD or FONT_REG
    fs:SetFont(path, size)
    if fs:GetFont() ~= path then fs:SetFont(FONT_FALLBACK, size) end
    -- flat skin: no drop shadow (the template default smears small bold text)
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
end

-- Font role per Blizzard template name, so every FontString the framework
-- creates picks up the skin face at a matched size.
local FONT_ROLE = {
    GameFontNormalLarge    = { true,  16 },
    GameFontNormal         = { true,  12 },
    GameFontHighlight      = { false, 12 },
    GameFontNormalSmall    = { false, 11 },
    GameFontHighlightSmall = { false, 11 },
    GameFontDisableSmall   = { false, 10 },
}

-- Flat window surface: a tiling near-solid file tinted by SetBackdropColor.
-- Borders are drawn as explicit 1px hairlines (see SkinBorder), not edge art.
local FLAT_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true, tileSize = 16,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
local LIST_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- 1px hairline frame border in the palette line colour.
local function SkinBorder(frame)
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetTexture(PAL.line[1], PAL.line[2], PAL.line[3], PAL.line[4])
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:SetPoint(p1, frame, p1, 0, 0); t:SetPoint(p2, frame, p2, 0, 0)
        return t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

-- Canonical class colours keyed by the class token from UnitClass; the window
-- always shows the player's own class, so the player's token gives the right
-- accent. Falls back to gold. (Defined before SkinButton, which captures it.)
local CLASS_COLORS = {
    WARRIOR = {0.78, 0.61, 0.43}, PALADIN = {0.96, 0.55, 0.73},
    HUNTER  = {0.67, 0.83, 0.45}, ROGUE   = {1.00, 0.96, 0.41},
    PRIEST  = {1.00, 1.00, 1.00}, SHAMAN  = {0.00, 0.44, 0.87},
    MAGE    = {0.41, 0.80, 0.94}, WARLOCK = {0.58, 0.51, 0.79},
    DRUID   = {1.00, 0.49, 0.04},
}
local function classColor()
    local _, token = UnitClass("player")
    return CLASS_COLORS[token or ""] or COL.gold
end

-- Restyle a UIPanelButtonTemplate button as a flat skin button, replacing the
-- red-gold art in code (no texture files needed).
--   "accent" - filled with the class colour; text auto-picks dark or light
--              by the accent's luminance. For the one primary action.
--   "ghost"  - hairline border, faint fill, ink text. Secondary actions.
--   "dd"     - ghost visuals for dropdowns: regular-weight text, and text
--              colour left alone (SetDropdown owns it for state colouring).
-- Also swaps the template's Enable/Disable for skin-aware versions.
local function SkinButton(b, style)
    if not b or b.arSkinned then return end
    b.arSkinned = true
    local t
    local regs = { b:GetRegions() }
    for i = 1, table.getn(regs) do
        local r = regs[i]
        if r.GetObjectType and r:GetObjectType() == "FontString" then t = r; break end
    end
    b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetHighlightTexture("")
    if b.SetDisabledTexture then b:SetDisabledTexture("") end
    local BTN = "Interface\\AddOns\\Aegis_SBR\\Icons\\Btn"
    local bg, outer
    local txtCol
    if style == "accent" then
        local a = classColor()
        bg = b:CreateTexture(nil, "BORDER")
        bg:SetTexture(BTN); bg:SetVertexColor(a[1], a[2], a[3]); bg:SetAlpha(0.95)
        bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        local lum = 0.3 * a[1] + 0.59 * a[2] + 0.11 * a[3]
        txtCol = (lum > 0.5) and { 0.06, 0.07, 0.09 } or { 0.95, 0.95, 0.97 }
    else
        -- rounded ghost: line-colour pill under a 1px-inset window-colour pill
        outer = b:CreateTexture(nil, "BACKGROUND")
        outer:SetTexture(BTN); outer:SetVertexColor(PAL.line[1], PAL.line[2], PAL.line[3])
        outer:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); outer:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        bg = b:CreateTexture(nil, "BORDER")
        bg:SetTexture(BTN); bg:SetVertexColor(PAL.bg[1], PAL.bg[2], PAL.bg[3])
        bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        txtCol = PAL.ink
    end
    local hov = b:CreateTexture(nil, "ARTWORK")
    hov:SetTexture(BTN); hov:SetVertexColor(1, 1, 1); hov:SetAlpha(0.07)
    hov:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); hov:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    hov:Hide()
    if t then
        SetFontSafe(t, style ~= "dd", 11)
        if style ~= "dd" then t:SetTextColor(txtCol[1], txtCol[2], txtCol[3]) end
    end
    b:SetScript("OnEnter", function() hov:Show() end)
    b:SetScript("OnLeave", function() hov:Hide() end)
    b:SetScript("OnMouseDown", function()
        if t then t:ClearAllPoints(); t:SetPoint("CENTER", b, "CENTER", 1, -1) end
    end)
    b:SetScript("OnMouseUp", function()
        if t then t:ClearAllPoints(); t:SetPoint("CENTER", b, "CENTER", 0, 0) end
    end)
    local baseA = (style == "accent") and 0.95 or 1
    local oe, od = b.Enable, b.Disable
    b.Enable = function(s)
        oe(s); bg:SetAlpha(baseA)
        if outer then outer:SetAlpha(1) end
        if t and style ~= "dd" then t:SetTextColor(txtCol[1], txtCol[2], txtCol[3]) end
    end
    b.Disable = function(s)
        od(s); bg:SetAlpha(0.35)
        if outer then outer:SetAlpha(0.35) end
        if t and style ~= "dd" then t:SetTextColor(0.35, 0.36, 0.40) end
    end
end

local function FS(parent, font, text)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    local role = FONT_ROLE[font or "GameFontNormal"]
    if role then SetFontSafe(f, role[1], role[2]) end
    if text then f:SetText(text) end
    return f
end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- Restyle a UIPanelCloseButton-ish button as a flat ghost square with an ink
-- glyph (default "×"); the close glyph hovers faintly red, others neutral.
local function SkinClose(b, glyph)
    if not b or b.arSkinned then return end
    b.arSkinned = true
    b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetHighlightTexture("")
    if b.SetDisabledTexture then b:SetDisabledTexture("") end
    b:SetWidth(20); b:SetHeight(20)
    local SQ = "Interface\\AddOns\\Aegis_SBR\\Icons\\RoundSq"
    local outer = b:CreateTexture(nil, "BACKGROUND")
    outer:SetTexture(SQ); outer:SetVertexColor(PAL.line[1], PAL.line[2], PAL.line[3])
    outer:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); outer:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bg = b:CreateTexture(nil, "BORDER")
    bg:SetTexture(SQ); bg:SetVertexColor(PAL.bg[1], PAL.bg[2], PAL.bg[3])
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local hov = b:CreateTexture(nil, "ARTWORK")
    hov:SetTexture(SQ)
    if glyph and glyph ~= "×" then hov:SetVertexColor(1, 1, 1); hov:SetAlpha(0.08)
    else hov:SetVertexColor(1, 0.3, 0.3); hov:SetAlpha(0.12) end
    hov:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); hov:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    hov:Hide()
    local x = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFontSafe(x, true, 13)
    x:SetText(glyph or "×"); x:SetPoint("CENTER", b, "CENTER", 0, 0)
    x:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
    b:SetScript("OnEnter", function() hov:Show() end)
    b:SetScript("OnLeave", function() hov:Hide() end)
end

-- Pill skin for the profile dropdown: layered rounded art (line-colour outer,
-- window-colour inner = a 1px rounded border), a soft hover, and left-aligned
-- bold text with room for the live dot.
local function PillSkin(b)
    if not b or b.arSkinned then return end
    b.arSkinned = true
    b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetHighlightTexture("")
    if b.SetDisabledTexture then b:SetDisabledTexture("") end
    local PILL = "Interface\\AddOns\\Aegis_SBR\\Icons\\Pill"
    local outer = b:CreateTexture(nil, "BACKGROUND")
    outer:SetTexture(PILL); outer:SetVertexColor(PAL.line[1], PAL.line[2], PAL.line[3])
    outer:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); outer:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local inner = b:CreateTexture(nil, "BORDER")
    inner:SetTexture(PILL); inner:SetVertexColor(PAL.bg[1], PAL.bg[2], PAL.bg[3])
    inner:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local hov = b:CreateTexture(nil, "ARTWORK")
    hov:SetTexture(PILL); hov:SetVertexColor(1, 1, 1); hov:SetAlpha(0.06)
    hov:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); hov:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    hov:Hide()
    local t = getglobal(b:GetName() .. "Text")
    if t then
        SetFontSafe(t, true, 11)
        t:ClearAllPoints(); t:SetPoint("LEFT", b, "LEFT", 24, 0)
        t:SetJustifyH("LEFT")
    end
    -- content-width: resize the pill to hug its text (dot + text + padding),
    -- clamped so it never gets absurdly wide. Called from Refresh after the
    -- dropdown text is set. Concept pills hug their label rather than filling.
    b.arFitText = function()
        if not t then return end
        local tw = t:GetStringWidth() or 0
        local wpx = 24 + tw + 14
        if wpx < 96 then wpx = 96 elseif wpx > 220 then wpx = 220 end
        b:SetWidth(wpx)
    end
    b:SetScript("OnEnter", function() hov:Show() end)
    b:SetScript("OnLeave", function() hov:Hide() end)
end

-- 9-slice a pre-baked rounded texture (64x64 art) onto a frame: corners are
-- drawn at fixed size and edges stretch, so every card gets identical crisp
-- corners regardless of its dimensions. reg() registers each texture (e.g.
-- into a section for dimming).
local function NineSlice(fr, file, corner, reg)
    local c = corner / 64
    local function tex(u1, u2, v1, v2)
        local t = fr:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(file); t:SetTexCoord(u1, u2, v1, v2)
        if reg then reg(t) end
        return t
    end
    local tl = tex(0, c, 0, c);         tl:SetWidth(corner); tl:SetHeight(corner); tl:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
    local tr = tex(1 - c, 1, 0, c);     tr:SetWidth(corner); tr:SetHeight(corner); tr:SetPoint("TOPRIGHT", fr, "TOPRIGHT", 0, 0)
    local bl = tex(0, c, 1 - c, 1);     bl:SetWidth(corner); bl:SetHeight(corner); bl:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", 0, 0)
    local br = tex(1 - c, 1, 1 - c, 1); br:SetWidth(corner); br:SetHeight(corner); br:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 0, 0)
    local top = tex(c, 1 - c, 0, c);    top:SetHeight(corner)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0); top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
    local bot = tex(c, 1 - c, 1 - c, 1); bot:SetHeight(corner)
    bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    local lft = tex(0, c, c, 1 - c);    lft:SetWidth(corner)
    lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0); lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
    local rgt = tex(1 - c, 1, c, 1 - c); rgt:SetWidth(corner)
    rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    local mid = tex(c, 1 - c, c, 1 - c)
    mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
end

local function trim(s) local r = string.gsub(s or "", "^%s*(.-)%s*$", "%1"); return r end

-- Attach a hover tooltip to any mouse-enabled frame. body lines are optional.
-- Chains any existing OnEnter/OnLeave (e.g. the row-hover highlight) instead of
-- overwriting it, so a control can both highlight its row and show a tooltip.
local function Tip(frame, title, line1, line2)
    if not frame then return end
    local prevEnter = frame:GetScript("OnEnter")
    local prevLeave = frame:GetScript("OnLeave")
    frame:SetScript("OnEnter", function()
        if prevEnter then prevEnter() end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if line1 then GameTooltip:AddLine(line1, 1, 1, 1) end
        if line2 then GameTooltip:AddLine(line2, 1, 1, 1) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if prevLeave then prevLeave() end
        GameTooltip:Hide()
    end)
end

-- Flat 1px separator at a given y offset from the frame top (palette line
-- colour). Section headers no longer use this - cards separate them - but it
-- stays available for class bodies via Aegis_SBR_UI:Divider.
local function divider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(PAL.line[1], PAL.line[2], PAL.line[3], 0.9)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y)
end

-- Wrappers so class body files (separate files) can use the framework helpers.
Aegis_SBR_UI.COL = COL
function Aegis_SBR_UI:FS(parent, font, text) return FS(parent, font, text) end
function Aegis_SBR_UI:Color(fs, c) color(fs, c) end
function Aegis_SBR_UI:Tip(frame, title, l1, l2) Tip(frame, title, l1, l2) end
function Aegis_SBR_UI:Divider(parent, y) divider(parent, y) end


-- ------------------------------------------------------------
-- custom dropdown
-- ------------------------------------------------------------
function Aegis_SBR_UI:CreateDropdown(uniqueName, parent, width, onSelect, style)
    local b = CreateFrame("Button", "AegisUI_DD_" .. uniqueName, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(22)
    b.onSelect = onSelect; b.options = {}; b.rows = {}
    if style == "pill" then PillSkin(b) else SkinButton(b, "dd") end
    -- Parent the popup to the window (not the button) so a body scroll frame
    -- cannot clip it; it is still anchored under the button below.
    local list = CreateFrame("Frame", "AegisUI_DD_" .. uniqueName .. "_List", self.frame or parent)
    list:SetBackdrop(LIST_BACKDROP)
    list:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 0.98)
    list:SetBackdropBorderColor(PAL.line[1], PAL.line[2], PAL.line[3], 1)
    list:SetFrameStrata("FULLSCREEN_DIALOG"); list:SetWidth(width)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 2); list:Hide()
    b.list = list
    b:SetScript("OnClick", function()
        if list:IsShown() then Aegis_SBR_UI:CloseDropdown(b) else Aegis_SBR_UI:OpenDropdown(b) end
    end)
    return b
end

function Aegis_SBR_UI:CloseDropdown(b)
    b.list:Hide()
    if self.openDD == b then self.openDD = nil end
end

function Aegis_SBR_UI:OpenDropdown(b)
    if self.openDD and self.openDD ~= b then self:CloseDropdown(self.openDD) end
    self.openDD = b
    local n = table.getn(b.options)
    local rowH = 18
    for i = 1, n do
        local row = b.rows[i]
        if not row then
            row = CreateFrame("Button", nil, b.list)
            row:SetHeight(rowH)
            row:SetPoint("TOPLEFT", b.list, "TOPLEFT", 6, -4 - (i - 1) * rowH)
            row:SetPoint("RIGHT", b.list, "RIGHT", -6, 0)
            local txt = FS(row, "GameFontHighlightSmall"); txt:SetPoint("LEFT", row, "LEFT", 2, 0); txt:SetJustifyH("LEFT")
            row.txt = txt
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); hl:SetBlendMode("ADD"); hl:SetAllPoints(row)
            b.rows[i] = row
        end
        local opt = b.options[i]
        row.txt:SetText(opt.label); row.value = opt.value
        row:SetScript("OnClick", function()
            b.value = row.value
            Aegis_SBR_UI:CloseDropdown(b)
            if b.onSelect then b.onSelect(row.value) end
        end)
        row:Show()
    end
    for i = n + 1, table.getn(b.rows) do b.rows[i]:Hide() end
    b.list:SetHeight(8 + n * rowH); b.list:Raise(); b.list:Show()
end

function Aegis_SBR_UI:SetDropdown(b, options, value, text, c)
    b.options = options; b.value = value; b:SetText(text)
    local fs = b:GetFontString()
    if fs and c then color(fs, c) end
end

-- ------------------------------------------------------------
-- checkbox
-- ------------------------------------------------------------
function Aegis_SBR_UI:CreateCheck(uniqueName, parent, labelText, spellName, onClick)
    local cb = CreateFrame("CheckButton", "AegisUI_CB_" .. uniqueName, parent, "UICheckButtonTemplate")
    cb:SetWidth(30); cb:SetHeight(16)
    -- skin: toggle-switch art from Icons\. The 1.12 client's CheckButton
    -- ignores file paths on SetCheckedTexture and the disabled variants (only
    -- SetNormalTexture takes a path), so for those slots we grab the
    -- template's texture OBJECTS and repoint their files instead. The ON pill
    -- ships white and is tinted to the class colour; OFF ships in final greys.
    cb:SetNormalTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\ToggleOff")
    cb:SetPushedTexture("")
    local a = classColor()
    local function repoint(tex, file, r, g, b)
        if not tex then return end
        tex:SetTexture(file)
        if r then tex:SetVertexColor(r, g, b) else tex:SetVertexColor(1, 1, 1) end
    end
    repoint(cb.GetCheckedTexture and cb:GetCheckedTexture(),
        "Interface\\AddOns\\Aegis_SBR\\Icons\\ToggleOn", a[1], a[2], a[3])
    repoint(cb.GetDisabledTexture and cb:GetDisabledTexture(),
        "Interface\\AddOns\\Aegis_SBR\\Icons\\ToggleOff")
    repoint(cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture(),
        "Interface\\AddOns\\Aegis_SBR\\Icons\\ToggleOn", a[1] * 0.6, a[2] * 0.6, a[3] * 0.6)
    local ht = cb.GetHighlightTexture and cb:GetHighlightTexture()
    if ht then
        ht:SetTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\ToggleOn")
        ht:SetBlendMode("ADD"); ht:SetAlpha(0.08)
    end
    local lab = FS(parent, "GameFontNormalSmall", labelText)
    lab:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", function()
        if Aegis_SBR_UI.loading then return end
        if onClick then onClick(cb:GetChecked() and true or false) end
    end)
    return { cb = cb, label = lab, baseText = labelText, spellName = spellName }
end

-- Bind a CreateCheck item to a value during RefreshBody. If a spell name is
-- attached (per-call override, else the one given at creation), the label is
-- greyed with "(not learned)" when unknown, or red when enabled-but-unknown.
-- Every class body used to hand-roll this; now they all share it.
function Aegis_SBR_UI:BindCheck(item, on, spellName)
    item.cb:SetChecked(on and true or false)
    item.cb:Enable()
    local name = spellName
    if name == nil then name = item.spellName end
    -- A slider row swaps between its slim label (slider shown) and full-width
    -- label (slider hidden); rows without a slider just keep their label.
    local function sliderShown(show)
        if not item.slider then return end
        if show then
            item.slider:Show(); if item.value then item.value:Show() end
            if item.labelSlimW then item.label:SetWidth(item.labelSlimW) end
        else
            item.slider:Hide(); if item.value then item.value:Hide() end
            if item.labelFullW then item.label:SetWidth(item.labelFullW) end
        end
    end
    if not name then
        item.label:SetText(item.baseText); color(item.label, COL.white)
        sliderShown(true)
        return
    end
    local known = Aegis_SBR.active and Aegis_SBR.active:KnowsSpell(name)
    if known then
        item.label:SetText(item.baseText); color(item.label, COL.white)
        sliderShown(true)
    elseif on then
        item.label:SetText(item.baseText .. " (not learned)"); color(item.label, COL.red)
        sliderShown(false)
    else
        item.label:SetText(item.baseText .. " (not learned)"); color(item.label, COL.grey)
        sliderShown(false)
    end
end

-- Enable or grey out a slider in one call (mouse + alpha), so callers do not
-- repeat the EnableMouse/SetAlpha pair. Used by the class config bodies to
-- follow a checkbox's on/off and learned state.
function Aegis_SBR_UI:SliderEnable(slider, on)
    if on then
        slider:EnableMouse(true);  slider:SetAlpha(1)
    else
        slider:EnableMouse(false); slider:SetAlpha(0.35)
    end
end

-- ------------------------------------------------------------
-- slider (Blizzard template). opts = {min,max,step,suffix}.
-- For compatibility the 4th argument may be the onChange function,
-- in which case default percent options are used.
-- ------------------------------------------------------------
function Aegis_SBR_UI:CreateSlider(uniqueName, parent, labelText, opts, onChange)
    if type(opts) == "function" then onChange = opts; opts = nil end
    opts = opts or {}
    local mn = opts.min or 0
    local mx = opts.max or 100
    local stp = opts.step or 5
    local suffix = opts.suffix
    if suffix == nil then suffix = "%" end
    local nm = "AegisUI_SL_" .. uniqueName
    local s = CreateFrame("Slider", nm, parent, "OptionsSliderTemplate")
    s:SetWidth(150); s:SetHeight(16)
    s:SetMinMaxValues(mn, mx); s:SetValueStep(stp)
    -- skin: drop the template's grooved track, draw a slim dark rail with a
    -- class-accent fill up to the thumb, and use the flat round thumb art.
    s:SetBackdrop(nil)
    local rail = s:CreateTexture(nil, "BACKGROUND")
    rail:SetTexture(0, 0, 0, 0.5); rail:SetHeight(3)
    rail:SetPoint("LEFT", s, "LEFT", 2, 0); rail:SetPoint("RIGHT", s, "RIGHT", -2, 0)
    local acc = classColor()
    local fill = s:CreateTexture(nil, "BORDER")
    fill:SetTexture(acc[1], acc[2], acc[3], 0.9); fill:SetHeight(3)
    fill:SetPoint("LEFT", s, "LEFT", 2, 0); fill:SetWidth(1)
    s:SetThumbTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\SliderThumb")
    local th = s:GetThumbTexture()
    if th then th:SetWidth(14); th:SetHeight(14); th:SetVertexColor(PAL.ink[1], PAL.ink[2], PAL.ink[3]) end
    local t = getglobal(nm .. "Text");  if t then t:SetText(labelText); SetFontSafe(t, false, 10); t:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3]) end
    local lo = getglobal(nm .. "Low");  if lo then lo:SetText("") end
    local hi = getglobal(nm .. "High"); if hi then hi:SetText(""); SetFontSafe(hi, true, 10) end
    s.labelFS = t
    s.valText = hi
    s.suffix = suffix
    s:SetScript("OnValueChanged", function()
        local v = s:GetValue()
        if s.valText then s.valText:SetText(tostring(v) .. s.suffix) end
        local w = s:GetWidth() - 4
        if w > 1 and mx > mn then
            local fw = (v - mn) / (mx - mn) * w
            if fw < 1 then fw = 1 end
            fill:SetWidth(fw)
        end
        if not Aegis_SBR_UI.loading and onChange then onChange(v) end
    end)
    return s
end

-- ------------------------------------------------------------
-- Auto-flow layout + scroll. A class can opt in with M.useScrollLayout = true;
-- the shell then hosts its body in a scroll frame and hands BuildBody the scroll
-- CHILD. The layout below is a vertical cursor that creates + places controls and
-- tracks the running height, so bodies stop hand-coding y offsets. Finish() sizes
-- the child for the scrollbar.
-- ------------------------------------------------------------
local LAY = {
    TOP_PAD = 8, BOT_PAD = 12,
    L_PAD = 6, COL2_X = 170, LABEL_W = 40, DD_LABEL_W = 82,
    ROW_H = 26, HEADER_H = 30, DD_H = 30, SLIDER_H = 40, SLIDER_TOP = 16,
    SECTION_GAP = 8,   -- breathing room between section cards
    VROW_H = 28,       -- concept-style single rows (toggle + slider + value)
}
local SCROLL = {
    WIN_H = 485,       -- compact fixed window height for scroll-layout classes
    TOP = -81,         -- body region starts here, below the profile pill row
    TOP_TABS = -109,   -- body start when the class has a spec tab rail
    TOP_TABS_SUB = -138, -- body start when the rail also carries per-tab subtitle lines
    BOTTOM_PAD = 44,   -- leaves room for the footer buttons
    LEFT = 16, WIDTH = 322, BAR_W = 16,
}

local Aegis_SBR_Layout = {}
Aegis_SBR_Layout.__index = Aegis_SBR_Layout

-- A section groups the controls placed under one Header so a class body can dim
-- the whole block (fade + lock) when its mode is not the active one. This is the
-- dimming half of the earlier work, with none of the collapsible/fold behaviour.
local Section = {}
Section.__index = Section
function Section:_add(region, interactive)
    table.insert(self.regions, region)
    if interactive then table.insert(self.controls, region) end
end
function Section:SetDimmed(d)
    d = d and true or false
    if self.dimmed == d then return end
    self.dimmed = d
    local a = d and 0.4 or 1
    for i = 1, table.getn(self.regions) do self.regions[i]:SetAlpha(a) end
    for i = 1, table.getn(self.controls) do self.controls[i]:EnableMouse(not d) end
end

function Aegis_SBR_UI:NewLayout(parent)
    local L = setmetatable({ ui = self, p = parent, host = nil, y = 0, sections = {}, cur = nil }, Aegis_SBR_Layout)
    self.bodyLayout = L   -- Refresh reflows this when the spec tab changes
    return L
end

-- Record a region (and whether it can take mouse input) into the section being
-- filled, if any. A no-op before the first Header, so shared controls never dim.
function Aegis_SBR_Layout:_rec(region, interactive)
    if self.cur then self.cur:_add(region, interactive) end
end

-- A full-width row highlight (hidden) sized to the row at the current cursor.
-- The row's controls light it up on hover (see wireHover); it renders on the
-- BORDER layer - above the section card fill, below the controls - and never
-- takes mouse input itself, so it cannot block a click.
function Aegis_SBR_Layout:_hl(h)
    local P = self.host or self.p
    local hl = P:CreateTexture(nil, "BORDER")
    hl:SetTexture(1, 1, 1, 0.05)
    hl:SetPoint("TOPLEFT", P, "TOPLEFT", 1, self.y - 1)
    hl:SetPoint("TOPRIGHT", P, "TOPRIGHT", -1, self.y - 1)
    hl:SetHeight((h or LAY.ROW_H) - 2)
    hl:Hide()
    return hl
end
-- Concept-style row separator: a soft hairline above every row except the
-- first one under a section's eyebrow. Registered on the section so it dims
-- with its card.
function Aegis_SBR_Layout:_sep()
    if self.y >= -LAY.HEADER_H then return end
    local P = self.host or self.p
    local t = P:CreateTexture(nil, "BORDER")
    t:SetTexture(PAL.line[1], PAL.line[2], PAL.line[3], 0.55)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", P, "TOPLEFT", 10, self.y)
    t:SetPoint("TOPRIGHT", P, "TOPRIGHT", -10, self.y)
    if self.cur then self.cur:_add(t, false) end
end

-- Point a control's hover at a row highlight. Chains any existing OnEnter/
-- OnLeave (e.g. a skinned button's own hover feedback) instead of replacing
-- it; Tip later chains onto this in turn.
local function wireHover(ctrl, hl)
    if not ctrl or not hl then return end
    local pe = ctrl:GetScript("OnEnter")
    local pl = ctrl:GetScript("OnLeave")
    ctrl:SetScript("OnEnter", function() if pe then pe() end hl:Show() end)
    ctrl:SetScript("OnLeave", function() if pl then pl() end hl:Hide() end)
end

-- Close the running section card: a flat panel with a 1px hairline border
-- spanning from the section's header to the current cursor. The textures are
-- registered on the section so SetDimmed fades the card with its controls.
-- Close the section being filled: freeze its container height to the content
-- laid out inside it. Reflow (below) stacks the visible containers.
function Aegis_SBR_Layout:_closeSection()
    if not self.cur or not self.cur.cont then return end
    self.cur.h = -self.y + 4
    self.cur.cont:SetHeight(self.cur.h)
    self.host = nil
end

-- A section header: closes the previous section and opens a new one as its
-- own CONTAINER frame, skinned as a card (fill + hairlines). The optional
-- second argument tags the section with a spec key (string, or a set table
-- like { enhancement = true, tank = true }); tagged sections only exist on
-- screen while their spec's tab is active - Reflow stacks whatever is shown.
-- Returns the section handle for SetDimmed, as before.
function Aegis_SBR_Layout:Header(text, spec)
    self:_closeSection()
    local cont = CreateFrame("Frame", nil, self.p)
    cont:SetPoint("TOPLEFT", self.p, "TOPLEFT", 0, 0)
    cont:SetPoint("TOPRIGHT", self.p, "TOPRIGHT", 0, 0)
    cont:SetHeight(10)
    local sec = setmetatable({ regions = {}, controls = {}, dimmed = false,
        cont = cont, spec = spec }, Section)
    NineSlice(cont, "Interface\\AddOns\\Aegis_SBR\\Icons\\Card", 10,
        function(t) sec:_add(t, false) end)
    local fs = FS(cont, "GameFontNormal", string.upper(text or ""))
    SetFontSafe(fs, true, 10)
    fs:SetPoint("TOPLEFT", cont, "TOPLEFT", LAY.L_PAD + 4, -10)
    fs:SetTextColor(PAL.mute[1], PAL.mute[2], PAL.mute[3])
    sec:_add(fs, false)
    table.insert(self.sections, sec)
    self.cur = sec
    self.host = cont
    self.y = -LAY.HEADER_H
    return sec
end

-- A single full-width checkbox row. args mirror CreateCheck.
function Aegis_SBR_Layout:Check(key, label, spell, onChange)
    self:_sep()
    local hl = self:_hl(LAY.ROW_H)
    local P = self.host or self.p
    local item = self.ui:CreateCheck(key, P, label, spell, onChange)
    item.cb:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD, self.y)
    item.label:SetWidth(278); item.label:SetHeight(12); item.label:SetJustifyH("LEFT")
    wireHover(item.cb, hl)
    self:_rec(item.cb, true); self:_rec(item.label, false)
    self.y = self.y - LAY.ROW_H
    return item
end

-- Two checkboxes side by side; a/b are {key,label,spell,onChange}.
function Aegis_SBR_Layout:CheckPair(a, b)
    self:_sep()
    local hl = self:_hl(LAY.ROW_H)
    local P = self.host or self.p
    local ia = self.ui:CreateCheck(a[1], P, a[2], a[3], a[4])
    ia.cb:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD, self.y)
    local ib = self.ui:CreateCheck(b[1], P, b[2], b[3], b[4])
    ib.cb:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.COL2_X, self.y)
    ia.label:SetWidth(128); ia.label:SetHeight(12); ia.label:SetJustifyH("LEFT")
    ib.label:SetWidth(116); ib.label:SetHeight(12); ib.label:SetJustifyH("LEFT")
    wireHover(ia.cb, hl); wireHover(ib.cb, hl)
    self:_rec(ia.cb, true); self:_rec(ia.label, false)
    self:_rec(ib.cb, true); self:_rec(ib.label, false)
    self.y = self.y - LAY.ROW_H
    return ia, ib
end

-- A full-width slider (label centred above the bar). opts is optional; a
-- function passed in its place is treated as the onChange (CreateSlider shim).
function Aegis_SBR_Layout:Slider(key, label, opts, onChange)
    self:_sep()
    local hl = self:_hl(LAY.SLIDER_H)
    local P = self.host or self.p
    local s = self.ui:CreateSlider(key, P, label, opts, onChange)
    s:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD + 6, self.y - LAY.SLIDER_TOP)
    wireHover(s, hl)
    self:_rec(s, true)
    self.y = self.y - LAY.SLIDER_H
    return s
end

-- Two sliders side by side; a/b are {key,label,onChange} or {key,label,opts,onChange}
-- (a function in the opts slot is treated as onChange by CreateSlider).
function Aegis_SBR_Layout:SliderPair(a, b)
    self:_sep()
    local hl = self:_hl(LAY.SLIDER_H)
    local P = self.host or self.p
    local sa = self.ui:CreateSlider(a[1], P, a[2], a[3], a[4])
    sa:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD + 6, self.y - LAY.SLIDER_TOP)
    local sb = self.ui:CreateSlider(b[1], P, b[2], b[3], b[4])
    sb:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.COL2_X, self.y - LAY.SLIDER_TOP)
    wireHover(sa, hl); wireHover(sb, hl)
    self:_rec(sa, true); self:_rec(sb, true)
    self.y = self.y - LAY.SLIDER_H
    return sa, sb
end

-- A label with a dropdown to its right (the dropdown floats right after the
-- label, so longer labels never collide with it).
function Aegis_SBR_Layout:Dropdown(key, label, width, onChange)
    self:_sep()
    local hl = self:_hl(LAY.DD_H)
    local P = self.host or self.p
    local lab = FS(P, "GameFontNormalSmall", label)
    SetFontSafe(lab, false, 12)
    lab:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD, self.y - 8)
    -- Fixed label column so every dropdown box lines up to the same left edge
    -- (labels vary in width - "Air totem" vs "Water totem" - and a box anchored
    -- to the label's right would otherwise start at a different x each row).
    lab:SetWidth(LAY.DD_LABEL_W); lab:SetJustifyH("LEFT")
    lab:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
    local d = self.ui:CreateDropdown(key, P, width or 150, onChange)
    d:SetPoint("TOPLEFT", lab, "TOPLEFT", LAY.DD_LABEL_W + 4, 1)
    -- Centre the box's own text so all the pickers read uniformly.
    local dt = getglobal(d:GetName() .. "Text")
    if dt then dt:SetJustifyH("CENTER"); dt:ClearAllPoints(); dt:SetPoint("CENTER", d, "CENTER", 0, 0) end
    wireHover(d, hl)
    self:_rec(d, true); self:_rec(lab, false)
    self.y = self.y - LAY.DD_H
    return d, lab
end

-- A label + dropdown on the left, and a checkbox on the right of the same row.
-- dd = {key,label,width,onChange}; ck = {key,label,spell,onChange}.
function Aegis_SBR_Layout:DropdownCheck(dd, ck)
    self:_sep()
    local hl = self:_hl(LAY.DD_H)
    local P = self.host or self.p
    local lab = FS(P, "GameFontNormalSmall", dd.label)
    lab:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD, self.y - 6)
    local d = self.ui:CreateDropdown(dd.key, P, dd.width or 110, dd.onChange)
    d:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.L_PAD + LAY.LABEL_W, self.y - 2)
    local item = self.ui:CreateCheck(ck[1], P, ck[2], ck[3], ck[4])
    item.cb:SetPoint("TOPLEFT", P, "TOPLEFT", LAY.COL2_X, self.y)
    item.label:SetWidth(116); item.label:SetHeight(12); item.label:SetJustifyH("LEFT")
    wireHover(d, hl); wireHover(item.cb, hl)
    self:_rec(d, true); self:_rec(lab, false)
    self:_rec(item.cb, true); self:_rec(item.label, false)
    self.y = self.y - LAY.DD_H
    return d, item
end

function Aegis_SBR_Layout:Gap(n) self.y = self.y - (n or 8) end

-- Concept-style row: [switch] Label sub ............ [slider--] [value]
-- One row per setting. o = { key, label, sub, spell, onToggle, slider = {
-- key, min, max, step, suffix, onChange, width } }. Omit onToggle for a plain
-- value row; omit slider for a plain toggle row. The muted sub-label rides
-- inside the label string as an inline colour code, so BindCheck's
-- "(not learned)" suffixing keeps working. Returns { cb, label, baseText,
-- spellName, slider, value } - BindCheck-compatible.
function Aegis_SBR_Layout:Row(o)
    self:_sep()
    local P = self.host or self.p
    local hl = self:_hl(LAY.VROW_H)
    local baseText = o.label or ""
    if o.sub then baseText = baseText .. "  |cff8b8f98" .. o.sub .. "|r" end
    local item
    local x = 12
    if o.onToggle then
        item = self.ui:CreateCheck(o.key, P, "", o.spell, o.onToggle)
        item.cb:SetPoint("TOPLEFT", P, "TOPLEFT", 10, self.y - 6)
        wireHover(item.cb, hl)
        self:_rec(item.cb, true)
        x = 48
    else
        item = { spellName = o.spell }
    end
    local lab = FS(P, "GameFontNormalSmall", baseText)
    SetFontSafe(lab, false, 12)
    lab:SetPoint("TOPLEFT", P, "TOPLEFT", x, self.y - 9)
    lab:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
    lab:SetHeight(12); lab:SetJustifyH("LEFT")
    self:_rec(lab, false)
    item.label = lab
    item.baseText = baseText
    if o.slider then
        local so = o.slider
        -- Uniform grid: EVERY slider row uses the same slider width and the same
        -- right-anchored value column, so the sliders line up in one clean
        -- vertical rail (the concept look). The label takes the space to their
        -- left (slimW). fullW is the whole row minus padding - BindCheck swaps to
        -- it and hides the slider when a spell is unlearned, so the long
        -- "(not learned)" label never has to share the row with a dead slider.
        local slimW = o.onToggle and 146 or 182
        item.labelSlimW = slimW
        item.labelFullW = 322 - x - 12
        lab:SetWidth(slimW)
        local valFS = FS(P, "GameFontNormalSmall", "")
        SetFontSafe(valFS, true, 11)
        valFS:SetPoint("TOPRIGHT", P, "TOPRIGHT", -12, self.y - 9)
        valFS:SetWidth(36); valFS:SetHeight(12); valFS:SetJustifyH("RIGHT")
        valFS:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
        self:_rec(valFS, false)
        local s = self.ui:CreateSlider(so.key, P, "", so, so.onChange)
        s:SetWidth(so.width or 70); s:SetHeight(14)
        s:SetPoint("TOPRIGHT", P, "TOPRIGHT", -54, self.y - 8)
        local tt = getglobal("AegisUI_SL_" .. so.key .. "Text")
        if tt then tt:SetText("") end
        s.valText = valFS   -- value writes land in the row's right column
        wireHover(s, hl)
        self:_rec(s, true)
        item.slider = s
        item.value = valFS
    else
        lab:SetWidth(322 - x - 12)
    end
    self.y = self.y - LAY.VROW_H
    return item
end

-- Close the last section and stack everything; returns the content height.
function Aegis_SBR_Layout:Finish()
    self:_closeSection()
    self:Reflow()
    return self.total or 0
end

-- Stack the visible section containers top to bottom. A section is visible
-- when it is untagged, when the class has no spec tabs, when no profile is
-- loaded, or when its spec tag matches the active tab. Resizes the scroll
-- child and re-ranges the scrollbar, so tab switches reflow live.
function Aegis_SBR_Layout:Reflow()
    local st = MOD() and MOD().specTabs
    local cur
    if st and self.ui.buf then cur = self.ui:CurrentSpecKey() end
    local y = -LAY.TOP_PAD
    local shown = 0
    for i = 1, table.getn(self.sections) do
        local sec = self.sections[i]
        local show = true
        if cur and sec.spec then
            if type(sec.spec) == "table" then show = sec.spec[cur] and true or false
            else show = (sec.spec == cur) end
        end
        if show then
            shown = shown + 1
            sec.cont:Show()
            sec.cont:ClearAllPoints()
            sec.cont:SetPoint("TOPLEFT", self.p, "TOPLEFT", 0, y)
            sec.cont:SetPoint("TOPRIGHT", self.p, "TOPRIGHT", 0, y)
            y = y - (sec.h or 10) - LAY.SECTION_GAP
        else
            sec.cont:Hide()
        end
    end
    if shown > 0 then y = y + LAY.SECTION_GAP end
    self.total = -y + LAY.BOT_PAD
    self.p:SetHeight(self.total)
    if self.ui.UpdateScrollRange then self.ui:UpdateScrollRange() end
end

-- Build the scroll frame + child + scrollbar inside the window, and return the
-- child for BuildBody to fill. Mouse wheel and the scrollbar both pan it.
function Aegis_SBR_UI:MakeScroll(f)
    local top = SCROLL.TOP
    if MOD() and MOD().specTabs then
        top = self:SpecHasSubtitles() and SCROLL.TOP_TABS_SUB or SCROLL.TOP_TABS
    end
    local viewH = SCROLL.WIN_H + top - SCROLL.BOTTOM_PAD   -- top is negative

    local sf = CreateFrame("ScrollFrame", "AegisUI_BodyScroll", f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", SCROLL.LEFT, top)
    sf:SetWidth(SCROLL.WIDTH); sf:SetHeight(viewH)

    local child = CreateFrame("Frame", "AegisUI_BodyScrollChild", sf)
    child:SetWidth(SCROLL.WIDTH); child:SetHeight(viewH)
    sf:SetScrollChild(child)

    local sb = CreateFrame("Slider", "AegisUI_BodyScrollBar", f, "UIPanelScrollBarTemplate")
    -- Inset the slider top/bottom by the thumb margin; the groove (drawn below)
    -- spans the full visible rail, so the thumb travels inside it with margin
    -- at each end and its half-height never overhangs.
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, top - 2 - 12)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, SCROLL.BOTTOM_PAD + 12 + 12)
    sb:SetWidth(SCROLL.BAR_W)
    -- skin: drop the template's arrow buttons (the wheel and thumb-drag below
    -- cover scrolling), draw a slim dark groove, and use a flat bright thumb.
    local up = getglobal("AegisUI_BodyScrollBarScrollUpButton")
    local dn = getglobal("AegisUI_BodyScrollBarScrollDownButton")
    if up then up:Hide() end
    if dn then dn:Hide() end
    -- Groove = the visible rail. It extends THUMB_MARGIN beyond the (inset)
    -- slider at top and bottom, so the thumb's centre-anchored travel stays
    -- inside the rail with margin to spare - no overhang on any class.
    local THUMB_MARGIN = 12
    local groove = sb:CreateTexture(nil, "BACKGROUND")
    groove:SetTexture(0, 0, 0, 0.45)
    groove:SetPoint("TOPLEFT", sb, "TOPLEFT", 6, THUMB_MARGIN)
    groove:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -6, -THUMB_MARGIN)
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local th = sb:GetThumbTexture()
    if th then th:SetWidth(4); th:SetHeight(20); th:SetVertexColor(0.42, 0.43, 0.48, 0.95) end
    sb.arThumb = th
    sb:SetScript("OnValueChanged", function() if sf.SetVerticalScroll then sf:SetVerticalScroll(sb:GetValue()) end end)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(20); sb:SetValue(0)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function()
        local mn, mx = sb:GetMinMaxValues()
        local v = sb:GetValue() - (arg1 * 28)
        if v < mn then v = mn elseif v > mx then v = mx end
        sb:SetValue(v)
    end)

    self.bodyScroll = sf; self.bodyChild = child; self.bodyScrollBar = sb
    return child
end

-- After the body is built, set the scrollbar range from the child height and
-- hide the bar when everything already fits.
function Aegis_SBR_UI:UpdateScrollRange()
    local sf, child, sb = self.bodyScroll, self.bodyChild, self.bodyScrollBar
    if not (sf and child and sb) then return end
    local maxScroll = child:GetHeight() - sf:GetHeight()
    if maxScroll < 0 then maxScroll = 0 end
    sb:SetMinMaxValues(0, maxScroll)
    if sb:GetValue() > maxScroll then sb:SetValue(maxScroll) end
    -- Only show the bar when the overflow is real. The child height carries a
    -- small bottom pad, so a panel whose controls fit can still be a few px
    -- taller than the viewport; that must not raise a bar with nothing to
    -- scroll (e.g. the Rogue panel). Require more than the pad to overflow.
    if maxScroll <= LAY.BOT_PAD then
        sb:SetMinMaxValues(0, 0); sb:SetValue(0)
        if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
        sb:Hide()
    else
        sb:Show()
    end
    -- Thumb is a small fixed grip (set at creation). Because the slider is
    -- inset THUMB_MARGIN inside the visible groove, its centre-anchored travel
    -- plus half-height stays within the rail on every class - no resize needed.
end


-- ------------------------------------------------------------
-- reusable dialog (input and yes/no), avoids StaticPopup quirks
-- ------------------------------------------------------------
function Aegis_SBR_UI:EnsureDialog()
    if self.dlg then return end
    local d = CreateFrame("Frame", "Aegis_SBR_Dialog", UIParent)
    d:SetWidth(300); d:SetHeight(140)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    d:SetBackdrop(FLAT_BACKDROP)
    d:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 0.99)
    SkinBorder(d)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:Hide()
    local prompt = FS(d, "GameFontNormal", ""); prompt:SetPoint("TOP", d, "TOP", 0, -24)
    prompt:SetWidth(260); prompt:SetJustifyH("CENTER")
    d.prompt = prompt
    local eb = CreateFrame("EditBox", "Aegis_SBR_DialogEdit", d, "InputBoxTemplate")
    eb:SetWidth(220); eb:SetHeight(20); eb:SetPoint("TOP", prompt, "BOTTOM", 0, -14)
    eb:SetAutoFocus(false); eb:SetMaxLetters(32)
    eb:SetScript("OnEscapePressed", function() d:Hide() end)
    d.eb = eb
    local ok = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    ok:SetWidth(100); ok:SetHeight(24); ok:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 24, 16)
    d.ok = ok
    local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    cancel:SetWidth(100); cancel:SetHeight(24); cancel:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -24, 16)
    cancel:SetScript("OnClick", function() d:Hide() end)
    d.cancel = cancel
    SkinButton(d.ok, "accent")
    SkinButton(d.cancel, "ghost")
    self.dlg = d
end

function Aegis_SBR_UI:ShowDialog(opts)
    self:EnsureDialog()
    local d = self.dlg
    d.prompt:SetText(opts.prompt or "")
    local function accept()
        local txt = opts.withInput and d.eb:GetText() or nil
        d:Hide()
        if opts.onAccept then opts.onAccept(txt) end
    end
    if opts.withInput then
        d.eb:Show(); d.eb:SetText(opts.initialText or "")
        d.eb:SetScript("OnEnterPressed", accept)
    else
        d.eb:Hide()
    end
    d.ok:SetText(opts.acceptLabel or "OK")
    d.cancel:SetText(opts.cancelLabel or "Cancel")
    d.ok:SetScript("OnClick", accept)
    d:Show(); d:Raise()
    if opts.withInput then d.eb:SetFocus() end
end

-- ============================================================
-- build (shell, then class body)
-- ============================================================
-- ------------------------------------------------------------
-- Spec tab rail. A class opts in with M.specTabs = { field = ..., default =
-- ..., tabs = { { key, label, tip1, tip2 }, ... } }; the rail then replaces
-- that class's spec dropdown. A tab click writes the key to the same profile
-- field the dropdown wrote to, so the body's dim logic and the rotation's
-- branching are untouched. Classes without specTabs are unaffected.
-- ------------------------------------------------------------
function Aegis_SBR_UI:BuildSpecTabs(f)
    local st = MOD() and MOD().specTabs
    if not st or not st.tabs then return end
    local n = table.getn(st.tabs)
    if n == 0 then return end
    local w = math.floor(348 / n)
    local acc = classColor()
    local base = f:CreateTexture(nil, "ARTWORK")
    base:SetTexture(PAL.line[1], PAL.line[2], PAL.line[3], 1)
    base:SetHeight(1)
    base:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -104)
    base:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -104)
    self.specTabBtns = {}
    for i = 1, n do
        local tab = st.tabs[i]
        local b = CreateFrame("Button", "AegisUI_TAB_" .. tab.key, f)
        b:SetWidth(w); b:SetHeight(23)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + (i - 1) * w, -81)
        local hov = b:CreateTexture(nil, "BACKGROUND")
        hov:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        hov:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        hov:SetTexture(1, 1, 1, 0.05); hov:Hide()
        local fs = FS(b, "GameFontNormal", string.upper(tab.label))
        SetFontSafe(fs, true, 10)
        fs:SetPoint("CENTER", b, "CENTER", 0, 1)
        fs:SetWidth(w - 6); fs:SetHeight(12)
        fs:SetTextColor(PAL.mute[1], PAL.mute[2], PAL.mute[3])
        local ul = b:CreateTexture(nil, "OVERLAY")
        ul:SetTexture(acc[1], acc[2], acc[3], 1)
        ul:SetHeight(2)
        ul:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 0)
        ul:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 0)
        ul:Hide()
        b:SetScript("OnEnter", function() hov:Show() end)
        b:SetScript("OnLeave", function() hov:Hide() end)
        b:SetScript("OnClick", function() Aegis_SBR_UI:SelectSpecTab(tab.key) end)
        if tab.tip1 then Tip(b, tab.label, tab.tip1, tab.tip2) end
        self.specTabBtns[i] = { key = tab.key, fs = fs, ul = ul }
    end

    -- Optional per-tab explanation line, shown just under the rail and swapped in
    -- Refresh to match the active tab. Reserves a little extra body offset.
    if self:SpecHasSubtitles() then
        local sub = FS(f, "GameFontNormalSmall", "")
        SetFontSafe(sub, false, 9)
        sub:SetJustifyH("LEFT"); sub:SetJustifyV("TOP")
        sub:SetWidth(348); sub:SetHeight(30)
        sub:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -108)
        sub:SetTextColor(PAL.mute[1], PAL.mute[2], PAL.mute[3])
        self.specSubFS = sub
    end
end

-- True if the active class's spec tabs carry per-tab subtitle lines.
function Aegis_SBR_UI:SpecHasSubtitles()
    local st = MOD() and MOD().specTabs
    if not st or not st.tabs then return false end
    for i = 1, table.getn(st.tabs) do
        if st.tabs[i].sub then return true end
    end
    return false
end

function Aegis_SBR_UI:SelectSpecTab(key)
    if not self.buf then return end
    local st = MOD() and MOD().specTabs
    if not st then return end
    -- NOTE: do NOT use "st.encode and st.encode(key) or key" here. encode may
    -- legitimately return false (e.g. the paladin Damage tab maps to healMode =
    -- false), and the and/or idiom would then fall through to the string key,
    -- storing "damage" instead of false. A non-empty string is truthy, so the
    -- rotation would read it as heal mode and the tab could never switch back.
    local val = key
    if st.encode then val = st.encode(key) end
    if self.buf[st.field] == val then return end
    self.buf[st.field] = val
    self:Refresh()   -- Refresh live-applies to the active profile (see AutoApplyActive)
end

-- Push the edit buffer onto the active profile whenever the profile being
-- edited IS the active one, so the UI behaves like a live control (a tab or a
-- click switches the running rotation immediately, no separate Activate step).
-- This deliberately does NOT gate on validity: the running rotation already
-- tolerates untrained spells (it skips what is not learned), and gating here was
-- what trapped a heal profile whose seals were not trained yet - the tab looked
-- switched but nothing applied, so only the slash command worked. Editing a
-- non-active profile stays buffered and the footer prompts for Activate.
function Aegis_SBR_UI:AutoApplyActive()
    if not self.buf or not self.editing then return end
    if AegisDB.active ~= self.editing then return end
    AegisDB.profiles[self.editing] = CORE.CopyProfile(CORE, self.buf)
end

-- Current tab key for the loaded profile: decodes the stored field value back to
-- a tab key (identity for plain string rails), falling back to the default.
function Aegis_SBR_UI:CurrentSpecKey()
    local st = MOD() and MOD().specTabs
    if not st or not self.buf then return nil end
    if st.decode then return st.decode(self.buf[st.field]) end
    return self.buf[st.field] or st.default
end

function Aegis_SBR_UI:Build()
    if self.built then return end

    local scrolled = MOD() and MOD().useScrollLayout
    local f = CreateFrame("Frame", "Aegis_SBR_UIFrame", UIParent)
    f:SetWidth(380); f:SetHeight(scrolled and SCROLL.WIN_H or ((MOD() and MOD().uiHeight) or 520))
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop(FLAT_BACKDROP)
    f:SetBackdropColor(PAL.bg[1], PAL.bg[2], PAL.bg[3], PAL.bg[4])
    SkinBorder(f)
    f:SetFrameStrata("HIGH")   -- above world nameplates, below dialogs/tooltips
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()
    self.frame = f

    -- 2px class-colour strip along the top edge: the skin's accent. The same
    -- window wears Druid orange, Shaman blue, Priest white automatically.
    local acc = classColor()
    local strip = f:CreateTexture(nil, "OVERLAY")
    strip:SetTexture(acc[1], acc[2], acc[3], 0.9)
    strip:SetHeight(2)
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)

    -- Identity row (concept-aligned): "A" sigil square in the class accent,
    -- uppercase wordmark, and a version chip; a hairline closes the row. The
    -- class identity is carried by the accent itself (strip, sigil, tabs).
    local sigil = f:CreateTexture(nil, "ARTWORK")
    sigil:SetTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\RoundSq")
    if sigil.SetGradientAlpha then
        -- bright accent at the top fading darker below, like the concept
        sigil:SetGradientAlpha("VERTICAL", acc[1] * 0.45, acc[2] * 0.45, acc[3] * 0.45, 1,
            acc[1], acc[2], acc[3], 1)
    else
        sigil:SetVertexColor(acc[1], acc[2], acc[3])
    end
    sigil:SetWidth(20); sigil:SetHeight(20)
    sigil:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    local sigilFS = FS(f, "GameFontNormal", "A")
    SetFontSafe(sigilFS, true, 9)
    sigilFS:SetPoint("CENTER", sigil, "CENTER", 0, 0)
    sigilFS:SetTextColor(0.06, 0.07, 0.09)

    local brand = FS(f, "GameFontNormalLarge", "AEGIS SBR")
    SetFontSafe(brand, true, 14)
    brand:SetPoint("LEFT", sigil, "RIGHT", 8, 0)
    brand:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])

    local chipFS = FS(f, "GameFontNormalSmall", Aegis_SBR.ver or "")
    SetFontSafe(chipFS, true, 10)
    chipFS:SetTextColor(PAL.mute[1], PAL.mute[2], PAL.mute[3])
    local chip = f:CreateTexture(nil, "BORDER")
    chip:SetTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\Pill")
    chip:SetVertexColor(0.13, 0.14, 0.17)
    chip:SetHeight(16)
    chip:SetWidth((chipFS:GetStringWidth() or 40) + 16)
    chip:SetPoint("LEFT", brand, "RIGHT", 10, 0)
    chipFS:SetPoint("CENTER", chip, "CENTER", 0, 0)

    -- Aegis logo (Phase 0 stub): the raw art arrives later as
    -- Interface\AddOns\Aegis_SBR\logo.tga (power-of-two, 32-bit). The 1.12
    -- client's SetTexture returns nil for a missing file, so until the file
    -- exists the row keeps the sigil + wordmark fallback and no stray solid
    -- quad is ever drawn. New textures need a full relog, not just /reload.
    local logo = f:CreateTexture(nil, "ARTWORK")
    local logoOK = logo:SetTexture("Interface\\AddOns\\Aegis_SBR\\logo")
    if logoOK then
        logo:SetWidth(96); logo:SetHeight(24)
        logo:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -8)
        sigil:Hide(); sigilFS:Hide(); brand:Hide()
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    else
        logo:Hide()
    end

    local hl1 = f:CreateTexture(nil, "ARTWORK")
    hl1:SetTexture(PAL.line[1], PAL.line[2], PAL.line[3], 1); hl1:SetHeight(1)
    hl1:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -40)
    hl1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -40)

    -- Profile band: a panel-tinted strip holding the pill and the management
    -- ghosts, closed by its own hairline - the concept's banded header.
    local band = f:CreateTexture(nil, "BACKGROUND")
    band:SetTexture(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
    band:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -41)
    band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -41)
    band:SetHeight(36)
    local hl2 = f:CreateTexture(nil, "ARTWORK")
    hl2:SetTexture(PAL.line[1], PAL.line[2], PAL.line[3], 1); hl2:SetHeight(1)
    hl2:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -77)
    hl2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -77)
    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton"); xb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
    SkinClose(xb)

    -- "?" help button + a toggleable help panel (overlays the window). Skinned
    -- to match the flat close [x] square beside it.
    self.helpBtn = CreateFrame("Button", nil, f)
    self.helpBtn:SetPoint("RIGHT", xb, "LEFT", -4, 0)
    SkinClose(self.helpBtn, "?")
    self.helpBtn:SetScript("OnClick", function()
        if self.helpFrame:IsShown() then self.helpFrame:Hide() else self.helpFrame:Show() end
    end)
    Tip(self.helpBtn, "Help", "The one-button concept and the /sbr commands.")

    local helpText =
        "|cffFFFFFFAegis runs your whole rotation from one key.|r Put |cffFFD100/sbr|r " ..
        "(nothing else) in a macro, drag it to your bar, and press it over and over - " ..
        "each press fires the best spell for the moment from your active profile.\n\n" ..
        "|cffFFD100Setup|r\n" ..
        "|cffFFD100/sbr|r - fire the rotation (your one button)\n" ..
        "|cffFFD100/sbr ui|r - open this window\n" ..
        "|cffFFD100/sbr minimap|r - show/hide the minimap button (also |cffFFD100/sbrmap|r)\n\n" ..
        "|cffFFD100Profiles|r\n" ..
        "|cffFFD100/sbr list|r - list your profiles\n" ..
        "|cffFFD100/sbr use <name>|r - activate a profile\n" ..
        "|cffFFD100/sbr new <name>|r - create a profile\n" ..
        "|cffFFD100/sbr del <name>|r - delete a profile\n" ..
        "|cffFFD100/sbr off|r - stop using any profile\n\n" ..
        "|cffFFD100Troubleshooting|r\n" ..
        "|cffFFD100/sbr check|r - sanity-check the active profile\n" ..
        "|cffFFD100/sbr reset|r - restore default profiles\n" ..
        "|cffFFD100/sbr debug|r - dump live spell and buff names\n" ..
        "|cffFFD100/sbr trace|r - toggle a per-press log of the rotation\n\n" ..
        "|cff888888Also /aegis; /ar still works as a legacy alias. Plus class-specific commands.|r"

    local hf = CreateFrame("Frame", "Aegis_SBR_HelpFrame", f)
    hf:SetWidth(360); hf:SetHeight(358)
    hf:SetPoint("CENTER", f, "CENTER", 0, 0)
    hf:SetBackdrop(FLAT_BACKDROP)
    hf:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 0.99)
    SkinBorder(hf)
    hf:SetFrameStrata("DIALOG")
    hf:EnableMouse(true); hf:Hide()
    self.helpFrame = hf
    local ht = FS(hf, "GameFontNormalLarge", "Aegis SBR - Help"); ht:SetPoint("TOP", hf, "TOP", 0, -14)
    ht:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
    local hbody = FS(hf, "GameFontHighlightSmall", helpText)
    hbody:SetPoint("TOPLEFT", hf, "TOPLEFT", 16, -42)
    hbody:SetWidth(328); hbody:SetJustifyH("LEFT"); hbody:SetJustifyV("TOP")
    local hx = CreateFrame("Button", nil, hf, "UIPanelCloseButton")
    hx:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -6, -6)
    SkinClose(hx)
    hx:SetScript("OnClick", function() hf:Hide() end)

    -- Profile pill row: the profile being edited, with a green live dot when it
    -- is also the active one, and the management ghosts right-aligned beside it.
    self.profileDD = self:CreateDropdown("profile", f, 132, function(v) self:Load(v) end, "pill")
    self.profileDD:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
    self.profileDD:SetHeight(22)
    self.liveDot = self.profileDD:CreateTexture(nil, "OVERLAY")
    self.liveDot:SetWidth(7); self.liveDot:SetHeight(7)
    self.liveDot:SetPoint("LEFT", self.profileDD, "LEFT", 10, 0)
    self.liveDot:SetTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\SliderThumb")
    self.liveDot:SetVertexColor(0.25, 0.75, 0.37)
    self.liveDot:Hide()

    -- management buttons
    self.delBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.delBtn:SetWidth(52); self.delBtn:SetHeight(20); self.delBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -49)
    self.delBtn:SetText("Delete"); self.delBtn:SetScript("OnClick", function() self:AskDelete() end)
    self.renBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.renBtn:SetWidth(58); self.renBtn:SetHeight(20); self.renBtn:SetPoint("RIGHT", self.delBtn, "LEFT", -6, 0)
    self.renBtn:SetText("Rename"); self.renBtn:SetScript("OnClick", function() self:AskRename() end)
    self.newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.newBtn:SetWidth(46); self.newBtn:SetHeight(20); self.newBtn:SetPoint("RIGHT", self.renBtn, "LEFT", -6, 0)
    self.newBtn:SetText("New"); self.newBtn:SetScript("OnClick", function() self:AskNew() end)

    self.statusDot = f:CreateTexture(nil, "ARTWORK")
    self.statusDot:SetTexture("Interface\\AddOns\\Aegis_SBR\\Icons\\SliderThumb")
    self.statusDot:SetWidth(8); self.statusDot:SetHeight(8)
    self.statusDot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 24)
    self.status = FS(f, "GameFontNormalSmall", "")
    self.status:SetPoint("LEFT", self.statusDot, "RIGHT", 6, 0)
    self.status:SetWidth(172); self.status:SetJustifyH("LEFT")

    self:BuildSpecTabs(f)

    self.activateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.activateBtn:SetWidth(78); self.activateBtn:SetHeight(22)
    self.activateBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    self.activateBtn:SetText("Activate")
    self.activateBtn:SetScript("OnClick", function() self:DoActivate() end)
    self.saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.saveBtn:SetWidth(58); self.saveBtn:SetHeight(22)
    self.saveBtn:SetPoint("RIGHT", self.activateBtn, "LEFT", -8, 0)
    self.saveBtn:SetText("Save")
    self.saveBtn:SetScript("OnClick", function() self:DoSave() end)

    -- skin the action buttons: Activate is the one accent-filled primary
    -- (it changes what the macro does); everything else is a quiet ghost.
    SkinButton(self.activateBtn, "accent")
    SkinButton(self.newBtn, "ghost")
    SkinButton(self.renBtn, "ghost")
    SkinButton(self.delBtn, "ghost")
    SkinButton(self.saveBtn, "ghost")

    -- plain language tooltips for new users
    Tip(self.profileDD, "Profile", "The set of seals and spells the rotation uses.", "Switch here to edit a different one.")
    Tip(self.activateBtn, "Activate", "Saves this profile and makes the macro use it.", "The macro always runs the active profile.")
    Tip(self.saveBtn, "Save", "Stores your changes to this profile.", "Does not change which profile the macro uses.")
    Tip(self.newBtn, "New", "Creates a new profile from a blank starter.")
    Tip(self.renBtn, "Rename", "Renames the profile being edited.")
    Tip(self.delBtn, "Delete", "Deletes the profile being edited, after a prompt.")

    if MOD() and MOD().BuildBody then
        if scrolled then
            local child = self:MakeScroll(f)
            MOD():BuildBody(self, child)
            self:UpdateScrollRange()
        else
            MOD():BuildBody(self, f)
        end
    end

    self.built = true
end

-- ============================================================
-- data binding
-- ============================================================
function Aegis_SBR_UI:CopyBuf(name)
    local src = AegisDB.profiles[name]
    if not src then return nil end
    return CORE.CopyProfile(CORE, src)
end

function Aegis_SBR_UI:Load(name)
    if not AegisDB.profiles[name] then return end
    self.editing = name
    self.buf = self:CopyBuf(name)
    self:Refresh()
end

function Aegis_SBR_UI:ProfileNameList()
    local list = {}
    for n in pairs(AegisDB.profiles) do table.insert(list, n) end
    table.sort(list)
    return list
end

function Aegis_SBR_UI:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide(); return end
    local pick = AegisDB.active
    if not pick or not AegisDB.profiles[pick] then pick = self:ProfileNameList()[1] end
    if pick then self.editing = pick; self.buf = self:CopyBuf(pick) else self.editing = nil; self.buf = nil end
    self.frame:Show()
    self:Refresh()
end

-- ============================================================
-- refresh (profile bar and validity, then class body)
-- ============================================================
function Aegis_SBR_UI:Refresh()
    if not self.built then return end
    self.loading = true

    local names = self:ProfileNameList()
    local opts = {}
    for i = 1, table.getn(names) do opts[i] = { label = names[i], value = names[i] } end
    self:SetDropdown(self.profileDD, opts, self.editing, self.editing or "(none)", COL.white)
    if self.profileDD.arFitText then self.profileDD.arFitText() end
    if self.liveDot then
        if self.editing and AegisDB.active == self.editing then self.liveDot:Show() else self.liveDot:Hide() end
    end

    -- spec tab rail active state (classes with M.specTabs)
    if self.specTabBtns then
        local cur = self:CurrentSpecKey()
        for i = 1, table.getn(self.specTabBtns) do
            local tb = self.specTabBtns[i]
            if tb.key == cur then
                tb.ul:Show(); tb.fs:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
            else
                tb.ul:Hide(); tb.fs:SetTextColor(PAL.mute[1], PAL.mute[2], PAL.mute[3])
            end
        end
        if self.specSubFS then
            local st = MOD() and MOD().specTabs
            local subText = ""
            if st and st.tabs then
                for i = 1, table.getn(st.tabs) do
                    if st.tabs[i].key == cur then subText = st.tabs[i].sub or ""; break end
                end
            end
            self.specSubFS:SetText(subText)
        end
    end

    if not self.buf then
        self.status:SetText("No profile. Use New to create one."); color(self.status, COL.grey)
        if self.statusDot then self.statusDot:SetVertexColor(0.45, 0.46, 0.50) end
        self.saveBtn:Disable(); self.activateBtn:Disable()
        self.loading = false
        return
    end

    if MOD() and MOD().RefreshBody then MOD():RefreshBody(self, self.buf) end
    if self.bodyLayout then self.bodyLayout:Reflow() end

    -- Live-apply edits to the active profile, so the window doubles as an
    -- in-combat control surface for the profile the rotation is running.
    self:AutoApplyActive()

    local ok, missing = MOD():ProfileValidity(self.buf)
    local isActive = self.editing and AegisDB.active == self.editing
    -- Missing spells no longer block anything: the rotation skips whatever is
    -- not trained, so a profile is always usable and always applies. Validity is
    -- now purely an amber note. This is what keeps the heal/damage tab from
    -- getting stuck on a character that has not trained every seal yet.
    if isActive then
        if ok then self.status:SetText("Active profile - changes apply live")
        else self.status:SetText("Active (live) - not trained yet: " .. table.concat(missing, ", ")) end
    else
        if ok then self.status:SetText("Profile valid - Activate to use")
        else self.status:SetText("Usable now, not trained yet: " .. table.concat(missing, ", ")) end
    end
    self.status:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
    if self.statusDot then
        if ok then self.statusDot:SetVertexColor(0.25, 0.75, 0.37)
        else self.statusDot:SetVertexColor(0.95, 0.75, 0.25) end
    end
    -- The active profile is already live, so its Save/Activate are redundant and
    -- stay disabled; a non-active profile keeps them so it can be saved/activated.
    if isActive then self.saveBtn:Disable(); self.activateBtn:Disable()
    else self.saveBtn:Enable(); self.activateBtn:Enable() end

    self.loading = false
end

-- ------------------------------------------------------------
-- profile management
-- ------------------------------------------------------------
function Aegis_SBR_UI:AskNew()
    self:ShowDialog({
        prompt = "New profile name:", withInput = true, acceptLabel = "Create",
        onAccept = function(txt) self:NewProfile(txt) end,
    })
end

function Aegis_SBR_UI:NewProfile(name)
    name = trim(name)
    if name == "" then DEFAULT_CHAT_FRAME:AddMessage("Aegis: name required.", 1, 0.5, 0.3); return end
    if AegisDB.profiles[name] then DEFAULT_CHAT_FRAME:AddMessage("Aegis: '" .. name .. "' already exists.", 1, 0.5, 0.3); return end
    AegisDB.profiles[name] = CORE.CopyProfile(CORE, MOD().templates.starter)
    self.editing = name
    self.buf = self:CopyBuf(name)
    self:Refresh()
end

function Aegis_SBR_UI:AskRename()
    if not self.editing then return end
    self:ShowDialog({
        prompt = "Rename '" .. self.editing .. "' to:", withInput = true, initialText = self.editing, acceptLabel = "Rename",
        onAccept = function(txt) self:RenameProfile(txt) end,
    })
end

function Aegis_SBR_UI:RenameProfile(newName)
    newName = trim(newName)
    if newName == "" or not self.editing then return end
    if newName == self.editing then return end
    if AegisDB.profiles[newName] then DEFAULT_CHAT_FRAME:AddMessage("Aegis: '" .. newName .. "' already exists.", 1, 0.5, 0.3); return end
    local old = self.editing
    AegisDB.profiles[newName] = AegisDB.profiles[old]
    AegisDB.profiles[old] = nil
    if AegisDB.active == old then AegisDB.active = newName end
    self.editing = newName
    self.buf = self:CopyBuf(newName)
    self:Refresh()
end

function Aegis_SBR_UI:AskDelete()
    if not self.editing then return end
    self:ShowDialog({
        prompt = "Delete profile '" .. self.editing .. "'?", withInput = false,
        acceptLabel = "Yes", cancelLabel = "No",
        onAccept = function() self:DeleteProfile() end,
    })
end

function Aegis_SBR_UI:DeleteProfile()
    if not self.editing then return end
    local name = self.editing
    AegisDB.profiles[name] = nil
    if AegisDB.active == name then AegisDB.active = nil end
    local nxt = self:ProfileNameList()[1]
    if nxt then self.editing = nxt; self.buf = self:CopyBuf(nxt) else self.editing = nil; self.buf = nil end
    self:Refresh()
end

-- ------------------------------------------------------------
-- commit
-- ------------------------------------------------------------
function Aegis_SBR_UI:DoSave()
    if not self.buf or not self.editing then return end
    AegisDB.profiles[self.editing] = CORE.CopyProfile(CORE, self.buf)
    DEFAULT_CHAT_FRAME:AddMessage("Aegis: saved '" .. self.editing .. "'.", 1, 0.8, 0)
    self:Refresh()
end

function Aegis_SBR_UI:DoActivate()
    if not self.buf or not self.editing then return end
    AegisDB.profiles[self.editing] = CORE.CopyProfile(CORE, self.buf)
    AegisDB.active = self.editing
    DEFAULT_CHAT_FRAME:AddMessage("Aegis: activated '" .. self.editing .. "'.", 1, 0.8, 0)
    self:Refresh()
end
