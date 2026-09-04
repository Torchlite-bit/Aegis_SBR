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
M.uiHeight = 730

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
-- Improved Slam takes 0.3s per rank off it, 2 ranks, so a fully talented Arms
-- warrior casts it in 1.9s. Both numbers come from the talent tooltip read at
-- rank 0/2, which is what makes 2.5 the BASE rather than one player's current
-- value - so subtracting the rank here is correct and does not double-count.
-- (The talent shortens Slam's global cooldown by the same amount; that matters
-- for the rotation's pacing but not for the swing test below.)
local SLAM_CAST_BASE = 2.5
local SLAM_CAST_PER_RANK = 0.3
local TALENT_IMP_SLAM = "Improved Slam"
-- How long the Revenge fallback waits between attempts while the combat log
-- has not answered even once. Matched to Revenge's own cooldown, so the
-- fallback can never cost more than one press per cooldown.
local REVENGE_PROBE_GAP = 5.0
-- Minimum gap between stance switches; stance changes have a ~1s internal
-- cooldown, so we never thrash faster than this.
local STANCE_CD = 1.0
-- Light throttle so a rapid press burst does not re-issue the queued
-- on-next-swing ability several times in the same swing.
local DUMP_THROTTLE = 0.3
-- Refresh Battle Shout when it is missing or has under this many seconds left.
-- It lasts ~2 min, so this refreshes it roughly once per two minutes.
local BSHOUT_RENEW = 30

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

local RAGE = {
    ["Mortal Strike"] = 30,
    ["Bloodthirst"]   = 30,
    ["Shield Slam"]   = 20,
    ["Whirlwind"]     = 25,
    ["Slam"]          = 15,
    ["Execute"]       = 10,   -- 15 base, but consumes all extra rage
    ["Overpower"]     = 5,
    ["Revenge"]       = 5,
    ["Sunder Armor"]  = 12,   -- 15 base, often reduced
    ["Thunder Clap"]  = 20,
    ["Charge"]        = 0,    -- generates rage; free to attempt
    ["Rend"]          = 10,
    ["Battle Shout"]        = 10,
    ["Demoralizing Shout"]  = 10,
    -- Master Strike: 20 rage, tooltip confirmed on Turtle. Was estimated at 25.
    ["Master Strike"] = 20,
    -- Concussion Blow costs NOTHING on Turtle and generates 10 rage on use
    -- (tooltip confirmed). Zero rather than absent so the intent is explicit:
    -- there is no cost to check, not "we never looked".
    ["Concussion Blow"] = 0,
}

-- Stances an ability may be used from (vanilla 1.12). nil = any stance.
local STANCE_REQ = {
    ["Mortal Strike"] = { "Battle Stance", "Berserker Stance" },
    ["Whirlwind"]     = { "Berserker Stance" },
    ["Execute"]       = { "Battle Stance", "Berserker Stance" },
    ["Overpower"]     = { "Battle Stance" },
    ["Revenge"]       = { "Defensive Stance" },
    ["Thunder Clap"]  = { "Battle Stance" },
    ["Charge"]        = { "Battle Stance" },
    ["Rend"]          = { "Battle Stance", "Defensive Stance" },
    ["Recklessness"]  = { "Berserker Stance" },
    ["Berserker Rage"]= { "Berserker Stance" },
    ["Shield Block"]  = { "Defensive Stance" },
    -- Bloodthirst, Shield Slam, Slam, Sunder Armor, Heroic Strike, Cleave,
    -- Death Wish, Bloodrage: usable in any stance (Shield Slam needs a shield).
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
    rend = "useRend",
    battleshout = "useBattleShout", bshout = "useBattleShout",
    demoshout = "useDemoShout", demo = "useDemoShout",
    masterstrike = "useMasterStrike", mstrike = "useMasterStrike",
    concussionblow = "useConcussionBlow", cblow = "useConcussionBlow",
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
        useHeroicStrike = true, dumpRage = 60, wwExcess = 60,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
        useCharge = false, useRend = false,
    },
    fury = {
        useMortalStrike = false, useBloodthirst = true, useShieldSlam = false,
        useWhirlwind = true, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = true, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 50,
        popCDs = false, autoCDElite = true,
        useDeathWish = true, useRecklessness = true, useBerserkerRage = true,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
        useCharge = false, useRend = false,
    },
    arms = {
        useMortalStrike = true, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = true, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = true, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = true, useCleave = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 55,
        popCDs = false, autoCDElite = true,
        useDeathWish = false, useRecklessness = true, useBerserkerRage = true,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
        useCharge = false, useRend = false,
    },
    prot = {
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = true,
        useWhirlwind = false, useSlam = false,
        useOverpower = false, useRevenge = true, useExecute = false,
        stanceDance = false, homeStance = "defensive",
        useSunder = true, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 70,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = true,
        useCharge = false, useRend = false,
    },
}

-- Fills any missing field with a default. No old-format migration yet,
-- so unknown keys are simply left alone.
function M:NormalizeProfile(c)
    local b = {
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = false, useSlam = false,
        useOverpower = false, useRevenge = false, useExecute = true,
        stanceDance = false, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 60, wwExcess = 60,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
        useCharge = false, useRend = false,
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

function M:SlamCastTime()
    local t = SLAM_CAST_BASE - SLAM_CAST_PER_RANK * self:TalentRank(TALENT_IMP_SLAM)
    if t < 0.5 then t = 0.5 end
    return t
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
function M:SlamFitsBeforeSwing()
    local left = Aegis_SBR:SwingTimeLeft()
    if not left then return true end
    return left >= self:SlamCastTime()
end

function M:Try(name, reason)
    if WEAPON_REQ[name] and not Aegis_SBR:WeaponAllows(WEAPON_REQ[name]) then return false end
    if self:CanCast(name, RAGE[name], STANCE_REQ[name]) then
        return self:Pick(name, reason)
    end
    return false
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
    -- Apply until we reach the configured stacks; once there we let it ride
    -- and re-apply only after it falls off (precise refresh timing is not
    -- reliable on 1.12 without extra debuff data).
    return self:SunderStacksOnTarget() < want
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

-- ============================================================
-- Rotation
-- ============================================================
function M:Rotate(cfg)
    local rage   = self:Rage()
    local now    = GetTime()
    local hp     = self:TargetHPPct()
    local cls    = UnitClassification("target")
    local isElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    local aoe    = cfg.aoeMode and true or false
    local inCombat = UnitAffectingCombat("player")

    local inExecute = cfg.useExecute and hp <= 20 and self:KnowsSpell("Execute")
        and rage >= RAGE["Execute"] and not self:InStance("Defensive Stance")

    if self:Tracing() then
        self:Trace("rage=" .. rage
            .. " stance=" .. (self:CurrentStanceName() or "-")
            .. " hp=" .. string.format("%.0f", hp)
            .. " aoe=" .. (aoe and "Y" or "N")
            .. " op=" .. ((now < (self.overpowerExpiry or 0)) and "Y" or "N")
            .. " rev=" .. ((now < (self.revengeExpiry or 0)) and "Y" or "N")
            .. " revseen=" .. (self.revengeSeen and "Y" or "N")
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
    -- 0a. Bloodrage to keep rage flowing (works out of combat for pulls), but
    --     never while a Charge opener is pending - see chargePending above.
    if cfg.useBloodrage and not chargePending and self:KnowsSpell("Bloodrage")
        and self:IsReady("Bloodrage") and rage < (cfg.bloodrageRage or 30) then
        self:PickExtra("Bloodrage")
    end

    -- 0b. Burst cooldowns, gated by the pop mode and (for the offensive
    --     ones) by being in combat so they are not wasted pre-pull.
    local popBurst = cfg.popCDs or (cfg.autoCDElite and isElite)
    if popBurst and inCombat then
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

    -- 0c. Sweeping Strikes for cleave windows (off the GCD).
    if aoe and cfg.useSweeping and self:KnowsSpell("Sweeping Strikes")
        and self:InAnyStance(STANCE_REQ["Sweeping Strikes"]) and self:IsReady("Sweeping Strikes") then
        self:PickExtra("Sweeping Strikes")
    end

    -- 0d. Shield Block to feed Revenge / mitigate (Defensive only, off GCD).
    if cfg.useShieldBlock and self:InStance("Defensive Stance")
        and self:KnowsSpell("Shield Block") and self:IsReady("Shield Block")
        -- Off the GCD, so it never reaches Try: checked here instead.
        and Aegis_SBR:WeaponAllows("shield") then
        self:PickExtra("Shield Block")
    end

    -- 0e. Rage dump on the next swing. Suppressed during the execute phase
    --     so rage is funneled into Execute instead. Cleave when in AoE mode
    --     (and known), otherwise Heroic Strike.
    if cfg.useHeroicStrike and not inExecute and rage >= (cfg.dumpRage or 60)
        and (now - (self.lastDump or 0)) > DUMP_THROTTLE then
        -- The throttle stamp is a state change, so it waits for a real press.
        if aoe and cfg.useCleave and self:KnowsSpell("Cleave") then
            if self:PickExtra("Cleave") then
                self:Later(function() self.lastDump = now end)
            end
        elseif self:KnowsSpell("Heroic Strike") then
            if self:PickExtra("Heroic Strike") then
                self:Later(function() self.lastDump = now end)
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 1. GCD priority (strict, exactly one cast per press via early return)
    -- ----------------------------------------------------------------

    -- 1@. Charge opener (toggle). Battle Stance only, and only as a pull: you
    --     must be OUT of melee range (so it is a gap-closer, never mid-fight)
    --     with an attackable target. Stance-dances to Battle if enabled and
    --     needed. Charge itself is blocked by the client once you are in
    --     combat, so this naturally stops applying after the pull.
    if chargePending then
        if self:InStance("Battle Stance") then
            if self:IsReady("Charge") then
                if self:Pick("Charge", "opener, out of melee") then return end
            end
        elseif cfg.stanceDance or cfg.homeStance == "battle" then
            if self:SwitchStance("Battle Stance") then return end
        end
    end

    self:OverpowerLearnTick()

    -- 1a. Revenge (Defensive). Mainly a tank reactive; only pursued while
    --     in Defensive, or stance-danced to it when home stance is Defensive.
    --
    --     Until the combat log has produced a trigger even once, "no window
    --     open" is silence rather than an answer: the parse may be reading a
    --     client whose wording it does not match. Silence must not close a
    --     gate, so Revenge is attempted on its cooldown instead. The first
    --     trigger read latches revengeSeen and this fallback never runs again.
    --
    --     Bounded twice: only while already in Defensive Stance, so a guess can
    --     never start a stance dance, and no more often than REVENGE_PROBE_GAP,
    --     so a refused cast - which starts no cooldown - cannot be retried on
    --     every press and stall the rest of the chain.
    local revOpen = now < (self.revengeExpiry or 0)
    local revProbe = false
    if not revOpen and not self.revengeSeen and self:InStance("Defensive Stance")
        and (now - (self.revengeProbeAt or 0)) >= REVENGE_PROBE_GAP then
        revOpen, revProbe = true, true
    end
    if cfg.useRevenge and self:KnowsSpell("Revenge") and revOpen
        and self:IsReady("Revenge") and rage >= RAGE["Revenge"] then
        if self:InStance("Defensive Stance") then
            local why = revProbe and "no trigger read yet, trying on cooldown"
                or "block/dodge/parry window"
            if self:Pick("Revenge", why) then
                self:Later(function()
                    self.revengeExpiry = 0
                    self.revengeProbeAt = GetTime()
                end)
                return
            end
        elseif cfg.stanceDance and cfg.homeStance == "defensive" then
            if self:SwitchStance("Defensive Stance") then return end
        end
    end

    -- 1b. Execute below 20% (highest single-target priority per design).
    if inExecute then
        if self:Try("Execute", "target below 20%") then return end
    end

    -- 1c. Overpower (Battle), reactive. Stance-dance in when enabled.
    if cfg.useOverpower and self:KnowsSpell("Overpower") and now < (self.overpowerExpiry or 0)
        and self:IsReady("Overpower") and rage >= RAGE["Overpower"] then
        if self:InStance("Battle Stance") then
            if self:Pick("Overpower", "target dodged") then
                self:Later(function()
                    -- Kept, not cleared, so a refusal arriving next frame can
                    -- still be attributed to this attempt and its age.
                    self.opSentAt = GetTime()
                    self.opSentAge = self.overpowerAt and (GetTime() - self.overpowerAt) or nil
                    self.overpowerExpiry = 0
                end)
                return
            end
        elseif cfg.stanceDance then
            if self:SwitchStance("Battle Stance") then return end
        end
    end

    -- 1c2. Whirlwind FIRST while in AoE mode. It sits at 1e below for the
    --      single-target rage dump, which is the right place for that job - but
    --      against several targets it hits all of them and Mortal Strike hits
    --      one, so letting the primary strike take the press there is a plain
    --      loss. Reported as Mortal Strike still going first in AoE.
    --
    --      Only in AoE, and the copy below still handles the rage dump: if this
    --      does not fire (cooldown, rage, wrong stance) the press falls through
    --      exactly as before.
    if aoe and cfg.useWhirlwind
        and self:CanCast("Whirlwind", RAGE["Whirlwind"], STANCE_REQ["Whirlwind"]) then
        if self:Pick("Whirlwind", "AoE, ahead of the primary strike") then return end
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
    if cfg.useDemoShout and not inExecute
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
    if cfg.useRend and not inExecute and self:KnowsSpell("Rend")
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

    -- 1e. Whirlwind: on cooldown in AoE, or as a single-target rage dump
    --     when rage is running high. Berserker stance only.
    if cfg.useWhirlwind and self:CanCast("Whirlwind", RAGE["Whirlwind"], STANCE_REQ["Whirlwind"]) then
        if aoe or rage >= (cfg.wwExcess or 60) then
            if self:Pick("Whirlwind", aoe and "AoE" or "rage dump") then return end
        end
    end

    -- 1f. Thunder Clap for AoE (Battle stance in 1.12).
    if aoe and cfg.useThunderClap and self:Try("Thunder Clap", "AoE") then return end

    -- 1g. Sunder Armor upkeep (threat / armor reduction).
    if cfg.useSunder and self:CanCast("Sunder Armor", RAGE["Sunder Armor"], nil)
        and self:NeedSunder(cfg) then
        if self:Pick("Sunder Armor", "stack upkeep") then return end
    end

    -- 1h. Slam filler (Arms), behind two gates it did not have before.
    --
    --      It yields to a primary strike that is ready and only short of rage -
    --      being the cheapest ability in the list, it used to take those presses
    --      and leave Mortal Strike or Whirlwind waiting.
    --
    --      And it stands down when its cast would run past the next white swing.
    --      Slam delays the swing rather than resetting it here, so this is worth
    --      an estimate but not worth being strict about: an unknown swing timer
    --      lets it through.
    if cfg.useSlam then
        local waiting = self:StrikeWaitingOnRage(cfg)
        if waiting then
            if self:Tracing() then self:Trace("slam held: " .. waiting .. " is ready, waiting on rage") end
        elseif not self:SlamFitsBeforeSwing() then
            if self:Tracing() then self:Trace("slam held: would clip the next swing") end
        elseif self:Try("Slam", "filler") then
            return
        end
    end

    -- 1i. Drift back to the home stance when nothing reactive is pending.
    if cfg.stanceDance and cfg.homeStance ~= "none" then
        local home = self.STANCES[cfg.homeStance]
        if home and not self:InStance(home)
            and now >= (self.overpowerExpiry or 0)
            and now >= (self.revengeExpiry or 0) then
            self:SwitchStance(home)
        end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:CmdAoe()
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.aoeMode = not cfg.aoeMode
    msgOut("AoE mode " .. (cfg.aoeMode and "on (Cleave + Whirlwind)" or "off (single target)") .. ".")
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
    if cmd == "aoe"   then self:CmdAoe(); return true end
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

local reactFrame = CreateFrame("Frame")
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")              -- our attacks that were avoided
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")  -- enemy attacks we fully avoided
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")    -- enemy attacks we partially blocked
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")     -- the same two in PvP: a player
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")       -- attacker uses its own events
reactFrame:SetScript("OnEvent", function()
    if not arg1 then return end

    -- Overpower: our own attack, avoided by the target. Unchanged.
    if event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        if string.find(string.lower(arg1), "dodge") then
            -- Both: the expiry the rotation gates on, and the moment itself, so
            -- the age of an attempt can be worked out afterwards.
            M.overpowerAt = GetTime()
            M.overpowerExpiry = M.overpowerAt + M.opWindow
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
        -- Latched: the parse works on this client, so the rotation fallback is
        -- never needed again this session.
        M.revengeSeen = true
    end
end)
