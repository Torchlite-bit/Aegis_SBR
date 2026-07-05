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
-- options panel (right-click): addon-wide, non class-specific options
-- ============================================================
local function buildPanel()
    local p = CreateFrame("Frame", "AutoRotaMinimapPanel", UIParent)
    p:SetWidth(232); p:SetHeight(104)
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

    local acq = CreateFrame("CheckButton", "AutoRotaMinimapAcquire", p, "UICheckButtonTemplate")
    acq:SetWidth(22); acq:SetHeight(22)
    acq:SetPoint("TOPLEFT", 10, -32)
    local acqLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    acqLabel:SetPoint("LEFT", acq, "RIGHT", 2, 0)
    acqLabel:SetText("Auto target (acquire nearest enemy)")
    acq:SetScript("OnClick", function()
        if AutoRotaDB then AutoRotaDB.acquire = acq:GetChecked() and true or false end
    end)
    p.acq = acq

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -58)
    hint:SetText("Off lets a separate assist addon set the target.")

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

function AM:TogglePanel()
    if not self.panel then return end
    if self.panel:IsShown() then self.panel:Hide(); return end
    self.panel.acq:SetChecked(not (AutoRotaDB and AutoRotaDB.acquire == false))
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
