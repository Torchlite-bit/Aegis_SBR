-- ============================================================
-- AutoRota_Minimap  -  draggable minimap button
-- Turtle WoW 1.12 frame API. Opens the shared configuration window
-- (AutoRotaUI:Toggle) on click. Position is stored per character in
-- AutoRotaDB.minimapAngle; visibility in AutoRotaDB.minimapHide.
-- No external libraries: the button rides the minimap edge using plain
-- trig, the same recipe vanilla addons have always used.
-- ============================================================

local DEFAULT_ANGLE = 200   -- degrees around the minimap, lower-left by default
local RADIUS = 80           -- distance from the minimap centre to the button

-- The built-in class crest sheet (4x4 grid, 0.25 steps). We pick the cell
-- matching the player's class so the button wears their class icon, and
-- fall back to a cog for anything unrecognised.
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

local button = CreateFrame("Button", "AutoRotaMinimapButton", Minimap)
button:SetWidth(31); button:SetHeight(31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")

-- icon (set to the class crest at login; cog as a pre-login fallback)
local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetTexture(FALLBACK_ICON)
icon:SetWidth(20); icon:SetHeight(20)
icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)

local function ApplyClassIcon()
    local _, class = UnitClass("player")
    local c = class and CLASS_TCOORDS[class]
    if c then
        icon:SetTexture(CLASS_ICON)
        icon:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        icon:SetTexture(FALLBACK_ICON)
        icon:SetTexCoord(0, 1, 0, 1)
    end
end

-- the standard circular minimap-button border
local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(53); border:SetHeight(53)
border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- ------------------------------------------------------------
-- placement and dragging
-- ------------------------------------------------------------
local function UpdatePos()
    local angle = math.rad(AutoRotaDB and AutoRotaDB.minimapAngle or DEFAULT_ANGLE)
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px = px / scale; py = py / scale
    AutoRotaDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
    UpdatePos()
end

button:SetScript("OnDragStart", function()
    this:LockHighlight()
    this:SetScript("OnUpdate", DragUpdate)
end)
button:SetScript("OnDragStop", function()
    this:UnlockHighlight()
    this:SetScript("OnUpdate", nil)
end)

-- ------------------------------------------------------------
-- click and tooltip
-- ------------------------------------------------------------
button:SetScript("OnClick", function()
    if arg1 == "RightButton" then
        -- right-click runs the bare rotation, handy while configuring
        AutoRota:EvalCommand("")
    else
        if not AutoRotaUI then
            AutoRota:Throttle("UI framework not loaded. AutoRota_UI.lua is missing or mislabeled in your AutoRota folder, reinstall the files.")
            return
        end
        AutoRotaUI:Toggle()
    end
end)

button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("AutoRota", 1, 0.82, 0)
    GameTooltip:AddLine("Left-click: open the configuration panel.", 1, 1, 1)
    GameTooltip:AddLine("Right-click: run the rotation once.", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("/armap to hide or show this button.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ------------------------------------------------------------
-- initialise: read saved position, class icon, and hide state. Runs at
-- ADDON_LOADED and PLAYER_LOGIN so it is robust to reload timing.
-- ------------------------------------------------------------
local function Init()
    if type(AutoRotaDB) ~= "table" then AutoRotaDB = {} end
    if AutoRotaDB.minimapAngle == nil then AutoRotaDB.minimapAngle = DEFAULT_ANGLE end
    ApplyClassIcon()
    UpdatePos()
    if AutoRotaDB.minimapHide then button:Hide() else button:Show() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 ~= "AutoRota" then return end
    Init()
end)

-- Anchor and show the button right away with defaults, so it is visible
-- even before the events above fire (some 1.12 clients skip PLAYER_LOGIN on
-- a /reload, and saved variables may not be ready during file execution).
-- Init() then refines the saved position, class icon, and hide state.
UpdatePos()
if not (AutoRotaDB and AutoRotaDB.minimapHide) then button:Show() end

-- ------------------------------------------------------------
-- /armap toggles visibility (kept separate from /ar so the core needs
-- no changes; see the note in chat for folding it into /ar instead)
-- ------------------------------------------------------------
SLASH_AUTOROTAMAP1 = "/armap"
SlashCmdList["AUTOROTAMAP"] = function()
    if type(AutoRotaDB) ~= "table" then AutoRotaDB = {} end
    AutoRotaDB.minimapHide = not AutoRotaDB.minimapHide
    if AutoRotaDB.minimapHide then button:Hide() else button:Show() end
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: minimap button "
        .. (AutoRotaDB.minimapHide and "hidden (/armap to show)." or "shown."), 1, 0.8, 0)
end
