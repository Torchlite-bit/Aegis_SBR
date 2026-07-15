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
--    Raptor Strike on cooldown, Mongoose Bite reactively after you dodge,
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
M.uiHeight = 850
M.meleeAutoAttack = false   -- managed here: Auto Shot (ranged) or Attack (melee)
M.autoAcquireTarget = false -- a ranged class should not auto-pull random mobs; pick targets

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end
local floor = math.floor

local MEND_PET_CD = 12   -- Mend Pet HoT lasts ~15s, refresh a little early
local REACT_WINDOW = 5.0 -- Mongoose Bite stays usable ~5s after a dodge
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

M.modeAlias = {
    ranged = "ranged", range = "ranged", ["r"] = "ranged",
    melee = "melee", ["m"] = "melee",
    auto = "auto", ["a"] = "auto", distance = "auto", dist = "auto",
}

M.stingAlias = {
    serpent = "Serpent Sting", ss = "Serpent Sting",
    scorpid = "Scorpid Sting", sco = "Scorpid Sting",
    viper = "Viper Sting", vs = "Viper Sting",
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
    if self:AutoShotting() then self.autoShotOn = true; self.autoShotT = GetTime(); return false end
    local now = GetTime()
    if self.lastAutoShot and self.lastAutoShot > 0 then
        if (now - self.lastAutoShot) < (self:RangedSpeed() + AUTOSHOT_STALL) then
            self.autoShotOn = true
            return false
        end
    else
        local id = self:TargetId()
        if self.autoShotOn and self.autoShotTarget == id
            and (now - (self.autoShotT or 0)) < (self:RangedSpeed() + AUTOSHOT_STALL) then
            return false
        end
    end
    CastSpellByName("Auto Shot")
    self.autoShotOn = true
    self.autoShotTarget = self:TargetId()
    self.autoShotT = now
    return true
end

-- Queue a shot through SuperWoW/Nampower so the weave lands without clipping
-- the Auto Shot in progress; falls back to a direct cast without the queue.
function M:Queue(name)
    if not self:KnowsSpell(name) then return false end
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
function M:MaintainDebuff(name, interval)
    if not self:KnowsSpell(name) then return false end
    if self:TargetDebuffUp(name, nil) then return false end
    local id = self:TargetId()
    local rec = self.debuffThrottle[name]
    local now = GetTime()
    if rec and rec.id == id and rec.t and (now - rec.t) <= (interval or 3) then
        return false
    end
    self.debuffThrottle[name] = { id = id, t = now }
    return self:Cast(name)
end

-- Sting upkeep. Identical bookkeeping to MaintainDebuff, but the stings are
-- ranged-weapon shots, so they must go out through the Nampower shot queue
-- (QueueSpellByName) exactly like Steady / Arcane / Multi-Shot. Dispatching a
-- sting through the instant CastSpellByName path (as MaintainDebuff does for the
-- melee/targeting debuffs) lets Nampower drop it whenever a global cooldown is
-- up, which silently burns the reapply throttle and the sting never fires.
function M:MaintainSting(name, interval)
    if not self:KnowsSpell(name) then return false end
    if self:TargetDebuffUp(name, nil) then return false end
    local id = self:TargetId()
    local rec = self.debuffThrottle[name]
    local now = GetTime()
    if rec and rec.id == id and rec.t and (now - rec.t) <= (interval or 3) then
        return false
    end
    self.debuffThrottle[name] = { id = id, t = now }
    return self:Queue(name)
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

-- Read-only: is a sting blocked on the current target right now? No side effects
-- (used by the rotation gate and the trace line).
function M:StingImmuneNow()
    local ct = UnitCreatureType and UnitCreatureType("target")
    if ct and self.STING_IMMUNE_TYPES[ct] then return true end
    local _, guid = UnitExists("target")
    return (guid and self.stingImmune[guid]) and true or false
end

-- Full check used by the rotation: the read-only test above, plus learning from
-- a pending application that never landed (the immune undead / boss case).
function M:StingBlocked(sting)
    if self:StingImmuneNow() then return true end
    local _, guid = UnitExists("target")
    if guid and self.stingTry and self.stingTry.guid == guid and self.stingTry.name == sting then
        if self:TargetDebuffUp(sting, nil) then
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

-- Mana aspect hysteresis: drop to the mana aspect below the low mark, swap
-- back to the combat aspect once mana climbs a buffer above it.
function M:UpdateAspectState(cfg)
    if cfg.useManaAspect and self:KnownManaAspect() then
        local mp = self:ManaPct()
        local low = cfg.manaAspectPct or 30
        if mp < low then self.manaAspectActive = true end
        if mp >= (low + MANA_ASPECT_HYST) then self.manaAspectActive = false end
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
        if ma and not self:HasBuff(ma) then return self:Cast(ma) end
        return false
    end
    local want = melee and "Aspect of the Wolf" or (cfg.rangedAspect or "Aspect of the Hawk")
    if self:KnowsSpell(want) and not self:HasBuff(want) then return self:Cast(want) end
    return false
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
        or self:TargetDebuffUp("Hunter's Mark", nil)
    -- Effective range state. "auto" picks ranged vs melee by distance each press
    -- (so abilities only fire in the matching state); otherwise honor the choice.
    local melee
    if cfg.mode == "auto" then
        melee = self:AutoMelee()
    else
        melee = (cfg.mode == "melee")
    end

    self:UpdateAspectState(cfg)

    if self.trace then
        self:Trace("mode=" .. (cfg.mode or "ranged") .. (cfg.mode == "auto" and ("/" .. (melee and "melee" or "ranged")) or "")
            .. " hp=" .. floor(targetHP)
            .. " sting=" .. (cfg.sting ~= "" and (cfg.sting
                .. (self:KnowsSpell(cfg.sting) and "" or "(unlearned)")
                .. (self:StingImmuneNow() and "(immune)" or "")
                .. (self:TargetDebuffUp(cfg.sting, nil) and "(up)" or "")) or "-")
            .. " inMelee=" .. (inMeleeNow and "Y" or "n")
            .. " mark=" .. (cfg.useHuntersMark and (self:TargetDebuffUp("Hunter's Mark", nil) and "Y" or "n") or "-")
            .. " L&L=" .. (self:HasBuff("Lock and Load") and "Y" or "n")
            .. " auto=" .. (self:AutoShotting() and "Y" or (self.autoShotOn and "assumed" or "N"))
            .. " steady=" .. (cfg.useSteadyShot and (self:SteadyReady() and "ready" or "wait") .. "/" .. self:WeaveSource() or "-")
            .. " manaAsp=" .. (self.manaAspectActive and "Y" or "n")
            .. " mongoose=" .. ((now < (self.dodgeUntil or 0)) and "Y" or "n")
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
        if self:KnowsSpell("Rapid Fire") and self:IsReady("Rapid Fire") then self:Cast("Rapid Fire") end
        if self:KnowsSpell("Bestial Wrath") and self:IsReady("Bestial Wrath") then self:Cast("Bestial Wrath") end
    end
    -- Kill Command is rotational for BM: fire on cooldown in combat (off GCD).
    if cfg.useKillCommand and inCombat and self:KnowsSpell("Kill Command") and self:IsReady("Kill Command") then
        self:Cast("Kill Command")
    end
    -- Baited Shot reaction inside the short window after the pet crits.
    if cfg.useBaitedShot and self:KnowsSpell("Baited Shot")
        and now < (self.petCritUntil or 0) and self:IsReady("Baited Shot") then
        self:Cast("Baited Shot")
    end

    -- ----------------------------------------------------------------
    -- 1. Aspect upkeep (one GCD cast when missing or swapping)
    -- ----------------------------------------------------------------
    if self:EnsureAspect(cfg, melee) then return end

    -- ----------------------------------------------------------------
    -- 2. Hunter's Mark ALWAYS leads (strict opener). The rotation does not
    --    proceed to Sting or shots until Mark is on the target. Universal, since
    --    the damage-amp debuff helps in melee too.
    -- ----------------------------------------------------------------
    if cfg.useHuntersMark then
        if self:MaintainDebuff("Hunter's Mark", 110) then return end
    end

    -- 3. Aimed Shot opener (optional): the first ranged shot, fired before Auto
    --    Shot starts. Gated on Auto Shot not yet running this fight plus its own
    --    cooldown, so it goes out exactly once at the pull.
    if cfg.useAimedOpener and not melee and not self.autoShotOn
        and self:KnowsSpell("Aimed Shot") and self:IsReady("Aimed Shot") then
        if self:Queue("Aimed Shot") then return end
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

    -- 5a. Serpent Sting - highest GCD priority so the DoT is kept up. Only AFTER
    --     Hunter's Mark is confirmed and only at range: it is a ranged shot, so
    --     even a melee hunter lands it on the pull and stops once closed. No HP
    --     gate - the reapply throttle already stops trash from getting a wasted
    --     refresh, and the Arcane finisher below still burns down a low mob.
    if cfg.sting ~= "" and not inMeleeNow and markOK
        and not self:StingBlocked(cfg.sting) then
        if self:MaintainSting(cfg.sting, STING_DUR[cfg.sting] or 12) then
            -- remember this application so a sting that never lands (an immune
            -- undead / boss) is learned and not re-cast every cycle.
            local _, guid = UnitExists("target")
            self.stingTry = { guid = guid, t = GetTime(), name = cfg.sting }
            self.stingQueuedT = now   -- protect the queued shot from eviction
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
            if self:Cast("Mend Pet") then self.mendPetT = now; return end
        end
    end

    -- 5c. Lock and Load reaction (MM capstone): cast Aimed Shot NOW. The proc
    --     drops its cast time and makes it cleave a line, so it never clips.
    if cfg.useAimedShot and self:KnowsSpell("Aimed Shot") and self:HasBuff("Lock and Load") then
        if self:Queue("Aimed Shot") then return end
    end

    -- 5d. Immolation Trap on cooldown (Survival, usable in combat on 1.18.1).
    if cfg.useImmolationTrap and self:KnowsSpell("Immolation Trap") and self:IsReady("Immolation Trap") then
        if self:Cast("Immolation Trap") then return end
    end

    -- ----------------------------------------------------------------
    -- 6a. Melee branch
    -- ----------------------------------------------------------------
    if melee then
        -- Carve: the Survival melee cone AoE (up to 5 targets, shares its cooldown
        -- with Multi-Shot). Leads the melee branch when AoE is toggled on.
        if aoe and cfg.useCarve and self:KnowsSpell("Carve") and self:IsReady("Carve") then
            if self:Cast("Carve") then return end
        end
        -- Mongoose Bite reactively after we dodge an enemy attack.
        if cfg.useMongooseBite and self:KnowsSpell("Mongoose Bite")
            and now < (self.dodgeUntil or 0) and self:IsReady("Mongoose Bite") then
            self.dodgeUntil = 0
            if self:Cast("Mongoose Bite") then return end
        end
        -- Lacerate bleed upkeep (Turtle Survival): apply/refresh when it falls off.
        if cfg.useLacerate and self:KnowsSpell("Lacerate") then
            if self:MaintainDebuff("Lacerate", 15) then return end
        end
        -- Raptor Strike on cooldown (queues on the next melee swing).
        if cfg.useRaptorStrike and self:KnowsSpell("Raptor Strike") and self:IsReady("Raptor Strike") then
            if self:Cast("Raptor Strike") then return end
        end
        -- Wing Clip (optional kite / slow).
        if cfg.useWingClip and self:KnowsSpell("Wing Clip") and self:IsReady("Wing Clip") then
            if self:Cast("Wing Clip") then return end
        end
        return
    end

    -- ----------------------------------------------------------------
    -- 6b. Ranged branch
    -- ----------------------------------------------------------------
    -- AoE: Multi-Shot on cooldown (3+ targets), then Volley channel (4+ dense).
    if aoe then
        if cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
            if self:Queue("Multi-Shot") then return end
        end
        if cfg.useVolley and self:KnowsSpell("Volley") and self:IsReady("Volley") then
            if self:Queue("Volley") then return end
        end
    end

    -- Steady Shot is the PRIMARY weave: tried first, but gated to the window right
    -- after each Auto Shot. When the gate is closed (mid-swing) or Steady is
    -- unlearned, the shots below fill the gap instead - so the cast-time Steady
    -- never clips Auto Shot, yet still goes out 1:1 with each shot.
    if cfg.useSteadyShot and self:KnowsSpell("Steady Shot") and self:SteadyReady() then
        if self:Queue("Steady Shot") then self.steadyT = GetTime(); return end
    end

    -- Multi-Shot woven into the post-Steady downtime (single-target burst when you
    -- have the GCDs to spare): Auto Shot -> Steady -> Multi-Shot.
    if cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
        if self:Queue("Multi-Shot") then return end
    end

    -- Low-HP finisher: below the floor, instant Arcane Shot burns the mob down
    -- ahead of the mana-gated filler. Runs regardless of the mana gate - it's a kill.
    if cfg.useArcaneShot and self:KnowsSpell("Arcane Shot")
        and targetHP <= STING_HP_FLOOR and self:IsReady("Arcane Shot") then
        if self:Queue("Arcane Shot") then return end
    end

    -- Arcane Shot filler: mana-inefficient, so only when mana is plentiful OR when
    -- Auto Shot cannot fire (moving / out of range -> shot timing has gone stale),
    -- so it never gets spammed during the stationary mana-conserving rotation.
    if cfg.useArcaneShot and self:KnowsSpell("Arcane Shot") and self:IsReady("Arcane Shot") then
        local autoStale = not (self.lastAutoShot and self.lastAutoShot > 0
            and (now - self.lastAutoShot) < (self:RangedSpeed() + 1.0))
        if self:ManaPct() >= ARCANE_MANA_FLOOR or autoStale then
            if self:Queue("Arcane Shot") then return end
        end
    end

    -- Aimed Shot on cooldown ONLY when neither the proc-only guard nor the opener
    -- mode owns it (it clips Auto Shot otherwise; Lock and Load is the safe path).
    if cfg.useAimedShot and not cfg.aimedOnlyOnProc and not cfg.useAimedOpener
        and self:KnowsSpell("Aimed Shot") and self:IsReady("Aimed Shot") then
        if self:Queue("Aimed Shot") then return end
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
    if sting == nil then msgOut("usage: /sbr sting serpent|scorpid|viper|none", 1, 0.5, 0.3); return end
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
    cfg[key] = (string.lower(onoff or "") == "on")
    msgOut(key .. " = " .. (cfg[key] and "on" or "off") .. " (active profile).")
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
-- the Auto Shot reset on leaving combat, the Mongoose Bite dodge window, and
-- the pet-crit window for Baited Shot.
-- ============================================================
local hunterFrame = CreateFrame("Frame")
hunterFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
hunterFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")  -- enemy attacks we avoided
hunterFrame:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")                 -- our pet's damage
hunterFrame:RegisterEvent("UNIT_CASTEVENT")                           -- SuperWoW: exact cast/shot timing
hunterFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_ENABLED" then
        M.autoShotOn = false
        M.autoShotTarget = nil
        M.steadyT = 0
        M.lastAutoShot = 0   -- forget the ranged-swing phase between pulls
        M.stingImmune = {}   -- relearn sting immunity each combat
        M.stingTry = nil
        M.stingQueuedT = nil
    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
        if arg1 and string.find(string.lower(arg1), "dodge") then
            M.dodgeUntil = GetTime() + REACT_WINDOW
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
