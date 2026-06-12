-- ============================================================
-- Class_Druid_UI  -  feral druid window body for AutoRota
-- Builds and binds only the druid specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.DRUID

-- ============================================================
-- build body (druid controls)
-- ============================================================
function M:BuildBody(ui, f)
    -- Form
    ui:FS(f, "GameFontNormal", "Form"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    ui:FS(f, "GameFontNormalSmall", "Preferred"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -168)
    self.formDD = ui:CreateDropdown("form", f, 170, function(v) if ui.buf then ui.buf.form = v; ui:Refresh() end end)
    self.formDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -166)

    -- Cat Form (DPS)
    ui:FS(f, "GameFontNormal", "Cat Form (DPS)"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -202)
    ui:FS(f, "GameFontNormalSmall", "Style"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -228)
    self.styleDD = ui:CreateDropdown("catStyle", f, 170, function(v) if ui.buf then ui.buf.catStyle = v; ui:Refresh() end end)
    self.styleDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -226)
    ui:FS(f, "GameFontNormalSmall", "Opener"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -256)
    self.openerDD = ui:CreateDropdown("opener", f, 170, function(v) if ui.buf then ui.buf.opener = v; ui:Refresh() end end)
    self.openerDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -254)

    self.tfCB = ui:CreateCheck("useTigersFury", f, "Tiger's Fury", "Tiger's Fury", function(on) if ui.buf then ui.buf.useTigersFury = on; ui:Refresh() end end)
    self.tfCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -284)
    self.ffCatCB = ui:CreateCheck("ffCat", f, "Faerie Fire", "Faerie Fire (Feral)", function(on) if ui.buf then ui.buf.ffCat = on; ui:Refresh() end end)
    self.ffCatCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -284)
    self.psCB = ui:CreateCheck("powershift", f, "Powershift", nil, function(on) if ui.buf then ui.buf.powershift = on; ui:Refresh() end end)
    self.psCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -308)

    self.cpSlider = ui:CreateSlider("cpFinish", f, "Finisher at combo points", {min=1,max=5,step=1,suffix=""}, function(v) if ui.buf then ui.buf.cpFinish = v; ui:Refresh() end end)
    self.cpSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -352)
    self.psSlider = ui:CreateSlider("psEnergy", f, "shift below energy", {min=0,max=40,step=5,suffix=""}, function(v) if ui.buf then ui.buf.psEnergy = v; ui:Refresh() end end)
    self.psSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -352)

    -- Bear Form (tank)
    ui:FS(f, "GameFontNormal", "Bear Form (Tank)"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -396)
    self.ffBearCB = ui:CreateCheck("ffBear", f, "Faerie Fire", "Faerie Fire (Feral)", function(on) if ui.buf then ui.buf.ffBear = on; ui:Refresh() end end)
    self.ffBearCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -420)
    self.demoCB = ui:CreateCheck("useDemo", f, "Demoralizing Roar", "Demoralizing Roar", function(on) if ui.buf then ui.buf.useDemo = on; ui:Refresh() end end)
    self.demoCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -420)
    self.maulCB = ui:CreateCheck("useMaul", f, "Maul (rage dump)", "Maul", function(on) if ui.buf then ui.buf.useMaul = on; ui:Refresh() end end)
    self.maulCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -444)
    self.swipeCB = ui:CreateCheck("aoeSwipe", f, "Swipe (AoE)", "Swipe", function(on) if ui.buf then ui.buf.aoeSwipe = on; ui:Refresh() end end)
    self.swipeCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -444)
    self.enrageCB = ui:CreateCheck("useEnrage", f, "Enrage when rage starved", "Enrage", function(on) if ui.buf then ui.buf.useEnrage = on; ui:Refresh() end end)
    self.enrageCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -468)

    -- Balance / Caster
    ui:FS(f, "GameFontNormal", "Balance / Caster"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -504)
    ui:FS(f, "GameFontNormalSmall", "Nuke"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -530)
    self.nukeDD = ui:CreateDropdown("nuke", f, 170, function(v) if ui.buf then ui.buf.nuke = v; ui:Refresh() end end)
    self.nukeDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -528)
    self.mfCB = ui:CreateCheck("useMoonfire", f, "Moonfire", "Moonfire", function(on) if ui.buf then ui.buf.useMoonfire = on; ui:Refresh() end end)
    self.mfCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -556)
    self.isCB = ui:CreateCheck("useInsectSwarm", f, "Insect Swarm", "Insect Swarm", function(on) if ui.buf then ui.buf.useInsectSwarm = on; ui:Refresh() end end)
    self.isCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -556)
    self.eclipseCB = ui:CreateCheck("eclipse", f, "React to Eclipse procs", nil, function(on) if ui.buf then ui.buf.eclipse = on; ui:Refresh() end end)
    self.eclipseCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -580)

    ui:Divider(f, -134)   -- above Form
    ui:Divider(f, -194)   -- above Cat
    ui:Divider(f, -388)   -- above Bear
    ui:Divider(f, -496)   -- above Balance

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
    ui:Tip(self.nukeDD, "Primary nuke", "Chain-cast to fish for Eclipse procs.", "Casting Wraths empowers Starfire and vice versa, the rotation swaps automatically on the proc.")
    ui:Tip(self.mfCB.cb, "Moonfire", "Kept up first. At low levels this plus the nuke IS the rotation.")
    ui:Tip(self.isCB.cb, "Insect Swarm", "Kept up right after Moonfire.")
    ui:Tip(self.eclipseCB.cb, "Eclipse reaction", "On a proc, cast the empowered opposite nuke. Casts are queued, so the swap lands the moment the window opens.", "If procs are not detected, run /ar debug with the proc up and report the buff name.")
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
    ui:BindCheck(self.mfCB, buf.useMoonfire)
    ui:BindCheck(self.isCB, buf.useInsectSwarm)
    ui:BindCheck(self.eclipseCB, buf.eclipse)

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
