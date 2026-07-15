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
--  * Adrenaline Rush and Blade Flurry are off-GCD, cast on demand or
--    automatically against elite and boss targets.
-- ============================================================

local M = Aegis_SBR:NewClassModule("ROGUE")
M.uiTitle = "Rogue"
M.uiHeight = 430

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- Buff duration table (seconds, index = combo points 1-5).
-- Defaults assume the Slice and Dice duration talent is fully talented
-- (+45%). Without it, use the commented base line so the refresh is not
-- timed too late.
local SND_DUR = {13.05, 17.4, 21.75, 26.1, 30.45}
-- local SND_DUR = {9, 12, 15, 18, 21}   -- vanilla base, no talent
local ENV_DUR = {12, 16, 20, 24, 28}
local BUFF_RENEW = 5    -- a buff counts as expiring soon below this remaining time

-- Builder universe, used by the UI to offer only learned ones
M.BUILDERS = { "Sinister Strike", "Backstab", "Hemorrhage", "Noxious Assault", "Mutilate" }

M.templates = {
    starter = {  -- valid for any rogue, only Slice and Dice upkeep
        builder = "", useSnd = true, useEnvenom = false, useRupture = false, useRiposte = false,
        cpFinish = 4, popCDs = false, autoCDElite = false,
    },
    assassination = {
        builder = "", useSnd = true, useEnvenom = true, useRupture = true, useRiposte = true,
        cpFinish = 4, popCDs = false, autoCDElite = false,
    },
    combat = {
        builder = "", useSnd = true, useEnvenom = false, useRupture = false, useRiposte = false,
        cpFinish = 5, popCDs = false, autoCDElite = true,
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
    if c.useSnd == nil then c.useSnd = true end
    if c.useEnvenom == nil then c.useEnvenom = false end
    if c.useRupture == nil then c.useRupture = false end
    if c.useRiposte == nil then c.useRiposte = false end
    if c.cpFinish == nil then c.cpFinish = 4 end
    if c.popCDs == nil then c.popCDs = false end
    if c.autoCDElite == nil then c.autoCDElite = false end
    -- old keys from any earlier format are dropped silently
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

-- True if a self buff is up. Tries the SuperWoW name first, then a texture
-- fragment as a fallback, so detection is robust across ranks.
function M:SelfBuffUp(name, texFrag)
    if name and self:HasBuff(name) then return true end
    if texFrag then
        for i = 1, 32 do
            local b = UnitBuff("player", i)
            if b and string.find(b, texFrag) then return true end
        end
    end
    return false
end

-- ============================================================
-- Rotation. The core has already secured a target and ensured auto attack.
-- Cooldowns are off the global cooldown, so they may be cast in the same
-- press as one GCD ability. Everything else uses early returns so exactly
-- one GCD ability is chosen per press.
-- ============================================================
function M:Rotate(cfg)
    local cls = UnitClassification("target")
    local isElite = (cls == "worldboss" or cls == "elite" or cls == "rareelite")
    if cfg.popCDs or (cfg.autoCDElite and isElite) then
        self:Cast("Adrenaline Rush")
        self:Cast("Blade Flurry")
    end

    local builder = cfg.builder
    if builder == "" then
        builder = self:KnowsSpell("Noxious Assault") and "Noxious Assault" or "Sinister Strike"
    end
    local useSnd = cfg.useSnd and self:KnowsSpell("Slice and Dice")
    local useEnv = cfg.useEnvenom and self:KnowsSpell("Envenom")
    local useRup = cfg.useRupture and self:KnowsSpell("Rupture")
    local cpEvis = cfg.cpFinish or 4

    local cp = GetComboPoints("player", "target")
    local now = GetTime()

    if self.trace then
        self:Trace("cp=" .. cp
            .. " build=" .. builder
            .. " snd=" .. (useSnd and (self:SelfBuffUp("Slice and Dice", "SliceDice") and "up" or "down") or "-")
            .. " env=" .. (useEnv and (self:SelfBuffUp("Envenom", "Sword_31") and "up" or "down") or "-")
            .. " rup=" .. (useRup and (self:TargetDebuffUp("Rupture", "Ability_Rogue_Rupture") and "up" or "down") or "-")
            .. " rip=" .. ((cfg.useRiposte and now < (self.riposteExpiry or 0)) and "Y" or "N")
            .. " elite=" .. (isElite and "Y" or "N"),
            -- Rogue never downranks (all ranks cost the same energy), so every
            -- Cast() below is a bare CastSpellByName(name) - vanilla resolves
            -- that to the highest known rank on its own. This line just
            -- surfaces the max rank on record for what would actually go out,
            -- so a bad rank pick would show up here instead of staying invisible.
            "rank: " .. builder .. "=R" .. self:MaxRank(builder)
            .. "  Eviscerate=R" .. self:MaxRank("Eviscerate")
            .. (useSnd and ("  SnD=R" .. self:MaxRank("Slice and Dice")) or "")
            .. (useEnv and ("  Envenom=R" .. self:MaxRank("Envenom")) or "")
            .. (useRup and ("  Rupture=R" .. self:MaxRank("Rupture")) or "")
            .. ((cfg.useRiposte and self:KnowsSpell("Riposte")) and ("  Riposte=R" .. self:MaxRank("Riposte")) or ""))
    end

    -- P1 Riposte, combo point independent, only inside the parry window
    if cfg.useRiposte and self:KnowsSpell("Riposte") and now < (self.riposteExpiry or 0) then
        CastSpellByName("Riposte")
        return
    end

    -- P2 no combo points, build (prevents an empty finisher)
    if cp == 0 then
        self:Cast(builder)
        return
    end

    -- P3 Slice and Dice gone or expiring soon, refresh as cheaply as possible
    if useSnd then
        local sndLeft = 0
        if self:SelfBuffUp("Slice and Dice", "SliceDice") then
            sndLeft = (self.sndExpire or 0) - now
            if sndLeft <= 0 then sndLeft = BUFF_RENEW + 1 end   -- active, timer unknown
        end
        if sndLeft < BUFF_RENEW then
            if cp == 1 then
                if self:Cast("Slice and Dice") then self.sndExpire = now + (SND_DUR[cp] or SND_DUR[1]) end
            else
                self:Cast("Eviscerate")
            end
            return
        end
    end

    -- P4 Envenom gone or expiring soon, same logic
    if useEnv then
        local envLeft = 0
        if self:SelfBuffUp("Envenom", "Sword_31") then
            envLeft = (self.envExpire or 0) - now
            if envLeft <= 0 then envLeft = BUFF_RENEW + 1 end
        end
        if envLeft < BUFF_RENEW then
            if cp == 1 then
                if self:Cast("Envenom") then self.envExpire = now + (ENV_DUR[cp] or ENV_DUR[1]) end
            else
                self:Cast("Eviscerate")
            end
            return
        end
    end

    -- P5 Rupture upkeep: a finisher that applies the bleed and, with the
    -- Assassination talent Taste for Blood, a stacking damage buff. Refreshed at
    -- the finisher threshold when it is missing on the target, before dumping
    -- the rest into Eviscerate. Rupture is baseline (no talent required); the
    -- talent just sweetens an already-worthwhile DoT, so the toggle is enough.
    if useRup and cp >= cpEvis and not self:TargetDebuffUp("Rupture", "Ability_Rogue_Rupture") then
        if self:Cast("Rupture") then return end
    end

    -- P6 buffs healthy, enough combo points, Eviscerate
    if cp >= cpEvis then
        self:Cast("Eviscerate")
        return
    end

    -- P7 otherwise build
    self:Cast(builder)
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "cp" then
        local n = tonumber(t[2])
        local cfg = Aegis_SBR:GetActiveProfile()
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
-- Parry window tracker for Riposte. Owned by the module, stays inert
-- while Riposte is not learned or the option is off.
-- ============================================================
local riposteFrame = CreateFrame("Frame")
riposteFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
riposteFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
        if arg1 and string.find(string.lower(arg1), "parry") then
            M.riposteExpiry = GetTime() + 5.5
        end
    end
end)
