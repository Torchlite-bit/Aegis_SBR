-- ============================================================
-- Class_Shaman_UI  -  shaman window body for AutoRota
-- Builds and binds only the shaman specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = AutoRota.classes.SHAMAN
M.useScrollLayout = true

-- ============================================================
-- build body (shaman controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Mode")
    self.modeDD = L:Dropdown("mode", "Spec", 130, set("mode"))

    L:Header("Shield & shock")
    self.shieldDD = L:Dropdown("shield", "Shield", 150, set("shield"))
    self.shockDD  = L:Dropdown("shock", "Shock", 150, set("shock"))

    self.meleeSection = L:Header("Melee strikes")
    self.ssCB, self.lsCB = L:CheckPair(
        { "useStormstrike", "Stormstrike", "Stormstrike", set("useStormstrike") },
        { "useLightningStrike", "Lightning Strike", "Lightning Strike", set("useLightningStrike") })

    L:Header("Casting & totems")
    self.lbCB, self.searCB = L:CheckPair(
        { "lbFiller", "Lightning Bolt", "Lightning Bolt", set("lbFiller") },
        { "useSearingTotem", "Searing Totem", "Searing Totem", set("useSearingTotem") })

    L:Header("Cooldowns & utility")
    self.emCB, self.blCB = L:CheckPair(
        { "useElementalMastery", "Elemental Mastery", "Elemental Mastery", set("useElementalMastery") },
        { "useBloodlust", "Bloodlust", "Bloodlust", set("useBloodlust") })
    self.tauntCB = L:Check("useTaunt", "Earthshaker taunt", "Earthshaker Slam", set("useTaunt"))

    self.restoSection = L:Header("Restoration (Heal)")
    self.htSlider, self.hpowSlider = L:SliderPair(
        { "healThreshold", "Heal below", { min = 50, max = 100, step = 5, suffix = "%" }, set("healThreshold") },
        { "healPower", "Heal power", { min = 0, max = 2000, step = 50, suffix = "" }, set("healPower") })
    self.manaTideCB, self.nsCB = L:CheckPair(
        { "useManaTide", "Mana Tide", "Mana Tide Totem", set("useManaTide") },
        { "useNSCombo", "Nature's Swiftness", nil, set("useNSCombo") })
    self.manaTideSlider, self.nsSlider = L:SliderPair(
        { "manaTideAt", "Mana Tide mana", { min = 0, max = 60, step = 5, suffix = "%" }, set("manaTideAt") },
        { "nsHpPct", "Nat.Swift HP", { min = 10, max = 70, step = 5, suffix = "%" }, set("nsHpPct") })
    self.lhwCB, self.chainCB = L:CheckPair(
        { "useLesserHW", "Lesser Heal Wave", "Lesser Healing Wave", set("useLesserHW") },
        { "useChainHeal", "Chain Heal", "Chain Heal", set("useChainHeal") })
    self.lhwSlider, self.chainSlider = L:SliderPair(
        { "lhwPct", "Lesser HW HP", { min = 20, max = 90, step = 5, suffix = "%" }, set("lhwPct") },
        { "chainHealCount", "Chain Heal #", { min = 2, max = 8, step = 1, suffix = "" }, set("chainHealCount") })
    self.totemsCB, self.weaveCB = L:CheckPair(
        { "useTotems", "Maintain totems", nil, set("useTotems") },
        { "weaveDamage", "Weave damage", nil, set("weaveDamage") })
    self.weaveSlider = L:Slider("weaveManaFloor", "Weave mana floor", { min = 0, max = 90, step = 5, suffix = "%" }, set("weaveManaFloor"))
    self.waterDD = L:Dropdown("totemWater", "Water totem", 160, set("totemWater"))
    self.earthDD = L:Dropdown("totemEarth", "Earth totem", 160, set("totemEarth"))
    self.fireDD  = L:Dropdown("totemFire", "Fire totem", 160, set("totemFire"))
    self.airDD   = L:Dropdown("totemAir", "Air totem", 160, set("totemAir"))

    L:Finish()

    ui:Tip(self.modeDD, "Mode", "Enhancement (melee), Elemental (caster), or Tank.", "Each press runs the rotation for the selected mode.")
    ui:Tip(self.shieldDD, "Shield", "Kept up automatically. Lightning Shield for damage/threat, Water Shield for mana.")
    ui:Tip(self.shockDD, "Shock", "One shock on the shared cooldown. Flame Shock is kept up as a DoT; Earth/Frost are cast on cooldown.")
    ui:Tip(self.ssCB.cb, "Stormstrike", "Talented melee strike. Grants a buff boosting your next 2 Nature hits by 20% - the rotation follows it with a shock. Auto-detected when learned.")
    ui:Tip(self.lsCB.cb, "Lightning Strike", "Talented melee instant that also fires an empowered version of your active shield. Auto-detected when learned.")
    ui:Tip(self.lbCB.cb, "Lightning Bolt filler", "Weave Lightning Bolt when nothing else is queued. This is also the main damage at low levels.")
    ui:Tip(self.searCB.cb, "Searing Totem", "Re-dropped on a timer while in combat (no totem-state API on 1.12).")
    ui:Tip(self.emCB.cb, "Elemental Mastery", "Pop before a nuke for a guaranteed crit (feeds Clearcasting and Electrify). Off the global cooldown.")
    ui:Tip(self.blCB.cb, "Bloodlust", "Self melee/cast haste burst (Turtle: self-only). Used in combat when off cooldown.")
    ui:Tip(self.tauntCB.cb, "Earthshaker Slam", "Tank taunt, cast only when the target is not already attacking you. Requires a shield.")
    ui:Tip(self.htSlider, "Heal threshold", "An ally below this health counts as hurt and pulls a heal. Everything in this section keys off it.")
    ui:Tip(self.hpowSlider, "Heal power", "Your bonus healing (+heal) from gear. Used to size downranks so each heal just covers the deficit.", "Leave at 0 to heal by rank only.")
    ui:Tip(self.manaTideCB.cb, "Mana Tide Totem", "Dropped when your own mana runs low, to refill the party.")
    ui:Tip(self.nsCB.cb, "Nature's Swiftness", "Pop NS (or Ancestral Swiftness) for an instant max Healing Wave when someone is in real trouble.")
    ui:Tip(self.manaTideSlider, "Mana Tide mana", "Drop Mana Tide once your mana falls under this percent.")
    ui:Tip(self.nsSlider, "Nat. Swiftness HP", "Trigger the instant NS heal when a target drops under this health.")
    ui:Tip(self.lhwCB.cb, "Lesser Healing Wave", "Fast single-target emergency heal. Takes priority over Chain Heal.")
    ui:Tip(self.chainCB.cb, "Chain Heal", "AoE heal that bounces between hurt allies.")
    ui:Tip(self.lhwSlider, "Lesser HW HP", "Use Lesser Healing Wave when a target drops under this health.")
    ui:Tip(self.chainSlider, "Chain Heal count", "How many hurt allies are needed before Chain Heal fires.")
    ui:Tip(self.totemsCB.cb, "Maintain totems", "While nobody needs healing, keep the totems below dropped (re-cast on a timer).")
    ui:Tip(self.weaveCB.cb, "Weave damage", "When nobody needs healing and you have an enemy targeted, cast Lightning Bolt in the downtime.", "Mana-gated so it never starves heals. Off by default - same as /ar weave on|off.")
    ui:Tip(self.weaveSlider, "Weave mana floor", "Only weave damage while your mana is above this percent.")
    ui:Tip(self.waterDD, "Water totem", "Which water totem to keep down. Mana Spring restores party mana.")
    ui:Tip(self.earthDD, "Earth totem", "Which earth totem to keep down (or none).")
    ui:Tip(self.fireDD, "Fire totem", "Which fire totem to keep down (or none).")
    ui:Tip(self.airDD, "Air totem", "Which air totem to keep down (or none).")
end

-- ============================================================
-- refresh body (shaman binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- mode dropdown (short labels for the compact window; detail is in the tip)
    local modeOpts = {
        { label = "Enhancement", value = "enhancement" },
        { label = "Elemental",   value = "elemental" },
        { label = "Tank",        value = "tank" },
        { label = "Restoration", value = "restoration" },
    }
    local modeLabel = { enhancement = "Enhancement", elemental = "Elemental", tank = "Tank", restoration = "Restoration" }
    local mcur = buf.mode or "enhancement"
    ui:SetDropdown(self.modeDD, modeOpts, mcur, modeLabel[mcur] or mcur, ui.COL.white)

    -- shield dropdown (colour red if the chosen shield is not learned)
    local shieldOpts = {
        { label = "Lightning Shield", value = "lightning" },
        { label = "Water Shield",     value = "water" },
        { label = "Earth Shield",     value = "earth" },
        { label = "(none)",           value = "none" },
    }
    local shieldLabel = { lightning = "Lightning Shield", water = "Water Shield", earth = "Earth Shield", none = "(none)" }
    local shcur = buf.shield or "lightning"
    local shName = self.SHIELDS[shcur] or ""
    local shShown, shCol = shieldLabel[shcur] or shcur, ui.COL.white
    if shcur ~= "none" and not self:KnowsSpell(shName) then shShown, shCol = (shieldLabel[shcur] or shcur) .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.shieldDD, shieldOpts, shcur, shShown, shCol)

    -- shock dropdown (colour red if the chosen shock is not learned)
    local shockOpts = {
        { label = "Earth Shock", value = "earth" },
        { label = "Frost Shock", value = "frost" },
        { label = "Flame Shock", value = "flame" },
        { label = "(none)",      value = "none" },
    }
    local shockLabel = { earth = "Earth Shock", frost = "Frost Shock", flame = "Flame Shock", none = "(none)" }
    local skcur = buf.shock or "earth"
    local skName = self.SHOCKS[skcur] or ""
    local skShown, skCol = shockLabel[skcur] or skcur, ui.COL.white
    if skcur ~= "none" and not self:KnowsSpell(skName) then skShown, skCol = (shockLabel[skcur] or skcur) .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.shockDD, shockOpts, skcur, skShown, skCol)

    ui:BindCheck(self.ssCB, buf.useStormstrike)
    ui:BindCheck(self.lsCB, buf.useLightningStrike)
    ui:BindCheck(self.lbCB, buf.lbFiller)
    ui:BindCheck(self.searCB, buf.useSearingTotem)
    ui:BindCheck(self.emCB, buf.useElementalMastery)
    ui:BindCheck(self.blCB, buf.useBloodlust)
    ui:BindCheck(self.tauntCB, buf.useTaunt)
    -- Restoration (Heal) block: toggles mirror the rotation's defaults; sliders and
    -- totem pickers are live only on-spec (and, where it applies, with the spell known).
    local isResto = buf.mode == "restoration"
    ui:BindCheck(self.manaTideCB, buf.useManaTide ~= false, "Mana Tide Totem")
    ui:BindCheck(self.nsCB, buf.useNSCombo ~= false)
    ui:BindCheck(self.lhwCB, buf.useLesserHW ~= false, "Lesser Healing Wave")
    ui:BindCheck(self.chainCB, buf.useChainHeal ~= false, "Chain Heal")
    ui:BindCheck(self.totemsCB, buf.useTotems ~= false)
    ui:BindCheck(self.weaveCB, buf.weaveDamage)
    -- NS is dual-named (Nature's / Ancestral Swiftness); grey the label if neither is known.
    if not self:NSSpell() then
        self.nsCB.label:SetText("Nature's Swiftness (not learned)"); ui:Color(self.nsCB.label, ui.COL.grey)
    end

    -- totem pickers: ordered options with a red "(not learned)" when the pick is unknown.
    local function totemDD(dd, opts, cur, tbl, fallback)
        cur = cur or fallback
        local label = "(none)"
        for i = 1, table.getn(opts) do if opts[i].value == cur then label = opts[i].label end end
        local shown, c = label, ui.COL.white
        local spell = tbl[cur]
        if cur ~= "none" and spell and spell ~= "" and not self:KnowsSpell(spell) then
            shown, c = label .. " (not learned)", ui.COL.red
        end
        ui:SetDropdown(dd, opts, cur, shown, c)
    end
    local waterOpts = { { label = "Mana Spring Totem", value = "manaspring" }, { label = "Healing Stream Totem", value = "healingstream" }, { label = "(none)", value = "none" } }
    local earthOpts = { { label = "Strength of Earth Totem", value = "strength" }, { label = "Stoneskin Totem", value = "stoneskin" }, { label = "Tremor Totem", value = "tremor" }, { label = "(none)", value = "none" } }
    local fireOpts  = { { label = "Searing Totem", value = "searing" }, { label = "Magma Totem", value = "magma" }, { label = "Fire Nova Totem", value = "firenova" }, { label = "Flametongue Totem", value = "flametongue" }, { label = "(none)", value = "none" } }
    local airOpts   = { { label = "Windfury Totem", value = "windfury" }, { label = "Grace of Air Totem", value = "graceofair" }, { label = "Nature Resistance Totem", value = "natureresist" }, { label = "Grounding Totem", value = "grounding" }, { label = "Windwall Totem", value = "windwall" }, { label = "(none)", value = "none" } }
    totemDD(self.waterDD, waterOpts, buf.totemWater, self.WATER_TOTEMS, "manaspring")
    totemDD(self.earthDD, earthOpts, buf.totemEarth, self.EARTH_TOTEMS, "none")
    totemDD(self.fireDD,  fireOpts,  buf.totemFire,  self.FIRE_TOTEMS,  "none")
    totemDD(self.airDD,   airOpts,   buf.totemAir,   self.AIR_TOTEMS,   "none")

    self.restoSection:SetDimmed(not isResto)
    -- BindCheck re-enables every box; keep the resto toggles inert off-spec.
    local restoCBs = { self.manaTideCB, self.nsCB, self.lhwCB, self.chainCB, self.totemsCB, self.weaveCB }
    for i = 1, table.getn(restoCBs) do
        if isResto then restoCBs[i].cb:Enable() else restoCBs[i].cb:Disable() end
    end
    local function rs(slider, on, val, suffix)
        slider:SetValue(val)
        if slider.valText then slider.valText:SetText(val .. (suffix or "")) end
        ui:SliderEnable(slider, on and true or false)
    end
    rs(self.htSlider, isResto, buf.healThreshold or 90, "%")
    rs(self.hpowSlider, isResto, buf.healPower or 0, "")
    rs(self.manaTideSlider, isResto and buf.useManaTide ~= false and self:KnowsSpell("Mana Tide Totem"), buf.manaTideAt or 25, "%")
    rs(self.nsSlider, isResto and buf.useNSCombo ~= false and self:NSSpell(), buf.nsHpPct or 40, "%")
    rs(self.lhwSlider, isResto and buf.useLesserHW ~= false and self:KnowsSpell("Lesser Healing Wave"), buf.lhwPct or 50, "%")
    rs(self.chainSlider, isResto and buf.useChainHeal ~= false and self:KnowsSpell("Chain Heal"), buf.chainHealCount or 3, "")
    rs(self.weaveSlider, isResto and buf.weaveDamage, buf.weaveManaFloor or 40, "%")
    -- totem pickers follow the master toggle, on-spec
    local totemsOn = isResto and buf.useTotems ~= false
    local totemDDs = { self.waterDD, self.earthDD, self.fireDD, self.airDD }
    for i = 1, table.getn(totemDDs) do
        if totemsOn then totemDDs[i]:Enable() else totemDDs[i]:Disable() end
    end

    -- Active-spec focus: melee strikes are dead weight while casting or healing, so
    -- fade + lock them in Elemental and Restoration. Enhancement and Tank stay lit.
    self.meleeSection:SetDimmed(buf.mode == "elemental" or buf.mode == "restoration")
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
