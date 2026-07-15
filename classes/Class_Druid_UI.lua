-- ============================================================
-- Class_Druid_UI  -  feral druid window body for Aegis_SBR
-- Builds and binds only the druid specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.DRUID
M.useScrollLayout = true
M.specTabs = {
    field = "form", default = "cat",
    tabs = {
        { key = "cat",    label = "Feral (Cat)",  tip1 = "Feral DPS rotation. Entered when you press the macro in caster form." },
        { key = "bear",   label = "Feral (Bear)", tip1 = "Tank rotation." },
        { key = "caster", label = "Balance", tip1 = "Runs the Balance rotation (enters Moonkin when learned).", tip2 = "Before any form is learned this runs automatically, so it works from level 1." },
        { key = "tree",   label = "Restoration", tip1 = "One-button group healing. Runs without an enemy target." },
    },
}

-- ============================================================
-- build body (druid controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Cat Form (DPS)", "cat")
    self.styleDD = L:Dropdown("catStyle", "Style", 170, set("catStyle"))
    self.openerDD = L:Dropdown("opener", "Opener", 170, set("opener"))
    self.tfRow = L:Row{ key = "useTigersFury", label = "Tiger's Fury", spell = "Tiger's Fury", onToggle = set("useTigersFury") }
    self.ffCatRow = L:Row{ key = "ffCat", label = "Faerie Fire", spell = "Faerie Fire (Feral)", onToggle = set("ffCat") }
    self.cpRow = L:Row{ label = "Finisher CP",
        slider = { key = "cpFinish", min = 1, max = 5, step = 1, suffix = "", onChange = set("cpFinish") } }
    self.psRow = L:Row{ key = "powershift", label = "Powershift", onToggle = set("powershift"),
        slider = { key = "psEnergy", min = 0, max = 40, step = 5, suffix = "", onChange = set("psEnergy") } }

    L:Header("Bear Form (Tank)", "bear")
    self.ffBearRow = L:Row{ key = "ffBear", label = "Faerie Fire", spell = "Faerie Fire (Feral)", onToggle = set("ffBear") }
    self.demoRow = L:Row{ key = "useDemo", label = "Demoralizing Roar", spell = "Demoralizing Roar", onToggle = set("useDemo") }
    self.maulRow = L:Row{ key = "useMaul", label = "Maul (rage dump)", spell = "Maul", onToggle = set("useMaul") }
    self.swipeRow = L:Row{ key = "aoeSwipe", label = "Swipe (AoE)", spell = "Swipe", onToggle = set("aoeSwipe") }
    self.enrageRow = L:Row{ key = "useEnrage", label = "Enrage", spell = "Enrage", onToggle = set("useEnrage") }
    self.growlRow = L:Row{ key = "useGrowl", label = "Growl", spell = "Growl", onToggle = set("useGrowl") }

    L:Header("Balance / Caster", "caster")
    self.nukeDD = L:Dropdown("nuke", "Nuke", 170, set("nuke"))
    self.mfRow = L:Row{ key = "useMoonfire", label = "Moonfire", spell = "Moonfire", onToggle = set("useMoonfire") }
    self.isRow = L:Row{ key = "useInsectSwarm", label = "Insect Swarm", spell = "Insect Swarm", onToggle = set("useInsectSwarm") }
    self.eclipseRow = L:Row{ key = "eclipse", label = "Eclipse reaction", onToggle = set("eclipse") }

    self.restoSection = L:Header("Healing", "tree")
    self.htRow = L:Row{ label = "Heal below",
        slider = { key = "healThreshold", min = 50, max = 100, step = 5, suffix = "%", onChange = set("healThreshold") } }
    self.hpowRow = L:Row{ label = "Heal power", sub = "+healing for downranks",
        slider = { key = "healPower", min = 0, max = 2000, step = 50, suffix = "", onChange = set("healPower") } }
    self.innervateRow = L:Row{ key = "useInnervate", label = "Innervate", spell = "Innervate", onToggle = set("useInnervate"),
        slider = { key = "innervateAt", min = 0, max = 60, step = 5, suffix = "%", onChange = set("innervateAt") } }
    self.nsRow = L:Row{ key = "useNSCombo", label = "Nature's Swiftness", spell = "Nature's Swiftness", onToggle = set("useNSCombo"),
        slider = { key = "nsHpPct", min = 10, max = 70, step = 5, suffix = "%", onChange = set("nsHpPct") } }
    self.swiftmendRow = L:Row{ key = "useSwiftmend", label = "Swiftmend", spell = "Swiftmend", onToggle = set("useSwiftmend"),
        slider = { key = "swiftmendPct", min = 20, max = 90, step = 5, suffix = "%", onChange = set("swiftmendPct") } }
    self.regrowthRow = L:Row{ key = "useRegrowth", label = "Regrowth", spell = "Regrowth", onToggle = set("useRegrowth"),
        slider = { key = "regrowthPct", min = 20, max = 90, step = 5, suffix = "%", onChange = set("regrowthPct") } }
    self.wgRow = L:Row{ key = "useWildGrowth", label = "Wild Growth", sub = "allies", spell = "Wild Growth", onToggle = set("useWildGrowth"),
        slider = { key = "wildGrowthCount", min = 2, max = 8, step = 1, suffix = "", onChange = set("wildGrowthCount") } }
    self.rejuvRow = L:Row{ key = "useRejuv", label = "Rejuvenation", spell = "Rejuvenation", onToggle = set("useRejuv") }
    self.lifebloomRow = L:Row{ key = "useLifebloom", label = "Lifebloom", spell = "Lifebloom", onToggle = set("useLifebloom") }

    self.downtimeSection = L:Header("Downtime", "tree")
    self.weaveRow = L:Row{ key = "weaveDamage", label = "Weave damage", onToggle = set("weaveDamage"),
        slider = { key = "weaveManaFloor", min = 0, max = 90, step = 5, suffix = "%", onChange = set("weaveManaFloor") } }

    L:Header("Defense (HP management)")
    self.hpRow = L:Row{ key = "hpManage", label = "Bear Form when HP is low", onToggle = set("hpManage") }
    self.hpLowRow = L:Row{ label = "Switch below",
        slider = { key = "hpLow", min = 0, max = 100, step = 5, suffix = "%", onChange = set("hpLow") } }
    self.hpHighRow = L:Row{ label = "Back above",
        slider = { key = "hpHigh", min = 0, max = 100, step = 5, suffix = "%", onChange = set("hpHigh") } }

    L:Finish()

    ui:Tip(self.styleDD, "Cat style", "Claw & Bleed keeps Rake and Rip rolling (pairs with bleed-energy talents). Shred & Powershift builds with Shred and finishes with Ferocious Bite.", "Use Shred for bleed-immune bosses (MC/BWL). Swap mid-fight with /sbr style.")
    ui:Tip(self.openerDD, "Stealth opener", "Used on the first press while Prowl is up.", "Auto picks Ravage if known (needs behind), else Pounce.")
    ui:Tip(self.tfRow.cb, "Tiger's Fury", "Recast just before the buff falls off.")
    ui:Tip(self.ffCatRow.cb, "Faerie Fire (Feral)", "Free armor debuff, kept up first in the priority.")
    ui:Tip(self.psRow.cb, "Powershift", "Shred style only. When energy is bottomed out, shift to caster and straight back into Cat for a fresh energy bar.", "Never fires while Tiger's Fury is up. Costs mana per re-shift; watch your blue bar.")
    ui:Tip(self.cpRow.slider, "Finisher combo points", "Rip / Ferocious Bite once combo points reach this number.")
    ui:Tip(self.psRow.slider, "Shift below energy", "Powershift only when energy is under this value.")
    ui:Tip(self.ffBearRow.cb, "Faerie Fire (Feral)", "Free threat plus the armor debuff, kept up first.")
    ui:Tip(self.demoRow.cb, "Demoralizing Roar", "Reapplied whenever the debuff is missing.")
    ui:Tip(self.maulRow.cb, "Maul", "Queued on the next swing as the single-target rage dump.")
    ui:Tip(self.swipeRow.cb, "Swipe (AoE)", "When on, Swipe leads the priority for multi-target threat.", "Manual toggle, also /sbr aoe, since 1.12 cannot count nearby enemies.")
    ui:Tip(self.enrageRow.cb, "Enrage", "Used in combat when rage is starved. Lowers your armor while active, so it is off by default.")
    ui:Tip(self.growlRow.cb, "Growl", "Taunts to grab threat on the pull and whenever the target is not focused on you. Faerie Fire (Feral) is the ranged opener that starts damage + threat from a distance.")
    ui:Tip(self.nukeDD, "Primary nuke", "Chain-cast to fish for Eclipse procs.", "Casting Wraths empowers Starfire and vice versa, the rotation swaps automatically on the proc.")
    ui:Tip(self.mfRow.cb, "Moonfire", "Kept up first. At low levels this plus the nuke IS the rotation.")
    ui:Tip(self.isRow.cb, "Insect Swarm", "Kept up right after Moonfire.")
    ui:Tip(self.eclipseRow.cb, "Eclipse reaction", "On a proc, cast the empowered opposite nuke. Casts are queued, so the swap lands the moment the window opens.", "If procs are not detected, run /sbr debug with the proc up and report the buff name.")
    ui:Tip(self.htRow.slider, "Heal threshold", "An ally below this health counts as hurt and pulls a heal. Everything in this section keys off it.")
    ui:Tip(self.hpowRow.slider, "Heal power", "Your bonus healing (+heal) from gear. Used to size downranks so each heal just covers the deficit.", "Leave at 0 to let it heal by rank only.")
    ui:Tip(self.innervateRow.cb, "Innervate", "Cast on yourself when your own mana drops, to keep the fight going.", "Slider: use Innervate once your mana falls under this percent.")
    ui:Tip(self.nsRow.cb, "Nature's Swiftness", "Pop NS for an instant max Healing Touch when someone is in real trouble.", "Slider: trigger the instant NS heal when a target drops under this health.")
    ui:Tip(self.innervateRow.slider, "Innervate mana", "Use Innervate once your mana falls under this percent.")
    ui:Tip(self.nsRow.slider, "Nature's Swiftness HP", "Trigger the instant NS heal when a target drops under this health.")
    ui:Tip(self.swiftmendRow.cb, "Swiftmend", "Instant top-up that consumes a Rejuv or Regrowth already on the target.", "Slider: fire when a target with a HoT drops under this health.")
    ui:Tip(self.regrowthRow.cb, "Regrowth", "Direct heal plus a HoT, used as a burst on a bigger deficit.", "Slider: cast when a target without one drops under this health.")
    ui:Tip(self.swiftmendRow.slider, "Swiftmend HP", "Swiftmend when a target with a HoT drops under this health.")
    ui:Tip(self.regrowthRow.slider, "Regrowth HP", "Cast Regrowth when a target without one drops under this health.")
    ui:Tip(self.wgRow.cb, "Wild Growth", "Turtle AoE HoT. Fires when several allies are hurt at once (if learned).", "Slider: how many hurt allies are needed before it fires.")
    ui:Tip(self.weaveRow.cb, "Weave damage", "When nobody needs healing and you have an enemy targeted, cast Moonfire + Wrath in the downtime.", "Mana-gated so it never starves heals. Off by default - same as /sbr weave on|off.")
    ui:Tip(self.wgRow.slider, "Wild Growth count", "How many hurt allies are needed before Wild Growth fires.")
    ui:Tip(self.weaveRow.slider, "Weave mana floor", "Only weave damage while your mana is above this percent.")
    ui:Tip(self.rejuvRow.cb, "Rejuvenation", "Kept rolling on the hurt target as the baseline maintenance HoT.")
    ui:Tip(self.lifebloomRow.cb, "Lifebloom", "Turtle rolling HoT stack on the target (if learned). Off by default.")
    ui:Tip(self.hpRow.cb, "Defensive Bear", "Below the lower value, force Bear Form (using Frenzied Regeneration when known) until HP is back at the upper value.", "Works from any form, including mid-fight in Cat or Moonkin. Inert until Bear Form is learned.")
    ui:Tip(self.hpLowRow.slider, "Switch below", "Going under this HP percent shifts you into Bear.")
    ui:Tip(self.hpHighRow.slider, "Back above", "Reaching this HP percent releases you back to the preferred form.")
end

-- ============================================================
-- refresh body (druid binding)
-- ============================================================
function M:RefreshBody(ui, buf)

    local styleOpts = {
        { label = "Claw & Bleed",       value = "bleed" },
        { label = "Shred & Powershift", value = "shred" },
    }
    local styleLabel = { bleed = "Claw & Bleed", shred = "Shred & Powershift" }
    local scur = buf.catStyle or "bleed"
    ui:SetDropdown(self.styleDD, styleOpts, scur, styleLabel[scur] or scur, ui.COL.white)

    local openOpts = {
        { label = "Auto (Ravage > Pounce)", value = "auto" },
        { label = "Ravage", value = "Ravage" },
        { label = "Pounce", value = "Pounce" },
        { label = "None",   value = "none" },
    }
    local openLabel = { auto = "Auto (Ravage > Pounce)", Ravage = "Ravage", Pounce = "Pounce", none = "None" }
    local ocur = buf.opener or "auto"
    local oshown, oc = openLabel[ocur] or ocur, ui.COL.white
    if (ocur == "Ravage" or ocur == "Pounce") and not self:KnowsSpell(ocur) then
        oshown, oc = ocur .. " (not learned)", ui.COL.red
    end
    ui:SetDropdown(self.openerDD, openOpts, ocur, oshown, oc)

    ui:BindCheck(self.tfRow, buf.useTigersFury)
    ui:BindCheck(self.ffCatRow, buf.ffCat)
    ui:BindCheck(self.psRow, buf.powershift)
    ui:BindCheck(self.ffBearRow, buf.ffBear)
    ui:BindCheck(self.demoRow, buf.useDemo)
    ui:BindCheck(self.maulRow, buf.useMaul)
    ui:BindCheck(self.swipeRow, buf.aoeSwipe)
    ui:BindCheck(self.enrageRow, buf.useEnrage)
    ui:BindCheck(self.growlRow, buf.useGrowl)
    ui:BindCheck(self.mfRow, buf.useMoonfire)
    ui:BindCheck(self.isRow, buf.useInsectSwarm)
    ui:BindCheck(self.eclipseRow, buf.eclipse)
    -- Healing + Downtime cards (concept rows). Toggles mirror the rotation's
    -- defaults (most on unless explicitly disabled); each slider carries its
    -- value and is live only on-spec, with its toggle on and the spell learned.
    local isResto = (buf.form or "cat") == "tree"
    ui:BindCheck(self.innervateRow, buf.useInnervate ~= false, "Innervate")
    ui:BindCheck(self.nsRow, buf.useNSCombo ~= false, "Nature's Swiftness")
    ui:BindCheck(self.swiftmendRow, buf.useSwiftmend ~= false, "Swiftmend")
    ui:BindCheck(self.regrowthRow, buf.useRegrowth ~= false, "Regrowth")
    ui:BindCheck(self.wgRow, buf.useWildGrowth, "Wild Growth")
    ui:BindCheck(self.weaveRow, buf.weaveDamage)
    ui:BindCheck(self.rejuvRow, buf.useRejuv ~= false, "Rejuvenation")
    ui:BindCheck(self.lifebloomRow, buf.useLifebloom, "Lifebloom")
    self.restoSection:SetDimmed(not isResto)
    self.downtimeSection:SetDimmed(not isResto)
    -- BindCheck re-enables every box; keep them inert off-spec.
    local restoCBs = { self.innervateRow, self.nsRow, self.swiftmendRow, self.regrowthRow,
                       self.wgRow, self.weaveRow, self.rejuvRow, self.lifebloomRow }
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
    rs(self.innervateRow.slider, isResto and buf.useInnervate ~= false and self:KnowsSpell("Innervate"), buf.innervateAt or 30, "%")
    rs(self.nsRow.slider, isResto and buf.useNSCombo ~= false and self:KnowsSpell("Nature's Swiftness"), buf.nsHpPct or 40, "%")
    rs(self.swiftmendRow.slider, isResto and buf.useSwiftmend ~= false and self:KnowsSpell("Swiftmend"), buf.swiftmendPct or 65, "%")
    rs(self.regrowthRow.slider, isResto and buf.useRegrowth ~= false and self:KnowsSpell("Regrowth"), buf.regrowthPct or 55, "%")
    rs(self.wgRow.slider, isResto and buf.useWildGrowth and self:KnowsSpell("Wild Growth"), buf.wildGrowthCount or 4, "")
    rs(self.weaveRow.slider, isResto and buf.weaveDamage, buf.weaveManaFloor or 40, "%")

    -- defense block: needs a bear form; sliders follow the checkbox
    local bearKnown = self:KnowsSpell("Bear Form") or self:KnowsSpell("Dire Bear Form")
    self.hpRow.cb:SetChecked(buf.hpManage and true or false)
    if bearKnown then
        self.hpRow.cb:Enable()
        self.hpRow.label:SetText(self.hpRow.baseText); ui:Color(self.hpRow.label, ui.COL.white)
    else
        self.hpRow.cb:Disable()
        self.hpRow.label:SetText(self.hpRow.baseText .. " (needs Bear Form)"); ui:Color(self.hpRow.label, ui.COL.grey)
    end
    local defOn = bearKnown and buf.hpManage
    self.hpLowRow.slider:SetValue(buf.hpLow or 35);   self.hpLowRow.slider.valText:SetText((buf.hpLow or 35) .. "%")
    self.hpHighRow.slider:SetValue(buf.hpHigh or 70); self.hpHighRow.slider.valText:SetText((buf.hpHigh or 70) .. "%")
    ui:SliderEnable(self.hpLowRow.slider, defOn and true or false)
    ui:SliderEnable(self.hpHighRow.slider, defOn and true or false)

    -- nuke dropdown: Wrath always (level 1), Starfire once known
    local nOpts = { { label = "Wrath", value = "Wrath" } }
    if self:KnowsSpell("Starfire") then table.insert(nOpts, { label = "Starfire", value = "Starfire" }) end
    local ncur = buf.nuke or "Wrath"
    local nshown, nc = ncur, ui.COL.white
    if ncur ~= "Wrath" and not self:KnowsSpell(ncur) then nshown, nc = ncur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.nukeDD, nOpts, ncur, nshown, nc)

    -- powershift is only meaningful in the Shred style
    if (buf.catStyle or "bleed") == "shred" then
        self.psRow.cb:Enable()
        self.psRow.label:SetText("Powershift"); ui:Color(self.psRow.label, ui.COL.white)
        ui:SliderEnable(self.psRow.slider, true)
    else
        self.psRow.cb:Disable()
        self.psRow.label:SetText("Powershift - Shred style only"); ui:Color(self.psRow.label, ui.COL.grey)
        ui:SliderEnable(self.psRow.slider, false)
    end

    local cpv = buf.cpFinish or 5
    self.cpRow.slider:SetValue(cpv)
    if self.cpRow.slider.valText then self.cpRow.slider.valText:SetText(tostring(cpv)) end
    local psv = buf.psEnergy or 15
    self.psRow.slider:SetValue(psv)
    if self.psRow.slider.valText then self.psRow.slider.valText:SetText(tostring(psv)) end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI framework not loaded. Aegis_SBR_UI.lua is missing or mislabeled in your Aegis_SBR folder, reinstall the files.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
