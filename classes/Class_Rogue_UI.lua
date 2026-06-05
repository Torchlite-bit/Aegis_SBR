-- ============================================================
-- Class_Rogue_UI  -  rogue window body for AutoRota
-- Builds and binds only the rogue specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.ROGUE

-- ============================================================
-- build body (rogue controls)
-- ============================================================
function M:BuildBody(ui, f)
    -- Rotation
    ui:FS(f, "GameFontNormal", "Rotation"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    ui:FS(f, "GameFontNormalSmall", "Builder"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -168)
    self.builderDD = ui:CreateDropdown("builder", f, 210, function(v) if ui.buf then ui.buf.builder = v; ui:Refresh() end end)
    self.builderDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -166)

    -- Finishers
    ui:FS(f, "GameFontNormal", "Finishers"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -200)
    self.sndCB = ui:CreateCheck("useSnd", f, "Keep Slice and Dice up", "Slice and Dice", function(on) if ui.buf then ui.buf.useSnd = on; ui:Refresh() end end)
    self.sndCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -222)
    self.envCB = ui:CreateCheck("useEnvenom", f, "Keep Envenom up", "Envenom", function(on) if ui.buf then ui.buf.useEnvenom = on; ui:Refresh() end end)
    self.envCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -246)
    self.ripCB = ui:CreateCheck("useRiposte", f, "Riposte in parry window", "Riposte", function(on) if ui.buf then ui.buf.useRiposte = on; ui:Refresh() end end)
    self.ripCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -270)

    self.cpSlider = ui:CreateSlider("cpFinish", f, "Eviscerate at combo points", {min=1,max=5,step=1,suffix=""}, function(v) if ui.buf then ui.buf.cpFinish = v; ui:Refresh() end end)
    self.cpSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -312)

    -- Cooldowns
    ui:FS(f, "GameFontNormal", "Cooldowns"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -344)
    self.cdCB = ui:CreateCheck("popCDs", f, "Always pop cooldowns", nil, function(on) if ui.buf then ui.buf.popCDs = on; ui:Refresh() end end)
    self.cdCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -366)
    self.cdEliteCB = ui:CreateCheck("autoCDElite", f, "Auto on elite and boss", nil, function(on) if ui.buf then ui.buf.autoCDElite = on; ui:Refresh() end end)
    self.cdEliteCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -366)

    ui:Divider(f, -134)   -- above Rotation
    ui:Divider(f, -192)   -- above Finishers
    ui:Divider(f, -300)   -- above Cooldowns area (below the slider)
    ui:Divider(f, -336)   -- above Cooldowns header

    ui:Tip(self.builderDD, "Builder", "The combo point builder. Auto picks Noxious Assault if known, else Sinister Strike.")
    ui:Tip(self.sndCB.cb, "Slice and Dice", "Refreshed cheaply at 1 combo point, dumped with Eviscerate above that.")
    ui:Tip(self.envCB.cb, "Envenom", "Kept up the same way as Slice and Dice (Turtle ability).")
    ui:Tip(self.ripCB.cb, "Riposte", "Cast right after a parry, inside the short Riposte window.")
    ui:Tip(self.cpSlider, "Finisher combo points", "Eviscerate is used once combo points reach this number.")
    ui:Tip(self.cdCB.cb, "Pop cooldowns", "Use Adrenaline Rush and Blade Flurry every press (off the global cooldown).")
    ui:Tip(self.cdEliteCB.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
end

-- ============================================================
-- refresh body (rogue binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- builder dropdown: Auto plus the builders the rogue actually knows
    local o = { { label = "Auto (spec based)", value = "" } }
    local avail = self:AvailableBuildersOf()
    for i = 1, table.getn(avail) do o[i + 1] = { label = avail[i], value = avail[i] } end
    local cur = buf.builder or ""
    local shown, c
    if cur == "" then shown, c = "Auto (spec based)", ui.COL.white
    elseif self:KnowsSpell(cur) then shown, c = cur, ui.COL.white
    else shown, c = cur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.builderDD, o, cur, shown, c)

    local function setCheck(item, on, spellName)
        item.cb:SetChecked(on and true or false)
        if not spellName then
            item.cb:Enable(); item.label:SetText(item.baseText); ui:Color(item.label, ui.COL.white); return
        end
        item.cb:Enable()
        local known = self:KnowsSpell(spellName)
        if on and not known then item.label:SetText(item.baseText .. " (not learned)"); ui:Color(item.label, ui.COL.red)
        elseif not known then item.label:SetText(item.baseText .. " (not learned)"); ui:Color(item.label, ui.COL.grey)
        else item.label:SetText(item.baseText); ui:Color(item.label, ui.COL.white) end
    end
    setCheck(self.sndCB, buf.useSnd, "Slice and Dice")
    setCheck(self.envCB, buf.useEnvenom, "Envenom")
    setCheck(self.ripCB, buf.useRiposte, "Riposte")
    setCheck(self.cdCB, buf.popCDs, nil)
    setCheck(self.cdEliteCB, buf.autoCDElite, nil)

    local cpv = buf.cpFinish or 4
    self.cpSlider:SetValue(cpv)
    if self.cpSlider.valText then self.cpSlider.valText:SetText(tostring(cpv)) end

end

-- Open the shared window for this class.
M.OpenConfig = function(mod) AutoRotaUI:Toggle() end
