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

-- Four tabs, because the three specs are played nothing like each other and a
-- single flat list forced every rogue to read past two thirds of it. The rail
-- itself is the shared one (Aegis_SBR_UI:BuildSpecTabs); a class only declares
-- the tabs and tags its sections.
--
-- IMPORTANT: these tabs are a VIEW. Switching one changes what is on screen and
-- nothing else - the rotation does not read cfg.spec, so a setting you turned on
-- stays on while a tab does not show it. That is deliberate: a tab that silently
-- disabled options would be a second, invisible set of switches. The Starter tab
-- is safe under that rule because everything it hides is either off by default or
-- a spell a rogue under twenty cannot cast yet.
M.specTabs = {
    field = "spec", default = "assassination",
    tabs = {
        { key = "starter", label = "Starter",
          tip1 = "The first twenty levels, and nothing else.",
          tip2 = "One builder, Slice and Dice, Eviscerate. Everything the other tabs carry is a talent, a poison or a spell you do not have yet - hidden here rather than explained.",
          sub = "The first twenty levels: a builder, Slice and Dice, Eviscerate." },
        { key = "assassination", label = "Assassin",
          tip1 = "Poison and bleed.",
          tip2 = "Envenom and Rupture are maintained buffs; the combo points above the ceiling go into Eviscerate. This is the spec the rotation was measured on.",
          sub = "Envenom and Rupture as maintained buffs, Eviscerate takes the surplus." },
        { key = "combat", label = "Combat",
          tip1 = "Sustained damage, with reactions.",
          tip2 = "Riposte and Surprise Attack fire inside the windows the target opens; Adrenaline Rush and Blade Flurry carry the burst.",
          sub = "Riposte and Surprise Attack react to the target; cooldowns carry the burst." },
        { key = "subtlety", label = "Subtlety",
          tip1 = "Bleeds, amplified.",
          tip2 = "Hemorrhage raises every bleed on the target, the group's included. Expose Armor and Mark for Death are worth more to the raid than to you, and the rotation puts them ahead of your own finishers for that reason.",
          sub = "Expose Armor and Mark for Death serve the raid; they run ahead of your own finishers." },
    },
}

-- ============================================================
-- build body (rogue controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    -- Every write lands in the ACTIVE TAB's layer (Aegis_SBR:TabView).
    local function set(key) return function(v) if ui.buf then M:TabView(ui.buf, M)[key] = v; ui:Refresh() end end end

    -- Grouped by FEATURE, not by spell type. The header carries the context, so
    -- each row only has to say the one thing that is specific to it - which is
    -- what lets "Use from" appear under both Eviscerate and Execute without
    -- ambiguity. Three rules hold throughout:
    --   * the value column shows the DIRECTION of a threshold, ">=" for a floor
    --     and "<=" for a ceiling. Four combo-point sliders reading "... CP" with
    --     two different meanings was the single biggest source of confusion.
    --   * a slider whose owning toggle is off is greyed, always.
    --   * the neutral position always reads "off", whichever end of the scale
    --     it happens to sit on.

    -- Surprise Attack belongs with the builders (it AWARDS a combo point), but
    -- it cannot go in the dropdown: that picks the builder you spam, while
    -- Surprise Attack is only castable inside the target's dodge window, so it
    -- rides on top of whichever builder is chosen rather than replacing it.
    -- Riposte joins them because it is likewise something you press when no
    -- finisher is due - it neither spends nor builds combo points.
    -- Untagged: every tab needs a builder, the starter included.
    L:Header("Attacks")
    self.builderDD = L:Dropdown("builder", "Builder", 170, set("builder"))

    -- Both are Combat talents and both are REACTIONS - the target opens a window
    -- and the press has to land inside it. They sit together for that reason, not
    -- because they do the same thing.
    L:Header("Reactions", "combat")
    self.saRow = L:Row{ key = "useSurpriseAttack", label = "Surprise Attack", spell = "Surprise Attack", onToggle = set("useSurpriseAttack") }
    self.ripRow = L:Row{ key = "useRiposte", label = "Riposte", spell = "Riposte", onToggle = set("useRiposte") }

    -- The three Subtlety talents plus the cooldown that hands two of them back.
    -- They sit above the shared finishers on purpose: two of the four are worth
    -- more to the group than to the rogue, and reading them first is how the tab
    -- says that.
    L:Header("Subtlety", "subtlety")
    self.garroteRow = L:Row{ key = "useGarrote", label = "Garrote from stealth", spell = "Garrote", onToggle = set("useGarrote") }
    self.vanishRow = L:Row{ key = "useVanishBurst", label = "Vanish into the burst", spell = "Vanish", onToggle = set("useVanishBurst") }
    self.evisSubRow = L:Row{ key = "useEviscerate", label = "Eviscerate when nothing is due", spell = "Eviscerate", onToggle = set("useEviscerate") }
    self.eaRow = L:Row{ key = "useExposeArmor", label = "Expose Armor from", spell = "Expose Armor", onToggle = set("useExposeArmor"),
        slider = { key = "exposeCP", min = 1, max = 5, step = 1, suffix = "", onChange = set("exposeCP") } }
    self.eaTTKRow = L:Row{ key = "useExposeTTK", label = "Expose Armor only if the target lives", onToggle = set("useExposeTTK"),
        slider = { key = "exposeMinTTK", min = 5, max = 60, step = 5, suffix = "s", onChange = set("exposeMinTTK") } }
    self.eaRefreshRow = L:Row{ label = "Expose Armor refresh under",
        slider = { key = "exposeRefresh", min = 1, max = 15, step = 1, suffix = "s", onChange = set("exposeRefresh") } }
    self.sodRow = L:Row{ key = "useShadowOfDeath", label = "Shadow of Death from", spell = "Shadow of Death", onToggle = set("useShadowOfDeath"),
        slider = { key = "sodCP", min = 1, max = 5, step = 1, suffix = "", onChange = set("sodCP") } }
    self.markRow = L:Row{ key = "useMark", label = "Mark for Death up to", spell = "Mark for Death", onToggle = set("useMark"),
        slider = { key = "markMaxCP", min = 1, max = 5, step = 1, suffix = "", onChange = set("markMaxCP") } }
    self.prepRow = L:Row{ key = "usePreparation", label = "Preparation", spell = "Preparation", onToggle = set("usePreparation") }
    self.gsRow = L:Row{ key = "useGhostly", label = "Ghostly Strike on cooldown", spell = "Ghostly Strike", onToggle = set("useGhostly") }

    -- Slice and Dice is the one upkeep a level 10 rogue already has, so it stays
    -- untagged while its tuning does not.
    L:Header("Buffs")
    self.sndRow = L:Row{ key = "useSnd", label = "Slice and Dice", spell = "Slice and Dice", onToggle = set("useSnd") }

    L:Header("Envenom", "assassination")
    self.envRow = L:Row{ key = "useEnvenom", label = "Envenom", spell = "Envenom", onToggle = set("useEnvenom") }

    L:Header("Buff timing", { assassination = true, combat = true, subtlety = true })
    self.renewRow = L:Row{ label = "Refresh when under",
        slider = { key = "buffRenew", min = 0, max = 2, step = 1, suffix = "s", onChange = set("buffRenew") } }
    -- Highest combo point count a refresh may spend. 5 = no ceiling (unchanged
    -- behaviour). At 1 the two buffs are only ever refreshed with the single
    -- point Ruthlessness returns and every surplus point goes into Eviscerate -
    -- the right trade while fights are shorter than a full-length buff, and the
    -- wrong one in a raid, where the ceiling belongs back at 5.
    self.refreshMaxRow = L:Row{ label = "Spend at most",
        slider = { key = "refreshMaxCP", min = 1, max = 5, step = 1, suffix = "", onChange = set("refreshMaxCP") } }

    -- Untagged: "how many points before I finish" is the whole rotation at low
    -- level. The reservation switch moved down into Execute, where the phase it
    -- refers to actually lives.
    L:Header("Eviscerate")
    self.cpRow = L:Row{ label = "Use from",
        slider = { key = "cpFinish", min = 1, max = 5, step = 1, suffix = "", onChange = set("cpFinish") } }

    -- Rupture keeps a section of its own rather than sitting with the two buffs
    -- above: the ceiling there does not apply to it, and putting them together
    -- would imply it does. Its threshold is a floor, theirs is a ceiling.
    L:Header("Rupture", { assassination = true, combat = true, subtlety = true })
    self.rupRow = L:Row{ key = "useRupture", label = "Enable from", spell = "Rupture", onToggle = set("useRupture"),
        slider = { key = "ruptureCP", min = 1, max = 5, step = 1, suffix = "", onChange = set("ruptureCP") } }
    self.rupTTKRow = L:Row{ key = "useRuptureTTK", label = "Only if the target lives", onToggle = set("useRuptureTTK"),
        slider = { key = "ruptureMinTTK", min = 4, max = 40, step = 2, suffix = "s", onChange = set("ruptureMinTTK") } }

    -- Execute is a PHASE with three conditions, not three features. Under one
    -- header they read as what they are: when it starts, what it may spend, and
    -- when it is called off again.
    L:Header("Execute", { assassination = true, combat = true, subtlety = true })
    self.evisOnlyRow = L:Row{ key = "evisExecuteOnly", label = "Eviscerate only in this phase", onToggle = set("evisExecuteOnly") }
    self.execRow = L:Row{ key = "useExecute", label = "Enable below", onToggle = set("useExecute"),
        slider = { key = "executeHpPct", min = 1, max = 30, step = 1, suffix = "%", onChange = set("executeHpPct") } }
    -- Lowest combo point count the execute dump may spend. 1 = unchanged.
    self.execMinRow = L:Row{ label = "Use from",
        slider = { key = "executeMinCP", min = 1, max = 5, step = 1, suffix = "", onChange = set("executeMinCP") } }
    -- A brake on the execute above, never a second trigger: when the target is
    -- measurably going to outlive this many seconds, the low-combo-point dump
    -- is skipped and the normal build-up continues. 0 switches the brake off.
    self.execTTKRow = L:Row{ label = "Skip if alive past",
        slider = { key = "executeTTK", min = 0, max = 8, step = 1, suffix = "s", onChange = set("executeTTK") } }

    L:Header("Cooldowns", { assassination = true, combat = true, subtlety = true })
    self.cbRow = L:Row{ key = "useColdBlood", label = "Cold Blood with Eviscerate", spell = "Cold Blood", onToggle = set("useColdBlood") }
    self.cdRow = L:Row{ key = "popCDs", label = "Pop cooldowns", onToggle = set("popCDs") }
    self.cdEliteRow = L:Row{ key = "autoCDElite", label = "Auto on elite", onToggle = set("autoCDElite") }

    -- Poisons: the poison-control settings (Quick Bar + rebuff) live in the
    -- shared Aegis_SBR_BuffUp module (global per character, not per profile), so
    -- their toggles write there directly. The pre-pull reminder stays a
    -- per-profile setting. Presets open a text dialog on click.
    L:Header("Poisons", { assassination = true, combat = true, subtlety = true })
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

    -- Last section on every tab: which Goblin Brainwashing Device slot this
    -- tab answers to. Untagged, so it shows on all of them and always reports
    -- the tab you are looking at.
    ui:BuildGobboRow(L)

    L:Finish()

    ui:Tip(self.builderDD, "Builder", "The combo point builder you spam. Auto picks Noxious Assault if known, else Sinister Strike.")
    ui:Tip(self.saRow.cb, "Surprise Attack", "An extra builder on top of the one above: it awards a combo point, but is only castable right after the TARGET dodges you, inside a short window.", "Combat capstone (20 points). Guaranteed hit - can't be blocked, dodged or parried. Takes priority when the window is open, since missing it wastes the proc.")
    ui:Tip(self.ripRow.cb, "Riposte", "Cast right after a parry, inside the short Riposte window. Neither spends nor builds combo points.")
    ui:Tip(self.sndRow.cb, "Slice and Dice", "Kept up: refreshed cheaply at 1 combo point, dumped with Eviscerate above that.")
    ui:Tip(self.envRow.cb, "Envenom", "Kept up the same way as Slice and Dice (Turtle ability).")
    ui:Tip(self.renewRow.slider, "Refresh buffs at", "Seconds of remaining time at which Slice and Dice and Envenom are re-applied - and, on the Subtlety tab, Taste for Blood by Rupture. Whatever is left on the buff at that moment is thrown away, so a lower value wastes fewer combo points.", "1 is the measured sweet spot: refreshes land with ~0.6s to spare and the buffs practically never drop. 2 is safer on low energy. 0 waits for the buff to lapse - efficient, but the downtime is real.")
    ui:Tip(self.rupRow.cb, "Rupture", "With the Assassination talent Taste for Blood it is kept up for that melee-damage BUFF (not the bleed) and takes priority over the other finishers. Without the talent it simply maintains the bleed on your target.", "The slider is its own combo-point threshold, separate from Eviscerate's on purpose: only Rupture's payoff scales with the points spent (2% damage per point), and sharing Eviscerate's higher threshold meant it never got cast at all.")
    ui:Tip(self.rupRow.slider, "Rupture at CP", "Combo points required before Rupture is cast. Lower = renewed more reliably but a weaker buff; higher = stronger buff but it may never be reached, since every buff refresh resets you to 1 point.", "Recommended: 5. A recast simply overwrites the buff at whatever combo points it was cast with, so anything below 5 risks replacing an existing 10% Taste for Blood buff with a weaker one the moment Rupture comes due.")
    ui:Tip(self.evisOnlyRow.cb, "Eviscerate only in execute", "Reserve Eviscerate for the execute phase, so every other combo point goes into maintaining your buffs instead of direct damage.", "Useful once you maintain several buffs: refreshes keep resetting your points, so a normal Eviscerate threshold is rarely reached anyway.")
    ui:Tip(self.cpRow.slider, "Finisher combo points", "Eviscerate is used once combo points reach this number.", "Greyed out while \"Eviscerate only in execute\" is on, since that setting bypasses this threshold entirely.")
    ui:Tip(self.rupTTKRow.cb, "Rupture only if the target lives", "Rupture only when the target is measured to live at least this many seconds. Shorter: Eviscerate with the same points.", "The estimate needs a few seconds of damage; until then Rupture is allowed.")
    ui:Tip(self.rupTTKRow.slider, "Target lives at least", "Seconds the target must have left for Rupture to go out.")
    ui:Tip(self.execRow.cb, "Execute low-HP targets", "Below the health value on the right, Eviscerate fires with whatever combo points are on hand (at least 1) instead of waiting for the normal threshold.", "Ruthlessness guarantees a combo point after any finisher, so this rarely goes unused once a fight is underway.")
    ui:Tip(self.execRow.slider, "Execute below", "Target health percent under which Eviscerate finishes early rather than risk combo points going to waste on a kill.")
    ui:Tip(self.cbRow.cb, "Cold Blood with Eviscerate", "Fires Cold Blood in the same press, right before Eviscerate, so the guaranteed crit lands on your biggest hit. Costs no global cooldown.", "Tied to Eviscerate, not used on cooldown: the buff is spent by the next BUILDER too, Noxious Assault included, so popped at any other moment it is wasted. Skipped below the Eviscerate threshold.")
    ui:Tip(self.refreshMaxRow.slider, "Spend at most", "Ceiling on the combo points a Slice and Dice or Envenom refresh may spend. Above it the surplus goes into Eviscerate first and the buff is refreshed on the next press with the point Ruthlessness returns.", "Only their DURATION scales with points, and duration past the end of the fight is thrown away - measured, a dungeon pull runs ~20s. Set 1 for dungeons, 5 (off) for raids.")
    ui:Tip(self.execMinRow.slider, "Use from", "Floor on the combo points the execute dump may spend. Off (1) lets a single point finish.", "Unspent combo points cost nothing when the target dies with them - a 1-point Eviscerate costs a full energy bar's worth for less damage than the builder it replaces. Measured: raising this to 3 lost 0 combo points on kills.")
    ui:Tip(self.execTTKRow.slider, "Skip if alive past", "Cancels the execute dump when the target is measurably going to live longer than this, so an elite parked at low health does not collect weak finishers.", "A brake only - it never STARTS the execute phase, and cancels only below the Eviscerate threshold, so a full-value finisher is never held back. The estimate is rough, hence one direction only.")
    ui:Tip(self.cdRow.cb, "Pop cooldowns", "Use Adrenaline Rush and Blade Flurry every press (off the global cooldown).")
    ui:Tip(self.cdEliteRow.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
    ui:Tip(self.eaRow.cb, "Expose Armor", "Kept up the whole fight, ahead of every other finisher. The time left is read off the target (ClassicAPI) or counted from the last cast; it is re-applied under the seconds set below.", "The points are reserved for it early: once there is no longer time to spend five elsewhere and build them back before it drops - measured on this fight's own combo rate, shown as cps= in the trace - no other finisher goes out and the five points wait for the refresh line.")
    ui:Tip(self.eaTTKRow.cb, "Expose Armor only if the target lives", "Expose Armor - and the combo points held back for it - only on a target the time-to-kill estimate says lives at least this long. Raid trash that dies sooner gets Rupture, the sigil and the Mark instead; bosses keep it.", "Until the estimate has a few seconds of damage, Expose Armor waits and the points go to the other finishers. Bosses always get it.")
    ui:Tip(self.eaTTKRow.slider, "Target lives at least", "Seconds the target must have left for Expose Armor.")
    ui:Tip(self.eaRefreshRow.slider, "Expose Armor refresh under", "Seconds left on the debuff at which it is re-applied with five points. Lower keeps more of each debuff; higher leaves more room for a late fifth point.")
    ui:Tip(self.eaRow.slider, "Expose Armor at CP", "Combo points required before the debuff is applied. Its strength scales with the points spent, so anything below 5 puts up a weaker reduction than the warrior's Sunder it is meant to replace.")
    ui:Tip(self.garroteRow.cb, "Garrote from stealth", "The opener, and again after Vanish: from stealth and behind the target, ahead of everything else. Two combo points with Initiative. Not on a bleed-immune target - there the press goes to Hemorrhage.")
    ui:Tip(self.vanishRow.cb, "Vanish into the burst", "While Mark for Death runs and Shadow of Death is ready: Vanish, Garrote from the new stealth, Shadow of Death at five. Preparation then hands the three back for a second round.", "Needs Flash Powder; a refused Vanish stands down for a minute.")
    ui:Tip(self.evisSubRow.cb, "Eviscerate when nothing is due", "At five combo points with Expose Armor fresh, Rupture and Slice and Dice running and the sigil on cooldown, Eviscerate spends them. Off: the points wait.")
    ui:Tip(self.sodRow.cb, "Shadow of Death", "A sigil on the target for 6 seconds that banks a share of ALL damage the target takes, then releases it as physical damage. One minute cooldown.", "Above the buffs and Eviscerate, because those can be refreshed on any press while a missed sigil window is gone. Its value comes from outside you: the more the group hits, the more it stores.")
    ui:Tip(self.sodRow.slider, "Shadow of Death at CP", "Both the share banked and its cap scale per combo point: 1 point banks 10% up to 50% of your attack power, 5 points bank 50% up to 250%.", "5 is not a preference here. A 1-point sigil caps at a fifth of a full one, and the ability is on the same one minute cooldown either way.")
    ui:Tip(self.markRow.cb, "Mark for Death", "135% weapon damage that awards TWO combo points and cannot be dodged, blocked or parried, plus 30% attack power for the whole party for 8 seconds. Three minute cooldown.", "It is a builder, not a finisher - which is why it goes out ahead of your normal builder rather than waiting for combo points. The 8 second window is what Shadow of Death is meant to be fired into.")
    ui:Tip(self.markRow.slider, "Mark up to CP", "Highest combo point count it may be used at. Above this the two points it awards would run into the cap and be thrown away.", "Only matters after Preparation, which hands the cooldown back early enough to catch you at high combo points.")
    ui:Tip(self.prepRow.cb, "Preparation", "Clears the cooldown on your other rogue abilities. Used only when Mark for Death AND Shadow of Death are both actually on cooldown, so the seven minutes buy back three plus one.", "It also waits for a press with no finisher due, since it applies nothing and deals no damage itself.")
    ui:Tip(self.gsRow.cb, "Ghostly Strike on cooldown", "Takes the place of your normal builder whenever its 20 second cooldown is up: same 40 energy, same single combo point, but 125% weapon damage instead of Hemorrhage's 110% - and 15% dodge for 7 seconds on top.", "It is not in the Builder list above on purpose. That list is what you spam, and an ability on a 20 second cooldown picked there would fail four presses out of five.")
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
    -- Read through the active tab's layer, so the page shows the tab's values.
    buf = M:TabView(buf, M)
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
    ui:BindCheck(self.cbRow, buf.useColdBlood)

    -- Subtlety. Two floors and one ceiling, so the value column has to say which
    -- is which - the same rule the rest of this window follows.
    ui:BindCheck(self.garroteRow, buf.useGarrote, "Garrote")
    ui:BindCheck(self.vanishRow, buf.useVanishBurst, "Vanish")
    ui:BindCheck(self.evisSubRow, buf.useEviscerate ~= false, "Eviscerate")
    ui:BindCheck(self.eaRow, buf.useExposeArmor)
    local earv = buf.exposeRefresh or 3
    self.eaRefreshRow.slider:SetValue(earv)
    if self.eaRefreshRow.slider.valText then self.eaRefreshRow.slider.valText:SetText("<" .. earv .. "s") end
    ui:SliderEnable(self.eaRefreshRow.slider, buf.useExposeArmor and true or false)
    ui:BindCheck(self.eaTTKRow, buf.useExposeTTK)
    local ettk = buf.exposeMinTTK or 20
    self.eaTTKRow.slider:SetValue(ettk)
    if self.eaTTKRow.slider.valText then self.eaTTKRow.slider.valText:SetText(">=" .. ettk .. "s") end
    ui:SliderEnable(self.eaTTKRow.slider, (buf.useExposeArmor and buf.useExposeTTK) and true or false)
    local eav = buf.exposeCP or 5
    self.eaRow.slider:SetValue(eav)
    if self.eaRow.slider.valText then self.eaRow.slider.valText:SetText(">=" .. eav) end
    ui:SliderEnable(self.eaRow.slider, buf.useExposeArmor and true or false)

    ui:BindCheck(self.sodRow, buf.useShadowOfDeath)
    local sodv = buf.sodCP or 5
    self.sodRow.slider:SetValue(sodv)
    if self.sodRow.slider.valText then self.sodRow.slider.valText:SetText(">=" .. sodv) end
    ui:SliderEnable(self.sodRow.slider, buf.useShadowOfDeath and true or false)

    ui:BindCheck(self.markRow, buf.useMark)
    local mkv = buf.markMaxCP or 3
    self.markRow.slider:SetValue(mkv)
    if self.markRow.slider.valText then self.markRow.slider.valText:SetText("<=" .. mkv) end
    ui:SliderEnable(self.markRow.slider, buf.useMark and true or false)

    ui:BindCheck(self.prepRow, buf.usePreparation)
    ui:BindCheck(self.gsRow, buf.useGhostly)
    ui:BindCheck(self.cdRow, buf.popCDs)
    ui:BindCheck(self.cdEliteRow, buf.autoCDElite)

    -- ">=" marks a floor, "<=" a ceiling. Without it four sliders all read
    -- "... CP" while meaning opposite things, which is exactly how a ceiling
    -- got mistaken for a floor.
    local cpv = buf.cpFinish or 4
    self.cpRow.slider:SetValue(cpv)
    if self.cpRow.slider.valText then self.cpRow.slider.valText:SetText(">=" .. cpv) end

    local rupv = buf.ruptureCP or 3
    self.rupRow.slider:SetValue(rupv)
    if self.rupRow.slider.valText then self.rupRow.slider.valText:SetText(">=" .. rupv) end
    -- Was live and settable with Rupture switched off, unlike every other row.
    ui:SliderEnable(self.rupRow.slider, buf.useRupture and true or false)
    ui:BindCheck(self.rupTTKRow, buf.useRuptureTTK)
    local rttk = buf.ruptureMinTTK or 16
    self.rupTTKRow.slider:SetValue(rttk)
    if self.rupTTKRow.slider.valText then self.rupTTKRow.slider.valText:SetText(">=" .. rttk .. "s") end
    ui:SliderEnable(self.rupTTKRow.slider, (buf.useRupture and buf.useRuptureTTK) and true or false)

    -- 0 is a valid setting ("only once it has dropped"), so this must not use
    -- `or` with a non-zero fallback - that would silently turn 0 into 3.
    local renewv = buf.buffRenew
    if renewv == nil then renewv = 1 end
    self.renewRow.slider:SetValue(renewv)
    if self.renewRow.slider.valText then self.renewRow.slider.valText:SetText(renewv .. "s") end
    -- Only meaningful while at least one of the two buffs it governs is on.
    ui:SliderEnable(self.renewRow.slider, (buf.useSnd or buf.useEnvenom) and true or false)

    local rmax = buf.refreshMaxCP or 5
    self.refreshMaxRow.slider:SetValue(rmax)
    if self.refreshMaxRow.slider.valText then
        self.refreshMaxRow.slider.valText:SetText(rmax < 5 and ("<=" .. rmax) or "off")
    end
    -- Needs a buff to govern, and needs Eviscerate to be available for the
    -- surplus - with "Eviscerate only in execute" there is nowhere for the
    -- extra points to go, so the ceiling would do nothing.
    ui:SliderEnable(self.refreshMaxRow.slider,
        ((buf.useSnd or buf.useEnvenom) and not buf.evisExecuteOnly) and true or false)

    ui:BindCheck(self.evisOnlyRow, buf.evisExecuteOnly)
    ui:SliderEnable(self.cpRow.slider, not buf.evisExecuteOnly)

    ui:BindCheck(self.execRow, buf.useExecute)
    local execv = buf.executeHpPct or 10
    self.execRow.slider:SetValue(execv)
    if self.execRow.slider.valText then self.execRow.slider.valText:SetText(execv .. "%") end

    local ttkv = buf.executeTTK or 0
    self.execTTKRow.slider:SetValue(ttkv)
    if self.execTTKRow.slider.valText then
        self.execTTKRow.slider.valText:SetText(ttkv > 0 and (ttkv .. "s") or "off")
    end
    local emin = buf.executeMinCP or 1
    self.execMinRow.slider:SetValue(emin)
    if self.execMinRow.slider.valText then
        self.execMinRow.slider.valText:SetText(emin > 1 and (">=" .. emin) or "off")
    end
    -- Every execute control is meaningless with execute itself switched off.
    ui:SliderEnable(self.execTTKRow.slider, buf.useExecute and true or false)
    ui:SliderEnable(self.execRow.slider, buf.useExecute and true or false)
    ui:SliderEnable(self.execMinRow.slider, buf.useExecute and true or false)

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
