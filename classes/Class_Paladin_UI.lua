-- ============================================================
-- Class_Paladin_UI  -  paladin window body for AutoRota
-- Builds and binds only the paladin specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
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

M.useScrollLayout = true

-- ============================================================
-- build body (paladin controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(field)  return function(v) if ui.buf then ui.buf[field] = v; ui:Refresh() end end end
    local function sset(key)   return function(v) if ui.buf then ui.buf.spells[key] = v; ui:Refresh() end end end

    L:Header("Seals")
    self.debuffDD = L:Dropdown("seal_debuff", "Debuff", 200, function(v) if ui.buf then ui.buf.seals.debuff = v; ui:Refresh() end end)
    self.damageDD = L:Dropdown("seal_damage", "Damage", 200, function(v) if ui.buf then ui.buf.seals.damage = v; ui:Refresh() end end)

    L:Header("Spells")
    self.spellCB = {}
    self.strikeModeDD = L:Dropdown("strikeMode", "Strike mode", 170, set("strikeMode"))
    self.spellCB.holyShield, self.spellCB.hammerOfWrath = L:CheckPair(
        { "holyShield", "Holy Shield", "Holy Shield", sset("holyShield") },
        { "hammerOfWrath", "Hammer of Wrath", "Hammer of Wrath", sset("hammerOfWrath") })
    self.spellCB.repentance, self.spellCB.consecration = L:CheckPair(
        { "repentance", "Repentance", "Repentance", sset("repentance") },
        { "consecration", "Consecration", "Consecration", sset("consecration") })
    self.spellCB.exorcism, self.twistCB = L:CheckPair(
        { "exorcism", "Exorcism", "Exorcism", sset("exorcism") },
        { "sealTwist", "Seal twisting", nil, set("sealTwist") })
    self.prioZealCB, self.downrankCB = L:CheckPair(
        { "prioZeal", "Prioritize Zeal", nil, set("prioZeal") },
        { "strikeDownrank", "Downrank low", nil, set("strikeDownrank") })

    L:Header("Mana management")
    self.manaCB = L:Check("manaManage", "Mana management (Seal of Wisdom)", "Seal of Wisdom", set("manaManage"))
    self.manaLowSlider, self.manaHighSlider = L:SliderPair(
        { "manaLow", "Switch below", set("manaLow") },
        { "manaHigh", "Back above", set("manaHigh") })
    self.weaveCB = L:Check("manaWeave", "Judgement weaving", nil, set("manaWeave"))
    self.weaveMinSlider = L:Slider("manaWeaveMin", "Skip weaving below", set("manaWeaveMin"))
    self.wisdomCB = L:Check("manaWisdomDebuff", "Use Wisdom debuff in mana mode", nil, set("manaWisdomDebuff"))

    L:Header("HP management")
    self.hpCB = L:Check("hpManage", "HP management (Seal of Light)", "Seal of Light", set("hpManage"))
    self.hpLowSlider, self.hpHighSlider = L:SliderPair(
        { "hpLow", "Switch below", set("hpLow") },
        { "hpHigh", "Back above", set("hpHigh") })

    L:Header("Healing")
    self.healCB = L:Check("healMode", "Heal mode (group healing)", nil, set("healMode"))
    self.healAtSlider = L:Slider("healThreshold", "Heal members below", set("healThreshold"))
    self.holyShockCB = L:Check("useHolyShock", "Holy Shock emergencies", "Holy Shock", set("useHolyShock"))
    self.holyShockSlider = L:Slider("holyShockPct", "Holy Shock below", set("holyShockPct"))

    L:Finish()

    ui:Tip(self.debuffDD, "Debuff seal", "Judged once to apply its debuff to the target.", "Autoattacks keep the debuff up afterwards.")
    ui:Tip(self.damageDD, "Damage seal", "Judged continuously for damage.", "Leaves no debuff, so it never overwrites the one above.")

    ui:Tip(self.spellCB.holyShield.cb,     "Holy Shield",     "Cast right after the strike, before seals.", "Fires whenever its own cooldown is ready.")
    ui:Tip(self.spellCB.hammerOfWrath.cb,  "Hammer of Wrath", "Execute, used only at or below 20 percent target HP.")
    ui:Tip(self.spellCB.repentance.cb,     "Repentance",      "Cast on cooldown as a damage proc on Turtle.")
    ui:Tip(self.spellCB.consecration.cb,   "Consecration (AoE)", "AoE filler, cast on cooldown. Manual toggle (also /ar aoe), since 1.12 cannot count nearby enemies.", "Held during mana recovery.")
    ui:Tip(self.spellCB.exorcism.cb,       "Exorcism",        "Strong nuke, used on cooldown but only against Undead and Demon targets.", "Held during mana recovery.")
    ui:Tip(self.strikeModeDD, "Strike mode", "Enables and styles Holy/Crusader Strike. Auto: Vengeful Strike talent -> keep Holy Might up; shield or Righteous Strike -> Holy lean for threat; otherwise Crusader lean. Off disables strikes.", "CS / HS / Holy then Crusader force a fixed style.")
    ui:Tip(self.prioZealCB.cb, "Prioritize Zeal", "Build Zeal to 3 stacks first, then follow the mode above.")
    ui:Tip(self.downrankCB.cb, "Downrank when low", "Use lower ranks of Holy/Crusader Strike as raw mana drops, to keep swinging while leveling.", "Full rank until mana nears a rank's cost; a large pool rarely downranks.")

    ui:Tip(self.manaCB.cb, "Mana management", "Below the lower value, hold Seal of Wisdom to recover mana.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.hpCB.cb, "HP management", "Below the lower value, hold Seal of Light to recover health.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.weaveCB.cb, "Judgement weaving", "During mana recovery, use the free Judgement on the damage seal.", "Costs a little mana for extra damage.")
    ui:Tip(self.weaveMinSlider, "Skip weaving below", "Below this mana, no new weave is started.", "A weave already started always finishes, so leave room for one full cycle.")
    ui:Tip(self.twistCB.cb, "Seal twisting (experimental)", "Holds the damage seal judge until just before the next swing.", "Needs a damage seal. Tune in game, timing depends on latency.")
    ui:Tip(self.wisdomCB.cb, "Wisdom debuff in mana mode", "While recovering mana, apply Judgement of Wisdom instead of the configured debuff.", "It returns mana to attackers, so it speeds recovery.")

    ui:Tip(self.healCB.cb, "Heal mode", "Heal the party/raid, picking the most-hurt reachable member and downranking for efficiency.", "Works at range with no target, and DPSes between heals when no one needs healing. Also /ar heal on|off.")
    ui:Tip(self.healAtSlider, "Heal members below", "Members below this health get healed; the attack rotation yields while anyone is below it.", "Also /ar healat <1-100>.")
    ui:Tip(self.holyShockCB.cb, "Holy Shock emergencies", "Use the instant Holy Shock for an emergency or a hurt unit out of melee range.")
    ui:Tip(self.holyShockSlider, "Holy Shock below", "Health under which Holy Shock is used as an instant emergency heal.", "Also /ar hsat <1-100>. +healing auto-reads from gear; override with /ar healpower <n>.")
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

    local function setCB(key) ui:BindCheck(self.spellCB[key], buf.spells[key]) end
    setCB("holyShield"); setCB("hammerOfWrath"); setCB("repentance")
    setCB("consecration"); setCB("exorcism")

    -- strike mode dropdown + tuning toggles
    local modeOpts = {
        { label = "Off",                value = "off" },
        { label = "Auto (talent/weapon)", value = "auto" },
        { label = "Crusader Strike",    value = "cs" },
        { label = "Holy Strike",        value = "hs" },
        { label = "Holy then Crusader", value = "hscs" },
    }
    local modeLabel = { off = "Off", auto = "Auto (talent/weapon)", cs = "Crusader Strike", hs = "Holy Strike", hscs = "Holy then Crusader" }
    local mcur = buf.strikeMode or "auto"
    ui:SetDropdown(self.strikeModeDD, modeOpts, mcur, modeLabel[mcur] or mcur, ui.COL.white)
    self.prioZealCB.cb:SetChecked(buf.prioZeal and true or false)
    self.downrankCB.cb:SetChecked(buf.strikeDownrank and true or false)

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

    -- Healing section
    ui:BindCheck(self.healCB, buf.healMode)
    self.healAtSlider:SetValue(buf.healThreshold or 90); self.healAtSlider.valText:SetText((buf.healThreshold or 90) .. "%")
    ui:BindCheck(self.holyShockCB, buf.useHolyShock, "Holy Shock")
    self.holyShockSlider:SetValue(buf.holyShockPct or 50); self.holyShockSlider.valText:SetText((buf.holyShockPct or 50) .. "%")
    -- Heal controls are meaningful only in heal mode; grey them otherwise.
    local healOn = buf.healMode and true or false
    self.healAtSlider:EnableMouse(healOn);    self.healAtSlider:SetAlpha(healOn and 1 or 0.35)
    self.holyShockSlider:EnableMouse(healOn); self.holyShockSlider:SetAlpha(healOn and 1 or 0.35)
    if not healOn then
        self.holyShockCB.cb:Disable(); ui:Color(self.holyShockCB.label, ui.COL.grey)
    end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
