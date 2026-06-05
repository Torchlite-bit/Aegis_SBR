-- ============================================================
-- Class_Warlock_UI  -  warlock window body for AutoRota
-- Builds and binds only the warlock specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.WARLOCK

-- ============================================================
-- build body (warlock controls)
-- ============================================================
function M:BuildBody(ui, f)
    -- Damage over time
    ui:FS(f, "GameFontNormal", "Damage over time"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    self.immoCB = ui:CreateCheck("useImmolate", f, "Immolate", "Immolate", function(on) if ui.buf then ui.buf.useImmolate = on; ui:Refresh() end end)
    self.immoCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -166)
    self.corrCB = ui:CreateCheck("useCorruption", f, "Corruption", "Corruption", function(on) if ui.buf then ui.buf.useCorruption = on; ui:Refresh() end end)
    self.corrCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -166)
    self.siphCB = ui:CreateCheck("useSiphonLife", f, "Siphon Life", "Siphon Life", function(on) if ui.buf then ui.buf.useSiphonLife = on; ui:Refresh() end end)
    self.siphCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -190)

    ui:FS(f, "GameFontNormalSmall", "Curse"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -216)
    self.curseDD = ui:CreateDropdown("curse", f, 210, function(v) if ui.buf then ui.buf.curse = v; ui:Refresh() end end)
    self.curseDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -214)

    -- Filler and pet
    ui:FS(f, "GameFontNormal", "Filler and pet"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -248)
    ui:FS(f, "GameFontNormalSmall", "Filler"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -274)
    self.fillerDD = ui:CreateDropdown("filler", f, 210, function(v) if ui.buf then ui.buf.filler = v; ui:Refresh() end end)
    self.fillerDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -272)
    self.petCB = ui:CreateCheck("petAttack", f, "Send pet to attack", nil, function(on) if ui.buf then ui.buf.petAttack = on; ui:Refresh() end end)
    self.petCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -300)

    -- Mana (Life Tap)
    ui:FS(f, "GameFontNormal", "Mana (Life Tap)"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -332)
    self.tapCB = ui:CreateCheck("lifeTap", f, "Use Life Tap", "Life Tap", function(on) if ui.buf then ui.buf.lifeTap = on; ui:Refresh() end end)
    self.tapCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -356)
    self.tapManaSlider = ui:CreateSlider("ltMana", f, "tap below mana", function(v) if ui.buf then ui.buf.lifeTapMana = v; ui:Refresh() end end)
    self.tapManaSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -398)
    self.tapHpSlider = ui:CreateSlider("ltHp", f, "keep HP above", function(v) if ui.buf then ui.buf.lifeTapHpMin = v; ui:Refresh() end end)
    self.tapHpSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -398)

    ui:Divider(f, -134)   -- above DoT
    ui:Divider(f, -236)   -- above Filler and pet
    ui:Divider(f, -320)   -- above Mana

    ui:Tip(self.immoCB.cb, "Immolate", "Direct fire damage plus a fire damage over time.", "Kept up first in the priority.")
    ui:Tip(self.corrCB.cb, "Corruption", "Shadow damage over time, applied after the curse.")
    ui:Tip(self.siphCB.cb, "Siphon Life", "Shadow damage over time that also heals you.")
    ui:Tip(self.curseDD, "Curse", "One curse per target. Curse of Agony has exact upkeep,", "others are reapplied on a timer for now.")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled DoT is up.", "Wand conserves mana, Shadow Bolt and Drain Life spend it.")
    ui:Tip(self.petCB.cb, "Pet attack", "Send the active pet onto your target.")
    ui:Tip(self.tapCB.cb, "Life Tap", "Convert health to mana when mana is low and health is high.")
    ui:Tip(self.tapManaSlider, "Tap below mana", "Life Tap only when mana is under this value.")
    ui:Tip(self.tapHpSlider, "Keep HP above", "Life Tap only while health stays over this value.")
end

-- ============================================================
-- refresh body (warlock binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- curse dropdown: none plus the curses the warlock knows
    local co = { { label = "(none)", value = "" } }
    local av = self:AvailableCursesOf()
    for i = 1, table.getn(av) do co[i + 1] = { label = av[i], value = av[i] } end
    local ccur = buf.curse or ""
    local cshown, cc
    if ccur == "" then cshown, cc = "(none)", ui.COL.white
    elseif self:KnowsSpell(ccur) then cshown, cc = ccur, ui.COL.white
    else cshown, cc = ccur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.curseDD, co, ccur, cshown, cc)

    -- filler dropdown: wand is always available, the casts only if known
    local fo = { { label = "Wand (Shoot)", value = "Shoot" } }
    if self:KnowsSpell("Shadow Bolt") then table.insert(fo, { label = "Shadow Bolt", value = "Shadow Bolt" }) end
    if self:KnowsSpell("Drain Life")  then table.insert(fo, { label = "Drain Life",  value = "Drain Life" })  end
    local fcur = buf.filler or "Shoot"
    local fshown, fc
    if fcur == "Shoot" then fshown, fc = "Wand (Shoot)", ui.COL.white
    elseif self:KnowsSpell(fcur) then fshown, fc = fcur, ui.COL.white
    else fshown, fc = fcur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.fillerDD, fo, fcur, fshown, fc)

    local function setCheck(item, on, spellName)
        item.cb:SetChecked(on and true or false)
        item.cb:Enable()
        if not spellName then item.label:SetText(item.baseText); ui:Color(item.label, ui.COL.white); return end
        local known = self:KnowsSpell(spellName)
        if on and not known then item.label:SetText(item.baseText .. " (not learned)"); ui:Color(item.label, ui.COL.red)
        elseif not known then item.label:SetText(item.baseText .. " (not learned)"); ui:Color(item.label, ui.COL.grey)
        else item.label:SetText(item.baseText); ui:Color(item.label, ui.COL.white) end
    end
    setCheck(self.immoCB, buf.useImmolate, "Immolate")
    setCheck(self.corrCB, buf.useCorruption, "Corruption")
    setCheck(self.siphCB, buf.useSiphonLife, "Siphon Life")
    setCheck(self.petCB, buf.petAttack, nil)
    setCheck(self.tapCB, buf.lifeTap, "Life Tap")

    self.tapManaSlider:SetValue(buf.lifeTapMana or 0); self.tapManaSlider.valText:SetText((buf.lifeTapMana or 0) .. "%")
    self.tapHpSlider:SetValue(buf.lifeTapHpMin or 0);  self.tapHpSlider.valText:SetText((buf.lifeTapHpMin or 0) .. "%")
    local tapOn = self:KnowsSpell("Life Tap") and buf.lifeTap
    if tapOn then
        self.tapManaSlider:EnableMouse(true);  self.tapManaSlider:SetAlpha(1)
        self.tapHpSlider:EnableMouse(true);    self.tapHpSlider:SetAlpha(1)
    else
        self.tapManaSlider:EnableMouse(false); self.tapManaSlider:SetAlpha(0.35)
        self.tapHpSlider:EnableMouse(false);   self.tapHpSlider:SetAlpha(0.35)
    end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod) AutoRotaUI:Toggle() end
