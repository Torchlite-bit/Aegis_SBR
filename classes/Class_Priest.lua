-- ============================================================
-- Class_Priest  -  priest module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Shadow / leveling DPS + Disc/Holy healing.
-- ============================================================
-- Two play modes, switched by the heal toggle (or /sbr heal on|off):
--
--  DPS (Shadow + leveling), the default:
--   * Keep Inner Fire up; optionally hold Shadowform.
--   * Power Word: Shield as mitigation when a mob is in melee or you are
--     taking heavy hits, gated on Weakened Soul so it never tries to re-shield.
--   * Mind Blast on cooldown (the Shadow Weaving trigger and the leveling pull).
--   * Spirit Tap finisher: under the execute threshold, prioritise a burst
--     (Mind Blast then Smite) so the priest secures the experience-yielding kill.
--   * Damage-over-time upkeep: Shadow Word: Pain (toggleable for raid debuff
--     limits), Devouring Plague (Undead), Holy Fire (only out of Shadowform).
--   * Filler: the chosen damage spell while mana is healthy, falling back to the
--     WAND when mana drops below a floor. That is the 5-second-rule loop -- the
--     engine wands to let mana regenerate instead of casting itself dry.
--
--  Heal (Discipline / Holy):
--   * Responsive triage with rank downranking (reuses the paladin heal engine):
--     the most-hurt reachable member is healed with the smallest rank that
--     covers the deficit, to conserve mana.
--   * Flash Heal is reserved for emergencies (a target near death).
--   * Greater Heal for big deficits, Heal for efficient sustained healing.
--   * Prayer of Healing for AoE, paired with Inner Focus (when ready) to negate
--     its mana cost.
--   * Power Word: Shield and Renew as maintenance, both Weakened-Soul / throttle
--     guarded so dungeons do not get over-bubbled.
--   * Between heals it can weave Smite / Holy Fire as offensive support (the
--     Enlighten / atonement style), and place Lightwell when enabled.
--
-- Almost everything is KnowsSpell-gated, so one profile scales from level 1 to
-- 60 -- abilities switch themselves on as they are trained. Cast-time spells are
-- queued with QueueSpellByName so the rotation never clips a cast or a channel.
-- ============================================================

local M = Aegis_SBR:NewClassModule("PRIEST")
M.uiTitle = "Priest"
M.uiHeight = 680
M.meleeAutoAttack = false   -- caster, no white melee swing

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- ---------- channel-clip protection ----------
-- Mind Flay (and Mana Burn) are channels; once one runs the rotation must not
-- queue another cast over it. Flag while any channel runs, clear on stop
-- (including the early stop when the target dies mid-channel). A 16s ceiling
-- guards a missed stop event so the rotation can never wedge.
M.channeling = false
M.chanStart = 0
local prChannelFrame = CreateFrame("Frame")
prChannelFrame:RegisterEvent("SPELLCAST_CHANNEL_START")
prChannelFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
prChannelFrame:SetScript("OnEvent", function()
    if event == "SPELLCAST_CHANNEL_START" then
        M.channeling = true; M.chanStart = GetTime()
    elseif event == "SPELLCAST_CHANNEL_STOP" then
        M.channeling = false
    end
end)

-- ---------- combat-state flag ----------
-- UnitAffectingCombat is unavailable on 1.12, so combat is tracked with the
-- regen events. Used to hold Lightwell placement until out of combat.
M.inCombat = false
local prCombatFrame = CreateFrame("Frame")
prCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
prCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
prCombatFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_DISABLED" then M.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then M.inCombat = false end
end)

-- ============================================================
-- Heal value tables (APPROXIMATE, tunable for Turtle WoW). The rank picker
-- downranks against these plus the gear +healing bonus. If downranking picks a
-- rank that over- or under-heals, adjust the numbers here.
-- ============================================================
M.FH_HEAL = { 220, 290, 370, 490, 630, 800, 950 }                 -- Flash Heal
M.FH_MANA = { 125, 155, 185, 225, 290, 350, 410 }
M.GH_HEAL = { 900, 1150, 1500, 1900, 2250, 2600 }                 -- Greater Heal
M.GH_MANA = { 370, 440, 510, 590, 650, 710 }
M.HEAL_HEAL = { 310, 500, 685, 900 }                              -- Heal
M.HEAL_MANA = { 155, 205, 255, 305 }
M.LH_HEAL = { 55, 95, 150 }                                       -- Lesser Heal
M.LH_MANA = { 30, 45, 65 }

-- ---------- gear +healing scan (own tooltip, unique global name) ----------
local healScanTip = CreateFrame("GameTooltip", "Aegis_SBR_PriestHealScan", nil, "GameTooltipTemplate")
healScanTip:SetOwner(healScanTip, "ANCHOR_NONE")
M.cachedHealBonus = nil
local healBonusFrame = CreateFrame("Frame")
healBonusFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
healBonusFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
healBonusFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
healBonusFrame:SetScript("OnEvent", function() M.cachedHealBonus = nil end)

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
    return 0
end

function M:GearHealBonus()
    if self.cachedHealBonus then return self.cachedHealBonus end
    local total = 0
    for slot = 1, 19 do
        if GetInventoryItemLink("player", slot) then
            healScanTip:ClearLines()
            healScanTip:SetInventoryItem("player", slot)
            for i = 1, healScanTip:NumLines() do
                local fs = getglobal("Aegis_SBR_PriestHealScanTextLeft" .. i)
                local txt = fs and fs:GetText()
                if txt then total = total + self:ParseHealBonus(txt) end
            end
        end
    end
    self.cachedHealBonus = total
    return total
end

-- ============================================================
-- Templates: starting presets, copied into the char's saved profiles once.
-- ============================================================
M.templates = {
    starter = {  -- solo from level 1: shadow damage + wand finisher, mana aware.
        healMode = false,
        useInnerFire = true, useShadowform = false,
        usePWShieldMelee = true,
        useMindBlast = true, useShadowWordPain = true, useDevouringPlague = true,
        useHolyFire = true, useMindFlay = true,
        useSpiritTapFinisher = true, executeHp = 25,
        filler = "Wand", fillerManaFloor = 25, useWand = true,
    },
    shadow = {  -- endgame shadow: Mind Flay filler, raid-friendly DoT control.
        healMode = false,
        useInnerFire = true, useShadowform = true,
        usePWShieldMelee = false,
        useMindBlast = true, useShadowWordPain = true, useDevouringPlague = true,
        useHolyFire = false, useMindFlay = true,
        useSpiritTapFinisher = false, executeHp = 20,
        filler = "Mind Flay", fillerManaFloor = 15, useWand = true,
    },
    heal = {  -- Discipline / Holy group healer that weaves damage between heals.
        healMode = true, healThreshold = 85,
        useFlashHeal = true, flashHealPct = 40,
        useGreaterHeal = true, greaterHealDeficit = 1000,
        usePWShield = true, useRenew = true,
        usePrayer = false, prayerCount = 3, useInnerFocus = true,
        offensiveWeave = false, useLightwell = false,
        useInnerFire = true, healPower = 0,
    },
}

function M:NormalizeProfile(c)
    -- shared
    if c.useInnerFire == nil then c.useInnerFire = true end
    -- DPS / shadow / leveling
    if c.healMode == nil then c.healMode = false end
    if c.useShadowform == nil then c.useShadowform = false end
    if c.usePWShieldMelee == nil then c.usePWShieldMelee = true end
    if c.useMindBlast == nil then c.useMindBlast = true end
    if c.useShadowWordPain == nil then c.useShadowWordPain = true end
    if c.useDevouringPlague == nil then c.useDevouringPlague = true end
    if c.useHolyFire == nil then c.useHolyFire = true end
    if c.useMindFlay == nil then c.useMindFlay = true end
    if c.useSpiritTapFinisher == nil then c.useSpiritTapFinisher = true end
    if c.executeHp == nil then c.executeHp = 25 end
    if c.filler == nil then c.filler = "Wand" end
    if c.fillerManaFloor == nil then c.fillerManaFloor = 25 end
    if c.useWand == nil then c.useWand = true end
    -- healing
    if c.healThreshold == nil then c.healThreshold = 85 end
    if c.useFlashHeal == nil then c.useFlashHeal = true end
    if c.flashHealPct == nil then c.flashHealPct = 40 end
    if c.useGreaterHeal == nil then c.useGreaterHeal = true end
    if c.greaterHealDeficit == nil then c.greaterHealDeficit = 1000 end
    if c.usePWShield == nil then c.usePWShield = true end
    if c.useRenew == nil then c.useRenew = true end
    if c.usePrayer == nil then c.usePrayer = false end
    if c.prayerCount == nil then c.prayerCount = 3 end
    if c.useInnerFocus == nil then c.useInnerFocus = true end
    if c.offensiveWeave == nil then c.offensiveWeave = false end
    if c.useLightwell == nil then c.useLightwell = false end
    if c.healPower == nil then c.healPower = 0 end
    return c
end

function M:ProfileValidity(cfg)
    return true, {}   -- everything degrades via KnowsSpell; no nag.
end

-- ============================================================
-- Talent rank by name (cached, cleared on point changes / login). Used only for
-- talents that grant no spell, so KnowsSpell cannot see them.
-- ============================================================
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
local prTalentFrame = CreateFrame("Frame")
prTalentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
prTalentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
prTalentFrame:SetScript("OnEvent", function() M.talentCache = nil end)

-- ============================================================
-- Wand / filler helpers
-- ============================================================
function M:Wanding()
    local slot = self.wandSlot
    if slot and IsAutoRepeatAction(slot) then return true end
    for s = 1, 120 do
        if IsAutoRepeatAction(s) then self.wandSlot = s; return true end
    end
    return false
end

-- Priests can only equip a wand in the ranged slot, so an occupied ranged slot
-- means a wand is available.
function M:HasWand()
    return GetInventoryItemLink("player", 18) ~= nil
end

-- Start the wand if it is not already auto-repeating.
function M:Wand()
    if self:Wanding() then return true end
    if not self:HasWand() then return false end
    CastSpellByName("Shoot")
    return true
end

-- Whether the wand may be used as the mana-regen filler right now: enabled in
-- the profile (the "Use wand" toggle) AND a wand is actually equipped, since a
-- priest can only wand from the ranged slot. When this is false the rotation
-- casts a damage spell instead of an empty wand press.
function M:WandUsable(cfg)
    return (cfg.useWand ~= false) and self:HasWand()
end

-- ============================================================
-- Cast / DoT helpers (mirror the warlock caster pattern)
-- ============================================================
function M:Queue(name)
    if not self:KnowsSpell(name) then return false end
    if self:Wanding() or not QueueSpellByName then
        CastSpellByName(name)
    else
        QueueSpellByName(name)
    end
    return true
end

-- True if the named aura is on a unit (SuperWoW id -> SpellInfo name path, with
-- a texture-fragment fallback). Works on any unit, not just the target.
function M:UnitHasAura(unit, name, harmful, texFrag)
    if not UnitExists(unit) then return false end
    local fn = harmful and UnitDebuff or UnitBuff
    for i = 1, 40 do
        local tex, _, d3, d4, d5 = fn(unit, i)
        if not tex then break end
        local id
        if type(d3) == "number" then id = d3
        elseif type(d4) == "number" then id = d4
        elseif type(d5) == "number" then id = d5 end
        if id and SpellInfo then
            if id < -1 then id = id + 65536 end
            if SpellInfo(id) == name then return true end
        end
        if texFrag and tex and string.find(tex, texFrag) then return true end
    end
    return false
end

function M:TargetHasTexture(frag)
    if not frag or frag == "" then return false end
    return self:TargetDebuffUp(nil, frag)
end

-- Throttle memory per DoT, keyed by target GUID, so a cast-time DoT is not
-- re-queued while it is still landing and an instant DoT is reapplied on a
-- sensible interval.
M.dotThrottle = {}
function M:ApplyDot(spellName, texFrag, interval)
    interval = interval or 3
    if self:TargetDebuffUp(spellName, texFrag) then return "up" end
    local detectable = (texFrag ~= nil) or self:CanResolveDebuffNames()
    local id = self:TargetId()
    local rec = self.dotThrottle[spellName]
    local now = GetTime()
    if rec and rec.id == id and rec.t and (now - rec.t) <= interval then
        if detectable then return "wait" else return "up" end
    end
    self.dotThrottle[spellName] = { id = id, t = now }
    self:Queue(spellName)
    return "cast"
end

-- ============================================================
-- Healing engine (adapted from the paladin; self-contained).
-- ============================================================
function M:CommitHeal(unit, amount, castTime)
    self.healTarget = UnitName(unit)
    self.healAmount = amount or 0
    self.healUntil = GetTime() + (castTime or 0) + 1.0
end

function M:PendingFor(unit)
    if self.healTarget and GetTime() < self.healUntil and UnitName(unit) == self.healTarget then
        return self.healAmount
    end
    return 0
end

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

function M:Reachable(u)
    if UnitIsUnit(u, "player") then return true end
    return CheckInteractDistance(u, 4)
end

-- Lowest effective-health reachable member below ratio, counting our pending
-- heal. Returns unit, missing health, ratio.
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
            if pct < bestPct then bestPct = pct; bestU = u; bestDef = mx - cur end
        end
    end
    return bestU, bestDef, bestPct
end

-- How many reachable members are below ratio (for the AoE heal trigger).
function M:HurtCount(ratio)
    local units = self:GroupUnits()
    local n = 0
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsFriend("player", u) and UnitHealthMax(u) > 0 and self:Reachable(u) then
            if UnitHealth(u) / UnitHealthMax(u) < ratio then n = n + 1 end
        end
    end
    return n
end

function M:HealDemand(cfg)
    if self.healUntil and GetTime() < self.healUntil then return true end
    return self:HurtCount((cfg.healThreshold or 85) / 100) > 0
end

-- Healing talent modifier: Spiritual Healing +2%/rank (name-based, so it is not
-- fragile to talent positions). Divine spec talents could be added the same way.
function M:HealMods()
    return 1 + 0.02 * self:TalentRank("Spiritual Healing")
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

-- Cast a heal on a unit without dropping the current target (SuperWoW unit arg).
function M:CastOn(spell, unit)
    CastSpellByName(spell, unit)
end

-- True when the global cooldown is free (probed through a cooldown-less spell).
function M:GcdReady()
    local probes = { "Lesser Heal", "Heal", "Flash Heal", "Smite", "Renew" }
    for i = 1, table.getn(probes) do
        if self:KnowsSpell(probes[i]) then return self:IsReady(probes[i]) end
    end
    return true
end

-- Per-unit Renew reapply throttle (Renew lasts ~15s; reapply a little before).
M.renewThrottle = {}
function M:RenewDue(unit)
    local name = UnitName(unit) or "?"
    local rec = self.renewThrottle[name]
    if rec and (GetTime() - rec) < 13 then return false end
    return true
end

-- Heal decision. Returns true when a heal was cast (or the GCD is held) this
-- press. Triage order: AoE -> emergency Flash -> big Greater Heal -> efficient
-- Heal/Flash -> maintenance (Renew, then a Weakened-Soul-gated shield).
function M:DoHeal(cfg)
    local ratio = (cfg.healThreshold or 85) / 100
    local unit, deficit, pct = self:WorstHurt(ratio)
    if not unit then return false end
    if not self:GcdReady() then return true end

    local mana = UnitMana("player")
    local hp = (cfg.healPower and cfg.healPower > 0) and cfg.healPower or self:GearHealBonus()
    local mods = self:HealMods()
    local C15, C30 = 1.5 / 3.5, 3.0 / 3.5
    local fhEff   = self:EffHeals(self.FH_HEAL, C15, mods, hp)
    local ghEff   = self:EffHeals(self.GH_HEAL, C30, mods, hp)
    local healEff = self:EffHeals(self.HEAL_HEAL, C30, mods, hp)

    -- AoE: Prayer of Healing, fronted by Inner Focus (instant, off-GCD) to wipe
    -- its mana cost. Inner Focus on one press, the prayer on the next.
    if cfg.usePrayer and self:KnowsSpell("Prayer of Healing")
        and self:HurtCount(ratio) >= (cfg.prayerCount or 3) then
        if cfg.useInnerFocus and self:KnowsSpell("Inner Focus") and self:OwnCDReady("Inner Focus")
            and not self:HasBuff("Inner Focus") then
            self:Cast("Inner Focus"); return true
        end
        self:Queue("Prayer of Healing"); return true
    end

    -- Emergency: a target near death gets Flash Heal (reserved for this so it
    -- does not drain the pool on routine damage).
    if cfg.useFlashHeal and self:KnowsSpell("Flash Heal") and pct <= (cfg.flashHealPct or 40) / 100 then
        local fh, amt = self:PickRank("Flash Heal", fhEff, self.FH_MANA, deficit, mana)
        if fh then self:CommitHeal(unit, amt, 1.5); self:CastOn(fh, unit); return true end
    end

    -- Big deficit: Greater Heal, downranked.
    if cfg.useGreaterHeal and self:KnowsSpell("Greater Heal") and deficit >= (cfg.greaterHealDeficit or 1000) then
        local gh, amt = self:PickRank("Greater Heal", ghEff, self.GH_MANA, deficit, mana)
        if gh then self:CommitHeal(unit, amt, 3.0); self:CastOn(gh, unit); return true end
    end

    -- Efficient sustained healing: Heal, downranked. Falls back to Flash Heal,
    -- then Lesser Heal, so a low-level priest still heals.
    local h, amt = self:PickRank("Heal", healEff, self.HEAL_MANA, deficit, mana)
    if h then self:CommitHeal(unit, amt, 3.0); self:CastOn(h, unit); return true end
    local fh2, amt2 = self:PickRank("Flash Heal", fhEff, self.FH_MANA, deficit, mana)
    if fh2 then self:CommitHeal(unit, amt2, 1.5); self:CastOn(fh2, unit); return true end
    local lhEff = self:EffHeals(self.LH_HEAL, C15, mods, hp)
    local lh, amt3 = self:PickRank("Lesser Heal", lhEff, self.LH_MANA, deficit, mana)
    if lh then self:CommitHeal(unit, amt3, 2.0); self:CastOn(lh, unit); return true end

    -- Maintenance for a mildly hurt unit: keep Renew up, then shield if there is
    -- no Weakened Soul (the over-bubble guard).
    if cfg.useRenew and self:KnowsSpell("Renew") and self:RenewDue(unit)
        and not self:UnitHasAura(unit, "Renew", false, "Spell_Holy_Renew") then
        self.renewThrottle[UnitName(unit) or "?"] = GetTime()
        self:CastOn("Renew", unit); return true
    end
    if cfg.usePWShield and self:KnowsSpell("Power Word: Shield")
        and not self:UnitHasAura(unit, "Weakened Soul", true, nil)
        and not self:UnitHasAura(unit, "Power Word: Shield", false, "Spell_Holy_PowerWordShield") then
        self:CastOn("Power Word: Shield", unit); return true
    end
    return false
end

-- Heal mode runs even with no attackable target, so the priest heals at range.
function M:RunsWithoutTarget(cfg)
    return cfg.healMode == true
end

-- ============================================================
-- Rotation entry point
-- ============================================================
function M:Rotate(cfg)
    -- Never act over a running channel (Mind Flay / Mana Burn).
    if self.channeling and self.chanStart and (GetTime() - self.chanStart) < 16 then return end

    local shadowform = self:HasBuff("Shadowform")

    -- Keep Inner Fire up in any mode (it is cheap and always wanted).
    if cfg.useInnerFire and self:KnowsSpell("Inner Fire") and not self:HasBuff("Inner Fire") then
        if self:Cast("Inner Fire") then return end
    end

    -- ---------------- HEAL MODE ----------------
    if cfg.healMode then
        if self:DoHeal(cfg) then return end

        -- No one needs healing: optional offensive support / maintenance.
        -- Lightwell first (placed when enabled, known, off cooldown, out of
        -- combat so it is not wasted mid-pull).
        if cfg.useLightwell and self:KnowsSpell("Lightwell") and self:OwnCDReady("Lightwell")
            and not self.inCombat then
            if self:Cast("Lightwell") then return end
        end

        -- Offensive weave: only with an attackable target and out of Shadowform.
        local hasEnemy = UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
        if cfg.offensiveWeave and hasEnemy and not shadowform then
            if self:KnowsSpell("Holy Fire") then
                local r = self:ApplyDot("Holy Fire", "Spell_Holy_SearingLight", 4)
                if r == "cast" or r == "wait" then return end
            end
            if self:Queue("Smite") then return end
        end
        return
    end

    -- ---------------- DPS MODE (shadow / leveling) ----------------
    -- Shadowform upkeep (optional).
    if cfg.useShadowform and self:KnowsSpell("Shadowform") and not shadowform then
        if self:Cast("Shadowform") then return end
    end

    -- Power Word: Shield mitigation: when a mob is in melee or you are taking
    -- heavy hits, and only if there is no Weakened Soul on you and no shield up.
    if cfg.usePWShieldMelee and self:KnowsSpell("Power Word: Shield")
        and not self:HasBuff("Power Word: Shield")
        and not self:UnitHasAura("player", "Weakened Soul", true, nil)
        and (self:InMeleeRange() or self:PlayerHPPct() < 50) then
        if self:Cast("Power Word: Shield") then return end
    end

    -- Everything below needs an attackable target.
    if not (UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")) then
        return
    end

    -- Spirit Tap finisher: under the execute threshold, burst to secure the kill
    -- (and the experience), Mind Blast then Smite.
    if cfg.useSpiritTapFinisher and self:TargetHPPct() < (cfg.executeHp or 25) then
        if cfg.useMindBlast and self:KnowsSpell("Mind Blast") and self:IsReady("Mind Blast") then
            if self:Queue("Mind Blast") then return end
        end
        if not shadowform and self:KnowsSpell("Smite") then
            if self:Queue("Smite") then return end
        end
    end

    -- Mind Blast on cooldown: the Shadow Weaving trigger and a strong nuke.
    if cfg.useMindBlast and self:KnowsSpell("Mind Blast") and self:IsReady("Mind Blast") then
        if self:Queue("Mind Blast") then return end
    end

    -- Damage-over-time upkeep.
    if cfg.useShadowWordPain and self:KnowsSpell("Shadow Word: Pain") then
        local r = self:ApplyDot("Shadow Word: Pain", "Spell_Shadow_ShadowWordPain", 3)
        if r == "cast" or r == "wait" then return end
    end
    if cfg.useDevouringPlague and self:KnowsSpell("Devouring Plague") then
        local r = self:ApplyDot("Devouring Plague", "Spell_Shadow_DevouringPlague", 3)
        if r == "cast" or r == "wait" then return end
    end
    if cfg.useHolyFire and not shadowform and self:KnowsSpell("Holy Fire") then
        local r = self:ApplyDot("Holy Fire", "Spell_Holy_SearingLight", 4)
        if r == "cast" or r == "wait" then return end
    end

    -- ---- Filler / mana-regen tail ----
    -- The wand is the mana-regen filler only when enabled in the profile (the
    -- "Use wand" toggle) AND a wand is actually equipped. When it is not usable,
    -- a damage spell is cast instead so a press is never wasted -- this covers a
    -- wandless priest and the toggle being off, including in Shadowform where
    -- Smite is blocked and only Mind Flay can fill.
    local wandUsable = self:WandUsable(cfg)
    local manaOK = self:ManaPct() >= (cfg.fillerManaFloor or 25)

    -- Mind Flay filler (a channel; counts as a cast) while mana is healthy.
    if cfg.useMindFlay and cfg.filler ~= "Wand" and self:KnowsSpell("Mind Flay") and manaOK then
        if self:Queue("Mind Flay") then return end
    end

    -- The chosen spell filler while mana is healthy -- or always, when there is
    -- no wand to drop to for regen (so disabling the wand keeps it casting).
    local fill = cfg.filler or "Wand"
    if fill ~= "Wand" and self:KnowsSpell(fill) and (manaOK or not wandUsable) then
        if self:Queue(fill) then return end
    end

    -- Wand for mana regen (the 5-second-rule loop), when usable.
    if wandUsable and self:Wand() then return end

    -- Wand not usable (disabled, or none equipped): keep doing damage instead of
    -- an empty press -- Mind Flay if known (works in Shadowform), else Smite out
    -- of Shadowform.
    if not wandUsable then
        if self:KnowsSpell("Mind Flay") then if self:Queue("Mind Flay") then return end end
        if not shadowform and self:KnowsSpell("Smite") then if self:Queue("Smite") then return end end
    end
end

-- ============================================================
-- Slash subcommands
-- ============================================================
function M:HandleCommand(cmd, t)
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
    if cmd == "flashat" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local v = tonumber(t[2])
        if v and v >= 1 and v <= 100 then cfg.flashHealPct = v; msgOut("Flash Heal reserved for below " .. v .. "% health.")
        else msgOut("usage: /sbr flashat <1-100>.", 1, 0.5, 0.3) end
        return true
    end
    if cmd == "filler" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local a = t[2]
        if a == "wand" then cfg.filler = "Wand"; msgOut("filler = Wand.")
        elseif a == "flay" then cfg.filler = "Mind Flay"; msgOut("filler = Mind Flay.")
        elseif a == "smite" then cfg.filler = "Smite"; msgOut("filler = Smite.")
        else msgOut("usage: /sbr filler <wand|flay|smite>.", 1, 0.5, 0.3) end
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
