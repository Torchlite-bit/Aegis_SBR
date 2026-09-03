-- ============================================================
-- Class_Shaman  -  shaman module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Enhancement, Elemental, and Tank, mode
-- adaptive, works from level 1.
-- ============================================================
-- Model:
--  * Three modes, chosen in the panel or with /sbr mode:
--      - enhancement (melee): auto-attack, Stormstrike, Lightning Strike,
--        a shock on cooldown, with Lightning Bolt weaved as a filler.
--      - elemental (caster): Flame Shock plus a Lightning Bolt filler that
--        builds Electrify, reacting to Elemental Focus (Clearcasting).
--      - tank: Earth Shock threat on cooldown, Stormstrike for the Nature
--        buff, Lightning Strike, an optional Earthshaker Slam taunt.
--  * Level 1+: a fresh shaman only has Lightning Bolt and melee, so the
--    Lightning Bolt filler carries the early levels and everything else
--    (shocks, shields, Stormstrike, Lightning Strike, totems) switches
--    itself on through KnowsSpell as it is learned. The profile is never
--    flagged for a not-yet-learned ability.
--  * Talent automation:
--      - Stormstrike and Lightning Strike are TALENT abilities that appear
--        in the spellbook when talented, so KnowsSpell detects them and the
--        rotation includes them automatically when present.
--      - Elemental Focus grants no spell (it is a passive crit proc that
--        makes the next spell 60% cheaper), so KnowsSpell cannot see it.
--        We read the talent tree to know it is present and surface the
--        Clearcasting proc, the one spot a talent read helps here (the same
--        approach the warlock uses for Nightfall).
--  * Shocks share one cooldown, so a single shock choice is cast when ready;
--    Flame Shock is treated as a maintained DoT, Earth/Frost as on-cooldown.
--  * Cast-time spells are queued with QueueSpellByName when available so the
--    rotation never clips the current cast.
-- ============================================================

local M = Aegis_SBR:NewClassModule("SHAMAN")
M.uiTitle = "Shaman"
-- Rotate runs under Aegis_SBR:Preview without casting (see Pick/Later).
M.previewReady = true
M.uiHeight = 698
M.meleeAutoAttack = false   -- melee swing is managed per-mode in the module

-- Talent that grants the Clearcasting proc. It grants no spell, so KnowsSpell
-- cannot see it; reading the talent rank is the only way to know it is present.
-- Adjust the name here if Turtle renames it (confirm with /sbr talents).
local TALENT_CLEARCAST = "Elemental Focus"

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- Flame Shock blind-reapply interval when its debuff cannot be detected.
local FLAMESHOCK_DUR = 12

-- Restoration: flat-healing talent (Turtle's resto tree may have none, so this
-- is ~neutral by default), the NS-equivalent / Mana Tide spell names, and the
-- totem blind-redrop intervals. Confirm names/durations via /sbr talents and /sbr debug.
local TALENT_HEALBONUS   = "Purification"
local MANATIDE_SPELL     = "Mana Tide Totem"
-- Per-totem redrop interval. Two blanket constants (55 water / 110 everything
-- else) used to cover this, which quietly broke every totem that does not last
-- ~120s: Searing (60s) stood idle for 50s of each cycle, Magma (20s) for 90s,
-- Grounding (45s) for 65s. Reported from play as "totem upkeep doesn't work".
--
-- Values are the vanilla durations, re-dropped a few seconds early so the totem
-- is replaced rather than briefly missing. Anything not listed falls back to
-- TOTEM_REDROP_DEFAULT, which is safe for the 120s totems that make up most of
-- the earth and air slots. Fire Nova is deliberately absent: it detonates after
-- ~5s rather than persisting, so it is a cooldown ability, not upkeep (see
-- MaintainFireTotems).
-- Where a totem grants the player an aura, that aura - not a clock - is the
-- truth. It disappears when the totem expires, when it is destroyed, when it is
-- recalled for mana, AND when the group walks out of its range, which is the
-- normal case in a moving dungeon and which no timer can see. Spell name ->
-- aura name; the two differ for most of them.
--
-- NOT every totem has one: Searing, Magma and Fire Nova only attack, Grounding
-- only absorbs. Those are absent here on purpose and fall back to the timer
-- below, which is also why the per-totem durations still matter - they are
-- exactly the short-lived ones.
--
-- Names are vanilla baselines and want confirming on Turtle with /sbr debug.
-- A wrong name is self-correcting rather than harmful: see TotemBuffNames.
M.TOTEM_BUFF = {
    ["Strength of Earth Totem"] = "Strength of Earth",
    ["Stoneskin Totem"]         = "Stoneskin",
    ["Windfury Totem"]          = "Windfury Totem",
    ["Grace of Air Totem"]      = "Grace of Air",
    ["Nature Resistance Totem"] = "Nature Resistance",
    ["Windwall Totem"]          = "Windwall",
    ["Flametongue Totem"]       = "Flametongue Totem",
    ["Mana Spring Totem"]       = "Mana Spring",
    ["Healing Stream Totem"]    = "Healing Stream",
}

-- Seconds allowed for a freshly dropped totem's aura to register before its
-- absence is believed. Without this the rotation would re-drop every press
-- during the gap between the cast landing and the buff appearing.
local TOTEM_APPLY_GRACE = 3
-- Shortest gap between two drop attempts on the same element slot.
local TOTEM_RETRY = 1.5
-- Confirmed casts that produced no aura before the name is written off.
local TOTEM_MISS_MAX = 2

-- How long Fire Nova Totem occupies the fire slot before it detonates. There is
-- no API for the life of your own totem, so this is calibrated from play rather
-- than read: at the original guess of 5s a tester reported Magma arriving
-- "2-3 sec" after the nova went off, which is that guess overshooting.
--
-- Wrong in either direction costs something, and they are not symmetric: too
-- LOW replaces a nova that has not detonated yet and throws its damage away,
-- too HIGH just leaves the slot empty for a moment. So this errs slightly
-- toward late.
local NOVA_STAND = 2.5

-- Set by MaintainAllTotems from the profile, read by MaintainTotem.
local cfgTotemRange = false

-- Fallback radius in yards, used only when the tooltip cannot be read. Real
-- radii come from Aegis_SBR:SpellRadius per totem.
local TOTEM_RANGE = 20
-- Tolerance on the radius, so a totem sitting exactly on the boundary does not
-- flicker between "in" and "out" with every step. 7% is the established value.
local TOTEM_RANGE_SLACK = 1.07
-- The four element slots, in one place so range checks and the recall can walk
-- them without repeating the list.
local TOTEM_SLOTS = { "water", "earth", "fire", "air" }
local RECALL_SPELL = "Totemic Recall"

local TOTEM_REDROP_DEFAULT = 110
-- How far before its real expiry a totem is re-dropped when the duration was
-- read from the tooltip. Matches the few-seconds-early margin the table above
-- already bakes into its hardcoded values.
local TOTEM_REDROP_EARLY = 3
local TOTEM_REDROP = {
    ["Searing Totem"]           = 55,
    ["Magma Totem"]             = 18,
    ["Flametongue Totem"]       = 110,
    ["Mana Spring Totem"]       = 55,
    ["Healing Stream Totem"]    = 55,
    ["Grounding Totem"]         = 40,
    ["Windfury Totem"]          = 110,
    ["Grace of Air Totem"]      = 110,
    ["Nature Resistance Totem"] = 110,
    ["Windwall Totem"]          = 110,
    ["Strength of Earth Totem"] = 110,
    ["Stoneskin Totem"]         = 110,
    ["Tremor Totem"]            = 110,
    -- 15s totem, so the blind clock has to be tight. It also grants no player
    -- aura (it is a taunt/absorb pet, not a buff), which puts it in the same
    -- group as Searing/Magma/Grounding: without ClassicAPI's slot read this
    -- clock IS the whole knowledge of whether it still stands.
    ["Stoneclaw Totem"]         = 13,
}

-- Shock debuff texture on the TARGET (fragment match), for Flame Shock upkeep.
M.dotTex = {
    ["Flame Shock"] = "Spell_Fire_FlameShock",
}

M.SHOCKS  = { earth = "Earth Shock", frost = "Frost Shock", flame = "Flame Shock", none = "" }
M.SHIELDS = { lightning = "Lightning Shield", water = "Water Shield", earth = "Earth Shield", none = "" }

-- Weapon imbues: self-cast spells that enchant the MAIN-HAND weapon (key -> spell).
-- Confirm exact Turtle names with /sbr debug. Main-hand only in this version;
-- off-hand imbue application is a fragile weapon-click flow and is deferred.
M.IMBUES = { rockbiter = "Rockbiter Weapon", flametongue = "Flametongue Weapon",
             frostbrand = "Frostbrand Weapon", windfury = "Windfury Weapon", none = "" }
M.imbueAlias = { rockbiter = "rockbiter", rb = "rockbiter",
                 flametongue = "flametongue", ft = "flametongue",
                 frostbrand = "frostbrand", fb = "frostbrand",
                 windfury = "windfury", wf = "windfury", none = "none", off = "none" }

-- Restoration totem picks (key -> spell), resolved per element. Names are
-- vanilla baselines - confirm against Turtle's spellbook with /sbr debug.
M.WATER_TOTEMS = { manaspring = "Mana Spring Totem", healingstream = "Healing Stream Totem", none = "" }
-- Stoneclaw is offered even though it TAUNTS: kept on upkeep it will pull mobs
-- off the tank every time it is re-dropped. That is the player's call to make,
-- not ours (user decision, 2026-08-18) - it is genuinely wanted for solo and for
-- pet-style kiting. It is not a default anywhere.
M.EARTH_TOTEMS = { strength = "Strength of Earth Totem", stoneskin = "Stoneskin Totem", tremor = "Tremor Totem", stoneclaw = "Stoneclaw Totem", none = "" }
M.FIRE_TOTEMS  = { searing = "Searing Totem", magma = "Magma Totem", firenova = "Fire Nova Totem", flametongue = "Flametongue Totem", none = "" }
M.AIR_TOTEMS   = { windfury = "Windfury Totem", graceofair = "Grace of Air Totem", natureresist = "Nature Resistance Totem", grounding = "Grounding Totem", windwall = "Windwall Totem", none = "" }

M.modeAlias  = { enhancement = "enhancement", enh = "enhancement", melee = "enhancement",
                 elemental = "elemental", ele = "elemental", caster = "elemental",
                 tank = "tank",
                 restoration = "restoration", resto = "restoration", heal = "restoration", healing = "restoration" }
M.shockAlias = { earth = "earth", es = "earth", frost = "frost", fs = "frost",
                 flame = "flame", fls = "flame", none = "none", off = "none" }
M.shieldAlias= { lightning = "lightning", ls = "lightning", water = "water", ws = "water",
                 earth = "earth", es = "earth", none = "none", off = "none" }

M.templates = {
    starter = {  -- usable from level 1: Lightning Bolt + melee carry the early
                 -- levels, the rest enables itself as it is learned
        mode = "enhancement", shield = "lightning", shock = "earth",
        lbFiller = true, useStormstrike = true, useLightningStrike = true,
        useElementalMastery = false, useBloodlust = false,
        useTaunt = false,
        useTotems = true, totemWater = "manaspring",
        totemEarth = "none", totemFire = "none", totemAir = "none",
    },
    enhancement = {
        mode = "enhancement", shield = "lightning", shock = "earth",
        lbFiller = true, useStormstrike = true, useLightningStrike = true,
        useElementalMastery = false, useBloodlust = false,
        useTaunt = false,
        -- Windfury air + Searing fire + Strength earth + Mana Spring water.
        useTotems = true, totemWater = "manaspring",
        totemEarth = "strength", totemFire = "searing", totemAir = "windfury",
    },
    elemental = {
        mode = "elemental", shield = "water", shock = "flame",
        lbFiller = true, useStormstrike = false, useLightningStrike = false,
        useElementalMastery = true, useBloodlust = false,
        useTaunt = false,
        -- Searing fire (spellpower/DoT damage) + Mana Spring + Grace of Air.
        useTotems = true, totemWater = "manaspring",
        totemEarth = "none", totemFire = "searing", totemAir = "graceofair",
    },
    tank = {
        mode = "tank", shield = "lightning", shock = "earth",
        lbFiller = false, useStormstrike = true, useLightningStrike = true,
        useElementalMastery = false, useBloodlust = false,
        useTaunt = true,
        -- Stoneskin earth + Grounding air; no fire by default (threat comes from
        -- shocks/strikes), Mana Spring for sustain.
        useTotems = true, totemWater = "manaspring",
        totemEarth = "stoneskin", totemFire = "none", totemAir = "grounding",
        -- Rockbiter is the threat imbue if the tank turns imbue upkeep on (off by default).
        imbueMain = "rockbiter",
    },
    restoration = {  -- Restoration: group healer, downranked HW / LHW + Chain Heal
        mode = "restoration", shield = "water", shock = "none",
        healThreshold = 90, useManaTide = true, manaTideAt = 25,
        useNSCombo = true, nsHpPct = 40, useLesserHW = true, lhwPct = 50,
        useChainHeal = true, chainHealCount = 3,
        useTotems = true, totemWater = "manaspring",
        totemEarth = "none", totemFire = "none", totemAir = "none", healPower = 0,
        weaveDamage = false, weaveManaFloor = 40,
    },
}

function M:NormalizeProfile(c)
    if c.mode == nil then c.mode = "enhancement" end
    if c.shield == nil then c.shield = "lightning" end
    if c.shock == nil then c.shock = "earth" end
    if c.lbFiller == nil then c.lbFiller = true end
    if c.useStormstrike == nil then c.useStormstrike = true end
    if c.useLightningStrike == nil then c.useLightningStrike = true end
    if c.useElementalMastery == nil then c.useElementalMastery = false end
    if c.useBloodlust == nil then c.useBloodlust = false end
    if c.useTaunt == nil then c.useTaunt = false end
    -- Restoration (heal) profile fields
    if c.healThreshold == nil then c.healThreshold = 90 end
    -- Heal / dispel priority. A list of player names, in order: position 1 is
    -- healed first on a near tie, position 2 next, everyone else last. The same
    -- list decides who is dispelled first, where order is the only lever.
    if c.healPrio == nil then c.healPrio = false end
    if c.healPrioTarget == nil then c.healPrioTarget = false end
    if type(c.healPrioList) ~= "table" then c.healPrioList = {} end
    -- Dispelling. Off by default: it spends a global cooldown that would
    -- otherwise be a heal, and which afflictions are worth removing is a
    -- judgement call that belongs to the player.
    if c.useCure == nil then c.useCure = false end
    -- The crossover. Curing runs BEFORE healing while the worst-hurt member is
    -- above this; below it, healing wins. At 90 the group is cleansed first and
    -- topped up from 90 to 100 afterwards - the order that matters when the
    -- affliction is doing more damage than the missing tenth of a health bar.
    -- 0 makes curing always yield, 100 makes it always come first.
    if c.curePct == nil then c.curePct = 90 end
    if c.useManaTide == nil then c.useManaTide = true end
    if c.manaTideAt == nil then c.manaTideAt = 25 end
    if c.useNSCombo == nil then c.useNSCombo = true end
    if c.nsHpPct == nil then c.nsHpPct = 40 end
    if c.useLesserHW == nil then c.useLesserHW = true end
    if c.lhwPct == nil then c.lhwPct = 50 end
    if c.useChainHeal == nil then c.useChainHeal = true end
    if c.chainHealCount == nil then c.chainHealCount = 3 end
    if c.useTotems == nil then c.useTotems = true end
    -- AoE fire pair (Fire Nova on cooldown + Magma between). Off by default:
    -- it takes over the fire slot from the single-totem picker.
    if c.aoeFireTotems == nil then c.aoeFireTotems = false end
    -- Both off by default: they depend on SuperWoW position data that has not
    -- been verified in play yet, and a wrong distance would re-drop totems (and
    -- burn mana) for no reason.
    if c.totemRange == nil then c.totemRange = false end
    if c.totemRecall == nil then c.totemRecall = false end
    if c.totemWater == nil then c.totemWater = "manaspring" end
    if c.totemEarth == nil then c.totemEarth = "none" end
    if c.totemFire == nil then c.totemFire = "none" end
    if c.totemAir == nil then c.totemAir = "none" end
    if c.healPower == nil then c.healPower = 0 end
    if c.weaveDamage == nil then c.weaveDamage = false end
    if c.weaveManaFloor == nil then c.weaveManaFloor = 40 end
    -- Weapon imbue upkeep (main-hand). Default OFF; out-of-combat only unless
    -- imbueInCombat is opted in. (There is no "warn under X minutes" threshold:
    -- it could only be edited while the automation was on, which is exactly
    -- when nobody needs it, and it never did anything but print a chat line.)
    -- has under that many minutes left (0 = only when it is missing entirely).
    if c.maintainImbue == nil then c.maintainImbue = false end
    if c.imbueMain == nil then c.imbueMain = "windfury" end
    if c.imbueInCombat == nil then c.imbueInCombat = false end
    return c
end

-- Everything in the shaman kit is gated by KnowsSpell in the rotation, and the
-- Lightning Bolt filler covers a level 1 shaman, so nothing here is strictly
-- required. A profile is never flagged just because an ability is not trained
-- yet. Mirrors the hunter, druid and warlock.
function M:ProfileValidity(cfg)
    return true, {}
end

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

-- Talent rank by name, cached and cleared on CHARACTER_POINTS_CHANGED / login
-- (see the frame at the bottom of this file). Same approach as the paladin.
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

function M:HasClearcast()
    return self:TalentRank(TALENT_CLEARCAST) > 0
end

-- True while the Elemental Focus (Clearcasting) proc is up: the next spell is
-- 60% cheaper. Tried by name first, then a texture scan as a fallback.
function M:ClearcastUp()
    if self:HasBuff("Clearcasting") then return true end
    -- Fallback for a differently worded proc. Was scanning UnitBuff's first
    -- return for "Clearcast", but that return is the icon texture PATH, not a
    -- name, so it never matched. Harmless in practice - the exact name above
    -- is almost certainly right - but it was the same defect the druid's
    -- Eclipse check had, where the fallback WAS load-bearing.
    return Aegis_SBR:BuffNameContaining("Clearcast") ~= nil
end

-- The configured shield/shock resolved to a spell name ("" if none/off).
function M:ShieldSpell(cfg) return self.SHIELDS[cfg.shield or "lightning"] or "" end
function M:ShockSpell(cfg)  return self.SHOCKS[cfg.shock or "earth"] or "" end

-- Shocks reach 20yd, Lightning Bolt 30. Without this check the rotation picks
-- the shock first (correctly, it is the stronger use of the cooldown), the cast
-- silently fails out of range, and the press is spent doing nothing at all -
-- even though Lightning Bolt below it would have reached. Reported from play at
-- level 4, where Earth Shock plus Lightning Bolt IS the whole rotation.
--
-- IsSpellInRange is the same API the default action bars use to red-tint an
-- out-of-range icon. It returns nil when it cannot judge (no target, unknown
-- spell); nil is treated as "in range" so an unanswerable check can never
-- silence an ability that would otherwise have fired.
function M:InSpellRange(spell)
    if not spell or spell == "" then return false end
    if not UnitExists("target") then return false end
    if not IsSpellInRange then return true end
    -- pcall because the API does not answer "cannot tell" for a name it fails
    -- to resolve - it THROWS ("Unable to determine spell id from spell name").
    -- Three of the names reaching here are talent-granted - Stormstrike,
    -- Lightning Strike, Earthshaker Slam - and a Goblin Brainwashing Device
    -- swap unlearns and relearns exactly those, so a press landing in that
    -- window asks about a spell the client can no longer name. (The shocks are
    -- trainer spells and survive a respec, which is why elemental and
    -- restoration never saw this.) Unprotected the error aborted the whole
    -- press - no shock, no shield upkeep, no totems, no filler, no swing.
    local ok, r = pcall(IsSpellInRange, spell, "target")
    if not ok then return true end
    -- The API answers 1 in range, 0 out of range, and -1 when it cannot judge
    -- (unknown spell, no range data). ONLY an explicit 0 may block: reading -1
    -- as "out of range" would silence an ability over a question the client
    -- refused to answer, which matters most for the melee abilities gated
    -- below - a tank whose Stormstrike stopped firing would be far worse than
    -- one that occasionally swings at thin air.
    if r == 0 then return false end
    return true
end

-- Queue a known spell through SuperWoW's cast queue so a cast in progress is
-- not clipped. Returns true if the spell is known and was issued.
function M:Queue(name, reason)
    if not self:KnowsSpell(name) then return false end
    self.pickReason = reason
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name; p.reason = self.pickReason; p.queue = true
        return true
    end
    if QueueSpellByName then QueueSpellByName(name) else CastSpellByName(name) end
    return true
end

-- Start the white swing in the melee modes (enhancement / tank). Runs whether
-- or not SuperCleveRoidMacros is loaded: the core's EnsureAutoAttack only
-- toggles Attack when you are not already swinging, so it is a no-op if SCRM
-- already started it and fills the gap otherwise.
function M:EnsureMeleeSwing()
    Aegis_SBR:EnsureAutoAttack()
end

-- Flame Shock maintained as a DoT (used when shock == flame). Returns true if
-- a cast was issued. Detection prefers the exact name/texture; when detectable,
-- missing means cast; otherwise it is reapplied on a blind timer.
M.flameT = 0
function M:MaintainFlameShock()
    if not self:KnowsSpell("Flame Shock") then return false end
    if not self:IsReady("Flame Shock") then return false end
    local tex = self.dotTex["Flame Shock"]
    -- Per-caster, so another shaman's Flame Shock is not ours.
    if self:TargetDebuffUp("Flame Shock", tex)
        and Aegis_SBR:DebuffMine("Flame Shock", self:TargetId()) then
        return false
    end
    local detectable = tex or Aegis_SBR:CanResolveDebuffNames()
    local now = GetTime()
    -- ClassicAPI knows the real expiration, INCLUDING Turtle's Molten Blast
    -- refresh of the caster's own Flame Shock (audit item S1) - which the blind
    -- clock could never see, so it re-shocked a debuff Molten Blast had just
    -- topped up. A known remaining time means it is genuinely still ticking and
    -- the snapshot above has merely not caught up; hold. Unknown falls through
    -- to the blind clock exactly as before.
    if Aegis_SBR.TargetDebuffRemaining then
        local mine = Aegis_SBR:TargetDebuffMine("Flame Shock")
        if mine ~= false and Aegis_SBR:TargetDebuffRemaining("Flame Shock") then
            return false
        end
    end
    if not detectable and (now - (self.flameT or 0)) < FLAMESHOCK_DUR then return false end
    if self:Queue("Flame Shock", "DoT missing") then
        self:Later(function()
            self.flameT = now
            Aegis_SBR:NoteDebuffApplied(self:TargetId(), "Flame Shock", FLAMESHOCK_DUR)
        end)
        return true
    end
    return false
end

-- ============================================================
-- Restoration (heal engine)
-- Same engine as the priest / druid healers: scan the group, find the
-- worst-hurt reachable unit, and pick the cheapest rank that covers the
-- deficit (downranking). Heals cast with a SuperWoW unit argument so the
-- current target is never dropped. Shaman healing is all direct (no HoTs to
-- track) and there is no form to manage, so this is the leanest of the three.
-- Runs with no enemy targeted (see RunsWithoutTarget).
--
-- Rank base-heal / mana numbers are VANILLA BASELINES, meant to be tuned to
-- Turtle 1.18.1; the downrank decision only needs the ranks ordered roughly
-- right, so approximate values still pick a sane rank.
-- ============================================================
-- ------------------------------------------------------------
-- Weapon imbue upkeep (main-hand). Detection via the core's WeaponEnchant
-- helper (GetWeaponEnchantInfo). Conservative by design: AUTO-CAST only when
-- the main hand is bare (no replace popup, no GCD waste); when an imbue is
-- present but under the threshold, WARN instead of overwriting (the replace
-- popup is untested, and re-imbuing mid-fight costs a GCD). Out of combat the
-- upkeep runs freely; in combat it only acts with the imbueInCombat opt-in.
-- Main-hand only this version (off-hand imbue is a fragile weapon-click flow).
-- ------------------------------------------------------------
function M:ImbueSpell(cfg)
    return self.IMBUES[cfg.imbueMain or "none"] or ""
end

-- "apply" = main hand bare, so there is something to do. A still-present imbue
-- is never flagged: overwriting one that still works spends a global cooldown
-- for nothing, and that judgement belongs to the player, not the rotation.
-- (overwrite needed, warn only); nil = upkeep off / healthy / imbue unknown /
-- no SuperWoW enchant API.
function M:ImbueState(cfg)
    if not cfg.maintainImbue then return nil end
    local spell = self:ImbueSpell(cfg)
    if spell == "" or not self:KnowsSpell(spell) then return nil end
    local has, ms = Aegis_SBR:WeaponEnchant("main")
    if has == nil then return nil end   -- no enchant API (non-SuperWoW): degrade
    if not has then return "apply" end
    return nil
end

M.imbueWarnT = 0
-- Chat warning, used only as the FALLBACK when the on-screen rebuff button is
-- switched off. Several players reported simply not noticing a chat line in a
-- fight, which is why the button exists; printing both would just be noise, and
-- the button already says the same thing where it cannot be missed.
function M:ImbueWarn(text)
    if Aegis_SBR_BuffUp and Aegis_SBR_BuffUp:WatchImbueMH() then return end
    local now = GetTime()
    if (now - (self.imbueWarnT or 0)) < 8 then return end   -- own throttle
    self:Later(function() self.imbueWarnT = now end)
    Aegis_SBR:Msg(text, 1, 0.6, 0.2)
end

-- Returns true if an imbue cast was issued this press.
-- Placed HIGH in every rotation rather than last, which is where it used to
-- sit. Rockbiter is a THREAT imbue: every white swing without it is lost aggro,
-- and a tank that re-applies it only once Stormstrike, the shock, Lightning
-- Strike and four totem slots all happen to be busy spends most of a pull
-- generating less threat than it should. Reported from play as "it will do the
-- full cycle of attack before putting rockbiter on again". The same argument
-- holds for a missing Windfury on a damage shaman, without the aggro part.
--
-- The cost is one global cooldown at most every five minutes, which is why
-- only the taunt outranks it: losing the mob to a healer beats a second of
-- weaker threat.
function M:MaintainImbue(cfg)
    local state = self:ImbueState(cfg)
    if not state then return false end
    local spell = self:ImbueSpell(cfg)
    -- state == "apply": bare main hand. Cast out of combat always; in combat
    -- only with the opt-in (else just a throttled reminder).
    if UnitAffectingCombat("player") and not cfg.imbueInCombat then
        self:ImbueWarn(spell .. " is missing.")
        return false
    end
    return self:Pick(spell, "imbue missing")
end

function M:RunsWithoutTarget(cfg)
    if cfg.mode == "restoration" then return true end   -- a healer runs with no enemy targeted
    -- Pre-pull imbue upkeep is a self-buff and must run with no target selected.
    if self:ImbueState(cfg) then return true end
    -- Totemic Recall matters precisely when there is no enemy left: you have
    -- walked away and the totems are standing where the fight was. Gating it
    -- behind a target meant it only ever fired mid-combat, which is the one
    -- moment you do not want it.
    if self:RecallDue(cfg) then return true end
    return false
end

function M:ManaPct()
    local mx = UnitManaMax("player")
    if not mx or mx <= 0 then return 100 end
    return UnitMana("player") / mx * 100
end

-- Healing Wave: primary direct heal, downranked to size the deficit.
M.HW_HEAL = { 45, 75, 150, 270, 400, 610, 840, 1110, 1440, 1730 }
M.HW_MANA = { 25, 45, 80, 155, 200, 265, 350, 440, 560, 620 }
-- Lesser Healing Wave: fast (1.5s) single-target emergency.
M.LHW_HEAL = { 200, 320, 460, 635, 830, 1015 }
M.LHW_MANA = { 105, 145, 185, 235, 290, 335 }
-- Chain Heal: AoE bounce heal (sized by its first-target heal).
M.CH_HEAL = { 320, 405, 550 }
M.CH_MANA = { 260, 305, 350 }

-- Incoming-heal bookkeeping so a queued heal is subtracted from the deficit
-- and the next press does not pile onto an already-covered target.
M.healPending = {}
function M:CommitHeal(unit, amount, castTime)
    local n = UnitName(unit) or "?"
    self:Later(function()
        self.healPending[n] = { amt = amount or 0, t = GetTime() + (castTime or 1.5) }
    end)
end
function M:PendingFor(unit)
    local n = UnitName(unit) or "?"
    local rec = self.healPending[n]
    if not rec then return 0 end
    if GetTime() > rec.t then self.healPending[n] = nil; return 0 end
    return rec.amt or 0
end

function M:GroupUnits()
    local t = {}
    local nr = GetNumRaidMembers()
    if nr > 0 then
        for i = 1, nr do t[i] = "raid" .. i end
    else
        t[1] = "player"
        local np = GetNumPartyMembers()
        for i = 1, np do t[i + 1] = "party" .. i end
    end
    return t
end

-- Uses IsSpellInRange against the longest-range known heal for an exact
-- answer instead of the old ~28yd CheckInteractDistance proxy (shaman heals
-- reach 40yd, so the proxy was under-filtering by 12yd). Falls back to the
-- proxy only if neither heal is learned yet (very early leveling).
function M:Reachable(u)
    if u == "player" then return true end
    -- Recently refused by the client (no line of sight, or out of range after
    -- IsSpellInRange could not judge). Never for yourself: you are always in
    -- your own line of sight, and a stale mark would drop you from your own
    -- heal list.
    if Aegis_SBR:CastBlocked(u) then return false end
    if self:KnowsSpell("Healing Wave") then return Aegis_SBR:SpellReaches("Healing Wave", u)
    elseif self:KnowsSpell("Lesser Healing Wave") then return Aegis_SBR:SpellReaches("Lesser Healing Wave", u) end
    return CheckInteractDistance(u, 4) and true or false
end

-- Worst-hurt reachable friendly, counting pending heals toward its health.
M.CURES = {
    { spell = "Cure Poison",  types = { Poison = true } },
    { spell = "Cure Disease", types = { Disease = true } },
}

-- Cure somebody, if there is nothing more pressing.
--
-- The threshold is a CROSSOVER, not an on/off switch: above it the affliction
-- outranks the missing health, below it the heal does.
--
-- Never loops on a cure that cannot work. The unit is stamped on the attempt and
-- left alone for a few seconds afterwards, which covers a resisted dispel, an
-- affliction that outlasts its own removal, and a client that refused the cast.
M.cureFail = {}
function M:CureStep(cfg, worst)
    if not cfg.useCure then return false end
    if not self:GcdReady() then return false end
    if worst and worst < ((cfg.curePct or 90) / 100) then return false end
    -- Ordered by the same priority list the healing uses.
    local units = Aegis_SBR:AppendPets(Aegis_SBR:PrioOrderUnits(cfg, self:GroupUnits()))
    local unit, spell = Aegis_SBR:PickCure(units, self.CURES,
        function(u) return self:Reachable(u) end, self.cureFail)
    if not unit or not spell then return false end
    self:Later(function() self.cureFail[UnitName(unit) or "?"] = GetTime() end)
    self:CastOn(spell, unit)
    return true
end

function M:WorstHurt(ratio, cfg)
    local units = self:GroupUnits()
    local wU, wDef, wPct, wBest = nil, 0, 1, 0
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsFriend("player", u)
            and UnitHealthMax(u) > 0 and self:Reachable(u) then
            local mx = UnitHealthMax(u)
            local cur = UnitHealth(u) + self:PendingFor(u)
            local pct = cur / mx
            if pct < ratio then
                local def = mx - cur
                -- Eligibility reads REAL health above; the priority list only
                -- reorders what is already eligible, so it can never remove
                -- somebody from consideration. This module ranks by the size of
                -- the deficit, so the handicap discounts that deficit rather
                -- than padding a percentage - the same idea in this module's own
                -- currency.
                local weight = def * (1 - Aegis_SBR:PrioListHandicap(cfg, u) / 100)
                if weight > wBest then wU, wDef, wPct, wBest = u, def, pct, weight end
            end
        end
    end
    return wU, wDef, wPct
end

function M:HurtCount(ratio)
    local units = self:GroupUnits()
    local n = 0
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsFriend("player", u)
            and UnitHealthMax(u) > 0 and self:Reachable(u) then
            if (UnitHealth(u) + self:PendingFor(u)) / UnitHealthMax(u) < ratio then n = n + 1 end
        end
    end
    return n
end

-- Flat healing multiplier from talents. The Turtle restoration tree has no clean
-- "+X% healing" talent (unlike druid's Gift of Nature), so this is ~neutral by
-- default; adjust TALENT_HEALBONUS if a flat one exists. Gear +healing is the
-- main lever and is supplied via cfg.healPower.
function M:HealMods()
    return 1 + 0.02 * self:TalentRank(TALENT_HEALBONUS)
end

function M:EffHeals(baseHeals, coeff, mods, healPower)
    local t = {}
    for r = 1, table.getn(baseHeals) do
        t[r] = (baseHeals[r] + coeff * (healPower or 0)) * mods
    end
    return t
end

-- Smallest affordable rank whose effective heal covers the deficit; else the
-- largest affordable rank.
function M:PickRank(baseName, effHeals, manas, deficit, mana)
    local maxr = self:MaxRank(baseName)
    if maxr < 1 then return nil end
    if maxr > table.getn(effHeals) then maxr = table.getn(effHeals) end
    local chosen = nil
    for r = 1, maxr do
        if manas[r] and mana >= manas[r] then
            chosen = r
            if effHeals[r] and effHeals[r] >= deficit then break end
        end
    end
    if not chosen then return nil end
    return baseName .. "(Rank " .. chosen .. ")", (effHeals[chosen] or 0)
end

function M:CastOn(spell, unit)
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = spell
        p.reason = "on " .. (UnitName(unit) or unit or "?")
        return
    end
    Aegis_SBR:NoteUnitCast(unit)
    CastSpellByName(spell, unit)
end

function M:GcdReady()
    local probes = { "Healing Wave", "Lesser Healing Wave", "Lightning Bolt", "Chain Heal" }
    for i = 1, table.getn(probes) do
        if self:KnowsSpell(probes[i]) then return self:IsReady(probes[i]) end
    end
    return true
end

-- Nature's Swiftness equivalent. The talent is "Ancestral Swiftness"; the spell
-- it grants may be named either of these on Turtle - try both (confirm /sbr debug).
M.NS_CANDIDATES = { "Nature's Swiftness", "Ancestral Swiftness" }
function M:NSSpell()
    for i = 1, table.getn(self.NS_CANDIDATES) do
        if self:KnowsSpell(self.NS_CANDIDATES[i]) then return self.NS_CANDIDATES[i] end
    end
    return nil
end
function M:NSUp()
    for i = 1, table.getn(self.NS_CANDIDATES) do
        if self:HasBuff(self.NS_CANDIDATES[i]) then return true end
    end
    return false
end

-- Totem upkeep on a blind timer (no totem-state API on 1.12), one clock per
-- element. Re-drop intervals are conservative; tune if Turtle durations differ.
M.totemT = {}
-- Confirmed casts, keyed by totem SPELL. UNIT_CASTEVENT only fires for a cast
-- that actually went out, which is the one honest piece of evidence that a
-- totem was really placed - Queue() cannot tell us, it reports success as soon
-- as the spell is merely known.
M.totemCastT = {}
-- The totem's UNIT, per element slot. SuperWoW makes a placed totem an
-- addressable unit, which is the only way to measure the real distance to it -
-- and that in turn is the only signal available for the totems that grant no
-- aura at all (Searing, Magma, Fire Nova, Grounding). Learned from
-- UNIT_MODEL_CHANGED at the bottom of this file; the technique is Call of
-- Elements'.
M.totemGuid = {}
-- Which totem is standing in each slot, so its own radius can be looked up.
M.totemSpell = {}
-- Last ATTEMPT per element slot, successful or not. Purely a throttle: without
-- it a totem that cannot be cast (no mana) would claim every single press and
-- starve the rest of the rotation, because Queue always says yes.
M.totemTryT = {}
-- Aura-name bookkeeping, all keyed by spell.
M.totemBuffBad  = {}   -- name written off for this session
M.totemBuffMiss = {}   -- confirmed casts that produced no aura
M.totemMissAt   = {}   -- which confirmed cast a miss was already counted for

-- Every totem name we might drop, mapped to its element slot. Dropping a totem
-- of one element replaces the previous totem of that element, so a fresh cast
-- of any of these updates that slot's clock. Built once from the pick tables.
M.TOTEM_ELEMENT = nil
function M:TotemElementMap()
    if self.TOTEM_ELEMENT then return self.TOTEM_ELEMENT end
    local m = {}
    local function add(tbl, slot) for _, spell in pairs(tbl) do if spell ~= "" then m[spell] = slot end end end
    add(self.WATER_TOTEMS, "water"); add(self.EARTH_TOTEMS, "earth")
    add(self.FIRE_TOTEMS, "fire");   add(self.AIR_TOTEMS, "air")
    -- Mana Tide / Healing Stream share the water slot; already covered by WATER.
    self.TOTEM_ELEMENT = m
    return m
end

-- SuperWoW's UNIT_CASTEVENT fires the instant a cast is registered, with the
-- caster GUID and spell name. We use it to timestamp our own totem drops from
-- the ACTUAL cast rather than guessing when Queue landed - so a totem the
-- player drops manually (or that Mana Tide bumps) also resets the right clock,
-- and the redrop timer reflects reality. Falls back cleanly to the Queue-time
-- stamp if the event never arrives.
function M:OnCastEvent(caster, target, spellName)
    if not spellName then return end
    local _, myGuid = UnitExists("player")
    if myGuid and caster ~= myGuid then return end
    local slot = self:TotemElementMap()[spellName]
    if slot then
        self.totemT[slot] = GetTime()
        self.totemCastT[spellName] = GetTime()
    end
end

-- ============================================================
-- ClassicAPI totem tracking
-- ============================================================
-- Aegis's own element keys against ClassicAPI's numeric slots
-- (1 Fire, 2 Earth, 3 Water, 4 Air).
local CAPI_SLOT = { fire = 1, earth = 2, water = 3, air = 4 }

-- What is ACTUALLY standing in an element slot, and for how long.
-- Returns name, secondsRemaining - or nil when ClassicAPI is absent or the slot
-- is empty. nil is "no answer", never "empty" - callers must fall through.
function M:CapiTotem(key)
    local slot = CAPI_SLOT[key]
    if not slot then return nil end
    if not Aegis_SBR.TotemSlot then return nil end
    return Aegis_SBR:TotemSlot(slot)
end

-- PLAYER_TOTEM_UPDATE (ClassicAPI) fires on drop, expiry AND early destruction
-- - a totem killed by a mob or pulled back with Totemic Recall. Vanilla cannot
-- see that case at all, which is the whole reason the redrop clock existed.
--
-- On a slot going empty the clock is zeroed so the very next press redrops
-- instead of waiting out the remainder of an interval for a totem that is no
-- longer standing. The per-spell cast stamp is cleared too, or the aura-miss
-- learning below would count the destruction as evidence that the buff NAME is
-- wrong and eventually write off a perfectly good totem.
function M:OnTotemUpdate(slot)
    if not slot then return end
    local key
    for k, v in pairs(CAPI_SLOT) do
        if v == slot then key = k; break end
    end
    if not key then return end
    -- Routed through CapiTotem so the capability guard lives in exactly one
    -- place: the event can only fire with ClassicAPI loaded, but the capability
    -- FILE is optional in the load order, same as Preview and Pet.
    local name = self:CapiTotem(key)
    if not name then
        self.totemT[key] = 0
        -- Only this slot's spells: a destroyed fire totem says nothing about
        -- the water slot's bookkeeping.
        for spell, s in pairs(self:TotemElementMap()) do
            if s == key then
                self.totemCastT[spell] = nil
                self.totemBuffMiss[spell] = 0
            end
        end
    end
end

-- Distance from the player to the totem standing in this slot, in yards, or
-- nil when it cannot be measured (no SuperWoW, totem never seen, totem gone).
-- nil always means "cannot judge" and must never be read as "out of range".
function M:TotemDistance(slot)
    if not UnitPosition then return nil end
    local guid = self.totemGuid[slot]
    if not guid or not UnitExists(guid) then return nil end
    local x1, y1, z1 = UnitPosition("player")
    local x2, y2, z2 = UnitPosition(guid)
    if not (x1 and x2) then return nil end
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- How far this totem actually reaches. A Magma covers a fraction of what an
-- aura totem does, so a single number for all four would be wrong for half of
-- them - and wrong in the expensive direction, calling a totem useful while it
-- hits nothing.
function M:TotemRadius(slot)
    local spell = self.totemSpell[slot]
    local r = spell and Aegis_SBR:SpellRadius(spell)
    if not r or r <= 0 then r = TOTEM_RANGE end
    return r * TOTEM_RANGE_SLACK
end

function M:TotemOutOfRange(slot)
    local d = self:TotemDistance(slot)
    if not d then return false end
    return d >= self:TotemRadius(slot)
end

-- Is anyone else in the group still standing in this totem's radius? A shaman
-- who has walked off is not reason enough to pull a totem the party is still
-- using - Mana Spring and Healing Stream serve the group, not the caster.
function M:GroupNearTotem(guid, radius)
    if not UnitPosition then return false end
    local x2, y2, z2 = UnitPosition(guid)
    if not x2 then return false end
    local prefix, count = "raid", GetNumRaidMembers()
    if count == 0 then prefix, count = "party", GetNumPartyMembers() end
    for i = 1, count do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") and not UnitIsDeadOrGhost(u) then
            local x1, y1, z1 = UnitPosition(u)
            if x1 then
                local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
                if math.sqrt(dx * dx + dy * dy + dz * dz) < (radius or TOTEM_RANGE) then return true end
            end
        end
    end
    return false
end

-- Totemic Recall: pull every totem back and get a quarter of their mana back.
--
-- Only when EVERY standing totem is out of reach, because the spell recalls all
-- of them at once - with three good totems and one stranded, recalling would
-- throw the three away for a sliver of mana. And only when no group member is
-- still inside one of them.
--
-- The gain is smaller than the 25% suggests: the totems are re-placed at full
-- cost afterwards, so it saves a quarter of one placement. What makes it worth
-- having is the side effect - the slots read as empty immediately and get
-- re-dropped where the shaman actually is, instead of waiting out the timer.
-- Split from the cast so the core can be told "this module has something to do
-- even with no target selected" without a preview or a check firing the spell.
function M:RecallDue(cfg)
    if not cfg.totemRecall then return false end
    if not UnitPosition then return false end
    if not self:KnowsSpell(RECALL_SPELL) then return false end
    if not self:OwnCDReady(RECALL_SPELL) then return false end

    local standing, stranded = 0, 0
    for i = 1, table.getn(TOTEM_SLOTS) do
        local slot = TOTEM_SLOTS[i]
        local guid = self.totemGuid[slot]
        local live = (guid and UnitExists(guid)) and true or false
        -- ClassicAPI reads the element slot from the client's own totem tracker,
        -- which does NOT need the totem's object to be loaded. That fixes the
        -- exact case this feature exists for: walk far enough away and the client
        -- drops the distant object, so UnitExists(guid) goes false, the totem
        -- stops counting as standing, and the recall can never fire. Reported
        -- from play as "recall only works with a mob targeted" - with a target
        -- you are usually still close enough for the object to be loaded.
        local capiName = self:CapiTotem(slot)

        if live or capiName then
            standing = standing + 1
            if live then
                -- Object loaded: measure properly, and leave it alone if a group
                -- member is still standing in its radius.
                if self:TotemOutOfRange(slot) and not self:GroupNearTotem(guid, self:TotemRadius(slot)) then
                    stranded = stranded + 1
                end
            else
                -- The slot says a totem stands but the client has no object for
                -- it. A totem cannot move, so losing its object IS the distance
                -- evidence. The group check is skipped here because it needs a
                -- position - accepted, because a totem too far for the shaman's
                -- own client to keep loaded is not one the party is still using.
                stranded = stranded + 1
            end
        end
    end
    return standing > 0 and stranded == standing
end

function M:RecallTotems(cfg)
    if not self:RecallDue(cfg) then return false end
    -- Treated as an off-GCD extra like the totems themselves. If it turns out
    -- to cost a global cooldown after all, this spends one - rarely, and only
    -- while walking away from a fight.
    return self:PickExtra(RECALL_SPELL)
end

-- The aura a totem grants, as the CLIENT names it - returned as two candidates
-- because our table is a guess and the two forms differ per totem for no
-- discernible reason (Windfury Totem keeps the word, Stoneskin drops it).
-- Checking the mapped name AND the totem's own spell name removes the guess
-- from every case where the answer is one of the two.
--
-- Returns nil when the aura cannot be used at all:
--   * no SpellInfo - buff names are resolved through it, so without SuperWoW
--     every aura reads as missing and the check would re-drop forever
--   * the name was written off after repeatedly producing no aura
-- In both cases the caller falls back to the blind timer.
function M:TotemBuffNames(spell)
    if not SpellInfo then return nil end
    if self.totemBuffBad[spell] then return nil end
    local mapped = self.TOTEM_BUFF[spell]
    if not mapped then return nil end
    return mapped, spell
end

-- One drop attempt, throttled per element slot.
--
-- The stamp that governs the redrop interval comes from the cast EVENT when
-- SuperWoW is present, never from the attempt: Queue reports success for a cast
-- that never went out (no mana, for instance), and stamping that made the
-- rotation believe a totem was standing for the whole interval - up to 110
-- seconds of nothing, which is exactly the "earth totem is not re-placed"
-- report. Without the event there is no better signal and the attempt has to
-- stand in, which is the old behaviour on a client that cannot do better.
function M:TryTotem(key, spell, now)
    if (now - (self.totemTryT[key] or 0)) < TOTEM_RETRY then return false end
    -- Most totems have no cooldown, but some do - Grounding and Fire Nova at 15s,
    -- Stoneclaw at 30s against a 15s duration, i.e. a guaranteed dead window every
    -- cycle. Without this gate the slot is retried every TOTEM_RETRY throughout
    -- that window: the casts fail harmlessly (off-GCD, error suppressed), but each
    -- one stamps totemTryT, so the FIRST genuinely castable attempt is delayed by
    -- up to another retry interval. Suppress-only - it can never add a cast.
    if not self:IsReady(spell) then return false end
    -- Cheapest way to avoid a failed cast is not to attempt one. The cost comes
    -- from the spellbook tooltip, and an unreadable cost counts as affordable,
    -- so this can never be the reason a totem stays down.
    if Aegis_SBR.CanAfford and not Aegis_SBR:CanAfford(spell) then return false end
    -- PickExtra, not Queue: with Nampower a totem costs no global cooldown, so
    -- it rides along in the same press as whatever the rotation is doing rather
    -- than spending a press of its own.
    if not self:PickExtra(spell) then return false end
    self:Later(function() self.totemTryT[key] = now end)
    if not SpellInfo then
        -- No cast event on this client, so the attempt has to stand in for both
        -- clocks. The per-spell one matters for the AoE fire pair, which judges
        -- Magma by when Magma itself was last placed - without this it would
        -- read "never placed" forever and re-drop on every retry.
        self:Later(function()
            self.totemT[key] = now
            self.totemCastT[spell] = now
        end)
    end
    return true
end

-- Decides whether a totem needs (re)dropping. Two very different questions
-- depending on the totem, which is why the aura is checked first:
--   * Aura totems: the buff answers expiry, destruction, Totemic Recall and
--     walking out of range in one read. A clock answers none of those.
--   * Damage/utility totems (Searing, Magma, Fire Nova, Grounding) grant no
--     aura at all, so the per-totem interval is the only signal available -
--     and it must be per totem, since the fire slot alone spans 20s (Magma)
--     to 120s (Flametongue).
function M:MaintainTotem(key, spell, interval)
    if spell == "" or not self:KnowsSpell(spell) then return false end
    local now = GetTime()

    -- Walked out of its radius: the totem is standing but doing nothing for us,
    -- so it counts as missing regardless of aura or clock. This is the only
    -- check that covers the totems granting no aura at all, which are exactly
    -- the ones the blind timer serves worst.
    if cfgTotemRange and self:TotemOutOfRange(key) then
        return self:TryTotem(key, spell, now)
    end

    -- ClassicAPI reads the element slot directly, which is the ground truth the
    -- rest of this function had to infer. It supersedes BOTH branches below:
    --   * the aura path, including its buff-name guessing and the miss-counting
    --     that exists only to survive a wrong name - there is no name involved
    --     here, so nothing to get wrong;
    --   * the blind redrop clock, which is the one that serves no-aura totems
    --     (Searing, Magma, Grounding, Fire Nova) worst.
    -- It also covers early destruction: a killed totem leaves the slot empty and
    -- is redropped on the next press instead of after the remainder of a clock.
    --
    -- Deliberately AFTER the range check: a totem standing at full duration but
    -- out of its radius still counts as missing, and the slot cannot know that.
    local capiName, capiRemain = self:CapiTotem(key)
    if capiName then
        if capiName == spell then
            -- Ours, standing, and the slot says how long it has left.
            -- TOTEM_APPLY_GRACE is not needed here: the slot is stamped from the
            -- cast packet, so there is no registration lag to wait out.
            if not capiRemain or capiRemain > 0 then return false end
        end
        -- A DIFFERENT totem occupies the slot (dropped by hand, or a Mana Tide
        -- bumping Healing Stream). The configured one is not up, so redrop it -
        -- the same conclusion the aura path reaches, reached without guessing.
        return self:TryTotem(key, spell, now)
    elseif Aegis_SBR.Capability and Aegis_SBR:Capability("totems") then
        -- Slot is genuinely empty and we can see that authoritatively.
        return self:TryTotem(key, spell, now)
    end

    local mapped, own = self:TotemBuffNames(spell)

    if mapped then
        if self:HasBuff(mapped) or self:HasBuff(own) then
            self:Later(function() self.totemBuffMiss[spell] = 0 end)
            return false
        end
        -- Everything below is judged against the CONFIRMED cast of THIS totem,
        -- not against the element slot's clock. The slot is stamped by any
        -- totem of that element, so dropping a Tremor Totem by hand made the
        -- slot look freshly cast - and that used to write off the Stoneskin
        -- name over an aura that was missing only because a different totem
        -- was standing in its place.
        local done = self.totemCastT[spell] or 0
        if done > 0 and (now - done) < TOTEM_APPLY_GRACE then
            return false                        -- just placed, let it register
        end
        -- A cast that produced no aura is counted ONCE per cast, and it takes
        -- TOTEM_MISS_MAX of them to write the name off. A single miss is not
        -- evidence: the shaman may simply have walked out of the totem's range
        -- right after dropping it, which is the very thing this check exists to
        -- notice. Two casts in a row with no aura is a name problem.
        if done > 0 and self.totemMissAt[spell] ~= done then
            local miss = (self.totemBuffMiss[spell] or 0) + 1
            self:Later(function()
                self.totemMissAt[spell] = done
                self.totemBuffMiss[spell] = miss
            end)
            if miss >= TOTEM_MISS_MAX then
                self:Later(function() self.totemBuffBad[spell] = true end)
                return false                    -- timer takes over next press
            end
        end
        return self:TryTotem(key, spell, now)
    end

    if not interval then interval = TOTEM_REDROP[spell] or TOTEM_REDROP_DEFAULT end
    -- The table holds MAX-RANK durations, but a totem's duration is rank
    -- dependent: rank 1 Searing lasts 30s where the table says 55, so a levelling
    -- shaman's fire slot sat empty for 25 seconds. The tooltip knows the real
    -- number for the rank actually known (see Aegis_SBR:SpellDuration).
    --
    -- Taken as a CEILING, never a replacement: min() means a tooltip read can
    -- only ever make the redrop EARLIER, never later. A misparse that returned
    -- something large therefore cannot regress today's behaviour, and the table
    -- stays the guarantee.
    if Aegis_SBR.SpellDuration then
        local real = Aegis_SBR:SpellDuration(spell)
        if real then
            local early = real - TOTEM_REDROP_EARLY
            if early < 5 then early = 5 end
            if early < interval then interval = early end
        end
    end
    if (now - (self.totemT[key] or 0)) < interval then return false end
    return self:TryTotem(key, spell, now)
end

-- Unified totem upkeep for every spec: drops the configured totem in each of
-- the four element slots during a lull, one per press. Damage specs default
-- their fire slot to Searing (see templates), so this fully replaces the old
-- standalone Searing upkeep with no loss - and adds water/earth/air on top.
-- AoE fire slot: Fire Nova on cooldown, Magma to cover the gaps.
--
-- These two cannot both live in the fire dropdown, because the point is to
-- ALTERNATE them, not to choose one. Fire Nova is not upkeep at all - it
-- detonates after ~5s and then sits on a cooldown - so it behaves like a
-- cooldown ability, while Magma is the sustained tick that fills the wait.
-- They share the one fire totem slot in game, so dropping either replaces the
-- other; that is exactly why Magma must not be re-dropped while Fire Nova is
-- still standing, and why the Magma timer is reset when Fire Nova goes down.
--
-- Requested for lasher farming, where the pull is a cluster of low-health mobs
-- and the fire slot is the whole damage plan.
function M:MaintainFireTotems(cfg)
    if not cfg.aoeFireTotems then return false end
    local nova, magma = "Fire Nova Totem", "Magma Totem"
    local haveNova, haveMagma = self:KnowsSpell(nova), self:KnowsSpell(magma)
    if not haveNova and not haveMagma then return false end

    if haveNova and self:OwnCDReady(nova) then
        if self:PickExtra(nova) then
            -- Same rule as TryTotem: with the cast event the stamp comes from
            -- the cast that actually happened, not from the attempt.
            self:Later(function()
                if not SpellInfo then self.totemT["fire"] = GetTime() end
                self.totemTryT["fire"] = GetTime()
            end)
            -- Nova occupies the slot only briefly; letting Magma follow as soon
            -- as it has detonated is the point of the pairing.
            self:Later(function() self.novaUntil = GetTime() + NOVA_STAND end)
            return true
        end
    end
    -- Magma fills the gap, but it may NOT be judged by the element slot's clock
    -- the way a normal totem is. That clock is stamped by any fire totem, Fire
    -- Nova included, so with Nova's ~15s cooldown against Magma's 18s interval
    -- the window never opened once - reported from play as "Magma Totem does
    -- not get placed at all".
    --
    -- The right clock is Magma's OWN last cast, plus one extra rule: a Nova
    -- since then has replaced it, so it is due again the moment that Nova has
    -- detonated. Both timestamps are already kept per spell by OnCastEvent.
    if haveMagma and GetTime() >= (self.novaUntil or 0) then
        local now = GetTime()
        local lastMagma = self.totemCastT[magma] or 0
        local lastNova  = self.totemCastT[nova] or 0
        local due = (lastMagma == 0)                                    -- never placed
            or (lastNova > lastMagma)                                   -- a Nova replaced it
            or ((now - lastMagma) >= (TOTEM_REDROP[magma] or TOTEM_REDROP_DEFAULT))
        if due and self:TryTotem("fire", magma, now) then return true end
    end
    return false
end

-- Totem upkeep, as off-GCD EXTRAS.
--
-- With Nampower a totem is instant and costs no global cooldown, so upkeep does
-- not compete with the rotation at all - which is why these used to sit near
-- the bottom of every priority list and why that position no longer matters.
-- The callers therefore do NOT return on a hit.
--
-- All four go out in a single press when Nampower is present; see the queue
-- test inside for why that condition and not a blanket one-per-press rule.
function M:MaintainAllTotems(cfg)
    if cfg.useTotems == false then return false end
    -- MaintainTotem is called from several places without cfg, so the toggle is
    -- handed over here rather than threaded through every signature.
    cfgTotemRange = cfg.totemRange and true or false
    if self:RecallTotems(cfg) then return true end

    -- All four in one press when the client can take it, one otherwise. The
    -- condition is the presence of the Nampower queue API, and it is the right
    -- test: without it a second CastSpellByName in the same frame overrides the
    -- first instead of being queued behind it, so only one totem would land.
    --
    -- Nampower is a hard requirement for this addon, so the single-cast path is
    -- a safety net rather than a supported mode.
    local oneOnly = (QueueSpellByName == nil)
    local did = false

    if self:MaintainTotem("water", self.WATER_TOTEMS[cfg.totemWater or "none"] or "") then
        did = true
        if oneOnly then return true end
    end
    if self:MaintainTotem("earth", self.EARTH_TOTEMS[cfg.totemEarth or "none"] or "") then
        did = true
        if oneOnly then return true end
    end
    -- The AoE pair owns the fire slot when enabled, so the single-totem picker
    -- is skipped rather than fighting it for the same slot.
    if cfg.aoeFireTotems then
        if self:MaintainFireTotems(cfg) then
            did = true
            if oneOnly then return true end
        end
    elseif self:MaintainTotem("fire", self.FIRE_TOTEMS[cfg.totemFire or "none"] or "") then
        did = true
        if oneOnly then return true end
    end
    if self:MaintainTotem("air", self.AIR_TOTEMS[cfg.totemAir or "none"] or "") then
        did = true
    end
    return did
end

-- Heal decision. Casts one spell per press via early return.
-- Order: Mana Tide (mana) -> NS->instant HW (emergency) -> Lesser Healing Wave
-- (single-target emergency, wins over AoE) -> Chain Heal (AoE) -> downranked
-- Healing Wave (fill) -> Water Shield upkeep -> totem upkeep (during downtime).
function M:RotateRestoration(cfg)
    -- Above the GCD guard on purpose: totems cost no global cooldown, so a
    -- resto shaman can keep them up straight through a heal cast. Everything
    -- below this line is a real cast and has to wait for the GCD.
    self:MaintainAllTotems(cfg)

    if not self:GcdReady() then return end

    local ratio = (cfg.healThreshold or 90) / 100
    local unit, deficit, pct = self:WorstHurt(ratio, cfg)

    -- Curing, above the heal but only while nobody is hurt past the crossover.
    if self:CureStep(cfg, pct) then return end

    -- Mana Tide Totem when low on mana (the mana cooldown).
    if cfg.useManaTide ~= false and self:KnowsSpell(MANATIDE_SPELL)
        and self:OwnCDReady(MANATIDE_SPELL) and self:ManaPct() <= (cfg.manaTideAt or 25) then
        if self:Queue(MANATIDE_SPELL, "mana low") then return end
    end

    if unit then
        local mana = UnitMana("player")
        local hpb  = cfg.healPower or 0
        local mods = self:HealMods()
        local hwEff  = self:EffHeals(self.HW_HEAL, 0.85, mods, hpb)
        local lhwEff = self:EffHeals(self.LHW_HEAL, 0.43, mods, hpb)
        local chEff  = self:EffHeals(self.CH_HEAL, 0.5, mods, hpb)

        -- Emergency: NS-equivalent -> instant max Healing Wave. If it is already
        -- up, fire the big heal now; otherwise pop it when a target is in trouble.
        if self:NSUp() then
            local maxr = self:MaxRank("Healing Wave")
            if maxr >= 1 then
                self:CommitHeal(unit, hwEff[maxr] or deficit, 0)
                self:CastOn("Healing Wave(Rank " .. maxr .. ")", unit); return
            end
        end
        if cfg.useNSCombo ~= false and pct <= (cfg.nsHpPct or 40) / 100 then
            local ns = self:NSSpell()
            if ns and self:OwnCDReady(ns) then
                if self:Pick(ns, "emergency heal") then return end
            end
        end

        -- Single-target emergency: fast Lesser Healing Wave (wins over AoE).
        if cfg.useLesserHW ~= false and self:KnowsSpell("Lesser Healing Wave")
            and pct <= (cfg.lhwPct or 50) / 100 then
            local lhw, amt = self:PickRank("Lesser Healing Wave", lhwEff, self.LHW_MANA, deficit, mana)
            if lhw then self:CommitHeal(unit, amt, 1.5); self:CastOn(lhw, unit); return end
        end

        -- AoE: Chain Heal when several are hurt.
        if cfg.useChainHeal ~= false and self:KnowsSpell("Chain Heal")
            and self:HurtCount(ratio) >= (cfg.chainHealCount or 3) then
            local ch, amt = self:PickRank("Chain Heal", chEff, self.CH_MANA, deficit, mana)
            if ch then self:CommitHeal(unit, amt, 2.5); self:CastOn(ch, unit); return end
        end

        -- Bread-and-butter: downranked Healing Wave sized to the deficit.
        local hw, amt = self:PickRank("Healing Wave", hwEff, self.HW_MANA, deficit, mana)
        if hw then self:CommitHeal(unit, amt, 3.0); self:CastOn(hw, unit); return end
    end

    -- Nothing urgent: keep the shield and totems up during the lull.
    if self:MaintainShield(cfg) then return end
    -- Weapon imbue upkeep: below every heal and totem, above the optional
    -- damage weave. Restoration reaches this only when nothing needs healing,
    -- so an imbue can never take the global cooldown away from a heal - but a
    -- bare weapon is worth fixing before spending that spare cast on a filler
    -- nuke, since it improves every later swing. Turtle's
    -- resto shaman does melee (and Rockbiter's threat matters when holding
    -- aggro), which is why this spec gets it at all; the shared MaintainImbue
    -- still applies its own rules, so in combat it only warns unless
    -- imbueInCombat is opted in.
    if self:MaintainImbue(cfg) then return end

    -- Downtime filler: optionally weave damage. Only with an enemy targeted and
    -- mana above the floor, so it never starves heals.
    if cfg.weaveDamage and self:ManaPct() >= (cfg.weaveManaFloor or 40)
        and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target") then
        if self:KnowsSpell("Lightning Bolt") then self:Queue("Lightning Bolt", "filler"); return end
    end
end

-- ============================================================
-- Rotation entry: dispatch by mode.
-- ============================================================
function M:Rotate(cfg)
    if cfg.mode == "restoration" then self:RotateRestoration(cfg); return end

    -- Non-heal specs: with no attackable target the only thing to do is pre-pull
    -- weapon-imbue upkeep (a self-buff). RunsWithoutTarget only lets the core
    -- reach here targetless when that upkeep is actually due, so the melee/caster
    -- rotations below never run without an enemy.
    local hasEnemy = UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
    if not hasEnemy then
        -- Off the global cooldown and unrelated to any target, so it belongs
        -- here as much as in combat.
        self:RecallTotems(cfg)
        self:MaintainImbue(cfg)
        return
    end

    if cfg.mode == "elemental" then
        self:RotateElemental(cfg)
    elseif cfg.mode == "tank" then
        self:RotateTank(cfg)
    else
        self:RotateEnhancement(cfg)
    end
end

-- Shared shield upkeep. Returns true if a cast was issued.
function M:MaintainShield(cfg)
    local shield = self:ShieldSpell(cfg)
    if shield == "" or not self:KnowsSpell(shield) then return false end
    -- The shield buff carries the spell's name, so HasBuff(name) detects it.
    if self:HasBuff(shield) then return false end
    if self:Queue(shield, "shield missing") then return true end
    return false
end

-- ------------------------------------------------------------
-- Enhancement (melee). Also the level 1 default.
-- ------------------------------------------------------------
function M:RotateEnhancement(cfg)
    self:EnsureMeleeSwing()
    local shock = self:ShockSpell(cfg)
    local cc = self:HasClearcast() and self:ClearcastUp()

    if self:Tracing() then
        self:Trace("enh shock=" .. (shock ~= "" and shock or "-")
            .. " ss=" .. (cfg.useStormstrike and (self:KnowsSpell("Stormstrike") and "Y" or "n") or "-")
            .. " ls=" .. (cfg.useLightningStrike and (self:KnowsSpell("Lightning Strike") and "Y" or "n") or "-")
            .. " cc=" .. (cc and "Y" or "n")
            .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    -- Totem upkeep runs FIRST, because it is off the global cooldown: it rides
    -- along with whatever this press does rather than competing with it. It has
    -- to sit above the early returns below - down at the bottom it would only
    -- ever be reached on a press where nothing else fired, which is the very
    -- problem being fixed.
    self:MaintainAllTotems(cfg)

    -- P1 shield upkeep
    if self:MaintainShield(cfg) then return end

    -- P2 weapon imbue, ahead of every damage ability - see MaintainImbue.
    -- A missing Windfury costs more damage than the global cooldown it takes
    -- to put back, and from last place it only ever got a press when the whole
    -- rotation happened to be on cooldown at once.
    if self:MaintainImbue(cfg) then return end

    -- P3 Bloodlust (self burst), only when enabled and off cooldown, in combat
    if cfg.useBloodlust and self:KnowsSpell("Bloodlust") and UnitAffectingCombat("player")
        and self:IsReady("Bloodlust") and not self:HasBuff("Bloodlust") then
        if self:Queue("Bloodlust", "burst") then return end
    end

    -- P4 Stormstrike: applies the +20% Nature self-buff for the next shocks
    if cfg.useStormstrike and self:KnowsSpell("Stormstrike") and self:IsReady("Stormstrike")
        and self:InSpellRange("Stormstrike") then
        if self:Queue("Stormstrike", "on cooldown") then return end
    end

    -- P5 Lightning Strike: melee instant that also empowers the active shield
    if cfg.useLightningStrike and self:KnowsSpell("Lightning Strike") and self:IsReady("Lightning Strike")
        and self:InSpellRange("Lightning Strike") then
        if self:Queue("Lightning Strike", "on cooldown") then return end
    end

    -- P6 shock on its (shared) cooldown, consuming the Stormstrike buff
    if shock ~= "" and self:KnowsSpell(shock) and self:IsReady(shock)
        and self:InSpellRange(shock) then
        if shock == "Flame Shock" then
            if self:MaintainFlameShock() then return end
        else
            if self:Queue(shock, "on cooldown") then return end
        end
    end

    -- P8 Lightning Bolt filler / weave. Also the level 1 damage source.
    if cfg.lbFiller and self:KnowsSpell("Lightning Bolt") then
        self:Queue("Lightning Bolt", "filler")
    end
end

-- ------------------------------------------------------------
-- Elemental (caster). No melee swing.
-- ------------------------------------------------------------
function M:RotateElemental(cfg)
    local cc = self:HasClearcast() and self:ClearcastUp()

    if self:Tracing() then
        self:Trace("ele shock=" .. (self:ShockSpell(cfg) ~= "" and self:ShockSpell(cfg) or "-")
            .. " cc=" .. (cc and "Y" or "n")
            .. " EM=" .. (cfg.useElementalMastery and (self:KnowsSpell("Elemental Mastery") and "Y" or "n") or "-")
            .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    -- Totem upkeep runs FIRST, because it is off the global cooldown: it rides
    -- along with whatever this press does rather than competing with it. It has
    -- to sit above the early returns below - down at the bottom it would only
    -- ever be reached on a press where nothing else fired, which is the very
    -- problem being fixed.
    self:MaintainAllTotems(cfg)

    -- P1 shield upkeep (Water Shield for mana by default)
    if self:MaintainShield(cfg) then return end

    -- P2 weapon imbue, ahead of the nukes - see MaintainImbue. Deliberately
    -- ABOVE Elemental Mastery rather than below it: that cooldown is meant to
    -- sit immediately in front of a damage spell, and nothing should be able
    -- to slip between the two.
    if self:MaintainImbue(cfg) then return end

    -- P3 Elemental Mastery before a nuke (instant, guarantees a crit -> feeds
    -- Clearcasting and Electrify), when enabled and off cooldown.
    if cfg.useElementalMastery and self:KnowsSpell("Elemental Mastery")
        and self:IsReady("Elemental Mastery") and not self:HasBuff("Elemental Mastery") then
        if self:Queue("Elemental Mastery", "before a nuke") then return end
    end

    -- P4 Flame Shock DoT upkeep (when chosen as the shock)
    if cfg.shock == "flame" then
        if self:MaintainFlameShock() then return end
    elseif self:ShockSpell(cfg) ~= "" then
        -- a non-Flame shock chosen: cast it on its cooldown as a nuke
        local shock = self:ShockSpell(cfg)
        if self:KnowsSpell(shock) and self:IsReady(shock) and self:InSpellRange(shock) then
            if self:Queue(shock, "on cooldown") then return end
        end
    end

    -- P6 Lightning Bolt filler, the main nuke (builds Electrify). Always the
    -- level 1 fallback.
    if self:KnowsSpell("Lightning Bolt") then
        self:Queue("Lightning Bolt", "filler")
    end
end

-- ------------------------------------------------------------
-- Tank. Earth Shock threat, Stormstrike for the Nature buff, Lightning Strike,
-- optional Earthshaker Slam taunt.
-- ------------------------------------------------------------
function M:RotateTank(cfg)
    self:EnsureMeleeSwing()
    local shock = self:ShockSpell(cfg)

    if self:Tracing() then
        self:Trace("tank shock=" .. (shock ~= "" and shock or "-")
            .. " ss=" .. (cfg.useStormstrike and (self:KnowsSpell("Stormstrike") and "Y" or "n") or "-")
            .. " ls=" .. (cfg.useLightningStrike and (self:KnowsSpell("Lightning Strike") and "Y" or "n") or "-")
            .. " taunt=" .. (cfg.useTaunt and (self:KnowsSpell("Earthshaker Slam") and "Y" or "n") or "-"))
    end

    -- Totem upkeep runs FIRST, because it is off the global cooldown: it rides
    -- along with whatever this press does rather than competing with it. It has
    -- to sit above the early returns below - down at the bottom it would only
    -- ever be reached on a press where nothing else fired, which is the very
    -- problem being fixed.
    self:MaintainAllTotems(cfg)

    -- P1 shield upkeep (Lightning Shield for threat)
    if self:MaintainShield(cfg) then return end

    -- P2 Earthshaker Slam taunt, only when the target is not already on you
    -- (the ability has no effect otherwise). Same idea as the druid Growl pull.
    --
    -- The range gate is what makes the imbue below reachable at all. A shaman
    -- tank pulls at range and then closes, and during that run the target is
    -- not on him yet - so the taunt condition was satisfied, the cast failed
    -- silently out of range, and the press returned having done nothing. The
    -- whole approach produced no imbue, no totems and no shield upkeep.
    if cfg.useTaunt and self:KnowsSpell("Earthshaker Slam") and self:IsReady("Earthshaker Slam")
        and self:InSpellRange("Earthshaker Slam") then
        if not (UnitExists("targettarget") and UnitIsUnit("targettarget", "player")) then
            if self:Queue("Earthshaker Slam", "taunt") then return end
        end
    end

    -- P3 weapon imbue, ahead of every damage ability - see MaintainImbue for
    -- why. Self-gated there: in combat it acts only with the imbueInCombat
    -- opt-in, otherwise it warns.
    if self:MaintainImbue(cfg) then return end

    -- P4 Stormstrike for the Nature buff that boosts shock threat
    if cfg.useStormstrike and self:KnowsSpell("Stormstrike") and self:IsReady("Stormstrike")
        and self:InSpellRange("Stormstrike") then
        if self:Queue("Stormstrike", "on cooldown") then return end
    end

    -- P5 Earth Shock (or chosen shock) on cooldown, the primary threat tool
    if shock ~= "" and self:KnowsSpell(shock) and self:IsReady(shock)
        and self:InSpellRange(shock) then
        if shock == "Flame Shock" then
            if self:MaintainFlameShock() then return end
        else
            if self:Queue(shock, "on cooldown") then return end
        end
    end

    -- P6 Lightning Strike (threat + empowered shield)
    if cfg.useLightningStrike and self:KnowsSpell("Lightning Strike") and self:IsReady("Lightning Strike")
        and self:InSpellRange("Lightning Strike") then
        if self:Queue("Lightning Strike", "on cooldown") then return end
    end

    -- P8 optional Lightning Bolt filler (off by default for tanks)
    if cfg.lbFiller and self:KnowsSpell("Lightning Bolt") then
        self:Queue("Lightning Bolt", "filler")
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "mode" then
        local cfg = Aegis_SBR:GetActiveProfile()
        local mode = self.modeAlias[string.lower(t[2] or "")]
        if cfg and mode then
            cfg.mode = mode
            msgOut("mode = " .. mode .. ".")
        else
            msgOut("usage: /sbr mode <enhancement|elemental|tank|resto>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "shock" then
        local cfg = Aegis_SBR:GetActiveProfile()
        local shock = self.shockAlias[string.lower(t[2] or "")]
        if cfg and shock then
            cfg.shock = shock
            msgOut("shock = " .. (shock == "none" and "(none)" or self.SHOCKS[shock]) .. ".")
        else
            msgOut("usage: /sbr shock <earth|frost|flame|none>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "weave" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return true end
        local a = string.lower(t[2] or "")
        if a == "on" then cfg.weaveDamage = true
        elseif a == "off" then cfg.weaveDamage = false
        else cfg.weaveDamage = not cfg.weaveDamage end
        msgOut("resto damage weave " .. (cfg.weaveDamage and "on" or "off") .. " (DPS only when nobody needs healing).")
        return true
    end
    if cmd == "shield" then
        local cfg = Aegis_SBR:GetActiveProfile()
        local shield = self.shieldAlias[string.lower(t[2] or "")]
        if cfg and shield then
            cfg.shield = shield
            msgOut("shield = " .. (shield == "none" and "(none)" or self.SHIELDS[shield]) .. ".")
        else
            msgOut("usage: /sbr shield <lightning|water|earth|none>", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end

-- ============================================================
-- Talent cache invalidation. Cleared at login and whenever talent points
-- change, so TalentRank() (Clearcasting detection) re-reads fresh data.
-- ============================================================
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_LOGIN")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
talentFrame:SetScript("OnEvent", function()
    M.talentCache = nil
end)

-- ============================================================
-- Totem units. SuperWoW reports a freshly placed totem through
-- UNIT_MODEL_CHANGED with a GUID in arg1; "<guid>owner" resolves to whoever
-- summoned it, which is what separates our own totems from every other one in
-- the raid. The unit name carries the totem's spell name, so it maps straight
-- onto the element slot. Those two facts are what make a distance to a totem
-- measurable at all.
--
-- Registered only when UnitPosition exists: without SuperWoW the GUID would be
-- useless anyway, and every distance check degrades to "cannot judge".
-- ============================================================
local totemWatch = CreateFrame("Frame")
if UnitPosition then totemWatch:RegisterEvent("UNIT_MODEL_CHANGED") end
totemWatch:SetScript("OnEvent", function()
    if not arg1 then return end
    if not UnitIsUnit(arg1 .. "owner", "player") then return end
    local _, _, name = string.find(UnitName(arg1) or "", "^(.- Totem)")
    if not name then return end
    local slot = M:TotemElementMap()[name]
    if slot then
        M.totemGuid[slot] = arg1
        M.totemSpell[slot] = name
    end
end)
