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
M.uiHeight = 878
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
local STEADY_CAST_DEFAULT = 1.5   -- assumed Steady Shot cast time until measured live
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

-- The mana-regenerating aspect (Turtle). First known name is used; gated by
-- KnowsSpell so an unknown name is simply inert.
M.MANA_ASPECTS = { "Aspect of the Viper", "Aspect of the Beast" }

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
}

M.modeAlias = {
    ranged = "ranged", range = "ranged", ["r"] = "ranged",
    melee = "melee", ["m"] = "melee",
    auto = "auto", ["a"] = "auto", distance = "auto", dist = "auto",
}

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
        mode = "auto",
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = false,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk",
        useManaAspect = false, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = false,
    },
    beastmastery = {
        mode = "ranged",
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = true,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk",
        useManaAspect = true, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 60,
        useKillCommand = true, useBaitedShot = true,
        popCDs = false, autoCDElite = true,
    },
    marksmanship = {
        mode = "ranged",
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = true,
        useAimedShot = true, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false,
        useRaptorStrike = false, useMongooseBite = false, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk",
        useManaAspect = true, manaAspectPct = 25,
        petAttack = true, useMendPet = true, mendPetHp = 40,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = true,
    },
    survival = {  -- hybrid: trap + melee, weaving shots
        mode = "melee",
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = true,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = true,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false, useLacerate = true, useCarve = true,
        useAspect = true, rangedAspect = "Aspect of the Hawk",
        useManaAspect = true, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = true,
    },
    melee = {  -- BM / melee weave
        mode = "melee",
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = false, useArcaneShot = false, useMultiShot = false,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false, useLacerate = true, useCarve = true,
        useAspect = true, rangedAspect = "Aspect of the Hawk",
        useManaAspect = false, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 60,
        useKillCommand = true, useBaitedShot = true,
        popCDs = false, autoCDElite = true,
    },
}

function M:NormalizeProfile(c)
    local b = {
        mode = "ranged",
        useHuntersMark = true, sting = "Serpent Sting",
        useSteadyShot = true, useArcaneShot = true, useMultiShot = false,
        useAimedShot = false, aimedOnlyOnProc = true,
        aoeMode = false, useVolley = false, useImmolationTrap = false,
        useRaptorStrike = true, useMongooseBite = true, useWingClip = false,
        useAspect = true, rangedAspect = "Aspect of the Hawk",
        useManaAspect = false, manaAspectPct = 30,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        petTaunt = false, useLacerate = false, useCarve = false, useAimedOpener = false,
        useKillCommand = false, useBaitedShot = false,
        popCDs = false, autoCDElite = false,
    }
    for k, v in pairs(b) do
        if c[k] == nil then c[k] = v end
    end
    if c.mode ~= "ranged" and c.mode ~= "melee" and c.mode ~= "auto" then c.mode = "ranged" end
    if type(c.sting) ~= "string" then c.sting = "Serpent Sting" end
    if type(c.rangedAspect) ~= "string" then c.rangedAspect = "Aspect of the Hawk" end
    -- Two-threshold mana-aspect swap: drop to the mana aspect below manaAspectPct,
    -- swap back to the combat aspect at manaAspectBackPct. Older profiles used a
    -- fixed +MANA_ASPECT_HYST hysteresis, so default the back mark to that to
    -- preserve their existing behavior exactly.
    if c.manaAspectBackPct == nil then c.manaAspectBackPct = (c.manaAspectPct or 30) + MANA_ASPECT_HYST end
    -- migrate the old ranged-only schema (useArcaneShot etc. carried over)
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
    if self.lastAutoShot and self.lastAutoShot > 0 then
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
    CastSpellByName("Auto Shot")
    self.autoShotOn = true
    self.autoShotTarget = self:TargetId()
    self.autoShotT = now
    return true
end

-- Queue a shot through SuperWoW/Nampower so the weave lands without clipping
-- the Auto Shot in progress; falls back to a direct cast without the queue.
function M:Queue(name, reason)
    if not self:KnowsSpell(name) then return false end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name; p.reason = reason; p.queue = true
        return true
    end
    Aegis_SBR:NoteSpellCast(name)
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

-- Debuffs this client has actually been seen to read back off a target, by
-- name. Same idea and same reason as stingSeen below: it is a property of the
-- CLIENT (does SuperWoW resolve the name, does the icon fragment match, does
-- ClassicAPI answer), not of any one mob, so it is kept for the session.
M.debuffSeen = {}

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
    if not self:Pick(name, "debuff missing") then return false end
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

function M:KnownImmuneType()
    local id = Aegis_SBR.UnitCreatureID and Aegis_SBR:UnitCreatureID("target")
    if not id then return false end
    local mem = self:ImmuneMemory()
    return (mem and mem[id]) and true or false
end

-- Read-only: is a sting blocked on the current target right now? No side effects
-- (used by the rotation gate and the trace line).
function M:StingImmuneNow()
    local ct = UnitCreatureType and UnitCreatureType("target")
    if ct and self.STING_IMMUNE_TYPES[ct] then return true end
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
-- combat aspect for the current state is maintained (Wolf melee / Hawk ranged).
function M:EnsureAspect(cfg, melee)
    if not cfg.useAspect then return false end
    if self.manaAspectActive then
        local ma = self:KnownManaAspect()
        if ma and not self:HasBuff(ma) then return self:Pick(ma, "mana aspect") end
        return false
    end
    local want = melee and "Aspect of the Wolf" or (cfg.rangedAspect or "Aspect of the Hawk")
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
function M:Rotate(cfg)
    local now      = GetTime()
    local cls      = UnitClassification("target")
    local isElite  = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    local aoe      = cfg.aoeMode and true or false
    local inCombat = UnitAffectingCombat("player")
    local inMeleeNow = self:InMeleeRange()   -- actual range to target, independent of mode
    local targetHP   = self:TargetHPPct()
    -- Strict opener gate: Serpent Sting may only follow a confirmed Hunter's Mark.
    -- (True when Mark is disabled or unlearned, so it never blocks at low level.)
    local markOK = (not cfg.useHuntersMark) or (not self:KnowsSpell("Hunter's Mark"))
        or self:DebuffUpAny("Hunter's Mark")
    -- Effective range state. "auto" picks ranged vs melee by distance each press
    -- (so abilities only fire in the matching state); otherwise honor the choice.
    local melee
    if cfg.mode == "auto" then
        melee = self:AutoMelee()
    else
        melee = (cfg.mode == "melee")
    end

    self:UpdateAspectState(cfg)

    -- Resolve smart sting (Viper > Serpent) to the effective sting for this target
    local effectiveSting = self:ResolveSting(cfg)

    if self:Tracing() then
        self:Trace("mode=" .. (cfg.mode or "ranged") .. (cfg.mode == "auto" and ("/" .. (melee and "melee" or "ranged")) or "")
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

    local popBurst = cfg.popCDs or (cfg.autoCDElite and isElite)
    if popBurst and inCombat then
        if self:KnowsSpell("Rapid Fire") and self:IsReady("Rapid Fire") then self:PickExtra("Rapid Fire") end
        if self:KnowsSpell("Bestial Wrath") and self:IsReady("Bestial Wrath") then self:PickExtra("Bestial Wrath") end
    end
    -- Kill Command is rotational for BM: fire on cooldown in combat (off GCD).
    if cfg.useKillCommand and inCombat and self:KnowsSpell("Kill Command") and self:IsReady("Kill Command") then
        self:PickExtra("Kill Command")
    end
    -- Baited Shot reaction inside the short window after the pet crits.
    if cfg.useBaitedShot and self:KnowsSpell("Baited Shot")
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
    if cfg.useHuntersMark then
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
    if cfg.sting ~= "" and not inMeleeNow and markOK
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
        elseif self.stingQueuedT and (now - self.stingQueuedT) < STING_QUEUE_HOLD then
            -- Sting was just queued but cannot be read on the target yet. Hold
            -- here instead of queuing Steady / Multi / Arcane, which would
            -- overwrite the still-pending sting in Nampower's single-slot queue
            -- before it fires. Auto Shot (handled above) keeps going meanwhile.
            return
        end
    end

    -- 5b. Mend Pet when the pet is hurting (throttled, HoT lasts ~15s).
    if cfg.useMendPet and UnitExists("pet") and self:KnowsSpell("Mend Pet") then
        if self:PetHPPct() < (cfg.mendPetHp or 50) and (now - (self.mendPetT or 0)) > MEND_PET_CD then
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

    -- 5d. Immolation Trap on cooldown (Survival, usable in combat on 1.18.1).
    if cfg.useImmolationTrap and self:KnowsSpell("Immolation Trap") and self:IsReady("Immolation Trap") then
        if self:Pick("Immolation Trap", "on cooldown") then return end
    end

    -- ----------------------------------------------------------------
    -- 6a. Melee branch
    -- ----------------------------------------------------------------
    if melee then
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
        if cfg.useMongooseBite and self:KnowsSpell("Mongoose Bite")
            and self:IsReady("Mongoose Bite") then
            if self:Pick("Mongoose Bite", "on cooldown") then return end
        end
        -- Lacerate bleed upkeep (Turtle Survival): apply/refresh when it falls off.
        if cfg.useLacerate and self:KnowsSpell("Lacerate") then
            if self:MaintainDebuff("Lacerate", 15) then return end
        end
        -- Raptor Strike on cooldown (queues on the next melee swing).
        if cfg.useRaptorStrike and self:KnowsSpell("Raptor Strike") and self:IsReady("Raptor Strike") then
            if self:Pick("Raptor Strike", "on cooldown") then return end
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
    -- AoE: Multi-Shot on cooldown (3+ targets), then Volley channel (4+ dense).
    if aoe then
        if cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
            if self:Queue("Multi-Shot", "AoE") then return end
        end
        if cfg.useVolley and self:KnowsSpell("Volley") and self:IsReady("Volley") then
            if self:Queue("Volley", "AoE") then return end
        end
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
    if cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
        if self:Queue("Multi-Shot", "instant") then return end
    end

    -- Low-HP finisher: below the floor, instant Arcane Shot burns the mob down
    -- ahead of the mana-gated filler. Runs regardless of the mana gate - it's a kill.
    if cfg.useArcaneShot and self:KnowsSpell("Arcane Shot")
        and targetHP <= STING_HP_FLOOR and self:IsReady("Arcane Shot") then
        if self:Queue("Arcane Shot", "finishing a low target") then return end
    end

    -- Arcane Shot filler: mana-inefficient, so only when mana is plentiful OR when
    -- Auto Shot cannot fire (moving / out of range -> shot timing has gone stale),
    -- so it never gets spammed during the stationary mana-conserving rotation.
    if cfg.useArcaneShot and self:KnowsSpell("Arcane Shot") and self:IsReady("Arcane Shot") then
        local autoStale = not (self.lastAutoShot and self.lastAutoShot > 0
            and (now - self.lastAutoShot) < (self:RangedSpeed() + 1.0))
        if self:ManaPct() >= ARCANE_MANA_FLOOR or autoStale then
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
function M:CmdMode(alias)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local mode = self.modeAlias[string.lower(alias or "")]
    if not mode then msgOut("usage: /sbr mode ranged|melee|auto", 1, 0.5, 0.3); return end
    cfg.mode = mode
    msgOut("playstyle = " .. mode .. ".")
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
    if cmd == "mode"  then self:CmdMode(t[2]); return true end
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
hunterFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_ENABLED" then
        M.autoShotOn = false
        M.autoShotTarget = nil
        M.steadyT = 0
        M.lastAutoShot = 0   -- forget the ranged-swing phase between pulls
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
                if arg3 == "CAST" then M.lastAutoShot = GetTime() end
            elseif nm == "Steady Shot" then
                if arg3 == "START" then
                    local d = tonumber(arg5)
                    if d and d > 0 then M.steadyCastDur = d / 1000 end
                end
            end
        end
    end
end)
