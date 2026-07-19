-- ============================================================
-- Class_Shaman_UI  -  shaman window body for Aegis_SBR
-- Builds and binds only the shaman specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.SHAMAN
M.useScrollLayout = true
M.specTabs = {
    field = "mode", default = "enhancement",
    tabs = {
        { key = "elemental",   label = "Elemental",      tip1 = "Caster rotation." },
        { key = "enhancement", label = "Enhance (DPS)",  tip1 = "Melee rotation." },
        { key = "tank",        label = "Enhance (Tank)", tip1 = "Threat-focused melee rotation.", tip2 = "Same config as DPS; the rotation prioritises threat." },
        { key = "restoration", label = "Restoration",    tip1 = "One-button group healing. Runs without an enemy target." },
    },
}

-- ============================================================
-- build body (shaman controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Shield & shock")
    self.shieldDD = L:Dropdown("shield", "Shield", 150, set("shield"))
    self.shockDD  = L:Dropdown("shock", "Shock", 150, set("shock"))

    self.meleeSection = L:Header("Melee strikes", { enhancement = true, tank = true })
    self.ssRow = L:Row{ key = "useStormstrike", label = "Stormstrike", spell = "Stormstrike", onToggle = set("useStormstrike") }
    self.lsRow = L:Row{ key = "useLightningStrike", label = "Lightning Strike", spell = "Lightning Strike", onToggle = set("useLightningStrike") }

    L:Header("Casting & totems")
    self.lbRow = L:Row{ key = "lbFiller", label = "Lightning Bolt", spell = "Lightning Bolt", onToggle = set("lbFiller") }

    -- Totems apply to EVERY spec (Windfury for Enhance, Searing for Ele, etc.),
    -- so this section is shared, not gated to Restoration. The rotation drops
    -- the picked totem in each element slot during a lull.
    L:Header("Totems")
    self.totemsRow = L:Row{ key = "useTotems", label = "Maintain totems", onToggle = set("useTotems") }
    self.waterDD = L:Dropdown("totemWater", "Water totem", 160, set("totemWater"))
    self.earthDD = L:Dropdown("totemEarth", "Earth totem", 160, set("totemEarth"))
    self.fireDD  = L:Dropdown("totemFire", "Fire totem", 160, set("totemFire"))
    self.airDD   = L:Dropdown("totemAir", "Air totem", 160, set("totemAir"))

    L:Header("Cooldowns & utility")
    self.emRow = L:Row{ key = "useElementalMastery", label = "Elemental Mastery", spell = "Elemental Mastery", onToggle = set("useElementalMastery") }
    self.blRow = L:Row{ key = "useBloodlust", label = "Bloodlust", spell = "Bloodlust", onToggle = set("useBloodlust") }
    self.tauntRow = L:Row{ key = "useTaunt", label = "Earthshaker taunt", spell = "Earthshaker Slam", onToggle = set("useTaunt") }

    -- Weapon imbue upkeep (melee specs). Main-hand only; auto-applies out of
    -- combat, reminds in combat unless "Apply in combat" is on.
    self.imbueSection = L:Header("Weapon imbue", { enhancement = true, tank = true })
    self.imbueRow = L:Row{ key = "maintainImbue", label = "Maintain imbue", onToggle = set("maintainImbue") }
    self.imbueDD = L:Dropdown("imbueMain", "Imbue", 160, set("imbueMain"))
    self.imbueThreshRow = L:Row{ label = "Warn under",
        slider = { key = "imbueThresholdMin", min = 0, max = 10, step = 1, suffix = " min", onChange = set("imbueThresholdMin") } }
    self.imbueCombatRow = L:Row{ key = "imbueInCombat", label = "Apply in combat", onToggle = set("imbueInCombat") }

    self.restoSection = L:Header("Restoration (Heal)", "restoration")
    self.htRow = L:Row{ label = "Heal below",
        slider = { key = "healThreshold", min = 50, max = 100, step = 5, suffix = "%", onChange = set("healThreshold") } }
    self.hpowRow = L:Row{ label = "Heal power", sub = "+healing for downranks",
        slider = { key = "healPower", min = 0, max = 2000, step = 50, suffix = "", onChange = set("healPower") } }
    self.manaTideRow = L:Row{ key = "useManaTide", label = "Mana Tide", spell = "Mana Tide Totem", onToggle = set("useManaTide"),
        slider = { key = "manaTideAt", min = 0, max = 60, step = 5, suffix = "%", onChange = set("manaTideAt") } }
    self.nsRow = L:Row{ key = "useNSCombo", label = "Nature's Swiftness", onToggle = set("useNSCombo"),
        slider = { key = "nsHpPct", min = 10, max = 70, step = 5, suffix = "%", onChange = set("nsHpPct") } }
    self.lhwRow = L:Row{ key = "useLesserHW", label = "Lesser Heal Wave", spell = "Lesser Healing Wave", onToggle = set("useLesserHW"),
        slider = { key = "lhwPct", min = 20, max = 90, step = 5, suffix = "%", onChange = set("lhwPct") } }
    self.chainRow = L:Row{ key = "useChainHeal", label = "Chain Heal", spell = "Chain Heal", onToggle = set("useChainHeal"),
        slider = { key = "chainHealCount", min = 2, max = 8, step = 1, suffix = "", onChange = set("chainHealCount") } }
    self.weaveRow = L:Row{ key = "weaveDamage", label = "Weave damage", onToggle = set("weaveDamage"),
        slider = { key = "weaveManaFloor", min = 0, max = 90, step = 5, suffix = "%", onChange = set("weaveManaFloor") } }

    L:Finish()

    ui:Tip(self.shieldDD, "Shield", "Kept up automatically. Lightning Shield for damage/threat, Water Shield for mana.")
    ui:Tip(self.shockDD, "Shock", "One shock on the shared cooldown. Flame Shock is kept up as a DoT; Earth/Frost are cast on cooldown.")
    ui:Tip(self.ssRow.cb, "Stormstrike", "Talented melee strike. Grants a buff boosting your next 2 Nature hits by 20% - the rotation follows it with a shock. Auto-detected when learned.")
    ui:Tip(self.lsRow.cb, "Lightning Strike", "Talented melee instant that also fires an empowered version of your active shield. Auto-detected when learned.")
    ui:Tip(self.lbRow.cb, "Lightning Bolt filler", "Weave Lightning Bolt when nothing else is queued. This is also the main damage at low levels.")
    ui:Tip(self.emRow.cb, "Elemental Mastery", "Pop before a nuke for a guaranteed crit (feeds Clearcasting and Electrify). Off the global cooldown.")
    ui:Tip(self.blRow.cb, "Bloodlust", "Self melee/cast haste burst (Turtle: self-only). Used in combat when off cooldown.")
    ui:Tip(self.tauntRow.cb, "Earthshaker Slam", "Tank taunt, cast only when the target is not already attacking you. Requires a shield.")
    ui:Tip(self.htRow.slider, "Heal threshold", "An ally below this health counts as hurt and pulls a heal. Everything in this section keys off it.")
    ui:Tip(self.hpowRow.slider, "Heal power", "Your bonus healing (+heal) from gear. Used to size downranks so each heal just covers the deficit.", "Leave at 0 to heal by rank only.")
    ui:Tip(self.manaTideRow.cb, "Mana Tide Totem", "Dropped when your own mana runs low, to refill the party.")
    ui:Tip(self.nsRow.cb, "Nature's Swiftness", "Pop NS (or Ancestral Swiftness) for an instant max Healing Wave when someone is in real trouble.")
    ui:Tip(self.manaTideRow.slider, "Mana Tide mana", "Drop Mana Tide once your mana falls under this percent.")
    ui:Tip(self.nsRow.slider, "Nat. Swiftness HP", "Trigger the instant NS heal when a target drops under this health.")
    ui:Tip(self.lhwRow.cb, "Lesser Healing Wave", "Fast single-target emergency heal. Takes priority over Chain Heal.")
    ui:Tip(self.chainRow.cb, "Chain Heal", "AoE heal that bounces between hurt allies.")
    ui:Tip(self.lhwRow.slider, "Lesser HW HP", "Use Lesser Healing Wave when a target drops under this health.")
    ui:Tip(self.chainRow.slider, "Chain Heal count", "How many hurt allies are needed before Chain Heal fires.")
    ui:Tip(self.totemsRow.cb, "Maintain totems", "Keeps the totems below dropped in every spec, re-cast during a lull. Cast timing is tracked from your actual casts (SuperWoW), not a blind clock.")
    ui:Tip(self.weaveRow.cb, "Weave damage", "When nobody needs healing and you have an enemy targeted, cast Lightning Bolt in the downtime.", "Mana-gated so it never starves heals. Off by default - same as /sbr weave on|off.")
    ui:Tip(self.weaveRow.slider, "Weave mana floor", "Only weave damage while your mana is above this percent.")
    ui:Tip(self.waterDD, "Water totem", "Which water totem to keep down. Mana Spring restores party mana.")
    ui:Tip(self.earthDD, "Earth totem", "Which earth totem to keep down (or none).")
    ui:Tip(self.fireDD, "Fire totem", "Which fire totem to keep down (or none).")
    ui:Tip(self.airDD, "Air totem", "Which air totem to keep down (or none).")
    ui:Tip(self.imbueRow.cb, "Maintain imbue", "Keep a main-hand weapon imbue up. Auto-applies only when the weapon is bare and you're out of combat (or on approach); in combat it reminds you unless 'Apply in combat' is on.", "Off-hand imbue isn't handled yet.")
    ui:Tip(self.imbueDD, "Imbue", "Which main-hand imbue to keep up (Rockbiter / Flametongue / Frostbrand / Windfury).")
    ui:Tip(self.imbueThreshRow.slider, "Warn under", "Warn when the imbue has fewer than this many minutes left. 0 = only act/warn once it is fully gone.")
    ui:Tip(self.imbueCombatRow.cb, "Apply in combat", "Allow re-imbuing during combat (costs a global cooldown). Off by default - imbues are best refreshed between pulls.")
end

-- ============================================================
-- refresh body (shaman binding)
-- ============================================================
function M:RefreshBody(ui, buf)

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

    ui:BindCheck(self.ssRow, buf.useStormstrike)
    ui:BindCheck(self.lsRow, buf.useLightningStrike)
    ui:BindCheck(self.lbRow, buf.lbFiller)
    ui:BindCheck(self.emRow, buf.useElementalMastery)
    ui:BindCheck(self.blRow, buf.useBloodlust)
    ui:BindCheck(self.tauntRow, buf.useTaunt)

    -- Weapon imbue: master toggle, then the picker / threshold / in-combat opt-in
    -- follow it (inert while the master is off).
    ui:BindCheck(self.imbueRow, buf.maintainImbue)
    ui:BindCheck(self.imbueCombatRow, buf.imbueInCombat)
    local imbueOpts = {
        { label = "Rockbiter Weapon",   value = "rockbiter" },
        { label = "Flametongue Weapon", value = "flametongue" },
        { label = "Frostbrand Weapon",  value = "frostbrand" },
        { label = "Windfury Weapon",    value = "windfury" },
        { label = "(none)",             value = "none" },
    }
    local imcur = buf.imbueMain or "windfury"
    local imLabel = "(none)"
    for i = 1, table.getn(imbueOpts) do if imbueOpts[i].value == imcur then imLabel = imbueOpts[i].label end end
    local imShown, imCol = imLabel, ui.COL.white
    local imSpell = self.IMBUES[imcur]
    if imcur ~= "none" and imSpell and imSpell ~= "" and not self:KnowsSpell(imSpell) then
        imShown, imCol = imLabel .. " (not learned)", ui.COL.red
    end
    ui:SetDropdown(self.imbueDD, imbueOpts, imcur, imShown, imCol)
    local imthr = buf.imbueThresholdMin or 0
    self.imbueThreshRow.slider:SetValue(imthr)
    if self.imbueThreshRow.slider.valText then self.imbueThreshRow.slider.valText:SetText(imthr .. " min") end
    -- picker / threshold / in-combat only interactive while imbue upkeep is on
    local imbueOn = buf.maintainImbue and true or false
    if imbueOn then self.imbueDD:Enable() else self.imbueDD:Disable() end
    if imbueOn then self.imbueCombatRow.cb:Enable() else self.imbueCombatRow.cb:Disable() end
    ui:SliderEnable(self.imbueThreshRow.slider, imbueOn)
    -- Restoration (Heal) block: toggles mirror the rotation's defaults; sliders and
    -- totem pickers are live only on-spec (and, where it applies, with the spell known).
    local isResto = buf.mode == "restoration"
    ui:BindCheck(self.manaTideRow, buf.useManaTide ~= false, "Mana Tide Totem")
    ui:BindCheck(self.nsRow, buf.useNSCombo ~= false)
    ui:BindCheck(self.lhwRow, buf.useLesserHW ~= false, "Lesser Healing Wave")
    ui:BindCheck(self.chainRow, buf.useChainHeal ~= false, "Chain Heal")
    ui:BindCheck(self.totemsRow, buf.useTotems ~= false)
    ui:BindCheck(self.weaveRow, buf.weaveDamage)
    -- NS is dual-named (Nature's / Ancestral Swiftness); grey the label if neither is known.
    if not self:NSSpell() then
        self.nsRow.label:SetText("Nature's Swiftness (not learned)"); ui:Color(self.nsRow.label, ui.COL.grey)
        -- dual-named spell, so BindCheck can't hide the slider; do it here so the
        -- full "(not learned)" label gets the whole row.
        self.nsRow.slider:Hide(); if self.nsRow.value then self.nsRow.value:Hide() end
        if self.nsRow.labelFullW then self.nsRow.label:SetWidth(self.nsRow.labelFullW) end
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
    local restoCBs = { self.manaTideRow, self.nsRow, self.lhwRow, self.chainRow, self.weaveRow }
    for i = 1, table.getn(restoCBs) do
        if isResto then restoCBs[i].cb:Enable() else restoCBs[i].cb:Disable() end
    end
    local function rs(slider, on, val, suffix)
        slider:SetValue(val)
        if slider.valText then slider.valText:SetText(val .. (suffix or "")) end
        ui:SliderEnable(slider, on and true or false)
    end
    rs(self.htRow.slider, isResto, buf.healThreshold or 90, "%")
    rs(self.hpowRow.slider, isResto, buf.healPower or 0, "")
    rs(self.manaTideRow.slider, isResto and buf.useManaTide ~= false and self:KnowsSpell("Mana Tide Totem"), buf.manaTideAt or 25, "%")
    rs(self.nsRow.slider, isResto and buf.useNSCombo ~= false and self:NSSpell(), buf.nsHpPct or 40, "%")
    rs(self.lhwRow.slider, isResto and buf.useLesserHW ~= false and self:KnowsSpell("Lesser Healing Wave"), buf.lhwPct or 50, "%")
    rs(self.chainRow.slider, isResto and buf.useChainHeal ~= false and self:KnowsSpell("Chain Heal"), buf.chainHealCount or 3, "")
    rs(self.weaveRow.slider, isResto and buf.weaveDamage, buf.weaveManaFloor or 40, "%")
    -- totem pickers follow the master toggle, on-spec
    -- Totems are shared across specs now: the picker enable follows the
    -- "Maintain totems" toggle only, and that toggle is always interactive.
    self.totemsRow.cb:Enable()
    local totemsOn = buf.useTotems ~= false
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
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
