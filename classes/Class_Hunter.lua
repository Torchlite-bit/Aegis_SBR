-- ============================================================
-- Class_Hunter  -  hunter module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). Ranged priority, configurable, all specs.
-- ============================================================
-- Model:
--  * Hunters fight at range around Auto Shot, weaving instants between
--    shots. Auto Shot is a toggle (like the warlock wand), so it is kept
--    running rather than recast every press: a press that fires an instant
--    never stops the shot.
--  * One GCD ability is chosen per press by strict priority with early
--    returns, the same single-cast discipline the other modules use. Off-GCD
--    layers (pet attack, burst cooldowns) fire and continue.
--  * Debuff upkeep (Hunter's Mark, the chosen Sting) uses the core's
--    SuperWoW name detection with a per-target throttle, so it is applied
--    exactly once and refreshed only when it falls off.
--  * AoE has no reliable enemy counter on 1.12, so it is a manual toggle
--    (/ar aoe) that leads with Volley / Multi-Shot.
--  * Cooldowns follow the rogue/warrior pattern: pop always, only on
--    elite/boss, or never. Rapid Fire plus Bestial Wrath / Intimidation
--    when those are known.
--  * Optional melee weave: when the target is in melee range, Raptor Strike
--    is used and melee auto-attack is started, so a mob in your face still
--    takes damage instead of standing in a dead zone.
-- ============================================================

local M = AutoRota:NewClassModule("HUNTER")
M.uiTitle = "Hunter"
M.uiHeight = 644
M.meleeAutoAttack = false   -- ranged class: Auto Shot is managed here instead

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- Light throttle so a rapid press burst does not re-toggle Auto Shot or
-- re-apply an instant debuff several times before it registers.
local MEND_PET_CD = 12   -- Mend Pet HoT lasts ~15s, refresh a little early

-- The three stings are mutually exclusive (one debuff slot). Durations are
-- only used as the reapply interval on clients without SuperWoW name
-- resolution; with SuperWoW the real debuff is seen and the timer is moot.
M.STINGS = { "Serpent Sting", "Scorpid Sting", "Viper Sting" }
local STING_DUR = {
    ["Serpent Sting"] = 15,
    ["Scorpid Sting"] = 20,
    ["Viper Sting"]   = 8,
}

M.stingAlias = {
    serpent = "Serpent Sting", ss = "Serpent Sting",
    scorpid = "Scorpid Sting", sco = "Scorpid Sting",
    viper = "Viper Sting", vs = "Viper Sting",
    none = "",
}

M.spellAlias = {
    mark = "useHuntersMark", hm = "useHuntersMark",
    arcane = "useArcaneShot", as = "useArcaneShot",
    multi = "useMultiShot", ms = "useMultiShot",
    aimed = "useAimedShot", aim = "useAimedShot",
    volley = "useVolley",
    aspect = "useAspectHawk", hawk = "useAspectHawk",
    raptor = "useRaptorStrike", rs = "useRaptorStrike",
    mend = "useMendPet",
}

-- Templates: starting presets, copied into the char's saved profiles once.
M.templates = {
    starter = {  -- valid from level 1: Mark, Serpent Sting, Arcane, Auto Shot
        useHuntersMark = true, sting = "Serpent Sting",
        useArcaneShot = true, useMultiShot = false, useAimedShot = false,
        aoeMode = false, useVolley = false,
        useAspectHawk = true,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        popCDs = false, autoCDElite = false,
        useRaptorStrike = true,
    },
    marksmanship = {
        useHuntersMark = true, sting = "Serpent Sting",
        useArcaneShot = true, useMultiShot = true, useAimedShot = true,
        aoeMode = false, useVolley = false,
        useAspectHawk = true,
        petAttack = true, useMendPet = true, mendPetHp = 40,
        popCDs = false, autoCDElite = true,
        useRaptorStrike = false,
    },
    beastmastery = {
        useHuntersMark = true, sting = "Serpent Sting",
        useArcaneShot = true, useMultiShot = true, useAimedShot = false,
        aoeMode = false, useVolley = false,
        useAspectHawk = true,
        petAttack = true, useMendPet = true, mendPetHp = 60,
        popCDs = false, autoCDElite = true,
        useRaptorStrike = false,
    },
    survival = {
        useHuntersMark = true, sting = "Serpent Sting",
        useArcaneShot = true, useMultiShot = true, useAimedShot = false,
        aoeMode = false, useVolley = false,
        useAspectHawk = true,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        popCDs = false, autoCDElite = true,
        useRaptorStrike = true,
    },
}

function M:NormalizeProfile(c)
    local b = {
        useHuntersMark = true, sting = "Serpent Sting",
        useArcaneShot = true, useMultiShot = false, useAimedShot = false,
        aoeMode = false, useVolley = false,
        useAspectHawk = true,
        petAttack = true, useMendPet = true, mendPetHp = 50,
        popCDs = false, autoCDElite = false,
        useRaptorStrike = true,
    }
    for k, v in pairs(b) do
        if c[k] == nil then c[k] = v end
    end
    -- a stored sting the player never had should still normalize cleanly
    if type(c.sting) ~= "string" then c.sting = "Serpent Sting" end
    return c
end

-- Only an explicitly chosen sting the character cannot cast is flagged; every
-- other ability degrades gracefully through KnowsSpell while leveling.
function M:ProfileValidity(cfg)
    local missing = {}
    if cfg.sting ~= "" and not self:KnowsSpell(cfg.sting) then table.insert(missing, cfg.sting) end
    return (table.getn(missing) == 0), missing
end

function M:AvailableStingsOf()
    local out = {}
    for i = 1, table.getn(self.STINGS) do
        if self:KnowsSpell(self.STINGS[i]) then table.insert(out, self.STINGS[i]) end
    end
    return out
end

-- ============================================================
-- Auto Shot upkeep. Auto Shot is an auto-repeat toggle: casting it while it
-- is already running turns it OFF. So it is only (re)started when it is not
-- repeating. IsAutoRepeatAction sees it when it is on an action bar; when it
-- is not, we fall back to an assumed-on flag per target so we never toggle it
-- off by accident.
-- ============================================================
function M:AutoShotting()
    local slot = self.autoShotSlot
    if slot and IsAutoRepeatAction(slot) then return true end
    for s = 1, 120 do
        if IsAutoRepeatAction(s) then self.autoShotSlot = s; return true end
    end
    return false
end

function M:EnsureAutoShot()
    if self:AutoShotting() then self.autoShotOn = true; return end
    local id = self:TargetId()
    -- already started on this target and not visibly repeating (Auto Shot not
    -- on a bar): leave it, recasting would only toggle it off.
    if self.autoShotOn and self.autoShotTarget == id then return end
    CastSpellByName("Auto Shot")
    self.autoShotOn = true
    self.autoShotTarget = id
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
    local detectable = AutoRota:CanResolveDebuffNames()
    local id = self:TargetId()
    local rec = self.debuffThrottle[name]
    local now = GetTime()
    if rec and rec.id == id and rec.t and (now - rec.t) <= (interval or 3) then
        return false   -- detectable: still landing; otherwise assumed up on the timer
    end
    self.debuffThrottle[name] = { id = id, t = now }
    return self:Cast(name)
end

function M:PetHPPct()
    if not UnitExists("pet") then return 100 end
    local mx = UnitHealthMax("pet")
    if mx and mx > 0 then return UnitHealth("pet") / mx * 100 end
    return 100
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
    local inMelee  = self:InMeleeRange()
    local meleeWeave = cfg.useRaptorStrike and inMelee and self:KnowsSpell("Raptor Strike")

    if self.trace then
        self:Trace("sting=" .. (cfg.sting ~= "" and cfg.sting or "-")
            .. " mark=" .. (cfg.useHuntersMark and (self:TargetDebuffUp("Hunter's Mark", nil) and "Y" or "n") or "-")
            .. " auto=" .. (self:AutoShotting() and "Y" or (self.autoShotOn and "assumed" or "N"))
            .. " melee=" .. (inMelee and "Y" or "N")
            .. " aoe=" .. (aoe and "Y" or "N")
            .. " elite=" .. (isElite and "Y" or "N")
            .. " pet=" .. (UnitExists("pet") and string.format("%.0f%%", self:PetHPPct()) or "-"))
    end

    -- ----------------------------------------------------------------
    -- 0. Off-GCD / fire-and-continue layer
    -- ----------------------------------------------------------------
    -- 0a. Pet attack.
    if cfg.petAttack and UnitExists("pet") then PetAttack() end

    -- 0b. Burst cooldowns (off the GCD), gated by the pop mode and combat.
    local popBurst = cfg.popCDs or (cfg.autoCDElite and isElite)
    if popBurst and inCombat then
        if self:KnowsSpell("Rapid Fire") and self:IsReady("Rapid Fire") then self:Cast("Rapid Fire") end
        if self:KnowsSpell("Bestial Wrath") and self:IsReady("Bestial Wrath") then self:Cast("Bestial Wrath") end
    end

    -- 0c. Ranged auto-attack upkeep, unless we are meleeing something on top
    --     of us (then start melee swings instead so Raptor Strike can land).
    if meleeWeave then
        AutoRota:EnsureAutoAttack()
    else
        self:EnsureAutoShot()
    end

    -- ----------------------------------------------------------------
    -- 1. GCD priority (strict, one cast per press via early return)
    -- ----------------------------------------------------------------

    -- 1a. Mend Pet when the pet is hurting (throttled, the HoT lasts ~15s).
    if cfg.useMendPet and UnitExists("pet") and self:KnowsSpell("Mend Pet") then
        if self:PetHPPct() < (cfg.mendPetHp or 50) and (now - (self.mendPetT or 0)) > MEND_PET_CD then
            if self:Cast("Mend Pet") then self.mendPetT = now; return end
        end
    end

    -- 1b. Keep Aspect of the Hawk up (ranged attack speed/power).
    if cfg.useAspectHawk and self:KnowsSpell("Aspect of the Hawk")
        and not self:HasBuff("Aspect of the Hawk") then
        if self:Cast("Aspect of the Hawk") then return end
    end

    -- 1c. Hunter's Mark upkeep.
    if cfg.useHuntersMark then
        if self:MaintainDebuff("Hunter's Mark", 110) then return end
    end

    -- 1d. Sting upkeep (the one configured slot).
    if cfg.sting ~= "" then
        if self:MaintainDebuff(cfg.sting, STING_DUR[cfg.sting] or 12) then return end
    end

    -- 1e. AoE leads with Volley (channel) then Multi-Shot when toggled on.
    if aoe then
        if cfg.useVolley and self:KnowsSpell("Volley") and self:IsReady("Volley") then
            if self:Cast("Volley") then return end
        end
        if cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
            if self:Cast("Multi-Shot") then return end
        end
    end

    -- 1f. Melee weave: Raptor Strike queues on the next melee swing.
    if meleeWeave and self:IsReady("Raptor Strike") then
        if self:Cast("Raptor Strike") then return end
    end

    -- 1g. Multi-Shot on cooldown (single target too, when enabled).
    if cfg.useMultiShot and self:KnowsSpell("Multi-Shot") and self:IsReady("Multi-Shot") then
        if self:Cast("Multi-Shot") then return end
    end

    -- 1h. Arcane Shot on cooldown, the staple instant nuke.
    if cfg.useArcaneShot and self:KnowsSpell("Arcane Shot") and self:IsReady("Arcane Shot") then
        if self:Cast("Arcane Shot") then return end
    end

    -- 1i. Aimed Shot (Marksmanship). It has a cast time, so it is queued to
    --     avoid clipping the current shot when SuperWoW is present.
    if cfg.useAimedShot and self:KnowsSpell("Aimed Shot") and self:IsReady("Aimed Shot") then
        if QueueSpellByName then QueueSpellByName("Aimed Shot") else CastSpellByName("Aimed Shot") end
        return
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:CmdSting(alias)
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local sting = self.stingAlias[string.lower(alias or "")]
    if sting == nil then msgOut("usage: /ar sting serpent|scorpid|viper|none", 1, 0.5, 0.3); return end
    cfg.sting = sting
    msgOut("sting = " .. ((sting == "") and "(none)" or sting) .. ".")
end

function M:CmdAoe()
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    cfg.aoeMode = not cfg.aoeMode
    msgOut("AoE mode " .. (cfg.aoeMode and "on (Volley + Multi-Shot)" or "off (single target)") .. ".")
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

function M:CmdSpell(alias, onoff)
    local cfg = AutoRota:GetActiveProfile()
    if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return end
    local key = self.spellAlias[string.lower(alias or "")]
    if not key then msgOut("unknown spell alias.", 1, 0.5, 0.3); return end
    cfg[key] = (string.lower(onoff or "") == "on")
    msgOut(key .. " = " .. (cfg[key] and "on" or "off") .. " (active profile).")
end

function M:HandleCommand(cmd, t)
    if cmd == "sting" then self:CmdSting(t[2]); return true end
    if cmd == "aoe"   then self:CmdAoe(); return true end
    if cmd == "cd"    then self:CmdCd(t[2]); return true end
    if cmd == "spell" then self:CmdSpell(t[2], t[3]); return true end
    return false
end

-- ============================================================
-- Auto Shot state reset: leaving combat stops Auto Shot, so clear the
-- assumed-on flag and let the next pull restart it cleanly.
-- ============================================================
local hunterFrame = CreateFrame("Frame")
hunterFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
hunterFrame:SetScript("OnEvent", function()
    M.autoShotOn = false
    M.autoShotTarget = nil
end)
