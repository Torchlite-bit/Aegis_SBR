-- ============================================================
-- Class_Hunter  -  hunter module for Aegis_SBR
-- Turtle WoW 1.18.1 (SuperWoW). Reworked for Turtle's hunter changes.
-- ============================================================
-- Turtle 1.18.1 reshaped the hunter heavily, so this module is built around
-- the live playstyles rather than vanilla:
--  * RANGED (BM / MM): Auto Shot is the damage backbone. Steady Shot (now
--    baseline at 20) weaves 1:1 after each Auto Shot - it is gated on the exact
--    Auto Shot timing from SuperWoW's UNIT_CASTEVENT (with an interval fallback)
--    so mashing it cannot chain casts and starve Auto Shot - with Arcane Shot and
--    Multi-Shot weaved as instants. Aimed Shot is NOT pressed on cooldown
--    (it clips Auto Shot) - it is only fired when the Marksmanship capstone
--    "Lock and Load" procs (crit from Steady/Aimed/Arcane resets Aimed Shot,
--    drops its cast time, and makes it cleave a line), or optionally on
--    cooldown if you turn the proc-only guard off.
--  * MELEE (Survival / BM-melee): Aspect of the Wolf, melee auto-attack,
--    Raptor Strike and Mongoose Bite on cooldown,
--    optional Wing Clip. Survival can also drop Immolation Trap on cooldown
--    in combat (a 1.18.1 change) and weave shots.
--  * Mana aspect swap: at a low-mana threshold the rotation swaps to the
--    mana-regenerating aspect, then back to the combat aspect once recovered
--    (hysteresis, so it does not flap at the boundary).
--  * Pet: attack, Mend Pet when hurt, Kill Command on cooldown (BM), and an
--    optional Baited Shot reaction when the pet crits.
-- Exact spell strings are gated by KnowsSpell, so an ability the character or
-- the server does not have simply no-ops instead of breaking the chain.
-- ============================================================

local M = Aegis_SBR:NewClassModule("HUNTER")
M.uiTitle = "Hunter"
-- Rotate runs under Aegis_SBR:Preview without casting (see Pick/Later).
M.previewReady = true
M.uiHeight = 1326
M.meleeAutoAttack = false   -- managed here: Auto Shot (ranged) or Attack (melee)
M.autoAcquireTarget = false -- a ranged class should not auto-pull random mobs; pick targets

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end
local floor = math.floor

local MEND_PET_CD = 12   -- Mend Pet HoT lasts ~15s, refresh a little early
local PETCRIT_WINDOW = 4.0
local MANA_ASPECT_HYST = 15   -- swap back to the combat aspect this far above the low mark
-- Steady Shot weave margin: it must finish this far before the next Auto Shot
-- launches to clear the ~0.5s shot windup plus latency, so it never clips.
local STEADY_BUFFER = 0.5
local STEADY_CAST_DEFAULT = 1.0   -- Steady Shot's tooltip cast time, until measured live
-- Auto Shot is considered stalled if no shot has fired for the ranged swing plus
-- this margin (covers a Steady Shot pause); then we restart it automatically.
local AUTOSHOT_STALL = 2.0
-- Below this target HP%, a fresh Serpent Sting cannot tick its full duration, so
-- the rotation finishes with Arcane Shot instead of wasting the DoT.
local STING_HP_FLOOR = 30
-- After the sting is queued into Nampower's single-slot shot queue, hold the
-- lower-priority shots (Steady / Multi / Arcane) for about one shot-cycle so they
-- do not overwrite the still-pending sting before it fires. The sting debuff
-- cannot be read back, so without this the rotation cannot tell the sting is
-- already in flight and immediately competes for the one queue slot.
local STING_QUEUE_HOLD = 1.5
-- Arcane Shot is mana-inefficient, so the stationary filler only fires above this
-- mana% (it always fires while moving, when Auto Shot cannot).
local ARCANE_MANA_FLOOR = 50

-- The mana-regenerating aspect. Turtle teaches Aspect of the Viper at level 56;
-- below that there is nothing to swap to and this whole branch stays inert,
-- which KnowsSpell takes care of.
--
-- "Aspect of the Beast" used to sit in this list as a second guess at what
-- Turtle might call the mana aspect. It is a different spell entirely - it makes
-- the hunter untrackable and returns no mana at all - and it is learned at 32,
-- twenty-four levels before Viper. So from 32 onwards it was the first KNOWN
-- name in the list and became the mana aspect: mana dipped under the threshold,
-- Beast went up in place of Hawk or Wolf, and because it regenerates nothing the
-- mana never climbed back over the return threshold. Reported as the automatic
-- Hawk/Wolf choice having stopped working at level 32, which is exactly what it
-- was. A name nobody has confirmed does not belong in a list that is searched by
-- "first one known".
M.MANA_ASPECTS = { "Aspect of the Viper" }

-- Combat aspects the user can pick per stance (config dropdowns). Wolf is the
-- classic melee aspect and no longer blocks ranged on Turtle; Viper doubles as
-- the mana aspect, so picking it here simply means "keep Viper up in this
-- stance". Order here is only the dropdown display order.
M.COMBAT_ASPECTS = {
    "Aspect of the Hawk", "Aspect of the Wolf", "Aspect of the Viper",
    "Aspect of the Beast", "Aspect of the Monkey", "Aspect of the Wild",
}

-- Stings are mutually exclusive (one debuff slot). Durations are only the
-- reapply interval on clients without SuperWoW name resolution.
M.STINGS = { "Serpent Sting", "Scorpid Sting", "Viper Sting" }
local STING_DUR = {
    ["Serpent Sting"] = 15,
    ["Scorpid Sting"] = 20,
    ["Viper Sting"]   = 8,
}
-- Debuff icon fragments (classic 1.12 icons) for the stings and Hunter's Mark,
-- fed to the core's ScanTargetDebuff as its fallback when SuperWoW's id->name
-- resolution is unavailable or misses an id. Without a fragment those checks
-- always read "not up" on such clients, so the sting was blind-recast every
-- throttle interval (and an Undead target was wrongly learned as immune after
-- 2.5s, since the applied sting could never be seen). Exact-name matching
-- still wins whenever SuperWoW resolves the debuff.
local STING_TEX = {
    ["Serpent Sting"] = "Ability_Hunter_Quickshot",
    ["Scorpid Sting"] = "Ability_Hunter_CriticalShot",
    ["Viper Sting"]   = "Ability_Hunter_AimedShot",
    ["Hunter's Mark"] = "Ability_Hunter_SniperShot",
    -- Read off a live target with /sbr debug: Interface\Icons\spell_lacerate_1C.
    -- Without it the bleed was invisible on any client that cannot resolve
    -- debuff names, and upkeep fell back to a blind 15s timer.
    ["Lacerate"]      = "spell_lacerate",
}

-- The three specs. There is no hybrid on this server: Beast Mastery and
-- Marksmanship shoot, Survival fights in melee. The old ranged/melee/auto
-- playstyle words are accepted where they map cleanly.
M.specAlias = {
    bm = "bm", beast = "bm", beastmastery = "bm", beastmaster = "bm",
    mm = "mm", marks = "mm", marksman = "mm", marksmanship = "mm",
    surv = "surv", survival = "surv", sv = "surv", melee = "surv",
}
M.SPEC_NAME = { bm = "Beast Mastery", mm = "Marksmanship", surv = "Survival" }
-- Whether a spec fights in melee by default.
M.SPEC_MELEE = { bm = false, mm = false, surv = true }

M.stingAlias = {
    serpent = "Serpent Sting", ss = "Serpent Sting",
    scorpid = "Scorpid Sting", sco = "Scorpid Sting",
    viper = "Viper Sting", vs = "Viper Sting",
    smart = "Viper > Serpent", ["vs>ss"] = "Viper > Serpent",
    none = "",
}

M.spellAlias = {
    mark = "useHuntersMark", hm = "useHuntersMark",
    steady = "useSteadyShot", st = "useSteadyShot",
    arcane = "useArcaneShot", as = "useArcaneShot",
    multi = "useMultiShot", ms = "useMultiShot",
    aimed = "useAimedShot", aim = "useAimedShot",
    volley = "useVolley",
    raptor = "useRaptorStrike", rs = "useRaptorStrike",
    mongoose = "useMongooseBite", mb = "useMongooseBite",
    wingclip = "useWingClip", wc = "useWingClip",
    lacerate = "useLacerate", lac = "useLacerate",
    carve = "useCarve",
    opener = "useAimedOpener", aimedopener = "useAimedOpener",
    immolation = "useImmolationTrap", trap = "useImmolationTrap",
    explosive = "useExplosiveTrap",
    aspect = "useAspect",
    killcommand = "useKillCommand", kc = "useKillCommand",
    baited = "useBaitedShot",
    mend = "useMendPet",
}

-- Templates: starting presets, copied into the char's saved profiles once.
M.templates = {
    starter = {  -- usable from level 1: Auto Shot now, the rest auto-enable as
                 -- they are learned (Serpent Sting L4, Hunter's Mark/Arcane L6,
                 -- Aspect of the Hawk L10, Steady Shot L20). Auto mode picks
                 -- ranged vs melee by distance, which suits low-level pulls where
                 -- mobs close fast and you weave melee between shots.
        spec = "bm", rangeSwitch = true,
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = false,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false, useExplosiveTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk", meleeAspect = "Aspect of the Wolf",
        useManaAspect = false, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = false,
    },
    beastmastery = {
        spec = "bm", rangeSwitch = true,
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = true,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false, useExplosiveTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk", meleeAspect = "Aspect of the Wolf",
        useManaAspect = true, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 60,
        useKillCommand = true, useBaitedShot = true,
        -- Situational: when the tank's aggro is safe, or for a fear, sleep or
        -- execute phase. That is the player's call, not the rotation's.
        useBestialWrath = false,
        popCDs = false, autoCDElite = true,
    },
    marksmanship = {
        spec = "mm", rangeSwitch = true,
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = true,
        useAimedShot = true, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false, useExplosiveTrap = false,
        useRaptorStrike = false, useMongooseBite = false, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk", meleeAspect = "Aspect of the Wolf",
        useManaAspect = true, manaAspectPct = 25,
        petAttack = true, useMendPet = true, mendPetHp = 40,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = true,
    },
    survival = {  -- melee: strikes, bleed, traps in combat
        spec = "surv", rangeSwitch = true,
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = true,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = true, useExplosiveTrap = true,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false, useLacerate = true, useCarve = true,
        useAspect = true, rangedAspect = "Aspect of the Hawk", meleeAspect = "Aspect of the Wolf",
        useManaAspect = true, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = true,
    },
    melee = {  -- BM / melee weave
        spec = "bm", rangeSwitch = true,
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = false, useArcaneShot = false, useMultiShot = false,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false, useExplosiveTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false, useLacerate = true, useCarve = true,
        useAspect = true, rangedAspect = "Aspect of the Hawk", meleeAspect = "Aspect of the Wolf",
        useManaAspect = false, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 60,
        useKillCommand = true, useBaitedShot = true,
        popCDs = false, autoCDElite = true,
    },
}

-- The talent that lets traps be placed in combat. Name as the client shows it.
local TALENT_UNTAMED_TRAPPER = "Untamed Trapper"

function M:NormalizeProfile(c)
    local b = {
        spec = "bm", rangeSwitch = true,
        -- Bestial Wrath has its own switch rather than riding on "Pop
        -- cooldowns" with Rapid Fire: one is a hunter cooldown and the other is
        -- a pet cooldown, and a hunter without a pet out wants the first and not
        -- the second. ON by default, because it was part of that shared gate
        -- before and switching it off here would quietly take away a cooldown
        -- people already had.
        useBestialWrath = true,
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = false,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false, useExplosiveTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk", meleeAspect = "Aspect of the Wolf",
        useManaAspect = false, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        petTaunt = false, useLacerate = false, useCarve = false, useAimedOpener = false,
        useRapidFire = true,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = false,
        -- Hunter's Mark and the sting only on a target that lives long enough
        -- to repay them (see LivesFor). Off by default.
        useDebuffTTK = false, markMinTTK = 8, stingMinTTK = 12,
        -- The single macro decides single or AoE by the enemies the nameplates
        -- show (see PressAoe). Off: the two macros decide, as before.
        smartAoe = false, smartAoeN = 3,
        -- Survival: Lacerate ahead of Mongoose Bite (strong gear).
        lacerateFirst = false,
    }
    for k, v in pairs(b) do
        if c[k] == nil then c[k] = v end
    end
    -- Migration from the playstyle field. Melee was Survival; ranged and auto
    -- could be either shooting spec, so the talent tree decides, and the old
    -- auto playstyle becomes the per-spec range switch.
    if c.spec == nil and c.mode ~= nil then
        if c.mode == "melee" then c.spec = "surv"
        else c.spec = M:SpecFromTalents() end
        if c.rangeSwitch == nil then c.rangeSwitch = (c.mode == "auto") end
        c.mode = nil
    end
    if c.spec ~= "bm" and c.spec ~= "mm" and c.spec ~= "surv" then
        c.spec = M:SpecFromTalents() or "bm"
    end
    if c.rangeSwitch == nil then c.rangeSwitch = true end
    -- One sparse layer per spec, each with its own AoE set. A key present in
    -- the active spec's layer wins over the base; absent, the base applies.
    for _, sp in pairs({ "bm", "mm", "surv" }) do
        if type(c[sp]) ~= "table" then c[sp] = {} end
        if type(c[sp].aoe) ~= "table" then c[sp].aoe = {} end
    end
    if type(c.sting) ~= "string" then c.sting = "Serpent Sting" end
    if type(c.rangedAspect) ~= "string" then c.rangedAspect = "Aspect of the Hawk" end
    if type(c.meleeAspect) ~= "string" then c.meleeAspect = "Aspect of the Wolf" end
    -- Two-threshold mana-aspect swap: drop to the mana aspect below manaAspectPct,
    -- swap back to the combat aspect at manaAspectBackPct. Older profiles used a
    -- fixed +MANA_ASPECT_HYST hysteresis, so default the back mark to that to
    -- preserve their existing behavior exactly.
    if c.manaAspectBackPct == nil then c.manaAspectBackPct = (c.manaAspectPct or 30) + MANA_ASPECT_HYST end
    return c
end

-- Only an explicitly chosen sting the character cannot cast is flagged; every
-- other ability degrades gracefully through KnowsSpell while leveling.
-- Everything in the hunter kit degrades gracefully through KnowsSpell in the
-- rotation, so nothing here is strictly required. In particular a configured
-- sting that is not learned yet is NOT flagged: Serpent Sting is level 4, so
-- a level 1-3 hunter (or any sting picked before it is trained) should still
-- read as a clean, usable profile and simply Auto Shot until the sting lands.
-- This mirrors the druid, which does not flag a not-yet-learned form.
function M:ProfileValidity(cfg)
    return true, {}
end

function M:AvailableStingsOf()
    local out = {}
    for i = 1, table.getn(self.STINGS) do
        if self:KnowsSpell(self.STINGS[i]) then table.insert(out, self.STINGS[i]) end
    end
    return out
end

-- The combat aspects this hunter can actually cast (config dropdowns), so a
-- level 10 hunter only sees Hawk until the rest are trained.
function M:AvailableAspectsOf()
    local out = {}
    for i = 1, table.getn(self.COMBAT_ASPECTS) do
        if self:KnowsSpell(self.COMBAT_ASPECTS[i]) then table.insert(out, self.COMBAT_ASPECTS[i]) end
    end
    return out
end

function M:KnownManaAspect()
    for i = 1, table.getn(self.MANA_ASPECTS) do
        if self:KnowsSpell(self.MANA_ASPECTS[i]) then return self.MANA_ASPECTS[i] end
    end
    return nil
end

-- ============================================================
-- Auto Shot upkeep. Auto Shot is an auto-repeat toggle: casting it while it
-- is already running turns it OFF. It is only (re)started when not repeating.
-- IsAutoRepeatAction sees it on an action bar; when it is not, an assumed-on
-- flag per target prevents toggling it off by accident.
--
-- The start itself goes through Aegis_SBR:StartRepeating, which cannot turn the
-- shot off where ClassicAPI provides a start-only cast. The detection above is
-- unchanged: it still decides WHETHER to send, the wrapper only removes the one
-- outcome in which sending was wrong. Suppress-only, per the regression rule.
-- ============================================================
function M:AutoShotting()
    local slot = self.autoShotSlot
    if slot and IsAutoRepeatAction(slot) then return true end
    for s = 1, 120 do
        if IsAutoRepeatAction(s) then self.autoShotSlot = s; return true end
    end
    return false
end

-- Returns true if it issued an Auto Shot cast this press, so the caller can make
-- that the press's action (vanilla will not also land a GCD cast in the same
-- frame - this is why Hunter's Mark used to lose to a same-press Auto Shot).
-- Stall handling: with SuperWoW we know the exact last-shot time, so a shot seen
-- within the last swing-and-a-bit means it is still firing; a stale time means it
-- stalled and we restart it. Without event data we fall back to an assume-on flag
-- that re-pokes periodically, so it can never get permanently stuck needing a
-- manual target swap (the old bug).
function M:EnsureAutoShot()
    if self:AutoShotting() then
        self:Later(function() self.autoShotOn = true; self.autoShotT = GetTime() end)
        return false
    end
    local now = GetTime()
    -- Only trust the last-shot time when it was a shot at THIS target. A recent
    -- shot at the mob you just tabbed away from says nothing about this one.
    local sameTarget = (self.lastAutoShotAt == nil) or (self.lastAutoShotAt == self:TargetId())
    if sameTarget and self.lastAutoShot and self.lastAutoShot > 0 then
        if (now - self.lastAutoShot) < (self:RangedSpeed() + AUTOSHOT_STALL) then
            self:Later(function() self.autoShotOn = true end)
            return false
        end
    else
        local id = self:TargetId()
        if self.autoShotOn and self.autoShotTarget == id
            and (now - (self.autoShotT or 0)) < (self:RangedSpeed() + AUTOSHOT_STALL) then
            return false
        end
    end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = "Auto Shot"
        p.reason = "restarting the shot"
        return true
    end
    if Aegis_SBR.StartRepeating then Aegis_SBR:StartRepeating("Auto Shot") else CastSpellByName("Auto Shot") end
    self.autoShotOn = true
    self.autoShotTarget = self:TargetId()
    self.autoShotT = now
    return true
end

-- Everything this module sends goes through one of these two, and both refuse
-- what cannot be paid for.
--
-- `Pick` and `PickQueue` in the core report success on "known and learned", not
-- on "accepted" - which is correct for them, since most classes check the cost
-- at the decision. This module did not, and the shape of that mistake is worse
-- here than elsewhere: Hunter's Mark LEADS the rotation and the mana-free Auto
-- Shot sits four steps below it. A hunter near empty therefore spent every press
-- on a cast that never happened and never reached the one attack that still
-- works at zero mana - reported as "at low mana neither ranged nor melee auto
-- attack starts on a target switch".
--
-- Gated here rather than at the call sites because there are twenty of them and
-- a new one would eventually forget. The same argument as the warlock's channel
-- gate.
--
-- An unreadable cost answers YES (see CanAfford), so a tooltip that failed to
-- populate can never lock a step out.
-- A press that reaches a cast and is turned away on cost must say so in the
-- log, or "it just waits" cannot be told apart from a rotation that decided
-- nothing. Once per spell per two seconds, so a mana-starved fight does not
-- drown the log.
function M:TraceCost(name)
    if not self:Tracing() then return end
    local now = GetTime()
    if not self.costTraced then self.costTraced = {} end
    if (self.costTraced[name] or 0) > now - 2.0 then return end
    self.costTraced[name] = now
    self:Trace("skip " .. name .. " (cost)")
end

function M:Pick(name, reason)
    if not Aegis_SBR:CanAfford(name) then self:TraceCost(name); return false end
    return Aegis_SBR.Pick(self, name, reason)
end

-- Queue a shot through SuperWoW/Nampower so the weave lands without clipping
-- the Auto Shot in progress; falls back to a direct cast without the queue.
function M:Queue(name, reason)
    if not self:KnowsSpell(name) then return false end
    if not Aegis_SBR:CanAfford(name) then self:TraceCost(name); return false end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name; p.reason = reason; p.queue = true
        return true
    end
    Aegis_SBR:NoteSpellCast(name)
    -- Every send in the log, with its reason: the per-press line says what the
    -- rotation saw, this says what it did with it.
    if self:Tracing() then self:Trace("-> " .. name .. " (" .. (reason or "") .. ")" .. (QueueSpellByName and " queued" or "")) end
    if QueueSpellByName then QueueSpellByName(name) else CastSpellByName(name) end
    return true
end

-- Auto Shot fires on the ranged swing timer; UnitRangedDamage's first return is
-- that interval and already includes ranged haste.
function M:RangedSpeed()
    local s = UnitRangedDamage and UnitRangedDamage("player")
    if s and s > 0 then return s end
    return 2.8   -- sane fallback if the API is unavailable
end

-- Steady Shot weave gate. Steady Shot has a cast time and, with Nampower,
-- casting it pauses the Auto Shot swing; firing it every press chains Steady
-- Shots and starves Auto Shot. So we weave exactly one Steady per swing, in the
-- window right after a shot, so it finishes before the next shot fires.
--
-- Precise path (SuperWoW): use the real last-shot time, but ONLY while it is
-- fresh. If it goes stale (Auto Shot paused, or a shot event was missed) we must
-- NOT keep computing a negative window - that locked the gate to "wait" forever,
-- which is why Steady stopped weaving. Stale -> fall back to the interval gate.
-- The post-shot room is clamped so even a fast ranged weapon still gets a weave.
function M:SteadyReady()
    local now   = GetTime()
    local speed = self:RangedSpeed()
    if self.lastAutoShot and self.lastAutoShot > 0 and (now - self.lastAutoShot) < (speed + 1.0) then
        -- One Steady per shot cycle: if we already wove since the last Auto Shot
        -- (steadyT is newer than lastAutoShot), hold until the next shot fires.
        if (self.steadyT or 0) >= self.lastAutoShot then return false end
        local cast = (self.steadyCastDur and self.steadyCastDur > 0) and self.steadyCastDur or STEADY_CAST_DEFAULT
        local room = speed - cast - STEADY_BUFFER
        if room < 0.3 then room = 0.3 end           -- always allow a brief post-shot weave
        return (now - self.lastAutoShot) <= room     -- only early in the swing window
    end
    return (now - (self.steadyT or 0)) >= speed       -- stale/unknown: one per swing
end

-- Does the target live long enough for a debuff that needs `need` seconds?
--
-- Hunter's Mark and the sting cost mana every pull, and on trash that dies in
-- ten seconds most of it is thrown away: a log had 154 Marks and 187 stings in
-- one session, a third of them on mobs already under 40%, while Steady Shot
-- was skipped for mana forty times and Arcane Shot never went out.
--
-- The time-to-kill estimate answers once it has three seconds of this target.
-- Before that, an untouched target (full health: the pull, a fresh mob) is
-- worth it as before; one already losing health waits for the estimate, and
-- the rotation carries on with the shots meanwhile.
function M:LivesFor(cfg, need)
    if not cfg.useDebuffTTK or not need or need <= 0 then return true end
    local ttk = Aegis_SBR:TargetTTK()
    if ttk then return ttk >= need end
    return self:TargetHPPct() >= 100
end

-- May a filler go out now without breaking the weave?
--
-- The rotation is Auto Shot and Steady Shot without clipping; everything else
-- is filler. A filler may move the next Steady Shot, not break it: its global
-- cooldown has to end while the Steady after the next Auto Shot can still
-- finish before the Auto Shot after that - the same window SteadyReady opens
-- for the weave. And a filler with a cast bar (Multi-Shot's is short) may not
-- run across the moment of the next Auto Shot, which it would delay.
--
-- The first version asked for a whole global cooldown of room before the next
-- Auto Shot. With Steady's own global cooldown in the same cycle that never
-- fits a swing under three seconds, and fillers were almost never used.
--
-- Unknown or stale shot timing (moving, out of range) answers yes: there is no
-- weave to protect then.
local FILLER_GCD = 1.5
-- Multi-Shot's cast bar on this client: half a second (measured in play).
local MULTI_CAST = 0.5
-- Without Steady Shot in the rotation there is no weave to protect: an instant
-- cannot clip the Auto Shot, and only a cast bar across its moment could delay
-- it. A player with Steady Shot switched off still got the room test, and with
-- a fast bow it answered no nearly all the time.
function M:FillerRoom(castTime, cfg)
    local last = self.lastAutoShot
    local steadyUsed = not cfg or (cfg.useSteadyShot and self:KnowsSpell("Steady Shot"))
    if not (last and last > 0) then return true end
    local now = GetTime()
    local speed = self:RangedSpeed()
    if now - last >= speed + 1.0 then return true end
    local nextAuto = last + speed
    castTime = castTime or 0
    if castTime > 0 and now < nextAuto and now + castTime > nextAuto - 0.1 then return false end
    if not steadyUsed then return true end
    local cast = (self.steadyCastDur and self.steadyCastDur > 0) and self.steadyCastDur or STEADY_CAST_DEFAULT
    local window = speed - cast - STEADY_BUFFER
    if window < 0.3 then window = 0.3 end
    return now + FILLER_GCD <= nextAuto + window
end

-- Is this press Steady Shot's? Then nothing below it may take the global.
-- Not while moving: Steady has a cast time and cannot go out, and holding the
-- sting for it would leave the press to nothing.
function M:SteadyDueNow(cfg)
    if Aegis_SBR:Moving() then return false end
    return cfg.useSteadyShot and self:KnowsSpell("Steady Shot") and self:SteadyReady() and true or false
end

-- Which weave path is live, for the trace line.
function M:WeaveSource()
    return (self.lastAutoShot and self.lastAutoShot > 0) and "precise" or "interval"
end

-- ============================================================
-- Debuff upkeep helper. Returns true if a cast was issued this press.
-- Detection prefers the exact spell name (SuperWoW), with a per-target
-- throttle so the instant is applied once and not re-queued before it
-- registers. Without name resolution, `interval` is the blind reapply timer.
-- ============================================================
M.debuffThrottle = {}
-- Debuffs where ANY hunter's copy is as good as ours, so the caster is
-- irrelevant. Hunter's Mark does not stack and its attack-power bonus helps
-- every attacker regardless of who applied it - re-marking over a raid mate's
-- mark is pure waste. Lacerate and the stings are the opposite: they are our
-- own damage and another hunter's copy says nothing about ours, so they are NOT
-- listed here and stay owner-filtered.
--
-- RANK IS DELIBERATELY IGNORED (user decision, 2026-08-18). A higher-rank Mark
-- does overwrite a lower one, so in a mixed-rank group re-marking could be an
-- upgrade - but that can only happen while levelling, never at 60 where every
-- hunter has the top rank. "Any Mark on the target is enough" is the rule; do
-- not add rank comparison without being asked.
local SHARED_DEBUFF = {
    ["Hunter's Mark"] = true,
}

-- Is this debuff on the target, according to EITHER detection path?
-- The old path (SuperWoW ids / icon fragment) answers "up or not"; ClassicAPI
-- answers with a real expiry and, where it matters, a caster. Either saying yes
-- is enough - both are positive evidence, and a miss on one is exactly the case
-- the other exists to cover.
-- Is the debuff we can see OURS? Shared ones never ask - anybody's Hunter's Mark
-- is as good as ours and re-marking over it is waste, which is what SHARED_DEBUFF
-- above says. The stings and Lacerate are the opposite: they are our own damage,
-- another hunter's copy says nothing about ours, and reading theirs as ours means
-- applying nothing at all for as long as they keep it up.
function M:DebuffOwned(name)
    if SHARED_DEBUFF[name] then return true end
    return Aegis_SBR:DebuffMine(name, self:TargetId())
end

function M:DebuffUpAny(name)
    if self:TargetDebuffUp(name, STING_TEX[name]) and self:DebuffOwned(name) then return true end
    if not Aegis_SBR.TargetDebuffRemaining then return false end
    if not SHARED_DEBUFF[name] and Aegis_SBR:TargetDebuffMine(name) == false then
        return false                      -- someone else's, and ownership matters here
    end
    local remain = Aegis_SBR:TargetDebuffRemaining(name)
    return (remain and remain > 0) and true or false
end

-- May Kill Command be tried right now? Turtle's tooltip: it can only be used
-- after the Hunter lands a critical strike on the target. Sent on cooldown
-- alone it was refused on every press of a fight - hundreds of "You can't do
-- that yet" lines in one log. So: armed by a crit of ours landing AFTER the
-- last send, whether that send went through or was refused. A send consumes
-- the crit; a refusal means there was none to consume. Either way the next
-- attempt waits for the next crit, and a hunter's crits are not rare.
--
-- "On the target" is the tooltip's condition, and it matters: Multi-Shot hits
-- three mobs, and a crit on a neighbour - or on the mob before this one - armed
-- it all the same. A log had eight of twenty-six sends refused that way. The
-- crit line must name the current target (see the frame at the bottom).
--
-- The combat-log reading missed most crits: a log had 33 Kill Commands in
-- twenty minutes of fighting, gaps of one to five minutes between them, and
-- the player pressing it by hand while it was lit. The button's own state is
-- what the client lights, so it is read first: Kill Command's slot on an
-- action bar (found by its icon, macros excluded) and IsUsableAction on it.
-- Should that ever answer yes to a send the client then refuses as "not yet",
-- the button reading is dropped for the session and the crit lines decide.
-- The action-bar slot of a spell the client lights only after a trigger (Kill
-- Command, Lacerate: "after a critical strike on the target"), found by its
-- icon with macros excluded, or nil. Per spell: slot, last scan, and whether
-- the reading has been dropped for the session.
M.reactive = {}

function M:ReactiveSlot(spell)
    local r = self.reactive[spell]
    if not r then r = {}; self.reactive[spell] = r end
    if r.bad then return nil end
    local sb = Aegis_SBR:FindSpellSlot(spell)
    local tex = sb and GetSpellTexture(sb, BOOKTYPE_SPELL)
    if not tex then return nil end
    local s = r.slot
    if s and GetActionTexture(s) == tex and not GetActionText(s) then return s end
    local now = GetTime()
    if (r.scanAt or 0) > now - 5 then return nil end
    r.scanAt = now
    r.slot = nil
    for i = 1, 120 do
        if GetActionTexture(i) == tex and not GetActionText(i) then r.slot = i; return i end
    end
    return nil
end

-- Is the triggered spell usable, by its button? true/false when the button
-- can be read, nil when it cannot (not on a bar, or dropped) - the caller then
-- falls back to the crit lines.
--
-- A send refused as "You can't do that yet" although the button said yes is
-- counted; two of them drop the button reading for the session. Nothing else
-- counts: a mob that died under the send, or "Ability is not ready yet" from
-- the cooldown answering a second send, says nothing about the button.
-- One second after a send it answers no: the button stays lit until the
-- client has taken the cast.
function M:ReactiveReady(spell, sentAt)
    local r = self.reactive[spell]
    if r and r.byButton and sentAt and Aegis_SBR.SpellRefusedAnySince
        and Aegis_SBR:SpellRefusedAnySince(spell, sentAt) and (r.checked or 0) < sentAt then
        r.checked = sentAt
        local why = Aegis_SBR.spellRefusedMsg and Aegis_SBR.spellRefusedMsg[spell] or ""
        if string.find(why, "can't do that yet", 1, true) and r.litFor == self:TargetId() then
            r.refusals = (r.refusals or 0) + 1
            if r.refusals >= 2 then r.bad = true end
        end
    end
    local slot = self:ReactiveSlot(spell)
    r = self.reactive[spell]
    if not slot then r.byButton = false; return nil end
    r.byButton = true
    -- The button stays lit across a target change, but the trigger was a crit
    -- on the OLD target: a log had the mob die, the next one targeted, the lit
    -- button sent - "You can't do that yet" - and two of those dropped the
    -- button reading for the rest of the session. So the light counts for the
    -- target it came on, and on another target only once a crit has named
    -- that one (the crit lines) after the light.
    local lit = IsUsableAction(slot) and true or false
    local tid = self:TargetId()
    local now = GetTime()
    if lit and not r.lit then r.litFor = tid; r.litAt = now end
    r.lit = lit
    if not lit then return false end
    if sentAt and now - sentAt < 1.0 then return false end
    if r.litFor ~= tid then
        local tname = UnitName("target")
        if not (M.lastCritName and M.lastCritName == tname and (M.lastCritAt or 0) > (r.litAt or 0)) then
            return false
        end
        r.litFor = tid
    end
    return true
end

-- The combat-log reading missed most crits: a log had 33 Kill Commands in
-- twenty minutes of fighting and the player pressing it by hand while it was
-- lit. The button is read first (ReactiveReady); the crit lines are the
-- fallback.
function M:KillCommandArmed()
    local b = self:ReactiveReady("Kill Command", self.killCommandSentAt)
    if b ~= nil then return b end
    if (M.lastCritAt or 0) <= (self.killCommandSentAt or 0) then return false end
    return M.lastCritName ~= nil and M.lastCritName == UnitName("target")
end

-- For the trace: which reading decides, and what it says.
function M:KillCommandText()
    local armed = self:KillCommandArmed()
    local r = self.reactive["Kill Command"]
    return ((r and r.byButton) and "btn" or "log") .. (armed and "+" or "-")
end

-- Debuffs this client has actually been seen to read back off a target, by
-- name. Same idea and same reason as stingSeen below: it is a property of the
-- CLIENT (does SuperWoW resolve the name, does the icon fragment match, does
-- ClassicAPI answer), not of any one mob, so it is kept for the session.
M.debuffSeen = {}

-- May Lacerate be tried right now? Yes once a crit of ours has landed since the
-- last time the client refused it. The refusal is read the same way the throttle
-- reads it: any refusal naming Lacerate after the send.
function M:LacerateArmed()
    -- The button first, as for Kill Command: a log had 22 of 215 Lacerates
    -- refused as "not yet" on the crit-line reading.
    local b = self:ReactiveReady("Lacerate", self.lacerateSentAt)
    if b ~= nil then return b end
    local sent = self.lacerateSentAt
    if sent and Aegis_SBR.SpellRefusedAnySince and Aegis_SBR:SpellRefusedAnySince("Lacerate", sent) then
        self.lacerateDisarmedAt = sent
        self.lacerateSentAt = nil
    end
    local dis = self.lacerateDisarmedAt
    if not dis then return true end
    return (M.lastCritAt or 0) > dis
end

-- Volley is aimed at the ground, and the placement - under the mouse, only
-- while the mouse is on an enemy - is the core's (Aegis_SBR:CastAtMouse),
-- shared with the other classes' ground spells.
function M:CastVolley()
    return self:CastAtMouse("Volley", "AoE, under the mouse")
end

function M:MaintainDebuff(name, interval)
    if not self:KnowsSpell(name) then return false end
    if self:DebuffUpAny(name) then
        -- Reading it once is the proof that reading works.
        self:Later(function() self.debuffSeen[name] = true end)
        return false
    end
    local id = self:TargetId()
    local rec = self.debuffThrottle[name]
    local now = GetTime()
    -- A throttle stamped on a cast the CLIENT threw away is worse than no
    -- throttle: it says "just applied" about something that never left the bow.
    -- Out of range, no line of sight and "needs to be in front of you" all
    -- arrive as an error message rather than in the combat log, so the resist /
    -- miss handler at the bottom of this file never sees them.
    if rec and Aegis_SBR.SpellRefusedSince and Aegis_SBR:SpellRefusedSince(name, rec.t) then
        self.debuffThrottle[name] = nil
        rec = nil
    end
    -- How long to wait before trying again - the same correction the stings
    -- already carry.
    --
    -- The full duration is only the right answer on a client that CANNOT read
    -- the debuff back off the target: there the timer is the whole knowledge.
    -- Once it has been read once, the check at the top of this function is the
    -- authority, and waiting out the duration after it reports "not up" is
    -- simply wrong. Hunter's Mark waits 110 seconds, so a first application that
    -- missed, was refused or never left the bow left the target unmarked for
    -- most of two minutes - reported from play as exactly that.
    --
    -- All that is still needed is the beat an applied debuff takes to register.
    local wait = interval or 3
    if self.debuffSeen[name] then wait = STING_QUEUE_HOLD end
    if rec and rec.id == id and rec.t and (now - rec.t) <= wait then
        return false
    end
    -- Queued, not cast outright.
    --
    -- The comment on MaintainSting below has described this bug since it was
    -- written - and named this function while doing it: dispatching through the
    -- instant CastSpellByName path lets the client drop the cast whenever a
    -- global cooldown is up, which stamps the reapply throttle on a cast that
    -- never left. For Hunter's Mark that throttle is 110 seconds, and the sting
    -- is gated on the mark being up, so ONE dropped cast silently costs both for
    -- most of two minutes.
    --
    -- That is exactly what a target switch under a held macro produces: the
    -- press lands mid-GCD from the cast aimed at the previous target. Reported
    -- as "switching target by tab or mouse often leaves Hunter's Mark and the
    -- DoT unapplied".
    if not self:Queue(name, "debuff missing") then return false end
    self:Later(function()
        self.debuffThrottle[name] = { id = id, t = now }
        Aegis_SBR:NoteDebuffApplied(id, name, interval)
    end)
    return true
end

-- Stings this client has actually been seen to read back off a target. Kept for
-- the session, because it is a property of the CLIENT (SuperWoW name resolution,
-- or an icon fragment that matches), not of any one mob.
M.stingSeen = {}

-- Sting upkeep. Identical bookkeeping to MaintainDebuff, but the stings are
-- ranged-weapon shots, so they must go out through the Nampower shot queue
-- (QueueSpellByName) exactly like Steady / Arcane / Multi-Shot. Dispatching a
-- sting through the instant CastSpellByName path (as MaintainDebuff does for the
-- melee/targeting debuffs) lets Nampower drop it whenever a global cooldown is
-- up, which silently burns the reapply throttle and the sting never fires.
function M:MaintainSting(name, interval)
    if not self:KnowsSpell(name) then return false end
    if self:TargetDebuffUp(name, STING_TEX[name]) then
        -- Reading it at all proves reading works on this client, whoever it
        -- belongs to - that is what stingSeen records.
        self:Later(function() self.stingSeen[name] = true end)
        -- Only OUR sting means there is nothing to do here.
        if self:DebuffOwned(name) then return false end
    end
    -- ClassicAPI second opinion, and it may ONLY ever say "do not cast".
    --
    -- This direction matters and is the whole lesson of the 2026-08-18 Hunter
    -- regression: the first attempt let ClassicAPI SHORTEN the retry throttle
    -- while the check above still decided whether to cast. Whenever the two
    -- detections disagreed the sting was re-queued every 1.5s, and since a sting
    -- is a ranged shot through the Nampower queue, it clipped Auto Shot on every
    -- press - the exact starvation this module's header warns about.
    --
    -- Read as an authority for "still on the target" instead, the change can
    -- only ever SUPPRESS a cast, never add one, so it cannot starve the shot
    -- timer no matter how the two paths disagree. It fixes the disagreement in
    -- the right direction: a sting the old detection cannot read is no longer
    -- re-applied on top of itself.
    if Aegis_SBR.TargetDebuffRemaining then
        local mine = Aegis_SBR:TargetDebuffMine(name)
        -- mine == false is another hunter's sting and says nothing about ours.
        -- mine == nil is "cannot tell" and is accepted, as elsewhere.
        if mine ~= false then
            local remain = Aegis_SBR:TargetDebuffRemaining(name)
            if remain and remain > 0 then
                self:Later(function() self.stingSeen[name] = true end)
                return false
            end
        end
    end
    local id = self:TargetId()
    local rec = self.debuffThrottle[name]
    local now = GetTime()
    -- A throttle stamped on a cast the CLIENT threw away is worse than no
    -- throttle: it says "just applied" about something that never left the bow.
    -- Out of range, no line of sight and "needs to be in front of you" all
    -- arrive as an error message rather than in the combat log, so the resist /
    -- miss handler at the bottom of this file never sees them.
    if rec and Aegis_SBR.SpellRefusedSince and Aegis_SBR:SpellRefusedSince(name, rec.t) then
        self.debuffThrottle[name] = nil
        rec = nil
    end
    -- How long to wait before trying again.
    --
    -- The sting's full duration is only the right answer on a client that cannot
    -- read the sting back off the target - there the timer IS the whole
    -- knowledge. Once it has been read once, the debuff check above is the
    -- authority, and waiting fifteen more seconds after it reports "not up" is
    -- simply wrong: a shot that missed or was resisted then goes un-reapplied for
    -- the sting's entire duration. All that is still needed is the moment an
    -- applied debuff takes to register, which is what STING_QUEUE_HOLD measures -
    -- and it is the same beat the queue hold below already waits out.
    local wait = interval or 3
    if self.stingSeen[name] then wait = STING_QUEUE_HOLD end
    if rec and rec.id == id and rec.t and (now - rec.t) <= wait then
        return false
    end
    if not self:Queue(name, "sting missing") then return false end
    self:Later(function()
        self.debuffThrottle[name] = { id = id, t = now }
        Aegis_SBR:NoteDebuffApplied(id, name, STING_DUR[name])
    end)
    return true
end

-- Trace decoration: how much of a reapply throttle is left, or "-" when none is
-- standing. Purely diagnostic.
function M:ThrottleText(name)
    local rec = name and self.debuffThrottle[name]
    if not rec or not rec.t or rec.id ~= self:TargetId() then return "-" end
    return string.format("%.0fs", GetTime() - rec.t)
end

-- Trace decoration: what ClassicAPI reports for this sting, or "" when it has
-- nothing to say (absent, unknown timing, not our sting). Purely diagnostic -
-- nothing reads this to make a decision.
function M:StingRemainText(name)
    if not Aegis_SBR.TargetDebuffRemaining then return "" end
    if Aegis_SBR:TargetDebuffMine(name) == false then return "(other's)" end
    local remain = Aegis_SBR:TargetDebuffRemaining(name)
    if not remain then return "" end
    return string.format("(%.1fs)", remain)
end

-- ============================================================
-- Sting immunity. Serpent / Scorpid / Viper Sting are Poison-school effects, so
-- they do not land on poison-immune targets and otherwise re-fire on a wasted
-- "immune" cast every cycle. Two layers:
--   * by creature type (deterministic): Mechanical and Elemental are immune to
--     Poison on 1.12, so the sting is skipped outright - zero wasted casts.
--     Undead is NOT blanket-immune (only specific undead are), so it is not
--     type-blocked; those are caught by the learn layer instead.
--   * learned (per target, this combat): if the sting was cast but never showed
--     up on the target, mark that mob immune and stop re-casting. This catches
--     the immune undead and immune bosses (e.g. Baron Aquanis) automatically
--     after a single cast.
-- Both are cleared when leaving combat (see the event frame at the bottom).
-- ============================================================
M.STING_IMMUNE_TYPES = { Mechanical = true, Elemental = true }
M.stingImmune = {}   -- [targetGUID] = true, learned for the current combat
M.stingTry = nil     -- { guid, t, name }: a sting application waiting to confirm

-- Immunity learned per creature TEMPLATE, kept across sessions in AegisDB.
--
-- The GUID table above forgets everything when combat ends, which means the same
-- lesson is re-bought with a wasted sting on the next Baron Aquanis, and the one
-- after that. Immunity is a property of the KIND of mob, not of the corpse in
-- front of you, so with ClassicAPI's creature-template id it is worth keeping.
--
-- Deliberately still opt-in on evidence, not on a hardcoded list: the same
-- single-cast proof as before decides, this only changes how long the answer is
-- remembered. Types that are ALWAYS immune (Mechanical/Elemental) stay a type
-- check and never enter this table.
local IMMUNE_MEMORY_MAX = 200

function M:ImmuneMemory()
    if not AegisDB then return nil end
    if type(AegisDB.stingImmuneIDs) ~= "table" then AegisDB.stingImmuneIDs = {} end
    return AegisDB.stingImmuneIDs
end

function M:RememberImmune(id)
    if not id then return end
    local mem = self:ImmuneMemory()
    if not mem then return end
    if mem[id] then return end
    -- Bounded so a long-lived profile cannot grow this without limit. Immune
    -- mobs are rare enough that hitting the cap means something is wrong, so it
    -- is cleared wholesale rather than pruned cleverly - relearning costs one
    -- sting per type, which is exactly what this feature already accepts.
    local n = 0
    for _ in pairs(mem) do n = n + 1 end
    if n >= IMMUNE_MEMORY_MAX then
        AegisDB.stingImmuneIDs = {}
        mem = AegisDB.stingImmuneIDs
    end
    mem[id] = true
end

-- /sbr immune clear empties this memory as well (see the core).
function M:ClearLearnedImmunity()
    if AegisDB then AegisDB.stingImmuneIDs = {} end
    self.stingImmune = {}
end

function M:KnownImmuneType()
    local id = Aegis_SBR.UnitCreatureID and Aegis_SBR:UnitCreatureID("target")
    if not id then return false end
    local mem = self:ImmuneMemory()
    return (mem and mem[id]) and true or false
end

-- Read-only: is a sting blocked on the current target right now? No side effects
-- (used by the rotation gate and the trace line).
M.LEARN_IMMUNE = { ["Serpent Sting"] = true }
function M:StingImmuneNow()
    local ct = UnitCreatureType and UnitCreatureType("target")
    if ct and self.STING_IMMUNE_TYPES[ct] then return true end
    -- The core's account-wide table (/sbr immune), by mob name.
    if Aegis_SBR.KnownImmune and Aegis_SBR:KnownImmune("Serpent Sting") then return true end
    -- Learned per mob type first: it survives the fight, so this is the check
    -- that saves the wasted cast on every later specimen.
    if self:KnownImmuneType() then return true end
    local _, guid = UnitExists("target")
    return (guid and self.stingImmune[guid]) and true or false
end

-- Full check used by the rotation: the read-only test above, plus learning from
-- a pending application that never landed (the immune undead / boss case).
function M:StingBlocked(sting)
    if self:StingImmuneNow() then return true end
    local _, guid = UnitExists("target")
    if guid and self.stingTry and self.stingTry.guid == guid and self.stingTry.name == sting then
        if self:TargetDebuffUp(sting, STING_TEX[sting]) then
            self.stingTry = nil                  -- it landed; stop watching
        elseif (GetTime() - self.stingTry.t) > 2.5 then
            -- Cast but never seen on the target. Only treat that as immunity on a
            -- type that can actually be poison-immune: Undead. (Mechanical and
            -- Elemental are already hard-blocked above.) On a Beast, Humanoid, etc.
            -- a missing debuff means the scan can't read this sting, NOT that the
            -- mob is immune - so do not flag it; the blind reapply timer in
            -- MaintainDebuff keeps the sting up on its own.
            local ct = UnitCreatureType and UnitCreatureType("target")
            self.stingTry = nil
            if ct == "Undead" then
                self.stingImmune[guid] = true     -- genuinely immune undead
                -- and remember the TYPE, so the next one costs nothing
                self:RememberImmune(Aegis_SBR.UnitCreatureID
                    and Aegis_SBR:UnitCreatureID("target"))
                return true
            end
        end
    end
    return false
end

-- Mend Pet due? The switch, the spell, a LIVING pet under the line, and the
-- throttle - which is cleared when the client refused the last one (out of
-- range, no line of sight): stamped on a cast that never happened, it held
-- the heal back for twelve seconds, which looked like "sometimes it works,
-- sometimes not".
function M:MendPetDue(cfg)
    if not cfg.useMendPet or not self:KnowsSpell("Mend Pet") then return false end
    if not UnitExists("pet") or UnitIsDead("pet") then return false end
    if self.mendPetT and Aegis_SBR.SpellRefusedSince and Aegis_SBR:SpellRefusedSince("Mend Pet", self.mendPetT) then
        self.mendPetT = nil
    end
    if self:PetHPPct() >= (cfg.mendPetHp or 50) then return false end
    return (GetTime() - (self.mendPetT or 0)) > MEND_PET_CD
end

-- With nothing attackable targeted the rotation does not run at all - and the
-- pet was then never healed, out of combat least of all: reported as Mend Pet
-- working only sometimes. The press does this one thing then.
function M:Prebuff(cfg)
    cfg = self:SpecConfig(cfg)
    if not self:MendPetDue(cfg) then return false end
    if self:Pick("Mend Pet", "pet needs healing") then
        local now = GetTime()
        self:Later(function() self.mendPetT = now end)
        return true
    end
    return false
end

function M:PetHPPct()
    if not UnitExists("pet") then return 100 end
    local mx = UnitHealthMax("pet")
    if mx and mx > 0 then return UnitHealth("pet") / mx * 100 end
    return 100
end

-- ============================================================
-- Auto mode: pick ranged vs melee by distance to the target. InMeleeRange uses
-- CheckInteractDistance (~10yd), the closest proxy vanilla offers. A short
-- "stickiness" keeps us in melee for a beat after the last in-range reading so
-- the mode does not flicker when the target jitters at the boundary.
-- ============================================================
function M:AutoMelee()
    local now = GetTime()
    if self:InMeleeRange() then
        self.meleeStickUntil = now + 0.75
        return true
    end
    return now < (self.meleeStickUntil or 0)
end

-- ============================================================
-- Smart pet taunt. If the target is hitting the player (or someone other than
-- the pet), the pet has lost aggro; command its Growl to pull it back. Pet
-- abilities live on the pet action bar, so we scan for Growl, cache the slot,
-- and cast it - throttled, since Growl has its own cooldown.
-- ============================================================
function M:PetLostAggro()
    if not UnitExists("pet") then return false end
    if not UnitExists("targettarget") then return false end
    return UnitIsUnit("targettarget", "player")
end

function M:PetGrowlSlot()
    local slot = self.petGrowlSlot
    if slot then
        local nm = GetPetActionInfo(slot)
        if nm == "Growl" then return slot end
    end
    for i = 1, 10 do
        if GetPetActionInfo(i) == "Growl" then self.petGrowlSlot = i; return i end
    end
    return nil
end

function M:PetGrowl()
    local now = GetTime()
    if (now - (self.petGrowlT or 0)) < 2.0 then return end   -- throttle, Growl has a CD
    local slot = self:PetGrowlSlot()
    if not slot then return end
    CastPetAction(slot)
    self.petGrowlT = now
end

-- Pet AoE cleave for AoE mode (Thunderstomp on gorillas, etc.). Like the taunt,
-- pet abilities live on the pet bar, so we scan for Thunderstomp, cache the slot,
-- and cast it throttled. No-ops if the pet has no cleave.
function M:PetCleave()
    local now = GetTime()
    if (now - (self.petCleaveT or 0)) < 2.0 then return end
    local slot = self.petCleaveSlot
    if not (slot and GetPetActionInfo(slot) == "Thunderstomp") then
        slot = nil
        for i = 1, 10 do
            if GetPetActionInfo(i) == "Thunderstomp" then slot = i; break end
        end
        self.petCleaveSlot = slot
    end
    if not slot then return end
    CastPetAction(slot)
    self.petCleaveT = now
end

-- Mana aspect hysteresis: drop to the mana aspect below the low mark
-- (manaAspectPct), swap back to the combat aspect at the high mark
-- (manaAspectBackPct). Both are user-set sliders; the back mark is guarded to
-- always sit above the low mark so the two edges never collapse into a flap.
-- Once the mana aspect is taken it is LATCHED: the combat aspect stays blocked
-- until mana recovers to the high mark, so a mid-fight Viper->Hawk/Wolf swap
-- below the mark can never drain the player back into Viper.
function M:UpdateAspectState(cfg)
    if cfg.useManaAspect and self:KnownManaAspect() then
        local mp = self:ManaPct()
        local low = cfg.manaAspectPct or 30
        local back = cfg.manaAspectBackPct or (low + MANA_ASPECT_HYST)
        if back <= low then back = low + 1 end
        if mp < low then self.manaAspectActive = true end
        if mp >= back then self.manaAspectActive = false end
    else
        self.manaAspectActive = false
    end
end

-- Keep the right aspect up. Returns true if an aspect was cast this press.
-- The mana aspect (Viper) swap takes priority in EITHER stance when low, so a
-- mana-heavy melee hunter recovers the same way a ranged one does; otherwise the
-- combat aspect picked for the current stance is maintained (user-selectable
-- dropdowns; defaults Wolf melee / Hawk ranged).
-- Aspect upkeep. Costs mana, sits one step above the auto-attack floor, and used
-- to spend the press whether or not it could be paid for - which is the second
-- half of the low-mana starvation: with Hunter's Mark falling through, the
-- aspect took the press instead. Pick now refuses an unaffordable cast, so this
-- returns false and the rotation reaches the swing.
function M:EnsureAspect(cfg, melee)
    if not cfg.useAspect then return false end
    if self.manaAspectActive then
        local ma = self:KnownManaAspect()
        if ma and not self:HasBuff(ma) then return self:Pick(ma, "mana aspect") end
        return false
    end
    local want = melee and (cfg.meleeAspect or "Aspect of the Wolf") or (cfg.rangedAspect or "Aspect of the Hawk")
    if self:KnowsSpell(want) and not self:HasBuff(want) then return self:Pick(want, "aspect upkeep") end
    return false
end

-- Resolve the "Viper > Serpent" smart sting: Viper Sting against mana users,
-- Serpent Sting for everything else. Returns the config sting unchanged for all
-- other values (including "" for None, and the three direct sting names).
function M:ResolveSting(cfg)
    if cfg.sting == "Viper > Serpent" then
        if self:KnowsSpell("Viper Sting") then
            local mmax = UnitManaMax("target")
            if mmax and mmax > 0 then return "Viper Sting" end
        end
        return "Serpent Sting"
    end
    return cfg.sting
end

-- ============================================================
-- Rotation
-- ============================================================
-- The spec with the most talent points, or nil before talents can be read.
-- Tab order on the hunter tree is Beast Mastery, Marksmanship, Survival.
function M:SpecFromTalents()
    if not GetTalentTabInfo then return nil end
    local best, bestPts, total = nil, -1, 0
    local keys = { "bm", "mm", "surv" }
    for i = 1, 3 do
        local _, _, pts = GetTalentTabInfo(i)
        pts = pts or 0
        total = total + pts
        if pts > bestPts then best, bestPts = keys[i], pts end
    end
    if total == 0 then return nil end
    return best
end

-- Single or AoE for this press.
--
-- Without "Smart single/AoE" the macros decide, as they always have. With it,
-- the single macro (and a bare /sbr) is decided by the enemies the nameplates
-- show: from N on the AoE column with all its switches, below it single. The
-- AoE macro, and the AoE toggle, still force AoE. No readable nameplates, no
-- count: the single press stays single. Once on, AoE holds two seconds, so a
-- mob dropping out of the count for a moment does not flip the rotation.
--
-- Counted around the player: in melee range for a hunter in melee, in shot
-- range otherwise - coarser, a second pack thirty yards off counts too.
local SMART_HOLD = 2.0
local SMART_MELEE_YARDS = 8
local SMART_RANGED_YARDS = 30
function M:PressAoe(cfg, over)
    local pressed = Aegis_SBR:PressModeHeld()
    if pressed and Aegis_SBR.pressAoe then return true end
    if not pressed and cfg.aoeMode then return true end
    local smart = over and over.smartAoe
    if smart == nil then smart = cfg.smartAoe end
    if not smart then return Aegis_SBR:AoeMode(cfg) end
    local melee = M.SPEC_MELEE[cfg.spec or "bm"] or false
    local rs = over and over.rangeSwitch
    if rs == nil then rs = cfg.rangeSwitch end
    if rs then melee = self:AutoMelee() end
    local n = Aegis_SBR:CountEnemiesNear(melee and SMART_MELEE_YARDS or SMART_RANGED_YARDS)
    local want = (over and over.smartAoeN) or cfg.smartAoeN or 3
    local now = GetTime()
    self.smartCount = n
    if n and n >= want then
        self.smartUntil = now + SMART_HOLD
        return true
    end
    return now < (self.smartUntil or 0)
end

-- The profile as THIS SPEC sees it, on this press.
--
-- Three tabs, three sparse layers: cfg.bm, cfg.mm, cfg.surv. A key present in
-- the active spec's layer wins over the base; absent, the base applies. Each
-- layer carries its own AoE set under .aoe, consulted first on an AoE press -
-- so the AoE column on the Survival tab is Survival's alone. Lookup order on an
-- AoE press: spec AoE, spec, base. On a single-target press: spec, base.
--
-- A proxy rather than a merged copy: the rotation's reads cost one lookup and
-- its writes still land on the real profile.
M.ownsAoeLayer = true

function M:SpecConfig(cfg)
    local spec = cfg.spec
    local over = spec and cfg[spec]
    if type(over) ~= "table" then return cfg end
    local aoeSet = self:PressAoe(cfg, over) and over.aoe or nil
    if type(aoeSet) ~= "table" then aoeSet = nil end
    return setmetatable({}, {
        __index = function(_, k)
            if aoeSet then
                local v = aoeSet[k]
                if v ~= nil then return v end
            end
            local v = over[k]
            if v ~= nil then return v end
            return cfg[k]
        end,
        __newindex = function(_, k, v) cfg[k] = v end,
    })
end

function M:Rotate(cfg)
    -- Everything below reads the profile through the active spec's own settings.
    cfg = self:SpecConfig(cfg)
    local now      = GetTime()
    local cls      = UnitClassification("target")
    local isElite  = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    local aoe      = self:PressAoe(cfg)
    local inCombat = UnitAffectingCombat("player")
    local inMeleeNow = self:InMeleeRange()   -- actual range to target, independent of mode
    local targetHP   = self:TargetHPPct()
    -- Strict opener gate: Serpent Sting may only follow a confirmed Hunter's Mark.
    -- (True when Mark is disabled or unlearned, so it never blocks at low level.)
    -- A Mark skipped for a short-lived target does not hold the sting back.
    local markWorth = self:LivesFor(cfg, cfg.markMinTTK)
    local markOK = (not cfg.useHuntersMark) or (not self:KnowsSpell("Hunter's Mark"))
        or not markWorth or self:DebuffUpAny("Hunter's Mark")
    -- Effective range state. "auto" picks ranged vs melee by distance each press
    -- (so abilities only fire in the matching state); otherwise honor the choice.
    -- The spec sets the default range; the range switch lets distance override
    -- it press by press, so a shooting spec that has been closed on uses its
    -- melee set and a melee spec that is kept at range uses its shots.
    local melee = M.SPEC_MELEE[cfg.spec or "bm"] or false
    if cfg.rangeSwitch then melee = self:AutoMelee() end

    self:UpdateAspectState(cfg)

    -- Resolve smart sting (Viper > Serpent) to the effective sting for this target
    local effectiveSting = self:ResolveSting(cfg)

    if self:Tracing() then
        self:Trace("spec=" .. (cfg.spec or "?") .. "/" .. (melee and "melee" or "ranged") .. (aoe and " AOE" or "")
            .. (cfg.smartAoe and (" smart=" .. (self.smartCount and tostring(self.smartCount) or "?")) or "")
            .. " hp=" .. floor(targetHP)
            .. " sting=" .. (cfg.sting ~= "" and (cfg.sting
                .. (effectiveSting ~= cfg.sting and ("->" .. effectiveSting) or "")
                .. (self:KnowsSpell(effectiveSting) and "" or "(unlearned)")
                .. (self:StingImmuneNow() and "(immune)" or "")
                .. (self:TargetDebuffUp(effectiveSting, STING_TEX[effectiveSting]) and "(up)" or "")
                -- ClassicAPI's own reading, shown separately from "(up)" on
                -- purpose: when the two disagree, that difference is the thing
                -- worth seeing in a trace.
                .. (self:StingRemainText(effectiveSting))) or "-")
            .. " inMelee=" .. (inMeleeNow and "Y" or "n")
            .. " mark=" .. (cfg.useHuntersMark and (self:DebuffUpAny("Hunter's Mark") and "Y" or "n") or "-")
            .. (cfg.useKillCommand and (" kc=" .. self:KillCommandText()) or "")
            .. " ttk=" .. (Aegis_SBR:TargetTTK() and string.format("%.0fs", Aegis_SBR:TargetTTK()) or "?")
            .. (cfg.useDebuffTTK and ((markWorth and "" or " markSkip") .. (self:LivesFor(cfg, cfg.stingMinTTK) and "" or " stingSkip")) or "")
            -- Seconds still to run on each reapply throttle, which is the one
            -- state that can make a missing debuff stay missing while every
            -- other field looks correct.
            .. " hold=" .. self:ThrottleText("Hunter's Mark") .. "/" .. self:ThrottleText(effectiveSting)
            .. " L&L=" .. (self:HasBuff("Lock and Load") and "Y" or "n")
            .. " auto=" .. (self:AutoShotting() and "Y" or (self.autoShotOn and "assumed" or "N"))
            .. " steady=" .. (cfg.useSteadyShot and (self:SteadyReady() and "ready" or "wait") .. "/" .. self:WeaveSource() or "-")
            .. " manaAsp=" .. (self.manaAspectActive and "Y" or "n")
            .. " mongoose=" .. (self:IsReady("Mongoose Bite") and "rdy" or "cd")
            .. " elite=" .. (isElite and "Y" or "N"))
    end

    -- ----------------------------------------------------------------
    -- 0. Off-GCD / fire-and-continue layer
    -- ----------------------------------------------------------------
    if cfg.petAttack and UnitExists("pet") then PetAttack() end

    -- Smart pet taunt (opt-in): if the mob peels onto us, send the pet's Growl
    -- to grab it back. Off the GCD, throttled internally.
    if cfg.petTaunt and self:PetLostAggro() then self:PetGrowl() end

    -- AoE pet cleave: while AoE mode is on, drive the pet's Thunderstomp. Off GCD,
    -- throttled, no-ops if the pet lacks it.
    if aoe and cfg.petAttack and UnitExists("pet") then self:PetCleave() end

    -- Nothing off the global cooldown is sent while a cast runs: the client
    -- drops it without a word. A log had Rapid Fire sent seven times during
    -- one Steady Shot, none of them taken. The press after the cast sends.
    local casting = CastingBarFrame and (CastingBarFrame.casting or CastingBarFrame.channeling)
    local popBurst = cfg.popCDs or (cfg.autoCDElite and isElite)
    if popBurst and inCombat and not casting then
        -- Rapid Fire speeds up ranged attacks and nothing else. In melee it is
        -- a cooldown spent on nothing, so it stays for the ranged branch - and
        -- is still ready when the hunter steps back to range.
        if cfg.useRapidFire ~= false and not melee
            and self:KnowsSpell("Rapid Fire") and self:IsReady("Rapid Fire") then
            self:PickExtra("Rapid Fire")
        end
        -- Bestial Wrath is a PET cooldown, not a hunter one, and it used to
        -- share this gate with Rapid Fire as though the two were the same kind
        -- of thing. Turtle's tooltip settles it: it grants the pet Scent of
        -- Blood for 18 seconds, which is the talent's own proc - 40% additional
        -- damage, dealt by the pet. With no pet out, or a dead one, the whole
        -- cooldown is spent on nothing and comes back in two minutes.
        --
        -- Its own toggle on top of that, so a hunter who wants Rapid Fire
        -- automated is not made to take the pet cooldown with it.
        --
        -- A dead pet still EXISTS as a unit, so both tests are needed; that is
        -- the same trap the warlock's PetHPPct documents.
        if cfg.useBestialWrath and self:KnowsSpell("Bestial Wrath")
            and self:IsReady("Bestial Wrath")
            and UnitExists("pet") and not UnitIsDead("pet") then
            self:PickExtra("Bestial Wrath")
        end
    end
    -- Kill Command is rotational for BM: fire in combat (off GCD) once a crit
    -- of ours has armed it - see KillCommandArmed.
    if cfg.useKillCommand and inCombat and not casting and self:KnowsSpell("Kill Command") and self:IsReady("Kill Command")
        and self:KillCommandArmed() then
        self:PickExtra("Kill Command")
        self:Later(function() self.killCommandSentAt = GetTime() end)
    end
    -- Baited Shot reaction inside the short window after the pet crits.
    if cfg.useBaitedShot and not casting and self:KnowsSpell("Baited Shot")
        and now < (self.petCritUntil or 0) and self:IsReady("Baited Shot") then
        self:PickExtra("Baited Shot")
    end

    -- ----------------------------------------------------------------
    -- 1. Hunter's Mark ALWAYS leads (strict opener) - the first thing a hunter
    --    does to a target, ahead of aspect upkeep. The rotation does not proceed
    --    to Sting or shots until Mark is on the target. Universal, since the
    --    damage-amp debuff helps in melee too.
    --
    --    It sits above the aspect on purpose: Mark costs one press ONCE per
    --    target (MaintainDebuff returns false as soon as the debuff is up, so it
    --    stops consuming the press), whereas the aspect is upkeep that can wait
    --    a single press without losing anything - including the mana swap to
    --    Viper, which is a threshold, not a deadline. The off-GCD layer above
    --    still runs first because it is fire-and-continue and never eats the
    --    press.
    -- ----------------------------------------------------------------
    if cfg.useHuntersMark and markWorth then
        if self:MaintainDebuff("Hunter's Mark", 110) then return end
    end

    -- ----------------------------------------------------------------
    -- 2. Aspect upkeep (one GCD cast when missing or swapping)
    -- ----------------------------------------------------------------
    if self:EnsureAspect(cfg, melee) then return end

    -- 3. Aimed Shot opener (optional): the first ranged shot, fired before Auto
    --    Shot starts. Gated on Auto Shot not yet running this fight plus its own
    --    cooldown, so it goes out exactly once at the pull.
    if cfg.useAimedOpener and not melee and not self.autoShotOn
        and self:KnowsSpell("Aimed Shot") and self:IsReady("Aimed Shot") then
        if self:Queue("Aimed Shot", "opener, before Auto Shot") then return end
    end

    -- 4. Auto-attack backbone: ranged keeps Auto Shot firing (the mana-free damage
    --    backbone); melee starts swings. Starting Auto Shot is its own press
    --    (vanilla cannot also cast in the same frame), so return when it fires.
    if melee then
        Aegis_SBR:EnsureAutoAttack()
    else
        if self:EnsureAutoShot() then return end
    end

    -- ----------------------------------------------------------------
    -- 5. GCD priority (strict, one cast per press via early return)
    -- ----------------------------------------------------------------

    -- 5a. Sting upkeep - highest GCD priority so the DoT is kept up. Only AFTER
    --     Hunter's Mark is confirmed and only at range: it is a ranged shot, so
    --     even a melee hunter lands it on the pull and stops once closed. No HP
    --     gate - the reapply throttle already stops trash from getting a wasted
    --     refresh, and the Arcane finisher below still burns down a low mob.
    --
    --     Filler all the same: the press that belongs to Steady Shot goes to
    --     Steady, and the sting waits for a gap with a global cooldown of room
    --     before the next Auto Shot - the weave is the rotation, the sting is
    --     not.
    --
    --     The hold for a sting already queued comes FIRST, outside the room
    --     test. Inside it, the press after the next Auto Shot - Steady Shot's
    --     press, where the room test says no - skipped the hold, queued Steady
    --     over the pending sting in Nampower's single slot, and the sting never
    --     left: reported as Serpent Sting no longer applied after v1.2.39.
    if cfg.sting ~= "" and not inMeleeNow and self.stingQueuedT
        and (now - self.stingQueuedT) < STING_QUEUE_HOLD
        and not self:DebuffUpAny(effectiveSting) then
        return
    end
    -- The sting is the exception among the fillers: a DoT that is missing is
    -- applied ahead of Steady Shot, costing one Steady per sting duration. As
    -- a pure filler it waited for room that a fast bow never leaves - Steady's
    -- global cooldown and the sting's together are three seconds - and was
    -- reported as no longer applied, even with Steady Shot switched off.
    -- Instant, so it clips nothing; the hold above keeps the queue clean.
    local stingRoom = true
    if cfg.sting ~= "" and not inMeleeNow and markOK and stingRoom
        and self:LivesFor(cfg, cfg.stingMinTTK)
        and not self:StingBlocked(effectiveSting) then
        if self:MaintainSting(effectiveSting, STING_DUR[effectiveSting] or 12) then
            -- remember this application so a sting that never lands (an immune
            -- undead / boss) is learned and not re-cast every cycle.
            local _, guid = UnitExists("target")
            self:Later(function()
                self.stingTry = { guid = guid, t = GetTime(), name = effectiveSting }
                self.stingQueuedT = now   -- protect the queued shot from eviction
            end)
            return
        end
        -- (The hold for a sting just queued - not yet readable on the target,
        -- so Steady / Multi / Arcane must not overwrite it in Nampower's
        -- single-slot queue - sits above this block. Only while the sting is
        -- NOT yet on the target: once it reads back the slot is free; it used
        -- to run its full length regardless, and a log showed the rotation
        -- silent for 1.5s on every pull.)
    end

    -- 5b. Mend Pet when the pet is hurting (throttled, HoT lasts ~15s).
    if self:MendPetDue(cfg) then
        do
            if self:Pick("Mend Pet", "pet needs healing") then
                self:Later(function() self.mendPetT = now end)
                return
            end
        end
    end

    -- 5c. Lock and Load reaction (MM capstone): cast Aimed Shot NOW. The proc
    --     drops its cast time and makes it cleave a line, so it never clips.
    if cfg.useAimedShot and self:KnowsSpell("Aimed Shot") and self:HasBuff("Lock and Load") then
        if self:Queue("Aimed Shot", "Lock and Load proc") then return end
    end

    -- 5d. The trap, chosen by mode.
    --
    -- Two rotations, one per situation: against a single target the trap is
    -- Immolation, against a pack it is Explosive - each on its own switch, and
    -- the AoE toggle decides which one this press asks for. Not both: in AoE
    -- the single-target trap is left alone, and the other way round.
    --
    -- IN COMBAT only with Untamed Trapper. Placing a trap while fighting is that
    -- Survival talent's doing, not the client's - its tooltip says so in as many
    -- words - and this used to assume the client allowed it for everyone. A
    -- hunter without the talent had a trap offered on every cooldown and
    -- refused on every one. Out of combat, on the pull, anyone may place one.
    local trapOK = (not inCombat) or self:TalentRank(TALENT_UNTAMED_TRAPPER) > 0
    if not trapOK then
        -- nothing: the trap is simply not available right now
    elseif aoe then
        if cfg.useExplosiveTrap and self:KnowsSpell("Explosive Trap") and self:IsReady("Explosive Trap") then
            if self:Pick("Explosive Trap", "AoE, on cooldown") then return end
        end
    else
        if cfg.useImmolationTrap and self:KnowsSpell("Immolation Trap") and self:IsReady("Immolation Trap") then
            if self:Pick("Immolation Trap", "on cooldown") then return end
        end
    end

    -- ----------------------------------------------------------------
    -- 6a. Melee branch
    -- ----------------------------------------------------------------
    if melee then
        -- Raptor Strike FIRST, and as an extra rather than the press's pick.
        --
        -- It is an on-next-swing attack: it queues on the white swing and spends
        -- no global cooldown, so it can go out in the same press as Mongoose
        -- Bite or Lacerate. Ranked as an ordinary rung below them - where it sat
        -- - it was only reached on presses where neither of those fired, and a
        -- swing that could have carried it went out plain.
        --
        -- This is the shape of the hand-written macro the module is measured
        -- against: trap, then Raptor Strike whenever ready, then Mongoose Bite,
        -- then Lacerate, with only the trap ending the press.
        if cfg.useRaptorStrike and self:KnowsSpell("Raptor Strike") and self:IsReady("Raptor Strike")
            and Aegis_SBR:CanAfford("Raptor Strike") then
            self:PickExtra("Raptor Strike")
        end
        -- Carve: the Survival melee cone AoE (up to 5 targets, shares its cooldown
        -- with Multi-Shot). Leads the melee branch when AoE is toggled on.
        if aoe and cfg.useCarve and self:KnowsSpell("Carve") and self:IsReady("Carve") then
            if self:Pick("Carve", "AoE cleave") then return end
        end
        -- Mongoose Bite, plainly on its own cooldown.
        --
        -- It was gated on a five second window after DODGING an enemy attack,
        -- which is the vanilla rule and not this client's: here it is an ordinary
        -- instant melee attack, 30 mana, five seconds. The gate meant it almost
        -- never fired, and the dodge tracker that fed it is gone with it.
        --
        -- With "Lacerate before Mongoose Bite" the bleed goes first (strong
        -- gear makes it the bigger hit); by default the Bite leads.
        local function lacerate()
            if cfg.useLacerate and self:KnowsSpell("Lacerate") and self:LacerateArmed() then
                if self:MaintainDebuff("Lacerate", 8) then
                    self:Later(function() self.lacerateSentAt = GetTime() end)
                    return true
                end
            end
            return false
        end
        if cfg.lacerateFirst and lacerate() then return end
        if cfg.useMongooseBite and self:KnowsSpell("Mongoose Bite")
            and self:IsReady("Mongoose Bite") then
            if self:Pick("Mongoose Bite", "on cooldown") then return end
        end
        -- Lacerate bleed upkeep. The tooltip on this client: an 8 second bleed on
        -- a 10 second cooldown, usable only after critically striking the target.
        --
        -- The cooldown outlasts the bleed, so "when it falls off" and "when it is
        -- ready" are the same moment, and upkeep by debuff is the right shape.
        -- The crit requirement is the part that needs evidence: offered without
        -- it, Lacerate took the press and was refused on every one until a crit
        -- happened to land. So it is ARMED by a crit of ours and DISARMED by a
        -- refusal - each refusal waits for the next crit, no guessed window.
        if not cfg.lacerateFirst and lacerate() then return end
        -- Carve as a single-target filler, BELOW every rotational attack, so it
        -- can only take a press nothing else wanted. Requested from play.
        --
        -- The research documents Carve as an AoE tool (Survival AoE is "Carve +
        -- Explosive Trap"), which is why the AoE lead above exists and stays. A
        -- cone hitting one target is still damage on an otherwise idle global,
        -- and the shared Multi-Shot cooldown costs nothing in melee, where
        -- Multi-Shot is not part of the branch at all.
        --
        -- Placed last rather than ranked against the strikes on purpose: its
        -- damage relative to Raptor Strike has not been measured, and filler is
        -- the position where being wrong about that is free.
        if cfg.useCarve and self:KnowsSpell("Carve") and self:IsReady("Carve") then
            if self:Pick("Carve", "single-target filler") then return end
        end
        -- Wing Clip (optional kite / slow).
        if cfg.useWingClip and self:KnowsSpell("Wing Clip") and self:IsReady("Wing Clip") then
            if self:Pick("Wing Clip", "slow") then return end
        end
        return
    end

    -- ----------------------------------------------------------------
    -- 6b. Ranged branch
    -- ----------------------------------------------------------------
    -- AoE lead: Multi-Shot ahead of the Steady weave, then Volley.
    --
    -- Volley is gated on its switch alone. The panel offers it in both columns,
    -- and the column of the press is what cfg already reads - a second gate on
    -- the AoE press here made the single column's switch do nothing, which is
    -- how "Volley is on and never tried" came about. Multi-Shot keeps its AoE
    -- lead; on a single press it has its own place after Steady Shot below.
    if aoe and cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
        if self:Queue("Multi-Shot", "AoE") then return end
    end
    if cfg.useVolley and self:KnowsSpell("Volley") and self:IsReady("Volley") then
        if self:CastVolley() then return end
    end

    -- Steady Shot is the PRIMARY weave: tried first, but gated to the window right
    -- after each Auto Shot. When the gate is closed (mid-swing) or Steady is
    -- unlearned, the shots below fill the gap instead - so the cast-time Steady
    -- never clips Auto Shot, yet still goes out 1:1 with each shot.
    if cfg.useSteadyShot and self:KnowsSpell("Steady Shot") and self:SteadyReady() then
        if self:Queue("Steady Shot", "weave after Auto Shot") then
            self:Later(function() self.steadyT = GetTime() end)
            return
        end
    end

    -- Multi-Shot woven into the post-Steady downtime (single-target burst when you
    -- have the GCDs to spare): Auto Shot -> Steady -> Multi-Shot.
    --
    -- Single target it is filler: below Kill Command and the Steady weave, and
    -- only with a global cooldown of room before the next Auto Shot, so it
    -- never delays the next Steady.
    local room = self:FillerRoom(nil, cfg)
    if cfg.useMultiShot and self:FillerRoom(MULTI_CAST, cfg) and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
        if self:Queue("Multi-Shot", "filler, room before the next shot") then return end
    end

    -- Low-HP finisher: below the floor, instant Arcane Shot burns the mob down
    -- ahead of the mana-gated filler. Runs regardless of the mana gate - it's a kill.
    if cfg.useArcaneShot and room and self:KnowsSpell("Arcane Shot")
        and targetHP <= STING_HP_FLOOR and self:IsReady("Arcane Shot") then
        if self:Queue("Arcane Shot", "finishing a low target") then return end
    end

    -- Arcane Shot filler: mana-inefficient, so only when mana is plentiful OR when
    -- Auto Shot cannot fire (moving / out of range -> shot timing has gone stale),
    -- so it never gets spammed during the stationary mana-conserving rotation.
    if cfg.useArcaneShot and self:KnowsSpell("Arcane Shot") and self:IsReady("Arcane Shot") then
        local autoStale = not (self.lastAutoShot and self.lastAutoShot > 0
            and (now - self.lastAutoShot) < (self:RangedSpeed() + 1.0))
        if (self:ManaPct() >= ARCANE_MANA_FLOOR and room) or autoStale then
            if self:Queue("Arcane Shot", "instant filler") then return end
        end
    end

    -- Aimed Shot on cooldown ONLY when neither the proc-only guard nor the opener
    -- mode owns it (it clips Auto Shot otherwise; Lock and Load is the safe path).
    if cfg.useAimedShot and not cfg.aimedOnlyOnProc and not cfg.useAimedOpener
        and self:KnowsSpell("Aimed Shot") and self:IsReady("Aimed Shot") then
        if self:Queue("Aimed Shot", "on cooldown") then return end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:CmdSpec(alias)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local spec = self.specAlias[string.lower(alias or "")]
    if not spec then msgOut("usage: /sbr spec bm|mm|survival", 1, 0.5, 0.3); return end
    cfg.spec = spec
    msgOut("spec = " .. (M.SPEC_NAME[spec] or spec) .. ".")
end

function M:CmdSting(alias)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local sting = self.stingAlias[string.lower(alias or "")]
    if sting == nil then msgOut("usage: /sbr sting serpent|scorpid|viper|smart|none", 1, 0.5, 0.3); return end
    cfg.sting = sting
    msgOut("sting = " .. ((sting == "") and "(none)" or sting) .. ".")
end

function M:CmdAoe()
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.aoeMode = not cfg.aoeMode
    msgOut("AoE mode " .. (cfg.aoeMode and "on (Volley + Multi-Shot)" or "off (single target)") .. ".")
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
    if cmd == "spec" or cmd == "mode" then self:CmdSpec(t[2]); return true end
    if cmd == "sting" then self:CmdSting(t[2]); return true end
    if cmd == "aoe"   then self:CmdAoe(); return true end
    if cmd == "cd"    then self:CmdCd(t[2]); return true end
    if cmd == "spell" then self:CmdSpell(t[2], t[3]); return true end
    return false
end

-- ============================================================
-- Event tracking: precise Auto Shot / Steady Shot timing from SuperWoW's
-- UNIT_CASTEVENT (arg1 casterGUID, arg3 type, arg4 spell id, arg5 cast ms),
-- the Auto Shot reset on leaving combat, and the pet-crit window for Baited
-- Shot.
-- ============================================================
local hunterFrame = CreateFrame("Frame")
hunterFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
hunterFrame:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")                 -- our pet's damage
hunterFrame:RegisterEvent("UNIT_CASTEVENT")                           -- SuperWoW: exact cast/shot timing
-- A resisted, missed or immune shot of ours is reported here. Without it those
-- look exactly like a sting that had just landed and not yet registered, so the
-- reapply throttle sat on it for the sting's whole duration.
hunterFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
-- The same lines can arrive on the combat channel instead of the spell one,
-- depending on how the client classifies the shot: a sting is a ranged attack
-- that applies a debuff, and the two message channels split on exactly that
-- distinction. Which one carries "Your Serpent Sting missed X." is not something
-- this code should assume, so both are read and the SAME narrow matcher decides
-- - only a line naming one of our own tracked shots does anything at all. If the
-- message never arrives here, registering it costs nothing.
hunterFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
-- Our own white crits. Lacerate may only be used after critically striking the
-- target, and a white swing is one of the two ways to do that; the other, an
-- ability crit, arrives on CHAT_MSG_SPELL_SELF_DAMAGE, already registered.
hunterFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
hunterFrame:SetScript("OnEvent", function()
    -- "You crit X for N." / "Your Raptor Strike crits X for N." - either one
    -- arms Lacerate. Checked before anything else because both channels are
    -- read further down for other reasons and return early there.
    if (event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_SPELL_SELF_DAMAGE")
        and arg1 and string.find(arg1, "crit") then
        -- Only a crit on the current target counts: Kill Command and Lacerate
        -- are both "after a critical strike on the target".
        local tname = UnitName("target")
        if tname and string.find(arg1, tname, 1, true) then
            M.lastCritAt = GetTime()
            M.lastCritName = tname
        end
    end
    if event == "PLAYER_REGEN_ENABLED" then
        M.autoShotOn = false
        M.autoShotTarget = nil
        M.steadyT = 0
        M.lastAutoShot = 0   -- forget the ranged-swing phase between pulls
        M.lastAutoShotAt = nil
        -- Only the per-GUID half: what was learned per creature TYPE lives in
        -- AegisDB and is meant to outlast the fight.
        M.stingImmune = {}
        M.stingTry = nil
        M.stingQueuedT = nil
    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        -- "Your Serpent Sting was resisted by X." / "... missed X." The throttle
        -- exists to stop a second cast while the first is still registering on
        -- the target; a resist or a miss means there is nothing to register, so
        -- it is cleared and the next press re-applies immediately. Matching only
        -- the word "resisted" was the bug: a MISS left the throttle standing and
        -- the sting went unapplied for its full fifteen seconds.
        --
        -- Still deliberately narrow: only our own shots, named in the line.
        local shot
        if arg1 then
            for name in pairs(STING_TEX) do
                if string.find(arg1, name, 1, true) then shot = name; break end
            end
        end
        if shot then
            if string.find(arg1, "immune") then
                -- "Your Serpent Sting failed. X is immune." Definitive, and
                -- better than the 2.5s inference in StingBlocked, which only
                -- dares to conclude immunity on an Undead. The throttle is left
                -- alone on purpose: there is nothing to retry. Only when the line
                -- names the CURRENT target, so a message about something else
                -- cannot silence the sting on this one.
                if shot ~= "Hunter's Mark" then
                    local tname = UnitName("target")
                    local _, guid = UnitExists("target")
                    if guid and tname and string.find(arg1, tname, 1, true) then
                        M.stingImmune[guid] = true
                        M:RememberImmune(Aegis_SBR.UnitCreatureID
                            and Aegis_SBR:UnitCreatureID("target"))
                    end
                end
                M.stingTry = nil
            elseif string.find(arg1, "resist") or string.find(arg1, "miss") then
                M.debuffThrottle[shot] = nil
                M.stingTry = nil
            end
        end
    elseif event == "CHAT_MSG_COMBAT_PET_HITS" then
        if arg1 and string.find(string.lower(arg1), "crit") then
            M.petCritUntil = GetTime() + PETCRIT_WINDOW
        end
    elseif event == "UNIT_CASTEVENT" then
        -- Only the player's own casts matter; filter by GUID before the spell
        -- lookup to stay cheap when many units are casting nearby.
        if not M.playerGUID then local _, g = UnitExists("player"); M.playerGUID = g end
        if arg1 and M.playerGUID and arg1 == M.playerGUID and SpellInfo then
            local nm = SpellInfo(arg4)
            if nm == "Auto Shot" then
                -- "CAST" is the projectile launch (the swing reset); ignore the
                -- "START" windup so the phase reference is the actual shot.
                if arg3 == "CAST" then
                    M.lastAutoShot = GetTime()
                    -- Which target it was aimed at. Without this the timestamp
                    -- is target-blind and a shot at the PREVIOUS mob reads as
                    -- "still firing" at the new one, so the restart never
                    -- happens - reported as auto shot not starting after a
                    -- target switch.
                    M.lastAutoShotAt = arg2
                end
            elseif nm == "Steady Shot" then
                if arg3 == "START" then
                    local d = tonumber(arg5)
                    if d and d > 0 then M.steadyCastDur = d / 1000 end
                end
            end
        end
    end
end)
