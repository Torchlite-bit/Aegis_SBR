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
M.uiHeight = 820

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- Tunable buff renew thresholds for the strike buffs
local HM_RENEW    = 7
local ZEAL_RENEW  = 12
local ZEAL_STACKS = 3

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
        seals = { debuff = "", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "autodps",
        spells = { holyStrike = false, crusaderStrike = false, holyShield = false, hammerOfWrath = false, repentance = false },
    },
    retri = {
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "autodps",
        spells = { holyStrike = true, crusaderStrike = true, holyShield = false, hammerOfWrath = false, repentance = false },
    },
    prot = {
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "tankblock",
        spells = { holyStrike = true, crusaderStrike = true, holyShield = true, hammerOfWrath = false, repentance = false },
    },
    heal = {  -- group healer: heals the party/raid, keeps Seal of Wisdom for mana
        seals = { debuff = "", damage = "" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeStyle = "autodps",
        spells = { holyStrike = false, crusaderStrike = false, holyShield = false, hammerOfWrath = false, repentance = false },
        healMode = true, healThreshold = 75, useHolyShock = true, holyShockPct = 50, healPower = 0,
        healWeaveManaFloor = 40, healReloadCS = true, healSplashHS = true,
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
    if c.healThreshold == nil then c.healThreshold = 75 end
    if c.useHolyShock == nil then c.useHolyShock = true end
    if c.holyShockPct == nil then c.holyShockPct = 50 end
    -- Split the old single heal-weave toggle into two independent behaviours
    -- (CS reload of Holy Shock, and Holy Strike filler), then retire it.
    if c.healReloadCS == nil then c.healReloadCS = (c.healWeaveStrikes ~= false) end
    if c.healSplashHS == nil then c.healSplashHS = (c.healWeaveStrikes ~= false) end
    c.healWeaveStrikes = nil
    if c.healWeaveManaFloor == nil then c.healWeaveManaFloor = 40 end
    if c.healPower == nil then c.healPower = 0 end
    -- Heal-mode mana upkeep. Self seal defaults on (free sustain); the group
    -- judge defaults off because it spends a GCD that cannot be a heal.
    if c.healManaSelf  == nil then c.healManaSelf  = true  end
    if c.healManaJudge == nil then c.healManaJudge = false end
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
function M:CastStrike(name, cfg)
    if cfg.strikeDownrank then
        local maxR = self:MaxRank(name)
        local r = self:DownrankFor(name)
        if r and maxR > 0 and r < maxR then
            CastSpellByName(name .. "(Rank " .. r .. ")")
            return true
        end
    end
    return self:Cast(name)
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

function M:HandleSeals(cfg)
    -- Returns true if a cast was issued, so the caller can stop.
    if not self.manaMgmtActive then self.weaving = false end

    local debuffSeal = cfg.seals.debuff
    local dmgSeal    = cfg.seals.damage
    local canJudge   = self:KnowsSpell("Judgement") -- Safety check for low levels

    -- During mana recovery, optionally apply the Seal of Wisdom debuff (Judgement
    -- of Wisdom) instead of the configured one, since it returns mana to attackers
    -- and aids recovery. Toggled per profile.
    local effDebuff = debuffSeal
    if self.manaMgmtActive and cfg.manaWisdomDebuff and self:KnowsSpell("Seal of Wisdom") then
        effDebuff = "Seal of Wisdom"
    end

    -- (A) Always make sure a new mob carries the (effective) debuff.
    -- Skipped if Judgement is not yet learned.
    if effDebuff ~= "" and canJudge and not self:DebuffEffectivelyUp(effDebuff) then
        if not self:HasBuff(effDebuff) then return self:Cast(effDebuff) end
        if self:IsReady("Judgement") then return self:Cast("Judgement") end
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
            if not self:HasBuff(dmg) then return self:Cast(dmg) end
            if canJudge and self:IsReady("Judgement") then
                local c = self:Cast("Judgement")
                self.weaving = false
                return c
            end
            return false
        end
        if canWeave and canJudge and self:IsReady("Judgement") and self:ManaPct() >= (cfg.manaWeaveMin or 0) then
            self.weaving = true
            return self:Cast(dmg)
        end
        self.weaving = false
        if not self:HasBuff("Seal of Wisdom") then return self:Cast("Seal of Wisdom") end
        return false
    end

    -- (C) HP management: hold Seal of Light
    if self.hpMgmtActive then
        if not self:HasBuff("Seal of Light") then return self:Cast("Seal of Light") end
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

    if not self:HasBuff(seal) then return self:Cast(seal) end       -- seal must be up before judging
    
    if judgeIt and canJudge and self:IsReady("Judgement") then
        -- Seal twisting: hold the damage seal judge until just before the next
        -- white swing, so the swing carries the seal proc and the judgement land
        -- together. The debuff judge in (A) is never delayed. Unknown timer judges now.
        if cfg.sealTwist and seal == dmgSeal and dmgSeal ~= "" then
            local tl = self:SwingTimeLeft()
            if tl and tl > 0.4 then return false end
        end
        return self:Cast("Judgement")
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

-- Exorcism only works on Undead and Demon targets.
function M:TargetIsUndeadOrDemon()
    local t = UnitCreatureType("target")
    return t == "Undead" or t == "Demon"
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
-- Also stamps their real HP at commit time (see PendingFor) and our own
-- expected cast completion (see StillCasting) - Holy Light's 2.5s cast is
-- longer than the 1.5s global cooldown, so GcdReady() alone reports "ready"
-- up to a full second before the cast actually finishes.
function M:CommitHeal(unit, amount, castTime)
    self.healTarget = UnitName(unit)
    self.healAmount = amount or 0
    self.healUntil = GetTime() + (castTime or 0) + 1.0
    self.healBaseline = UnitHealth(unit)
    self.castingUntil = GetTime() + (castTime or 0)
end

-- True while our own heal cast is still expected to be resolving, even after
-- the shared GCD (1.5s) has already cleared - closes the gap for any heal
-- whose cast time exceeds the GCD (Holy Light at 2.5s), where a spammed
-- press could otherwise start a second heal before the first has landed,
-- since the target's HP (and PendingFor's prediction) hasn't updated yet.
function M:StillCasting()
    return self.castingUntil and GetTime() < self.castingUntil
end

-- Predicted incoming heal for a unit from our own pending cast, else 0. Only
-- trusted while their REAL health hasn't dropped below what it was at commit
-- time - otherwise new damage landed after the heal was queued, and letting
-- the stale prediction pad WorstHurt's health estimate back up would mask a
-- fresh crisis for the rest of the cast (up to ~castTime + 1s) instead of
-- reacting to it immediately.
function M:PendingFor(unit)
    if self.healTarget and GetTime() < self.healUntil and UnitName(unit) == self.healTarget then
        if UnitHealth(unit) >= (self.healBaseline or 0) then
            return self.healAmount
        end
    end
    return 0
end

-- Units to consider for healing: raid1..N in a raid, else player + party1..N.
function M:GroupUnits()
    local units = {}
    local nr = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if nr > 0 then
        for i = 1, nr do table.insert(units, "raid" .. i) end
    else
        table.insert(units, "player")
        local np = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, np do table.insert(units, "party" .. i) end
    end
    return units
end

-- Self is always reachable; others must be within heal range. Uses
-- IsSpellInRange against the longest-range known heal (Flash of Light/Holy
-- Light, both 40yd) for an exact answer instead of CheckInteractDistance's
-- ~28yd proxy, which under-filtered by 12yd. Falls back to the proxy only if
-- neither heal is learned yet (very early leveling).
function M:Reachable(u)
    if UnitIsUnit(u, "player") then return true end
    if self:KnowsSpell("Flash of Light") then return IsSpellInRange("Flash of Light", u) == 1
    elseif self:KnowsSpell("Holy Light") then return IsSpellInRange("Holy Light", u) == 1 end
    return CheckInteractDistance(u, 4)
end

-- The healable group member with the lowest effective health below ratio,
-- counting our own in-flight heal. Returns unit, missing health, ratio.
function M:WorstHurt(ratio)
    local units = self:GroupUnits()
    local bestU, bestPct, bestDef = nil, ratio, 0
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsFriend("player", u) and UnitHealthMax(u) > 0 and self:Reachable(u) then
            local mx = UnitHealthMax(u)
            local cur = UnitHealth(u) + self:PendingFor(u)
            if cur > mx then cur = mx end
            local pct = cur / mx
            if pct < bestPct then
                bestPct = pct; bestU = u; bestDef = mx - cur
            end
        end
    end
    return bestU, bestDef, bestPct
end

-- True while healing is needed, so the attack rotation yields. Uses real health
-- (no in-flight prediction) so a heal already on the way still counts as demand
-- and keeps a Seal of Wisdom judgement from stealing the global cooldown.
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
function M:HealMods()
    local _, _, _, _, hlRank = GetTalentInfo(1, 6)
    local _, _, _, _, dfRank = GetTalentInfo(1, 13)
    return 1 + 0.04 * (hlRank or 0), 1 + 0.05 * (dfRank or 0)
end

-- Effective heal per rank: base + healing-coefficient * bonus, then talents.
function M:EffHeals(baseHeals, coeff, mods, healPower)
    local t = {}
    for r = 1, table.getn(baseHeals) do
        t[r] = (baseHeals[r] + coeff * (healPower or 0)) * mods
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
-- (Mortal-Strike-type debuffs), mirroring QuickHeal's icon-based detection.
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

-- Heal decision. Returns true when a heal was cast (or the GCD is held) this
-- press. Holy Shock for an emergency or an out-of-range unit, otherwise a
-- downranked Flash of Light, with Holy Light for large deficits - unless the
-- target is below the emergency line, where Flash of Light's faster cast
-- stays the safer bet even if it cannot fully cover the deficit.
function M:DoHeal(cfg)
    local ratio = (cfg.healThreshold or 75) / 100
    local unit, deficit, pct = self:WorstHurt(ratio)
    if not unit then return false end

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
    local hlMod, dfMod = self:HealMods()
    local C15, C25 = 1.5 / 3.5, 2.5 / 3.5
    local folEff = self:EffHeals(self.FOL_HEAL, C15, hlMod, hp)
    local hlEff  = self:EffHeals(self.HL_HEAL,  C25, hlMod, hp)
    local hsEff  = self:EffHeals(self.HS_HEAL,  C15, hlMod * dfMod, hp)

    -- Healing-reduction debuffs (Mortal Strike and the like) inflate the
    -- effective deficit for rank selection, so a stronger rank is picked;
    -- the amount actually committed for in-flight tracking is scaled back
    -- down since the extra healing never lands.
    local hdb = self:HealDebuffModifier(unit)
    local rankDeficit = (hdb < 1) and (deficit / hdb) or deficit

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
        and (pct <= (cfg.holyShockPct or 50) / 100 or not CheckInteractDistance(unit, 3))
        and IsSpellInRange("Holy Shock", unit) == 1 then
        local hs, amt = self:PickRank("Holy Shock", hsEff, self.HS_MANA, rankDeficit, mana)
        if hs then
            self:CommitHeal(unit, amt * hdb, 0)
            self:CastOn(hs, unit)
            return true
        end
    end

    -- Cast-time compensation: the target keeps losing health while the cast
    -- is in flight, so in combat the deficit is padded before comparing it
    -- against each spell's ranks - Flash of Light (1.5s) less than Holy
    -- Light (2.5s), mirroring QuickHeal's k/K factors.
    local inCombat = UnitAffectingCombat("player") or UnitAffectingCombat(unit)
    local folDeficit = inCombat and (rankDeficit / 0.9) or rankDeficit
    local hlDeficit  = inCombat and (rankDeficit / 0.8) or rankDeficit

    -- Below the Holy Shock emergency line, stay on the faster Flash of Light
    -- even for a deficit it cannot fully cover - a fast partial heal beats
    -- risking the target dying mid-cast on a slow Holy Light.
    local emergency = pct <= (cfg.holyShockPct or 50) / 100

    if emergency then
        local fol, folRaw = self:PickRank("Flash of Light", folEff, self.FOL_MANA, folDeficit, mana)
        if fol then self:CommitHeal(unit, folRaw * hdb, 1.5); self:CastOn(fol, unit); return true end
        -- Flash of Light itself cannot be cast (unlearned/unaffordable): Holy
        -- Light as a last resort, better than holding the GCD entirely.
        local hl, hlRaw = self:PickRank("Holy Light", hlEff, self.HL_MANA, hlDeficit, mana)
        if hl then self:CommitHeal(unit, hlRaw * hdb, 2.5); self:CastOn(hl, unit); return true end
        return false
    end

    -- Not an emergency: get each spell's best candidate rank, then pick
    -- whichever actually-landing heal (after the debuff modifier) wastes the
    -- least - a rank that covers the deficit beats one that falls short, and
    -- between two that cover it, the smaller one wins unless Holy Light is
    -- clearly (>=10%) more efficient, which keeps trivial ties on the faster
    -- Flash of Light instead of flip-flopping to a slower cast for pennies.
    local fol, folRaw = self:PickRank("Flash of Light", folEff, self.FOL_MANA, folDeficit, mana)
    local hl,  hlRaw  = self:PickRank("Holy Light", hlEff, self.HL_MANA, hlDeficit, mana)
    local folLanded = fol and (folRaw * hdb) or nil
    local hlLanded  = hl  and (hlRaw  * hdb) or nil
    local folCovers = folLanded and folLanded >= deficit
    local hlCovers  = hlLanded  and hlLanded  >= deficit

    local pick, amt, castTime
    if folCovers and hlCovers then
        if hlLanded <= folLanded * 0.9 then pick, amt, castTime = hl, hlLanded, 2.5
        else pick, amt, castTime = fol, folLanded, 1.5 end
    elseif folCovers then pick, amt, castTime = fol, folLanded, 1.5
    elseif hlCovers then pick, amt, castTime = hl, hlLanded, 2.5
    elseif fol and hl then
        -- Neither covers it: take the bigger partial heal so the group is
        -- topped off in fewer presses.
        if folLanded >= hlLanded then pick, amt, castTime = fol, folLanded, 1.5
        else pick, amt, castTime = hl, hlLanded, 2.5 end
    elseif fol then pick, amt, castTime = fol, folLanded, 1.5
    elseif hl then pick, amt, castTime = hl, hlLanded, 2.5
    end

    if pick then self:CommitHeal(unit, amt, castTime); self:CastOn(pick, unit); return true end
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

-- Toggle B - Holy Strike filler: in downtime with nobody to heal, strike so the
-- Holy Strike splash tops the melee group (Crusader Strike only as a fallback
-- before Holy Strike is trained). Gated by its own mana floor, so the filler
-- never starves a heal. Each cast is a GCD, hence its own opt-in.
function M:HealWeaveStrike(cfg)
    if not cfg.healSplashHS then return false end
    if not self:HealMeleeReady(cfg) then return false end
    -- Only worth the GCD if someone actually has a scratch to top off - by the
    -- time this runs, HealStrikeEngine/DoHeal/HealDemand have already ruled out
    -- anyone below the priority threshold, but a fully-topped group (everyone at
    -- 100%) would otherwise still eat a splash cast for pure overheal.
    if not self:WorstHurt(1.0) then return false end
    local maxm = UnitManaMax("player")
    if not maxm or maxm == 0 then return false end
    if UnitMana("player") / maxm * 100 < (cfg.healWeaveManaFloor or 40) then return false end
    local pick
    if self:KnowsSpell("Holy Strike") then pick = "Holy Strike"
    elseif self:KnowsSpell("Crusader Strike") then pick = "Crusader Strike" end
    if not pick or not self:IsReady(pick) then return false end
    return self:CastStrike(pick, cfg)
end

-- Heal-mode mana upkeep. Keeps Seal of Wisdom up so melee swings return mana to
-- you, and optionally judges it once per mob (Judgement of Wisdom) so the whole
-- group gets mana back. Only worthwhile in melee on an attackable mob. Heals
-- always preempt this above, so it never runs while anyone needs healing - but
-- the group judge still spends a GCD, hence it is opt-in.
function M:HealSeals(cfg)
    if not (cfg.healManaSelf or cfg.healManaJudge) then return false end
    if not self:KnowsSpell("Seal of Wisdom") then return false end
    if not (UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")) then return false end
    if not self:InMeleeRange() then return false end
    -- Seal of Wisdom must be up (both the self-mana and the judge need it).
    if not self:HasBuff("Seal of Wisdom") then return self:Cast("Seal of Wisdom") end
    -- Stamp Judgement of Wisdom on the mob once, if the group judge is enabled.
    if cfg.healManaJudge and self:KnowsSpell("Judgement") and self:IsReady("Judgement")
        and not self:DebuffEffectivelyUp("Seal of Wisdom") then
        return self:Cast("Judgement")
    end
    return false
end

function M:Rotate(cfg)
    self:UpdateManagement(cfg)

    -- Heal mode, melee-holy: the Blessed Strikes engine reloads Holy Shock
    -- between heals (never over an emergency), then group healing preempts the
    -- attack rotation, so a judgement or strike GCD never delays a needed heal.
    if cfg.healMode and self:HealStrikeEngine(cfg) then return end
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
        if self:HealDemand(cfg) then return end
        if self:HealWeaveStrike(cfg) then return end
        if self:HealSeals(cfg) then return end
    end

    if self.trace then
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
                .. " mana=" .. UnitMana("player")
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
            if self:Cast(s) then return end
        end
    end

    -- 1. Strike (damage/tank mode only; heal mode has its own strike weaving,
    -- HealStrikeEngine/HealWeaveStrike, above)
    if not cfg.healMode and self:StrikeEnabled(cfg) and self:SharedStrikeReady(cfg) then
        local pick = self:ResolveSharedCD(cfg)
        if pick and self:CastStrike(pick, cfg) then return end
    end
    -- 2. Holy Shield. Check its OWN cooldown and hold through the global
    -- cooldown so it reliably lands right after the strike and before seals,
    -- instead of losing the GCD edge to the unconditional seal recast.
    -- (damage/tank mode only, same reasoning as the strike above)
    if not cfg.healMode and cfg.spells.holyShield and self:OwnCDReady("Holy Shield") then
        if self:Cast("Holy Shield") then return end
    end
    -- 2b. Consecration leads AoE: when toggled on (checkbox or /sbr aoe), cast it
    -- on cooldown right after the strike so it is a primary AoE source rather
    -- than a leftover filler. Held during mana recovery. Ground-targeted, but a
    -- plain cast drops it at your feet on the usual SuperWoW/Nampower setup.
    -- (damage/tank mode only)
    if not cfg.healMode and cfg.spells.consecration and not self.manaMgmtActive
        and self:KnowsSpell("Consecration") and self:IsReady("Consecration") then
        if self:Cast("Consecration") then return end
    end
    -- 3. Seal upkeep and judgement (damage/tank mode only; heal mode runs its
    -- own Seal of Wisdom upkeep via HealSeals above)
    if not cfg.healMode and self:HandleSeals(cfg) then return end
    -- 4. Hammer of Wrath as execute (damage/tank mode only)
    if not cfg.healMode and cfg.spells.hammerOfWrath and self:TargetHPPct() <= 20 and self:IsReady("Hammer of Wrath") then
        if self:Cast("Hammer of Wrath") then return end
    end
    -- 5. Repentance (boss damage proc on Turtle) (damage/tank mode only)
    if not cfg.healMode and cfg.spells.repentance and self:IsReady("Repentance") then
        if self:Cast("Repentance") then return end
    end
    -- 6. Exorcism, a strong nuke but only against Undead and Demon targets.
    -- Skipped during mana recovery so it does not burn the mana we are saving.
    -- (damage/tank mode only)
    if not cfg.healMode and cfg.spells.exorcism and not self.manaMgmtActive
        and self:KnowsSpell("Exorcism") and self:TargetIsUndeadOrDemon()
        and self:IsReady("Exorcism") then
        if self:Cast("Exorcism") then return end
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
    cfg.spells[key] = (string.lower(onoff or "") == "on")
    msgOut("'" .. name .. "' " .. key .. " = " .. (cfg.spells[key] and "on" or "off") .. ".")
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
function M:HandleCommand(cmd, t)
    if cmd == "seal"   then self:CmdSeal(t[2], string.lower(t[3] or ""), t[4]); return true end
    if cmd == "spell"  then self:CmdSpell(t[2], t[3], t[4]); return true end
    if cmd == "aoe"    then self:CmdAoe(); return true end
    if cmd == "strike" then self:CmdStrike(t[2]); return true end
    if cmd == "heal" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local a = string.lower(t[2] or "")
        if a == "on" then cfg.healMode = true; msgOut("heal mode on.")
        elseif a == "off" then cfg.healMode = false; msgOut("heal mode off.")
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
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_LOGIN")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
talentFrame:SetScript("OnEvent", function()
    M.talentCache = nil
end)
