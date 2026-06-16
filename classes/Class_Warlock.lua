-- ============================================================
-- Class_Warlock  -  warlock module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). DoT priority, configurable, level 1+.
-- ============================================================
-- Model (mirrors the proven leveling macro):
--  * Keep the enabled damage-over-time effects up in priority order,
--    Immolate, then the chosen Curse, then Corruption, then Siphon Life.
--  * Detection is by debuff texture on the target. A short per-effect
--    memory keyed by target GUID prevents re-queuing a cast-time DoT
--    while it is still landing.
--  * Survival / execute / pet tools, each optional:
--      - Drain Life kicks in as a self-heal channel when your health dips
--        below a threshold (the drain-tank safety net).
--      - Health Funnel tops the pet when it drops, as long as you are not
--        low yourself (it costs your health).
--      - Shadowburn executes the target under 20% (instant, costs a shard).
--      - Drain Soul channels in the target's last seconds to bank a Soul
--        Shard and regen mana (the leveling finisher).
--  * When nothing above applies, fall back to the filler: the wand, Shadow
--    Bolt, or Drain Life. The wand filler degrades to Shadow Bolt when no
--    wand is equipped, so a level 1 warlock (Shadow Bolt only) still nukes.
--  * Optional Life Tap when mana is low and health is high.
--  * Nightfall reaction: a free instant Shadow Bolt the moment Shadow Trance
--    procs. This auto-enables when the Nightfall talent is detected (the one
--    place a talent-tree read helps here; almost everything else is covered
--    by KnowsSpell since talented spells appear in the spellbook).
--  * The pet is sent onto the target when enabled.
-- Cast-time spells are queued with QueueSpellByName when available, so
-- the rotation never clips the current cast.
-- ============================================================

local M = AutoRota:NewClassModule("WARLOCK")
M.uiTitle = "Warlock"
M.uiHeight = 716
M.meleeAutoAttack = false   -- caster, no white melee swing

-- Talent that turns on the free instant Shadow Bolt proc (Shadow Trance).
-- It grants no spell, so KnowsSpell cannot see it; reading the talent rank is
-- the only way to know it is present. Adjust the name here if Turtle renames it.
local TALENT_NIGHTFALL = "Nightfall"

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- Debuff textures on the TARGET (fragment match)
M.dotTex = {
    ["Immolate"]     = "Immolation",                      -- Spell_Fire_Immolation
    ["Corruption"]   = "Spell_Shadow_AbominationExplosion",
    ["Siphon Life"]  = "Spell_Shadow_Requiem",
}

-- Curses the UI may offer. Only those with a verified texture get exact
-- upkeep, the rest are reapplied on a timer (see CurseInterval).
M.CURSES = {
    "Curse of Agony", "Curse of Weakness", "Curse of Recklessness",
    "Curse of the Elements", "Curse of Shadow", "Curse of Tongues", "Curse of Doom",
}
M.curseTex = {
    ["Curse of Agony"] = "Spell_Shadow_CurseOfSargeras",
    -- Add more here once confirmed in game with /ar debug.
}

-- Filler universe
M.FILLERS = { "Shoot", "Shadow Bolt", "Drain Life" }

M.templates = {
    starter = {  -- usable from level 1: the filler is the wand, which falls
                 -- back to Shadow Bolt when no wand is equipped, so a fresh
                 -- warlock nukes with Shadow Bolt and the DoTs/curse switch
                 -- themselves on as they are learned. Drain-tank survival and
                 -- the Drain Soul shard finisher are on for leveling.
        useImmolate = true, curse = "Curse of Agony", useCorruption = true, useSiphonLife = false,
        filler = "Shoot", petAttack = true,
        lifeTap = false, lifeTapMana = 20, lifeTapHpMin = 40,
        drainLifeSustain = true, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = false, shadowburnHp = 20,
        useDrainSoul = true, drainSoulHp = 20,
    },
    affliction = {
        useImmolate = false, curse = "Curse of Agony", useCorruption = true, useSiphonLife = true,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
        drainLifeSustain = true, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = false, shadowburnHp = 20,
        useDrainSoul = false, drainSoulHp = 20,
    },
    destruction = {
        useImmolate = true, curse = "Curse of the Elements", useCorruption = false, useSiphonLife = false,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
        drainLifeSustain = false, drainLifeHp = 35,
        healthFunnel = true, healthFunnelPetHp = 50, healthFunnelHpMin = 45,
        useShadowburn = true, shadowburnHp = 20,
        useDrainSoul = false, drainSoulHp = 20,
    },
}

M.curseAlias = {
    agony = "Curse of Agony", coa = "Curse of Agony",
    weakness = "Curse of Weakness", cow = "Curse of Weakness",
    recklessness = "Curse of Recklessness", cor = "Curse of Recklessness",
    elements = "Curse of the Elements", coe = "Curse of the Elements",
    shadow = "Curse of Shadow", cos = "Curse of Shadow",
    tongues = "Curse of Tongues", cot = "Curse of Tongues",
    doom = "Curse of Doom", cod = "Curse of Doom",
    none = "",
}

function M:NormalizeProfile(c)
    if c.useImmolate == nil then c.useImmolate = true end
    if c.curse == nil then c.curse = "Curse of Agony" end
    if c.useCorruption == nil then c.useCorruption = true end
    if c.useSiphonLife == nil then c.useSiphonLife = false end
    if c.filler == nil then c.filler = "Shoot" end
    if c.petAttack == nil then c.petAttack = true end
    if c.lifeTap == nil then c.lifeTap = false end
    if c.lifeTapMana == nil then c.lifeTapMana = 20 end
    if c.lifeTapHpMin == nil then c.lifeTapHpMin = 40 end
    if c.nightfall == nil then c.nightfall = false end
    if c.drainLifeSustain == nil then c.drainLifeSustain = false end
    if c.drainLifeHp == nil then c.drainLifeHp = 35 end
    if c.healthFunnel == nil then c.healthFunnel = false end
    if c.healthFunnelPetHp == nil then c.healthFunnelPetHp = 50 end
    if c.healthFunnelHpMin == nil then c.healthFunnelHpMin = 45 end
    if c.useShadowburn == nil then c.useShadowburn = false end
    if c.shadowburnHp == nil then c.shadowburnHp = 20 end
    if c.useDrainSoul == nil then c.useDrainSoul = false end
    if c.drainSoulHp == nil then c.drainSoulHp = 20 end
    return c
end

function M:AvailableCursesOf()
    local out = {}
    for i = 1, table.getn(self.CURSES) do
        if self:KnowsSpell(self.CURSES[i]) then table.insert(out, self.CURSES[i]) end
    end
    return out
end

-- Everything in the warlock kit is gated by KnowsSpell in the rotation, and
-- the filler falls back to Shadow Bolt when the chosen one is not usable yet
-- (see ResolveFiller), so nothing here is strictly required. A profile is
-- never flagged just because an ability is not trained yet: a level 1 warlock
-- whose only damage is Shadow Bolt reads as a clean, usable profile and the
-- DoTs/curse switch themselves on as they are learned. Mirrors the hunter and
-- druid, which do not flag not-yet-learned abilities.
function M:ProfileValidity(cfg)
    return true, {}
end

-- True while the wand is auto-repeating. The last seen auto-repeat slot is
-- cached, so the common case (already wanding) costs a single check; the
-- full action bar scan only runs when the cached slot is not repeating.
function M:Wanding()
    local slot = self.wandSlot
    if slot and IsAutoRepeatAction(slot) then return true end
    for s = 1, 120 do
        if IsAutoRepeatAction(s) then self.wandSlot = s; return true end
    end
    return false
end

-- A wand is equipped when there is an item in the ranged slot (18); warlocks
-- can only put wands there. Used so the "Shoot" filler degrades gracefully
-- when no wand is available (notably at level 1).
function M:HasWand()
    return GetInventoryItemLink("player", 18) ~= nil
end

-- Resolve the configured filler to one that can actually fire right now.
-- The wand filler needs a wand equipped; a spell filler needs to be learned.
-- When neither holds, fall back to Shadow Bolt (the warlock's level 1 nuke and
-- universal filler) so the rotation always has something to cast while
-- leveling. Returns nil only if even Shadow Bolt is somehow unknown.
function M:ResolveFiller(cfg)
    local f = cfg.filler or "Shoot"
    if f == "Shoot" then
        if self:HasWand() then return "Shoot" end
        if self:KnowsSpell("Shadow Bolt") then return "Shadow Bolt" end
        return nil
    end
    if self:KnowsSpell(f) then return f end
    if self:KnowsSpell("Shadow Bolt") then return "Shadow Bolt" end
    return nil
end

-- Queue a known spell. Normally this uses SuperWoW's cast queue so a
-- cast in progress is not clipped. While the wand is auto-repeating,
-- though, a queued cast would have to wait for the current shot (up to
-- the full wand speed), which shows up as a pause after a target switch.
-- In that case cast directly, which interrupts the wand and fires now.
function M:Queue(name)
    if not self:KnowsSpell(name) then return false end
    if self:Wanding() or not QueueSpellByName then
        CastSpellByName(name)
    else
        QueueSpellByName(name)
    end
    return true
end

-- True while the Nightfall proc (Shadow Trance) is on the warlock.
function M:ShadowTranceUp()
    if self:HasBuff("Shadow Trance") then return true end
    for i = 1, 32 do
        local b = UnitBuff("player", i)
        if b and string.find(b, "Spell_Shadow_Twilight") then return true end
    end
    return false
end

function M:PetHPPct()
    if not UnitExists("pet") then return 100 end
    local mx = UnitHealthMax("pet")
    if mx and mx > 0 then return UnitHealth("pet") / mx * 100 end
    return 100
end

-- Talent rank by name, cached and cleared on CHARACTER_POINTS_CHANGED / login
-- (see the frame at the bottom of this file). Same approach as the paladin.
-- Used only for talents that grant no spell (so KnowsSpell cannot see them).
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

-- Nightfall (Shadow Trance proc) is a passive talent with no spell of its own,
-- so we read the talent tree to know it is present and react to the proc
-- automatically, even if the manual toggle is off.
function M:HasNightfall()
    return self:TalentRank(TALENT_NIGHTFALL) > 0
end

function M:TargetHasTexture(frag)
    if not frag or frag == "" then return false end
    return self:TargetDebuffUp(nil, frag)
end

function M:CurseTex(name)
    return self.curseTex[name]
end

-- Throttle memory per DoT, keyed by target GUID
M.dotThrottle = {}

-- Apply or maintain one DoT. Returns:
--   "up"   the effect is present (or assumed present within its interval)
--   "cast" a cast was queued this press
--   "wait" recently cast and still landing, do nothing further this press
-- Detection prefers the exact spell name (SuperWoW id path), then the icon
-- fragment. When the effect is detectable (a texture is known, or SuperWoW can
-- resolve names), missing-but-recent counts as "wait" so the cast is allowed to
-- land before re-queuing. Otherwise recent counts as "up" and the effect is
-- simply reapplied on the interval, the old texture-less blind-timer path.
function M:ApplyDot(spellName, texFrag, interval)
    interval = interval or 3
    if self:TargetDebuffUp(spellName, texFrag) then return "up" end
    local detectable = (texFrag ~= nil) or AutoRota:CanResolveDebuffNames()
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
-- Rotation. The core has already secured a target (no melee auto
-- attack for this class). One queued cast per press, DoTs first.
-- ============================================================
function M:Rotate(cfg)
    if cfg.petAttack and UnitExists("pet") then PetAttack() end

    local hp     = self:PlayerHPPct()
    local thp    = self:TargetHPPct()
    local nightfall = cfg.nightfall or self:HasNightfall()

    -- P0 Drain Life self-heal: your survival comes first. Channels Drain Life
    -- when you drop below the threshold (the drain-tank safety net).
    if cfg.drainLifeSustain and self:KnowsSpell("Drain Life") and hp < (cfg.drainLifeHp or 35) then
        self:Queue("Drain Life")
        return
    end

    -- P1 Nightfall reaction: spend the free instant Shadow Bolt as soon as
    -- Shadow Trance is up. Auto-on when the Nightfall talent is detected, even
    -- if the manual toggle is off. Skipped when Shadow Bolt is already the
    -- filler (it would be cast anyway, instant during the proc).
    if nightfall and cfg.filler ~= "Shadow Bolt" and self:KnowsSpell("Shadow Bolt") and self:ShadowTranceUp() then
        self:Queue("Shadow Bolt")
        return
    end

    -- P2 Health Funnel: keep the pet alive when it drops, but only while you
    -- can spare the health (it transfers yours to the pet).
    if cfg.healthFunnel and self:KnowsSpell("Health Funnel") and UnitExists("pet")
        and self:PetHPPct() < (cfg.healthFunnelPetHp or 50) and hp > (cfg.healthFunnelHpMin or 45) then
        self:Queue("Health Funnel")
        return
    end

    -- P3 Shadowburn execute: instant finish under the execute threshold (costs
    -- a Soul Shard). On a cooldown, so it is gated by IsReady.
    if cfg.useShadowburn and self:KnowsSpell("Shadowburn") and self:IsReady("Shadowburn")
        and thp < (cfg.shadowburnHp or 20) then
        if self:Queue("Shadowburn") then return end
    end

    -- P4 Drain Soul finisher: channel in the target's last seconds to bank a
    -- Soul Shard and regen mana. (If both this and Shadowburn are enabled,
    -- Shadowburn fires first when ready; this fills otherwise.)
    if cfg.useDrainSoul and self:KnowsSpell("Drain Soul") and thp < (cfg.drainSoulHp or 20) then
        self:Queue("Drain Soul")
        return
    end

    -- Build the ordered DoT list from the enabled, known effects.
    local order = {}
    if cfg.useImmolate then table.insert(order, { "Immolate", self.dotTex["Immolate"], 3 }) end
    if cfg.curse ~= "" then
        local tex = self:CurseTex(cfg.curse)
        -- Exact upkeep when the curse is detectable (known icon, or SuperWoW
        -- name resolution); only a curse we cannot see at all falls back to the
        -- 20s blind reapply timer.
        local detectable = tex or AutoRota:CanResolveDebuffNames()
        table.insert(order, { cfg.curse, tex, detectable and 3 or 20 })
    end
    if cfg.useCorruption then table.insert(order, { "Corruption", self.dotTex["Corruption"], 3 }) end
    if cfg.useSiphonLife then table.insert(order, { "Siphon Life", self.dotTex["Siphon Life"], 3 }) end

    if self.trace then
        local up = ""
        for i = 1, table.getn(order) do
            local sp, tex = order[i][1], order[i][2]
            up = up .. " " .. sp .. "=" .. (tex and (self:TargetHasTexture(tex) and "Y" or "n") or "?")
        end
        self:Trace("dots" .. up .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    for i = 1, table.getn(order) do
        local sp, tex, iv = order[i][1], order[i][2], order[i][3]
        if self:KnowsSpell(sp) then
            local st = self:ApplyDot(sp, tex, iv)
            if st == "cast" or st == "wait" then return end
            -- "up": continue to the next DoT
        end
    end

    -- All enabled DoTs up. Optional Life Tap, then the filler.
    if cfg.lifeTap and self:KnowsSpell("Life Tap") then
        if self:ManaPct() < (cfg.lifeTapMana or 20) and self:PlayerHPPct() > (cfg.lifeTapHpMin or 40) then
            self:Queue("Life Tap")
            return
        end
    end

    local filler = self:ResolveFiller(cfg)
    if filler == "Shoot" then
        -- spammable wand, only start it if it is not already auto repeating
        if self:Wanding() then return end
        CastSpellByName("Shoot")
    elseif filler then
        self:Queue(filler)
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "curse" then
        local curse = self.curseAlias[string.lower(t[2] or "")]
        local cfg = AutoRota:GetActiveProfile()
        if cfg and curse ~= nil then
            cfg.curse = curse
            msgOut("curse = " .. ((curse == "") and "(none)" or curse) .. ".")
        else
            msgOut("usage: /ar curse <agony|elements|shadow|weakness|recklessness|tongues|doom|none>", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end

-- ============================================================
-- Talent cache invalidation. Cleared at login and whenever talent points
-- change, so TalentRank() (used for Nightfall detection) re-reads fresh data
-- on its next call. Same approach as the paladin.
-- ============================================================
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_LOGIN")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
talentFrame:SetScript("OnEvent", function()
    M.talentCache = nil
end)
