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
M.uiHeight = 648

local function msgOut(text, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: " .. text, r or 1, g or 0.8, b or 0.0)
end

-- Tunable buff renew thresholds for the strike buffs
local HM_RENEW    = 7
local ZEAL_RENEW  = 12
local ZEAL_STACKS = 3

-- Judgement debuff detection (texture fragment on the TARGET)
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
        spells = { holyStrike = false, crusaderStrike = false, holyShield = false, hammerOfWrath = false, repentance = false },
    },
    retri = {
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        spells = { holyStrike = true, crusaderStrike = true, holyShield = false, hammerOfWrath = false, repentance = false },
    },
    prot = {
        seals = { debuff = "Seal of the Crusader", damage = "Seal of Righteousness" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        spells = { holyStrike = true, crusaderStrike = false, holyShield = true, hammerOfWrath = false, repentance = false },
    },
    heal = {  -- holds Seal of Wisdom, judges it once per enemy for the group debuff
        seals = { debuff = "Seal of Wisdom", damage = "" },
        manaManage = false, manaLow = 30, manaHigh = 70,
        hpManage = false, hpLow = 30, hpHigh = 70,
        spells = { holyStrike = false, crusaderStrike = false, holyShield = false, hammerOfWrath = false, repentance = false },
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
    local sk = { "holyStrike", "crusaderStrike", "holyShield", "hammerOfWrath", "repentance" }
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
    if cfg.spells.holyStrike     and not self:KnowsSpell("Holy Strike")     then table.insert(missing, "Holy Strike")     end
    if cfg.spells.crusaderStrike and not self:KnowsSpell("Crusader Strike") then table.insert(missing, "Crusader Strike") end
    if cfg.spells.holyShield     and not self:KnowsSpell("Holy Shield")     then table.insert(missing, "Holy Shield")     end
    if cfg.spells.hammerOfWrath  and not self:KnowsSpell("Hammer of Wrath") then table.insert(missing, "Hammer of Wrath") end
    if cfg.spells.repentance     and not self:KnowsSpell("Repentance")      then table.insert(missing, "Repentance")      end
    if cfg.manaManage and not self:KnowsSpell("Seal of Wisdom") then table.insert(missing, "Seal of Wisdom (mana)") end
    if cfg.hpManage   and not self:KnowsSpell("Seal of Light")  then table.insert(missing, "Seal of Light (hp)")    end
    return (table.getn(missing) == 0), missing
end

function M:TargetHasJudgementDebuff(sealName)
    local frag = self.debuffTex[sealName]
    if not frag or frag == "" then return false end
    for i = 1, 40 do
        local t = UnitDebuff("target", i)
        if t and string.find(t, frag) then return true end
    end
    return false
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
function M:StrikeEnabled(cfg)
    return cfg.spells.holyStrike or cfg.spells.crusaderStrike
end

function M:SharedStrikeReady(cfg)
    if cfg.spells.holyStrike     and self:KnowsSpell("Holy Strike")     and self:IsReady("Holy Strike")     then return true end
    if cfg.spells.crusaderStrike and self:KnowsSpell("Crusader Strike") and self:IsReady("Crusader Strike") then return true end
    return false
end

function M:ResolveSharedCD(cfg)
    local hs = cfg.spells.holyStrike and self:KnowsSpell("Holy Strike")
    local cs = cfg.spells.crusaderStrike and self:KnowsSpell("Crusader Strike")
    if hs and cs then
        -- both on: keep Holy Might, then build and hold Zeal
        local hmt = self:BuffTime("Holy Might")
        local zt, zc = self:BuffTime("Zeal")
        if hmt < HM_RENEW then return "Holy Strike" end
        if zc < ZEAL_STACKS then return "Crusader Strike" end
        if zt < ZEAL_RENEW then return "Crusader Strike" end
        return "Holy Strike"
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

-- ============================================================
-- Rotation. Strict single-cast priority with early returns, so exactly
-- one spell is chosen per press. Casting more than one CastSpellByName
-- per frame is unreliable in 1.12 (a later call overrides an earlier
-- one), which would invert the priority. The strike queues on the next
-- swing even out of range, so the swing start stays smooth.
-- Priority: 0 pre-cast seal while running in, 1 strike, 2 Holy Shield,
-- 3 seals/judgement, 4 Hammer, 5 Repentance.
-- ============================================================
function M:Rotate(cfg)
    self:UpdateManagement(cfg)

    if self.trace then
        local strk = (self:StrikeEnabled(cfg) and self:SharedStrikeReady(cfg)) and "Y" or "N"
        local db = cfg.seals.debuff
        self:Trace("strike=" .. strk
            .. " HShld(use=" .. (cfg.spells.holyShield and "Y" or "N")
            .. ",k=" .. (self:KnowsSpell("Holy Shield") and "Y" or "N")
            .. "," .. self:CDInfo("Holy Shield") .. ")"
            .. " debuff=" .. (db ~= "" and db or "-")
            .. " dbuff=" .. ((db ~= "" and self:TargetHasJudgementDebuff(db)) and "Y" or "N")
            .. " seen=" .. ((self.debuffSeenAt and (GetTime() - self.debuffSeenAt) < 1.5) and "Y" or "N")
            .. " dmg=" .. (cfg.seals.damage ~= "" and cfg.seals.damage or "-")
            .. " range=" .. (self:InMeleeRange() and "Y" or "N")
            .. " swing=" .. (self:SwingTimeLeft() and string.format("%.2fs", self:SwingTimeLeft()) or "-"))
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
        if pick and self:Cast(pick) then return end
    end
    -- 2. Holy Shield. Check its OWN cooldown and hold through the global
    -- cooldown so it reliably lands right after the strike and before seals,
    -- instead of losing the GCD edge to the unconditional seal recast.
    if cfg.spells.holyShield and self:OwnCDReady("Holy Shield") then
        if self:Cast("Holy Shield") then return end
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

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "seal"  then self:CmdSeal(t[2], string.lower(t[3] or ""), t[4]); return true end
    if cmd == "spell" then self:CmdSpell(t[2], t[3], t[4]); return true end
    return false
end