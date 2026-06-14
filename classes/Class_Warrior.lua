-- ============================================================
-- Class_Warrior  -  warrior module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). Roleless, configurable, all specs.
-- ============================================================
-- Model:
--  * Warriors are gated by STANCE and RAGE, not mana. The core's
--    self:Cast() reports success whenever a spell is merely KNOWN, which
--    is fine for paladin/rogue but would stall our priority chain the
--    moment a known ability is uncastable (wrong stance / not enough
--    rage). So this module uses self:CanCast(name, rageCost, stances)
--    before committing to any GCD ability, and gates stance-restricted
--    abilities explicitly. Stance rules follow vanilla 1.12; if Turtle
--    relaxes a restriction we simply stay conservative (never unsafe).
--  * Off-GCD / on-next-swing abilities (Heroic Strike, Cleave, Death
--    Wish, Recklessness, Berserker Rage, Bloodrage, Shield Block) are
--    fired in a "fire and continue" layer, then exactly one GCD ability
--    is chosen by strict priority with early returns, the same single
--    cast per press discipline the paladin and rogue modules use.
--  * Reactive procs (Overpower after the target dodges, Revenge after we
--    block/dodge/parry) are tracked from the combat log into short
--    windows, mirroring the rogue's Riposte tracker.
--  * AoE has no reliable enemy counter on 1.12 (SuperWoW exposes none),
--    so AoE is a manual toggle, flippable mid-fight with /ar aoe.
--  * Cooldowns follow the rogue's pattern: pop always, only on
--    elite/boss, or never (manual) via two checkboxes.
-- ============================================================

local M = AutoRota:NewClassModule("WARRIOR")
M.uiTitle = "Warrior"
M.uiHeight = 730

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- Reactive proc windows (seconds). Overpower and Revenge stay usable for
-- about 5s after the triggering event.
local REACT_WINDOW = 5.0
-- Minimum gap between stance switches; stance changes have a ~1s internal
-- cooldown, so we never thrash faster than this.
local STANCE_CD = 1.0
-- Light throttle so a rapid press burst does not re-issue the queued
-- on-next-swing ability several times in the same swing.
local DUMP_THROTTLE = 0.3

-- Stance key -> spell name. Used by the home-stance setting and switching.
M.STANCES = {
    battle    = "Battle Stance",
    defensive = "Defensive Stance",
    berserker = "Berserker Stance",
}

-- Approximate base rage costs, used only to decide whether to ATTEMPT a
-- GCD ability (so the priority can fall through to a cheaper one instead
-- of stalling). Talents/ranks shift these a little; values are slightly
-- forgiving on purpose. Tune here if a spec feels like it skips casts.
local RAGE = {
    ["Mortal Strike"] = 30,
    ["Bloodthirst"]   = 30,
    ["Shield Slam"]   = 20,
    ["Whirlwind"]     = 25,
    ["Slam"]          = 15,
    ["Execute"]       = 10,   -- 15 base, but consumes all extra rage
    ["Overpower"]     = 5,
    ["Revenge"]       = 5,
    ["Sunder Armor"]  = 12,   -- 15 base, often reduced
    ["Thunder Clap"]  = 20,
}

-- Stances an ability may be used from (vanilla 1.12). nil = any stance.
local STANCE_REQ = {
    ["Mortal Strike"] = { "Battle Stance", "Berserker Stance" },
    ["Whirlwind"]     = { "Berserker Stance" },
    ["Execute"]       = { "Battle Stance", "Berserker Stance" },
    ["Overpower"]     = { "Battle Stance" },
    ["Revenge"]       = { "Defensive Stance" },
    ["Thunder Clap"]  = { "Battle Stance" },
    ["Recklessness"]  = { "Berserker Stance" },
    ["Berserker Rage"]= { "Berserker Stance" },
    ["Shield Block"]  = { "Defensive Stance" },
    -- Bloodthirst, Shield Slam, Slam, Sunder Armor, Heroic Strike, Cleave,
    -- Death Wish, Bloodrage: usable in any stance (Shield Slam needs a shield).
}

M.spellAlias = {
    mortalstrike = "useMortalStrike", ms = "useMortalStrike",
    bloodthirst = "useBloodthirst", bt = "useBloodthirst",
    shieldslam = "useShieldSlam", ss = "useShieldSlam",
    whirlwind = "useWhirlwind", ww = "useWhirlwind",
    slam = "useSlam",
    overpower = "useOverpower", op = "useOverpower",
    revenge = "useRevenge", rev = "useRevenge",
    execute = "useExecute", exec = "useExecute",
    sunder = "useSunder", sa = "useSunder",
    thunderclap = "useThunderClap", tc = "useThunderClap",
    heroicstrike = "useHeroicStrike", hs = "useHeroicStrike",
    cleave = "useCleave",
    sweeping = "useSweeping", sweep = "useSweeping",
    deathwish = "useDeathWish", dw = "useDeathWish",
    recklessness = "useRecklessness", reck = "useRecklessness",
    berserkerrage = "useBerserkerRage", br = "useBerserkerRage",
    bloodrage = "useBloodrage", bld = "useBloodrage",
    shieldblock = "useShieldBlock", sb = "useShieldBlock",
}

-- Templates: starting presets, copied into the char's saved profiles once.
M.templates = {
    starter = {  -- valid for any warrior at any level: Execute, rage dump, Bloodrage
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = false, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = false, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 60, wwExcess = 60,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
    },
    fury = {
        useMortalStrike = false, useBloodthirst = true, useShieldSlam = false,
        useWhirlwind = true, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = true, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 50,
        popCDs = false, autoCDElite = true,
        useDeathWish = true, useRecklessness = true, useBerserkerRage = true,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
    },
    arms = {
        useMortalStrike = true, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = true, useSlam = false,
        useOverpower = true, useRevenge = false, useExecute = true,
        stanceDance = true, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = true, useCleave = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 55,
        popCDs = false, autoCDElite = true,
        useDeathWish = false, useRecklessness = true, useBerserkerRage = true,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
    },
    prot = {
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = true,
        useWhirlwind = false, useSlam = false,
        useOverpower = false, useRevenge = true, useExecute = false,
        stanceDance = false, homeStance = "defensive",
        useSunder = true, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 50, wwExcess = 70,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = true,
    },
}

-- Fills any missing field with a default. No old-format migration yet,
-- so unknown keys are simply left alone.
function M:NormalizeProfile(c)
    local b = {
        useMortalStrike = false, useBloodthirst = false, useShieldSlam = false,
        useWhirlwind = false, useSlam = false,
        useOverpower = false, useRevenge = false, useExecute = true,
        stanceDance = false, homeStance = "berserker",
        useSunder = false, sunderStacks = 5, useThunderClap = false,
        aoeMode = false, useSweeping = false, useCleave = true,
        useHeroicStrike = true, dumpRage = 60, wwExcess = 60,
        popCDs = false, autoCDElite = false,
        useDeathWish = false, useRecklessness = false, useBerserkerRage = false,
        useBloodrage = true, bloodrageRage = 30, useShieldBlock = false,
    }
    for k, v in pairs(b) do
        if c[k] == nil then c[k] = v end
    end
    if not self.STANCES[c.homeStance] and c.homeStance ~= "none" then c.homeStance = "berserker" end
    return c
end

-- Nothing is hard-required: the rotation degrades gracefully through
-- KnowsSpell, so any profile can be activated and used while leveling.
-- Unlearned abilities are flagged in the UI labels, not here.
function M:ProfileValidity(cfg)
    return true, {}
end

-- ============================================================
-- Rage and stance helpers
-- ============================================================
function M:Rage()
    return UnitMana("player") or 0
end

function M:CurrentStanceName()
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, n do
        local _, name, isActive = GetShapeshiftFormInfo(i)
        if isActive then return name end
    end
    return nil
end

function M:InStance(name)
    return self:CurrentStanceName() == name
end

function M:InAnyStance(list)
    if not list then return true end
    local cur = self:CurrentStanceName()
    if not cur then return true end   -- no stance info, do not block
    for i = 1, table.getn(list) do
        if list[i] == cur then return true end
    end
    return false
end

function M:StanceIndex(name)
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, n do
        local _, sName = GetShapeshiftFormInfo(i)
        if sName == name then return i end
    end
    return nil   -- stance not learned
end

-- Switch to a named stance if it is learned, not already active, and the
-- swap cooldown has elapsed. Returns true if a switch was issued.
function M:SwitchStance(name)
    local idx = self:StanceIndex(name)
    if not idx then return false end
    if self:CurrentStanceName() == name then return false end
    local now = GetTime()
    if now - (self.lastStanceSwap or 0) < STANCE_CD then return false end
    CastShapeshiftForm(idx)
    self.lastStanceSwap = now
    return true
end

-- True only if the ability is known, off cooldown (own cd, ignoring the
-- raw GCD edge), affordable, and usable in the current stance. This is the
-- gate that keeps a stance/rage locked ability from stalling the chain.
function M:CanCast(name, rageCost, stances)
    if not self:KnowsSpell(name) then return false end
    if not self:IsReady(name) then return false end
    if rageCost and self:Rage() < rageCost then return false end
    if stances and not self:InAnyStance(stances) then return false end
    return true
end

-- Convenience wrapper that reads the rage cost and stance requirement from
-- the tables above, then attempts the cast. Returns true if cast.
function M:Try(name)
    if self:CanCast(name, RAGE[name], STANCE_REQ[name]) then
        return self:Cast(name)
    end
    return false
end

-- ============================================================
-- Sunder Armor stack tracking on the target
-- ============================================================
function M:SunderStacksOnTarget()
    -- Exact name match first (SuperWoW id path), "Sunder" icon fragment as the
    -- fallback. The snapshot carries the application count on either path.
    return self:TargetDebuffStacks("Sunder Armor", "Sunder")
end

function M:NeedSunder(cfg)
    local want = cfg.sunderStacks or 5
    -- Apply until we reach the configured stacks; once there we let it ride
    -- and re-apply only after it falls off (precise refresh timing is not
    -- reliable on 1.12 without extra debuff data).
    return self:SunderStacksOnTarget() < want
end

-- ============================================================
-- Rotation
-- ============================================================
function M:Rotate(cfg)
    local rage   = self:Rage()
    local now    = GetTime()
    local hp     = self:TargetHPPct()
    local cls    = UnitClassification("target")
    local isElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    local aoe    = cfg.aoeMode and true or false
    local inCombat = UnitAffectingCombat("player")

    local inExecute = cfg.useExecute and hp <= 20 and self:KnowsSpell("Execute")
        and rage >= RAGE["Execute"] and not self:InStance("Defensive Stance")

    if self.trace then
        self:Trace("rage=" .. rage
            .. " stance=" .. (self:CurrentStanceName() or "-")
            .. " hp=" .. string.format("%.0f", hp)
            .. " aoe=" .. (aoe and "Y" or "N")
            .. " op=" .. ((now < (self.overpowerExpiry or 0)) and "Y" or "N")
            .. " rev=" .. ((now < (self.revengeExpiry or 0)) and "Y" or "N")
            .. " elite=" .. (isElite and "Y" or "N"))
    end

    -- ----------------------------------------------------------------
    -- 0. Off-GCD / on-next-swing layer (fire and continue, no return)
    -- ----------------------------------------------------------------
    -- 0a. Bloodrage to keep rage flowing (works out of combat for pulls).
    if cfg.useBloodrage and self:KnowsSpell("Bloodrage") and self:IsReady("Bloodrage")
        and rage < (cfg.bloodrageRage or 30) then
        CastSpellByName("Bloodrage")
    end

    -- 0b. Burst cooldowns, gated by the pop mode and (for the offensive
    --     ones) by being in combat so they are not wasted pre-pull.
    local popBurst = cfg.popCDs or (cfg.autoCDElite and isElite)
    if popBurst and inCombat then
        if cfg.useDeathWish and self:KnowsSpell("Death Wish") and self:IsReady("Death Wish") then
            self:Cast("Death Wish")
        end
        if cfg.useRecklessness and self:InStance("Berserker Stance")
            and self:KnowsSpell("Recklessness") and self:IsReady("Recklessness") then
            self:Cast("Recklessness")
        end
        if cfg.useBerserkerRage and self:InStance("Berserker Stance")
            and self:KnowsSpell("Berserker Rage") and self:IsReady("Berserker Rage") then
            self:Cast("Berserker Rage")
        end
    end

    -- 0c. Sweeping Strikes for cleave windows (off the GCD).
    if aoe and cfg.useSweeping and self:KnowsSpell("Sweeping Strikes")
        and self:InAnyStance(STANCE_REQ["Sweeping Strikes"]) and self:IsReady("Sweeping Strikes") then
        self:Cast("Sweeping Strikes")
    end

    -- 0d. Shield Block to feed Revenge / mitigate (Defensive only, off GCD).
    if cfg.useShieldBlock and self:InStance("Defensive Stance")
        and self:KnowsSpell("Shield Block") and self:IsReady("Shield Block") then
        self:Cast("Shield Block")
    end

    -- 0e. Rage dump on the next swing. Suppressed during the execute phase
    --     so rage is funneled into Execute instead. Cleave when in AoE mode
    --     (and known), otherwise Heroic Strike.
    if cfg.useHeroicStrike and not inExecute and rage >= (cfg.dumpRage or 60)
        and (now - (self.lastDump or 0)) > DUMP_THROTTLE then
        if aoe and cfg.useCleave and self:KnowsSpell("Cleave") then
            CastSpellByName("Cleave"); self.lastDump = now
        elseif self:KnowsSpell("Heroic Strike") then
            CastSpellByName("Heroic Strike"); self.lastDump = now
        end
    end

    -- ----------------------------------------------------------------
    -- 1. GCD priority (strict, exactly one cast per press via early return)
    -- ----------------------------------------------------------------

    -- 1a. Revenge (Defensive). Mainly a tank reactive; only pursued while
    --     in Defensive, or stance-danced to it when home stance is Defensive.
    if cfg.useRevenge and self:KnowsSpell("Revenge") and now < (self.revengeExpiry or 0)
        and self:IsReady("Revenge") and rage >= RAGE["Revenge"] then
        if self:InStance("Defensive Stance") then
            self.revengeExpiry = 0
            if self:Cast("Revenge") then return end
        elseif cfg.stanceDance and cfg.homeStance == "defensive" then
            if self:SwitchStance("Defensive Stance") then return end
        end
    end

    -- 1b. Execute below 20% (highest single-target priority per design).
    if inExecute then
        if self:Try("Execute") then return end
    end

    -- 1c. Overpower (Battle), reactive. Stance-dance in when enabled.
    if cfg.useOverpower and self:KnowsSpell("Overpower") and now < (self.overpowerExpiry or 0)
        and self:IsReady("Overpower") and rage >= RAGE["Overpower"] then
        if self:InStance("Battle Stance") then
            self.overpowerExpiry = 0
            if self:Cast("Overpower") then return end
        elseif cfg.stanceDance then
            if self:SwitchStance("Battle Stance") then return end
        end
    end

    -- 1d. Primary strike on cooldown. Usually only one of these is known /
    --     talented for a given spec, so order between them rarely matters.
    if cfg.useShieldSlam   and self:Try("Shield Slam")   then return end
    if cfg.useBloodthirst  and self:Try("Bloodthirst")   then return end
    if cfg.useMortalStrike and self:Try("Mortal Strike") then return end

    -- 1e. Whirlwind: on cooldown in AoE, or as a single-target rage dump
    --     when rage is running high. Berserker stance only.
    if cfg.useWhirlwind and self:CanCast("Whirlwind", RAGE["Whirlwind"], STANCE_REQ["Whirlwind"]) then
        if aoe or rage >= (cfg.wwExcess or 60) then
            if self:Cast("Whirlwind") then return end
        end
    end

    -- 1f. Thunder Clap for AoE (Battle stance in 1.12).
    if aoe and cfg.useThunderClap and self:Try("Thunder Clap") then return end

    -- 1g. Sunder Armor upkeep (threat / armor reduction).
    if cfg.useSunder and self:CanCast("Sunder Armor", RAGE["Sunder Armor"], nil)
        and self:NeedSunder(cfg) then
        if self:Cast("Sunder Armor") then return end
    end

    -- 1h. Slam filler (Arms). Has a cast time and resets the swing timer,
    --     so it suits 2H builds and may feel awkward with heavy spam.
    if cfg.useSlam and self:Try("Slam") then return end

    -- 1i. Drift back to the home stance when nothing reactive is pending.
    if cfg.stanceDance and cfg.homeStance ~= "none" then
        local home = self.STANCES[cfg.homeStance]
        if home and not self:InStance(home)
            and now >= (self.overpowerExpiry or 0)
            and now >= (self.revengeExpiry or 0) then
            self:SwitchStance(home)
        end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:CmdAoe()
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.aoeMode = not cfg.aoeMode
    msgOut("AoE mode " .. (cfg.aoeMode and "on (Cleave + Whirlwind)" or "off (single target)") .. ".")
end

function M:CmdCd(mode)
    local cfg = AutoRota:GetActiveProfile()
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
        msgOut("usage: /ar cd on | elite | off", 1, 0.5, 0.3)
    end
end

function M:CmdDance()
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.stanceDance = not cfg.stanceDance
    msgOut("stance dancing " .. (cfg.stanceDance and "on" or "off") .. ".")
end

function M:CmdSpell(alias, onoff)
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local key = self.spellAlias[string.lower(alias or "")]
    if not key then msgOut("unknown spell alias.", 1, 0.5, 0.3); return end
    cfg[key] = (string.lower(onoff or "") == "on")
    msgOut(key .. " = " .. (cfg[key] and "on" or "off") .. " (active profile).")
end

function M:HandleCommand(cmd, t)
    if cmd == "aoe"   then self:CmdAoe(); return true end
    if cmd == "cd"    then self:CmdCd(t[2]); return true end
    if cmd == "dance" then self:CmdDance(); return true end
    if cmd == "spell" then self:CmdSpell(t[2], t[3]); return true end
    return false
end

-- ============================================================
-- Reactive proc tracker. Owned by the module, stays inert unless the
-- matching option is enabled. Overpower comes from the TARGET dodging our
-- attack; Revenge from us blocking, dodging, or parrying an enemy attack.
-- ============================================================
local reactFrame = CreateFrame("Frame")
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")             -- our attacks that were avoided
reactFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES") -- enemy attacks we avoided
reactFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        if arg1 and string.find(string.lower(arg1), "dodge") then
            M.overpowerExpiry = GetTime() + REACT_WINDOW
        end
    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
        local s = arg1 and string.lower(arg1)
        if s and (string.find(s, "block") or string.find(s, "dodge") or string.find(s, "parry")) then
            M.revengeExpiry = GetTime() + REACT_WINDOW
        end
    end
end)
