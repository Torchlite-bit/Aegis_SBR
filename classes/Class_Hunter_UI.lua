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
    -- Shots & Stings
    ui:FS(f, "GameFontNormal", "Shots & Stings"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    ui:FS(f, "GameFontNormalSmall", "Sting"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -168)
    self.stingDD = ui:CreateDropdown("sting", f, 200, function(v) if ui.buf then ui.buf.sting = v; ui:Refresh() end end)
    self.stingDD:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -166)
    self.markCB = ui:CreateCheck("useHuntersMark", f, "Keep Hunter's Mark up", "Hunter's Mark", function(on) if ui.buf then ui.buf.useHuntersMark = on; ui:Refresh() end end)
    self.markCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -192)

    -- Shots
    ui:FS(f, "GameFontNormal", "Shots"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -226)
    self.arcaneCB = ui:CreateCheck("useArcaneShot", f, "Arcane Shot", "Arcane Shot", function(on) if ui.buf then ui.buf.useArcaneShot = on; ui:Refresh() end end)
    self.arcaneCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -248)
    self.multiCB = ui:CreateCheck("useMultiShot", f, "Multi-Shot", "Multi-Shot", function(on) if ui.buf then ui.buf.useMultiShot = on; ui:Refresh() end end)
    self.multiCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -248)
    self.aimedCB = ui:CreateCheck("useAimedShot", f, "Aimed Shot (cast)", "Aimed Shot", function(on) if ui.buf then ui.buf.useAimedShot = on; ui:Refresh() end end)
    self.aimedCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -272)

    -- AoE
    ui:FS(f, "GameFontNormal", "AoE (manual toggle, /ar aoe)"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -306)
    self.volleyCB = ui:CreateCheck("useVolley", f, "Volley leads AoE", "Volley", function(on) if ui.buf then ui.buf.useVolley = on; ui:Refresh() end end)
    self.volleyCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -328)

    -- Aspect & Pet
    ui:FS(f, "GameFontNormal", "Aspect & Pet"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -362)
    self.aspectCB = ui:CreateCheck("useAspectHawk", f, "Keep Aspect of the Hawk up", "Aspect of the Hawk", function(on) if ui.buf then ui.buf.useAspectHawk = on; ui:Refresh() end end)
    self.aspectCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -384)
    self.petCB = ui:CreateCheck("petAttack", f, "Send pet to attack", nil, function(on) if ui.buf then ui.buf.petAttack = on; ui:Refresh() end end)
    self.petCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -408)
    self.mendCB = ui:CreateCheck("useMendPet", f, "Mend Pet when hurt", "Mend Pet", function(on) if ui.buf then ui.buf.useMendPet = on; ui:Refresh() end end)
    self.mendCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -408)
    self.mendSlider = ui:CreateSlider("mendPetHp", f, "Mend Pet below", function(v) if ui.buf then ui.buf.mendPetHp = v; ui:Refresh() end end)
    self.mendSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -450)

    -- Melee weave
    ui:FS(f, "GameFontNormal", "Melee weave"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -484)
    self.raptorCB = ui:CreateCheck("useRaptorStrike", f, "Raptor Strike in melee range", "Raptor Strike", function(on) if ui.buf then ui.buf.useRaptorStrike = on; ui:Refresh() end end)
    self.raptorCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -506)

    -- Cooldowns
    ui:FS(f, "GameFontNormal", "Cooldowns"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -540)
    self.cdCB = ui:CreateCheck("popCDs", f, "Always pop cooldowns", nil, function(on) if ui.buf then ui.buf.popCDs = on; ui:Refresh() end end)
    self.cdCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -562)
    self.cdEliteCB = ui:CreateCheck("autoCDElite", f, "Auto on elite and boss", nil, function(on) if ui.buf then ui.buf.autoCDElite = on; ui:Refresh() end end)
    self.cdEliteCB.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -562)

    ui:Divider(f, -134)   -- above Shots & Stings
    ui:Divider(f, -218)   -- above Shots
    ui:Divider(f, -298)   -- above AoE
    ui:Divider(f, -354)   -- above Aspect & Pet
    ui:Divider(f, -476)   -- above Melee weave
    ui:Divider(f, -532)   -- above Cooldowns

    ui:Tip(self.stingDD, "Sting", "The one sting kept up on the target. Serpent is the staple DoT; Scorpid lowers melee hit; Viper drains mana.")
    ui:Tip(self.markCB.cb, "Hunter's Mark", "Applied once per target and refreshed when it falls off (exact upkeep with SuperWoW).")
    ui:Tip(self.arcaneCB.cb, "Arcane Shot", "Instant nuke, fired on cooldown between Auto Shots.")
    ui:Tip(self.multiCB.cb, "Multi-Shot", "Fired on cooldown. Also leads AoE alongside Volley.")
    ui:Tip(self.aimedCB.cb, "Aimed Shot", "Marksmanship cast. Queued through SuperWoW so it does not clip the current shot.")
    ui:Tip(self.volleyCB.cb, "Volley", "When AoE mode is on, Volley channels first, then Multi-Shot fills.", "Toggle AoE with /ar aoe; 1.12 cannot count nearby enemies.")
    ui:Tip(self.aspectCB.cb, "Aspect of the Hawk", "Recast whenever the buff is missing.")
    ui:Tip(self.petCB.cb, "Pet attack", "Sends your pet onto the target each press.")
    ui:Tip(self.mendCB.cb, "Mend Pet", "Heals the pet when it drops below the slider value (HoT, refreshed every ~12s).")
    ui:Tip(self.mendSlider, "Mend Pet below", "Pet health percent under which Mend Pet is cast.")
    ui:Tip(self.raptorCB.cb, "Raptor Strike", "When the target is in melee range, start melee swings and use Raptor Strike so a mob in your face still takes hits.")
    ui:Tip(self.cdCB.cb, "Pop cooldowns", "Use Rapid Fire (and Bestial Wrath when known) every press.")
    ui:Tip(self.cdEliteCB.cb, "Auto on elite", "Pop the cooldowns only against elite and boss targets.")
end

-- ============================================================
-- refresh body (hunter binding)
-- ============================================================
function M:RefreshBody(ui, buf)
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
    ui:BindCheck(self.arcaneCB, buf.useArcaneShot)
    ui:BindCheck(self.multiCB, buf.useMultiShot)
    ui:BindCheck(self.aimedCB, buf.useAimedShot)
    ui:BindCheck(self.volleyCB, buf.useVolley)
    ui:BindCheck(self.aspectCB, buf.useAspectHawk)
    ui:BindCheck(self.petCB, buf.petAttack)
    ui:BindCheck(self.mendCB, buf.useMendPet)
    ui:BindCheck(self.raptorCB, buf.useRaptorStrike)
    ui:BindCheck(self.cdCB, buf.popCDs)
    ui:BindCheck(self.cdEliteCB, buf.autoCDElite)

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
