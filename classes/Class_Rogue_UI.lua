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
    self.saRow = L:Row{ key = "useSurpriseAttack", label = "Surprise Attack", spell = "Surprise Attack", onToggle = set("useSurpriseAttack") }
    self.cpRow = L:Row{ label = "Eviscerate at CP",
        slider = { key = "cpFinish", min = 1, max = 5, step = 1, suffix = "", onChange = set("cpFinish") } }
    self.execRow = L:Row{ key = "useExecute", label = "Execute low-HP targets", onToggle = set("useExecute"),
        slider = { key = "executeHpPct", min = 1, max = 30, step = 1, suffix = "%", onChange = set("executeHpPct") } }

    L:Header("Cooldowns")
    self.cdRow = L:Row{ key = "popCDs", label = "Pop cooldowns", onToggle = set("popCDs") }
    self.cdEliteRow = L:Row{ key = "autoCDElite", label = "Auto on elite", onToggle = set("autoCDElite") }

    -- Poisons: the poison-control settings (Quick Bar + rebuff) live in the
    -- shared Aegis_SBR_BuffUp module (global per character, not per profile), so
    -- their toggles write there directly. The pre-pull reminder stays a
    -- per-profile setting. Presets open a text dialog on click.
    L:Header("Poisons")
    local function abu(fn) return function(v) if Aegis_SBR_BuffUp then Aegis_SBR_BuffUp[fn](Aegis_SBR_BuffUp, v) end end end
    self.pcRow  = L:Row{ key = "abuPoisonControl", label = "Poison control (Quick Bar + rebuff)", onToggle = abu("SetPoisonControl") }
    self.pmhRow = L:Row{ key = "abuWatchMH", label = "Rebuff button: mainhand", onToggle = abu("SetWatchPoisonMH") }
    self.pohRow = L:Row{ key = "abuWatchOH", label = "Rebuff button: offhand", onToggle = abu("SetWatchPoisonOH") }
    self.qbRow  = L:Row{ key = "abuQuickBar", label = "Show poison Quick Bar", onToggle = abu("SetQuickBarEnabled") }
    self.presetBtns = {}
    local maxp = (Aegis_SBR_BuffUp and Aegis_SBR_BuffUp:MaxPresets()) or 4
    for i = 1, maxp do
        local idx = i
        self.presetBtns[idx] = L:Button{ label = "Preset " .. idx, onClick = function()
            local cur = ""
            if Aegis_SBR_BuffUp then cur = (Aegis_SBR_BuffUp:GetPreset(idx)) or "" end
            Aegis_SBR_UI:ShowDialog({
                prompt = "Poison type for preset " .. idx .. " (name only, no rank - e.g. Instant Poison)",
                withInput = true, initialText = cur, acceptLabel = "Save",
                onAccept = function(txt)
                    if Aegis_SBR_BuffUp then Aegis_SBR_BuffUp:SetPreset(idx, txt or "", "") end
                    ui:Refresh()
                end,
            })
        end }
    end

    L:Finish()

    ui:Tip(self.builderDD, "Builder", "The combo point builder. Auto picks Noxious Assault if known, else Sinister Strike.")
    ui:Tip(self.sndRow.cb, "Slice and Dice", "Kept up: refreshed cheaply at 1 combo point, dumped with Eviscerate above that.")
    ui:Tip(self.envRow.cb, "Envenom", "Kept up the same way as Slice and Dice (Turtle ability).")
    ui:Tip(self.rupRow.cb, "Rupture", "Applied as a finisher at your combo-point threshold when it falls off the target.", "With the Assassination talent Taste for Blood, keeping it up is also a stacking damage buff.")
    ui:Tip(self.ripRow.cb, "Riposte", "Cast right after a parry, inside the short Riposte window.")
    ui:Tip(self.saRow.cb, "Surprise Attack", "Cast right after the TARGET dodges you, inside a short window (mirror image of Riposte).", "Combat capstone (20 points). Guaranteed hit, cheap, awards a combo point.")
    ui:Tip(self.cpRow.slider, "Finisher combo points", "Eviscerate is used once combo points reach this number.")
    ui:Tip(self.execRow.cb, "Execute low-HP targets", "Below the health value on the right, Eviscerate fires with whatever combo points are on hand (at least 1) instead of waiting for the normal threshold.", "Ruthlessness guarantees a combo point after any finisher, so this rarely goes unused once a fight is underway.")
    ui:Tip(self.execRow.slider, "Execute below", "Target health percent under which Eviscerate finishes early rather than risk combo points going to waste on a kill.")
    ui:Tip(self.cdRow.cb, "Pop cooldowns", "Use Adrenaline Rush and Blade Flurry every press (off the global cooldown).")
    ui:Tip(self.cdEliteRow.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
    ui:Tip(self.pcRow.cb, "Poison control", "Master switch for the poison Quick Bar and rebuff buttons (also in the minimap right-click menu). Applies to this character across all rogue profiles.", "Applying a poison needs a real click, so it is always button-driven, never cast from the rotation macro.")
    ui:Tip(self.pmhRow.cb, "Rebuff button: mainhand", "Show a click-to-apply button when the mainhand poison has fallen off.")
    ui:Tip(self.pohRow.cb, "Rebuff button: offhand", "Show a click-to-apply button when the offhand poison has fallen off.")
    ui:Tip(self.qbRow.cb, "Show poison Quick Bar", "A small movable bar of your poison presets: left-click a preset for mainhand, right-click for offhand.")
    for i = 1, table.getn(self.presetBtns) do
        ui:Tip(self.presetBtns[i], "Poison preset " .. i, "Click to set the poison type for this preset - just the name, NO rank (e.g. Instant Poison, not Instant Poison VI).", "Whatever rank of that poison is in your bags is found and applied automatically, so you never have to update the preset when you learn a higher rank.")
    end
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
    ui:BindCheck(self.saRow, buf.useSurpriseAttack)
    ui:BindCheck(self.cdRow, buf.popCDs)
    ui:BindCheck(self.cdEliteRow, buf.autoCDElite)

    local cpv = buf.cpFinish or 4
    self.cpRow.slider:SetValue(cpv)
    if self.cpRow.slider.valText then self.cpRow.slider.valText:SetText(tostring(cpv)) end

    ui:BindCheck(self.execRow, buf.useExecute)
    local execv = buf.executeHpPct or 10
    self.execRow.slider:SetValue(execv)
    if self.execRow.slider.valText then self.execRow.slider.valText:SetText(execv .. "%") end

    -- Poison-control rows bind to the global Aegis_SBR_BuffUp state, not the
    -- profile buffer, so they are set directly here.
    if Aegis_SBR_BuffUp then
        self.pcRow.cb:SetChecked(Aegis_SBR_BuffUp:PoisonControlEnabled())
        self.pmhRow.cb:SetChecked(Aegis_SBR_BuffUp:WatchPoisonMH())
        self.pohRow.cb:SetChecked(Aegis_SBR_BuffUp:WatchPoisonOH())
        self.qbRow.cb:SetChecked(Aegis_SBR_BuffUp:QuickBarEnabled())
        for i = 1, table.getn(self.presetBtns) do
            local nm = Aegis_SBR_BuffUp:GetPreset(i)
            self.presetBtns[i].value:SetText((nm and nm ~= "") and nm or "|cff666666(empty)|r")
        end
    end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
