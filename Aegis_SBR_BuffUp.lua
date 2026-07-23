-- ============================================================
-- Aegis_SBR_BuffUp  -  buff / poison / weapon-enchant upkeep monitor
-- Turtle WoW 1.12 frame API. No external libraries.
-- ============================================================
-- Ported and restyled from the standalone BuffUp addon (Zanthor), folded
-- into Aegis so a single addon covers both the rotation and upkeep alerts.
-- Two INDEPENDENT features, each with its own enable flag so one can run
-- without the other (toggled in the minimap right-click panel):
--   * Buff monitor  (all classes): watch chosen self-buffs and show clickable
--                    rebuff buttons when any is missing. (Phase C.)
--   * Poison control (rogue): weapon-poison presets + a Quick Bar to apply
--                    them, plus rebuff prompts when a poison falls off. Config
--                    lives in the Rogue class panel (consolidated with the
--                    pre-pull poison reminder).
-- Poison application needs a real click (hardware event), so it is always
-- button-driven - never fired from the spammed rotation macro.
-- ============================================================

Aegis_SBR_BuffUp = {}
local ABU = Aegis_SBR_BuffUp

-- Flat-dark palette, mirrored from Aegis_SBR_UI's PAL (those are file-locals,
-- not importable), so the Quick Bar and rebuff buttons match the config window.
local PAL = {
    bg    = {0.055, 0.059, 0.071, 0.97},
    panel = {0.088, 0.096, 0.116, 1.0},
    line  = {0.15,  0.165, 0.196, 1.0},
    ink   = {0.91,  0.90,  0.88},
    mute  = {0.55,  0.56,  0.60},
}

-- Class accent colours, mirrored from Aegis_SBR_UI (those are file-locals).
-- The window always belongs to the player, so their own class token gives the
-- right accent; falls back to gold.
local CLASS_COLORS = {
    WARRIOR = {0.78, 0.61, 0.43}, PALADIN = {0.96, 0.55, 0.73},
    HUNTER  = {0.67, 0.83, 0.45}, ROGUE   = {1.00, 0.96, 0.41},
    PRIEST  = {1.00, 1.00, 1.00}, SHAMAN  = {0.00, 0.44, 0.87},
    MAGE    = {0.41, 0.80, 0.94}, WARLOCK = {0.58, 0.51, 0.79},
    DRUID   = {1.00, 0.49, 0.04},
}
local function classColor()
    local _, class = UnitClass("player")
    return (class and CLASS_COLORS[class]) or {1, 0.82, 0}
end

-- Quick Bar sizing.
local QB_BTN_W = 62
local QB_BTN_H = 30
local QB_BTN_GAP = 3
local QB_HANDLE_W = 12
local QB_MAX_PRESETS = 4
local QB_BAR_H = 3       -- charge/time indicator bar height
local QB_BAR_INSET = 4   -- inset of the bars from the button edge
local QB_HALF_W = math.floor((62 - 2 * 4 - 2) / 2)  -- half-button bar width (QB_BTN_W/INSET), shared by create + render

-- Stat capture: after applying a poison, read its full charges/duration once
-- so the Quick Bar bars have a reference maximum to scale against.
local CAPTURE_DELAY = 1.5    -- wait this long after apply before first read
local CAPTURE_TIMEOUT = 6.0  -- give up after this many seconds

-- Rebuff-button stack sizing.
local BTN_W = 184
local BTN_H = 30
local BTN_START_Y = -210
local BTN_SPACING = 34
local BTN_MAX = 6

-- Known poison duration tiers (ms), longest first - used later for the
-- charge/time bars (Phase D). Kept here so SnapDuration is defined once.
local KNOWN_DURATIONS = { 3600000, 1800000, 900000, 600000 }  -- 60m, 30m, 15m, 10m

-- Runtime state (not saved).
local abu_lastCheck = 0
local abu_pendingRescan = nil
local abu_lastPoisonMH = nil        -- preset index last applied to MH
local abu_lastPoisonOH = nil        -- preset index last applied to OH
local abu_pendingCaptureMH = nil    -- {readyAt, timeoutAt, itemName} after apply
local abu_pendingCaptureOH = nil
local abu_quickBar = nil
local abu_qbButtons = {}
local abu_buttonPool = {}

-- ------------------------------------------------------------
-- Saved state. Nested under AegisDB (per-character already). EnsureDB is
-- idempotent and safe from any entry point before AegisDB.buffup exists.
-- ------------------------------------------------------------
function ABU:EnsureDB()
    if type(AegisDB) ~= "table" then AegisDB = {} end
    local db = AegisDB.buffup
    if type(db) ~= "table" then db = {}; AegisDB.buffup = db end
    if db.buffMonitor == nil then db.buffMonitor = false end
    if db.poisonControl == nil then db.poisonControl = false end
    if type(db.watchList) ~= "table" then db.watchList = {} end
    if type(db.presets) ~= "table" then db.presets = {} end
    if db.watchPoisonMH == nil then db.watchPoisonMH = false end
    if db.watchPoisonOH == nil then db.watchPoisonOH = false end
    if db.quickBarEnabled == nil then db.quickBarEnabled = true end
    if db.quickBarPos == nil then db.quickBarPos = nil end
    if type(db.poisonStats) ~= "table" then db.poisonStats = {} end
    if db.checkInterval == nil then db.checkInterval = 1.0 end
    -- Normalise presets to exactly QB_MAX_PRESETS slots.
    for i = 1, QB_MAX_PRESETS do
        if type(db.presets[i]) ~= "table" then db.presets[i] = { itemName = "", shortLabel = "" } end
        if db.presets[i].itemName == nil then db.presets[i].itemName = "" end
        if db.presets[i].shortLabel == nil then db.presets[i].shortLabel = "" end
    end
    return db
end

-- ------------------------------------------------------------
-- Independent enable flags.
-- ------------------------------------------------------------
function ABU:BuffMonitorEnabled() return self:EnsureDB().buffMonitor == true end
function ABU:PoisonControlEnabled() return self:EnsureDB().poisonControl == true end
function ABU:SetBuffMonitor(on) self:EnsureDB().buffMonitor = (on == true); self:Refresh() end
function ABU:SetPoisonControl(on) self:EnsureDB().poisonControl = (on == true); self:Refresh() end

-- Poison-control sub-settings, edited from the Rogue class panel.
function ABU:WatchPoisonMH() return self:EnsureDB().watchPoisonMH == true end
function ABU:WatchPoisonOH() return self:EnsureDB().watchPoisonOH == true end
function ABU:QuickBarEnabled() return self:EnsureDB().quickBarEnabled == true end
function ABU:SetWatchPoisonMH(on) self:EnsureDB().watchPoisonMH = (on == true); self:Refresh() end
function ABU:SetWatchPoisonOH(on) self:EnsureDB().watchPoisonOH = (on == true); self:Refresh() end
function ABU:SetQuickBarEnabled(on) self:EnsureDB().quickBarEnabled = (on == true); self:Refresh() end

-- Preset accessors for the Rogue config panel.
function ABU:CountPresets()
    local db = self:EnsureDB()
    local n = 0
    for i = 1, QB_MAX_PRESETS do
        if db.presets[i].itemName ~= "" then n = n + 1 end
    end
    return n
end

function ABU:GetPreset(i)
    local db = self:EnsureDB()
    local p = db.presets[i]
    return p.itemName, p.shortLabel
end

function ABU:SetPreset(i, itemName, shortLabel)
    if i < 1 or i > QB_MAX_PRESETS then return end
    local db = self:EnsureDB()
    db.presets[i].itemName = itemName or ""
    db.presets[i].shortLabel = shortLabel or ""
    self:Refresh()
end

function ABU:MaxPresets() return QB_MAX_PRESETS end

-- ------------------------------------------------------------
-- Helpers.
-- ------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd3ffAegis|r: " .. tostring(msg))
end

local abu_scanTip = nil
local function ScanTooltip()
    if not abu_scanTip then
        abu_scanTip = CreateFrame("GameTooltip", "Aegis_SBR_BuffUpScanTip", UIParent, "GameTooltipTemplate")
    end
    return abu_scanTip
end

-- Player can use weapon poisons (item-applied): rogues only. The poison
-- control toggle is labelled "(rogue)" and does nothing for other classes.
local function IsPoisonClass()
    local _, class = UnitClass("player")
    return class == "ROGUE"
end

-- Snap a captured remaining time to the nearest full tier; isFresh true when
-- close to a full tier (used by the Phase-D charge/time bars).
local function SnapDuration(capturedMs)
    for i = 1, table.getn(KNOWN_DURATIONS) do
        local dur = KNOWN_DURATIONS[i]
        if capturedMs > dur * 0.85 then return dur, true end
    end
    return capturedMs, false
end

-- Short label for a preset button. An explicit shortLabel always wins;
-- otherwise auto-abbreviate elegantly. Because the whole bar is poisons, the
-- redundant word "Poison" is dropped and any rank kept, which reads far better
-- than a hard mid-word cut: "Instant Poison VI" -> "Instant VI",
-- "Dissolvent Poison" -> "Dissolvent". Only if it is STILL too long is it
-- trimmed - keeping a trailing rank and never ending on a stray tilde.
local PRESET_MAXLEN = 10
local function PresetLabel(i)
    local db = ABU:EnsureDB()
    local p = db.presets[i]
    if p.shortLabel and p.shortLabel ~= "" then return p.shortLabel end
    local nm = p.itemName
    if not nm or nm == "" then return "" end
    local s = string.gsub(nm, "[Pp]oison", "")
    s = string.gsub(s, "%s+", " ")   -- collapse doubled spaces left by the drop
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    if s == "" then s = nm end
    if string.len(s) <= PRESET_MAXLEN then return s end
    -- Still long: preserve a trailing rank (roman numerals or digits) and
    -- shorten the leading part to fit, trimming any trailing space/punctuation
    -- so it never ends on a stray "-" or space.
    local _, _, rank = string.find(s, "%s+([IVXLCDM%d]+)$")
    if rank then
        local budget = PRESET_MAXLEN - string.len(rank) - 1
        if budget < 1 then budget = 1 end
        local head = string.gsub(string.sub(s, 1, budget), "[%s%p]+$", "")
        return head .. " " .. rank
    end
    return string.gsub(string.sub(s, 1, PRESET_MAXLEN), "[%s%p]+$", "")
end

-- Find a poison item in the bags by (substring) name. Returns bag, slot.
local function FindPoisonInBags(poisonName)
    if not poisonName or poisonName == "" then return nil, nil end
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link and string.find(link, poisonName, 1, true) then return bag, slot end
        end
    end
    return nil, nil
end

-- Which preset (if any) is currently on a hand, by tooltip scan. invSlot 16=MH,
-- 17=OH. Returns preset index or nil.
local function DetectActivePoisonByTooltip(invSlot)
    local db = ABU:EnsureDB()
    if ABU:CountPresets() == 0 then return nil end
    local tt = ScanTooltip()
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    tt:ClearLines()
    tt:SetInventoryItem("player", invSlot)
    local numLines = tt:NumLines() or 0
    for line = 1, numLines do
        local region = getglobal("Aegis_SBR_BuffUpScanTipTextLeft" .. line)
        local text = region and region:GetText()
        if text and text ~= "" then
            for i = 1, QB_MAX_PRESETS do
                local nm = db.presets[i].itemName
                if nm ~= "" and string.find(text, nm, 1, true) then
                    tt:Hide()
                    return i
                end
            end
        end
    end
    tt:Hide()
    return nil
end

-- Hybrid: tooltip scan first (survives /reload), runtime last-applied fallback.
local function GetActivePoisonIndex(hand)
    local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
    local invSlot, runtimeVar
    if hand == "oh" then
        if not hasOH then return nil end
        invSlot = 17; runtimeVar = abu_lastPoisonOH
    else
        if not hasMH then return nil end
        invSlot = 16; runtimeVar = abu_lastPoisonMH
    end
    local idx = DetectActivePoisonByTooltip(invSlot)
    if idx then return idx end
    return runtimeVar
end

-- Apply a preset poison to a hand. MUST be called from a button OnClick
-- (hardware event) - the enchant-replace path is not valid from a script.
function ABU:ApplyPoison(presetIdx, hand)
    local db = self:EnsureDB()
    local p = db.presets[presetIdx]
    if not p or p.itemName == "" then
        Print("|cffff6666Preset " .. presetIdx .. " not configured.|r")
        return
    end
    local bag, slot = FindPoisonInBags(p.itemName)
    if not bag then
        Print("|cffff6666Not in bags:|r " .. p.itemName)
        return
    end
    local invSlot = (hand == "oh") and 17 or 16
    ClearCursor()
    UseContainerItem(bag, slot)
    PickupInventoryItem(invSlot)
    ReplaceEnchant()
    -- Schedule a one-off capture of this poison's full charges/duration if we
    -- don't already have it, so the bars have a reference maximum.
    if not db.poisonStats[p.itemName] then
        local cap = { readyAt = GetTime() + CAPTURE_DELAY, timeoutAt = GetTime() + CAPTURE_TIMEOUT, itemName = p.itemName }
        if hand == "oh" then abu_pendingCaptureOH = cap else abu_pendingCaptureMH = cap end
    end
    if hand == "oh" then abu_lastPoisonOH = presetIdx else abu_lastPoisonMH = presetIdx end
    Print("|cff77dd77Poison:|r " .. p.itemName .. " -> " .. ((hand == "oh") and "Offhand" or "Mainhand"))
end

-- ============================================================
-- Quick Bar (horizontal preset bar; rogue, poison control on)
-- ============================================================
local function CreateQuickBar()
    if abu_quickBar then return abu_quickBar end
    local f = CreateFrame("Frame", "Aegis_SBR_BuffUpQuickBar", UIParent)
    f:SetWidth(QB_HANDLE_W + QB_BTN_W * QB_MAX_PRESETS + QB_BTN_GAP * (QB_MAX_PRESETS - 1) + 8)
    f:SetHeight(QB_BTN_H + 8)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(PAL.bg[1], PAL.bg[2], PAL.bg[3], PAL.bg[4])
    f:SetBackdropBorderColor(PAL.line[1], PAL.line[2], PAL.line[3], 1)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)

    local handle = CreateFrame("Button", nil, f)
    handle:SetWidth(QB_HANDLE_W); handle:SetHeight(QB_BTN_H)
    handle:SetPoint("LEFT", f, "LEFT", 3, 0)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton", "RightButton")
    handle:SetScript("OnDragStart", function() f:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local db = ABU:EnsureDB()
        local point, _, relPoint, x, y = f:GetPoint()
        db.quickBarPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local grip = handle:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    grip:SetPoint("CENTER", handle, "CENTER", 0, 0)
    grip:SetText("|cff555555:::|r")

    for i = 1, QB_MAX_PRESETS do
        local b = CreateFrame("Button", "Aegis_SBR_BuffUpQB" .. i, f)
        b:SetWidth(QB_BTN_W); b:SetHeight(QB_BTN_H)
        if i == 1 then
            b:SetPoint("LEFT", handle, "RIGHT", 3, 0)
        else
            b:SetPoint("LEFT", abu_qbButtons[i - 1], "RIGHT", QB_BTN_GAP, 0)
        end
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.label = label
        local mhInd = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mhInd:SetPoint("LEFT", b, "LEFT", 3, 0)
        b.mhInd = mhInd
        local ohInd = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ohInd:SetPoint("RIGHT", b, "RIGHT", -3, 0)
        b.ohInd = ohInd

        -- Charge (top) + time (bottom) bars, split left half = mainhand,
        -- right half = offhand. Backgrounds are a dark track, the bars scale
        -- against the poison's captured full charges/duration.
        local function bar(anchor, ox, oy)
            local bg = b:CreateTexture(nil, "ARTWORK")
            bg:SetHeight(QB_BAR_H); bg:SetWidth(QB_HALF_W)
            bg:SetPoint(anchor, b, anchor, ox, oy)
            bg:SetTexture(0, 0, 0, 0.4)
            local fill = b:CreateTexture(nil, "OVERLAY")
            fill:SetHeight(QB_BAR_H); fill:SetWidth(QB_HALF_W)
            fill:SetPoint(anchor, bg, anchor, 0, 0)
            return bg, fill
        end
        b.mhChargesBg, b.mhChargesBar = bar("TOPLEFT",     QB_BAR_INSET,  -QB_BAR_INSET)
        b.mhTimeBg,    b.mhTimeBar    = bar("BOTTOMLEFT",  QB_BAR_INSET,   QB_BAR_INSET)
        b.ohChargesBg, b.ohChargesBar = bar("TOPRIGHT",   -QB_BAR_INSET,  -QB_BAR_INSET)
        b.ohTimeBg,    b.ohTimeBar    = bar("BOTTOMRIGHT",-QB_BAR_INSET,   QB_BAR_INSET)
        b.presetIdx = i
        b:SetScript("OnClick", function()
            -- Left = mainhand, right = offhand (mirror of BuffUp).
            local hand = (arg1 == "RightButton") and "oh" or "mh"
            ABU:ApplyPoison(this.presetIdx, hand)
        end)
        b:SetScript("OnEnter", function()
            local nm = ABU:GetPreset(this.presetIdx)
            if nm and nm ~= "" then
                GameTooltip:SetOwner(this, "ANCHOR_TOP")
                GameTooltip:SetText(nm)
                -- Name is matched as a substring, so any rank in the bags
                -- counts. Show which one would actually be applied.
                local bag, slot = FindPoisonInBags(nm)
                if bag then
                    local link = GetContainerItemLink(bag, slot)
                    GameTooltip:AddLine("In bags: " .. (link or "yes") .. " (any rank matches)", 0.5, 1, 0.5)
                else
                    GameTooltip:AddLine("Not in bags", 1, 0.4, 0.4)
                end
                GameTooltip:AddLine("Left-click: mainhand", 0.7, 1, 0.7)
                GameTooltip:AddLine("Right-click: offhand", 0.7, 0.8, 1)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        abu_qbButtons[i] = b
    end

    -- Restore saved position, else default near the bottom centre.
    local db = ABU:EnsureDB()
    f:ClearAllPoints()
    if db.quickBarPos then
        f:SetPoint(db.quickBarPos.point or "CENTER", UIParent, db.quickBarPos.relPoint or "CENTER",
            db.quickBarPos.x or 0, db.quickBarPos.y or 0)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    end
    f:Hide()
    abu_quickBar = f
    return f
end

-- Render one hand's charge (top) + time (bottom) bar for a button, scaling
-- against the poison's captured full charges / duration. Hidden when the hand
-- is not carrying this preset or no stats have been captured yet.
local function RenderBars(chargesBg, chargesBar, timeBg, timeBar, active, stats, curCharges, curExp)
    if not (active and stats) then
        chargesBg:Hide(); chargesBar:Hide(); timeBg:Hide(); timeBar:Hide()
        return
    end
    local chargePct = 0
    if stats.charges and stats.charges > 0 then chargePct = (curCharges or 0) / stats.charges end
    if chargePct > 1 then chargePct = 1 end
    local cW = QB_HALF_W * chargePct; if cW < 1 then cW = 1 end
    chargesBar:SetWidth(cW)
    if chargePct > 0.5 then chargesBar:SetTexture(0.2, 0.9, 0.2, 0.85)
    elseif chargePct > 0.25 then chargesBar:SetTexture(0.9, 0.8, 0.1, 0.85)
    else chargesBar:SetTexture(0.9, 0.2, 0.2, 0.85) end
    local timePct = 0
    if stats.timeMs and stats.timeMs > 0 then timePct = (curExp or 0) / stats.timeMs end
    if timePct > 1 then timePct = 1 end
    local tW = QB_HALF_W * timePct; if tW < 1 then tW = 1 end
    timeBar:SetWidth(tW)
    if timePct > 0.5 then timeBar:SetTexture(0.2, 0.6, 1, 0.85)
    elseif timePct > 0.2 then timeBar:SetTexture(0.4, 0.4, 0.8, 0.85)
    else timeBar:SetTexture(0.6, 0.2, 0.2, 0.85) end
    chargesBg:Show(); chargesBar:Show(); timeBg:Show(); timeBar:Show()
end

local function UpdateQuickBar()
    local db = ABU:EnsureDB()
    local f = abu_quickBar or CreateQuickBar()
    -- Only for rogues, with the feature on, the bar enabled, and presets set.
    if not (db.poisonControl and db.quickBarEnabled and IsPoisonClass()) or ABU:CountPresets() == 0 then
        f:Hide()
        return
    end

    local mhIdx = GetActivePoisonIndex("mh")
    local ohIdx = GetActivePoisonIndex("oh")
    local hasMH, mhExp, mhCharges, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()

    -- Pack only the configured presets, left to right, and size the frame to
    -- exactly that many buttons (empty slots leave no gap).
    local visible = 0
    for i = 1, QB_MAX_PRESETS do
        local b = abu_qbButtons[i]
        local nm = db.presets[i].itemName
        if nm ~= "" then
            visible = visible + 1
            b:ClearAllPoints()
            b:SetPoint("LEFT", f, "LEFT", 4 + QB_HANDLE_W + (visible - 1) * (QB_BTN_W + QB_BTN_GAP), 0)
            b.label:SetText(PresetLabel(i))
            local isMH = (mhIdx == i)
            local isOH = (ohIdx == i)
            local available = (FindPoisonInBags(nm) ~= nil)
            b.mhInd:SetText(isMH and "|cff77dd77M|r" or "")
            b.ohInd:SetText(isOH and "|cff66aaffO|r" or "")
            if isMH and isOH then
                b:SetBackdropColor(0.10, 0.24, 0.13, 0.95); b:SetBackdropBorderColor(0.3, 0.9, 0.45, 0.9); b.label:SetTextColor(0.8, 1, 0.8)
            elseif isMH then
                b:SetBackdropColor(0.08, 0.20, 0.10, 0.95); b:SetBackdropBorderColor(0.3, 0.75, 0.35, 0.8); b.label:SetTextColor(0.75, 1, 0.75)
            elseif isOH then
                b:SetBackdropColor(0.06, 0.11, 0.24, 0.95); b:SetBackdropBorderColor(0.3, 0.5, 0.95, 0.8); b.label:SetTextColor(0.75, 0.85, 1)
            elseif available then
                b:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 0.95); b:SetBackdropBorderColor(PAL.line[1], PAL.line[2], PAL.line[3], 1); b.label:SetTextColor(PAL.ink[1], PAL.ink[2], PAL.ink[3])
            else
                b:SetBackdropColor(0.10, 0.10, 0.10, 0.7); b:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5); b.label:SetTextColor(PAL.mute[1], PAL.mute[2], PAL.mute[3])
            end
            local stats = db.poisonStats[nm]
            RenderBars(b.mhChargesBg, b.mhChargesBar, b.mhTimeBg, b.mhTimeBar, isMH, stats, mhCharges, mhExp)
            RenderBars(b.ohChargesBg, b.ohChargesBar, b.ohTimeBg, b.ohTimeBar, isOH, stats, ohCharges, ohExp)
            b:Show()
        else
            b:Hide()
        end
    end

    f:SetWidth(QB_HANDLE_W + QB_BTN_W * visible + QB_BTN_GAP * (visible - 1) + 8)
    f:Show()
end

-- ============================================================
-- Buff monitor (all classes): detection + watch-list management
-- ============================================================

-- Highest spellbook slot matching a spell name (for casting a watched buff).
local function FindSpellInBook(spellName)
    if not spellName or spellName == "" then return nil end
    local last = nil
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == spellName then last = i end
        i = i + 1
        if i > 400 then break end
    end
    return last
end

-- Is a watched buff currently up? Matches the spell name via the buff tooltip
-- first (rank/locale proof), then the icon texture as a fallback.
local function PlayerHasBuff(texture, id, spellName)
    local tt = ScanTooltip()
    for i = 1, 32 do
        local tex, _, bid = UnitBuff("player", i)
        if not tex then break end
        if id and bid and bid == id then return true end
        if spellName and spellName ~= "" then
            tt:SetOwner(UIParent, "ANCHOR_NONE")
            tt:ClearLines()
            tt:SetUnitBuff("player", i)
            local region = getglobal("Aegis_SBR_BuffUpScanTipTextLeft1")
            local name = region and region:GetText()
            tt:Hide()
            if name and name == spellName then return true end
        elseif texture and tex and string.find(tex, texture) then
            return true
        end
    end
    return false
end

-- Snapshot the player's current buffs (texture, id, resolved spell name).
local function ScanPlayerBuffs()
    local out = {}
    local tt = ScanTooltip()
    for i = 1, 32 do
        local tex, _, bid = UnitBuff("player", i)
        if not tex then break end
        tt:SetOwner(UIParent, "ANCHOR_NONE")
        tt:ClearLines()
        tt:SetUnitBuff("player", i)
        local region = getglobal("Aegis_SBR_BuffUpScanTipTextLeft1")
        local name = region and region:GetText()
        tt:Hide()
        table.insert(out, { texture = tex, id = bid, spellName = name or "" })
    end
    return out
end

-- Watch-list mutators (used by the config window).
function ABU:AddWatch(entry)
    local db = self:EnsureDB()
    -- Skip duplicates by spell name (or texture when unnamed).
    for i = 1, table.getn(db.watchList) do
        local w = db.watchList[i]
        if entry.spellName ~= "" and w.spellName == entry.spellName then return end
        if entry.spellName == "" and w.texture == entry.texture then return end
    end
    table.insert(db.watchList, {
        texture = entry.texture, id = entry.id,
        spellName = entry.spellName or "",
        label = (entry.spellName ~= "" and entry.spellName) or "Buff",
    })
    self:Refresh()
end

function ABU:RemoveWatch(index)
    local db = self:EnsureDB()
    table.remove(db.watchList, index)
    self:Refresh()
end

function ABU:WatchList() return self:EnsureDB().watchList end
function ABU:ScanBuffs() return ScanPlayerBuffs() end

-- On SPELLS_CHANGED, refresh stored ids / names for watched buffs so a newly
-- learned rank stays matched.
function ABU:RescanBuffList()
    local db = self:EnsureDB()
    if table.getn(db.watchList) == 0 then return end
    local cur = ScanPlayerBuffs()
    for i = 1, table.getn(db.watchList) do
        local w = db.watchList[i]
        for j = 1, table.getn(cur) do
            local c = cur[j]
            if w.texture and c.texture and string.find(c.texture, w.texture) then
                if c.spellName ~= "" and (not w.spellName or w.spellName == "") then
                    w.spellName = c.spellName; w.label = c.spellName
                end
                if c.id and c.id ~= w.id then w.id = c.id end
                break
            end
        end
    end
end

-- ============================================================
-- Rebuff-button stack (missing poison / missing watched buffs)
-- ============================================================
local function GetButton(index)
    if abu_buttonPool[index] then return abu_buttonPool[index] end
    local b = CreateFrame("Button", "Aegis_SBR_BuffUpBtn" .. index, UIParent)
    b:SetWidth(BTN_W); b:SetHeight(BTN_H)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    b:SetMovable(true); b:EnableMouse(true)
    b:RegisterForDrag("RightButton")
    b:SetScript("OnDragStart", function() this:StartMoving() end)
    b:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    b:SetFrameStrata("DIALOG")
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text = txt
    b:Hide()
    abu_buttonPool[index] = b
    return b
end

local function StyleButton(b, style)
    if style == "poison" then
        b:SetBackdropColor(0.13, 0.05, 0.18, 0.95); b:SetBackdropBorderColor(0.7, 0.4, 0.9, 0.9)
    else
        b:SetBackdropColor(0.05, 0.13, 0.18, 0.95); b:SetBackdropBorderColor(0.4, 0.75, 0.95, 0.9)
    end
end

local function HideAllButtons()
    for i = 1, BTN_MAX do
        if abu_buttonPool[i] then abu_buttonPool[i]:Hide() end
    end
end

-- Poison name to reapply for a rebuff prompt: the last one used on that hand,
-- else the first configured preset.
local function GetRebuffPoisonName(hand)
    local db = ABU:EnsureDB()
    local lastIdx = (hand == "oh") and abu_lastPoisonOH or abu_lastPoisonMH
    if lastIdx and db.presets[lastIdx] and db.presets[lastIdx].itemName ~= "" then
        return db.presets[lastIdx].itemName, lastIdx
    end
    for i = 1, QB_MAX_PRESETS do
        if db.presets[i].itemName ~= "" then return db.presets[i].itemName, i end
    end
    return nil, nil
end

local function UpdateButtons()
    local db = ABU:EnsureDB()
    if UnitIsDeadOrGhost("player") then HideAllButtons(); return end

    local missing = {}

    -- Poison rebuff prompts (rogue, poison control on).
    if db.poisonControl and IsPoisonClass() then
        local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
        if db.watchPoisonMH and not hasMH then
            local nm, idx = GetRebuffPoisonName("mh")
            if nm and FindPoisonInBags(nm) then
                table.insert(missing, { label = "|cffdd99ffPoison: Mainhand|r", style = "poison",
                    action = function() ABU:ApplyPoison(idx, "mh") end })
            end
        end
        if db.watchPoisonOH and not hasOH then
            local nm, idx = GetRebuffPoisonName("oh")
            if nm and FindPoisonInBags(nm) then
                table.insert(missing, { label = "|cffdd99ffPoison: Offhand|r", style = "poison",
                    action = function() ABU:ApplyPoison(idx, "oh") end })
            end
        end
    end

    -- Watched-buff rebuff prompts (all classes, buff monitor on).
    if db.buffMonitor then
        for i = 1, table.getn(db.watchList) do
            local w = db.watchList[i]
            if not PlayerHasBuff(w.texture, w.id, w.spellName) then
                local sp = w.spellName
                if sp and sp ~= "" then
                    table.insert(missing, { label = "|cff88ddffBuff: " .. sp .. "|r", style = "buff",
                        action = function()
                            local id = FindSpellInBook(sp)
                            if id then CastSpell(id, BOOKTYPE_SPELL) else CastSpellByName(sp) end
                        end })
                end
            end
        end
    end

    local count = table.getn(missing)
    if count > BTN_MAX then count = BTN_MAX end
    for i = 1, count do
        local b = GetButton(i)
        local data = missing[i]
        b:ClearAllPoints()
        b:SetPoint("TOP", UIParent, "TOP", 0, BTN_START_Y - (i - 1) * BTN_SPACING)
        StyleButton(b, data.style)
        b.text:SetText(data.label)
        b.buffAction = data.action
        b:SetScript("OnClick", function() if this.buffAction then this.buffAction() end end)
        b:Show()
    end
    for i = count + 1, BTN_MAX do
        if abu_buttonPool[i] then abu_buttonPool[i]:Hide() end
    end
end

-- ============================================================
-- Buff monitor config window (opened from the minimap panel)
-- ============================================================
local CFG_ROW_H = 18
local CFG_WATCH_MAX = 8
local CFG_SCAN_MAX = 12

local function cfgRow(parent, y)
    local r = CreateFrame("Button", nil, parent)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
    r:SetHeight(CFG_ROW_H)
    local hl = r:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(r); hl:SetTexture(1, 1, 1, 0.06); hl:Hide()
    local t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", r, "LEFT", 4, 0); t:SetJustifyH("LEFT")
    r.text = t
    r:SetScript("OnEnter", function() hl:Show() end)
    r:SetScript("OnLeave", function() hl:Hide() end)
    r:Hide()
    return r
end

function ABU:CreateConfigWindow()
    if self.cfgWin then return self.cfgWin end
    local w = CreateFrame("Frame", "Aegis_SBR_BuffUpConfig", UIParent)
    w:SetWidth(300)
    w:SetHeight(30 + 20 + CFG_WATCH_MAX * CFG_ROW_H + 28 + CFG_SCAN_MAX * CFG_ROW_H + 16)
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    w:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local cc = classColor()
    w:SetBackdropColor(PAL.bg[1], PAL.bg[2], PAL.bg[3], 0.98)
    w:SetBackdropBorderColor(cc[1], cc[2], cc[3], 1)   -- class-coloured frame
    w:SetFrameStrata("DIALOG")
    w:EnableMouse(true); w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function() w:StartMoving() end)
    w:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
    w:Hide()

    -- Class-tinted title bar strip across the top, plus a hairline under it.
    local titleBar = w:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(22)
    titleBar:SetTexture(cc[1], cc[2], cc[3], 0.14)
    local accent = w:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -26)
    accent:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -26)
    accent:SetHeight(1)
    accent:SetTexture(cc[1], cc[2], cc[3], 0.8)

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("Buff monitor")
    title:SetTextColor(cc[1], cc[2], cc[3])

    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() w:Hide() end)

    local watchLbl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    watchLbl:SetPoint("TOPLEFT", 12, -30)
    watchLbl:SetText("|cffaaccffWatched buffs|r (click to remove)")

    w.watchRows = {}
    local y = -48
    for i = 1, CFG_WATCH_MAX do
        w.watchRows[i] = cfgRow(w, y)
        y = y - CFG_ROW_H
    end

    local scanLbl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanLbl:SetPoint("TOPLEFT", 12, y - 6)
    scanLbl:SetText("|cffaaccffYour current buffs|r (click to watch)")

    local rescan = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    rescan:SetWidth(64); rescan:SetHeight(18)
    rescan:SetPoint("TOPRIGHT", -12, y - 4)
    rescan:SetText("Rescan")
    rescan:SetScript("OnClick", function() ABU:RefreshConfigWindow() end)

    w.scanRows = {}
    y = y - 24
    for i = 1, CFG_SCAN_MAX do
        w.scanRows[i] = cfgRow(w, y)
        y = y - CFG_ROW_H
    end

    self.cfgWin = w
    return w
end

function ABU:RefreshConfigWindow()
    local w = self.cfgWin
    if not w then return end
    local db = self:EnsureDB()

    -- Watched list (click to remove).
    for i = 1, CFG_WATCH_MAX do
        local row = w.watchRows[i]
        local entry = db.watchList[i]
        if entry then
            row.text:SetText("|cffff8888x|r  " .. (entry.label or entry.spellName or "Buff"))
            row.idx = i
            row:SetScript("OnClick", function() ABU:RemoveWatch(this.idx); ABU:RefreshConfigWindow() end)
            row:Show()
        else
            row:Hide()
        end
    end

    -- Current buffs (click to add), skipping ones already watched.
    local cur = ScanPlayerBuffs()
    local shown = 0
    for i = 1, table.getn(cur) do
        local c = cur[i]
        local already = false
        for j = 1, table.getn(db.watchList) do
            local wtc = db.watchList[j]
            if (c.spellName ~= "" and wtc.spellName == c.spellName)
                or (c.spellName == "" and wtc.texture == c.texture) then already = true; break end
        end
        if not already and shown < CFG_SCAN_MAX then
            shown = shown + 1
            local row = w.scanRows[shown]
            row.text:SetText("|cff88ff88+|r  " .. ((c.spellName ~= "" and c.spellName) or "(unnamed icon)"))
            row.entry = c
            row:SetScript("OnClick", function() ABU:AddWatch(this.entry); ABU:RefreshConfigWindow() end)
            row:Show()
        end
    end
    for i = shown + 1, CFG_SCAN_MAX do w.scanRows[i]:Hide() end
end

function ABU:ToggleConfigWindow()
    local w = self:CreateConfigWindow()
    if w:IsShown() then w:Hide(); return end
    self:RefreshConfigWindow()
    w:Show(); w:Raise()
end

-- ------------------------------------------------------------
-- Refresh: dispatch to the feature renderers, gated per flag.
-- ------------------------------------------------------------
function ABU:Refresh()
    local db = self:EnsureDB()
    if db.poisonControl then
        UpdateQuickBar()
    elseif abu_quickBar then
        abu_quickBar:Hide()
    end
    UpdateButtons()
end

-- ------------------------------------------------------------
-- Driver: one throttled OnUpdate that fans out to the renderers.
-- ------------------------------------------------------------
local abu_frame = CreateFrame("Frame", "Aegis_SBR_BuffUpFrame")
abu_frame:RegisterEvent("VARIABLES_LOADED")
abu_frame:RegisterEvent("SPELLS_CHANGED")

abu_frame:SetScript("OnUpdate", function()
    local db = ABU:EnsureDB()
    if not (db.buffMonitor or db.poisonControl) then
        if abu_quickBar and abu_quickBar:IsShown() then abu_quickBar:Hide() end
        return
    end
    local now = GetTime()
    local interval = db.checkInterval or 1.0
    if now - abu_lastCheck < interval then return end
    abu_lastCheck = now
    if abu_pendingRescan and now >= abu_pendingRescan then
        abu_pendingRescan = nil
        ABU:RescanBuffList()
    end

    -- Capture a freshly applied poison's full charges/duration (retry until
    -- the enchant reads close to a full tier, or give up after the timeout).
    local hasMH, mhExp, mhCharges, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()
    if abu_pendingCaptureMH and now >= abu_pendingCaptureMH.readyAt then
        if now > abu_pendingCaptureMH.timeoutAt then
            abu_pendingCaptureMH = nil
        elseif hasMH and mhCharges and mhCharges > 0 and mhExp and mhExp > 0 then
            local snapped, isFresh = SnapDuration(mhExp)
            if isFresh then
                db.poisonStats[abu_pendingCaptureMH.itemName] = { charges = mhCharges, timeMs = snapped }
                abu_pendingCaptureMH = nil
            end
        end
    end
    if abu_pendingCaptureOH and now >= abu_pendingCaptureOH.readyAt then
        if now > abu_pendingCaptureOH.timeoutAt then
            abu_pendingCaptureOH = nil
        elseif hasOH and ohCharges and ohCharges > 0 and ohExp and ohExp > 0 then
            local snapped, isFresh = SnapDuration(ohExp)
            if isFresh then
                db.poisonStats[abu_pendingCaptureOH.itemName] = { charges = ohCharges, timeMs = snapped }
                abu_pendingCaptureOH = nil
            end
        end
    end

    ABU:Refresh()
end)

abu_frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        ABU:EnsureDB()
        return
    end
    if event == "SPELLS_CHANGED" then
        if not abu_pendingRescan then abu_pendingRescan = GetTime() + 3 end
        return
    end
end)
