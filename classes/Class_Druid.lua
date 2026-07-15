-- ============================================================
-- Class_Druid  -  feral + balance druid module for Aegis_SBR
-- Turtle WoW 1.12 (SuperWoW). Cat (DPS), Bear (tank), and a caster /
-- Moonkin (Balance) rotation, form adaptive, works from level 1.
-- ============================================================
-- Model:
--  * The rotation follows the form you are IN. Cat Form runs the DPS
--    rotation, Bear/Dire Bear runs the tank rotation, Moonkin (or plain
--    caster form with a "caster" preference) runs the Balance rotation,
--    and otherwise caster form shifts you into the profile's preferred
--    form. This also closes the powershift loop: shifting out lands in
--    caster, the next press shifts straight back into Cat.
--  * Level 1+: if the preferred combat form is not learned yet (Bear is
--    level 10, Cat is 20), the caster rotation runs instead, so a fresh
--    druid gets Moonfire upkeep and Wrath from the very first level and
--    the profile grows into its form automatically.
--  * Balance: keep Moonfire and Insect Swarm up, react to Eclipse procs
--    by casting the empowered opposite nuke, otherwise chain-cast the
--    primary nuke to fish for the next proc. Nukes are queued through
--    SuperWoW so spamming never clips the current cast.
--  * Two cat styles (Turtle WoW): "Claw & Bleed" keeps Rake and Rip
--    rolling and builds with Claw (pairs with bleed-energy talents like
--    Ancient Brutality); "Shred & Powershift" builds with Shred and
--    finishes with Ferocious Bite for bleed-immune targets (MC/BWL),
--    optionally powershifting for energy.
--  * Powershifting never fires while Tiger's Fury is up, so the buff is
--    not thrown away; it waits for the buff to fall off.
--  * Bear keeps Faerie Fire and Demoralizing Roar up, dumps rage into
--    Maul, and leads with Swipe when the AoE toggle (/sbr aoe) is on.
-- ============================================================

local M = Aegis_SBR:NewClassModule("DRUID")
M.uiTitle = "Druid"
M.uiHeight = 768
-- Auto-attack is managed per form in this module instead of by the core, so a
-- white swing is only started in Cat/Bear (where you melee) and never in
-- caster/Moonkin (where you are casting). See EnsureMeleeSwing below.
M.meleeAutoAttack = false

-- Chat output is shared in the core; this shim keeps call sites unchanged.
local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

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
    ["Moonfire"]            = "Spell_Nature_StarFall",
    ["Insect Swarm"]        = "Spell_Nature_InsectSwarm",
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
        useMoonfire = true, useInsectSwarm = true, eclipse = true, nuke = "Wrath",
    },
    balance = {  -- caster / Moonkin: DoTs up, Eclipse weaving
        form = "caster", catStyle = "bleed", opener = "auto", cpFinish = 5,
        useTigersFury = true, ffCat = true,
        powershift = false, psEnergy = 15,
        ffBear = true, useDemo = true, useMaul = true, aoeSwipe = false, useEnrage = false,
        useMoonfire = true, useInsectSwarm = true, eclipse = true, nuke = "Wrath",
    },
    tree = {  -- Restoration: heal in caster form (downranked HoTs + Healing Touch)
        form = "tree",
        healThreshold = 90, useInnervate = true, innervateAt = 30,
        useNSCombo = true, nsHpPct = 40, useSwiftmend = true, swiftmendPct = 65,
        useRegrowth = true, regrowthPct = 55, useRejuv = true,
        useWildGrowth = false, wildGrowthCount = 4, useLifebloom = false, healPower = 0,
        weaveDamage = false, weaveManaFloor = 40,
    },
}

M.styleAlias = { bleed = "bleed", claw = "bleed", shred = "shred", powershift = "shred" }
M.formAlias  = { cat = "cat", bear = "bear", caster = "caster", moonkin = "caster", balance = "caster",
                 tree = "tree", resto = "tree", restoration = "tree", heal = "tree" }

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
    if c.hpManage == nil then c.hpManage = false end
    if c.hpLow == nil then c.hpLow = 35 end
    if c.hpHigh == nil then c.hpHigh = 70 end
    if c.useMoonfire == nil then c.useMoonfire = true end
    if c.useInsectSwarm == nil then c.useInsectSwarm = true end
    if c.eclipse == nil then c.eclipse = true end
    if c.nuke == nil then c.nuke = "Wrath" end
    if c.useGrowl == nil then c.useGrowl = true end
    -- Restoration (heal) profile fields
    if c.healThreshold == nil then c.healThreshold = 90 end
    if c.useInnervate == nil then c.useInnervate = true end
    if c.innervateAt == nil then c.innervateAt = 30 end
    if c.useNSCombo == nil then c.useNSCombo = true end
    if c.nsHpPct == nil then c.nsHpPct = 40 end
    if c.useSwiftmend == nil then c.useSwiftmend = true end
    if c.swiftmendPct == nil then c.swiftmendPct = 65 end
    if c.useRegrowth == nil then c.useRegrowth = true end
    if c.regrowthPct == nil then c.regrowthPct = 55 end
    if c.useRejuv == nil then c.useRejuv = true end
    if c.useWildGrowth == nil then c.useWildGrowth = false end
    if c.wildGrowthCount == nil then c.wildGrowthCount = 4 end
    if c.useLifebloom == nil then c.useLifebloom = false end
    if c.healPower == nil then c.healPower = 0 end
    if c.weaveDamage == nil then c.weaveDamage = false end
    if c.weaveManaFloor == nil then c.weaveManaFloor = 40 end
    return c
end

-- Start the form's white swing in melee forms (Cat/Bear). This runs whether
-- or not SuperCleveRoidMacros is loaded: the core's EnsureAutoAttack only
-- toggles Attack when you are NOT already swinging (its IsCurrentAction guard),
-- so if SCRM already started the swing this is a no-op, and if nothing did
-- (e.g. a bare "/sbr" macro gives SCRM no /startattack to hook) Aegis_SBR starts
-- it. Either way the swing runs, with no double-toggle.
-- NOTE: the Attack action must sit on a bar slot that is NOT replaced by the
-- Cat/Bear form bar (a side or bottom bar), otherwise there is nothing for
-- this to toggle while shapeshifted.
function M:EnsureMeleeSwing()
    -- Shapeshifting swaps the whole action bar AND stops the current swing, so
    -- the core's cached Attack slot can be stale the first press in a new form.
    -- Drop it on a form change to force one fresh scan, which re-finds Attack
    -- on the now-current bars and restarts the swing that the shift halted.
    local form = self:CurrentForm() or "none"
    if form ~= self.lastSwingForm then
        Aegis_SBR.attackSlot = nil
        self.lastSwingForm = form
    end
    Aegis_SBR:EnsureAutoAttack()
end

function M:ProfileValidity(cfg)
    local missing = {}
    -- Only flag explicit choices the character cannot make; level-gated
    -- upkeeps degrade gracefully in the rotation via KnowsSpell. A combat
    -- form that is not learned YET is not flagged either: the caster
    -- rotation covers those levels and the profile grows into its form.
    if cfg.catStyle == "shred" and self:KnowsSpell("Cat Form") and not self:KnowsSpell("Shred") then table.insert(missing, "Shred") end
    if cfg.opener == "Ravage" and not self:KnowsSpell("Ravage") then table.insert(missing, "Ravage") end
    if cfg.opener == "Pounce" and not self:KnowsSpell("Pounce") then table.insert(missing, "Pounce") end
    if cfg.nuke == "Starfire" and not self:KnowsSpell("Starfire") then table.insert(missing, "Starfire") end
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
    return self:TargetDebuffUp(nil, frag)
end

-- The debuffTex keys are the spell names, so they also serve as the exact
-- name match (SuperWoW id path); the texture stays as the fallback.
function M:DebuffUp(spellName)
    return self:TargetDebuffUp(spellName, self.debuffTex[spellName])
end

-- Affordable and learned. UnitMana("player") reads the active power, so
-- in Cat Form this is energy and in Bear Form it is rage.
function M:CanPay(name)
    if not self:KnowsSpell(name) then return false end
    local cost = COST[name] or 0
    return UnitMana("player") >= cost
end

-- Queue a cast-time spell through SuperWoW so spamming the macro never
-- clips the cast in progress; the press during a cast queues the next
-- spell, which is also what lands the Eclipse-buffed nuke the moment the
-- proc window opens.
function M:QueueCast(name)
    if not self:KnowsSpell(name) then return false end
    if QueueSpellByName then QueueSpellByName(name) else CastSpellByName(name) end
    return true
end

-- Which Eclipse side is up on the player, if any: "lunar" empowers
-- Starfire, "solar" empowers Wrath. Exact buff names are tried first,
-- then a texture scan as a fallback (orange = solar, blue/plain = lunar).
-- If Turtle uses different names, /sbr debug with the proc up shows them;
-- they drop into this list in one place.
M.ECLIPSE_LUNAR = { "Eclipse (Lunar)", "Lunar Eclipse", "Eclipse" }
M.ECLIPSE_SOLAR = { "Eclipse (Solar)", "Solar Eclipse" }
function M:EclipseSide()
    for i = 1, table.getn(self.ECLIPSE_SOLAR) do
        if self:HasBuff(self.ECLIPSE_SOLAR[i]) then return "solar" end
    end
    for i = 1, table.getn(self.ECLIPSE_LUNAR) do
        if self:HasBuff(self.ECLIPSE_LUNAR[i]) then return "lunar" end
    end
    for i = 1, 32 do
        local b = UnitBuff("player", i)
        if b and string.find(b, "Eclipse") then
            if string.find(b, "Orange") or string.find(b, "Solar") then return "solar" end
            return "lunar"
        end
    end
    return nil
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

    self:EnsureMeleeSwing()

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

    self:EnsureMeleeSwing()

    if self.trace then
        self:Trace("bear rage=" .. rage
            .. " def=" .. (self.hpDefenseActive and "Y" or "N")
            .. " FF=" .. (cfg.ffBear and (self:DebuffUp("Faerie Fire (Feral)") and "Y" or "n") or "-")
            .. " demo=" .. (cfg.useDemo and (self:DebuffUp("Demoralizing Roar") and "Y" or "n") or "-")
            .. " aoe=" .. (cfg.aoeSwipe and "Y" or "N")
            .. " enrage=" .. (cfg.useEnrage and self:CDInfo("Enrage") or "-"))
    end

    -- P1 Growl to take threat when the target is not already focused on us.
    -- Covers the pull (target has no aggro yet) and any aggro loss in a group;
    -- a solo druid who is already being attacked never wastes the taunt.
    if cfg.useGrowl and self:KnowsSpell("Growl") and self:IsReady("Growl") then
        if not (UnitExists("targettarget") and UnitIsUnit("targettarget", "player")) then
            if self:CastSafe("Growl") then return end
        end
    end

    -- P2 Faerie Fire (Feral): the bear's ranged opener. Instant, 30yd, applies
    -- the armor debuff and deals threat+damage, so it starts the pull from
    -- range (Moonfire cannot be cast in bear form; this is its bear analog).
    if cfg.ffBear and not self:DebuffUp("Faerie Fire (Feral)") then
        if self:CastSafe("Faerie Fire (Feral)") then return end
    end

    -- P3 Enrage when rage starved (opt-in; it lowers armor, so only in combat)
    if cfg.useEnrage and rage < 20 and UnitAffectingCombat("player") and self:OwnCDReady("Enrage") then
        if self:CastSafe("Enrage") then return end
    end

    -- P4 Demoralizing Roar upkeep
    if cfg.useDemo and self:KnowsSpell("Demoralizing Roar") and not self:DebuffUp("Demoralizing Roar") then
        if self:CanPay("Demoralizing Roar") and self:CastSafe("Demoralizing Roar") then return end
    end

    -- P5 Swipe leads when the AoE toggle is on
    if cfg.aoeSwipe and self:CanPay("Swipe") then
        if self:CastSafe("Swipe") then return end
    end

    -- P6 Maul as the rage dump (queues on the next swing)
    if cfg.useMaul and self:CanPay("Maul") then
        if self:CastSafe("Maul") then return end
    end
end

-- ============================================================
-- Caster / Moonkin (Balance). Also the level 1+ fallback before any
-- combat form is learned: at low levels this degrades to Moonfire
-- upkeep plus Wrath, exactly the right leveling caster loop.
-- ============================================================
function M:RotateCaster(cfg)
    local side = cfg.eclipse and self:EclipseSide() or nil

    if self.trace then
        self:Trace("caster nuke=" .. (cfg.nuke or "Wrath")
            .. " MF=" .. (cfg.useMoonfire and (self:DebuffUp("Moonfire") and "Y" or "n") or "-")
            .. " IS=" .. (cfg.useInsectSwarm and (self:DebuffUp("Insect Swarm") and "Y" or "n") or "-")
            .. " eclipse=" .. (side or "-")
            .. " mana=" .. string.format("%.0f", self:ManaPct()))
    end

    -- P1 Moonfire upkeep (instant)
    if cfg.useMoonfire and self:KnowsSpell("Moonfire") and not self:DebuffUp("Moonfire") then
        if self:CastSafe("Moonfire") then return end
    end

    -- P2 Insect Swarm upkeep (instant)
    if cfg.useInsectSwarm and self:KnowsSpell("Insect Swarm") and not self:DebuffUp("Insect Swarm") then
        if self:CastSafe("Insect Swarm") then return end
    end

    -- P3 Eclipse reaction: cast the empowered opposite nuke. Because casts
    -- are queued, the press during the current cast already lines this up
    -- for the instant the proc window opens.
    if side == "lunar" and self:KnowsSpell("Starfire") then
        if self:QueueCast("Starfire") then return end
    end
    if side == "solar" and self:KnowsSpell("Wrath") then
        if self:QueueCast("Wrath") then return end
    end

    -- P4 chain-cast the primary nuke to fish for the next proc
    local nuke = cfg.nuke or "Wrath"
    if not self:KnowsSpell(nuke) then nuke = "Wrath" end
    if self:QueueCast(nuke) then return end
end

-- ============================================================
-- Defensive form switch (hysteresis, like the paladin's resource
-- management): below hpLow force Bear and stay there, at/above hpHigh
-- release back to the preferred form. Inert until a bear form is known.
-- ============================================================
function M:BearFormSpell()
    if self:KnowsSpell("Dire Bear Form") then return "Dire Bear Form" end
    if self:KnowsSpell("Bear Form") then return "Bear Form" end
    return nil
end

function M:UpdateDefense(cfg)
    if cfg.hpManage and self:BearFormSpell() then
        local hp = self:PlayerHPPct()
        if hp < (cfg.hpLow or 35) then self.hpDefenseActive = true end
        if hp >= (cfg.hpHigh or 70) then self.hpDefenseActive = false end
    else
        self.hpDefenseActive = false
    end
end

-- ============================================================
-- Rotation entry: follow the form you are in. Cat and Bear run their
-- rotations, Moonkin runs Balance. From plain caster form: a "caster"
-- preference enters Moonkin (when learned) and runs Balance; a cat/bear
-- preference shifts into that form; and if no combat form is learned
-- yet (level 1-9, or 10-19 for a cat profile), the caster rotation
-- carries the character until the form appears.
-- ============================================================
-- ============================================================
-- Restoration (heal engine)
-- Modeled on the Priest engine: scan the group, find the worst-hurt
-- reachable unit, and pick the cheapest rank that covers the deficit
-- (downranking). Heals cast with a SuperWoW unit argument so the current
-- target is never dropped. Per the build plan this heals in CASTER form and
-- does NOT auto-shift into Tree of Life (left off until Tree's 1.18.1 cast
-- rules are confirmed). HoT upkeep is tracked by a per-unit reapply timer,
-- not by reading the buff back (raid buff readback is unreliable on 1.12).
--
-- Rank base-heal / mana numbers are VANILLA BASELINES, meant to be tuned to
-- Turtle 1.18.1; the downrank decision only needs the ranks ordered roughly
-- right, so approximate values still pick a sane rank.
-- ============================================================
function M:RunsWithoutTarget(cfg)
    return cfg.form == "tree"   -- a healer runs with no enemy targeted
end

function M:ManaPct()
    local mx = UnitManaMax("player")
    if not mx or mx <= 0 then return 100 end
    return UnitMana("player") / mx * 100
end

-- Name-based talent rank (position-proof).
function M:TalentRank(name)
    for t = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(t) do
            local nm, _, _, _, rank = GetTalentInfo(t, i)
            if nm == name then return rank or 0 end
        end
    end
    return 0
end

-- Healing Touch: primary direct heal, downranked to "snipe".
M.HT_HEAL = { 44, 99, 219, 404, 631, 850, 1111, 1414, 1739, 2123, 2472, 2832 }
M.HT_MANA = { 25, 55, 110, 185, 270, 335, 404, 495, 560, 655, 740, 825 }
-- Regrowth: fast direct + HoT burst (direct portion sized here).
M.RG_HEAL = { 139, 187, 257, 328, 414, 511, 612, 713, 814, 915 }
M.RG_MANA = { 120, 160, 215, 280, 350, 415, 480, 545, 600, 675 }
-- Rejuvenation: HoT total over its duration (maintenance, max affordable rank).
M.RJ_TOTAL = { 32, 56, 116, 180, 244, 304, 388, 488, 608, 752, 888, 932 }
M.RJ_MANA  = { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 390, 415 }

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

-- Per-unit HoT reapply timer (apply, then re-apply a little before it ends).
M.hotT = {}
function M:NoteHoT(unit, spell)
    local n = UnitName(unit) or "?"
    self.hotT[n] = self.hotT[n] or {}
    self.hotT[n][spell] = GetTime()
end
function M:HoTActive(unit, spell, dur)
    local n = UnitName(unit) or "?"
    local rec = self.hotT[n]
    if not rec or not rec[spell] then return false end
    return (GetTime() - rec[spell]) < dur
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

-- Gift of Nature: +2% healing per rank (name-based).
function M:HealMods()
    return 1 + 0.02 * self:TalentRank("Gift of Nature")
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

-- Largest affordable rank (for HoTs, where bigger ticks are just better).
function M:MaxAffordableRank(baseName, manas, mana)
    local maxr = self:MaxRank(baseName)
    if maxr < 1 then return nil end
    if maxr > table.getn(manas) then maxr = table.getn(manas) end
    for r = maxr, 1, -1 do
        if manas[r] and mana >= manas[r] then return baseName .. "(Rank " .. r .. ")" end
    end
    return nil
end

function M:CastOn(spell, unit)
    CastSpellByName(spell, unit)
end

function M:GcdReady()
    local probes = { "Rejuvenation", "Healing Touch", "Regrowth", "Wrath", "Moonfire" }
    for i = 1, table.getn(probes) do
        if self:KnowsSpell(probes[i]) then return self:IsReady(probes[i]) end
    end
    return true
end

-- Heal decision. Returns nothing; casts one heal per press via early return.
-- Order: drop form to cast -> Innervate (mana) -> NS->instant HT (emergency) ->
-- Swiftmend -> Wild Growth (AoE) -> Regrowth (burst) -> Rejuv/Lifebloom upkeep ->
-- downranked Healing Touch (fill).
function M:RotateResto(cfg)
    -- Heals only cast in caster form; drop any shapeshift first (no Tree auto-shift).
    local form = self:CurrentForm()
    if form then
        if self.trace then self:Trace("resto: dropping " .. form .. " to cast") end
        self:CastSafe(form)
        return
    end
    if not self:GcdReady() then return end

    local ratio = (cfg.healThreshold or 90) / 100
    local unit, deficit, pct = self:WorstHurt(ratio)

    -- Innervate yourself when low so the fight can keep going.
    if cfg.useInnervate ~= false and self:KnowsSpell("Innervate")
        and self:OwnCDReady("Innervate") and not self:HasBuff("Innervate")
        and self:ManaPct() <= (cfg.innervateAt or 30) then
        self:CastOn("Innervate", "player"); return
    end

    if not unit then
        -- Nobody needs healing: optionally weave damage in the downtime. Only with
        -- an enemy targeted and mana above the floor, so it never starves heals.
        if cfg.weaveDamage and self:ManaPct() >= (cfg.weaveManaFloor or 40)
            and UnitExists("target") and UnitCanAttack("player", "target")
            and not UnitIsDeadOrGhost("target") then
            if self:KnowsSpell("Moonfire") and not self:HoTActive("target", "Moonfire", 10) then
                self:NoteHoT("target", "Moonfire"); CastSpellByName("Moonfire"); return
            end
            if self:KnowsSpell("Wrath") then CastSpellByName("Wrath"); return end
        end
        return   -- nobody hurt past the threshold; nothing to weave
    end

    local mana = UnitMana("player")
    local hpb  = cfg.healPower or 0
    local mods = self:HealMods()
    local htEff = self:EffHeals(self.HT_HEAL, 0.8, mods, hpb)
    local rgEff = self:EffHeals(self.RG_HEAL, 0.5, mods, hpb)

    -- Emergency: Nature's Swiftness -> instant max Healing Touch. If NS is already
    -- up, fire the big heal now; otherwise pop NS when a target is in real trouble.
    if self:HasBuff("Nature's Swiftness") then
        local maxr = self:MaxRank("Healing Touch")
        if maxr >= 1 then
            self:CommitHeal(unit, htEff[maxr] or deficit, 0)
            self:CastOn("Healing Touch(Rank " .. maxr .. ")", unit); return
        end
    end
    if cfg.useNSCombo ~= false and pct <= (cfg.nsHpPct or 40) / 100
        and self:KnowsSpell("Nature's Swiftness") and self:OwnCDReady("Nature's Swiftness") then
        self:Cast("Nature's Swiftness"); return
    end

    -- Swiftmend: instant top-up that consumes a Rejuv/Regrowth already on the unit.
    if cfg.useSwiftmend ~= false and self:KnowsSpell("Swiftmend") and self:OwnCDReady("Swiftmend")
        and pct <= (cfg.swiftmendPct or 65) / 100
        and (self:HoTActive(unit, "Rejuvenation", 11) or self:HoTActive(unit, "Regrowth", 18)) then
        self:CastOn("Swiftmend", unit); return
    end

    -- AoE: Wild Growth when several are hurt (Turtle addition, if learned).
    if cfg.useWildGrowth and self:KnowsSpell("Wild Growth") and self:OwnCDReady("Wild Growth")
        and self:HurtCount(ratio) >= (cfg.wildGrowthCount or 4) then
        self:CastOn("Wild Growth", unit); return
    end

    -- Burst: Regrowth (direct + HoT) on a big deficit if it has no Regrowth yet.
    if cfg.useRegrowth ~= false and self:KnowsSpell("Regrowth")
        and pct <= (cfg.regrowthPct or 55) / 100 and not self:HoTActive(unit, "Regrowth", 18) then
        local rg, amt = self:PickRank("Regrowth", rgEff, self.RG_MANA, deficit, mana)
        if rg then self:CommitHeal(unit, amt, 2.0); self:NoteHoT(unit, "Regrowth"); self:CastOn(rg, unit); return end
    end

    -- Maintenance: keep Rejuvenation rolling (max affordable rank).
    if cfg.useRejuv ~= false and self:KnowsSpell("Rejuvenation") and not self:HoTActive(unit, "Rejuvenation", 11) then
        local rj = self:MaxAffordableRank("Rejuvenation", self.RJ_MANA, mana)
        if rj then self:NoteHoT(unit, "Rejuvenation"); self:CastOn(rj, unit); return end
    end

    -- Lifebloom: rolling stack (Turtle addition, if learned).
    if cfg.useLifebloom and self:KnowsSpell("Lifebloom") and not self:HoTActive(unit, "Lifebloom", 6) then
        self:NoteHoT(unit, "Lifebloom"); self:CastOn("Lifebloom", unit); return
    end

    -- Fill: downranked Healing Touch sized to the deficit.
    local ht, amt = self:PickRank("Healing Touch", htEff, self.HT_MANA, deficit, mana)
    if ht then self:CommitHeal(unit, amt, 2.5); self:CastOn(ht, unit); return end
end

function M:Rotate(cfg)
    if cfg.form == "tree" then self:RotateResto(cfg); return end
    self:UpdateDefense(cfg)
    local form = self:CurrentForm()
    local inBear = (form == "Bear Form" or form == "Dire Bear Form")

    -- Defensive override: force Bear while HP is recovering. Form-to-form
    -- shifts are direct in 1.12 (one cast), so Cat/Moonkin go straight in.
    if self.hpDefenseActive then
        if not inBear then
            local b = self:BearFormSpell()
            if self.trace then self:Trace("DEFENSE: hp " .. string.format("%.0f", self:PlayerHPPct()) .. "%, shifting to " .. b) end
            self:CastSafe(b)
            return
        end
        -- turtled up: Frenzied Regeneration converts rage to health
        if self:KnowsSpell("Frenzied Regeneration") and self:OwnCDReady("Frenzied Regeneration") then
            if self:CastSafe("Frenzied Regeneration") then return end
        end
        self:RotateBear(cfg)
        return
    end

    if form == "Cat Form" then
        self:RotateCat(cfg)
    elseif inBear then
        self:RotateBear(cfg)
    elseif form == "Moonkin Form" then
        self:RotateCaster(cfg)
    else
        if cfg.form == "caster" then
            if self:KnowsSpell("Moonkin Form") then
                if self.trace then self:Trace("entering Moonkin Form") end
                self:CastSafe("Moonkin Form")
                return
            end
            self:RotateCaster(cfg)
            return
        end
        local want = self:PreferredFormSpell(cfg)
        if want then
            if self.trace then self:Trace("caster form, shifting into " .. want) end
            self:CastSafe(want)
        else
            -- no combat form learned yet: the caster loop carries level 1+
            self:RotateCaster(cfg)
        end
    end
end

-- ============================================================
-- Class specific slash subcommands, dispatched from the core
-- ============================================================
function M:HandleCommand(cmd, t)
    if cmd == "aoe" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return true end
        cfg.aoeSwipe = not cfg.aoeSwipe
        msgOut("Swipe " .. (cfg.aoeSwipe and "on (AoE)" or "off") .. ".")
        return true
    end
    if cmd == "weave" then
        local cfg = Aegis_SBR:GetActiveProfile()
        if not cfg then msgOut("no profile active.", 1, 0.5, 0.3); return true end
        local a = string.lower(t[2] or "")
        if a == "on" then cfg.weaveDamage = true
        elseif a == "off" then cfg.weaveDamage = false
        else cfg.weaveDamage = not cfg.weaveDamage end
        msgOut("resto damage weave " .. (cfg.weaveDamage and "on" or "off") .. " (DPS only when nobody needs healing).")
        return true
    end
    if cmd == "style" then
        local cfg = Aegis_SBR:GetActiveProfile()
        local style = self.styleAlias[string.lower(t[2] or "")]
        if cfg and style then
            cfg.catStyle = style
            msgOut("cat style = " .. (style == "bleed" and "Claw & Bleed" or "Shred & Powershift") .. ".")
        else
            msgOut("usage: /sbr style <bleed|shred>", 1, 0.5, 0.3)
        end
        return true
    end
    if cmd == "form" then
        local cfg = Aegis_SBR:GetActiveProfile()
        local form = self.formAlias[string.lower(t[2] or "")]
        if cfg and form then
            cfg.form = form
            msgOut("preferred form = " .. form .. ".")
        else
            msgOut("usage: /sbr form <cat|bear|caster|resto>", 1, 0.5, 0.3)
        end
        return true
    end
    return false
end
