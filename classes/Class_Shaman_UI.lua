-- ============================================================
-- Class_Shaman_UI  -  shaman window body for AutoRota
-- Builds and binds only the shaman specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.SHAMAN

-- ============================================================
-- build body (shaman controls)
-- ============================================================
function M:BuildBody(ui, f)
    -- Mode
    ui:FS(f, "GameFontNormal", "Mode"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    self.modeDD = ui:CreateDropdown("mode", f, 210, function(v) if ui.buf then ui.buf.mode = v; ui:Refresh() end end)
    self.modeDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -166)
    ui:FS(f, "GameFontNormalSmall", "Spec"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -168)

    -- Shields & Shocks
    ui:FS(f, "GameFontNormal", "Shield and shock"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -200)
    ui:FS(f, "GameFontNormalSmall", "Shield"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -228)
    self.shieldDD = ui:CreateDropdown("shield", f, 210, function(v) if ui.buf then ui.buf.shield = v; ui:Refresh() end end)
    self.shieldDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -226)
    ui:FS(f, "GameFontNormalSmall", "Shock"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -260)
    self.shockDD = ui:CreateDropdown("shock", f, 210, function(v) if ui.buf then ui.buf.shock = v; ui:Refresh() end end)
    self.shockDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -258)

    -- Abilities
    ui:FS(f, "GameFontNormal", "Abilities"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -292)
    self.ssCB = ui:CreateCheck("useStormstrike", f, "Stormstrike", "Stormstrike", function(on) if ui.buf then ui.buf.useStormstrike = on; ui:Refresh() end end)
    self.ssCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -316)
    self.lsCB = ui:CreateCheck("useLightningStrike", f, "Lightning Strike", "Lightning Strike", function(on) if ui.buf then ui.buf.useLightningStrike = on; ui:Refresh() end end)
    self.lsCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -316)
    self.lbCB = ui:CreateCheck("lbFiller", f, "Lightning Bolt filler", "Lightning Bolt", function(on) if ui.buf then ui.buf.lbFiller = on; ui:Refresh() end end)
    self.lbCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -340)
    self.searCB = ui:CreateCheck("useSearingTotem", f, "Searing Totem", "Searing Totem", function(on) if ui.buf then ui.buf.useSearingTotem = on; ui:Refresh() end end)
    self.searCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -340)

    -- Cooldowns and utility
    ui:FS(f, "GameFontNormal", "Cooldowns and utility"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -374)
    self.emCB = ui:CreateCheck("useElementalMastery", f, "Elemental Mastery", "Elemental Mastery", function(on) if ui.buf then ui.buf.useElementalMastery = on; ui:Refresh() end end)
    self.emCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -398)
    self.blCB = ui:CreateCheck("useBloodlust", f, "Bloodlust", "Bloodlust", function(on) if ui.buf then ui.buf.useBloodlust = on; ui:Refresh() end end)
    self.blCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -398)
    self.tauntCB = ui:CreateCheck("useTaunt", f, "Earthshaker Slam taunt", "Earthshaker Slam", function(on) if ui.buf then ui.buf.useTaunt = on; ui:Refresh() end end)
    self.tauntCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -422)

    ui:Divider(f, -134)   -- above Mode
    ui:Divider(f, -192)   -- above Shield and shock
    ui:Divider(f, -284)   -- above Abilities
    ui:Divider(f, -366)   -- above Cooldowns and utility

    ui:Tip(self.modeDD, "Mode", "Enhancement (melee), Elemental (caster), or Tank.", "Each press runs the rotation for the selected mode.")
    ui:Tip(self.shieldDD, "Shield", "Kept up automatically. Lightning Shield for damage/threat, Water Shield for mana.")
    ui:Tip(self.shockDD, "Shock", "One shock on the shared cooldown. Flame Shock is kept up as a DoT; Earth/Frost are cast on cooldown.")
    ui:Tip(self.ssCB.cb, "Stormstrike", "Talented melee strike. Grants a buff boosting your next 2 Nature hits by 20% — the rotation follows it with a shock. Auto-detected when learned.")
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
    -- mode dropdown
    local modeOpts = {
        { label = "Enhancement (melee)", value = "enhancement" },
        { label = "Elemental (caster)",  value = "elemental" },
        { label = "Tank",                value = "tank" },
    }
    local modeLabel = { enhancement = "Enhancement (melee)", elemental = "Elemental (caster)", tank = "Tank" }
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
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
