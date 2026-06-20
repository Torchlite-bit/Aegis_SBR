-- ============================================================
-- Class_Warlock_UI  -  warlock window body for AutoRota
-- Builds and binds only the warlock specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = AutoRota.classes.WARLOCK
M.useScrollLayout = true

-- ============================================================
-- build body (warlock controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    -- set(field) writes ui.buf[field]; slider frame names differ from their
    -- buf fields, so the layout key (frame name) and the field are passed apart.
    local function set(field) return function(v) if ui.buf then ui.buf[field] = v; ui:Refresh() end end end

    L:Header("Damage over time")
    self.immoCB, self.corrCB = L:CheckPair(
        { "useImmolate", "Immolate", "Immolate", set("useImmolate") },
        { "useCorruption", "Corruption", "Corruption", set("useCorruption") })
    self.siphCB = L:Check("useSiphonLife", "Siphon Life", "Siphon Life", set("useSiphonLife"))
    self.curseDD = L:Dropdown("curse", "Curse", 200, set("curse"))

    L:Header("Filler and pet")
    self.fillerDD = L:Dropdown("filler", "Filler", 200, set("filler"))
    self.petCB, self.petMeleeCB = L:CheckPair(
        { "petAttack", "Send pet to attack", nil, set("petAttack") },
        { "petMeleeOnly", "Pet melee only", nil, set("petMeleeOnly") })
    self.nightfallCB = L:Check("nightfall", "Shadow Bolt on Shadow Trance", "Shadow Bolt", set("nightfall"))

    L:Header("Mana (Life Tap)")
    self.tapCB = L:Check("lifeTap", "Use Life Tap", "Life Tap", set("lifeTap"))
    self.tapManaSlider, self.tapHpSlider = L:SliderPair(
        { "ltMana", "Tap below mana", set("lifeTapMana") },
        { "ltHp", "Keep HP above", set("lifeTapHpMin") })

    L:Header("Execute (target low HP)")
    self.sburnCB, self.dsoulCB = L:CheckPair(
        { "useShadowburn", "Shadowburn", "Shadowburn", set("useShadowburn") },
        { "useDrainSoul", "Drain Soul", "Drain Soul", set("useDrainSoul") })
    self.sburnSlider, self.dsoulSlider = L:SliderPair(
        { "sbHp", "Burn below", set("shadowburnHp") },
        { "dsHp", "Drain below", set("drainSoulHp") })

    L:Header("Survival")
    self.drainCB, self.funnelCB = L:CheckPair(
        { "drainLifeSustain", "Drain Life when low", "Drain Life", set("drainLifeSustain") },
        { "healthFunnel", "Health Funnel", "Health Funnel", set("healthFunnel") })
    self.drainSlider, self.funnelPetSlider = L:SliderPair(
        { "dlHp", "Heal below", set("drainLifeHp") },
        { "hfPet", "Pet below", set("healthFunnelPetHp") })
    self.funnelSelfSlider = L:Slider("hfSelf", "Keep your HP above", set("healthFunnelHpMin"))

    L:Finish()

    ui:Tip(self.immoCB.cb, "Immolate", "Direct fire damage plus a fire damage over time.", "Kept up first in the priority.")
    ui:Tip(self.corrCB.cb, "Corruption", "Shadow damage over time, applied after the curse.")
    ui:Tip(self.siphCB.cb, "Siphon Life", "Shadow damage over time that also heals you.")
    ui:Tip(self.curseDD, "Curse", "One curse per target. Curse of Agony has exact upkeep,", "others are reapplied on a timer for now.")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled DoT is up.", "Wand conserves mana, Shadow Bolt and Drain Life spend it.")
    ui:Tip(self.petCB.cb, "Pet attack", "Send the active pet onto your target.")
    ui:Tip(self.petMeleeCB.cb, "Pet only in melee range", "Send the pet only when the target is within melee range,", "so an accidentally targeted far enemy does not pull the pet away.")
    ui:Tip(self.nightfallCB.cb, "Shadow Bolt on Shadow Trance", "When the Nightfall proc lights up, fire the free instant Shadow Bolt.", "Auto-enabled when the Nightfall talent is detected; this toggle forces it on otherwise. Only used when the filler is not already Shadow Bolt.")
    ui:Tip(self.tapCB.cb, "Life Tap", "Convert health to mana when mana is low and health is high.")
    ui:Tip(self.tapManaSlider, "Tap below mana", "Life Tap only when mana is under this value.")
    ui:Tip(self.tapHpSlider, "Keep HP above", "Life Tap only while health stays over this value.")
    ui:Tip(self.sburnCB.cb, "Shadowburn", "Instant execute under the threshold below. Costs a Soul Shard and has a cooldown.", "Burst finish; if you want the shard instead, use Drain Soul.")
    ui:Tip(self.dsoulCB.cb, "Drain Soul", "Channel in the target's last seconds to bank a Soul Shard and regen mana.", "If both this and Shadowburn are on, Shadowburn fires first when ready.")
    ui:Tip(self.sburnSlider, "Burn below", "Target health percent under which Shadowburn fires.")
    ui:Tip(self.dsoulSlider, "Drain below", "Target health percent under which Drain Soul channels.")
    ui:Tip(self.drainCB.cb, "Drain Life when low", "Self-heal channel when your health dips below the value - the drain-tank safety net.")
    ui:Tip(self.funnelCB.cb, "Health Funnel pet", "Top the pet up when it drops, as long as your own health is safe (it transfers yours to the pet).")
    ui:Tip(self.drainSlider, "Heal below", "Your health percent under which Drain Life is channeled.")
    ui:Tip(self.funnelPetSlider, "Pet below", "Pet health percent under which Health Funnel is cast.")
    ui:Tip(self.funnelSelfSlider, "Keep your HP above", "Never Health Funnel while your own health is under this value.")
end

-- ============================================================
-- refresh body (warlock binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- curse dropdown: none plus the curses the warlock knows
    local co = { { label = "(none)", value = "" } }
    local av = self:AvailableCursesOf()
    for i = 1, table.getn(av) do co[i + 1] = { label = av[i], value = av[i] } end
    local ccur = buf.curse or ""
    local cshown, cc
    if ccur == "" then cshown, cc = "(none)", ui.COL.white
    elseif self:KnowsSpell(ccur) then cshown, cc = ccur, ui.COL.white
    else cshown, cc = ccur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.curseDD, co, ccur, cshown, cc)

    -- filler dropdown: wand is always available, the casts only if known
    local fo = { { label = "Wand (Shoot)", value = "Shoot" } }
    if self:KnowsSpell("Shadow Bolt") then table.insert(fo, { label = "Shadow Bolt", value = "Shadow Bolt" }) end
    if self:KnowsSpell("Drain Life")  then table.insert(fo, { label = "Drain Life",  value = "Drain Life" })  end
    local fcur = buf.filler or "Shoot"
    local fshown, fc
    if fcur == "Shoot" then fshown, fc = "Wand (Shoot)", ui.COL.white
    elseif self:KnowsSpell(fcur) then fshown, fc = fcur, ui.COL.white
    else fshown, fc = fcur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.fillerDD, fo, fcur, fshown, fc)

    ui:BindCheck(self.immoCB, buf.useImmolate)
    ui:BindCheck(self.corrCB, buf.useCorruption)
    ui:BindCheck(self.siphCB, buf.useSiphonLife)
    ui:BindCheck(self.petCB, buf.petAttack)
    ui:BindCheck(self.petMeleeCB, buf.petMeleeOnly)
    if not buf.petAttack then
        self.petMeleeCB.cb:Disable()
        ui:Color(self.petMeleeCB.label, ui.COL.grey)
    end
    ui:BindCheck(self.nightfallCB, buf.nightfall)
    ui:BindCheck(self.tapCB, buf.lifeTap)

    self.tapManaSlider:SetValue(buf.lifeTapMana or 0); self.tapManaSlider.valText:SetText((buf.lifeTapMana or 0) .. "%")
    self.tapHpSlider:SetValue(buf.lifeTapHpMin or 0);  self.tapHpSlider.valText:SetText((buf.lifeTapHpMin or 0) .. "%")
    local tapOn = self:KnowsSpell("Life Tap") and buf.lifeTap
    if tapOn then
        self.tapManaSlider:EnableMouse(true);  self.tapManaSlider:SetAlpha(1)
        self.tapHpSlider:EnableMouse(true);    self.tapHpSlider:SetAlpha(1)
    else
        self.tapManaSlider:EnableMouse(false); self.tapManaSlider:SetAlpha(0.35)
        self.tapHpSlider:EnableMouse(false);   self.tapHpSlider:SetAlpha(0.35)
    end

    -- Execute
    ui:BindCheck(self.sburnCB, buf.useShadowburn)
    ui:BindCheck(self.dsoulCB, buf.useDrainSoul)
    self.sburnSlider:SetValue(buf.shadowburnHp or 0); self.sburnSlider.valText:SetText((buf.shadowburnHp or 0) .. "%")
    self.dsoulSlider:SetValue(buf.drainSoulHp or 0);  self.dsoulSlider.valText:SetText((buf.drainSoulHp or 0) .. "%")
    ui:SliderEnable(self.sburnSlider, self:KnowsSpell("Shadowburn") and buf.useShadowburn)
    ui:SliderEnable(self.dsoulSlider, self:KnowsSpell("Drain Soul") and buf.useDrainSoul)

    -- Survival
    ui:BindCheck(self.drainCB, buf.drainLifeSustain)
    ui:BindCheck(self.funnelCB, buf.healthFunnel)
    self.drainSlider:SetValue(buf.drainLifeHp or 0);       self.drainSlider.valText:SetText((buf.drainLifeHp or 0) .. "%")
    self.funnelPetSlider:SetValue(buf.healthFunnelPetHp or 0); self.funnelPetSlider.valText:SetText((buf.healthFunnelPetHp or 0) .. "%")
    self.funnelSelfSlider:SetValue(buf.healthFunnelHpMin or 0); self.funnelSelfSlider.valText:SetText((buf.healthFunnelHpMin or 0) .. "%")
    ui:SliderEnable(self.drainSlider, self:KnowsSpell("Drain Life") and buf.drainLifeSustain)
    local funnelOn = self:KnowsSpell("Health Funnel") and buf.healthFunnel
    ui:SliderEnable(self.funnelPetSlider, funnelOn)
    ui:SliderEnable(self.funnelSelfSlider, funnelOn)
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
