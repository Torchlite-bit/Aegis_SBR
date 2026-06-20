-- ============================================================
-- Class_Hunter_UI  -  hunter window body for AutoRota
-- Builds and binds only the hunter specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = AutoRota.classes.HUNTER
M.useScrollLayout = true

-- ============================================================
-- build body (hunter controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end

    L:Header("Playstyle")
    self.modeDD = L:Dropdown("mode", "Mode", 160, set("mode"))

    L:Header("Targeting")
    self.markCB = L:Check("useHuntersMark", "Hunter's Mark", "Hunter's Mark", set("useHuntersMark"))
    self.stingDD = L:Dropdown("sting", "Sting", 180, set("sting"))

    L:Header("Ranged Shots")
    self.steadyCB, self.arcaneCB = L:CheckPair(
        { "useSteadyShot", "Steady Shot", "Steady Shot", set("useSteadyShot") },
        { "useArcaneShot", "Arcane Shot", "Arcane Shot", set("useArcaneShot") })
    self.multiCB, self.aimedCB = L:CheckPair(
        { "useMultiShot", "Multi-Shot", "Multi-Shot", set("useMultiShot") },
        { "useAimedShot", "Aimed Shot", "Aimed Shot", set("useAimedShot") })
    self.aimedProcCB = L:Check("aimedOnlyOnProc", "Aimed only on Lock and Load", nil, set("aimedOnlyOnProc"))
    self.aimedOpenerCB = L:Check("useAimedOpener", "Aimed Shot opener (pre-pull)", nil, set("useAimedOpener"))

    L:Header("AoE & Survival")
    self.volleyCB, self.trapCB = L:CheckPair(
        { "useVolley", "Volley leads AoE", "Volley", set("useVolley") },
        { "useImmolationTrap", "Immolation Trap", "Immolation Trap", set("useImmolationTrap") })

    L:Header("Melee")
    self.raptorCB, self.mongooseCB = L:CheckPair(
        { "useRaptorStrike", "Raptor Strike", "Raptor Strike", set("useRaptorStrike") },
        { "useMongooseBite", "Mongoose Bite", "Mongoose Bite", set("useMongooseBite") })
    self.wingCB, self.lacerateCB = L:CheckPair(
        { "useWingClip", "Wing Clip", "Wing Clip", set("useWingClip") },
        { "useLacerate", "Lacerate bleed", "Lacerate", set("useLacerate") })
    self.carveCB = L:Check("useCarve", "Carve (melee AoE)", "Carve", set("useCarve"))

    L:Header("Aspect")
    self.aspectCB = L:Check("useAspect", "Keep combat aspect (Hawk/Wolf)", nil, set("useAspect"))
    self.manaAspCB = L:Check("useManaAspect", "Swap to mana aspect when low", nil, set("useManaAspect"))
    self.manaSlider = L:Slider("manaAspectPct", "Swap below mana", set("manaAspectPct"))

    L:Header("Pet")
    self.petCB, self.mendCB = L:CheckPair(
        { "petAttack", "Send pet to attack", nil, set("petAttack") },
        { "useMendPet", "Mend Pet", "Mend Pet", set("useMendPet") })
    self.mendSlider = L:Slider("mendPetHp", "Mend Pet below", set("mendPetHp"))
    self.tauntCB, self.kcCB = L:CheckPair(
        { "petTaunt", "Pet taunt", "Growl", set("petTaunt") },
        { "useKillCommand", "Kill Command", "Kill Command", set("useKillCommand") })
    self.baitedCB = L:Check("useBaitedShot", "Baited Shot on pet crit", "Baited Shot", set("useBaitedShot"))

    L:Header("Cooldowns")
    self.cdCB, self.cdEliteCB = L:CheckPair(
        { "popCDs", "Pop cooldowns", nil, set("popCDs") },
        { "autoCDElite", "Auto on elite", nil, set("autoCDElite") })

    L:Finish()

    ui:Tip(self.modeDD, "Playstyle", "Auto picks ranged vs melee by your distance to the target each press, so shots fire at range and strikes fire in melee. Ranged runs the Auto Shot + Steady Shot weave (BM/MM). Melee runs Aspect of the Wolf, melee swings, Raptor Strike and Mongoose Bite (Survival / BM-melee).", "Switch live with /ar mode ranged|melee|auto.")
    ui:Tip(self.tauntCB.cb, "Smart Pet Taunt", "When the mob peels off your pet onto you, sends the pet's Growl to grab it back (throttled). Off by default; leave it off for melee-weave builds where you want aggro.")
    ui:Tip(self.markCB.cb, "Hunter's Mark", "Applied once per target and refreshed when it falls off.")
    ui:Tip(self.stingDD, "Sting", "The one sting kept up. Serpent is the staple DoT; Scorpid lowers melee hit; Viper drains mana.")
    ui:Tip(self.steadyCB.cb, "Steady Shot", "Baseline at level 20. The 1:1 weave after each Auto Shot and the main filler. Queued so it does not clip the shot.")
    ui:Tip(self.arcaneCB.cb, "Arcane Shot", "Instant, weaved on cooldown between Auto Shots.")
    ui:Tip(self.multiCB.cb, "Multi-Shot", "On cooldown. Also leads AoE with Volley.")
    ui:Tip(self.aimedCB.cb, "Aimed Shot", "Only fired when Lock and Load procs (cast time drop + line cleave), so it never clips Auto Shot.")
    ui:Tip(self.aimedProcCB.cb, "Aimed only on Lock and Load", "Recommended on. Turn off to also hard-cast Aimed Shot on cooldown (will clip Auto Shot).")
    ui:Tip(self.aimedOpenerCB.cb, "Aimed Shot opener", "Open the pull with a hard-cast Aimed Shot before combat, then never clip Auto Shot during the fight.")
    ui:Tip(self.volleyCB.cb, "Volley", "When AoE mode is on (/ar aoe), Volley leads then Multi-Shot fills.")
    ui:Tip(self.trapCB.cb, "Immolation Trap", "Survival: dropped on cooldown. Patch 1.18.1 allows traps in combat.")
    ui:Tip(self.raptorCB.cb, "Raptor Strike", "Melee on-next-swing strike, used on cooldown in melee mode.")
    ui:Tip(self.mongooseCB.cb, "Mongoose Bite", "Reactive: fired in the window after you dodge an enemy attack.")
    ui:Tip(self.wingCB.cb, "Wing Clip", "Optional melee slow / kite tool.")
    ui:Tip(self.lacerateCB.cb, "Lacerate", "Melee bleed, kept rolling on the target in melee mode.")
    ui:Tip(self.carveCB.cb, "Carve", "Melee AoE strike. Leads the melee priority when AoE mode is on (/ar aoe).")
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
    ui:BindCheck(self.aimedOpenerCB, buf.useAimedOpener)

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
