-- ============================================================
-- AutoRota_Minimap  -  draggable minimap button + addon options
-- Turtle WoW 1.12 frame API. No external libraries.
--   * Left-click  : open the class configuration window (AutoRotaUI:Toggle).
--   * Right-click : open a small options panel (self-targeting toggle plus a
--                   shortcut to the config window).
--   * Drag        : ride the minimap edge; position saved per character in
--                   AutoRotaDB.minimapAngle, visibility in AutoRotaDB.minimapHide.
-- The button wears the player's class crest, falling back to a cog.
-- ============================================================

AutoRotaMinimap = {}
local AM = AutoRotaMinimap

local DEFAULT_ANGLE = 200   -- degrees around the minimap, lower-left by default
local RADIUS = 80           -- distance from the minimap centre to the button

-- The built-in class crest sheet (4x4 grid, 0.25 steps). We pick the cell
-- matching the player's class so the button wears their class icon, and fall
-- back to a cog for anything unrecognised.
local CLASS_ICON = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local CLASS_TCOORDS = {
    WARRIOR = { 0,    0.25, 0,    0.25 },
    MAGE    = { 0.25, 0.5,  0,    0.25 },
    ROGUE   = { 0.5,  0.75, 0,    0.25 },
    DRUID   = { 0.75, 1.0,  0,    0.25 },
    HUNTER  = { 0,    0.25, 0.25, 0.5  },
    SHAMAN  = { 0.25, 0.5,  0.25, 0.5  },
    PRIEST  = { 0.5,  0.75, 0.25, 0.5  },
    WARLOCK = { 0.75, 1.0,  0.25, 0.5  },
    PALADIN = { 0,    0.25, 0.5,  0.75 },
}

-- ------------------------------------------------------------
-- placement, dragging, and the class icon
-- ------------------------------------------------------------
local function placeButton()
    local angle = math.rad((AutoRotaDB and AutoRotaDB.minimapAngle) or DEFAULT_ANGLE)
    AM.button:ClearAllPoints()
    AM.button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

local function dragUpdate()
    local cx, cy = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px = px / scale; py = py / scale
    if AutoRotaDB then AutoRotaDB.minimapAngle = math.deg(math.atan2(py - cy, px - cx)) end
    placeButton()
end

local function applyClassIcon()
    local _, class = UnitClass("player")
    local c = class and CLASS_TCOORDS[class]
    if c then
        AM.icon:SetTexture(CLASS_ICON)
        AM.icon:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        AM.icon:SetTexture(FALLBACK_ICON)
        AM.icon:SetTexCoord(0, 1, 0, 1)
    end
end

-- ============================================================
-- shared group-member picker popup, used by the assist-target row below.
-- Lists raid1-40 while in a raid, else party1-4 plus the player. Only feeds
-- a NAME into the edit box; the actual assist logic (AutoRota:RunAssist)
-- re-resolves the unit and matches by GUID every press, so a stale or
-- same-named pick here can never cause it to track the wrong mob.
-- ============================================================
local pickerFrame = nil

local function showGroupPicker(anchorFrame, onPick)
    if not pickerFrame then
        local pf = CreateFrame("Frame", "AutoRotaGroupPicker", UIParent)
        pf:SetWidth(150)
        pf:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        pf:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        pf:SetBackdropBorderColor(0.5, 0.5, 0.7, 0.9)
        pf:SetFrameStrata("TOOLTIP")
        pf:EnableMouse(true)
        pf:Hide()
        pf.rows = {}
        for i = 1, 40 do
            local row = CreateFrame("Button", nil, pf)
            row:SetPoint("TOPLEFT", pf, "TOPLEFT", 4, -4 - (i - 1) * 16)
            row:SetWidth(142); row:SetHeight(14)
            local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.text = t
            row:SetScript("OnEnter", function() this.text:SetTextColor(0.4, 1, 0.6); pf.mouseInside = true end)
            row:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1); pf.mouseInside = false end)
            row:Hide()
            pf.rows[i] = row
        end
        -- Close automatically once the mouse has been outside for 2 seconds.
        pf:SetScript("OnUpdate", function()
            if not this:IsVisible() then return end
            if this.mouseInside then this.closeTimer = nil; return end
            if not this.closeTimer then this.closeTimer = GetTime() end
            if GetTime() - this.closeTimer > 2 then this:Hide(); this.closeTimer = nil end
        end)
        pf:SetScript("OnEnter", function() this.mouseInside = true end)
        pf:SetScript("OnLeave", function() this.mouseInside = false end)
        pickerFrame = pf
    end

    local pf = pickerFrame
    if pf:IsShown() and pf.currentAnchor == anchorFrame then
        pf:Hide()
        return
    end
    pf.currentAnchor = anchorFrame
    pf.mouseInside = true
    pf.closeTimer = nil

    local members = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local n = UnitName("raid" .. i)
            if n then table.insert(members, n) end
        end
    else
        local pn = UnitName("player")
        if pn then table.insert(members, pn) end
        for i = 1, 4 do
            local n = UnitName("party" .. i)
            if n then table.insert(members, n) end
        end
    end

    if table.getn(members) == 0 then
        pf:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("AutoRota: no group members found.", 1, 0.5, 0.3)
        return
    end

    pf:ClearAllPoints()
    pf:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 2)

    local count = 0
    for i = 1, 40 do pf.rows[i]:Hide() end
    for i, name in ipairs(members) do
        count = count + 1
        pf.rows[i].text:SetText(name)
        pf.rows[i].text:SetTextColor(1, 1, 1)
        pf.rows[i].memberName = name
        pf.rows[i]:SetScript("OnClick", function()
            onPick(this.memberName)
            pf:Hide()
        end)
        pf.rows[i]:Show()
    end
    pf:SetHeight(count * 16 + 8)
    pf:Show()
end

-- ============================================================
-- options panel (right-click): addon-wide, non class-specific options
-- ============================================================
local function buildPanel()
    local p = CreateFrame("Frame", "AutoRotaMinimapPanel", UIParent)
    p:SetWidth(232); p:SetHeight(214)
    p:SetFrameStrata("DIALOG")
    p:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    -- match the config window's flat dark skin
    p:SetBackdropColor(0.088, 0.096, 0.116, 0.98)
    p:SetBackdropBorderColor(0.15, 0.165, 0.196, 1)
    p:EnableMouse(true)
    p:Hide()

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("AutoRota options")

    local modeLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT", 12, -30)
    modeLabel:SetText("Targeting")

    -- Three mutually exclusive radios. Each one, on click, just writes its
    -- own mode to AutoRotaDB and re-syncs all three from that single source
    -- of truth (RefreshPanel), rather than manually unchecking siblings.
    local function makeRadio(yOff, text, mode)
        local r = CreateFrame("CheckButton", nil, p, "UIRadioButtonTemplate")
        r:SetWidth(16); r:SetHeight(16)
        r:SetPoint("TOPLEFT", 14, yOff)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", r, "RIGHT", 4, 0)
        lbl:SetText(text)
        r.mode = mode
        r:SetScript("OnClick", function()
            if AutoRotaDB then AutoRotaDB.targetMode = this.mode end
            AM:RefreshPanel()
        end)
        return r
    end

    p.autoRadio   = makeRadio(-48, "Auto (nearest enemy)", "auto")
    p.manualRadio = makeRadio(-66, "Manual (defer to me / assist addon)", "manual")
    p.assistRadio = makeRadio(-84, "Assist:", "assist")

    -- Assist target: a name (typed or picked), matched to a live group unit
    -- and then to that unit's target by GUID every press - see RunAssist.
    local edit = CreateFrame("EditBox", "AutoRotaAssistEdit", p, "InputBoxTemplate")
    edit:SetWidth(112); edit:SetHeight(18)
    edit:SetAutoFocus(false)
    edit:SetPoint("LEFT", p.assistRadio, "RIGHT", 44, 0)
    edit:SetScript("OnEnterPressed", function()
        local txt = edit:GetText()
        if AutoRotaDB then
            AutoRotaDB.assistTarget = txt
            if txt ~= "" then AutoRotaDB.targetMode = "assist" end
        end
        AM:RefreshPanel()
        edit:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    p.assistEdit = edit

    local pickBtn = CreateFrame("Button", nil, p)
    pickBtn:SetWidth(18); pickBtn:SetHeight(18)
    pickBtn:SetPoint("LEFT", edit, "RIGHT", 4, 0)
    pickBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    pickBtn:SetBackdropColor(0.15, 0.15, 0.25, 0.9)
    pickBtn:SetBackdropBorderColor(0.4, 0.4, 0.6, 0.7)
    local pickText = pickBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pickText:SetPoint("CENTER", pickBtn, "CENTER", 0, 0)
    pickText:SetText("|cff88ccffP|r")
    pickBtn:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.6, 0.6, 0.8, 1)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Pick a group member")
        GameTooltip:Show()
    end)
    pickBtn:SetScript("OnLeave", function()
        this:SetBackdropBorderColor(0.4, 0.4, 0.6, 0.7)
        GameTooltip:Hide()
    end)
    pickBtn:SetScript("OnClick", function()
        showGroupPicker(pickBtn, function(name)
            p.assistEdit:SetText(name)
            if AutoRotaDB then
                AutoRotaDB.assistTarget = name
                AutoRotaDB.targetMode = "assist"
            end
            AM:RefreshPanel()
        end)
    end)

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -108)
    hint:SetWidth(208)
    hint:SetJustifyH("LEFT")
    hint:SetText("Assist mirrors that player's target by GUID, not by name - a same-named mob from another group is never mistaken for theirs.")

    local cfg = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cfg:SetWidth(208); cfg:SetHeight(22)
    cfg:SetPoint("BOTTOM", 0, 12)
    cfg:SetText("Open rotation config")
    cfg:SetScript("OnClick", function()
        p:Hide()
        if AutoRotaUI then AutoRotaUI:Toggle() end
    end)

    AM.panel = p
end

-- Re-sync all three radios and the assist edit box from AutoRotaDB.
function AM:RefreshPanel()
    local p = self.panel
    if not p then return end
    local mode = AutoRota and AutoRota:TargetMode() or "auto"
    p.autoRadio:SetChecked(mode == "auto")
    p.manualRadio:SetChecked(mode == "manual")
    p.assistRadio:SetChecked(mode == "assist")
    p.assistEdit:SetText((AutoRotaDB and AutoRotaDB.assistTarget) or "")
end

function AM:TogglePanel()
    if not self.panel then return end
    if self.panel:IsShown() then self.panel:Hide(); return end
    self:RefreshPanel()
    self.panel:ClearAllPoints()
    self.panel:SetPoint("TOPRIGHT", self.button, "BOTTOMLEFT", 4, 0)
    self.panel:Show()
end

-- ============================================================
-- the button
-- ============================================================
local function buildButton()
    local b = CreateFrame("Button", "AutoRotaMinimapButton", Minimap)
    b:SetWidth(31); b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)
    AM.button = b

    -- icon (class crest at login; cog as a pre-login fallback)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(FALLBACK_ICON)
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
    AM.icon = icon

    -- the standard circular minimap-button border
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(53); border:SetHeight(53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            AM:TogglePanel()
        else
            if AM.panel then AM.panel:Hide() end
            if AutoRotaUI then
                AutoRotaUI:Toggle()
            else
                AutoRota:Throttle("UI framework not loaded. AutoRota_UI.lua is missing or mislabeled in your AutoRota folder, reinstall the files.")
            end
        end
    end)

    b:SetScript("OnDragStart", function() this:LockHighlight(); this:SetScript("OnUpdate", dragUpdate) end)
    b:SetScript("OnDragStop", function() this:UnlockHighlight(); this:SetScript("OnUpdate", nil) end)

    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("AutoRota", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: configure rotation.", 1, 1, 1)
        GameTooltip:AddLine("Right-click: addon options.", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("/armap or /ar minimap to hide or show.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Show or hide the button, remembered across sessions. Called by /ar minimap
-- (through the core) and by /armap. Returns the new hidden state.
function AM:ToggleShown()
    if type(AutoRotaDB) ~= "table" then AutoRotaDB = {} end
    AutoRotaDB.minimapHide = not AutoRotaDB.minimapHide
    if self.button then
        if AutoRotaDB.minimapHide then self.button:Hide() else self.button:Show() end
    end
    return AutoRotaDB.minimapHide
end

-- ============================================================
-- initialise: refine saved position, class icon, and hide state. Runs at
-- ADDON_LOADED and PLAYER_LOGIN so it is robust to reload timing.
-- ============================================================
local function init()
    if type(AutoRotaDB) ~= "table" then AutoRotaDB = {} end
    if AutoRotaDB.minimapAngle == nil then AutoRotaDB.minimapAngle = DEFAULT_ANGLE end
    applyClassIcon()
    placeButton()
    if AutoRotaDB.minimapHide then AM.button:Hide() else AM.button:Show() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 ~= "AutoRota" then return end
    init()
end)

-- Build and anchor the button right away with defaults, so it is visible even
-- before the events above fire (some 1.12 clients skip PLAYER_LOGIN on a
-- /reload, and saved variables may not be ready during file execution). init()
-- then refines the saved position, class icon, and hide state.
buildButton()
buildPanel()
placeButton()
if not (AutoRotaDB and AutoRotaDB.minimapHide) then AM.button:Show() end

-- /armap toggles visibility (kept as a convenience alongside /ar minimap).
SLASH_AUTOROTAMAP1 = "/armap"
SlashCmdList["AUTOROTAMAP"] = function()
    local hidden = AM:ToggleShown()
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: minimap button "
        .. (hidden and "hidden (/armap to show)." or "shown."), 1, 0.8, 0)
end
