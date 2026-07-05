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
        cbItem.label:SetTextColor(0.91, 0.90, 0.88); cbItem.label:SetText(cbItem.baseText)
    else
        cbItem.cb:Disable()
        sLow:EnableMouse(false); sHigh:EnableMouse(false); sLow:SetAlpha(0.35); sHigh:SetAlpha(0.35)
        cbItem.label:SetTextColor(0.55, 0.55, 0.55); cbItem.label:SetText(cbItem.baseText .. (reason and (" - " .. reason) or ""))
    end
end

M.useScrollLayout = true
-- Damage | Healer rail. The rotation's only real branch is healMode (attack vs.
-- heal), so the two tabs bind to that boolean via encode/decode. Ret and Prot
-- both live on Damage (they differ only by the seals/strikes below, not by the
-- rotation), so the spec names live in the tooltips rather than the labels.
M.specTabs = {
    field = "healMode", default = "damage",
    encode = function(key) return key == "heal" end,          -- key -> healMode boolean
    decode = function(v) return v and "heal" or "damage" end,  -- boolean -> tab key
    tabs = {
        { key = "damage", label = "Damage", tip1 = "Retribution & Protection - melee rotation.", tip2 = "Pick your seals, strikes and cooldowns below." },
        { key = "heal",   label = "Healer", tip1 = "Holy - one-button group healing.", tip2 = "Judges Seal of Wisdom for mana; weaves strikes melee-holy style (Blessed Strikes reloads Holy Shock)." },
    },
}

-- ============================================================
-- build body (paladin controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(field)  return function(v) if ui.buf then ui.buf[field] = v; ui:Refresh() end end end
    local function sset(key)   return function(v) if ui.buf then ui.buf.spells[key] = v; ui:Refresh() end end end

    L:Header("Seals", "damage")
    self.debuffDD = L:Dropdown("seal_debuff", "Debuff", 200, function(v) if ui.buf then ui.buf.seals.debuff = v; ui:Refresh() end end)
    self.damageDD = L:Dropdown("seal_damage", "Damage", 200, function(v) if ui.buf then ui.buf.seals.damage = v; ui:Refresh() end end)

    L:Header("Spells", "damage")
    self.spellCB = {}
    self.strikeModeDD = L:Dropdown("strikeMode", "Strike mode", 170, set("strikeMode"))
    self.spellCB.holyShield = L:Row{ key = "holyShield", label = "Holy Shield", spell = "Holy Shield", onToggle = sset("holyShield") }
    self.spellCB.hammerOfWrath = L:Row{ key = "hammerOfWrath", label = "Hammer of Wrath", spell = "Hammer of Wrath", onToggle = sset("hammerOfWrath") }
    self.spellCB.repentance = L:Row{ key = "repentance", label = "Repentance", spell = "Repentance", onToggle = sset("repentance") }
    self.spellCB.consecration = L:Row{ key = "consecration", label = "Consecration", spell = "Consecration", onToggle = sset("consecration") }
    self.spellCB.exorcism = L:Row{ key = "exorcism", label = "Exorcism", spell = "Exorcism", onToggle = sset("exorcism") }
    self.twistRow = L:Row{ key = "sealTwist", label = "Seal twisting", onToggle = set("sealTwist") }
    self.prioZealRow = L:Row{ key = "prioZeal", label = "Prioritize Zeal", onToggle = set("prioZeal") }
    self.downrankRow = L:Row{ key = "strikeDownrank", label = "Downrank low", onToggle = set("strikeDownrank") }

    L:Header("Mana management")
    self.manaRow = L:Row{ key = "manaManage", label = "Mana management", spell = "Seal of Wisdom", onToggle = set("manaManage") }
    self.manaLowRow = L:Row{ label = "Switch below",
        slider = { key = "manaLow", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaLow") } }
    self.manaHighRow = L:Row{ label = "Back above",
        slider = { key = "manaHigh", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaHigh") } }
    self.weaveRow = L:Row{ key = "manaWeave", label = "Judgement weaving", onToggle = set("manaWeave"),
        slider = { key = "manaWeaveMin", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaWeaveMin") } }
    self.wisdomRow = L:Row{ key = "manaWisdomDebuff", label = "Wisdom debuff in mana mode", onToggle = set("manaWisdomDebuff") }

    L:Header("HP management")
    self.hpRow = L:Row{ key = "hpManage", label = "HP management", spell = "Seal of Light", onToggle = set("hpManage") }
    self.hpLowRow = L:Row{ label = "Switch below",
        slider = { key = "hpLow", min = 0, max = 100, step = 5, suffix = "%", onChange = set("hpLow") } }
    self.hpHighRow = L:Row{ label = "Back above",
        slider = { key = "hpHigh", min = 0, max = 100, step = 5, suffix = "%", onChange = set("hpHigh") } }

    L:Header("Healing", "heal")
    self.healAtRow = L:Row{ label = "Heal members below",
        slider = { key = "healThreshold", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healThreshold") } }
    self.holyShockRow = L:Row{ key = "useHolyShock", label = "Holy Shock emergencies", spell = "Holy Shock", onToggle = set("useHolyShock"),
        slider = { key = "holyShockPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("holyShockPct") } }
    self.healWeaveRow = L:Row{ key = "healWeaveStrikes", label = "Weave strikes (melee holy)", onToggle = set("healWeaveStrikes"),
        slider = { key = "healWeaveManaFloor", min = 0, max = 90, step = 5, suffix = "%", onChange = set("healWeaveManaFloor") } }

    L:Finish()

    ui:Tip(self.debuffDD, "Debuff seal", "Judged once to apply its debuff to the target.", "Autoattacks keep the debuff up afterwards.")
    ui:Tip(self.damageDD, "Damage seal", "Judged continuously for damage.", "Leaves no debuff, so it never overwrites the one above.")

    ui:Tip(self.spellCB.holyShield.cb,     "Holy Shield",     "Cast right after the strike, before seals.", "Fires whenever its own cooldown is ready.")
    ui:Tip(self.spellCB.hammerOfWrath.cb,  "Hammer of Wrath", "Execute, used only at or below 20 percent target HP.")
    ui:Tip(self.spellCB.repentance.cb,     "Repentance",      "Cast on cooldown as a damage proc on Turtle.")
    ui:Tip(self.spellCB.consecration.cb,   "Consecration (AoE)", "AoE filler, cast on cooldown. Manual toggle (also /ar aoe), since 1.12 cannot count nearby enemies.", "Held during mana recovery.")
    ui:Tip(self.spellCB.exorcism.cb,       "Exorcism",        "Strong nuke, used on cooldown but only against Undead and Demon targets.", "Held during mana recovery.")
    ui:Tip(self.strikeModeDD, "Strike mode", "Enables and styles Holy/Crusader Strike. Auto: Vengeful Strike talent -> keep Holy Might up; shield or Righteous Strike -> Holy lean for threat; otherwise Crusader lean. Off disables strikes.", "CS / HS / Holy then Crusader force a fixed style.")
    ui:Tip(self.prioZealRow.cb, "Prioritize Zeal", "Build Zeal to 3 stacks first, then follow the mode above.")
    ui:Tip(self.downrankRow.cb, "Downrank when low", "Use lower ranks of Holy/Crusader Strike as raw mana drops, to keep swinging while leveling.", "Full rank until mana nears a rank's cost; a large pool rarely downranks.")

    ui:Tip(self.manaRow.cb, "Mana management", "Below the lower value, hold Seal of Wisdom to recover mana.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.hpRow.cb, "HP management", "Below the lower value, hold Seal of Light to recover health.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.weaveRow.cb, "Judgement weaving", "During mana recovery, use the free Judgement on the damage seal.", "Costs a little mana for extra damage.")
    ui:Tip(self.weaveRow.slider, "Skip weaving below", "Below this mana, no new weave is started.", "A weave already started always finishes, so leave room for one full cycle.")
    ui:Tip(self.twistRow.cb, "Seal twisting (experimental)", "Holds the damage seal judge until just before the next swing.", "Needs a damage seal. Tune in game, timing depends on latency.")
    ui:Tip(self.wisdomRow.cb, "Wisdom debuff in mana mode", "While recovering mana, apply Judgement of Wisdom instead of the configured debuff.", "It returns mana to attackers, so it speeds recovery.")

    ui:Tip(self.healAtRow.slider, "Heal members below", "Members below this health get healed; the attack rotation yields while anyone is below it.", "Also /ar healat <1-100>.")
    ui:Tip(self.holyShockRow.cb, "Holy Shock emergencies", "Use the instant Holy Shock for an emergency or a hurt unit out of melee range.")
    ui:Tip(self.holyShockRow.slider, "Holy Shock below", "Health under which Holy Shock is used as an instant emergency heal.", "Also /ar hsat <1-100>. +healing auto-reads from gear; override with /ar healpower <n>.")
    ui:Tip(self.healWeaveRow.cb, "Weave strikes (melee holy)", "Between heals: Crusader Strike reloads Holy Shock (Blessed Strikes, auto-detected), and Holy Strike splash-heals the melee group in downtime.", "Never fires over an emergency - anyone under the Holy Shock line is healed first.")
    ui:Tip(self.healWeaveRow.slider, "Weave mana floor", "Strikes weave only while your mana is above this, so weaving never starves a heal.")
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
    self.prioZealRow.cb:SetChecked(buf.prioZeal and true or false)
    self.downrankRow.cb:SetChecked(buf.strikeDownrank and true or false)

    -- seal twisting needs a damage seal to time the judge against
    local twistOK = buf.seals.damage ~= "" and self:KnowsSpell(buf.seals.damage)
    self.twistRow.cb:SetChecked(buf.sealTwist and true or false)
    if twistOK then
        self.twistRow.cb:Enable()
        self.twistRow.label:SetText("Seal twisting"); ui:Color(self.twistRow.label, ui.COL.white)
    else
        self.twistRow.cb:Disable()
        self.twistRow.label:SetText("Seal twisting - needs damage seal"); ui:Color(self.twistRow.label, ui.COL.grey)
    end

    local manaOK = self:KnowsSpell("Seal of Wisdom")
    local manaReason = "not learned"
    setBlockEnabled(self.manaRow, self.manaLowRow.slider, self.manaHighRow.slider, manaOK, manaReason)
    self.manaRow.cb:SetChecked(buf.manaManage and true or false)
    self.manaLowRow.slider:SetValue(buf.manaLow or 0);  self.manaLowRow.slider.valText:SetText((buf.manaLow or 0) .. "%")
    self.manaHighRow.slider:SetValue(buf.manaHigh or 0); self.manaHighRow.slider.valText:SetText((buf.manaHigh or 0) .. "%")

    -- Judgement weaving: only meaningful when mana management is on and a damage seal exists
    local dmg = buf.seals.damage
    local weaveOK = manaOK and buf.manaManage and dmg ~= "" and self:KnowsSpell(dmg)
    self.weaveRow.cb:SetChecked(buf.manaWeave and true or false)
    self.weaveRow.slider:SetValue(buf.manaWeaveMin or 0)
    self.weaveRow.slider.valText:SetText((buf.manaWeaveMin or 0) .. "%")
    if weaveOK then
        self.weaveRow.cb:Enable()
        ui:Color(self.weaveRow.label, ui.COL.white)
        self.weaveRow.slider:EnableMouse(true); self.weaveRow.slider:SetAlpha(1)
    else
        self.weaveRow.cb:Disable()
        ui:Color(self.weaveRow.label, ui.COL.grey)
        self.weaveRow.slider:EnableMouse(false); self.weaveRow.slider:SetAlpha(0.35)
    end

    -- Wisdom debuff in mana mode: meaningful when mana management is on and SoW is known
    local wisdomOK = manaOK and buf.manaManage
    self.wisdomRow.cb:SetChecked(buf.manaWisdomDebuff and true or false)
    if wisdomOK then
        self.wisdomRow.cb:Enable()
        self.wisdomRow.label:SetText("Wisdom debuff in mana mode"); ui:Color(self.wisdomRow.label, ui.COL.white)
    else
        self.wisdomRow.cb:Disable()
        self.wisdomRow.label:SetText("Wisdom debuff - enable mana management"); ui:Color(self.wisdomRow.label, ui.COL.grey)
    end

    local hpOK = self:KnowsSpell("Seal of Light")
    local hpReason = "not learned"
    setBlockEnabled(self.hpRow, self.hpLowRow.slider, self.hpHighRow.slider, hpOK, hpReason)
    self.hpRow.cb:SetChecked(buf.hpManage and true or false)
    self.hpLowRow.slider:SetValue(buf.hpLow or 0);  self.hpLowRow.slider.valText:SetText((buf.hpLow or 0) .. "%")
    self.hpHighRow.slider:SetValue(buf.hpHigh or 0); self.hpHighRow.slider.valText:SetText((buf.hpHigh or 0) .. "%")

    -- Healing section
    self.healAtRow.slider:SetValue(buf.healThreshold or 90); self.healAtRow.slider.valText:SetText((buf.healThreshold or 90) .. "%")
    ui:BindCheck(self.holyShockRow, buf.useHolyShock, "Holy Shock")
    self.holyShockRow.slider:SetValue(buf.holyShockPct or 50); self.holyShockRow.slider.valText:SetText((buf.holyShockPct or 50) .. "%")
    -- Heal controls are meaningful only in heal mode; grey them otherwise.
    -- The heal controls live in the heal-only "Healing" card, which the tab rail
    -- hides entirely on the Damage tab, so no mode gating is needed here - only
    -- grey Holy Shock when it is not learned.
    if not self:KnowsSpell("Holy Shock") then
        self.holyShockRow.cb:Disable(); ui:Color(self.holyShockRow.label, ui.COL.grey)
    end

    -- Melee-holy strike weaving: slider follows the toggle.
    local weaveOn = buf.healWeaveStrikes ~= false
    ui:BindCheck(self.healWeaveRow, weaveOn)
    self.healWeaveRow.slider:SetValue(buf.healWeaveManaFloor or 40)
    ui:SliderEnable(self.healWeaveRow.slider, weaveOn)
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
