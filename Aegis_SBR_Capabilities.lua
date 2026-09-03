-- ============================================================
-- Aegis_SBR - ClassicAPI capability layer
-- ============================================================
-- ClassicAPI is a DLL (brues-code/ClassicAPI) that backports parts of the
-- modern Blizzard API onto the 1.12 client. It is RECOMMENDED, never required:
-- every player without it must keep exactly today's behaviour, so nothing in
-- this file may be a hard dependency of anything.
--
-- The contract every helper here follows:
--
--   * A helper returns nil when ClassicAPI is absent OR when it is present but
--     has no answer. nil means "UNKNOWN", never "zero" and never "no".
--   * Callers must treat unknown the way the engine already treats an
--     unreadable spell cost or an unconfident DoT estimate: as "not a reason to
--     hold back", falling through to the existing blind-timer path.
--   * No helper here casts, and none of them is called from the rotation yet.
--     Wiring a helper into a gate changes WHEN an ability fires and is a
--     rotation change - see CLAUDE.md Critical Rule #1.
--
-- Probing is per FUNCTION, not just per DLL: ClassicAPI versions differ, and a
-- present namespace with a missing member would otherwise error mid-combat.
-- ============================================================

-- Detected once, then read from here. Kept private so nothing can flip a flag
-- from outside and fake a capability the client does not actually have.
local caps = {
    present  = false,   -- DLL loaded at all
    version  = nil,     -- CLASSIC_API_VERSION integer
    auras    = false,   -- C_UnitAuras: hostile debuff timers + caster
    range    = false,   -- C_Spell.IsSpellInRange: true geometric range
    cooldown = false,   -- C_Spell.GetSpellCooldown by spell id
    totems   = false,   -- GetTotemInfo + PLAYER_TOTEM_UPDATE
    creature = false,   -- UnitCreatureID: the creature-template id behind a unit
    loc      = false,   -- C_LossOfControl: stun / silence / school lockout
    timer    = false,   -- C_Timer.After
    encoding = false,   -- C_EncodingUtil: profile import/export (roadmap P3)
}

local detected = false

-- ============================================================
-- Detection
-- ============================================================
-- CLASSIC_API_VERSION is set by the DLL itself and is an integer, so it is both
-- the presence probe and the basis of any future ">= N" gate. Each capability
-- is then confirmed by touching the exact function we intend to call.
function Aegis_SBR:DetectClassicAPI()
    caps.version = CLASSIC_API_VERSION
    caps.present = (CLASSIC_API_VERSION ~= nil)

    if caps.present then
        caps.auras = (C_UnitAuras and C_UnitAuras.GetUnitAuras
                      and C_UnitAuras.GetAuraDataByIndex) and true or false
        caps.range    = (C_Spell and C_Spell.IsSpellInRange) and true or false
        caps.cooldown = (C_Spell and C_Spell.GetSpellCooldown) and true or false
        caps.totems   = (GetTotemInfo ~= nil)
        caps.creature = (UnitCreatureID ~= nil)
        caps.loc      = (C_LossOfControl
                         and C_LossOfControl.GetActiveLossOfControlDataCount
                         and C_LossOfControl.GetActiveLossOfControlData) and true or false
        caps.timer    = (C_Timer and C_Timer.After) and true or false
        caps.encoding = (C_EncodingUtil and C_EncodingUtil.SerializeJSON
                         and C_EncodingUtil.DeserializeJSON) and true or false
    end

    detected = true
    return caps.present
end

local function ensure()
    if not detected then Aegis_SBR:DetectClassicAPI() end
end

function Aegis_SBR:HasClassicAPI()
    ensure()
    return caps.present
end

function Aegis_SBR:ClassicAPIVersion()
    ensure()
    return caps.version
end

-- Per-feature probe. Modules gate on this rather than on HasClassicAPI, so an
-- older DLL that lacks one function still gets every other capability.
function Aegis_SBR:Capability(key)
    ensure()
    return caps[key] and true or false
end

-- ============================================================
-- Target aura timing and ownership
-- ============================================================
-- This is the capability 1.12 has no answer for at all. The existing
-- SnapshotTargetDebuffs stays exactly as it is - it answers "is it up" and
-- "how many stacks", which already works through SuperWoW - and this is a
-- SEPARATE snapshot carrying the two things it cannot know: how long the
-- debuff has left, and whether it is ours.
--
-- Kept separate on purpose. Folding the ClassicAPI data into the existing
-- snapshot would change what "up" means the moment a caster filter is applied
-- (another warlock's Corruption would stop counting), and that is a rotation
-- change hiding inside a refactor.
--
-- Keyed by GetTime() like the other per-press snapshots, so it can never be
-- read stale within a frame.
local function playerGUID()
    -- Resolved lazily, never cached as nil: at file load time the player unit
    -- does not exist yet.
    if not Aegis_SBR.capiPlayerGUID then
        local _, g = UnitExists("player")
        if g then Aegis_SBR.capiPlayerGUID = g end
    end
    return Aegis_SBR.capiPlayerGUID
end

function Aegis_SBR:SnapshotTargetAuras()
    if not self:Capability("auras") then return end
    local byName = {}
    if UnitExists("target") then
        local mine = playerGUID()
        local list = C_UnitAuras.GetUnitAuras("target", "HARMFUL")
        if list then
            for i = 1, table.getn(list) do
                local a = list[i]
                if a and a.name and a.name ~= "" and not byName[a.name] then
                    local remain
                    -- expirationTime is 0 when the cast was never observed
                    -- (aura predates login, cache evicted). That is UNKNOWN.
                    if a.expirationTime and a.expirationTime > 0 then
                        remain = a.expirationTime - GetTime()
                        if remain < 0 then remain = 0 end
                    end
                    local own
                    if a.sourceUnit == "player" then own = true
                    elseif a.sourceGUID and mine then own = (a.sourceGUID == mine)
                    elseif a.sourceUnit then own = false end
                    byName[a.name] = {
                        remain  = remain,
                        mine    = own,
                        stacks  = a.applications,
                        spellId = a.spellId,
                        dur     = a.duration,
                    }
                end
            end
        end
    end
    Aegis_SBR.capiAuraSnap  = byName
    Aegis_SBR.capiAuraSnapT = GetTime()
end

local function auraEntry(name)
    if not Aegis_SBR:Capability("auras") then return nil end
    if not (Aegis_SBR.capiAuraSnap and Aegis_SBR.capiAuraSnapT == GetTime()) then
        Aegis_SBR:SnapshotTargetAuras()
    end
    local snap = Aegis_SBR.capiAuraSnap
    return snap and snap[name]
end

-- Seconds left on a debuff on the current target, or nil when unknown.
-- nil covers: no ClassicAPI, no target, debuff absent, and - importantly - the
-- debuff being present but with no observed cast to time it from. Callers must
-- fall back to their existing blind interval on nil, never to 0.
function Aegis_SBR:TargetDebuffRemaining(name)
    local e = auraEntry(name)
    if not e then return nil end
    return e.remain
end

-- true / false / nil. nil is "cannot tell", which is NOT the same as false:
-- an aura applied before login has no caster recorded.
function Aegis_SBR:TargetDebuffMine(name)
    local e = auraEntry(name)
    if not e then return nil end
    return e.mine
end

-- Full applied duration (talent- and combo-point-modified where ClassicAPI saw
-- the cast). Useful for "is this worth refreshing yet" pandemic maths.
function Aegis_SBR:TargetDebuffDuration(name)
    local e = auraEntry(name)
    if not e then return nil end
    return e.dur
end

-- ============================================================
-- Spell range
-- ============================================================
-- Verified 2026-08-18: this honours MINIMUM range too, which
-- CheckInteractDistance structurally cannot - the proxy is monotonic, a real
-- spell range is a band. See docs/research-classicapi.md section 4.
--
-- Returns true / false / nil. nil means: no ClassicAPI, no such unit, or a
-- rangeless spell (self buff) - the same "does not apply" the API itself uses.
function Aegis_SBR:SpellInRange(spell, unit)
    if not self:Capability("range") then return nil end
    if not spell or spell == "" then return nil end
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
    if not ok then return nil end
    return r
end

-- ============================================================
-- Totems
-- ============================================================
-- Returns name, secondsRemaining for a slot (1 Fire, 2 Earth, 3 Water, 4 Air),
-- or nil when there is no totem in that slot / no ClassicAPI.
--
-- Note the API quirk deliberately not exposed here: GetTotemInfo's first return
-- means "you carry the totem TOOL item", not "a totem is out". The active test
-- is a non-empty name, which is what this wrapper does, so callers cannot get
-- it wrong.
function Aegis_SBR:TotemSlot(slot)
    if not self:Capability("totems") then return nil end
    local _, name, start, dur = GetTotemInfo(slot)
    if not name or name == "" then return nil end
    local remain
    if start and dur and dur > 0 then
        remain = (start + dur) - GetTime()
        if remain < 0 then remain = 0 end
    end
    return name, remain
end

-- Seconds left on a named totem, or nil if it is not out anywhere.
function Aegis_SBR:TotemRemaining(name)
    if not self:Capability("totems") then return nil end
    for slot = 1, 4 do
        local n, remain = self:TotemSlot(slot)
        if n == name then return remain end
    end
    return nil
end

-- ============================================================
-- Creature identity
-- ============================================================
-- The creature-TEMPLATE id: every Kobold Geomancer in the world shares one, and
-- it is stable across sessions. That is the difference between learning
-- something about the mob in front of you and learning it about the KIND of mob
-- - a lesson worth keeping is worth keeping past this one corpse.
--
-- Vanilla packs the entry id into bits 24-47 of a creature GUID, so this is a
-- read, not a cache lookup. nil for players (a player GUID carries no template),
-- for an empty token, and when ClassicAPI is absent.
function Aegis_SBR:UnitCreatureID(unit)
    if not self:Capability("creature") then return nil end
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    -- pcall'd: a garbage token raises, and this is called from rotation gates
    -- where an error would take the whole press down.
    local ok, id = pcall(UnitCreatureID, unit)
    if ok and type(id) == "number" and id > 0 then return id end
    return nil
end

-- ============================================================
-- Loss of control
-- ============================================================
-- Returns seconds remaining for the first active effect of locType, or nil.
-- locType: "STUN" / "FEAR" / "ROOT" / "SILENCE" / "PACIFY" / "PACIFYSILENCE" /
-- "CONFUSE" / "CHARM" / "POSSESS" / "DISARM" / "SCHOOL_INTERRUPT".
-- Pass nil to ask "is ANY effect active".
--
-- timeRemaining is nullable in the modern contract and ClassicAPI honours that:
-- CC whose applying cast was not observed reports the type but no timing. So a
-- return of 0 with a true second value means "active, duration unknown".
function Aegis_SBR:LossOfControl(locType)
    if not self:Capability("loc") then return nil end
    local n = C_LossOfControl.GetActiveLossOfControlDataCount()
    if not n or n == 0 then return nil end
    for i = 1, n do
        local d = C_LossOfControl.GetActiveLossOfControlData(i)
        if d and (not locType or d.locType == locType) then
            return (d.timeRemaining or 0), true
        end
    end
    return nil
end

-- ============================================================
-- Deferred callbacks
-- ============================================================
-- Bookkeeping only. The rotation is deliberately synchronous and press-driven;
-- a deferred callback that CASTS would fire outside a press and is a new class
-- of bug. Returns true if the callback was scheduled.
function Aegis_SBR:After(delay, fn)
    if not self:Capability("timer") then return false end
    if type(fn) ~= "function" then return false end
    C_Timer.After(delay, fn)
    return true
end

-- ============================================================
-- Status reporting
-- ============================================================
-- Ordered for the report; pairs() has no defined order and a status list that
-- reshuffles between logins is needlessly hard to read.
local CAP_ORDER = {
    { "auras",    "target debuff timers + caster" },
    { "range",    "exact spell range (incl. min range)" },
    { "cooldown", "spell cooldown by id" },
    { "totems",   "totem tracking + destruction" },
    { "creature", "creature-template id (per mob type, not per mob)" },
    { "loc",      "stun / silence / school lockout" },
    { "timer",    "deferred callbacks" },
    { "encoding", "profile import/export" },
}

-- One short line for the login banner.
function Aegis_SBR:ClassicAPIBannerLine()
    ensure()
    if not caps.present then
        return "ClassicAPI not detected - running the built-in fallbacks."
    end
    local n = 0
    for i = 1, table.getn(CAP_ORDER) do
        if caps[CAP_ORDER[i][1]] then n = n + 1 end
    end
    return "ClassicAPI v" .. tostring(caps.version) .. " detected - "
        .. n .. "/" .. table.getn(CAP_ORDER) .. " capabilities available (/sbr capi)."
end

-- Full report behind /sbr capi.
function Aegis_SBR:CmdClassicAPI()
    ensure()
    if not caps.present then
        self:Msg("ClassicAPI: NOT installed.", 1, 0.6, 0.3)
        self:Msg("Everything runs on the built-in fallbacks - nothing is degraded, "
            .. "but enemy debuff timers, exact range and totem tracking stay unavailable.", 0.8, 0.8, 0.8)
        return
    end
    self:Msg("ClassicAPI v" .. tostring(caps.version) .. " active.", 0.4, 1, 0.4)
    for i = 1, table.getn(CAP_ORDER) do
        local key, label = CAP_ORDER[i][1], CAP_ORDER[i][2]
        local on = caps[key]
        DEFAULT_CHAT_FRAME:AddMessage(
            (on and "  |cff44ff44on |r " or "  |cffff8844off|r ") .. label,
            0.8, 0.8, 0.8)
    end
    -- Live proof rather than a claim: show what the target actually reports.
    if caps.auras and UnitExists("target") then
        self:SnapshotTargetAuras()
        local snap = Aegis_SBR.capiAuraSnap
        local any = false
        for name, e in pairs(snap or {}) do
            any = true
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s  rest=%s  mine=%s  stacks=%s",
                name,
                e.remain and string.format("%.1fs", e.remain) or "?",
                tostring(e.mine), tostring(e.stacks)), 0.7, 0.85, 1)
        end
        if not any then
            DEFAULT_CHAT_FRAME:AddMessage("  target has no debuffs", 0.6, 0.6, 0.6)
        end
    end
end

-- ============================================================
-- Passive probe log (AegisProbe)
-- ============================================================
-- Verifying a ClassicAPI claim by hand means standing still and running slash
-- commands, which is not possible while grouped - the rest of the party does not
-- wait. So the measurements collect themselves while playing and are read off
-- disk afterwards.
--
-- Same constraint as the press log: the 1.12 sandbox has no file access, so the
-- only way out is a SavedVariable, serialised to
--   WTF\Account\<ACCOUNT>\<Realm>\<Char>\SavedVariables\Aegis_SBR.lua
-- on /reload or logout. Nothing is on disk until one of those happens.
--
-- Its OWN SavedVariable, deliberately: probe data is throwaway diagnostics and
-- must never bloat AegisDB (profiles) or crowd out the press log.
--
-- OFF by default; enabled per character with /sbr probe on.
--
-- Categories are separate ring buffers so a chatty one cannot starve the rest -
-- range flips fire far more often than finisher casts, and a shared buffer would
-- push the rare, valuable entries out first.
-- ============================================================
local PROBE_MAX = 300

-- Diagnostic only - nothing in the rotation reads these. A melee ability per
-- class for the range sampler; casters have none and are simply not sampled.
local PROBE_MELEE = {
    WARRIOR = { "Heroic Strike", "Rend" },
    ROGUE   = { "Sinister Strike", "Backstab" },
    HUNTER  = { "Raptor Strike" },
    DRUID   = { "Maul", "Claw", "Shred" },
    SHAMAN  = { "Stormstrike" },
    PALADIN = { "Crusader Strike" },
}

-- Finishers whose real duration scales with combo points - the case 1.12 never
-- transmits and ClassicAPI claims to reconstruct.
local PROBE_FINISHER = {
    ["Rupture"]        = "target",
    ["Kidney Shot"]    = "target",
    ["Slice and Dice"] = "player",
    ["Rip"]            = "target",
}

-- Maintained DoTs, per class. Added after a Warlock capture came back completely
-- empty: the first version of this probe was built around the rogue/hunter/shaman
-- questions and had no instrument at all for the class whose workaround
-- (Class_Warlock's DotRemaining bookkeeping) ClassicAPI is supposed to replace.
--
-- What this answers is COVERAGE, not correctness: how often a freshly applied DoT
-- comes back with a real expiry rather than nil or the bare Spell.dbc base. A
-- reading equal to the base is the documented cache-miss signature (the
-- SMSG_SPELL_GO packet was not observed), and a workaround can only be retired if
-- misses are rare.
local PROBE_DOT = {
    WARLOCK = { "Corruption", "Immolate", "Curse of Agony", "Siphon Life", "Curse of Doom" },
    SHAMAN  = { "Flame Shock" },
    HUNTER  = { "Serpent Sting", "Scorpid Sting", "Viper Sting" },
    PRIEST  = { "Shadow Word: Pain", "Devouring Plague" },
    DRUID   = { "Moonfire", "Rake", "Insect Swarm" },
    WARRIOR = { "Rend" },
    ROGUE   = { "Garrote" },
    MAGE    = { "Pyroblast" },
}

-- name -> true for this character's class, built once.
local probeDots

local function probeDotSet()
    if probeDots then return probeDots end
    probeDots = {}
    local _, cls = UnitClass("player")
    local list = PROBE_DOT[cls]
    if list then
        for i = 1, table.getn(list) do probeDots[list[i]] = true end
    end
    return probeDots
end

function Aegis_SBR:ProbeInit(reset)
    if type(AegisProbe) ~= "table" then AegisProbe = {} end
    local P = AegisProbe
    if reset or type(P.cat) ~= "table" then
        P.cat = {}
        P.started = date and date("%Y-%m-%d %H:%M:%S") or ""
        P.t0 = GetTime()
        P.capi = self:ClassicAPIVersion()
        local _, cls = UnitClass("player")
        P.class = cls
        P.player = UnitName("player")
    end
    if not P.t0 then P.t0 = GetTime() end
    return P
end

function Aegis_SBR:ProbeEnabled()
    return (type(AegisProbe) == "table") and AegisProbe.enabled and true or false
end

-- Append one line to a category's ring. Wrap-by-index like the press log:
-- table.remove(t, 1) would shift every entry on every write.
function Aegis_SBR:ProbeWrite(cat, text)
    if not self:ProbeEnabled() or not text then return end
    local P = self:ProbeInit()
    if type(P.cat[cat]) ~= "table" then P.cat[cat] = { pos = 0, e = {} } end
    local C = P.cat[cat]
    C.pos = C.pos + 1
    local slot = math.mod(C.pos - 1, PROBE_MAX) + 1
    C.e[slot] = string.format("%.2f|%s", GetTime() - (P.t0 or 0), text)
end

-- A ranged fallback so casters contribute range data too. Without it a warlock or
-- mage recorded nothing at all, because PROBE_MELEE has no entry for them - which
-- is exactly how the first Warlock capture came back empty.
local PROBE_RANGED = {
    WARLOCK = { "Shadow Bolt", "Corruption" },
    MAGE    = { "Frostbolt", "Fireball" },
    PRIEST  = { "Smite", "Mind Blast" },
    DRUID   = { "Wrath", "Moonfire" },
    SHAMAN  = { "Lightning Bolt" },
    HUNTER  = { "Auto Shot" },
    PALADIN = { "Holy Light" },
}

function Aegis_SBR:ProbeMeleeSpell()
    if self.probeMelee ~= nil then
        if self.probeMelee == false then return nil end
        return self.probeMelee
    end
    local _, cls = UnitClass("player")
    local list = PROBE_MELEE[cls]
    if list then
        for i = 1, table.getn(list) do
            if self:KnowsSpell(list[i]) then
                self.probeMelee = list[i]
                return self.probeMelee
            end
        end
    end
    -- No melee ability: fall back to a ranged one. The flips then mark the outer
    -- edge instead of the melee edge, which is still a real measurement - just of
    -- a different boundary, and the logged spell name says which.
    list = PROBE_RANGED[cls]
    if list then
        for i = 1, table.getn(list) do
            if self:KnowsSpell(list[i]) then
                self.probeMelee = list[i]
                return self.probeMelee
            end
        end
    end
    self.probeMelee = false
    return nil
end

-- Centre-to-centre distance to the target in yards, or nil. UnitPosition is
-- SuperWoW's (Required); the third return is treated as optional because
-- ClassicAPI defines a same-named global and load order decides which is live.
-- Returns distance, source. The SOURCE is logged because the 2026-08-18 BRS
-- capture showed UnitPosition resolving only for PLAYERS - every NPC target came
-- back nil - and a bare "?" could not distinguish "no API" from "API said no".
local function probeDistance()
    if not UnitExists("target") then return nil end
    -- Same priority as Aegis_SBR_Range:Distance, and for the same reason: UnitXP
    -- is Required and resolves NPCs, UnitPosition only resolves players.
    if UnitXP then
        local ok, d = pcall(UnitXP, "distanceBetween", "player", "target")
        if ok and type(d) == "number" and d >= 0 then return d, "xp" end
    end
    if UnitDistanceSquared then
        local ok, d = pcall(UnitDistanceSquared, "target")
        if ok and type(d) == "number" and d >= 0 then return math.sqrt(d), "sq" end
    end
    if UnitPosition then
        local x1, y1, z1 = UnitPosition("player")
        local x2, y2, z2 = UnitPosition("target")
        if x1 and x2 then
            local dx, dy = x2 - x1, y2 - y1
            local dz = ((z1 and z2) and (z2 - z1)) or 0
            return math.sqrt(dx * dx + dy * dy + dz * dz), "pos"
        end
    end
    return nil, "none"
end

-- Sampler. Records ONLY transitions, so standing still costs just the compare.
-- Mob name and classification go into the line because target SIZE is the
-- variable that makes a geometric range check differ from the flat proxy, and
-- there is no API for a bounding radius - the name is how it gets classified
-- when the log is read back.
function Aegis_SBR:ProbeTick()
    if not self:ProbeEnabled() then return end
    local now = GetTime()
    if (now - (self.probeT or 0)) < 0.2 then return end
    self.probeT = now

    if not UnitExists("target") or UnitIsDead("target") then
        self.probeLastRange = nil
        return
    end

    local spell = self:ProbeMeleeSpell()
    if spell and self:Capability("range") then
        local v = self:SpellInRange(spell, "target")
        if v ~= nil then
            if self.probeLastRange ~= nil and v ~= self.probeLastRange then
                local d, src = probeDistance()
                self:ProbeWrite("range", string.format(
                    "%s inRange=%s proxy=%s dist=%s/%s mob=%s cls=%s lvl=%s",
                    spell, tostring(v),
                    tostring(CheckInteractDistance("target", 3) and true or false),
                    d and string.format("%.1f", d) or "?", tostring(src),
                    tostring(UnitName("target")),
                    tostring(UnitClassification("target")),
                    tostring(UnitLevel("target"))))
            end
            self.probeLastRange = v
        end
    end

    -- Detection disagreement: ClassicAPI seeing a debuff the old path cannot
    -- read. That is the exact fault behind the 2026-08-18 Hunter regression, so
    -- logging it turns the next such case into evidence instead of a guess.
    if self:Capability("auras") then
        self:SnapshotTargetAuras()
        local snap = self.capiAuraSnap
        if snap then
            for name, e in pairs(snap) do
                if not self:TargetDebuffUp(name, nil) then
                    local key = name .. "|" .. tostring(UnitName("target"))
                    if self.probeSeen ~= key then
                        self.probeSeen = key
                        self:ProbeWrite("mismatch", string.format(
                            "capi-only debuff %s rest=%s mine=%s mob=%s",
                            name,
                            e.remain and string.format("%.1f", e.remain) or "?",
                            tostring(e.mine), tostring(UnitName("target"))))
                    end
                end
            end
        end
    end
end

-- Combo points are already spent by the time a finisher's cast registers, so
-- the last non-zero reading is carried forward. Sampled from the rotation press,
-- which is exactly when the points are still in hand.
function Aegis_SBR:ProbeNoteCombo()
    if not self:ProbeEnabled() then return end
    local cp = GetComboPoints and GetComboPoints() or 0
    if cp and cp > 0 then self.probeCP = cp end
end

-- Finisher landed: read back the duration the server actually granted.
-- Deferred, because the aura is not on the target in the same frame as the cast
-- packet. Uses ClassicAPI's timer - without ClassicAPI there is no duration to
-- read anyway, so the gate costs nothing.
function Aegis_SBR:ProbeOnCast(spellName)
    if not self:ProbeEnabled() or not spellName then return end
    if not self:Capability("timer") then return end

    local where = PROBE_FINISHER[spellName]
    if where then
        local cp = self.probeCP or 0
        self:After(0.6, function()
            local dur, remain
            if where == "player" then
                dur = Aegis_SBR:BuffTime(spellName)
                remain = dur
            else
                dur = Aegis_SBR:TargetDebuffDuration(spellName)
                remain = Aegis_SBR:TargetDebuffRemaining(spellName)
            end
            Aegis_SBR:ProbeWrite("finisher", string.format(
                "%s cp=%s dur=%s rest=%s",
                spellName, tostring(cp),
                dur and string.format("%.1f", dur) or "?",
                remain and string.format("%.1f", remain) or "?"))
        end)
        self.probeCP = 0
        return
    end

    -- Maintained DoT: read back what the capability layer knows 0.6s after the
    -- cast. `up` distinguishes the two ways a nil remaining can happen - the
    -- debuff genuinely not being there (a resist, a miss, a dead target) versus
    -- it being there with no observed cast to time it from. Only the second is a
    -- coverage problem.
    if probeDotSet()[spellName] then
        self:After(0.6, function()
            local dur    = Aegis_SBR:TargetDebuffDuration(spellName)
            local remain = Aegis_SBR:TargetDebuffRemaining(spellName)
            local mine   = Aegis_SBR:TargetDebuffMine(spellName)
            local up     = Aegis_SBR:TargetDebuffUp(spellName, nil)
            Aegis_SBR:ProbeWrite("dot", string.format(
                "%s dur=%s rest=%s mine=%s up=%s mob=%s",
                spellName,
                dur and string.format("%.1f", dur) or "?",
                remain and string.format("%.1f", remain) or "?",
                tostring(mine), tostring(up),
                tostring(UnitName("target"))))
        end)
    end
end

-- Totem slot change (ClassicAPI PLAYER_TOTEM_UPDATE). Drop, expiry and early
-- destruction all land here; which one it was follows from whether the slot is
-- occupied afterwards.
function Aegis_SBR:ProbeOnTotem(slot)
    if not self:ProbeEnabled() then return end
    local name, remain = self:TotemSlot(slot)
    self:ProbeWrite("totem", string.format("slot=%s %s rest=%s",
        tostring(slot), name or "(empty)",
        remain and string.format("%.1f", remain) or "-"))
end

function Aegis_SBR:CmdProbe(arg)
    arg = string.lower(arg or "")
    if arg == "on" then
        self:ProbeInit()
        AegisProbe.enabled = true
        self:Msg("probe log ON. Play normally; /reload or log out writes it to disk.", 0.4, 1, 0.4)
        if not self:HasClassicAPI() then
            self:Msg("note: without ClassicAPI nothing can be recorded.", 1, 0.7, 0.3)
        end
        return
    end
    if arg == "off" then
        if type(AegisProbe) == "table" then AegisProbe.enabled = false end
        self:Msg("probe log OFF (kept; /sbr probe clear discards it).")
        return
    end
    if arg == "clear" then
        self:ProbeInit(true)
        AegisProbe.enabled = true
        self:Msg("probe log cleared, still recording.")
        return
    end
    local P = (type(AegisProbe) == "table") and AegisProbe or nil
    if not P or type(P.cat) ~= "table" then
        self:Msg("probe log: never started. /sbr probe on")
        return
    end
    self:Msg("probe log " .. (P.enabled and "ON" or "OFF") .. ", started " .. tostring(P.started))
    local any = false
    for cat, C in pairs(P.cat) do
        any = true
        DEFAULT_CHAT_FRAME:AddMessage("  " .. cat .. ": " .. tostring(C.pos) .. " recorded", 0.8, 0.8, 0.8)
    end
    if not any then
        DEFAULT_CHAT_FRAME:AddMessage("  nothing recorded yet", 0.6, 0.6, 0.6)
    end
    DEFAULT_CHAT_FRAME:AddMessage("  /reload or log out to flush it to SavedVariables.", 0.6, 0.6, 0.6)
end

-- Drives ProbeTick. Its own frame so nothing depends on the rotation being
-- pressed - the sampler must run while walking, not only while attacking.
local probeFrame = CreateFrame("Frame")
probeFrame:SetScript("OnUpdate", function() Aegis_SBR:ProbeTick() end)
