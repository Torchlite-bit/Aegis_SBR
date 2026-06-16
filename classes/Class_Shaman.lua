-- ============================================================
-- Class_Shaman  -  shaman module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). Enhancement, Elemental, and Tank, mode
-- adaptive, works from level 1.
-- ============================================================
-- Model:
--  * Three modes, chosen in the panel or with /ar mode:
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

local M = AutoRota:NewClassModule("SHAMAN")
M.uiTitle = "Shaman"
M.uiHeight = 642
M.meleeAutoAttack = false   -- melee swing is managed per-mode in the module

-- Talent that grants the Clearcasting proc. It grants no spell, so KnowsSpell
-- cannot see it; reading the talent rank is the only way to know it is present.
-- Adjust the name here if Turtle renames it (confirm with /ar talents).
local TALENT_CLEARCAST = "Elemental Focus"

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- Re-drop interval for the damage totem (no reliable "is my totem up" API on
-- 1.12, so it is refreshed on a blind timer while in combat).
local SEARING_REDROP = 30
-- Flame Shock blind-reapply interval when its debuff cannot be detected.
local FLAMESHOCK_DUR = 12

-- Shock debuff texture on the TARGET (fragment match), for Flame Shock upkeep.
M.dotTex = {
    ["Flame Shock"] = "Spell_Fire_FlameShock",
}

M.SHOCKS  = { earth = "Earth Shock", frost = "Frost Shock", flame = "Flame Shock", none = "" }
M.SHIELDS = { lightning = "Lightning Shield", water = "Water Shield", earth = "Earth Shield", none = "" }

M.modeAlias  = { enhancement = "enhancement", enh = "enhancement", melee = "enhancement",
                 elemental = "elemental", ele = "elemental", caster = "elemental",
                 tank = "tank" }
M.shockAlias = { earth = "earth", es = "earth", frost = "frost", fs = "frost",
                 flame = "flame", fls = "flame", none = "none", off = "none" }
M.shieldAlias= { lightning = "lightning", ls = "lightning", water = "water", ws = "water",
                 earth = "earth", es = "earth", none = "none", off = "none" }

M.templates = {
    starter = {  -- usable from level 1: Lightning Bolt + melee carry the early
                 -- levels, the rest enables itself as it is learned
        mode = "enhancement", shield = "lightning", shock = "earth",
        lbFiller = true, useStormstrike = true, useLightningStrike = true,
        useSearingTotem = false, useElementalMastery = false, useBloodlust = false,
        useTaunt = false,
    },
    enhancement = {
        mode = "enhancement", shield = "lightning", shock = "earth",
        lbFiller = true, useStormstrike = true, useLightningStrike = true,
        useSearingTotem = true, useElementalMastery = false, useBloodlust = false,
        useTaunt = false,
    },
    elemental = {
        mode = "elemental", shield = "water", shock = "flame",
        lbFiller = true, useStormstrike = false, useLightningStrike = false,
        useSearingTotem = true, useElementalMastery = true, useBloodlust = false,
        useTaunt = false,
    },
    tank = {
        mode = "tank", shield = "lightning", shock = "earth",
        lbFiller = false, useStormstrike = true, useLightningStrike = true,
        useSearingTotem = false, useElementalMastery = false, useBloodlust = false,
        useTaunt = true,
    },
}

function M:NormalizeProfile(c)
    if c.mode == nil then c.mode = "enhancement" end
    if c.shield == nil then c.shield = "lightning" end
    if c.shock == nil then c.shock = "earth" end
    if c.lbFiller == nil then c.lbFiller = true end
    if c.useStormstrike == nil then c.useStormstrike = true end
    if c.useLightningStrike == nil then c.useLightningStrike = true end
    if c.useSearingTotem == nil then c.useSearingTotem = false end
    if c.useElementalMastery == nil then c.useElementalMastery = false end
    if c.useBloodlust == nil then c.useBloodlust = false end
    if c.useTaunt == nil then c.useTaunt = false end
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
    for i = 1, 32 do
        local b = UnitBuff("player", i)
        if b and string.find(b, "Clearcast") then return true end
    end
    return false
end

-- The configured shield/shock resolved to a spell name ("" if none/off).
function M:ShieldSpell(cfg) return self.SHIELDS[cfg.shield or "lightning"] or "" end
function M:ShockSpell(cfg)  return self.SHOCKS[cfg.shock or "earth"] or "" end

-- Queue a known spell through SuperWoW's cast queue so a cast in progress is
-- not clipped. Returns true if the spell is known and was issued.
function M:Queue(name)
    if not self:KnowsSpell(name) then return false end
    if QueueSpellByName then QueueSpellByName(name) else CastSpellByName(name) end
    return true
end

-- Start the white swing in the melee modes (enhancement / tank). Runs whether
-- or not SuperCleveRoidMacros is loaded: the core's EnsureAutoAttack only
-- toggles Attack when you are not already swinging, so it is a no-op if SCRM
-- already started it and fills the gap otherwise.
function M:EnsureMeleeSwing()
    AutoRota:EnsureAutoAttack()
end

-- Searing Totem upkeep on a blind timer (no totem-state API on 1.12).
M.searingT = 0
function M:MaintainSearingTotem(cfg)
    if not cfg.useSearingTotem then return false end
    if not self:KnowsSpell("Searing Totem") then return false end
    local now = GetTime()
    if (now - (self.searingT or 0)) < SEARING_REDROP then return false end
    if self:Queue("Searing Totem") then self.searingT = now; return true end
    return false
end

-- Flame Shock maintained as a DoT (used when shock == flame). Returns true if
-- a cast was issued. Detection prefers the exact name/texture; when detectable,
-- missing means cast; otherwise it is reapplied on a blind timer.
M.flameT = 0
function M:MaintainFlameShock()
    if not self:KnowsSpell("Flame Shock") then return false end
    if not self:IsReady("Flame Shock") then return false end
    local tex = self.dotTex["Flame Shock"]
    if self:TargetDebuffUp("Flame Shock", tex) then return false end
    local detectable = tex or AutoRota:CanResolveDebuffNames()
    local now = GetTime()
    if not detectable and (now - (self.flameT or 0)) < FLAMESHOCK_DUR then return false end
    if self:Queue("Flame Shock") then self.flameT = now; return true end
    return false
end

-- ============================================================
-- Rotation entry: dispatch by mode.
-- ============================================================
function M:Rotate(cfg)
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
    if self:Queue(shield) then return true end
    return false
end

-- ------------------------------------------------------------
-- Enhancement (melee). Also the level 1 default.
-- ------------------------------------------------------------
function M:RotateEnhancement(cfg)
    self:EnsureMeleeSwing()
    local shock = self:ShockSpell(cfg)
    local cc = self:HasClearcast() and self:ClearcastUp()

    if self.trace then
        self:Trace("enh shock=" .. (shock ~= "" and shock or "-")
            .. " ss=" .. (cfg.useStormstrike and (self:KnowsSpell("Stormstrike") and "Y" or "n") or "-")
            .. " ls=" .. (cfg.useLightningStrike and (self:KnowsSpell("Lightning Strike") and "Y" or "n") or "-")
            .. " cc=" .. (cc and "Y" or "n")
            .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    -- P1 shield upkeep
    if self:MaintainShield(cfg) then return end

    -- P2 Bloodlust (self burst), only when enabled and off cooldown, in combat
    if cfg.useBloodlust and self:KnowsSpell("Bloodlust") and UnitAffectingCombat("player")
        and self:IsReady("Bloodlust") and not self:HasBuff("Bloodlust") then
        if self:Queue("Bloodlust") then return end
    end

    -- P3 Stormstrike: applies the +20% Nature self-buff for the next shocks
    if cfg.useStormstrike and self:KnowsSpell("Stormstrike") and self:IsReady("Stormstrike") then
        if self:Queue("Stormstrike") then return end
    end

    -- P4 Lightning Strike: melee instant that also empowers the active shield
    if cfg.useLightningStrike and self:KnowsSpell("Lightning Strike") and self:IsReady("Lightning Strike") then
        if self:Queue("Lightning Strike") then return end
    end

    -- P5 shock on its (shared) cooldown, consuming the Stormstrike buff
    if shock ~= "" and self:KnowsSpell(shock) and self:IsReady(shock) then
        if shock == "Flame Shock" then
            if self:MaintainFlameShock() then return end
        else
            if self:Queue(shock) then return end
        end
    end

    -- P6 Searing Totem upkeep (timer gated, low priority)
    if self:MaintainSearingTotem(cfg) then return end

    -- P7 Lightning Bolt filler / weave. Also the level 1 damage source.
    if cfg.lbFiller and self:KnowsSpell("Lightning Bolt") then
        self:Queue("Lightning Bolt")
    end
end

-- ------------------------------------------------------------
-- Elemental (caster). No melee swing.
-- ------------------------------------------------------------
function M:RotateElemental(cfg)
    local cc = self:HasClearcast() and self:ClearcastUp()

    if self.trace then
        self:Trace("ele shock=" .. (self:ShockSpell(cfg) ~= "" and self:ShockSpell(cfg) or "-")
            .. " cc=" .. (cc and "Y" or "n")
            .. " EM=" .. (cfg.useElementalMastery and (self:KnowsSpell("Elemental Mastery") and "Y" or "n") or "-")
            .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    -- P1 shield upkeep (Water Shield for mana by default)
    if self:MaintainShield(cfg) then return end

    -- P2 Elemental Mastery before a nuke (instant, guarantees a crit -> feeds
    -- Clearcasting and Electrify), when enabled and off cooldown.
    if cfg.useElementalMastery and self:KnowsSpell("Elemental Mastery")
        and self:IsReady("Elemental Mastery") and not self:HasBuff("Elemental Mastery") then
        if self:Queue("Elemental Mastery") then return end
    end

    -- P3 Flame Shock DoT upkeep (when chosen as the shock)
    if cfg.shock == "flame" then
        if self:MaintainFlameShock() then return end
    elseif self:ShockSpell(cfg) ~= "" then
        -- a non-Flame shock chosen: cast it on its cooldown as a nuke
        local shock = self:ShockSpell(cfg)
        if self:KnowsSpell(shock) and self:IsReady(shock) then
            if self:Queue(shock) then return end
        end
    end

    -- P4 Searing Totem upkeep
    if self:MaintainSearingTotem(cfg) then return end

    -- P5 Lightning Bolt filler, the main nuke (builds Electrify). Always the
    -- level 1 fallback.
    if self:KnowsSpell("Lightning Bolt") then
        self:Queue("Lightning Bolt")
    end
end

-- ------------------------------------------------------------
-- Tank. Earth Shock threat, Stormstrike for the Nature buff, Lightning Strike,
-- optional Earthshaker Slam taunt.
-- ------------------------------------------------------------
function M:RotateTank(cfg)
    self:EnsureMeleeSwing()
    local shock = self:ShockSpell(cfg)

    if self.trace then
        self:Trace("tank shock=" .. (shock ~= "" and shock or "-")
            .. " ss=" .. (cfg.useStormstrike and (self:KnowsSpell("Stormstrike") and "Y" or "n") or "-")
            .. " ls=" .. (cfg.useLightningStrike and (self:KnowsSpell("Lightning Strike") and "Y" or "n") or "-")
            .. " taunt=" .. (cfg.useTaunt and (self:KnowsSpell("Earthshaker Slam") and "Y" or "n") or "-"))
    end

    -- P1 shield upkeep (Lightning Shield for threat)
    if self:MaintainShield(cfg) then return end

    -- P2 Earthshaker Slam taunt, only when the target is not already on you
    -- (the ability has no effect otherwise). Same idea as the druid Growl pull.
    if cfg.useTaunt and self:KnowsSpell("Earthshaker Slam") and self:IsReady("Earthshaker Slam") then
        if not (UnitExists("targettarget") and UnitIsUnit("targettarget", "player")) then
            if self:Queue("Earthshaker Slam") then return end
        end
    end

    -- P3 Stormstrike for the Nature buff that boosts shock threat
    if cfg.useStormstrike and self:KnowsSpell("Stormstrike") and self:IsReady("Stormstrike") then
        if self:Queue("Stormstrike") then return end
    end

    -- P4 Earth Shock (or chosen shock) on cooldown, the primary threat tool
    if shock ~= "" and self:KnowsSpell(shock) and self:IsReady(shock) then
        if shock == "Flame Shock" then
            if self:MaintainFlameShock() then return end
        else
            if self:Queue(shock) then return end
        end
    end

    -- P5 Lightning Strike (threat + empowered shield)
    if cfg.useLightningStrike and self:KnowsSpell("Lightning Strike") and self:IsReady("Lightning Strike") then
        if self:Queue("Lightning Strike") then return end
    end

    -- P6 Searing Totem upkeep
    if self:MaintainSearingTotem(cfg) then return end

    -- P7 optional Lightning Bolt filler (off by default for tanks)
    if cfg.lbFiller and self:KnowsSpell("Lightning Bolt") then
        self:Queue("Lightning Bolt")
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "mode" then
        local cfg = AutoRota:GetActiveProfile()
        local mode = self.modeAlias[string.lower(t[2] or "")]
        if cfg and mode then
            cfg.mode = mode
            msgOut("mode = " .. mode .. ".")
        else
            msgOut("usage: /ar mode <enhancement|elemental|tank>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "shock" then
        local cfg = AutoRota:GetActiveProfile()
        local shock = self.shockAlias[string.lower(t[2] or "")]
        if cfg and shock then
            cfg.shock = shock
            msgOut("shock = " .. (shock == "none" and "(none)" or self.SHOCKS[shock]) .. ".")
        else
            msgOut("usage: /ar shock <earth|frost|flame|none>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "shield" then
        local cfg = AutoRota:GetActiveProfile()
        local shield = self.shieldAlias[string.lower(t[2] or "")]
        if cfg and shield then
            cfg.shield = shield
            msgOut("shield = " .. (shield == "none" and "(none)" or self.SHIELDS[shield]) .. ".")
        else
            msgOut("usage: /ar shield <lightning|water|earth|none>", 1, 0.5, 0.3)
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
