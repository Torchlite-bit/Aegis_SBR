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
    self.veRow = L:Row{ key = "useVampiricEmbrace", label = "Vampiric Embrace", spell = "Vampiric Embrace", onToggle = set("useVampiricEmbrace") }
    self.devouringRow = L:Row{ key = "useDevouringPlague", label = "Devouring Plague", spell = "Devouring Plague", onToggle = set("useDevouringPlague") }
    self.holyFireRow = L:Row{ key = "useHolyFire", label = "Holy Fire", spell = "Holy Fire", onToggle = set("useHolyFire") }
    self.mindFlayRow = L:Row{ key = "useMindFlay", label = "Mind Flay", spell = "Mind Flay", onToggle = set("useMindFlay") }
    self.pwShieldMeleeRow = L:Row{ key = "usePWShieldMelee", label = "Shield in melee", spell = "Power Word: Shield", onToggle = set("usePWShieldMelee") }
    self.spiritTapRow = L:Row{ key = "useSpiritTapFinisher", label = "Finisher (secure kill)", spell = "Mind Blast", onToggle = set("useSpiritTapFinisher"),
        slider = { key = "executeHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("executeHp") } }
    self.painSpikeRow = L:Row{ key = "usePainSpike", label = "Pain Spike in the finisher", spell = "Pain Spike", onToggle = set("usePainSpike") }
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
    self.offensiveRow = L:Row{ key = "offensiveWeave", label = "Weave Smite/Holy Fire above mana", spell = "Smite", onToggle = set("offensiveWeave"),
        slider = { key = "healNukeMana", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healNukeMana") } }
    self.healWandRow = L:Row{ key = "healWand", label = "Wand between heals", onToggle = set("healWand") }
    self.holyNovaRow = L:Row{ key = "useHolyNova", label = "Holy Nova between heals, enemies", spell = "Holy Nova", onToggle = set("useHolyNova"),
        slider = { key = "holyNovaCount", min = 1, max = 10, step = 1, onChange = set("holyNovaCount") } }
    self.lightwellRow = L:Row{ key = "useLightwell", label = "Place Lightwell", spell = "Lightwell", onToggle = set("useLightwell") }


    L:Header("Dispel")
    self.cureRow = L:Row{ key = "useCure", label = "Cure afflictions", spell = "Dispel Magic", onToggle = set("useCure") }
    self.curePctRow = L:Row{ label = "Cure first above",
        slider = { key = "curePct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("curePct") } }


    L:Header("Heal priority")
    self.prioRow = L:Row{ key = "healPrio", label = "Use priority list", onToggle = set("healPrio") }
    self.prioTargetRow = L:Row{ key = "healPrioTarget", label = "Your target first", onToggle = set("healPrioTarget") }

    L:Header("Priority list", function()
        return ui.buf and (ui.buf.healPrio or ui.buf.healPrioTarget) and true or false
    end)
    self.prioAddBtn = L:Button{ label = "Add target", onClick = function()
        if ui.buf then Aegis_SBR:PrioAdd(ui.buf, UnitName("target")); ui:Refresh() end
    end }
    self.prioClearBtn = L:Button{ label = "Clear", onClick = function()
        if ui.buf then ui.buf.healPrioList = {}; ui:Refresh() end
    end }
    self.prioBtns = {}
    for i = 1, 5 do
        local idx = i
        self.prioBtns[idx] = L:Button{ label = idx .. ".", onClick = function()
            if ui.buf then Aegis_SBR:PrioRemove(ui.buf, idx); ui:Refresh() end
        end }
    end

    L:Finish()

    ui:Tip(self.prioRow.cb, "Use priority list", "On a near tie, heal the listed players first: position 1 before position 2, both before anyone unlisted.", "A handicap, not a strict order - position 2 counts as 20%% healthier than it is, unlisted players as 35%%. Somebody in real trouble always outranks a scratched tank, because eligibility reads real health and only the ORDER is adjusted.")
    ui:Tip(self.prioTargetRow.cb, "Your target first", "While you have a friendly target selected it is considered first, ahead of the list.")
    ui:Tip(self.prioAddBtn, "Add target", "Adds your current target to the end of the list.", "Names, not raid slots, so the list survives a regroup. The same list decides who is dispelled first.")
    ui:Tip(self.prioClearBtn, "Clear", "Empties the priority list.")

    ui:Tip(self.cureRow.cb, "Cure afflictions", "Remove curses, poisons, diseases and magic from the group with whatever your class has for it - here: Disease (Abolish or Cure Disease) and Magic (Dispel Magic).", "Off by default. A dispel costs a global cooldown that would otherwise be a heal, and only what you can actually remove is ever considered.")
    ui:Tip(self.curePctRow.slider, "Cure first above", "The crossover between curing and healing, read off the WORST-HURT member. Above it the affliction comes first; below it the heal does.", "At 90 the group is cleansed first and topped up from 90 to 100 afterwards - the right order when the affliction is doing more damage than the missing tenth of a bar. 0 makes curing always yield, 100 makes it always come first.")

    ui:Tip(self.healRow.cb, "Heal mode", "Heal the party/raid with responsive downranking, and weave damage between heals.", "Also /sbr heal on|off. Off runs the shadow/leveling damage rotation.")
    ui:Tip(self.innerFireRow.cb, "Inner Fire", "Keep Inner Fire active at all times for the armor and spell bonus.")
    ui:Tip(self.shadowformRow.cb, "Hold Shadowform", "Stay in Shadowform. While in it, Holy spells (Smite, Holy Fire, heals) are skipped.", "Leave off for a leveling priest who still casts Holy spells.")
    ui:Tip(self.mindBlastRow.cb, "Mind Blast", "Cast on cooldown - the Shadow Weaving trigger and the leveling pull.")
    ui:Tip(self.swpRow.cb, "Shadow Word: Pain", "Keep the DoT up. Turn off in raids to respect debuff-slot limits.")
    ui:Tip(self.veRow.cb, "Vampiric Embrace", "Keep the one-minute debuff up after Shadow Word: Pain; your party is healed for a share of the shadow damage you deal. Takes a debuff slot and adds threat, so off by default.")
    ui:Tip(self.devouringRow.cb, "Devouring Plague", "Undead-only DoT; used automatically when known.")
    ui:Tip(self.holyFireRow.cb, "Holy Fire", "Fire DoT and a strong nuke. Skipped while in Shadowform.")
    ui:Tip(self.mindFlayRow.cb, "Mind Flay", "Channelled shadow filler. Used when the filler is not the wand and mana is healthy.")
    ui:Tip(self.pwShieldMeleeRow.cb, "Shield when in melee", "Cast Power Word: Shield when a mob reaches melee or you drop below half health.", "Skipped while Weakened Soul is on you, so it never wastes a cast.")
    ui:Tip(self.spiritTapRow.cb, "Finisher (secure kill)", "Under the threshold below, burst with Mind Blast then Smite to land the killing blow", "and the experience (which also feeds Spirit Tap).")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled cast is up. Wand conserves mana (the 5-second rule);", "Mind Flay and Smite spend it. The wand is always used when mana drops below the floor.")
    ui:Tip(self.useWandRow.cb, "Use wand for mana regen", "On: the filler drops to the wand below the mana floor to let mana regenerate (the 5-second rule).", "Off: the priest keeps casting and never wands - it can run dry. With no wand equipped it auto-casts Mind Flay or Smite instead.")
    ui:Tip(self.spiritTapRow.slider, "Finisher below", "Target health percent under which the kill-securing finisher fires.")
    ui:Tip(self.painSpikeRow.cb, "Pain Spike", "Under the finisher threshold, Pain Spike goes out first: instant shadow burst whose damage heals back after landing, so it is only worth a killing blow.")
    ui:Tip(self.useWandRow.slider, "Wand below mana", "Your mana percent under which the filler drops to the wand to let mana regenerate.")
    ui:Tip(self.healAtRow.slider, "Heal members below", "Members below this health get healed; lower ranks are chosen for small deficits.")
    ui:Tip(self.flashHealRow.cb, "Flash Heal", "Fast, expensive heal reserved for emergencies so it does not drain your mana.")
    ui:Tip(self.greaterHealRow.cb, "Greater Heal", "Big, slow heal used (downranked) for large deficits.")
    ui:Tip(self.flashHealRow.slider, "Flash only below", "Health percent under which Flash Heal is allowed as an emergency heal.")
    ui:Tip(self.pwShieldRow.cb, "Power Word: Shield", "Below the Flash Heal line: the shield first, then Flash Heal - but only when there is no Weakened Soul, the over-bubble guard.")
    ui:Tip(self.renewRow.cb, "Renew", "On a member under the heal line but above the Flash Heal line: Renew first when it is missing, the direct heal on the next press.")
    ui:Tip(self.prayerRow.cb, "Prayer of Healing", "Group heal when several members are hurt at once.")
    ui:Tip(self.innerFocusRow.cb, "Inner Focus on AoE", "Pop Inner Focus before Prayer of Healing to negate its mana cost.")
    ui:Tip(self.offensiveRow.cb, "Weave Smite/Holy Fire", "When no one needs healing, cast Holy Fire and Smite on your target - while your mana is above the value on the right.", "Heals always come first: a Smite or Holy Fire still casting is stopped as soon as somebody drops under the heal line. Skipped in Shadowform. Needs an enemy targeted (or the Assist targeting mode).")
    ui:Tip(self.offensiveRow.slider, "Smite above mana", "Mana percent above which the weave nukes. Below it the wand takes over, if switched on.")
    ui:Tip(self.healWandRow.cb, "Wand between heals", "When no one needs healing and the weave is off or under its mana line: the wand on your target. No mana is spent, so the five-second rule brings it back.", "A heal that is needed goes first and stops the wand.")
    ui:Tip(self.holyNovaRow.cb, "Holy Nova between heals", "When no one needs healing: Holy Nova while at least the number of enemies on the right stand within 10 yards of you, and your mana is above the weave line. It also heals the group.", "Heals come first. Needs the Holy Nova talent. Without nameplates to count, an enemy target in melee range counts as one.")
    ui:Tip(self.holyNovaRow.slider, "Enemies within 10 yards", "How many enemies must stand around you for Holy Nova.")
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
    ui:BindCheck(self.veRow, buf.useVampiricEmbrace, "Vampiric Embrace")
    ui:BindCheck(self.holyFireRow, buf.useHolyFire, "Holy Fire")
    ui:BindCheck(self.mindFlayRow, buf.useMindFlay, "Mind Flay")
    ui:BindCheck(self.pwShieldMeleeRow, buf.usePWShieldMelee, "Power Word: Shield")
    ui:BindCheck(self.spiritTapRow, buf.useSpiritTapFinisher, "Mind Blast")
    ui:BindCheck(self.painSpikeRow, buf.usePainSpike, "Pain Spike")
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
    local hnm = buf.healNukeMana or 50
    self.offensiveRow.slider:SetValue(hnm); self.offensiveRow.slider.valText:SetText(hnm .. "%")
    ui:SliderEnable(self.offensiveRow.slider, (buf.healMode and buf.offensiveWeave) and true or false)
    ui:BindCheck(self.healWandRow, buf.healWand)
    if not self:HasWand() then
        self.healWandRow.label:SetText("Wand between heals (none)")
        ui:Color(self.healWandRow.label, ui.COL.grey)
    else
        self.healWandRow.label:SetText("Wand between heals")
    end
    ui:BindCheck(self.holyNovaRow, buf.useHolyNova, "Holy Nova")
    local hnc = buf.holyNovaCount or 3
    self.holyNovaRow.slider:SetValue(hnc); self.holyNovaRow.slider.valText:SetText(hnc .. "+")
    ui:SliderEnable(self.holyNovaRow.slider, (buf.healMode and buf.useHolyNova) and true or false)
    ui:BindCheck(self.lightwellRow, buf.useLightwell, "Lightwell")
    -- heal sliders matter in heal mode
    ui:SliderEnable(self.healAtRow.slider, buf.healMode)
    ui:SliderEnable(self.flashHealRow.slider, buf.healMode and buf.useFlashHeal)

    ui:BindCheck(self.cureRow, buf.useCure, "Dispel Magic")
    local cpv = buf.curePct or 90
    self.curePctRow.slider:SetValue(cpv)
    if self.curePctRow.slider.valText then self.curePctRow.slider.valText:SetText(">" .. cpv .. "%") end
    ui:SliderEnable(self.curePctRow.slider, buf.useCure and true or false)

    ui:BindCheck(self.prioRow, buf.healPrio)

    ui:BindCheck(self.prioTargetRow, buf.healPrioTarget)
    local plist = buf.healPrioList or {}
    for i = 1, table.getn(self.prioBtns) do
        self.prioBtns[i].value:SetText(plist[i] or "|cff666666(empty)|r")
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
