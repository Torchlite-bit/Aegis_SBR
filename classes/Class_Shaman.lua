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

-- Restoration: flat-healing talent (Turtle's resto tree may have none, so this
-- is ~neutral by default), the NS-equivalent / Mana Tide spell names, and the
-- totem blind-redrop intervals. Confirm names/durations via /ar talents and /ar debug.
local TALENT_HEALBONUS   = "Purification"
local MANATIDE_SPELL     = "Mana Tide Totem"
local WATER_TOTEM_REDROP = 55
local OTHER_TOTEM_REDROP = 110

-- Shock debuff texture on the TARGET (fragment match), for Flame Shock upkeep.
M.dotTex = {
    ["Flame Shock"] = "Spell_Fire_FlameShock",
}

M.SHOCKS  = { earth = "Earth Shock", frost = "Frost Shock", flame = "Flame Shock", none = "" }
M.SHIELDS = { lightning = "Lightning Shield", water = "Water Shield", earth = "Earth Shield", none = "" }

-- Restoration totem picks (key -> spell), resolved per element. Names are
-- vanilla baselines - confirm against Turtle's spellbook with /ar debug.
M.WATER_TOTEMS = { manaspring = "Mana Spring Totem", healingstream = "Healing Stream Totem", none = "" }
M.EARTH_TOTEMS = { strength = "Strength of Earth Totem", stoneskin = "Stoneskin Totem", tremor = "Tremor Totem", none = "" }
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
    if c.useSearingTotem == nil then c.useSearingTotem = false end
    if c.useElementalMastery == nil then c.useElementalMastery = false end
    if c.useBloodlust == nil then c.useBloodlust = false end
    if c.useTaunt == nil then c.useTaunt = false end
    -- Restoration (heal) profile fields
    if c.healThreshold == nil then c.healThreshold = 90 end
    if c.useManaTide == nil then c.useManaTide = true end
    if c.manaTideAt == nil then c.manaTideAt = 25 end
    if c.useNSCombo == nil then c.useNSCombo = true end
    if c.nsHpPct == nil then c.nsHpPct = 40 end
    if c.useLesserHW == nil then c.useLesserHW = true end
    if c.lhwPct == nil then c.lhwPct = 50 end
    if c.useChainHeal == nil then c.useChainHeal = true end
    if c.chainHealCount == nil then c.chainHealCount = 3 end
    if c.useTotems == nil then c.useTotems = true end
    if c.totemWater == nil then c.totemWater = "manaspring" end
    if c.totemEarth == nil then c.totemEarth = "none" end
    if c.totemFire == nil then c.totemFire = "none" end
    if c.totemAir == nil then c.totemAir = "none" end
    if c.healPower == nil then c.healPower = 0 end
    if c.weaveDamage == nil then c.weaveDamage = false end
    if c.weaveManaFloor == nil then c.weaveManaFloor = 40 end
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
function M:RunsWithoutTarget(cfg)
    return cfg.mode == "restoration"   -- a healer runs with no enemy targeted
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
    self.healPending[n] = { amt = amount or 0, t = GetTime() + (castTime or 1.5) }
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

-- Heal range proxy: ~28yd (the largest CheckInteractDistance band). Heals reach
-- 40yd, so this is conservative, but it keeps the picker off units it can't hit.
function M:Reachable(u)
    if u == "player" then return true end
    return CheckInteractDistance(u, 4) and true or false
end

-- Worst-hurt reachable friendly, counting pending heals toward its health.
function M:WorstHurt(ratio)
    local units = self:GroupUnits()
    local wU, wDef, wPct = nil, 0, 1
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsFriend("player", u)
            and UnitHealthMax(u) > 0 and self:Reachable(u) then
            local mx = UnitHealthMax(u)
            local cur = UnitHealth(u) + self:PendingFor(u)
            local pct = cur / mx
            if pct < ratio then
                local def = mx - cur
                if def > wDef then wU, wDef, wPct = u, def, pct end
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
-- it grants may be named either of these on Turtle - try both (confirm /ar debug).
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
function M:MaintainTotem(key, spell, interval)
    if spell == "" or not self:KnowsSpell(spell) then return false end
    local now = GetTime()
    if (now - (self.totemT[key] or 0)) < interval then return false end
    if self:Queue(spell) then self.totemT[key] = now; return true end
    return false
end

-- Heal decision. Casts one spell per press via early return.
-- Order: Mana Tide (mana) -> NS->instant HW (emergency) -> Lesser Healing Wave
-- (single-target emergency, wins over AoE) -> Chain Heal (AoE) -> downranked
-- Healing Wave (fill) -> Water Shield upkeep -> totem upkeep (during downtime).
function M:RotateRestoration(cfg)
    if not self:GcdReady() then return end

    local ratio = (cfg.healThreshold or 90) / 100
    local unit, deficit, pct = self:WorstHurt(ratio)

    -- Mana Tide Totem when low on mana (the mana cooldown).
    if cfg.useManaTide ~= false and self:KnowsSpell(MANATIDE_SPELL)
        and self:OwnCDReady(MANATIDE_SPELL) and self:ManaPct() <= (cfg.manaTideAt or 25) then
        if self:Queue(MANATIDE_SPELL) then return end
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
            if ns and self:OwnCDReady(ns) then self:Cast(ns); return end
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
    if cfg.useTotems ~= false then
        if self:MaintainTotem("water", self.WATER_TOTEMS[cfg.totemWater or "manaspring"] or "", WATER_TOTEM_REDROP) then return end
        if self:MaintainTotem("earth", self.EARTH_TOTEMS[cfg.totemEarth or "none"] or "", OTHER_TOTEM_REDROP) then return end
        if self:MaintainTotem("fire",  self.FIRE_TOTEMS[cfg.totemFire or "none"] or "", OTHER_TOTEM_REDROP) then return end
        if self:MaintainTotem("air",   self.AIR_TOTEMS[cfg.totemAir or "none"] or "", OTHER_TOTEM_REDROP) then return end
    end
    -- Downtime filler: optionally weave damage. Only with an enemy targeted and
    -- mana above the floor, so it never starves heals.
    if cfg.weaveDamage and self:ManaPct() >= (cfg.weaveManaFloor or 40)
        and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target") then
        if self:KnowsSpell("Lightning Bolt") then self:Queue("Lightning Bolt"); return end
    end
end

-- ============================================================
-- Rotation entry: dispatch by mode.
-- ============================================================
function M:Rotate(cfg)
    if cfg.mode == "elemental" then
        self:RotateElemental(cfg)
    elseif cfg.mode == "tank" then
        self:RotateTank(cfg)
    elseif cfg.mode == "restoration" then
        self:RotateRestoration(cfg)
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
            msgOut("usage: /ar mode <enhancement|elemental|tank|resto>", 1, 0.5, 0.3)
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
    if cmd == "weave" then
        local cfg = AutoRota:GetActiveProfile()
        if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return true end
        local a = string.lower(t[2] or "")
        if a == "on" then cfg.weaveDamage = true
        elseif a == "off" then cfg.weaveDamage = false
        else cfg.weaveDamage = not cfg.weaveDamage end
        msgOut("resto damage weave " .. (cfg.weaveDamage and "on" or "off") .. " (DPS only when nobody needs healing).")
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
