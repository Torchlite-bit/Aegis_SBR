-- ============================================================
-- Class_Warlock_UI  -  warlock window body for Aegis_SBR
-- Builds and binds only the warlock specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.WARLOCK
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
    self.coaRow = L:Row{ key = "coaSecondary", label = "Keep Curse of Agony up too (Malediction)", spell = "Curse of Agony", onToggle = set("coaSecondary") }

    L:Header("Filler and pet")
    self.fillerDD = L:Dropdown("filler", "Filler", 200, set("filler"))
    self.gapDD = L:Dropdown("dhGapFiller", "Between channels", 200, set("dhGapFiller"))
    self.dhDotRow = L:Row{ label = "Top up DoTs before Dark Harvest",
        slider = { key = "dhDot", min = 0, max = 20, step = 1, suffix = "s", onChange = set("dhDotRemain") } }
    self.chanDotRow = L:Row{ label = "Top up DoTs before other channels",
        slider = { key = "chDot", min = 0, max = 20, step = 1, suffix = "s", onChange = set("chanDotRemain") } }
    self.petRow = L:Row{ key = "petAttack", label = "Send pet to attack", onToggle = set("petAttack") }
    self.petMeleeRow = L:Row{ key = "petMeleeOnly", label = "Pet melee only", onToggle = set("petMeleeOnly") }
    self.nightfallRow = L:Row{ key = "nightfall", label = "Shadow Bolt on Shadow Trance", spell = "Shadow Bolt", onToggle = set("nightfall") }

    L:Header("Mana (Life Tap)")
    self.tapRow = L:Row{ key = "lifeTap", label = "Use Life Tap", spell = "Life Tap", onToggle = set("lifeTap"),
        slider = { key = "ltMana", min = 0, max = 100, step = 5, suffix = "%", onChange = set("lifeTapMana") } }
    self.tapHpRow = L:Row{ label = "Keep HP above",
        slider = { key = "ltHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("lifeTapHpMin") } }
    self.wandFloorRow = L:Row{ label = "Wand below mana",
        slider = { key = "wmFloor", min = 0, max = 50, step = 5, suffix = "%", onChange = set("wandManaFloor") } }

    L:Header("Execute (target low HP)")
    self.sburnRow = L:Row{ key = "useShadowburn", label = "Shadowburn", spell = "Shadowburn", onToggle = set("useShadowburn"),
        slider = { key = "sbHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("shadowburnHp") } }
    self.dsoulRow = L:Row{ key = "useDrainSoul", label = "Drain Soul", spell = "Drain Soul", onToggle = set("useDrainSoul"),
        slider = { key = "dsHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("drainSoulHp") } }
    self.shardRow = L:Row{ key = "keepShards", label = "Stop early to keep shards", onToggle = set("keepShards"),
        slider = { key = "shardTarget", min = 1, max = 60, step = 1, suffix = "", onChange = set("shardTarget") } }
    self.dotStopRow = L:Row{ label = "Stop new DoTs below",
        slider = { key = "dotStopHp", min = 0, max = 50, step = 5, suffix = "%", onChange = set("dotStopHp") } }
    self.dotStopCorrRow = L:Row{ key = "dotStopKeepCorruption", label = "Keep Corruption up anyway", spell = "Corruption",
        onToggle = set("dotStopKeepCorruption") }

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
    ui:Tip(self.coaRow.cb, "Keep Curse of Agony up too", "Malediction lets Curse of Agony run beside your main curse but it expires sooner.", "When on, only Curse of Agony is recast as it falls off. Not used with Curse of Doom or when it already is the main curse.")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled DoT is up.", "Wand conserves mana, Shadow Bolt and Drain Life spend it. Drain Soul is for a low-level warlock with no wand: a channel, so it yields whenever a DoT would lapse during it.")
    ui:Tip(self.gapDD, "Between channels", "What to use while Dark Harvest is on cooldown. Only applies when Dark Harvest is your filler.", "Only started when nothing needs you during the channel: no DoT about to lapse, no Dark Harvest coming up mid-channel. Otherwise the wand covers the gap.")
    ui:Tip(self.petRow.cb, "Pet attack", "Send the active pet onto your target.")
    ui:Tip(self.petMeleeRow.cb, "Pet only in melee range", "Send the pet only when the target is within melee range,", "so an accidentally targeted far enemy does not pull the pet away.")
    ui:Tip(self.nightfallRow.cb, "Shadow Bolt on Shadow Trance", "When the Nightfall proc lights up, fire the free instant Shadow Bolt.", "Auto-enabled when the Nightfall talent is detected; this toggle forces it on otherwise. Only used when the filler is not already Shadow Bolt.")
    ui:Tip(self.tapRow.cb, "Life Tap", "Convert health to mana when mana is low and health is high.")
    ui:Tip(self.tapRow.slider, "Tap below mana", "Life Tap only when mana is under this value.")
    ui:Tip(self.tapHpRow.slider, "Keep HP above", "Life Tap only while health stays over this value.")
    ui:Tip(self.dhDotRow.slider, "Top up DoTs before Dark Harvest",
        "A DoT with less time left than this is re-applied before Dark Harvest starts.",
        "Dark Harvest speeds up the DoTs already on the target, so one that drops out partway through loses that boost for the rest of the channel - which is why this margin is the larger of the two. 0 starts the channel whatever the DoTs are doing.")
    ui:Tip(self.chanDotRow.slider, "Top up DoTs before other channels",
        "The same, for Drain Life, Drain Soul and anything else used as a filler or between Dark Harvest channels.",
        "These channels do nothing for your DoTs - the only question is whether they keep running alongside, so a shorter margin is usually enough. The rotation holds the whole press for a channel, so anything due inside it has to go out first. 0 starts the channel whatever the DoTs are doing.")
    ui:Tip(self.wandFloorRow.slider, "Wand below mana", "Below this mana percent, switch to the wand instead of stalling on a DoT you cannot afford right now (Life Tap is tried first if it is safe to use).")
    ui:Tip(self.sburnRow.cb, "Shadowburn", "Instant execute under the threshold below. Costs a Soul Shard and has a cooldown.", "Burst finish; if you want the shard instead, use Drain Soul.")
    ui:Tip(self.dsoulRow.cb, "Drain Soul", "Channel in the target's last seconds to bank a Soul Shard and regen mana.", "If both this and Shadowburn are on, Shadowburn fires first when ready.")
    ui:Tip(self.sburnRow.slider, "Burn below", "Target health percent under which Shadowburn fires.")
    ui:Tip(self.dsoulRow.slider, "Drain below", "Target health percent under which Drain Soul channels.")
    ui:Tip(self.shardRow.cb, "Stop early to keep shards", "Once you hold at least this many shards, Drain Soul stops finishing targets so the filler (or Shadowburn) takes over instead.")
    ui:Tip(self.shardRow.slider, "Shard target", "Drain Soul keeps finishing targets while you hold fewer shards than this.")
    ui:Tip(self.dotStopRow.slider, "Stop new DoTs below", "Below this target health, no damage-over-time effect is applied or refreshed any more - the press goes to your filler instead.", "A fresh DoT never earns its mana back on a mob about to die: Siphon Life needs most of its 30s to break even and Curse of Agony's damage comes at the end. Set to 0 to switch this off. DoTs already ticking are never cancelled.")
    ui:Tip(self.dotStopCorrRow.cb, "Keep Corruption up anyway", "Exempt Corruption from the stop above, so it alone is still refreshed while the target is nearly dead.", "Corruption is the shortest and most mana-efficient of the DoTs, which is why it is the one worth refreshing when nothing else is.")
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
    if self:KnowsSpell("Drain Soul")  then table.insert(fo, { label = "Drain Soul",  value = "Drain Soul" })  end
    if self:KnowsSpell("Dark Harvest") then table.insert(fo, { label = "Dark Harvest", value = "Dark Harvest" }) end
    local fcur = buf.filler or "Shoot"
    local fshown, fc
    if fcur == "Shoot" then fshown, fc = "Wand (Shoot)", ui.COL.white
    elseif self:KnowsSpell(fcur) then fshown, fc = fcur, ui.COL.white
    else fshown, fc = fcur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.fillerDD, fo, fcur, fshown, fc)

    -- Gap filler: only meaningful while Dark Harvest is the chosen filler, so
    -- it is greyed out otherwise rather than silently doing nothing.
    local go = { { label = "Wand (Shoot)", value = "Shoot" } }
    if self:KnowsSpell("Shadow Bolt") then table.insert(go, { label = "Shadow Bolt", value = "Shadow Bolt" }) end
    if self:KnowsSpell("Drain Life")  then table.insert(go, { label = "Drain Life",  value = "Drain Life" })  end
    if self:KnowsSpell("Drain Soul")  then table.insert(go, { label = "Drain Soul",  value = "Drain Soul" })  end
    local gcur = buf.dhGapFiller or "Shoot"
    local gshown, gc
    if gcur == "Shoot" then gshown, gc = "Wand (Shoot)", ui.COL.white
    elseif self:KnowsSpell(gcur) then gshown, gc = gcur, ui.COL.white
    else gshown, gc = gcur .. " (not learned)", ui.COL.red end
    if fcur ~= "Dark Harvest" then gshown, gc = gshown .. " (Dark Harvest only)", ui.COL.grey end
    ui:SetDropdown(self.gapDD, go, gcur, gshown, gc)

    ui:BindCheck(self.immoRow, buf.useImmolate)
    ui:BindCheck(self.corrRow, buf.useCorruption)
    ui:BindCheck(self.siphRow, buf.useSiphonLife)
    ui:BindCheck(self.coaRow, buf.coaSecondary)
    -- The secondary Curse of Agony is pointless when it already is the main
    -- curse and impossible with Curse of Doom, so grey it out in those cases.
    if buf.curse == "Curse of Agony" or buf.curse == "Curse of Doom" then
        self.coaRow.cb:Disable()
        ui:Color(self.coaRow.label, ui.COL.grey)
    end
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

    -- Always active: a safety net independent of the Life Tap toggle above.
    self.dhDotRow.slider:SetValue(buf.dhDotRemain or 0); self.dhDotRow.slider.valText:SetText((buf.dhDotRemain or 0) .. "s")
    ui:SliderEnable(self.dhDotRow.slider, true)
    self.chanDotRow.slider:SetValue(buf.chanDotRemain or 0); self.chanDotRow.slider.valText:SetText((buf.chanDotRemain or 0) .. "s")
    ui:SliderEnable(self.chanDotRow.slider, true)
    self.wandFloorRow.slider:SetValue(buf.wandManaFloor or 0); self.wandFloorRow.slider.valText:SetText((buf.wandManaFloor or 0) .. "%")
    ui:SliderEnable(self.wandFloorRow.slider, true)

    -- Execute
    ui:BindCheck(self.sburnRow, buf.useShadowburn)
    ui:BindCheck(self.dsoulRow, buf.useDrainSoul)
    ui:BindCheck(self.shardRow, buf.keepShards)
    self.sburnRow.slider:SetValue(buf.shadowburnHp or 0); self.sburnRow.slider.valText:SetText((buf.shadowburnHp or 0) .. "%")
    self.dsoulRow.slider:SetValue(buf.drainSoulHp or 0);  self.dsoulRow.slider.valText:SetText((buf.drainSoulHp or 0) .. "%")
    self.shardRow.slider:SetValue(buf.shardTarget or 1);  self.shardRow.slider.valText:SetText(tostring(buf.shardTarget or 1))
    ui:SliderEnable(self.sburnRow.slider, self:KnowsSpell("Shadowburn") and buf.useShadowburn)

    -- With Drain Soul chosen as the filler it already runs above the execute
    -- threshold as well, so the execute finisher has nothing left to add - the
    -- setting would sit there looking meaningful while changing nothing. Greyed
    -- out and relabelled rather than silently ignored.
    -- KnowsSpell-gated so an unlearned Drain Soul keeps BindCheck's own
    -- "(not learned)" label instead of being relabelled over it.
    local dsIsFiller = (buf.filler == "Drain Soul") and self:KnowsSpell("Drain Soul")
    if dsIsFiller then
        self.dsoulRow.cb:Disable()
        self.dsoulRow.label:SetText(self.dsoulRow.baseText .. " - already the filler")
        ui:Color(self.dsoulRow.label, ui.COL.grey)
    end
    ui:SliderEnable(self.dsoulRow.slider, self:KnowsSpell("Drain Soul") and buf.useDrainSoul and not dsIsFiller)

    -- Keeping shards is a refinement of the Drain Soul finisher, so grey it
    -- out whenever that finisher itself is off, unlearned, or superseded above.
    local dsoulOn = self:KnowsSpell("Drain Soul") and buf.useDrainSoul and not dsIsFiller
    if not dsoulOn then
        self.shardRow.cb:Disable()
        ui:Color(self.shardRow.label, ui.COL.grey)
    end
    ui:SliderEnable(self.shardRow.slider, dsoulOn and buf.keepShards)

    -- DoT stop: the slider is always live (0 switches the feature off), and the
    -- Corruption exception only means anything while the stop is actually armed.
    self.dotStopRow.slider:SetValue(buf.dotStopHp or 0)
    self.dotStopRow.slider.valText:SetText((buf.dotStopHp or 0) .. "%")
    ui:SliderEnable(self.dotStopRow.slider, true)
    ui:BindCheck(self.dotStopCorrRow, buf.dotStopKeepCorruption)
    if (buf.dotStopHp or 0) <= 0 then
        self.dotStopCorrRow.cb:Disable()
        ui:Color(self.dotStopCorrRow.label, ui.COL.grey)
    end

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
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
