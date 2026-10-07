-- ============================================================
-- Class_Rogue  -  rogue module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Assassination flavoured, configurable.
-- ============================================================
-- Model:
--  * A builder fills combo points (auto picks Noxious Assault if known,
--    else Sinister Strike, or a fixed choice from the profile).
--  * Slice and Dice and Envenom are optional self buffs kept alive by
--    their own timers, refreshed cheaply at 1 combo point or dumped with
--    Eviscerate above that, mirroring the proven ExAutoRogue logic.
--  * Eviscerate is the finisher once combo points reach the threshold.
--  * Riposte fires inside the parry window when learned and enabled.
--  * Surprise Attack fires inside the target's dodge window when learned and
--    enabled - a Combat capstone (20 Combat points), the mirror image of
--    Riposte: it reacts to the TARGET dodging OUR attack rather than us
--    parrying theirs. Guaranteed hit (unblockable/undodgeable/unparryable),
--    cheap (10 energy), and awards a combo point, so it is worth interrupting
--    the normal builder/finisher flow for whenever the window is open.
--  * Adrenaline Rush and Blade Flurry are off-GCD, cast on demand or
--    automatically against elite and boss targets.
-- ============================================================

local M = Aegis_SBR:NewClassModule("ROGUE")
M.uiTitle = "Rogue"
M.uiHeight = 734

-- Each panel tab keeps its own settings layer (Aegis_SBR:TabView): a change
-- made on one tab stays on that tab.
M.tabLayers = { field = "spec", keys = { "starter", "assassination", "combat", "subtlety" } }
-- Rotate runs under Aegis_SBR:Preview without casting (see Pick/Later).
M.previewReady = true

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- Slice and Dice, Envenom and the Rupture proxy buff (Taste for Blood) are all
-- read straight off the real buff timer (GetPlayerBuffTimeLeft via
-- Aegis_SBR:BuffTime) - in-game /sbr trace confirmed all three resolve to a
-- live countdown, not just presence, so no stamped/estimated duration table
-- is needed for any of them (previously SnD and Envenom used a hardcoded
-- duration table stamped at cast time; that guess is gone now that the real
-- timer reads back reliably).
--
-- Reading the live timer is also why no duration table is maintained here any
-- more - but the underlying numbers still matter when reasoning about upkeep
-- cost, so they live in docs/turtle-mechanics.md (Rogue section) instead of
-- being re-derived. The one that bites: Turtle's SnD duration talent is called
-- **Improved Blade Tactics** (not "Improved Slice and Dice"), +45% at 3/3, and
-- the spell tooltip shows only the BASE duration - so a talented rogue's Slice
-- and Dice really lasts 13.05-30.45s, not the 9-21s the tooltip implies.
local TALENT_TASTE = "Taste for Blood"
-- Expose Armor is only worth five combo points WITH this talent, which is what
-- makes it beat the warrior's Sunder stack instead of duplicating it. Reported
-- from play (2026-08-18): without it, drop Expose Armor from the rotation
-- entirely rather than paying a finisher's worth of points every 30s for a
-- redundant debuff.
local TALENT_IEA = "Improved Expose Armor"
-- Default renew window: seconds of remaining buff time at or below which Slice
-- and Dice / Envenom are re-applied. Overridable per profile via cfg.buffRenew.
-- This used to be 5, sized for the era when the remaining time was ESTIMATED
-- from a stamped duration table - a wide margin was right when the number could
-- be wrong. Now that the real timer is read (see the header), that justification
-- is gone and 5s was simply throwing away up to a sixth of the buff's life, and
-- with it the combo points that paid for it. Lower is more efficient; too low
-- risks dropping the buff, because at 0 combo points the refresh needs TWO
-- presses (a builder first), which on an energy-starved rogue can take several
-- seconds. 0 means "only once it has actually dropped" - hence the <= test at
-- the call site, so a fully expired buff (BuffTime returns 0) still qualifies.
-- 1 is measured, not guessed: a 2 minute press log at this setting refreshed
-- with an average of 0.64s left on the buff, never dropped Slice and Dice, and
-- lost Envenom only three times for ~2.4s combined (2% downtime) - far less
-- than the up-to-4s of buff life the old 5 threw away on every single refresh.
local BUFF_RENEW = 1
-- Taste for Blood gets a wider renew window than the other two buffs: Slice and
-- Dice and Envenom can be refreshed at any combo point, while Rupture waits for
-- its own (higher) point threshold, so its opportunity comes around far less
-- often. Renewing from roughly half the buff's life onward makes sure such a
-- moment falls inside the window instead of after the buff has already lapsed.
local TFB_RENEW = 10
-- Expose Armor is re-applied under this much time left unless the profile
-- says otherwise (the slider on the Subtlety tab).
local EXPOSE_REFRESH_DEFAULT = 3.0

-- Builder universe, used by the UI to offer only learned ones
-- Deliberately WITHOUT Ghostly Strike. This list answers "which builder do you
-- spam", and Ghostly Strike has a 20 second cooldown - picked here, four presses
-- out of five would simply fail. It rides on top of the chosen builder instead
-- (see the cooldown override in Decide).
M.BUILDERS = { "Sinister Strike", "Backstab", "Hemorrhage", "Noxious Assault", "Mutilate" }

M.templates = {
    starter = {  -- valid for any rogue, only Slice and Dice upkeep
        builder = "", useSnd = true, useEnvenom = false, useRupture = false, useRiposte = false,
        useSurpriseAttack = false,
        useExecute = false, executeHpPct = 10, executeTTK = 4, executeMinCP = 1, refreshMaxCP = 5, evisExecuteOnly = false, ruptureCP = 3,
        cpFinish = 4, buffRenew = 1, useColdBlood = false, popCDs = false, autoCDElite = false,
    },
    assassination = {
        builder = "", useSnd = true, useEnvenom = true, useRupture = true, useRiposte = true,
        useSurpriseAttack = false,
        -- ruptureCP = 5 (not lower): Taste for Blood's magnitude is fixed at whatever combo
        -- points Rupture was cast with (2% per point) and a recast overwrites it outright, no
        -- keep-the-stronger-one logic - so anything below 5 risks replacing an existing 10%
        -- buff with a weaker one the moment Rupture comes due (Discord-reported, confirmed).
        useExecute = false, executeHpPct = 10, executeTTK = 4, executeMinCP = 1, refreshMaxCP = 5, evisExecuteOnly = false, ruptureCP = 5,
        cpFinish = 4, buffRenew = 1, useColdBlood = false, popCDs = false, autoCDElite = false,
    },
    combat = {
        builder = "", useSnd = true, useEnvenom = false, useRupture = false, useRiposte = false,
        useSurpriseAttack = true,
        useExecute = false, executeHpPct = 10, executeTTK = 4, executeMinCP = 1, refreshMaxCP = 5, evisExecuteOnly = false, ruptureCP = 3,
        cpFinish = 5, buffRenew = 1, useColdBlood = false, popCDs = false, autoCDElite = true,
    },
    subtlety = {  -- raid support: Expose Armor kept up, the Mark/Vanish/Garrote/Sigil burst
        spec = "subtlety", builder = "Hemorrhage", useSnd = true, useEnvenom = false, useRupture = true, useRiposte = false,
        useSurpriseAttack = false, useGarrote = true, useVanishBurst = true, useEviscerate = true,
        useExposeArmor = true, exposeCP = 5, useShadowOfDeath = true, sodCP = 5, useMark = true, markMaxCP = 3,
        usePreparation = true, useGhostly = false,
        useExecute = false, executeHpPct = 10, executeTTK = 4, executeMinCP = 1, refreshMaxCP = 2, evisExecuteOnly = false, ruptureCP = 5,
        cpFinish = 5, buffRenew = 1, useColdBlood = false, popCDs = false, autoCDElite = false,
    },
}

M.builderAlias = {
    sinister = "Sinister Strike", ss = "Sinister Strike",
    backstab = "Backstab", bs = "Backstab",
    hemorrhage = "Hemorrhage", hem = "Hemorrhage",
    noxious = "Noxious Assault", na = "Noxious Assault",
    mutilate = "Mutilate", mu = "Mutilate",
    auto = "", none = "",
}

-- Fills any missing field with a default
function M:NormalizeProfile(c)
    if c.builder == nil then c.builder = "" end
    -- Which spec's settings the config window shows for this profile. It is a
    -- VIEW, not a mode: the rotation does not branch on it, so anything you
    -- switched on stays on even while a tab does not show it. Written here so a
    -- profile made before the tabs existed opens on a sensible one - existing
    -- profiles are Assassination, which is the only spec either maintainer has
    -- actually played.
    if c.spec == nil then c.spec = "assassination" end
    if c.useSnd == nil then c.useSnd = true end
    if c.useEnvenom == nil then c.useEnvenom = false end
    if c.useRupture == nil then c.useRupture = false end
    if c.useRiposte == nil then c.useRiposte = false end
    if c.useSurpriseAttack == nil then c.useSurpriseAttack = false end
    -- Execute: finish with whatever combo points are on hand once the target
    -- is nearly dead, instead of risking them going to waste on a kill.
    -- Ruthlessness (Assassination talent, 100% at 3/3) guarantees at least 1
    -- combo point after any finisher, so there is always something to spend.
    if c.useExecute == nil then c.useExecute = false end
    if c.executeHpPct == nil then c.executeHpPct = 10 end
    -- Both combo-point floors default to 1, which is the behaviour that existed
    -- before them: no floor at all. They are opt-in tuning, not a new model.
    if c.executeMinCP == nil then c.executeMinCP = 1 end
    -- Highest combo point count a buff refresh is allowed to spend. Above it the
    -- surplus goes into Eviscerate first and the buff is refreshed on the next
    -- press with the point Ruthlessness hands back. 5 = no ceiling, which is
    -- what the rotation always did.
    --
    -- Subtlety defaults to 1 instead, because that IS its rotation rather than a
    -- tuning preference: 5-CP finishers with a 1-CP Slice and Dice refresh in
    -- between, off the point Ruthlessness hands straight back (play report,
    -- 2026-08-18). Assassination keeps 5 - v1.1.8 measured 1 as right for short
    -- dungeon fights and wrong in a raid, where the buff runs its full length.
    --
    -- c.spec is settled at the top of this function, so reading it here is safe.
    -- It has to happen HERE and not further down with the other Subtlety fields:
    -- by then the field is no longer nil and an override would never fire.
    if c.refreshMaxCP == nil then
        c.refreshMaxCP = 5
    end
    -- Retired: a combo point FLOOR for refreshes. Measured over 1355 presses it
    -- pushed Envenom uptime from 84% down to 61% and pinned the rotation at
    -- 2 combo points, because reaching the floor costs a builder GCD during
    -- which the buff is simply not up. The ceiling above is the same knob
    -- turned the right way round. Do not reintroduce it without new evidence.
    c.refreshMinCP = nil
    -- Seconds-to-live that count as "about to die". When the core can measure
    -- how fast the target is losing health it is a far better trigger than a
    -- health percentage: 10% of a boss is a minute of fighting, 10% of a boar
    -- is already over. 0 turns the measurement off and leaves the health
    -- percentage in sole charge, exactly as before this setting existed.
    if c.executeTTK == nil then c.executeTTK = 4 end
    -- Rupture only on a target measured to live at least this long. Trash
    -- in a raid dies before a Rupture (or the Taste for Blood it buys) pays
    -- its five points back; there they go into Eviscerate. Off by default.
    if c.useRuptureTTK == nil then c.useRuptureTTK = false end
    if c.ruptureMinTTK == nil then c.ruptureMinTTK = 16 end
    -- Rupture carries its OWN combo-point threshold, deliberately separate from
    -- Eviscerate's: only Rupture's payoff (the Taste for Blood damage buff)
    -- scales with the points spent, and sharing Eviscerate's higher threshold
    -- meant Rupture never got cast at all - buff refreshes reset the combo
    -- points long before that threshold was reached.
    if c.ruptureCP == nil then c.ruptureCP = 3 end
    -- Optionally reserve Eviscerate for the execute phase only, so every other
    -- combo point goes into the maintained buffs instead.
    if c.evisExecuteOnly == nil then c.evisExecuteOnly = false end
    if c.cpFinish == nil then c.cpFinish = 4 end
    -- Renew window for Slice and Dice / Envenom, in seconds of remaining time.
    -- Existing profiles are moved off the old hardcoded 5 deliberately: that
    -- value only ever existed to cover an estimated timer we no longer use.
    if c.buffRenew == nil then c.buffRenew = BUFF_RENEW end
    -- Cold Blood: opt-in. Rides along with Eviscerate only (see ColdBloodReady).
    if c.useColdBlood == nil then c.useColdBlood = false end
    -- ------------------------------------------------------------
    -- Subtlety. All four default ON for a Subtlety profile and OFF for every
    -- other, which is why they are read after c.spec is settled above: they are
    -- that tree's talents, so a Subtlety rogue wants them and nobody else can
    -- cast them anyway. An existing profile switched to the Subtlety tab keeps
    -- whatever it had - the fields are no longer nil by then - and the tab shows
    -- all four so they can be turned on deliberately.
    local sub = (c.spec == "subtlety")
    -- Expose Armor is upkeep, not a one-off. With Improved Expose Armor it is a
    -- STRONGER armor reduction than Sunder Armor rather than a redundant one, so
    -- it overrides the warrior's stack instead of competing with it - which is
    -- what makes it worth five combo points every time it drops. Those points
    -- are gone from Shadow of Death and Eviscerate: that is the trade, and it is
    -- paid for the raid, not for your own damage meter.
    if c.useExposeArmor == nil then c.useExposeArmor = sub end
    if c.exposeCP == nil then c.exposeCP = 5 end
    -- Shadow of Death stores a share of ALL damage the target takes for six
    -- seconds and releases it, both the share and the cap scaling per combo
    -- point (5 points = 50% of damage taken, up to 250% attack power). Five
    -- points is not a preference, it is the whole ability - a 1-point sigil caps
    -- at a fifth of that.
    if c.useShadowOfDeath == nil then c.useShadowOfDeath = sub end
    if c.sodCP == nil then c.sodCP = 5 end
    -- Mark for Death AWARDS two combo points, so it is a builder that happens to
    -- buff the party, not a finisher. Cast above this many points and the two it
    -- gives are thrown away against the cap.
    if c.useMark == nil then c.useMark = sub end
    if c.markMaxCP == nil then c.markMaxCP = 3 end
    -- Preparation clears the other rogue cooldowns; here it exists to hand back
    -- Mark for Death and Shadow of Death, so it only fires when both are down.
    if c.usePreparation == nil then c.usePreparation = sub end
    -- Ghostly Strike: same 40 energy and same single combo point as Hemorrhage,
    -- but 125% weapon damage against 110%. On its 20 second cooldown it is
    -- simply the better press, which is all the "hemo and ghostly" in the
    -- described rotation ever was - a cooldown coming back, not an alternation.
    if c.useGhostly == nil then c.useGhostly = sub end
    -- Garrote from stealth: the Subtlety opener (two combo points with
    -- Initiative, plus Serrated Blades on the bleed).
    if c.useGarrote == nil then c.useGarrote = sub end
    -- The burst: Mark for Death, Vanish, Garrote from the new stealth, Shadow
    -- of Death at five - then Preparation and the same again.
    if c.useVanishBurst == nil then c.useVanishBurst = sub end
    -- Eviscerate only as the overflow finisher when nothing else is due.
    if c.useEviscerate == nil then c.useEviscerate = true end
    if c.exposeRefresh == nil then c.exposeRefresh = EXPOSE_REFRESH_DEFAULT end
    -- Expose Armor only on a target that lives long enough (see ExposeWorth).
    if c.useExposeTTK == nil then c.useExposeTTK = false end
    if c.exposeMinTTK == nil then c.exposeMinTTK = 20 end
    if c.popCDs == nil then c.popCDs = false end
    if c.autoCDElite == nil then c.autoCDElite = false end
    -- old keys from any earlier format are dropped silently
    c.poisonReminder = nil   -- retired: superseded by the Aegis_SBR_BuffUp poison Quick Bar / rebuff buttons
    return c
end

function M:AvailableBuildersOf()
    local out = {}
    for i = 1, table.getn(self.BUILDERS) do
        if self:KnowsSpell(self.BUILDERS[i]) then table.insert(out, self.BUILDERS[i]) end
    end
    return out
end

function M:ProfileValidity(cfg)
    local missing = {}
    
    -- Keep this: if they manually chose a specific builder they don't know, flag it
    if cfg.builder ~= "" and not self:KnowsSpell(cfg.builder) then table.insert(missing, cfg.builder) end
    
    -- Level-dependent upkeeps/cooldowns shouldn't render the whole profile un-activatable,
    -- as M:Rotate already degrades gracefully using self:KnowsSpell()
    -- if cfg.useSnd     and not self:KnowsSpell("Slice and Dice") then table.insert(missing, "Slice and Dice") end
    -- if cfg.useEnvenom and not self:KnowsSpell("Envenom")        then table.insert(missing, "Envenom")        end
    -- if cfg.useRiposte and not self:KnowsSpell("Riposte")        then table.insert(missing, "Riposte")        end
    -- if (cfg.popCDs or cfg.autoCDElite) and not self:KnowsSpell("Adrenaline Rush") and not self:KnowsSpell("Blade Flurry") then
    --     table.insert(missing, "Adrenaline Rush / Blade Flurry")
    -- end
    
    return (table.getn(missing) == 0), missing
end

-- Seconds left on Taste for Blood - the melee damage buff Rupture exists for.
-- Read straight from the buff, which carries a real timer: verified in game
-- that it resolves by name through the same GetPlayerBuffID -> SpellInfo path
-- the core's snapshot uses ("Taste for Blood 11.506"), and BuffTime returns 0
-- when it is absent. NOTE this tracks the PLAYER buff, not the target's bleed:
-- the talent grants the buff "regardless of successful application" and it
-- survives a target switch, so the target debuff is the wrong signal.
-- Deliberately NO estimated-duration fallback: an earlier version stamped an
-- expected duration on cast and preferred it whenever the buff read as absent,
-- which inverted the whole point - once the real buff had run out, the stale
-- stamp still claimed it was up, so Rupture never won at the threshold.
function M:TasteLeft()
    return self:BuffTime(TALENT_TASTE) or 0
end

-- Talent rank by name, cached; cleared when talents are respent (see the event
-- frame at the bottom of this file).
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

-- Does Rupture need (re)casting? Two different questions depending on the
-- talent, which is why the rank is read rather than assumed:
--   * WITH Taste for Blood, Rupture is maintained for the PLAYER buff, so the
--     buff's own remaining time decides.
--   * WITHOUT it there is no buff at all - Rupture is then just a bleed, so it
--     falls back to whether the DoT is on the TARGET. (Using the buff check
--     here would read "always missing" and re-cast Rupture every single time.)
function M:RuptureDue()
    if self:TalentRank(TALENT_TASTE) > 0 then
        return self:TasteLeft() < TFB_RENEW
    end
    -- Rupture is per-caster: two rogues on one mob each get their own, so
    -- another rogue's says nothing about ours. Expose Armor is the opposite and
    -- is deliberately NOT owner-checked - only one sits on a target at a time
    -- and re-applying over somebody else's is waste.
    return not (self:TargetDebuffUp("Rupture", "Ability_Rogue_Rupture")
        and Aegis_SBR:DebuffMine("Rupture", self:TargetId()))
end

-- Fire Cold Blood immediately before the Eviscerate it is meant to turn into a
-- crit. Confirmed in game that it costs no global cooldown, so both go out in
-- the same press - and that is the whole point: the buff applies to the NEXT
-- Sinister Strike, Backstab, Ambush, Noxious Assault or Eviscerate, and
-- Noxious Assault is a BUILDER. Popped at any other moment it is eaten by the
-- next builder for a fraction of the payoff, so it is deliberately not a
-- priority step of its own - it only ever rides along with a finisher.
-- Gated on cpFinish rather than a threshold of its own: that setting already
-- means "enough points for Eviscerate to be worth it", and it keeps the 3
-- minute cooldown off the execute finisher, which fires with whatever is on
-- hand (often 1-2 points) and would waste the crit.
function M:ColdBloodReady(cfg, cp)
    if not cfg.useColdBlood then return false end
    if cp < (cfg.cpFinish or 4) then return false end
    if not self:KnowsSpell("Cold Blood") then return false end
    if not self:OwnCDReady("Cold Blood") then return false end
    -- The energy check is not a nicety, it protects a three minute cooldown.
    -- Cold Blood is free and off the GCD, so it always "succeeds"; the
    -- Eviscerate behind it does not, and one that fails for want of energy
    -- leaves the buff to be eaten by the next Sinister Strike for a fraction
    -- of the payoff.
    if not Aegis_SBR:CanAfford("Eviscerate") then return false end
    return true
end


-- ============================================================
-- Subtlety.
--
-- Three abilities the other two trees do not have, and one shared cooldown.
-- Every one of them is gated on KnowsSpell as well as on its switch, so a
-- profile carrying them does nothing surprising on a rogue who has not trained
-- the talent.
-- ============================================================

-- Expose Armor is due when it is simply not on the target.
--
-- There is no better test available: a target debuff carries no readable time
-- left on this client (the core's snapshot resolves NAMES and stacks, nothing
-- more), so the refresh necessarily lands after it has dropped rather than
-- before. One global cooldown of gap every thirty seconds on an armor debuff is
-- a price worth paying for a check that cannot be wrong.
--
-- The throttle behind it is a safety net, not a timer. Without SuperWoW the
-- debuff may be unreadable altogether, and "not up" would then be true on every
-- single press - which would spend every combo point the rogue ever earns on
-- re-applying a debuff that was already there. The stamp is written by Rotate,
-- never by Decide, which must stay free of side effects.
-- Only the beat in which a cast that cannot be read back yet would be
-- re-sent; the thirty seconds are the ledger's job now (ExposeLeft). It was
-- 25, and a new mob with the same NAME as the last (the id falls back to the
-- name when the GUID cannot be read) inherited the whole window - the first
-- five points then went into Shadow of Death instead of Expose Armor.
local EXPOSE_RETRY = 3
-- Expose Armor lasts 30 seconds (tooltip, rank 5). Written to the debuff
-- ledger on every cast, so the time left is known on any client; where
-- ClassicAPI reads the real remaining time off the target, that wins.
local EXPOSE_DURATION = 30
-- Re-applied under this much time left: the "Expose Armor refresh under"
-- slider on the Subtlety tab (exposeRefresh), and nothing else. An earlier
-- version refreshed as soon as the reserve had five points, which put the
-- debuff back at thirteen seconds against a one second setting - a switch
-- the rotation walks around is worse than no switch.

-- Seconds per combo point assumed until the fight has measured its own
-- (see NoteComboRate): Hemorrhage costs 30 energy at 10 energy a second.
local CP_SECS_DEFAULT = 3.0
-- Margin on the rebuild estimate: the energy for Expose Armor itself after
-- the last builder, and a press or two.
local CP_RESERVE_MARGIN = 2.5

-- Mechanical and Elemental creatures take no bleed: Garrote is a bleed and
-- is not opened with on them (the press from stealth goes to Hemorrhage).
-- Rupture is still cast on them with Taste for Blood - the tooltip grants the
-- buff "regardless of successful application". Cached per target; an unknown
-- type answers "not immune". What the type cannot tell - a boss immune by
-- flag - the core's learned table does, from the one Garrote that failed on
-- that kind of mob (Aegis_SBR:KnownImmune, /sbr immune).
M.LEARN_IMMUNE = { ["Garrote"] = true }
function M:TargetIsBleedImmune()
    local id = self:TargetId()
    if id ~= self.bleedTypeId then
        local t = UnitCreatureType("target")
        self.bleedTypeId = id
        self.bleedImmune = (t == "Mechanical" or t == "Elemental")
    end
    if self.bleedImmune then return true end
    return Aegis_SBR.KnownImmune and Aegis_SBR:KnownImmune("Garrote") or false
end

-- In stealth? The client's own flag where it exists, the buff otherwise.
function M:Stealthed()
    if IsStealthed then return IsStealthed() and true or false end
    return self:HasBuff("Stealth") or self:HasBuff("Vanish")
end

-- A cast the client took can still be dodged or parried, and the ledger
-- written on the send then claims thirty seconds the target never carried -
-- reported as Expose Armor gone from the mob for a minute while the trace
-- counted it down twice. Two answers: the miss line in the combat log clears
-- the ledger at once (see the frame at the bottom), and where the target's
-- auras can be read at all, a debuff not readable a beat after the cast is
-- not there, whatever the ledger says.
local EXPOSE_SETTLE = 1.5

function M:ExposeLeft()
    local live = Aegis_SBR.TargetDebuffRemaining and Aegis_SBR:TargetDebuffRemaining("Expose Armor")
    if live and live > 0 then return live end
    local id = self:TargetId()
    local rec = id and Aegis_SBR.debuffLedger and Aegis_SBR.debuffLedger[id .. "|Expose Armor"]
    if rec and rec.expires then
        local left = rec.expires - GetTime()
        if left <= 0 then return nil end
        -- Readable target, cast settled, nothing there: it missed.
        if Aegis_SBR.Capability and Aegis_SBR:Capability("auras")
            and self.exposeT and (GetTime() - self.exposeT) > EXPOSE_SETTLE
            and not self:TargetDebuffUp("Expose Armor", "Ability_Warrior_Riposte") then
            Aegis_SBR.debuffLedger[id .. "|Expose Armor"] = nil
            return nil
        end
        return left
    end
    -- Readable on the target but with no time recorded (applied before the
    -- ledger knew this mob): treat it as fresh rather than as missing.
    if self:TargetDebuffUp("Expose Armor", "Ability_Warrior_Riposte") then return EXPOSE_DURATION end
    return nil
end

-- How long this fight has been taking per combo point, learned as it goes:
-- every combo point gained from a builder is timed, and the average is a
-- running one so a lucky Honor Among Thieves streak or a dodge does not set
-- the number for good. Called from Rotate with the count before and after.
function M:NoteComboRate(before, after, at)
    if not before or not after then return end
    if after > before and self.cpLastGainAt then
        local per = (at - self.cpLastGainAt) / (after - before)
        if per > 0.3 and per < 15 then
            self.cpSecs = self.cpSecs and (self.cpSecs * 0.7 + per * 0.3) or per
        end
    end
    if after ~= before then self.cpLastGainAt = at end
end

function M:ComboSecs()
    return self.cpSecs or CP_SECS_DEFAULT
end

-- The rate the reserve plans with: never faster than energy alone allows
-- (thirty energy a builder, ten a second), whatever a lucky streak measured.
-- Two logs had the estimate dip to 1.5-2.0 s on Honor Among Thieves procs,
-- the points spent on that promise, and the fifth point back two seconds
-- after the debuff had dropped.
local CP_SECS_FLOOR = 2.5
function M:ReserveSecs()
    local c = self:ComboSecs()
    if c < CP_SECS_FLOOR then c = CP_SECS_FLOOR end
    return c
end

-- Are the combo points spoken for by the next Expose Armor?
--
-- The debuff has to be up the whole fight, and it costs five points every
-- thirty seconds. So from the moment there is no longer time to spend five
-- points elsewhere AND build them back (Ruthlessness hands one straight back,
-- so four to build) before it drops, every other finisher stands down and
-- the points are pooled for it. What "time to build" means is measured on the
-- fight itself (ComboSecs), not assumed.
-- Seconds to build `n` combo points from `energy` pooled: one global
-- cooldown per builder, and the energy the builders need beyond what is
-- pooled comes in at ten a second. A measured rate cannot say this - a full
-- bar builds four points in four seconds, an empty one in twelve - and a
-- log had five points held at a hundred energy for six seconds because the
-- rate said "not enough time". Procs (Honor Among Thieves, the set's energy
-- return) only make this faster, so it errs on the safe side.
--
-- The energy comes in at the rate this fight has shown, not at the bare ten
-- a second: the measured seconds per point (ComboSecs) carry the procs -
-- Honor Among Thieves, an energy-return set - as an effective income, and
-- the builders' global cooldowns run while it accrues (they overlap, they do
-- not add). A version that summed cooldowns and regeneration at ten a second
-- reserved the points at 23 seconds left and held everything for 14 - Slice
-- and Dice down, the sigil and the Mark waiting.
function M:BuildSecs(n, energy)
    local cost = Aegis_SBR:SpellCost("Hemorrhage") or 30
    local income = cost / self:ComboSecs()          -- energy per second, as played
    if income < 10 then income = 10 end
    local short = n * cost - (energy or 0)
    if short < 0 then short = 0 end
    local byEnergy = short / income
    local byGcd = n * 1.0
    if byEnergy > byGcd then return byEnergy end
    return byGcd
end

-- Does the target live long enough for Expose Armor ("Expose Armor only if the
-- target lives")? Raid trash dies in six seconds with forty people on it, and
-- every new mob came without the debuff: a log had it missing on two thirds of
-- the presses, the reserve holding every finisher for it, and with that no
-- Rupture, no Taste for Blood, no Mark, no sigil and no Preparation.
--
-- An unknown time to kill (the first seconds on a target) answers no, except
-- on a boss, which always lives long enough: the opener reaches five points in
-- about three seconds, and a later log had Expose Armor spent there on trash
-- that died two to twelve seconds later, while the reserve held the energy at
-- the cap. Until the estimate stands, the points go to the other finishers.
-- The second return says the answer is "not known yet" rather than "too short".
function M:ExposeWorth(cfg)
    if not cfg.useExposeTTK then return true end
    if UnitClassification("target") == "worldboss" then return true end
    local ttk = Aegis_SBR:TargetTTK()
    if not ttk then return false, true end
    return ttk >= (cfg.exposeMinTTK or 20)
end

function M:ExposeReserve(cfg, cp)
    if not cfg.useExposeArmor or not self:KnowsSpell("Expose Armor") then return false end
    if not self:ExposeWorth(cfg) then return false end
    if self:TalentRank(TALENT_IEA) < 1 then return false end
    local left = self:ExposeLeft()
    if not left then return true end                 -- missing: the next five are its
    -- After a five-point finisher Ruthlessness hands one back: four to build,
    -- from what is left of the energy after that finisher.
    local energy = (UnitMana("player") or 0) - 30
    local need = self:BuildSecs(4, energy) + CP_RESERVE_MARGIN
    return left <= need
end

function M:ExposeDue(cfg)
    if not cfg.useExposeArmor then return false end
    if not self:ExposeWorth(cfg) then return false end
    if not self:KnowsSpell("Expose Armor") then return false end
    -- Without Improved Expose Armor the debuff only matches the warrior's Sunder
    -- stack instead of beating it, so five combo points every 30s buy nothing the
    -- raid did not already have. Suppress-only: this can stop a cast, never add
    -- one, so it cannot starve anything the way a widened gate could.
    if self:TalentRank(TALENT_IEA) < 1 then return false end
    local left = self:ExposeLeft()
    if left and left > (cfg.exposeRefresh or EXPOSE_REFRESH_DEFAULT) then return false end
    -- The retry throttle only where nothing can be read: with the debuff
    -- readable, "not there" is the answer and a missed cast is re-done at
    -- once rather than after a thirty second guess.
    local readable = Aegis_SBR.Capability and Aegis_SBR:Capability("auras")
    if not readable and self.exposeT and self.exposeId and self.exposeId == self:TargetId()
        and (GetTime() - self.exposeT) < EXPOSE_RETRY then
        return false
    end
    return true
end

-- Mark for Death: off cooldown, and not already running.
--
-- The cooldown alone would normally be enough - three minutes is far longer
-- than the eight second buff - but Preparation resets it, and re-casting into
-- the buff that is still up would throw the reset away. That is exactly what
-- the player who described this rotation meant by "wait for previous Mark to
-- end to do it again".
function M:MarkReady(cfg, cp, builder)
    if not cfg.useMark then return false end
    if not self:KnowsSpell("Mark for Death") then return false end
    if not self:OwnCDReady("Mark for Death") then return false end
    if cp > (cfg.markMaxCP or 3) then return false end
    if self:BuffTime("Mark for Death") > 0 then return false end
    if self.markSentAt and (GetTime() - self.markSentAt) < 8 and not self:OwnCDReady("Mark for Death") then return false end
    -- Hemorrhage first, then the Mark: the opener order the spec is played
    -- in (Garrote, Hemorrhage, Mark for Death, Expose Armor at five), and the
    -- Hemorrhage debuff then covers the Mark's own strike. Mid-fight the
    -- debuff is simply up, so this costs nothing there.
    if builder == "Hemorrhage" and self:KnowsSpell("Hemorrhage")
        and not self:TargetDebuffUp("Hemorrhage", "Spell_Shadow_LifeDrain") then
        return false
    end
    return true
end

-- Preparation only when it actually buys something back. Both of its targets
-- are down = the seven minute cooldown returns a three minute one and a one
-- minute one; either alone is not worth it.
function M:PreparationReady(cfg)
    if not cfg.usePreparation then return false end
    if not self:KnowsSpell("Preparation") then return false end
    if not self:OwnCDReady("Preparation") then return false end
    local want = false
    if cfg.useMark and self:KnowsSpell("Mark for Death") then
        if self:OwnCDReady("Mark for Death") then return false end
        want = true
    end
    if cfg.useShadowOfDeath and self:KnowsSpell("Shadow of Death") then
        if self:OwnCDReady("Shadow of Death") then return false end
        want = true
    end
    return want
end

-- Spend the surplus before refreshing a buff.
--
-- Slice and Dice and Envenom have fixed potency; only their DURATION scales
-- with the points spent. Duration is worth paying for exactly as long as the
-- fight lasts long enough to use it - and measured over 28 fights, a dungeon
-- pull runs 19s with 20s of downtime after it, during which the buff decays
-- to nothing. It carries into the next pull a median of 0.0 seconds. A 5-point
-- Slice and Dice buys 30s for the same 20 energy a 1-point one spends on 13s,
-- and on a 19 second fight the extra 17s is simply thrown away.
--
-- So above the ceiling the points go into Eviscerate instead, and the buff is
-- refreshed on the very next press with the point Ruthlessness returns. This
-- is the model experienced players describe, and it only holds while fights
-- are short - in a raid, where the buff runs its full length, the ceiling
-- belongs back at 5.
--
-- Never dumps when that would leave the buff down for nothing: an unaffordable
-- or unlearned Eviscerate, or evisExecuteOnly reserving it for the execute
-- phase, all fall through to the plain refresh.
-- Where surplus combo points may go instead of into a buff refresh.
--
-- Eviscerate normally, unless it is reserved for the execute phase. Rupture is
-- the fallback, but ONLY from its own threshold: a recast overwrites Taste for
-- Blood with whatever combo points it was cast at, so dumping two points into
-- it would replace a 10% buff with a 4% one - the exact trap the separate
-- ruptureCP slider exists to avoid.
--
-- nil means the surplus genuinely has nowhere to go.
function M:DumpTarget(cfg, cp)
    -- Rupture FIRST. Whenever its own threshold is reached and the buff is
    -- actually due, the points belong there and not in an Eviscerate - the
    -- Taste for Blood buff is what the combo points are being saved for.
    -- RuptureDue is the same test P3 uses, so the two cannot drift apart: with
    -- the talent it asks whether the buff is gone or inside its renew window,
    -- without it whether the bleed is missing from the target.
    if cfg.useRupture and self:KnowsSpell("Rupture")
        and cp >= (cfg.ruptureCP or 3) and self:RuptureDue() then
        return "Rupture"
    end
    -- Eviscerate takes the surplus only when Rupture cannot: below Rupture's
    -- threshold, with the buff still healthy, or with Rupture switched off.
    if not cfg.evisExecuteOnly and self:KnowsSpell("Eviscerate") then return "Eviscerate" end
    return nil
end


-- What the surplus should do when a buff is due above the ceiling:
--   nil      nothing special, refresh the buff as usual
--   "hold"   spend the press on nothing and let the energy come back
--   <spell>  cast this finisher instead; the refresh lands on the next press
function M:DumpDecision(cfg, cp)
    if cp <= (cfg.refreshMaxCP or 5) then return nil end
    local spell = self:DumpTarget(cfg, cp)
    -- No target at all: Eviscerate reserved for execute (or not yet learned)
    -- AND Rupture off or below its threshold. Refusing the refresh here would
    -- deadlock - the points cannot be spent, the buff can never come back, and
    -- the rotation would build into a full combo bar forever. This is the one
    -- case where a refresh above the ceiling is still the least bad outcome.
    if not spell then return nil end
    -- Short of energy is NEVER a reason to overspend the points. Energy passes
    -- on its own; combo points spent on duration this fight will not use do
    -- not come back.
    if not Aegis_SBR:CanAfford(spell) then return "hold" end
    return spell
end


-- ============================================================
-- Rotation. The core has already secured a target and ensured auto attack.
--
-- Split into Decide and Rotate (see Aegis_SBR:Perform). Decide works out what
-- the press should do and returns a plan WITHOUT casting anything, so the
-- upcoming-spell window can ask the same question four times a second without
-- a single ability going out. Rotate is then only "decide, then do it".
--
-- Because of that split, nothing in Decide may have side effects. The trace is
-- the one exception and it is gated on the `tracing` argument, which only the
-- real press passes - otherwise the preview would flood the log.
--
-- Cooldowns are off the global cooldown, so they ride along as `extras` in the
-- same press as one GCD ability. Everything else returns early so exactly one
-- GCD ability is chosen.
-- ============================================================
local function plan(spell, reason, extras)
    return { spell = spell, reason = reason, extras = extras }
end

-- Cold Blood belongs to the Eviscerate it is meant to turn into a crit, so it
-- is attached to that plan rather than being a decision of its own.
-- Seconds the target is measured to have left when that is shorter than the
-- "Only if the target lives" line, else nil. An unknown time to kill (the
-- first seconds of a fight, a target not losing health) never suppresses.
function M:RuptureTooShort(cfg)
    if not cfg.useRuptureTTK then return nil end
    local ttk = Aegis_SBR:TargetTTK()
    if ttk and ttk < (cfg.ruptureMinTTK or 16) then return ttk end
    return nil
end

function M:FinisherPlan(cfg, cp, spell, reason, extras)
    if spell == "Eviscerate" and self:ColdBloodReady(cfg, cp) then
        extras = extras or {}
        table.insert(extras, "Cold Blood")
    end
    return plan(spell, reason, extras)
end

function M:Decide(cfg, tracing)
    if cfg.spec == "subtlety" then return self:DecideSubtlety(cfg, tracing) end
    local cls = UnitClassification("target")
    local isElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")

    local builder = cfg.builder
    -- Backstab is refused from the front and refused without a dagger, and both
    -- were unchecked: chosen as the builder under either condition, every press
    -- went into a refusal. Fall back to the strike that has no requirement
    -- rather than standing still.
    --
    -- Only a DEFINITE no falls back. No UnitXP, or an item the client has not
    -- cached, answers "cannot tell" and Backstab is used exactly as before.
    if builder == "Backstab"
        and not (Aegis_SBR:PositionAllows("behind") and Aegis_SBR:WeaponAllows("dagger")) then
        builder = self:KnowsSpell("Sinister Strike") and "Sinister Strike" or ""
    end
    if builder == "" then
        -- Both alternatives are talents, so knowing one says which tree was
        -- spent in: Noxious Assault means Assassination, Hemorrhage means at
        -- least ten points in Subtlety. Sinister Strike is what is left.
        if self:KnowsSpell("Noxious Assault") then builder = "Noxious Assault"
        elseif self:KnowsSpell("Hemorrhage") then builder = "Hemorrhage"
        else builder = "Sinister Strike" end
    end
    -- Ghostly Strike replaces the builder for this press whenever it is off
    -- cooldown: more damage for the same energy and the same combo point. It
    -- overrides rather than queues, because a builder press is exactly what it
    -- is worth - it is not worth a finisher's slot.
    if cfg.useGhostly and self:KnowsSpell("Ghostly Strike") and self:OwnCDReady("Ghostly Strike") then
        builder = "Ghostly Strike"
    end
    local useSnd = cfg.useSnd and self:KnowsSpell("Slice and Dice")
    local useEnv = cfg.useEnvenom and self:KnowsSpell("Envenom")
    local useRup = cfg.useRupture and self:KnowsSpell("Rupture")
    -- Dying too soon for it: no Rupture, the points go to Eviscerate below.
    if useRup and self:RuptureTooShort(cfg) then useRup = false end
    local cpEvis = cfg.cpFinish or 4

    local cp = GetComboPoints("player", "target")
    local now = GetTime()

    -- Off-GCD cooldowns ride along with whatever else the press does. Gated on
    -- their own cooldown as well as on being known: the cast would fail anyway
    -- while they are down, but the preview would otherwise list them forever.
    local extras
    if cfg.popCDs or (cfg.autoCDElite and isElite) then
        extras = {}
        if self:KnowsSpell("Adrenaline Rush") and self:OwnCDReady("Adrenaline Rush") then
            table.insert(extras, "Adrenaline Rush")
        end
        if self:KnowsSpell("Blade Flurry") and self:OwnCDReady("Blade Flurry") then
            table.insert(extras, "Blade Flurry")
        end
        if table.getn(extras) == 0 then extras = nil end
    end

    -- Execute: once the target is nearly dead, finish with whatever combo
    -- points are on hand rather than risk them going to waste on the kill.
    --
    -- The health percentage is the ONLY thing that starts the execute phase.
    -- Time to kill was briefly allowed to start it too and that was wrong: a
    -- normal mob's whole life is shorter than any sensible window, so "dies
    -- within 4 seconds" is true from the first measurement onward and the
    -- rotation dumped 1-point Eviscerates from full health. Time can only ever
    -- take the execute phase AWAY, never grant it - and only below cpFinish,
    -- so a full-value finisher is never held back. Unknown TTK never suppresses.
    local execute = cfg.useExecute and cp >= (cfg.executeMinCP or 1)
        and self:TargetHPPct() <= (cfg.executeHpPct or 10)
    local ttk = Aegis_SBR:TargetTTK()
    local ttkWin = cfg.executeTTK or 0
    if execute and cp < cpEvis and ttkWin > 0 and ttk and ttk > ttkWin then
        execute = false
    end

    if tracing and self:Tracing() then
        self:Trace("cp=" .. cp
            .. " build=" .. builder
            .. " snd=" .. (useSnd and string.format("%.1fs", self:BuffTime("Slice and Dice")) or "-")
            .. " env=" .. (useEnv and string.format("%.1fs", self:BuffTime("Envenom")) or "-")
            .. " tfb=" .. (useRup and ((self:TalentRank(TALENT_TASTE) > 0)
                and string.format("%.0fs", self:TasteLeft())
                or (self:TargetDebuffUp("Rupture", "Ability_Rogue_Rupture") and "dot" or "no-dot")) or "-")
            .. " rip=" .. ((cfg.useRiposte and now < (self.riposteExpiry or 0)) and "Y" or "N")
            .. " sa=" .. ((cfg.useSurpriseAttack and now < (self.surpriseExpiry or 0)) and "Y" or "N")
            .. " en=" .. (UnitMana("player") or 0)
            .. "/" .. (Aegis_SBR:SpellCost("Eviscerate") or "?")
            .. " hp=" .. string.format("%.0f%%", self:TargetHPPct())
            .. " ttk=" .. (ttk and string.format("%.1fs", ttk) or "?")
            .. " exec=" .. (cfg.useExecute and (execute and "Y" or "N") or "-")
            .. " cap=" .. (cfg.refreshMaxCP or 5) .. "/" .. (cfg.executeMinCP or 1)
            .. " dump=" .. (self:DumpTarget(cfg, cp) or "-")
            .. " cb=" .. (cfg.useColdBlood and (self:KnowsSpell("Cold Blood")
                and (self:OwnCDReady("Cold Blood") and "rdy" or "cd") or "?") or "-")
            .. " elite=" .. (isElite and "Y" or "N")
            .. (cfg.useExposeArmor and (" ea=" .. (self:ExposeDue(cfg) and "due" or (self:ExposeLeft() and string.format("%.1fs", self:ExposeLeft()) or "up"))
                .. (self:ExposeReserve(cfg, cp) and "/reserve" or "") .. " cps=" .. string.format("%.1f", self:ComboSecs())) or "")
            .. (cfg.useShadowOfDeath and (" sod=" .. (self:KnowsSpell("Shadow of Death")
                and (self:OwnCDReady("Shadow of Death") and "rdy" or "cd") or "?")) or "")
            .. (cfg.useMark and (" mark=" .. (self:KnowsSpell("Mark for Death")
                and (self:OwnCDReady("Mark for Death") and "rdy" or "cd") or "?")) or "")
            .. (cfg.usePreparation and (" prep=" .. (self:PreparationReady(cfg) and "Y" or "N")) or "")
            .. (cfg.useGhostly and (" gs=" .. (self:KnowsSpell("Ghostly Strike")
                and (self:OwnCDReady("Ghostly Strike") and "rdy" or "cd") or "?")) or ""),
            -- Rogue never downranks (all ranks cost the same energy), so every
            -- cast below is a bare CastSpellByName(name) - vanilla resolves
            -- that to the highest known rank on its own. This line just
            -- surfaces the max rank on record for what would actually go out,
            -- so a bad rank pick would show up here instead of staying invisible.
            "rank: " .. builder .. "=R" .. self:MaxRank(builder)
            .. "  Eviscerate=R" .. self:MaxRank("Eviscerate")
            .. (useSnd and ("  SnD=R" .. self:MaxRank("Slice and Dice")) or "")
            .. (useEnv and ("  Envenom=R" .. self:MaxRank("Envenom")) or "")
            .. (useRup and ("  Rupture=R" .. self:MaxRank("Rupture")) or "")
            .. ((cfg.useRiposte and self:KnowsSpell("Riposte")) and ("  Riposte=R" .. self:MaxRank("Riposte")) or "")
            .. ((cfg.useSurpriseAttack and self:KnowsSpell("Surprise Attack")) and ("  SurpriseAttack=R" .. self:MaxRank("Surprise Attack")) or ""))
    end

    -- P0 Garrote from stealth: the opener. Requires stealth and being behind
    -- the target; Initiative makes it two combo points and Serrated Blades
    -- adds to the bleed. A definite "not behind" falls through to the normal
    -- builder rather than a refusal; "cannot tell" lets it go out.
    if cfg.useGarrote and self:KnowsSpell("Garrote") and self:Stealthed()
        and Aegis_SBR:PositionAllows("behind") then
        if not Aegis_SBR:CanAfford("Garrote") then
            return plan(nil, "pooling energy for Garrote", extras)
        end
        return plan("Garrote", "opener from stealth", extras)
    end

    -- P1 Riposte, combo point independent, only inside the parry window
    if cfg.useRiposte and self:KnowsSpell("Riposte") and now < (self.riposteExpiry or 0) then
        return plan("Riposte", "parry window open", extras)
    end

    -- P1b Surprise Attack, combo point independent, only inside the target's
    -- dodge window. Guaranteed to land and cheap, so like Riposte it jumps the
    -- normal builder/finisher queue rather than waiting its turn - missing the
    -- window wastes the proc entirely.
    if cfg.useSurpriseAttack and self:KnowsSpell("Surprise Attack") and now < (self.surpriseExpiry or 0) then
        return plan("Surprise Attack", "dodge window open", extras)
    end

    -- P1c Mark for Death, above the builder because it IS a better builder:
    -- 135% weapon damage, two combo points, and it cannot be dodged, blocked or
    -- parried - plus 30% attack power for the whole party for eight seconds.
    -- Nothing a normal builder does competes with that, so it never waits its
    -- turn. Its own gate keeps it off the press when the two points it awards
    -- would run into the cap.
    if self:MarkReady(cfg, cp, builder) and Aegis_SBR:CanAfford("Mark for Death") then
        return plan("Mark for Death", "party cooldown, " .. cp .. " CP", extras)
    end

    -- P2 no combo points, build (prevents an empty finisher)
    if cp == 0 then
        return plan(builder, "no combo points", extras)
    end

    -- How much life is left on each maintained buff - read straight off the
    -- real buff timer. 0 is a meaningful renew setting ("wait until it has
    -- actually dropped") and 0 is truthy in Lua, so the `or` fallback only
    -- fires for a genuinely unset field. The test is <= rather than < so that
    -- a lapsed buff, which reads as 0 seconds left, still counts as due.
    local sndLeft = useSnd and self:BuffTime("Slice and Dice") or 0
    local envLeft = useEnv and self:BuffTime("Envenom") or 0
    local renew = cfg.buffRenew or BUFF_RENEW
    local sndDue = useSnd and sndLeft <= renew
    local envDue = useEnv and envLeft <= renew
    local rupDue = useRup and self:RuptureDue()
    local rupCP = cfg.ruptureCP or 3

    -- Execute first: on a dying target a fresh buff or bleed is wasted, so the
    -- points go straight into damage.
    if execute then
        return self:FinisherPlan(cfg, cp, "Eviscerate",
            "execute, target at " .. string.format("%.0f%%", self:TargetHPPct()), extras)
    end

    -- P2b Expose Armor, ahead of every other finisher.
    --
    -- It is the only one that serves the RAID rather than this rogue: with
    -- Improved Expose Armor it reduces more armor than Sunder Armor does, so it
    -- replaces the warrior's stack rather than duplicating it, and every
    -- physical attacker on the target gains from it. That is worth more than the
    -- Eviscerate the same five points would have bought, which is precisely why
    -- it outranks them - a Subtlety rogue is not a damage meter entry.
    --
    -- Short of energy it POOLS rather than falling through. Falling through
    -- would hand the points to Rupture or Eviscerate, and the debuff would then
    -- have to wait for a fresh five - which on a thirty second refresh means it
    -- is simply down.
    if self:ExposeDue(cfg) and cp >= (cfg.exposeCP or 5) then
        if not Aegis_SBR:CanAfford("Expose Armor") then
            return plan(nil, "pooling energy for Expose Armor, " .. cp .. " CP", extras)
        end
        local left = self:ExposeLeft()
        return plan("Expose Armor", (left and string.format("%.1fs left", left) or "armor debuff missing") .. ", " .. cp .. " CP", extras)
    end

    -- P2b' The points are reserved for the next Expose Armor (see
    -- ExposeReserve): no other finisher until it has gone out. Below five,
    -- build; at five, pool - the next press inside the refresh window casts it.
    if self:ExposeReserve(cfg, cp) then
        local left = self:ExposeLeft()
        local why = string.format("Expose Armor in %s, %.1fs per CP", left and string.format("%.1fs", left) or "?", self:ComboSecs())
        if cp >= (cfg.exposeCP or 5) then
            return plan(nil, "holding " .. cp .. " CP for " .. why, extras)
        end
        return plan(builder, "building for " .. why, extras)
    end

    -- P2c Shadow of Death, above the maintained buffs.
    --
    -- One minute of cooldown against buffs that can be refreshed on any press:
    -- a missed sigil window is gone, a refresh is merely late. And it is the one
    -- finisher whose value comes from OUTSIDE the rogue - it banks a share of
    -- all damage the target takes over six seconds - so it wants to go out while
    -- the target is being hit by everyone, which is exactly the moment the party
    -- buff from Mark for Death has just started.
    --
    -- Pools for the same reason Expose Armor does: the points are the ability.
    if cfg.useShadowOfDeath and self:KnowsSpell("Shadow of Death")
        and self:OwnCDReady("Shadow of Death") and cp >= (cfg.sodCP or 5) then
        if not Aegis_SBR:CanAfford("Shadow of Death") then
            return plan(nil, "pooling energy for Shadow of Death, " .. cp .. " CP", extras)
        end
        return plan("Shadow of Death", "sigil, " .. cp .. " CP", extras)
    end

    -- P3 Rupture, at its OWN combo-point threshold. It goes first among the
    -- buffs because it is the only one whose strength scales with the points
    -- spent (2% melee damage per point via Taste for Blood), and the moment
    -- another buff comes due is exactly the combo-point peak. Ruthlessness
    -- hands a point straight back, which lands the cheap refreshes below on
    -- the very next press.
    if rupDue and cp >= rupCP then
        return plan("Rupture", "Taste for Blood due, " .. cp .. " CP", extras)
    end

    -- P4/P5 the two fixed-strength buffs. Only their DURATION scales with combo
    -- points, so above the ceiling the surplus goes into a finisher first and
    -- the refresh lands on the next press with the point Ruthlessness returns.
    if sndDue then
        local d = self:DumpDecision(cfg, cp)
        if d == "hold" then
            return plan(nil, "pooling energy, " .. cp .. " CP to spend", extras)
        end
        if d then
            return self:FinisherPlan(cfg, cp, d, "spending " .. cp .. " CP before the refresh", extras)
        end
        return plan("Slice and Dice", string.format("%.1fs left", sndLeft), extras)
    end
    if envDue then
        local d = self:DumpDecision(cfg, cp)
        if d == "hold" then
            return plan(nil, "pooling energy, " .. cp .. " CP to spend", extras)
        end
        if d then
            return self:FinisherPlan(cfg, cp, d, "spending " .. cp .. " CP before the refresh", extras)
        end
        return plan("Envenom", string.format("%.1fs left", envLeft), extras)
    end

    -- P6 Eviscerate as the surplus finisher: only once every maintained buff is
    -- healthy. Suppressed while Rupture is waiting for its threshold, so it can
    -- never steal the points Rupture is saving up for. Can be reserved for the
    -- execute phase entirely (evisExecuteOnly).
    if not cfg.evisExecuteOnly and not rupDue and cp >= cpEvis then
        return self:FinisherPlan(cfg, cp, "Eviscerate", cp .. " CP, buffs healthy", extras)
    end

    -- P6b Preparation. Last, because it deals no damage and applies nothing:
    -- it is only ever worth a press when there is no finisher due, and its own
    -- gate already insists that both Mark for Death and Shadow of Death are
    -- actually on cooldown, so the seven minutes buy back three plus one.
    if self:PreparationReady(cfg) then
        return plan("Preparation", "resetting Mark and the sigil", extras)
    end

    -- P7 otherwise build
    return plan(builder, "building to " .. cpEvis .. " CP", extras)
end

-- Vanish stands down this long after the client refused it (no Flash Powder,
-- or a stealth the fight will not allow).
local VANISH_BACKOFF = 60
-- The Mark waits for the sigil when the sigil is this close to coming back,
-- so the two go out as one burst; further away than this the Mark goes alone.
local BURST_WAIT = 20

-- ============================================================
-- Subtlety, the raid rotation - as played by a Subtlety rogue in a forty man
-- raid and written down for us, ability by ability:
--
--   Garrote, Hemo Hemo Hemo, Expose Armor, Slice and Dice, Hemo Hemo, (tea,)
--   Hemo Hemo, Rupture, Slice and Dice, Mark for Death, Vanish, Garrote,
--   Shadow of Death, Preparation, Mark for Death, Vanish, Garrote, Shadow of
--   Death, Slice and Dice, Hemo x4, Expose Armor, Slice and Dice, and so on.
--
-- On a bleed-immune target the same without Garrote (Hemorrhage breaks the
-- stealth Vanish gave, which is still used for the shield and the aggro
-- reset), and Rupture still goes out for Taste for Blood.
--
-- Which is the priority list below. Expose Armor is kept up ahead of every
-- other finisher, with the combo points reserved for it in time (see
-- ExposeReserve) - except inside the burst, where the Mark for Death buff is
-- running and the Sigil goes out regardless, as the rotation above does.
-- Slice and Dice is refreshed with whatever points are on hand, which after a
-- five-point finisher is the one Ruthlessness hands back. Eviscerate only
-- when nothing else is due, and only when switched on.
function M:DecideSubtlety(cfg, tracing)
    local cls = UnitClassification("target")
    local isElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    local now = GetTime()
    local cp = GetComboPoints("player", "target")

    local builder = cfg.builder
    if builder == "" or not self:KnowsSpell(builder) then
        builder = self:KnowsSpell("Hemorrhage") and "Hemorrhage" or "Sinister Strike"
    end
    if cfg.useGhostly and self:KnowsSpell("Ghostly Strike") and self:OwnCDReady("Ghostly Strike") then
        builder = "Ghostly Strike"
    end

    local extras
    if cfg.popCDs or (cfg.autoCDElite and isElite) then
        extras = {}
        if self:KnowsSpell("Blade Flurry") and self:OwnCDReady("Blade Flurry") then
            table.insert(extras, "Blade Flurry")
        end
        if table.getn(extras) == 0 then extras = nil end
    end

    local immune = self:TargetIsBleedImmune()
    local stealthed = self:Stealthed()
    -- The Mark's eight seconds. The buff is not readable by that name on the
    -- player on this client (two logs: Vanish never fired, the Mark read as
    -- "not up" a quarter second after its own cast), so the cast itself is
    -- the evidence: sent within eight seconds and the cooldown running.
    local markUp = self:BuffTime("Mark for Death") > 0
        or (self.markSentAt and (now - self.markSentAt) < 8
            and self:KnowsSpell("Mark for Death") and not self:OwnCDReady("Mark for Death")) or false
    local useSnd = cfg.useSnd and self:KnowsSpell("Slice and Dice")
    local sndLeft = useSnd and self:BuffTime("Slice and Dice") or 0
    local sndDue = useSnd and sndLeft <= (cfg.buffRenew or BUFF_RENEW)
    local useRup = cfg.useRupture and self:KnowsSpell("Rupture")
    -- A target that dies before the "Only if the target lives" line gets no
    -- Rupture at all - not for the bleed and not for Taste for Blood - and the
    -- Mark stops waiting for the buff (tfbWait below reads useRup).
    local rupShort = useRup and self:RuptureTooShort(cfg)
    if rupShort then useRup = false end
    -- Rupture is due when Taste for Blood is under the same "Refresh when
    -- under" line as Slice and Dice - the slider on the panel, not the
    -- assassination path's ten second half-life: that re-cast Rupture every
    -- twelve seconds of a twenty-two second buff, five points each time.
    local rupDue = useRup and ((self:TalentRank(TALENT_TASTE) > 0 and self:TasteLeft() <= (cfg.buffRenew or BUFF_RENEW))
        or (self:TalentRank(TALENT_TASTE) == 0 and self:RuptureDue()))
    local sodReady = cfg.useShadowOfDeath and self:KnowsSpell("Shadow of Death") and self:OwnCDReady("Shadow of Death")
    local eaDue = self:ExposeDue(cfg)
    -- Inside the burst (the Mark running) the reserve is suspended: the Sigil
    -- goes out, Expose Armor is re-applied when its window comes.
    local reserve = (not markUp) and self:ExposeReserve(cfg, cp)
    local eaLeft = self:ExposeLeft()

    -- Vanish refused since the last try (no reagent, most likely): stand down.
    if self.vanishAt and Aegis_SBR.SpellRefusedAnySince and Aegis_SBR:SpellRefusedAnySince("Vanish", self.vanishAt) then
        self.vanishAt = nil
        self.vanishBlockedUntil = now + VANISH_BACKOFF
    end
    local vanishOK = cfg.useVanishBurst and self:KnowsSpell("Vanish") and self:OwnCDReady("Vanish")
        and now >= (self.vanishBlockedUntil or 0)

    if tracing and self:Tracing() then
        self:Trace("sub cp=" .. cp .. " build=" .. builder
            .. " stealth=" .. (stealthed and "Y" or "n")
            .. " immune=" .. (immune and "Y" or "n")
            .. " ea=" .. (eaLeft and string.format("%.1fs", eaLeft) or "none") .. (eaDue and "/due" or "") .. (reserve and "/reserve" or "")
            .. (function()
                if not cfg.useExposeArmor then return "" end
                local worth, unknown = self:ExposeWorth(cfg)
                if worth then return "" end
                return unknown and "/ttk?" or "/short"
            end)()
            .. " cps=" .. string.format("%.1f", self:ComboSecs())
            .. " snd=" .. (useSnd and string.format("%.1fs", sndLeft) or "-")
            .. " tfb=" .. (useRup and string.format("%.0fs", self:TasteLeft()) or "-")
            .. " sod=" .. (cfg.useShadowOfDeath and (sodReady and "rdy" or "cd") or "-")
            .. " mark=" .. (cfg.useMark and (self:OwnCDReady("Mark for Death") and "rdy" or "cd") or "-") .. (markUp and "/up" or "")
            .. " vanish=" .. (cfg.useVanishBurst and (vanishOK and "rdy" or "cd") or "-")
            .. " prep=" .. (self:PreparationReady(cfg) and "Y" or "n")
            .. " en=" .. (UnitMana("player") or 0)
            .. " hp=" .. string.format("%.0f%%", self:TargetHPPct()))
    end

    -- P0 Garrote from stealth (the opener, and again after Vanish). Not on a
    -- bleed-immune target, and only from behind; there the press goes to the
    -- builder, which breaks the stealth as the rotation intends.
    if stealthed and cfg.useGarrote and self:KnowsSpell("Garrote") and not immune
        and Aegis_SBR:PositionAllows("behind") then
        -- The tooltip's thirty already carries Dirty Deeds (fifty untalented);
        -- a version that took twenty more off sent Garrote at nine energy,
        -- refused nine times in a row, and lost two seconds of the stealth.
        if not Aegis_SBR:CanAfford("Garrote") then
            return plan(nil, "pooling energy for Garrote", extras)
        end
        return plan("Garrote", "opener from stealth", extras)
    end

    -- The Expose Armor sent a moment ago is not confirmed yet (see Rotate):
    -- no other finisher may take its points in the meantime. A log had the
    -- send refused by the global cooldown and Rupture spending the five
    -- points a quarter second later.
    if self.exposeCheck and cp >= (cfg.exposeCP or 5) then
        return plan(nil, "confirming Expose Armor", extras)
    end

    -- P0b Execute: the target is nearly dead, and the points on hand go into
    -- Eviscerate before they die with it. The Execute section of the panel:
    -- health line, the fewest points it may spend, and the brake that calls it
    -- off below five points while the target is measured to live on. Ahead of
    -- Expose Armor - a debuff on a dying target is thirty seconds nobody uses.
    if cfg.useExecute and self:KnowsSpell("Eviscerate") and cp >= (cfg.executeMinCP or 1)
        and self:TargetHPPct() <= (cfg.executeHpPct or 10) then
        local ttk = Aegis_SBR:TargetTTK()
        local brake = cp < 5 and (cfg.executeTTK or 0) > 0 and ttk and ttk > cfg.executeTTK
        if not brake then
            if not Aegis_SBR:CanAfford("Eviscerate") then
                return plan(nil, "pooling energy for Eviscerate, execute", extras)
            end
            return self:FinisherPlan(cfg, cp, "Eviscerate",
                "execute, target at " .. string.format("%.0f%%", self:TargetHPPct()) .. ", " .. cp .. " CP", extras)
        end
    end

    -- P1 Expose Armor, ahead of every other finisher. Inside the reserve the
    -- five points have no other use, so it goes out the moment they are
    -- there rather than at the last two seconds: a log showed five points
    -- and a full energy bar held for six seconds - forty energy regenerated
    -- into nothing - to save six seconds of a thirty second debuff.
    if eaDue and cp >= (cfg.exposeCP or 5) and cfg.useExposeArmor
        and self:KnowsSpell("Expose Armor") and self:TalentRank(TALENT_IEA) >= 1 then
        if not Aegis_SBR:CanAfford("Expose Armor") then
            return plan(nil, "pooling energy for Expose Armor, " .. cp .. " CP", extras)
        end
        return plan("Expose Armor", (eaLeft and string.format("%.1fs left", eaLeft) or "armor debuff missing") .. ", " .. cp .. " CP", extras)
    end

    -- The burst is Mark, Vanish, Garrote, sigil - in that order. So the sigil
    -- waits for the Mark whenever the Mark is ready or about to be (within
    -- BURST_WAIT), and for Taste for Blood as the Mark does; alone it only
    -- goes out when the Mark is far away. A log had the sigil spent early on
    -- its own, so the Mark that followed had nothing to burst with and
    -- Preparation fired straight after it.
    -- Not while the reserve holds the points: Rupture cannot come then, and
    -- the Mark waiting for its buff locked the whole burst behind Expose Armor.
    local tfbWait = useRup and not reserve and self:TalentRank(TALENT_TASTE) > 0 and self:TasteLeft() <= 0
    local markSoon = false
    if cfg.useMark and self:KnowsSpell("Mark for Death") and not markUp then
        markSoon = self:OwnCDReady("Mark for Death") or ((Aegis_SBR:OwnCDLeft("Mark for Death") or 0) <= BURST_WAIT)
    end
    -- The burst stays open for a while after the Mark: Vanish, Garrote and
    -- the points to five take longer than the Mark's eight seconds, and the
    -- sigil is still the burst's finisher then - a log had it held for Taste
    -- for Blood at that moment and lost to the next Expose Armor.
    local burstOpen = markUp or (self.markSentAt and (now - self.markSentAt) < 20
        and self:KnowsSpell("Mark for Death") and not self:OwnCDReady("Mark for Death"))
    -- Held for the Mark only. It used to wait for Taste for Blood as well,
    -- and between bursts that never came true at a five-point moment: Taste
    -- for Blood runs 22 seconds, Expose Armor 30, the points come every ten -
    -- a log had the sigil ready for a hundred seconds and every five points
    -- going to Rupture, Expose Armor or Eviscerate around it.
    local sodHold = markSoon and not burstOpen

    -- P2a Rupture ahead of the sigil only when Taste for Blood has lapsed
    -- outright: ten percent of melee damage for its whole duration outranks
    -- one sigil, a mere refresh does not.
    -- Never inside the burst: there the five points are the sigil's (a log
    -- had Taste for Blood lapse exactly as the Garrote after Vanish landed,
    -- and Rupture took the burst's points).
    if not reserve and not burstOpen and rupDue and tfbWait and cp >= (cfg.ruptureCP or 5) then
        if not Aegis_SBR:CanAfford("Rupture") then
            return plan(nil, "pooling energy for Rupture, " .. cp .. " CP", extras)
        end
        return plan("Rupture", "Taste for Blood gone, " .. cp .. " CP", extras)
    end

    -- P2 Shadow of Death at five, the burst's finisher.
    if not reserve and sodReady and not sodHold and cp >= (cfg.sodCP or 5) then
        if not Aegis_SBR:CanAfford("Shadow of Death") then
            return plan(nil, "pooling energy for Shadow of Death, " .. cp .. " CP", extras)
        end
        return plan("Shadow of Death", "sigil, " .. cp .. " CP", extras)
    end

    -- P3 Rupture at five for Taste for Blood - on an immune target too, the
    -- buff does not need the bleed to land.
    if not reserve and rupDue and cp >= (cfg.ruptureCP or 5) then
        if not Aegis_SBR:CanAfford("Rupture") then
            return plan(nil, "pooling energy for Rupture, " .. cp .. " CP", extras)
        end
        return plan("Rupture", "Taste for Blood due, " .. cp .. " CP", extras)
    end

    -- P3' Where Rupture would have gone, on a target that dies before it pays:
    -- Eviscerate, with the same points.
    if rupShort and not reserve and cp >= (cfg.ruptureCP or 5) and self:KnowsSpell("Eviscerate") then
        if not Aegis_SBR:CanAfford("Eviscerate") then
            return plan(nil, "pooling energy for Eviscerate, " .. cp .. " CP", extras)
        end
        return self:FinisherPlan(cfg, cp, "Eviscerate",
            string.format("dies in %.0fs, no Rupture, %d CP", rupShort, cp), extras)
    end

    -- P4 Slice and Dice with the point Ruthlessness returned after a finisher
    -- - up to "Spend at most" points. Above that a finisher is closer than a
    -- refresh: five points go into Rupture or the sigil first, and Slice and
    -- Dice takes the point that comes back (a log had it refreshed with four
    -- points, twice, and Rupture waited).
    local sndOK = (not reserve) or (cp <= 2 and eaLeft and eaLeft > 6)
    if sndOK and sndDue and cp >= 1 and cp <= (cfg.refreshMaxCP or 5) then
        if not Aegis_SBR:CanAfford("Slice and Dice") then
            return plan(nil, "pooling energy for Slice and Dice, " .. cp .. " CP", extras)
        end
        return plan("Slice and Dice", string.format("%.1fs left, %d CP", sndLeft, cp), extras)
    end

    -- P5 Vanish into the burst: the Mark is running, the Sigil is ready, and
    -- the points are low enough for the Garrote that follows.
    if vanishOK and markUp and sodReady and cp <= (cfg.markMaxCP or 3)
        and not stealthed and UnitAffectingCombat("player") then
        return plan("Vanish", "burst: Garrote and the sigil next", extras)
    end

    -- P6 Preparation once the Mark and the sigil are both on cooldown, so the
    -- burst can be run again at once. Vanish is not waited for: a Vanish still
    -- ready loses nothing to the reset, and waiting for it deadlocked - Vanish
    -- waits for the sigil, the reset waited for Vanish (seen in a log: the
    -- reset stood ready for forty seconds and never went out).
    local vanishSpent = not cfg.useVanishBurst or not self:KnowsSpell("Vanish")
        or not self:OwnCDReady("Vanish") or now < (self.vanishBlockedUntil or 0)
    if self:PreparationReady(cfg) and vanishSpent and not markUp then
        return plan("Preparation", "resetting the burst", extras)
    end

    -- P7 Mark for Death, the burst's opener: two points, party attack power.
    -- Only once Taste for Blood is running (Rupture first, as the rotation
    -- has it), so the burst lands with the melee bonus up - and so the opener
    -- stays Garrote, Hemorrhage to five, Expose Armor. And not while the sigil
    -- is about to come back: the Mark, Vanish, Garrote and the sigil are one
    -- burst, and a Mark spent twenty seconds early leaves the sigil without
    -- the attack power it was meant to land under.
    local sodWait = false
    if cfg.useShadowOfDeath and self:KnowsSpell("Shadow of Death") and not sodReady then
        local cdLeft = Aegis_SBR:OwnCDLeft("Shadow of Death") or 0
        sodWait = cdLeft > 0 and cdLeft <= BURST_WAIT
    end
    -- With Vanish and the sigil ready the Mark opens a burst, and the Garrote
    -- after Vanish adds two more points: the Mark then goes out at one point
    -- at most, so Vanish (which needs three or fewer) follows at once. A log
    -- had the Mark at two points, Vanish blocked at four, and the burst
    -- scattered over the next Expose Armor.
    local burstReady = vanishOK and sodReady and not stealthed
    local markCap = burstReady and 1 or (cfg.markMaxCP or 3)
    if not tfbWait and not sodWait and cp <= markCap and self:MarkReady(cfg, cp, builder)
        and Aegis_SBR:CanAfford("Mark for Death") then
        return plan("Mark for Death", "party cooldown, " .. cp .. " CP", extras)
    end

    -- P7b Rupture ahead of an overflow Eviscerate when Taste for Blood will
    -- lapse before the next five points can be there: the buff is worth more
    -- than the Eviscerate, and the points now are the only ones in time (a
    -- log had Eviscerate at two seconds of the buff left, and Rupture then
    -- waited twenty-six seconds for the next five).
    if not reserve and useRup and self:TalentRank(TALENT_TASTE) > 0 and cp >= (cfg.ruptureCP or 5) then
        local tfbLeft = self:TasteLeft()
        local nextFive = self:BuildSecs(4, (UnitMana("player") or 0) - 30) + 1.0
        if tfbLeft > 0 and tfbLeft < nextFive and Aegis_SBR:CanAfford("Rupture") then
            return plan("Rupture", string.format("Taste for Blood lapses in %.0fs, before the next five", tfbLeft), extras)
        end
    end

    -- P8 five points and nothing due: the reserve holds them for Expose
    -- Armor, otherwise Eviscerate spends them when allowed.
    if cp >= (cfg.cpFinish or 5) then
        if reserve then
            -- Energy about to cap while the points wait: a Hemorrhage costs
            -- nothing that would not have been lost, and keeps its debuff up.
            if (UnitMana("player") or 0) >= 90 and self:KnowsSpell(builder) then
                return plan(builder, "energy at the cap while holding for Expose Armor", extras)
            end
            return plan(nil, string.format("holding %d CP for Expose Armor in %s", cp,
                eaLeft and string.format("%.1fs", eaLeft) or "?"), extras)
        end
        -- Only with room to spare before the next Expose Armor: an
        -- Eviscerate just outside the reserve left the debuff down for two
        -- seconds when the points came back slowly.
        -- The extra five seconds cover a slow rebuild on low energy; at a full
        -- bar the rebuild is four global cooldowns, and the margin alone does.
        local energyNow = UnitMana("player") or 0
        local spare = (energyNow >= 90) and 1 or 5
        local room = (not eaLeft) or eaLeft > self:BuildSecs(4, energyNow - 30) + CP_RESERVE_MARGIN + spare
        if cfg.useEviscerate and self:KnowsSpell("Eviscerate") and room then
            if not Aegis_SBR:CanAfford("Eviscerate") then
                return plan(nil, "pooling energy for Eviscerate, " .. cp .. " CP", extras)
            end
            return self:FinisherPlan(cfg, cp, "Eviscerate", cp .. " CP, nothing else due", extras)
        end
        -- Five points, nothing due, no room even for that Eviscerate - and
        -- the energy about to cap. Idling here lost seven seconds at full
        -- energy in a log. Rupture early when Taste for Blood is past half,
        -- else a Hemorrhage for the energy's sake.
        if energyNow >= 90 then
            if useRup and self:TalentRank(TALENT_TASTE) > 0 and self:TasteLeft() <= 12
                and Aegis_SBR:CanAfford("Rupture") then
                return plan("Rupture", "energy at the cap, Taste for Blood refreshed early", extras)
            end
            if self:KnowsSpell(builder) then
                return plan(builder, "energy at the cap while holding " .. cp .. " CP", extras)
            end
        end
        return plan(nil, "holding " .. cp .. " CP", extras)
    end

    -- P9 build
    local why = reserve and (eaLeft and string.format("building for Expose Armor in %.1fs", eaLeft) or "building for Expose Armor (none up)")
        or ("building to " .. (cfg.cpFinish or 5) .. " CP")
    return plan(builder, why, extras)
end

function M:Rotate(cfg)
    -- Combo points gained since the last press, timed: what the Expose Armor
    -- reserve is measured against. Read before Decide, which may spend them.
    local cpNow = GetComboPoints("player", "target") or 0
    -- Did the Expose Armor sent last press go out? Its points are gone if it
    -- did. Still there: the client refused it, and the thirty seconds stamped
    -- on the send are withdrawn so the press re-sends it.
    -- Judged only once the server has had time to answer (the points drop
    -- on its confirmation, not on the send), so a slow answer is not read as
    -- a refusal.
    local chk = self.exposeCheck
    if chk and (GetTime() - chk.t) >= 0.6 then
        self.exposeCheck = nil
        if chk.id == self:TargetId() and cpNow >= chk.cp and chk.cp > 0 then
            if Aegis_SBR.debuffLedger and chk.id then Aegis_SBR.debuffLedger[chk.id .. "|Expose Armor"] = nil end
            self.exposeT = nil
            if self:Tracing() then self:Trace("Expose Armor did not go out (points still there) - again") end
        end
    end
    if self.cpSeenId ~= self:TargetId() then self.cpSeenId = self:TargetId(); self.cpSeen = nil; self.cpLastGainAt = nil end
    if self.cpSeen ~= nil then self:NoteComboRate(self.cpSeen, cpNow, GetTime()) end
    self.cpSeen = cpNow

    local p = self:Decide(cfg, true)
    -- Nothing is sent into the global cooldown. The client refuses such a
    -- send without a word, and every piece of bookkeeping below then records
    -- a cast that never happened - the Expose Armor ledger above all. The
    -- press is held and the next one, a quarter second later, sends. A spell
    -- on a cooldown of its own is not the global cooldown and is not held
    -- here; Decide already asked OwnCDReady for those.
    if p and p.spell and not Aegis_SBR:IsReady(p.spell)
        and (Aegis_SBR:OwnCDLeft(p.spell) or 0) <= 0 then
        if self:Tracing() then self:Trace("global cooldown, holding " .. p.spell) end
        return
    end
    -- Read BEFORE Perform: the cast spends them, and Rupture's duration is what
    -- was spent (8s at one combo point, two more per point after that).
    local cpSpent = GetComboPoints("player", "target") or 0
    Aegis_SBR:Perform(self, p)
    -- Whose Rupture is on the mob. Two rogues each get their own, so without
    -- this the second one to arrive reads the first one's as theirs and never
    -- applies a bleed at all. Written here rather than in Decide, which the
    -- preview window asks four times a second and which must not change
    -- anything.
    if p and p.spell == "Rupture" and cpSpent > 0 then
        -- Taste for Blood adds six seconds to the bleed (tooltip).
        local tfb = (self:TalentRank(TALENT_TASTE) > 0) and 6 or 0
        Aegis_SBR:NoteDebuffApplied(self:TargetId(), "Rupture", 6 + 2 * cpSpent + tfb)
    end
    if p and p.spell == "Vanish" then self.vanishAt = GetTime() end
    if p and p.spell == "Mark for Death" then self.markSentAt = GetTime() end
    -- Expose Armor has neither a cooldown to read nor a readable duration on the
    -- target, so the one thing that stops it re-firing on a client that cannot
    -- see the debuff is remembering the attempt. Written HERE and not in Decide:
    -- Decide is asked four times a second by the preview window and must not
    -- change anything.
    if p and p.spell == "Expose Armor" then
        self.exposeT = GetTime()
        self.exposeId = self:TargetId()
        -- Thirty seconds from now, for ExposeLeft on a client that cannot read
        -- the time off the target - PROVISIONALLY: the next press checks that
        -- the points were actually spent (see the top of Rotate). A send a
        -- quarter second behind a builder is refused by the global cooldown
        -- with no message, and stamping it anyway had the rotation treat the
        -- debuff as up and put the five points into Rupture instead.
        Aegis_SBR:NoteDebuffApplied(self:TargetId(), "Expose Armor", EXPOSE_DURATION)
        self.exposeCheck = { cp = cpSpent, id = self:TargetId(), t = GetTime() }
    end
    -- A finisher spent the points: the next gain is timed from here, not from
    -- the last builder before it.
    if p and p.spell and cpSpent > 0 and (p.spell == "Expose Armor" or p.spell == "Shadow of Death"
        or p.spell == "Rupture" or p.spell == "Eviscerate" or p.spell == "Slice and Dice" or p.spell == "Envenom") then
        self.cpLastGainAt = GetTime()
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "cp" then
        local n = tonumber(t[2])
        local cfg = M:TabView(Aegis_SBR:GetActiveProfile(), M)
        if cfg and n and n >= 1 and n <= 5 then
            cfg.cpFinish = n
            msgOut("finisher combo points = " .. n .. ".")
        else
            msgOut("usage: /sbr cp <1-5> (sets the active profile)", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end

-- ============================================================
-- Parry window tracker for Riposte. Owned by the module, stays inert while
-- Riposte is not learned or the option is off. (The old pre-pull poison
-- reminder was retired: the poison Quick Bar / rebuff buttons in
-- Aegis_SBR_BuffUp already surface a missing poison on screen.)
-- ============================================================
local riposteFrame = CreateFrame("Frame")
riposteFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
riposteFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")   -- talents respent
riposteFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
        if arg1 and string.find(string.lower(arg1), "parry") then
            M.riposteExpiry = GetTime() + 5.5
        end
    elseif event == "CHARACTER_POINTS_CHANGED" then
        M.talentCache = nil   -- Taste for Blood may have been (un)learned
    end
end)

-- ============================================================
-- Dodge window tracker for Surprise Attack - the mirror image of the parry
-- tracker above: OUR attack getting dodged by the target, not us parrying
-- theirs, so it listens on CHAT_MSG_COMBAT_SELF_MISSES instead. The 5.5s
-- window length is carried over from Riposte's (audit R1: Turtle's actual
-- Surprise Attack window is unconfirmed - verify in-game and adjust if it
-- turns out shorter/longer, e.g. by watching how often "sa=Y" in /sbr trace
-- goes stale before a press catches it).
-- ============================================================
local surpriseFrame = CreateFrame("Frame")
surpriseFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
-- Ability misses ("Your Expose Armor was dodged by X.") arrive on the spell
-- channel, not on SELF_MISSES.
surpriseFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
surpriseFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        if arg1 and string.find(string.lower(arg1), "dodge") then
            M.surpriseExpiry = GetTime() + 5.5
        end
    end
    -- Expose Armor that did not land: forget the thirty seconds the ledger
    -- was given on the send, so the next five points go into it again.
    if arg1 and string.find(arg1, "Expose Armor", 1, true) then
        local l = string.lower(arg1)
        if string.find(l, "dodge") or string.find(l, "parr") or string.find(l, "miss")
            or string.find(l, "immune") or string.find(l, "resist") or string.find(l, "block") then
            local id = M:TargetId()
            if id and Aegis_SBR.debuffLedger then Aegis_SBR.debuffLedger[id .. "|Expose Armor"] = nil end
            M.exposeT = nil
            if Aegis_SBR.logging then Aegis_SBR:LogWrite("Expose Armor did not land: " .. arg1) end
        end
    end
end)
