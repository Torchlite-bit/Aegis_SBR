-- ============================================================
-- Class_Warrior_UI  -  warrior window body for Aegis_SBR
-- Builds and binds only the warrior specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.WARRIOR
M.useScrollLayout = true

-- Maps each boolean toggle to the spell it depends on, so the label can
-- show "(not learned)" while leveling. nil = no spell (pure behaviour flag).
local SPELL_OF = {
    useMortalStrike = "Mortal Strike", useBloodthirst = "Bloodthirst",
    useShieldSlam = "Shield Slam", useWhirlwind = "Whirlwind", useSlam = "Slam",
    useOverpower = "Overpower", useRevenge = "Revenge", useExecute = "Execute",
    useSunder = "Sunder Armor", useThunderClap = "Thunder Clap",
    useHeroicStrike = "Heroic Strike", useCleave = "Cleave",
    useCharge = "Charge", useRend = "Rend",
    useSweeping = "Sweeping Strikes", useDeathWish = "Death Wish",
    useRecklessness = "Recklessness", useBerserkerRage = "Berserker Rage",
    useBloodrage = "Bloodrage", useShieldBlock = "Shield Block",
    useBattleShout = "Battle Shout", useDemoShout = "Demoralizing Shout",
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
    -- a concept single-row toggle, registered like the old one()/pair() so the
    -- RefreshBody bind loop over self.cb keeps working unchanged.
    local function row(key, label)
        local it = L:Row{ key = key, label = label, spell = SPELL_OF[key], onToggle = set(key) }
        self.cb[key] = it
        return it
    end

    L:Header("Strikes")
    row("useMortalStrike", "Mortal Strike")
    row("useBloodthirst", "Bloodthirst")
    row("useShieldSlam", "Shield Slam")
    row("useWhirlwind", "Whirlwind")
    row("useSlam", "Slam")
    row("useCharge", "Charge opener")
    row("useRend", "Rend bleed")

    L:Header("Reactive & Execute")
    row("useOverpower", "Overpower")
    row("useExecute", "Execute")
    row("useRevenge", "Revenge")
    row("stanceDance", "Stance dancing")
    self.stanceDD = L:Dropdown("homeStance", "Home stance", 150, set("homeStance"))

    L:Header("Threat / AoE")
    row("aoeMode", "AoE mode")
    row("useSweeping", "Sweeping Strikes")
    row("useSunder", "Sunder Armor")
    row("useThunderClap", "Thunder Clap")
    row("useCleave", "Cleave (AoE)")
    self.sunderRow = L:Row{ label = "Sunder stacks",
        slider = { key = "sunderStacks", min = 1, max = 5, step = 1, suffix = "", onChange = set("sunderStacks") } }

    L:Header("Shouts")
    row("useBattleShout", "Battle Shout")
    row("useDemoShout", "Demoralizing Shout")

    L:Header("Rage dump")
    row("useHeroicStrike", "Heroic Strike")
    self.dumpRow = L:Row{ label = "Dump above rage",
        slider = { key = "dumpRage", min = 0, max = 100, step = 5, suffix = "", onChange = set("dumpRage") } }
    self.wwRow = L:Row{ label = "WW above rage",
        slider = { key = "wwExcess", min = 0, max = 100, step = 5, suffix = "", onChange = set("wwExcess") } }

    L:Header("Cooldowns")
    row("popCDs", "Pop cooldowns")
    row("autoCDElite", "Auto on elite")
    row("useDeathWish", "Death Wish")
    row("useRecklessness", "Recklessness")
    row("useBerserkerRage", "Berserker Rage")
    row("useBloodrage", "Bloodrage")
    row("useShieldBlock", "Shield Block")

    L:Finish()

    -- ---- tooltips ----
    ui:Tip(self.cb.useMortalStrike.cb, "Mortal Strike", "Arms primary strike, used on cooldown.")
    ui:Tip(self.cb.useBloodthirst.cb,  "Bloodthirst",   "Fury primary strike, used on cooldown.")
    ui:Tip(self.cb.useShieldSlam.cb,   "Shield Slam",   "Protection primary strike. Requires a shield equipped.")
    ui:Tip(self.cb.useWhirlwind.cb,    "Whirlwind",     "Berserker stance. On cooldown in AoE, or as a single-target rage dump above the Whirlwind rage value.")
    ui:Tip(self.cb.useSlam.cb,         "Slam",          "2H filler. Has a cast time and resets your swing, so it can feel awkward with heavy spam.")
    ui:Tip(self.cb.useCharge.cb,       "Charge opener", "Leveling opener: Charge the target from range on the pull (Battle Stance, out of combat only). Stance-dances to Battle if needed.", "The client blocks Charge once you are in combat, so it only fires on the initial gap-close.")
    ui:Tip(self.cb.useRend.cb,         "Rend bleed",    "Keeps Rend up on the target (Battle or Defensive stance). A leveling tool - off by default, since it is rarely used at endgame.", "Skipped during Execute so rage goes to Execute instead.")
    ui:Tip(self.cb.useOverpower.cb,    "Overpower",     "Battle stance only. Fires in the short window after the target dodges you. Enable Stance dancing to auto-swap to Battle.")
    ui:Tip(self.cb.useExecute.cb,      "Execute",       "Top single-target priority below 20% target HP. Suppresses the rage dump so rage feeds Execute.")
    ui:Tip(self.cb.useRevenge.cb,      "Revenge",       "Defensive stance only. Fires after you block, dodge, or parry.")
    ui:Tip(self.cb.stanceDance.cb,     "Stance dancing (experimental)", "Auto-swaps to Battle for Overpower (and to Defensive for Revenge when home is Defensive), then drifts back to your home stance.", "Costs a little rage per swap; tune in game.")
    ui:Tip(self.stanceDD,              "Home stance",   "The stance the rotation returns to when dancing. Berserker for most DPS, Defensive for tanking.")
    ui:Tip(self.cb.aoeMode.cb,         "AoE mode",      "Switches the rage dump to Cleave and uses Whirlwind on cooldown. Flip mid-fight with /sbr aoe.")
    ui:Tip(self.cb.useSweeping.cb,     "Sweeping Strikes", "Fired on cooldown while AoE mode is on (off the global cooldown).")
    ui:Tip(self.cb.useSunder.cb,       "Sunder Armor",  "Applied as a filler up to the stack count below, then left to ride.")
    ui:Tip(self.cb.useThunderClap.cb,  "Thunder Clap",  "AoE filler. Battle stance in 1.12, so a Defensive tank will not auto-cast it.")
    ui:Tip(self.cb.useCleave.cb,       "Cleave in AoE", "When AoE mode is on, dump rage with Cleave instead of Heroic Strike.")
    ui:Tip(self.sunderRow.slider,          "Sunder stacks", "Apply Sunder Armor until the target carries this many stacks.")
    ui:Tip(self.cb.useBattleShout.cb,  "Battle Shout",  "Keeps the party attack-power buff up. Refreshed only when it is missing or about to expire, and below your strikes so it never delays one.", "Skipped during Execute so rage feeds Execute. On by default.")
    ui:Tip(self.cb.useDemoShout.cb,    "Demoralizing Shout", "Keeps the enemy attack-power reduction on your target, for mitigation (tanking). Re-applied only when it falls off the target. Off by default.", "Uses a debuff slot - mind the raid debuff cap.")
    ui:Tip(self.cb.useHeroicStrike.cb, "Rage dump",     "Queue Heroic Strike (or Cleave in AoE) on the next swing when rage is above the value below.")
    ui:Tip(self.dumpRow.slider,            "Dump above rage", "Only queue the rage dump when rage is at least this high, so you never starve your strikes.")
    ui:Tip(self.wwRow.slider,              "Whirlwind above rage", "Single-target only: also fire Whirlwind when rage is at least this high, to bleed off excess.")
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
    self.sunderRow.slider:SetValue(ss)
    if self.sunderRow.slider.valText then self.sunderRow.slider.valText:SetText(tostring(ss)) end

    local dr = buf.dumpRage or 60
    self.dumpRow.slider:SetValue(dr)
    if self.dumpRow.slider.valText then self.dumpRow.slider.valText:SetText(tostring(dr)) end

    local ww = buf.wwExcess or 60
    self.wwRow.slider:SetValue(ww)
    if self.wwRow.slider.valText then self.wwRow.slider.valText:SetText(tostring(ww)) end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
