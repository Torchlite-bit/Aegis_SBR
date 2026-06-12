-- ============================================================
-- Class_Druid  -  feral druid module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). Cat (DPS) and Bear (tank), form adaptive.
-- ============================================================
-- Model:
--  * The rotation follows the form you are IN. Cat Form runs the DPS
--    rotation, Bear/Dire Bear runs the tank rotation, and caster form
--    shifts you into the profile's preferred form. This also closes the
--    powershift loop: shifting out lands in caster, the next press
--    shifts straight back into Cat.
--  * Two cat styles (Turtle WoW): "Claw & Bleed" keeps Rake and Rip
--    rolling and builds with Claw (pairs with bleed-energy talents like
--    Ancient Brutality); "Shred & Powershift" builds with Shred and
--    finishes with Ferocious Bite for bleed-immune targets (MC/BWL),
--    optionally powershifting for energy.
--  * Powershifting never fires while Tiger's Fury is up, so the buff is
--    not thrown away; it waits for the buff to fall off.
--  * Bear keeps Faerie Fire and Demoralizing Roar up, dumps rage into
--    Maul, and leads with Swipe when the AoE toggle (/ar aoe) is on.
-- ============================================================

local M = AutoRota:NewClassModule("DRUID")
M.uiTitle = "Druid (Feral)"
M.uiHeight = 600

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- Untalented 1.12 base costs; talents only lower these, so gating on the
-- base never blocks an affordable cast for long, it just avoids burning a
-- press on a cast the client would reject.
local COST = {
    ["Claw"] = 45, ["Shred"] = 60, ["Rake"] = 40,
    ["Rip"] = 30, ["Ferocious Bite"] = 35,
    ["Tiger's Fury"] = 30, ["Pounce"] = 50, ["Ravage"] = 60,
    ["Maul"] = 15, ["Swipe"] = 20, ["Demoralizing Roar"] = 10,
}
local TF_RENEW = 2   -- recast Tiger's Fury when under this many seconds left

-- Debuff textures on the TARGET (fragment match)
M.debuffTex = {
    ["Faerie Fire (Feral)"] = "Spell_Nature_FaerieFire",
    ["Rake"]                = "Ability_Druid_Disembowel",
    ["Rip"]                 = "Ability_GhoulFrenzy",
    ["Demoralizing Roar"]   = "Ability_Druid_DemoralizingRoar",
}

M.templates = {
    starter = {  -- leveling cat: bleeds, no powershift
        form = "cat", catStyle = "bleed", opener = "auto", cpFinish = 5,
        useTigersFury = true, ffCat = true,
        powershift = false, psEnergy = 15,
        ffBear = true, useDemo = true, useMaul = true, aoeSwipe = false, useEnrage = false,
    },
    catbleed = {
        form = "cat", catStyle = "bleed", opener = "auto", cpFinish = 5,
        useTigersFury = true, ffCat = true,
        powershift = false, psEnergy = 15,
        ffBear = true, useDemo = true, useMaul = true, aoeSwipe = false, useEnrage = false,
    },
    catshred = {  -- bleed-immune raid targets: Shred, FB, powershift
        form = "cat", catStyle = "shred", opener = "auto", cpFinish = 5,
        useTigersFury = true, ffCat = true,
        powershift = true, psEnergy = 15,
        ffBear = true, useDemo = true, useMaul = true, aoeSwipe = false, useEnrage = false,
    },
    bear = {
        form = "bear", catStyle = "bleed", opener = "auto", cpFinish = 5,
        useTigersFury = true, ffCat = true,
        powershift = false, psEnergy = 15,
        ffBear = true, useDemo = true, useMaul = true, aoeSwipe = false, useEnrage = true,
    },
}

M.styleAlias = { bleed = "bleed", claw = "bleed", shred = "shred", powershift = "shred" }
M.formAlias  = { cat = "cat", bear = "bear" }

function M:NormalizeProfile(c)
    if c.form == nil then c.form = "cat" end
    if c.catStyle == nil then c.catStyle = "bleed" end
    if c.opener == nil then c.opener = "auto" end
    if c.cpFinish == nil then c.cpFinish = 5 end
    if c.useTigersFury == nil then c.useTigersFury = true end
    if c.ffCat == nil then c.ffCat = true end
    if c.powershift == nil then c.powershift = false end
    if c.psEnergy == nil then c.psEnergy = 15 end
    if c.ffBear == nil then c.ffBear = true end
    if c.useDemo == nil then c.useDemo = true end
    if c.useMaul == nil then c.useMaul = true end
    if c.aoeSwipe == nil then c.aoeSwipe = false end
    if c.useEnrage == nil then c.useEnrage = false end
    return c
end

function M:ProfileValidity(cfg)
    local missing = {}
    -- Only flag explicit choices the character cannot make; level-gated
    -- upkeeps degrade gracefully in the rotation via KnowsSpell.
    if cfg.form == "cat" and not self:KnowsSpell("Cat Form") then table.insert(missing, "Cat Form") end
    if cfg.form == "bear" and not (self:KnowsSpell("Bear Form") or self:KnowsSpell("Dire Bear Form")) then table.insert(missing, "Bear Form") end
    if cfg.catStyle == "shred" and not self:KnowsSpell("Shred") then table.insert(missing, "Shred") end
    if cfg.opener == "Ravage" and not self:KnowsSpell("Ravage") then table.insert(missing, "Ravage") end
    if cfg.opener == "Pounce" and not self:KnowsSpell("Pounce") then table.insert(missing, "Pounce") end
    return (table.getn(missing) == 0), missing
end

-- ============================================================
-- Helpers
-- ============================================================

-- CastSpellByName parses trailing parentheses as a rank spec, so a name
-- like "Faerie Fire (Feral)" needs an explicit empty rank: "...(Feral)()".
function M:CastSafe(name)
    if not self:KnowsSpell(name) then return false end
    if string.find(name, "%(") then
        CastSpellByName(name .. "()")
    else
        CastSpellByName(name)
    end
    return true
end

-- The shapeshift form currently active, by name, or nil in caster form.
function M:CurrentForm()
    for i = 1, GetNumShapeshiftForms() do
        local _, name, active = GetShapeshiftFormInfo(i)
        if active then return name end
    end
    return nil
end

-- The form spell the profile wants entered from caster form.
function M:PreferredFormSpell(cfg)
    if cfg.form == "bear" then
        if self:KnowsSpell("Dire Bear Form") then return "Dire Bear Form" end
        if self:KnowsSpell("Bear Form") then return "Bear Form" end
        return nil
    end
    if self:KnowsSpell("Cat Form") then return "Cat Form" end
    -- a druid below 20 with a bear-less cat profile still gets bear
    if self:KnowsSpell("Dire Bear Form") then return "Dire Bear Form" end
    if self:KnowsSpell("Bear Form") then return "Bear Form" end
    return nil
end

function M:TargetHasTexture(frag)
    if not frag or frag == "" then return false end
    for i = 1, 40 do
        local t = UnitDebuff("target", i)
        if t and string.find(t, frag) then return true end
    end
    return false
end

function M:DebuffUp(spellName)
    return self:TargetHasTexture(self.debuffTex[spellName])
end

-- Affordable and learned. UnitMana("player") reads the active power, so
-- in Cat Form this is energy and in Bear Form it is rage.
function M:CanPay(name)
    if not self:KnowsSpell(name) then return false end
    local cost = COST[name] or 0
    return UnitMana("player") >= cost
end

-- ============================================================
-- Cat Form (DPS)
-- ============================================================
function M:ResolveOpener(cfg)
    local o = cfg.opener or "auto"
    if o == "none" then return nil end
    if o == "Ravage" or (o == "auto" and self:KnowsSpell("Ravage")) then
        if self:CanPay("Ravage") then return "Ravage" end
    end
    if o == "Pounce" or o == "auto" then
        if self:CanPay("Pounce") then return "Pounce" end
    end
    return nil   -- not affordable / not known: fall through, Rake/Claw opens fine
end

function M:RotateCat(cfg)
    local energy = UnitMana("player")
    local cp = GetComboPoints("player", "target")
    local bleed = (cfg.catStyle ~= "shred")

    if self.trace then
        self:Trace("cat style=" .. (cfg.catStyle or "bleed")
            .. " energy=" .. energy .. " cp=" .. cp
            .. " prowl=" .. (self:HasBuff("Prowl") and "Y" or "N")
            .. " TF=" .. (cfg.useTigersFury and string.format("%.0fs", self:BuffTime("Tiger's Fury")) or "-")
            .. " FF=" .. (cfg.ffCat and (self:DebuffUp("Faerie Fire (Feral)") and "Y" or "n") or "-")
            .. " rake=" .. (bleed and (self:DebuffUp("Rake") and "Y" or "n") or "-")
            .. " rip=" .. (bleed and (self:DebuffUp("Rip") and "Y" or "n") or "-")
            .. " ps=" .. (cfg.powershift and "on" or "off"))
    end

    -- P0 stealth opener
    if self:HasBuff("Prowl") then
        local op = self:ResolveOpener(cfg)
        if op and self:CastSafe(op) then return end
        -- no affordable opener: fall through, the builder breaks stealth
    end

    -- P1 Faerie Fire (Feral), free, keeps the armor debuff up
    if cfg.ffCat and not self:DebuffUp("Faerie Fire (Feral)") then
        if self:CastSafe("Faerie Fire (Feral)") then return end
    end

    -- P2 Tiger's Fury upkeep
    if cfg.useTigersFury and self:KnowsSpell("Tiger's Fury") then
        if self:BuffTime("Tiger's Fury") < TF_RENEW and self:CanPay("Tiger's Fury") then
            if self:CastSafe("Tiger's Fury") then return end
        end
    end

    -- P3 finisher at the combo threshold
    if cp >= (cfg.cpFinish or 5) then
        if bleed and self:KnowsSpell("Rip") and not self:DebuffUp("Rip") then
            if self:CanPay("Rip") and self:CastSafe("Rip") then return end
        elseif self:CanPay("Ferocious Bite") then
            if self:CastSafe("Ferocious Bite") then return end
        end
        return   -- at threshold but not affordable yet: wait, never waste a builder
    end

    -- P4 Rake upkeep (bleed style)
    if bleed and self:KnowsSpell("Rake") and not self:DebuffUp("Rake") then
        if self:CanPay("Rake") and self:CastSafe("Rake") then return end
    end

    -- P5 builder
    local builder = bleed and "Claw" or "Shred"
    if self:CanPay(builder) then
        if self:CastSafe(builder) then return end
    end

    -- P6 powershift (shred style, opt-in): bottomed on energy and Tiger's
    -- Fury is NOT running (a shift would throw the buff away). Shifting out
    -- lands in caster form; the next press shifts straight back into Cat,
    -- which forces a fresh energy bar. Needs mana for the re-shift.
    if cfg.powershift and not bleed and energy < (cfg.psEnergy or 15) then
        if not self:HasBuff("Tiger's Fury") then
            self:CastSafe("Cat Form")   -- recasting the active form shifts OUT
            return
        end
    end
end

-- ============================================================
-- Bear Form (tank)
-- ============================================================
function M:RotateBear(cfg)
    local rage = UnitMana("player")

    if self.trace then
        self:Trace("bear rage=" .. rage
            .. " FF=" .. (cfg.ffBear and (self:DebuffUp("Faerie Fire (Feral)") and "Y" or "n") or "-")
            .. " demo=" .. (cfg.useDemo and (self:DebuffUp("Demoralizing Roar") and "Y" or "n") or "-")
            .. " aoe=" .. (cfg.aoeSwipe and "Y" or "N")
            .. " enrage=" .. (cfg.useEnrage and self:CDInfo("Enrage") or "-"))
    end

    -- P1 Enrage when rage starved (opt-in; it lowers armor, so only in combat)
    if cfg.useEnrage and rage < 20 and UnitAffectingCombat("player") and self:OwnCDReady("Enrage") then
        if self:CastSafe("Enrage") then return end
    end

    -- P2 Faerie Fire (Feral), free threat and the armor debuff
    if cfg.ffBear and not self:DebuffUp("Faerie Fire (Feral)") then
        if self:CastSafe("Faerie Fire (Feral)") then return end
    end

    -- P3 Demoralizing Roar upkeep
    if cfg.useDemo and self:KnowsSpell("Demoralizing Roar") and not self:DebuffUp("Demoralizing Roar") then
        if self:CanPay("Demoralizing Roar") and self:CastSafe("Demoralizing Roar") then return end
    end

    -- P4 Swipe leads when the AoE toggle is on
    if cfg.aoeSwipe and self:CanPay("Swipe") then
        if self:CastSafe("Swipe") then return end
    end

    -- P5 Maul as the rage dump (queues on the next swing)
    if cfg.useMaul and self:CanPay("Maul") then
        if self:CastSafe("Maul") then return end
    end
end

-- ============================================================
-- Rotation entry: follow the form you are in; from caster form, enter
-- the preferred one. Travel/Aquatic/Moonkin count as "not a combat form"
-- and are shifted out of, so keep those profiles off this macro.
-- ============================================================
function M:Rotate(cfg)
    local form = self:CurrentForm()
    if form == "Cat Form" then
        self:RotateCat(cfg)
    elseif form == "Bear Form" or form == "Dire Bear Form" then
        self:RotateBear(cfg)
    else
        local want = self:PreferredFormSpell(cfg)
        if want then
            if self.trace then self:Trace("caster form, shifting into " .. want) end
            self:CastSafe(want)
        else
            self:Throttle("no combat form known yet, learn Bear Form first.")
        end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "aoe" then
        local cfg = AutoRota:GetActiveProfile()
        if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return true end
        cfg.aoeSwipe = not cfg.aoeSwipe
        msgOut("Swipe " .. (cfg.aoeSwipe and "on (AoE)" or "off") .. ".")
        return true
    end
    if cmd == "style" then
        local cfg = AutoRota:GetActiveProfile()
        local style = self.styleAlias[string.lower(t[2] or "")]
        if cfg and style then
            cfg.catStyle = style
            msgOut("cat style = " .. (style == "bleed" and "Claw & Bleed" or "Shred & Powershift") .. ".")
        else
            msgOut("usage: /ar style <bleed|shred>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "form" then
        local cfg = AutoRota:GetActiveProfile()
        local form = self.formAlias[string.lower(t[2] or "")]
        if cfg and form then
            cfg.form = form
            msgOut("preferred form = " .. form .. ".")
        else
            msgOut("usage: /ar form <cat|bear>", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end
