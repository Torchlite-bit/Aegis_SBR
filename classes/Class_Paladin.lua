-- ============================================================
-- Class_Paladin  -  paladin module for AutoRota
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

local M = AutoRota:NewClassModule("PALADIN")
M.uiTitle = "Paladin"
M.uiHeight = 706

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

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

-- Talents that change what the strikes do (Turtle WoW). Vengeful Strike is
-- what makes Holy Strike apply the Holy Might buff at all; Righteous Strike
-- makes Holy Strike a high-threat tanking tool. We read their ranks so the
-- rotation never maintains a buff the player cannot actually get.
local TALENT_HOLY_MIGHT = "Vengeful Strike"
local TALENT_THREAT     = "Righteous Strike"

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

-- Templates: starting presets, copied into the char's saved profiles once.
M.templates = {
    starter = {  -- valid for a brand new paladin (only Seal of Righteousness)
        seals = { debuff = "", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeMode = "auto",
        spells = { holyShield = false, hammerOfWrath = false, repentance = false },
    },
    retri = {
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeMode = "auto",
        spells = { holyShield = false, hammerOfWrath = false, repentance = false },
    },
    prot = {
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeMode = "auto",
        spells = { holyShield = true, hammerOfWrath = false, repentance = false },
    },
    heal = {  -- holds Seal of Wisdom, judges it once per enemy for the group debuff
        seals = { debuff = "Seal of Wisdom", damage = "" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        strikeMode = "off",
        spells = { holyShield = false, hammerOfWrath = false, repentance = false },
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
    holyshield = "holyShield",
    hammer = "hammerOfWrath", how = "hammerOfWrath",
    repentance = "repentance", rep = "repentance",
    consecration = "consecration", consec = "consecration", cons = "consecration",
    exorcism = "exorcism", exo = "exorcism",
}

-- Strike-mode aliases for /ar strike <mode>
M.strikeModeAlias = {
    off = "off", none = "off",
    auto = "auto",
    cs = "cs", crusader = "cs",
    hs = "hs", holy = "hs",
    hscs = "hscs", ["holy-cs"] = "hscs",
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

    -- Migrate the old per-strike checkboxes into the strikeMode dropdown, then
    -- drop the dead keys. Both on -> auto, one on -> that one, both off -> off.
    if c.strikeMode == nil and (c.spells.holyStrike ~= nil or c.spells.crusaderStrike ~= nil) then
        local hs, cs = c.spells.holyStrike, c.spells.crusaderStrike
        if hs and cs then c.strikeMode = "auto"
        elseif hs then c.strikeMode = "hs"
        elseif cs then c.strikeMode = "cs"
        else c.strikeMode = "off" end
    end
    c.spells.holyStrike = nil
    c.spells.crusaderStrike = nil

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
    if c.strikeMode == nil then c.strikeMode = "auto" end   -- auto | cs | hs | hscs
    if c.prioZeal == nil then c.prioZeal = false end
    if c.strikeDownrank == nil then c.strikeDownrank = false end
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
-- Strikes are on whenever the mode is not "off" and at least one strike is
-- known. Which strikes are usable is decided purely by KnowsSpell, so the mode
-- dropdown is the single enable + style control.
function M:StrikeEnabled(cfg)
    if (cfg.strikeMode or "auto") == "off" then return false end
    return self:KnowsSpell("Holy Strike") or self:KnowsSpell("Crusader Strike")
end

function M:SharedStrikeReady(cfg)
    if (cfg.strikeMode or "auto") == "off" then return false end
    if self:KnowsSpell("Holy Strike")     and self:IsReady("Holy Strike")     then return true end
    if self:KnowsSpell("Crusader Strike") and self:IsReady("Crusader Strike") then return true end
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

-- Opener: the first strike on a fresh target. Auto gets Holy Might up first if
-- the talent makes it work, else opens by the tanking lean (weapon/threat).
function M:ResolveOpener(cfg)
    local m = cfg.strikeMode or "auto"
    if m == "cs" then return "Crusader Strike" end
    if m == "hs" or m == "hscs" then return "Holy Strike" end
    if self:HolyMightWorthwhile() then return "Holy Strike" end   -- ret: get Holy Might rolling
    if self:AutoLeansHoly() then return "Holy Strike" end          -- tank: threat opener
    return "Crusader Strike"                                       -- leveling/dps: just build Zeal
end

-- Filler lean once both buffs are maintained: "holy" or "crusader".
function M:ResolveFiller(cfg)
    local m = cfg.strikeMode or "auto"
    if m == "cs" or m == "hscs" then return "crusader" end
    if m == "hs" then return "holy" end
    if self:AutoLeansHoly() then return "holy" end                 -- tanking leans Holy Strike
    return "crusader"
end

function M:ResolveSharedCD(cfg)
    local hs = self:KnowsSpell("Holy Strike")
    local cs = self:KnowsSpell("Crusader Strike")
    if hs and cs then
        -- Opener: fire the chosen first strike once per fresh target.
        local id = self:TargetId()
        if id ~= self.strikeTargetId then
            self.strikeTargetId = id
            self.strikeOpened = false
        end
        if not self.strikeOpened then
            self.strikeOpened = true
            return self:ResolveOpener(cfg)
        end

        local hmt = self:BuffTime("Holy Might")
        local zt, zc = self:BuffTime("Zeal")

        -- Optionally rush Zeal to full stacks before anything else.
        if cfg.prioZeal and zc < ZEAL_STACKS then return "Crusader Strike" end

        -- Maintain Holy Might ONLY if a talent makes Holy Strike apply it,
        -- so a leveling paladin never burns globals on a buff it cannot get.
        if self:HolyMightWorthwhile() and hmt < HM_RENEW then return "Holy Strike" end

        -- Keep Zeal built and rolling.
        if zc < ZEAL_STACKS then return "Crusader Strike" end
        if zt < ZEAL_RENEW then return "Crusader Strike" end

        -- Filler lean.
        if self:ResolveFiller(cfg) == "holy" then return "Holy Strike" end
        return "Crusader Strike"
    elseif hs then
        return "Holy Strike"
    elseif cs then
        return "Crusader Strike"
    end
    return nil
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
-- one), which would invert the priority. The strike queues on the next
-- swing even out of range, so the swing start stays smooth.
-- Priority: 0 pre-cast seal while running in, 1 strike, 2 Holy Shield,
-- 2b Consecration (when AoE-toggled on), 3 seals/judgement, 4 Hammer,
-- 5 Repentance, 6 Exorcism (undead/demon). Exorcism stays low so it never
-- delays a strike, Holy Shield, seal upkeep, or the execute; both Consecration
-- and Exorcism are skipped during mana recovery so they do not undo it.
-- ============================================================
function M:Rotate(cfg)
    self:UpdateManagement(cfg)

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
            "mode=" .. (cfg.strikeMode or "auto")
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
    -- normal strict priority below applies. We never judge out of range.
    if not self:InMeleeRange() then
        local s = self:DesiredOpenerSeal(cfg)
        if s and self:KnowsSpell(s) and not self:HasBuff(s) then
            if self:Cast(s) then return end
        end
    end

    -- 1. Strike
    if self:StrikeEnabled(cfg) and self:SharedStrikeReady(cfg) then
        local pick = self:ResolveSharedCD(cfg)
        if pick and self:CastStrike(pick, cfg) then return end
    end
    -- 2. Holy Shield. Check its OWN cooldown and hold through the global
    -- cooldown so it reliably lands right after the strike and before seals,
    -- instead of losing the GCD edge to the unconditional seal recast.
    if cfg.spells.holyShield and self:OwnCDReady("Holy Shield") then
        if self:Cast("Holy Shield") then return end
    end
    -- 2b. Consecration leads AoE: when toggled on (checkbox or /ar aoe), cast it
    -- on cooldown right after the strike so it is a primary AoE source rather
    -- than a leftover filler. Held during mana recovery. Ground-targeted, but a
    -- plain cast drops it at your feet on the usual SuperWoW/Nampower setup.
    if cfg.spells.consecration and not self.manaMgmtActive
        and self:KnowsSpell("Consecration") and self:IsReady("Consecration") then
        if self:Cast("Consecration") then return end
    end
    -- 3. Seal upkeep and judgement
    if self:HandleSeals(cfg) then return end
    -- 4. Hammer of Wrath as execute
    if cfg.spells.hammerOfWrath and self:TargetHPPct() <= 20 and self:IsReady("Hammer of Wrath") then
        if self:Cast("Hammer of Wrath") then return end
    end
    -- 5. Repentance (boss damage proc on Turtle)
    if cfg.spells.repentance and self:IsReady("Repentance") then
        if self:Cast("Repentance") then return end
    end
    -- 6. Exorcism, a strong nuke but only against Undead and Demon targets.
    -- Skipped during mana recovery so it does not burn the mana we are saving.
    if cfg.spells.exorcism and not self.manaMgmtActive
        and self:KnowsSpell("Exorcism") and self:TargetIsUndeadOrDemon()
        and self:IsReady("Exorcism") then
        if self:Cast("Exorcism") then return end
    end
end

function M:CmdSeal(name, slot, alias)
    local cfg = name and AutoRotaDB.profiles[name]
    if not cfg then msgOut("profile not found.", 1, 0.5, 0.3); return end
    if slot ~= "debuff" and slot ~= "damage" then msgOut("slot must be debuff or damage.", 1, 0.5, 0.3); return end
    local seal = self.sealAlias[string.lower(alias or "")]
    if seal == nil then msgOut("unknown seal alias.", 1, 0.5, 0.3); return end
    cfg.seals[slot] = seal
    msgOut("'" .. name .. "' " .. slot .. " seal = " .. ((seal == "") and "(none)" or seal) .. ".")
end

function M:CmdSpell(name, alias, onoff)
    local cfg = name and AutoRotaDB.profiles[name]
    if not cfg then msgOut("profile not found.", 1, 0.5, 0.3); return end
    local key = self.spellAlias[string.lower(alias or "")]
    if not key then msgOut("unknown spell alias.", 1, 0.5, 0.3); return end
    cfg.spells[key] = (string.lower(onoff or "") == "on")
    msgOut("'" .. name .. "' " .. key .. " = " .. (cfg.spells[key] and "on" or "off") .. ".")
end

-- Quick AoE toggle: flips Consecration on the active profile, for binding to
-- a key. There is no reliable enemy count on 1.12, so this stays manual.
function M:CmdAoe()
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.spells.consecration = not cfg.spells.consecration
    msgOut("Consecration " .. (cfg.spells.consecration and "on (AoE)" or "off") .. ".")
end

-- Set the strike mode on the active profile (off/auto/cs/hs/hscs), for macros.
function M:CmdStrike(alias)
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local mode = self.strikeModeAlias[string.lower(alias or "")]
    if not mode then msgOut("usage: /ar strike off|auto|cs|hs|hscs", 1, 0.5, 0.3); return end
    cfg.strikeMode = mode
    msgOut("strike mode = " .. mode .. ".")
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "seal"   then self:CmdSeal(t[2], string.lower(t[3] or ""), t[4]); return true end
    if cmd == "spell"  then self:CmdSpell(t[2], t[3], t[4]); return true end
    if cmd == "aoe"    then self:CmdAoe(); return true end
    if cmd == "strike" then self:CmdStrike(t[2]); return true end
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
