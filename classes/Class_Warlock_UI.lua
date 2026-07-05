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
    self.immoRow = L:Row{ key = "useImmolate", label = "Immolate", spell = "Immolate", onToggle = set("useImmolate") }
    self.corrRow = L:Row{ key = "useCorruption", label = "Corruption", spell = "Corruption", onToggle = set("useCorruption") }
    self.siphRow = L:Row{ key = "useSiphonLife", label = "Siphon Life", spell = "Siphon Life", onToggle = set("useSiphonLife") }
    self.curseDD = L:Dropdown("curse", "Curse", 200, set("curse"))

    L:Header("Filler and pet")
    self.fillerDD = L:Dropdown("filler", "Filler", 200, set("filler"))
    self.petRow = L:Row{ key = "petAttack", label = "Send pet to attack", onToggle = set("petAttack") }
    self.petMeleeRow = L:Row{ key = "petMeleeOnly", label = "Pet melee only", onToggle = set("petMeleeOnly") }
    self.nightfallRow = L:Row{ key = "nightfall", label = "Shadow Bolt on Shadow Trance", spell = "Shadow Bolt", onToggle = set("nightfall") }

    L:Header("Mana (Life Tap)")
    self.tapRow = L:Row{ key = "lifeTap", label = "Use Life Tap", spell = "Life Tap", onToggle = set("lifeTap"),
        slider = { key = "ltMana", min = 0, max = 100, step = 5, suffix = "%", onChange = set("lifeTapMana") } }
    self.tapHpRow = L:Row{ label = "Keep HP above",
        slider = { key = "ltHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("lifeTapHpMin") } }

    L:Header("Execute (target low HP)")
    self.sburnRow = L:Row{ key = "useShadowburn", label = "Shadowburn", spell = "Shadowburn", onToggle = set("useShadowburn"),
        slider = { key = "sbHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("shadowburnHp") } }
    self.dsoulRow = L:Row{ key = "useDrainSoul", label = "Drain Soul", spell = "Drain Soul", onToggle = set("useDrainSoul"),
        slider = { key = "dsHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("drainSoulHp") } }

    L:Header("Survival")
    self.drainRow = L:Row{ key = "drainLifeSustain", label = "Drain Life when low", spell = "Drain Life", onToggle = set("drainLifeSustain"),
        slider = { key = "dlHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("drainLifeHp") } }
    self.funnelRow = L:Row{ key = "healthFunnel", label = "Health Funnel", spell = "Health Funnel", onToggle = set("healthFunnel"),
        slider = { key = "hfPet", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healthFunnelPetHp") } }
    self.funnelSelfRow = L:Row{ label = "Keep your HP above",
        slider = { key = "hfSelf", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healthFunnelHpMin") } }

    L:Finish()

    ui:Tip(self.immoRow.cb, "Immolate", "Direct fire damage plus a fire damage over time.", "Kept up first in the priority.")
    ui:Tip(self.corrRow.cb, "Corruption", "Shadow damage over time, applied after the curse.")
    ui:Tip(self.siphRow.cb, "Siphon Life", "Shadow damage over time that also heals you.")
    ui:Tip(self.curseDD, "Curse", "One curse per target. Curse of Agony has exact upkeep,", "others are reapplied on a timer for now.")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled DoT is up.", "Wand conserves mana, Shadow Bolt and Drain Life spend it.")
    ui:Tip(self.petRow.cb, "Pet attack", "Send the active pet onto your target.")
    ui:Tip(self.petMeleeRow.cb, "Pet only in melee range", "Send the pet only when the target is within melee range,", "so an accidentally targeted far enemy does not pull the pet away.")
    ui:Tip(self.nightfallRow.cb, "Shadow Bolt on Shadow Trance", "When the Nightfall proc lights up, fire the free instant Shadow Bolt.", "Auto-enabled when the Nightfall talent is detected; this toggle forces it on otherwise. Only used when the filler is not already Shadow Bolt.")
    ui:Tip(self.tapRow.cb, "Life Tap", "Convert health to mana when mana is low and health is high.")
    ui:Tip(self.tapRow.slider, "Tap below mana", "Life Tap only when mana is under this value.")
    ui:Tip(self.tapHpRow.slider, "Keep HP above", "Life Tap only while health stays over this value.")
    ui:Tip(self.sburnRow.cb, "Shadowburn", "Instant execute under the threshold below. Costs a Soul Shard and has a cooldown.", "Burst finish; if you want the shard instead, use Drain Soul.")
    ui:Tip(self.dsoulRow.cb, "Drain Soul", "Channel in the target's last seconds to bank a Soul Shard and regen mana.", "If both this and Shadowburn are on, Shadowburn fires first when ready.")
    ui:Tip(self.sburnRow.slider, "Burn below", "Target health percent under which Shadowburn fires.")
    ui:Tip(self.dsoulRow.slider, "Drain below", "Target health percent under which Drain Soul channels.")
    ui:Tip(self.drainRow.cb, "Drain Life when low", "Self-heal channel when your health dips below the value - the drain-tank safety net.")
    ui:Tip(self.funnelRow.cb, "Health Funnel pet", "Top the pet up when it drops, as long as your own health is safe (it transfers yours to the pet).")
    ui:Tip(self.drainRow.slider, "Heal below", "Your health percent under which Drain Life is channeled.")
    ui:Tip(self.funnelRow.slider, "Pet below", "Pet health percent under which Health Funnel is cast.")
    ui:Tip(self.funnelSelfRow.slider, "Keep your HP above", "Never Health Funnel while your own health is under this value.")
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

    ui:BindCheck(self.immoRow, buf.useImmolate)
    ui:BindCheck(self.corrRow, buf.useCorruption)
    ui:BindCheck(self.siphRow, buf.useSiphonLife)
    ui:BindCheck(self.petRow, buf.petAttack)
    ui:BindCheck(self.petMeleeRow, buf.petMeleeOnly)
    if not buf.petAttack then
        self.petMeleeRow.cb:Disable()
        ui:Color(self.petMeleeRow.label, ui.COL.grey)
    end
    ui:BindCheck(self.nightfallRow, buf.nightfall)
    ui:BindCheck(self.tapRow, buf.lifeTap)

    self.tapRow.slider:SetValue(buf.lifeTapMana or 0);  self.tapRow.slider.valText:SetText((buf.lifeTapMana or 0) .. "%")
    self.tapHpRow.slider:SetValue(buf.lifeTapHpMin or 0); self.tapHpRow.slider.valText:SetText((buf.lifeTapHpMin or 0) .. "%")
    local tapOn = self:KnowsSpell("Life Tap") and buf.lifeTap
    ui:SliderEnable(self.tapRow.slider, tapOn and true or false)
    ui:SliderEnable(self.tapHpRow.slider, tapOn and true or false)

    -- Execute
    ui:BindCheck(self.sburnRow, buf.useShadowburn)
    ui:BindCheck(self.dsoulRow, buf.useDrainSoul)
    self.sburnRow.slider:SetValue(buf.shadowburnHp or 0); self.sburnRow.slider.valText:SetText((buf.shadowburnHp or 0) .. "%")
    self.dsoulRow.slider:SetValue(buf.drainSoulHp or 0);  self.dsoulRow.slider.valText:SetText((buf.drainSoulHp or 0) .. "%")
    ui:SliderEnable(self.sburnRow.slider, self:KnowsSpell("Shadowburn") and buf.useShadowburn)
    ui:SliderEnable(self.dsoulRow.slider, self:KnowsSpell("Drain Soul") and buf.useDrainSoul)

    -- Survival
    ui:BindCheck(self.drainRow, buf.drainLifeSustain)
    ui:BindCheck(self.funnelRow, buf.healthFunnel)
    self.drainRow.slider:SetValue(buf.drainLifeHp or 0);       self.drainRow.slider.valText:SetText((buf.drainLifeHp or 0) .. "%")
    self.funnelRow.slider:SetValue(buf.healthFunnelPetHp or 0); self.funnelRow.slider.valText:SetText((buf.healthFunnelPetHp or 0) .. "%")
    self.funnelSelfRow.slider:SetValue(buf.healthFunnelHpMin or 0); self.funnelSelfRow.slider.valText:SetText((buf.healthFunnelHpMin or 0) .. "%")
    ui:SliderEnable(self.drainRow.slider, self:KnowsSpell("Drain Life") and buf.drainLifeSustain)
    local funnelOn = self:KnowsSpell("Health Funnel") and buf.healthFunnel
    ui:SliderEnable(self.funnelRow.slider, funnelOn)
    ui:SliderEnable(self.funnelSelfRow.slider, funnelOn)
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
