-- ============================================================
-- Class_Paladin_UI  -  paladin window body for AutoRota
-- Builds and binds only the paladin specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.PALADIN

local function setBlockEnabled(cbItem, sLow, sHigh, on, reason)
    if on then
        cbItem.cb:Enable()
        sLow:EnableMouse(true); sHigh:EnableMouse(true); sLow:SetAlpha(1); sHigh:SetAlpha(1)
        cbItem.label:SetTextColor(1, 1, 1); cbItem.label:SetText(cbItem.baseText)
    else
        cbItem.cb:Disable()
        sLow:EnableMouse(false); sHigh:EnableMouse(false); sLow:SetAlpha(0.35); sHigh:SetAlpha(0.35)
        cbItem.label:SetTextColor(0.55, 0.55, 0.55); cbItem.label:SetText(cbItem.baseText .. (reason and (" - " .. reason) or ""))
    end
end

-- ============================================================
-- build body (paladin controls)
-- ============================================================
function M:BuildBody(ui, f)
    ui:FS(f, "GameFontNormal", "Seals"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    ui:FS(f, "GameFontNormalSmall", "Debuff"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -166)
    self.debuffDD = ui:CreateDropdown("seal_debuff", f, 210, function(v) if ui.buf then ui.buf.seals.debuff = v; ui:Refresh() end end)
    self.debuffDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -164)
    ui:FS(f, "GameFontNormalSmall", "Damage"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -194)
    self.damageDD = ui:CreateDropdown("seal_damage", f, 210, function(v) if ui.buf then ui.buf.seals.damage = v; ui:Refresh() end end)
    self.damageDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -192)

    ui:FS(f, "GameFontNormal", "Spells"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -222)
    self.spellCB = {}
    self.spellCB.holyStrike     = ui:CreateCheck("holyStrike",     f, "Holy Strike",     "Holy Strike",     function(v) if ui.buf then ui.buf.spells.holyStrike = v; ui:Refresh() end end)
    self.spellCB.crusaderStrike = ui:CreateCheck("crusaderStrike", f, "Crusader Strike", "Crusader Strike", function(v) if ui.buf then ui.buf.spells.crusaderStrike = v; ui:Refresh() end end)
    self.spellCB.holyShield     = ui:CreateCheck("holyShield",     f, "Holy Shield",     "Holy Shield",     function(v) if ui.buf then ui.buf.spells.holyShield = v; ui:Refresh() end end)
    self.spellCB.hammerOfWrath  = ui:CreateCheck("hammerOfWrath",  f, "Hammer of Wrath", "Hammer of Wrath", function(v) if ui.buf then ui.buf.spells.hammerOfWrath = v; ui:Refresh() end end)
    self.spellCB.repentance     = ui:CreateCheck("repentance",     f, "Repentance",      "Repentance",      function(v) if ui.buf then ui.buf.spells.repentance = v; ui:Refresh() end end)
    self.spellCB.holyStrike.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -240)
    self.spellCB.crusaderStrike.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -240)
    self.spellCB.holyShield.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -262)
    self.spellCB.hammerOfWrath.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -262)
    self.spellCB.repentance.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -284)

    self.twistCB = ui:CreateCheck("sealTwist", f, "Seal twisting", nil, function(v) if ui.buf then ui.buf.sealTwist = v; ui:Refresh() end end)
    self.twistCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -284)

    self.manaCB = ui:CreateCheck("manaManage", f, "Mana management (Seal of Wisdom)", "Seal of Wisdom", function(v) if ui.buf then ui.buf.manaManage = v; ui:Refresh() end end)
    self.manaCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -314)
    self.manaLowSlider  = ui:CreateSlider("manaLow",  f, "switch below", function(v) if ui.buf then ui.buf.manaLow  = v; ui:Refresh() end end)
    self.manaHighSlider = ui:CreateSlider("manaHigh", f, "back above",   function(v) if ui.buf then ui.buf.manaHigh = v; ui:Refresh() end end)
    self.manaLowSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -356)
    self.manaHighSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -356)
    self.weaveCB = ui:CreateCheck("manaWeave", f, "Judgement weaving", nil, function(v) if ui.buf then ui.buf.manaWeave = v; ui:Refresh() end end)
    self.weaveCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -388)
    self.weaveMinSlider = ui:CreateSlider("manaWeaveMin", f, "skip weaving below", function(v) if ui.buf then ui.buf.manaWeaveMin = v; ui:Refresh() end end)
    self.weaveMinSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -426)
    self.wisdomCB = ui:CreateCheck("manaWisdomDebuff", f, "Use Wisdom debuff in mana mode", nil, function(v) if ui.buf then ui.buf.manaWisdomDebuff = v; ui:Refresh() end end)
    self.wisdomCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -456)

    self.hpCB = ui:CreateCheck("hpManage", f, "HP management (Seal of Light)", "Seal of Light", function(v) if ui.buf then ui.buf.hpManage = v; ui:Refresh() end end)
    self.hpCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -490)
    self.hpLowSlider  = ui:CreateSlider("hpLow",  f, "switch below", function(v) if ui.buf then ui.buf.hpLow  = v; ui:Refresh() end end)
    self.hpHighSlider = ui:CreateSlider("hpHigh", f, "back above",   function(v) if ui.buf then ui.buf.hpHigh = v; ui:Refresh() end end)
    self.hpLowSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -532)
    self.hpHighSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -532)

    -- section separators for easier scanning
    ui:Divider(f, -134)   -- above Seals
    ui:Divider(f, -214)   -- above Spells
    ui:Divider(f, -306)   -- above Mana management
    ui:Divider(f, -480)   -- above HP management, below the Wisdom debuff toggle


    ui:Tip(self.debuffDD, "Debuff seal", "Judged once to apply its debuff to the target.", "Autoattacks keep the debuff up afterwards.")
    ui:Tip(self.damageDD, "Damage seal", "Judged continuously for damage.", "Leaves no debuff, so it never overwrites the one above.")

    ui:Tip(self.spellCB.holyStrike.cb,     "Holy Strike",     "Shares a cooldown with Crusader Strike.")
    ui:Tip(self.spellCB.crusaderStrike.cb, "Crusader Strike", "Shares a cooldown with Holy Strike.")
    ui:Tip(self.spellCB.holyShield.cb,     "Holy Shield",     "Cast right after the strike, before seals.", "Fires whenever its own cooldown is ready.")
    ui:Tip(self.spellCB.hammerOfWrath.cb,  "Hammer of Wrath", "Execute, used only at or below 20 percent target HP.")
    ui:Tip(self.spellCB.repentance.cb,     "Repentance",      "Cast on cooldown as a damage proc on Turtle.")

    ui:Tip(self.manaCB.cb, "Mana management", "Below the lower value, hold Seal of Wisdom to recover mana.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.hpCB.cb, "HP management", "Below the lower value, hold Seal of Light to recover health.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.weaveCB.cb, "Judgement weaving", "During mana recovery, use the free Judgement on the damage seal.", "Costs a little mana for extra damage.")
    ui:Tip(self.weaveMinSlider, "Skip weaving below", "Below this mana, no new weave is started.", "A weave already started always finishes, so leave room for one full cycle.")
    ui:Tip(self.twistCB.cb, "Seal twisting (experimental)", "Holds the damage seal judge until just before the next swing.", "Needs a damage seal. Tune in game, timing depends on latency.")
    ui:Tip(self.wisdomCB.cb, "Wisdom debuff in mana mode", "While recovering mana, apply Judgement of Wisdom instead of the configured debuff.", "It returns mana to attackers, so it speeds recovery.")
end

-- ============================================================
-- refresh body (paladin binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    local function sealDD(dd, list, cur)
        cur = cur or ""
        local o = { { label = "(none)", value = "" } }
        local avail = self:AvailableSealsOf(list)
        for i = 1, table.getn(avail) do o[i + 1] = { label = avail[i], value = avail[i] } end
        local shown, c
        if cur == "" then shown, c = "(none)", ui.COL.white
        elseif self:KnowsSpell(cur) then shown, c = cur, ui.COL.white
        else shown, c = cur .. " (not learned)", ui.COL.red end
        ui:SetDropdown(dd, o, cur, shown, c)
    end
    sealDD(self.debuffDD, self.DEBUFF_SEALS, buf.seals.debuff)
    sealDD(self.damageDD, self.DAMAGE_SEALS, buf.seals.damage)

    local function setCB(key)
        local item = self.spellCB[key]
        local on = buf.spells[key] and true or false
        item.cb:SetChecked(on)
        local known = self:KnowsSpell(item.spellName)
        if on and not known then item.label:SetText(item.baseText .. " (not learned)"); ui:Color(item.label, ui.COL.red)
        elseif not known then item.label:SetText(item.baseText .. " (not learned)"); ui:Color(item.label, ui.COL.grey)
        else item.label:SetText(item.baseText); ui:Color(item.label, ui.COL.white) end
    end
    setCB("holyStrike"); setCB("crusaderStrike"); setCB("holyShield"); setCB("hammerOfWrath"); setCB("repentance")

    -- seal twisting needs a damage seal to time the judge against
    local twistOK = buf.seals.damage ~= "" and self:KnowsSpell(buf.seals.damage)
    self.twistCB.cb:SetChecked(buf.sealTwist and true or false)
    if twistOK then
        self.twistCB.cb:Enable()
        self.twistCB.label:SetText("Seal twisting"); ui:Color(self.twistCB.label, ui.COL.white)
    else
        self.twistCB.cb:Disable()
        self.twistCB.label:SetText("Seal twisting (needs damage seal)"); ui:Color(self.twistCB.label, ui.COL.grey)
    end

    local manaOK = self:KnowsSpell("Seal of Wisdom")
    local manaReason = "not learned"
    setBlockEnabled(self.manaCB, self.manaLowSlider, self.manaHighSlider, manaOK, manaReason)
    self.manaCB.cb:SetChecked(buf.manaManage and true or false)
    self.manaLowSlider:SetValue(buf.manaLow or 0);  self.manaLowSlider.valText:SetText((buf.manaLow or 0) .. "%")
    self.manaHighSlider:SetValue(buf.manaHigh or 0); self.manaHighSlider.valText:SetText((buf.manaHigh or 0) .. "%")

    -- Judgement weaving: only meaningful when mana management is on and a damage seal exists
    local dmg = buf.seals.damage
    local weaveOK = manaOK and buf.manaManage and dmg ~= "" and self:KnowsSpell(dmg)
    self.weaveCB.cb:SetChecked(buf.manaWeave and true or false)
    self.weaveMinSlider:SetValue(buf.manaWeaveMin or 0)
    self.weaveMinSlider.valText:SetText((buf.manaWeaveMin or 0) .. "%")
    if weaveOK then
        self.weaveCB.cb:Enable()
        self.weaveCB.label:SetText(dmg .. " Judgement weaving")
        ui:Color(self.weaveCB.label, ui.COL.white)
        self.weaveMinSlider:EnableMouse(true); self.weaveMinSlider:SetAlpha(1)
    else
        self.weaveCB.cb:Disable()
        local reason = (not buf.manaManage) and "enable mana management" or "needs a damage seal"
        self.weaveCB.label:SetText("Judgement weaving - " .. reason)
        ui:Color(self.weaveCB.label, ui.COL.grey)
        self.weaveMinSlider:EnableMouse(false); self.weaveMinSlider:SetAlpha(0.35)
    end

    -- Wisdom debuff in mana mode: meaningful when mana management is on and SoW is known
    local wisdomOK = manaOK and buf.manaManage
    self.wisdomCB.cb:SetChecked(buf.manaWisdomDebuff and true or false)
    if wisdomOK then
        self.wisdomCB.cb:Enable()
        self.wisdomCB.label:SetText("Use Wisdom debuff in mana mode"); ui:Color(self.wisdomCB.label, ui.COL.white)
    else
        self.wisdomCB.cb:Disable()
        self.wisdomCB.label:SetText("Use Wisdom debuff in mana mode (enable mana management)"); ui:Color(self.wisdomCB.label, ui.COL.grey)
    end

    local hpOK = self:KnowsSpell("Seal of Light")
    local hpReason = "not learned"
    setBlockEnabled(self.hpCB, self.hpLowSlider, self.hpHighSlider, hpOK, hpReason)
    self.hpCB.cb:SetChecked(buf.hpManage and true or false)
    self.hpLowSlider:SetValue(buf.hpLow or 0);  self.hpLowSlider.valText:SetText((buf.hpLow or 0) .. "%")
    self.hpHighSlider:SetValue(buf.hpHigh or 0); self.hpHighSlider.valText:SetText((buf.hpHigh or 0) .. "%")
end

-- Open the shared window for this class.
M.OpenConfig = function(mod) AutoRotaUI:Toggle() end
