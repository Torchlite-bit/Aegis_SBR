-- ============================================================
-- Class_Priest_UI  -  priest window body for Aegis_SBR
-- Builds and binds only the priest specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.PRIEST
M.useScrollLayout = true

function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(field) return function(v) if ui.buf then ui.buf[field] = v; ui:Refresh() end end end

    L:Header("General")
    self.healRow = L:Row{ key = "healMode", label = "Heal mode", onToggle = set("healMode") }
    self.innerFireRow = L:Row{ key = "useInnerFire", label = "Inner Fire", spell = "Inner Fire", onToggle = set("useInnerFire") }

    L:Header("Shadow & leveling")
    self.shadowformRow = L:Row{ key = "useShadowform", label = "Hold Shadowform", spell = "Shadowform", onToggle = set("useShadowform") }
    self.mindBlastRow = L:Row{ key = "useMindBlast", label = "Mind Blast", spell = "Mind Blast", onToggle = set("useMindBlast") }
    self.swpRow = L:Row{ key = "useShadowWordPain", label = "Shadow Word: Pain", spell = "Shadow Word: Pain", onToggle = set("useShadowWordPain") }
    self.devouringRow = L:Row{ key = "useDevouringPlague", label = "Devouring Plague", spell = "Devouring Plague", onToggle = set("useDevouringPlague") }
    self.holyFireRow = L:Row{ key = "useHolyFire", label = "Holy Fire", spell = "Holy Fire", onToggle = set("useHolyFire") }
    self.mindFlayRow = L:Row{ key = "useMindFlay", label = "Mind Flay", spell = "Mind Flay", onToggle = set("useMindFlay") }
    self.pwShieldMeleeRow = L:Row{ key = "usePWShieldMelee", label = "Shield in melee", spell = "Power Word: Shield", onToggle = set("usePWShieldMelee") }
    self.spiritTapRow = L:Row{ key = "useSpiritTapFinisher", label = "Finisher (secure kill)", spell = "Mind Blast", onToggle = set("useSpiritTapFinisher"),
        slider = { key = "executeHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("executeHp") } }
    self.fillerDD = L:Dropdown("filler", "Filler", 170, set("filler"))
    self.useWandRow = L:Row{ key = "useWand", label = "Use wand", onToggle = set("useWand"),
        slider = { key = "fillerManaFloor", min = 0, max = 100, step = 5, suffix = "%", onChange = set("fillerManaFloor") } }

    L:Header("Healing")
    self.healAtRow = L:Row{ label = "Heal members below",
        slider = { key = "healThreshold", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healThreshold") } }
    self.flashHealRow = L:Row{ key = "useFlashHeal", label = "Flash Heal", spell = "Flash Heal", onToggle = set("useFlashHeal"),
        slider = { key = "flashHealPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("flashHealPct") } }
    self.greaterHealRow = L:Row{ key = "useGreaterHeal", label = "Greater Heal", spell = "Greater Heal", onToggle = set("useGreaterHeal") }
    self.pwShieldRow = L:Row{ key = "usePWShield", label = "Power Word: Shield", spell = "Power Word: Shield", onToggle = set("usePWShield") }
    self.renewRow = L:Row{ key = "useRenew", label = "Renew", spell = "Renew", onToggle = set("useRenew") }
    self.prayerRow = L:Row{ key = "usePrayer", label = "Prayer of Healing", spell = "Prayer of Healing", onToggle = set("usePrayer") }
    self.innerFocusRow = L:Row{ key = "useInnerFocus", label = "Inner Focus", spell = "Inner Focus", onToggle = set("useInnerFocus") }
    self.offensiveRow = L:Row{ key = "offensiveWeave", label = "Weave Smite/Holy Fire", spell = "Smite", onToggle = set("offensiveWeave") }
    self.lightwellRow = L:Row{ key = "useLightwell", label = "Place Lightwell", spell = "Lightwell", onToggle = set("useLightwell") }

    L:Finish()

    ui:Tip(self.healRow.cb, "Heal mode", "Heal the party/raid with responsive downranking, and weave damage between heals.", "Also /sbr heal on|off. Off runs the shadow/leveling damage rotation.")
    ui:Tip(self.innerFireRow.cb, "Inner Fire", "Keep Inner Fire active at all times for the armor and spell bonus.")
    ui:Tip(self.shadowformRow.cb, "Hold Shadowform", "Stay in Shadowform. While in it, Holy spells (Smite, Holy Fire, heals) are skipped.", "Leave off for a leveling priest who still casts Holy spells.")
    ui:Tip(self.mindBlastRow.cb, "Mind Blast", "Cast on cooldown - the Shadow Weaving trigger and the leveling pull.")
    ui:Tip(self.swpRow.cb, "Shadow Word: Pain", "Keep the DoT up. Turn off in raids to respect debuff-slot limits.")
    ui:Tip(self.devouringRow.cb, "Devouring Plague", "Undead-only DoT; used automatically when known.")
    ui:Tip(self.holyFireRow.cb, "Holy Fire", "Fire DoT and a strong nuke. Skipped while in Shadowform.")
    ui:Tip(self.mindFlayRow.cb, "Mind Flay", "Channelled shadow filler. Used when the filler is not the wand and mana is healthy.")
    ui:Tip(self.pwShieldMeleeRow.cb, "Shield when in melee", "Cast Power Word: Shield when a mob reaches melee or you drop below half health.", "Skipped while Weakened Soul is on you, so it never wastes a cast.")
    ui:Tip(self.spiritTapRow.cb, "Finisher (secure kill)", "Under the threshold below, burst with Mind Blast then Smite to land the killing blow", "and the experience (which also feeds Spirit Tap).")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled cast is up. Wand conserves mana (the 5-second rule);", "Mind Flay and Smite spend it. The wand is always used when mana drops below the floor.")
    ui:Tip(self.useWandRow.cb, "Use wand for mana regen", "On: the filler drops to the wand below the mana floor to let mana regenerate (the 5-second rule).", "Off: the priest keeps casting and never wands - it can run dry. With no wand equipped it auto-casts Mind Flay or Smite instead.")
    ui:Tip(self.spiritTapRow.slider, "Finisher below", "Target health percent under which the kill-securing finisher fires.")
    ui:Tip(self.useWandRow.slider, "Wand below mana", "Your mana percent under which the filler drops to the wand to let mana regenerate.")
    ui:Tip(self.healAtRow.slider, "Heal members below", "Members below this health get healed; lower ranks are chosen for small deficits.")
    ui:Tip(self.flashHealRow.cb, "Flash Heal", "Fast, expensive heal reserved for emergencies so it does not drain your mana.")
    ui:Tip(self.greaterHealRow.cb, "Greater Heal", "Big, slow heal used (downranked) for large deficits.")
    ui:Tip(self.flashHealRow.slider, "Flash only below", "Health percent under which Flash Heal is allowed as an emergency heal.")
    ui:Tip(self.pwShieldRow.cb, "Power Word: Shield", "Shield a hurt member, but only when there is no Weakened Soul - the over-bubble guard.")
    ui:Tip(self.renewRow.cb, "Renew", "Keep the heal-over-time on a hurt member as efficient maintenance.")
    ui:Tip(self.prayerRow.cb, "Prayer of Healing", "Group heal when several members are hurt at once.")
    ui:Tip(self.innerFocusRow.cb, "Inner Focus on AoE", "Pop Inner Focus before Prayer of Healing to negate its mana cost.")
    ui:Tip(self.offensiveRow.cb, "Weave Smite/Holy Fire", "When no one needs healing, cast Smite/Holy Fire as offensive support.", "Skipped in Shadowform. Pairs with Enlighten-style talents.")
    ui:Tip(self.lightwellRow.cb, "Place Lightwell", "Place a Lightwell when out of combat, off cooldown, and known.")
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
    ui:BindCheck(self.healRow, buf.healMode)
    ui:BindCheck(self.innerFireRow, buf.useInnerFire, "Inner Fire")

    -- Shadow & leveling
    ui:BindCheck(self.shadowformRow, buf.useShadowform, "Shadowform")
    ui:BindCheck(self.mindBlastRow, buf.useMindBlast, "Mind Blast")
    ui:BindCheck(self.swpRow, buf.useShadowWordPain, "Shadow Word: Pain")
    ui:BindCheck(self.devouringRow, buf.useDevouringPlague, "Devouring Plague")
    ui:BindCheck(self.holyFireRow, buf.useHolyFire, "Holy Fire")
    ui:BindCheck(self.mindFlayRow, buf.useMindFlay, "Mind Flay")
    ui:BindCheck(self.pwShieldMeleeRow, buf.usePWShieldMelee, "Power Word: Shield")
    ui:BindCheck(self.spiritTapRow, buf.useSpiritTapFinisher, "Mind Blast")
    self.spiritTapRow.slider:SetValue(buf.executeHp or 0);   self.spiritTapRow.slider.valText:SetText((buf.executeHp or 0) .. "%")
    self.useWandRow.slider:SetValue(buf.fillerManaFloor or 0); self.useWandRow.slider.valText:SetText((buf.fillerManaFloor or 0) .. "%")
    ui:BindCheck(self.useWandRow, buf.useWand)
    if not self:HasWand() then
        self.useWandRow.label:SetText("Use wand (none)")
        ui:Color(self.useWandRow.label, ui.COL.grey)
    end
    -- the damage filler/sliders matter in DPS mode
    local dpsOn = not buf.healMode
    ui:SliderEnable(self.spiritTapRow.slider, dpsOn and buf.useSpiritTapFinisher)
    ui:SliderEnable(self.useWandRow.slider, dpsOn)

    -- Healing
    self.healAtRow.slider:SetValue(buf.healThreshold or 0); self.healAtRow.slider.valText:SetText((buf.healThreshold or 0) .. "%")
    self.flashHealRow.slider:SetValue(buf.flashHealPct or 0); self.flashHealRow.slider.valText:SetText((buf.flashHealPct or 0) .. "%")
    ui:BindCheck(self.flashHealRow, buf.useFlashHeal, "Flash Heal")
    ui:BindCheck(self.greaterHealRow, buf.useGreaterHeal, "Greater Heal")
    ui:BindCheck(self.pwShieldRow, buf.usePWShield, "Power Word: Shield")
    ui:BindCheck(self.renewRow, buf.useRenew, "Renew")
    ui:BindCheck(self.prayerRow, buf.usePrayer, "Prayer of Healing")
    ui:BindCheck(self.innerFocusRow, buf.useInnerFocus, "Inner Focus")
    ui:BindCheck(self.offensiveRow, buf.offensiveWeave, "Smite")
    ui:BindCheck(self.lightwellRow, buf.useLightwell, "Lightwell")
    -- heal sliders matter in heal mode
    ui:SliderEnable(self.healAtRow.slider, buf.healMode)
    ui:SliderEnable(self.flashHealRow.slider, buf.healMode and buf.useFlashHeal)
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
