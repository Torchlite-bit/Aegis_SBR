-- ============================================================
-- Class_Rogue_UI  -  rogue window body for AutoRota
-- Builds and binds only the rogue specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout): BuildBody is
-- handed the scroll child and the cursor-based layout API places
-- everything; detail lives in tooltips so labels stay short.
-- ============================================================

local M = AutoRota.classes.ROGUE
M.useScrollLayout = true

-- ============================================================
-- build body (rogue controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Rotation")
    self.builderDD = L:Dropdown("builder", "Builder", 170, set("builder"))

    L:Header("Finishers")
    self.sndCB, self.envCB = L:CheckPair(
        { "useSnd", "Slice and Dice", "Slice and Dice", set("useSnd") },
        { "useEnvenom", "Envenom", "Envenom", set("useEnvenom") })
    self.rupCB, self.ripCB = L:CheckPair(
        { "useRupture", "Rupture", "Rupture", set("useRupture") },
        { "useRiposte", "Riposte", "Riposte", set("useRiposte") })
    self.cpSlider = L:Slider("cpFinish", "Eviscerate at combo points", { min = 1, max = 5, step = 1, suffix = "" }, set("cpFinish"))

    L:Header("Cooldowns")
    self.cdCB, self.cdEliteCB = L:CheckPair(
        { "popCDs", "Pop cooldowns", nil, set("popCDs") },
        { "autoCDElite", "Auto on elite", nil, set("autoCDElite") })

    L:Finish()

    ui:Tip(self.builderDD, "Builder", "The combo point builder. Auto picks Noxious Assault if known, else Sinister Strike.")
    ui:Tip(self.sndCB.cb, "Slice and Dice", "Kept up: refreshed cheaply at 1 combo point, dumped with Eviscerate above that.")
    ui:Tip(self.envCB.cb, "Envenom", "Kept up the same way as Slice and Dice (Turtle ability).")
    ui:Tip(self.rupCB.cb, "Rupture", "Applied as a finisher at your combo-point threshold when it falls off the target.", "With the Assassination talent Taste for Blood, keeping it up is also a stacking damage buff.")
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

    ui:BindCheck(self.sndCB, buf.useSnd)
    ui:BindCheck(self.envCB, buf.useEnvenom)
    ui:BindCheck(self.rupCB, buf.useRupture)
    ui:BindCheck(self.ripCB, buf.useRiposte)
    ui:BindCheck(self.cdCB, buf.popCDs)
    ui:BindCheck(self.cdEliteCB, buf.autoCDElite)

    local cpv = buf.cpFinish or 4
    self.cpSlider:SetValue(cpv)
    if self.cpSlider.valText then self.cpSlider.valText:SetText(tostring(cpv)) end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
