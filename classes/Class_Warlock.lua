-- ============================================================
-- Class_Warlock  -  warlock module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). DoT priority, configurable, level 1+.
-- ============================================================
-- Model (mirrors the proven leveling macro):
--  * Keep the enabled damage-over-time effects up in priority order,
--    Immolate, then the chosen Curse, then Corruption, then Siphon Life.
--  * Malediction (optional): if the main curse is not Curse of Agony or
--    Curse of Doom, that talent piggybacks Curse of Agony on every curse
--    cast. Enabling coaSecondary tracks and refreshes that DoT on its own.
--  * Detection is by debuff texture on the target. A short per-effect
--    memory keyed by target GUID prevents re-queuing a cast-time DoT
--    while it is still landing.
--  * Survival / execute / pet tools, each optional:
--      - Drain Life kicks in as a self-heal channel when your health dips
--        below a threshold (the drain-tank safety net).
--      - Health Funnel tops the pet when it drops, as long as you are not
--        low yourself (it costs your health).
--      - Shadowburn executes the target under 20% (instant, costs a shard,
--        skipped with zero shards in the bag).
--      - Drain Soul channels in the target's last seconds to bank a Soul
--        Shard and regen mana (the leveling finisher). Optionally capped by
--        keepShards/shardTarget so it stops once enough shards are banked.
--  * When nothing above applies, fall back to the filler: the wand, Shadow
--    Bolt, Drain Life, or Dark Harvest. The wand filler degrades to Shadow
--    Bolt when no wand is equipped, so a level 1 warlock (Shadow Bolt only)
--    still nukes. Dark Harvest wands (or Shadow Bolts) the gap between its
--    own cooldowns instead of leaving the rotation idle.
--  * Optional Life Tap when mana is low and health is high.
--  * Nightfall reaction: a free instant Shadow Bolt the moment Shadow Trance
--    procs. This auto-enables when the Nightfall talent is detected (the one
--    place a talent-tree read helps here; almost everything else is covered
--    by KnowsSpell since talented spells appear in the spellbook).
--  * The pet is sent onto the target when enabled.
-- Cast-time spells are queued with QueueSpellByName when available, so
-- the rotation never clips the current cast.
-- ============================================================

local M = AutoRota:NewClassModule("WARLOCK")
M.uiTitle = "Warlock"
M.uiHeight = 716
M.meleeAutoAttack = false   -- caster, no white melee swing

-- Talent that turns on the free instant Shadow Bolt proc (Shadow Trance).
-- It grants no spell, so KnowsSpell cannot see it; reading the talent rank is
-- the only way to know it is present. Adjust the name here if Turtle renames it.
local TALENT_NIGHTFALL = "Nightfall"

-- Dark Harvest base (pre-talent) channel length in seconds. SuperCleveRoidMacros'
-- TWoW-specific Dark Harvest handling (Utility.lua, credited to Avitasia/
-- Cursive) uses 8s as the base. Confirmed in-game: Rapid Deterioration also
-- shortens the channel itself by the same percentage as the three DoTs it
-- affects (8s * 0.94 = 7.52s matches the tooltip exactly at rank 2), so this
-- is scaled by RapidDeteriorationPct just like Corruption/Curse of Agony/
-- Siphon Life - see DHChannelLength below, use that instead of this raw base.
local DH_CHANNEL_BASE = 8

-- Dark Harvest boosts this warlock's own DoT tick rate by 30% on the target
-- for the length of its (talent-scaled) channel, which also burns through the
-- DoTs' own remaining duration 30% faster while it runs. So a DoT needs a full
-- channel's worth of *accelerated* life left, i.e. channel * (1 + boost)
-- seconds of normal remaining duration, to survive the whole channel. Any
-- enabled DoT with less than that is topped up first (see DotRemaining, which
-- also backs this boost out of its estimate for a channel that already ran).
local DH_TICK_BOOST = 0.30

-- Once an enabled DoT is due to fall off within this many seconds, the wand
-- filler stops (or does not start) feeding new shots. Reacting only after the
-- DoT is actually gone risks the recast racing a wand shot already in
-- flight; holding off a moment early instead means the wand is idle - not
-- mid-shot - by the time the DoT genuinely needs recasting.
local WAND_STOP_BEFORE_DOT = 1.5

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- Channel-clip protection (merged from the modified branch). Drain Life and
-- Drain Soul are channels; once one is running the rotation must not queue a
-- DoT refresh or the filler over it. This frame flags while any channel runs
-- and clears the instant it stops (including an early stop when the target
-- dies mid-channel).
M.channeling = false
M.chanStart = 0
-- Nightfall single-use tracking (merged from the modified branch). The instant
-- Shadow Bolt from a Shadow Trance proc is spent once per proc; the icon can
-- linger after the proc is consumed, so we consume on the rising edge and rearm
-- only once the icon clears.
M.stConsumed = false
M.stConsumedAt = 0
local wlChannelFrame = CreateFrame("Frame")
wlChannelFrame:RegisterEvent("SPELLCAST_CHANNEL_START")
wlChannelFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
wlChannelFrame:SetScript("OnEvent", function()
    if event == "SPELLCAST_CHANNEL_START" then
        M.channeling = true; M.chanStart = GetTime()
    elseif event == "SPELLCAST_CHANNEL_STOP" then
        M.channeling = false
    end
end)

-- Confirms whether a DoT cast sent via QueueDot actually landed, using
-- SuperWoW's UNIT_CASTEVENT (casterGUID, targetGUID, type, spellId,
-- castDuration; type is one of START/CAST/FAIL/CHANNEL/MAINHAND/OFFHAND).
-- dotThrottle is only stamped on a confirmed CAST; a FAIL (most commonly the
-- GCD still being active while the wand fires) just drops the pending mark,
-- so ApplyDot retries on the very next press instead of blanking out the
-- full interval on a cast that never happened. Requires SpellInfo (spell id
-- -> name) to resolve which of our pending DoTs the event is about.
local wlCastEventFrame = CreateFrame("Frame")
wlCastEventFrame:RegisterEvent("UNIT_CASTEVENT")
wlCastEventFrame:SetScript("OnEvent", function()
    if event ~= "UNIT_CASTEVENT" or not SpellInfo then return end
    if not M.playerGUID then
        local _, guid = UnitExists("player")
        M.playerGUID = guid
    end
    if not M.playerGUID or arg1 ~= M.playerGUID then return end
    if arg3 ~= "CAST" and arg3 ~= "FAIL" then return end
    local name = SpellInfo(arg4)
    if not name then return end
    local pend = M.dotPending[name]
    if not pend or pend.id ~= arg2 then return end
    M.dotPending[name] = nil
    if arg3 == "CAST" then
        M.dotThrottle[name] = { id = pend.id, t = GetTime() }
    end
end)

-- Debuff textures on the TARGET (fragment match)
M.dotTex = {
    ["Immolate"]     = "Immolation",                      -- Spell_Fire_Immolation
    ["Corruption"]   = "Spell_Shadow_AbominationExplosion",
    ["Siphon Life"]  = "Spell_Shadow_Requiem",
}

-- Curses the UI may offer. Only those with a verified texture get exact
-- upkeep, the rest are reapplied on a timer (see CurseInterval).
M.CURSES = {
    "Curse of Agony", "Curse of Weakness", "Curse of Recklessness",
    "Curse of the Elements", "Curse of Shadow", "Curse of Tongues", "Curse of Doom",
}
M.curseTex = {
    ["Curse of Agony"] = "Spell_Shadow_CurseOfSargeras",
    -- Add more here once confirmed in game with /ar debug.
}

-- Base duration in seconds for each DoT, used only to estimate remaining time
-- before starting Dark Harvest (see DotRemaining/DHMinDotRemain below).
-- 1.12 has no API for a debuff's remaining time, so this pairs the known,
-- rank-independent duration with our own last-cast timestamp. Adjust here if
-- Turtle's values differ from stock classic. These are pre-Rapid Deterioration
-- base values; DotRemaining applies that talent's reduction on top (below).
M.dotDuration = {
    ["Immolate"]              = 15,
    ["Corruption"]            = 18,
    ["Siphon Life"]           = 30,
    ["Curse of Agony"]        = 24,
    ["Curse of Weakness"]     = 120,
    ["Curse of Recklessness"] = 120,
    ["Curse of the Elements"] = 300,
    ["Curse of Shadow"]       = 300,
    ["Curse of Tongues"]      = 30,
    ["Curse of Doom"]         = 60,
}

-- Rapid Deterioration (Turtle-specific Affliction talent): 2 ranks, 3% shorter
-- duration per rank in exchange for more damage per tick. Confirmed in-game at
-- rank 2 (6% total): Corruption 18s->~17s, Curse of Agony 24s->~22.5s, Siphon
-- Life 30s->~28s. Only these three are affected: not Immolate (Destruction) or
-- the other curses. Scales with the rank actually taken, not just presence.
M.rapidDetSpells = { ["Corruption"] = true, ["Curse of Agony"] = true, ["Siphon Life"] = true }
local TALENT_RAPID_DETERIORATION = "Rapid Deterioration"
local RAPID_DETERIORATION_PCT_PER_RANK = 3

-- Tick count for the three Dark-Harvest-eligible DoTs at max rank, taken
-- directly from Cursive's spells/warlock.lua (numTicks field) so our tick
-- alignment matches its verified GetLastTickTime exactly: Corruption 18s/6
-- ticks, Curse of Agony 24s/12 ticks, Siphon Life 30s/10 ticks - all a flat
-- rate regardless of Rapid Deterioration, since duration and tick count
-- shrink together (tick interval scales, tick count does not).
M.dotNumTicks = { ["Corruption"] = 6, ["Curse of Agony"] = 12, ["Siphon Life"] = 10 }

-- Filler universe
M.FILLERS = { "Shoot", "Shadow Bolt", "Drain Life", "Dark Harvest" }

M.templates = {
    starter = {  -- usable from level 1: the filler is the wand, which falls
                 -- back to Shadow Bolt when no wand is equipped, so a fresh
                 -- warlock nukes with Shadow Bolt and the DoTs/curse switch
                 -- themselves on as they are learned. Drain-tank survival and
                 -- the Drain Soul shard finisher are on for leveling.
        useImmolate = true, curse = "Curse of Agony", useCorruption = true, useSiphonLife = false,
        filler = "Shoot", petAttack = true,
        lifeTap = false, lifeTapMana = 20, lifeTapHpMin = 40,
        drainLifeSustain = true, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = false, shadowburnHp = 20,
        useDrainSoul = true, drainSoulHp = 20,
    },
    affliction = {
        useImmolate = false, curse = "Curse of Agony", useCorruption = true, useSiphonLife = true,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
        drainLifeSustain = true, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = false, shadowburnHp = 20,
        useDrainSoul = false, drainSoulHp = 20,
    },
    destruction = {
        useImmolate = true, curse = "Curse of the Elements", useCorruption = false, useSiphonLife = false,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
        drainLifeSustain = false, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = true, shadowburnHp = 20,
        useDrainSoul = false, drainSoulHp = 20,
    },
}

M.curseAlias = {
    agony = "Curse of Agony", coa = "Curse of Agony",
    weakness = "Curse of Weakness", cow = "Curse of Weakness",
    recklessness = "Curse of Recklessness", cor = "Curse of Recklessness",
    elements = "Curse of the Elements", coe = "Curse of the Elements",
    shadow = "Curse of Shadow", cos = "Curse of Shadow",
    tongues = "Curse of Tongues", cot = "Curse of Tongues",
    doom = "Curse of Doom", cod = "Curse of Doom",
    none = "",
}

function M:NormalizeProfile(c)
    if c.useImmolate == nil then c.useImmolate = true end
    if c.curse == nil then c.curse = "Curse of Agony" end
    if c.useCorruption == nil then c.useCorruption = true end
    if c.useSiphonLife == nil then c.useSiphonLife = false end
    if c.filler == nil then c.filler = "Shoot" end
    if c.petAttack == nil then c.petAttack = true end
    if c.petMeleeOnly == nil then c.petMeleeOnly = false end
    if c.lifeTap == nil then c.lifeTap = false end
    if c.lifeTapMana == nil then c.lifeTapMana = 20 end
    if c.lifeTapHpMin == nil then c.lifeTapHpMin = 40 end
    if c.wandManaFloor == nil then c.wandManaFloor = 15 end
    if c.nightfall == nil then c.nightfall = false end
    if c.drainLifeSustain == nil then c.drainLifeSustain = false end
    if c.drainLifeHp == nil then c.drainLifeHp = 35 end
    if c.healthFunnel == nil then c.healthFunnel = false end
    if c.healthFunnelPetHp == nil then c.healthFunnelPetHp = 50 end
    if c.healthFunnelHpMin == nil then c.healthFunnelHpMin = 45 end
    if c.useShadowburn == nil then c.useShadowburn = false end
    if c.shadowburnHp == nil then c.shadowburnHp = 20 end
    if c.useDrainSoul == nil then c.useDrainSoul = false end
    if c.drainSoulHp == nil then c.drainSoulHp = 20 end
    if c.coaSecondary == nil then c.coaSecondary = false end
    if c.keepShards == nil then c.keepShards = false end
    if c.shardTarget == nil then c.shardTarget = 3 end
    return c
end

function M:AvailableCursesOf()
    local out = {}
    for i = 1, table.getn(self.CURSES) do
        if self:KnowsSpell(self.CURSES[i]) then table.insert(out, self.CURSES[i]) end
    end
    return out
end

-- Everything in the warlock kit is gated by KnowsSpell in the rotation, and
-- the filler falls back to Shadow Bolt when the chosen one is not usable yet
-- (see ResolveFiller), so nothing here is strictly required. A profile is
-- never flagged just because an ability is not trained yet: a level 1 warlock
-- whose only damage is Shadow Bolt reads as a clean, usable profile and the
-- DoTs/curse switch themselves on as they are learned. Mirrors the hunter and
-- druid, which do not flag not-yet-learned abilities.
function M:ProfileValidity(cfg)
    return true, {}
end

-- True while the wand is auto-repeating. The last seen auto-repeat slot is
-- cached, so the common case (already wanding) costs a single check; the
-- full action bar scan only runs when the cached slot is not repeating.
function M:Wanding()
    local slot = self.wandSlot
    if slot and IsAutoRepeatAction(slot) then return true end
    for s = 1, 120 do
        if IsAutoRepeatAction(s) then self.wandSlot = s; return true end
    end
    return false
end

-- A wand is equipped when there is an item in the ranged slot (18); warlocks
-- can only put wands there. Used so the "Shoot" filler degrades gracefully
-- when no wand is available (notably at level 1).
function M:HasWand()
    return GetInventoryItemLink("player", 18) ~= nil
end

-- Resolve the configured filler to one that can actually fire right now.
-- The wand filler needs a wand equipped; a spell filler needs to be learned.
-- When neither holds, fall back to Shadow Bolt (the warlock's level 1 nuke and
-- universal filler) so the rotation always has something to cast while
-- leveling. Returns nil only if even Shadow Bolt is somehow unknown.
function M:ResolveFiller(cfg)
    local f = cfg.filler or "Shoot"
    if f == "Shoot" then
        if self:HasWand() then return "Shoot" end
        if self:KnowsSpell("Shadow Bolt") then return "Shadow Bolt" end
        return nil
    end
    if self:KnowsSpell(f) then return f end
    if self:KnowsSpell("Shadow Bolt") then return "Shadow Bolt" end
    return nil
end

-- Queue a known spell. Normally this uses SuperWoW's cast queue so a
-- cast in progress is not clipped. While the wand is auto-repeating,
-- though, a queued cast would have to wait for the current shot (up to
-- the full wand speed), which shows up as a pause after a target switch.
-- In that case cast directly instead, which interrupts the wand and fires
-- now. This must always end up taking SOME action here (direct cast or
-- queue): an earlier version added an IsReady gate that returned with
-- nothing done when the GCD looked active, on the assumption the very next
-- press would catch it once ready. In testing that starved the rotation
-- completely once the wand was running - IsReady evidently does not clear
-- reliably while auto-repeat is active on this server, so that gate was a
-- dead end rather than an optimization. Removed; always act.
function M:Queue(name)
    if not self:KnowsSpell(name) then return false end
    if self:Wanding() or not QueueSpellByName then
        CastSpellByName(name)
    else
        QueueSpellByName(name)
    end
    return true
end

-- True while the Nightfall proc (Shadow Trance) is on the warlock.
function M:ShadowTranceUp()
    if self:HasBuff("Shadow Trance") then return true end
    for i = 1, 32 do
        local b = UnitBuff("player", i)
        if b and string.find(b, "Spell_Shadow_Twilight") then return true end
    end
    return false
end

function M:PetHPPct()
    if not UnitExists("pet") then return 100 end
    local mx = UnitHealthMax("pet")
    if mx and mx > 0 then return UnitHealth("pet") / mx * 100 end
    return 100
end

-- Talent rank by name, cached and cleared on CHARACTER_POINTS_CHANGED / login
-- (see the frame at the bottom of this file). Same approach as the paladin.
-- Used only for talents that grant no spell (so KnowsSpell cannot see them).
function M:TalentRank(name)
    if not self.talentCache then self.talentCache = {} end
    if self.talentCache[name] ~= nil then return self.talentCache[name] end
    local rank = 0
    local tabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    for tab = 1, tabs do
        for i = 1, GetNumTalents(tab) do
            local n, _, _, _, r = GetTalentInfo(tab, i)
            if n == name then rank = r or 0; break end
        end
        if rank > 0 then break end
    end
    self.talentCache[name] = rank
    return rank
end

-- Nightfall (Shadow Trance proc) is a passive talent with no spell of its own,
-- so we read the talent tree to know it is present and react to the proc
-- automatically, even if the manual toggle is off.
function M:HasNightfall()
    return self:TalentRank(TALENT_NIGHTFALL) > 0
end

-- Rapid Deterioration is also a no-spell passive, read the same way. Returns
-- the total percent duration reduction for the rank actually taken (0, 3, or 6).
function M:RapidDeteriorationPct()
    return self:TalentRank(TALENT_RAPID_DETERIORATION) * RAPID_DETERIORATION_PCT_PER_RANK
end

-- Dark Harvest's own channel length, scaled by Rapid Deterioration exactly
-- like the three DoTs it affects (confirmed in-game: 8s base -> 7.52s tooltip
-- at rank 2, i.e. the same 6% cut). Use this instead of DH_CHANNEL_BASE
-- anywhere the actual channel length matters.
function M:DHChannelLength()
    return DH_CHANNEL_BASE * (1 - self:RapidDeteriorationPct() / 100)
end

-- Minimum DoT time remaining needed to survive a full Dark Harvest channel at
-- its 30%-accelerated tick rate (see DH_TICK_BOOST above).
function M:DHMinDotRemain()
    return self:DHChannelLength() * (1 + DH_TICK_BOOST)
end

-- Number of Soul Shards across all bags (they stack, so sum the counts).
function M:CountSoulShards()
    local total = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots then
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Soul Shard") then
                    local _, count = GetContainerItemInfo(bag, slot)
                    total = total + (count or 1)
                end
            end
        end
    end
    return total
end

function M:TargetHasTexture(frag)
    if not frag or frag == "" then return false end
    return self:TargetDebuffUp(nil, frag)
end

function M:CurseTex(name)
    return self.curseTex[name]
end

-- Estimated seconds left on a DoT we currently have on the target, or nil if
-- its duration is unknown or we have no record of casting it on this target.
-- Approximated from our own last-(re)cast timestamp (dotThrottle) plus the
-- spell's known base duration, since 1.12 exposes no real remaining-time API
-- for target debuffs. Only meant to gate the Dark Harvest start (see
-- DHMinDotRemain); it is not precise enough to drive normal DoT upkeep.
--
-- The Dark Harvest correction below is a direct port of Cursive's verified
-- curses:TrackDarkHarvest / GetLastTickTime / GetDarkHarvestReduction
-- (curses.lua), not our own guess: align the boost's start to this DoT's own
-- last tick at-or-before the channel, then charge 30% of the resulting active
-- span. One simplification versus Cursive: Cursive polls this live, including
-- while a channel is still running, so it tracks dhStartTime/dhEndTime as two
-- separate fields. We only ever call this once any channel has already ended
-- (Rotate()'s guard returns early while self.dhEnd is still in the future),
-- so there is no "currently channeling" case to handle - only "did the last
-- completed channel on this target overlap this DoT's lifetime".
function M:DotRemaining(spellName)
    local dur = self.dotDuration[spellName]
    if not dur then return nil end
    if self.rapidDetSpells[spellName] then
        dur = dur * (1 - self:RapidDeteriorationPct() / 100)
    end
    local id = self:TargetId()
    local rec = self.dotThrottle[spellName]
    if not rec or rec.id ~= id then return nil end
    local now = GetTime()
    local remain = dur - (now - rec.t)

    local ticks = self.dotNumTicks[spellName]
    if ticks and self.dhStart and self.dhEnd and self.dhTarget == id
        and self.dhStart < rec.t + dur and self.dhEnd > rec.t then
        local tickTime = dur / ticks
        local dhStartTime = math.floor((self.dhStart - rec.t) / tickTime) * tickTime + rec.t
        if dhStartTime < rec.t then dhStartTime = rec.t end
        local dhActiveTime = self.dhEnd - dhStartTime
        if dhActiveTime > 0 then
            remain = remain - dhActiveTime * DH_TICK_BOOST
        end
    end
    return remain
end

-- True when any enabled, tracked DoT is due to fall off within
-- WAND_STOP_BEFORE_DOT seconds (see there). A DoT with no confident estimate
-- (DotRemaining returns nil) never counts, matching the "unknown is not
-- urgent" stance used for the Dark Harvest pre-check.
function M:DotExpiringSoon(order)
    for i = 1, table.getn(order) do
        local sp = order[i][1]
        if self:KnowsSpell(sp) then
            local remain = self:DotRemaining(sp)
            if remain and remain <= WAND_STOP_BEFORE_DOT then
                return true
            end
        end
    end
    return false
end

-- Throttle memory per DoT, keyed by target GUID. Only stamped once
-- UNIT_CASTEVENT confirms the cast actually landed (see the frame near the
-- end of this file) - not the instant it is sent.
M.dotThrottle = {}

-- Casts sent but not yet confirmed CAST or FAIL by UNIT_CASTEVENT, keyed by
-- spell name -> { id = targetId at cast time, t = time sent }.
M.dotPending = {}

-- Send a DoT cast and mark it pending confirmation. dotThrottle is only
-- stamped once UNIT_CASTEVENT confirms it actually went out (CAST), so a
-- cast that silently fails (e.g. the GCD was still active) is retried on the
-- very next press instead of blocking for the full interval on a guess -
-- this replaced an earlier version that stamped the throttle optimistically
-- right here, which is exactly what caused that multi-second stall.
function M:QueueDot(spellName, id)
    self.dotPending[spellName] = { id = id, t = GetTime() }
    self:Queue(spellName)
end

-- Apply or maintain one DoT. Returns:
--   "up"   the effect is present (or assumed present within its interval)
--   "cast" a cast was sent this press
--   "wait" recently cast (confirmed or still awaiting confirmation) and
--          landing/pending, do nothing further this press
-- Detection prefers the exact spell name (SuperWoW id path), then the icon
-- fragment. When the effect is detectable (a texture is known, or SuperWoW can
-- resolve names), missing-but-recent counts as "wait" so the cast is allowed to
-- land before re-queuing. Otherwise recent counts as "up" and the effect is
-- simply reapplied on the interval, the old texture-less blind-timer path.
function M:ApplyDot(spellName, texFrag, interval)
    interval = interval or 3
    if self:TargetDebuffUp(spellName, texFrag) then return "up" end
    local detectable = (texFrag ~= nil) or AutoRota:CanResolveDebuffNames()
    local id = self:TargetId()
    local rec = self.dotThrottle[spellName]
    local now = GetTime()
    if self.trace then
        local throttleAge = (rec and rec.id == id and rec.t) and (now - rec.t) or -1
        local pend = self.dotPending[spellName]
        local pendAge = (pend and pend.id == id) and (now - pend.t) or -1
        self:Trace(string.format("%s missing wanding=%s throttleAge=%.2f pendAge=%.2f",
            spellName, tostring(self:Wanding()), throttleAge, pendAge))
    end
    if rec and rec.id == id and rec.t and (now - rec.t) <= interval then
        if detectable then return "wait" else return "up" end
    end
    -- A cast already sent is still awaiting CAST/FAIL confirmation. A 2s
    -- ceiling (comfortably above normal ack latency) guards against a missed
    -- event so this can never get stuck waiting forever.
    local pend = self.dotPending[spellName]
    if pend and pend.id == id and (now - pend.t) <= 2 then
        return "wait"
    end
    self:QueueDot(spellName, id)
    return "cast"
end

-- ============================================================
-- Rotation. The core has already secured a target (no melee auto
-- attack for this class). One queued cast per press, DoTs first.
-- ============================================================
function M:Rotate(cfg)
    -- Send the pet in. With petMeleeOnly, only when the target is within melee
    -- range (the same gate as the melee auto-attack), so an accidentally
    -- targeted far enemy never pulls the pet away.
    if cfg.petAttack and UnitExists("pet") then
        if not cfg.petMeleeOnly or self:InMeleeRange() then PetAttack() end
    end

    -- Never act while a channel runs (Drain Life / Drain Soul), so a DoT refresh
    -- or the filler cannot clip it. The stop event also fires when the target
    -- dies mid-channel; a 16s ceiling guards against a missed stop so the
    -- rotation can never get stuck.
    if self.channeling and self.chanStart and (GetTime() - self.chanStart) < 16 then return end

    -- Protect a running Dark Harvest channel. While it channels, do nothing so
    -- neither the wand nor any spell clips it. The 30s cooldown is active for
    -- the whole channel, so OwnCDReady is false during it. If the target dies
    -- the cooldown resets to ready, which ends the protection at once and lets
    -- the next target be channeled immediately.
    -- The OwnCDReady read lags the actual cast by a tick or two (the client's
    -- cooldown API is not updated the instant the cast is queued), so trusting
    -- it right away raced a Rotate() call right after the channel started: it
    -- still saw the cooldown as "ready" and let another spell through, which
    -- clipped the channel it had just begun. A short unconditional grace
    -- window after dhStart closes that race; only past it does an early
    -- CD-ready reading (an early kill) end the protection ahead of time.
    if self.dhEnd and GetTime() < self.dhEnd and self:TargetId() == self.dhTarget then
        if (GetTime() - (self.dhStart or 0)) < 1 or not self:OwnCDReady("Dark Harvest") then
            return
        end
    end

    local nightfall = cfg.nightfall or self:HasNightfall()

    -- P0 Nightfall reaction (highest priority): spend the free instant Shadow
    -- Bolt the moment Shadow Trance procs. This costs no mana, no GCD beyond
    -- the instant cast itself, and clips nothing, so it is checked before any
    -- other priority. Left any lower and a channel started first (Drain Life,
    -- Drain Soul) can burn through the whole proc window before the rotation
    -- gets back around to it, wasting the proc entirely. Only the FIRST cast
    -- is instant; the proc is then gone even though the icon can linger, so a
    -- second cast would be a full-cast Shadow Bolt that clips the rotation.
    -- Fire on the rising edge only and rearm when the icon clears (a 15s
    -- ceiling, above the buff's duration, recovers from a missed clear).
    -- Skipped when Shadow Bolt is already the filler.
    if nightfall and cfg.filler ~= "Shadow Bolt" and self:KnowsSpell("Shadow Bolt") then
        if self:ShadowTranceUp() then
            if not self.stConsumed then
                self.stConsumed = true
                self.stConsumedAt = GetTime()
                self:Queue("Shadow Bolt")
                return
            elseif self.stConsumedAt and (GetTime() - self.stConsumedAt) > 15 then
                self.stConsumed = false
            end
        else
            self.stConsumed = false
        end
    end

    local hp     = self:PlayerHPPct()
    local thp    = self:TargetHPPct()

    -- P1 Drain Life self-heal: your survival comes first. Channels Drain Life
    -- when you drop below the threshold (the drain-tank safety net).
    if cfg.drainLifeSustain and self:KnowsSpell("Drain Life") and hp < (cfg.drainLifeHp or 35) then
        self:Queue("Drain Life")
        return
    end

    -- P2 Health Funnel: keep the pet alive when it drops, but only while you
    -- can spare the health (it transfers yours to the pet).
    if cfg.healthFunnel and self:KnowsSpell("Health Funnel") and UnitExists("pet")
        and self:PetHPPct() < (cfg.healthFunnelPetHp or 50) and hp > (cfg.healthFunnelHpMin or 45) then
        self:Queue("Health Funnel")
        return
    end

    -- P3 Shadowburn execute: instant finish under the execute threshold (costs
    -- a Soul Shard). On a cooldown, so it is gated by IsReady. Also gated on
    -- actually holding a shard: without one the cast fails in-game while
    -- IsReady/Queue both still report success, which would stall the rotation
    -- on a dead attempt instead of falling through to Drain Soul or the filler.
    if cfg.useShadowburn and self:KnowsSpell("Shadowburn") and self:IsReady("Shadowburn")
        and thp < (cfg.shadowburnHp or 20) and self:CountSoulShards() > 0 then
        if self:Queue("Shadowburn") then return end
    end

    -- P4 Drain Soul finisher: channel in the target's last seconds to bank a
    -- Soul Shard and regen mana. (If both this and Shadowburn are enabled,
    -- Shadowburn fires first when ready; this fills otherwise.) With
    -- keepShards on, it stops once shardTarget is banked so it does not keep
    -- draining a target you could just finish off with the filler.
    if cfg.useDrainSoul and self:KnowsSpell("Drain Soul") and thp < (cfg.drainSoulHp or 20)
        and (not cfg.keepShards or self:CountSoulShards() < (cfg.shardTarget or 0)) then
        self:Queue("Drain Soul")
        return
    end

    -- Low-mana safety valve. ApplyDot has no notion of cost, so without this a
    -- DoT that needs refreshing but cannot be afforded would still be queued,
    -- fail in-game, and stall the rotation on its throttle window doing
    -- nothing. Below the floor, prefer Life Tap if it is safe to use (it fixes
    -- the actual problem); otherwise drop to the wand, which is free and, on a
    -- target carrying a mana-return debuff (e.g. a paladin's Seal of Wisdom),
    -- can even help you recover.
    if self:ManaPct() < (cfg.wandManaFloor or 15) then
        if cfg.lifeTap and self:KnowsSpell("Life Tap") and hp > (cfg.lifeTapHpMin or 40) then
            self:Queue("Life Tap")
            return
        end
        if self:HasWand() then
            if self:Wanding() then return end
            if self.trace then
                self:Trace(string.format("wandstart ready=%s mana=%.0f hp=%.0f",
                    tostring(self:IsReady("Shoot")), self:ManaPct(), hp))
            end
            CastSpellByName("Shoot")
            return
        end
    end

    -- Build the ordered DoT list from the enabled, known effects.
    local order = {}
    if cfg.useImmolate then table.insert(order, { "Immolate", self.dotTex["Immolate"], 3 }) end
    if cfg.curse ~= "" then
        local tex = self:CurseTex(cfg.curse)
        -- Exact upkeep when the curse is detectable (known icon, or SuperWoW
        -- name resolution); only a curse we cannot see at all falls back to the
        -- 20s blind reapply timer.
        local detectable = tex or AutoRota:CanResolveDebuffNames()
        table.insert(order, { cfg.curse, tex, detectable and 3 or 20 })
    end
    -- Malediction secondary curse: with that talent Curse of Agony coexists
    -- with the main curse, but expires sooner and is otherwise unmonitored.
    -- When enabled, keep it up on its own. Skipped if the main curse already
    -- is Curse of Agony, or is Curse of Doom, which the talent does not
    -- combine with.
    if cfg.coaSecondary and self:KnowsSpell("Curse of Agony")
        and cfg.curse ~= "Curse of Agony" and cfg.curse ~= "Curse of Doom" then
        local coaTex = self:CurseTex("Curse of Agony")
        local coaDetectable = coaTex or AutoRota:CanResolveDebuffNames()
        table.insert(order, { "Curse of Agony", coaTex, coaDetectable and 3 or 20 })
    end
    if cfg.useCorruption then table.insert(order, { "Corruption", self.dotTex["Corruption"], 3 }) end
    if cfg.useSiphonLife then table.insert(order, { "Siphon Life", self.dotTex["Siphon Life"], 3 }) end

    if self.trace then
        local up = ""
        for i = 1, table.getn(order) do
            local sp, tex = order[i][1], order[i][2]
            up = up .. " " .. sp .. "=" .. (tex and (self:TargetHasTexture(tex) and "Y" or "n") or "?")
        end
        self:Trace("dots" .. up .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    for i = 1, table.getn(order) do
        local sp, tex, iv = order[i][1], order[i][2], order[i][3]
        if self:KnowsSpell(sp) then
            local st = self:ApplyDot(sp, tex, iv)
            if st == "cast" or st == "wait" then return end
            -- "up": continue to the next DoT
        end
    end

    -- All enabled DoTs up. Optional Life Tap, then the filler.
    if cfg.lifeTap and self:KnowsSpell("Life Tap") then
        if self:ManaPct() < (cfg.lifeTapMana or 20) and self:PlayerHPPct() > (cfg.lifeTapHpMin or 40) then
            self:Queue("Life Tap")
            return
        end
    end

    -- Dark Harvest is cooldown-gated rather than learned/unlearned, so it needs
    -- its own dispatch ahead of ResolveFiller: channel it the instant it is off
    -- cooldown, otherwise wand-fill the gap (degrading to Shadow Bolt if no
    -- wand is equipped) so the rotation is never idle between channels.
    if cfg.filler == "Dark Harvest" and self:KnowsSpell("Dark Harvest") then
        if self:OwnCDReady("Dark Harvest") then
            -- Every enabled DoT is already up at this point (the loop above
            -- only falls through once none of them needed casting). Before
            -- committing to the channel, make sure none of them will fall off
            -- partway through it: top up anything estimated to have less than
            -- DHMinDotRemain() seconds left so the full channel ticks at the
            -- boosted rate. Unknown remaining time (no duration on file, or no
            -- cast record for this target) is not treated as urgent, so the
            -- channel is not blocked on a guess.
            local minRemain = self:DHMinDotRemain()
            if self.trace then
                local id = self:TargetId()
                for i = 1, table.getn(order) do
                    local sp = order[i][1]
                    if self:KnowsSpell(sp) then
                        local remain = self:DotRemaining(sp)
                        local rec = self.dotThrottle[sp]
                        self:Trace(string.format("DHcheck %s remain=%s min=%.2f rec=%s",
                            sp, remain and string.format("%.2f", remain) or "nil", minRemain,
                            (rec and rec.id == id) and "ok" or "missing/other-target"))
                    end
                end
            end
            for i = 1, table.getn(order) do
                local sp = order[i][1]
                if self:KnowsSpell(sp) then
                    local remain = self:DotRemaining(sp)
                    if remain and remain < minRemain then
                        self:QueueDot(sp, self:TargetId())
                        return
                    end
                end
            end
            self.dhStart = GetTime()
            self.dhEnd = self.dhStart + self:DHChannelLength()
            self.dhTarget = self:TargetId()
            self:Queue("Dark Harvest")
            return
        end
        if self:HasWand() then
            if self:DotExpiringSoon(order) then
                if self:Wanding() then CastSpellByName("Shoot") end -- toggles the repeat off
                return
            end
            if self:Wanding() then return end
            CastSpellByName("Shoot")
        elseif self:KnowsSpell("Shadow Bolt") then
            self:Queue("Shadow Bolt")
        end
        return
    end

    local filler = self:ResolveFiller(cfg)
    if filler == "Shoot" then
        if self:DotExpiringSoon(order) then
            -- A tracked DoT is about to fall off. Stop feeding the wand (or
            -- don't start it) instead of risking the recast racing a shot
            -- already in flight - Shoot toggles the repeat off when cast
            -- again while it is already running.
            if self:Wanding() then CastSpellByName("Shoot") end
            return
        end
        -- spammable wand, only start it if it is not already auto repeating
        if self:Wanding() then return end
        CastSpellByName("Shoot")
    elseif filler then
        self:Queue(filler)
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "curse" then
        local curse = self.curseAlias[string.lower(t[2] or "")]
        local cfg = AutoRota:GetActiveProfile()
        if cfg and curse ~= nil then
            cfg.curse = curse
            msgOut("curse = " .. ((curse == "") and "(none)" or curse) .. ".")
        else
            msgOut("usage: /ar curse <agony|elements|shadow|weakness|recklessness|tongues|doom|none>", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end

-- ============================================================
-- Talent cache invalidation. Cleared at login and whenever talent points
-- change, so TalentRank() (used for Nightfall detection) re-reads fresh data
-- on its next call. Same approach as the paladin.
-- ============================================================
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_LOGIN")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
talentFrame:SetScript("OnEvent", function()
    M.talentCache = nil
end)
