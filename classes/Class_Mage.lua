-- ============================================================
-- Class_Mage  -  mage module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Frost / Fire / Arcane, mode adaptive,
-- works from level 1 to raiding.
-- ============================================================
-- Model:
--  * Three specs, chosen in the panel or with /sbr mode frost|fire|arcane:
--      - frost: the leveling / kiting and Turtle Icicles spec. Frostbolt nuke,
--        Frost Nova root, Icicles (reset/empowered by freeze effects via Flash
--        Freeze), Ice Barrier, Cone of Cold.
--      - fire: burst. Pyroblast opener, Scorch to stack Fire Vulnerability
--        (the Improved Scorch debuff), Fireball nuke, Fire Blast, Combustion.
--      - arcane: Arcane Rupture upkeep + Arcane Missiles filler, Arcane Surge
--        when not hasted, Arcane Power burst.
--  * Level 1+: a fresh mage only has Fireball (Frostbolt at ~4), so the nuke
--    filler carries the early levels and everything else switches itself on
--    through KnowsSpell as it is trained. The profile is never flagged for a
--    not-yet-learned ability.
--  * The leveling "nuke then wand" rule: below a target-health threshold (or
--    below a mana floor) the rotation finishes with the WAND to conserve mana.
--    A "Use wand" toggle and a missing-wand auto-fallback mirror the priest.
--  * Cast-time spells are queued with QueueSpellByName so a cast/channel is
--    never clipped; the Arcane Missiles / Icicles / Blizzard / Evocation
--    channels are protected by a channel watcher.
--
-- Turtle custom mechanics, all confirmed present BY NAME in the client spell
-- DB: Icicles, Arcane Rupture, Arcane Surge, Flash Freeze, Fire Vulnerability.
-- Their exact proc / stack behaviour is best-effort here (see the README
-- caveats). The freeze-reset of Icicles is handled implicitly: the engine casts
-- Icicles whenever its cooldown is up, and Frostbite / Flash Freeze keep
-- resetting that cooldown, so it fires in the empowered window automatically.
-- ============================================================

local M = Aegis_SBR:NewClassModule("MAGE")
M.uiTitle = "Mage"
M.uiHeight = 628
M.meleeAutoAttack = false   -- caster, no white melee swing

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- ---------- channel-clip protection ----------
-- Arcane Missiles, Icicles, Blizzard and Evocation are channels; once one runs
-- the rotation must not queue a cast over it. Flag while any channel runs, clear
-- on stop. A 16s ceiling guards a missed stop event so the rotation never wedges.
M.channeling = false
M.chanStart = 0
local mgChannelFrame = CreateFrame("Frame")
mgChannelFrame:RegisterEvent("SPELLCAST_CHANNEL_START")
mgChannelFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
mgChannelFrame:SetScript("OnEvent", function()
    if event == "SPELLCAST_CHANNEL_START" then
        M.channeling = true; M.chanStart = GetTime()
    elseif event == "SPELLCAST_CHANNEL_STOP" then
        M.channeling = false
    end
end)

M.modeAlias = { frost = "frost", ice = "frost", fire = "fire",
                arcane = "arcane", arc = "arcane" }

-- ============================================================
-- Templates: starting presets, copied into the char's saved profiles once.
-- ============================================================
M.templates = {
    starter = {  -- level 1 frost leveling: Frostbolt nuke + Frost Nova kite +
                 -- wand finish; everything enables itself as it is learned.
        mode = "frost", aoeMode = false,
        useWand = true, wandHp = 40, wandManaFloor = 25,
        useFrostNova = true, useEvocation = true, evocAt = 15, useManaShield = false,
        useIceBarrier = true, useIcicles = true, useConeOfCold = true,
        usePyroblast = true, useScorch = true, scorchStacks = 5, useFireBlast = true, useCombustion = true,
        useArcaneRupture = true, useArcaneSurge = true, useArcanePower = true,
    },
    frost = {  -- Frost spec (Icicles). Caster: no target-health wanding, low
               -- mana floor as a safety net only.
        mode = "frost", aoeMode = false,
        useWand = true, wandHp = 0, wandManaFloor = 10,
        useFrostNova = true, useEvocation = true, evocAt = 12, useManaShield = false,
        useIceBarrier = true, useIcicles = true, useConeOfCold = true,
        usePyroblast = true, useScorch = true, scorchStacks = 5, useFireBlast = true, useCombustion = true,
        useArcaneRupture = true, useArcaneSurge = true, useArcanePower = true,
    },
    fire = {  -- Fire spec. Scorch debuff + Fireball + Combustion.
        mode = "fire", aoeMode = false,
        useWand = true, wandHp = 0, wandManaFloor = 10,
        useFrostNova = true, useEvocation = true, evocAt = 15, useManaShield = false,
        useIceBarrier = true, useIcicles = true, useConeOfCold = true,
        usePyroblast = true, useScorch = true, scorchStacks = 5, useFireBlast = true, useCombustion = true,
        useArcaneRupture = true, useArcaneSurge = true, useArcanePower = true,
    },
    arcane = {  -- Arcane spec. Rupture upkeep + Arcane Missiles + Arcane Power.
        mode = "arcane", aoeMode = false,
        useWand = true, wandHp = 0, wandManaFloor = 10,
        useFrostNova = true, useEvocation = true, evocAt = 15, useManaShield = false,
        useIceBarrier = true, useIcicles = true, useConeOfCold = true,
        usePyroblast = true, useScorch = true, scorchStacks = 5, useFireBlast = true, useCombustion = true,
        useArcaneRupture = true, useArcaneSurge = true, useArcanePower = true,
    },
}

function M:NormalizeProfile(c)
    if c.mode == nil then c.mode = "frost" end
    if c.aoeMode == nil then c.aoeMode = false end
    -- wand / leveling
    if c.useWand == nil then c.useWand = true end
    if c.wandHp == nil then c.wandHp = 40 end
    if c.wandManaFloor == nil then c.wandManaFloor = 25 end
    -- shared
    if c.useFrostNova == nil then c.useFrostNova = true end
    if c.useEvocation == nil then c.useEvocation = true end
    if c.evocAt == nil then c.evocAt = 15 end
    if c.useManaShield == nil then c.useManaShield = false end
    -- frost
    if c.useIceBarrier == nil then c.useIceBarrier = true end
    if c.useIcicles == nil then c.useIcicles = true end
    if c.useConeOfCold == nil then c.useConeOfCold = true end
    -- fire
    if c.usePyroblast == nil then c.usePyroblast = true end
    if c.useScorch == nil then c.useScorch = true end
    if c.scorchStacks == nil then c.scorchStacks = 5 end
    if c.useFireBlast == nil then c.useFireBlast = true end
    if c.useCombustion == nil then c.useCombustion = true end
    -- arcane
    if c.useArcaneRupture == nil then c.useArcaneRupture = true end
    if c.useArcaneSurge == nil then c.useArcaneSurge = true end
    if c.useArcanePower == nil then c.useArcanePower = true end
    return c
end

-- Everything in the kit is KnowsSpell-gated and the nuke filler covers a level 1
-- mage, so nothing here is strictly required; a profile is never flagged just
-- because an ability is not trained yet. Mirrors the hunter / shaman / warlock.
function M:ProfileValidity(cfg)
    return true, {}
end

-- ============================================================
-- Wand helpers (mirror the priest)
-- ============================================================
function M:Wanding()
    local slot = self.wandSlot
    if slot and IsAutoRepeatAction(slot) then return true end
    for s = 1, 120 do
        if IsAutoRepeatAction(s) then self.wandSlot = s; return true end
    end
    return false
end

-- A mage can only equip a wand in the ranged slot, so an occupied ranged slot
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

-- The wand may be used only when enabled in the profile (the "Use wand" toggle)
-- AND a wand is actually equipped.
function M:WandUsable(cfg)
    return (cfg.useWand ~= false) and self:HasWand()
end

-- Wand this press? Finish a low-health mob with the wand (the leveling "nuke
-- then wand" rule), or wand to regenerate when mana is low. Both require a
-- usable wand. With wandHp = 0 the target-health rule is off (caster / raid).
function M:ShouldWand(cfg)
    if not self:WandUsable(cfg) then return false end
    if cfg.wandHp and cfg.wandHp > 0 and self:TargetHPPct() <= cfg.wandHp then return true end
    if self:ManaPct() < (cfg.wandManaFloor or 25) then return true end
    return false
end

-- ============================================================
-- Cast helper: queue a known spell through SuperWoW's cast queue so a cast in
-- progress is not clipped. Returns true if the spell is known and was issued.
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

-- True while a haste cooldown is active, so Arcane skips Arcane Surge (its 1.5s
-- GCD does not scale with haste, making it a loss under Arcane Power / MQG).
function M:Hasted()
    return self:HasBuff("Arcane Power")
        or self:HasBuff("Mind Quickening Gem")
        or self:HasBuff("Mind Quickening")
        or self:HasBuff("Enlightenment")
end

-- A live enemy is targeted.
function M:HasEnemy()
    return UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
end

-- ============================================================
-- Shared upkeep (runs in every spec / AoE): shields, then emergency Evocation.
-- Returns true if a cast was issued.
-- ============================================================
function M:Upkeep(cfg)
    -- Ice Barrier (Frost): a cheap shield that also boosts Frost damage on
    -- Turtle. Kept up when known, off cooldown, and not already active.
    if cfg.useIceBarrier and self:KnowsSpell("Ice Barrier") and self:IsReady("Ice Barrier")
        and not self:HasBuff("Ice Barrier") then
        if self:Cast("Ice Barrier") then return true end
    end

    -- Mana Shield (optional, off by default): only when enabled, and never
    -- stacked under an active Ice Barrier.
    if cfg.useManaShield and self:KnowsSpell("Mana Shield")
        and not self:HasBuff("Mana Shield") and not self:HasBuff("Ice Barrier") then
        if self:Cast("Mana Shield") then return true end
    end

    -- Evocation: restore mana when low, in combat, and the target is not about
    -- to die (no point channelling on a mob at 10%). A channel, so the channel
    -- guard protects it on the following press.
    if cfg.useEvocation and self:KnowsSpell("Evocation") and self:IsReady("Evocation")
        and self:ManaPct() < (cfg.evocAt or 15) and UnitAffectingCombat("player")
        and (not UnitExists("target") or self:TargetHPPct() > 30) then
        if self:Cast("Evocation") then return true end
    end
    return false
end

-- ============================================================
-- Rotation entry: shared upkeep, then dispatch by spec / AoE.
-- ============================================================
function M:Rotate(cfg)
    -- Never act over a running channel (Arcane Missiles / Icicles / Evocation).
    if self.channeling and self.chanStart and (GetTime() - self.chanStart) < 16 then return end

    -- Shields and emergency Evocation, in any spec (Ice Barrier pre-pull works
    -- with no target).
    if self:Upkeep(cfg) then return end

    -- Everything below needs an attackable target.
    if not self:HasEnemy() then return end

    if cfg.aoeMode then
        self:RotateAoE(cfg)
    elseif cfg.mode == "fire" then
        self:RotateFire(cfg)
    elseif cfg.mode == "arcane" then
        self:RotateArcane(cfg)
    else
        self:RotateFrost(cfg)
    end
end

-- ------------------------------------------------------------
-- Frost: Frostbolt nuke, Frost Nova root, Icicles, Cone of Cold.
-- ------------------------------------------------------------
function M:RotateFrost(cfg)
    -- Mitigation: root the mob when it reaches melee (the leveling kite).
    if cfg.useFrostNova and self:KnowsSpell("Frost Nova") and self:IsReady("Frost Nova")
        and self:InMeleeRange() then
        if self:Cast("Frost Nova") then return end
    end

    -- Leveling: finish a low mob / regenerate with the wand.
    if self:ShouldWand(cfg) then if self:Wand() then return end end

    -- Cone of Cold: emergency slow + damage when the mob is close. Gated on
    -- melee range so it is not spammed at distance.
    if cfg.useConeOfCold and self:KnowsSpell("Cone of Cold") and self:IsReady("Cone of Cold")
        and self:InMeleeRange() then
        if self:Queue("Cone of Cold") then return end
    end

    -- Icicles: the Turtle nuke, reset/empowered by freeze effects. Cast whenever
    -- ready; the Frostbite proc from Frostbolt keeps the cooldown resetting.
    if cfg.useIcicles and self:KnowsSpell("Icicles") and self:IsReady("Icicles") then
        if self:Queue("Icicles") then return end
    end

    -- Frostbolt filler (primary nuke). Fireball covers levels 1-3 before it.
    if self:KnowsSpell("Frostbolt") then self:Queue("Frostbolt"); return end
    if self:KnowsSpell("Fireball") then self:Queue("Fireball"); return end
    self:Wand()
end

-- ------------------------------------------------------------
-- Fire: Combustion, Pyroblast opener, Scorch debuff, Fire Blast, Fireball.
-- ------------------------------------------------------------
M.scorchT = 0
M.scorchId = nil
function M:RotateFire(cfg)
    -- Mitigation root (leveling kite).
    if cfg.useFrostNova and self:KnowsSpell("Frost Nova") and self:IsReady("Frost Nova")
        and self:InMeleeRange() then
        if self:Cast("Frost Nova") then return end
    end

    -- Leveling: finish / regenerate with the wand.
    if self:ShouldWand(cfg) then if self:Wand() then return end end

    -- Combustion: guarantees crits on the next fire spells. Fire it before
    -- nuking, when off cooldown and not already active.
    if cfg.useCombustion and self:KnowsSpell("Combustion") and self:IsReady("Combustion")
        and not self:HasBuff("Combustion") then
        if self:Cast("Combustion") then return end
    end

    -- Pyroblast opener: only on a near-full-health target, so it is the pull
    -- cast and not a 6s cast stuck mid-fight.
    if cfg.usePyroblast and self:KnowsSpell("Pyroblast") and self:TargetHPPct() >= 85 then
        if self:Queue("Pyroblast") then return end
    end

    -- Scorch: build / maintain Fire Vulnerability up to the chosen stacks. A
    -- per-target throttle caps it to one cast per ~1.5s, so if the debuff cannot
    -- be read (name resolution off) Fireball still fills between Scorches rather
    -- than the rotation spamming Scorch forever.
    if cfg.useScorch and self:KnowsSpell("Scorch") then
        local stacks = self:TargetDebuffStacks("Fire Vulnerability", "Spell_Fire_SoulBurn")
        if stacks < (cfg.scorchStacks or 5) then
            local id = self:TargetId()
            local now = GetTime()
            local recent = (self.scorchId == id) and ((now - (self.scorchT or 0)) < 1.5)
            if not recent then
                self.scorchT = now; self.scorchId = id
                if self:Queue("Scorch") then return end
            end
        end
    end

    -- Fire Blast: instant, on cooldown -- extra damage and the movement /
    -- finishing tool.
    if cfg.useFireBlast and self:KnowsSpell("Fire Blast") and self:IsReady("Fire Blast") then
        if self:Queue("Fire Blast") then return end
    end

    -- Fireball filler (primary nuke). Frostbolt covers very early levels if Fire
    -- was somehow picked before Fireball is up.
    if self:KnowsSpell("Fireball") then self:Queue("Fireball"); return end
    if self:KnowsSpell("Frostbolt") then self:Queue("Frostbolt"); return end
    self:Wand()
end

-- ------------------------------------------------------------
-- Arcane: Arcane Rupture upkeep, Arcane Power, Arcane Surge (no haste),
-- Arcane Missiles filler.
-- ------------------------------------------------------------
function M:RotateArcane(cfg)
    -- Mitigation root (leveling kite).
    if cfg.useFrostNova and self:KnowsSpell("Frost Nova") and self:IsReady("Frost Nova")
        and self:InMeleeRange() then
        if self:Cast("Frost Nova") then return end
    end

    -- Leveling: finish / regenerate with the wand.
    if self:ShouldWand(cfg) then if self:Wand() then return end end

    -- Arcane Rupture upkeep: keep it on the target (it boosts Arcane Missiles).
    -- Detect either a target-debuff or a self-buff implementation.
    if cfg.useArcaneRupture and self:KnowsSpell("Arcane Rupture") then
        local up = self:TargetDebuffUp("Arcane Rupture", "Spell_Arcane_Blast")
            or self:HasBuff("Arcane Rupture")
        if not up then
            if self:Queue("Arcane Rupture") then return end
        end
    end

    -- Arcane Power: the damage steroid, off cooldown and not already active.
    if cfg.useArcanePower and self:KnowsSpell("Arcane Power") and self:IsReady("Arcane Power")
        and not self:HasBuff("Arcane Power") then
        if self:Cast("Arcane Power") then return end
    end

    -- Arcane Surge: used in the no-haste rotation; skipped while hasted.
    if not self:Hasted() and cfg.useArcaneSurge and self:KnowsSpell("Arcane Surge")
        and self:IsReady("Arcane Surge") then
        if self:Queue("Arcane Surge") then return end
    end

    -- Arcane Missiles filler (channel). Frostbolt / Fireball cover the early
    -- levels before Missiles is trained.
    if self:KnowsSpell("Arcane Missiles") then self:Queue("Arcane Missiles"); return end
    if self:KnowsSpell("Frostbolt") then self:Queue("Frostbolt"); return end
    if self:KnowsSpell("Fireball") then self:Queue("Fireball"); return end
    self:Wand()
end

-- ------------------------------------------------------------
-- AoE (kiting): Frost Nova freeze, Cone of Cold snare, Icicles, then Arcane
-- Explosion as the PBAoE finisher. Ground-targeted AoE (Blizzard / Flamestrike)
-- is intentionally not auto-cast -- it needs a cursor click that cannot be
-- placed reliably from a one-button rotation.
-- ------------------------------------------------------------
function M:RotateAoE(cfg)
    -- Freeze the pack when it reaches melee.
    if cfg.useFrostNova and self:KnowsSpell("Frost Nova") and self:IsReady("Frost Nova")
        and self:InMeleeRange() then
        if self:Cast("Frost Nova") then return end
    end

    -- Cone of Cold: snare + damage the pack in front of you (not range-gated in
    -- AoE -- you face the pack).
    if cfg.useConeOfCold and self:KnowsSpell("Cone of Cold") and self:IsReady("Cone of Cold") then
        if self:Queue("Cone of Cold") then return end
    end

    -- Icicles when ready (strong on a frozen pack).
    if cfg.useIcicles and self:KnowsSpell("Icicles") and self:IsReady("Icicles") then
        if self:Queue("Icicles") then return end
    end

    -- Drop to the wand below the mana floor so AoE does not bottom out with no
    -- escape.
    if self:WandUsable(cfg) and self:ManaPct() < (cfg.wandManaFloor or 25) then
        if self:Wand() then return end
    end

    -- Arcane Explosion: the PBAoE finisher for every spec.
    if self:KnowsSpell("Arcane Explosion") then self:Queue("Arcane Explosion"); return end

    -- Low-level fallback: just nuke the target.
    if self:KnowsSpell("Frostbolt") then self:Queue("Frostbolt"); return end
    if self:KnowsSpell("Fireball") then self:Queue("Fireball"); return end
    self:Wand()
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core.
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "mode" then
        local cfg = Aegis_SBR:GetActiveProfile()
        local mode = self.modeAlias[string.lower(t[2] or "")]
        if cfg and mode then
            cfg.mode = mode
            msgOut("mode = " .. mode .. ".")
        else
            msgOut("usage: /sbr mode <frost|fire|arcane>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "aoe" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return true end
        cfg.aoeMode = not cfg.aoeMode
        msgOut("AoE mode " .. (cfg.aoeMode and "on" or "off") .. ".")
        return true
    end
    if cmd == "wandhp" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then return true end
        local v = tonumber(t[2])
        if v and v >= 0 and v <= 100 then
            cfg.wandHp = v
            if v == 0 then msgOut("wand-finish off (cast targets to death).")
            else msgOut("wand-finish below " .. v .. "% target health.") end
        else
            msgOut("usage: /sbr wandhp <0-100> (0 = off)", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end
