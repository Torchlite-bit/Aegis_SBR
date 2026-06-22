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
    }
    local modeLabel = { enhancement = "Enhancement", elemental = "Elemental", tank = "Tank" }
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

    -- Active-spec focus: melee strikes are dead weight while casting, so fade +
    -- lock them in Elemental. Enhancement and Tank are both melee, so they stay lit.
    self.meleeSection:SetDimmed(buf.mode == "elemental")
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
