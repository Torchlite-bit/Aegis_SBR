-- ============================================================
-- Class_Paladin  -  paladin module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Roleless seal model.
-- ============================================================
-- Model:
--  * One debuff seal slot (optional) and one damage seal slot (optional).
--  * A debuff seal is judged only while its debuff is missing on the target.
--    Once applied it is kept as a buff (refreshed by autoattacks of any
--    paladin) and not judged again. If a damage seal is also set, the
--    rotation switches to it as soon as the debuff is up and judges it
--    continuously for damage (damage seals carry no debuff to overwrite).
--  * Mana management (Seal of Wisdom) and HP management (Seal of Light)
--    are optional overrides with their own hysteresis.
--  * Strikes are driven by the Holy Strike / Crusader Strike checkboxes.
-- ============================================================

local M = Aegis_SBR:NewClassModule("PALADIN")
M.uiTitle = "Paladin"
-- Rotate runs under Aegis_SBR:Preview without casting (see Pick/Later).
M.previewReady = true
M.uiHeight = 820

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- Tunable buff renew thresholds for the strike buffs
local HM_RENEW    = 7
local ZEAL_RENEW  = 12
local ZEAL_STACKS = 3

-- How long you must have been standing still before Consecration is allowed.
--
-- Not zero, and that is the correction. "Not moving right now" is true for the
-- fraction of a second between two steps of repositioning, so a check without a
-- dwell drops the patch into exactly the gap the switch exists to avoid.
--
-- Two seconds against an eight second patch: long enough that a step is not
-- mistaken for a stand, short enough that a real fight never waits for it -
-- you are stationary the moment melee starts.
local CONSEC_DWELL = 2

-- Fallback radius for the enemy count, used only if the tooltip cannot be read.
local CONSEC_RADIUS = 8

-- Enough enemies standing in it? nil from the counter means the count could not
-- be taken - no nameplates drawn, no SuperWoW - and that must read as YES, never
-- as zero. A capability that cannot answer is not allowed to switch an ability
-- off silently; that is the same rule the range and movement checks follow, and
-- the one defect this file has hit most often.
function M:ConsecrationCrowded(cfg)
    local want = cfg.consecMinTargets or 0
    if want <= 0 then return true end
    local n = Aegis_SBR:CountEnemiesNear(self:SpellRadius("Consecration") or CONSEC_RADIUS)
    if n == nil then return true end
    return n >= want
end

-- Absolute-mana downrank thresholds (Turtle WoW), mirroring the proven
-- ExAutoCSHS tables. Cast the lowest-numbered rank whose ceiling the current
-- raw mana is under; at or above the last ceiling, use full rank. These are
-- flat mana costs, so they self-adjust by level: a small pool naturally lands
-- on cheaper ranks, while a large pool stays at full rank until nearly empty.
local DOWNRANK = {
    ["Crusader Strike"] = { 40, 130, 170, 200 },            -- R1..R4 ceilings, else max
    ["Holy Strike"]     = { 12, 25, 38, 51, 64, 75, 90 },   -- R1..R7 ceilings, else max
}

-- Talents that change what the strikes do (Turtle WoW). Exact talent names as
-- they appear in GetTalentInfo (verified via /sbr talents):
--  * "Vengeful Strikes" (Retribution) is what makes Holy Strike apply the Holy
--    Might Strength buff at all.
--  * "Righteous Strikes" (Protection) makes Holy Strike a high-threat tank tool.
-- TalentRank matches the name exactly, so the trailing "s" matters: a mismatch
-- silently reads rank 0 and the rotation would never maintain a buff the player
-- in fact has. We read their ranks so it never maintains one they cannot get.
local TALENT_HOLY_MIGHT = "Vengeful Strikes"
local TALENT_BLESSED = "Blessed Strikes"   -- Holy: Crusader Strike resets Holy Shock (100% at 5/5)
local TALENT_THREAT     = "Righteous Strikes"

-- Judgement debuff detection. The exact debuff name (resolved through
-- SuperWoW spell ids) is matched first; the icon fragment is the fallback for
-- clients without SuperWoW. A seal applies a judgement debuff of a different
-- name, so the seal -> judgement-name map is kept alongside the textures.
M.debuffName = {
    ["Seal of Wisdom"]       = "Judgement of Wisdom",
    ["Seal of the Crusader"] = "Judgement of the Crusader",
    ["Seal of Light"]        = "Judgement of Light",
    ["Seal of Justice"]      = "Judgement of Justice",
}
M.debuffTex = {
    ["Seal of Wisdom"]       = "RighteousnessAura",  -- Judgement of Wisdom
    ["Seal of the Crusader"] = "HolySmite",          -- Judgement of the Crusader
    ["Seal of Light"]        = "HealingAura",        -- Judgement of Light
    ["Seal of Justice"]      = "SealOfWrath",         -- Judgement of Justice
}

-- Seal universe split by category, used by the UI to offer only learned ones
M.DEBUFF_SEALS = { "Seal of the Crusader", "Seal of Justice", "Seal of Wisdom", "Seal of Light" }
M.DAMAGE_SEALS = { "Seal of Righteousness", "Seal of Command" }

-- ============================================================
-- Healing support (merged from the modified branch). Self-contained: the
-- ret/prot rotation below is untouched and only yields to these in heal mode.
-- Base heal values per rank (approximate; tunable for Turtle WoW). The rank
-- picker downranks against these plus the gear +healing bonus.
-- ============================================================
M.FOL_HEAL = { 67, 102, 153, 206, 278, 348, 428 }
M.FOL_MANA = { 35, 50, 70, 90, 115, 140, 180 }
M.HL_HEAL  = { 50, 83, 173, 333, 522, 739, 999, 1317, 1680 }
M.HL_MANA  = { 35, 60, 110, 190, 275, 365, 465, 580, 660 }
M.HS_HEAL  = { 315, 360, 500, 655 }
M.HS_MANA  = { 225, 335, 410, 485 }

-- +Healing penalty factor for spells learnt BEFORE level 20: such a rank only
-- receives (1 - (20 - levelLearnt) * 0.0375) of the gear bonus, while its base
-- heal is unaffected. This is what stops downranking from scaling for free with
-- +healing, and it only bites harder the better the gear gets - at +900 healing
-- an unpenalised Holy Light rank 1 looks like a ~690 heal when it actually lands
-- ~230, so the rank picker would happily choose it and badly underheal.
--
-- Cross-checked against an independent implementation of the same formula, and
-- against a different set of factors derived from the same rule for another
-- healing class, which confirms the reading.
-- Only Holy Light is affected: ranks 1/2/3 are learnt at level 1/6/14. Flash of
-- Light starts at level 20 and Holy Shock at 40, so both come out at a factor of
-- 1 and need no table.
M.HL_PEN = { 0.2875, 0.475, 0.775 }   -- ranks 1-3; nil (= 1) from rank 4 up

-- ============================================================
-- Heal ranks, per spell: rank, base heal, mana, +healing penalty factor.
--
-- The choice is made in two steps, which is the shape the established ladder
-- uses and NOT what stood here before:
--
--   1. Which spell. Holy Light only when the target is BELOW the healthy line
--      AND no Flash of Light is big enough to cover the need (or there is no
--      Flash of Light at all, or a proc makes Holy Light cheap in time).
--   2. Which rank, walking upward and keeping the last one whose heal is still
--      SMALLER than what is missing - so the cast lands just under the deficit
--      rather than just over it.
--
-- An earlier version of this file had step 1 inverted, reaching for Holy Light
-- on HEALTHY targets. That is backwards: the long cast is for somebody a fast
-- heal cannot save, not for somebody who is barely scratched.
-- ============================================================
M.HL_RANKS = {
    { rank = 1, base =   43, mana =  35, pf = 0.2875 },
    { rank = 2, base =   83, mana =  60, pf = 0.475 },
    { rank = 3, base =  173, mana = 110, pf = 0.775 },
    { rank = 4, base =  333, mana = 190 },
    { rank = 5, base =  522, mana = 275 },
    { rank = 6, base =  739, mana = 365 },
    { rank = 7, base =  999, mana = 465 },
    { rank = 8, base = 1317, mana = 580 },
    { rank = 9, base = 1680, mana = 660 },
}
M.FOL_RANKS = {
    { rank = 1, base =  67, mana =  35 },
    { rank = 2, base = 102, mana =  50 },
    { rank = 3, base = 153, mana =  70 },
    { rank = 4, base = 206, mana =  90 },
    { rank = 5, base = 278, mana = 115 },
    { rank = 6, base = 348, mana = 140 },
    { rank = 7, base = 428, mana = 180 },
}

-- Buff textures that make Holy Light instant or fast, and therefore free to use
-- however hurt the target is. Both are detected by TEXTURE rather than by name,
-- which is locale proof and does not depend on a spell id resolving.
--   Holy Judgement          - next Holy Light one second faster
--   Hand of Edward the Odd  - next spell instant
local FORCE_HL_TEX = { "ability_paladin_judgementblue", "Spell_Holy_SearingLight" }

-- Auto-read the gear +healing bonus by scanning equipped-item tooltips. Cached,
-- refreshed when equipment changes. A manual healPower above zero overrides it.
local healScanTip = CreateFrame("GameTooltip", "Aegis_SBR_HealScan", nil, "GameTooltipTemplate")
healScanTip:SetOwner(healScanTip, "ANCHOR_NONE")

M.cachedHealBonus = nil
local healBonusFrame = CreateFrame("Frame")
healBonusFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
healBonusFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
healBonusFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
healBonusFrame:SetScript("OnEvent", function() M.cachedHealBonus = nil end)

-- One tooltip line contributes its healing number (pure healing and spell
-- damage-and-healing, English and German), mirroring ItemBonusLib's patterns.
function M:ParseHealBonus(txt)
    local _, _, n
    _, _, n = string.find(txt, "[Hh]ealing done by spells and effects by up to (%d+)")
    if n then return tonumber(n) end
    _, _, n = string.find(txt, "damage and healing done by magical spells and effects by up to (%d+)")
    if n then return tonumber(n) end
    _, _, n = string.find(txt, "[Hh]ealing %+(%d+)")
    if n then return tonumber(n) end
    _, _, n = string.find(txt, "^%+(%d+) [Hh]ealing")
    if n then return tonumber(n) end
    _, _, n = string.find(txt, "[Hh]eilung von Zaubern und Effekten um bis zu (%d+)")
    if n then return tonumber(n) end
    _, _, n = string.find(txt, "[Ss]chaden und Heilung von Zaubern und Effekten um bis zu (%d+)")
    if n then return tonumber(n) end
    return 0
end

-- Sum +healing across all equipped slots.
function M:GearHealBonus()
    if self.cachedHealBonus then return self.cachedHealBonus end
    local total = 0
    for slot = 1, 19 do
        if GetInventoryItemLink("player", slot) then
            healScanTip:ClearLines()
            healScanTip:SetInventoryItem("player", slot)
            for i = 1, healScanTip:NumLines() do
                local fs = getglobal("Aegis_SBR_HealScanTextLeft" .. i)
                local txt = fs and fs:GetText()
                if txt then total = total + self:ParseHealBonus(txt) end
            end
        end
    end
    self.cachedHealBonus = total
    return total
end

-- Templates: starting presets, copied into the char's saved profiles once.
M.templates = {
    starter = {  -- valid for a brand new paladin (only Seal of Righteousness)
        spec = "retri",
        seals = { debuff = "", damage = "Seal of Righteousness" },
        consecInMana = false,
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "autodps",
        -- Downranking on for the starter: a levelling paladin has a small pool
        -- and every rank of a strike hits nearly as hard for a fraction of it.
        strikeDownrank = true,
        spells = { holyStrike = false, crusaderStrike = false, holyShield = false, hammerOfWrath = false, repentance = false },
    },
    retri = {
        spec = "retri",
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        consecInMana = false,
        -- Mana management ON, unlike every other template. Retribution is the
        -- spec that runs itself dry: it spends on every strike and every judge
        -- and has no cheap filler to fall back on. Leaving the one mechanism
        -- that recovers mana switched off by default meant a questing paladin
        -- went out of mana and stayed there (play report, 2026-08-22).
        manaManage = true, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "autodps",
        strikeDownrank = true,
        spells = { holyStrike = true, crusaderStrike = true, holyShield = false, hammerOfWrath = false, repentance = false },
    },
    prot = {
        spec = "tank",
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        consecInMana = false,
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "tankblock",
        spells = { holyStrike = true, crusaderStrike = true, holyShield = true, hammerOfWrath = false, repentance = false },
    },
    heal = {  -- group healer: heals the party/raid, keeps Seal of Wisdom for mana
        spec = "heal",
        seals = { debuff = "", damage = "" },
        consecInMana = false,
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "autodps",
        spells = { holyStrike = false, crusaderStrike = false, holyShield = false, hammerOfWrath = false, repentance = false },
        healMode = true, healThreshold = 75, useHolyShock = true, holyShockPct = 50, healPower = 0,
        healReloadCS = true, healSplashHS = true, hsMinHP = 100, hsMinTargets = 1,
        healManaSelf = true, healManaJudge = false,
    },
}

M.sealAlias = {
    crusader = "Seal of the Crusader", sotc = "Seal of the Crusader",
    justice = "Seal of Justice", soj = "Seal of Justice",
    wisdom = "Seal of Wisdom", sow = "Seal of Wisdom",
    light = "Seal of Light", sol = "Seal of Light",
    righteousness = "Seal of Righteousness", sor = "Seal of Righteousness",
    command = "Seal of Command", soc = "Seal of Command",
    none = "",
}

M.spellAlias = {
    holystrike = "holyStrike", hs = "holyStrike",
    crusaderstrike = "crusaderStrike", cs = "crusaderStrike",
    holyshield = "holyShield",
    hammer = "hammerOfWrath", how = "hammerOfWrath",
    repentance = "repentance", rep = "repentance",
    consecration = "consecration", consec = "consecration", cons = "consecration",
    exorcism = "exorcism", exo = "exorcism",
}

-- Optional /sbr strike <what> aliases. The UI is the primary control; this is a
-- thin convenience for macros. off/hs/cs set the two strike toggles; auto/tank
-- set both toggles on and pick the both-on strategy.
M.strikeCmdAlias = {
    off = "off", none = "off",
    hs = "hs", holy = "hs",
    cs = "cs", crusader = "cs",
    auto = "auto", dps = "auto",
    tank = "tank", block = "tank",
}

-- Fills any missing field with a default and migrates old-format profiles
-- (old standard slot becomes the damage slot, old mana slot is dropped).
function M:NormalizeProfile(c)
    c.seals = c.seals or {}
    if c.seals.damage == nil then c.seals.damage = c.seals.standard or "" end
    if c.seals.debuff == nil then c.seals.debuff = "" end
    c.seals.standard = nil
    c.seals.mana = nil

    c.spells = c.spells or {}

    -- Strike model: two toggles (holyStrike / crusaderStrike) plus a strategy
    -- (strikeStyle) that only matters when BOTH are on. Migrate forward from the
    -- interim strikeMode dropdown (off/auto/cs/hs/hscs), which had replaced the
    -- original two toggles, so both old save formats land here correctly.
    if c.spells.holyStrike == nil or c.spells.crusaderStrike == nil then
        local hs, cs = c.spells.holyStrike, c.spells.crusaderStrike
        if c.strikeMode ~= nil then
            local m = c.strikeMode
            if m == "off"      then hs, cs = false, false
            elseif m == "cs"   then hs, cs = false, true
            elseif m == "hs"   then hs, cs = true, false
            else                    hs, cs = true, true    -- auto / hscs / unknown
            end
        end
        c.spells.holyStrike     = (hs == true)
        c.spells.crusaderStrike = (cs == true)
    end
    -- Strategy for when both strikes are enabled: autodps | tankblock.
    if c.strikeStyle == nil then c.strikeStyle = "autodps" end
    c.strikeMode = nil   -- retire the interim dropdown field
    c.prioZeal = nil     -- retired: its logic now lives inside "autodps"

    local sk = { "holyShield", "hammerOfWrath", "repentance", "consecration", "exorcism" }
    for i = 1, table.getn(sk) do
        if c.spells[sk[i]] == nil then c.spells[sk[i]] = false end
    end

    -- Let Consecration ignore the mana-recovery hold (see the rotation step).
    if c.consecInMana == nil then c.consecInMana = false end
    if c.manaManage == nil then c.manaManage = false end
    if c.manaLow  == nil then c.manaLow  = 30 end
    if c.manaHigh == nil then c.manaHigh = 70 end
    if c.manaWeave == nil then c.manaWeave = false end
    if c.manaWeaveMin == nil then c.manaWeaveMin = 15 end
    if c.manaWisdomDebuff == nil then c.manaWisdomDebuff = false end
    if c.hpManage == nil then c.hpManage = false end
    if c.hpLow  == nil then c.hpLow  = 30 end
    if c.hpHigh == nil then c.hpHigh = 70 end
    if c.sealTwist == nil then c.sealTwist = false end
    if c.strikeDownrank == nil then c.strikeDownrank = false end
    -- Healing support (merged). Roleless: healMode alone drives heal behavior.
    -- Coerce to a strict boolean. This also repairs any profile corrupted by the
    -- old tab bug, which could store the string "damage" (truthy) into healMode.
    c.healMode = (c.healMode == true)
    -- Which page of the panel this profile is on: "tank", "retri" or "heal".
    --
    -- healMode stays the field the ROTATION branches on - every existing check
    -- reads it and none of them had to change. spec is derived into it at the
    -- top of Rotate, so the two can never disagree, and an older profile that
    -- only has healMode lands on the right tab here.
    if c.spec == nil then c.spec = c.healMode and "heal" or "retri" end
    -- "retri" is the DPS page; the key kept its old name through the rename so
    -- profiles written before it keep working.
    if c.spec ~= "tank" and c.spec ~= "solo" and c.spec ~= "retri" and c.spec ~= "heal" then
        c.spec = c.healMode and "heal" or "retri"
    end
    c.healMode = (c.spec == "heal")
    if c.healThreshold == nil then c.healThreshold = 75 end
    -- Reserve Holy Light for targets below this health percent (0 = off, the
    -- efficiency comparison in DoHeal decides on its own). Community request:
    -- Flash of Light is the mana-efficient workhorse, so some players want the
    -- big heal held back for people who are genuinely low rather than picked
    -- whenever the raw deficit happens to be large.
    -- Retired: a second Holy Light threshold. It said "no Holy Light above X%
    -- health", which is the same sentence as ratioHealthy's "Holy Light below
    -- X%" - two sliders about the same decision, pointing the same way, with
    -- different names. Cleared rather than left dormant: a hidden setting that
    -- still acts is worse than one you can see.
    c.holyLightPct = nil
    -- The "healthy" ratio. Below it a target is hurt enough to be worth a Holy
    -- Light; above it the fast heal is used whatever the deficit. Above this the target is
    -- considered safe enough to spend a 2.5s Holy Light on; below it, Flash of
    -- Light takes over however far short it falls.
    if c.ratioHealthy == nil then c.ratioHealthy = 60 end
    -- Rank bounds per spell. The maximum caps downranking from the top, the
    -- minimum forces at least that rank whenever mana allows.
    if c.folMaxRank == nil then c.folMaxRank = 7 end
    if c.hlMaxRank == nil then c.hlMaxRank = 9 end
    if c.folMinRank == nil then c.folMinRank = 1 end
    if c.hlMinRank == nil then c.hlMinRank = 1 end
    -- Heal priority. A LIST of player names, in order, plus a switch.
    --
    -- The usual approach elsewhere is a FILTER - "heal main tanks only" on a
    -- macro you choose to press. A one-button rotation cannot ask which macro you
    -- meant, so the list has to influence the choice instead of restricting it.
    if c.healPrio == nil then c.healPrio = false end
    if type(c.healPrioList) ~= "table" then c.healPrioList = {} end
    -- Your current friendly target counts as position 1 while it is selected.
    if c.healPrioTarget == nil then c.healPrioTarget = false end
    -- Only heal YOURSELF below this. A healer has more ways out of trouble than
    -- anyone else - stepping out of a cleave is often enough - so being at 70%
    -- is not a reason to spend a cast on yourself. 0 turns the exception off and
    -- you are treated like any other group member.
    if c.healSelfPct == nil then c.healSelfPct = 40 end
    -- Prefer whoever is actually TAKING damage over whoever merely has a low
    -- bar. 1.12 has no threat API and no way to enumerate the mobs, so this is
    -- measured rather than asked: a unit that lost health in the last few
    -- seconds is in danger, one sitting still at 40% is not.
    if c.healAggro == nil then c.healAggro = false end
    -- Pre-heal somebody who has aggro even while they are above the heal
    -- threshold: the damage is coming, and topping them off first is cheaper
    -- than catching them after.
    if c.healPrecast == nil then c.healPrecast = false end
    -- Emergency invulnerability. Below this share of your own health, everything
    -- stops and the bubble goes up. 0 = off, and off is the default: a spell on
    -- a five minute cooldown that also drops your damage by 60% is not something
    -- an addon should decide for you unasked.
    if c.panicPct == nil then c.panicPct = 0 end
    -- The tank's version of the same idea, and deliberately a different spell.
    -- A bubble drops every point of threat you have built, which on a tank hands
    -- the whole pull to somebody who cannot survive it - the emergency that
    -- saves you kills the group. Lay on Hands costs no threat.
    if c.tankLohPct == nil then c.tankLohPct = 0 end
    -- Health to reach while a bubble is up. Ten seconds of immunity is the only
    -- completely safe casting time a paladin ever gets: no damage, so no
    -- pushback and no risk of dying mid-cast. 0 = off.
    --
    -- A health goal rather than a number of casts, which is what this started
    -- as: three casts means something entirely different at rank 1 with +40
    -- healing than at rank 9 with +900, while "get me to 80%" means the same
    -- thing to everyone. The heal engine already sizes a rank to a deficit, so
    -- the goal is simply handed to it as a threshold.
    if c.panicHealTo == nil then c.panicHealTo = 0 end
    c.panicHealCasts = nil   -- retired: replaced by the health goal above
    -- Dispelling. Off by default - it spends a global cooldown that would
    -- otherwise be a heal, and which afflictions are worth removing is a
    -- judgement call that belongs to the player, not to us.
    if c.useCure == nil then c.useCure = false end
    -- The crossover. Curing runs BEFORE healing while the worst-hurt member is
    -- above this; below it, healing wins. At 90 the group is cleansed first and
    -- topped from 90 to 100 afterwards, which is the order that matters when the
    -- affliction is doing more damage than the missing tenth of a health bar.
    if c.curePct == nil then c.curePct = 90 end
    -- Pets. 0 never, 1 only when no player needs healing, 2 equal to players.
    -- A pet you have TARGETED is always considered, at any setting.
    if c.petPriority == nil then c.petPriority = 1 end
    -- Raid subgroups to ignore, keyed by group number. Empty = heal everyone.
    if type(c.raidGroupSkip) ~= "table" then c.raidGroupSkip = {} end
    -- Cancel a heal in flight once this share of it would be pure overheal.
    -- 0 = off, which is the behaviour before this existed: a started cast always
    -- finishes. Stopping a cast is visible and surprising, so it is opt-in.
    if c.overhealCancel == nil then c.overhealCancel = 0 end
    -- Grace period before a cancel may fire, so a cast is never cut the instant
    -- it starts on a target somebody else is already healing.
    if c.overhealCancelDelay == nil then c.overhealCancelDelay = 0 end
    if c.useHolyShock == nil then c.useHolyShock = true end
    if c.holyShockPct == nil then c.holyShockPct = 50 end
    -- Holy Strike ahead of the healing itself, on cooldown, whenever you are in
    -- melee range. Off by default because it IS a trade: a strike takes the
    -- global cooldown a direct heal wanted, so somebody occasionally waits a
    -- beat longer.
    --
    -- Asked for by a level 60 holy paladin, whose whole rotation is built on it:
    -- Holy Strike, then Holy Light or two Flashes of Light while it comes back.
    -- It splash-heals the group AND returns mana through Seal of Wisdom, which
    -- is why a paladin who only casts the two direct heals cannot keep up. The
    -- range requirement is the control: step out of melee and the rotation is
    -- an ordinary healing rotation again.
    if c.hsPriority == nil then c.hsPriority = false end
    -- Damage fillers for heal mode, both off by default and both LAST in the
    -- order - below the healing, below the seal work, below everything the
    -- healer tab exists for. They only ever take a press nothing else wanted.
    --
    -- Hammer of Wrath is nearly free: instant, on its own cooldown, and only
    -- legal inside the execute window, so it cannot compete with a heal it
    -- would otherwise have been.
    --
    -- Consecration is the one with a cost, which is why it is separate. It
    -- spends real mana and it makes threat on everything standing in it - as a
    -- healer that is a decision, not a bonus.
    -- Consecration held while you are moving, on every tab.
    --
    -- ON by default, which is the exception to this file's usual "new switches
    -- start off". Reported from play: when you are moving the mobs are usually
    -- moving too, so the patch lands on ground everyone is about to leave - the
    -- mana is spent, the damage is not dealt, and the threat lands on nothing.
    -- The behaviour it replaces is the accident, not the feature.
    --
    -- Turning it off restores casting on cooldown regardless. A tank who
    -- repositions constantly may well want that: Consecration is threat, and a
    -- held cast is threat not made.
    --
    -- Where movement cannot be measured at all (no SuperWoW) Moving() answers
    -- "standing still", so this switch simply never blocks anything.
    if c.consecStill == nil then c.consecStill = true end
    -- How many enemies must be standing in the patch. 0 is off, which is the
    -- default and the behaviour every earlier version had: cast on cooldown and
    -- let the player decide with the AoE toggle.
    --
    -- Off by default because the count depends on nameplates being drawn. It is
    -- a real measurement where it works and no measurement at all where it does
    -- not, and a default that quietly needs a client setting is a trap.
    if c.consecMinTargets == nil then c.consecMinTargets = 0 end
    -- Seconds of measured time-to-kill a NON-elite target must have before
    -- Repentance is spent learning whether it is immune. Elites and bosses skip
    -- this and are always worth the one cast.
    if c.repentProbeTTK == nil then c.repentProbeTTK = 15 end
    if c.healFillerHoW == nil then c.healFillerHoW = false end
    if c.healFillerConsec == nil then c.healFillerConsec = false end
    if c.healFillerExo == nil then c.healFillerExo = false end
    -- Below this share of mana the fillers stop entirely and what is left is
    -- kept for healing. Asked for from play, and it is the right shape: the
    -- fillers are free only while mana is not the constraint, and the moment it
    -- is, every point of it belongs to the group.
    --
    -- Independent of the melee tabs' mana management, which latches and is about
    -- pacing a damage rotation. This is one line and it does one thing.
    if c.healFillerMana == nil then c.healFillerMana = 40 end
    -- Split the old single heal-weave toggle into two independent behaviours
    -- (CS reload of Holy Shock, and Holy Strike filler), then retire it.
    if c.healReloadCS == nil then c.healReloadCS = (c.healWeaveStrikes ~= false) end
    if c.healSplashHS == nil then c.healSplashHS = (c.healWeaveStrikes ~= false) end
    c.healWeaveStrikes = nil
    -- Retired: a mana floor under the Holy Strike filler. Two things were wrong
    -- with it. It gated a mana-RETURNING ability on having mana, so it switched
    -- off exactly when it was needed; and it belonged to a second Holy Strike
    -- path that has been removed - one switch now drives one rule, the headcount
    -- trigger in HolyStrikeDue.
    c.healWeaveManaFloor = nil
    -- Holy Strike restrictions - and they RESTRICT. By default it goes out on
    -- cooldown like any other strike.
    --
    -- These shipped at 93% / 3 targets, a pair of numbers lifted from a manually
    -- pressed macro whose question was "is this worth pressing as a group heal".
    -- A rotation asks something else entirely: Holy Strike is a damage ability on
    -- a cooldown and the splash is a bonus, so holding it back means giving up
    -- damage to avoid healing by accident. Both play reports said so from
    -- opposite ends - while levelling it was the single largest source of
    -- healing precisely because it was pressed constantly, and at three targets
    -- it had to be pressed by hand.
    if c.hsMinHP == nil then c.hsMinHP = 100 end
    if c.hsMinTargets == nil then c.hsMinTargets = 1 end
    -- Migration, once: profiles written while the old defaults were live carry
    -- 93 / 3 as stored values, so a corrected DEFAULT never reaches them - and a
    -- restriction nobody chose would go on silently holding Holy Strike back.
    -- Only that exact pair is moved; anything else was set on purpose.
    if c.hsMinHP == 93 and c.hsMinTargets == 3 then
        c.hsMinHP = 100
        c.hsMinTargets = 1
    end
    if c.healPower == nil then c.healPower = 0 end
    -- Heal-mode mana upkeep. Self seal defaults on (free sustain); the group
    -- judge defaults off because it spends a GCD that cannot be a heal.
    if c.healManaSelf  == nil then c.healManaSelf  = true  end
    if c.healManaJudge == nil then c.healManaJudge = false end
    -- Pre-load Holy Judgement during a lull. OFF by default: it is on the "adds
    -- casts" side, and a cast added to a healer's rotation is exactly the kind of
    -- change that has to be play-tested before it becomes the default.
    if c.healJudgeHL == nil then c.healJudgeHL = false end
    return c
end

function M:AvailableSealsOf(list)
    local out = {}
    for i = 1, table.getn(list) do
        if self:KnowsSpell(list[i]) then table.insert(out, list[i]) end
    end
    return out
end

function M:ProfileValidity(cfg)
    local missing = {}
    if cfg.seals.debuff ~= "" and not self:KnowsSpell(cfg.seals.debuff) then table.insert(missing, cfg.seals.debuff) end
    if cfg.seals.damage ~= "" and not self:KnowsSpell(cfg.seals.damage) then table.insert(missing, cfg.seals.damage) end
    if cfg.spells.holyShield     and not self:KnowsSpell("Holy Shield")     then table.insert(missing, "Holy Shield")     end
    if cfg.spells.hammerOfWrath  and not self:KnowsSpell("Hammer of Wrath") then table.insert(missing, "Hammer of Wrath") end
    if cfg.spells.repentance     and not self:KnowsSpell("Repentance")      then table.insert(missing, "Repentance")      end
    if cfg.spells.consecration   and not self:KnowsSpell("Consecration")    then table.insert(missing, "Consecration")    end
    if cfg.spells.exorcism       and not self:KnowsSpell("Exorcism")        then table.insert(missing, "Exorcism")        end
    if cfg.manaManage and not self:KnowsSpell("Seal of Wisdom") then table.insert(missing, "Seal of Wisdom (mana)") end
    if cfg.hpManage   and not self:KnowsSpell("Seal of Light")  then table.insert(missing, "Seal of Light (hp)")    end
    return (table.getn(missing) == 0), missing
end

function M:TargetHasJudgementDebuff(sealName)
    local nm   = self.debuffName[sealName]
    local frag = self.debuffTex[sealName]
    if not nm and (not frag or frag == "") then return false end
    return self:TargetDebuffUp(nm, frag)
end

-- ============================================================
-- Management hysteresis state
-- ============================================================
function M:UpdateManagement(cfg)
    if cfg.manaManage and self:KnowsSpell("Seal of Wisdom") then
        local mp = self:ManaPct()
        if mp < cfg.manaLow  then self.manaMgmtActive = true end
        if mp >= cfg.manaHigh then self.manaMgmtActive = false end
    else
        self.manaMgmtActive = false
    end

    if cfg.hpManage and self:KnowsSpell("Seal of Light") then
        local hp = self:PlayerHPPct()
        if hp < cfg.hpLow  then self.hpMgmtActive = true end
        if hp >= cfg.hpHigh then self.hpMgmtActive = false end
    else
        self.hpMgmtActive = false
    end
end

-- ============================================================
-- Strikes
-- ============================================================
-- Which strikes the profile enables, and whether they are actually learned.
-- Gating on the two toggles (not just KnowsSpell) is what makes "only Holy
-- Strike" or "only Crusader Strike" mean exactly that.
function M:HSOn(cfg) return cfg.spells.holyStrike     and self:KnowsSpell("Holy Strike")     end
function M:CSOn(cfg) return cfg.spells.crusaderStrike and self:KnowsSpell("Crusader Strike") end

function M:StrikeEnabled(cfg)
    return (self:HSOn(cfg) or self:CSOn(cfg)) and true or false
end

function M:SharedStrikeReady(cfg)
    if self:HSOn(cfg) and self:IsReady("Holy Strike")     then return true end
    if self:CSOn(cfg) and self:IsReady("Crusader Strike") then return true end
    return false
end

-- A shield or offhand in slot 17 means we are tanking right now (two-handers
-- leave it empty), the same live playstyle read ExAutoCSHS uses.
function M:HasOffhand()
    if GetInventoryItemLink then return GetInventoryItemLink("player", 17) ~= nil end
    return false
end

-- Auto leans Holy Strike when tanking: the deep-Prot threat talent or a shield
-- equipped. Otherwise (two-hander, no threat talent) it leans Crusader Strike.
function M:AutoLeansHoly()
    if self:TalentRank(TALENT_THREAT) > 0 then return true end
    return self:HasOffhand()
end

-- Talent rank by name, cached. The cache is cleared on CHARACTER_POINTS_CHANGED
-- and at login (see the frame at the bottom of this file).
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

-- Holy Strike only applies Holy Might if the player has the talent for it,
-- so there is no point maintaining that buff otherwise (the core leveling fix).
function M:HolyMightWorthwhile()
    return self:TalentRank(TALENT_HOLY_MIGHT) > 0
end

-- MaxRank(name) is inherited from the core, which serves it from the cached
-- spellbook index (rebuilt on SPELLS_CHANGED).

-- The downrank ceiling tells which rank to use for the current raw mana, or
-- nil when mana is above all ceilings (use full rank).
function M:DownrankFor(name)
    local t = DOWNRANK[name]
    if not t then return nil end
    local mana = UnitMana("player")
    for r = 1, table.getn(t) do
        if mana < t[r] then return r end
    end
    return nil
end

-- The rank a strike would actually cast right now (clamped to what is known),
-- used both for casting and for the trace readout.
function M:EffectiveStrikeRank(name, cfg)
    local maxR = self:MaxRank(name)
    if not cfg.strikeDownrank then return maxR end
    local r = self:DownrankFor(name)
    if not r or maxR == 0 or r >= maxR then return maxR end
    return r
end

-- Cast a strike, optionally downranked to save mana. Picks the highest rank
-- the current raw mana can afford (per the tables above), never above the
-- highest known rank; at full rank it casts the base name.
-- Can this spell be paid for right now?
--
-- The paladin module asked this nowhere at all, which is what makes running out
-- of mana a trap rather than a phase. Pick only checks that a spell is KNOWN and
-- then reports success, so at low mana the rotation kept choosing a strike, the
-- cast quietly failed, and the press was spent. Every press. Nothing fell
-- through to anything cheaper, and nothing noticed.
--
-- CanAfford answers true when the cost cannot be read, so an unreadable tooltip
-- degrades to exactly the old behaviour rather than silencing an ability.
function M:Affordable(name)
    return Aegis_SBR:CanAfford(name)
end

function M:CastStrike(name, cfg)
    -- Checked against the rank that will actually go out: a downranked strike
    -- costs less, and refusing it at full-rank price would hold back the very
    -- thing downranking exists for.
    if cfg.strikeDownrank then
        local maxR = self:MaxRank(name)
        local r = self:DownrankFor(name)
        if r and maxR > 0 and r < maxR then
            local ranked = name .. "(Rank " .. r .. ")"
            -- No affordability gate on the downranked cast, deliberately. The
            -- spell index is keyed by bare name, so the cost of a specific rank
            -- cannot be read - and checking the FULL rank's price here would
            -- refuse the cheap cast that downranking exists to make. A downrank
            -- is already the answer to being short of mana.
            if Aegis_SBR.deciding then
                local p = Aegis_SBR.decidePlan
                p.spell = ranked; p.reason = "downranked to save mana"
                return true
            end
            CastSpellByName(ranked)
            return true
        end
    end
    if not self:Affordable(name) then return false end
    return self:Pick(name, "strike")
end

-- The single strike chosen for this shared-cooldown window. Gated on the two
-- toggles, so a single enabled strike is used exclusively; only when BOTH are
-- enabled does the strategy (autodps | tankblock) decide the mix.
function M:ResolveSharedCD(cfg)
    local hs = self:HSOn(cfg)
    local cs = self:CSOn(cfg)
    if hs and cs then
        if (cfg.strikeStyle or "autodps") == "tankblock" then return self:ResolveTankBlock(cfg) end
        return self:ResolveAutoDPS(cfg)
    elseif hs then
        return "Holy Strike"
    elseif cs then
        return "Crusader Strike"
    end
    return nil
end

-- Auto DPS ladder, talent-aware. Without Vengeful Strikes, Holy Strike grants
-- no Holy Might, so the ladder just builds Zeal on Crusader Strike and otherwise
-- swings Holy Strike (which still returns mana and health to the group). With
-- the talent, Holy Might is kept up, Zeal is ramped to three stacks, and if BOTH
-- buffs are about to fall in the same window Zeal wins - losing three stacks
-- costs more than a one-GCD Holy Might refresh.
function M:ResolveAutoDPS(cfg)
    local zt, zc = self:BuffTime("Zeal")

    if not self:HolyMightWorthwhile() then
        -- Pre-talent (leveling): Crusader Strike to three Zeal, then Holy Strike
        -- unless Zeal is about to expire.
        if zc < ZEAL_STACKS then return "Crusader Strike" end
        if zt < ZEAL_RENEW  then return "Crusader Strike" end
        return "Holy Strike"
    end

    -- Talented: keep Holy Might up and Zeal at three stacks.
    local hmt = self:BuffTime("Holy Might")
    if hmt <= 0 then return "Holy Strike" end            -- opener / lost it: get Holy Might rolling

    if zc < ZEAL_STACKS then                             -- still ramping Zeal
        if hmt < HM_RENEW then return "Holy Strike" end  -- but refresh Holy Might if it is about to drop
        return "Crusader Strike"
    end

    -- Zeal is full: maintenance. Zeal wins ties (three stacks are precious).
    if zt  < ZEAL_RENEW then return "Crusader Strike" end
    if hmt < HM_RENEW  then return "Holy Strike"     end
    return "Holy Strike"                                 -- filler tops Holy Might, adds mana and heal
end

-- Tank, both strikes on: keep the Crusader Strike block buff (Zealous Defense,
-- consumed on the next block) loaded, and spend every other window on Holy
-- Strike for threat. Re-applying Crusader Strike while the buff is still up
-- would waste it, so Holy Strike takes those windows.
function M:ResolveTankBlock(cfg)
    if not self:HasBuff("Zealous Defense") then return "Crusader Strike" end
    return "Holy Strike"
end

-- True if the configured debuff is up on the current target, with a short memory
-- against brief detection dropouts and a reset on a real target change (by GUID,
-- so same named mobs are told apart).
function M:DebuffEffectivelyUp(debuffSeal)
    if not debuffSeal or debuffSeal == "" then return false end
    local id = self:TargetId()
    if id ~= self.debuffTargetId or debuffSeal ~= self.debuffTrackedSeal then
        self.debuffTargetId = id
        self.debuffTrackedSeal = debuffSeal
        self.debuffSeenAt = nil
        self.weaving = false          -- new target or changed debuff starts fresh
    end
    local now = GetTime()
    if self:TargetHasJudgementDebuff(debuffSeal) then self.debuffSeenAt = now end
    return self.debuffSeenAt ~= nil and (now - self.debuffSeenAt) < 1.5
end

-- `forceDebuff` overrides the profile's debuff seal for this press only, and
-- exists for one caller: the Hammer of Wrath execute, which wants Judgement of
-- the Crusader on the target and asks for it HERE rather than casting a seal
-- itself. Routing it through this function is the point - the seal cycle stays
-- in one place, so nothing can end up fighting over which seal is carried.
function M:HandleSeals(cfg, forceDebuff)
    -- Returns true if a cast was issued, so the caller can stop.
    if not self.manaMgmtActive then self.weaving = false end

    local debuffSeal = forceDebuff or cfg.seals.debuff
    local dmgSeal    = cfg.seals.damage
    local canJudge   = self:KnowsSpell("Judgement") -- Safety check for low levels

    -- During mana recovery, optionally apply the Seal of Wisdom debuff (Judgement
    -- of Wisdom) instead of the configured one, since it returns mana to attackers
    -- and aids recovery. Toggled per profile.
    local effDebuff = debuffSeal
    -- The forced seal wins over the mana-recovery substitution: it was asked for
    -- by a step that already decided it is worth the mana.
    if not forceDebuff and self.manaMgmtActive and cfg.manaWisdomDebuff
        and self:KnowsSpell("Seal of Wisdom") then
        effDebuff = "Seal of Wisdom"
    end

    -- (A) Always make sure a new mob carries the (effective) debuff.
    -- Skipped if Judgement is not yet learned.
    if effDebuff ~= "" and canJudge and not self:DebuffEffectivelyUp(effDebuff) then
        if not self:HasBuff(effDebuff) then return self:Pick(effDebuff, "debuff seal") end
        -- Judgement reaches about ten yards; the seal above is a self buff and
        -- needs nothing. Without this the seal went up at range and the
        -- judgement behind it failed on every press.
        if self:IsReady("Judgement") and self:Affordable("Judgement")
            and Aegis_SBR:SpellReaches("Judgement", "target") then
            return self:Pick("Judgement", "stamp the debuff")
        end
        return false   -- seal up, waiting for judgement to apply the debuff
    end

    -- (B) mana management: hold Seal of Wisdom, optionally weave the damage seal
    if self.manaMgmtActive then
        local dmg = dmgSeal
        local canWeave = cfg.manaWeave and dmg ~= "" and self:KnowsSpell(dmg)

        -- The mana floor only gates STARTING a weave. Once self.weaving is set,
        -- the cycle is always finished (get the seal up, judge, back to Seal of
        -- Wisdom), even if mana dips below the floor, so the swap is never wasted.
        if canWeave and self.weaving then
            if not self:HasBuff(dmg) then return self:Pick(dmg, "weave: damage seal up") end
            if canJudge and self:IsReady("Judgement") then
                local c = self:Affordable("Judgement")
                    and self:Pick("Judgement", "weave: judge, then back to Wisdom")
                self:Later(function() self.weaving = false end)
                return c
            end
            return false
        end
        if canWeave and canJudge and self:IsReady("Judgement") and self:ManaPct() >= (cfg.manaWeaveMin or 0) then
            self:Later(function() self.weaving = true end)
            return self:Pick(dmg, "weave: starting")
        end
        self:Later(function() self.weaving = false end)
        if not self:HasBuff("Seal of Wisdom") then return self:Pick("Seal of Wisdom", "mana management") end
        return false
    end

    -- (C) HP management: hold Seal of Light
    if self.hpMgmtActive then
        if not self:HasBuff("Seal of Light") then return self:Pick("Seal of Light", "health management") end
        return false
    end

    -- (D) normal: the debuff is up (or none). Judge the damage seal continuously,
    -- else hold the debuff seal as a buff only.
    local seal, judgeIt
    if dmgSeal ~= "" then
        seal, judgeIt = dmgSeal, true
    elseif debuffSeal ~= "" then
        seal, judgeIt = debuffSeal, false
    else
        return false
    end

    if not self:HasBuff(seal) then return self:Pick(seal, "seal missing") end       -- seal must be up before judging
    
    if judgeIt and canJudge and self:IsReady("Judgement") then
        -- Seal twisting: hold the damage seal judge until just before the next
        -- white swing, so the swing carries the seal proc and the judgement land
        -- together. The debuff judge in (A) is never delayed. Unknown timer judges now.
        if cfg.sealTwist and seal == dmgSeal and dmgSeal ~= "" then
            local tl = self:SwingTimeLeft()
            if tl and tl > 0.4 then return false end
        end
        if not self:Affordable("Judgement") then return false end
        return self:Pick("Judgement", "judge the seal")
    end
    return false
end

-- The seal we want UP first on contact, so it can be pre-cast while running in.
function M:DesiredOpenerSeal(cfg)
    if self.manaMgmtActive then return "Seal of Wisdom" end
    if self.hpMgmtActive  then return "Seal of Light" end
    if cfg.seals.debuff ~= "" then return cfg.seals.debuff end   -- debuff seal judged first
    if cfg.seals.damage ~= "" then return cfg.seals.damage end
    return nil
end

-- What the paladin can do with nobody targeted: put the seal on.
--
-- A seal is a self buff and needs neither an enemy nor range - the rotation
-- simply never got the chance to cast one, because the core holds a melee module
-- back until there is something to hit, and the module's own opener branch sits
-- behind that same guard. So the seal went up on CONTACT, costing a global
-- cooldown at the one moment it is worth the most.
--
-- Holy Shield belongs here too, and for a reason that is easy to get wrong: its
-- COOLDOWN EQUALS ITS DURATION. Nothing is thrown away by raising it early -
-- arrive inside the ten seconds and it is already up; arrive later and the
-- cooldown has expired with it, so it goes up on contact exactly as before. The
-- one thing that breaks that symmetry is blocks being consumed early, which
-- cannot happen while running in with nobody hitting you.
--
-- Nothing is spent while both are up, so holding the button between pulls costs
-- one cast per lapse rather than one per press - though note Holy Shield lapses
-- every ten seconds against the seal's thirty, so idling on the button is three
-- times as expensive with it enabled.
--
-- UpdateManagement runs first so a paladin in mana or health recovery pre-casts
-- the seal that recovery wants, not the damage one.
function M:Prebuff(cfg)
    if cfg.healMode then return false end
    self:UpdateManagement(cfg)
    local seal = self:DesiredOpenerSeal(cfg)
    if seal and seal ~= "" and self:KnowsSpell(seal) and not self:HasBuff(seal)
        and self:Affordable(seal) then
        return self:Pick(seal, "pre-buff")
    end

    if cfg.spells.holyShield and self:KnowsSpell("Holy Shield")
        and self:OwnCDReady("Holy Shield") and not self:HasBuff("Holy Shield")
        and self:Affordable("Holy Shield") then
        return self:Pick("Holy Shield", "pre-buff")
    end
    return false
end

-- Exorcism only works on Undead and Demon targets. The creature type cannot
-- change under a given target, so it is resolved once per target rather than on
-- every press - the check sits in the rotation's hot path and this is a plain
-- API call saved on all but the first press against each mob. Keyed by target
-- id (GUID based, so same-named mobs are told apart), which also means a target
-- swap re-reads immediately instead of answering from a stale cache.
function M:TargetIsUndeadOrDemon()
    local id = self:TargetId()
    if id ~= self.creatureTypeId then
        local t = UnitCreatureType("target")
        self.creatureTypeId = id
        self.creatureTypeUD = (t == "Undead" or t == "Demon")
    end
    return self.creatureTypeUD
end

-- Is something hitting US right now? The mob we are fighting is the one that
-- matters, and its target answers directly - one API call, no scanning.
--
-- Used for spell PUSHBACK: every hit taken during a cast delays it, which is
-- what makes a cast-time execute a poor trade while you are being beaten on.
function M:BeingAttacked()
    return (UnitExists("targettarget") and UnitIsUnit("targettarget", "player")) and true or false
end

-- Seconds of setup between here and a Hammer of Wrath cast landing under
-- Judgement of the Crusader, when that judgement is not up yet.
--
-- Counted honestly, because the whole decision rests on it:
--   * Judgement's own remaining cooldown, which nothing can shorten
--   * a global cooldown to put Seal of the Crusader on, unless it is already
--     the seal being carried
--   * a global cooldown for the Judgement itself, which CONSUMES the seal
--   * a global cooldown to put the damage seal back on, or you swing bare
--   * Hammer of Wrath's own cast time on top
--
-- The judgement debuff lasts ten seconds, so a setup of four to five seconds
-- leaves room for one Hammer of Wrath, maybe two. On a normal mob at 20% health
-- that arithmetic never closes - which is correct, and means this path is for
-- elites and bosses by construction rather than by a special case.
local GCD_EST = 1.5
local HOW_CAST = 1.0
function M:CrusaderSetupTime(cfg)
    local gcds = 2   -- the judgement, and putting the damage seal back
    if cfg.seals.damage ~= "Seal of the Crusader"
        and not self:HasBuff("Seal of the Crusader") then
        gcds = gcds + 1
    end
    return Aegis_SBR:OwnCDLeft("Judgement") + gcds * GCD_EST + HOW_CAST
end

-- Is the Seal of the Crusader detour worth taking before Hammer of Wrath?
--
-- Only with a measured time to kill, and only when it comfortably exceeds the
-- setup. An unknown estimate is never a reason to act - the target simply gets
-- the hammer straight away, which is the cheaper mistake.
function M:CrusaderDetourWorthIt(cfg)
    if not self:KnowsSpell("Seal of the Crusader") then return false end
    if not self:KnowsSpell("Judgement") then return false end
    local ttk = Aegis_SBR:TargetTTK()
    if not ttk then return false end
    -- Being hit stretches the hammer's cast through pushback, which eats into
    -- the little uptime the detour buys in the first place.
    local need = self:CrusaderSetupTime(cfg)
    if self:BeingAttacked() then need = need + HOW_CAST end
    return ttk > need
end

-- ============================================================
-- Rotation. Strict single-cast priority with early returns, so exactly
-- one spell is chosen per press. Casting more than one CastSpellByName
-- per frame is unreliable in 1.12 (a later call overrides an earlier
-- one), which would invert the priority. The strike (Holy Strike/Crusader
-- Strike) is a plain GCD-consuming instant cast, same as Judgement below it -
-- confirmed in-game (audit P2); it does NOT queue on the next swing the way
-- an off-GCD ability would. Strike still leads Judgement in this priority
-- deliberately: threat generation on the first Holy Strike matters for
-- tanking, and Holy Might/Zeal buff upkeep matters for Retribution - both
-- outweigh a Judgement/debuff briefly waiting one extra press.
-- Priority: 0 pre-cast seal while running in, 1 strike, 2 Holy Shield,
-- 2b Consecration (when AoE-toggled on), 3 seals/judgement, 4 Hammer,
-- 5 Repentance, 6 Exorcism (undead/demon). Exorcism stays low so it never
-- delays a strike, Holy Shield, seal upkeep, or the execute; both Consecration
-- and Exorcism are skipped during mana recovery so they do not undo it.
-- ============================================================
-- ============================================================
-- Healing engine (merged). Active only in heal mode; uses the core's MaxRank.
-- ============================================================

-- Record an in-flight heal so the next press does not pile onto the same unit.
-- Also stamps our own expected cast completion (see StillCasting) - Holy
-- Light's 2.5s cast is longer than the 1.5s global cooldown, so GcdReady()
-- alone reports "ready" up to a full second before the cast actually finishes.
-- Records the heal about to go out, and logs it.
--
-- `spell` and `deficit` are for the log only. This is the one place that knows
-- both what was actually chosen and what the target was actually missing, so it
-- is the only place overhealing can be measured rather than reconstructed - the
-- trace line further up prints the candidate ranks BEFORE the choice is made.
--
-- The predicted heal is the module's own estimate, not the amount the server
-- lands. It is the right number anyway for the question being asked: whether the
-- RANK PICKER chose too big a heal. A gap between this and the log's health
-- readings would be a separate bug, in the heal tables rather than the choice.
--
-- Inside Later, so a preview press neither commits nor logs.
function M:CommitHeal(unit, amount, castTime, spell, deficit)
    self:Later(function()
        self.healTarget = UnitName(unit)
        -- The unit token as well as the name: the overheal monitor has to read
        -- live health during the cast, and a name cannot be queried.
        self.healUnit = unit
        self.healStart = GetTime()
        self.healAmount = amount or 0
        -- How wasteful this heal ALREADY was when it was chosen. The cancel
        -- monitor compares against this rather than against zero, so it can only
        -- react to the situation changing during the cast - see below.
        local a0 = amount or 0
        local d0 = deficit or 0
        self.healWaste0 = (a0 > 0) and ((a0 - d0) / a0 * 100) or 0
        if self.healWaste0 < 0 then self.healWaste0 = 0 end
        -- Health at the moment of committing, so the credit below can end on
        -- EVIDENCE rather than on a clock: the instant this rises, the client
        -- has caught up and the real value is the accurate one.
        self.healPreHP = UnitHealth(unit) or 0
        -- Now only a ceiling, for the case where the rise never arrives at all
        -- (the unit left, the cast was eaten). Three seconds rather than one,
        -- because it is no longer the thing doing the work.
        self.healUntil = GetTime() + (castTime or 0) + 3.0
        self.castingUntil = GetTime() + (castTime or 0)
        if Aegis_SBR.logging and spell then
            local amt = amount or 0
            local def = deficit or 0
            local over = amt - def
            if over < 0 then over = 0 end
            Aegis_SBR:LogWrite(string.format(
                "heal-cast %s on %s def=%.0f heal=%.0f over=%.0f (%.0f%%)",
                spell, UnitName(unit) or "?", def, amt, over,
                (amt > 0) and (over / amt * 100) or 0))
        end
    end)
end

-- True while our own heal cast is still expected to be resolving, even after
-- the shared GCD (1.5s) has already cleared - closes the gap for any heal
-- whose cast time exceeds the GCD (Holy Light at 2.5s), where a spammed
-- press could otherwise start a second heal before the first has landed,
-- since the target's HP (and PendingFor's prediction) hasn't updated yet.
-- Checks the client's OWN cast-bar state first (CastingBarFrame.casting),
-- which reflects the real, server-confirmed cast regardless of exactly when
-- Nampower's queue actually started it - Nampower queues a press that lands
-- during an active cast/GCD and fires it the instant that cast completes, a
-- behavior that applies to plain CastSpellByName too, not just calls that
-- explicitly use QueueSpellByName (see docs/dependencies.md). A castTime-based
-- guess (castingUntil) assumes the cast started the instant CastSpellByName
-- was called, which is not guaranteed once Nampower's queue is involved -
-- the real cast bar sidesteps that assumption entirely. castingUntil stays
-- as a fallback for the rare case CastingBarFrame is unavailable.
function M:StillCasting()
    if CastingBarFrame and (CastingBarFrame.casting or CastingBarFrame.channeling) then
        return true
    end
    -- castingUntil is cleared by the client's own SPELLCAST_STOP / FAILED /
    -- INTERRUPTED at the bottom of this file, so it can be trusted outright.
    --
    -- It used to be given up after a fixed 0.4s instead, on the theory that a
    -- refused cast never reaches the cast bar. That guess also released casts
    -- that were merely QUEUED behind a global cooldown: the next press re-decided
    -- from scratch, the target's health had drifted across the Flash-of-Light /
    -- Holy-Light line in the meantime, a different spell was chosen, and it clipped
    -- the one already flying. Reported as the rotation "fighting over which one to
    -- use" - and it went away entirely at a threshold where the branch cannot
    -- flip, which is what identified it. Measure the end of a cast, never guess it.
    return self.castingUntil and GetTime() < self.castingUntil
end

-- Predicted incoming heal for a unit from our own pending cast, else 0. The
-- caller (WorstHurt) ADDS this to the unit's real current HP and clamps to
-- max, so the prediction can never over-claim: it self-corrects for new
-- damage. A tank that keeps taking hits while the heal is in flight simply
-- has a lower real HP, and real + pending lands wherever it actually will;
-- only a hit big enough that even the incoming heal won't cover it leaves the
-- unit below the threshold and eligible for another heal. This is why there
-- is no "discard if HP dropped below commit-time baseline" guard here - that
-- guard re-healed any actively-tanked target during the post-cast latency
-- window (real HP already below commit time, but the landed heal's HP update
-- not yet arrived from the server), causing the exact overheal it was meant
-- to avoid.
--
-- WHEN THE CREDIT ENDS was a guessed second, and that second is what both of
-- these reports are: "I healed someone full but the next heal was still on the
-- same target", and "Holy Shock fires above the threshold, mostly out of
-- combat". A party member's health arrives on the server's own cadence, which
-- out of combat is slow. If the credit expires before the new value does
-- arrive, the unit reads at its PRE-HEAL health - so it is picked again and
-- healed into a full bar, and the same stale reading puts its percentage under
-- the Holy Shock emergency line.
--
-- So the credit now ends on evidence: the moment the unit's health rises above
-- what it was when we committed, the client has caught up and its own value is
-- the accurate one. The timer is demoted to a ceiling for the case where the
-- rise never comes.
--
-- Only a RISE clears it. Deliberately not "health changed", and not "health
-- dropped below the commit baseline" - that second guard existed once and
-- re-healed any actively tanked target during exactly this latency window,
-- which is the overheal it was meant to prevent.
function M:PendingFor(unit)
    if not self.healTarget or UnitName(unit) ~= self.healTarget then return 0 end
    if not self.healUntil or GetTime() >= self.healUntil then return 0 end
    local hp = UnitHealth(unit)
    if hp and self.healPreHP and hp > self.healPreHP then return 0 end
    return self.healAmount
end

-- Units to consider for healing: raid1..N in a raid, else player + party1..N.
-- Healing already on its way from OTHER healers, in points, or 0 when nothing
-- can tell us. Optional in exactly the way ClassicAPI is: present, it sharpens
-- the deficit; absent, everything behaves as before.
--
-- Our own pending heal is subtracted out - that one is already tracked by
-- PendingFor and would otherwise be counted twice.
function M:IncomingHeal(unit)
    if not HealComm or not HealComm.getHeal then return 0 end
    local nm = UnitName(unit)
    if not nm then return 0 end
    local total = HealComm:getHeal(nm) or 0
    local mine = 0
    if HealComm.GetMyPendingHeal then mine = HealComm:GetMyPendingHeal(nm) or 0 end
    local other = total - mine
    if other < 0 then other = 0 end
    return other
end

-- True when this unit sits in a raid subgroup the profile has switched off.
-- Only meaningful in a raid; in a party there are no subgroups.
function M:GroupFiltered(cfg, idx)
    if not cfg or type(cfg.raidGroupSkip) ~= "table" then return false end
    if not idx or not GetRaidRosterInfo then return false end
    local _, _, sub = GetRaidRosterInfo(idx)
    return (sub and cfg.raidGroupSkip[sub]) and true or false
end

-- The units worth considering, with their raid index where they have one (so a
-- subgroup filter can be applied) and whether they are a pet.
-- Solofarming has no group to heal: the whole heal engine is pointed at the
-- player and nothing else changes. Reusing the engine rather than writing a
-- second one is the point - rank choice, Holy Judgement, Holy Shock and the
-- overheal cancel all behave exactly as they do for a healer.
function M:GroupUnits(withPets, cfg)
    if cfg and cfg.spec == "solo" then return { "player" } end
    return self:GroupUnitsAll(withPets)
end

function M:GroupUnitsAll(withPets)
    local units = {}
    local nr = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if nr > 0 then
        for i = 1, nr do
            table.insert(units, "raid" .. i)
            if withPets then table.insert(units, "raidpet" .. i) end
        end
    else
        table.insert(units, "player")
        if withPets then table.insert(units, "pet") end
        local np = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, np do
            table.insert(units, "party" .. i)
            if withPets then table.insert(units, "partypet" .. i) end
        end
    end
    return units
end

-- Raid index behind a unit token, for the subgroup filter. nil for party units
-- and pets, which have no subgroup of their own.
local function raidIndex(u)
    local _, _, n = string.find(u, "^raid(%d+)$")
    if not n then _, _, n = string.find(u, "^raidpet(%d+)$") end
    return tonumber(n)
end

local function isPetUnit(u)
    return (u == "pet") or string.find(u, "^partypet") or string.find(u, "^raidpet")
end

-- Self is always reachable; others must be within heal range. Uses
-- IsSpellInRange against the longest-range known heal (Flash of Light/Holy
-- Light, both 40yd) for an exact answer instead of CheckInteractDistance's
-- ~28yd proxy, which under-filtered by 12yd. Falls back to the proxy only if
-- neither heal is learned yet (very early leveling).
-- ============================================================
-- Repentance: two spells wearing one name
--
-- On a target the incapacitate LANDS, it is a six second crowd control that any
-- damage breaks - which in a group is immediately, so on trash it buys a stun
-- and nothing else. On a target IMMUNE to the crowd control it becomes something
-- else entirely: twenty seconds during which every melee attack the enemy makes
-- costs it holy damage. On a boss that is a large damage gain; on trash it is a
-- wasted global cooldown.
--
-- Nothing tells us in advance which one we are about to get. So it is learned,
-- once per creature type, and remembered.
--
-- WHEN A VERDICT MAY BE RECORDED is the whole difficulty, and the rule is: only
-- when the cast actually resolved. Repentance is instant, so it cannot be
-- interrupted - but it can fail to leave at all (out of range, dropped) and then
-- it has taught us nothing. The proof that it resolved is that ITS COOLDOWN
-- STARTED. A resist resolves the cast but says nothing about immunity, so it
-- also voids the probe.
--
-- Without that gate, "no immune message arrived" would be read as "not immune",
-- and a boss would be recorded as ordinary trash forever on the strength of one
-- out-of-range press. That is the same mistake the warlock throttle and the
-- hunter's reapply timer each made once.
-- ============================================================
local REPENT_VERDICT_MAX = 300
-- How long after the cast the verdict is read. Long enough for the combat log
-- line and the cooldown to have registered, short enough to be the same fight.
local REPENT_PROBE_WAIT = 1.0

-- What we file the verdict under. The creature template id where ClassicAPI can
-- read it - that is what actually identifies a kind of mob - and the name only
-- as a fallback, since names are localised and can collide.
function M:RepentanceKey()
    local id = Aegis_SBR.UnitCreatureID and Aegis_SBR:UnitCreatureID("target")
    if id then return "id:" .. tostring(id) end
    local nm = UnitName("target")
    return nm and ("nm:" .. nm) or nil
end

function M:RepentanceMemory()
    if not AegisDB then return nil end
    if type(AegisDB.repentImmune) ~= "table" then AegisDB.repentImmune = {} end
    return AegisDB.repentImmune
end

-- true (immune, so the damage effect), false (crowd control), or nil (unknown).
function M:RepentanceVerdict()
    local mem = self:RepentanceMemory()
    local key = self:RepentanceKey()
    if not mem or not key then return nil end
    return mem[key]
end

function M:RepentanceRecord(key, immune)
    local mem = self:RepentanceMemory()
    if not mem or not key then return end
    if mem[key] ~= nil then return end
    -- Bounded the same way the hunter's immunity memory is: creature types are
    -- finite, so hitting the cap means something is wrong, and relearning costs
    -- one cast per type.
    local n = 0
    for _ in pairs(mem) do n = n + 1 end
    if n >= REPENT_VERDICT_MAX then AegisDB.repentImmune = {}; mem = AegisDB.repentImmune end
    mem[key] = immune and true or false
end

-- Read the verdict of a probe that has had time to resolve.
function M:RepentanceResolve()
    local pr = self.repentProbe
    if not pr then return end
    if (GetTime() - pr.t) < REPENT_PROBE_WAIT then return end
    self.repentProbe = nil
    -- Voided: a resist tells us nothing, and a cast that never left tells us
    -- less than that.
    if pr.voided then return end
    if not pr.immune then
        -- The cooldown is the proof the cast resolved. Not started means it
        -- never happened, so nothing is recorded and the type stays unknown.
        if Aegis_SBR:OwnCDReady("Repentance") then return end
    end
    self:RepentanceRecord(pr.key, pr.immune)
end

-- Should Repentance go out on this target at all?
--
--   immune      -> yes, it is a damage cooldown here
--   not immune  -> only to stop a cast, which is the one thing the crowd control
--                  is still worth a global cooldown for
--   unknown     -> probe, but only where the answer could pay for itself
--
-- The probe is deliberately NOT run on everything. The damage effect pays out
-- over twenty seconds of the enemy swinging; a trash mob that dies in five
-- cannot pay for it even when immune, so learning the answer there buys nothing
-- and costs a global cooldown per creature type.
function M:RepentanceWanted(cfg)
    local v = self:RepentanceVerdict()
    if v == true then return true, nil end
    if v == false then
        return Aegis_SBR:TargetIsCasting(), nil
    end
    if Aegis_SBR:TargetIsCasting() then return true, nil end   -- worth it regardless
    local cls = UnitClassification and UnitClassification("target")
    local tough = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    if not tough then
        local ttk = Aegis_SBR:TargetTTK()
        -- nil is "not known to be dying soon" and must not trigger a probe on
        -- its own; only a measured, long life does.
        if not (ttk and ttk >= (cfg.repentProbeTTK or 15)) then return false, nil end
    end
    return true, self:RepentanceKey()
end

-- Buffs that stop ALL damage.
--
-- These do NOT remove a paladin from the heal list. The bubble runs for ten
-- seconds and then the same low health bar is standing there without it, so the
-- free casting time is exactly when to top it up - just at low priority, behind
-- anyone actually taking damage (see IMMUNE_HANDICAP).
--
-- Self only, and that is not a shortcut: your own heals land on you through your
-- own Divine Shield, while somebody ELSE under one cannot be healed by you at
-- all. Detecting theirs would also mean guessing from an icon, and a false
-- positive would silently drop a group member from the heal list.
--
-- Hand of Protection is deliberately NOT here: it stops physical damage only,
-- so somebody under it can still be burned down by magic and still wants heals.
--
-- Only checked for the player. Our own buffs resolve by name exactly; another
-- unit's would have to be guessed from an icon, and a false positive there would
-- silently drop a group member from the heal list.
local IMMUNE_BUFFS = { "Divine Shield", "Divine Protection" }
function M:SelfInvulnerable()
    for i = 1, table.getn(IMMUNE_BUFFS) do
        if self:HasBuff(IMMUNE_BUFFS[i]) then return true end
    end
    return false
end

function M:Reachable(u)
    if UnitIsUnit(u, "player") then return true end
    -- Recently refused by the client (no line of sight, or out of range after
    -- IsSpellInRange could not judge). Never for yourself: you are always in
    -- your own line of sight, and a stale mark would drop you from your own
    -- heal list.
    if Aegis_SBR:CastBlocked(u) then return false end
    if self:KnowsSpell("Flash of Light") then return Aegis_SBR:SpellReaches("Flash of Light", u)
    elseif self:KnowsSpell("Holy Light") then return Aegis_SBR:SpellReaches("Holy Light", u) end
    return CheckInteractDistance(u, 4)
end

-- The healable group member with the lowest effective health below ratio,
-- counting our own in-flight heal. Returns unit, missing health, ratio.
-- Health handicap in PERCENTAGE POINTS, by position on the priority list.
-- Position 1 carries none, position 2 twenty, and anyone not on the list
-- thirty-five. A handicap makes a unit read as healthier than it is, so it only
-- decides near-ties - which is the case worth deciding. A dps at 20% still out-
-- ranks a tank at 90%; a tank at 60% now outranks a dps at 45%, which is the
-- "the tank only had minimally more health" case that loses fights.
local PRIO_HANDICAP = { 0, 20 }
local PRIO_OTHERS = 35

-- How long after losing health a unit still counts as in danger, and what not
-- being in danger costs. The window is generous on purpose: a gap between two
-- swings must not flip somebody out of danger mid-cast.
local DANGER_WINDOW = 4
local DANGER_HANDICAP = 25

-- What being invulnerable costs in the order. NOT a skip: the bubble lasts ten
-- seconds and then the same low health bar is standing there unprotected, so the
-- right move is to top them up while it is free - just behind anybody who is
-- actually being hit. Large enough that almost any real casualty outranks them.
local IMMUNE_HANDICAP = 40

-- Ceiling on the total. The handicaps are independent switches and were never
-- meant to be summed without limit: a bubbled, unlisted, undamaged player scored
-- 25 + 40 + 35 = 100 and so read as at FULL health whatever their real bar said,
-- which does not delay a heal, it cancels it. Priority may reorder the queue; it
-- may never remove somebody from it.
local HANDICAP_MAX = 50

-- Who currently has a mob's attention.
--
-- 1.12 has no threat API, but a unit token can be CHAINED: "party1target" is the
-- mob a party member is fighting, and "party1targettarget" is whoever that mob
-- is hitting back. Walking every group member's target and asking who it is
-- attacking therefore gives real aggro - no threat library, no retargeting, and
-- no SuperWoW needed. (UnitXP's enemy scan is not usable here: its verbs work by
-- changing your target and restoring it afterwards, which a rotation running
-- four times a second cannot do.)
--
-- The gap this leaves is real and is why the health test below stays: a mob
-- beating on somebody that NOBODY in the group has targeted is invisible here.
-- The two are independent positive signals and either one is enough.
local AGGRO_UNITS_PARTY = 4
local AGGRO_UNITS_RAID = 40

-- Identity of a unit: its GUID where SuperWoW provides one, its name otherwise.
-- A GUID is exact; a name is what 1.12 alone can offer.
local function unitKey(u)
    local ok, guid = UnitExists(u)
    if guid then return guid end
    return UnitName(u)
end

function M:ScanAggro(units)
    -- Who each group member is, looked up once.
    local keyOf, ofKey = {}, {}
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) then
            local k = unitKey(u)
            if k then keyOf[u] = k; ofKey[k] = u end
        end
    end

    -- Every visible enemy's victim, matched straight back to a group member.
    --
    -- Matching by identity through a lookup, not by comparing every victim
    -- against every member: that pairing cost eighty times forty comparisons per
    -- scan in a full raid, four times a second, and was one of two places that
    -- made this addon expensive exactly where frames are scarcest.
    local hit = {}
    local function consider(enemy)
        if not UnitExists(enemy) then return end
        if UnitIsDead(enemy) then return end
        if not UnitCanAttack(enemy, "player") then return end
        local v = enemy .. "target"
        if not UnitExists(v) then return end
        local k = unitKey(v)
        local u = k and ofKey[k]
        if u then hit[u] = (hit[u] or 0) + 1 end
    end

    consider("target")
    consider("mouseover")
    consider("pettarget")
    local nr = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if nr > 0 then
        if nr > AGGRO_UNITS_RAID then nr = AGGRO_UNITS_RAID end
        for i = 1, nr do
            consider("raid" .. i .. "target")
            consider("raidpet" .. i .. "target")
        end
    else
        for i = 1, AGGRO_UNITS_PARTY do
            consider("party" .. i .. "target")
            consider("partypet" .. i .. "target")
        end
    end
    self.aggroOn = hit
end

-- Health sampler plus the aggro scan. Throttled rather than run per press: the
-- preview window asks the same question four times a second, and in a full raid
-- the scan touches eighty unit tokens.
local DANGER_SCAN = 0.25
function M:SampleDanger(units)
    local now = GetTime()
    if self.dangerT and (now - self.dangerT) < DANGER_SCAN then return end
    self.dangerT = now
    self:ScanAggro(units)
    if not self.dangerHP then self.dangerHP = {} end
    if not self.dangerHit then self.dangerHit = {} end
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) then
            local nm = UnitName(u)
            if nm then
                local hp = UnitHealth(u)
                local prev = self.dangerHP[nm]
                if prev and hp < prev then self.dangerHit[nm] = now end
                self.dangerHP[nm] = hp
            end
        end
    end
end

-- In danger when something is attacking them, or when they have been losing
-- health. Two independent positive signals; either is enough, and neither can
-- push anybody DOWN the order on its own - that is what the handicap does.
function M:InDanger(unit)
    -- Aggro is keyed by unit token (identity), the health history by name - a
    -- name is the only key that survives from one scan to the next.
    if self.aggroOn and self.aggroOn[unit] then return true end
    local nm = UnitName(unit)
    if not nm or not self.dangerHit then return false end
    local t = self.dangerHit[nm]
    return (t and (GetTime() - t) <= DANGER_WINDOW) and true or false
end

-- How many mobs are on this unit, 0 when none are visible. Read-only; the
-- rotation does not use it yet, but it is what the trace shows.
function M:AggroCount(unit)
    if not self.aggroOn then return 0 end
    return self.aggroOn[unit] or 0
end

-- Total handicap for a unit in percentage points, 0 when nothing applies.
--
-- Three independent sources, added together: the priority list, your current
-- target, and whether the unit is actually taking damage. Each may only ever
-- make a unit look HEALTHIER, never more hurt, so no combination of them can
-- invent an emergency - and none of them is consulted for the emergency line,
-- which always reads real health.
function M:PrioHandicap(cfg, unit)
    local h = 0

    if cfg.healPrio then
        local list = cfg.healPrioList
        if list and table.getn(list) > 0 then
            local name = UnitName(unit)
            local found = nil
            if name then
                for i = 1, table.getn(list) do
                    if list[i] == name then found = PRIO_HANDICAP[i] or PRIO_OTHERS end
                end
            end
            h = h + (found or PRIO_OTHERS)
        end
    end

    -- A friendly target you selected yourself is the clearest statement of
    -- intent there is, so it overrides the list rather than adding to it.
    if cfg.healPrioTarget and UnitExists("target") and UnitIsFriend("player", "target")
        and UnitIsUnit(unit, "target") then
        h = 0
    end

    -- Invulnerable, or simply not being hit. These are ONE fact, not two: the
    -- bubble is what drops the aggro in the first place, so charging for both
    -- would be counting the same safety twice. The stronger of the two wins.
    local safe = 0
    if UnitIsUnit(unit, "player") and self:SelfInvulnerable() then
        safe = IMMUNE_HANDICAP
    elseif cfg.healAggro and not self:InDanger(unit) then
        safe = DANGER_HANDICAP
    end
    h = h + safe

    if h > HANDICAP_MAX then h = HANDICAP_MAX end
    return h
end

-- Chooses by ADJUSTED health, reports REAL health and the REAL deficit.
--
-- That split is the whole safety of the feature: the handicap may only ever
-- decide who gets the next cast, never how big it is, and never whether the
-- emergency line has been crossed. Everything downstream - Holy Shock, the
-- danger guard above Holy Strike, the rank cascade - keeps seeing the truth.
-- The smallest heal this paladin can actually cast, in points.
--
-- A deficit under this cannot be healed at all - every point of the cast is
-- overheal by construction, because rank 1 is the floor of the ladder. Not a
-- tuning value and not a guess: it is read from the same rank table and the same
-- +healing the rank picker uses.
function M:SmallestHeal()
    local hp = self:GearHealBonus()
    local e = self.FOL_RANKS[1]
    if self:MaxRank("Flash of Light") < 1 then e = self.HL_RANKS[1] end
    if not e then return 0 end
    local coeff = (e == self.FOL_RANKS[1]) and (1.5 / 3.5) or (2.5 / 3.5)
    return (e.base + coeff * hp * (e.pf or 1)) * self:HealTalentMod()
end

-- Answered once per press.
--
-- Six call sites reach this, several of them in the same press, and each answer
-- walks the whole group reading health, incoming heals, reachability and the
-- priority handicaps. Repeating that for an answer that cannot have changed
-- between two steps of one press is pure cost, and in a forty-man raid it is the
-- shape of cost this addon has been bitten by before.
--
-- Keyed by the arguments that change the answer: the threshold, and whether a
-- profile was passed at all (without one there are no handicaps, no pets and no
-- self threshold, so it is a genuinely different question). The token is bumped
-- where the rotation is invoked, so a stale answer cannot survive a press.
function M:WorstHurt(ratio, cfg)
    local tok = Aegis_SBR.pressToken
    local key = tostring(ratio) .. (cfg and "|c" or "|-")
    if tok and self.whToken == tok then
        local hit = self.whCache and self.whCache[key]
        if hit then return hit[1], hit[2], hit[3] end
    else
        self.whToken, self.whCache = tok, {}
    end
    local u, def, pct = self:WorstHurtNow(ratio, cfg)
    if tok then
        if not self.whCache then self.whCache = {} end
        self.whCache[key] = { u, def, pct }
    end
    return u, def, pct
end

function M:WorstHurtNow(ratio, cfg)
    local pets = cfg and (cfg.petPriority or 1) > 0
    local units = self:GroupUnits(pets, cfg)
    if cfg and (cfg.healAggro or cfg.healPrecast) then self:SampleDanger(units) end

    -- Players and pets are judged separately, because a pet may only take the
    -- cast under conditions a player never has to meet (see petPriority).
    -- Eligibility is decided on REAL health, ranking on ADJUSTED health. Keeping
    -- those apart is the whole safety of the priority system: a handicap may
    -- reorder the queue, it may never push somebody out of it.
    --
    -- Both were the same test before, and the arithmetic then quietly excluded
    -- people: an unlisted, undamaged player at 60% health carried +50 points and
    -- so read as 110%, which is above any threshold - so with the party full and
    -- one member at 60%, nothing was healed at all. That is the "sometimes it
    -- won't heal me even when the party is full" report, and it was never about
    -- the self threshold.
    local bestU, bestPct, bestDef, bestReal = nil, 99, 0, nil
    local petU, petPct, petDef, petReal = nil, 99, 0, nil
    local selfU, selfDef, selfReal = nil, 0, nil
    -- Whether the current best candidate is below the threshold for real, or is
    -- only there as a pre-heal.
    local bestReal2 = false
    local anyPlayerHurt = false

    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsFriend("player", u) and UnitHealthMax(u) > 0 and self:Reachable(u)
            and not self:GroupFiltered(cfg, raidIndex(u)) then
            local mx = UnitHealthMax(u)
            -- Our own heal in flight, plus whatever other healers have coming.
            local cur = UnitHealth(u) + self:PendingFor(u) + self:IncomingHeal(u)
            if cur > mx then cur = mx end
            local pct = cur / mx
            local pet = isPetUnit(u) and true or false

            local skip = false
            -- Your own health has its own threshold: a healer can usually step
            -- out of trouble instead of spending a cast on themselves.
            --
            -- Only while somebody ELSE could use that cast, though. Held
            -- unconditionally it produced the exact complaint "everyone was
            -- fully healed, I was at 50%, and it refused to heal me" - the
            -- threshold is about not stealing a cast from the group, not about
            -- staying hurt in an empty room. Remembered here and used at the
            -- bottom if nothing else wants healing.
            if cfg and (cfg.healSelfPct or 0) > 0 and UnitIsUnit(u, "player")
                and pct > (cfg.healSelfPct / 100) then
                skip = true
                -- Remembered as a fallback ONLY while genuinely below the heal
                -- threshold. Without that second condition the fallback fired at
                -- full health: being above the self threshold is true at 100%
                -- too, so the player came back as a target with a deficit of
                -- zero, and the rank ladder then cast its floor rank over and
                -- over. That is the idle self-healing.
                if pct < ratio then
                    selfU, selfDef, selfReal = u, mx - cur, pct
                end
            end


            local adj = pct
            if cfg then
                adj = pct + (self:PrioHandicap(cfg, u) / 100)
                if adj > 1 then adj = 1 end
            end

            -- Pre-heal: something is already hitting them, so a deficit counts
            -- even above the threshold that would normally ignore it. Never for
            -- a full-health unit - there is nothing to heal.
            local precast = false
            if cfg and cfg.healPrecast and not pet and pct < 1 and self:InDanger(u) then
                precast = true
            end

            -- A friendly unit you selected yourself outranks EVERYTHING: the
            -- other switches, the pet rules, the thresholds. Clicking somebody
            -- is the one unambiguous instruction the rotation ever gets, and it
            -- used to lose to the pet/player split - a targeted pet was passed
            -- over for any player below the threshold.
            if cfg and cfg.healPrioTarget and pct < 1 and not skip
                and UnitExists("target") and UnitIsFriend("player", "target")
                and UnitIsUnit(u, "target") then
                return u, mx - cur, pct
            end

            -- Below the threshold, or hurt enough that a pre-heal would land
            -- something. The size test is what stopped the pre-heal from firing
            -- on anybody who had taken a single hit in the last few seconds: at
            -- 99% health the whole cast is overheal, so it is not a heal.
            local deficit = mx - cur
            local eligible = (pct < ratio)
                or (precast and deficit >= self:SmallestHeal())
            if not skip and eligible then
                if pet then
                    if petU == nil or adj < petPct then
                        petPct = adj; petU = u; petDef = mx - cur; petReal = pct
                    end
                else
                    -- A pre-heal is a filler: it may take the press only when
                    -- nobody is actually below the threshold. Ranked behind
                    -- every real casualty, never in front of one.
                    local real = (pct < ratio)
                    if real then anyPlayerHurt = true end
                    local better = (bestU == nil) or (real and not bestReal2)
                        or ((real == (bestReal2 or false)) and adj < bestPct)
                    if better then
                        bestPct = adj; bestU = u; bestDef = deficit; bestReal = pct
                        bestReal2 = real
                    end
                end
            end
        end
    end

    if bestU then return bestU, bestDef, bestReal end

    -- No player wants the cast. A pet gets it when it is ranked equal to
    -- players, when nobody else needs healing, or when you have targeted it.
    if petU and cfg then
        local prio = cfg.petPriority or 1
        if prio >= 2 or (prio == 1 and not anyPlayerHurt)
            or (UnitExists("target") and UnitIsUnit(petU, "target")) then
            return petU, petDef, petReal
        end
    end

    -- Nobody else wants the cast, so the self threshold has nothing to protect.
    if selfU then return selfU, selfDef, selfReal end
    return nil, 0, nil
end

-- True while healing is needed, so the attack rotation yields. Uses real health
-- (no in-flight prediction) so a heal already on the way still counts as demand
-- and keeps a Seal of Wisdom judgement from stealing the global cooldown.
-- RETIRED, kept only because the damage rotation's comments still refer to the
-- idea. It used to yield the whole press whenever anybody was below the heal
-- threshold, including when DoHeal had just failed to produce a cast - so a
-- paladin who could not afford a heal stood still instead of meleeing, and the
-- mana that would have paid for the heal never came back. Nothing calls it.
function M:HealDemand(cfg)
    if self.healUntil and GetTime() < self.healUntil then return true end
    local ratio = (cfg.healThreshold or 75) / 100
    local units = self:GroupUnits()
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsFriend("player", u) and UnitHealthMax(u) > 0 and self:Reachable(u) then
            if UnitHealth(u) / UnitHealthMax(u) < ratio then return true end
        end
    end
    return false
end

-- Healing talent modifiers: Healing Light +4%/rank, Divine Favor ~5%/rank.
-- Is any of these buff textures on the player? Texture matching is what makes
-- proc detection locale proof: the icon path is the same on every client, the
-- buff name is not.
function M:BuffTextureUp(frags)
    if not GetPlayerBuffTexture then return false end
    for i = 0, 31 do
        local ix = GetPlayerBuff(i, "HELPFUL")
        if not ix or ix == -1 then break end
        local tex = GetPlayerBuffTexture(ix)
        if tex then
            for j = 1, table.getn(frags) do
                if string.find(string.lower(tex), string.lower(frags[j]), 1, true) then return true end
            end
        end
    end
    return false
end

-- Every talent that scales a heal, as one multiplier: Healing Light (+4%/rank)
-- and Holy Power (+0.5%/rank, the crit talent's average contribution).
function M:HealTalentMod()
    local _, _, _, _, hlRank = GetTalentInfo(1, 6)
    local _, _, _, _, hpRank = GetTalentInfo(1, 15)
    return (1 + 0.04 * (hlRank or 0)) * (1 + 0.005 * (hpRank or 0))
end

-- RETIRED as a heal multiplier. Kept for reference only: the second return is
-- Divine Favor, a CRIT talent, and treating it as extra healing is what made
-- Holy Shock read 20% too large. Nothing calls this.
function M:HealMods()
    local _, _, _, _, hlRank = GetTalentInfo(1, 6)
    local _, _, _, _, dfRank = GetTalentInfo(1, 13)
    return 1 + 0.04 * (hlRank or 0), 1 + 0.05 * (dfRank or 0)
end

-- Effective heal per rank: base + healing-coefficient * bonus, then talents.
-- `pen` is the optional per-rank +healing penalty for ranks learnt below level
-- 20 (see HL_PEN). It scales ONLY the gear-bonus part, never the base heal,
-- which is what makes a downranked heal stop keeping pace with gear.
function M:EffHeals(baseHeals, coeff, mods, healPower, pen)
    local t = {}
    for r = 1, table.getn(baseHeals) do
        local p = 1
        if pen and pen[r] then p = pen[r] end
        t[r] = (baseHeals[r] + coeff * (healPower or 0) * p) * mods
    end
    return t
end

-- Pick the smallest affordable rank whose effective heal covers the deficit;
-- fall back to the largest affordable rank. Returns a castable spell + heal.
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

-- Cast a heal on a specific unit without changing the current target
-- (SuperWoW's unit argument to CastSpellByName).
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

-- True when the global cooldown is free, probed through a cooldown-less paladin
-- spell so the only cooldown reported is the global one.
function M:GcdReady()
    local probes = { "Flash of Light", "Holy Light", "Seal of Righteousness", "Seal of Wisdom", "Seal of the Crusader" }
    for i = 1, table.getn(probes) do
        if self:KnowsSpell(probes[i]) then return self:IsReady(probes[i]) end
    end
    return true
end

-- Known texture fragments for effects that reduce healing received on a unit
-- (Mortal-Strike-type debuffs), detected by icon.
-- Value is the healing multiplier applied per stack found.
local HEAL_DEBUFF = {
    { frag = "Ability_CriticalStrike",     mult = 0.5 },  -- Mortal Wound
    { frag = "Ability_Warrior_SavageBlow", mult = 0.5 },  -- Mortal Strike / Mortal Cleave (Warrior talent)
    { frag = "Spell_Shadow_GatherShadows", mult = 0.5 },  -- Curse of the Deadwood / Gehenna's Curse
    { frag = "Ability_Creature_Poison_03", mult = 0.9 },  -- Necrotic Poison
}

-- Combined healing-reduction multiplier on a unit from known debuffs (1 = no
-- reduction). The heal engine divides the deficit by this before picking a
-- rank, so a target under Mortal Strike gets a correspondingly bigger heal
-- queued up instead of quietly landing short.
function M:HealDebuffModifier(unit)
    local mult = 1
    for i = 1, 16 do
        local tex = UnitDebuff(unit, i)
        if not tex then break end
        for j = 1, table.getn(HEAL_DEBUFF) do
            if string.find(tex, HEAL_DEBUFF[j].frag) then mult = mult * HEAL_DEBUFF[j].mult end
        end
    end
    return mult
end

-- Pick a rank inside one spell's ladder.
--
-- Walks upward and keeps the last rank whose padded heal is still smaller than
-- what the target is missing, so the cast lands just under the deficit. Rank 1
-- is the floor whenever it is affordable, `minRank` forces at least that rank
-- regardless of need, and `maxRank` caps the top.
--
-- The padding is the cast-time compensation: the target keeps losing health
-- while the cast is in flight, so a slow heal is judged against 80% of its size
-- and a fast one against 90%. Out of combat there is nothing to compensate.
function M:SelectRank(ranks, known, healneed, mana, healMod, talentMod, pad, minRank, maxRank)
    local pick, size
    for i = 1, table.getn(ranks) do
        local e = ranks[i]
        if e.rank <= known and e.rank <= (maxRank or 99) and mana >= e.mana then
            local total = (e.base + healMod * (e.pf or 1)) * talentMod
            if i == 1 or healneed > (total * pad) or e.rank <= (minRank or 1) then
                pick, size = e.rank, total
            end
        end
    end
    return pick, size
end

-- Which spell, then which rank. Pure: no casting, no state. DoHeal and the trace
-- both call it, so the line in the log can never describe a different rule than
-- the one that actually chose the spell.
-- Returns spell string, effective heal, cast time.
function M:CascadePick(cfg, rankDeficit, pct, mana, hlFast)
    local hlCast = hlFast and 1.5 or 2.5
    local hp = (cfg.healPower and cfg.healPower > 0) and cfg.healPower or self:GearHealBonus()
    local talentMod = self:HealTalentMod()
    local folMod = (1.5 / 3.5) * hp
    local hlMod  = (2.5 / 3.5) * hp

    local folKnown = self:MaxRank("Flash of Light")
    local hlKnown  = self:MaxRank("Holy Light")
    if folKnown > table.getn(self.FOL_RANKS) then folKnown = table.getn(self.FOL_RANKS) end
    if hlKnown  > table.getn(self.HL_RANKS)  then hlKnown  = table.getn(self.HL_RANKS) end
    local noFL = folKnown < 1

    -- In combat the deficit is compared against a discounted heal, because the
    -- target keeps losing health while the cast flies.
    local inCombat = UnitAffectingCombat("player")
    local padFast = inCombat and 0.9 or 1.0
    local padSlow = inCombat and 0.8 or 1.0

    -- Step 1: which spell. The biggest Flash of Light this paladin knows decides
    -- it - if that covers the need, the long cast is not worth its time.
    local maxFL = 0
    if folKnown >= 1 then
        local e = self.FOL_RANKS[folKnown]
        maxFL = (e.base + folMod) * talentMod
    end
    local flCovers = (folKnown >= 1) and (maxFL >= rankDeficit)
    local healthy = pct >= ((cfg.ratioHealthy or 60) / 100)
    -- Holy Judgement (hlFast) is the exception to the HEALTH condition, not to
    -- the size one. Treating it as a blanket override is how a full-strength
    -- paladin cast Holy Light rank 1 on a scratch: the buff forced the slow-heal
    -- branch, and the rank ladder then picked its floor because the deficit was
    -- tiny. A fast Holy Light is still the wrong tool when a Flash of Light
    -- covers the need outright.
    local useHL = noFL or ((not healthy or hlFast) and (not flCovers))

    local rank, size
    if useHL then
        rank, size = self:SelectRank(self.HL_RANKS, hlKnown, rankDeficit, mana, hlMod,
            talentMod, padSlow, cfg.hlMinRank, cfg.hlMaxRank)
        if rank then return "Holy Light(Rank " .. rank .. ")", size, hlCast end
    end
    rank, size = self:SelectRank(self.FOL_RANKS, folKnown, rankDeficit, mana, folMod,
        talentMod, padFast, cfg.folMinRank, cfg.folMaxRank)
    if rank then return "Flash of Light(Rank " .. rank .. ")", size, 1.5 end
    -- Flash of Light unaffordable or unknown: Holy Light is better than nothing.
    if not useHL then
        rank, size = self:SelectRank(self.HL_RANKS, hlKnown, rankDeficit, mana, hlMod,
            talentMod, padSlow, cfg.hlMinRank, cfg.hlMaxRank)
        if rank then return "Holy Light(Rank " .. rank .. ")", size, hlCast end
    end
    return nil, nil, nil
end

-- Heal decision. Returns true when a heal was cast (or the GCD is held) this
-- press. Holy Shock for an emergency or an out-of-range unit, otherwise a
-- downranked Flash of Light, with Holy Light for large deficits - unless the
-- target is below the emergency line, where Flash of Light's faster cast
-- stays the safer bet even if it cannot fully cover the deficit.
function M:DoHeal(cfg)
    local ratio = (cfg.healThreshold or 75) / 100
    local unit, deficit, pct = self:WorstHurt(ratio, cfg)
    if not unit then return false end
    -- Nothing worth casting. A deficit smaller than the smallest heal we own is
    -- pure overheal by construction, so this is not a threshold to tune - it is
    -- the point below which "healing" stops meaning anything. Kept here as well
    -- as in the selection, because every path that can pick a target passes
    -- through this one.
    if deficit <= 0 or deficit < self:SmallestHeal() then return false end

    -- A heal is needed but the GCD still blocks a cast: yield without casting or
    -- predicting, so the attack rotation does not run and no false in-flight
    -- heal masks the target. The heal fires the instant the GCD frees.
    if not self:GcdReady() then return true end
    -- Also yield while our own last heal is still expected to be casting,
    -- even if the GCD itself has already cleared (Holy Light's 2.5s cast
    -- outlasts the 1.5s GCD) - otherwise a spammed press in that gap can
    -- start a second heal on a target whose HP hasn't caught up yet.
    if self:StillCasting() then return true end

    local mana = UnitMana("player")
    local hp = (cfg.healPower and cfg.healPower > 0) and cfg.healPower or self:GearHealBonus()
    -- Only Holy Shock still needs a precomputed table; the two direct heals are
    -- chosen inside CascadePick from their own rank ladders.
    -- Divine Favor is NOT in here, and that is the correction: it raises Holy
    -- Shock's CRIT CHANCE, not the size of a cast that does not crit. Folding it
    -- in as a flat multiplier inflated every prediction by 5% per rank.
    --
    -- Measured, 2026-08-23: gear bonus 40, Holy Shock rank 3. The model said 724
    -- against three non-crit landings of 587 / 576 / 567 - a 20% overestimate,
    -- exactly the 1.25 of Divine Favor at 5/5. Without it: 579 predicted against
    -- 576 measured, 0.6% out. The two crits in the same capture landed 871 and
    -- 886, a factor of ~1.5 on the non-crit value, which is the crit multiplier
    -- doing its own separate job.
    --
    -- A crit is a bonus, never something a rank choice may count on: predicting
    -- the average would pick a rank too small and underheal whenever it does not
    -- crit.
    local hsEff = self:EffHeals(self.HS_HEAL, 1.5 / 3.5, self:HealTalentMod(), hp)

    -- Healing-reduction debuffs (Mortal Strike and the like) inflate the
    -- effective deficit for rank selection, so a stronger rank is picked;
    -- the amount actually committed for in-flight tracking is scaled back
    -- down since the extra healing never lands.
    local hdb = self:HealDebuffModifier(unit)
    local rankDeficit = (hdb < 1) and (deficit / hdb) or deficit

    -- ForceHL: a buff that makes the long heal cheap in time, so Holy Light
    -- stops being a risk however hurt the target is. Holy
    -- Judgement takes a second off it; Hand of Edward the Odd makes the next
    -- spell instant. Both are the stated exception to the Holy Light gate below.
    --
    -- Detected by TEXTURE first - locale proof and independent of a spell id
    -- resolving. The name check stays as a second positive source; either one
    -- saying yes is enough.
    --
    -- It also corrects the cast time handed to CommitHeal, which otherwise
    -- claimed 2.5s for a 1.5s cast and blocked the next press for the difference.
    --
    -- NOT the healing coefficient (2.5/3.5) further up: that follows the spell's
    -- BASE cast time and does not move with a talent.
    local hlFast = self:BuffTextureUp(FORCE_HL_TEX) or self:HasBuff("Holy Judgement")
    local hlCast = hlFast and 1.5 or 2.5

    -- Holy Shock: instant, for an emergency or a hurt unit out of melee range.
    -- Holy Shock's own range (20yd) is shorter than Flash of Light/Holy
    -- Light's (40yd); IsSpellInRange gives an exact answer (the same API the
    -- default action bar and hotbar addons use to red-tint an out-of-range
    -- icon), so it gates the actual cast precisely - a target between 20 and
    -- 40yd now correctly falls straight through to Flash of Light/Holy Light
    -- below instead of wasting the press on a Holy Shock that would have
    -- failed to reach (this was the bug: previously nothing was cast at all
    -- for a hurt unit sitting in that 20-40yd gap).
    if cfg.useHolyShock and self:KnowsSpell("Holy Shock") and self:OwnCDReady("Holy Shock")
        -- Below the emergency line. That line, and nothing else.
        --
        -- There used to be a second way in: "or the target is further than ten
        -- yards away", on the reasoning that only an instant heal reaches
        -- somebody out of MELEE range. That reasoning does not survive contact
        -- with a healer - Flash of Light and Holy Light both reach forty yards,
        -- so melee range has nothing to do with whether a normal heal lands.
        -- What the clause actually said was "anybody standing more than ten
        -- yards away", which in a party is most people and in a raid is nearly
        -- everybody: the emergency instant fired on any hurt group member at any
        -- health, and the slider it is configured with meant nothing. Reported
        -- as "I set Holy Shock to below 50% but the rotation spams it way
        -- earlier". Melee range still decides one thing, the Holy Strike splash,
        -- and it is checked there.
        --
        -- An earlier round of the same defect narrowed that clause to exclude
        -- the player, because CheckInteractDistance gives no usable answer about
        -- yourself and so read as "far away" - which put Holy Shock on the
        -- paladin at full health. Narrowing it was treating the symptom; the
        -- clause itself was the fault.
        and pct <= (cfg.holyShockPct or 50) / 100
        and Aegis_SBR:SpellReaches("Holy Shock", unit) then
        local hs, amt = self:PickRank("Holy Shock", hsEff, self.HS_MANA, rankDeficit, mana)
        if hs then
            self:CommitHeal(unit, amt * hdb, 0, hs, deficit)
            self:CastOn(hs, unit)
            return true
        end
    end

    local pick, pickEff, castTime = self:CascadePick(cfg, rankDeficit, pct, mana, hlFast)
    local amt = pick and (pickEff or 0) * hdb or nil

    if pick then self:CommitHeal(unit, amt, castTime, pick, deficit); self:CastOn(pick, unit); return true end
    return false
end

-- Heal mode runs even without an attackable target, so the paladin can heal at
-- range. The core's RunRotation honors this hook.
function M:RunsWithoutTarget(cfg)
    return cfg.healMode == true
end

-- ------------------------------------------------------------
-- Melee-holy strike weaving (heal mode). Turtle's Holy paladin fights in
-- melee: Holy Strike splash-heals the group, and with Blessed Strikes
-- (100% at 5/5) Crusader Strike resets Holy Shock, keeping the emergency
-- instant permanently loaded. These are two independent behaviours, each on
-- its own toggle, because each cast spends a global cooldown.
-- ------------------------------------------------------------
function M:HealMeleeReady(cfg)
    if not (UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")) then return false end
    if not self:InMeleeRange() then return false end
    if not self:GcdReady() then return false end
    -- A strike here would interrupt a still-resolving Holy Light cast (2.5s,
    -- longer than the 1.5s GCD) - see StillCasting.
    if self:StillCasting() then return false end
    return true
end

-- True when the Crusader Strike -> Holy Shock reset can actually work.
function M:BlessedReloadUsable()
    return self:TalentRank(TALENT_BLESSED) > 0
        and self:KnowsSpell("Crusader Strike")
        and self:KnowsSpell("Holy Shock")
end

-- Toggle A - Reload Holy Shock (CS): when Holy Shock is on cooldown, weave
-- Crusader Strike to reset it (Blessed Strikes), keeping the emergency instant
-- loaded. Runs even between heals while people are hurt, but NEVER while anyone
-- is below the Holy Shock emergency line - a critical member gets the heal
-- first. Not gated by the filler mana floor, since keeping the emergency loaded
-- is the priority. Auto-detects the talent.
function M:HealStrikeEngine(cfg)
    if not cfg.healReloadCS then return false end
    if not cfg.useHolyShock then return false end
    if not self:BlessedReloadUsable() then return false end
    if self:OwnCDReady("Holy Shock") then return false end          -- already loaded
    if not self:IsReady("Crusader Strike") then return false end
    local _, _, pct = self:WorstHurt((cfg.healThreshold or 75) / 100)
    if pct and pct <= (cfg.holyShockPct or 50) / 100 then return false end
    if not self:HealMeleeReady(cfg) then return false end
    return self:CastStrike("Crusader Strike", cfg)
end

-- Heal-mode mana upkeep. Keeps Seal of Wisdom up so melee swings return mana to
-- you, and optionally judges it once per mob (Judgement of Wisdom) so the whole
-- group gets mana back. Only worthwhile in melee on an attackable mob. Heals
-- always preempt this above, so it never runs while anyone needs healing - but
-- the group judge still spends a GCD, hence it is opt-in.
-- Keep Seal of Wisdom up. A SELF BUFF: it needs no target, no enemy and no
-- melee range - it needs a global cooldown and nothing else.
--
-- It used to sit behind all three of those checks, and behind the rotation's
-- "no attackable target, stop here" guard on top, so a healer standing back
-- with nothing targeted never refreshed it at all. That is the reported "Seal of
-- Wisdom uptime is pretty bad sometimes": not a priority problem, a requirement
-- that was never true for the thing it guarded.
function M:HealSealUp(cfg)
    if not cfg.healManaSelf then return false end
    if not self:KnowsSpell("Seal of Wisdom") then return false end
    if self:HasBuff("Seal of Wisdom") then return false end
    if not self:Affordable("Seal of Wisdom") then return false end
    return self:Pick("Seal of Wisdom", "self mana")
end

-- Stamp Judgement of Wisdom on the mob, so the whole group gets mana back. This
-- one really does need a target in melee range, and the seal on you to judge.
function M:HealSeals(cfg)
    if not cfg.healManaJudge then return false end
    if not self:KnowsSpell("Seal of Wisdom") then return false end
    if not (UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")) then return false end
    if not self:InMeleeRange() then return false end
    if not self:HasBuff("Seal of Wisdom") then return false end
    if cfg.healManaJudge and self:KnowsSpell("Judgement") and self:IsReady("Judgement")
        and not self:DebuffEffectivelyUp("Seal of Wisdom") then
        if not self:Affordable("Judgement") then return false end
        return self:Pick("Judgement", "judge the seal")
    end
    return false
end

-- Pre-load the Holy Judgement buff during a lull, so the next Holy Light casts
-- in 1.5s instead of 2.5s.
--
-- The timing is the whole point, and it is why this belongs in the lull and
-- nowhere else. Judging in ORDER to speed up a heal that is already due is a net
-- loss: the judgement costs a global cooldown, so 1.5s + 1.5s is slower than
-- simply casting the 2.5s Holy Light. Cast while nobody needs healing, the
-- global cooldown was free anyway and the next emergency lands a second sooner.
--
-- Often redundant, deliberately so: HealSeals above already casts Judgement when
-- the group-mana judge is enabled and the debuff is missing, and that cast grants
-- this buff for free. This step only earns its place when that one is switched
-- off, or when the debuff is already stamped and the buff has since been spent.
function M:HealJudgeBuff(cfg)
    if not cfg.healJudgeHL then return false end
    if not self:KnowsSpell("Judgement") then return false end
    if not self:KnowsSpell("Holy Light") then return false end
    if self:HasBuff("Holy Judgement") then return false end
    if not self:IsReady("Judgement") then return false end
    if not (UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")) then return false end
    if not self:InMeleeRange() then return false end
    if not self:Affordable("Judgement") then return false end
    return self:Pick("Judgement", "pre-load Holy Judgement")
end

-- Holy Strike triggers on how many people are hurt, not on whether anybody is
-- hurt ENOUGH to warrant a direct heal.
--
-- This is the correction the reports kept pointing at from both ends. Holy
-- Strike is a splash heal, so its worth is a headcount: three people at 93% are
-- worth more than a Flash of Light on one of them, and none of them is hurt
-- enough for the heal threshold to notice. It used to sit below the heal gate,
-- where it only ever ran when NOBODY needed healing - fine while levelling,
-- where that is most of the time, and useless in a dungeon taking steady damage,
-- which is exactly the split the two play reports described.
--
-- Deliberately no mana floor. Ours had one at 40%, which switched off a
-- mana-RETURNING ability precisely when mana ran short.
function M:HolyStrikeDue(cfg)
    if not cfg.healSplashHS then return false end
    if not self:KnowsSpell("Holy Strike") then return false end
    if not self:IsReady("Holy Strike") then return false end
    if not self:HealMeleeReady(cfg) then return false end
    local thr = (cfg.hsMinHP or 100) / 100
    local units = self:GroupUnits(false, cfg)
    local n = 0
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsFriend("player", u) and UnitHealthMax(u) > 0
            -- 10 yards, via CheckInteractDistance(unit, 3). Holy Strike's splash
            -- does not reach further.
            --
            -- YOURSELF exempt from the distance test: CheckInteractDistance is
            -- an interaction range to ANOTHER unit and gives no useful answer
            -- about the player. Counted through it, the paladin standing in the
            -- middle of his own splash was left out of his own headcount - one
            -- short of a threshold of three, every time. The same exemption
            -- Reachable already makes for the heal itself.
            and (UnitIsUnit(u, "player") or CheckInteractDistance(u, 3)) then
            if UnitHealth(u) / UnitHealthMax(u) <= thr then n = n + 1 end
        end
    end
    return n >= (cfg.hsMinTargets or 1)
end

-- What this paladin can remove, best spell first. Cleanse covers all three;
-- Purify is the low-level version without Magic.
M.CURES = {
    { spell = "Cleanse", types = { Poison = true, Disease = true, Magic = true } },
    { spell = "Purify",  types = { Poison = true, Disease = true } },
}
M.cureFail = {}

-- The group, ordered the way the heal priority orders it: your friendly target
-- first, then the priority list in its own order, then everyone else in roster
-- order.
--
-- Dispelling reuses the list rather than carrying one of its own, because it is
-- the same statement about the same people - a poison on the tank matters for
-- the same reason a heal on the tank does. It is used whenever the list has
-- entries; the heal-priority SWITCH governs the health handicap, which is a
-- weighting and has no meaning for an affliction that is simply there or not.
--
-- Within one affliction type this decides who gets it first; the type order
-- itself is decided in the core and comes first.
function M:CureUnitOrder(cfg)
    local units = self:GroupUnits(false, cfg)
    local list = cfg.healPrioList
    local wantTarget = cfg.healPrioTarget and UnitExists("target")
        and UnitIsFriend("player", "target")
    if not wantTarget and (not list or table.getn(list) == 0) then return units end

    local out, taken = {}, {}
    local function add(u)
        if u and not taken[u] then taken[u] = true; table.insert(out, u) end
    end

    if wantTarget then
        for i = 1, table.getn(units) do
            if UnitExists(units[i]) and UnitIsUnit(units[i], "target") then add(units[i]) end
        end
    end
    if list then
        for r = 1, table.getn(list) do
            for i = 1, table.getn(units) do
                local u = units[i]
                if UnitExists(u) and UnitName(u) == list[r] then add(u) end
            end
        end
    end
    for i = 1, table.getn(units) do add(units[i]) end
    return out
end

-- Cure somebody, if there is nothing more pressing.
--
-- The threshold is a CROSSOVER, not an on/off: above it the affliction outranks
-- the missing health, below it the heal does. That is the whole setting - a
-- player who wants curing to always yield sets it to 0, one who wants it to
-- always come first sets it to 100.
function M:CureStep(cfg, worst)
    if not cfg.useCure then return false end
    if not self:GcdReady() or self:StillCasting() then return false end
    -- Somebody is hurt enough that the heal comes first.
    if worst and worst < ((cfg.curePct or 90) / 100) then return false end
    local unit, spell = Aegis_SBR:PickCure(Aegis_SBR:AppendPets(self:CureUnitOrder(cfg)), self.CURES,
        function(u) return self:Reachable(u) end, self.cureFail)
    if not unit or not spell then return false end
    if not self:Affordable(spell) then return false end
    self:Later(function() self.cureFail[UnitName(unit) or "?"] = GetTime() end)
    self:CastOn(spell, unit)
    return true
end

-- Last resort: stop everything and become invulnerable.
--
-- Above every other step in the rotation, healing included, because a heal that
-- is still casting when you die was not worth starting. Divine Shield first,
-- Divine Protection as the fallback for a paladin who has not learned it yet -
-- both are instant and neither costs a global cooldown worth worrying about.
--
-- Skipped while one is already up, and while Forbearance blocks a new one: the
-- cast would fail and the press would be spent on nothing.
function M:PanicShield(cfg)
    if (cfg.panicPct or 0) <= 0 then return false end
    -- Out of combat a low health bar is not an emergency, it is lunch. Bubbling
    -- there burns a five minute cooldown for nothing - reported exactly that
    -- way: "I was out of combat and just bubbled myself for no reason".
    if not UnitAffectingCombat("player") then return false end
    local mx = UnitHealthMax("player")
    if not mx or mx <= 0 then return false end
    if (UnitHealth("player") / mx) > (cfg.panicPct / 100) then return false end
    if self:SelfInvulnerable() then return false end
    if self:HasBuff("Forbearance") then return false end
    if self:KnowsSpell("Divine Shield") and self:OwnCDReady("Divine Shield")
        and self:Affordable("Divine Shield") then
        return self:Pick("Divine Shield", "emergency")
    end
    if self:KnowsSpell("Divine Protection") and self:OwnCDReady("Divine Protection")
        and self:Affordable("Divine Protection") then
        return self:Pick("Divine Protection", "emergency")
    end
    return false
end

-- Lay on Hands on yourself, as the tank's last resort.
--
-- Not gated on Forbearance: Lay on Hands is not part of that group on this
-- client, and if that ever changed the cast would simply fail without consuming
-- the cooldown. It does drain your mana, which is why it sits below every other
-- answer and behind a threshold you set yourself.
function M:PanicLayOnHands(cfg)
    if (cfg.tankLohPct or 0) <= 0 then return false end
    if not UnitAffectingCombat("player") then return false end
    -- Never on top of a bubble. Both thresholds can be crossed at once, and the
    -- shield fires first - so without this the next press spent an HOUR-long
    -- cooldown healing somebody who cannot currently be damaged. While
    -- invulnerable there is nothing to heal against; when it drops, this fires
    -- on its own if the health is still low enough.
    if self:SelfInvulnerable() then return false end
    if not self:KnowsSpell("Lay on Hands") then return false end
    local mx = UnitHealthMax("player")
    if not mx or mx <= 0 then return false end
    if (UnitHealth("player") / mx) > (cfg.tankLohPct / 100) then return false end
    if not self:OwnCDReady("Lay on Hands") then return false end
    return Aegis_SBR:CastOnUnit("Lay on Hands", "player", "emergency")
end

-- Heal yourself while the bubble holds.
--
-- Runs above everything except the emergencies themselves, and only while
-- actually invulnerable - the count is a ceiling on how much of the window to
-- spend, not a queue that keeps firing after it ends. Stops early at full
-- health, because the point is the health and not the casts.
--
-- Uses the ordinary heal engine aimed at the player, like Solofarming does, so
-- rank choice and Holy Judgement behave exactly as everywhere else.
function M:PanicHeal(cfg)
    local goal = cfg.panicHealTo or 0
    if goal <= 0 then return false end
    if not self:SelfInvulnerable() then return false end

    local mx = UnitHealthMax("player")
    if not mx or mx <= 0 then return false end
    if (UnitHealth("player") / mx) >= (goal / 100) then return false end

    -- The ordinary heal engine, aimed at the player and told to stop at the
    -- goal. Nothing here counts casts or remembers anything between presses:
    -- the health bar is the state, so there is nothing to get out of step.
    local win = { spec = "solo", healThreshold = goal, healSelfPct = 0 }
    for k, v in pairs(cfg) do if win[k] == nil then win[k] = v end end
    return self:DoHeal(win)
end

function M:Rotate(cfg)
    -- The panel writes `spec`; everything below branches on `healMode`. Deriving
    -- it here rather than in the tab handler keeps the two in step no matter how
    -- the profile was changed - slash command, tab click, or an imported profile.
    if cfg.spec then cfg.healMode = (cfg.spec == "heal") end

    self:UpdateManagement(cfg)

    -- Before anything else, in every mode.
    --
    -- The bubble first where it is set, because five minutes is a far cheaper
    -- cooldown than an hour - but only the healer page offers it, and the tank
    -- page offers Lay on Hands instead, for the reason recorded at tankLohPct.
    if self:PanicShield(cfg) then return end
    if self:PanicLayOnHands(cfg) then return end
    if self:PanicHeal(cfg) then return end

    -- Heal-mode trace. It has to sit HERE, above the heal branches, because every
    -- one of them returns - the strike/seal trace further down is unreachable for
    -- a paladin who is actually healing, which is why a healer produced no trace
    -- at all and every report about the heal path had to be argued from theory.
    --
    -- Reads only. The gate conditions are printed as their raw INPUTS (melee,
    -- mana, the switches) and never by calling HealStrikeEngine / HolyStrikeDue
    -- / HealSeals, which cast when they return true.
    --
    -- The two ranks shown are picked against the RAW deficit, not against the
    -- padded one DoHeal uses (combat compensation, healing-reduction debuffs), so
    -- a rank here can legitimately be one below what actually goes out. Printing
    -- the input is the point: it is the number to compare against the character
    -- sheet when overhealing is being investigated.
    if cfg.healMode and self:Tracing() then
        local ratio = (cfg.healThreshold or 75) / 100
        local u, def, pct = self:WorstHurt(ratio, cfg)
        local mana = UnitMana("player")
        local maxm = UnitManaMax("player")
        local hp = (cfg.healPower and cfg.healPower > 0) and cfg.healPower or self:GearHealBonus()
        -- The SAME call DoHeal makes, so the log cannot describe a rule other
        -- than the one that picks. The only difference is the deficit: raw here,
        -- healing-debuff-adjusted there, which is noted on the line itself.
        local hlFast = self:BuffTextureUp(FORCE_HL_TEX) or self:HasBuff("Holy Judgement")
        local qhPick
        if u then qhPick = self:CascadePick(cfg, def, pct, mana, hlFast) end
        local emg = (u and pct <= (cfg.holyShockPct or 50) / 100) and "Y" or "N"
        local pend = u and self:PendingFor(u) or 0
        -- ONE argument, not two. Aegis_SBR:Trace writes only its FIRST argument to
        -- the press log, and the second half - ranks, +healing, the gate inputs -
        -- is exactly what has to be readable off disk when a tester sends their
        -- SavedVariables in. A long wrapped chat line is the cheaper price.
        self:Trace(
            "heal unit=" .. (u and (UnitName(u) or u) or "-")
                .. " pct=" .. (pct and string.format("%.0f%%", pct * 100) or "-")
                .. " def=" .. (u and string.format("%.0f", def) or "-")
                .. " pend=" .. string.format("%.0f", pend)
                .. " thr=" .. (cfg.healThreshold or 75)
                .. " emg=" .. emg .. "/" .. (cfg.holyShockPct or 50)
                .. " gcd=" .. (self:GcdReady() and "Y" or "N")
                .. " cast=" .. (self:StillCasting() and "Y" or "N")
                .. " hold=" .. ((self.healUntil and GetTime() < self.healUntil)
                    and string.format("%.1fs", self.healUntil - GetTime()) or "-")
                .. "  pick=" .. (qhPick or "-")
                .. " healthy=" .. (cfg.ratioHealthy or 10) .. "%"
                .. " +heal=" .. hp .. (((cfg.healPower or 0) > 0) and "(manual)" or "(gear)")
                .. " mana=" .. mana .. "/" .. (maxm or 0)
                .. " melee=" .. (self:InMeleeRange() and "Y" or "N")
                .. " hs(" .. (self:KnowsSpell("Holy Shock") and "k" or "-")
                .. "," .. (self:OwnCDReady("Holy Shock") and "rdy" or "cd") .. ")"
                .. " splash=" .. (cfg.healSplashHS and "on" or "off")
                .. "/" .. (cfg.hsMinTargets or 1) .. "@" .. (cfg.hsMinHP or 100) .. "%"
                .. " hsDue=" .. (self:HolyStrikeDue(cfg) and "Y" or "N")
                .. " reload=" .. (cfg.healReloadCS and "on" or "off")
                .. " seal=" .. (cfg.healManaSelf and "self" or "-")
                .. "/" .. (cfg.healManaJudge and "judge" or "-")
                .. (cfg.healAggro and (" danger=" .. (u and (self:InDanger(u) and "Y" or "n") or "-")
                    .. "/" .. (u and self:AggroCount(u) or 0)) or "")
                .. " hj=" .. (hlFast and "up" or "-")
                .. (cfg.healJudgeHL and "/pre" or ""))
    end

    -- Heal mode, melee-holy: the Blessed Strikes engine reloads Holy Shock
    -- between heals (never over an emergency), then group healing preempts the
    -- attack rotation, so a judgement or strike GCD never delays a needed heal.
    -- Curing, above the heal but only while nobody is hurt past the crossover.
    if cfg.healMode and cfg.useCure then
        local _, _, worst = self:WorstHurt((cfg.healThreshold or 75) / 100)
        if self:CureStep(cfg, worst) then return end
    end

    -- The three steps that are allowed ABOVE the healing, and only these.
    --
    -- Everything else in heal mode is an optimisation of the quiet moments, and
    -- it stays below the heal. That ordering was measured against a real log:
    -- with the heal threshold at 95%, somebody was under it on 98% of presses,
    -- the heal claimed 99% of them, and the whole block below ran ONE time in
    -- 1267 presses. In a dungeon there are lulls; in a battleground there are
    -- none, and every "quiet moment" step starves completely.
    if cfg.healMode then
        -- Is anybody in the emergency band? The two mana steps yield to that;
        -- Holy Strike deliberately does not (see below).
        local _, _, worstPct = self:WorstHurt((cfg.healThreshold or 75) / 100, cfg)
        local emergency = worstPct and worstPct <= (cfg.holyShockPct or 50) / 100

        -- 1. Holy Strike, on cooldown, ahead of the healing itself.
        --
        -- Opt-in, and above EVERYTHING when it is on - which is how it was
        -- specified and is not an oversight. Holy Strike is not a damage ability
        -- that happens to heal: it splash-heals the group and returns mana
        -- through Seal of Wisdom in the same swing, which is why it outranks a
        -- single-target heal often enough to be worth a switch.
        --
        -- No emergency guard here on purpose. The control the player has is
        -- range: HolyStrikeDue requires melee, so stepping back turns this off
        -- and leaves an ordinary healing rotation. Its own two thresholds still
        -- apply - they are restrictions the player set themselves.
        if cfg.hsPriority and self:HolyStrikeDue(cfg) then
            if self:CastStrike("Holy Strike", cfg) then return end
        end

        -- 2. Seal of Wisdom when it has run out. A self buff: no target, no
        -- enemy, no melee range, one global cooldown - and it pays for every
        -- heal after it. Measured in the same log: 17% of presses under 10%
        -- mana, seven of them at zero.
        if not emergency and self:HealSealUp(cfg) then return end

        -- 3. Judgement of Wisdom, once, so the group gets mana back too. Once
        -- per mob and then Holy Strike's hits keep it up, so it is cheap - but
        -- it never came up at all from below the heal.
        if not emergency and self:HealSeals(cfg) then return end
    end

    if cfg.healMode and self:DoHeal(cfg) then return end

    -- Heal mode works at range with no target; everything below needs an
    -- attackable target, so stop here when there is none.
    if not (UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")) then
        return
    end

    -- In heal mode the attack rotation yields while anyone needs healing, so a
    -- Seal of Wisdom judgement never steals the GCD from a heal. With nobody
    -- hurt, strike with the heal policy (Holy Strike splash) before the
    -- generic damage rotation below.
    if cfg.healMode then
        -- Holy Strike, the splash heal - but never over somebody in real danger,
        -- who needs a cast aimed at them rather than an area effect.
        -- Only when the switch above is OFF; with it on, Holy Strike has
        -- already had its say ahead of the heal.
        if not cfg.hsPriority then
            local _, _, worst = self:WorstHurt((cfg.healThreshold or 75) / 100, cfg)
            if not (worst and worst <= (cfg.holyShockPct or 50) / 100) then
                if self:HolyStrikeDue(cfg) then
                    if self:CastStrike("Holy Strike", cfg) then return end
                end
            end
        end

        -- Seal of Wisdom and its judgement have moved above the heal, where
        -- they can actually be reached; they are not repeated here. What is left
        -- in this block only shortens a cooldown.
        -- Reload Holy Shock last of the strike-shaped steps: it applies nothing
        -- and heals nobody, it only shortens a cooldown.
        if self:HealStrikeEngine(cfg) then return end
        if self:HealJudgeBuff(cfg) then return end

        -- Damage fillers, last of everything and opt-in. A press reaching here
        -- was not wanted by the healing, the seal, the judgement, the splash or
        -- the Holy Shock reload - so it is genuinely spare.
        --
        -- Spare presses are not spare MANA, though. Below the filler threshold
        -- none of them run and what is left is saved for healing.
        --
        -- Hammer of Wrath first: it is instant, so it costs the least of the
        -- two, and its window closes on its own.
        -- Deliberately NOT gated on the Tank/DPS spell toggles: those belong to
        -- the melee tabs, and a checkbox on the Healer tab that silently does
        -- nothing because of a setting on another page is a trap.
        local fillerMana = cfg.healFillerMana or 0
        local fillersOK = (fillerMana <= 0) or (self:ManaPct() > fillerMana)

        if fillersOK and cfg.healFillerHoW and self:KnowsSpell("Hammer of Wrath")
            and self:TargetHPPct() <= 20 and self:IsReady("Hammer of Wrath")
            and self:Affordable("Hammer of Wrath")
            and Aegis_SBR:SpellReaches("Hammer of Wrath", "target") then
            if self:Pick("Hammer of Wrath", "heal filler") then return end
        end

        -- Consecration burns the ground around YOU, so melee range is required
        -- here exactly as it is in the damage rotation - cast at thirty yards it
        -- lands on empty floor and still spends the press. Held during mana
        -- recovery unless the same opt-out the damage rotation uses is set: as a
        -- healer the mana it costs is heals you will not be casting.
        -- Exorcism next: a single strong nuke against Undead and Demon targets,
        -- on its own cooldown, so it competes with nothing.
        if fillersOK and cfg.healFillerExo and self:KnowsSpell("Exorcism")
            and self:TargetIsUndeadOrDemon() and self:IsReady("Exorcism")
            and self:Affordable("Exorcism")
            and Aegis_SBR:SpellReaches("Exorcism", "target") then
            if self:Pick("Exorcism", "heal filler") then return end
        end

        if fillersOK and cfg.healFillerConsec and self:InMeleeRange()
            and (not self.manaMgmtActive or cfg.consecInMana)
            and (not cfg.consecStill or Aegis_SBR:StillFor(CONSEC_DWELL))
            and self:ConsecrationCrowded(cfg)
            and self:KnowsSpell("Consecration") and self:IsReady("Consecration")
            and self:Affordable("Consecration") then
            if self:Pick("Consecration", "heal filler") then return end
        end
    end

    if self:Tracing() then
        -- select() does not exist on this client; take the second return plainly.
        local _, traceZeal = self:BuffTime("Zeal")
        traceZeal = traceZeal or 0
        local db = cfg.seals.debuff
        local strk = (self:StrikeEnabled(cfg) and self:SharedStrikeReady(cfg)) and "Y" or "N"
        self:Trace(
            "strike=" .. strk
                .. " HShld(use=" .. (cfg.spells.holyShield and "Y" or "N")
                .. ",k=" .. (self:KnowsSpell("Holy Shield") and "Y" or "N")
                .. "," .. self:CDInfo("Holy Shield") .. ")"
                .. " debuff=" .. (db ~= "" and db or "-")
                .. " dbuff=" .. ((db ~= "" and self:TargetHasJudgementDebuff(db)) and "Y" or "N")
                .. " seen=" .. ((self.debuffSeenAt and (GetTime() - self.debuffSeenAt) < 1.5) and "Y" or "N")
                .. " dmg=" .. (cfg.seals.damage ~= "" and cfg.seals.damage or "-")
                .. " range=" .. (self:InMeleeRange() and "Y" or "N")
                .. " swing=" .. (self:SwingTimeLeft() and string.format("%.2fs", self:SwingTimeLeft()) or "-"),
            "hsOn=" .. (self:HSOn(cfg) and "Y" or "N")
                .. " csOn=" .. (self:CSOn(cfg) and "Y" or "N")
                .. " style=" .. (cfg.strikeStyle or "autodps")
                .. " HS(k=" .. (self:KnowsSpell("Holy Strike") and "Y" or "N")
                .. ",R=" .. self:EffectiveStrikeRank("Holy Strike", cfg) .. "/" .. self:MaxRank("Holy Strike") .. ")"
                .. " CS(k=" .. (self:KnowsSpell("Crusader Strike") and "Y" or "N")
                .. ",R=" .. self:EffectiveStrikeRank("Crusader Strike", cfg) .. "/" .. self:MaxRank("Crusader Strike") .. ")"
                .. " lean=" .. (self:AutoLeansHoly() and "holy" or "crusader")
                .. " oh=" .. (self:HasOffhand() and "Y" or "N")
                .. " dr=" .. (cfg.strikeDownrank and "on" or "off")
                .. " afford=" .. (self:Affordable("Judgement") and "J" or "-")
                .. ((self:KnowsSpell("Crusader Strike") and self:Affordable("Crusader Strike")) and "C" or "-")
                .. ((self:KnowsSpell("Holy Strike") and self:Affordable("Holy Strike")) and "H" or "-")
                .. " mana=" .. UnitMana("player")
                .. " how=" .. (self:TargetHPPct() <= 20 and (self:IsReady("Hammer of Wrath") and "rdy" or "cd") or "-")
                .. " sotc=" .. (self:TargetHasJudgementDebuff("Seal of the Crusader") and "up" or "-")
                .. " zeal=" .. traceZeal
                .. " ctype=" .. (UnitCreatureType and (UnitCreatureType("target") or "?") or "?")
                -- Nameplate-derived enemy count, "?" when it cannot be taken.
                .. " near=" .. (function()
                    local n = Aegis_SBR:CountEnemiesNear(self:SpellRadius("Consecration") or 8)
                    return n and tostring(n) or "?"
                end)() .. "/" .. (cfg.consecMinTargets or 0)
                .. " exo=" .. (cfg.spells.exorcism and (
                    (not self:KnowsSpell("Exorcism")) and "unknown"
                    or (not self:TargetIsUndeadOrDemon()) and "wrong type"
                    or self.manaMgmtActive and "MANA MODE"
                    or (not self:IsReady("Exorcism")) and "cd"
                    or (not Aegis_SBR:SpellReaches("Exorcism", "target")) and "range"
                    or (not self:Affordable("Exorcism")) and "cost"
                    or "ready") or "off")
                .. " hit=" .. (self:BeingAttacked() and "Y" or "N")
                .. " setup=" .. string.format("%.1fs", self:CrusaderSetupTime(cfg))
                .. " ttk=" .. (Aegis_SBR:TargetTTK() and string.format("%.1fs", Aegis_SBR:TargetTTK()) or "?")
                .. " veng=" .. self:TalentRank(TALENT_HOLY_MIGHT)
                .. " rght=" .. self:TalentRank(TALENT_THREAT))
    end

    -- 0. Pre-cast the seal while running in (out of melee range), so the first
    -- hit on contact already carries a seal. Skipped once in range, where the
    -- normal strict priority below applies. We never judge out of range. In heal
    -- mode this is skipped so a range healer keeps the GCD free for the heal.
    if not cfg.healMode and not self:InMeleeRange() then
        local s = self:DesiredOpenerSeal(cfg)
        if s and self:KnowsSpell(s) and not self:HasBuff(s) then
            if self:Pick(s, "strike") then return end
        end
    end

    -- 0. Hammer of Wrath, ahead of everything else once the target is inside the
    -- execute window. It has its own cooldown and a hard health gate, so a
    -- missed window is simply gone - unlike a strike, which comes back.
    --
    -- Out of melee reach it goes straight out: there is nothing else this
    -- rotation can do at that distance anyway.
    --
    -- In melee it first asks whether Judgement of the Crusader is on the target,
    -- because that debuff amplifies the holy damage the hammer deals. If the
    -- judgement is missing, the detour to apply it is taken ONLY when the target
    -- is measurably going to live long enough to pay for it (see
    -- CrusaderDetourWorthIt) - the seal work runs through HandleSeals below
    -- rather than casting here, so the two cannot fight over which seal is on.
    if not cfg.healMode and cfg.spells.hammerOfWrath
        and self:KnowsSpell("Hammer of Wrath")
        and self:TargetHPPct() <= 20 and self:IsReady("Hammer of Wrath")
        and self:Affordable("Hammer of Wrath")
        and Aegis_SBR:SpellReaches("Hammer of Wrath", "target") then
        local melee = self:InMeleeRange()
        local crusaderUp = self:TargetHasJudgementDebuff("Seal of the Crusader")
        -- Zeal, stacked by Crusader Strike, shortens the hammer's cast. In melee
        -- that is the difference between the cast landing and the mob dying
        -- under it, so melee waits for three stacks as well as the judgement.
        --
        -- At range neither applies: there is nothing else to do at thirty yards,
        -- nobody is pushing the cast back, and holding the hammer for a buff you
        -- can only build in melee would mean not casting it at all.
        local _, zeal = self:BuffTime("Zeal")
        local meleeReady = crusaderUp and (zeal or 0) >= ZEAL_STACKS
        if not melee or meleeReady or not self:CrusaderDetourWorthIt(cfg) then
            if self:Pick("Hammer of Wrath", "execute") then return end
        else
            -- Worth the detour: hand the seal work to HandleSeals with the
            -- crusader seal forced for this press, then come back next press and
            -- the branch above fires with the debuff up.
            if self:HandleSeals(cfg, "Seal of the Crusader") then return end
        end
    end

    -- SOLOFARMING, and only here. Tank and DPS pass straight through.
    --
    -- Two things come before the damage, because both are what keep a paladin
    -- standing in the middle of four mobs: healing yourself, and having Holy
    -- Shield up. The damage itself is largely passive - Consecration, the aura
    -- proc, the block - so nothing here competes with a global cooldown that
    -- would otherwise have been a big hit.
    if cfg.spec == "solo" then
        -- Self-healing through the ordinary heal engine, aimed at the player
        -- (see GroupUnits). Holy Shock, Flash of Light and Holy Light all reach
        -- it, including the Holy Judgement speed-up.
        if self:DoHeal(cfg) then return end

        -- Holy Shield kept up rather than used on cooldown: block chance is
        -- survival here, and the blocks are a damage source of their own.
        if cfg.spells.holyShield and self:KnowsSpell("Holy Shield")
            and not self:HasBuff("Holy Shield") and self:OwnCDReady("Holy Shield")
            and self:Affordable("Holy Shield") then
            if self:Pick("Holy Shield", "keep the block up") then return end
        end
    end

    -- 0b. Exorcism against an Undead or Demon target, directly behind the
    -- hammer and ahead of everything else - but AFTER the solofarming block,
    -- where staying alive outranks any nuke.
    --
    -- It sat LAST, below the strike, Holy Shield, Consecration, the seals and
    -- two more - so it only ever got a press when all of those were on cooldown
    -- at once. That is the wrong place for a rare, strong spell that carries its
    -- own cooldown: what it competes with is a strike that will come back in
    -- three seconds, and it loses that trade every time.
    --
    -- Still skipped during mana recovery. That suppression is silent and has no
    -- opt-out of its own, unlike Consecration's - if Exorcism seems ready and
    -- simply never fires, the trace line says "exo=MANA MODE" and that is why.
    if not cfg.healMode and cfg.spells.exorcism and not self.manaMgmtActive
        and self:KnowsSpell("Exorcism") and self:TargetIsUndeadOrDemon()
        and self:IsReady("Exorcism") and Aegis_SBR:SpellReaches("Exorcism", "target")
        and self:Affordable("Exorcism") then
        if self:Pick("Exorcism", "undead or demon") then return end
    end

    -- 1. Strike (damage/tank mode only; heal mode has its own strike weaving,
    -- HealStrikeEngine/HolyStrikeDue, above)
    --
    -- Melee range is checked here and nowhere else in this chain: a strike is
    -- the first thing the rotation reaches for, and Pick reports success as soon
    -- as a spell is known and affordable - so at range every press was spent on
    -- a swing that could not land, and the ranged abilities further down were
    -- never reached at all.
    --
    -- On SOLOFARMING the strikes stop being a damage source and become one
    -- thing: the way Holy Shock comes back. Holy Strike's returns to the paladin
    -- himself are halved, and both strikes share a cooldown - so spending that
    -- cooldown on anything other than the Crusader Strike reset costs the
    -- self-heal it would have bought. HealStrikeEngine already expresses exactly
    -- that rule, so it is used here rather than restated.
    if cfg.spec == "solo" then
        if self:HealStrikeEngine(cfg) then return end
    elseif not cfg.healMode and self:InMeleeRange()
        and self:StrikeEnabled(cfg) and self:SharedStrikeReady(cfg) then
        local pick = self:ResolveSharedCD(cfg)
        if pick and self:CastStrike(pick, cfg) then return end
    end
    -- 2. Holy Shield. Check its OWN cooldown and hold through the global
    -- cooldown so it reliably lands right after the strike and before seals,
    -- instead of losing the GCD edge to the unconditional seal recast.
    -- (damage/tank mode only, same reasoning as the strike above)
    if not cfg.healMode and cfg.spells.holyShield and self:OwnCDReady("Holy Shield") then
        if self:Pick("Holy Shield", "block charges") then return end
    end
    -- 2b. Consecration leads AoE: when toggled on (checkbox or /sbr aoe), cast it
    -- on cooldown right after the strike so it is a primary AoE source rather
    -- than a leftover filler. Ground-targeted, but a plain cast drops it at your
    -- feet on the usual SuperWoW/Nampower setup. (damage/tank mode only)
    --
    -- Held during mana recovery UNLESS consecInMana is set. That opt-out exists
    -- because the recovery flag is a latching hysteresis: it switches on below
    -- manaLow and only off again at manaHigh, so with a wide band (a tank on
    -- 60/90, say) it can stay on for an entire fight - mana sitting comfortably
    -- in between, yet Consecration silently suppressed the whole time. The flag
    -- is not surfaced anywhere, so that reads as "it is off cooldown and simply
    -- not being cast". For a tank the AoE threat usually matters more than the
    -- mana it saves, hence the switch.
    --
    -- Melee range is required even though Consecration takes no target: it burns
    -- the ground around YOU, so cast at thirty yards it lands on empty floor and
    -- still spends the press - which is how it used to block every ranged
    -- ability below it.
    if not cfg.healMode and cfg.spells.consecration and self:InMeleeRange()
        and (not self.manaMgmtActive or cfg.consecInMana)
        and (not cfg.consecStill or Aegis_SBR:StillFor(CONSEC_DWELL))
        and self:ConsecrationCrowded(cfg)
        and self:KnowsSpell("Consecration") and self:IsReady("Consecration") then
        if self:Pick("Consecration", "AoE") then return end
    end
    -- 3. Seal upkeep and judgement (damage/tank mode only; heal mode runs its
    -- own Seal of Wisdom upkeep via HealSeals above)
    if not cfg.healMode and self:HandleSeals(cfg) then return end
    -- 5. Repentance. On an immune target it is a damage cooldown; on everything
    -- else it is a crowd control worth spending only to stop a cast. Which one
    -- this creature gives is learned once and remembered - see RepentanceWanted.
    --
    -- Resolved OUTSIDE the readiness gate, and that is not tidiness: a probe is
    -- read a second after the cast, when Repentance is by definition on its own
    -- cooldown. Inside the gate the verdict would first be looked at a minute
    -- later, with the cooldown free again - which this reads as "the cast never
    -- happened" and discards. The probe would never resolve at all.
    if not cfg.healMode then self:RepentanceResolve() end
    if not cfg.healMode and cfg.spells.repentance and self:IsReady("Repentance")
        and Aegis_SBR:SpellReaches("Repentance", "target") then
        local want, probeKey = self:RepentanceWanted(cfg)
        if want then
            local reason = probeKey and "learning the immunity"
                or (self:RepentanceVerdict() and "damage on an immune target" or "stopping a cast")
            if self:Pick("Repentance", reason) then
                if probeKey then
                    self:Later(function()
                        self.repentProbe = { key = probeKey, t = GetTime() }
                    end)
                end
                return
            end
        end
    end
end

function M:CmdSeal(name, slot, alias)
    local cfg = name and AegisDB.profiles[name]
    if not cfg then msgOut("profile not found.", 1, 0.5, 0.3); return end
    if slot ~= "debuff" and slot ~= "damage" then msgOut("slot must be debuff or damage.", 1, 0.5, 0.3); return end
    local seal = self.sealAlias[string.lower(alias or "")]
    if seal == nil then msgOut("unknown seal alias.", 1, 0.5, 0.3); return end
    cfg.seals[slot] = seal
    msgOut("'" .. name .. "' " .. slot .. " seal = " .. ((seal == "") and "(none)" or seal) .. ".")
end

function M:CmdSpell(name, alias, onoff)
    local cfg = name and AegisDB.profiles[name]
    if not cfg then msgOut("profile not found.", 1, 0.5, 0.3); return end
    local key = self.spellAlias[string.lower(alias or "")]
    if not key then msgOut("unknown spell alias.", 1, 0.5, 0.3); return end
    -- `== nil` on purpose: false is a valid result and must not read as an error.
    local v = Aegis_SBR:ToggleArg(cfg.spells[key], onoff)
    if v == nil then
        msgOut("usage: /sbr spell " .. name .. " " .. string.lower(alias) .. " [on|off] - no argument toggles.", 1, 0.5, 0.3)
        return
    end
    cfg.spells[key] = v
    msgOut("'" .. name .. "' " .. Aegis_SBR:SpellLabel(key) .. " " .. (cfg.spells[key] and "on" or "off") .. ".")
end

-- Quick AoE toggle: flips Consecration on the active profile, for binding to
-- a key. There is no reliable enemy count on 1.12, so this stays manual.
function M:CmdAoe()
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.spells.consecration = not cfg.spells.consecration
    msgOut("Consecration " .. (cfg.spells.consecration and "on (AoE)" or "off") .. ".")
end

-- Optional macro helper: set the strikes on the active profile. off = both off,
-- hs = only Holy Strike, cs = only Crusader Strike, auto = both on + Auto DPS,
-- tank = both on + Tank (block, then aggro). The UI is the primary control.
function M:CmdStrike(alias)
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local what = self.strikeCmdAlias[string.lower(alias or "")]
    if not what then msgOut("usage: /sbr strike off|hs|cs|auto|tank", 1, 0.5, 0.3); return end
    cfg.spells = cfg.spells or {}
    if what == "off" then
        cfg.spells.holyStrike, cfg.spells.crusaderStrike = false, false
    elseif what == "hs" then
        cfg.spells.holyStrike, cfg.spells.crusaderStrike = true, false
    elseif what == "cs" then
        cfg.spells.holyStrike, cfg.spells.crusaderStrike = false, true
    elseif what == "auto" then
        cfg.spells.holyStrike, cfg.spells.crusaderStrike, cfg.strikeStyle = true, true, "autodps"
    elseif what == "tank" then
        cfg.spells.holyStrike, cfg.spells.crusaderStrike, cfg.strikeStyle = true, true, "tankblock"
    end
    local both = cfg.spells.holyStrike and cfg.spells.crusaderStrike
    msgOut("strikes -> HS " .. (cfg.spells.holyStrike and "on" or "off")
        .. ", CS " .. (cfg.spells.crusaderStrike and "on" or "off")
        .. (both and (", style " .. (cfg.strikeStyle or "autodps")) or "") .. ".")
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
-- Priority list management. Names, not units: a raid slot changes between
-- pulls, a name does not.
function M:PrioAdd(cfg, name)
    if not name or name == "" then return false end
    if type(cfg.healPrioList) ~= "table" then cfg.healPrioList = {} end
    for i = 1, table.getn(cfg.healPrioList) do
        if cfg.healPrioList[i] == name then return false end
    end
    table.insert(cfg.healPrioList, name)
    return true
end

function M:PrioRemove(cfg, idx)
    if type(cfg.healPrioList) ~= "table" then return false end
    if not cfg.healPrioList[idx] then return false end
    table.remove(cfg.healPrioList, idx)
    return true
end

-- One switch between the two playstyles: it drives the healthy ratio to 100 or
-- to 0 and calls the ends "High HPS" and "Normal HPS". At 100 no target ever
-- counts as healthy, so Holy Light is never used; at 0 every target does, so
-- Holy Light is used whenever it is the bigger heal. Deliberately no second code
-- path - the same ladder serves both ends.
function M:ToggleHPS(cfg)
    -- 0 = nobody is ever "hurt enough", so Holy Light is never used: the fast
    -- heal carries everything. 100 = everybody is, so Holy Light is used
    -- whenever no Flash of Light can cover the need.
    if (cfg.ratioHealthy or 60) <= 0 then
        cfg.ratioHealthy = 100
        return "normal"
    end
    cfg.ratioHealthy = 0
    return "high"
end

function M:HandleCommand(cmd, t)
    if cmd == "hps" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local mode = self:ToggleHPS(cfg)
        if mode == "high" then
            msgOut("High HPS: Flash of Light only, Holy Light never (except with Holy Judgement).")
        else
            msgOut("Normal HPS: Holy Light whenever it is the bigger heal.")
        end
        return true
    end
    if cmd == "prio" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local a = string.lower(t[2] or "")
        if a == "add" then
            local nm = (t[3] and t[3] ~= "") and t[3] or UnitName("target")
            if self:PrioAdd(cfg, nm) then msgOut("priority: added " .. (nm or "?") .. ".")
            else msgOut("priority: nothing added (no target, or already listed).", 1, 0.5, 0.3) end
        elseif a == "del" or a == "remove" then
            if self:PrioRemove(cfg, tonumber(t[3])) then msgOut("priority: removed.")
            else msgOut("usage: /sbr prio del <number>", 1, 0.5, 0.3) end
        elseif a == "clear" then
            cfg.healPrioList = {}; msgOut("priority list cleared.")
        elseif a == "on" or a == "off" then
            cfg.healPrio = (a == "on"); msgOut("heal priority " .. a .. ".")
        else
            local l = cfg.healPrioList or {}
            msgOut("heal priority " .. (cfg.healPrio and "on" or "off")
                .. " - /sbr prio add|del <n>|clear|on|off")
            for i = 1, table.getn(l) do
                DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ". " .. l[i], 0.8, 0.85, 1)
            end
        end
        return true
    end
    if cmd == "seal"   then self:CmdSeal(t[2], string.lower(t[3] or ""), t[4]); return true end
    if cmd == "spell"  then self:CmdSpell(t[2], t[3], t[4]); return true end
    if cmd == "aoe"    then self:CmdAoe(); return true end
    if cmd == "strike" then self:CmdStrike(t[2]); return true end
    if cmd == "heal" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local a = string.lower(t[2] or "")
        -- Writes `spec`, not `healMode`: the rotation derives healMode from spec
        -- on every press, so setting it here alone would be undone immediately.
        -- Switching off returns to Retribution, which is the default melee page.
        if a == "on" then cfg.spec = "heal"; cfg.healMode = true; msgOut("heal mode on.")
        elseif a == "off" then
            if cfg.spec == "heal" then cfg.spec = "retri" end
            cfg.healMode = false
            msgOut("heal mode off (" .. cfg.spec .. ").")
        else msgOut("heal mode is " .. (cfg.healMode and "on" or "off") .. ". Use /sbr heal on or off.") end
        return true
    end
    if cmd == "healat" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local v = tonumber(t[2])
        if v and v >= 1 and v <= 100 then cfg.healThreshold = v; msgOut("healing members below " .. v .. "% health.")
        else msgOut("usage: /sbr healat <1-100>.", 1, 0.5, 0.3) end
        return true
    end
    if cmd == "hsat" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local v = tonumber(t[2])
        if v and v >= 1 and v <= 100 then cfg.holyShockPct = v; msgOut("Holy Shock emergency below " .. v .. "% health.")
        else msgOut("usage: /sbr hsat <1-100>.", 1, 0.5, 0.3) end
        return true
    end
    if cmd == "healpower" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local v = tonumber(t[2])
        if v and v >= 0 then cfg.healPower = v; msgOut("healing bonus set to " .. v .. " (0 = auto from gear).")
        else msgOut("usage: /sbr healpower <number>.", 1, 0.5, 0.3) end
        return true
    end
    return false
end

-- ============================================================
-- Talent cache invalidation. Cleared at login and whenever talent points
-- change, so TalentRank() re-reads fresh data on its next call.
-- ============================================================
-- ============================================================
-- Landed-heal probe (log only, off unless /sbr log on)
-- ============================================================
-- Pairs what the module PREDICTED with what the server actually healed for, so
-- the heal model can be checked against Turtle instead of assumed.
--
-- The model is base heal + coefficient * +healing, with the coefficient taken
-- from the spell's base cast time (1.5/3.5 for Flash of Light, 2.5/3.5 for Holy
-- Light) - vanilla's rule. Turtle is free to have changed any part of that, and
-- nothing in the addon would notice: a wrong coefficient or a mis-scanned gear
-- bonus both show up only as picking the wrong rank, which is exactly the
-- overhealing that was reported.
--
-- A crit is flagged rather than filtered. It is ~1.5x and would otherwise read
-- as the model underestimating by half.
--
-- The verdict on a Repentance probe, read out of the combat log.
--
-- "immune" is the answer we are actually after: it means the crowd control did
-- not take and the damage effect did instead, which is the whole reason to keep
-- casting this on that creature. "resist" and "miss" VOID the probe rather than
-- answering it - the cast resolved and its cooldown started, but nothing landed
-- and nothing was learned, so recording either verdict would be a guess.
--
-- Matched narrowly: only a line that names Repentance, and only while a probe is
-- actually outstanding. A message about anything else cannot record a verdict.
local repentFrame = CreateFrame("Frame")
repentFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
repentFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
repentFrame:SetScript("OnEvent", function()
    local pr = M.repentProbe
    if not pr or not arg1 then return end
    if not string.find(arg1, "Repentance", 1, true) then return end
    if string.find(arg1, "immune") then
        pr.immune = true
    elseif string.find(arg1, "resist") or string.find(arg1, "miss") then
        pr.voided = true
    end
end)

-- prediction comes from CommitHeal's stored value; it is the amount for the
-- cast that just resolved, since a heal cannot land before it is committed.
local healLogFrame = CreateFrame("Frame")
healLogFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
healLogFrame:SetScript("OnEvent", function()
    if not Aegis_SBR.logging then return end
    if not arg1 then return end
    local crit = false
    local _, _, spell, who, amt = string.find(arg1, "^Your (.+) critically heals (.+) for (%d+)")
    if spell then
        crit = true
    else
        _, _, spell, who, amt = string.find(arg1, "^Your (.+) heals (.+) for (%d+)")
    end
    if not spell then return end
    -- The combat log calls the player "you", never by name, so a self-heal never
    -- matched the stored target and every one of them logged pred=- . That threw
    -- away exactly the samples the model check needs most: 100 of the landed
    -- heals in the first capture were self-heals, all unpairable.
    if who == "you" or who == "You" then who = UnitName("player") or who end
    local pred = (M.healTarget == who) and M.healAmount or nil
    Aegis_SBR:LogWrite(string.format("heal-land %s on %s amount=%s%s pred=%s",
        spell, who, amt, crit and " CRIT" or "",
        pred and string.format("%.0f", pred) or "-"))
end)

local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_LOGIN")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
talentFrame:SetScript("OnEvent", function()
    M.talentCache = nil
end)

-- ============================================================
-- Overheal cancel
-- ============================================================
-- Stops a heal already in flight once too much of it has become waste - someone
-- else landed a heal first, or the target simply stopped taking damage. The cast
-- is abandoned rather than finished, and the mana with it.
--
-- Off unless a threshold is set, because a cancelled cast is visible and
-- surprising: the cast bar vanishes mid-way and nothing happens. The delay
-- exists for the same reason - it stops a cast being cut the instant it starts.
--
-- Cancelling also clears the in-flight prediction. Leaving it would be worse
-- than not cancelling at all: the target would go on looking healthier than they
-- are for the rest of the committed window.
-- ============================================================
-- How much MORE wasteful a heal has to have become, in percentage points, before
-- the cancel is allowed to fire.
local WASTE_GROWTH = 10

local overhealFrame = CreateFrame("Frame")
overhealFrame:SetScript("OnUpdate", function()
    if Aegis_SBR.active ~= M then return end
    if not M.castingUntil or GetTime() >= M.castingUntil then return end
    if not M.healUnit or not M.healAmount or M.healAmount <= 0 then return end
    local cfg = Aegis_SBR:GetActiveProfile()
    if not cfg or not cfg.healMode then return end
    local thr = cfg.overhealCancel or 0
    if thr <= 0 then return end
    if (GetTime() - (M.healStart or 0)) < (cfg.overhealCancelDelay or 0) then return end
    local u = M.healUnit
    if not UnitExists(u) or UnitIsDeadOrGhost(u) then return end
    local mx = UnitHealthMax(u)
    if not mx or mx <= 0 then return end
    local need = mx - (UnitHealth(u) + M:IncomingHeal(u))
    if need < 0 then need = 0 end
    local waste = (M.healAmount - need) / M.healAmount * 100
    -- Two conditions, and the second one is what stops this from being a loop.
    --
    -- Cancelling exists for the situation CHANGING mid-cast: another healer
    -- landed one first, or the target stopped taking damage. It must never fire
    -- on a heal that was already this wasteful when the rotation chose it -
    -- there the cancel simply repeals the decision, the next press makes the
    -- same choice, and the pair repeats forever. From the outside that looks
    -- like a rotation doing nothing at all, right up until an INSTANT heal comes
    -- off cooldown and slips through because it finishes before this can fire.
    -- (Reported exactly that way: "doing nothing until Holy Shock was ready".)
    --
    -- If a heal is too wasteful to be worth starting, that is a job for the
    -- selection - a threshold, not a cancel.
    if waste >= thr and waste > (M.healWaste0 or 0) + WASTE_GROWTH then
        SpellStopCasting()
        if Aegis_SBR.logging then
            Aegis_SBR:LogWrite(string.format("heal-cancel on %s waste=%.0f%% (was %.0f%%)",
                UnitName(u) or "?", waste, M.healWaste0 or 0))
        end
        M.castingUntil = nil
        M.healUntil = nil
        M.healTarget = nil
        M.healUnit = nil
        M.healAmount = 0
    end
end)

-- ============================================================
-- End of cast
-- ============================================================
-- The client says when a cast stops, whether it finished, failed or was
-- interrupted - so the commitment is cleared on evidence instead of on a timer.
-- Without this, StillCasting has to fall back on a guess, and every guess is
-- wrong in one of two directions: too short clips a cast that was merely queued,
-- too long freezes the rotation after a cast the client refused outright.
local castEndFrame = CreateFrame("Frame")
castEndFrame:RegisterEvent("SPELLCAST_STOP")
castEndFrame:RegisterEvent("SPELLCAST_FAILED")
castEndFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
castEndFrame:SetScript("OnEvent", function()
    M.castingUntil = nil
    -- A cast that FAILED or was interrupted never landed, so the healing it
    -- promised must stop counting too - otherwise the target goes on looking
    -- healthier than it is for the rest of the committed window and nobody
    -- heals it.
    if event ~= "SPELLCAST_STOP" then
        M.healUntil = nil
        M.healTarget = nil
        M.healUnit = nil
        M.healAmount = 0
    end
end)
