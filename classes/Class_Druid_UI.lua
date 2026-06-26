-- ============================================================
-- Class_Druid_UI  -  feral druid window body for AutoRota
-- Builds and binds only the druid specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = AutoRota.classes.DRUID
M.useScrollLayout = true

-- ============================================================
-- build body (druid controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Form")
    self.formDD = L:Dropdown("form", "Preferred", 170, set("form"))

    L:Header("Cat Form (DPS)")
    self.styleDD = L:Dropdown("catStyle", "Style", 170, set("catStyle"))
    self.openerDD = L:Dropdown("opener", "Opener", 170, set("opener"))
    self.tfCB, self.ffCatCB = L:CheckPair(
        { "useTigersFury", "Tiger's Fury", "Tiger's Fury", set("useTigersFury") },
        { "ffCat", "Faerie Fire", "Faerie Fire (Feral)", set("ffCat") })
    self.psCB = L:Check("powershift", "Powershift", nil, set("powershift"))
    self.cpSlider, self.psSlider = L:SliderPair(
        { "cpFinish", "Finisher CP", { min = 1, max = 5, step = 1, suffix = "" }, set("cpFinish") },
        { "psEnergy", "Shift below energy", { min = 0, max = 40, step = 5, suffix = "" }, set("psEnergy") })

    L:Header("Bear Form (Tank)")
    self.ffBearCB, self.demoCB = L:CheckPair(
        { "ffBear", "Faerie Fire", "Faerie Fire (Feral)", set("ffBear") },
        { "useDemo", "Demoralizing Roar", "Demoralizing Roar", set("useDemo") })
    self.maulCB, self.swipeCB = L:CheckPair(
        { "useMaul", "Maul (rage dump)", "Maul", set("useMaul") },
        { "aoeSwipe", "Swipe (AoE)", "Swipe", set("aoeSwipe") })
    self.enrageCB, self.growlCB = L:CheckPair(
        { "useEnrage", "Enrage", "Enrage", set("useEnrage") },
        { "useGrowl", "Growl", "Growl", set("useGrowl") })

    L:Header("Balance / Caster")
    self.nukeDD = L:Dropdown("nuke", "Nuke", 170, set("nuke"))
    self.mfCB, self.isCB = L:CheckPair(
        { "useMoonfire", "Moonfire", "Moonfire", set("useMoonfire") },
        { "useInsectSwarm", "Insect Swarm", "Insect Swarm", set("useInsectSwarm") })
    self.eclipseCB = L:Check("eclipse", "Eclipse reaction", nil, set("eclipse"))

    self.restoSection = L:Header("Restoration (Heal)")
    self.htSlider, self.hpowSlider = L:SliderPair(
        { "healThreshold", "Heal below", { min = 50, max = 100, step = 5, suffix = "%" }, set("healThreshold") },
        { "healPower", "Heal power", { min = 0, max = 2000, step = 50, suffix = "" }, set("healPower") })
    self.innervateCB, self.nsCB = L:CheckPair(
        { "useInnervate", "Innervate", "Innervate", set("useInnervate") },
        { "useNSCombo", "Nature's Swiftness", "Nature's Swiftness", set("useNSCombo") })
    self.innervateSlider, self.nsSlider = L:SliderPair(
        { "innervateAt", "Innervate mana", { min = 0, max = 60, step = 5, suffix = "%" }, set("innervateAt") },
        { "nsHpPct", "Nat.Swift HP", { min = 10, max = 70, step = 5, suffix = "%" }, set("nsHpPct") })
    self.swiftmendCB, self.regrowthCB = L:CheckPair(
        { "useSwiftmend", "Swiftmend", "Swiftmend", set("useSwiftmend") },
        { "useRegrowth", "Regrowth", "Regrowth", set("useRegrowth") })
    self.swiftmendSlider, self.regrowthSlider = L:SliderPair(
        { "swiftmendPct", "Swiftmend HP", { min = 20, max = 90, step = 5, suffix = "%" }, set("swiftmendPct") },
        { "regrowthPct", "Regrowth HP", { min = 20, max = 90, step = 5, suffix = "%" }, set("regrowthPct") })
    self.wildGrowthCB, self.weaveCB = L:CheckPair(
        { "useWildGrowth", "Wild Growth", "Wild Growth", set("useWildGrowth") },
        { "weaveDamage", "Weave damage", nil, set("weaveDamage") })
    self.wgSlider, self.weaveSlider = L:SliderPair(
        { "wildGrowthCount", "Wild Growth #", { min = 2, max = 8, step = 1, suffix = "" }, set("wildGrowthCount") },
        { "weaveManaFloor", "Weave floor", { min = 0, max = 90, step = 5, suffix = "%" }, set("weaveManaFloor") })
    self.rejuvCB, self.lifebloomCB = L:CheckPair(
        { "useRejuv", "Rejuvenation", "Rejuvenation", set("useRejuv") },
        { "useLifebloom", "Lifebloom", "Lifebloom", set("useLifebloom") })

    L:Header("Defense (HP management)")
    self.hpCB = L:Check("hpManage", "Bear Form when HP is low", nil, set("hpManage"))
    self.hpLowSlider, self.hpHighSlider = L:SliderPair(
        { "hpLow", "Switch below", set("hpLow") },
        { "hpHigh", "Back above", set("hpHigh") })

    L:Finish()

    ui:Tip(self.formDD, "Preferred form", "Entered when you press the macro in caster form. Caster/Moonkin runs the Balance rotation (and enters Moonkin when learned).", "Before any form is learned, the caster rotation runs automatically, so this works from level 1.")
    ui:Tip(self.styleDD, "Cat style", "Claw & Bleed keeps Rake and Rip rolling (pairs with bleed-energy talents). Shred & Powershift builds with Shred and finishes with Ferocious Bite.", "Use Shred for bleed-immune bosses (MC/BWL). Swap mid-fight with /ar style.")
    ui:Tip(self.openerDD, "Stealth opener", "Used on the first press while Prowl is up.", "Auto picks Ravage if known (needs behind), else Pounce.")
    ui:Tip(self.tfCB.cb, "Tiger's Fury", "Recast just before the buff falls off.")
    ui:Tip(self.ffCatCB.cb, "Faerie Fire (Feral)", "Free armor debuff, kept up first in the priority.")
    ui:Tip(self.psCB.cb, "Powershift", "Shred style only. When energy is bottomed out, shift to caster and straight back into Cat for a fresh energy bar.", "Never fires while Tiger's Fury is up. Costs mana per re-shift; watch your blue bar.")
    ui:Tip(self.cpSlider, "Finisher combo points", "Rip / Ferocious Bite once combo points reach this number.")
    ui:Tip(self.psSlider, "Shift below energy", "Powershift only when energy is under this value.")
    ui:Tip(self.ffBearCB.cb, "Faerie Fire (Feral)", "Free threat plus the armor debuff, kept up first.")
    ui:Tip(self.demoCB.cb, "Demoralizing Roar", "Reapplied whenever the debuff is missing.")
    ui:Tip(self.maulCB.cb, "Maul", "Queued on the next swing as the single-target rage dump.")
    ui:Tip(self.swipeCB.cb, "Swipe (AoE)", "When on, Swipe leads the priority for multi-target threat.", "Manual toggle, also /ar aoe, since 1.12 cannot count nearby enemies.")
    ui:Tip(self.enrageCB.cb, "Enrage", "Used in combat when rage is starved. Lowers your armor while active, so it is off by default.")
    ui:Tip(self.growlCB.cb, "Growl", "Taunts to grab threat on the pull and whenever the target is not focused on you. Faerie Fire (Feral) is the ranged opener that starts damage + threat from a distance.")
    ui:Tip(self.nukeDD, "Primary nuke", "Chain-cast to fish for Eclipse procs.", "Casting Wraths empowers Starfire and vice versa, the rotation swaps automatically on the proc.")
    ui:Tip(self.mfCB.cb, "Moonfire", "Kept up first. At low levels this plus the nuke IS the rotation.")
    ui:Tip(self.isCB.cb, "Insect Swarm", "Kept up right after Moonfire.")
    ui:Tip(self.eclipseCB.cb, "Eclipse reaction", "On a proc, cast the empowered opposite nuke. Casts are queued, so the swap lands the moment the window opens.", "If procs are not detected, run /ar debug with the proc up and report the buff name.")
    ui:Tip(self.htSlider, "Heal threshold", "An ally below this health counts as hurt and pulls a heal. Everything in this section keys off it.")
    ui:Tip(self.hpowSlider, "Heal power", "Your bonus healing (+heal) from gear. Used to size downranks so each heal just covers the deficit.", "Leave at 0 to let it heal by rank only.")
    ui:Tip(self.innervateCB.cb, "Innervate", "Cast on yourself when your own mana drops, to keep the fight going.")
    ui:Tip(self.nsCB.cb, "Nature's Swiftness", "Pop NS for an instant max Healing Touch when someone is in real trouble.")
    ui:Tip(self.innervateSlider, "Innervate mana", "Use Innervate once your mana falls under this percent.")
    ui:Tip(self.nsSlider, "Nat. Swiftness HP", "Trigger the instant NS heal when a target drops under this health.")
    ui:Tip(self.swiftmendCB.cb, "Swiftmend", "Instant top-up that consumes a Rejuv or Regrowth already on the target.")
    ui:Tip(self.regrowthCB.cb, "Regrowth", "Direct heal plus a HoT, used as a burst on a bigger deficit.")
    ui:Tip(self.swiftmendSlider, "Swiftmend HP", "Swiftmend when a target with a HoT drops under this health.")
    ui:Tip(self.regrowthSlider, "Regrowth HP", "Cast Regrowth when a target without one drops under this health.")
    ui:Tip(self.wildGrowthCB.cb, "Wild Growth", "Turtle AoE HoT. Fires when several allies are hurt at once (if learned).")
    ui:Tip(self.weaveCB.cb, "Weave damage", "When nobody needs healing and you have an enemy targeted, cast Moonfire + Wrath in the downtime.", "Mana-gated so it never starves heals. Off by default - same as /ar weave on|off.")
    ui:Tip(self.wgSlider, "Wild Growth count", "How many hurt allies are needed before Wild Growth fires.")
    ui:Tip(self.weaveSlider, "Weave mana floor", "Only weave damage while your mana is above this percent.")
    ui:Tip(self.rejuvCB.cb, "Rejuvenation", "Kept rolling on the hurt target as the baseline maintenance HoT.")
    ui:Tip(self.lifebloomCB.cb, "Lifebloom", "Turtle rolling HoT stack on the target (if learned). Off by default.")
    ui:Tip(self.hpCB.cb, "Defensive Bear", "Below the lower value, force Bear Form (using Frenzied Regeneration when known) until HP is back at the upper value.", "Works from any form, including mid-fight in Cat or Moonkin. Inert until Bear Form is learned.")
    ui:Tip(self.hpLowSlider, "Switch below", "Going under this HP percent shifts you into Bear.")
    ui:Tip(self.hpHighSlider, "Back above", "Reaching this HP percent releases you back to the preferred form.")
end

-- ============================================================
-- refresh body (druid binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    local formOpts = {
        { label = "Cat Form",  value = "cat" },
        { label = "Bear Form", value = "bear" },
        { label = "Caster / Moonkin", value = "caster" },
        { label = "Restoration (Heal)", value = "tree" },
    }
    local formLabel = { cat = "Cat Form", bear = "Bear Form", caster = "Caster / Moonkin", tree = "Restoration (Heal)" }
    local fcur = buf.form or "cat"
    ui:SetDropdown(self.formDD, formOpts, fcur, formLabel[fcur] or fcur, ui.COL.white)

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

    ui:BindCheck(self.tfCB, buf.useTigersFury)
    ui:BindCheck(self.ffCatCB, buf.ffCat)
    ui:BindCheck(self.psCB, buf.powershift)
    ui:BindCheck(self.ffBearCB, buf.ffBear)
    ui:BindCheck(self.demoCB, buf.useDemo)
    ui:BindCheck(self.maulCB, buf.useMaul)
    ui:BindCheck(self.swipeCB, buf.aoeSwipe)
    ui:BindCheck(self.enrageCB, buf.useEnrage)
    ui:BindCheck(self.growlCB, buf.useGrowl)
    ui:BindCheck(self.mfCB, buf.useMoonfire)
    ui:BindCheck(self.isCB, buf.useInsectSwarm)
    ui:BindCheck(self.eclipseCB, buf.eclipse)
    -- Restoration (Heal) block. Toggles mirror the rotation's defaults (most on
    -- unless explicitly disabled); each threshold slider carries its value and is
    -- live only on-spec, with its toggle on and the spell learned.
    local isResto = (buf.form or "cat") == "tree"
    ui:BindCheck(self.innervateCB, buf.useInnervate ~= false, "Innervate")
    ui:BindCheck(self.nsCB, buf.useNSCombo ~= false, "Nature's Swiftness")
    ui:BindCheck(self.swiftmendCB, buf.useSwiftmend ~= false, "Swiftmend")
    ui:BindCheck(self.regrowthCB, buf.useRegrowth ~= false, "Regrowth")
    ui:BindCheck(self.wildGrowthCB, buf.useWildGrowth, "Wild Growth")
    ui:BindCheck(self.weaveCB, buf.weaveDamage)
    ui:BindCheck(self.rejuvCB, buf.useRejuv ~= false, "Rejuvenation")
    ui:BindCheck(self.lifebloomCB, buf.useLifebloom, "Lifebloom")
    self.restoSection:SetDimmed(not isResto)
    -- BindCheck re-enables every box; keep them inert off-spec.
    local restoCBs = { self.innervateCB, self.nsCB, self.swiftmendCB, self.regrowthCB,
                       self.wildGrowthCB, self.weaveCB, self.rejuvCB, self.lifebloomCB }
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
    rs(self.innervateSlider, isResto and buf.useInnervate ~= false and self:KnowsSpell("Innervate"), buf.innervateAt or 30, "%")
    rs(self.nsSlider, isResto and buf.useNSCombo ~= false and self:KnowsSpell("Nature's Swiftness"), buf.nsHpPct or 40, "%")
    rs(self.swiftmendSlider, isResto and buf.useSwiftmend ~= false and self:KnowsSpell("Swiftmend"), buf.swiftmendPct or 65, "%")
    rs(self.regrowthSlider, isResto and buf.useRegrowth ~= false and self:KnowsSpell("Regrowth"), buf.regrowthPct or 55, "%")
    rs(self.wgSlider, isResto and buf.useWildGrowth and self:KnowsSpell("Wild Growth"), buf.wildGrowthCount or 4, "")
    rs(self.weaveSlider, isResto and buf.weaveDamage, buf.weaveManaFloor or 40, "")

    -- defense block: needs a bear form; sliders follow the checkbox
    local bearKnown = self:KnowsSpell("Bear Form") or self:KnowsSpell("Dire Bear Form")
    self.hpCB.cb:SetChecked(buf.hpManage and true or false)
    if bearKnown then
        self.hpCB.cb:Enable()
        self.hpCB.label:SetText(self.hpCB.baseText); ui:Color(self.hpCB.label, ui.COL.white)
    else
        self.hpCB.cb:Disable()
        self.hpCB.label:SetText(self.hpCB.baseText .. " (needs Bear Form)"); ui:Color(self.hpCB.label, ui.COL.grey)
    end
    local defOn = bearKnown and buf.hpManage
    self.hpLowSlider:SetValue(buf.hpLow or 35);   self.hpLowSlider.valText:SetText((buf.hpLow or 35) .. "%")
    self.hpHighSlider:SetValue(buf.hpHigh or 70); self.hpHighSlider.valText:SetText((buf.hpHigh or 70) .. "%")
    if defOn then
        self.hpLowSlider:EnableMouse(true);  self.hpLowSlider:SetAlpha(1)
        self.hpHighSlider:EnableMouse(true); self.hpHighSlider:SetAlpha(1)
    else
        self.hpLowSlider:EnableMouse(false);  self.hpLowSlider:SetAlpha(0.35)
        self.hpHighSlider:EnableMouse(false); self.hpHighSlider:SetAlpha(0.35)
    end

    -- nuke dropdown: Wrath always (level 1), Starfire once known
    local nOpts = { { label = "Wrath", value = "Wrath" } }
    if self:KnowsSpell("Starfire") then table.insert(nOpts, { label = "Starfire", value = "Starfire" }) end
    local ncur = buf.nuke or "Wrath"
    local nshown, nc = ncur, ui.COL.white
    if ncur ~= "Wrath" and not self:KnowsSpell(ncur) then nshown, nc = ncur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.nukeDD, nOpts, ncur, nshown, nc)

    -- powershift is only meaningful in the Shred style
    if (buf.catStyle or "bleed") == "shred" then
        self.psCB.cb:Enable()
        self.psCB.label:SetText("Powershift"); ui:Color(self.psCB.label, ui.COL.white)
        self.psSlider:EnableMouse(true); self.psSlider:SetAlpha(1)
    else
        self.psCB.cb:Disable()
        self.psCB.label:SetText("Powershift (Shred style only)"); ui:Color(self.psCB.label, ui.COL.grey)
        self.psSlider:EnableMouse(false); self.psSlider:SetAlpha(0.35)
    end

    local cpv = buf.cpFinish or 5
    self.cpSlider:SetValue(cpv)
    if self.cpSlider.valText then self.cpSlider.valText:SetText(tostring(cpv)) end
    local psv = buf.psEnergy or 15
    self.psSlider:SetValue(psv)
    if self.psSlider.valText then self.psSlider.valText:SetText(tostring(psv)) end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI framework not loaded. AutoRota_UI.lua is missing or mislabeled in your AutoRota folder, reinstall the files.")
        return
    end
    AutoRotaUI:Toggle()
end
