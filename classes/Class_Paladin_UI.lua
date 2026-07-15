-- ============================================================
-- Class_Paladin_UI  -  paladin window body for Aegis_SBR
-- Builds and binds only the paladin specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.PALADIN

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
        { key = "damage", label = "Tank / Damage",
          sub  = "This tab is also the active mode. While it is active, all Healer settings are ignored.",
          tip1 = "Retribution and Protection melee rotation.", tip2 = "Selecting this tab also makes it the active mode." },
        { key = "heal",   label = "Healer",
          sub  = "This tab is also the active mode. While it is active, all Tank / Damage settings are ignored.",
          tip1 = "Holy one-button group healing.", tip2 = "Selecting this tab also makes it the active mode." },
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

    L:Header("Strikes", "damage")
    self.spellCB = {}
    -- Two toggles drive the strikes. One alone means exactly that strike; both
    -- on reveals the strategy dropdown below.
    self.spellCB.holyStrike = L:Row{ key = "holyStrike", label = "Holy Strike", spell = "Holy Strike", onToggle = sset("holyStrike") }
    self.spellCB.crusaderStrike = L:Row{ key = "crusaderStrike", label = "Crusader Strike", spell = "Crusader Strike", onToggle = sset("crusaderStrike") }
    self.strikeStyleDD, self.strikeStyleLbl = L:Dropdown("strikeStyle", "Both on", 190, set("strikeStyle"))
    self.downrankRow = L:Row{ key = "strikeDownrank", label = "Downrank when low", onToggle = set("strikeDownrank") }

    L:Header("Spells", "damage")
    self.spellCB.holyShield = L:Row{ key = "holyShield", label = "Holy Shield", spell = "Holy Shield", onToggle = sset("holyShield") }
    self.spellCB.hammerOfWrath = L:Row{ key = "hammerOfWrath", label = "Hammer of Wrath", spell = "Hammer of Wrath", onToggle = sset("hammerOfWrath") }
    self.spellCB.repentance = L:Row{ key = "repentance", label = "Repentance", spell = "Repentance", onToggle = sset("repentance") }
    self.spellCB.consecration = L:Row{ key = "consecration", label = "Consecration", spell = "Consecration", onToggle = sset("consecration") }
    self.spellCB.exorcism = L:Row{ key = "exorcism", label = "Exorcism", spell = "Exorcism", onToggle = sset("exorcism") }
    self.twistRow = L:Row{ key = "sealTwist", label = "Seal twisting", onToggle = set("sealTwist") }

    L:Header("Mana management", "damage")
    self.manaRow = L:Row{ key = "manaManage", label = "Mana management", spell = "Seal of Wisdom", onToggle = set("manaManage") }
    self.manaLowRow = L:Row{ label = "Switch below",
        slider = { key = "manaLow", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaLow") } }
    self.manaHighRow = L:Row{ label = "Back above",
        slider = { key = "manaHigh", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaHigh") } }
    self.weaveRow = L:Row{ key = "manaWeave", label = "Judgement weaving", onToggle = set("manaWeave"),
        slider = { key = "manaWeaveMin", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaWeaveMin") } }
    self.wisdomRow = L:Row{ key = "manaWisdomDebuff", label = "Wisdom debuff in mana mode", onToggle = set("manaWisdomDebuff") }

    L:Header("HP management", "damage")
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
    self.healReloadRow = L:Row{ key = "healReloadCS", label = "Reload Holy Shock (CS)", onToggle = set("healReloadCS") }
    self.healSplashRow = L:Row{ key = "healSplashHS", label = "Holy Strike filler", onToggle = set("healSplashHS"),
        slider = { key = "healWeaveManaFloor", min = 0, max = 90, step = 5, suffix = "%", onChange = set("healWeaveManaFloor") } }

    L:Header("Mana management", "heal")
    self.healManaSelfRow  = L:Row{ key = "healManaSelf",  label = "Seal of Wisdom (self mana)",  spell = "Seal of Wisdom", onToggle = set("healManaSelf") }
    self.healManaJudgeRow = L:Row{ key = "healManaJudge", label = "Judge Wisdom (group mana)",   spell = "Seal of Wisdom", onToggle = set("healManaJudge") }

    L:Finish()

    ui:Tip(self.debuffDD, "Debuff seal", "Judged once to apply its debuff to the target.", "Autoattacks keep the debuff up afterwards.")
    ui:Tip(self.damageDD, "Damage seal", "Judged continuously for damage.", "Leaves no debuff, so it never overwrites the one above.")

    ui:Tip(self.spellCB.holyShield.cb,     "Holy Shield",     "Cast right after the strike, before seals.", "Fires whenever its own cooldown is ready.")
    ui:Tip(self.spellCB.hammerOfWrath.cb,  "Hammer of Wrath", "Execute, used only at or below 20 percent target HP.")
    ui:Tip(self.spellCB.repentance.cb,     "Repentance",      "Cast on cooldown as a damage proc on Turtle.")
    ui:Tip(self.spellCB.consecration.cb,   "Consecration (AoE)", "AoE filler, cast on cooldown. Manual toggle (also /sbr aoe), since 1.12 cannot count nearby enemies.", "Held during mana recovery.")
    ui:Tip(self.spellCB.exorcism.cb,       "Exorcism",        "Strong nuke, used on cooldown but only against Undead and Demon targets.", "Held during mana recovery.")
    ui:Tip(self.spellCB.holyStrike.cb, "Holy Strike", "Shares the 6s strike cooldown with Crusader Strike.", "With Vengeful Strikes it grants Holy Might. Even untalented it returns mana and heals the group.")
    ui:Tip(self.spellCB.crusaderStrike.cb, "Crusader Strike", "Shares the 6s strike cooldown with Holy Strike.", "Builds Zeal. Tank: with Righteous Strikes it also loads the block buff Zealous Defense.")
    ui:Tip(self.strikeStyleDD, "Both-on strategy", "Used only when BOTH strikes are enabled. Enable a single strike alone to force just that one.", "Auto DPS keeps Zeal and, if talented, Holy Might up. Tank block keeps Zealous Defense loaded, else strikes for aggro.")
    ui:Tip(self.downrankRow.cb, "Downrank when low", "Use lower ranks of Holy/Crusader Strike as raw mana drops, to keep swinging while leveling.", "Full rank until mana nears a rank's cost. A large pool rarely downranks.")

    ui:Tip(self.manaRow.cb, "Mana management", "Below the lower value, hold Seal of Wisdom to recover mana.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.hpRow.cb, "HP management", "Below the lower value, hold Seal of Light to recover health.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.weaveRow.cb, "Judgement weaving", "During mana recovery, weave the DAMAGE seal in and judge it for extra damage.", "This does NOT put Seal of Wisdom on the target - that is the 'Wisdom debuff' option below.")
    ui:Tip(self.weaveRow.slider, "Skip weaving below", "Below this mana, no new weave is started.", "A weave already started always finishes, so leave room for one full cycle.")
    ui:Tip(self.twistRow.cb, "Seal twisting (experimental)", "Holds the damage seal judge until just before the next swing.", "Needs a damage seal. Tune in game, timing depends on latency.")
    ui:Tip(self.wisdomRow.cb, "Wisdom debuff in mana mode", "During mana recovery, judge Seal of Wisdom onto the TARGET (Judgement of Wisdom) instead of your configured debuff.", "The target then returns mana to everyone attacking it, so the whole group recovers.")

    ui:Tip(self.healAtRow.slider, "Heal members below", "Members below this health get healed; the attack rotation yields while anyone is below it.", "Also /sbr healat <1-100>.")
    ui:Tip(self.holyShockRow.cb, "Holy Shock emergencies", "Use the instant Holy Shock for an emergency or a hurt unit out of melee range.")
    ui:Tip(self.holyShockRow.cb, "Holy Shock emergencies", "In heal mode Holy Shock is used ONLY as an instant heal, never for damage.", "Fires for an emergency or a hurt unit out of melee range, below the health value on the right.")
    ui:Tip(self.holyShockRow.slider, "Holy Shock below", "Health under which Holy Shock is used as an instant emergency heal.", "Below this same line, Flash of Light is also kept over Holy Light even for a big deficit - faster beats fuller when it's this close. Also /sbr hsat <1-100>. +healing auto-reads from gear; override with /sbr healpower <n>.")
    ui:Tip(self.healReloadRow.cb, "Reload Holy Shock (CS)", "When Holy Shock is on cooldown, use Crusader Strike to reset it (Blessed Strikes, auto-detected), keeping the emergency instant loaded.", "Uses a GCD, but never fires while anyone is below the Holy Shock line - the heal comes first. Not limited by the filler mana floor.")
    ui:Tip(self.healSplashRow.cb, "Holy Strike filler", "In downtime with nobody to heal, use Holy Strike so its splash tops the melee group.", "Uses a GCD, and only above the mana value on the right, so filler never starves a heal.")
    ui:Tip(self.healSplashRow.slider, "Filler mana floor", "Holy Strike filler only fires while your mana is above this.")

    ui:Tip(self.healManaSelfRow.cb, "Seal of Wisdom (self mana)", "In melee downtime, keep Seal of Wisdom up so your own swings return mana to you.", "Only fires when nobody needs healing, so it never delays a heal.")
    ui:Tip(self.healManaJudgeRow.cb, "Judge Wisdom (group mana)", "Also judge Seal of Wisdom onto the mob (Judgement of Wisdom), so everyone attacking it gets mana back.", "Judgement uses a GCD and you cannot heal during that global, so it only fires when nobody needs healing.")
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
    setCB("holyStrike"); setCB("crusaderStrike")
    setCB("holyShield"); setCB("hammerOfWrath"); setCB("repentance")
    setCB("consecration"); setCB("exorcism")

    -- Both-on strategy: only meaningful when BOTH strikes are enabled. With a
    -- single strike on it is used exclusively, so the box is greyed and its text
    -- explains why.
    local styleOpts = {
        { label = "Auto DPS",   value = "autodps" },
        { label = "Tank block", value = "tankblock" },
    }
    local styleLabel = { autodps = "Auto DPS", tankblock = "Tank block" }
    local scur = buf.strikeStyle or "autodps"
    local bothOn = (buf.spells.holyStrike and buf.spells.crusaderStrike) and true or false
    if bothOn then
        ui:SetDropdown(self.strikeStyleDD, styleOpts, scur, styleLabel[scur] or scur, ui.COL.white)
        self.strikeStyleDD:Enable(); self.strikeStyleDD:SetAlpha(1)
        ui:Color(self.strikeStyleLbl, ui.COL.white)
    else
        ui:SetDropdown(self.strikeStyleDD, styleOpts, scur, "enable both strikes", ui.COL.grey)
        self.strikeStyleDD:Disable(); self.strikeStyleDD:SetAlpha(0.5)
        ui:Color(self.strikeStyleLbl, ui.COL.grey)
    end

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
    -- Holy Shock emergencies. The stored preference defaults on so it just works
    -- the moment Holy Shock is trained; but while the spell is not learned the
    -- toggle is shown OFF (not a misleading lit "on") and greyed. The saved value
    -- stays untouched, so learning the spell lights it up automatically.
    local hsKnown = self:KnowsSpell("Holy Shock")
    ui:BindCheck(self.holyShockRow, buf.useHolyShock and hsKnown, "Holy Shock")
    self.holyShockRow.slider:SetValue(buf.holyShockPct or 50); self.holyShockRow.slider.valText:SetText((buf.holyShockPct or 50) .. "%")
    -- The heal controls live in the heal-only "Healing" card, which the tab rail
    -- hides entirely on the Damage tab, so no mode gating is needed here.
    if not hsKnown then
        self.holyShockRow.cb:Disable()
    end

    -- Reload Holy Shock (CS): greyed unless Blessed Strikes plus both spells are
    -- present, since the reset cannot happen otherwise.
    local reloadOK = self:BlessedReloadUsable()
    ui:BindCheck(self.healReloadRow, (buf.healReloadCS ~= false) and reloadOK)
    if reloadOK then
        self.healReloadRow.label:SetText("Reload Holy Shock (CS)"); ui:Color(self.healReloadRow.label, ui.COL.white)
    else
        self.healReloadRow.cb:Disable()
        self.healReloadRow.label:SetText("Reload Holy Shock (CS) - needs Blessed Strikes"); ui:Color(self.healReloadRow.label, ui.COL.grey)
    end

    -- Holy Strike filler: its mana-floor slider follows the toggle.
    local splashOn = buf.healSplashHS ~= false
    ui:BindCheck(self.healSplashRow, splashOn)
    self.healSplashRow.slider:SetValue(buf.healWeaveManaFloor or 40)
    self.healSplashRow.slider.valText:SetText((buf.healWeaveManaFloor or 40) .. "%")
    ui:SliderEnable(self.healSplashRow.slider, splashOn)

    -- Heal-mode mana upkeep. Both need Seal of Wisdom; shown OFF and greyed while
    -- it is not learned, without touching the stored value.
    local sowKnown = self:KnowsSpell("Seal of Wisdom")
    ui:BindCheck(self.healManaSelfRow,  buf.healManaSelf  and sowKnown, "Seal of Wisdom")
    ui:BindCheck(self.healManaJudgeRow, buf.healManaJudge and sowKnown, "Seal of Wisdom")
    if not sowKnown then
        self.healManaSelfRow.cb:Disable()
        self.healManaJudgeRow.cb:Disable()
    end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
