-- ============================================================
-- Aegis_SBR_Pet  -  a small always-on pet readout
--
-- Level, experience toward the next level, and happiness. All of it is in the
-- default Pet Details panel already; the point here is a window small enough to
-- leave on screen, so the state is glanceable instead of something you open a
-- frame to check.
--
-- The border carries the happiness, because that is the part you act on: green
-- happy, yellow content, red unhappy. Colour reaches you across the screen in a
-- way a number does not.
--
-- Toggled from the Hunter panel; visibility, position and scale live in
-- AegisDB.petWindow.
-- ============================================================

Aegis_SBR_Pet = {}
local AP = Aegis_SBR_Pet

local TICK = 0.5          -- the readout changes slowly; twice a second is plenty
local BASE_W = 176
local MIN_SCALE, MAX_SCALE = 0.6, 2.0

-- Border thickness in pixels. The stock tooltip edge is a thin ornamental line
-- and only gets blurry when scaled up, so the border is four solid bars instead
-- - a colour you are meant to read across the room wants to be a block, not a
-- hairline. One number to tune.
local BORDER_W = 2

-- Happiness is 1 unhappy, 2 content, 3 happy. The border takes these; the
-- damage figure beside the label is what the number actually costs you.
local HAPPY = {
    [1] = { label = "Unhappy", r = 0.85, g = 0.15, b = 0.15 },
    [2] = { label = "Content", r = 0.95, g = 0.80, b = 0.10 },
    [3] = { label = "Happy",   r = 0.25, g = 0.80, b = 0.30 },
}

-- When the happiness DROPS, three signals at once, so it is not missed in a
-- fight: the raid-warning sound (a second one, the quest-failed sound, when it
-- drops to Unhappy), a raid-warning text in the middle of the screen, and the
-- window's border flashing white for a few seconds. A rise is silent. Not on
-- the first reading of a pet (login, summon), only on a change while the same
-- pet is out.
local SOUND_WORSE   = "RaidWarning"
local SOUND_UNHAPPY = "igQuestFailed"
local FLASH_SECS    = 5

local COL_BG    = { 0.05, 0.05, 0.07, 0.92 }
local COL_TEXT  = { 0.85, 0.86, 0.90 }
local COL_MUTE  = { 0.55, 0.57, 0.62 }
local COL_TITLE = { 0.55, 0.57, 0.62 }

function AP:DB()
    if not AegisDB then return nil end
    if type(AegisDB.petWindow) ~= "table" then AegisDB.petWindow = {} end
    local db = AegisDB.petWindow
    -- Deliberately no learned timings here. A countdown to the next loyalty
    -- level was built and removed: the client exposes no progress within a
    -- level, so it had to be measured - and a zone change dismisses the pet for
    -- a moment, which is indistinguishable from a level starting. The clock
    -- restarted on every zone line and the estimate was worthless. Loyalty is
    -- shown as the level it is; the game does not know more than that either.
    return db
end

-- Sound on a mood change: on unless switched off (per character).
function AP:SoundOn()
    local db = self:DB()
    return not (db and db.sound == false)
end

function AP:SetSound(on)
    local db = self:DB()
    if db then db.sound = on and true or false end
end

function AP:NoteHappiness(h)
    local pet = UnitName("pet")
    if pet ~= self.lastPet then
        self.lastPet = pet
        self.lastHappy = h
        return
    end
    local before = self.lastHappy
    self.lastHappy = h
    if not (before and h) or h >= before or not self:SoundOn() then return end
    PlaySound(SOUND_WORSE)
    if h == 1 then PlaySound(SOUND_UNHAPPY) end
    local hap = HAPPY[h]
    local msg = (pet or "Pet") .. " is " .. (hap and hap.label or "less happy")
        .. (h == 1 and " - feed it" or "")
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, { r = hap and hap.r or 1, g = hap and hap.g or 0.3, b = hap and hap.b or 0.3 })
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0.3, 0.3)
    end
    self.flashUntil = GetTime() + FLASH_SECS
end

function AP:Enabled()
    local db = self:DB()
    return db and db.shown and true or false
end

-- Loyalty level as a number, plus whatever text the client gives. Two readings
-- are in circulation and both are covered: GetPetLoyalty may hand back a number
-- first, or a single description string with the level in it.
function AP:Loyalty()
    if not GetPetLoyalty then return nil, nil end
    local a, b = GetPetLoyalty()
    local lvl = tonumber(a)
    local text = b
    if not lvl and type(a) == "string" then
        text = a
        local _, _, d = string.find(a, "(%d+)")
        lvl = tonumber(d)
    end
    -- The label the client returns says the level again in words on some
    -- builds: "(Loyalty Level 4) Dependable". The number is printed right
    -- beside it, so a leading parenthetical is dropped - it said nothing new
    -- and cost a line break in a window this narrow.
    if type(text) == "string" then
        text = string.gsub(text, "^%s*%b()%s*", "")
        text = string.gsub(text, "^%s*(.-)%s*$", "%1")
        if text == "" then text = nil end
    end
    return lvl, text
end

-- ------------------------------------------------------------
function AP:Build()
    if self.win then return self.win end
    local f = CreateFrame("Frame", "Aegis_SBR_PetFrame", UIParent)
    f:SetWidth(BASE_W); f:SetHeight(74)
    -- Background only; the border below replaces the backdrop's own edge, which
    -- would otherwise sit under the coloured bars as a second, thinner frame.
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(COL_BG[1], COL_BG[2], COL_BG[3], COL_BG[4])

    local function bar(p1, p2, w, h)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1, f, p1, 0, 0)
        t:SetPoint(p2, f, p2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    f.border = {
        bar("TOPLEFT", "TOPRIGHT", nil, BORDER_W),
        bar("BOTTOMLEFT", "BOTTOMRIGHT", nil, BORDER_W),
        bar("TOPLEFT", "BOTTOMLEFT", BORDER_W, nil),
        bar("TOPRIGHT", "BOTTOMRIGHT", BORDER_W, nil),
    }
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local db = AP:DB()
        if db then
            local point, _, relPoint, x, y = this:GetPoint()
            db.pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    local function line(y, font, col)
        local t = f:CreateFontString(nil, "OVERLAY", font)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", BORDER_W + 6, y)
        t:SetWidth(BASE_W - 20); t:SetJustifyH("LEFT")
        t:SetTextColor(col[1], col[2], col[3])
        return t
    end

    f.nameText  = line(-8,  "GameFontNormalSmall", COL_TEXT)
    f.xpText    = line(-24, "GameFontNormalSmall", COL_MUTE)
    f.happyText = line(-40, "GameFontNormalSmall", COL_TEXT)
    f.loyalText = line(-56, "GameFontNormalSmall", COL_TEXT)

    -- The level sits right-aligned on the name line, so a long pet name cannot
    -- push it out of the window.
    local lvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lvl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(BORDER_W + 6), -8)
    lvl:SetJustifyH("RIGHT")
    lvl:SetTextColor(COL_TITLE[1], COL_TITLE[2], COL_TITLE[3])
    f.levelText = lvl

    local db = self:DB()
    if db and db.scale then f:SetScale(db.scale) end
    if db and db.pos then
        f:SetPoint(db.pos.point or "CENTER", UIParent, db.pos.relPoint or "CENTER",
                   db.pos.x or 0, db.pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end

    f:SetScript("OnUpdate", function()
        AP.elapsed = (AP.elapsed or 0) + (arg1 or 0)
        if AP.elapsed < TICK then return end
        AP.elapsed = 0
        AP:Refresh()
    end)

    f:Hide()
    self.win = f
    return f
end

function AP:BorderColor(r, g, b, a)
    local f = self.win
    if not (f and f.border) then return end
    for i = 1, table.getn(f.border) do
        f.border[i]:SetTexture(r, g, b, a or 1)
    end
end

function AP:Refresh()
    local f = self.win
    if not f or not f:IsShown() then return end

    if not UnitExists("pet") or UnitIsDead("pet") then
        f.nameText:SetText("no pet")
        f.levelText:SetText("")
        f.xpText:SetText("")
        f.happyText:SetText("")
        f.loyalText:SetText("")
        self:BorderColor(0.30, 0.30, 0.33, 0.9)
        self.lastPet = nil
        return
    end

    f.nameText:SetText(UnitName("pet") or "pet")
    f.levelText:SetText("Lv " .. (UnitLevel("pet") or "?"))

    -- Experience is only reported for a pet that still gains it; a pet at the
    -- player's level reads back as zero, and a blank line says that better than
    -- "0 / 0" does.
    local cur, max = 0, 0
    if GetPetExperience then cur, max = GetPetExperience() end
    if max and max > 0 then
        f.xpText:SetText("XP " .. cur .. " / " .. max
            .. "   " .. math.floor(cur / max * 100 + 0.5) .. "%")
    else
        f.xpText:SetText("")
    end

    -- One call, and NOT written as `GetPetHappiness and GetPetHappiness()`:
    -- an `and` expression is truncated to a single value, so the damage figure
    -- would silently come back nil.
    local h, dmg
    if GetPetHappiness then h, dmg = GetPetHappiness() end
    local hap = h and HAPPY[h]
    self:NoteHappiness(hap and h or nil)
    if hap then
        -- The flash after a drop: white on every other tick, the mood colour
        -- between, for FLASH_SECS.
        self.flashOn = (GetTime() < (self.flashUntil or 0)) and not self.flashOn
        if self.flashOn then self:BorderColor(1, 1, 1, 1) else self:BorderColor(hap.r, hap.g, hap.b, 1) end
        f.happyText:SetText(hap.label .. (dmg and ("   " .. dmg .. "% dmg") or ""))
        f.happyText:SetTextColor(hap.r, hap.g, hap.b)

    else
        -- A warlock pet, or any pet without happiness.
        self:BorderColor(0.30, 0.30, 0.33, 0.9)
        f.happyText:SetText("")
    end

    local lvl, ltext = self:Loyalty()
    if lvl then
        f.loyalText:SetText("Loyalty " .. lvl .. (ltext and ("  " .. ltext) or ""))
    else
        f.loyalText:SetText("")
    end
end

function AP:SetShown(on)
    local db = self:DB()
    if db then db.shown = on and true or false end
    local f = self:Build()
    if on then f:Show(); self:Refresh() else f:Hide() end
end

function AP:Toggle()
    self:SetShown(not self:Enabled())
    return self:Enabled()
end

function AP:Restore()
    if self:Enabled() then self:SetShown(true) end
end
