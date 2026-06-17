-- ============================================================
-- Class_Hunter_UI  -  hunter window body for AutoRota
-- Builds and binds only the hunter specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.HUNTER

-- ============================================================
-- build body (hunter controls)
-- ============================================================
function M:BuildBody(ui, f)
    -- Playstyle
    ui:FS(f, "GameFontNormal", "Playstyle"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    ui:FS(f, "GameFontNormalSmall", "Mode"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -168)
    self.modeDD = ui:CreateDropdown("mode", f, 160, function(v) if ui.buf then ui.buf.mode = v; ui:Refresh() end end)
    self.modeDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -166)

    -- Targeting
    ui:FS(f, "GameFontNormal", "Targeting"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -200)
    self.markCB = ui:CreateCheck("useHuntersMark", f, "Keep Hunter's Mark up", "Hunter's Mark", function(on) if ui.buf then ui.buf.useHuntersMark = on; ui:Refresh() end end)
    self.markCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -222)
    ui:FS(f, "GameFontNormalSmall", "Sting"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -248)
    self.stingDD = ui:CreateDropdown("sting", f, 180, function(v) if ui.buf then ui.buf.sting = v; ui:Refresh() end end)
    self.stingDD:SetPoint("TOPLEFT", f, "TOPLEFT", 90, -246)

    -- Ranged Shots
    ui:FS(f, "GameFontNormal", "Ranged Shots"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -280)
    self.steadyCB = ui:CreateCheck("useSteadyShot", f, "Steady Shot weave", "Steady Shot", function(on) if ui.buf then ui.buf.useSteadyShot = on; ui:Refresh() end end)
    self.steadyCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -302)
    self.arcaneCB = ui:CreateCheck("useArcaneShot", f, "Arcane Shot", "Arcane Shot", function(on) if ui.buf then ui.buf.useArcaneShot = on; ui:Refresh() end end)
    self.arcaneCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -302)
    self.multiCB = ui:CreateCheck("useMultiShot", f, "Multi-Shot", "Multi-Shot", function(on) if ui.buf then ui.buf.useMultiShot = on; ui:Refresh() end end)
    self.multiCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -326)
    self.aimedCB = ui:CreateCheck("useAimedShot", f, "Aimed Shot", "Aimed Shot", function(on) if ui.buf then ui.buf.useAimedShot = on; ui:Refresh() end end)
    self.aimedCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -326)
    self.aimedProcCB = ui:CreateCheck("aimedOnlyOnProc", f, "Aimed only on Lock and Load", nil, function(on) if ui.buf then ui.buf.aimedOnlyOnProc = on; ui:Refresh() end end)
    self.aimedProcCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -350)

    -- AoE & Survival
    ui:FS(f, "GameFontNormal", "AoE & Survival"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -384)
    self.volleyCB = ui:CreateCheck("useVolley", f, "Volley leads AoE", "Volley", function(on) if ui.buf then ui.buf.useVolley = on; ui:Refresh() end end)
    self.volleyCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -406)
    self.trapCB = ui:CreateCheck("useImmolationTrap", f, "Immolation Trap on cd", "Immolation Trap", function(on) if ui.buf then ui.buf.useImmolationTrap = on; ui:Refresh() end end)
    self.trapCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -406)

    -- Melee
    ui:FS(f, "GameFontNormal", "Melee"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -440)
    self.raptorCB = ui:CreateCheck("useRaptorStrike", f, "Raptor Strike", "Raptor Strike", function(on) if ui.buf then ui.buf.useRaptorStrike = on; ui:Refresh() end end)
    self.raptorCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -462)
    self.mongooseCB = ui:CreateCheck("useMongooseBite", f, "Mongoose Bite (after dodge)", "Mongoose Bite", function(on) if ui.buf then ui.buf.useMongooseBite = on; ui:Refresh() end end)
    self.mongooseCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -462)
    self.wingCB = ui:CreateCheck("useWingClip", f, "Wing Clip", "Wing Clip", function(on) if ui.buf then ui.buf.useWingClip = on; ui:Refresh() end end)
    self.wingCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -486)
    self.lacerateCB = ui:CreateCheck("useLacerate", f, "Lacerate bleed", "Lacerate", function(on) if ui.buf then ui.buf.useLacerate = on; ui:Refresh() end end)
    self.lacerateCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -486)
    self.carveCB = ui:CreateCheck("useCarve", f, "Carve (melee AoE, with /ar aoe)", "Carve", function(on) if ui.buf then ui.buf.useCarve = on; ui:Refresh() end end)
    self.carveCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -510)

    -- Aspect
    ui:FS(f, "GameFontNormal", "Aspect"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -546)
    self.aspectCB = ui:CreateCheck("useAspect", f, "Keep combat aspect up (Hawk / Wolf)", nil, function(on) if ui.buf then ui.buf.useAspect = on; ui:Refresh() end end)
    self.aspectCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -568)
    self.manaAspCB = ui:CreateCheck("useManaAspect", f, "Swap to mana aspect when low", nil, function(on) if ui.buf then ui.buf.useManaAspect = on; ui:Refresh() end end)
    self.manaAspCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -592)
    self.manaSlider = ui:CreateSlider("manaAspectPct", f, "swap below", function(v) if ui.buf then ui.buf.manaAspectPct = v; ui:Refresh() end end)
    self.manaSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 210, -592)

    -- Pet
    ui:FS(f, "GameFontNormal", "Pet"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -626)
    self.petCB = ui:CreateCheck("petAttack", f, "Send pet to attack", nil, function(on) if ui.buf then ui.buf.petAttack = on; ui:Refresh() end end)
    self.petCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -648)
    self.mendCB = ui:CreateCheck("useMendPet", f, "Mend Pet when hurt", "Mend Pet", function(on) if ui.buf then ui.buf.useMendPet = on; ui:Refresh() end end)
    self.mendCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -648)
    self.mendSlider = ui:CreateSlider("mendPetHp", f, "Mend Pet below", function(v) if ui.buf then ui.buf.mendPetHp = v; ui:Refresh() end end)
    self.mendSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -674)
    self.tauntCB = ui:CreateCheck("petTaunt", f, "Pet taunts when it loses aggro", "Growl", function(on) if ui.buf then ui.buf.petTaunt = on; ui:Refresh() end end)
    self.tauntCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -674)
    self.kcCB = ui:CreateCheck("useKillCommand", f, "Kill Command on cd", "Kill Command", function(on) if ui.buf then ui.buf.useKillCommand = on; ui:Refresh() end end)
    self.kcCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -698)
    self.baitedCB = ui:CreateCheck("useBaitedShot", f, "Baited Shot on pet crit", "Baited Shot", function(on) if ui.buf then ui.buf.useBaitedShot = on; ui:Refresh() end end)
    self.baitedCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -698)

    -- Cooldowns
    ui:FS(f, "GameFontNormal", "Cooldowns"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -732)
    self.cdCB = ui:CreateCheck("popCDs", f, "Always pop cooldowns", nil, function(on) if ui.buf then ui.buf.popCDs = on; ui:Refresh() end end)
    self.cdCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -754)
    self.cdEliteCB = ui:CreateCheck("autoCDElite", f, "Auto on elite and boss", nil, function(on) if ui.buf then ui.buf.autoCDElite = on; ui:Refresh() end end)
    self.cdEliteCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -754)

    ui:Divider(f, -134)   -- above Playstyle
    ui:Divider(f, -192)   -- above Targeting
    ui:Divider(f, -272)   -- above Ranged Shots
    ui:Divider(f, -376)   -- above AoE & Survival
    ui:Divider(f, -432)   -- above Melee
    ui:Divider(f, -538)   -- above Aspect
    ui:Divider(f, -618)   -- above Pet
    ui:Divider(f, -724)   -- above Cooldowns

    ui:Tip(self.modeDD, "Playstyle", "Auto picks ranged vs melee by your distance to the target each press, so shots fire at range and strikes fire in melee. Ranged runs the Auto Shot + Steady Shot weave (BM/MM). Melee runs Aspect of the Wolf, melee swings, Raptor Strike and Mongoose Bite (Survival / BM-melee).", "Switch live with /ar mode ranged|melee|auto.")
    ui:Tip(self.tauntCB.cb, "Smart Pet Taunt", "When the mob peels off your pet onto you, sends the pet's Growl to grab it back (throttled). Off by default; leave it off for melee-weave builds where you want aggro.")
    ui:Tip(self.markCB.cb, "Hunter's Mark", "Applied once per target and refreshed when it falls off.")
    ui:Tip(self.stingDD, "Sting", "The one sting kept up. Serpent is the staple DoT; Scorpid lowers melee hit; Viper drains mana.")
    ui:Tip(self.steadyCB.cb, "Steady Shot", "Baseline at level 20. The 1:1 weave after each Auto Shot and the main filler. Queued so it does not clip the shot.")
    ui:Tip(self.arcaneCB.cb, "Arcane Shot", "Instant, weaved on cooldown between Auto Shots.")
    ui:Tip(self.multiCB.cb, "Multi-Shot", "On cooldown. Also leads AoE with Volley.")
    ui:Tip(self.aimedCB.cb, "Aimed Shot", "Only fired when Lock and Load procs (cast time drop + line cleave), so it never clips Auto Shot.")
    ui:Tip(self.aimedProcCB.cb, "Aimed only on Lock and Load", "Recommended on. Turn off to also hard-cast Aimed Shot on cooldown (will clip Auto Shot).")
    ui:Tip(self.volleyCB.cb, "Volley", "When AoE mode is on (/ar aoe), Volley leads then Multi-Shot fills.")
    ui:Tip(self.trapCB.cb, "Immolation Trap", "Survival: dropped on cooldown. Patch 1.18.1 allows traps in combat.")
    ui:Tip(self.raptorCB.cb, "Raptor Strike", "Melee on-next-swing strike, used on cooldown in melee mode.")
    ui:Tip(self.mongooseCB.cb, "Mongoose Bite", "Reactive: fired in the window after you dodge an enemy attack.")
    ui:Tip(self.wingCB.cb, "Wing Clip", "Optional melee slow / kite tool.")
    ui:Tip(self.aspectCB.cb, "Combat aspect", "Keeps Aspect of the Hawk up in ranged mode, Aspect of the Wolf in melee mode.")
    ui:Tip(self.manaAspCB.cb, "Mana aspect swap", "Swap to the mana-regenerating aspect below the slider value, then back to your combat aspect once mana recovers.")
    ui:Tip(self.manaSlider, "Swap below", "Mana percent under which the mana aspect is used.")
    ui:Tip(self.petCB.cb, "Pet attack", "Sends your pet onto the target each press.")
    ui:Tip(self.mendCB.cb, "Mend Pet", "Heals the pet below the slider value (HoT, refreshed ~12s).")
    ui:Tip(self.mendSlider, "Mend Pet below", "Pet health percent under which Mend Pet is cast.")
    ui:Tip(self.kcCB.cb, "Kill Command", "Beast Mastery: fired on cooldown while in combat.")
    ui:Tip(self.baitedCB.cb, "Baited Shot", "Fired in the short window after your pet lands a critical strike.")
    ui:Tip(self.cdCB.cb, "Pop cooldowns", "Use Rapid Fire (and Bestial Wrath when known) every press.")
    ui:Tip(self.cdEliteCB.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
end

-- ============================================================
-- refresh body (hunter binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- mode dropdown
    local modeOpts = {
        { label = "Auto (by distance)", value = "auto" },
        { label = "Ranged (BM / MM)", value = "ranged" },
        { label = "Melee (Survival / BM)", value = "melee" },
    }
    local modeLabel = { auto = "Auto (by distance)", ranged = "Ranged (BM / MM)", melee = "Melee (Survival / BM)" }
    local mcur = buf.mode or "ranged"
    ui:SetDropdown(self.modeDD, modeOpts, mcur, modeLabel[mcur] or mcur, ui.COL.white)

    -- sting dropdown: None plus the stings the hunter actually knows
    local o = { { label = "None", value = "" } }
    local avail = self:AvailableStingsOf()
    for i = 1, table.getn(avail) do o[i + 1] = { label = avail[i], value = avail[i] } end
    local cur = buf.sting or ""
    local shown, c
    if cur == "" then shown, c = "None", ui.COL.white
    elseif self:KnowsSpell(cur) then shown, c = cur, ui.COL.white
    else shown, c = cur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.stingDD, o, cur, shown, c)

    ui:BindCheck(self.markCB, buf.useHuntersMark)
    ui:BindCheck(self.steadyCB, buf.useSteadyShot)
    ui:BindCheck(self.arcaneCB, buf.useArcaneShot)
    ui:BindCheck(self.multiCB, buf.useMultiShot)
    ui:BindCheck(self.aimedCB, buf.useAimedShot)
    ui:BindCheck(self.volleyCB, buf.useVolley)
    ui:BindCheck(self.trapCB, buf.useImmolationTrap)
    ui:BindCheck(self.raptorCB, buf.useRaptorStrike)
    ui:BindCheck(self.mongooseCB, buf.useMongooseBite)
    ui:BindCheck(self.wingCB, buf.useWingClip)
    ui:BindCheck(self.lacerateCB, buf.useLacerate)
    ui:BindCheck(self.carveCB, buf.useCarve)
    ui:BindCheck(self.aspectCB, buf.useAspect)
    ui:BindCheck(self.manaAspCB, buf.useManaAspect)
    ui:BindCheck(self.petCB, buf.petAttack)
    ui:BindCheck(self.tauntCB, buf.petTaunt)
    ui:BindCheck(self.mendCB, buf.useMendPet)
    ui:BindCheck(self.kcCB, buf.useKillCommand)
    ui:BindCheck(self.baitedCB, buf.useBaitedShot)
    ui:BindCheck(self.cdCB, buf.popCDs)
    ui:BindCheck(self.cdEliteCB, buf.autoCDElite)

    -- "Aimed only on Lock and Load" follows the Aimed Shot checkbox.
    self.aimedProcCB.cb:SetChecked(buf.aimedOnlyOnProc and true or false)
    if buf.useAimedShot then
        self.aimedProcCB.cb:Enable()
        self.aimedProcCB.label:SetText("Aimed only on Lock and Load"); ui:Color(self.aimedProcCB.label, ui.COL.white)
    else
        self.aimedProcCB.cb:Disable()
        self.aimedProcCB.label:SetText("Aimed only on Lock and Load"); ui:Color(self.aimedProcCB.label, ui.COL.grey)
    end

    -- mana aspect slider follows the swap checkbox
    local map = buf.manaAspectPct or 30
    self.manaSlider:SetValue(map)
    if self.manaSlider.valText then self.manaSlider.valText:SetText(map .. "%") end
    if buf.useManaAspect then
        self.manaSlider:EnableMouse(true);  self.manaSlider:SetAlpha(1)
    else
        self.manaSlider:EnableMouse(false); self.manaSlider:SetAlpha(0.35)
    end

    -- Mend Pet threshold slider follows the Mend Pet checkbox.
    local mhp = buf.mendPetHp or 50
    self.mendSlider:SetValue(mhp)
    if self.mendSlider.valText then self.mendSlider.valText:SetText(mhp .. "%") end
    if buf.useMendPet then
        self.mendSlider:EnableMouse(true);  self.mendSlider:SetAlpha(1)
    else
        self.mendSlider:EnableMouse(false); self.mendSlider:SetAlpha(0.35)
    end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI framework not loaded. AutoRota_UI.lua is missing or mislabeled in your AutoRota folder, reinstall the files.")
        return
    end
    AutoRotaUI:Toggle()
end
