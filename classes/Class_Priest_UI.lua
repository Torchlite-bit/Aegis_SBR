-- ============================================================
-- Class_Priest_UI  -  priest window body for AutoRota
-- Builds and binds only the priest specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = AutoRota.classes.PRIEST
M.useScrollLayout = true

function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(field) return function(v) if ui.buf then ui.buf[field] = v; ui:Refresh() end end end

    L:Header("General")
    self.healCB, self.innerFireCB = L:CheckPair(
        { "healMode", "Heal mode", nil, set("healMode") },
        { "useInnerFire", "Inner Fire", "Inner Fire", set("useInnerFire") })

    L:Header("Shadow & leveling")
    self.shadowformCB, self.mindBlastCB = L:CheckPair(
        { "useShadowform", "Hold Shadowform", "Shadowform", set("useShadowform") },
        { "useMindBlast", "Mind Blast", "Mind Blast", set("useMindBlast") })
    self.swpCB, self.devouringCB = L:CheckPair(
        { "useShadowWordPain", "Shadow Word: Pain", "Shadow Word: Pain", set("useShadowWordPain") },
        { "useDevouringPlague", "Devouring Plague", "Devouring Plague", set("useDevouringPlague") })
    self.holyFireCB, self.mindFlayCB = L:CheckPair(
        { "useHolyFire", "Holy Fire", "Holy Fire", set("useHolyFire") },
        { "useMindFlay", "Mind Flay", "Mind Flay", set("useMindFlay") })
    self.pwShieldMeleeCB, self.spiritTapCB = L:CheckPair(
        { "usePWShieldMelee", "Shield in melee", "Power Word: Shield", set("usePWShieldMelee") },
        { "useSpiritTapFinisher", "Finisher", "Mind Blast", set("useSpiritTapFinisher") })
    self.fillerDD, self.useWandCB = L:DropdownCheck(
        { key = "filler", label = "Filler", width = 110, onChange = set("filler") },
        { "useWand", "Use wand", nil, set("useWand") })
    self.executeSlider, self.manaFloorSlider = L:SliderPair(
        { "executeHp", "Finisher below", set("executeHp") },
        { "fillerManaFloor", "Wand below mana", set("fillerManaFloor") })

    L:Header("Healing")
    self.healAtSlider = L:Slider("healThreshold", "Heal members below", set("healThreshold"))
    self.flashHealCB, self.greaterHealCB = L:CheckPair(
        { "useFlashHeal", "Flash Heal", "Flash Heal", set("useFlashHeal") },
        { "useGreaterHeal", "Greater Heal", "Greater Heal", set("useGreaterHeal") })
    self.flashAtSlider = L:Slider("flashHealPct", "Flash only below", set("flashHealPct"))
    self.pwShieldCB, self.renewCB = L:CheckPair(
        { "usePWShield", "Power Word: Shield", "Power Word: Shield", set("usePWShield") },
        { "useRenew", "Renew", "Renew", set("useRenew") })
    self.prayerCB, self.innerFocusCB = L:CheckPair(
        { "usePrayer", "Prayer of Healing", "Prayer of Healing", set("usePrayer") },
        { "useInnerFocus", "Inner Focus", "Inner Focus", set("useInnerFocus") })
    self.offensiveCB, self.lightwellCB = L:CheckPair(
        { "offensiveWeave", "Weave Smite/Holy Fire", "Smite", set("offensiveWeave") },
        { "useLightwell", "Place Lightwell", "Lightwell", set("useLightwell") })

    L:Finish()

    ui:Tip(self.healCB.cb, "Heal mode", "Heal the party/raid with responsive downranking, and weave damage between heals.", "Also /ar heal on|off. Off runs the shadow/leveling damage rotation.")
    ui:Tip(self.innerFireCB.cb, "Inner Fire", "Keep Inner Fire active at all times for the armor and spell bonus.")
    ui:Tip(self.shadowformCB.cb, "Hold Shadowform", "Stay in Shadowform. While in it, Holy spells (Smite, Holy Fire, heals) are skipped.", "Leave off for a leveling priest who still casts Holy spells.")
    ui:Tip(self.mindBlastCB.cb, "Mind Blast", "Cast on cooldown - the Shadow Weaving trigger and the leveling pull.")
    ui:Tip(self.swpCB.cb, "Shadow Word: Pain", "Keep the DoT up. Turn off in raids to respect debuff-slot limits.")
    ui:Tip(self.devouringCB.cb, "Devouring Plague", "Undead-only DoT; used automatically when known.")
    ui:Tip(self.holyFireCB.cb, "Holy Fire", "Fire DoT and a strong nuke. Skipped while in Shadowform.")
    ui:Tip(self.mindFlayCB.cb, "Mind Flay", "Channelled shadow filler. Used when the filler is not the wand and mana is healthy.")
    ui:Tip(self.pwShieldMeleeCB.cb, "Shield when in melee", "Cast Power Word: Shield when a mob reaches melee or you drop below half health.", "Skipped while Weakened Soul is on you, so it never wastes a cast.")
    ui:Tip(self.spiritTapCB.cb, "Finisher (secure kill)", "Under the threshold below, burst with Mind Blast then Smite to land the killing blow", "and the experience (which also feeds Spirit Tap).")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled cast is up. Wand conserves mana (the 5-second rule);", "Mind Flay and Smite spend it. The wand is always used when mana drops below the floor.")
    ui:Tip(self.useWandCB.cb, "Use wand for mana regen", "On: the filler drops to the wand below the mana floor to let mana regenerate (the 5-second rule).", "Off: the priest keeps casting and never wands - it can run dry. With no wand equipped it auto-casts Mind Flay or Smite instead.")
    ui:Tip(self.executeSlider, "Finisher below", "Target health percent under which the kill-securing finisher fires.")
    ui:Tip(self.manaFloorSlider, "Wand below mana", "Your mana percent under which the filler drops to the wand to let mana regenerate.")
    ui:Tip(self.healAtSlider, "Heal members below", "Members below this health get healed; lower ranks are chosen for small deficits.")
    ui:Tip(self.flashHealCB.cb, "Flash Heal", "Fast, expensive heal reserved for emergencies so it does not drain your mana.")
    ui:Tip(self.greaterHealCB.cb, "Greater Heal", "Big, slow heal used (downranked) for large deficits.")
    ui:Tip(self.flashAtSlider, "Flash only below", "Health percent under which Flash Heal is allowed as an emergency heal.")
    ui:Tip(self.pwShieldCB.cb, "Power Word: Shield", "Shield a hurt member, but only when there is no Weakened Soul - the over-bubble guard.")
    ui:Tip(self.renewCB.cb, "Renew", "Keep the heal-over-time on a hurt member as efficient maintenance.")
    ui:Tip(self.prayerCB.cb, "Prayer of Healing", "Group heal when several members are hurt at once.")
    ui:Tip(self.innerFocusCB.cb, "Inner Focus on AoE", "Pop Inner Focus before Prayer of Healing to negate its mana cost.")
    ui:Tip(self.offensiveCB.cb, "Weave Smite/Holy Fire", "When no one needs healing, cast Smite/Holy Fire as offensive support.", "Skipped in Shadowform. Pairs with Enlighten-style talents.")
    ui:Tip(self.lightwellCB.cb, "Place Lightwell", "Place a Lightwell when out of combat, off cooldown, and known.")
end

function M:RefreshBody(ui, buf)
    -- filler dropdown: wand always, the casts only if known
    local fo = { { label = "Wand (Shoot)", value = "Wand" } }
    if self:KnowsSpell("Mind Flay") then table.insert(fo, { label = "Mind Flay", value = "Mind Flay" }) end
    if self:KnowsSpell("Smite")     then table.insert(fo, { label = "Smite",     value = "Smite" })     end
    local fcur = buf.filler or "Wand"
    local fshown, fc
    if fcur == "Wand" then fshown, fc = "Wand (Shoot)", ui.COL.white
    elseif self:KnowsSpell(fcur) then fshown, fc = fcur, ui.COL.white
    else fshown, fc = fcur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.fillerDD, fo, fcur, fshown, fc)

    -- General
    ui:BindCheck(self.healCB, buf.healMode)
    ui:BindCheck(self.innerFireCB, buf.useInnerFire, "Inner Fire")

    -- Shadow & leveling
    ui:BindCheck(self.shadowformCB, buf.useShadowform, "Shadowform")
    ui:BindCheck(self.mindBlastCB, buf.useMindBlast, "Mind Blast")
    ui:BindCheck(self.swpCB, buf.useShadowWordPain, "Shadow Word: Pain")
    ui:BindCheck(self.devouringCB, buf.useDevouringPlague, "Devouring Plague")
    ui:BindCheck(self.holyFireCB, buf.useHolyFire, "Holy Fire")
    ui:BindCheck(self.mindFlayCB, buf.useMindFlay, "Mind Flay")
    ui:BindCheck(self.pwShieldMeleeCB, buf.usePWShieldMelee, "Power Word: Shield")
    ui:BindCheck(self.spiritTapCB, buf.useSpiritTapFinisher, "Mind Blast")
    self.executeSlider:SetValue(buf.executeHp or 0);        self.executeSlider.valText:SetText((buf.executeHp or 0) .. "%")
    self.manaFloorSlider:SetValue(buf.fillerManaFloor or 0); self.manaFloorSlider.valText:SetText((buf.fillerManaFloor or 0) .. "%")
    ui:BindCheck(self.useWandCB, buf.useWand)
    if not self:HasWand() then
        self.useWandCB.label:SetText("Use wand (none)")
        ui:Color(self.useWandCB.label, ui.COL.grey)
    end
    -- the damage filler/sliders matter in DPS mode
    local dpsOn = not buf.healMode
    ui:SliderEnable(self.executeSlider, dpsOn and buf.useSpiritTapFinisher)
    ui:SliderEnable(self.manaFloorSlider, dpsOn)

    -- Healing
    self.healAtSlider:SetValue(buf.healThreshold or 0); self.healAtSlider.valText:SetText((buf.healThreshold or 0) .. "%")
    self.flashAtSlider:SetValue(buf.flashHealPct or 0); self.flashAtSlider.valText:SetText((buf.flashHealPct or 0) .. "%")
    ui:BindCheck(self.flashHealCB, buf.useFlashHeal, "Flash Heal")
    ui:BindCheck(self.greaterHealCB, buf.useGreaterHeal, "Greater Heal")
    ui:BindCheck(self.pwShieldCB, buf.usePWShield, "Power Word: Shield")
    ui:BindCheck(self.renewCB, buf.useRenew, "Renew")
    ui:BindCheck(self.prayerCB, buf.usePrayer, "Prayer of Healing")
    ui:BindCheck(self.innerFocusCB, buf.useInnerFocus, "Inner Focus")
    ui:BindCheck(self.offensiveCB, buf.offensiveWeave, "Smite")
    ui:BindCheck(self.lightwellCB, buf.useLightwell, "Lightwell")
    -- heal sliders matter in heal mode
    ui:SliderEnable(self.healAtSlider, buf.healMode)
    ui:SliderEnable(self.flashAtSlider, buf.healMode and buf.useFlashHeal)
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
