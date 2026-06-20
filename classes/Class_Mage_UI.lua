-- ============================================================
-- Class_Mage_UI  -  mage window body for AutoRota
-- Builds and binds only the mage specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================
-- All three specs' controls are shown at once; the KnowsSpell red-out marks
-- anything not trained for your current spec/level, so there is no mode-greying.
-- ============================================================

local M = AutoRota.classes.MAGE

function M:BuildBody(ui, f)
    -- General
    ui:FS(f, "GameFontNormal", "General"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    ui:FS(f, "GameFontNormalSmall", "Spec"):SetPoint("TOPLEFT", f, "TOPLEFT", 22, -170)
    self.modeDD = ui:CreateDropdown("mode", f, 150, function(v) if ui.buf then ui.buf.mode = v; ui:Refresh() end end)
    self.modeDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -166)
    self.aoeCB = ui:CreateCheck("aoeMode", f, "AoE mode", nil, function(on) if ui.buf then ui.buf.aoeMode = on; ui:Refresh() end end)
    self.aoeCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 270, -166)

    self.useWandCB = ui:CreateCheck("useWand", f, "Use wand", nil, function(on) if ui.buf then ui.buf.useWand = on; ui:Refresh() end end)
    self.useWandCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -192)
    self.manaShieldCB = ui:CreateCheck("useManaShield", f, "Mana Shield", "Mana Shield", function(on) if ui.buf then ui.buf.useManaShield = on; ui:Refresh() end end)
    self.manaShieldCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -192)
    self.frostNovaCB = ui:CreateCheck("useFrostNova", f, "Frost Nova (root in melee)", "Frost Nova", function(on) if ui.buf then ui.buf.useFrostNova = on; ui:Refresh() end end)
    self.frostNovaCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -216)
    self.evocationCB = ui:CreateCheck("useEvocation", f, "Evocation (low mana)", "Evocation", function(on) if ui.buf then ui.buf.useEvocation = on; ui:Refresh() end end)
    self.evocationCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -216)

    self.wandHpSlider = ui:CreateSlider("wandHp", f, "wand-finish below target HP", function(v) if ui.buf then ui.buf.wandHp = v; ui:Refresh() end end)
    self.wandHpSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -256)
    self.manaFloorSlider = ui:CreateSlider("wandManaFloor", f, "wand below mana", function(v) if ui.buf then ui.buf.wandManaFloor = v; ui:Refresh() end end)
    self.manaFloorSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -256)
    self.evocAtSlider = ui:CreateSlider("evocAt", f, "Evocate below mana", function(v) if ui.buf then ui.buf.evocAt = v; ui:Refresh() end end)
    self.evocAtSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -296)

    -- Frost
    ui:FS(f, "GameFontNormal", "Frost"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -328)
    self.iceBarrierCB = ui:CreateCheck("useIceBarrier", f, "Ice Barrier", "Ice Barrier", function(on) if ui.buf then ui.buf.useIceBarrier = on; ui:Refresh() end end)
    self.iceBarrierCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -352)
    self.iciclesCB = ui:CreateCheck("useIcicles", f, "Icicles", "Icicles", function(on) if ui.buf then ui.buf.useIcicles = on; ui:Refresh() end end)
    self.iciclesCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -352)
    self.coneCB = ui:CreateCheck("useConeOfCold", f, "Cone of Cold", "Cone of Cold", function(on) if ui.buf then ui.buf.useConeOfCold = on; ui:Refresh() end end)
    self.coneCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -376)

    -- Fire
    ui:FS(f, "GameFontNormal", "Fire"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -408)
    self.pyroCB = ui:CreateCheck("usePyroblast", f, "Pyroblast (opener)", "Pyroblast", function(on) if ui.buf then ui.buf.usePyroblast = on; ui:Refresh() end end)
    self.pyroCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -432)
    self.scorchCB = ui:CreateCheck("useScorch", f, "Scorch (Fire Vulnerability)", "Scorch", function(on) if ui.buf then ui.buf.useScorch = on; ui:Refresh() end end)
    self.scorchCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -432)
    self.fireBlastCB = ui:CreateCheck("useFireBlast", f, "Fire Blast", "Fire Blast", function(on) if ui.buf then ui.buf.useFireBlast = on; ui:Refresh() end end)
    self.fireBlastCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -456)
    self.combustionCB = ui:CreateCheck("useCombustion", f, "Combustion", "Combustion", function(on) if ui.buf then ui.buf.useCombustion = on; ui:Refresh() end end)
    self.combustionCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -456)

    -- Arcane
    ui:FS(f, "GameFontNormal", "Arcane"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -488)
    self.ruptureCB = ui:CreateCheck("useArcaneRupture", f, "Arcane Rupture (upkeep)", "Arcane Rupture", function(on) if ui.buf then ui.buf.useArcaneRupture = on; ui:Refresh() end end)
    self.ruptureCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -512)
    self.surgeCB = ui:CreateCheck("useArcaneSurge", f, "Arcane Surge (no haste)", "Arcane Surge", function(on) if ui.buf then ui.buf.useArcaneSurge = on; ui:Refresh() end end)
    self.surgeCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -512)
    self.arcanePowerCB = ui:CreateCheck("useArcanePower", f, "Arcane Power", "Arcane Power", function(on) if ui.buf then ui.buf.useArcanePower = on; ui:Refresh() end end)
    self.arcanePowerCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -536)

    ui:Divider(f, -322)   -- above Frost
    ui:Divider(f, -402)   -- above Fire
    ui:Divider(f, -482)   -- above Arcane

    -- Tooltips
    ui:Tip(self.modeDD, "Spec", "Frost: the kiting / Icicles spec and the best leveler. Fire: Scorch debuff + Fireball burst. Arcane: Rupture upkeep + Arcane Missiles.", "Switch live with /ar mode frost|fire|arcane.")
    ui:Tip(self.aoeCB.cb, "AoE mode", "Kite-AoE: Frost Nova to freeze, Cone of Cold to snare, Icicles, then Arcane Explosion.", "Blizzard / Flamestrike are not auto-cast (they need a ground click). Also /ar aoe.")
    ui:Tip(self.useWandCB.cb, "Use wand", "On: finish low mobs and regen mana with the wand (the leveling 'nuke then wand' rule).", "Off: never wand. With no wand equipped the rotation just keeps casting.")
    ui:Tip(self.manaShieldCB.cb, "Mana Shield", "Optional. Keeps Mana Shield up (drains mana for damage), never stacked under Ice Barrier.")
    ui:Tip(self.frostNovaCB.cb, "Frost Nova", "Root the mob when it reaches melee so you can step back and wand - the leveling kite.")
    ui:Tip(self.evocationCB.cb, "Evocation", "Channel Evocation to restore mana when low, in combat, and the target is not about to die.")
    ui:Tip(self.wandHpSlider, "Wand-finish below target HP", "Target health percent under which you stop casting and wand the mob down. 0 = off (cast to death, for raiding).")
    ui:Tip(self.manaFloorSlider, "Wand below mana", "Your mana percent under which the rotation drops to the wand to let mana regenerate.")
    ui:Tip(self.evocAtSlider, "Evocate below mana", "Your mana percent under which Evocation is used (when enabled and in combat).")
    ui:Tip(self.iceBarrierCB.cb, "Ice Barrier", "Keep Ice Barrier up: a shield that also boosts Frost damage. Cast before the pull and when it drops.")
    ui:Tip(self.iciclesCB.cb, "Icicles", "Turtle Frost nuke, cast whenever its cooldown is up. Freeze effects (Frostbite / Flash Freeze) keep resetting it, so it fires in the empowered window automatically.")
    ui:Tip(self.coneCB.cb, "Cone of Cold", "Single target: a close-range emergency slow + damage. In AoE mode: snare the pack in front of you.")
    ui:Tip(self.pyroCB.cb, "Pyroblast", "Opener only - cast on a near-full-health target, so it is the pull and not a 6s cast mid-fight.")
    ui:Tip(self.scorchCB.cb, "Scorch", "Build and maintain the Fire Vulnerability debuff up to the stack count, then Fireball fills.")
    ui:Tip(self.fireBlastCB.cb, "Fire Blast", "Instant, used on cooldown - extra damage and the movement / finishing tool.")
    ui:Tip(self.combustionCB.cb, "Combustion", "Fire on cooldown to guarantee crits on your next fire spells.")
    ui:Tip(self.ruptureCB.cb, "Arcane Rupture", "Keep it on the target to boost Arcane Missiles. Re-applied whenever it falls off.")
    ui:Tip(self.surgeCB.cb, "Arcane Surge", "Used in the rotation while NOT hasted; skipped under Arcane Power / MQG (its GCD does not scale).")
    ui:Tip(self.arcanePowerCB.cb, "Arcane Power", "The Arcane damage steroid, used on cooldown.")
end

function M:RefreshBody(ui, buf)
    -- spec dropdown
    local modeOpts = {
        { label = "Frost",  value = "frost" },
        { label = "Fire",   value = "fire" },
        { label = "Arcane", value = "arcane" },
    }
    local modeLabel = { frost = "Frost (kite / Icicles)", fire = "Fire (burst)", arcane = "Arcane (haste)" }
    local mcur = buf.mode or "frost"
    ui:SetDropdown(self.modeDD, modeOpts, mcur, modeLabel[mcur] or mcur, ui.COL.white)

    -- General
    ui:BindCheck(self.aoeCB, buf.aoeMode)
    ui:BindCheck(self.useWandCB, buf.useWand)
    if not self:HasWand() then
        self.useWandCB.label:SetText("Use wand (none)")
        ui:Color(self.useWandCB.label, ui.COL.grey)
    end
    ui:BindCheck(self.manaShieldCB, buf.useManaShield, "Mana Shield")
    ui:BindCheck(self.frostNovaCB, buf.useFrostNova, "Frost Nova")
    ui:BindCheck(self.evocationCB, buf.useEvocation, "Evocation")
    self.wandHpSlider:SetValue(buf.wandHp or 0);          self.wandHpSlider.valText:SetText((buf.wandHp or 0) .. "%")
    self.manaFloorSlider:SetValue(buf.wandManaFloor or 0); self.manaFloorSlider.valText:SetText((buf.wandManaFloor or 0) .. "%")
    self.evocAtSlider:SetValue(buf.evocAt or 0);          self.evocAtSlider.valText:SetText((buf.evocAt or 0) .. "%")
    ui:SliderEnable(self.wandHpSlider, buf.useWand)
    ui:SliderEnable(self.manaFloorSlider, buf.useWand)
    ui:SliderEnable(self.evocAtSlider, buf.useEvocation)

    -- Frost
    ui:BindCheck(self.iceBarrierCB, buf.useIceBarrier, "Ice Barrier")
    ui:BindCheck(self.iciclesCB, buf.useIcicles, "Icicles")
    ui:BindCheck(self.coneCB, buf.useConeOfCold, "Cone of Cold")

    -- Fire
    ui:BindCheck(self.pyroCB, buf.usePyroblast, "Pyroblast")
    ui:BindCheck(self.scorchCB, buf.useScorch, "Scorch")
    ui:BindCheck(self.fireBlastCB, buf.useFireBlast, "Fire Blast")
    ui:BindCheck(self.combustionCB, buf.useCombustion, "Combustion")

    -- Arcane
    ui:BindCheck(self.ruptureCB, buf.useArcaneRupture, "Arcane Rupture")
    ui:BindCheck(self.surgeCB, buf.useArcaneSurge, "Arcane Surge")
    ui:BindCheck(self.arcanePowerCB, buf.useArcanePower, "Arcane Power")
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
