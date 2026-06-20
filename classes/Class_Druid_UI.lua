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
    }
    local formLabel = { cat = "Cat Form", bear = "Bear Form", caster = "Caster / Moonkin" }
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
