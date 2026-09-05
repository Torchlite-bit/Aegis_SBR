-- ============================================================
-- Class_Warlock  -  warlock module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). DoT priority, configurable, level 1+.
-- ============================================================
-- Model (mirrors the proven leveling macro):
--  * Keep the enabled damage-over-time effects up in priority order:
--    Immolate, the chosen Curse, Siphon Life, the Malediction Curse of
--    Agony, then Corruption (see the order block in Rotate for why).
--  * Below an optional target-health threshold no DoT is re-applied at all
--    (a fresh DoT never pays its mana back on a mob about to die), with an
--    opt-in exception for Corruption, the cheapest and shortest of them.
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
--    Bolt, Drain Life, Drain Soul, or Dark Harvest. The wand filler degrades
--    to Shadow Bolt when no wand is equipped, so a level 1 warlock (Shadow
--    Bolt only) still nukes. Drain Soul is there for the low-level warlock
--    with no wand yet; being a channel it stands down for a press whenever a
--    DoT would lapse while it runs. Dark Harvest fills the gap between its own cooldowns with
--    a configurable choice (dhGapFiller: wand, Shadow Bolt, Drain Life or
--    Drain Soul) instead of leaving the rotation idle.
--  * Optional Life Tap when mana is low and health is high.
--  * Nightfall reaction: a free instant Shadow Bolt the moment Shadow Trance
--    procs. This auto-enables when the Nightfall talent is detected (the one
--    place a talent-tree read helps here; almost everything else is covered
--    by KnowsSpell since talented spells appear in the spellbook).
--  * The pet is sent onto the target when enabled.
-- Cast-time spells are queued with QueueSpellByName when available, so
-- the rotation never clips the current cast.
-- ============================================================

local M = Aegis_SBR:NewClassModule("WARLOCK")
M.uiTitle = "Warlock"
-- Rotate runs under Aegis_SBR:Preview without casting (see Pick/Later).
M.previewReady = true
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

-- Dark Harvest's mana cost, read off the in-game tooltip (Rank 1/1, 230 mana -
-- it has a single rank, so there is no per-rank table to keep). Used only to
-- decide whether a ready channel is actually affordable before letting it take
-- priority over Life Tap (see the Life Tap block in Rotate). Deliberately
-- compared as a hard floor: understating it would let the rotation queue a
-- channel that fails in-game while the cooldown never starts, which stalls the
-- next press on the same dead attempt. Adjust here if Turtle changes the cost.
local DH_MANA = 230

-- Once an enabled DoT is due to fall off within this many seconds, the wand
-- filler stops (or does not start) feeding new shots. Reacting only after the
-- DoT is actually gone risks the recast racing a wand shot already in
-- flight; holding off a moment early instead means the wand is idle - not
-- mid-shot - by the time the DoT genuinely needs recasting.
local WAND_STOP_BEFORE_DOT = 1.5

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

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
-- The end of an ordinary cast, so a DoT waiting for confirmation is released on
-- evidence instead of on a two second timer.
--
-- ApplyDot answers "wait" while a cast it sent has not been confirmed, and the
-- caller returns from the WHOLE rotation on that answer - deliberately, because
-- Nampower's queue holds one spell and anything else would evict it. But when
-- the confirmation never arrives, that guess costs two full seconds of doing
-- nothing, spamming the button. Reported as the rotation stalling for a few
-- seconds; this is the only path in the module that can stall for that long.
wlChannelFrame:RegisterEvent("SPELLCAST_STOP")
wlChannelFrame:RegisterEvent("SPELLCAST_FAILED")
wlChannelFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
wlChannelFrame:SetScript("OnEvent", function()
    if event == "SPELLCAST_CHANNEL_START" then
        M.channeling = true
        M.chanStart = GetTime()
        -- Which channel this is. The event does not say, but Queue stamped the
        -- name through NoteSpellCast a moment ago, and that is the only thing
        -- that could have started one.
        M.chanSpell = Aegis_SBR.lastSpell
    elseif event == "SPELLCAST_CHANNEL_STOP" then
        M.channeling = false
        M.chanSpell = nil
    else
        -- A cast ended, one way or another. Nothing is left in the queue to
        -- protect, so no DoT should still be waiting on one.
        M.dotPending = {}
        -- And a channel that was INTERRUPTED is over too. This branch used to
        -- leave the channel flags alone, on the assumption that a broken channel
        -- would still announce itself through CHANNEL_STOP - which is exactly the
        -- event this client is unreliable about. So the rotation went on holding
        -- still for the channel's whole expected length after it had already been
        -- broken. Reported as the warlock standing there doing nothing.
        --
        -- FAILED is included: a channel refused at the moment it should have
        -- started never runs, and waiting out its length is the same mistake.
        if event == "SPELLCAST_INTERRUPTED" or event == "SPELLCAST_FAILED" then
            if M.channeling and Aegis_SBR.Tracing and Aegis_SBR:Tracing() then
                Aegis_SBR:Trace("channel " .. event .. " after "
                    .. string.format("%.1fs", GetTime() - (M.chanStart or GetTime())))
            end
            M.channeling = false
            M.chanSpell = nil
            -- Dark Harvest keeps its own protection window on top of this one,
            -- for the cooldown race described at that guard. It has the same
            -- blind spot and needs the same release.
            M.dhEnd = nil
        end
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
--
-- A RESIST is not a cast failure and never shows up here: the cast completes,
-- the spell is thrown away on landing. UNIT_CASTEVENT reports CAST, the throttle
-- is stamped as though the DoT were up, and every press for the next interval
-- reads "missing but recently cast" and answers "wait" - the rotation visibly
-- stalls for a couple of seconds on a DoT that was never applied. The combat log
-- is the only place that knows, so it is read below.
local wlCastEventFrame = CreateFrame("Frame")
wlCastEventFrame:RegisterEvent("UNIT_CASTEVENT")
-- "Your Corruption was resisted by X." - see the resist branch at the bottom.
wlCastEventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
-- Learned immunity is relearned every fight rather than remembered: a GUID
-- belongs to one mob for one pull, and carrying the table around for a session
-- would eventually answer for a different creature entirely.
wlCastEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
wlCastEventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_ENABLED" then
        M.dotImmune = {}
        return
    end
    if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        -- A resisted or missed DoT never landed, so both the confirmation stamp
        -- and any pending mark are wrong and are cleared: the next press applies
        -- it again immediately instead of waiting out the interval.
        --
        -- Deliberately NOT "immune". An immune target would turn an immediate
        -- retry into a loop, and the interval that suppresses it there is doing
        -- its job. Only genuinely wasted casts are unblocked here.
        if not arg1 then return end
        -- "Your Immolate failed. X is immune." Definitive, and the only signal
        -- there is. Recorded against the current target and only when the line
        -- names it, so a message about something else cannot silence a DoT here.
        if string.find(arg1, "immune") then
            local tname = UnitName("target")
            local _, guid = UnitExists("target")
            if not (tname and guid and string.find(arg1, tname, 1, true)) then return end
            local function mark(name)
                if string.find(arg1, name, 1, true) then
                    M.dotImmune[guid .. "|" .. name] = true
                    M.dotThrottle[name] = nil
                    M.dotPending[name] = nil
                    return true
                end
            end
            for name in pairs(M.dotTex) do if mark(name) then return end end
            for i = 1, table.getn(M.CURSES) do if mark(M.CURSES[i]) then return end end
            return
        end
        if not (string.find(arg1, "resist") or string.find(arg1, "miss")) then return end
        for name in pairs(M.dotTex) do
            if string.find(arg1, name, 1, true) then
                M.dotThrottle[name] = nil
                M.dotPending[name] = nil
                return
            end
        end
        for i = 1, table.getn(M.CURSES) do
            local name = M.CURSES[i]
            if string.find(arg1, name, 1, true) then
                M.dotThrottle[name] = nil
                M.dotPending[name] = nil
                return
            end
        end
        return
    end
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
    -- How long this confirmation took. The ceiling that decides how long the
    -- rotation may wait for the NEXT one is built from these, so it tracks the
    -- connection instead of a number somebody picked once.
    M:NoteConfirmLatency(GetTime() - pend.t)
    if arg3 == "CAST" then
        -- One arriving confirmation is the proof that confirmations arrive on
        -- this client. Until that has happened even once, QueueDot stamps the
        -- throttle itself - see there.
        M.castEventSeen = true
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
-- Set form of the list above, for "is this spell a curse" tests.
M.curseIsA = {}
for i = 1, table.getn(M.CURSES) do M.curseIsA[M.CURSES[i]] = true end

M.curseTex = {
    ["Curse of Agony"] = "Spell_Shadow_CurseOfSargeras",
    -- The rest are LEARNED rather than listed; see CurseTex below. A guessed
    -- fragment re-casts the curse every three seconds forever, which is why
    -- this table only ever holds icons somebody confirmed in game.
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
local TALENT_IMP_CORRUPTION = "Improved Corruption"
local TALENT_BANE = "Bane"

-- Base cast time of each DoT we apply. Anything absent is instant, which covers
-- every curse and Siphon Life.
--
-- Needed for one question only: may this be cast while moving. Movement breaks a
-- cast exactly as it breaks a channel, and the shape of that failure is worse -
-- the rotation RETURNS after sending a DoT, so a cast movement keeps breaking
-- takes every press and nothing else ever runs. Reported as "hangups in rotation
-- and dot wasnt applied while moving", which is both halves of the same defect.
--
-- The talent reductions are the vanilla ones. If Turtle has changed a number,
-- the symptom is mild and visible - a DoT skipped while running that could have
-- landed - and `/sbr talents` prints the exact talent names to correct against.
local DOT_CAST_TIME = {
    ["Corruption"] = 2.0,   -- Improved Corruption: -0.4s per rank, instant at 5/5
    ["Immolate"]   = 2.0,   -- Bane: -0.1s per rank, never instant
}
local RAPID_DETERIORATION_PCT_PER_RANK = 3

-- Tick count for the three Dark-Harvest-eligible DoTs at max rank, taken
-- directly from Cursive's spells/warlock.lua (numTicks field) so our tick
-- alignment matches its verified GetLastTickTime exactly: Corruption 18s/6
-- ticks, Curse of Agony 24s/12 ticks, Siphon Life 30s/10 ticks - all a flat
-- rate regardless of Rapid Deterioration, since duration and tick count
-- shrink together (tick interval scales, tick count does not).
M.dotNumTicks = { ["Corruption"] = 6, ["Curse of Agony"] = 12, ["Siphon Life"] = 10 }

-- Filler universe
M.FILLERS = { "Shoot", "Shadow Bolt", "Drain Life", "Drain Soul", "Dark Harvest" }

-- What fills the gap while Dark Harvest is on cooldown. Only consulted when
-- Dark Harvest is the chosen filler; the wand stays the default because it is
-- free. Drain Soul is here by user request (a player who does not want to wand
-- at all) - note it is a CHANNEL, which is why DS_CHANNEL_BASE below exists.
M.GAP_FILLERS = { "Shoot", "Shadow Bolt", "Drain Life", "Drain Soul" }

-- Drain Soul's base channel length on Turtle. NOT the vanilla 15s: confirmed
-- in-game at 5.64s with Rapid Deterioration 2/2, and 6 * 0.94 = 5.64 exactly,
-- so the base is 6 and the talent scales it - the same relationship already
-- established for Dark Harvest (8 -> 7.52 at the same rank). Use
-- DSChannelLength() rather than this raw base.
--
-- Only used to decide whether STARTING a channel is safe, never to track a
-- running one (the SPELLCAST_CHANNEL_* watcher does that). Two things must not
-- happen while it runs, because the channel guard stops the rotation acting at
-- all: a DoT lapsing unrefreshed, and Dark Harvest coming off cooldown with
-- nobody there to press it.
local DS_CHANNEL_BASE = 6

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
        dotStopHp = 20, dotStopKeepCorruption = true,
    },
    affliction = {
        -- Dark Harvest is the Affliction capstone and the strongest filler by a
        -- wide margin (it also accelerates the shadow DoTs already ticking), so
        -- it leads here. Until it is talented, ResolveFiller drops to the wand -
        -- deliberately not Shadow Bolt, which is far too mana-hungry to spam as
        -- a filler; it stays reserved for the free Shadow Trance procs.
        useImmolate = false, curse = "Curse of Agony", useCorruption = true, useSiphonLife = true,
        filler = "Dark Harvest", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
        drainLifeSustain = true, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = false, shadowburnHp = 20,
        useDrainSoul = false, drainSoulHp = 20,
        dotStopHp = 20, dotStopKeepCorruption = true,
    },
    destruction = {
        -- Shadow Bolt stays the filler here: Destruction never reaches Dark
        -- Harvest, and its whole kit is built around Shadow Bolt spam.
        useImmolate = true, curse = "Curse of the Elements", useCorruption = false, useSiphonLife = false,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
        drainLifeSustain = false, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = true, shadowburnHp = 20,
        useDrainSoul = false, drainSoulHp = 20,
        dotStopHp = 20, dotStopKeepCorruption = true,
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
    -- What fills the gap while Dark Harvest is on cooldown (Dark Harvest filler
    -- only). Defaults to the wand, which is what the gap used to be hardcoded to.
    if c.dhGapFiller == nil then c.dhGapFiller = "Shoot" end
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
    -- Execute-phase DoT stop. Defaults to 0 (off) rather than the templates'
    -- 20, so a profile saved before this existed keeps its old behaviour until
    -- the slider is moved; fresh profiles get the efficiency straight away.
    if c.dotStopHp == nil then c.dotStopHp = 0 end
    if c.dotStopKeepCorruption == nil then c.dotStopKeepCorruption = true end
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
-- When the chosen one cannot fire, fall back to the WAND first and only then to
-- Shadow Bolt: spamming Shadow Bolt as a filler burns far more mana than it is
-- worth (it is kept for the free Shadow Trance procs instead), while the wand
-- costs nothing. This matters most for an Affliction profile set to Dark
-- Harvest before the capstone is talented - that used to silently fall through
-- to Shadow Bolt spam. Shadow Bolt remains the last resort so a warlock with no
-- wand equipped still has something to cast; nil only if even that is unknown.
function M:ResolveFiller(cfg)
    local f = cfg.filler or "Shoot"
    if f ~= "Shoot" and self:KnowsSpell(f) then return f end
    if self:HasWand() then return "Shoot" end
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
-- Everything that CHANNELS. Movement breaks a channel outright, so starting one
-- while running is not a slightly worse cast - it is a global cooldown spent on
-- nothing at all.
M.CHANNELED = {
    ["Drain Life"]    = true,
    ["Drain Soul"]    = true,
    ["Dark Harvest"]  = true,
    ["Health Funnel"] = true,
}

function M:Queue(name, reason)
    if not self:KnowsSpell(name) then return false end
    -- Moving: refuse every channel, and let the caller fall through to whatever
    -- it would have done otherwise. Refused here rather than at each decision
    -- so no channel site can be forgotten - there are six of them.
    --
    -- The affliction rotation is built for exactly this: instant DoTs, the
    -- instant Shadow Bolt off a Nightfall proc, and channels. Only the last of
    -- those cares where you are standing, so moving costs nothing but the
    -- channel, and standing still runs the complete rotation.
    if M.CHANNELED[name] and Aegis_SBR:Moving() then
        if self:Tracing() then self:Trace("moving, no " .. name) end
        return false
    end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name; p.reason = reason; p.queue = true
        return true
    end
    Aegis_SBR:NoteSpellCast(name)
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

-- 100 means "nothing to heal here", which covers both no pet and a dead one -
-- a dead pet still EXISTS as a unit and reads 0 health, so without the second
-- test every pet-health gate in the module fires at a corpse.
function M:PetHPPct()
    if not UnitExists("pet") or UnitIsDead("pet") then return 100 end
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

-- Cast time of a DoT for THIS character, talents included. 0 means instant.
function M:DotCastTime(spell)
    local t = DOT_CAST_TIME[spell]
    if not t then return 0 end
    if spell == "Corruption" then
        t = t - 0.4 * self:TalentRank(TALENT_IMP_CORRUPTION)
    elseif spell == "Immolate" then
        t = t - 0.1 * self:TalentRank(TALENT_BANE)
    end
    if t < 0 then t = 0 end
    return t
end

-- Dark Harvest's own channel length, scaled by Rapid Deterioration exactly
-- like the three DoTs it affects (confirmed in-game: 8s base -> 7.52s tooltip
-- at rank 2, i.e. the same 6% cut). Use this instead of DH_CHANNEL_BASE
-- anywhere the actual channel length matters.
function M:DHChannelLength()
    return DH_CHANNEL_BASE * (1 - self:RapidDeteriorationPct() / 100)
end

-- Drain Soul's channel length, scaled by Rapid Deterioration exactly like Dark
-- Harvest's (see DS_CHANNEL_BASE for the in-game confirmation).
function M:DSChannelLength()
    return DS_CHANNEL_BASE * (1 - self:RapidDeteriorationPct() / 100)
end

-- How long each channel is expected to run, for the stall guard in Rotate.
--
-- The talent matters more here than anywhere else: Rapid Deterioration cuts
-- these durations, and a guard that waited for the UNSHORTENED length would sit
-- idle for exactly the time the talent saves - turning a damage talent into
-- dead air. It is applied only where the module has confirmed it in game (Dark
-- Harvest 8 -> 7.52 at rank 2, and Drain Soul the same way); Drain Life and
-- Health Funnel use their base length, because whether the talent touches them
-- has not been established and guessing SHORT is the direction that clips a
-- channel.
local CHANNEL_BASE = {
    ["Drain Life"]    = 5,
    ["Health Funnel"] = 10,
}
local CHANNEL_TALENTED = {
    ["Drain Soul"]   = true,
    ["Dark Harvest"] = true,
}

-- Grace on top, so a channel that runs marginally longer than the table says is
-- never cut off. Small: the whole point is to stop waiting, and the measured
-- overshoot being repaired here was three to four times this.
local CHANNEL_GRACE = 0.25

-- ============================================================
-- How long to wait for a confirmation
-- ============================================================
-- ApplyDot holds the whole rotation while a DoT it sent is unconfirmed, so the
-- ceiling on that wait is dead air whenever it is too generous. It used to be a
-- flat two seconds, picked as "comfortably above normal ack latency" without
-- anyone measuring the latency.
--
-- Measured now, as a slow-decaying maximum: the worst confirmation seen
-- recently, times a safety factor, clamped to a floor and to the old two second
-- ceiling. On a quiet connection it settles near two thirds of a second; when
-- the server is struggling the observed latency rises and the ceiling rises
-- with it, which is the direction that matters - too SHORT re-sends a DoT that
-- was only slow to be acknowledged, wasting a global cooldown and the mana.
--
-- Decaying rather than a plain maximum, so one bad moment does not widen the
-- ceiling for the rest of the session.
local CONFIRM_MIN = 0.6
local CONFIRM_MAX = 2.0
local CONFIRM_FACTOR = 3
local CONFIRM_DECAY = 0.97

M.confirmSeen = 0

function M:NoteConfirmLatency(dt)
    if not dt or dt < 0 then return end
    if dt > self.confirmSeen then
        self.confirmSeen = dt
    else
        self.confirmSeen = self.confirmSeen * CONFIRM_DECAY
    end
end

function M:ConfirmCeiling()
    local c = (self.confirmSeen or 0) * CONFIRM_FACTOR
    if c < CONFIRM_MIN then c = CONFIRM_MIN end
    if c > CONFIRM_MAX then c = CONFIRM_MAX end
    return c
end

function M:ChannelLength(name)
    if not name then return nil end
    if name == "Dark Harvest" then return self:DHChannelLength() end
    if name == "Drain Soul"   then return self:DSChannelLength() end
    local b = CHANNEL_BASE[name]
    if not b then return nil end
    if CHANNEL_TALENTED[name] then
        return b * (1 - self:RapidDeteriorationPct() / 100)
    end
    return b
end

-- Minimum DoT time remaining needed to survive a full Dark Harvest channel at
-- its 30%-accelerated tick rate (see DH_TICK_BOOST above).
function M:DHMinDotRemain()
    return self:DHChannelLength() * (1 + DH_TICK_BOOST)
end

-- Is this one DoT going to be running for the whole of a channel `need` seconds
-- long? Three sources, best first, and each one is only consulted when the one
-- above it has no answer:
--
--   1. A remaining time. Exact where ClassicAPI supplies it, estimated from our
--      own last cast otherwise. Short means short.
--   2. Whether it is visibly on the target and ours. No remaining time, but
--      "not there at all" is an answer, and it is the important one.
--   3. Our own reapply stamp, for a DoT the client cannot show us - an
--      unresolvable curse is the case that matters. No stamp for this target
--      means we have not put it up.
--
-- Only when all three are silent does it answer "assume covered", which is the
-- module's standing rule: a detection that cannot answer must not close a gate.
function M:DotCoversChannel(sp, tex, need)
    local remain = self:DotRemaining(sp)
    if remain and remain > 0 then return remain >= need end

    local detectable = tex or Aegis_SBR:CanResolveDebuffNames()
    if detectable then
        return (self:TargetDebuffUp(sp, tex) and self:DotIsMine(sp)) and true or false
    end

    local rec = self.dotThrottle[sp]
    if rec and rec.id == self:TargetId() and rec.t then
        local dur = self:DotAppliedDuration(sp)
        if dur then return (dur - (GetTime() - rec.t)) >= need end
        return true
    end
    return false
end

-- Would every enabled DoT still be running at the end of this channel?
--
-- A MISSING DoT blocks the channel, which is the correction here. It used to
-- count as fine on the reasoning that the ladder below would apply it anyway -
-- but the channel RETURNS when it starts, so the ladder never ran that press,
-- and the DoT stayed missing for the five seconds the channel held. Reported
-- as Drain Life being prioritised over DoTs that are not up at all.
--
-- Blocking here costs nothing: the ladder is directly below, so the press that
-- would have started the channel applies the missing DoT instead and the
-- channel starts on the next one.
function M:DotsCoverChannel(channel, cfg)
    local need = self:ChannelLength(channel)
    if not need then return true end
    local list = {
        { "Corruption",  self.dotTex["Corruption"],  cfg and cfg.useCorruption },
        { "Siphon Life", self.dotTex["Siphon Life"], cfg and cfg.useSiphonLife },
    }
    if cfg and cfg.curse and cfg.curse ~= "" then
        table.insert(list, { cfg.curse, self:CurseTex(cfg.curse), true })
    end
    for i = 1, table.getn(list) do
        local sp, tex, enabled = list[i][1], list[i][2], list[i][3]
        if enabled and self:KnowsSpell(sp) and not self:DotCoversChannel(sp, tex, need) then
            if self:Tracing() then
                self:Trace("channel held: " .. sp .. " would not last the channel")
            end
            return false
        end
    end
    return true
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

-- ============================================================
-- Learned curse textures
-- ============================================================
-- Only Curse of Agony has a confirmed icon in the table above, and the comment
-- there says why the rest are missing: a GUESSED fragment is worse than none.
-- It makes `detectable` true, which drops the reapply interval from 20 seconds
-- to 3, and then never matches - so the curse is re-cast every three seconds
-- for the rest of the fight. A five minute curse becomes the most expensive
-- spell in the rotation.
--
-- So it is learned rather than guessed, the same way the hunter learns sting
-- immunity and the paladin learns what Repentance does to a creature: cast the
-- curse, look at what appeared on the target that was not there before, and
-- only accept the answer when it is unambiguous.
--
-- Worth having even where SuperWoW resolves debuff names, for the one case a
-- timestamp can never cover: a curse that was DISPELLED still has four minutes
-- on our own clock and is not on the target at all.
local CURSE_LEARN_MIN = 0.3    -- before this the debuff may not have landed yet
local CURSE_LEARN_MAX = 4.0    -- after this, something else could have applied it
local CURSE_TEX_STRIKES = 3    -- wrong-looking answers tolerated before unlearning

function M:CurseTexMemory()
    if not AegisDB then return nil end
    if type(AegisDB.warlockCurseTex) ~= "table" then AegisDB.warlockCurseTex = {} end
    return AegisDB.warlockCurseTex
end

function M:CurseTex(name)
    if not name then return nil end
    if self.curseTex[name] then return self.curseTex[name] end
    local mem = self:CurseTexMemory()
    return mem and mem[name] or nil
end

-- A texture path we are willing to store. The basename only, because the full
-- path varies, and rejected outright if it carries a Lua pattern character -
-- ScanTargetDebuff matches with string.find in PATTERN mode, so a stray "-"
-- would quietly match the wrong thing.
local function CurseTexCandidate(path)
    if type(path) ~= "string" or path == "" then return nil end
    local base = path
    local cut = string.len(base)
    while cut > 0 do
        local c = string.sub(base, cut, cut)
        if c == "\\" or c == "/" then base = string.sub(base, cut + 1); break end
        cut = cut - 1
    end
    if base == "" then return nil end
    if string.find(base, "[%^%$%(%)%%%.%[%]%*%+%-%?]") then return nil end
    return base
end

-- Snapshot of what is on the target right now, so the cast below can be
-- compared against it.
function M:TargetTexSet()
    local set = {}
    Aegis_SBR:SnapshotTargetDebuffs()
    local snap = Aegis_SBR.tdebuffSnap
    if snap and snap.list then
        for i = 1, table.getn(snap.list) do
            if snap.list[i].tex then set[snap.list[i].tex] = true end
        end
    end
    return set
end

function M:BeginCurseLearn(spell, id)
    if self:CurseTex(spell) then return end
    if not self:CurseTexMemory() then return end
    self.curseLearn = { spell = spell, id = id, t = GetTime(), before = self:TargetTexSet() }
end

-- Run once per press. Accepts an answer only when EXACTLY ONE new texture
-- appeared: two means we cannot tell which is ours, and guessing here is the
-- thing this whole mechanism exists to avoid.
function M:CurseLearnTick()
    local L = self.curseLearn
    if not L then return end
    local age = GetTime() - L.t
    if age < CURSE_LEARN_MIN then return end
    if age > CURSE_LEARN_MAX or self:TargetId() ~= L.id then
        self.curseLearn = nil
        return
    end
    local now, new, count = self:TargetTexSet(), nil, 0
    for tex in pairs(now) do
        if not L.before[tex] then new = tex; count = count + 1 end
    end
    if count ~= 1 then
        if count > 1 then self.curseLearn = nil end
        return
    end
    local cand = CurseTexCandidate(new)
    self.curseLearn = nil
    if not cand then return end
    local mem = self:CurseTexMemory()
    if not mem then return end
    mem[L.spell] = cand
    if self:Tracing() then self:Trace("learned curse icon: " .. L.spell .. " = " .. cand) end
end

-- A learned texture that turns out not to match is the failure mode the guess
-- was avoiding, so it is watched: three casts that leave the icon invisible and
-- it is dropped, back to the blind timer that at least does no harm.
function M:CurseTexStrike(spell)
    local mem = self:CurseTexMemory()
    if not mem or not mem[spell] then return end
    self.curseTexMiss = self.curseTexMiss or {}
    self.curseTexMiss[spell] = (self.curseTexMiss[spell] or 0) + 1
    if self.curseTexMiss[spell] >= CURSE_TEX_STRIKES then
        if self:Tracing() then self:Trace("dropped learned icon for " .. spell .. ": never visible") end
        mem[spell] = nil
        self.curseTexMiss[spell] = nil
    end
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
    -- ClassicAPI, when present, knows the server's real expiration for a debuff
    -- on ANOTHER unit, including the caster-modified duration - so Rapid
    -- Deterioration, Dark Harvest and Conflagrate's Immolate shave are already
    -- folded in, and none of the estimation below is needed.
    --
    -- Three conditions before we trust it:
    --   * a remaining time is actually known (nil = the cast predates login or
    --     the cache evicted; that is UNKNOWN, not zero)
    --   * the DoT is OURS. mine == false means another warlock's, and refreshing
    --     our own priority off someone else's timer would be wrong. mine == nil
    --     is "cannot tell" and is accepted, matching the pre-ClassicAPI
    --     assumption that a tracked DoT on our target is ours.
    -- Anything else falls through to the original estimate below, unchanged.
    if Aegis_SBR.TargetDebuffRemaining then
        local mine = Aegis_SBR:TargetDebuffMine(spellName)
        if mine ~= false then
            local exact = Aegis_SBR:TargetDebuffRemaining(spellName)
            if exact then return exact end
        end
    end

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

-- True when any enabled, tracked DoT is due to fall off within `within`
-- seconds. A DoT with no confident estimate (DotRemaining returns nil) never
-- counts, matching the "unknown is not urgent" stance used for the Dark
-- Harvest pre-check.
-- The DoT that would lapse during a channel of `len` seconds, or nil.
--
-- The channel guard stops the rotation for the channel's whole length, so
-- anything due inside it has to go out BEFORE it starts. Returning the spell
-- rather than a yes/no lets the caller top it up, which is what Dark Harvest
-- has done since v1.2.6 - the other channels used to ride the wand until the
-- danger passed instead, which is the behaviour being removed here.
function M:DotLapsingWithin(order, len, dotsSuppressed)
    if dotsSuppressed then return nil end
    for i = 1, table.getn(order) do
        local sp = order[i][1]
        if self:KnowsSpell(sp) then
            local remain = self:DotRemaining(sp)
            if remain and remain < len then return sp, remain end
        end
    end
    return nil
end

function M:DotExpiringSoonBy(order, within)
    for i = 1, table.getn(order) do
        local sp = order[i][1]
        if self:KnowsSpell(sp) then
            local remain = self:DotRemaining(sp)
            if remain and remain <= within then
                return true
            end
        end
    end
    return false
end

-- The wand's own horizon (see WAND_STOP_BEFORE_DOT).
function M:DotExpiringSoon(order)
    return self:DotExpiringSoonBy(order, WAND_STOP_BEFORE_DOT)
end

-- Seconds left on a spell's OWN cooldown, ignoring the global cooldown; 0 when
-- it is ready. Needed to tell whether a long channel would still be running
-- when Dark Harvest comes back up.
function M:OwnCDLeft(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return 0 end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 or dur <= 1.55 then return 0 end
    local left = start + dur - GetTime()
    if left < 0 then left = 0 end
    return left
end

-- Throttle memory per DoT, keyed by target GUID. Only stamped once
-- UNIT_CASTEVENT confirms the cast actually landed (see the frame near the
-- end of this file) - not the instant it is sent.
M.dotThrottle = {}

-- Spells a given target turned out to be immune to, learned for the current
-- combat and keyed by "<targetGUID>|<spell>". Cleared on leaving combat, like
-- the hunter's sting immunity this mirrors.
--
-- 1.12 offers no way to ask whether a mob resists a school, so the only honest
-- source is the client saying so: "Your Immolate failed. X is immune." Without
-- it the rotation re-applied a DoT that cannot land every three seconds for the
-- whole fight - reported as Immolate being spammed on fire-immune mobs.
M.dotImmune = {}

function M:DotImmune(spellName)
    local _, guid = UnitExists("target")
    if not guid then return false end
    return self.dotImmune[guid .. "|" .. spellName] and true or false
end

-- Casts sent but not yet confirmed CAST or FAIL by UNIT_CASTEVENT, keyed by
-- spell name -> { id = targetId at cast time, t = time sent }.
M.dotPending = {}

-- Send a DoT cast and mark it pending confirmation.
--
-- Where UNIT_CASTEVENT answers, dotThrottle is stamped only once it confirms the
-- cast went out, so a cast that silently failed (the GCD was still up) is
-- retried on the very next press rather than blocking for the whole interval on
-- a guess. That replaced an older version which stamped optimistically here, and
-- it is the right design - on a client that confirms.
--
-- On one that does not, it degrades to no throttle at all, and a captured
-- session showed exactly that: 746 seconds of play, 580 measurements, and
-- throttleAge was -1 in every single one. The throttle had never been stamped
-- once. With the debuff read also failing much of the time (Corruption was
-- readable on a quarter of presses in the same log), nothing was left to stop a
-- re-send but the two second pending window - so every press went into sending
-- the same DoT again or waiting on it, and the filler was never reached. That is
-- the reported multi-second hangup.
--
-- So the confirmation is treated as a capability to be established, not assumed:
-- until one has actually arrived, the send stamps the throttle itself. Where
-- confirmations do arrive, the first one flips castEventSeen and this behaves
-- exactly as before. Same shape as the hunter's stingSeen / debuffSeen, and the
-- same lesson - a detection that never answers must not be the only thing a
-- decision rests on.
function M:QueueDot(spellName, id)
    if not self:Queue(spellName, "DoT missing") then return end
    self:Later(function()
        local now = GetTime()
        -- A curse we have no icon for: watch what appears on the target.
        if self.curseIsA and self.curseIsA[spellName] then self:BeginCurseLearn(spellName, id) end
        self.dotPending[spellName] = { id = id, t = now }
        if not M.castEventSeen then
            self.dotThrottle[spellName] = { id = id, t = now }
        end
        -- Per TARGET, unlike dotThrottle, which holds only the most recent cast
        -- of each spell and is overwritten the instant you dot a second mob -
        -- the normal affliction pattern. Without this, coming back to the first
        -- mob would read as "never cast here".
        Aegis_SBR:NoteDebuffApplied(id, spellName, self:DotAppliedDuration(spellName))
    end)
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
-- Whose DoT is on the target? The model lives in the core (DebuffMine) because
-- every class that keeps a debuff up has the same question; here it only needs
-- this warlock's duration table, Rapid Deterioration included.
function M:DotIsMine(spellName)
    return Aegis_SBR:DebuffMine(spellName, self:TargetId())
end

-- The duration this DoT will actually run for, Rapid Deterioration folded in,
-- handed to the ledger at the moment it is applied.
function M:DotAppliedDuration(spellName)
    local dur = self.dotDuration[spellName]
    if dur and self.rapidDetSpells[spellName] then
        dur = dur * (1 - self:RapidDeteriorationPct() / 100)
    end
    return dur
end

function M:ApplyDot(spellName, texFrag, interval)
    interval = interval or 3
    if self:TargetDebuffUp(spellName, texFrag) and self:DotIsMine(spellName) then
        return "up"
    end
    -- Immune to this one: report it as handled so the DoT chain moves on to the
    -- next spell instead of stopping here for the rest of the fight.
    if self:DotImmune(spellName) then return "up" end
    -- Moving, and this one is not instant: skip it and let the chain carry on to
    -- the DoTs that ARE instant, then to the filler.
    --
    -- Reported as "up" rather than "wait" deliberately. "wait" returns from the
    -- whole rotation, which is the stall being fixed here; "up" means "nothing to
    -- do about this one", which is exactly true while running.
    if self:DotCastTime(spellName) > 0 and Aegis_SBR:Moving() then
        if self:Tracing() then self:Trace("moving, skipping " .. spellName) end
        return "up"
    end

    local detectable = (texFrag ~= nil) or Aegis_SBR:CanResolveDebuffNames()
    local id = self:TargetId()
    local rec = self.dotThrottle[spellName]
    local now = GetTime()
    if self:Tracing() then
        local throttleAge = (rec and rec.id == id and rec.t) and (now - rec.t) or -1
        local pend = self.dotPending[spellName]
        local pendAge = (pend and pend.id == id) and (now - pend.t) or -1
        self:Trace(string.format("%s missing wanding=%s throttleAge=%.2f pendAge=%.2f conf=%s vis=%s",
            spellName, tostring(self:Wanding()), throttleAge, pendAge,
            M.castEventSeen and "Y" or "N",
            -- Visible on the target but not ours: the second-warlock case.
            self:TargetDebuffUp(spellName, texFrag) and "other's" or "no"))
    end
    -- Stamping on send (see QueueDot) means a cast the CLIENT threw away would
    -- otherwise hold the throttle for the whole interval - the exact regression
    -- the old comment there warns about. Out of range and line of sight arrive
    -- as an error message, never in the combat log, so the resist / miss handler
    -- cannot see them. Discard the stamp when one of those named this spell.
    if rec and Aegis_SBR.SpellRefusedSince and Aegis_SBR:SpellRefusedSince(spellName, rec.t) then
        self.dotThrottle[spellName] = nil
        rec = nil
    end
    if rec and rec.id == id and rec.t and (now - rec.t) <= interval then
        -- A learned icon that stays invisible right after our own cast is a
        -- wrong icon. Counted here, dropped after a few (see CurseTexStrike).
        if detectable and texFrag and self.curseIsA[spellName]
            and not self:TargetDebuffUp(spellName, texFrag) then
            self:CurseTexStrike(spellName)
        end
        if detectable then return "wait" else return "up" end
    end
    -- A cast already sent is still awaiting CAST/FAIL confirmation, and this is
    -- the one early exit that holds the WHOLE rotation without casting anything.
    --
    -- The ceiling used to be a flat two seconds, chosen as "comfortably above
    -- normal ack latency" without ever measuring what that latency is. On a
    -- training dummy it cost eleven seconds of a two and a half minute session,
    -- three of them in one go, all on Corruption.
    --
    -- It is measured now: ConfirmCeiling watches how long confirmations actually
    -- take on this connection and allows a generous multiple of that. On a quiet
    -- server it settles near two thirds of a second; under the lag that produced
    -- those three second holes it widens by itself rather than double-casting a
    -- DoT that was merely slow to be acknowledged.
    local pend = self.dotPending[spellName]
    if pend and pend.id == id and (now - pend.t) <= self:ConfirmCeiling() then
        return "wait"
    end
    self:QueueDot(spellName, id)
    return "cast"
end

-- Start or stop the wand. Shoot toggles auto-repeat, so casting it while it
-- is already running is how the rotation stops it - both directions are a real
-- press and are reported as such.
function M:Shoot(reason)
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = "Shoot"; p.reason = reason
        return true
    end
    CastSpellByName("Shoot")
    return true
end

-- ============================================================
-- Rotation. The core has already secured a target (no melee auto
-- attack for this class). One queued cast per press, DoTs first.
-- ============================================================
function M:Rotate(cfg)
    -- Send the pet in. With petMeleeOnly, only when the target is within melee
    -- range (the same gate as the melee auto-attack), so an accidentally
    -- targeted far enemy never pulls the pet away.
    if cfg.petAttack and UnitExists("pet") and not UnitIsDead("pet") then
        if not cfg.petMeleeOnly or self:InMeleeRange() then PetAttack() end
    end

    -- Never act while a channel runs (Drain Life / Drain Soul), so a DoT refresh
    -- or the filler cannot clip it. The stop event also fires when the target
    -- dies mid-channel; a 16s ceiling guards against a missed stop so the
    -- rotation can never get stuck.
    --
    -- The ceiling used to be the ONLY time-based release, and sixteen seconds is
    -- no release at all: it is there for a lost event, not for the normal case.
    -- Measured on a training dummy, every one of nine channels held the rotation
    -- for roughly nine tenths of a second AFTER its last tick - the stop event
    -- simply arrives late. Nine holes of a second in two and a half minutes is
    -- what "choppy" means from the outside.
    --
    -- So the guard now ends at whichever comes first: the event, or the length
    -- the channel was always going to have. That length is known - it is the
    -- same number DHChannelLength already computes for Dark Harvest, talent
    -- included - it was just never used here.
    if self.channeling and self.chanStart then
        local held = GetTime() - self.chanStart
        local expect = self:ChannelLength(self.chanSpell)
        local limit = expect and (expect + CHANNEL_GRACE) or 16

        -- Moving breaks a channel outright - it is why Queue refuses to START
        -- one while moving, and the same fact ends one that is already running.
        -- Checked here rather than waited for, because the client announces a
        -- broken channel through an event this one does not reliably send.
        local why = nil
        if Aegis_SBR:Moving() then
            why = "broken by movement"
        elseif held < limit then
            if self:Tracing() then
                self:Trace(string.format("STALL channel %.1fs of %.1fs (%s)",
                    held, limit, self.chanSpell or "unknown"))
            end
            return
        else
            why = "released on time, no stop event"
        end
        -- Cleared here, or every following press would re-enter this branch and
        -- re-decide the same way.
        self.channeling = false
        self.chanSpell = nil
        self.dhEnd = nil
        if self:Tracing() then
            self:Trace(string.format("channel %s after %.1fs", why, held))
        end
    end

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
            if self:Tracing() then
                self:Trace(string.format("STALL harvest %.1fs left", self.dhEnd - GetTime()))
            end
            return
        end
    end

    -- Resolve a pending icon observation before anything else reads CurseTex.
    self:CurseLearnTick()

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
    --
    -- REVERTED, 2026-09-04. Re-sending while the buff was still up - on the
    -- reading that a lingering buff proved the bolt had never landed - played
    -- measurably worse and was taken straight back out. The measurement behind
    -- it stands (nine sends, the buff surviving every one of them), so the
    -- reading of WHY is what was wrong: the extra sends cost more than the
    -- missed procs did. Anything tried here next needs to explain that.
    if nightfall and cfg.filler ~= "Shadow Bolt" and self:KnowsSpell("Shadow Bolt") then
        if self:ShadowTranceUp() then
            if self:Tracing() then
                self:Trace(string.format("trance up spent=%s conf=%s",
                    self.stConsumed and "Y" or "n",
                    M.castEventSeen and "Y" or "N"))
            end
            if not self.stConsumed then
                if self:Queue("Shadow Bolt", "Nightfall proc") then
                    if self:Tracing() then self:Trace("trance SENT Shadow Bolt") end
                    self:Later(function()
                        self.stConsumed = true
                        self.stConsumedAt = GetTime()
                    end)
                    return
                end
            elseif self.stConsumedAt and (GetTime() - self.stConsumedAt) > 15 then
                self:Later(function() self.stConsumed = false end)
            end
        else
            self:Later(function() self.stConsumed = false end)
        end
    end

    local hp     = self:PlayerHPPct()
    local thp    = self:TargetHPPct()

    -- P1 Drain Life self-heal: your survival comes first. Channels Drain Life
    -- when you drop below the threshold (the drain-tank safety net).
    -- The channel is five seconds in which no global cooldown is spent, so a
    -- DoT that runs out during it is five seconds of ticks thrown away - and
    -- re-applying it afterwards costs the global cooldown that was saved. Dark
    -- Harvest has topped its DoTs up before channelling since v1.2.6; this is
    -- the same rule for the same reason, one channel later.
    --
    -- Falling through is all that is needed: the DoT ladder is directly below,
    -- so the press applies what is short and the channel starts on the next one.
    --
    -- Except when health is genuinely low. Drain Life at that point is not a
    -- filler, it is the reason the warlock is still alive, and holding it for a
    -- DoT refresh would be the wrong trade. Half the configured threshold is
    -- where it stops waiting for anything.
    if cfg.drainLifeSustain and self:KnowsSpell("Drain Life") and hp < (cfg.drainLifeHp or 35) then
        local urgent = hp < (cfg.drainLifeHp or 35) / 2
        if urgent or self:DotsCoverChannel("Drain Life", cfg) then
            if self:Queue("Drain Life", "filler, self healing") then return end
        end
    end

    -- P2 Health Funnel: keep the pet alive when it drops, but only while you
    -- can spare the health (it transfers yours to the pet).
    if cfg.healthFunnel and self:KnowsSpell("Health Funnel")
        and UnitExists("pet") and not UnitIsDead("pet")
        and self:PetHPPct() < (cfg.healthFunnelPetHp or 50) and hp > (cfg.healthFunnelHpMin or 45) then
        if self:Queue("Health Funnel", "pet is hurt") then return end
    end

    -- P3 Shadowburn execute: instant finish under the execute threshold (costs
    -- a Soul Shard). On a cooldown, so it is gated by IsReady. Also gated on
    -- actually holding a shard: without one the cast fails in-game while
    -- IsReady/Queue both still report success, which would stall the rotation
    -- on a dead attempt instead of falling through to Drain Soul or the filler.
    if cfg.useShadowburn and self:KnowsSpell("Shadowburn") and self:IsReady("Shadowburn")
        and thp < (cfg.shadowburnHp or 20) and self:CountSoulShards() > 0 then
        if self:Queue("Shadowburn", "finisher") then return end
    end

    -- P4 Drain Soul finisher: channel in the target's last seconds to bank a
    -- Soul Shard and regen mana. (If both this and Shadowburn are enabled,
    -- Shadowburn fires first when ready; this fills otherwise.) With
    -- keepShards on, it stops once shardTarget is banked so it does not keep
    -- draining a target you could just finish off with the filler.
    if cfg.useDrainSoul and self:KnowsSpell("Drain Soul") and thp < (cfg.drainSoulHp or 20)
        and (not cfg.keepShards or self:CountSoulShards() < (cfg.shardTarget or 0)) then
        if self:Queue("Drain Soul", "filler channel") then return end
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
            self:Queue("Life Tap", "mana from health")
            return
        end
        if self:HasWand() then
            if self:Wanding() then return end
            if self:Tracing() then
                self:Trace(string.format("wandstart ready=%s mana=%.0f hp=%.0f",
                    tostring(self:IsReady("Shoot")), self:ManaPct(), hp))
            end
            self:Shoot("wanding")
            return
        end
    end

    -- Build the ordered DoT list from the enabled, known effects. The order is
    -- deliberate, and anything switched off simply lets the rest move up:
    --  1. Immolate, while it is still in use. Its cast time is the point at low
    --     levels: those extra ~1.5s let the pet build aggro before your own
    --     damage lands. It is normally switched off around 30, where its
    --     damage-per-mana falls behind the shadow DoTs and the cast time turns
    --     from an asset into a cost.
    --  2. The chosen curse. Curse of Agony's damage is back-loaded, so it needs
    --     the head start; Curse of the Elements/Shadow amplify damage taken and
    --     are applied per tick (not snapshot at cast), so landing them before
    --     the DoTs means every later tick is already buffed.
    --  3. Siphon Life. It only pays its mana back if it runs most of its 30s,
    --     so a late application is a straight loss - it has to go on early.
    --  4. The Malediction Curse of Agony, back-loaded like the main curse and
    --     therefore ahead of flat-damage Corruption.
    --  5. Corruption. Instant and the best damage-per-mana of the set, so it
    --     loses the least by being applied last.
    local order = {}
    if cfg.useImmolate then table.insert(order, { "Immolate", self.dotTex["Immolate"], 3 }) end
    if cfg.curse ~= "" then
        local tex = self:CurseTex(cfg.curse)
        -- Exact upkeep when the curse is detectable (known icon, or SuperWoW
        -- name resolution); only a curse we cannot see at all falls back to the
        -- 20s blind reapply timer.
        local detectable = tex or Aegis_SBR:CanResolveDebuffNames()
        table.insert(order, { cfg.curse, tex, detectable and 3 or 20 })
    end
    if cfg.useSiphonLife then table.insert(order, { "Siphon Life", self.dotTex["Siphon Life"], 3 }) end
    -- Malediction secondary curse: with that talent Curse of Agony coexists
    -- with the main curse, but expires sooner and is otherwise unmonitored.
    -- When enabled, keep it up on its own. Skipped if the main curse already
    -- is Curse of Agony, or is Curse of Doom, which the talent does not
    -- combine with.
    if cfg.coaSecondary and self:KnowsSpell("Curse of Agony")
        and cfg.curse ~= "Curse of Agony" and cfg.curse ~= "Curse of Doom" then
        local coaTex = self:CurseTex("Curse of Agony")
        local coaDetectable = coaTex or Aegis_SBR:CanResolveDebuffNames()
        table.insert(order, { "Curse of Agony", coaTex, coaDetectable and 3 or 20 })
    end
    if cfg.useCorruption then table.insert(order, { "Corruption", self.dotTex["Corruption"], 3 }) end

    -- Execute phase: stop RE-APPLYING DoTs once the target is nearly dead. A
    -- fresh DoT never pays its mana back on a mob with seconds to live - Siphon
    -- Life needs most of its 30s to break even and Curse of Agony's damage is
    -- back-loaded, so both are pure waste there. Corruption can be exempted
    -- (dotStopKeepCorruption): it is the shortest and cheapest of them, which
    -- is exactly why the drain-tank guides keep refreshing that one alone.
    -- Only re-application stops; DoTs already ticking are never touched, and
    -- the press falls through to the filler (or Shadowburn / Drain Soul, which
    -- have already had their own shot above).
    local dotStopHp = cfg.dotStopHp or 0
    local dotsSuppressed = dotStopHp > 0 and thp <= dotStopHp

    if self:Tracing() then
        local up = ""
        for i = 1, table.getn(order) do
            local sp, tex = order[i][1], order[i][2]
            up = up .. " " .. sp .. "=" .. (tex and (self:TargetHasTexture(tex) and "Y" or "n") or "?")
        end
        self:Trace("dots" .. up .. " mana=" .. string.format("%.0f", self:ManaPct())
            .. " dotstop=" .. (dotStopHp > 0 and (dotsSuppressed and "Y" or "n") or "-"))
    end

    for i = 1, table.getn(order) do
        local sp, tex, iv = order[i][1], order[i][2], order[i][3]
        local exempt = cfg.dotStopKeepCorruption and sp == "Corruption"
        local allowed = (not dotsSuppressed) or exempt
        if self:KnowsSpell(sp) and allowed then
            local st = self:ApplyDot(sp, tex, iv)
            if st == "wait" and self:Tracing() then
                -- The one early exit that can hold the WHOLE rotation without
                -- casting anything, which is what a reported "it did nothing for
                -- two seconds" looks like from outside. Says which of the two
                -- waits it is: a cast still awaiting confirmation, or the
                -- interval after a confirmed cast whose debuff is not visible.
                local rec, pend = self.dotThrottle[sp], self.dotPending[sp]
                local id = self:TargetId()
                local kind = "?"
                if pend and pend.id == id then kind = string.format("unconfirmed %.1fs", GetTime() - pend.t)
                elseif rec and rec.id == id then kind = string.format("throttle %.1fs of %ds", GetTime() - rec.t, iv) end
                self:Trace("STALL dot " .. sp .. " " .. kind)
            end
            if st == "cast" or st == "wait" then return end
            -- "up": continue to the next DoT
        end
    end

    -- All enabled DoTs up. Optional Life Tap, then the filler.
    --
    -- A Dark Harvest that is ready AND affordable goes first, though. The DoT
    -- top-up in the branch below exists precisely so the channel gets its full
    -- boosted duration; spending a GCD on Life Tap here eats into that same
    -- headroom, so by the time the channel would start a DoT has dropped under
    -- the threshold again and gets re-applied - a second GCD and the mana Life
    -- Tap had just bought, both wasted. Tapping one press later costs nothing:
    -- the channel itself is ~7.5s during which no GCD is spent anyway.
    -- The affordability check matters - without it a channel we cannot pay for
    -- would be queued, fail in-game, and (its cooldown never having started)
    -- be retried on the very next press, stalling the rotation instead of
    -- fixing the mana. Below the cost, Life Tap keeps its turn.
    local dhFirst = cfg.filler == "Dark Harvest" and self:KnowsSpell("Dark Harvest")
        and self:OwnCDReady("Dark Harvest") and (UnitMana("player") or 0) >= DH_MANA
    if cfg.lifeTap and self:KnowsSpell("Life Tap") and not dhFirst then
        if self:ManaPct() < (cfg.lifeTapMana or 20) and self:PlayerHPPct() > (cfg.lifeTapHpMin or 40) then
            self:Queue("Life Tap", "mana from health")
            return
        end
    end

    -- Dark Harvest is cooldown-gated rather than learned/unlearned, so it needs
    -- its own dispatch ahead of ResolveFiller: channel it the instant it is off
    -- cooldown, otherwise wand-fill the gap (degrading to Shadow Bolt if no
    -- wand is equipped) so the rotation is never idle between channels.
    if cfg.filler == "Dark Harvest" and self:KnowsSpell("Dark Harvest") then
        -- Moving is handled here rather than at the Queue below, because that
        -- branch returns either way: refused there, the press would be spent on
        -- nothing instead of falling through to the gap filler.
        if self:OwnCDReady("Dark Harvest") and not self:Moving() then
            -- Every enabled DoT is already up at this point (the loop above
            -- only falls through once none of them needed casting). Before
            -- committing to the channel, make sure none of them will fall off
            -- partway through it: top up anything estimated to have less than
            -- DHMinDotRemain() seconds left so the full channel ticks at the
            -- boosted rate. Unknown remaining time (no duration on file, or no
            -- cast record for this target) is not treated as urgent, so the
            -- channel is not blocked on a guess.
            local minRemain = self:DHMinDotRemain()
            if self:Tracing() then
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
            -- Skipped entirely in the execute phase: topping a DoT up there is
            -- the same wasted mana the stop above avoids, and the sooner the
            -- channel starts on a dying target the better - a target that dies
            -- mid-channel resets Dark Harvest's cooldown outright.
            if not dotsSuppressed then
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
            end
            if self:Queue("Dark Harvest", "mana from the channel") then
                self:Later(function()
                    self.dhStart = GetTime()
                    self.dhEnd = self.dhStart + self:DHChannelLength()
                    self.dhTarget = self:TargetId()
                end)
            end
            return
        end
        -- Dark Harvest is on cooldown: fill the gap with the configured choice.
        local gap = cfg.dhGapFiller or "Shoot"

        -- A CHANNEL in the gap - Drain Life or Drain Soul. The guard at the top
        -- of Rotate stops the rotation for the channel's whole length, so two
        -- things have to be true before one starts: no enabled DoT may lapse
        -- inside it, and Dark Harvest must not come off cooldown mid-channel and
        -- sit there unpressed.
        --
        -- What CHANGED is what happens when they are not true. Both used to fall
        -- back to the wand - "ride the wand until it is safe" - and Drain Life
        -- was not checked at all, so it channelled straight over a lapsing DoT
        -- and over Dark Harvest's return. Reported as the wand still being woven
        -- in at full mana with Drain Life set as the gap filler.
        --
        -- Now a DoT that would lapse is topped up instead, which is what the
        -- press was needed for anyway, and the wand is left for the one case
        -- where there is genuinely nothing else: Dark Harvest due back sooner
        -- than the channel would take.
        if M.CHANNELED[gap] and self:KnowsSpell(gap) then
            local len = (gap == "Drain Soul") and self:DSChannelLength()
                or (self:ChannelLength(gap) or 0)
            local lapsing = self:DotLapsingWithin(order, len, dotsSuppressed)
            if lapsing then
                if self:Tracing() then
                    self:Trace("gap channel held: " .. lapsing .. " would lapse during it")
                end
                self:QueueDot(lapsing, self:TargetId())
                return
            end
            if self:OwnCDLeft("Dark Harvest") >= len then
                if self:Queue(gap, "gap channel") then return end
                -- Refused, and Queue refuses a channel only for movement.
                if self:HasWand() and not self:Wanding() then
                    self:Shoot("wanding, moving")
                    return
                end
            elseif self:Tracing() then
                self:Trace(string.format("gap channel held: Dark Harvest back in %.1fs of %.1fs",
                    self:OwnCDLeft("Dark Harvest"), len))
            end
            -- Dark Harvest is due back before this channel would end. Anything
            -- started now would still be running when it comes up.
            gap = "Shoot"
        end
        if gap == "Shadow Bolt" and self:KnowsSpell("Shadow Bolt") then
            self:Queue("Shadow Bolt", "filler nuke")
            return
        end

        if self:HasWand() then
            if self:DotExpiringSoon(order) then
                if self:Wanding() then self:Shoot("stopping the wand for a DoT") end -- toggles the repeat off
                return
            end
            if self:Wanding() then return end
            self:Shoot(gap == "Shoot" and "wanding, gap filler" or "wanding, gap unavailable")
        elseif self:KnowsSpell("Shadow Bolt") then
            self:Queue("Shadow Bolt", "filler nuke")
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
            if self:Wanding() then self:Shoot("stopping the wand for a DoT") end
            return
        end
        -- spammable wand, only start it if it is not already auto repeating
        if self:Wanding() then return end
        self:Shoot("wanding")
    elseif filler == "Drain Soul" then
        -- Same channel caution as the Dark Harvest gap filler, minus the
        -- cooldown half: there is no Dark Harvest to be held up here, only the
        -- DoTs, which cannot be refreshed while the channel guard is holding
        -- the rotation. If one would lapse during it, fall through to the wand
        -- (or Shadow Bolt without one) for this press instead.
        if not self:DotExpiringSoonBy(order, self:DSChannelLength()) then
            if self:Queue("Drain Soul", "filler channel") then return end
        end
        if self:HasWand() then
            if self:Wanding() then return end
            self:Shoot("wanding")
        elseif self:KnowsSpell("Shadow Bolt") then
            self:Queue("Shadow Bolt", "filler nuke")
        end
    elseif filler and M.CHANNELED[filler] then
        -- A CHANNEL as the configured filler, which is a different job from the
        -- Dark Harvest branch above: Dark Harvest has a cooldown, so there is a
        -- gap between channels that something has to fill. Drain Life and the
        -- others have none. There is no gap - the right behaviour is to start
        -- the next one as soon as the last ends, and to stop only when a DoT
        -- needs the press.
        --
        -- Reported: with Drain Life as the filler the rotation wove the wand in
        -- between channels. It fell into the generic branch below, whose only
        -- answer to "cannot channel right now" was the wand.
        --
        -- A DoT that would lapse DURING the channel is topped up first rather
        -- than waited out on the wand - the same rule Dark Harvest has used
        -- since v1.2.6, and for the same reason: the channel guard stops the
        -- rotation for its whole length, so anything due inside it has to go out
        -- before it starts.
        local len = self:ChannelLength(filler) or 0
        if not dotsSuppressed then
            for i = 1, table.getn(order) do
                local sp = order[i][1]
                if self:KnowsSpell(sp) then
                    local remain = self:DotRemaining(sp)
                    if remain and remain < len then
                        if self:Tracing() then
                            self:Trace(string.format("filler channel held: %s has %.1fs of %.1fs",
                                sp, remain, len))
                        end
                        self:QueueDot(sp, self:TargetId())
                        return
                    end
                end
            end
        end
        if self:Queue(filler, "filler channel") then return end
        -- Refused, and the only thing Queue refuses a channel for is movement.
        -- The wand is the one ranged attack that costs nothing to give up.
        if self:HasWand() and not self:Wanding() then self:Shoot("wanding, moving") end
    elseif filler then
        if self:Queue(filler, "filler") then return end
        if self:HasWand() and not self:Wanding() then self:Shoot("wanding, filler refused") end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "curse" then
        local curse = self.curseAlias[string.lower(t[2] or "")]
        local cfg = Aegis_SBR:GetActiveProfile()
        if cfg and curse ~= nil then
            cfg.curse = curse
            msgOut("curse = " .. ((curse == "") and "(none)" or curse) .. ".")
        else
            msgOut("usage: /sbr curse <agony|elements|shadow|weakness|recklessness|tongues|doom|none>", 1, 0.5, 0.3)
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
