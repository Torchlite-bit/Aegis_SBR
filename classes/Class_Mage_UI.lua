-- ============================================================
-- Class_Mage_UI  -  mage window body for AutoRota
-- Builds and binds only the mage specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================
-- This module opts into the scroll layout (M.useScrollLayout): the shell hosts
-- the body in a compact scroll frame and hands BuildBody the scroll child, and
-- the cursor-based layout API places everything (no hand-coded y offsets). All
-- three specs' controls are shown; the KnowsSpell red-out marks anything not
-- trained for your current spec/level. Detail that used to sit in the labels now
-- lives in the tooltips, keeping labels short for the narrower window.
-- ============================================================

local M = AutoRota.classes.MAGE
M.useScrollLayout = true

function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("General")
    self.modeDD, self.aoeCB = L:DropdownCheck(
        { key = "mode", label = "Spec", width = 110, onChange = set("mode") },
        { "aoeMode", "AoE", nil, set("aoeMode") })
    self.useWandCB, self.manaShieldCB = L:CheckPair(
        { "useWand", "Use wand", nil, set("useWand") },
        { "useManaShield", "Mana Shield", "Mana Shield", set("useManaShield") })
    self.frostNovaCB, self.evocationCB = L:CheckPair(
        { "useFrostNova", "Frost Nova", "Frost Nova", set("useFrostNova") },
        { "useEvocation", "Evocation", "Evocation", set("useEvocation") })
    self.wandHpSlider, self.manaFloorSlider = L:SliderPair(
        { "wandHp", "Wand below target HP", set("wandHp") },
        { "wandManaFloor", "Wand below mana", set("wandManaFloor") })
    self.evocAtSlider = L:Slider("evocAt", "Evocate below mana", set("evocAt"))

    L:Header("Frost")
    self.iceBarrierCB, self.iciclesCB = L:CheckPair(
        { "useIceBarrier", "Ice Barrier", "Ice Barrier", set("useIceBarrier") },
        { "useIcicles", "Icicles", "Icicles", set("useIcicles") })
    self.coneCB = L:Check("useConeOfCold", "Cone of Cold", "Cone of Cold", set("useConeOfCold"))

    L:Header("Fire")
    self.pyroCB, self.scorchCB = L:CheckPair(
        { "usePyroblast", "Pyroblast", "Pyroblast", set("usePyroblast") },
        { "useScorch", "Scorch", "Scorch", set("useScorch") })
    self.fireBlastCB, self.combustionCB = L:CheckPair(
        { "useFireBlast", "Fire Blast", "Fire Blast", set("useFireBlast") },
        { "useCombustion", "Combustion", "Combustion", set("useCombustion") })

    L:Header("Arcane")
    self.ruptureCB, self.surgeCB = L:CheckPair(
        { "useArcaneRupture", "Arcane Rupture", "Arcane Rupture", set("useArcaneRupture") },
        { "useArcaneSurge", "Arcane Surge", "Arcane Surge", set("useArcaneSurge") })
    self.arcanePowerCB = L:Check("useArcanePower", "Arcane Power", "Arcane Power", set("useArcanePower"))

    L:Finish()

    -- Tooltips carry the detail that used to be in the labels.
    ui:Tip(self.modeDD, "Spec", "Frost = kiting / Icicles (best leveler). Fire = Scorch debuff + Fireball burst. Arcane = Rupture upkeep + Arcane Missiles.", "Also /ar mode frost|fire|arcane.")
    ui:Tip(self.aoeCB.cb, "AoE mode", "Frost Nova to freeze, Cone of Cold to snare, Icicles, then Arcane Explosion.", "Blizzard / Flamestrike are not auto-cast (they need a ground click). Also /ar aoe.")
    ui:Tip(self.useWandCB.cb, "Use wand", "On: finish low mobs and regen mana with the wand (the 'nuke then wand' rule). Off: never wand. With no wand equipped it just keeps casting.")
    ui:Tip(self.manaShieldCB.cb, "Mana Shield", "Optional. Keeps Mana Shield up (drains mana for damage), never stacked under Ice Barrier.")
    ui:Tip(self.frostNovaCB.cb, "Frost Nova", "Root the mob when it reaches melee so you can step back and wand - the leveling kite.")
    ui:Tip(self.evocationCB.cb, "Evocation", "Channel Evocation to restore mana when low, in combat, and the target is not about to die.")
    ui:Tip(self.wandHpSlider, "Wand below target HP", "Target health percent under which you stop casting and wand the mob down. 0 = off (cast to death, for raiding).")
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
    -- spec dropdown (short labels for the compact window; detail is in the tip)
    local modeOpts = {
        { label = "Frost",  value = "frost" },
        { label = "Fire",   value = "fire" },
        { label = "Arcane", value = "arcane" },
    }
    local modeLabel = { frost = "Frost", fire = "Fire", arcane = "Arcane" }
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
