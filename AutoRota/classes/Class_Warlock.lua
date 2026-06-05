-- ============================================================
-- Class_Warlock  -  warlock module for AutoRota
-- Turtle WoW 1.12 (SuperWoW). DoT priority, configurable.
-- ============================================================
-- Model (mirrors the proven leveling macro):
--  * Keep the enabled damage-over-time effects up in priority order,
--    Immolate, then the chosen Curse, then Corruption, then Siphon Life.
--  * Detection is by debuff texture on the target. A short per-effect
--    memory keyed by target GUID prevents re-queuing a cast-time DoT
--    while it is still landing.
--  * When every enabled DoT is up, fall back to the filler, either the
--    wand, Shadow Bolt or Drain Life.
--  * Optional Life Tap when mana is low and health is high.
--  * The pet is sent onto the target when enabled.
-- Cast-time spells are queued with QueueSpellByName when available, so
-- the rotation never clips the current cast.
-- ============================================================

local M = AutoRota:NewClassModule("WARLOCK")
M.uiTitle = "Warlock"
M.uiHeight = 470
M.meleeAutoAttack = false   -- caster, no white melee swing

local function msgOut(text, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: " .. text, r or 1, g or 0.8, b or 0.0)
end

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
    starter = {  -- matches the leveling macro, valid early
        useImmolate = true, curse = "Curse of Agony", useCorruption = true, useSiphonLife = false,
        filler = "Shoot", petAttack = true,
        lifeTap = false, lifeTapMana = 20, lifeTapHpMin = 40,
    },
    affliction = {
        useImmolate = false, curse = "Curse of Agony", useCorruption = true, useSiphonLife = true,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
    },
    destruction = {
        useImmolate = true, curse = "Curse of the Elements", useCorruption = false, useSiphonLife = false,
        filler = "Shadow Bolt", petAttack = true,
        lifeTap = true, lifeTapMana = 25, lifeTapHpMin = 40,
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
    return c
end

function M:AvailableCursesOf()
    local out = {}
    for i = 1, table.getn(self.CURSES) do
        if self:KnowsSpell(self.CURSES[i]) then table.insert(out, self.CURSES[i]) end
    end
    return out
end

function M:ProfileValidity(cfg)
    local missing = {}
    if cfg.useImmolate   and not self:KnowsSpell("Immolate")    then table.insert(missing, "Immolate")    end
    if cfg.useCorruption and not self:KnowsSpell("Corruption")  then table.insert(missing, "Corruption")  end
    if cfg.useSiphonLife and not self:KnowsSpell("Siphon Life") then table.insert(missing, "Siphon Life") end
    if cfg.curse ~= "" and not self:KnowsSpell(cfg.curse)       then table.insert(missing, cfg.curse)      end
    if cfg.filler ~= "Shoot" and not self:KnowsSpell(cfg.filler) then table.insert(missing, cfg.filler)    end
    if cfg.lifeTap and not self:KnowsSpell("Life Tap")          then table.insert(missing, "Life Tap")     end
    return (table.getn(missing) == 0), missing
end

-- Queue a known spell, preferring SuperWoW's cast queue so a cast in
-- progress is not clipped. Returns true if the spell is known.
function M:Queue(name)
    if not self:KnowsSpell(name) then return false end
    if QueueSpellByName then QueueSpellByName(name) else CastSpellByName(name) end
    return true
end

function M:TargetHasTexture(frag)
    if not frag or frag == "" then return false end
    for i = 1, 40 do
        local t = UnitDebuff("target", i)
        if t and string.find(t, frag) then return true end
    end
    return false
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
-- With a known texture, missing-but-recent counts as "wait" (let it land).
-- Without a texture, recent counts as "up" so the rotation moves on and
-- the effect is simply reapplied once the interval elapses.
function M:ApplyDot(spellName, texFrag, interval)
    interval = interval or 3
    if texFrag and self:TargetHasTexture(texFrag) then return "up" end
    local id = self:TargetId()
    local rec = self.dotThrottle[spellName]
    local now = GetTime()
    if rec and rec.id == id and rec.t and (now - rec.t) <= interval then
        if texFrag then return "wait" else return "up" end
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

    -- Build the ordered DoT list from the enabled, known effects.
    local order = {}
    if cfg.useImmolate then table.insert(order, { "Immolate", self.dotTex["Immolate"], 3 }) end
    if cfg.curse ~= "" then
        local tex = self:CurseTex(cfg.curse)
        table.insert(order, { cfg.curse, tex, tex and 3 or 20 })
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

    local filler = cfg.filler or "Shoot"
    if filler == "Shoot" then
        -- spammable wand, only start it if it is not already auto repeating
        for s = 1, 120 do if IsAutoRepeatAction(s) then return end end
        CastSpellByName("Shoot")
    else
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
