-- ============================================================
-- Class_Warlock_UI  -  warlock window body for AutoRota
-- Builds and binds only the warlock specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.WARLOCK

-- ============================================================
-- build body (warlock controls)
-- ============================================================
function M:BuildBody(ui, f)
    -- Damage over time
    ui:FS(f, "GameFontNormal", "Damage over time"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    self.immoCB = ui:CreateCheck("useImmolate", f, "Immolate", "Immolate", function(on) if ui.buf then ui.buf.useImmolate = on; ui:Refresh() end end)
    self.immoCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -166)
    self.corrCB = ui:CreateCheck("useCorruption", f, "Corruption", "Corruption", function(on) if ui.buf then ui.buf.useCorruption = on; ui:Refresh() end end)
    self.corrCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -166)
    self.siphCB = ui:CreateCheck("useSiphonLife", f, "Siphon Life", "Siphon Life", function(on) if ui.buf then ui.buf.useSiphonLife = on; ui:Refresh() end end)
    self.siphCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -190)

    ui:FS(f, "GameFontNormalSmall", "Curse"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -216)
    self.curseDD = ui:CreateDropdown("curse", f, 210, function(v) if ui.buf then ui.buf.curse = v; ui:Refresh() end end)
    self.curseDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -214)

    -- Filler and pet
    ui:FS(f, "GameFontNormal", "Filler and pet"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -248)
    ui:FS(f, "GameFontNormalSmall", "Filler"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -274)
    self.fillerDD = ui:CreateDropdown("filler", f, 210, function(v) if ui.buf then ui.buf.filler = v; ui:Refresh() end end)
    self.fillerDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -272)
    self.petCB = ui:CreateCheck("petAttack", f, "Send pet to attack", nil, function(on) if ui.buf then ui.buf.petAttack = on; ui:Refresh() end end)
    self.petCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -300)
    self.nightfallCB = ui:CreateCheck("nightfall", f, "Shadow Bolt on Shadow Trance", "Shadow Bolt", function(on) if ui.buf then ui.buf.nightfall = on; ui:Refresh() end end)
    self.nightfallCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -324)

    -- Mana (Life Tap)
    ui:FS(f, "GameFontNormal", "Mana (Life Tap)"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -356)
    self.tapCB = ui:CreateCheck("lifeTap", f, "Use Life Tap", "Life Tap", function(on) if ui.buf then ui.buf.lifeTap = on; ui:Refresh() end end)
    self.tapCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -380)
    self.tapManaSlider = ui:CreateSlider("ltMana", f, "tap below mana", function(v) if ui.buf then ui.buf.lifeTapMana = v; ui:Refresh() end end)
    self.tapManaSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -422)
    self.tapHpSlider = ui:CreateSlider("ltHp", f, "keep HP above", function(v) if ui.buf then ui.buf.lifeTapHpMin = v; ui:Refresh() end end)
    self.tapHpSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -422)

    -- Execute (target low HP)
    ui:FS(f, "GameFontNormal", "Execute (target low HP)"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -454)
    self.sburnCB = ui:CreateCheck("useShadowburn", f, "Shadowburn", "Shadowburn", function(on) if ui.buf then ui.buf.useShadowburn = on; ui:Refresh() end end)
    self.sburnCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -478)
    self.dsoulCB = ui:CreateCheck("useDrainSoul", f, "Drain Soul (shard)", "Drain Soul", function(on) if ui.buf then ui.buf.useDrainSoul = on; ui:Refresh() end end)
    self.dsoulCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -478)
    self.sburnSlider = ui:CreateSlider("sbHp", f, "burn below", function(v) if ui.buf then ui.buf.shadowburnHp = v; ui:Refresh() end end)
    self.sburnSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -520)
    self.dsoulSlider = ui:CreateSlider("dsHp", f, "drain below", function(v) if ui.buf then ui.buf.drainSoulHp = v; ui:Refresh() end end)
    self.dsoulSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -520)

    -- Survival
    ui:FS(f, "GameFontNormal", "Survival"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -556)
    self.drainCB = ui:CreateCheck("drainLifeSustain", f, "Drain Life when low", "Drain Life", function(on) if ui.buf then ui.buf.drainLifeSustain = on; ui:Refresh() end end)
    self.drainCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -580)
    self.funnelCB = ui:CreateCheck("healthFunnel", f, "Health Funnel pet", "Health Funnel", function(on) if ui.buf then ui.buf.healthFunnel = on; ui:Refresh() end end)
    self.funnelCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -580)
    self.drainSlider = ui:CreateSlider("dlHp", f, "heal below", function(v) if ui.buf then ui.buf.drainLifeHp = v; ui:Refresh() end end)
    self.drainSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -622)
    self.funnelPetSlider = ui:CreateSlider("hfPet", f, "pet below", function(v) if ui.buf then ui.buf.healthFunnelPetHp = v; ui:Refresh() end end)
    self.funnelPetSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -622)
    self.funnelSelfSlider = ui:CreateSlider("hfSelf", f, "keep your HP above", function(v) if ui.buf then ui.buf.healthFunnelHpMin = v; ui:Refresh() end end)
    self.funnelSelfSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -664)

    ui:Divider(f, -134)   -- above DoT
    ui:Divider(f, -236)   -- above Filler and pet
    ui:Divider(f, -344)   -- above Mana
    ui:Divider(f, -446)   -- above Execute
    ui:Divider(f, -548)   -- above Survival

    ui:Tip(self.immoCB.cb, "Immolate", "Direct fire damage plus a fire damage over time.", "Kept up first in the priority.")
    ui:Tip(self.corrCB.cb, "Corruption", "Shadow damage over time, applied after the curse.")
    ui:Tip(self.siphCB.cb, "Siphon Life", "Shadow damage over time that also heals you.")
    ui:Tip(self.curseDD, "Curse", "One curse per target. Curse of Agony has exact upkeep,", "others are reapplied on a timer for now.")
    ui:Tip(self.fillerDD, "Filler", "Used when every enabled DoT is up.", "Wand conserves mana, Shadow Bolt and Drain Life spend it.")
    ui:Tip(self.petCB.cb, "Pet attack", "Send the active pet onto your target.")
    ui:Tip(self.nightfallCB.cb, "Shadow Bolt on Shadow Trance", "When the Nightfall proc lights up, fire the free instant Shadow Bolt.", "Auto-enabled when the Nightfall talent is detected; this toggle forces it on otherwise. Only used when the filler is not already Shadow Bolt.")
    ui:Tip(self.tapCB.cb, "Life Tap", "Convert health to mana when mana is low and health is high.")
    ui:Tip(self.tapManaSlider, "Tap below mana", "Life Tap only when mana is under this value.")
    ui:Tip(self.tapHpSlider, "Keep HP above", "Life Tap only while health stays over this value.")
    ui:Tip(self.sburnCB.cb, "Shadowburn", "Instant execute under the threshold below. Costs a Soul Shard and has a cooldown.", "Burst finish; if you want the shard instead, use Drain Soul.")
    ui:Tip(self.dsoulCB.cb, "Drain Soul", "Channel in the target's last seconds to bank a Soul Shard and regen mana.", "If both this and Shadowburn are on, Shadowburn fires first when ready.")
    ui:Tip(self.sburnSlider, "Burn below", "Target health percent under which Shadowburn fires.")
    ui:Tip(self.dsoulSlider, "Drain below", "Target health percent under which Drain Soul channels.")
    ui:Tip(self.drainCB.cb, "Drain Life when low", "Self-heal channel when your health dips below the value — the drain-tank safety net.")
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
