-- ============================================================
-- Class_Warrior_UI  -  warrior window body for AutoRota
-- Builds and binds only the warrior specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- ============================================================

local M = AutoRota.classes.WARRIOR

-- Maps each boolean toggle to the spell it depends on, so the label can
-- show "(not learned)" while leveling. nil = no spell (pure behaviour flag).
local SPELL_OF = {
    useMortalStrike = "Mortal Strike", useBloodthirst = "Bloodthirst",
    useShieldSlam = "Shield Slam", useWhirlwind = "Whirlwind", useSlam = "Slam",
    useOverpower = "Overpower", useRevenge = "Revenge", useExecute = "Execute",
    useSunder = "Sunder Armor", useThunderClap = "Thunder Clap",
    useHeroicStrike = "Heroic Strike", useCleave = "Cleave",
    useSweeping = "Sweeping Strikes", useDeathWish = "Death Wish",
    useRecklessness = "Recklessness", useBerserkerRage = "Berserker Rage",
    useBloodrage = "Bloodrage", useShieldBlock = "Shield Block",
    stanceDance = nil, aoeMode = nil, popCDs = nil, autoCDElite = nil,
}

-- ============================================================
-- build body (warrior controls)
-- ============================================================
function M:BuildBody(ui, f)
    self.cb = {}

    -- A bound boolean checkbox: writes ui.buf[key] and refreshes.
    local function mkCheck(key, labelText)
        local spell = SPELL_OF[key]
        local item = ui:CreateCheck(key, f, labelText, spell, function(v)
            if ui.buf then ui.buf[key] = v; ui:Refresh() end
        end)
        self.cb[key] = item
        return item
    end

    -- ---- Strikes ----
    ui:FS(f, "GameFontNormal", "Strikes"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -142)
    mkCheck("useMortalStrike", "Mortal Strike").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -164)
    mkCheck("useBloodthirst",  "Bloodthirst").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -164)
    mkCheck("useShieldSlam",   "Shield Slam").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -186)
    mkCheck("useWhirlwind",    "Whirlwind").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -186)
    mkCheck("useSlam",         "Slam").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -208)

    -- ---- Reactive & Execute ----
    ui:FS(f, "GameFontNormal", "Reactive & Execute"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -236)
    mkCheck("useOverpower", "Overpower").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -258)
    mkCheck("useExecute",   "Execute").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -258)
    mkCheck("useRevenge",   "Revenge").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -280)
    mkCheck("stanceDance",  "Stance dancing").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -302)

    ui:FS(f, "GameFontNormalSmall", "Home stance"):SetPoint("TOPLEFT", f, "TOPLEFT", 24, -328)
    self.stanceDD = ui:CreateDropdown("homeStance", f, 150, function(v)
        if ui.buf then ui.buf.homeStance = v; ui:Refresh() end
    end)
    self.stanceDD:SetPoint("TOPLEFT", f, "TOPLEFT", 120, -326)

    -- ---- Threat / AoE ----
    ui:FS(f, "GameFontNormal", "Threat / AoE"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -362)
    mkCheck("aoeMode",       "AoE mode").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -384)
    mkCheck("useSweeping",   "Sweeping Strikes").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -384)
    mkCheck("useSunder",     "Sunder Armor").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -406)
    mkCheck("useThunderClap","Thunder Clap").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -406)
    mkCheck("useCleave",     "Cleave in AoE").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -430)
    self.sunderSlider = ui:CreateSlider("sunderStacks", f, "Sunder stacks", {min=1,max=5,step=1,suffix=""},
        function(v) if ui.buf then ui.buf.sunderStacks = v; ui:Refresh() end end)
    self.sunderSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -444)

    -- ---- Rage dump ----
    ui:FS(f, "GameFontNormal", "Rage dump"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -470)
    mkCheck("useHeroicStrike", "Heroic Strike / Cleave dump").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -492)
    self.dumpSlider = ui:CreateSlider("dumpRage", f, "dump above rage", {min=0,max=100,step=5,suffix=""},
        function(v) if ui.buf then ui.buf.dumpRage = v; ui:Refresh() end end)
    self.dumpSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -528)
    self.wwSlider = ui:CreateSlider("wwExcess", f, "Whirlwind above rage", {min=0,max=100,step=5,suffix=""},
        function(v) if ui.buf then ui.buf.wwExcess = v; ui:Refresh() end end)
    self.wwSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -528)

    -- ---- Cooldowns ----
    ui:FS(f, "GameFontNormal", "Cooldowns"):SetPoint("TOPLEFT", f, "TOPLEFT", 20, -568)
    mkCheck("popCDs",          "Always pop cooldowns").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -590)
    mkCheck("autoCDElite",     "Auto on elite and boss").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -590)
    mkCheck("useDeathWish",    "Death Wish").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -612)
    mkCheck("useRecklessness", "Recklessness").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -612)
    mkCheck("useBerserkerRage","Berserker Rage").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -634)
    mkCheck("useBloodrage",    "Bloodrage").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -634)
    mkCheck("useShieldBlock",  "Shield Block").cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -656)

    -- ---- section separators ----
    ui:Divider(f, -134)   -- above Strikes
    ui:Divider(f, -228)   -- above Reactive & Execute
    ui:Divider(f, -354)   -- above Threat / AoE
    ui:Divider(f, -462)   -- above Rage dump
    ui:Divider(f, -560)   -- above Cooldowns

    -- ---- tooltips ----
    ui:Tip(self.cb.useMortalStrike.cb, "Mortal Strike", "Arms primary strike, used on cooldown.")
    ui:Tip(self.cb.useBloodthirst.cb,  "Bloodthirst",   "Fury primary strike, used on cooldown.")
    ui:Tip(self.cb.useShieldSlam.cb,   "Shield Slam",   "Protection primary strike. Requires a shield equipped.")
    ui:Tip(self.cb.useWhirlwind.cb,    "Whirlwind",     "Berserker stance. On cooldown in AoE, or as a single-target rage dump above the Whirlwind rage value.")
    ui:Tip(self.cb.useSlam.cb,         "Slam",          "2H filler. Has a cast time and resets your swing, so it can feel awkward with heavy spam.")
    ui:Tip(self.cb.useOverpower.cb,    "Overpower",     "Battle stance only. Fires in the short window after the target dodges you. Enable Stance dancing to auto-swap to Battle.")
    ui:Tip(self.cb.useExecute.cb,      "Execute",       "Top single-target priority below 20% target HP. Suppresses the rage dump so rage feeds Execute.")
    ui:Tip(self.cb.useRevenge.cb,      "Revenge",       "Defensive stance only. Fires after you block, dodge, or parry.")
    ui:Tip(self.cb.stanceDance.cb,     "Stance dancing (experimental)", "Auto-swaps to Battle for Overpower (and to Defensive for Revenge when home is Defensive), then drifts back to your home stance.", "Costs a little rage per swap; tune in game.")
    ui:Tip(self.stanceDD,              "Home stance",   "The stance the rotation returns to when dancing. Berserker for most DPS, Defensive for tanking.")
    ui:Tip(self.cb.aoeMode.cb,         "AoE mode",      "Switches the rage dump to Cleave and uses Whirlwind on cooldown. Flip mid-fight with /ar aoe.")
    ui:Tip(self.cb.useSweeping.cb,     "Sweeping Strikes", "Fired on cooldown while AoE mode is on (off the global cooldown).")
    ui:Tip(self.cb.useSunder.cb,       "Sunder Armor",  "Applied as a filler up to the stack count below, then left to ride.")
    ui:Tip(self.cb.useThunderClap.cb,  "Thunder Clap",  "AoE filler. Battle stance in 1.12, so a Defensive tank will not auto-cast it.")
    ui:Tip(self.cb.useCleave.cb,       "Cleave in AoE", "When AoE mode is on, dump rage with Cleave instead of Heroic Strike.")
    ui:Tip(self.sunderSlider,          "Sunder stacks", "Apply Sunder Armor until the target carries this many stacks.")
    ui:Tip(self.cb.useHeroicStrike.cb, "Rage dump",     "Queue Heroic Strike (or Cleave in AoE) on the next swing when rage is above the value below.")
    ui:Tip(self.dumpSlider,            "Dump above rage", "Only queue the rage dump when rage is at least this high, so you never starve your strikes.")
    ui:Tip(self.wwSlider,              "Whirlwind above rage", "Single-target only: also fire Whirlwind when rage is at least this high, to bleed off excess.")
    ui:Tip(self.cb.popCDs.cb,          "Always pop",    "Use the enabled cooldowns whenever they are ready.")
    ui:Tip(self.cb.autoCDElite.cb,     "Auto on elite", "Use the enabled cooldowns only against elite and boss targets. Leave both off to control them manually.")
    ui:Tip(self.cb.useDeathWish.cb,    "Death Wish",    "Fury cooldown. Part of the burst set governed above.")
    ui:Tip(self.cb.useRecklessness.cb, "Recklessness",  "Berserker stance. Part of the burst set governed above.")
    ui:Tip(self.cb.useBerserkerRage.cb,"Berserker Rage","Berserker stance. Part of the burst set governed above.")
    ui:Tip(self.cb.useBloodrage.cb,    "Bloodrage",     "Fired (off the GCD) to top up rage when it drops low. Works before the pull too.")
    ui:Tip(self.cb.useShieldBlock.cb,  "Shield Block",  "Defensive stance. Used on cooldown to feed Revenge and mitigate.")
end

-- ============================================================
-- refresh body (warrior binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    for key, item in pairs(self.cb) do
        ui:BindCheck(item, buf[key], SPELL_OF[key] or false)
    end

    -- home stance dropdown
    local stanceOpts = {
        { label = "Berserker",    value = "berserker" },
        { label = "Battle",       value = "battle" },
        { label = "Defensive",    value = "defensive" },
        { label = "Don't manage", value = "none" },
    }
    local stanceLabel = { berserker = "Berserker", battle = "Battle", defensive = "Defensive", none = "Don't manage" }
    local cur = buf.homeStance or "berserker"
    ui:SetDropdown(self.stanceDD, stanceOpts, cur, stanceLabel[cur] or cur, ui.COL.white)

    -- sliders
    local ss = buf.sunderStacks or 5
    self.sunderSlider:SetValue(ss)
    if self.sunderSlider.valText then self.sunderSlider.valText:SetText(tostring(ss)) end

    local dr = buf.dumpRage or 60
    self.dumpSlider:SetValue(dr)
    if self.dumpSlider.valText then self.dumpSlider.valText:SetText(tostring(dr)) end

    local ww = buf.wwExcess or 60
    self.wwSlider:SetValue(ww)
    if self.wwSlider.valText then self.wwSlider.valText:SetText(tostring(ww)) end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod) AutoRotaUI:Toggle() end
