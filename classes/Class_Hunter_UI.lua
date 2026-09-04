-- ============================================================
-- Class_Hunter_UI  -  hunter window body for Aegis_SBR
-- Builds and binds only the hunter specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.HUNTER
M.useScrollLayout = true
M.specTabs = {
    field = "mode", default = "ranged",
    tabs = {
        { key = "auto",   label = "Auto",   tip1 = "Picks ranged vs melee by your distance to the target each press." },
        { key = "ranged", label = "Ranged", tip1 = "Auto Shot + Steady Shot weave (BM / MM)." },
        { key = "melee",  label = "Melee",  tip1 = "Aspect of the Wolf, swings, Raptor Strike, Mongoose Bite (Survival / BM-melee)." },
    },
}

-- ============================================================
-- build body (hunter controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Targeting")
    self.markRow = L:Row{ key = "useHuntersMark", label = "Hunter's Mark", spell = "Hunter's Mark", onToggle = set("useHuntersMark") }
    self.stingDD = L:Dropdown("sting", "Sting", 180, set("sting"))

    self.rangedSection = L:Header("Ranged Shots", { ranged = true, auto = true })
    self.steadyRow = L:Row{ key = "useSteadyShot", label = "Steady Shot", spell = "Steady Shot", onToggle = set("useSteadyShot") }
    self.arcaneRow = L:Row{ key = "useArcaneShot", label = "Arcane Shot", spell = "Arcane Shot", onToggle = set("useArcaneShot") }
    self.multiRow = L:Row{ key = "useMultiShot", label = "Multi-Shot", spell = "Multi-Shot", onToggle = set("useMultiShot") }
    self.aimedRow = L:Row{ key = "useAimedShot", label = "Aimed Shot", spell = "Aimed Shot", onToggle = set("useAimedShot") }
    self.aimedProcRow = L:Row{ key = "aimedOnlyOnProc", label = "Aimed only on L&L", onToggle = set("aimedOnlyOnProc") }
    self.aimedOpenerRow = L:Row{ key = "useAimedOpener", label = "Aimed opener (pre-pull)", onToggle = set("useAimedOpener") }

    L:Header("AoE & Survival")
    self.volleyRow = L:Row{ key = "useVolley", label = "Volley leads AoE", spell = "Volley", onToggle = set("useVolley") }
    self.trapRow = L:Row{ key = "useImmolationTrap", label = "Immolation Trap", spell = "Immolation Trap", onToggle = set("useImmolationTrap") }

    self.meleeSection = L:Header("Melee", { melee = true, auto = true })
    self.raptorRow = L:Row{ key = "useRaptorStrike", label = "Raptor Strike", spell = "Raptor Strike", onToggle = set("useRaptorStrike") }
    self.mongooseRow = L:Row{ key = "useMongooseBite", label = "Mongoose Bite", spell = "Mongoose Bite", onToggle = set("useMongooseBite") }
    self.wingRow = L:Row{ key = "useWingClip", label = "Wing Clip", spell = "Wing Clip", onToggle = set("useWingClip") }
    self.lacerateRow = L:Row{ key = "useLacerate", label = "Lacerate bleed", spell = "Lacerate", onToggle = set("useLacerate") }
    self.carveRow = L:Row{ key = "useCarve", label = "Carve (melee AoE)", spell = "Carve", onToggle = set("useCarve") }

    L:Header("Aspect")
    self.aspectRow = L:Row{ key = "useAspect", label = "Combat aspect",
        sub = "automatic Hawk / Wolf - switch off to choose your own", onToggle = set("useAspect") }
    self.manaAspRow = L:Row{ key = "useManaAspect", label = "Viper below",
        spell = "Aspect of the Viper", onToggle = set("useManaAspect"),
        slider = { key = "manaAspectPct", min = 0, max = 90, step = 5, suffix = "%", onChange = set("manaAspectPct") } }
    self.manaBackRow = L:Row{ label = "Back to combat at",
        slider = { key = "manaAspectBackPct", min = 5, max = 100, step = 5, suffix = "%", onChange = set("manaAspectBackPct") } }

    L:Header("Pet")
    self.petRow = L:Row{ key = "petAttack", label = "Send pet to attack", onToggle = set("petAttack") }
    self.mendRow = L:Row{ key = "useMendPet", label = "Mend Pet", spell = "Mend Pet", onToggle = set("useMendPet"),
        slider = { key = "mendPetHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("mendPetHp") } }
    self.tauntRow = L:Row{ key = "petTaunt", label = "Pet taunt", spell = "Growl", onToggle = set("petTaunt") }
    self.kcRow = L:Row{ key = "useKillCommand", label = "Kill Command", spell = "Kill Command", onToggle = set("useKillCommand") }
    self.baitedRow = L:Row{ key = "useBaitedShot", label = "Baited Shot on pet crit", spell = "Baited Shot", onToggle = set("useBaitedShot") }
    -- A window, not a rotation setting, so it writes to the pet module directly
    -- and lives per character rather than per profile - the same arrangement the
    -- rogue's poison rows use for the shared upkeep module.
    self.petWinRow = L:Row{ key = "petWindow", label = "Show pet window", onToggle = function(on)
        if Aegis_SBR_Pet then Aegis_SBR_Pet:SetShown(on) end
    end }

    L:Header("Cooldowns")
    self.cdRow = L:Row{ key = "popCDs", label = "Pop cooldowns", onToggle = set("popCDs") }
    self.cdEliteRow = L:Row{ key = "autoCDElite", label = "Auto on elite", onToggle = set("autoCDElite") }

    -- Last section on every tab: which Goblin Brainwashing Device slot this
    -- tab answers to. Untagged, so it shows on all of them and always reports
    -- the tab you are looking at.
    ui:BuildGobboRow(L)

    L:Finish()

    ui:Tip(self.tauntRow.cb, "Smart Pet Taunt", "When the mob peels off your pet onto you, sends the pet's Growl to grab it back (throttled). Off by default; leave it off for melee-weave builds where you want aggro.")
    ui:Tip(self.markRow.cb, "Hunter's Mark", "Applied once per target and refreshed when it falls off.")
    ui:Tip(self.stingDD, "Sting", "The one sting kept up. Serpent is the staple DoT; Scorpid lowers melee hit; Viper drains mana. \"Viper > Serpent\" uses Viper Sting against mana users and falls back to Serpent Sting for everything else.")
    ui:Tip(self.steadyRow.cb, "Steady Shot", "Baseline at level 20. The 1:1 weave after each Auto Shot and the main filler. Queued so it does not clip the shot.")
    ui:Tip(self.arcaneRow.cb, "Arcane Shot", "Instant, weaved on cooldown between Auto Shots.")
    ui:Tip(self.multiRow.cb, "Multi-Shot", "On cooldown. Also leads AoE with Volley.")
    ui:Tip(self.aimedRow.cb, "Aimed Shot", "Only fired when Lock and Load procs (cast time drop + line cleave), so it never clips Auto Shot.")
    ui:Tip(self.aimedProcRow.cb, "Aimed only on Lock and Load", "Recommended on. Turn off to also hard-cast Aimed Shot on cooldown (will clip Auto Shot).")
    ui:Tip(self.aimedOpenerRow.cb, "Aimed Shot opener", "Open the pull with a hard-cast Aimed Shot before combat, then never clip Auto Shot during the fight.")
    ui:Tip(self.volleyRow.cb, "Volley", "When AoE mode is on (/sbr aoe), Volley leads then Multi-Shot fills.")
    ui:Tip(self.trapRow.cb, "Immolation Trap", "Survival: dropped on cooldown. Patch 1.18.1 allows traps in combat.")
    ui:Tip(self.raptorRow.cb, "Raptor Strike", "Melee on-next-swing strike, used on cooldown in melee mode.")
    ui:Tip(self.mongooseRow.cb, "Mongoose Bite", "An instant melee attack, used on its five second cooldown. 45% weapon damage plus a little, and it strikes with both weapons while dual wielding.", "It carries no dodge requirement on this client: the vanilla rule that it only follows a dodge does not apply here, so it goes out whenever the cooldown is up and you are in melee range.")
    ui:Tip(self.wingRow.cb, "Wing Clip", "Optional melee slow / kite tool.")
    ui:Tip(self.lacerateRow.cb, "Lacerate", "Melee bleed, kept rolling on the target in melee mode.")
    ui:Tip(self.carveRow.cb, "Carve", "Melee AoE strike. Leads the melee priority when AoE mode is on (/sbr aoe).")
    ui:Tip(self.aspectRow.cb, "Combat aspect", "Keeps Aspect of the Hawk up in ranged mode, Aspect of the Wolf in melee mode.", "Switch it OFF and the rotation never touches your aspect at all - the mana swap below included - so you can pick one yourself and it stays. That is the way to run an aspect the rotation has no use for, such as Aspect of the Beast.")
    ui:Tip(self.manaAspRow.cb, "Mana aspect swap", "Swap to Aspect of the Viper when mana drops below the first value, then back to your combat aspect (Hawk ranged / Wolf melee) once mana recovers to the second value.", "Needs Aspect of the Viper, which is learned at level 56. Before that there is nothing to swap to and this does nothing - no other aspect returns mana.")
    ui:Tip(self.manaAspRow.slider, "Viper below", "Drop to Aspect of the Viper when your mana falls under this percent.")
    ui:Tip(self.manaBackRow.slider, "Back to combat at", "Swap back to Aspect of the Hawk/Wolf once mana recovers to this percent. Set it above the 'Viper below' value.")
    ui:Tip(self.petRow.cb, "Pet attack", "Sends your pet onto the target each press.")
    ui:Tip(self.petWinRow.cb, "Show pet window", "A small movable readout: level, experience toward the next level, and happiness, with the border coloured green, yellow or red so the state reaches you across the screen.", "The point is a window small enough to leave up. Deliberately no countdown to the next loyalty level: the client exposes no progress within a level, and a measured one restarted at every zone change.")
    ui:Tip(self.mendRow.cb, "Mend Pet", "Heals the pet below the slider value (HoT, refreshed ~12s).")
    ui:Tip(self.mendRow.slider, "Mend Pet below", "Pet health percent under which Mend Pet is cast.")
    ui:Tip(self.kcRow.cb, "Kill Command", "Beast Mastery: fired on cooldown while in combat.")
    ui:Tip(self.baitedRow.cb, "Baited Shot", "Fired in the short window after your pet lands a critical strike.")
    ui:Tip(self.cdRow.cb, "Pop cooldowns", "Use Rapid Fire (and Bestial Wrath when known) every press.")
    ui:Tip(self.cdEliteRow.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
end

-- ============================================================
-- refresh body (hunter binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- sting dropdown: None plus the stings the hunter actually knows, plus the
    -- smart "Viper > Serpent" option when both stings are known
    local o = { { label = "None", value = "" } }
    local avail = self:AvailableStingsOf()
    for i = 1, table.getn(avail) do o[i + 1] = { label = avail[i], value = avail[i] } end
    if self:KnowsSpell("Viper Sting") and self:KnowsSpell("Serpent Sting") then
        table.insert(o, { label = "Viper > Serpent", value = "Viper > Serpent" })
    end
    local cur = buf.sting or ""
    local shown, c
    if cur == "" then shown, c = "None", ui.COL.white
    elseif cur == "Viper > Serpent" then shown, c = "Viper > Serpent", ui.COL.white
    elseif self:KnowsSpell(cur) then shown, c = cur, ui.COL.white
    else shown, c = cur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.stingDD, o, cur, shown, c)

    ui:BindCheck(self.markRow, buf.useHuntersMark)
    ui:BindCheck(self.steadyRow, buf.useSteadyShot)
    ui:BindCheck(self.arcaneRow, buf.useArcaneShot)
    ui:BindCheck(self.multiRow, buf.useMultiShot)
    ui:BindCheck(self.aimedRow, buf.useAimedShot)
    ui:BindCheck(self.volleyRow, buf.useVolley)
    ui:BindCheck(self.trapRow, buf.useImmolationTrap)
    ui:BindCheck(self.raptorRow, buf.useRaptorStrike)
    ui:BindCheck(self.mongooseRow, buf.useMongooseBite)
    ui:BindCheck(self.wingRow, buf.useWingClip)
    ui:BindCheck(self.lacerateRow, buf.useLacerate)
    ui:BindCheck(self.carveRow, buf.useCarve)
    ui:BindCheck(self.aspectRow, buf.useAspect)
    ui:BindCheck(self.manaAspRow, buf.useManaAspect)
    ui:BindCheck(self.petRow, buf.petAttack)
    if Aegis_SBR_Pet then self.petWinRow.cb:SetChecked(Aegis_SBR_Pet:Enabled()) end
    ui:BindCheck(self.tauntRow, buf.petTaunt)
    ui:BindCheck(self.mendRow, buf.useMendPet)
    ui:BindCheck(self.kcRow, buf.useKillCommand)
    ui:BindCheck(self.baitedRow, buf.useBaitedShot)
    ui:BindCheck(self.cdRow, buf.popCDs)
    ui:BindCheck(self.cdEliteRow, buf.autoCDElite)

    -- "Aimed only on Lock and Load" follows the Aimed Shot checkbox.
    self.aimedProcRow.cb:SetChecked(buf.aimedOnlyOnProc and true or false)
    if buf.useAimedShot then
        self.aimedProcRow.cb:Enable(); ui:Color(self.aimedProcRow.label, ui.COL.white)
    else
        self.aimedProcRow.cb:Disable(); ui:Color(self.aimedProcRow.label, ui.COL.grey)
    end
    ui:BindCheck(self.aimedOpenerRow, buf.useAimedOpener)

    -- The mana swap needs Aspect of the Viper, which Turtle teaches at level 56.
    -- The checkbox row carries the spell name, so the shared BindCheck above
    -- already greys it with "(not learned)" and hides its slider. Only the
    -- second row needs doing by hand: it has no checkbox of its own, so nothing
    -- would otherwise tell it that the pair it belongs to is inactive.
    local viperOK = self:KnowsSpell("Aspect of the Viper")
    ui:Color(self.manaBackRow.label, viperOK and ui.COL.white or ui.COL.grey)

    -- mana aspect sliders follow the swap checkbox: swap-to-Viper (low) and
    -- swap-back-to-combat (high).
    local map = buf.manaAspectPct or 30
    self.manaAspRow.slider:SetValue(map)
    if self.manaAspRow.slider.valText then self.manaAspRow.slider.valText:SetText(map .. "%") end
    ui:SliderEnable(self.manaAspRow.slider, (viperOK and buf.useManaAspect) and true or false)
    local mback = buf.manaAspectBackPct or (map + 15)
    self.manaBackRow.slider:SetValue(mback)
    if self.manaBackRow.slider.valText then self.manaBackRow.slider.valText:SetText(mback .. "%") end
    ui:SliderEnable(self.manaBackRow.slider, (viperOK and buf.useManaAspect) and true or false)

    -- Mend Pet threshold slider follows the Mend Pet checkbox.
    local mhp = buf.mendPetHp or 50
    self.mendRow.slider:SetValue(mhp)
    if self.mendRow.slider.valText then self.mendRow.slider.valText:SetText(mhp .. "%") end
    ui:SliderEnable(self.mendRow.slider, buf.useMendPet and true or false)

    -- Active-spec focus: fade + lock the playstyle you are not in. Auto uses both,
    -- so neither dims; Ranged dims only in pure Melee and Melee only in pure Ranged.
    local m = buf.mode or "ranged"
    self.rangedSection:SetDimmed(m == "melee")
    self.meleeSection:SetDimmed(m == "ranged")
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI framework not loaded. Aegis_SBR_UI.lua is missing or mislabeled in your Aegis_SBR folder, reinstall the files.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
