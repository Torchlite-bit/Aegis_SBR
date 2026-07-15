-- ============================================================
-- Class_Mage_UI  -  mage window body for Aegis_SBR
-- Builds and binds only the mage specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- ============================================================
-- This module opts into the scroll layout (M.useScrollLayout): the shell hosts
-- the body in a compact scroll frame and hands BuildBody the scroll child, and
-- the cursor-based layout API places everything (no hand-coded y offsets). All
-- three specs' controls are shown; the KnowsSpell red-out marks anything not
-- trained for your current spec/level. Detail that used to sit in the labels now
-- lives in the tooltips, keeping labels short for the narrower window.
-- ============================================================

local M = Aegis_SBR.classes.MAGE
M.useScrollLayout = true
M.specTabs = {
    field = "mode", default = "frost",
    tabs = {
        { key = "frost",  label = "Frost",  tip1 = "Kiting / Icicles. The strongest leveler." },
        { key = "fire",   label = "Fire",   tip1 = "Scorch debuff + Fireball burst." },
        { key = "arcane", label = "Arcane", tip1 = "Rupture upkeep + Arcane Missiles." },
    },
}

function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("General")
    self.aoeRow = L:Row{ key = "aoeMode", label = "AoE rotation", onToggle = set("aoeMode") }
    self.useWandRow = L:Row{ key = "useWand", label = "Use wand", onToggle = set("useWand"),
        slider = { key = "wandHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("wandHp") } }
    self.wandManaRow = L:Row{ label = "Wand below mana",
        slider = { key = "wandManaFloor", min = 0, max = 100, step = 5, suffix = "%", onChange = set("wandManaFloor") } }
    self.manaShieldRow = L:Row{ key = "useManaShield", label = "Mana Shield", spell = "Mana Shield", onToggle = set("useManaShield") }
    self.frostNovaRow = L:Row{ key = "useFrostNova", label = "Frost Nova", spell = "Frost Nova", onToggle = set("useFrostNova") }
    self.evocationRow = L:Row{ key = "useEvocation", label = "Evocation", spell = "Evocation", onToggle = set("useEvocation"),
        slider = { key = "evocAt", min = 0, max = 100, step = 5, suffix = "%", onChange = set("evocAt") } }

    self.frostSection = L:Header("Frost", "frost")
    self.iceBarrierRow = L:Row{ key = "useIceBarrier", label = "Ice Barrier", spell = "Ice Barrier", onToggle = set("useIceBarrier") }
    self.iciclesRow = L:Row{ key = "useIcicles", label = "Icicles", spell = "Icicles", onToggle = set("useIcicles") }
    self.coneRow = L:Row{ key = "useConeOfCold", label = "Cone of Cold", spell = "Cone of Cold", onToggle = set("useConeOfCold") }

    self.fireSection = L:Header("Fire", "fire")
    self.pyroRow = L:Row{ key = "usePyroblast", label = "Pyroblast", spell = "Pyroblast", onToggle = set("usePyroblast") }
    self.scorchRow = L:Row{ key = "useScorch", label = "Scorch", spell = "Scorch", onToggle = set("useScorch") }
    self.fireBlastRow = L:Row{ key = "useFireBlast", label = "Fire Blast", spell = "Fire Blast", onToggle = set("useFireBlast") }
    self.combustionRow = L:Row{ key = "useCombustion", label = "Combustion", spell = "Combustion", onToggle = set("useCombustion") }

    self.arcaneSection = L:Header("Arcane", "arcane")
    self.ruptureRow = L:Row{ key = "useArcaneRupture", label = "Arcane Rupture", spell = "Arcane Rupture", onToggle = set("useArcaneRupture") }
    self.surgeRow = L:Row{ key = "useArcaneSurge", label = "Arcane Surge", spell = "Arcane Surge", onToggle = set("useArcaneSurge") }
    self.arcanePowerRow = L:Row{ key = "useArcanePower", label = "Arcane Power", spell = "Arcane Power", onToggle = set("useArcanePower") }

    L:Finish()

    -- Tooltips carry the detail that used to be in the labels.
    ui:Tip(self.aoeRow.cb, "AoE mode", "Frost Nova to freeze, Cone of Cold to snare, Icicles, then Arcane Explosion.", "Blizzard / Flamestrike are not auto-cast (they need a ground click). Also /sbr aoe.")
    ui:Tip(self.useWandRow.cb, "Use wand", "On: finish low mobs and regen mana with the wand (the 'nuke then wand' rule). Off: never wand. With no wand equipped it just keeps casting.")
    ui:Tip(self.manaShieldRow.cb, "Mana Shield", "Optional. Keeps Mana Shield up (drains mana for damage), never stacked under Ice Barrier.")
    ui:Tip(self.frostNovaRow.cb, "Frost Nova", "Root the mob when it reaches melee so you can step back and wand - the leveling kite.")
    ui:Tip(self.evocationRow.cb, "Evocation", "Channel Evocation to restore mana when low, in combat, and the target is not about to die.")
    ui:Tip(self.useWandRow.slider, "Wand below target HP", "Target health percent under which you stop casting and wand the mob down. 0 = off (cast to death, for raiding).")
    ui:Tip(self.wandManaRow.slider, "Wand below mana", "Your mana percent under which the rotation drops to the wand to let mana regenerate.")
    ui:Tip(self.evocationRow.slider, "Evocate below mana", "Your mana percent under which Evocation is used (when enabled and in combat).")
    ui:Tip(self.iceBarrierRow.cb, "Ice Barrier", "Keep Ice Barrier up: a shield that also boosts Frost damage. Cast before the pull and when it drops.")
    ui:Tip(self.iciclesRow.cb, "Icicles", "Turtle Frost nuke, cast whenever its cooldown is up. Freeze effects (Frostbite / Flash Freeze) keep resetting it, so it fires in the empowered window automatically.")
    ui:Tip(self.coneRow.cb, "Cone of Cold", "Single target: a close-range emergency slow + damage. In AoE mode: snare the pack in front of you.")
    ui:Tip(self.pyroRow.cb, "Pyroblast", "Opener only - cast on a near-full-health target, so it is the pull and not a 6s cast mid-fight.")
    ui:Tip(self.scorchRow.cb, "Scorch", "Build and maintain the Fire Vulnerability debuff up to the stack count, then Fireball fills.")
    ui:Tip(self.fireBlastRow.cb, "Fire Blast", "Instant, used on cooldown - extra damage and the movement / finishing tool.")
    ui:Tip(self.combustionRow.cb, "Combustion", "Fire on cooldown to guarantee crits on your next fire spells.")
    ui:Tip(self.ruptureRow.cb, "Arcane Rupture", "Keep it on the target to boost Arcane Missiles. Re-applied whenever it falls off.")
    ui:Tip(self.surgeRow.cb, "Arcane Surge", "Used in the rotation while NOT hasted; skipped under Arcane Power / MQG (its GCD does not scale).")
    ui:Tip(self.arcanePowerRow.cb, "Arcane Power", "The Arcane damage steroid, used on cooldown.")
end

function M:RefreshBody(ui, buf)
    -- General
    ui:BindCheck(self.aoeRow, buf.aoeMode)
    ui:BindCheck(self.useWandRow, buf.useWand)
    if not self:HasWand() then
        self.useWandRow.label:SetText("Use wand (none)")
        ui:Color(self.useWandRow.label, ui.COL.grey)
    end
    ui:BindCheck(self.manaShieldRow, buf.useManaShield, "Mana Shield")
    ui:BindCheck(self.frostNovaRow, buf.useFrostNova, "Frost Nova")
    ui:BindCheck(self.evocationRow, buf.useEvocation, "Evocation")
    self.useWandRow.slider:SetValue(buf.wandHp or 0);      self.useWandRow.slider.valText:SetText((buf.wandHp or 0) .. "%")
    self.wandManaRow.slider:SetValue(buf.wandManaFloor or 0); self.wandManaRow.slider.valText:SetText((buf.wandManaFloor or 0) .. "%")
    self.evocationRow.slider:SetValue(buf.evocAt or 0);    self.evocationRow.slider.valText:SetText((buf.evocAt or 0) .. "%")
    ui:SliderEnable(self.useWandRow.slider, buf.useWand)
    ui:SliderEnable(self.wandManaRow.slider, buf.useWand)
    ui:SliderEnable(self.evocationRow.slider, buf.useEvocation)

    -- Frost
    ui:BindCheck(self.iceBarrierRow, buf.useIceBarrier, "Ice Barrier")
    ui:BindCheck(self.iciclesRow, buf.useIcicles, "Icicles")
    ui:BindCheck(self.coneRow, buf.useConeOfCold, "Cone of Cold")

    -- Fire
    ui:BindCheck(self.pyroRow, buf.usePyroblast, "Pyroblast")
    ui:BindCheck(self.scorchRow, buf.useScorch, "Scorch")
    ui:BindCheck(self.fireBlastRow, buf.useFireBlast, "Fire Blast")
    ui:BindCheck(self.combustionRow, buf.useCombustion, "Combustion")

    -- Arcane
    ui:BindCheck(self.ruptureRow, buf.useArcaneRupture, "Arcane Rupture")
    ui:BindCheck(self.surgeRow, buf.useArcaneSurge, "Arcane Surge")
    ui:BindCheck(self.arcanePowerRow, buf.useArcanePower, "Arcane Power")

    -- Active-spec focus: fade + lock the two specs you are not in. The General
    -- block (shared cooldowns, wand, evocation) is never dimmed.
    local m = buf.mode or "frost"
    self.frostSection:SetDimmed(m ~= "frost")
    self.fireSection:SetDimmed(m ~= "fire")
    self.arcaneSection:SetDimmed(m ~= "arcane")
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
