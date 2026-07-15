-- ============================================================
-- Class_Rogue_UI  -  rogue window body for Aegis_SBR
-- Builds and binds only the rogue specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout): BuildBody is
-- handed the scroll child and the cursor-based layout API places
-- everything; detail lives in tooltips so labels stay short.
-- ============================================================

local M = Aegis_SBR.classes.ROGUE
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
    self.sndRow = L:Row{ key = "useSnd", label = "Slice and Dice", spell = "Slice and Dice", onToggle = set("useSnd") }
    self.envRow = L:Row{ key = "useEnvenom", label = "Envenom", spell = "Envenom", onToggle = set("useEnvenom") }
    self.rupRow = L:Row{ key = "useRupture", label = "Rupture", spell = "Rupture", onToggle = set("useRupture") }
    self.ripRow = L:Row{ key = "useRiposte", label = "Riposte", spell = "Riposte", onToggle = set("useRiposte") }
    self.cpRow = L:Row{ label = "Eviscerate at CP",
        slider = { key = "cpFinish", min = 1, max = 5, step = 1, suffix = "", onChange = set("cpFinish") } }

    L:Header("Cooldowns")
    self.cdRow = L:Row{ key = "popCDs", label = "Pop cooldowns", onToggle = set("popCDs") }
    self.cdEliteRow = L:Row{ key = "autoCDElite", label = "Auto on elite", onToggle = set("autoCDElite") }

    L:Finish()

    ui:Tip(self.builderDD, "Builder", "The combo point builder. Auto picks Noxious Assault if known, else Sinister Strike.")
    ui:Tip(self.sndRow.cb, "Slice and Dice", "Kept up: refreshed cheaply at 1 combo point, dumped with Eviscerate above that.")
    ui:Tip(self.envRow.cb, "Envenom", "Kept up the same way as Slice and Dice (Turtle ability).")
    ui:Tip(self.rupRow.cb, "Rupture", "Applied as a finisher at your combo-point threshold when it falls off the target.", "With the Assassination talent Taste for Blood, keeping it up is also a stacking damage buff.")
    ui:Tip(self.ripRow.cb, "Riposte", "Cast right after a parry, inside the short Riposte window.")
    ui:Tip(self.cpRow.slider, "Finisher combo points", "Eviscerate is used once combo points reach this number.")
    ui:Tip(self.cdRow.cb, "Pop cooldowns", "Use Adrenaline Rush and Blade Flurry every press (off the global cooldown).")
    ui:Tip(self.cdEliteRow.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
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

    ui:BindCheck(self.sndRow, buf.useSnd)
    ui:BindCheck(self.envRow, buf.useEnvenom)
    ui:BindCheck(self.rupRow, buf.useRupture)
    ui:BindCheck(self.ripRow, buf.useRiposte)
    ui:BindCheck(self.cdRow, buf.popCDs)
    ui:BindCheck(self.cdEliteRow, buf.autoCDElite)

    local cpv = buf.cpFinish or 4
    self.cpRow.slider:SetValue(cpv)
    if self.cpRow.slider.valText then self.cpRow.slider.valText:SetText(tostring(cpv)) end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
