-- ============================================================
-- Class_Warrior_UI  -  warrior window body for AutoRota
-- Builds and binds only the warrior specific controls. The shared
-- window shell and profile management live in AutoRota_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = AutoRota.classes.WARRIOR
M.useScrollLayout = true

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
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    self.cb = {}

    -- helpers: place via the layout cursor and register into self.cb for RefreshBody.
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end
    local function one(key, label)
        local it = L:Check(key, label, SPELL_OF[key], set(key))
        self.cb[key] = it
        return it
    end
    local function pair(ka, la, kb, lb)
        local a, b = L:CheckPair(
            { ka, la, SPELL_OF[ka], set(ka) },
            { kb, lb, SPELL_OF[kb], set(kb) })
        self.cb[ka] = a; self.cb[kb] = b
    end

    L:Header("Strikes")
    pair("useMortalStrike", "Mortal Strike", "useBloodthirst", "Bloodthirst")
    pair("useShieldSlam", "Shield Slam", "useWhirlwind", "Whirlwind")
    one("useSlam", "Slam")

    L:Header("Reactive & Execute")
    pair("useOverpower", "Overpower", "useExecute", "Execute")
    pair("useRevenge", "Revenge", "stanceDance", "Stance dancing")
    self.stanceDD = L:Dropdown("homeStance", "Home stance", 150, set("homeStance"))

    L:Header("Threat / AoE")
    pair("aoeMode", "AoE mode", "useSweeping", "Sweeping Strikes")
    pair("useSunder", "Sunder Armor", "useThunderClap", "Thunder Clap")
    one("useCleave", "Cleave (AoE)")
    self.sunderSlider = L:Slider("sunderStacks", "Sunder stacks", { min = 1, max = 5, step = 1, suffix = "" }, set("sunderStacks"))

    L:Header("Rage dump")
    one("useHeroicStrike", "Heroic Strike")
    self.dumpSlider, self.wwSlider = L:SliderPair(
        { "dumpRage", "Dump above rage", { min = 0, max = 100, step = 5, suffix = "" }, set("dumpRage") },
        { "wwExcess", "WW above rage", { min = 0, max = 100, step = 5, suffix = "" }, set("wwExcess") })

    L:Header("Cooldowns")
    pair("popCDs", "Pop cooldowns", "autoCDElite", "Auto on elite")
    pair("useDeathWish", "Death Wish", "useRecklessness", "Recklessness")
    pair("useBerserkerRage", "Berserker Rage", "useBloodrage", "Bloodrage")
    one("useShieldBlock", "Shield Block")

    L:Finish()

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
M.OpenConfig = function(mod)
    if not AutoRotaUI then
        AutoRota:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    AutoRotaUI:Toggle()
end
