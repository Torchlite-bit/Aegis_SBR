-- ============================================================
-- Class_Warrior  -  warrior module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Roleless, configurable, all specs.
-- ============================================================
-- Model:
--  * Warriors are gated by STANCE and RAGE, not mana. The core's
--    self:Cast() reports success whenever a spell is merely KNOWN, which
--    is fine for paladin/rogue but would stall our priority chain the
--    moment a known ability is uncastable (wrong stance / not enough
--    rage). So this module uses self:CanCast(name, rageCost, stances)
--    before committing to any GCD ability, and gates stance-restricted
--    abilities explicitly. Stance rules follow vanilla 1.12; if Turtle
--    relaxes a restriction we simply stay conservative (never unsafe).
--  * Off-GCD / on-next-swing abilities (Heroic Strike, Cleave, Death
--    Wish, Recklessness, Berserker Rage, Bloodrage, Shield Block) are
--    fired in a "fire and continue" layer, then exactly one GCD ability
--    is chosen by strict priority with early returns, the same single
--    cast per press discipline the paladin and rogue modules use.
--  * Reactive procs (Overpower after the target dodges, Revenge after we
--    block/dodge/parry) are tracked from the combat log into short
--    windows, mirroring the rogue's Riposte tracker.
--  * AoE has no reliable enemy counter on 1.12 (SuperWoW exposes none),
--    so AoE is a manual toggle, flippable mid-fight with /sbr aoe.
--  * Cooldowns follow the rogue's pattern: pop always, only on
--    elite/boss, or never (manual) via two checkboxes.
-- ============================================================

local M = Aegis_SBR:NewClassModule("WARRIOR")
M.uiTitle = "Warrior"
-- Rotate runs under Aegis_SBR:Preview without casting (see Pick/Later).
M.previewReady = true
M.uiHeight = 886

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- Reactive proc windows (seconds). Overpower and Revenge stay usable for
-- about 5s after the triggering event.
local REACT_WINDOW = 5.0

-- Overpower's window, LEARNED rather than assumed.
--
-- The tooltip gives the cooldown (5s) and says the ability is usable "after the
-- target dodges", but not for how long. Vanilla's answer is five seconds - and
-- five seconds measured from the DODGE, where all we can see is the combat-log
-- line about it, which arrives later. Our window therefore sits later than the
-- real one and its tail is spent firing into a window the server has closed.
-- That is what "Overpower misses or fires late" describes.
--
-- A fixed trim was the first answer here and it was a guess about somebody
-- else's latency. This measures instead: when the client refuses an Overpower
-- that was sent at age X, the window was already shut at X, so it is set just
-- below X. Shrink only, never grow - a refusal is evidence, an acceptance is
-- not - and never below the floor, which would make the ability unusable.
local OVERPOWER_WINDOW = 5.0
local OVERPOWER_WINDOW_MIN = 2.5
local OVERPOWER_LEARN_BACKOFF = 0.3
M.opWindow = OVERPOWER_WINDOW

-- Slam's cast time, for the "do not clip the next swing" test below.
--
-- 2.5s, read off the Turtle tooltip - NOT the 1.12 value of 1.5s. That is a
-- large difference for this test: against a 3.4s two-hander a 2.5s cast only
-- fits in the first nine tenths of a second after a swing, where a 1.5s one
-- fits nearly half the time. Assuming stock values here would have let Slam
-- clip most of the swings it was supposed to protect.
--
-- Improved Slam takes 0.25s per rank off it, 2 ranks, so a fully talented Arms
-- warrior casts it in 2.0s. 2.5 is the BASE - the spell tooltip was read with
-- the talent at 0/2 - so subtracting the rank here is correct and does not
-- double-count.
--
-- 0.25, not the 0.3 the in-game talent tooltip shows: that is a rounded
-- display. The exact figures come from the client's own Talent.dbc by way of
-- TalentStage's generated rank data - "by 0.25 sec" at rank 1, "by 0.5 sec" at
-- rank 2.
-- (The talent shortens Slam's global cooldown by the same amount; that matters
-- for the rotation's pacing but not for the swing test below.)
local SLAM_CAST_BASE = 2.5
local SLAM_CAST_PER_RANK = 0.25
local TALENT_IMP_SLAM = "Improved Slam"
local TALENT_IMP_EXECUTE = "Improved Execute"
-- Tactical Mastery 5/5 retains 25 rage across a stance switch - exactly
-- Whirlwind's cost. Below that rank a dance leaves too little rage to spend,
-- so the Whirlwind dance below is gated on rank, not assumed.
local TALENT_TACTICAL_MASTERY = "Tactical Mastery"
local TALENT_RAVAGER = "Ravager"
local TALENT_IMP_HEROIC_STRIKE = "Improved Heroic Strike"
local TALENT_FLURRY = "Flurry"
-- How long the Revenge fallback waits between attempts while the combat log
-- has not answered even once. Matched to Revenge's own cooldown, so the
-- fallback can never cost more than one press per cooldown.
local REVENGE_PROBE_GAP = 5.0
-- Minimum gap between stance switches; stance changes have a ~1s internal
-- cooldown, so we never thrash faster than this.
local STANCE_CD = 1.0
local OVERPOWER_STANCE_RAGE = 25
local OVERPOWER_SWING_LOOKAHEAD = 0.5
-- The Overpower dance must still pay for itself: switching to Battle and
-- firing the Overpower takes a stance swap plus a GCD. If the learned proc
-- window has less than this left, the dance would land in Battle as the proc
-- expires - a wasted press and possibly a wasted rage dump - so it is given
-- up and the press falls through to the ordinary rotation.
local OVERPOWER_DANCE_LEAD = 2.0
-- Light throttle so a rapid press burst does not re-issue the queued
-- on-next-swing ability several times in the same swing.
local DUMP_THROTTLE = 0.3
-- Refresh Battle Shout when it is missing or has under this many seconds left.
-- It lasts ~2 min, so this refreshes it roughly once per two minutes.
local BSHOUT_RENEW = 30

-- Fallback radius for the auto-AoE enemy count, used only if the Whirlwind
-- tooltip cannot be read. Matches the paladin's Consecration fallback.
local AOE_RADIUS = 8

-- Scan radius for an off-target enemy to interrupt. Matches the ~9.9yd
-- melee proxy InMeleeRange uses, so a nearer nameplate caster is exactly as
-- kickable as the target would be at that distance.
local INTERRUPT_SCAN_YARDS = 10

-- Whirlwind is worth a global in AoE against two or more enemies (set by
-- /sbr aoe auto's "two weapon-hits worth" doctrine: two weapon damage hits
-- out-value the single-target strike the global would replace - count is the
-- proxy for that payout, no weapon read needed). Three was the old
-- conservative rule (a "real pack"); two says: once the count reaches two,
-- Whirlwind beats the single-target alternative. An unknown count lets it
-- through (fail open) - a count that cannot be taken must not close the gate.
local WW_MIN_PACK = 2

-- Sweeping Strikes copies the attack that spends its charge. Per charge Mortal
-- Strike copies more than a Whirlwind hit, and at two or three enemies
-- Whirlwind already hits them all, so its extra hit lands on an already-hit mob
-- where Mortal Strike's lands on a second one. Whirlwind only becomes the
-- better spender once it hits four: then its own AoE plus the extra hit beats a
-- single Mortal Strike copy. (1.12: one Whirlwind burns one charge and adds one
-- hit, not one per target.)
local SS_BIG_PACK = 4

-- A Sweeping Strikes pop is only worth its 30 rage while the pack can survive
-- the copied hits; a pack whose every member is about to die spends the
-- charges on corpses. These are the floors: at least SWEEP_MIN_TARGETS
-- enemies (target or others) must read above SWEEP_MIN_HP or the pop is held
-- for a better window - one healthy enemy next to a dying one still wastes
-- the second charge. A health read that cannot be taken stays nil and fails
-- open - an unknowable pack must not close the gate.
local SWEEP_MIN_HP = 50
local SWEEP_MIN_TARGETS = 2

-- How long auto AoE holds before flipping back to single target once the pack
-- drops below the threshold. Nameplates vanish and reappear (a mob steps out
-- of range, interior walls, the fixed cap), so the mode must not thrash on a
-- flicker; the hold is per threshold tick, not cumulative.
local AOE_EXIT_HOLD = 1.0

-- How often the CC scan may re-read the pack's auras. Each press walking the
-- nameplates AND reading every enemy's aura list is the same shape of cost the
-- enemy counter article warns about; a fight's CC state changes on the order
-- of seconds, not tenths.
local CC_SCAN_TTL = 0.5

-- How many swing periods may go by with no white swing before the swing
-- tracker is called unknown. Mirrors the core's SWING_STALE: a running
-- auto-attack re-anchors on every swing, so missing this many in a row means
-- nothing is swinging - there is no next swing to clip, and the modulo below
-- would otherwise keep producing a perfectly plausible countdown forever.
local SWING_STALE_PERIODS = 2.5

-- After a Charge opener the warrior is mid-animation and out of Demo Shout
-- range for a short window. Hold the shout so it does not waste a press on a
-- client refusal; one successful Shout on arrival covers the same debuff window.
local CHARGE_DEMO_HOLD = 2.0

-- After the client refuses an Intercept (target beyond its reach), hold it for
-- a short window. Unlike the kicks there is no cast to key a backoff to, so
-- the refusal is consumed and the gate reopens after the window: a chase
-- re-picks at most once per window instead of on every press.
local INTERCEPT_RESEND = 3.0
-- Intercept's own reach. The near end is not a number: the gate is
-- `not InMeleeRange()`, so the weapon you carry sets it (a 2H pushes it past the
-- old flat 8 yd floor and nothing is ever refused for standing a little far
-- off). A target inside melee is a strike, not a leap. An UNKNOWN distance
-- passes (fail open - the client refuses, and the hold above absorbs it), in
-- line with the rest of the addon.
local INTERCEPT_MAX_YARDS = 25

-- Stance key -> spell name. Used by the home-stance setting and switching.
M.STANCES = {
    battle    = "Battle Stance",
    defensive = "Defensive Stance",
    berserker = "Berserker Stance",
}

-- Approximate base rage costs, used only to decide whether to ATTEMPT a
-- GCD ability (so the priority can fall through to a cheaper one instead
-- of stalling). Talents/ranks shift these a little; values are slightly
-- forgiving on purpose. Tune here if a spec feels like it skips casts.
-- Rend's applied duration, for telling our bleed from another warrior's.
local REND_DUR = 21

-- Re-apply Sunder Armor with this much time left on the stack. A fresh Sunder
-- at max stacks refreshes the duration and keeps the count; dropping it loses
-- every stack and takes five GCDs to rebuild, so the refresh sits early enough
-- for a GCD + a press to land short of the drop.
local SUNDER_REFRESH = 3.0

local RAGE = {
    ["Mortal Strike"] = 30,
    ["Bloodthirst"]   = 30,
    ["Shield Slam"]   = 20,
    ["Whirlwind"]     = 25,
    ["Slam"]          = 15,
    ["Heroic Strike"] = 15,   -- base, reduced by Improved Heroic Strike talent (1/point)
    ["Execute"]       = 15,   -- untalented client floor: refuses below 15 despite consuming all extra rage (Improved Execute lowers it - see ExecuteCost)
    ["Overpower"]     = 5,
    ["Revenge"]       = 5,
    ["Sunder Armor"]  = 10,   -- Turtle 1.18.1
    ["Thunder Clap"]  = 20,
    ["Charge"]        = 0,    -- generates rage; free to attempt
    -- Intercept: 10 rage, tooltip confirmed on Turtle. Generates rage on hit,
    -- like Charge. 25 yd reach, 30s cooldown, Berserker Stance only.
    ["Intercept"]     = 10,
    ["Rend"]          = 10,
    ["Hamstring"]     = 10,
    ["Battle Shout"]        = 10,
    ["Demoralizing Shout"]  = 10,
    -- Master Strike: 20 rage, tooltip confirmed on Turtle. Was estimated at 25.
    ["Master Strike"] = 20,
    -- Concussion Blow costs NOTHING on Turtle and generates 10 rage on use
    -- (tooltip confirmed). Zero rather than absent so the intent is explicit:
    -- there is no cost to check, not "we never looked".
    ["Concussion Blow"] = 0,
    ["Cleave"]          = 20,   -- base, reduced by Ravager talent (1/point)
    ["Pummel"]      = 10,   -- forgiving; verify Turtle tooltip if it feels strict
    ["Shield Bash"] = 5,    -- forgiving; verify Turtle tooltip if it feels strict
    -- Sweeping Strikes: 30 rage, off the GCD. The pop never passes through
    -- CanCast - it is fired from the off-GCD layer - so until this entry
    -- existed there was nothing anywhere to check its cost against.
    ["Sweeping Strikes"] = 30,
}

-- Stances an ability may be used from (vanilla 1.12). nil = any stance.
local STANCE_REQ = {
    ["Mortal Strike"] = { "Battle Stance", "Berserker Stance" },
    ["Whirlwind"]     = { "Berserker Stance" },
    ["Execute"]       = { "Battle Stance", "Berserker Stance" },
    ["Overpower"]     = { "Battle Stance" },
    ["Revenge"]       = { "Defensive Stance" },
    ["Thunder Clap"]  = { "Battle Stance", "Defensive Stance" },
    ["Charge"]        = { "Battle Stance" },
    ["Intercept"]     = { "Berserker Stance" },
    ["Rend"]          = { "Battle Stance", "Defensive Stance" },
    ["Hamstring"]     = { "Battle Stance", "Berserker Stance" },
    ["Recklessness"]  = { "Berserker Stance" },
    ["Berserker Rage"]= { "Berserker Stance" },
    ["Shield Block"]  = { "Defensive Stance" },
    ["Sweeping Strikes"]= { "Battle Stance" },
    ["Pummel"]        = { "Battle Stance", "Berserker Stance" },
    -- Bloodthirst, Shield Slam, Slam, Sunder Armor, Heroic Strike, Cleave,
    -- Death Wish, Bloodrage, Shield Bash (interrupt, any stance): usable in
    -- any stance (Shield Slam and Shield Bash need a shield).
}

M.spellAlias = {
    mortalstrike = "useMortalStrike", ms = "useMortalStrike",
    bloodthirst = "useBloodthirst", bt = "useBloodthirst",
    shieldslam = "useShieldSlam", ss = "useShieldSlam",
    whirlwind = "useWhirlwind", ww = "useWhirlwind",
    slam = "useSlam",
    overpower = "useOverpower", op = "useOverpower",
    revenge = "useRevenge", rev = "useRevenge",
    execute = "useExecute", exec = "useExecute",
    sunder = "useSunder", sa = "useSunder",
    thunderclap = "useThunderClap", tc = "useThunderClap",
    heroicstrike = "useHeroicStrike", hs = "useHeroicStrike",
    cleave = "useCleave",
    sweeping = "useSweeping", sweep = "useSweeping",
    deathwish = "useDeathWish", dw = "useDeathWish",
    recklessness = "useRecklessness", reck = "useRecklessness",
    berserkerrage = "useBerserkerRage", br = "useBerserkerRage",
    bloodrage = "useBloodrage", bld = "useBloodrage",
    shieldblock = "useShieldBlock", sb = "useShieldBlock",
    charge = "useCharge",
    intercept = "useIntercept", intc = "useIntercept",
    rend = "useRend",
    battleshout = "useBattleShout", bshout = "useBattleShout",
    demoshout = "useDemoShout", demo = "useDemoShout",
    masterstrike = "useMasterStrike", mstrike = "useMasterStrike",
    concussionblow = "useConcussionBlow", cblow = "useConcussionBlow",
    pummel = "usePummel",
    shieldbash = "useShieldBash", sbash = "useShieldBash",
    healonly = "interruptHealsOnly", honly = "interruptHealsOnly",
}

-- Templates: starting presets, copied into the char's saved profiles once.
M.templates = {
    starter = {  -- valid for any warrior at any level: Execute, rage dump, Bloodrage
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = false, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = false, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        aoeAuto = false, aoeThreshold = 2, aoeCc = true,
        useHeroicStrike = true, dumpRage = 60, wwExcess = 60,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, bloodrageHealthPct = 25, useShieldBlock = false,
        useCharge = false, useIntercept = false, useRend = false,
        usePummel = false, useShieldBash = false,
    },
    fury = {
        useMortalStrike = false, useBloodthirst = true, useShieldSlam = false,
        useWhirlwind = true, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = true, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        aoeAuto = false, aoeThreshold = 2, aoeCc = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 50,
        popCDs = false, autoCDElite = true,
        useDeathWish = true, useRecklessness = true, useBerserkerRage = true,
        useBloodrage = true, bloodrageRage = 30, bloodrageHealthPct = 25, useShieldBlock = false,
        useCharge = false, useIntercept = false, useRend = false,
        usePummel = true, useShieldBash = true,
    },
    arms = {
        useMortalStrike = true, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = true, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = true, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = true, useCleave = true,
        aoeAuto = false, aoeThreshold = 2, aoeCc = true,
useHeroicStrike = true, dumpRage = 50, wwExcess = 55,
        popCDs = false, autoCDElite = true,
        useDeathWish = false, useRecklessness = true, useBerserkerRage = true,
        useBloodrage = true, bloodrageRage = 30, bloodrageHealthPct = 25, useShieldBlock = false,
        useCharge = false, useIntercept = false, useRend = false,
        usePummel = true, useShieldBash = true,
    },
    prot = {
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = true,
        useWhirlwind = false, useSlam = false,
        useOverpower = false, useRevenge = true, useExecute = false,
        stanceDance = false, homeStance = "defensive",
        useSunder = true, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        aoeAuto = false, aoeThreshold = 2, aoeCc = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 70,
popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        burstMinHp = 0,
        useBloodrage = true, bloodrageRage = 30, bloodrageHealthPct = 25, useShieldBlock = false,
        useCharge = false, useIntercept = false, useRend = false,
        usePummel = false, useShieldBash = true,
    },
}

-- Fills any missing field with a default. No old-format migration yet,
-- so unknown keys are simply left alone.
function M:NormalizeProfile(c)
    local b = {
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = false, useSlam = false,
        useOverpower = false, useRevenge = false, useExecute = true,
        slamCancelForExecute = true,
        stanceDance = false, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 60, wwExcess = 60,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, bloodrageHealthPct = 25, useShieldBlock = false,
        useCharge = false, useIntercept = false, useRend = false,
        -- Pummel / Shield Bash interrupts: off until opted into, like every
        -- other reactive here. Both fire only while the target is mid-cast
        -- (SuperWoW cast events), so they change nothing without SuperWoW.
        usePummel = false, useShieldBash = false,
        -- Interrupt tuning: heal-only kicks only confirmed heal casts (built-in
        -- list + interruptHealList inclusions); min-time shortens what is worth
        -- a kick; wait-at holds the kick until the cast reaches the configured
        -- progress threshold (0-100%). All off/zero by default = interrupt
        -- anything mid-cast.
        interruptHealsOnly = false, interruptMinTime = 0, interruptHealList = {},
        interruptWaitAt = 0,
        -- Battle Shout on by default (near-universal AP buff); Demoralizing Shout
        -- off by default (opt-in mitigation debuff, mainly for tanking).
        useBattleShout = true, useDemoShout = false,
        -- Master Strike (Arms talent) is primarily a PvP pick, so it stays OFF
        -- until the player opts in; it then fires on cooldown below the spec's
        -- primary strike.
        useMasterStrike = false,
        -- Concussion Blow (Protection talent): off until opted into, like every
        -- other talent-gated extra here. KnowsSpell keeps it inert until the
        -- point is actually spent.
        useConcussionBlow = false,
        -- Auto AoE: decide the AoE switch from the drawn enemy count instead of
        -- the manual toggle. Off by default, because it depends on nameplates
        -- being drawn - a real measurement where that works and no measurement
        -- where it does not, and a default that quietly needs a client setting
        -- is a trap (same reasoning as the paladin's consecMinTargets).
        aoeAuto = false,
        -- Pack size that flips auto AoE on. Minimum 2: with one enemy the
        -- single-target priority list is always better, and it avoids the
        -- on/off churn a threshold of 1 would cause around every pull.
        aoeThreshold = 2,
        -- Stand AoE down while a damage-breakable control (Polymorph, Freeze,
        -- Sap) is on any enemy in the pack. On by default: breaking CC is a
        -- group wipe, and the only cost of a false positive is a missed cast.
        aoeCc = true,
        -- Hamstring kept on the target (runners, PvP, kiting). Off by default.
        useHamstring = false,
        -- Thunder Clap not on a target that already carries its slow.
        tcSkipIfUp = false,
    }
    for k, v in pairs(b) do
        if c[k] == nil then c[k] = v end
    end
    if not self.STANCES[c.homeStance] and c.homeStance ~= "none" then c.homeStance = "berserker" end
    return c
end

-- Nothing is hard-required: the rotation degrades gracefully through
-- KnowsSpell, so any profile can be activated and used while leveling.
-- Unlearned abilities are flagged in the UI labels, not here.
function M:ProfileValidity(cfg)
    return true, {}
end

-- ============================================================
-- Rage and stance helpers
-- ============================================================
function M:Rage()
    return UnitMana("player") or 0
end

-- Cleave cost with Ravager talent reduction (Turtle Fury talent, 1 rage per point).
function M:CleaveCost()
    local base = RAGE["Cleave"] or 20
    local talentRank = self:TalentRank(TALENT_RAVAGER) or 0
    local cost = base - talentRank
    if cost < 0 then cost = 0 end
    return cost
end

-- Heroic Strike cost with Improved Heroic Strike reduction (Arms talent,
-- 1 rage per point, three ranks). Base is 15 on this client.
function M:HeroicStrikeCost()
    local base = RAGE["Heroic Strike"] or 15
    local talentRank = self:TalentRank(TALENT_IMP_HEROIC_STRIKE) or 0
    local cost = base - talentRank
    if cost < 0 then cost = 0 end
    return cost
end

function M:TryRageDump(cfg, aoe, now, skipCleave)
    if not cfg.useHeroicStrike or (now - (self.lastDump or 0)) <= DUMP_THROTTLE then return false end
    local rage = self:Rage()
    if aoe and not skipCleave and cfg.useCleave and self:KnowsSpell("Cleave")
        and rage >= (cfg.dumpRage or 60) and rage >= self:CleaveCost() then
        if self:PickExtra("Cleave") then
            if not Aegis_SBR.deciding then self.lastDump = now end
            return true
        end
    -- The single-target dump is single-target ONLY. In a pack Heroic Strike hits
    -- one of eight, so spending the rage here is worse than holding it for the
    -- GCD: wwFirst is the case that reaches this elseif in AoE, and it means
    -- "Whirlwind owns the next press", not "Whirlwind first, then dump". The
    -- captured evidence was 2 presses at a 2-pack, rage >= the dump floor, Cleave
    -- affordable and known - skipCleave the only way the branch above could fail,
    -- so 15 rage went into a one-target hit on every one of them.
    elseif not aoe and self:KnowsSpell("Heroic Strike") and rage >= (cfg.dumpRage or 60)
        and rage >= self:HeroicStrikeCost() then
        if self:PickExtra("Heroic Strike") then
            if not Aegis_SBR.deciding then self.lastDump = now end
            return true
        end
    end
    return false
end

function M:CurrentStanceName()
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, n do
        local _, name, isActive = GetShapeshiftFormInfo(i)
        if isActive then return name end
    end
    return nil
end

function M:InStance(name)
    return self:CurrentStanceName() == name
end

function M:InAnyStance(list)
    if not list then return true end
    local cur = self:CurrentStanceName()
    if not cur then return true end   -- no stance info, do not block
    for i = 1, table.getn(list) do
        if list[i] == cur then return true end
    end
    return false
end

function M:StanceIndex(name)
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, n do
        local _, sName = GetShapeshiftFormInfo(i)
        if sName == name then return i end
    end
    return nil   -- stance not learned
end

-- Switch to a named stance if it is learned, not already active, and the
-- swap cooldown has elapsed. Returns true if a switch was issued.
-- A stance swap is a press like any other, so under a preview it has to be
-- reported rather than performed - and its throttle stamp only advances on a
-- real press.
function M:SwitchStance(name)
    local idx = self:StanceIndex(name)
    if not idx then return false end
    if self:CurrentStanceName() == name then return false end
    local now = GetTime()
    if now - (self.lastStanceSwap or 0) < STANCE_CD then return false end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name
        p.reason = "stance dance"
        return true
    end
    -- A real press is the only place a dance has to be recorded: the branch
    -- above only reports it to the preview window, so on a real press the swap
    -- used to go out silently and the press it consumed left no trace at all -
    -- only inferable afterwards from a stance flip in the state line with no
    -- gcd line between them. Rage is included because the waste from a dance is
    -- never rage spent ON the swap (a swap costs none) - it is rage the new
    -- stance cannot spend, which is what 1c's pre-dump exists to prevent, and
    -- that judgement needs the level at the moment the swap was issued.
    if self:Tracing() then self:Trace("dance " .. name .. " rage=" .. self:Rage()) end
    CastShapeshiftForm(idx)
    self.lastStanceSwap = now
    return true
end

-- True only if the ability is known, off cooldown (own cd, ignoring the
-- raw GCD edge), affordable, and usable in the current stance. This is the
-- gate that keeps a stance/rage locked ability from stalling the chain.
function M:CanCast(name, rageCost, stances)
    if not self:KnowsSpell(name) then return false end
    if not self:IsReady(name) then return false end
    if rageCost and self:Rage() < rageCost then return false end
    if stances and not self:InAnyStance(stances) then return false end
    return true
end

-- Convenience wrapper that reads the rage cost and stance requirement from
-- the tables above, then attempts the cast. Returns true if cast.
-- Abilities the client refuses on the weapon alone. Checked in Try, so every
-- step that goes through it is covered and a new one cannot forget.
--
-- The comment beside the stance table has said "Shield Slam needs a shield"
-- since it was written, without anything testing for it: a fury warrior who
-- switched the option on spent every press on a refusal, silently.
--
-- WeaponAllows only ever refuses on a DEFINITE answer. An item the client has
-- not cached yet, or a locale whose subtype strings we do not know, reads as
-- "cannot tell" and changes nothing.
local WEAPON_REQ = {
    ["Shield Slam"]  = "shield",
    ["Shield Block"] = "shield",
    ["Shield Bash"]  = "shield",
}

-- Slam's cast time with the talent folded in.
-- Did the client refuse the Overpower we just sent? Then the window was
-- already closed at that age, and the next one should stop sooner.
--
-- Only a refusal within the blame window counts, and only once per attempt.
-- The reading is weak by nature - UI_ERROR_MESSAGE says plenty of things - but
-- it is only consulted in the moment after we sent this exact ability, and the
-- consequence of a false positive is a marginally tighter window rather than a
-- wrong cast.
function M:OverpowerLearnTick()
    -- Resolve the previous Overpower attempt.
    --
    -- Pick returns true when the spell is KNOWN, not when the client accepted
    -- the cast. Closing the window on that answer threw it away whenever the
    -- cast was refused - a stance edge, latency - and Overpower was skipped
    -- silently. The window is left open until the client has answered instead:
    -- refused, and the next press retries; accepted, and the cooldown starting
    -- is the confirmation (a refused cast starts none). Neither within half a
    -- second is NOT an answer - a refusal can arrive late or be blamed on a
    -- spell sent after this one - and silence must not close the gate, so the
    -- window is kept until the proc's own expiry ends it.
    if self.overpowerAttemptAt and (GetTime() - self.overpowerAttemptAt) > 0.5 then
        if Aegis_SBR.SpellRefusedAnySince
            and Aegis_SBR:SpellRefusedAnySince("Overpower", self.overpowerAttemptAt) then
            if self:Tracing() then self:Trace("overpower refused, window stays open") end
        elseif not self:IsReady("Overpower") then
            self.overpowerExpiry = 0
            self.overpowerStanceHold = true
        end
        self.overpowerAttemptAt = nil
    end
    if not self.opSentAt then return end
    if GetTime() - self.opSentAt > 2 then
        self.opSentAt, self.opSentAge = nil, nil
        return
    end
    if not Aegis_SBR.SpellRefusedAnySince then return end
    if not Aegis_SBR:SpellRefusedAnySince("Overpower", self.opSentAt) then return end

    local age = self.opSentAge
    self.opSentAt, self.opSentAge = nil, nil
    if not age then return end
    local w = age - OVERPOWER_LEARN_BACKOFF
    if w < OVERPOWER_WINDOW_MIN then w = OVERPOWER_WINDOW_MIN end
    if w < self.opWindow then
        self.opWindow = w
        if self:Tracing() then
            self:Trace(string.format("overpower window -> %.1fs (refused at %.1fs)", w, age))
        end
    end
end

-- Resolve a Revenge attempt the same way as an Overpower one, and for the
-- same reason: Pick answers "known", not "accepted", so an accepted cast is
-- only told apart by the cooldown it starts. A refusal keeps the window open
-- for the next press, and an unattributed outcome is not an answer and must
-- not close the gate.
function M:RevengeResolveTick()
    if not self.revengeAttemptAt then return end
    if GetTime() - self.revengeAttemptAt <= 0.5 then return end
    if Aegis_SBR.SpellRefusedAnySince
        and Aegis_SBR:SpellRefusedAnySince("Revenge", self.revengeAttemptAt) then
        if self:Tracing() then self:Trace("revenge refused, window stays open") end
    elseif not self:IsReady("Revenge") then
        self.revengeExpiry = 0
    end
    self.revengeAttemptAt = nil
end

function M:FlurryHastePct()
    local rank = self:TalentRank(TALENT_FLURRY) or 0
    if rank <= 0 or not self:HasBuff("Flurry") then return 0 end
    return rank * 6
end

function M:SlamCastTime()
    local t = SLAM_CAST_BASE - SLAM_CAST_PER_RANK * self:TalentRank(TALENT_IMP_SLAM)
    local haste = self:FlurryHastePct()
    if haste > 0 then t = t * 100 / (100 + haste) end
    if t < 0.5 then t = 0.5 end
    return t
end

-- Execute's minimum rage with the talent folded in.
--
-- 15 is the client's floor for the untalented spell. Improved Execute (Fury,
-- 2 ranks) lowers it by 2, then 5 - the vanilla values stand until a server
-- rebalance is confirmed. The talent read is the same one SlamCastTime uses
-- for Improved Slam; a wrong rank costs at most one refused cast.
--
-- The full rage bar is still consumed either way - the talent only moves the
-- minimum, which is exactly what the gate checks.
function M:ExecuteCost()
    local rank = self:TalentRank(TALENT_IMP_EXECUTE)
    if rank == 2 then return RAGE["Execute"] - 5 end
    if rank == 1 then return RAGE["Execute"] - 2 end
    return RAGE["Execute"]
end

-- Is a Slam cast still running?
--
-- Slam is the only ability a warrior casts rather than swings, so one stamp
-- covers the whole class. The stamp is set when Slam is sent and cleared by the
-- client the moment the cast ends, one way or another; the time is the fallback
-- for a cast whose end is never announced.
function M:SlamCasting()
    return (self.slamCastUntil and GetTime() < self.slamCastUntil) and true or false
end

-- Cancel a running Slam so Execute can go out.
--
-- Reported: with a two-hander, Execute comes up while Slam is mid-cast and the
-- press is lost waiting for a cast that is now the wrong ability.
--
-- The IsReady test is what makes this worth doing at all. Slam starts the global
-- cooldown when the CAST starts, and the cast is longer than the cooldown - 2.5s
-- against 1.5s, or 2.0s with both ranks of Improved Slam. Cancel early and the
-- Slam is thrown away while Execute still cannot fire, which is a strictly worse
-- result than letting the Slam land. Cancelling only once Execute would actually
-- go out confines this to the tail of the cast, where the whole gain is.
--
-- Through Later, so a preview never cancels a real cast.
function M:CancelSlamForExecute()
    if not self:SlamCasting() then return false end
    if not Aegis_SBR:IsReady("Execute") then return false end
    self:Later(function()
        if self:Tracing() then self:Trace("cancelling Slam, Execute is up") end
        SpellStopCasting()
        self.slamCastUntil = nil
    end)
    return true
end

-- Cancel a running Slam so an interrupt can go out.
--
-- The interrupt is off-GCD, so after Slam's cast completes the next press can
-- still kick: canceling then would throw the Slam away for nothing. The castEnd
-- test confines the cancel to the tail of the enemy cast - the window closes
-- before Slam lands either way, so the Kick is the whole gain. Unknown cast end
-- (nil) is cancelled, matching the fail-open rule.
--
-- Used by both interrupt paths (target and nearby caster), after the interrupt
-- pick is already chosen, so a cancel is never spent on a pick that cannot cast.
-- Through Later, so a preview never cancels a real cast.
function M:CancelSlamForInterrupt(castEnd)
    if not self:SlamCasting() then return false end
    if castEnd and castEnd > (self.slamCastUntil or 0) then return false end
    self:Later(function()
        if self:Tracing() then self:Trace("cancelling Slam, interrupt is up") end
        SpellStopCasting()
        self.slamCastUntil = nil
    end)
    return true
end

-- Cancel a running Slam so an AoE ability can go out.
--
-- Slam is single-target with a cast time, so in AoE it has no value to wait
-- for: an auto-AoE flip (or a manual one) can land mid-cast and the press
-- after it would be lost waiting out a cast that is now the wrong ability.
-- No timing gate - unlike the interrupt cancel, there is no case where the
-- Slam is worth keeping in AoE. The caller has already verified the replacing
-- ability can cast. Through Later, so a preview never cancels a real cast.
function M:CancelSlamForAoE()
    if not self:SlamCasting() then return false end
    self:Later(function()
        if self:Tracing() then self:Trace("cancelling Slam, AoE ability up") end
        SpellStopCasting()
        self.slamCastUntil = nil
    end)
    return true
end

-- Cancel a running Slam so an Intercept can go out.
--
-- Intercept is picked only while out of melee, so a Slam mid-cast at that
-- moment cannot land anyway: the target is out of the range the cast needs. No
-- timing gate - unlike the interrupt cancel, there is no case where the Slam is
-- worth keeping while the target has left melee, and the leap must go out NOW
-- or the target keeps running. The caller has already verified the Intercept
-- can cast. Through Later, so a preview never cancels a real cast.
function M:CancelSlamForIntercept()
    if not self:SlamCasting() then return false end
    self:Later(function()
        if self:Tracing() then self:Trace("cancelling Slam, Intercept up") end
        SpellStopCasting()
        self.slamCastUntil = nil
    end)
    return true
end

-- The strike Slam should be waiting for, or nil.
--
-- Slam sits below the primary strikes already, so the ORDER was never the
-- problem: Try refuses an unaffordable cast, and Slam is the cheapest thing in
-- the list, so a press with Mortal Strike ready but three rage short fell
-- straight through to Slam. Reported as Slam always taking preference.
--
-- Only a strike that is genuinely READY and merely unaffordable counts. One on
-- cooldown is not something to wait for - that is exactly the gap Slam is meant
-- to fill.
local SLAM_YIELD_TO = { "Shield Slam", "Bloodthirst", "Mortal Strike", "Whirlwind" }

function M:StrikeWaitingOnRage(cfg)
    local enabled = {
        ["Shield Slam"]   = cfg.useShieldSlam,
        ["Bloodthirst"]   = cfg.useBloodthirst,
        ["Mortal Strike"] = cfg.useMortalStrike,
        ["Whirlwind"]     = cfg.useWhirlwind,
    }
    for i = 1, table.getn(SLAM_YIELD_TO) do
        local n = SLAM_YIELD_TO[i]
        if enabled[n] and self:KnowsSpell(n) and self:IsReady(n)
            and (not STANCE_REQ[n] or self:InAnyStance(STANCE_REQ[n]))
            and (not WEAPON_REQ[n] or Aegis_SBR:WeaponAllows(WEAPON_REQ[n]))
            and self:Rage() < (RAGE[n] or 0) then
            return n
        end
    end
    return nil
end

-- Would a Slam started now push the next white swing back?
--
-- Slam does not reset the swing timer on this client, it delays it, so being
-- wrong here costs a fraction of a swing rather than a whole one - which is why
-- an estimate is good enough. An UNKNOWN swing timer answers yes, in line with
-- the rest of the addon: a detection that cannot answer must not close a gate.
-- Read on SELF, not on Aegis_SBR.
--
-- The swing tracker keeps its state on the class MODULE - OnSwingMessage is
-- called as Aegis_SBR.active:OnSwingMessage(...) - so asking the core table
-- reads a lastSwing nothing ever writes. SwingTimeLeft then answered nil on
-- every press, and an unknown swing timer lets Slam through by design, so this
-- gate had never once closed. The paladin, which asks self:, was right all
-- along; this was the difference between the two.
--
-- There used to be a post-Charge hold: wait for the first white swing to land
-- before letting Slam through. It is gone. The swing latch proved unreliable
-- on this client - the event that should have released the hold often never
-- arrived - and the hold stood Slam down exactly in the opener the player
-- wanted it in. The risk of a Slam clipping the very first swing is accepted
-- by design now; an unknown timer never stands the cast down.
function M:SlamFitsBeforeSwing()
    -- After a disarm restart, hold Slam for one weapon cycle so the first
    -- swing lands before Slam delays it. Time-bounded: if the swing latch
    -- never fires, the hold expires and Slam is allowed through (same as
    -- the accepted risk everywhere else).
    if self.lastDisarmRestart then
        local elapsed = GetTime() - self.lastDisarmRestart
        if elapsed < (self.swingSpeed or 3.0) + 0.5 then return false end
        self.lastDisarmRestart = nil
    end
    -- The PERIOD is read live here, not taken from the tracker's latched
    -- swingSpeed. That value is only refreshed when a white swing lands (core
    -- OnSwingMessage / UNIT_CASTEVENT MAINHAND), so it lags any attack-speed
    -- change by up to one whole swing period.
    --
    -- Flurry is the case that bites, because it changes the period mid-pull:
    -- 3.40s -> 2.62s at 5/5 on this client (both measured off the press log),
    -- and the read taken on the swing landing in the same frame Flurry is
    -- applied still returns the old number. For one period after that,
    -- SwingTimeLeft() OVER-reads the time to the next swing by up to 0.78s, so
    -- a `left >= SlamCastTime` test passes with that much real margin already
    -- gone and the cast lands on the swing it was meant to leave alone. The
    -- false-positive band is 0.78s wide in a 2.62s cycle - about 30% of hasted
    -- swing positions - which is why it read as intermittent and Flurry-only.
    -- A captured instance: Flurry procs, the swing anchors and latches 3.40,
    -- the next press sees left=3.32 against a true 2.54.
    --
    -- The cast model needed no change and was verified against the server: it
    -- grants 1923ms at Flurry 5/5, which is exactly 2500 * 100/130, so
    -- SlamCastTime's Flurry fold-in is right.
    --
    -- The ANCHOR stays the event - lastSwing is written by the swing itself and
    -- is the accurate half. An unknown anchor or period answers yes, in line
    -- with the rest of the addon: a detection that cannot answer must not close
    -- a gate.
    local mh = UnitAttackSpeed("player")
    if not self.lastSwing or not mh or mh <= 0 then return true end
    local elapsed = GetTime() - self.lastSwing
    if elapsed > mh * SWING_STALE_PERIODS then return true end
    local left = mh - math.mod(elapsed, mh)
    return left >= self:SlamCastTime()
end

function M:Try(name, reason)
    if WEAPON_REQ[name] and not Aegis_SBR:WeaponAllows(WEAPON_REQ[name]) then return false end
    -- Execute's floor moves with Improved Execute, so the static table is not
    -- the cost to check: inExecute (above) already asks ExecuteCost, and Try
    -- asking the untalented 15 made the two disagree. At 10-14 rage with 2/5
    -- talented the phase was entered (dump suppressed) and the cast then
    -- refused, so the press fell through to a strike with rage held away from
    -- both Execute and the dump.
    local cost = (name == "Execute") and self:ExecuteCost() or RAGE[name]
    if self:CanCast(name, cost, STANCE_REQ[name]) then
        return self:Pick(name, reason)
    end
    return false
end

-- ============================================================
-- Heal-cast detection for the heal-only interrupt toggle
--
-- 1.12 has no spell-school API, so "is this a heal" is a name match against
-- every vanilla cast-time / channeled heal (instants like Renew and Rejuvenation
-- never carry a cast duration, so there is nothing to interrupt anyway - they
-- are deliberately absent). Turtle custom heal names go in the per-profile
-- inclusion list (cfg.interruptHealList), matched the same way.
-- ============================================================
local INTERRUPT_HEALS = {
    ["heal"] = true, ["greater heal"] = true, ["flash heal"] = true,
    ["prayer of healing"] = true,
    ["holy light"] = true, ["flash of light"] = true,
    ["healing touch"] = true, ["regrowth"] = true, ["tranquility"] = true,
    ["healing wave"] = true, ["lesser healing wave"] = true, ["chain heal"] = true,
}

-- True when this cast name is a known heal (built-in list or the profile's
-- inclusion list). An unknown or unresolvable name answers FALSE deliberately:
-- heal-only is a preference filter - only kick what is confirmed to be a heal.
function M:IsHealCast(name, cfg)
    if not name then return false end
    local n = string.lower(name)
    if INTERRUPT_HEALS[n] then return true end
    local list = cfg.interruptHealList
    if list then
        for i = 1, table.getn(list) do
            if string.lower(list[i]) == n then return true end
        end
    end
    return false
end

-- Inclusion-list add/remove (case-insensitive, never duplicated). Mirrors the
-- healers' PrioAdd/PrioRemove so the UI can use the same button+slot shape.
function M:IntHealAdd(cfg, name)
    if not name or name == "" then return false end
    if type(cfg.interruptHealList) ~= "table" then cfg.interruptHealList = {} end
    local n = string.lower(name)
    for i = 1, table.getn(cfg.interruptHealList) do
        if string.lower(cfg.interruptHealList[i]) == n then return false end
    end
    table.insert(cfg.interruptHealList, name)
    return true
end

function M:IntHealRemove(cfg, idx)
    if type(cfg.interruptHealList) ~= "table" then return false end
    if not cfg.interruptHealList[idx] then return false end
    table.remove(cfg.interruptHealList, idx)
    return true
end

-- ============================================================
-- Interrupt pick
--
-- TargetIsCasting() (core) is true whenever a non-instant cast is in progress.
-- Pick whichever interrupt is castable in the current stance — no dance, the
-- window is too short for the stance CD. Shield Bash is usable in Battle /
-- Defensive but needs a shield; Pummel works in Battle or Berserker on Turtle
-- (vanilla restricted it to Berserker - the in-repo docs/rotations.md flags
-- Turtle's changes) and costs nothing to check. Returns the spell name if
-- castable, nil otherwise.
--
-- castStart (core TargetCastStart) feeds the refusal backoff: an interrupt that
-- was refused since this cast began (LOS, not facing) is not re-picked for the
-- same window. nil castStart = "cannot tell" -> SpellRefusedSince answers false
-- -> the gate stays open, matching the fail-open rule.
--
-- No stance dance by design: the ~1s stance internal CD is enough to slip past
-- a fast cast. A tank in Defensive has Shield Bash; an Arms or Fury warrior
-- keeps Pummel in either home or Berserker, so the kick usually fires without
-- one.
-- ============================================================
function M:InterruptPick(cfg, castStart)
    if cfg.usePummel and self:KnowsSpell("Pummel") and self:IsReady("Pummel")
        and not Aegis_SBR:SpellRefusedSince("Pummel", castStart)
        and self:Rage() >= RAGE["Pummel"]
        and self:InAnyStance(STANCE_REQ["Pummel"]) then
        return "Pummel"
    end
    if cfg.useShieldBash and self:KnowsSpell("Shield Bash") and self:IsReady("Shield Bash")
        and not Aegis_SBR:SpellRefusedSince("Shield Bash", castStart)
        and self:Rage() >= RAGE["Shield Bash"]
        and (not WEAPON_REQ["Shield Bash"] or Aegis_SBR:WeaponAllows(WEAPON_REQ["Shield Bash"])) then
        return "Shield Bash"
    end
    return nil
end

-- Second-half interrupt delay (interruptWaitAt): hold the kick until the
-- enemy cast reaches the configured progress threshold (0-100%, 0 = off).
-- A cast the enemy drops on its own then spends no interrupt, and kicking
-- late delays the heal longer - the cast time already spent is the lockout's
-- head start, and the cooldown after is the same either way.
--
-- An unknown start or duration answers TRUE (fail open): the delay must never
-- remove a kick - the same rule as an unknown duration passing the min-time
-- check. The ledger's start is the UNIT_CASTEVENT arrival time, so a START
-- that arrives late reads as slightly more progress than the cast has really
-- made; the threshold lands a fraction early, never late.
function M:CastPastThreshold(castStart, castDur, threshold)
    if not castStart or not castDur or castDur <= 0 or not threshold or threshold <= 0 then return true end
    return (GetTime() - castStart) >= (castDur * (threshold / 100))
end

-- The nearby ENEMY (not the current target) that is mid-cast and interruptible,
-- or nil. Walks the same nameplate scan the enemy counter uses, so it sees a
-- caster you have not targeted; nil scan = "cannot tell" = no kick, the same
-- withhold stance TargetIsCasting takes without SuperWoW. The returned cast
-- start feeds the same SpellRefusedSince backoff the target path uses, so a
-- refusal belongs to the cast being kicked.
--
-- A nameplate GUID is the unit token; on SuperWoW clients a GUID answers the
-- unit APIs and CastSpellByName's unit argument alike.
function M:NearCaster(cfg)
    local list = Aegis_SBR:EnemiesNear(INTERRUPT_SCAN_YARDS)
    if not list then return nil end
    for i = 1, table.getn(list) do
        local u = list[i]
        if not UnitIsUnit(u, "target") then
            local _, guid = UnitExists(u)
            if guid and Aegis_SBR:EnemyIsCasting(guid) then
                -- Same filters as the target path: min-time, second-half
                -- wait, then heal-only.
                local castDur = Aegis_SBR:EnemyCastDuration(guid)
                local castStart = Aegis_SBR:EnemyCastStart(guid)
                if (not castDur) or castDur >= (cfg.interruptMinTime or 0) then
if (not cfg.interruptWaitAt) or cfg.interruptWaitAt <= 0 or self:CastPastThreshold(castStart, castDur, cfg.interruptWaitAt) then
                        local castName = Aegis_SBR:EnemyCastName(guid)
                        if (not cfg.interruptHealsOnly) or self:IsHealCast(castName, cfg) then
                            return { guid = guid, start = castStart }
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Sunder Armor stack tracking on the target
-- ============================================================
function M:SunderStacksOnTarget()
    -- Exact name match first (SuperWoW id path), "Sunder" icon fragment as the
    -- fallback. The snapshot carries the application count on either path.
    return self:TargetDebuffStacks("Sunder Armor", "Sunder")
end

function M:NeedSunder(cfg)
    local want = cfg.sunderStacks or 5
    -- Apply until we reach the configured stacks, then hold the count: a fresh
    -- Sunder at max stacks refreshes the duration without losing them. Precise
    -- refresh timing needs the debuff's remaining time, which ClassicAPI alone
    -- can read; while it is unknown this falls back to "rides until it drops"
    -- (the previous behaviour - correct on both paths, just more expensive).
    local stacks = self:SunderStacksOnTarget()
    if stacks < want then return true end
    if Aegis_SBR.TargetDebuffRemaining and stacks > 0 then
        local remain = Aegis_SBR:TargetDebuffRemaining("Sunder Armor")
        if remain and remain <= SUNDER_REFRESH then return true end
    end
    return false
end

-- ============================================================
-- Bleed immunity
-- ============================================================
-- Mechanical and Elemental targets cannot be bled, so Rend never lands on them.
-- Without this test the Rend gate below reads "the debuff is not on the target"
-- forever and re-attempts it on EVERY press, burning a GCD and the rage each
-- time. Cached per target id the same way the paladin caches creature type
-- (Class_Paladin.lua): a mob's type never changes, so this costs one API call
-- per target rather than one per press, and keying on the id (GUID based) means
-- a target swap re-reads at once instead of answering from a stale cache.
--
-- An UNKNOWN type must ALLOW the cast: UnitCreatureType returns nil for some
-- units, and failing open only risks the behaviour we already have today, while
-- failing closed would silently disable Rend against ordinary mobs. Note the
-- comparison is against English strings - UnitCreatureType is localised, so this
-- degrades to "never immune" on a non-enUS client, which is the safe direction.
-- Can this target carry Demoralizing Shout at all?
--
-- Reported: targeting a totem made the rotation re-cast the shout on every
-- press. The upkeep is gated on "the debuff is not on the target", and a totem
-- has no attack power to reduce, so the debuff never lands and that test is
-- true forever. Same shape as the Rend-on-a-bleed-immune-target loop below.
--
-- Two answers, in order:
--
--   * The creature type, which settles the reported case immediately. It is an
--     English comparison like the bleed test below it, so it is a fast path
--     rather than the whole answer.
--   * What actually happened. Two casts on this target that left the debuff
--     off and it is written off, whatever the client calls it. That covers the
--     immune targets nobody has enumerated, and every non-English client.
--
-- Reset on a target change, so nothing is carried to the next mob.
local SHOUT_STRIKES = 2
local SHOUT_SETTLE = 1.5

function M:TargetTakesShout()
    local id = Aegis_SBR:TargetId()
    if id ~= self.shoutId then
        self.shoutId = id
        self.shoutTries = 0
        self.shoutCastAt = nil
        self.shoutOK = (UnitCreatureType("target") ~= "Totem")
    end
    if not self.shoutOK then return false end

    -- A cast has had time to land and the debuff is still not there.
    if self.shoutCastAt and (GetTime() - self.shoutCastAt) > SHOUT_SETTLE then
        self.shoutCastAt = nil
        if not Aegis_SBR:TargetDebuffUp("Demoralizing Shout", "Ability_Warrior_WarCry") then
            self.shoutTries = (self.shoutTries or 0) + 1
            if self.shoutTries >= SHOUT_STRIKES then
                self.shoutOK = false
                if self:Tracing() then
                    self:Trace("demo shout: target never takes it, stopping")
                end
                return false
            end
        end
    end
    return true
end

function M:TargetIsBleedImmune()
    local id = Aegis_SBR:TargetId()
    if id ~= self.bleedTypeId then
        local t = UnitCreatureType("target")
        self.bleedTypeId = id
        self.bleedImmune = (t == "Mechanical" or t == "Elemental")
    end
    return self.bleedImmune
end

-- Spellcasters take full Shout damage but their damage is spells, not
-- attack power - so Demoralizing Shout contributes nothing against them and
-- wastes a GCD + 10 rage. Only melee/stance-reliant targets get the shout.
-- `UnitClass` cannot answer here: most caster mobs have no class ("Unknown"),
-- so a class list would only catch PvP-style classed NPCs and miss everything
-- else. The reliable signal is casting itself: the moment the unit is seen
-- casting or channeling (UnitCastingInfo / UnitChannelInfo, a snapshot that
-- works on any mob), that fact is latched for this target id, and the shout
-- stands down. A target never seen casting answers "cannot tell" (the very
-- first cast may just not have happened yet), which must not close the gate -
-- unknown keeps the shout, exactly like the creature-type checks above.
function M:TargetIsSpellcaster()
    local id = Aegis_SBR:TargetId()
    if id ~= self.shoutCasterId then
        self.shoutCasterId = id
        self.shoutCasterSeen = false
    end
    if (UnitCastingInfo and UnitCastingInfo("target"))
        or (UnitChannelInfo and UnitChannelInfo("target")) then
        self.shoutCasterSeen = true
    end
    return self.shoutCasterSeen
end

-- ============================================================
-- CC-aware AoE decision
--
-- Two layers, both built on the drawn-enemy count the core enumerates.
--
-- AUTO mode decides the aoe flag itself: count >= threshold enters, count below
-- the threshold exits after a short hold so a flickering nameplate does not
-- reroute the rotation every press. A count that cannot be taken (no
-- nameplates drawn) must keep the manual answer - nil is not zero, and a
-- "cannot tell" that read as an empty pack would silently stand the rotation
-- down in single target forever.
--
-- The CC layer stands the final flag down WHILE a control effect that breaks on
-- damage is on any enemy the scan can see. Polymorph is the familiar one;
-- OctoWow's extra forms (Rodent, Draenei Homunculus, ...) keep the name family,
-- which is why the match is a PREFIX - an exact-name list would go stale the
-- day the server adds one more model. Freeze (Freezing Trap - damage breaks the
-- freeze; Frost Nova's ROOT does not and is deliberately absent) and Sap ride
-- along. Fear is absent too: damage does not cancel fear on this client, so a
-- feared mob is not a reason to stop.
--
-- The scan reads the target through the vanilla API (UnitDebuff) and the rest
-- of the pack through ClassicAPI (UnitAuraNames, capability-gated). A unit that
-- vanishes mid-scan, or a pack a source cannot read, answers "cannot tell" -
-- which, per the rule that detection without an answer never closes a gate,
-- does NOT stand anything down. The no-ClassicAPI player gets exactly today's
-- behaviour, plus the target check the vanilla API can always do.
-- ============================================================
local CC_BREAK_CAP = 16          -- debuff slots per unit to read (1.12 target cap)
local CC_BREAK_PREFIX = { "polymorph", "freeze", "sap" }

-- name -> the blocking CC name when the debuff breaks on damage, else nil.
function M:UnitHasBreakableCc(name)
    if not name or name == "" then return nil end
    local low = string.lower(name)
    for i = 1, table.getn(CC_BREAK_PREFIX) do
        if string.find(low, CC_BREAK_PREFIX[i], 1, true) then return low end
    end
    return nil
end

-- The living enemy set within the AoE radius, for the CC scan.
function M:AoEPackUnits()
    local radius = Aegis_SBR:SpellRadius("Whirlwind") or AOE_RADIUS
    local list = Aegis_SBR:EnemiesNearCached(radius)
    if not list then list = Aegis_SBR:EnemiesNear(radius) end
    return list
end

-- Whirlwind is worth a global in AoE against two or more enemies: it lands
-- weapon damage on every one inside the radius, so two weapon-hits beat the
-- single-target strike the global would replace, and the gate is a pack
-- proxy for that payout (count can be taken, so this side cannot lie).
function M:AoEWWPackAt(n)
    local radius = Aegis_SBR:SpellRadius("Whirlwind") or AOE_RADIUS
    local c = Aegis_SBR:CountEnemiesNear(radius)
    if c == nil then return true end   -- cannot tell: fails open
    return c >= n
end

function M:AoEWWPack()
    return self:AoEWWPackAt(WW_MIN_PACK)
end

-- Thunder Clap only where it hits what was asked for. It is a pulse around the
-- warrior: the enemies inside its radius are counted against the auto-AoE
-- "from N" line; with no count, the target has to be in reach - which also
-- keeps it off a Charge still in flight - and, switched on, it is not cast on a
-- target that already carries the slow. All three were reported: the pack size
-- ignored, Thunder Clap thrown during the Charge, and no range check at all.
local TC_RADIUS = 8
function M:ThunderClapWorth(cfg)
    if cfg.tcSkipIfUp and Aegis_SBR:TargetDebuffUp("Thunder Clap", "Spell_Nature_ThunderClap") then
        return false
    end
    local radius = Aegis_SBR:SpellRadius("Thunder Clap") or TC_RADIUS
    local n = Aegis_SBR:CountEnemiesNear(radius)
    if n ~= nil then return n >= (cfg.aoeThreshold or 2) end
    return Aegis_SBR:InMeleeRange()
end

-- true when a damage-breakable control is on any readable enemy, false when
-- every readable enemy is clear, nil when the pack could not be scanned at all
-- (no ClassicAPI). nil never stands the flag down - see the block comment above.
--
-- Cached for CC_SCAN_TTL: each check walks the nameplates and reads every
-- enemy's harmful list, and a scan once per half second per target is enough.
function M:PackHasBreakableCc()
    local now = GetTime()
    local c = self.packCcCheck
    if c and (now - c.t) < CC_SCAN_TTL then return c.hit end
    local hit = self:ScanPackForCc()
    self.packCcCheck = { hit = hit, t = now }
    return hit
end

function M:ScanPackForCc()
    -- Target first: the one unit the vanilla API can read on any client.
    if UnitExists("target") then
        for i = 1, CC_BREAK_CAP do
            local name = UnitDebuff("target", i)
            if not name then break end
            local hit = self:UnitHasBreakableCc(name)
            if hit then return hit end
        end
    end

    -- The rest of the pack needs ClassicAPI. Without it the scan has no answer
    -- for the units it cannot see - return nil, which must read as "do not act".
    if not Aegis_SBR:Capability("auras") then return nil end
    local list = self:AoEPackUnits()
    if not list then return nil end
    for i = 1, table.getn(list) do
        local u = list[i]
        if not UnitExists(u) then return nil end -- vanishing mob, whole read void
        local names = Aegis_SBR:UnitAuraNames(u)
        if not names then return nil end         -- this enemy cannot be read
        for j = 1, table.getn(names) do
            local hit = self:UnitHasBreakableCc(names[j])
            if hit then return hit end
        end
    end
    return false
end

-- true when at least `need` enemies within the AoE radius read above `minPct`
-- health, false when fewer can be found, nil when the pack could not be
-- scanned at all. nil never stands a gate down - see the block comment above:
-- a health read that cannot be taken must not close the pop.
--
-- Walks the SAME cached walk the AoE count was built on (the CC scan's
-- trick), so this costs a few UnitHealth reads, not another nameplate sweep.
function M:PackHasHealthyEnemy(minPct, need)
    -- The cached walk from the AoE count decides; without it there is no
    -- answer - return nil, which must read as "do not act" (fail open).
    local radius = Aegis_SBR:SpellRadius("Whirlwind") or AOE_RADIUS
    local list = Aegis_SBR:EnemiesNearCached(radius)
    if not list then return nil end
    local healthy = 0
    for i = 1, table.getn(list) do
        local u = list[i]
        if UnitExists(u) then
            local mx = UnitHealthMax(u)
            if mx and mx > 0 and UnitHealth(u) / mx * 100 > minPct then
                healthy = healthy + 1
                if healthy >= need then return true end
            end
        end
    end
    return false
end

-- ============================================================
-- Rotation
-- ============================================================
function M:Rotate(cfg)
    local rage   = self:Rage()
    local now    = GetTime()
    local hp     = self:TargetHPPct()
    local cls    = UnitClassification("target")
    local isElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")

    -- The AoE switch. `aoeMode` stays the manual line for the auto-off player,
    -- and the toggle STILL wins when pulled. With auto on, the manual line is
    -- the `aoeOverride` three-state: on/off (both forced, the /sbr aoe cycle)
    -- or nil (idle, let the count decide). The state writes are deferred
    -- through Later so a preview never mutates the real coefficients.
    -- A press mode (/sbr run single|aoe) is the player's answer for THIS
    -- press and outranks both the toggle and the auto count.
    local pressed  = Aegis_SBR:PressModeHeld()
    local aoe      = Aegis_SBR:AoeMode(cfg)
    local aoeCount = nil   -- enemy count behind an auto decision (trace)
    local ccState  = "off" -- PackHasBreakableCc result (trace)
    if not pressed and not cfg.aoeMode and cfg.aoeAuto then
        if cfg.aoeOverride == true then
            -- /sbr aoe cycled here: forced on, the count never sees this press.
            aoe = true
        elseif cfg.aoeOverride == false then
            -- ... and here: forced off, stands even against a full pack.
            aoe = false
        else
            -- No override held: the count decides, and nil is "cannot tell",
            -- not zero: the switch changes only on a real count, otherwise the
            -- idle state stands.
            local radius = Aegis_SBR:SpellRadius("Whirlwind") or AOE_RADIUS
            local n = Aegis_SBR:CountEnemiesNear(radius)
            if n ~= nil then
                aoeCount = n
                local want = cfg.aoeThreshold or 2
                local since = self.aoeBelowSince
                if n >= want then
                    aoe = true
                    if since then self:Later(function() self.aoeBelowSince = nil end) end
                elseif n <= 1 then
                    -- one enemy, or none within radius, is single target by
                    -- definition and flips back immediately.
                    aoe = false
                    if since then self:Later(function() self.aoeBelowSince = nil end) end
                else
                    -- below the threshold but not alone (only reachable with the
                    -- threshold above 2): hold briefly so a flickering nameplate
                    -- does not re-route the rotation on every press.
                    if not since then
                        local t = now
                        self:Later(function() self.aoeBelowSince = now end)
                        since = t
                    end
                    aoe = (now - since) < AOE_EXIT_HOLD
                end
            end
        end
    end

    -- Breakable CC stands the WHOLE switch down, manual included: a group pull
    -- sitting by a polymorphed sheep is exactly the case the manual toggle
    -- cannot see from here.
    if aoe and cfg.aoeCc then
        local hit = self:PackHasBreakableCc()
        if hit == nil then       ccState = "unknown"
        elseif hit == false then ccState = "none"
        else                     ccState = hit; aoe = false end
    end

    local inCombat = UnitAffectingCombat("player")

    local inExecute = cfg.useExecute and hp <= 20 and self:KnowsSpell("Execute")
        and rage >= self:ExecuteCost() and not self:InStance("Defensive Stance")

    -- Is an Intercept pending? Same shape as chargePending (an attackable target
    -- out of melee) but Berserker Stance, and WITHOUT a stance dance: the 1@b
    -- block fires only from the stance you are already in, so this test carries
    -- no stance clause and no dance can be spent here.
    --
    -- Combat state is deliberately not part of it. In combat the client blocks
    -- Charge, so a target that left melee has no other answer; out of it a
    -- berserker with rage spends that rage on the leap rather than on a swap to
    -- Battle. The far end is the ability's own reach, and an unknown distance
    -- passes (fail open - see INTERCEPT_MAX_YARDS).
    --
    -- The refusal hold is part of the gate so the trace can report it blocked.
    -- Unlike the kicks there is no cast to key a SpellRefusedSince backoff to,
    -- so keying it to the attempt time would lock the spell forever: the stamp
    -- would never advance because the gate is closed. The refusal is consumed in
    -- the block instead and the gate holds for INTERCEPT_RESEND.
    local interceptRange = Aegis_SBR:DistanceTo("target")
    local interceptPending = cfg.useIntercept and self:KnowsSpell("Intercept")
        and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target") and not self:InMeleeRange()
        and (not interceptRange or interceptRange <= INTERCEPT_MAX_YARDS)
        and rage >= RAGE["Intercept"]
        and now >= (self.interceptBlockedUntil or 0)
    -- Interrupt state for the trace, resolved once here: the in-progress cast
    -- name plus which filter (if any) suppressed the kick. intname=none means
    -- no cast in progress; int=off/range/min/wait/heal/backoff/kick says why
    -- the interrupt branch did or did not pick.
    local intCastName, intState
    if self:Tracing() then
        intCastName = Aegis_SBR:TargetCastName()
        intState = "off"
        if cfg.usePummel or cfg.useShieldBash then
            if not Aegis_SBR:TargetIsCasting() then
                -- No cast on the target: the off-target scan decides. NearCaster
                -- applies the same filters, so "off" here means nothing kickable
                -- nearby either; "near" is a kick that consumes the press.
                local nearT = self:NearCaster(cfg)
                if nearT then
                    intCastName = Aegis_SBR:EnemyCastName(nearT.guid)
                    intState = self:InterruptPick(cfg, nearT.start) and "near" or "nearbackoff"
                else
                    intState = "off"
                end
            elseif not self:InMeleeRange() then
                intState = "range"
            elseif (Aegis_SBR:TargetCastDuration() or 0) < (cfg.interruptMinTime or 0) then
                intState = "min"
            elseif cfg.interruptWaitAt and cfg.interruptWaitAt > 0 and Aegis_SBR:TargetCastDuration()
                and not self:CastPastThreshold(Aegis_SBR:TargetCastStart(), Aegis_SBR:TargetCastDuration(), cfg.interruptWaitAt) then
                intState = "wait"
            elseif cfg.interruptHealsOnly and not self:IsHealCast(intCastName, cfg) then
                intState = "heal"
            else
                intState = self:InterruptPick(cfg, Aegis_SBR:TargetCastStart()) and "kick" or "backoff"
            end
        end
    end

    if self:Tracing() then
        self:Trace("rage=" .. rage
            .. " stance=" .. (self:CurrentStanceName() or "-")
            .. " hp=" .. string.format("%.0f", hp)
            .. " aoe=" .. (aoe and "Y" or "N")
            .. " aoeauto=" .. (
                cfg.aoeAuto and ((cfg.aoeOverride ~= nil and ("manual/" .. (cfg.aoeOverride and "on" or "off")))
                    or (aoeCount and tostring(aoeCount)) or "unknown") or "off")
            .. " cc=" .. ccState
            .. " op=" .. ((now < (self.overpowerExpiry or 0)) and "Y" or "N")
            .. " ophold=" .. (self.overpowerStanceHold and "Y" or "N")
            .. " fl=" .. self:FlurryHastePct()
            .. " sw=" .. (self:SwingTimeLeft() and string.format("%.2f", self:SwingTimeLeft()) or "-")
            .. " swage=" .. (self.lastSwing and string.format("%.2f", now - self.lastSwing) or "-")
            .. " rev=" .. ((now < (self.revengeExpiry or 0)) and "Y" or "N")
            .. " revseen=" .. (self.revengeSeen and "Y" or "N")
            .. " intname=" .. (intCastName or "none")
            .. " int=" .. intState
            .. " intc=" .. (interceptPending and "Y" or "N")
            -- Demoralizing Shout, because its upkeep loop on a target that
            -- cannot take the debuff was reported from play and left no trace
            -- at all: "up" is whether the debuff is on the target, "takes" is
            -- whether this target can hold it. takes=N with the shout enabled
            -- is the guard doing its job.
            .. " demo=" .. (cfg.useDemoShout and (
                (Aegis_SBR:TargetDebuffUp("Demoralizing Shout", "Ability_Warrior_WarCry")
                    and "up" or "no")
                .. "/" .. (self:TargetTakesShout() and "takes" or "immune")) or "off")
            .. " ctype=" .. (UnitCreatureType and (UnitCreatureType("target") or "?") or "?")
            .. " elite=" .. (isElite and "Y" or "N"))
    end

    -- Is a Charge opener pending? Resolved HERE, before the off-GCD layer,
    -- because Bloodrage has to know about it. Bloodrage flags us in combat and
    -- the Charge gate below is `not inCombat`, so firing Bloodrage on a pull
    -- press does not merely go first - it disqualifies Charge for the rest of
    -- the pull, which reads in game as "Charge never fires even in range".
    -- (They also both issue a CastSpellByName in the same frame, which is
    -- unreliable in 1.12 - a later call can override an earlier one.)
    -- Holding Bloodrage for the one press costs nothing: Charge generates rage
    -- by itself, and Bloodrage is still there the moment we land.
    -- Stance is deliberately NOT part of this test - while we are dancing to
    -- Battle the opener is still pending, so Bloodrage must keep waiting.
    local chargePending = cfg.useCharge and self:KnowsSpell("Charge") and not inCombat
        and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target") and not self:InMeleeRange()

    -- ----------------------------------------------------------------
    -- 0. Off-GCD / on-next-swing layer (fire and continue, no return)
    -- ----------------------------------------------------------------

    -- 0@i. Interrupt (Pummel / Shield Bash), FIRST thing on the press.
    --      A kick is worth more than a burst pop, and the two cannot share the
    --      frame: both go out as CastSpellByName, and on 1.12 the later call in
    --      a frame can override the earlier one (the same rule the Sweeping
    --      Strikes block below is built around). With this below the 0-layer,
    --      Berserker Rage popped on the press that should have kicked and the
    --      interrupt went with it - reported as "Berserker Rage shoots before
    --      interrupt". Off-GCD either way, so the pop loses nothing but one
    --      press: the next one sees the pop already buffed.
    --
    --      Top priority on its own terms: an interrupted heal or buff is worth
    --      more than any strike. Fires only when the target is mid-cast
    --      (SuperWoW cast events) and the chosen interrupt is ready and
    --      castable in the CURRENT stance - no stance dance for interrupts, the
    --      ~1s internal CD is too slow for a fast cast. Consumes the press like
    --      any other pick; off-GCD means the next press gets the strike back
    --      immediately. Without SuperWoW this is inert (TargetIsCasting answers
    --      false = safe: withholds).
    --
    --      Gated on InMeleeRange: both interrupts are melee abilities, and
    --      without the gate a casting enemy at range got the interrupt picked,
    --      refused by the client, and re-picked on every press for the whole
    --      cast - the same wasted-press loop as the Demo Shout charge bug. The
    --      gate also lets a casting pull target fall through to Charge below.
    --
    --      interruptMinTime (default 0) withholds the kick on casts shorter
    --      than the setting - the user's explicit choice, so this may close a
    --      gate where a capability toggle may not. An unknown duration (nil)
    --      is allowed through (fail open).
    --
    --      interruptWaitAt (default 0) holds the kick until the cast reaches
    --      the configured progress % (0-100) - see CastPastThreshold. Same
    --      fail-open stance: an unknown start or duration passes, so the
    --      delay never withholds a kick it cannot measure.
    if (cfg.usePummel or cfg.useShieldBash) and Aegis_SBR:TargetIsCasting()
        and self:InMeleeRange() then
        local castStart = Aegis_SBR:TargetCastStart()
        local castDur = Aegis_SBR:TargetCastDuration()
        local castName = Aegis_SBR:TargetCastName()
        if (not castDur) or castDur >= (cfg.interruptMinTime or 0) then
            if (not cfg.interruptWaitAt) or cfg.interruptWaitAt <= 0 or self:CastPastThreshold(castStart, castDur, cfg.interruptWaitAt) then
                if (not cfg.interruptHealsOnly) or self:IsHealCast(castName, cfg) then
                    local ptr = self:InterruptPick(cfg, castStart)
                    if ptr then
                        -- Slam mid-cast would lock the client out of the kick:
                        -- cancel it (only when the enemy cast ends first, see
                        -- CancelSlamForInterrupt) so this press lands the interrupt.
                        self:CancelSlamForInterrupt(castStart and castStart + (castDur or 0))
                        if self:Pick(ptr, "target casting") then return end
                    end
                end
            end
        end
    end

    -- 0@i'. Same interrupt, off-target: the nearest casting enemy in melee
    --       range that is NOT the current target. Reached only when the target
    --       path above did not pick (no cast on the target, target out of melee,
    --       or the filters withheld). Casts at the enemy's GUID without
    --       dropping your target - SuperWoW's unit argument, so a tank holding
    --       aggro does not switch targets to kick the caster behind the pack.
    --
    --       Same filters and the same SpellRefusedSince backoff, keyed to the
    --       cast being kicked. The nameplate walk already capped the scan at
    --       INTERRUPT_SCAN_YARDS, so the melee-range gate is structural here.
    --       Without SuperWoW the walk sees no nameplate GUIDs, answers nil, and
    --       this path is as inert as the target path.
    if (cfg.usePummel or cfg.useShieldBash) then
        local near = self:NearCaster(cfg)
        if near then
            local ptr = self:InterruptPick(cfg, near.start)
            if ptr then
                -- Same Slam cancel as the target path; the enemy cast ends
                -- before Slam lands (or the cast end is unknown = fail open).
                local cend = near.start
                if cend then
                    local cdur = Aegis_SBR:EnemyCastDuration(near.guid)
                    if cdur then cend = cend + cdur end
                end
                self:CancelSlamForInterrupt(cend)
                if self:PickAt(ptr, near.guid, "nearby caster") then return end
            end
        end
    end

    -- 0a. Bloodrage on the two floors, out of combat and in (v1.2.37). It was
    --     opening prep only until this release: out of combat it front-loaded
    --     for the next engagement, in combat it had a 2s window after
    --     PLAYER_REGEN_DISABLED and nothing after that. Both thresholds are now
    --     sliders (bloodrageRage, bloodrageHealthPct) and they are the ONLY
    --     timing gate - there is no window and no special case, so the spell
    --     fires whenever rage is under the floor and health is over it.
    --     The Charge hold is untouched and still comes from `not chargePending`
    --     above: on the pull press Charge goes out first, and Bloodrage follows.
    --     That is the one ordering rule here that is not a floor.
    --     The cost is why the health floor is the guard that matters: Bloodrage
    --     costs 5% health on this server (vanilla charged 16% of BASE health;
    --     the client rebalanced it), so a cast at the default 25% floor lands at
    --     worst at 20%. Pre-pull that is nearly free; mid-fight it is not, and
    --     raising bloodrageHealthPct is the only thing between a top-up and a
    --     death, so the default is deliberately conservative.
    if cfg.useBloodrage and not chargePending and self:KnowsSpell("Bloodrage")
        and self:IsReady("Bloodrage") and rage < (cfg.bloodrageRage or 30)
        and hp > (cfg.bloodrageHealthPct or 25)
        -- A real target is required, not just the rage line: out-of-combat pulls
        -- are the point of the toggle, but standing idly - or running between
        -- packs with nothing selected - is not a pull, and burning 5% health for
        -- rage that decays before any fight is a plain loss.
        and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target") then
        self:PickExtra("Bloodrage")
    end

    -- 0b. Burst cooldowns, gated by the pop mode and (for the offensive
    --     ones) by being in combat so they are not wasted pre-pull.
    --     burstMinHp (0 = off) withholds the pop on a target below the
    --     threshold - don't waste a long cooldown on a dying mob.
    local popBurst = cfg.popCDs or (cfg.autoCDElite and isElite)
    if popBurst and inCombat and (not cfg.burstMinHp or cfg.burstMinHp <= 0 or hp > cfg.burstMinHp) then
        if cfg.useDeathWish and self:KnowsSpell("Death Wish") and self:IsReady("Death Wish") then
            self:PickExtra("Death Wish")
        end
        if cfg.useRecklessness and self:InStance("Berserker Stance")
            and self:KnowsSpell("Recklessness") and self:IsReady("Recklessness") then
            self:PickExtra("Recklessness")
        end
        if cfg.useBerserkerRage and self:InStance("Berserker Stance")
            and self:KnowsSpell("Berserker Rage") and self:IsReady("Berserker Rage") then
            self:PickExtra("Berserker Rage")
        end
    end

    -- 0b2. Fear response. Berserker Rage is immune to fear on Turtle 1.18.1
    -- (tooltip-confirmed, docs/turtle-mechanics.md), so reacting to a fear the
    -- player is ALREADY in is the whole point. This sits OUTSIDE the popBurst
    -- gate above deliberately: the immunity is defensive, and gating it on
    -- popCDs / autoCDElite / burstMinHp would hide it from every profile
    -- running those off - several presets do. So it answers only to
    -- useBerserkerRage (the spell toggle) and the live state.
    if cfg.useBerserkerRage and self:InStance("Berserker Stance")
        and self:KnowsSpell("Berserker Rage") and self:IsReady("Berserker Rage")
        and not self:HasBuff("Berserker Rage") and self:FearActive() then
        self:PickExtra("Berserker Rage")
    end

    -- 0b3. Battle dance for the Sweeping Strikes pop. Sweeping Strikes is
    --      Battle-only (STANCE_REQ), so a warrior whose home stance is
    --      Berserker could never use it: the 0c gate below asks
    --      InAnyStance({"Battle Stance"}) and answers no, and nothing in the
    --      rotation went looking for another way in. An Arms warrior sat in
    --      Berserker for the whole pack on Whirlwind and Mortal Strike with
    --      the toggle on and the buff never appeared. This is that way in.
    --
    --      At any pack size, deliberately. SS_BIG_PACK (see the comment on it)
    --      says Whirlwind out-values the copied hits at four or more, so on a
    --      big pack this dance gives up the AoE strike to buy Mortal Strike
    --      copies. Approved as it stands - the pop is the point, and one dance
    --      per cooldown is the price. The size argument is kept here so the
    --      trade is on record rather than rediscovered later.
    --
    --      Tactical Mastery 5/5 is the floor for the same reason as the
    --      Whirlwind dance at 1c2: below it the swap retains too little and the
    --      dance spends a press that can cast nothing.
    --
    --      From Berserker only. That keeps this from fighting the Overpower and
    --      Revenge dances, which are already in Battle by the time they run,
    --      and from dragging a Defensive-stance tank out of its own stance.
    --
    --      Not while Slam is casting, like every other dance here: the cast
    --      locks the client out of the swap.
    if aoe and cfg.stanceDance and cfg.useSweeping
        and self:KnowsSpell("Sweeping Strikes") and self:IsReady("Sweeping Strikes")
        and not self:HasBuff("Sweeping Strikes")
        and self:InStance("Berserker Stance")
        and not self:SlamCasting() and not chargePending
        -- Same hold as 0c: charges spent on a pack that is about to drop are
        -- charges wasted, and an unreadable pack fails open.
        and self:PackHasHealthyEnemy(SWEEP_MIN_HP, SWEEP_MIN_TARGETS) ~= false
        and self:TalentRank(TALENT_TACTICAL_MASTERY) >= 5 then
        -- The dump clause the Overpower dance has at 1b, for the same reason.
        -- Tactical Mastery retains 25 rage flat, so every point above that is
        -- stranded by the swap, and Whirlwind is Berserker-only - the one
        -- spell that can still take it. Below the dump floor the swap costs
        -- nothing that the next press was not going to spend anyway.
        if rage > RAGE["Whirlwind"] and cfg.useWhirlwind
            and self:Try("Whirlwind", "dump before Battle stance") then
            return
        end
        -- The pop lands on a later press, not this one: the swap keeps 25 rage
        -- and Sweeping Strikes costs 30, so the client would refuse it. The
        -- rage gate on 0c turns that refusal into a wait, and ssHold below
        -- keeps the stance until it can pay.
        if self:SwitchStance("Battle Stance") then return end
    end

    -- 0c. Sweeping Strikes for cleave windows (off the GCD).
    --
    --     Affordable is part of the gate. PickExtra only asks whether the
    --     spell is known - it cannot see rage - so without the cost check the
    --     pop went out under 30 rage, the client refused it, and the press that
    --     carried it was spent for nothing. Same shape as the Demo Shout charge
    --     loop: an off-GCD cast that is refused takes the press with it.
    if aoe and cfg.useSweeping and self:KnowsSpell("Sweeping Strikes")
        and self:InAnyStance(STANCE_REQ["Sweeping Strikes"]) and self:IsReady("Sweeping Strikes")
        and rage >= RAGE["Sweeping Strikes"] then
        -- Off the pull press: Charge owns that frame, and a later Charge call
        -- would override the pop (the same same-frame rule the strike below
        -- leans on). And when the pop does go out, end the press HERE: a GCD
        -- pick a few lines down is a LATER CastSpellByName and could override
        -- the pop - which is Mortal Strike "firing before Sweeping Strikes
        -- activates". The next press sees the buff up and fires the strike into
        -- it. (Preview mode keeps walking so it can show what would follow.)
        if not chargePending and not self:HasBuff("Sweeping Strikes")
            -- Hold the pop while too few enemies are healthy: charges spent
            -- on a mob about to drop are charges wasted (SWEEP_MIN_HP x
            -- SWEEP_MIN_TARGETS). A pack whose health cannot be read returns
            -- nil and still pops.
            and self:PackHasHealthyEnemy(SWEEP_MIN_HP, SWEEP_MIN_TARGETS) ~= false
            and self:PickExtra("Sweeping Strikes") and not Aegis_SBR.deciding then
            return
        end
    end

    -- 0d. Shield Block to feed Revenge / mitigate (Defensive only, off GCD).
    if cfg.useShieldBlock and self:InStance("Defensive Stance")
        and self:KnowsSpell("Shield Block") and self:IsReady("Shield Block")
        -- Off the GCD, so it never reaches Try: checked here instead.
        and Aegis_SBR:WeaponAllows("shield") then
        self:PickExtra("Shield Block")
    end

    local ssWantsMs = cfg.useSweeping and cfg.useMortalStrike
        and self:HasBuff("Sweeping Strikes")
        and not self:AoEWWPackAt(SS_BIG_PACK)
        and self:CanCast("Mortal Strike", RAGE["Mortal Strike"], nil)
    -- Whether the stance now belongs to Sweeping Strikes: the pop waiting to be
    -- paid for, or the charges waiting to be spent. Read without a pack-size
    -- term on purpose - the dance at 0b3 fires at any size, so a hold that
    -- dropped out at four would undo it on the very next press.
    local ssHold = aoe and cfg.useSweeping and self:KnowsSpell("Sweeping Strikes")
        and (self:IsReady("Sweeping Strikes") or self:HasBuff("Sweeping Strikes"))
    local wwFirst = aoe and cfg.useWhirlwind and self:AoEWWPack() and not ssWantsMs
        and self:CanCast("Whirlwind", RAGE["Whirlwind"], STANCE_REQ["Whirlwind"])

    -- 0e. Rage dump on the next swing. Suppressed during the execute phase
    --     so rage is funneled into Execute instead. Cleave in AoE, Heroic
    --     Strike in single target - never Heroic Strike in a pack, and never
    --     a dump at all when wwFirst says Whirlwind already owns the press.
    local rageDumped = false
    if not inExecute then rageDumped = self:TryRageDump(cfg, aoe, now, wwFirst) end

    -- 1@b. Intercept (toggle). The gap closer, Berserker Stance, and no stance
    --     dance anywhere in it: it fires only from the stance you are already
    --     in, so it never costs a press or a swap to get there. Combat state
    --     is not part of the test - in combat the client blocks Charge and this
    --     is the only answer for a target that left melee, and out of it a
    --     berserker with rage spends the rage on the leap instead of on a
    --     dance to Battle and a free Charge.
    --
    --     Sits BEFORE the Charge block for exactly that reason: already in
    --     Berserker with 10 rage, this takes the pull press and the Charge
    --     dance below never starts. From any other stance the gate simply does
    --     not answer and Charge below stays the opener.
    --
    --     Refusal hold: past the ability's reach the client refuses, and no cast
    --     starts to key a SpellRefusedSince backoff to, so a refused leap holds
    --     for INTERCEPT_RESEND seconds instead of re-picking on every press of
    --     the chase.
    if interceptPending then
        -- Consume a refusal since the last attempt and hold for the window;
        -- SpellRefusedSince keys to nil after the consume, so the hold is
        -- the duration, not the refusal stamp (which would never expire).
        if Aegis_SBR:SpellRefusedSince("Intercept", self.lastInterceptAt) then
            self.interceptBlockedUntil = GetTime() + INTERCEPT_RESEND
            self.lastInterceptAt = nil
        elseif self:InStance("Berserker Stance") and self:IsReady("Intercept") then
            self:CancelSlamForIntercept()
            if self:Pick("Intercept", "gap closer, Berserker") then
                self.lastInterceptAt = GetTime()
                return
            end
        end
    end

    -- 1@. Charge opener (toggle). Battle Stance only, and only as a pull: you
    --     must be OUT of melee range (so it is a gap-closer, never mid-fight)
    --     with an attackable target. Stance-dances to Battle if enabled and
    --     needed. Charge itself is blocked by the client once you are in
    --     combat, so this naturally stops applying after the pull.
    if chargePending then
        if self:InStance("Battle Stance") then
            if self:IsReady("Charge") then
                if self:Pick("Charge", "opener, out of melee") then
                    self.lastChargeAt = GetTime()
                    return
                end
            end
        elseif cfg.stanceDance and not self:SlamCasting()
            and self:IsReady("Charge")
            and self:TalentRank(TALENT_TACTICAL_MASTERY) >= 2 then
            -- TM 2/5 keeps 10 rage through the swap.
            if self:SwitchStance("Battle Stance") then return end
        end
    end

    self:OverpowerLearnTick()
    self:RevengeResolveTick()

    -- Sunder Armor (toggle). Leads the ordinary GCD rotation in single target -
    -- approved, and the reason this block sits above everything below it.
    --
    -- It is a SINGLE-TARGET debuff, so it stands down in a pack the same way Slam
    -- and Rend do. Without the clause it took the lead global in 6-8 packs
    -- (captured: 3 casts at count=6, 1 at 7, 3 at 8) and debuffed one
    -- mob out of eight while Whirlwind, which hits all of them, waited - and
    -- docs/rotations.md names Thunder Clap, not Sunder, as the AoE answer for
    -- every warrior spec. The debuff is not lost by standing down: it re-applies
    -- on the first press back to single target, and NeedSunder only asks for a
    -- refresh it can still get.
    if cfg.useSunder and not aoe and self:CanCast("Sunder Armor", RAGE["Sunder Armor"], nil)
        and self:NeedSunder(cfg) then
        if self:Pick("Sunder Armor", "first GCD, single target") then return end
    end

    -- 1a. Revenge (Defensive). Mainly a tank reactive; only pursued while
    --     in Defensive, or stance-danced to it when home stance is Defensive.
    --
    --     Until the combat log has produced a trigger even once, "no window
    --     open" is silence rather than an answer: the parse may be reading a
    --     client whose wording it does not match. Silence must not close a
    --     gate, so Revenge is attempted on its cooldown instead. The first
    --     trigger read latches revengeSeen and this fallback never runs again.
    --
    --     Bounded: only while already in Defensive Stance, so a guess can never
    --     start a stance dance. The probe repeats at REVENGE_PROBE_GAP until a
    --     trigger is read, so a refused cast - which starts no cooldown - cannot
    --     be retried on every press and stall the rest of the chain.
    local revOpen = now < (self.revengeExpiry or 0)
    local revProbe = not self.revengeSeen and self:InStance("Defensive Stance")
        and (now - (self.revengeProbeAt or 0)) >= REVENGE_PROBE_GAP
    if cfg.useRevenge and self:KnowsSpell("Revenge") and (revOpen or revProbe)
        and self:IsReady("Revenge") and rage >= RAGE["Revenge"] then
        if self:InStance("Defensive Stance") then
            local why = revProbe and "no trigger read yet, trying on cooldown"
                or "block/dodge/parry window"
            if self:Pick("Revenge", why) then
                self:Later(function()
                    -- Bookmarked, not settled: RevengeResolveTick closes the
                    -- window only on a confirmed cast, like Overpower.
                    self.revengeAttemptAt = GetTime()
                    if revProbe then self.revengeProbeAt = GetTime() end
                end)
                return
            end
        elseif cfg.stanceDance and cfg.homeStance == "defensive" then
            if self:SwitchStance("Defensive Stance") then return end
        end
    end

    -- 1b. Overpower (Battle), reactive. Stance-dance in when enabled.
    --
    --      ABOVE Execute (1b2), which was the bug: Execute returns on every
    --      press it can pay for, so while it sat above the proc an
    --      execute-phase press never reached the dance below and the warrior
    --      stayed in Berserker until the proc window closed - the reported
    --      "Overpower proc sometimes missed, seems to stay in zerker during
    --      execute". The proc is the shorter window of the two and expires
    --      unused; Execute is still cast on the press after, once the proc is
    --      spent or the dance has happened.
    --
    --      Not Bloodthirst: 1d is already below this block, so a ready
    --      Bloodthirst never kept the proc waiting.
    if cfg.useOverpower and self:KnowsSpell("Overpower") and now < (self.overpowerExpiry or 0)
        and self:IsReady("Overpower") and rage >= RAGE["Overpower"]
        and not rageDumped and (now - (self.lastDump or 0)) > DUMP_THROTTLE then
        -- A press that lands inside Slam's cast is a refused attempt: the cast
        -- locks the client, and the refusal teaches the learned window to
        -- shrink to the 2.5s floor that Slam's own 2.5s cast then consumes
        -- whole - which reads in game as "Overpower never procs" whenever the
        -- dodge lands while Slam is mid-flight. Consume the press instead: no
        -- attempt, no refusal, and the window stays open for the press after
        -- the cast lands. Slam is the warrior's only cast, so this is the only
        -- lock to wait out.
        if self:SlamCasting() then return end
        if self:InStance("Battle Stance") then
            if self:Pick("Overpower", "target dodged") then
                self:Later(function()
                    -- Kept, not cleared, so a refusal arriving next frame can
                    -- still be attributed to this attempt and its age.
                    self.opSentAt = GetTime()
                    self.opSentAge = self.overpowerAt and (GetTime() - self.overpowerAt) or nil
                    -- NOT overpowerExpiry = 0: see OverpowerLearnTick. A send
                    -- is not an accepted cast, so the window closes only once
                    -- the client has answered.
                    self.overpowerAttemptAt = GetTime()
                end)
                return
            end
        elseif cfg.stanceDance then
            -- The dance gives up when the proc window can no longer carry it:
            -- a stance swap plus a GCD is roughly OVERPOWER_DANCE_LEAD, so a
            -- window any closer to closing than that would fire into a proc
            -- the server has already dropped - a wasted swap and a wasted
            -- rage dump before it. Let the press fall through instead.
            if (self.overpowerExpiry or 0) - now <= OVERPOWER_DANCE_LEAD then
                if self:Tracing() then self:Trace("overpower dance lost: window closing") end
            elseif rage > RAGE["Whirlwind"] then
                if cfg.useWhirlwind and self:Try("Whirlwind", "dump before Battle stance") then return end
                if self:TryRageDump(cfg, aoe, now) then return end
            elseif self:SwitchStance("Battle Stance") then return end
        end
    end

    -- 1b2. Execute below 20% (highest single-target priority per design, below
    --       the Overpower proc above).
    --
    -- A Slam still casting is cancelled first, so the press that would have been
    -- spent waiting out the cast lands the Execute instead. Off by setting
    -- slamCancelForExecute to false.
    if inExecute then
        if cfg.slamCancelForExecute then self:CancelSlamForExecute() end
        if self:Try("Execute", "target below 20%") then return end
    end

    -- 1c2. Whirlwind FIRST while in AoE mode, against a real pack (two or more
    --      enemies - AoEWWPack). It sits at 1e below for the single-target rage
    --      dump, which is the right place for that job - but against several
    --      targets it hits all of them and Mortal Strike hits one, so letting
    --      the primary strike take the press there is a plain loss. Reported as
    --      Mortal Strike still going first in AoE.
    --
    --      The one exception is Sweeping Strikes on a small pack: Mortal Strike
    --      spends the charge better than Whirlwind there (see SS_BIG_PACK), so
    --      the jump is held and the primary strike at 1d takes the charge.
    --      Resolved here, once, so the cast and the dance below agree.
    --
    --      Only in AoE, and the copy below still handles the rage dump: if this
    --      does not fire (cooldown, rage, wrong stance) the press falls through
    --      exactly as before. A Slam still casting is stopped so the Whirlwind
    --      goes out now instead of after the cast.
    if wwFirst then
        self:CancelSlamForAoE()
        if self:Pick("Whirlwind", "AoE, ahead of the primary strike") then return end
    elseif aoe and cfg.useWhirlwind and cfg.stanceDance and not self:SlamCasting()
        and self:AoEWWPack() and not ssWantsMs
        and self:TalentRank(TALENT_TACTICAL_MASTERY) >= 5
        and rage >= RAGE["Whirlwind"]
        and self:KnowsSpell("Whirlwind") and self:IsReady("Whirlwind")
        and not self:InStance("Berserker Stance") then
        -- Not in Berserker but Tactical Mastery 5/5 keeps 25 rage through the
        -- swap, which exactly covers Whirlwind's cost. Dance in; 1i drifts back
        -- to the home stance once the Whirlwind is away.
        if self:SwitchStance("Berserker Stance") then return end
    end

    -- 1c2b. Thunder Clap jumps ahead in AoE like Whirlwind does: it hits every
    --      enemy in range where the primary strike hits one. Battle/Defensive
    --      stance on 1.12, so a berserker falls through to the strikes - the
    --      stance gate is what keeps the two AoE jumps from competing for the
    --      same press. Cancels a stale Slam like the Whirlwind jump does.
    if aoe and cfg.useThunderClap and self:ThunderClapWorth(cfg)
        and self:CanCast("Thunder Clap", RAGE["Thunder Clap"], STANCE_REQ["Thunder Clap"]) then
        self:CancelSlamForAoE()
        if self:Pick("Thunder Clap", "AoE, ahead of the primary strike") then return end
    end

    -- 1d. Primary strike on cooldown. Usually only one of these is known /
    --     talented for a given spec, so order between them rarely matters.
    if cfg.useShieldSlam   and self:Try("Shield Slam", "primary strike")   then return end
    if cfg.useBloodthirst  and self:Try("Bloodthirst", "primary strike")   then return end
    if cfg.useMortalStrike and self:Try("Mortal Strike", "primary strike") then return end

    -- 1d0. Master Strike (Arms talent, opt-in - off by default as it is mainly a
    --      PvP pick). Placed directly BELOW the spec's primary strike so enabling
    --      it never displaces Mortal Strike / Bloodthirst / Shield Slam; it fills
    --      the windows where the primary is on cooldown. It is a talent-granted
    --      spell, so KnowsSpell sees it only once talented. No stance entry in
    --      STANCE_REQ (unverified), so it is not stance-gated - report back if it
    --      turns out to be Battle/Berserker only.
    if cfg.useMasterStrike and self:Try("Master Strike", "filler strike") then return end

    -- 1d0b. Concussion Blow (Protection talent, opt-in - off by default). Placed
    --       directly below the primary strike for the same reason Master Strike
    --       is: enabling it must never displace Shield Slam, and it fills the
    --       windows where the primary is cooling down.
    --
    --       Turtle tooltip: instant, 20s cooldown, 5yd, 190 damage, 3s stun,
    --       "high amount of threat", penetrates 100% of armor, and it COSTS
    --       NOTHING while generating 10 rage.
    --
    --       That last part is the argument for putting it HIGHER than this. It
    --       is free threat that pays for the next Shield Slam, so spending a
    --       global cooldown on it costs only the global cooldown, and bosses
    --       being stun-immune removes the usual reason to hold a stun back.
    --       It stays below the primary strike anyway, because that is still the
    --       larger threat and the change is not mine to make on a tank I cannot
    --       play - moving it one block up is a two-line edit if the answer is
    --       yes.
    --
    --       No stance entry: none is confirmed.
    if cfg.useConcussionBlow and self:Try("Concussion Blow", "stun on cooldown") then return end

    -- 1d1. Battle Shout upkeep (party attack-power buff). Refreshed only when it
    --      is missing or about to expire, and BELOW the strikes so it never
    --      delays one - it costs a GCD only ~once every couple of minutes. Any
    --      stance; skipped in the execute phase so rage funnels to Execute. The
    --      time-left read is guarded so an unknown (0) duration never spams it.
    if cfg.useBattleShout and not inExecute
        and self:CanCast("Battle Shout", RAGE["Battle Shout"], nil) then
        local up = self:HasBuff("Battle Shout")
        local bt = self:BuffTime("Battle Shout")
        if not up or (bt > 0 and bt < BSHOUT_RENEW) then
            if self:Pick("Battle Shout", up and "about to expire" or "missing") then return end
        end
    end

    -- 1d1b. Demoralizing Shout upkeep (opt-in; AoE attack-power reduction on the
    --       target for mitigation). Debuff-tracked like Rend, re-applied only
    --       when it is not on the target. Any stance; skipped during execute.
    --       Skipped on ranged casters (TargetIsSpellcaster + not in melee): AP
    --       reduction does nothing to a spell user at range. A caster in melee
    --       range still auto-attacks, so the AP reduction applies to their melee
    --       swings and the shout is worth it. Also held for CHARGE_DEMO_HOLD
    --       after a Charge opener so it does not fire while the warrior is still
    --       mid-animation and out of range.
    if cfg.useDemoShout and not inExecute
        and not (self:TargetIsSpellcaster() and not self:InMeleeRange())
        and (GetTime() - (self.lastChargeAt or 0)) > CHARGE_DEMO_HOLD
        and self:CanCast("Demoralizing Shout", RAGE["Demoralizing Shout"], nil)
        and self:TargetTakesShout()
        and not Aegis_SBR:TargetDebuffUp("Demoralizing Shout", "Ability_Warrior_WarCry") then
        if self:Pick("Demoralizing Shout", "not on target") then
            self:Later(function() self.shoutCastAt = GetTime() end)
            return
        end
    end

    -- 1d2. Rend bleed upkeep (toggle; a leveling tool, off by default). Battle
    --      or Defensive stance, applied only when the bleed is not already on
    --      the target. Skipped in the execute phase so rage funnels to Execute,
    --      and skipped entirely on bleed-immune targets, where the debuff can
    --      never land and the "not up" test would otherwise re-cast forever.
    if cfg.useRend and not inExecute and not aoe and self:KnowsSpell("Rend")
        and not self:TargetIsBleedImmune()
        and self:CanCast("Rend", RAGE["Rend"], STANCE_REQ["Rend"])
        -- Rend is per-caster. Demoralizing Shout above is shared and is
        -- deliberately left alone: anybody's copy is as good as ours.
        and not (Aegis_SBR:TargetDebuffUp("Rend", "ability_rend")
            and Aegis_SBR:DebuffMine("Rend", Aegis_SBR:TargetId())) then
        if self:Pick("Rend", "bleed missing") then
            Aegis_SBR:NoteDebuffApplied(Aegis_SBR:TargetId(), "Rend", REND_DUR)
            return
        end
    end

    -- 1d3. Hamstring (toggle, off by default): the slow kept on the target, for
    --      runners and PvP. Shared - anybody's Hamstring is the same slow - and
    --      not re-sent on the same target for a few seconds, so an immune or
    --      unreadable target cannot take every press.
    if cfg.useHamstring and not inExecute and not aoe and self:KnowsSpell("Hamstring")
        and self:CanCast("Hamstring", RAGE["Hamstring"], STANCE_REQ["Hamstring"])
        and not Aegis_SBR:TargetDebuffUp("Hamstring", "Ability_ShockWave")
        and not (self.hamstringId == Aegis_SBR:TargetId() and GetTime() - (self.hamstringAt or 0) < 4) then
        if self:Pick("Hamstring", "slow missing") then
            local id = Aegis_SBR:TargetId()
            self:Later(function() self.hamstringId = id; self.hamstringAt = GetTime() end)
            return
        end
    end

    -- 1e. Whirlwind: against a real 3+ pack in AoE, or as a single-target rage
    --     dump when rage is running high. Berserker stance only.
    if cfg.useWhirlwind and not self:SlamCasting()
        and self:CanCast("Whirlwind", RAGE["Whirlwind"], STANCE_REQ["Whirlwind"]) then
        if (aoe and self:AoEWWPack()) or rage >= (cfg.wwExcess or 60) then
            if self:Pick("Whirlwind", aoe and "AoE" or "rage dump") then return end
        end
    end

    -- 1h. Slam filler (Arms), behind two gates it did not have before, and
    --      stood down entirely in AoE mode - the 2.5s single-target cast is a
    --      loss against a pack, where the GCD belongs to Whirlwind / Thunder
    --      Clap (which jump ahead via 1c2/1c2b).
    --
    --      It yields to a primary strike that is ready and only short of rage -
    --      being the cheapest ability in the list, it used to take those presses
    --      and leave Mortal Strike or Whirlwind waiting.
    --
    --      And it stands down when its cast would run past the next white swing.
    --      Slam delays the swing rather than resetting it here, so this is worth
    --      an estimate but not worth being strict about: an unknown swing timer
    --      lets it through, except before the very first swing of combat has
    --      landed - Slam then delays the opener, which the rotation hangs off.
    if cfg.useSlam and not aoe then
        local waiting = self:StrikeWaitingOnRage(cfg)
        if waiting then
            if self:Tracing() then self:Trace("slam held: " .. waiting .. " is ready, waiting on rage") end
        elseif not self:SlamFitsBeforeSwing() then
            if self:Tracing() then self:Trace("slam held: would clip the next swing") end
        elseif not self:SlamCasting() and self:Try("Slam", "filler") then
            -- For CancelSlamForExecute above. SlamCastTime folds in Improved Slam.
            self:Later(function()
                self.slamCastUntil = GetTime() + self:SlamCastTime()
            end)
            return
        end
    end

    -- 1i. Drift back to the home stance when nothing reactive is pending.
    if cfg.stanceDance and cfg.homeStance ~= "none" then
        local home = self.STANCES[cfg.homeStance]
        -- Hold the drift while staying in Berserker pays: while Berserker Rage
        -- is up (rage and fear-immunity), or Whirlwind is stood ready as the
        -- next hit - the same gate 1e uses, the AoE pack or the rage-excess
        -- dump - so the Whirlwind fires without a re-dance and its Tactical
        -- Mastery cost. Drift resumes when neither holds.
        --
        -- ssHold is the third hold, and it is the one that makes the Sweeping
        -- Strikes dance at 0b3 worth anything: the pop cannot be paid for on
        -- the press after the swap (25 retained, 30 spent), so without it the
        -- stance drifted straight back to Berserker and the buff was never
        -- bought. It holds for the charges too, so they are spent in the stance
        -- that can spend them.
        local wwComing = cfg.useWhirlwind and not self:SlamCasting()
            and not ssWantsMs
            and self:KnowsSpell("Whirlwind") and self:IsReady("Whirlwind")
            and ((aoe and self:AoEWWPack()) or rage >= (cfg.wwExcess or 60))
        local holdHome = false
        if self.overpowerStanceHold then
            local left = self:SwingTimeLeft()
            holdHome = rage > OVERPOWER_STANCE_RAGE
                or (left and left <= OVERPOWER_SWING_LOOKAHEAD)
            if not holdHome then self.overpowerStanceHold = nil end
        end
        if home and not self:InStance(home)
            and not (self:InStance("Berserker Stance")
                and (self:HasBuff("Berserker Rage") or wwComing))
            and not chargePending and not holdHome and not ssHold
            and now >= (self.overpowerExpiry or 0)
            and now >= (self.revengeExpiry or 0) then
            self:SwitchStance(home)
        end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:CmdAoe(arg, onoff)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    if arg == "auto" then
        -- `== nil` on purpose: false is a valid result and must not read as an error.
        local v = Aegis_SBR:ToggleArg(cfg.aoeAuto, onoff)
        if v == nil then
            msgOut("usage: /sbr aoe auto [on|off] - no argument toggles.", 1, 0.5, 0.3)
            return
        end
        cfg.aoeAuto = v
        -- fresh start on (re)enable: the count decides until the manual line
        -- gets pulled. `aoeMode` is left alone - the auto-off toggle keeps it.
        cfg.aoeOverride = nil
        msgOut("auto AoE " .. (v and "on (switch by enemy count)" or "off (manual toggle only)") .. ".")
        return
    end
    if arg and arg ~= "" then
        msgOut("usage: /sbr aoe | /sbr aoe auto [on|off]", 1, 0.5, 0.3)
        return
    end
    if cfg.aoeAuto then
        -- With auto on, /sbr aoe FORCES a side: first press off, next on,
        -- then off again. nil (the idle hand) means the count decides.
        cfg.aoeMode = false
        -- Cycle nil -> false -> true -> nil by explicit branch. Do NOT
        -- rewrite this as and/or chaining: `X and false` is false for every X,
        -- and a false that reaches the final `or nil` gets absorbed (false or
        -- nil = nil), which latches the state on nil and kills the cycle.
        -- nil = idle hand: the enemy count decides. Reachable again each full
        -- pass, so a manual press can never strand autoaoe.
        local cur = cfg.aoeOverride
        if cur == nil then
            cfg.aoeOverride = false
        elseif cur == false then
            cfg.aoeOverride = true
        else
            cfg.aoeOverride = nil
        end
        if cfg.aoeOverride == nil then
            msgOut("AoE back to auto (enemy count decides).")
        elseif cfg.aoeOverride then
            msgOut("AoE forced ON over auto (next /sbr aoe: back to auto).")
        else
            msgOut("AoE forced OFF over auto (next /sbr aoe: ON, then auto).")
        end
    else
        cfg.aoeMode = not cfg.aoeMode
        msgOut("AoE mode " .. (cfg.aoeMode and "on (Cleave + Whirlwind)" or "off (single target)")
            .. ". auto=" .. (cfg.aoeAuto and "on" or "off") .. ".")
    end
end

function M:CmdCd(mode)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    mode = string.lower(mode or "")
    if mode == "on" or mode == "always" then
        cfg.popCDs = true;  cfg.autoCDElite = false
        msgOut("cooldowns: always pop.")
    elseif mode == "elite" or mode == "boss" then
        cfg.popCDs = false; cfg.autoCDElite = true
        msgOut("cooldowns: auto on elite and boss only.")
    elseif mode == "off" or mode == "manual" or mode == "none" then
        cfg.popCDs = false; cfg.autoCDElite = false
        msgOut("cooldowns: manual (off).")
    else
        msgOut("usage: /sbr cd on | elite | off", 1, 0.5, 0.3)
    end
end

function M:CmdDance()
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.stanceDance = not cfg.stanceDance
    msgOut("stance dancing " .. (cfg.stanceDance and "on" or "off") .. ".")
end

function M:CmdSpell(alias, onoff)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local key = self.spellAlias[string.lower(alias or "")]
    if not key then msgOut("unknown spell alias.", 1, 0.5, 0.3); return end
    -- `== nil` on purpose: false is a valid result and must not read as an error.
    local v = Aegis_SBR:ToggleArg(cfg[key], onoff)
    if v == nil then
        msgOut("usage: /sbr spell " .. string.lower(alias) .. " [on|off] - no argument toggles.", 1, 0.5, 0.3)
        return
    end
    cfg[key] = v
    msgOut(Aegis_SBR:SpellLabel(key) .. " " .. (cfg[key] and "on" or "off") .. ".")
end

function M:HandleCommand(cmd, t)
    if cmd == "aoe"   then self:CmdAoe(t[2], t[3]); return true end
    if cmd == "cd"    then self:CmdCd(t[2]); return true end
    if cmd == "dance" then self:CmdDance(); return true end
    if cmd == "spell" then self:CmdSpell(t[2], t[3]); return true end
    return false
end

-- ============================================================
-- Reactive proc tracker. Owned by the module, stays inert unless the
-- matching option is enabled. Overpower comes from the TARGET dodging our
-- attack; Revenge from us blocking, dodging, or parrying an enemy attack.
-- ============================================================
-- The combat log is the only source for these windows and its wording is
-- localised, so the FrameXML format strings are compiled into patterns instead
-- of being matched as English substrings - which answer "never" on every other
-- client. The English fallback covers only a missing global.
local function ReactPattern(fmt, fallback)
    if type(fmt) ~= "string" then return fallback end
    local s = fmt
    -- Placeholders first, through sentinels, so the escape pass below cannot
    -- turn "%s" into the whitespace class.
    s = string.gsub(s, "%%%d+%$s", "\1")
    s = string.gsub(s, "%%%d+%$d", "\2")
    s = string.gsub(s, "%%s", "\1")
    s = string.gsub(s, "%%d", "\2")
    s = string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    s = string.gsub(s, "\1", ".-")
    s = string.gsub(s, "\2", "%%d+")
    return s
end

local function MatchesAny(text, pats)
    for i = 1, table.getn(pats) do
        if pats[i] and string.find(text, pats[i]) then return true end
    end
    return false
end

-- A blocked attack is NOT a miss. A partial block - the normal case - still
-- lands, so its line carries a "(N blocked)" trailer on the HITS event; only a
-- full block, where the block value covers the whole hit, reaches MISSES.
-- Reading MISSES alone therefore misses nearly every block a tank takes, which
-- is why Revenge followed a dodge or a parry but never a block.
local BLOCK_TRAILER_PAT = ReactPattern(BLOCK_TRAILER, "blocked")

-- "X attacks. You block/dodge/parry." Self-explicit, so these stay safe on the
-- hostile-player events, which also carry lines about other people.
local REVENGE_MISS_PATS = {
    ReactPattern(VSBLOCKOTHERSELF, "You block"),
    ReactPattern(VSDODGEOTHERSELF, "You dodge"),
    ReactPattern(VSPARRYOTHERSELF, "You parry"),
}

-- The block trailer does not say who blocked, so a self-hit line is required
-- alongside it before a partial block counts.
local SELF_HIT_PATS = {
    ReactPattern(COMBATHITOTHERSELF,           "hits you for"),
    ReactPattern(COMBATHITCRITOTHERSELF,       "crits you for"),
    ReactPattern(COMBATHITSCHOOLOTHERSELF,     "hits you for"),
    ReactPattern(COMBATHITCRITSCHOOLOTHERSELF, "crits you for"),
}

-- Slam is the only cast a warrior has, so these three events mean exactly one
-- thing here: that cast is over. Kept on its own frame because the react frame
-- below returns immediately on an event with no arg1.
local castFrame = CreateFrame("Frame")
castFrame:RegisterEvent("SPELLCAST_STOP")
castFrame:RegisterEvent("SPELLCAST_FAILED")
castFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
castFrame:SetScript("OnEvent", function()
    if M.logging then M:LogWrite("slamend " .. tostring(event)) end
    M.slamCastUntil = nil
end)

local reactFrame = CreateFrame("Frame")
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")              -- our attacks that were avoided
reactFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")               -- ability dodge: "Your Slam was dodged by X."
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")  -- enemy attacks we fully avoided
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")    -- enemy attacks we partially blocked
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")     -- the same two in PvP: a player
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")       -- attacker uses its own events
reactFrame:SetScript("OnEvent", function()
    if not arg1 then return end

    -- Overpower: our own attack, avoided by the target. The client reports an
    -- ability dodge ("Your Slam was dodged by Sparkleshell Snapper.") through
    -- the SPELL channel, not SELF_MISSES - a dodge that never matched made the
    -- whole window dead on this client. Listen on both; only the word decides.
    if event == "CHAT_MSG_COMBAT_SELF_MISSES" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        if string.find(string.lower(arg1), "dodge") then
            if M.logging then M:LogWrite("dodge " .. arg1) end
            -- Both: the expiry the rotation gates on, and the moment itself, so
            -- the age of an attempt can be worked out afterwards.
            M.overpowerAt = GetTime()
            M.overpowerExpiry = M.overpowerAt + M.opWindow
            -- An unresolved attempt belonged to the window that just ended; a
            -- fresh dodge opens a new one, and the leftover must not decide it.
            M.overpowerAttemptAt = nil
        end
        return
    end

    local trigger
    if event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
        trigger = string.find(arg1, BLOCK_TRAILER_PAT) and MatchesAny(arg1, SELF_HIT_PATS)
    else
        trigger = MatchesAny(arg1, REVENGE_MISS_PATS)
    end

    if trigger then
        M.revengeExpiry = GetTime() + REACT_WINDOW
        -- An unresolved attempt belonged to the window that just ended; a
        -- fresh trigger opens a new one, and the leftover must not decide it.
        M.revengeAttemptAt = nil
        -- Latched: the parse works on this client, so the rotation fallback is
        -- never needed again this session.
        M.revengeSeen = true
    end
end)
