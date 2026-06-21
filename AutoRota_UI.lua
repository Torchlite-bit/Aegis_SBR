-- ============================================================
-- AutoRota_UI  -  shared configuration window framework
-- Turtle WoW 1.12 frame API. Builds the window shell and profile
-- management, then delegates the class specific body to the active
-- module via M:BuildBody(ui, frame) and M:RefreshBody(ui, buf).
-- ============================================================

AutoRotaUI = { built = false, loading = false, editing = nil, buf = nil, openDD = nil }

local CORE = AutoRota
local function MOD() return AutoRota.active end


local COL = {
    gold  = {1.0, 0.82, 0.0}, white = {1.0, 1.0, 1.0},
    green = {0.3, 1.0, 0.3},  red = {1.0, 0.35, 0.35}, grey = {0.55, 0.55, 0.55},
}
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local LIST_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function FS(parent, font, text)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    if text then f:SetText(text) end
    return f
end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function trim(s) local r = string.gsub(s or "", "^%s*(.-)%s*$", "%1"); return r end

-- Attach a hover tooltip to any mouse-enabled frame. body lines are optional.
local function Tip(frame, title, line1, line2)
    if not frame then return end
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if line1 then GameTooltip:AddLine(line1, 1, 1, 1) end
        if line2 then GameTooltip:AddLine(line2, 1, 1, 1) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Thin horizontal separator line at a given y offset from the frame top.
local function divider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(0.5, 0.5, 0.5, 0.4)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y)
end

-- Wrappers so class body files (separate files) can use the framework helpers.
AutoRotaUI.COL = COL
function AutoRotaUI:FS(parent, font, text) return FS(parent, font, text) end
function AutoRotaUI:Color(fs, c) color(fs, c) end
function AutoRotaUI:Tip(frame, title, l1, l2) Tip(frame, title, l1, l2) end
function AutoRotaUI:Divider(parent, y) divider(parent, y) end


-- ------------------------------------------------------------
-- custom dropdown
-- ------------------------------------------------------------
function AutoRotaUI:CreateDropdown(uniqueName, parent, width, onSelect)
    local b = CreateFrame("Button", "ARUI_DD_" .. uniqueName, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(22)
    b.onSelect = onSelect; b.options = {}; b.rows = {}
    -- Parent the popup to the window (not the button) so a body scroll frame
    -- cannot clip it; it is still anchored under the button below.
    local list = CreateFrame("Frame", "ARUI_DD_" .. uniqueName .. "_List", self.frame or parent)
    list:SetBackdrop(LIST_BACKDROP); list:SetBackdropColor(0, 0, 0, 0.95)
    list:SetFrameStrata("FULLSCREEN_DIALOG"); list:SetWidth(width)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 2); list:Hide()
    b.list = list
    b:SetScript("OnClick", function()
        if list:IsShown() then AutoRotaUI:CloseDropdown(b) else AutoRotaUI:OpenDropdown(b) end
    end)
    return b
end

function AutoRotaUI:CloseDropdown(b)
    b.list:Hide()
    if self.openDD == b then self.openDD = nil end
end

function AutoRotaUI:OpenDropdown(b)
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
            AutoRotaUI:CloseDropdown(b)
            if b.onSelect then b.onSelect(row.value) end
        end)
        row:Show()
    end
    for i = n + 1, table.getn(b.rows) do b.rows[i]:Hide() end
    b.list:SetHeight(8 + n * rowH); b.list:Raise(); b.list:Show()
end

function AutoRotaUI:SetDropdown(b, options, value, text, c)
    b.options = options; b.value = value; b:SetText(text)
    local fs = b:GetFontString()
    if fs and c then color(fs, c) end
end

-- ------------------------------------------------------------
-- checkbox
-- ------------------------------------------------------------
function AutoRotaUI:CreateCheck(uniqueName, parent, labelText, spellName, onClick)
    local cb = CreateFrame("CheckButton", "ARUI_CB_" .. uniqueName, parent, "UICheckButtonTemplate")
    cb:SetWidth(20); cb:SetHeight(20)
    local lab = FS(parent, "GameFontNormalSmall", labelText)
    lab:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", function()
        if AutoRotaUI.loading then return end
        if onClick then onClick(cb:GetChecked() and true or false) end
    end)
    return { cb = cb, label = lab, baseText = labelText, spellName = spellName }
end

-- Bind a CreateCheck item to a value during RefreshBody. If a spell name is
-- attached (per-call override, else the one given at creation), the label is
-- greyed with "(not learned)" when unknown, or red when enabled-but-unknown.
-- Every class body used to hand-roll this; now they all share it.
function AutoRotaUI:BindCheck(item, on, spellName)
    item.cb:SetChecked(on and true or false)
    item.cb:Enable()
    local name = spellName
    if name == nil then name = item.spellName end
    if not name then
        item.label:SetText(item.baseText); color(item.label, COL.white)
        return
    end
    local known = AutoRota.active and AutoRota.active:KnowsSpell(name)
    if known then
        item.label:SetText(item.baseText); color(item.label, COL.white)
    elseif on then
        item.label:SetText(item.baseText .. " (not learned)"); color(item.label, COL.red)
    else
        item.label:SetText(item.baseText .. " (not learned)"); color(item.label, COL.grey)
    end
end

-- Enable or grey out a slider in one call (mouse + alpha), so callers do not
-- repeat the EnableMouse/SetAlpha pair. Used by the class config bodies to
-- follow a checkbox's on/off and learned state.
function AutoRotaUI:SliderEnable(slider, on)
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
function AutoRotaUI:CreateSlider(uniqueName, parent, labelText, opts, onChange)
    if type(opts) == "function" then onChange = opts; opts = nil end
    opts = opts or {}
    local mn = opts.min or 0
    local mx = opts.max or 100
    local stp = opts.step or 5
    local suffix = opts.suffix
    if suffix == nil then suffix = "%" end
    local nm = "ARUI_SL_" .. uniqueName
    local s = CreateFrame("Slider", nm, parent, "OptionsSliderTemplate")
    s:SetWidth(150); s:SetHeight(16)
    s:SetMinMaxValues(mn, mx); s:SetValueStep(stp)
    local t = getglobal(nm .. "Text");  if t then t:SetText(labelText) end
    local lo = getglobal(nm .. "Low");  if lo then lo:SetText("") end
    local hi = getglobal(nm .. "High"); if hi then hi:SetText("") end
    s.labelFS = t
    s.valText = hi
    s.suffix = suffix
    s:SetScript("OnValueChanged", function()
        local v = s:GetValue()
        if s.valText then s.valText:SetText(tostring(v) .. s.suffix) end
        if not AutoRotaUI.loading and onChange then onChange(v) end
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
    L_PAD = 6, COL2_X = 170, LABEL_W = 40,
    ROW_H = 26, HEADER_H = 30, DD_H = 30, SLIDER_H = 40, SLIDER_TOP = 16,
}
local SCROLL = {
    WIN_H = 480,       -- compact fixed window height for scroll-layout classes
    TOP = -142,        -- body region starts here, below the profile/status header
    BOTTOM_PAD = 44,   -- leaves room for the footer buttons
    LEFT = 16, WIDTH = 322, BAR_W = 16,
}

local AutoRotaLayout = {}
AutoRotaLayout.__index = AutoRotaLayout

function AutoRotaUI:NewLayout(parent)
    return setmetatable({ ui = self, p = parent, y = -LAY.TOP_PAD, first = true }, AutoRotaLayout)
end

-- A section header with a divider above it (except the first).
function AutoRotaLayout:Header(text)
    if not self.first then divider(self.p, self.y - 2) end
    self.first = false
    local fs = FS(self.p, "GameFontNormal", text)
    fs:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD, self.y - 10)
    color(fs, COL.gold)
    self.y = self.y - LAY.HEADER_H
    return fs
end

-- A single full-width checkbox row. args mirror CreateCheck.
function AutoRotaLayout:Check(key, label, spell, onChange)
    local item = self.ui:CreateCheck(key, self.p, label, spell, onChange)
    item.cb:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD, self.y)
    self.y = self.y - LAY.ROW_H
    return item
end

-- Two checkboxes side by side; a/b are {key,label,spell,onChange}.
function AutoRotaLayout:CheckPair(a, b)
    local ia = self.ui:CreateCheck(a[1], self.p, a[2], a[3], a[4])
    ia.cb:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD, self.y)
    local ib = self.ui:CreateCheck(b[1], self.p, b[2], b[3], b[4])
    ib.cb:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.COL2_X, self.y)
    self.y = self.y - LAY.ROW_H
    return ia, ib
end

-- A full-width slider (label centred above the bar). opts is optional; a
-- function passed in its place is treated as the onChange (CreateSlider shim).
function AutoRotaLayout:Slider(key, label, opts, onChange)
    local s = self.ui:CreateSlider(key, self.p, label, opts, onChange)
    s:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD + 6, self.y - LAY.SLIDER_TOP)
    self.y = self.y - LAY.SLIDER_H
    return s
end

-- Two sliders side by side; a/b are {key,label,onChange} or {key,label,opts,onChange}
-- (a function in the opts slot is treated as onChange by CreateSlider).
function AutoRotaLayout:SliderPair(a, b)
    local sa = self.ui:CreateSlider(a[1], self.p, a[2], a[3], a[4])
    sa:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD + 6, self.y - LAY.SLIDER_TOP)
    local sb = self.ui:CreateSlider(b[1], self.p, b[2], b[3], b[4])
    sb:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.COL2_X, self.y - LAY.SLIDER_TOP)
    self.y = self.y - LAY.SLIDER_H
    return sa, sb
end

-- A label with a dropdown to its right (the dropdown floats right after the
-- label, so longer labels never collide with it).
function AutoRotaLayout:Dropdown(key, label, width, onChange)
    local lab = FS(self.p, "GameFontNormalSmall", label)
    lab:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD, self.y - 8)
    local d = self.ui:CreateDropdown(key, self.p, width or 150, onChange)
    d:SetPoint("LEFT", lab, "RIGHT", 8, 0)
    self.y = self.y - LAY.DD_H
    return d, lab
end

-- A label + dropdown on the left, and a checkbox on the right of the same row.
-- dd = {key,label,width,onChange}; ck = {key,label,spell,onChange}.
function AutoRotaLayout:DropdownCheck(dd, ck)
    local lab = FS(self.p, "GameFontNormalSmall", dd.label)
    lab:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD, self.y - 6)
    local d = self.ui:CreateDropdown(dd.key, self.p, dd.width or 110, dd.onChange)
    d:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.L_PAD + LAY.LABEL_W, self.y - 2)
    local item = self.ui:CreateCheck(ck[1], self.p, ck[2], ck[3], ck[4])
    item.cb:SetPoint("TOPLEFT", self.p, "TOPLEFT", LAY.COL2_X, self.y)
    self.y = self.y - LAY.DD_H
    return d, item
end

function AutoRotaLayout:Gap(n) self.y = self.y - (n or 8) end

-- Size the scroll child to the content laid out so far; returns the height.
function AutoRotaLayout:Finish()
    local h = -self.y + LAY.BOT_PAD
    self.p:SetHeight(h)
    return h
end

-- Build the scroll frame + child + scrollbar inside the window, and return the
-- child for BuildBody to fill. Mouse wheel and the scrollbar both pan it.
function AutoRotaUI:MakeScroll(f)
    local viewH = SCROLL.WIN_H + SCROLL.TOP - SCROLL.BOTTOM_PAD   -- TOP is negative

    local sf = CreateFrame("ScrollFrame", "ARUI_BodyScroll", f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", SCROLL.LEFT, SCROLL.TOP)
    sf:SetWidth(SCROLL.WIDTH); sf:SetHeight(viewH)

    local child = CreateFrame("Frame", "ARUI_BodyScrollChild", sf)
    child:SetWidth(SCROLL.WIDTH); child:SetHeight(viewH)
    sf:SetScrollChild(child)

    local sb = CreateFrame("Slider", "ARUI_BodyScrollBar", f, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, -16)
    sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 16)
    sb:SetWidth(SCROLL.BAR_W)
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
function AutoRotaUI:UpdateScrollRange()
    local sf, child, sb = self.bodyScroll, self.bodyChild, self.bodyScrollBar
    if not (sf and child and sb) then return end
    local maxScroll = child:GetHeight() - sf:GetHeight()
    if maxScroll < 0 then maxScroll = 0 end
    sb:SetMinMaxValues(0, maxScroll)
    if sb:GetValue() > maxScroll then sb:SetValue(maxScroll) end
    if maxScroll <= 0 then sb:Hide() else sb:Show() end
end


-- ------------------------------------------------------------
-- reusable dialog (input and yes/no), avoids StaticPopup quirks
-- ------------------------------------------------------------
function AutoRotaUI:EnsureDialog()
    if self.dlg then return end
    local d = CreateFrame("Frame", "AutoRotaDialog", UIParent)
    d:SetWidth(300); d:SetHeight(140)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    d:SetBackdrop(BACKDROP)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:Hide()
    local prompt = FS(d, "GameFontNormal", ""); prompt:SetPoint("TOP", d, "TOP", 0, -24)
    prompt:SetWidth(260); prompt:SetJustifyH("CENTER")
    d.prompt = prompt
    local eb = CreateFrame("EditBox", "AutoRotaDialogEdit", d, "InputBoxTemplate")
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
    self.dlg = d
end

function AutoRotaUI:ShowDialog(opts)
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
function AutoRotaUI:Build()
    if self.built then return end

    local scrolled = MOD() and MOD().useScrollLayout
    local f = CreateFrame("Frame", "AutoRotaUIFrame", UIParent)
    f:SetWidth(380); f:SetHeight(scrolled and SCROLL.WIN_H or ((MOD() and MOD().uiHeight) or 520))
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop(BACKDROP)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()
    self.frame = f

    local title = FS(f, "GameFontNormalLarge", "AutoRota" .. (MOD() and (" - " .. (MOD().uiTitle or "")) or "")); title:SetPoint("TOP", f, "TOP", 0, -16); color(title, COL.gold)
    local sub = FS(f, "GameFontDisableSmall", "Pick or create a profile, configure below, then Activate")
    sub:SetPoint("TOP", f, "TOP", 0, -34)
    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton"); xb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

    FS(f, "GameFontNormalSmall", "Profile being edited"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -46)
    self.profileDD = self:CreateDropdown("profile", f, 150, function(v) self:Load(v) end)
    self.profileDD:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -60)
    self.activateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.activateBtn:SetWidth(90); self.activateBtn:SetHeight(22)
    self.activateBtn:SetPoint("LEFT", self.profileDD, "RIGHT", 8, 0)
    self.activateBtn:SetText("Activate")
    self.activateBtn:SetScript("OnClick", function() self:DoActivate() end)

    -- management buttons
    self.newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.newBtn:SetWidth(75); self.newBtn:SetHeight(22); self.newBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -88)
    self.newBtn:SetText("New"); self.newBtn:SetScript("OnClick", function() self:AskNew() end)
    self.renBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.renBtn:SetWidth(85); self.renBtn:SetHeight(22); self.renBtn:SetPoint("LEFT", self.newBtn, "RIGHT", 6, 0)
    self.renBtn:SetText("Rename"); self.renBtn:SetScript("OnClick", function() self:AskRename() end)
    self.delBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.delBtn:SetWidth(75); self.delBtn:SetHeight(22); self.delBtn:SetPoint("LEFT", self.renBtn, "RIGHT", 6, 0)
    self.delBtn:SetText("Delete"); self.delBtn:SetScript("OnClick", function() self:AskDelete() end)

    self.status = FS(f, "GameFontNormalSmall", ""); self.status:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -116)
    self.status:SetWidth(340); self.status:SetJustifyH("LEFT")

    self.saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.saveBtn:SetWidth(90); self.saveBtn:SetHeight(24)
    self.saveBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -110, 16)
    self.saveBtn:SetText("Save")
    self.saveBtn:SetScript("OnClick", function() self:DoSave() end)
    self.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    self.closeBtn:SetWidth(90); self.closeBtn:SetHeight(24)
    self.closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 16)
    self.closeBtn:SetText("Close")
    self.closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- plain language tooltips for new users
    Tip(self.profileDD, "Profile", "The set of seals and spells the rotation uses.", "Switch here to edit a different one.")
    Tip(self.activateBtn, "Activate", "Saves this profile and makes the macro use it.", "The macro always runs the active profile.")
    Tip(self.saveBtn, "Save", "Stores your changes to this profile.", "Does not change which profile the macro uses.")
    Tip(self.closeBtn, "Close", "Closes the window. Unsaved changes are discarded.")
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
function AutoRotaUI:CopyBuf(name)
    local src = AutoRotaDB.profiles[name]
    if not src then return nil end
    return CORE.CopyProfile(CORE, src)
end

function AutoRotaUI:Load(name)
    if not AutoRotaDB.profiles[name] then return end
    self.editing = name
    self.buf = self:CopyBuf(name)
    self:Refresh()
end

function AutoRotaUI:ProfileNameList()
    local list = {}
    for n in pairs(AutoRotaDB.profiles) do table.insert(list, n) end
    table.sort(list)
    return list
end

function AutoRotaUI:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide(); return end
    local pick = AutoRotaDB.active
    if not pick or not AutoRotaDB.profiles[pick] then pick = self:ProfileNameList()[1] end
    if pick then self.editing = pick; self.buf = self:CopyBuf(pick) else self.editing = nil; self.buf = nil end
    self.frame:Show()
    self:Refresh()
end

-- ============================================================
-- refresh (profile bar and validity, then class body)
-- ============================================================
function AutoRotaUI:Refresh()
    if not self.built then return end
    self.loading = true

    local names = self:ProfileNameList()
    local opts = {}
    for i = 1, table.getn(names) do opts[i] = { label = names[i], value = names[i] } end
    self:SetDropdown(self.profileDD, opts, self.editing, self.editing or "(none)", COL.white)

    if not self.buf then
        self.status:SetText("No profile. Use New to create one."); color(self.status, COL.grey)
        self.saveBtn:Disable(); self.activateBtn:Disable()
        self.loading = false
        return
    end

    if MOD() and MOD().RefreshBody then MOD():RefreshBody(self, self.buf) end

    local ok, missing = MOD():ProfileValidity(self.buf)
    if ok then
        self.status:SetText("Profile valid."); color(self.status, COL.green)
        self.saveBtn:Enable(); self.activateBtn:Enable()
    else
        self.status:SetText("Invalid, missing " .. table.concat(missing, ", ")); color(self.status, COL.red)
        self.saveBtn:Disable(); self.activateBtn:Disable()
    end

    self.loading = false
end

-- ------------------------------------------------------------
-- profile management
-- ------------------------------------------------------------
function AutoRotaUI:AskNew()
    self:ShowDialog({
        prompt = "New profile name:", withInput = true, acceptLabel = "Create",
        onAccept = function(txt) self:NewProfile(txt) end,
    })
end

function AutoRotaUI:NewProfile(name)
    name = trim(name)
    if name == "" then DEFAULT_CHAT_FRAME:AddMessage("AutoRota: name required.", 1, 0.5, 0.3); return end
    if AutoRotaDB.profiles[name] then DEFAULT_CHAT_FRAME:AddMessage("AutoRota: '" .. name .. "' already exists.", 1, 0.5, 0.3); return end
    AutoRotaDB.profiles[name] = CORE.CopyProfile(CORE, MOD().templates.starter)
    self.editing = name
    self.buf = self:CopyBuf(name)
    self:Refresh()
end

function AutoRotaUI:AskRename()
    if not self.editing then return end
    self:ShowDialog({
        prompt = "Rename '" .. self.editing .. "' to:", withInput = true, initialText = self.editing, acceptLabel = "Rename",
        onAccept = function(txt) self:RenameProfile(txt) end,
    })
end

function AutoRotaUI:RenameProfile(newName)
    newName = trim(newName)
    if newName == "" or not self.editing then return end
    if newName == self.editing then return end
    if AutoRotaDB.profiles[newName] then DEFAULT_CHAT_FRAME:AddMessage("AutoRota: '" .. newName .. "' already exists.", 1, 0.5, 0.3); return end
    local old = self.editing
    AutoRotaDB.profiles[newName] = AutoRotaDB.profiles[old]
    AutoRotaDB.profiles[old] = nil
    if AutoRotaDB.active == old then AutoRotaDB.active = newName end
    self.editing = newName
    self.buf = self:CopyBuf(newName)
    self:Refresh()
end

function AutoRotaUI:AskDelete()
    if not self.editing then return end
    self:ShowDialog({
        prompt = "Delete profile '" .. self.editing .. "'?", withInput = false,
        acceptLabel = "Yes", cancelLabel = "No",
        onAccept = function() self:DeleteProfile() end,
    })
end

function AutoRotaUI:DeleteProfile()
    if not self.editing then return end
    local name = self.editing
    AutoRotaDB.profiles[name] = nil
    if AutoRotaDB.active == name then AutoRotaDB.active = nil end
    local nxt = self:ProfileNameList()[1]
    if nxt then self.editing = nxt; self.buf = self:CopyBuf(nxt) else self.editing = nil; self.buf = nil end
    self:Refresh()
end

-- ------------------------------------------------------------
-- commit
-- ------------------------------------------------------------
function AutoRotaUI:DoSave()
    if not self.buf or not self.editing then return end
    if not MOD():ProfileValidity(self.buf) then return end
    AutoRotaDB.profiles[self.editing] = CORE.CopyProfile(CORE, self.buf)
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: saved '" .. self.editing .. "'.", 1, 0.8, 0)
    self:Refresh()
end

function AutoRotaUI:DoActivate()
    if not self.buf or not self.editing then return end
    if not MOD():ProfileValidity(self.buf) then return end
    AutoRotaDB.profiles[self.editing] = CORE.CopyProfile(CORE, self.buf)
    AutoRotaDB.active = self.editing
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: activated '" .. self.editing .. "'.", 1, 0.8, 0)
    self:Refresh()
end
