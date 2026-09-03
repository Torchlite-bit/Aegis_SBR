-- ============================================================
-- Aegis: Single Button Rotation (Aegis_SBR)  -  configurable
-- one-button rotation, multi class. Turtle WoW 1.12 (SuperWoW).
-- Formerly AutoRota.
-- ============================================================
-- The core holds everything that is not class specific. Each class
-- ships a module (Class_<Name>.lua) that registers itself here. On
-- login the player class is detected and the matching module becomes
-- active, providing its templates, profile rules, rotation and UI.
-- ============================================================
-- Run with a bare macro, spam it:   /sbr
-- Configure per character:          /sbr ui
-- Other commands: list, use <name>, off, new <name> [template],
--   del <name>, check, reset, debug, trace, capi, probe [on|off|clear],
--   range [reset|scale <n>], plus class commands.
-- /aegis is the long form; /ar stays as a legacy alias.
-- ============================================================

Aegis_SBR = {
    ver = "1.2.18",
    classes = {},     -- token -> module table
    active = nil,      -- the module for this character's class
    Loaded = false,
    lastMsg = 0,
}

-- A class module inherits every shared helper through __index, so inside
-- a module "self:Cast(...)" resolves to the core while "self.weaving" and
-- the like stay private to the module instance.
function Aegis_SBR:NewClassModule(token)
    local m = setmetatable({ classToken = token }, { __index = self })
    self.classes[token] = m
    return m
end

-- Shared chat output, inherited by every class module (so modules use
-- self:Msg(...) instead of redefining their own local printer).
function Aegis_SBR:Msg(text, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage("Aegis: " .. text, r or 1, g or 0.8, b or 0.0)
end

local function msgOut(text, r, g, b) Aegis_SBR:Msg(text, r, g, b) end

-- ============================================================
-- Shared rotation and utility helpers (class independent)
-- ============================================================

-- One pass over the spellbook builds a name -> slot index (last slot wins, so
-- the highest rank is kept, same as the old linear scan) plus a name -> max
-- rank table. Every later lookup is then a table read instead of a full scan.
-- The index is built lazily and dropped on SPELLS_CHANGED, so learning a spell
-- or a new rank triggers a rebuild on the next lookup.
function Aegis_SBR:BuildSpellIndex()
    local idx, ranks = {}, {}
    local i = 1
    while true do
        local n, rnk = GetSpellName(i, BOOKTYPE_SPELL)
        if not n then break end
        idx[n] = i
        local digits = string.gsub(rnk or "", "%D", "")
        local num = tonumber(digits) or 1
        if not ranks[n] or num > ranks[n] then ranks[n] = num end
        i = i + 1
    end
    Aegis_SBR.spellIndex = idx
    Aegis_SBR.spellRanks = ranks
end

function Aegis_SBR:InvalidateSpellIndex()
    Aegis_SBR.spellIndex = nil
    Aegis_SBR.spellRanks = nil
    Aegis_SBR.costCache  = nil   -- slots moved, and a talent may have changed a cost
    Aegis_SBR.radiusCache = nil
    Aegis_SBR.durCache   = nil   -- learning a rank changes the duration too
end

function Aegis_SBR:FindSpellSlot(name)
    if not Aegis_SBR.spellIndex then Aegis_SBR:BuildSpellIndex() end
    return Aegis_SBR.spellIndex[name]
end

-- Highest known rank number of a spell (0 if unknown). Used for downranking.
function Aegis_SBR:MaxRank(name)
    if not Aegis_SBR.spellRanks then Aegis_SBR:BuildSpellIndex() end
    return Aegis_SBR.spellRanks[name] or 0
end

function Aegis_SBR:KnowsSpell(name)
    return self:FindSpellSlot(name) ~= nil
end

-- ============================================================
-- Spell cost. Read from the spellbook tooltip rather than kept in a table:
-- talents change costs (Improved Sinister Strike, Improved Shred, ...), Turtle
-- rebalances them, and a hardcoded number that is wrong by 5 energy is worse
-- than no check at all - it would silently hold back an ability the character
-- can actually afford. The tooltip is what the client itself believes, so it is
-- right by construction on any server and at any talent build.
--
-- Cached per spell name and dropped with the spellbook index, which
-- SPELLS_CHANGED invalidates - and learning a rank or spending a talent point
-- fires exactly that.
--
-- Returns nil when the cost cannot be read (no tooltip line, unknown spell).
-- Callers must treat nil as "affordable": an unreadable cost may never be the
-- reason an ability does not fire.
-- ============================================================
local SCAN_TIP = "Aegis_SBR_ScanTip"
local scanTip

function Aegis_SBR:SpellCost(name)
    if not self.costCache then self.costCache = {} end
    local hit = self.costCache[name]
    if hit then return hit end
    local slot = self:FindSpellSlot(name)
    if not slot then return nil end          -- not cached: it may be learned later
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", SCAN_TIP, nil, "GameTooltipTemplate")
    end
    -- SetOwner is repeated before every read, not done once at creation: a
    -- tooltip that has been cleared or hidden in between can refuse to
    -- populate its lines without a live owner, and that failure is silent -
    -- it just reads back as "no cost".
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpell(slot, BOOKTYPE_SPELL)
    -- The cost sits on the left of the second line ("45 Energy"), but a spell
    -- without one puts something else there, so a few lines are checked. The
    -- pattern needs the WHOLE line to be a number and a single word, which is
    -- what keeps "30 yd range" and "6 sec cooldown" from being read as costs.
    local cost
    for i = 2, 4 do
        local fs = getglobal(SCAN_TIP .. "TextLeft" .. i)
        local txt = fs and fs:GetText()
        if txt then
            -- Four digit mana costs are printed with a thousands separator.
            txt = string.gsub(txt, ",", "")
            local _, _, num = string.find(txt, "^(%d+) %a+$")
            if num then cost = tonumber(num); break end
        end
    end
    -- Only SUCCESS is cached. A failed read is not necessarily a spell without
    -- a cost - it can equally be a tooltip that did not populate this once -
    -- and caching that would freeze the wrong answer in place until the next
    -- SPELLS_CHANGED, which is exactly the kind of intermittent, unreproducible
    -- behaviour that is worst to debug. Re-scanning costs one hidden tooltip.
    if cost then self.costCache[name] = cost end
    return cost
end

-- The radius a spell affects, in yards, or nil when the tooltip does not say.
--
-- Read rather than tabulated, for the same reason SpellCost is: a totem's reach
-- differs per totem and per rank (a Magma hits eight yards, an aura totem
-- twenty), and a guessed twenty would call a Magma "in range" from fifteen
-- yards away while it is hitting nothing at all.
--
-- The number lives in the description text, not in the range field on line two
-- - that one is how far you may CAST it, which for a totem is your own feet. So
-- the left-hand lines are scanned for the first "N yards"; scanning the left
-- side only is also what keeps the cast range on the right of line two out of
-- it. The same read is used elsewhere for totem radii, so the pattern is proven.
function Aegis_SBR:SpellRadius(name)
    if not self.radiusCache then self.radiusCache = {} end
    local hit = self.radiusCache[name]
    if hit then return hit end
    local slot = self:FindSpellSlot(name)
    if not slot then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", SCAN_TIP, nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpell(slot, BOOKTYPE_SPELL)
    local radius
    for i = 2, 8 do
        local fs = getglobal(SCAN_TIP .. "TextLeft" .. i)
        local txt = fs and fs:GetText()
        if txt then
            local _, _, n = string.find(txt, "(%d+)%.?%d* +ya?r?ds?")
            if n then radius = tonumber(n); break end
        end
    end
    -- Only successful reads are cached, same as SpellCost: a tooltip that
    -- failed to populate once must not freeze "no radius" in place.
    if radius then self.radiusCache[name] = radius end
    return radius
end

-- ============================================================
-- Spell duration, read from the tooltip for the same reason SpellCost and
-- SpellRadius are: it is RANK dependent, and a hardcoded number is wrong for
-- every rank but one.
--
-- The case that forced this: rank 1 Searing Totem lasts 30s, the shaman module's
-- TOTEM_REDROP table said 55 (the max-rank value). A levelling shaman's fire
-- totem was therefore missing for 25 seconds before Aegis considered re-dropping
-- it - which is exactly the "totem upkeep doesn't work" report that table's own
-- comment records. Turtle is also free to rebalance any of it.
--
-- Returns nil when no duration line can be read. Callers must keep their own
-- fallback; this is a correction, not a replacement.
-- ============================================================
function Aegis_SBR:SpellDuration(name)
    if not self.durCache then self.durCache = {} end
    local hit = self.durCache[name]
    if hit then return hit end
    local slot = self:FindSpellSlot(name)
    if not slot then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", SCAN_TIP, nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpell(slot, BOOKTYPE_SPELL)
    local secs
    -- "Lasts N sec" is the authoritative phrasing and is preferred outright.
    -- Only if it is absent do we fall back to the LAST "N sec" on the line,
    -- because a tick interval ("every 2 seconds") comes before the duration
    -- ("for 20 sec") and taking the first match would read the interval.
    for i = 2, 8 do
        local fs = getglobal(SCAN_TIP .. "TextLeft" .. i)
        local txt = fs and fs:GetText()
        if txt then
            local _, _, n = string.find(txt, "[Ll]asts%s+(%d+)%s*sec")
            if n then secs = tonumber(n); break end
        end
    end
    if not secs then
        for i = 2, 8 do
            local fs = getglobal(SCAN_TIP .. "TextLeft" .. i)
            local txt = fs and fs:GetText()
            if txt then
                local pos, last = 1, nil
                while true do
                    local s2, e2, n = string.find(txt, "(%d+)%s*sec", pos)
                    if not s2 then break end
                    last = tonumber(n); pos = e2 + 1
                end
                if last then secs = last end
            end
        end
    end
    -- Guard against a misread: anything outside a plausible spell duration is
    -- discarded rather than cached, so a bad parse degrades to "unknown".
    if secs and (secs < 3 or secs > 3600) then secs = nil end
    if secs then self.durCache[name] = secs end
    return secs
end

-- Can the player pay for this spell right now? UnitMana returns whichever
-- resource the class uses, so this is energy on a rogue, rage on a warrior and
-- mana everywhere else, with no per-class branch needed.
function Aegis_SBR:CanAfford(name)
    local cost = self:SpellCost(name)
    if not cost then return true end
    return (UnitMana("player") or 0) >= cost
end

-- ============================================================
-- Decide / Perform
--
-- A class module may split its rotation in two: Decide(cfg) works out what the
-- press should do and returns a PLAN without touching the game, and Perform
-- carries it out. Nothing else changes - Rotate stays the entry point and calls
-- both - but it lets anything else ask "what would happen if I pressed now?"
-- without a cast going out. That is what the upcoming-spell window uses.
--
-- A plan is:
--   spell   the one global-cooldown ability, or nil for a deliberate hold
--   extras  off-GCD casts to fire first, in order (Cold Blood, Adrenaline Rush)
--   queue   cast through the SuperWoW queue instead, for cast-time spells
--   reason  short human text, shown in the window
--
-- The rule that makes this worth doing: Decide must have NO side effects, so
-- calling it four times a second for a preview cannot disturb the rotation.
-- Timers stamped after a cast belong in Perform or in the caller, never in
-- Decide.
-- ============================================================
function Aegis_SBR:Perform(mod, plan)
    if not plan then return end
    -- Routed through the two-mode terminal operations, so a module that builds
    -- an explicit plan behaves the same under a preview as one that calls Pick
    -- directly in its body.
    if plan.extras then
        for i = 1, table.getn(plan.extras) do mod:PickExtra(plan.extras[i]) end
    end
    if not plan.spell then return end
    if plan.queue then mod:PickQueue(plan.spell, plan.reason)
    else mod:Pick(plan.spell, plan.reason) end
end

-- What the rotation would do right now, without doing it. nil when the active
-- class has not been converted yet, or when there is no profile.
-- ------------------------------------------------------------
-- One rotation body, two modes.
--
-- A module's priority list has to answer two questions: "do it" when the
-- button is pressed, and "what would you do" four times a second for the
-- preview window. Keeping two versions of a priority list would guarantee they
-- drift apart, and rewriting each list into one that returns a plan means
-- touching every branch of every class - which is exactly where a rotation
-- gets changed by accident.
--
-- So the SAME body runs in both modes and only the terminal operations differ:
--
--   Pick / PickQueue  the one global-cooldown ability. Casts, or records.
--   PickExtra         an off-GCD cast that does not end the press.
--   Later(fn)         a state change - a timer stamp, an expiry reset. Runs on
--                     a real press only; a preview must never mutate anything.
--
-- Pick returns exactly what Cast returned before it (false when the spell is
-- not known), so control flow through a priority list is untouched.
--
-- The flags live on Aegis_SBR itself, never on the module: modules inherit
-- from it, so a module reading self.deciding finds the core's value, and there
-- is only ever one mode in play.
-- ------------------------------------------------------------
function Aegis_SBR:Pick(name, reason)
    if not name or not self:KnowsSpell(name) then return false end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name
        p.reason = reason
        return true
    end
    -- Counts real presses. The preview window uses it to know when the answer
    -- has legitimately changed, instead of redrawing on every sub-second wobble.
    Aegis_SBR.pressSeq = (Aegis_SBR.pressSeq or 0) + 1
    Aegis_SBR:NoteSpellCast(name)
    CastSpellByName(name)
    return true
end

function Aegis_SBR:PickQueue(name, reason)
    if not name or not self:KnowsSpell(name) then return false end
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = name
        p.reason = reason
        p.queue = true
        return true
    end
    -- Counts real presses. The preview window uses it to know when the answer
    -- has legitimately changed, instead of redrawing on every sub-second wobble.
    Aegis_SBR.pressSeq = (Aegis_SBR.pressSeq or 0) + 1
    Aegis_SBR:NoteSpellCast(name)
    if QueueSpellByName then QueueSpellByName(name) else CastSpellByName(name) end
    return true
end

function Aegis_SBR:PickExtra(name)
    if not name or not self:KnowsSpell(name) then return false end
    if Aegis_SBR.deciding then
        table.insert(Aegis_SBR.decidePlan.extras, name)
        return true
    end
    -- Recorded like Pick does. This is a real cast that the client can refuse,
    -- and leaving it unrecorded meant its refusal was blamed on whatever spell
    -- came before it - the same misattribution auto-attack caused.
    Aegis_SBR:NoteSpellCast(name)
    CastSpellByName(name)
    return true
end

function Aegis_SBR:Later(fn)
    if Aegis_SBR.deciding then return end
    fn()
end

-- What the rotation would do right now, without doing it. nil when the class
-- has not been converted, when there is no profile, or when the run failed -
-- a preview that errors must never leave the mode flag set, or the next real
-- press would record instead of cast.
function Aegis_SBR:Preview()
    local mod = self.active
    if not mod or not mod.previewReady then return nil end
    local cfg = self:GetActiveProfile()
    if not cfg then return nil end
    -- The same preparation a real press does. Without it the preview reads
    -- stale buff and debuff data and takes different branches than the press
    -- it is supposed to be predicting - which shows up as the window flicking
    -- between abilities. Both snapshots are pure caches of the current game
    -- state, so refreshing them here costs nothing and changes nothing.
    self:SnapshotBuffs()
    self:SnapshotTargetDebuffs()
    Aegis_SBR.decidePlan = { extras = {} }
    Aegis_SBR.deciding = true
    local ok = pcall(function() mod:Rotate(cfg) end)
    Aegis_SBR.deciding = false
    local plan = Aegis_SBR.decidePlan
    Aegis_SBR.decidePlan = nil
    if not ok then return nil end
    return plan
end

function Aegis_SBR:Cast(name)
    if self:KnowsSpell(name) then CastSpellByName(name); return true end
    return false
end

function Aegis_SBR:IsReady(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return false end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 then return true end
    return (start + dur - GetTime()) <= 0
end

-- Human readable cooldown state for tracing
function Aegis_SBR:CDInfo(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return "unknown" end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 then return "ready" end
    local rem = start + dur - GetTime()
    if dur <= 1.55 then return string.format("gcd %.1fs", rem) end   -- only the global cooldown
    return string.format("cd %.1fs", rem)
end

-- Seconds left on a spell's OWN cooldown, 0 when it is ready. The global
-- cooldown is not a wait for a specific spell, so it reports 0 like OwnCDReady
-- treats it as ready - a plan that has to add up several waits must not count
-- the same 1.5s once per step.
function Aegis_SBR:OwnCDLeft(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return 0 end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 or dur <= 1.55 then return 0 end
    local rem = start + dur - GetTime()
    if rem < 0 then return 0 end
    return rem
end

-- True if the spell's OWN cooldown is free, ignoring the global cooldown.
-- A short reported duration (<= ~1.5s) means only the GCD is active, which
-- we treat as "ready" so a held priority spell does not lose the GCD-edge
-- race to the unconditional seal recast.
function Aegis_SBR:OwnCDReady(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return false end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 then return true end
    if dur <= 1.55 then return true end
    return (start + dur - GetTime()) <= 0
end

-- ============================================================
-- Swing timer tracker. A plain white swing shows in the combat log as
-- "You hit/crit/miss ...", while a named ability or seal shows as
-- "Your <name> ...". Only plain swings move the timer. We predict the next
-- swing from the last one plus the main hand speed, the same idea AttackBar
-- uses. This is the foundation for seal twisting.
-- ============================================================
function Aegis_SBR:OnSwingMessage(msg)
    if not msg then return end
    if string.find(msg, "^Your ") then return end   -- a named ability or seal, not a white swing
    if string.find(msg, "^You ") then
        self.lastSwing = GetTime()
        local mh = UnitAttackSpeed("player")
        if mh and mh > 0 then self.swingSpeed = mh end
    end
end

-- How many swings may be missed before the timer is called unknown. A running
-- auto-attack re-anchors lastSwing every swingSpeed seconds and a miss, dodge
-- or parry anchors it too, so missing this many in a row means nothing is
-- swinging - not that the next swing is imminent.
local SWING_STALE = 2.5

-- Predicted seconds until the next white swing, or nil if unknown.
--
-- The modulo below is what makes the staleness test necessary: it keeps
-- cycling forever from the last real swing, so after auto-attack stops it goes
-- on reporting a perfectly plausible countdown. In a captured log the trace
-- showed a healthy swing timer through stretches where no swing had landed for
-- ten seconds, which is exactly the "auto-attack sometimes was not running"
-- report it should have made visible.
function Aegis_SBR:SwingTimeLeft()
    if not self.lastSwing or not self.swingSpeed or self.swingSpeed <= 0 then return nil end
    local elapsed = GetTime() - self.lastSwing
    if elapsed > self.swingSpeed * SWING_STALE then return nil end
    return self.swingSpeed - math.mod(elapsed, self.swingSpeed)
end

-- Throttled per-press trace, toggled with /sbr trace. Accepts any number of
-- lines; the throttle is checked once so multi-line traces are never half
-- swallowed (Lua 5.0 packs varargs into the implicit `arg` table).
-- ============================================================
-- Press log (AegisLog). The 1.12 Lua sandbox has no file access at all - no
-- io, no os - so the only way to get data off the client is a SavedVariable,
-- which the client serialises to
--   WTF\Account\<ACCOUNT>\<Realm>\<Char>\SavedVariables\Aegis_SBR.lua
-- on /reload or logout. It is therefore NOT live: nothing is on disk until
-- one of those happens. Kept in its own SavedVariable rather than inside
-- AegisDB so a big log can never bloat or endanger the profile data, and so
-- it can be cleared on its own.
--
-- A true ring buffer (write index that wraps) rather than append-and-trim:
-- table.remove(t, 1) would shift every entry on every press, which at a
-- multi-thousand cap is real work inside the rotation's hot path.
-- ============================================================
local LOG_MAX = 2000

function Aegis_SBR:LogInit(reset)
    if type(AegisLog) ~= "table" then AegisLog = {} end
    if reset or type(AegisLog.entries) ~= "table" then
        AegisLog.entries = {}
        AegisLog.pos = 0        -- entries written since the last clear (can exceed max)
        AegisLog.max = LOG_MAX
        AegisLog.started = date and date("%Y-%m-%d %H:%M:%S") or ""
        AegisLog.t0 = GetTime()
    end
    if not AegisLog.t0 then AegisLog.t0 = GetTime() end
    if not AegisLog.max then AegisLog.max = LOG_MAX end
    return AegisLog
end

-- Append one line. Timestamps are seconds since the log was (re)started, so
-- the file stays readable without needing wall-clock per entry.
function Aegis_SBR:LogWrite(text)
    if not text then return end
    local L = self:LogInit()
    L.pos = (L.pos or 0) + 1
    local slot = math.mod(L.pos - 1, L.max) + 1
    L.entries[slot] = string.format("%.2f|%s", GetTime() - (L.t0 or 0), text)
end

-- True when anything wants trace output - chat, the press log, or both. The
-- class modules build their trace strings inside a guard so the concatenation
-- is skipped entirely when nobody is listening; that guard MUST use this and
-- not self.trace, or enabling only the log records nothing (the string is
-- never built, so Trace is never even called).
function Aegis_SBR:Tracing()
    -- A preview runs the same body four times a second; letting it trace would
    -- bury the real presses in the log and make the press log useless.
    if Aegis_SBR.deciding then return false end
    return (self.trace or self.logging) and true or false
end

-- Chat trace and the press log are independent on purpose: the chat line is
-- throttled to stay readable while playing, but the log wants EVERY press or
-- the CP distribution it is meant to answer would be a biased sample.
-- Only the FIRST line is logged. Callers pass the per-press state line first and
-- any supplementary diagnostics after it; those extras are static for a whole
-- session (the rogue's "rank: ..." line, for instance, never changes while
-- playing), so recording them once per press doubled both the file size and the
-- number of ring slots burned, for nothing. They stay in the chat trace, which
-- is where they are actually useful.
function Aegis_SBR:Trace(...)
    if not self.trace and not self.logging then return end
    if self.logging and arg[1] then self:LogWrite(arg[1]) end
    if not self.trace then return end
    local now = GetTime()
    if now - (self.traceT or 0) < 0.4 then return end
    self.traceT = now
    for i = 1, arg.n do
        if arg[i] then DEFAULT_CHAT_FRAME:AddMessage("SBR: " .. arg[i], 0.6, 0.8, 1.0) end
    end
end

-- One pass over the player's buffs per rotation press. Every HasBuff/BuffTime
-- in the same press then reads this table instead of rescanning all 32 slots.
-- Keyed by GetTime(), which is constant within a frame, so the snapshot can
-- never be read stale.
function Aegis_SBR:SnapshotBuffs()
    if not GetPlayerBuff then return end
    local snap = {}
    for i = 0, 31 do
        local ix = GetPlayerBuff(i, "HELPFUL")
        if ix and ix ~= -1 then
            local id = GetPlayerBuffID and GetPlayerBuffID(ix)
            if id then
                if id < -1 then id = id + 65536 end
                local nm = SpellInfo and SpellInfo(id)
                if nm and not snap[nm] then
                    local tl = GetPlayerBuffTimeLeft(ix) or 0
                    local st = (GetPlayerBuffApplications and GetPlayerBuffApplications(ix)) or 1
                    snap[nm] = { tl, st }
                end
            end
        end
    end
    self.buffSnap = snap
    self.buffSnapT = GetTime()
end

function Aegis_SBR:ScanBuff(name)
    -- fresh snapshot from this frame: O(1) read
    if self.buffSnap and self.buffSnapT == GetTime() then
        local e = self.buffSnap[name]
        if e then return e[1], e[2] end
        return nil, 0
    end
    -- no snapshot (UI refresh, slash commands, etc.): full scan as before
    if not GetPlayerBuff then return nil, 0 end
    for i = 0, 31 do
        local ix = GetPlayerBuff(i, "HELPFUL")
        if ix and ix ~= -1 then
            local id = GetPlayerBuffID and GetPlayerBuffID(ix)
            if id then
                if id < -1 then id = id + 65536 end
                if SpellInfo and SpellInfo(id) == name then
                    local tl = GetPlayerBuffTimeLeft(ix) or 0
                    local st = (GetPlayerBuffApplications and GetPlayerBuffApplications(ix)) or 1
                    return tl, st
                end
            end
        end
    end
    return nil, 0
end

function Aegis_SBR:HasBuff(name)
    local tl = self:ScanBuff(name)
    return tl ~= nil
end

-- First player buff whose RESOLVED NAME contains `frag`, or nil. The partial
-- match HasBuff cannot do: HasBuff needs the exact name, so it cannot answer
-- "is any Eclipse buff up" when the server's wording is not the one we guessed.
--
-- This exists because three modules hand-rolled that fallback with
-- `UnitBuff("player", i)` and searched the result for a spell NAME - but
-- UnitBuff's first return is the icon TEXTURE PATH, not a name (see
-- Aegis_SBR_BuffUp.lua, which names it `tex` and builds a tooltip to get the
-- name). Searching a file path for "Eclipse" or "Clearcast" matches only if
-- the artist happened to put that word in the filename, so those fallbacks
-- were dead. The warlock's copy searched for "Spell_Shadow_Twilight" and was
-- the only correct one, which is what identified the pattern.
--
-- Names come from the same SuperWoW id -> SpellInfo path as ScanBuff, so a
-- client without it simply finds nothing rather than misreporting.
function Aegis_SBR:BuffNameContaining(frag)
    if not frag or frag == "" then return nil end
    if self.buffSnap and self.buffSnapT == GetTime() then
        for nm in pairs(self.buffSnap) do
            if string.find(nm, frag, 1, true) then return nm end
        end
        return nil
    end
    if not GetPlayerBuff then return nil end
    for i = 0, 31 do
        local ix = GetPlayerBuff(i, "HELPFUL")
        if ix and ix ~= -1 then
            local id = GetPlayerBuffID and GetPlayerBuffID(ix)
            if id then
                if id < -1 then id = id + 65536 end
                local nm = SpellInfo and SpellInfo(id)
                if nm and string.find(nm, frag, 1, true) then return nm end
            end
        end
    end
    return nil
end

function Aegis_SBR:BuffTime(name)
    local tl, st = self:ScanBuff(name)
    return tl or 0, st or 0
end

-- ============================================================
-- Target debuff detection. One pass per press over the target's debuffs,
-- resolving each to its spell NAME through SuperWoW's spell id (the id is
-- returned by UnitDebuff and mapped with SpellInfo, the same id path the
-- player buff snapshot uses). Name matching is exact and rank/locale proof,
-- so it replaces the old icon-fragment guessing. The icon texture is kept in
-- the snapshot as a fallback for clients without SuperWoW (or ids we cannot
-- map), so detection degrades to the previous behaviour rather than breaking.
-- ============================================================
function Aegis_SBR:SnapshotTargetDebuffs()
    local byName, list = {}, {}
    if UnitExists("target") then
        for i = 1, 40 do
            -- vanilla returns (texture, applications, dispelType); SuperWoW
            -- appends the spell id. applications is always the 2nd return, so
            -- the id is the first NUMERIC value among the trailing returns
            -- (dispelType is a string or nil and is skipped naturally).
            local tex, stacks, d3, d4, d5 = UnitDebuff("target", i)
            if not tex then break end
            stacks = stacks or 0
            local id
            if type(d3) == "number" then id = d3
            elseif type(d4) == "number" then id = d4
            elseif type(d5) == "number" then id = d5 end
            if id and SpellInfo then
                if id < -1 then id = id + 65536 end
                local nm = SpellInfo(id)
                if nm and nm ~= "" and byName[nm] == nil then byName[nm] = stacks end
            end
            table.insert(list, { tex = tex, stacks = stacks })
        end
    end
    self.tdebuffSnap = { byName = byName, list = list }
    self.tdebuffSnapT = GetTime()
end

-- Returns up (bool), stacks. Tries the exact spell name first (SuperWoW id
-- path), then the optional icon-fragment fallback. Builds the snapshot on
-- demand when it is stale, so slash commands and the UI work outside a press.
function Aegis_SBR:ScanTargetDebuff(name, texFrag)
    if not (self.tdebuffSnap and self.tdebuffSnapT == GetTime()) then
        self:SnapshotTargetDebuffs()
    end
    local snap = self.tdebuffSnap
    if name and name ~= "" then
        local s = snap.byName[name]
        if s ~= nil then return true, s end
    end
    if texFrag and texFrag ~= "" then
        for i = 1, table.getn(snap.list) do
            local e = snap.list[i]
            if e.tex and string.find(e.tex, texFrag) then return true, e.stacks end
        end
    end
    return false, 0
end

function Aegis_SBR:TargetDebuffUp(name, texFrag)
    local up = self:ScanTargetDebuff(name, texFrag)
    return up
end

function Aegis_SBR:TargetDebuffStacks(name, texFrag)
    local up, st = self:ScanTargetDebuff(name, texFrag)
    if up then return st or 0 end
    return 0
end

-- True when SuperWoW's id->name path is available, so a debuff without a
-- known icon fragment can still be tracked exactly (used by modules to decide
-- between exact upkeep and a blind reapply timer).
function Aegis_SBR:CanResolveDebuffNames()
    return SpellInfo ~= nil
end

-- Does this spell reach the unit?
--
-- IsSpellInRange answers 1 in range, 0 out of range, and -1 when it cannot
-- judge: an unknown spell, missing range data, or a unit the spell cannot
-- currently be cast on at all. ONLY an explicit 0 may block.
--
-- Reading -1 as "out of range" is how a healer stops healing somebody standing
-- right next to them - an immunity bubble, a phase change, a brief untargetable
-- moment all produce it, and the unit then vanishes from the heal list entirely
-- with no message. The asymmetry decides the rule: a wrongly INCLUDED unit
-- costs one failed cast, a wrongly EXCLUDED tank costs the fight.
--
-- Same stance the shaman's InSpellRange has always taken; this is that rule
-- moved somewhere every module can reach it.
function Aegis_SBR:SpellReaches(spell, unit)
    if not spell or spell == "" then return true end
    if not unit or not UnitExists(unit) then return false end
    if not IsSpellInRange then return CheckInteractDistance(unit, 4) and true or false end
    -- pcall: an unresolvable name throws here rather than answering -1, and a
    -- thrown error aborts the press outright - strictly worse than the -1 case
    -- this function already treats as "in range".
    local ok, r = pcall(IsSpellInRange, spell, unit)
    if not ok then return true end
    if r == 0 then return false end
    return true
end

-- ============================================================
-- Line of sight
-- ============================================================
-- The one answer 1.12 has no API for: IsSpellInRange measures distance and
-- knows nothing about the pillar in between. Until now the only source was the
-- client refusing a cast, which is a five second blacklist applied AFTER a
-- press was already spent - and which recovers only when the window runs out,
-- not when the corner is cleared.
--
-- UnitXP_SP3 answers it outright, and it is already a required dependency for
-- the range window. Puppeteer draws its unit frames from this same call.
--
-- Armed only after the world exists. Puppeteer guards the same call against
-- being made too early because it can crash the client; PLAYER_ENTERING_WORLD
-- is strictly later than the ADDON_LOADED it uses.
Aegis_SBR.sightReady = false
local sightFrame = CreateFrame("Frame")
sightFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
sightFrame:SetScript("OnEvent", function()
    Aegis_SBR.sightReady = true
end)

-- True unless the client says outright that the unit is NOT in sight. Without
-- UnitXP_SP3, before the world is up, or on a throw, it answers true - a
-- detection that cannot answer must never close a gate.
function Aegis_SBR:InSight(unit)
    if not unit or not UnitExists(unit) then return true end
    if not self.sightReady or not UnitXP then return true end
    local ok, r = pcall(UnitXP, "inSight", "player", unit)
    if not ok then return true end
    if r == false or r == 0 then return false end
    return true
end

-- ============================================================
-- Heal / dispel priority list
-- ============================================================
-- A list of player NAMES, in order. Names rather than raid slots, so it survives
-- a regroup; shared between healing and dispelling because it is the same
-- statement about the same people - a poison on the tank matters for the same
-- reason a heal on the tank does.
--
-- Lives here rather than in each class so the four healers and the mage cannot
-- drift apart on what "priority" means.

-- How many percentage points a unit's health is padded by, according to its
-- place on the list. Position 1 carries none, position 2 twenty, anyone unlisted
-- thirty-five. The padding makes a unit read as HEALTHIER, so it only decides
-- near-ties - a badly hurt damage dealer still outranks a scratched tank.
local PRIO_STEPS = { 0, 20 }
local PRIO_OTHERS = 35

function Aegis_SBR:PrioAdd(cfg, name)
    if not name or name == "" then return false end
    if type(cfg.healPrioList) ~= "table" then cfg.healPrioList = {} end
    for i = 1, table.getn(cfg.healPrioList) do
        if cfg.healPrioList[i] == name then return false end
    end
    table.insert(cfg.healPrioList, name)
    return true
end

function Aegis_SBR:PrioRemove(cfg, idx)
    if type(cfg.healPrioList) ~= "table" then return false end
    if not idx or not cfg.healPrioList[idx] then return false end
    table.remove(cfg.healPrioList, idx)
    return true
end

-- Handicap from the list alone, 0 when the feature is off or the list is empty.
function Aegis_SBR:PrioListHandicap(cfg, unit)
    if not cfg or not cfg.healPrio then return 0 end
    local list = cfg.healPrioList
    if not list or table.getn(list) == 0 then return 0 end
    local name = UnitName(unit)
    if name then
        for i = 1, table.getn(list) do
            if list[i] == name then return PRIO_STEPS[i] or PRIO_OTHERS end
        end
    end
    return PRIO_OTHERS
end

-- The same units, reordered: your friendly target first (when that option is
-- on), then the list in its own order, then everyone else as they came.
--
-- Used for dispelling, where there is nothing to weigh - an affliction is
-- present or it is not, so order is the only lever. Applied whenever the list
-- has entries, independently of the heal-priority switch, which governs the
-- health handicap above and has no meaning here.
function Aegis_SBR:PrioOrderUnits(cfg, units)
    if not cfg then return units end
    local list = cfg.healPrioList
    local wantTarget = cfg.healPrioTarget and UnitExists("target")
        and UnitIsFriend("player", "target")
    if not wantTarget and (not list or table.getn(list) == 0) then return units end

    local out, taken = {}, {}
    local function add(u)
        if u and not taken[u] then taken[u] = true; table.insert(out, u) end
    end
    if wantTarget then
        for i = 1, table.getn(units) do
            if UnitExists(units[i]) and UnitIsUnit(units[i], "target") then add(units[i]) end
        end
    end
    if list then
        for r = 1, table.getn(list) do
            for i = 1, table.getn(units) do
                local u = units[i]
                if UnitExists(u) and UnitName(u) == list[r] then add(u) end
            end
        end
    end
    for i = 1, table.getn(units) do add(units[i]) end
    return out
end

-- The party or raid as unit tokens, for a class that has no roster helper of
-- its own.
function Aegis_SBR:GroupUnitList()
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

-- ============================================================
-- Talent slot binding (Goblin Brainwashing Device)
--
-- Turtle's device stores four talent builds and swaps between them, and fires no
-- event to say which one is now live. It does not have to: the device is an
-- ordinary gossip NPC, and the option you click reads "Activate 2nd
-- Specialization". The number is in the text.
--
-- So the slot is read where it is actually stated - by hooking the gossip click,
-- the same way ItemRack does it. Exact, immediate, and untroubled by two specs
-- happening to have identical talents.
--
-- A second, weaker source backs it up. Every confirmed switch teaches us what
-- that slot's talents look like, so a later change with no gossip click - a
-- login, most obviously - is still recognised by the build alone. The
-- fingerprint is exact per talent rank rather than a per-tree total, because two
-- different builds can share 31/0/20.
--
-- Both sources only ever ACT on a match. An unrecognised build changes nothing:
-- spending a single talent point fires the same event, and a guess would swap
-- your rotation mid-fight.
-- ============================================================
local GOBBO_SLOTS = 4

-- Every talent's rank, in a fixed order. Exact rather than a per-tree total,
-- because two different builds can share 31/0/20 and must not be confused.
-- Returns nil while the talent tables are not loaded yet (early login), which
-- callers must treat as "do not know", never as "no talents".
function Aegis_SBR:TalentFingerprint()
    if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then return nil end
    local tabs = GetNumTalentTabs() or 0
    if tabs == 0 then return nil end
    local out, spent = {}, 0
    for t = 1, tabs do
        local n = GetNumTalents(t) or 0
        for i = 1, n do
            local _, _, _, _, rank = GetTalentInfo(t, i)
            rank = rank or 0
            spent = spent + rank
            table.insert(out, rank)
        end
    end
    -- No points spent at all is not a build, it is a fresh character or a
    -- half-loaded talent frame. Never photograph it.
    if spent == 0 then return nil end
    return table.concat(out, ",")
end

function Aegis_SBR:GobboStore()
    if not AegisDB then return nil end
    if type(AegisDB.gobbo) ~= "table" then AegisDB.gobbo = {} end
    return AegisDB.gobbo
end

-- Bind one slot to the profile and tab given, photographing the talents now.
-- A slot holds one binding and a tab belongs to one slot, so both are cleared
-- first - otherwise two tabs could answer to the same build.
function Aegis_SBR:GobboBind(slot, profile, tab)
    local st = self:GobboStore()
    if not st or not slot or slot < 1 or slot > GOBBO_SLOTS then return false, "bad slot" end
    for i = 1, GOBBO_SLOTS do
        local b = st[i]
        if b and b.profile == profile and b.tab == tab then st[i] = nil end
    end
    st[slot] = { profile = profile, tab = tab }
    return true
end

-- What each slot's talents looked like the last time we saw it activated.
-- Learned, never entered: the player binds a NUMBER, and the build behind that
-- number is whatever the device produced.
function Aegis_SBR:GobboFpStore()
    if not AegisDB then return nil end
    if type(AegisDB.gobboFp) ~= "table" then AegisDB.gobboFp = {} end
    return AegisDB.gobboFp
end

function Aegis_SBR:GobboClear(slot)
    local st = self:GobboStore()
    if st and slot then st[slot] = nil end
end

-- Which slot this profile and tab are bound to, or nil.
function Aegis_SBR:GobboSlotOf(profile, tab)
    local st = self:GobboStore()
    if not st then return nil end
    for i = 1, GOBBO_SLOTS do
        local b = st[i]
        if b and b.profile == profile and b.tab == tab then return i end
    end
    return nil
end

-- Switch to whatever slot N is bound to. Returns true if anything moved.
function Aegis_SBR:GobboActivate(slot, why)
    local st = self:GobboStore()
    local b = st and st[slot]
    if not b or not AegisDB or not AegisDB.profiles then return false end
    if not AegisDB.profiles[b.profile] then
        msgOut("talent slot " .. slot .. " points at profile '" .. b.profile
            .. "', which no longer exists.", 1, 0.5, 0.3)
        return false
    end
    local changed = false
    if AegisDB.active ~= b.profile then
        AegisDB.active = b.profile
        changed = true
    end
    -- The tab is a field on the profile, written exactly the way the tab rail
    -- writes it, so the rotation's own branching is untouched.
    local sp = self.active and self.active.specTabs
    if sp and b.tab then
        local val = b.tab
        if sp.encode then val = sp.encode(b.tab) end
        local cfg = AegisDB.profiles[b.profile]
        if cfg and cfg[sp.field] ~= val then cfg[sp.field] = val; changed = true end
    end
    if changed then
        msgOut("talent slot " .. slot .. " (" .. (why or "?") .. "): '" .. b.profile
            .. "'" .. (b.tab and (" / " .. b.tab) or "") .. ".")
        if Aegis_SBR_UI and Aegis_SBR_UI.built and Aegis_SBR_UI.Refresh then
            Aegis_SBR_UI:Refresh()
        end
    end
    return changed
end

-- The device told us which slot, in its own gossip text. Act on it now, and arm
-- the fingerprint so the talent change that follows teaches us this build.
function Aegis_SBR:GobboOnGossip(slot)
    if not slot or slot < 1 or slot > GOBBO_SLOTS then return end
    self.gobboLearn = slot
    self:GobboActivate(slot, "device")
end

-- Talents changed: learn the armed slot's build, or recognise a known one.
-- Silent when nothing matches, which is the common case.
function Aegis_SBR:GobboApply()
    local st = self:GobboStore()
    if not st or not AegisDB or not AegisDB.profiles then return end
    local fp = self:TalentFingerprint()
    if not fp then return end
    local fps = self:GobboFpStore()
    if not fps then return end

    -- A gossip click just told us the slot, so whatever the talents are now IS
    -- that slot's build. Learned rather than asked for, which is why binding a
    -- number never requires you to be wearing that spec.
    if self.gobboLearn then
        fps[self.gobboLearn] = fp
        self.gobboLearn = nil
        self.gobboLastFp = fp
        return
    end

    if fp == self.gobboLastFp then return end
    self.gobboLastFp = fp
    for i = 1, GOBBO_SLOTS do
        if fps[i] == fp then return self:GobboActivate(i, "talents") end
    end
end

-- Hook the device's gossip options and read the slot out of the text, which is
-- where it is plainly stated. Chained, not replaced: ItemRack hooks the same
-- global for the same reason, and both have to keep working.
--
-- Only "Activate ..." counts. A "Save ..." click stores your CURRENT build into
-- that slot and changes nothing about what you are wearing, so acting on it
-- would switch the rotation to a spec you never entered.
local GBD_NAME = "Goblin Brainwashing Device"
function Aegis_SBR:HookGossip()
    if self.gossipHooked then return end
    if not GossipTitleButton_OnClick then return end
    self.gossipHooked = true
    local prev = GossipTitleButton_OnClick
    GossipTitleButton_OnClick = function(button)
        if this and this.type ~= "Available" and this.type ~= "Active"
            and GossipFrameNpcNameText and GossipFrameNpcNameText:GetText() == GBD_NAME then
            local text = this:GetText() or ""
            if not string.find(text, "^Save") then
                local _, _, num = string.find(text, "Activate (%d)")
                local slot = tonumber(num)
                -- A renamed spec loses the number, so fall back to the names the
                -- spec-naming addon keeps, matched by position.
                if not slot and GNS_SpecNames then
                    local mine = GNS_SpecNames[UnitName("player") or ""]
                    if mine then
                        local _, _, nm = string.find(text, "^Activate%s*(.+) %([%d/]+%)$")
                        if nm then
                            for i = 1, GOBBO_SLOTS do
                                if mine[i] == nm then slot = i; break end
                            end
                        end
                    end
                end
                if slot then Aegis_SBR:GobboOnGossip(slot) end
            end
        end
        if prev then return prev(button) end
    end
end

function Aegis_SBR:CmdGobbo()
    local st = self:GobboStore()
    msgOut("talent slots:")
    local any = false
    for i = 1, GOBBO_SLOTS do
        local b = st and st[i]
        if b then
            any = true
            msgOut("  " .. i .. " -> '" .. b.profile .. "'" .. (b.tab and (" / " .. b.tab) or ""))
        end
    end
    if not any then msgOut("  (none bound - pick a slot on any spec tab)") end
    local fps = self:GobboFpStore()
    local learned = 0
    for i = 1, GOBBO_SLOTS do if fps and fps[i] then learned = learned + 1 end end
    msgOut("  device hook " .. (self.gossipHooked and "installed" or "NOT installed")
        .. ", " .. learned .. " of " .. GOBBO_SLOTS .. " builds learned.")
end

-- Are we moving?
--
-- Shared: the warlock refuses to start a channel while moving, and the paladin
-- refuses to drop Consecration on ground it is about to leave.
--
-- 1.12 has no speed API, so this is measured the way the movement-speed addons
-- do it: our own position, sampled and differenced. SuperWoW's UnitPosition
-- resolves for players, which is all this needs.
--
-- Answers FALSE when it cannot tell - no SuperWoW, no reading yet. "Cannot
-- judge" must never block a cast; the same rule the range checks follow.
--
-- The sample interval is what makes it stable. Two presses can be a tenth of a
-- second apart, and over that gap a walking character barely moves, so
-- differencing every press would read as standing still half the time.
local MOVE_SAMPLE = 0.2
-- Yards of drift tolerated. Position readings jitter slightly while stationary,
-- and a knockback or a fear is genuinely movement, so this is small.
local MOVE_EPS = 0.15

function Aegis_SBR:Moving()
    if not UnitPosition then return false end
    local x, y = UnitPosition("player")
    if not x or not y then return false end
    local now = GetTime()
    local s = self.moveSample
    if not s then
        self.moveSample = { x = x, y = y, t = now, moving = false }
        return false
    end
    -- Between samples, the last answer stands rather than being recomputed off
    -- a stale reference point.
    if (now - s.t) < MOVE_SAMPLE then return s.moving end
    local dx, dy = x - s.x, y - s.y
    s.x, s.y, s.t = x, y, now
    s.moving = (dx * dx + dy * dy) > (MOVE_EPS * MOVE_EPS)
    -- When the standing still began, for StillFor below.
    if s.moving then s.since = nil
    elseif not s.since then s.since = now end
    return s.moving
end

-- Have we been standing still for at least this long?
--
-- Not the same question as "are we moving", and the difference is the whole
-- point. Stopping is not a commitment to stay stopped: a step to reposition
-- puts a fraction of a second of stillness in the middle of moving, and a check
-- that only asks "moving right now" fires into it. That gap was spotted from
-- play before the first version shipped with it.
--
-- So a ground effect asks for a DWELL, not for a moment. What it buys is a
-- guess that the next few seconds look like the last few - the only guess
-- available, since nothing can see where somebody intends to walk.
--
-- Answers TRUE when movement cannot be measured at all (no SuperWoW), so this
-- never becomes a gate that can never open.
function Aegis_SBR:StillFor(seconds)
    if not UnitPosition then return true end
    if self:Moving() then return false end
    local s = self.moveSample
    if not s then return true end
    if not s.since then return false end
    return (GetTime() - s.since) >= (seconds or 0)
end

-- ============================================================
-- Are we behind the target?
--
-- Vanilla cannot answer this at all - there is no facing in the 1.12 API - but
-- UnitXP_SP3 can, and it is already a Required dependency for the range window.
-- Backstab and Ambush are refused outright from the front, so a rogue who picks
-- Backstab as their builder and stands anywhere else spends every press on a
-- refusal. Nothing here checked it; "behind" appeared only in comments.
--
-- Three-state on purpose, and nil is the common case: without UnitXP there is no
-- answer, and a step that needs one must then go ahead rather than lock itself
-- out. The same rule as the range checks - a source that cannot answer never
-- closes a gate.
-- ============================================================
function Aegis_SBR:BehindTarget()
    if not UnitXP or not UnitExists("target") then return nil end
    local ok, r = pcall(UnitXP, "behind", "player", "target")
    if not ok or r == nil then return nil end
    return r and true or false
end

-- Only an explicit false forbids.
function Aegis_SBR:PositionAllows(need)
    if need ~= "behind" then return true end
    return self:BehindTarget() ~= false
end

-- ============================================================
-- What is actually equipped
--
-- Several abilities are refused by the client on the weapon alone: Shield Slam,
-- Shield Block and Shield Bash need a shield, Backstab and Ambush need a dagger.
-- Nothing here checked that, and Class_Warrior.lua even carries the note
-- "(Shield Slam needs a shield)" next to a step that did not test for one - so a
-- fury warrior who switched the option on spent every press on a refusal.
--
-- Both answers are three-state, and the third state is the important one. A
-- freshly logged-in client has not cached the item yet and GetItemInfo returns
-- nothing; the subtype string is also LOCALISED, so a non-English client will
-- not match "Daggers" no matter what is in the hand. Either way the answer is
-- "cannot tell" - nil - and every caller must read that as "go ahead". Blocking
-- an ability because we failed to identify a weapon would be a worse bug than
-- the one being fixed, and it would be invisible.
--
-- The shield check leans on itemEquipLoc first, which is a constant rather than
-- a translated word and therefore holds everywhere. There is no equivalent for
-- daggers - equipLoc says only "one hand" - so that one is honest about being
-- an English-client improvement and a no-op elsewhere.
-- ============================================================
local SLOT_OFFHAND, SLOT_MAINHAND = 17, 16
local DAGGER_SUBTYPE = { ["Daggers"] = true, ["Dagger"] = true }

-- Cleared whenever gear changes; rebuilt lazily.
function Aegis_SBR:ClearEquipCache()
    self.equipCache = nil
end

local function itemAt(slot)
    if not GetInventoryItemLink or not GetItemInfo then return nil end
    local link = GetInventoryItemLink("player", slot)
    if not link then return "empty" end
    local _, _, id = string.find(link, "item:(%d+)")
    if not id then return nil end
    local _, _, _, _, _, subType, _, equipLoc = GetItemInfo(tonumber(id))
    if not subType and not equipLoc then return nil end
    return { subType = subType, equipLoc = equipLoc }
end

local function cached(self, slot)
    if not self.equipCache then self.equipCache = {} end
    local hit = self.equipCache[slot]
    if hit ~= nil then return hit end
    local v = itemAt(slot)
    -- Only a definite answer is cached. A tooltip that has not populated yet
    -- must not freeze "unknown" in place for the session.
    if v ~= nil then self.equipCache[slot] = v end
    return v
end

-- true / false / nil (cannot tell).
function Aegis_SBR:HasShield()
    local v = cached(self, SLOT_OFFHAND)
    if v == nil then return nil end
    if v == "empty" then return false end
    if v.equipLoc == "INVTYPE_SHIELD" then return true end
    if v.equipLoc then return false end          -- something else is in the hand
    return nil
end

-- true / false / nil (cannot tell). See the note above: false is only ever
-- returned when the subtype was read AND recognised as a weapon that is not a
-- dagger, so a locale this does not know answers nil and blocks nothing.
function Aegis_SBR:HasDagger()
    local v = cached(self, SLOT_MAINHAND)
    if v == nil then return nil end
    if v == "empty" then return false end
    if not v.subType then return nil end
    if DAGGER_SUBTYPE[v.subType] then return true end
    -- Recognised as a weapon class, and not a dagger.
    if string.find(v.subType, "s$") or string.find(v.subType, "Weapon") then return false end
    return nil
end

-- Convenience for a rotation step: does the weapon requirement forbid this?
-- Only an explicit false forbids; nil never does.
function Aegis_SBR:WeaponAllows(need)
    local have
    if need == "shield" then have = self:HasShield()
    elseif need == "dagger" then have = self:HasDagger()
    else return true end
    return have ~= false
end

-- ============================================================
-- Counting nearby enemies
--
-- 1.12 has no API for "how many mobs are near me", which is why every AoE
-- toggle in this addon is manual. It is still answerable, just not from the
-- vanilla API: a VISIBLE NAMEPLATE is a frame under WorldFrame, and SuperWoW
-- puts that unit's GUID in the frame's first name string - and a GUID is a unit
-- token to SuperWoW. So the nameplates you can see enumerate the mobs you can
-- see, and each one can then be asked its distance like any other unit.
--
-- That is how IWinEnhanced does it (through SuperCleveRoidMacros), and it is
-- worth being plain about the consequence: this counts what the CLIENT is
-- drawing. Nameplates switched off means nothing to enumerate. It is not a
-- hidden mob radar and cannot be.
--
-- Which is why the answer distinguishes "none" from "cannot tell", and returns
-- NIL for the latter. Everything gated on this must fail open - a count that
-- cannot be taken must never be read as zero and silently switch an ability off.
-- The capability is latched the first time a nameplate actually resolves, the
-- same way sting / debuff / cast-event detection is established elsewhere.
-- ============================================================
local ENEMY_CACHE_TTL = 0.3

-- Distance to any unit, not just the target. Same source order and the same
-- reasoning as the range window's own measurement.
function Aegis_SBR:DistanceTo(unit)
    if not unit or not UnitExists(unit) then return nil end
    if UnitDistanceSquared then
        local ok, d = pcall(UnitDistanceSquared, unit)
        if ok and type(d) == "number" and d >= 0 then return math.sqrt(d) end
    end
    if UnitXP then
        local ok, d = pcall(UnitXP, "distanceBetween", "player", unit)
        if ok and type(d) == "number" and d >= 0 then return d end
    end
    return nil
end

-- Enemies within `yards`, or nil when the count cannot be taken.
--
-- Cached for a fraction of a second: walking every WorldFrame child builds a
-- table each time, and doing that on every press in a raid is exactly the shape
-- of the cost this addon has been bitten by before.
function Aegis_SBR:CountEnemiesNear(yards)
    if not yards or yards <= 0 then return nil end
    local now = GetTime()
    local c = self.enemyCount
    if c and c.yards == yards and (now - c.t) < ENEMY_CACHE_TTL then return c.n end

    local seen, n = {}, 0
    -- Deduplicated by GUID, never by unit token. The two sources below name the
    -- same mob differently: the nameplate scan hands over a GUID, and "target"
    -- is a token for a mob that also HAS a nameplate. Keyed by token, your own
    -- target was therefore counted twice - reported from play as "set it to 2
    -- and it fires on one mob, set it to 4 and it fires on three", an off-by-one
    -- that appears the moment you have a target, which in combat is always.
    local function consider(unit)
        if not unit then return end
        if not UnitExists(unit) or not UnitCanAttack("player", unit) then return end
        if UnitIsDeadOrGhost(unit) then return end
        local _, guid = UnitExists(unit)
        local key = guid or unit
        if seen[key] then return end
        seen[key] = true
        local d = self:DistanceTo(unit)
        if d and d <= yards then n = n + 1 end
    end

    -- Nameplates: the only source that sees a mob you have not targeted.
    if WorldFrame and WorldFrame.GetChildren then
        local kids = { WorldFrame:GetChildren() }
        for i = 1, table.getn(kids) do
            local f = kids[i]
            if f and f.IsVisible and f:IsVisible() and f.GetName then
                local ok, guid = pcall(f.GetName, f, 1)
                if ok and type(guid) == "string" and guid ~= "" and UnitExists(guid) then
                    self.enemyScanSeen = true
                    consider(guid)
                end
            end
        end
    end

    -- Without a working nameplate scan there is no count, only a guess. Say so.
    if not self.enemyScanSeen then return nil end

    -- Cheap extras the scan can miss (a target behind you draws no nameplate).
    consider("target")
    consider("targettarget")
    consider("pettarget")

    self.enemyCount = { yards = yards, n = n, t = now }
    return n
end

-- ============================================================
-- Is the target casting?
--
-- 1.12 cannot see another unit's cast at all - there is no API and no cast bar
-- to read. SuperWoW's UNIT_CASTEVENT can: it reports every registered cast with
-- the caster's GUID, the spell id and the cast length in milliseconds, so a
-- START recorded against a GUID plus its duration is a cast in progress.
--
-- Kept in the core rather than in a class because it answers the same question
-- for every interrupt there will ever be, and because the event is already
-- registered and dispatched here.
--
-- Instants never appear as a cast in progress (they arrive as CAST with no
-- meaningful duration), which is correct: there is nothing to interrupt.
-- ============================================================
Aegis_SBR.enemyCastEnd = {}

function Aegis_SBR:NoteEnemyCast(guid, ms)
    if not guid then return end
    local secs = tonumber(ms)
    if not secs or secs <= 0 then return end
    self.enemyCastEnd[guid] = GetTime() + (secs / 1000)
end

function Aegis_SBR:ClearEnemyCast(guid)
    if guid then self.enemyCastEnd[guid] = nil end
end

-- True only when a cast is genuinely still running. Answers FALSE without
-- SuperWoW, which is "cannot tell" - and here that is the safe direction: it
-- withholds an interrupt rather than inventing one.
function Aegis_SBR:TargetIsCasting()
    if not UnitExists("target") then return false end
    local _, guid = UnitExists("target")
    if not guid then return false end
    local t = self.enemyCastEnd[guid]
    if not t then return false end
    if GetTime() > t then self.enemyCastEnd[guid] = nil; return false end
    return true
end

-- ============================================================
-- Whose debuff is that?
--
-- Most damage-over-time effects do NOT stack between casters: two warlocks on
-- one mob each get their own Corruption, two rogues each get their own Rupture,
-- and the client shows both. Reading "Corruption is on the target" as "MY
-- Corruption is on the target" means the second one to arrive applies nothing at
-- all and spends the fight on filler, because somebody else's debuff answers for
-- theirs. Reported from play on the warlock; it was true of every class that
-- keeps a debuff up.
--
-- Two sources, in order of how much they actually know:
--
--   1. ClassicAPI records the caster. Where it answers true or false, that ends
--      the question. nil is "cannot tell" - an aura applied before login has no
--      caster on file - and falls through to:
--
--   2. Our own ledger of what we applied, per target and spell, checked against
--      the effect's duration. This needs no API at all, which is the point: most
--      clients running this have no caster information whatsoever.
--
-- Wrong in the cautious direction when the ledger is missing (after a reload,
-- say): it answers "not mine", one extra application goes out, and the ledger is
-- right from then on. The failure it replaces is the opposite and never self-
-- corrects - applying nothing for as long as somebody else keeps theirs up.
--
-- NOT for debuffs that are shared rather than owned: Hunter's Mark, Sunder
-- Armor, Demoralizing Shout, a paladin's judgement. There, anybody's copy is as
-- good as ours and re-applying over it is pure waste. Each class names its own;
-- this only answers the question it is asked.
-- ============================================================
Aegis_SBR.debuffLedger = {}

-- `duration` is optional and is the effect's length AS APPLIED - the caster is
-- the only one who knows it, and for several effects it is not a constant at
-- all (a rogue's Rupture runs 6 to 16 seconds depending on the combo points
-- spent). Stored as an expiry rather than a timestamp for exactly that reason.
-- Omit it and the entry never expires, which reads as "ours" for as long as the
-- debuff is visible: the right answer when nothing better is known, since the
-- alternative is re-applying on a guess.
function Aegis_SBR:NoteDebuffApplied(targetId, spell, duration)
    if not targetId or not spell then return end
    self.debuffLedger[targetId .. "|" .. spell] = {
        expires = duration and (GetTime() + duration) or nil,
    }
end

-- Cleared on leaving combat: a GUID belongs to one mob for one pull, and
-- carrying the table around for a session would eventually answer for a
-- different creature entirely.
function Aegis_SBR:ClearDebuffLedger()
    self.debuffLedger = {}
end

-- true when the debuff on this target is ours. The duration was supplied when it
-- was applied, so nothing here has to guess how long it runs.
function Aegis_SBR:DebuffMine(spell, targetId)
    if not spell then return true end
    if self.TargetDebuffMine then
        local mine = self:TargetDebuffMine(spell)
        if mine == true then return true end
        if mine == false then return false end
    end
    local rec = targetId and self.debuffLedger[targetId .. "|" .. spell]
    if not rec then return false end
    if not rec.expires then return true end
    return GetTime() < rec.expires
end

-- Every pet belonging to the given player units, appended in the same order.
--
-- Dispelling only. Pets carry poisons, diseases and curses like anybody else and
-- a hunter's pet dying to a poison is a third of that hunter's damage gone -
-- they were simply never in the list, because the roster helpers are shared with
-- the healing engines and healing a pet is its own opt-in decision.
--
-- Appended rather than interleaved on purpose: within one affliction type the
-- order decides who is cured first, and a player outranks a pet there.
function Aegis_SBR:AppendPets(units)
    if not units then return units end
    local out = {}
    local n = table.getn(units)
    for i = 1, n do out[i] = units[i] end
    for i = 1, n do
        local u = units[i]
        local pet
        if u == "player" then pet = "pet"
        else
            local _, _, k = string.find(u, "^party(%d+)$")
            if k then pet = "partypet" .. k end
            if not pet then
                local _, _, r = string.find(u, "^raid(%d+)$")
                if r then pet = "raidpet" .. r end
            end
        end
        if pet and UnitExists(pet) then table.insert(out, pet) end
    end
    return out
end

-- Units the client has just refused a cast on, by name, with the time it said
-- so. Line of sight and range are the two answers no API can give in advance:
-- IsSpellInRange measures distance and knows nothing about the hill in between,
-- and it answers -1 "cannot judge" often enough that a heal target can be picked
-- who was never castable.
--
-- Without this the refusal changed nothing: the same unit was still the worst
-- hurt on the next press, so it was picked again, refused again, forever - the
-- reported "if I don't have line of sight, the rotation just keeps spamming".
-- Reported from Alterac Valley, where a raid is spread across a whole zone and
-- both conditions are the normal case rather than the exception.
--
-- Held for a few seconds only. Both conditions are about where two people happen
-- to be standing, and that changes constantly.
local BLOCK_WINDOW = 5
-- How long after our cast an error may still be blamed on it. The error arrives
-- on the same frame in practice; the allowance is for a laggy one, and it is
-- short so a later refusal about something else cannot land on this unit.
local BLAME_WINDOW = 1.5
Aegis_SBR.castBlocked = {}

-- Remember who we just aimed a unit-targeted cast at, so an error message that
-- names no unit can be attributed. Called by every class's CastOn.
function Aegis_SBR:NoteUnitCast(unit)
    self.lastUnitCast = unit and UnitName(unit) or nil
    self.lastUnitCastAt = GetTime()
end

-- True while the client has recently refused to cast on this unit.
function Aegis_SBR:CastBlocked(unit)
    if not unit then return false end
    local t = self.castBlocked[UnitName(unit) or ""]
    return (t and (GetTime() - t) < BLOCK_WINDOW) and true or false
end

-- Compared against the client's own strings, so it holds in any locale. The
-- literals are a fallback for a client that does not define a global - and, on
-- Turtle, more than a fallback: in a captured tank log every one of 69 refusals
-- went through the UNRECOGNISED branch below. The client answers a melee
-- ability with the ERR_ family ("You are too far away!", "You are facing the
-- wrong way!", "Ability is not ready yet.", "Can't do that while stunned")
-- where these lists carried only the SPELL_FAILED_ wordings. Both are listed
-- now, and the comparison is normalised so a trailing period cannot decide it.
--
-- Every entry must be non-nil: an undefined global in the middle of a table
-- makes table.getn undefined in Lua 5.0, which is why each one carries `or`.
local function NormErr(text)
    if type(text) ~= "string" then return nil end
    local t = string.lower(text)
    t = string.gsub(t, "^%s+", "")
    t = string.gsub(t, "[%s%.!]+$", "")
    return t
end

-- Refusals that say something about the UNIT: it cannot be reached from here.
-- These mark the unit as well as the spell.
--
-- Facing and movement used to be in this list and are not conditions of the
-- UNIT at all - they are conditions of US. On a paladin who melees while
-- healing that mattered: CastOn stamps the heal target as the last unit cast,
-- and a facing error from the melee layer arriving within the blame window then
-- marked the person being healed as unreachable. Healing needs line of sight,
-- never a direction, so a facing refusal can never be about a heal target.
local CAST_REFUSED = {
    SPELL_FAILED_LINE_OF_SIGHT or "Target not in line of sight",
    SPELL_FAILED_OUT_OF_RANGE or "Out of range",
    SPELL_FAILED_TOO_CLOSE or "Target too close",
    ERR_OUT_OF_RANGE or "Out of range",
    ERR_SPELL_OUT_OF_RANGE or "You are too far away!",
    -- Observed verbatim on Turtle 1.12, where the globals above hold other
    -- wordings for the same conditions.
    "Out of range",
    "You are too far away!",
    "Target not in line of sight",
}

-- Refusals that say something about US, not about the target. These clear the
-- SPELL's throttle and nothing else - blacklisting a unit because we were out of
-- mana would stop us healing somebody who is perfectly reachable.
--
-- Mana matters here because a throttle stamped on a cast that never left is the
-- worst of both worlds: Hunter's Mark carries a 110 second one, so a single
-- unaffordable attempt used to leave the target unmarked for most of two minutes
-- - and the sting, gated on the mark, never went out either.
local CAST_REFUSED_SELF = {
    ERR_NOT_ENOUGH_MANA or "Not enough mana",
    SPELL_FAILED_NO_POWER or "Not enough mana",
    ERR_OUT_OF_RAGE or "Not enough rage",
    ERR_OUT_OF_ENERGY or "Not enough energy",
    -- Moved here from the unit list: both describe how WE are standing or
    -- moving, so they void the spell's throttle and must not blacklist anybody.
    SPELL_FAILED_UNIT_NOT_INFRONT or "You are facing the wrong way!",
    SPELL_FAILED_MOVING or "Can't do that while moving",
    ERR_BADATTACKFACING or "You are facing the wrong way!",
    "You are facing the wrong way!",
    -- Also observed verbatim on Turtle 1.12.
    "Can't do that while stunned",
    -- The client is still busy with the previous cast or channel. Measured on an
    -- arcane mage: after every Arcane Missiles channel the FIRST cast issued was
    -- thrown away and only the second, one press later, took - mana unchanged
    -- across the first, then dropping on the second, in all four cycles of a
    -- captured log. Without this entry that refusal was unrecognised, so the
    -- spell's throttle stayed stamped on a cast that never left.
    SPELL_FAILED_SPELL_IN_PROGRESS or "Another action is in progress",
}

-- Recognised, and deliberately acted on by NEITHER ledger.
--
-- A cooldown refusal does not reliably mean the cast was thrown away. Nampower
-- queues a press that arrives during a global cooldown and fires it the instant
-- the cooldown clears, so the client can answer "not ready yet" for a cast that
-- then happens anyway. Voiding the spell's throttle on that would re-send a
-- spell that is already in flight - the double cast these throttles exist to
-- prevent.
--
-- Listed all the same, so it stops arriving in the unrecognised trace below and
-- being mistaken for a refusal nobody has classified yet.
local CAST_REFUSED_IGNORED = {
    ERR_SPELL_COOLDOWN or "Spell is not ready yet",
    SPELL_FAILED_NOT_READY or "Ability is not ready yet",
    "Ability is not ready yet",
    "Spell is not ready yet",
}

-- Spells the client has just refused, by name, with the time it said so.
--
-- Separate from castBlocked above, which is about a UNIT and is used to stop
-- picking somebody unreachable. This one is about the SPELL, and exists because
-- several modules keep a "we just cast this, do not send it again" throttle -
-- which is correct after a cast that happened, and wrong after one the client
-- threw away. Hunter's Mark carries a 110 second throttle and the first Serpent
-- Sting of a session fifteen: refused once at the start of a pull, either goes
-- unapplied for that long. Reported exactly that way.
Aegis_SBR.spellRefused = {}

-- Was this spell refused at or after the moment `t` - the moment a throttle was
-- stamped? Timestamps rather than ordering, because the error and the stamp can
-- land in either order within one frame and both must give the same answer.
function Aegis_SBR:SpellRefusedSince(name, t)
    if not name or not t then return false end
    local r = self.spellRefused[name]
    return (r and r >= t) and true or false
end

-- Remember what we just sent, so an error message that names no spell can be
-- attributed to it. Called by the shared Pick/PickQueue and by the class
-- wrappers that cast directly.
function Aegis_SBR:NoteSpellCast(name)
    self.lastSpell = name
    self.lastSpellAt = GetTime()
end

function Aegis_SBR:OnCastError(msg)
    if not msg then return end
    -- Normalised on both sides: the client's "Out of range." and a global's
    -- "Out of range" are the same refusal, and exact equality answered no.
    local norm = NormErr(msg)
    if not norm then return end
    local unitRefused, selfRefused = false, false
    for i = 1, table.getn(CAST_REFUSED) do
        if norm == NormErr(CAST_REFUSED[i]) then unitRefused = true; break end
    end
    if not unitRefused then
        for i = 1, table.getn(CAST_REFUSED_SELF) do
            if norm == NormErr(CAST_REFUSED_SELF[i]) then selfRefused = true; break end
        end
    end
    if not (unitRefused or selfRefused) then
        for i = 1, table.getn(CAST_REFUSED_IGNORED) do
            if norm == NormErr(CAST_REFUSED_IGNORED[i]) then return end
        end
    end
    -- An UNRECOGNISED refusal used to return here and leave no trace anywhere:
    -- the message was dropped, and RunRotation's UIErrorsFrame:Clear() then wiped
    -- it off the screen, so neither the log nor the player ever learned why a
    -- cast did not happen. That is the failure this file warns about in its own
    -- rules - "an ability silently stops and nothing says why" - and it cost
    -- several rounds on a mage report where every first cast after a channel was
    -- being thrown away by the client.
    --
    -- It is deliberately only TRACED, not acted on. UI_ERROR_MESSAGE carries far
    -- more than cast refusals (full health, bags full, quest text), so treating
    -- every one as a refused cast would clear throttles that were correctly set.
    -- Naming the message is what lets a real one be added to a list above.
    if not (unitRefused or selfRefused) then
        if self:Tracing() and self.lastSpell
            and (GetTime() - (self.lastSpellAt or 0)) <= BLAME_WINDOW then
            self:Trace("refused? " .. tostring(self.lastSpell) .. " :: " .. tostring(msg))
        end
        return
    end
    local now = GetTime()

    -- The spell, for the throttles that must not treat a thrown-away cast as a
    -- cast that happened.
    if self.lastSpell and (now - (self.lastSpellAt or 0)) <= BLAME_WINDOW then
        self.spellRefused[self.lastSpell] = now
        self.lastSpell = nil
    end

    -- The unit, for the heal target selection. Only for refusals that are ABOUT
    -- the unit, and only while the unit cast is the LAST thing we sent.
    --
    -- The second test is what keeps somebody else's refusal off a heal target.
    -- A press casts on a unit, the rotation then sends a targetless or melee
    -- ability, and the error belongs to that second one - but the unit stamp is
    -- still standing, and without this it collected the blame. Auto-attack was
    -- the worst case: it runs before the module every press and used to leave no
    -- record at all, so its "too far away" landed on whatever came last.
    if unitRefused and self.lastUnitCast
        and (now - (self.lastUnitCastAt or 0)) <= BLAME_WINDOW
        and (self.lastUnitCastAt or 0) >= (self.lastSpellAt or 0) then
        self.castBlocked[self.lastUnitCast] = now
        -- Spent: one refusal marks one unit, so the next error cannot be blamed
        -- on the same cast.
        self.lastUnitCast = nil
    end
end

-- Cast at a unit without changing your target (SuperWoW's unit argument), and
-- report rather than cast while a preview is running.
function Aegis_SBR:CastOnUnit(spell, unit, reason)
    if Aegis_SBR.deciding then
        local p = Aegis_SBR.decidePlan
        p.spell = spell
        p.reason = reason or ("on " .. (UnitName(unit) or unit or "?"))
        return true
    end
    Aegis_SBR.pressSeq = (Aegis_SBR.pressSeq or 0) + 1
    Aegis_SBR:NoteUnitCast(unit)
    -- The SPELL as well, so OnCastError can tell whether the unit cast is still
    -- the most recent thing we sent. Without it lastSpellAt belongs to some
    -- earlier press and the comparison there is meaningless.
    Aegis_SBR:NoteSpellCast(spell)
    CastSpellByName(spell, unit)
    return true
end

-- ============================================================
-- Dispelling
-- ============================================================
-- What a unit is afflicted with, as a set of dispel types: Magic, Curse,
-- Poison, Disease.
--
-- The type is the THIRD return of UnitDebuff and has been there all along - the
-- target-debuff snapshot reads past it looking for the SuperWoW spell id. No
-- tooltip scanning and no icon list is needed for this, which is the one part of
-- dispelling 1.12 makes easy.
--
-- An empty string is a real answer here and means "not dispellable by type",
-- so it is skipped rather than stored.
function Aegis_SBR:DispelTypes(unit)
    local out = nil
    if not UnitExists(unit) then return nil end
    for i = 1, 40 do
        local tex, _, dtype = UnitDebuff(unit, i)
        if not tex then break end
        if dtype and dtype ~= "" then
            out = out or {}
            out[dtype] = true
        end
    end
    return out
end

-- How long a unit is left alone after a cure that did not take. Without it a
-- cure that cannot work - the debuff outlasted the cast, the spell was resisted,
-- the client refused it - is retried on every single press.
local CURE_RETRY = 5

-- Which affliction to remove first. Magic before Curse before Poison before
-- Disease, which is the established default order for this.
--
-- Ordered on purpose, and this drives the whole search: the first version
-- walked each spell's covered types with `pairs`, which has no defined order in
-- Lua. A paladin holding Cleanse - three types in one spell - therefore removed
-- whichever type the table happened to enumerate first, not the one that
-- mattered. Roughly: magic tends to be the crowd control and the damage
-- amplifier, disease the slow tick you can outheal.
local DISPEL_ORDER = { "Magic", "Curse", "Poison", "Disease" }

-- Pick somebody to cure and the spell to do it with.
--
-- Type first, then unit: a Magic effect anywhere in the group outranks a Poison
-- anywhere, which is how the ordering above is meant to work. Within one type
-- the group is walked in roster order.
--
-- `cures` is the class's list, each { spell = ..., types = { Poison = true } };
-- for a given affliction the first entry that covers it AND is trained wins, so
-- a class lists its better spell first (Abolish before Cure, Cleanse before
-- Purify). `units` is the class's own group list, `reach` an optional "can I
-- reach this unit" test.
--
-- Returns unit, spell, type. Nothing is cast here.
function Aegis_SBR:PickCure(units, cures, reach, blacklist)
    -- Which spell, if any, answers each affliction. Resolved once instead of
    -- inside the unit loop.
    local spellFor = {}
    local anySpell = false
    for oi = 1, table.getn(DISPEL_ORDER) do
        local want = DISPEL_ORDER[oi]
        for c = 1, table.getn(cures) do
            local e = cures[c]
            if e.types[want] and self:KnowsSpell(e.spell) then
                spellFor[want] = e.spell
                anySpell = true
                break
            end
        end
    end
    if not anySpell then return nil, nil, nil end

    -- Each unit's afflictions, read ONCE.
    --
    -- This loop used to sit inside the type loop, so a forty-man raid cost four
    -- passes over forty members at up to forty debuff slots each - better than
    -- six thousand UnitDebuff calls per press, four times a second. Invisible in
    -- a five-man and ruinous in a raid, which is exactly how it was found.
    local order, seen = {}, 0
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsFriend("player", u)
            and (not reach or reach(u)) then
            local nm = UnitName(u)
            local bl = blacklist and nm and blacklist[nm]
            if not (bl and (GetTime() - bl) < CURE_RETRY) then
                local types = self:DispelTypes(u)
                if types then
                    seen = seen + 1
                    order[seen] = { unit = u, types = types, charmed = UnitIsCharmed(u) }
                end
            end
        end
    end
    if seen == 0 then return nil, nil, nil end

    -- Type first, then unit: a Magic effect anywhere in the group outranks a
    -- Poison anywhere. Within one type the units keep the order they arrived in,
    -- which is where a class's priority list has already had its say.
    for oi = 1, table.getn(DISPEL_ORDER) do
        local want = DISPEL_ORDER[oi]
        local spell = spellFor[want]
        if spell then
            for i = 1, seen do
                local e = order[i]
                -- Never strip Magic off a charmed ally: the charm itself IS the
                -- magic, and removing it is the one dispel that hands the mob
                -- its damage dealer back.
                local charmSafe = (want ~= "Magic") or not e.charmed
                if e.types[want] and charmSafe then return e.unit, spell, want end
            end
        end
    end
    return nil, nil, nil
end

function Aegis_SBR:ManaPct()
    local mx = UnitManaMax("player")
    if mx and mx > 0 then return UnitMana("player") / mx * 100 end
    return 100
end

function Aegis_SBR:PlayerHPPct()
    local mx = UnitHealthMax("player")
    if mx and mx > 0 then return UnitHealth("player") / mx * 100 end
    return 100
end

function Aegis_SBR:TargetHPPct()
    local mx = UnitHealthMax("target")
    if mx and mx > 0 then return UnitHealth("target") / mx * 100 end
    return 100
end

-- ============================================================
-- Temporary weapon-enchant detection (SuperWoW / vanilla).
-- GetWeaponEnchantInfo returns, per hand: present flag, time remaining in
-- MILLISECONDS, charges, enchant id. slot is "main" or "off". Returns
-- has, msRemaining, charges (all nil/false when no SuperWoW or no enchant).
-- Read live every call on purpose: msRemaining is a running countdown, so a
-- cached-until-UNIT_INVENTORY_CHANGED value would report stale time-left.
-- Confirmed on Turtle 1.12 (2026-07-19): has=1, ms counts down, charges=0 for
-- a time-based enchant -- so gate upkeep on has/ms, NOT on charges.
-- ============================================================
function Aegis_SBR:WeaponEnchant(slot)
    if not GetWeaponEnchantInfo then return false, nil, nil end
    -- Six return values on 1.12, not seven: there is no enchant-id slot between
    -- the hands on this client. Reading a seventh put hasOH on the off-hand
    -- EXPIRATION, so WeaponEnchant("off") returned nonsense. Latent until now,
    -- because the only caller asks for the main hand, where both readings agree.
    -- The six-value form is the one Aegis_SBR_BuffUp uses and its charge counts
    -- are confirmed correct in game.
    local hasMH, mhMs, mhCh, hasOH, ohMs, ohCh = GetWeaponEnchantInfo()
    if slot == "off" then return (hasOH and true or false), ohMs, ohCh end
    return (hasMH and true or false), mhMs, mhCh
end

-- Optional identity: the enchant ID on a hand ("main"/"off"), or nil. Gated
-- separately on GetWeaponEnchantID (SuperWoW 2.1), which returns mh, oh.
-- Confirmed on Turtle 1.12 (2026-07-19): returns a small integer / nil.
function Aegis_SBR:WeaponEnchantId(slot)
    if not GetWeaponEnchantID then return nil end
    local mh, oh = GetWeaponEnchantID("player")
    if slot == "off" then return oh end
    return mh
end

-- The Attack action's bar slot is cached: one IsAttackAction call verifies it
-- each press, and the full 1..172 scan only runs when the cache is empty or
-- the button was moved/removed.
function Aegis_SBR:EnsureAutoAttack()
    local slot = self.attackSlot
    if not (slot and IsAttackAction(slot)) then
        slot = nil
        for z = 1, 172 do
            if IsAttackAction(z) then slot = z; break end
        end
        self.attackSlot = slot
    end
    if slot then
        -- Attack is on a bar: toggle it only when not already swinging, so this
        -- is a no-op if SCRM (or the player) already started the swing.
        if not IsCurrentAction(slot) then
            -- Recorded, because the client answers this with the same "too far
            -- away" and "facing the wrong way" a spell gets, and this runs
            -- BEFORE the module every press. Unrecorded, those errors landed on
            -- whatever spell happened to be last - in one log fourteen of them
            -- on Seal of Wisdom, a self buff that can be neither.
            -- "Attack" is not a spell any throttle is keyed on, so blaming it
            -- costs nothing and keeps the blame off something real.
            self:NoteSpellCast("Attack")
            UseAction(slot)
        end
    elseif AttackTarget then
        -- No Attack on any bar (common on Warriors who never place it, and on
        -- anyone running SuperCleveRoidMacros, which drives the swing with
        -- /startattack so the button never needs slotting).
        --
        -- AttackTarget() is a TOGGLE on 1.12 - it STOPS the swing when one is
        -- already running, and there is no /startattack equivalent in the Lua
        -- API (that arrived in 2.0). With no slot there is also nothing to read
        -- IsCurrentAction from, so the state cannot be checked first. Calling it
        -- every press therefore flipped auto-attack off as often as on, which is
        -- exactly what spamming the macro looked like in game.
        --
        -- Fired at most once per target instead: enough to open the swing on a
        -- fresh target, never enough to flip-flop under spam. If something else
        -- stops the swing later we deliberately do NOT retry, because from here
        -- "not swinging" and "swinging" are indistinguishable - a blind retry is
        -- the bug being removed. Put Attack on a bar (any slot the stance/form
        -- bar does not overwrite) to get the guarded path above, which can read
        -- the state and restart the swing whenever it actually drops.
        local id = self:TargetId()
        if id ~= self.attackToggledFor then
            self.attackToggledFor = id
            self:NoteSpellCast("Attack")
            AttackTarget()
        end
    end
end

-- A stable id for the current target. SuperWoW returns the GUID as the second
-- value of UnitExists, which lets us tell apart two mobs that share a name.
function Aegis_SBR:TargetId()
    local _, guid = UnitExists("target")
    if guid then return guid end
    return UnitName("target") or ""
end

-- ============================================================
-- Time to kill (TTK)
-- How long the current target has left, in seconds, from how fast its health
-- is actually falling. Two rotation problems need it and neither can be solved
-- with a health PERCENTAGE alone: spending combo points before the mob dies
-- (5 CP at 20% is worth dumping on a dying trash mob and worth holding on a
-- boss), and not re-applying a DoT or a buff that will outlive the fight.
--
-- Percent per second, not damage per second: TargetHPPct is a ratio, so no
-- absolute health value is needed and the estimate works on mobs whose max
-- health we cannot read. It also means the number is directly comparable
-- across a level 4 boar and a raid boss.
--
-- Deliberately a plain rolling window rather than the recursive least squares
-- the TimeToKill addon uses. RLS earns its keep over a multi-minute boss with
-- phase changes; here the consumer only ever asks "less than a few seconds?",
-- a question a short window answers just as well and with no tuning constants
-- to get wrong.
--
-- TargetTTK returns nil, never a guess, until it has enough history. Every
-- consumer must treat nil as "not dying soon" - the same rule DotRemaining
-- follows, so an unknown can never suppress an ability.
-- ============================================================
local TTK_WINDOW   = 8      -- seconds of history kept
local TTK_MIN_SPAN = 3      -- seconds of history needed before answering
local TTK_MIN_STEP = 0.3    -- shortest gap between two samples
local TTK_MIN_N    = 4      -- samples needed before answering

function Aegis_SBR:ResetTTK()
    self.ttkId = nil
    self.ttkN  = 0
    self.ttkT  = {}
    self.ttkH  = {}
end

-- Called once per press from RunRotation, which is the only place that reliably
-- fires while a fight is happening (there is no combat tick to hang this on).
-- Presses arrive at roughly the GCD, so the window holds about eight samples.
function Aegis_SBR:SampleTTK()
    local id  = self:TargetId()
    local now = GetTime()
    local hp  = self:TargetHPPct()
    if id ~= self.ttkId then self:ResetTTK(); self.ttkId = id end
    local n = self.ttkN or 0
    if n > 0 and (now - self.ttkT[n]) < TTK_MIN_STEP then return end
    -- Health going UP is never part of a kill curve: the mob was healed, or a
    -- different mob is reusing the id (the name fallback, when SuperWoW GUIDs
    -- are unavailable). Either way the stored samples describe a fight that is
    -- no longer happening, so start over rather than average across the jump.
    -- One percent of slack absorbs a mob's own health regeneration.
    if n > 0 and hp > self.ttkH[n] + 1 then
        n = 0
        self.ttkT = {}
        self.ttkH = {}
    end
    n = n + 1
    self.ttkT[n] = now
    self.ttkH[n] = hp
    -- Drop samples older than the window by shifting the rest down. n is single
    -- digits, so the copy costs nothing and avoids a wrapping ring index.
    local cut, first = now - TTK_WINDOW, 1
    while first < n and self.ttkT[first] < cut do first = first + 1 end
    if first > 1 then
        local k = 0
        for i = first, n do
            k = k + 1
            self.ttkT[k] = self.ttkT[i]
            self.ttkH[k] = self.ttkH[i]
        end
        for i = k + 1, n do self.ttkT[i] = nil; self.ttkH[i] = nil end
        n = k
    end
    self.ttkN = n
end

-- Seconds until the current target dies, or nil when it cannot be estimated
-- (too little history, or the target is not losing health).
function Aegis_SBR:TargetTTK()
    if not UnitExists("target") then return nil end
    if self:TargetId() ~= self.ttkId then return nil end
    local n = self.ttkN or 0
    if n < TTK_MIN_N then return nil end
    local span = self.ttkT[n] - self.ttkT[1]
    if span < TTK_MIN_SPAN then return nil end
    local drop = self.ttkH[1] - self.ttkH[n]
    if drop <= 0 then return nil end
    local hp = self:TargetHPPct()
    if hp <= 0 then return 0 end
    return hp / (drop / span)
end

-- "Will the target be dead within sec seconds?" The one form call sites should
-- use, because it answers false for an unknown TTK rather than making every
-- caller remember to nil-check.
function Aegis_SBR:TTKBelow(sec)
    if not sec or sec <= 0 then return false end
    local ttk = self:TargetTTK()
    if not ttk then return false end
    return ttk < sec
end

-- Best effort melee proximity. CheckInteractDistance index 3 is about 9.9
-- yards, a practical proxy for "close enough to fight". Used only to decide
-- whether we are still running in, so we can pre-cast the seal on the way.
--
-- NOTE (2026-08-18): a ClassicAPI version of this - probing a real melee
-- ability through C_Spell.IsSpellInRange, so the target's bounding radius
-- counts - was reverted after a Hunter regression report (ranged attack stopped
-- while in ranged mode). Cause not yet identified; do not re-apply without a
-- reproduction. See docs/research-classicapi.md.
-- CheckInteractDistance's smallest index is 3, the duel distance, and that is
-- about 9.9 yards - roughly twice the reach of a melee ability. Everything
-- gated on this therefore fired from too far out: in a captured tank log, 42 of
-- the 46 distance refusals the client sent arrived on a press where this
-- answered yes, and auto-attack is gated on it too.
--
-- A plain distance threshold cannot replace it. Our two distance sources do not
-- measure the same thing (see Aegis_SBR_Range.lua): ClassicAPI measures centre
-- to centre, UnitXP_SP3 adjusts for the hitbox. Melee reach is five yards plus
-- the target's radius, so a fixed five-yard cut against a centre-to-centre
-- number would report "not in melee" while standing inside a large mob - a
-- worse failure than the one being fixed, and on exactly the boss fights where
-- it matters most.
--
-- So the client is asked instead, about a real ability: IsSpellInRange knows
-- both the ability's reach and the target's radius, and it is the same
-- arithmetic behind the refusal message. A module opts in by defining
-- MeleeProbe; one that does not keeps exactly today's behaviour, which is also
-- what happens without ClassicAPI or when the call cannot judge.
--
-- Answered once per press: the paladin alone reaches this from ten places.
function Aegis_SBR:InMeleeRange()
    if not UnitExists("target") then return false end
    local tok = self.pressToken
    if tok and self.meleeTok == tok and self.meleeAns ~= nil then return self.meleeAns end

    local ans = nil
    local probe = self.active and self.active.MeleeProbe and self.active:MeleeProbe()
    if probe and IsSpellInRange then
        -- pcall for the same reason SpellReaches uses one: an unresolvable name
        -- throws rather than answering -1, and a throw aborts the whole press.
        local ok, r = pcall(IsSpellInRange, probe, "target")
        if ok and r == 1 then ans = true
        elseif ok and r == 0 then ans = false end
    end
    if ans == nil then ans = CheckInteractDistance("target", 3) and true or false end

    if tok then self.meleeTok, self.meleeAns = tok, ans end
    return ans
end

function Aegis_SBR:Throttle(text)
    local now = GetTime()
    if (now - (self.lastMsg or 0)) > 3 then
        DEFAULT_CHAT_FRAME:AddMessage("Aegis: " .. text, 1, 0.5, 0.3)
        self.lastMsg = now
    end
end

-- ============================================================
-- Talent dump: prints every talent's exact GetTalentInfo name and rank, tab by
-- tab. Used to verify the strings the class modules match against (e.g. the
-- paladin's "Vengeful Strikes"/"Righteous Strikes"), since a one-character
-- mismatch makes a talent read as rank 0.
-- ============================================================
function Aegis_SBR:Talents()
    DEFAULT_CHAT_FRAME:AddMessage("--- Aegis talents ---", 1, 0.8, 0.0)
    local tabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    if tabs == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("no talent API available.", 1, 0.5, 0.3)
        return
    end
    for tab = 1, tabs do
        local tabName = GetTalentTabInfo and GetTalentTabInfo(tab) or ("Tab " .. tab)
        DEFAULT_CHAT_FRAME:AddMessage(tab .. " - " .. (tabName or ("Tab " .. tab)) .. ":", 1, 0.82, 0.0)
        for i = 1, GetNumTalents(tab) do
            local n, _, _, _, rank = GetTalentInfo(tab, i)
            if n then
                local r = rank or 0
                DEFAULT_CHAT_FRAME:AddMessage("    " .. n .. "  (" .. r .. ")",
                    (r > 0 and 0.6 or 0.7), (r > 0 and 1 or 0.7), (r > 0 and 0.6 or 0.7))
            end
        end
    end
end

-- ============================================================
-- Debug dump
-- ============================================================
function Aegis_SBR:Debug()
    DEFAULT_CHAT_FRAME:AddMessage("--- Aegis debug ---", 1, 0.8, 0.0)
    if UnitExists("target") then
        DEFAULT_CHAT_FRAME:AddMessage("Target debuffs (name / stacks / texture):", 1, 0.8, 0.0)
        local any = false
        for i = 1, 40 do
            local t, stacks, d3, d4, d5 = UnitDebuff("target", i)
            if not t then break end
            any = true
            local id
            if type(d3) == "number" then id = d3
            elseif type(d4) == "number" then id = d4
            elseif type(d5) == "number" then id = d5 end
            local nm = "?"
            if id and SpellInfo then
                if id < -1 then id = id + 65536 end
                nm = SpellInfo(id) or "?"
            end
            DEFAULT_CHAT_FRAME:AddMessage("  [" .. i .. "] " .. nm .. " / " .. (stacks or 0) .. " / " .. t)
        end
        if not any then DEFAULT_CHAT_FRAME:AddMessage("  (none)") end
        -- TTK only fills while the rotation button is being pressed, so a debug
        -- run on a fresh target legitimately reports "unknown".
        local ttk = self:TargetTTK()
        DEFAULT_CHAT_FRAME:AddMessage("Time to kill: "
            .. (ttk and (string.format("%.1f", ttk) .. "s") or "unknown")
            .. " (" .. (self.ttkN or 0) .. " samples)", 1, 0.8, 0.0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("No target.", 1, 0.5, 0.5)
    end
    DEFAULT_CHAT_FRAME:AddMessage("Player buffs (name / time / stacks):", 1, 0.8, 0.0)
    if GetPlayerBuff then
        for i = 0, 31 do
            local ix = GetPlayerBuff(i, "HELPFUL")
            if ix and ix ~= -1 then
                local id = GetPlayerBuffID and GetPlayerBuffID(ix)
                local nm = "?"
                if id then
                    if id < -1 then id = id + 65536 end
                    if SpellInfo then nm = SpellInfo(id) or "?" end
                end
                local tl = GetPlayerBuffTimeLeft(ix) or 0
                local st = (GetPlayerBuffApplications and GetPlayerBuffApplications(ix)) or 1
                DEFAULT_CHAT_FRAME:AddMessage("  " .. nm .. " / " .. string.format("%.0f", tl) .. "s / " .. st)
            end
        end
    end
end

function Aegis_SBR:Tokenize(msg)
    local t = {}
    for w in string.gfind(msg or "", "%S+") do table.insert(t, w) end
    return t
end

-- Re-join tokens from index i onwards with single spaces. Needed wherever an
-- argument is a SPELL NAME: "Serpent Sting" tokenizes into two words, and the
-- t[2]-style reads used by the other commands would silently keep only the
-- first. Returns "" when there is nothing from i onwards.
function Aegis_SBR:JoinFrom(t, i)
    local out = ""
    for k = i, table.getn(t) do
        if out == "" then out = t[k] else out = out .. " " .. t[k] end
    end
    return out
end

-- Resolve an on/off command argument against the value it is changing.
--   (no argument) -> toggle, matching /sbr aoe and the other bare commands,
--                    which is what a keybind needs: one binding, both ways.
--   on / off      -> set absolutely, so a macro that passes one stays
--                    idempotent however often it fires.
--   anything else -> nil, so the caller can print usage and change NOTHING.
-- That last case is the bug this replaces: the old `(onoff or "") == "on"` sent
-- every unrecognised argument to FALSE, so both a bare `/sbr spell mark` and a
-- typo like `/sbr spell mark of` silently DISABLED the spell you were trying to
-- turn on, and reported it as though you had asked for that.
--
-- Callers must test the result with `== nil`, never `if not v` - false is a
-- legitimate return here and would otherwise be mistaken for the error case.
function Aegis_SBR:ToggleArg(current, arg)
    local a = string.lower(arg or "")
    if a == "" then return not current end
    if a == "on" then return true end
    if a == "off" then return false end
    return nil
end

-- Turn a config key into something worth printing: "useHuntersMark" -> "Hunters
-- Mark". Derived rather than kept in a lookup table because there are 47 spell
-- toggles across the three classes that have the command, and a table would be
-- one more place to forget when an ability is added. gsub (not match/gmatch,
-- which 5.0 lacks) is assigned to a local first so its second return, the
-- replacement count, cannot leak into a concatenation at the call site.
function Aegis_SBR:SpellLabel(key)
    local s = string.gsub(key or "", "^use", "")
    s = string.gsub(s, "(%l)(%u)", "%1 %2")
    if s == "" then return key or "" end
    -- Explicit sub/upper rather than a gsub with a function replacement: the
    -- paladin's keys carry no "use" prefix ("holyStrike"), so they arrive here
    -- starting lowercase and need capitalising, and this form does not depend on
    -- 5.0 accepting a function as the replacement argument.
    return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- ============================================================
-- Saved variables and profiles (generic, schema comes from the module)
-- ============================================================
function Aegis_SBR:DeepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = self:DeepCopy(v) end
    return r
end

-- A full copy of a profile, then normalized by the active module. Every UI
-- save/activate commits through here, so the cached validity is dropped.
function Aegis_SBR:CopyProfile(p)
    self.validCacheName = nil
    local c = self:DeepCopy(p)
    if self.active and self.active.NormalizeProfile then self.active:NormalizeProfile(c) end
    return c
end

function Aegis_SBR:InitDB()
    if type(AegisDB) ~= "table" then AegisDB = {} end
    if type(AegisDB.profiles) ~= "table" then AegisDB.profiles = {} end
    if not self.active or not self.active.templates then return end
    if not next(AegisDB.profiles) then
        for name, tpl in pairs(self.active.templates) do
            AegisDB.profiles[name] = self:CopyProfile(tpl)
        end
    end
    -- migrate any already-stored profiles to the current format
    for _, cfg in pairs(AegisDB.profiles) do self.active:NormalizeProfile(cfg) end
end

function Aegis_SBR:GetActiveProfile()
    if not AegisDB or not AegisDB.active then return nil end
    return AegisDB.profiles[AegisDB.active]
end

-- Validity is a class rule. Without a module nothing is missing.
function Aegis_SBR:Validity(cfg)
    if self.active and self.active.ProfileValidity then return self.active:ProfileValidity(cfg) end
    return true, {}
end

-- ============================================================
-- Generic profile commands (the text interface, UI is primary)
-- ============================================================
function Aegis_SBR:CmdList()
    msgOut("Profiles:")
    local active = AegisDB.active
    local any = false
    for name, cfg in pairs(AegisDB.profiles) do
        any = true
        local ok, missing = self:Validity(cfg)
        local mark = (name == active) and " [active]" or ""
        local valid = ok and "valid" or ("INVALID, missing " .. table.concat(missing, ", "))
        msgOut("  " .. name .. mark .. " - " .. valid)
    end
    if not any then msgOut("  (none, use /sbr reset)") end
    if not active then msgOut("No profile is active.") end
end

function Aegis_SBR:CmdUse(name)
    local cfg = name and AegisDB.profiles[name]
    if not cfg then msgOut("profile '" .. tostring(name) .. "' not found.", 1, 0.5, 0.3); return end
    local ok, missing = self:Validity(cfg)
    if not ok then msgOut("cannot activate '" .. name .. "', missing " .. table.concat(missing, ", "), 1, 0.5, 0.3); return end
    AegisDB.active = name
    msgOut("activated '" .. name .. "'.")
end

function Aegis_SBR:CmdOff()
    AegisDB.active = nil
    msgOut("deactivated. No profile active.")
end

function Aegis_SBR:CmdNew(name, template)
    if not self.active or not self.active.templates then msgOut("no class module loaded.", 1, 0.5, 0.3); return end
    if not name then msgOut("usage: /sbr new <name> [template]", 1, 0.5, 0.3); return end
    if AegisDB.profiles[name] then msgOut("'" .. name .. "' already exists.", 1, 0.5, 0.3); return end
    if template == "" then template = nil end   -- the dispatcher lowercases t[3] or "", so a missing arg arrives as ""
    local tpl = self.active.templates[template or "starter"]
    if not tpl then msgOut("unknown template '" .. tostring(template) .. "'.", 1, 0.5, 0.3); return end
    AegisDB.profiles[name] = self:CopyProfile(tpl)
    msgOut("created '" .. name .. "' from template '" .. (template or "starter") .. "'.")
end

function Aegis_SBR:CmdDel(name)
    if not name or not AegisDB.profiles[name] then msgOut("profile not found.", 1, 0.5, 0.3); return end
    AegisDB.profiles[name] = nil
    if AegisDB.active == name then AegisDB.active = nil end
    msgOut("deleted '" .. name .. "'.")
end

function Aegis_SBR:CmdCheck()
    local cfg = self:GetActiveProfile()
    if not cfg then msgOut("no profile active."); return end
    local ok, missing = self:Validity(cfg)
    if ok then msgOut("active profile '" .. AegisDB.active .. "' is valid.")
    else msgOut("active profile invalid, missing " .. table.concat(missing, ", "), 1, 0.5, 0.3) end
end

function Aegis_SBR:CmdReset()
    if not self.active or not self.active.templates then msgOut("no class module loaded.", 1, 0.5, 0.3); return end
    AegisDB.profiles = {}
    for n, tpl in pairs(self.active.templates) do AegisDB.profiles[n] = self:CopyProfile(tpl) end
    AegisDB.active = nil
    msgOut("profile list reseeded from templates, nothing active.")
end

-- ============================================================
-- Rotation entry point
-- ============================================================
-- Targeting mode: three-way, mutually exclusive.
--   "auto"   - acquire the nearest enemy when you have none (the old default).
--   "manual" - never touch targeting; defer to you or a separate assist addon.
--   "assist" - continuously mirror AegisDB.assistTarget's current target.
-- Migrated transparently from the older acquire boolean (true/nil -> "auto",
-- false -> "manual") the first time this is read after upgrading.
-- ============================================================
function Aegis_SBR:TargetMode()
    if type(AegisDB) ~= "table" then return "auto" end
    local m = AegisDB.targetMode
    if m == "auto" or m == "manual" or m == "assist" then return m end
    local migrated = (AegisDB.acquire == false) and "manual" or "auto"
    AegisDB.targetMode = migrated
    return migrated
end

-- /sbr acquire on|off|assist <name> - set targeting mode (also on the minimap
-- right-click). "on"/"auto" and "off"/"manual"/"defer" keep their old
-- meaning; "assist <name>" is new and requires a party/raid member's name.
function Aegis_SBR:CmdAcquire(arg, arg2)
    local low = string.lower(arg or "")
    if low == "" then
        local mode = self:TargetMode()
        local desc = mode == "auto" and "auto (acquires nearest enemy)"
            or mode == "assist" and ("assist (mirrors " .. ((AegisDB and AegisDB.assistTarget) or "?") .. ")")
            or "manual (defers to you or an assist addon)"
        msgOut("targeting mode is " .. desc .. ". Use /sbr acquire on, off, or assist <name>.")
        return
    end
    if low == "on" or low == "self" or low == "auto" then
        if AegisDB then AegisDB.targetMode = "auto" end
        msgOut("targeting mode: auto. Aegis acquires the nearest enemy when it has no target.")
    elseif low == "off" or low == "manual" or low == "defer" then
        if AegisDB then AegisDB.targetMode = "manual" end
        msgOut("targeting mode: manual. Aegis leaves targeting to you or your assist addon.")
    elseif low == "assist" then
        if not arg2 or arg2 == "" then
            msgOut("usage: /sbr acquire assist <party/raid member name>.", 1, 0.5, 0.3)
            return
        end
        if AegisDB then
            AegisDB.targetMode = "assist"
            AegisDB.assistTarget = arg2
        end
        msgOut("targeting mode: assist. Mirroring " .. arg2 .. "'s target.")
    else
        msgOut("usage: /sbr acquire on or /sbr acquire off or /sbr acquire assist <name>.", 1, 0.5, 0.3)
    end
end

-- Resolve a party/raid member's unit id by exact (case-insensitive) name.
-- Raid members are only enumerable while actually in a raid; a solo party
-- falls back to partyN + the player.
function Aegis_SBR:FindGroupUnitByName(name)
    if not name or name == "" then return nil end
    local want = string.lower(name)
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local n = UnitName("raid" .. i)
            if n and string.lower(n) == want then return "raid" .. i end
        end
        return nil
    end
    local pn = UnitName("player")
    if pn and string.lower(pn) == want then return "player" end
    for i = 1, 4 do
        local n = UnitName("party" .. i)
        if n and string.lower(n) == want then return "party" .. i end
    end
    return nil
end

-- Continuously mirror AegisDB.assistTarget's current target, matched by
-- GUID only. Name-only matching cannot tell two different mobs with the same
-- name apart (e.g. one tapped by a different nearby group), which in
-- practice meant silently attacking the wrong group's mob without ever
-- noticing - SuperWoW's GUID-aware UnitExists/TargetUnit avoids that
-- entirely by re-resolving the assist target's live target every call.
function Aegis_SBR:RunAssist()
    local name = AegisDB and AegisDB.assistTarget
    if not name or name == "" then return end
    local unit = self:FindGroupUnitByName(name)
    if not unit then
        self:Throttle("assist target '" .. name .. "' is not in your group.")
        return
    end
    local _, theirGUID = UnitExists(unit .. "target")
    if not theirGUID then
        -- They have no target: drop any stale target of our own rather than
        -- keep fighting whatever we had selected before they cleared theirs.
        if UnitExists("target") then ClearTarget() end
        return
    end
    if UnitIsDead(unit .. "target") or not UnitCanAttack("player", unit .. "target") then
        return
    end
    local _, myGUID = UnitExists("target")
    if myGUID ~= theirGUID then
        TargetUnit(theirGUID)
    end
end

-- ============================================================
-- Performance sampling
-- ============================================================
-- How long OUR rotation takes per press, and what the frame rate is doing
-- around it. Written into the probe log, so the answer comes out of a raid you
-- were going to run anyway - reproducing a forty-man group to test something is
-- not a thing anybody can do on request.
--
-- debugprofilestart/stop are millisecond timers the client provides; where they
-- are missing the sampler simply reports frame rate and press count, which still
-- separates "the addon is slow" from "everything is slow".
--
-- One line every five seconds, so a whole raid night is a few hundred lines.
local PERF_REPORT = 5
-- A token that changes once per press.
--
-- Several rotation questions are expensive and get asked more than once in the
-- same press by different steps - the paladin asks "who is worst hurt" up to six
-- times, and each answer walks the whole group reading health, range and
-- handicaps. In a forty-man raid that is the same costly loop several times over
-- for an answer that cannot have changed in between.
--
-- Bumped where the rotation is invoked rather than where a cast happens, because
-- what has to be identified is the PRESS, not the outcome.
function Aegis_SBR:NewPress()
    self.pressToken = (self.pressToken or 0) + 1
end

function Aegis_SBR:PerfStart()
    if not self:ProbeEnabled() then return end
    if debugprofilestart then debugprofilestart() end
    self.perfOn = true
end

function Aegis_SBR:PerfStop()
    if not self.perfOn then return end
    self.perfOn = false
    local ms = debugprofilestop and debugprofilestop() or nil

    self.perfN = (self.perfN or 0) + 1
    if ms then
        self.perfSum = (self.perfSum or 0) + ms
        if not self.perfMax or ms > self.perfMax then self.perfMax = ms end
    end

    local now = GetTime()
    if not self.perfT then self.perfT = now; return end
    if (now - self.perfT) < PERF_REPORT then return end

    local span = now - self.perfT
    local fps = GetFramerate and GetFramerate() or 0
    local n = self.perfN or 0
    local nr = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local np = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    self:ProbeWrite("perf", string.format(
        "fps=%.0f presses=%d (%.1f/s) rot_avg=%s rot_max=%s group=%d",
        fps, n, n / span,
        self.perfSum and string.format("%.2fms", self.perfSum / n) or "?",
        self.perfMax and string.format("%.2fms", self.perfMax) or "?",
        (nr > 0) and nr or (np + 1)))

    self.perfT = now
    self.perfN = 0
    self.perfSum = nil
    self.perfMax = nil
end

function Aegis_SBR:RunRotation()
    if not self.active then self:Throttle("no module for your class yet."); return end
    local cfg = self:GetActiveProfile()
    if not cfg then
        self:Throttle("no profile active. Open /sbr ui or use /sbr use <name>.")
        return
    end
    -- Validity is cached per active profile, not recomputed every press: it only
    -- changes when a spell is learned (SPELLS_CHANGED clears it) or the active
    -- profile switches/saves (those paths clear it too).
    if self.validCacheName ~= AegisDB.active then
        local ok, missing = self:Validity(cfg)
        self.validCacheName = AegisDB.active
        self.validCacheOK = ok
        self.validCacheMissing = missing
    end
    if not self.validCacheOK then
        self:Throttle("active profile incomplete, missing " .. table.concat(self.validCacheMissing, ", ") .. ". Running with what is available.")
    end

    -- Support modules (e.g. the paladin heal mode) may run without an attackable
    -- target and must not be forced to grab one.
    local supportRun = self.active.RunsWithoutTarget and self.active:RunsWithoutTarget(cfg)

    -- Targeting: three mutually exclusive modes (see TargetMode). "assist"
    -- actively mirrors a chosen group/raid member's target every press, even
    -- while you already have some target selected, so it runs unconditionally
    -- here rather than only when you have none. "auto" only ever grabs when
    -- you have nothing, behind the same per-module opt-out as before
    -- (autoAcquireTarget == false, e.g. the Hunter, so a ranged class never
    -- grabs and pulls a random mob). "manual" defers entirely, only dropping
    -- a corpse so a separate assist addon can reassign you.
    local mode = self:TargetMode()
    if mode == "assist" then
        -- Unlike "auto" below, mirroring an ally's existing target is never a
        -- fresh pull, so it runs for support modules (e.g. the paladin heal
        -- mode) too - that's what lets a melee-holy healer's strike weaving
        -- (which needs an actual target) follow the tank hands-free.
        self:RunAssist()
    elseif not UnitExists("target") or UnitIsDead("target") then
        if mode == "auto" and self.active.autoAcquireTarget ~= false and not supportRun then
            TargetNearestEnemy()
        elseif UnitExists("target") and UnitIsDead("target") then
            ClearTarget()
        end
    end

    local hasEnemy = UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
    if not hasEnemy then
        -- No attackable target: a support module still runs (to heal); others hold.
        if supportRun then
            self:SnapshotBuffs()
            self:SnapshotTargetDebuffs()
            self:NewPress()
            self:PerfStart()
            self.active:Rotate(cfg)
            self:PerfStop()
            UIErrorsFrame:Clear()
        elseif self.active.Prebuff then
            -- Everything a module can honestly do with nobody targeted: self
            -- buffs it wants up before contact. Deliberately a SEPARATE hook
            -- from RunsWithoutTarget, which also decides whether auto-acquire
            -- fires - answering "yes, run me" there would stop a melee class
            -- picking up a target at all.
            self:SnapshotBuffs()
            self.active:Prebuff(cfg)
            UIErrorsFrame:Clear()
        end
        return
    end

    -- Bumped here rather than just before Rotate, because the melee-range test
    -- below is now memoised per press and the auto-attack gate is its first
    -- caller. Under the old order that call answered from the PREVIOUS press.
    self:NewPress()

    -- Keep the white swing going for melee classes. Runs whether or not
    -- SuperCleveRoidMacros is loaded: EnsureAutoAttack only toggles Attack when
    -- you are not already swinging, so it is a no-op if SCRM (or anything else)
    -- already started it. Gated on melee range so an accidentally targeted far
    -- enemy never starts a swing (no stray pull). meleeAutoAttack == false (e.g.
    -- the Druid) opts out and manages its own swing in the module.
    if self.active.meleeAutoAttack ~= false and self:InMeleeRange() then self:EnsureAutoAttack() end

    self:SnapshotBuffs()
    self:SnapshotTargetDebuffs()
    self:SampleTTK()
    -- Probe log: combo points are read BEFORE the rotation runs, because a
    -- finisher spends them and the cast event arrives with the counter already
    -- at zero. No-op unless the probe log is enabled.
    if self.ProbeNoteCombo then self:ProbeNoteCombo() end
    self:PerfStart()
    self.active:Rotate(cfg)
    self:PerfStop()
    UIErrorsFrame:Clear()
end

-- ============================================================
-- Command dispatch
-- ============================================================
function Aegis_SBR:EvalCommand(msg)
    local t = self:Tokenize(msg)
    local cmd = string.lower(t[1] or "")

    if cmd == "" then self:RunRotation(); return end
    if cmd == "list"  then self:CmdList(); return end
    if cmd == "use"   then self:CmdUse(t[2]); return end
    if cmd == "off" or cmd == "none" then self:CmdOff(); return end
    if cmd == "new"   then self:CmdNew(t[2], string.lower(t[3] or "")); return end
    if cmd == "del" or cmd == "delete" then self:CmdDel(t[2]); return end
    if cmd == "check" then self:CmdCheck(); return end
    if cmd == "reset" then self:CmdReset(); return end
    if cmd == "acquire" then self:CmdAcquire(t[2], t[3]); return end
    -- Range readout: distance to the target plus a melee / ranged / out band.
    -- Also reachable from the minimap button's right-click panel.
    if cmd == "range" then
        if not Aegis_SBR_Range then
            msgOut("range window module not loaded.", 1, 0.5, 0.3)
            return
        end
        local sub = string.lower(t[2] or "")
        if sub == "reset" then
            Aegis_SBR_Range:Reset()
            msgOut("range window: calibration, position and size reset.")
            return
        end
        if sub == "scale" then
            local n = tonumber(t[3])
            if not n then
                msgOut("usage: /sbr range scale <0.3-2.0>  (currently "
                    .. string.format("%.2f", Aegis_SBR_Range:Scale()) .. ")", 1, 0.7, 0.3)
                return
            end
            Aegis_SBR_Range:Build()
            Aegis_SBR_Range:ApplyScale(n)
            msgOut("range window scale " .. string.format("%.2f", Aegis_SBR_Range:Scale()) .. ".")
            return
        end
        local on = Aegis_SBR_Range:Toggle()
        msgOut("range window " .. (on and "shown" or "hidden") .. ".")
        if on and not self:HasClassicAPI() then
            msgOut("without ClassicAPI the bands use flat thresholds (marked with a dot).", 0.8, 0.8, 0.8)
        end
        return
    end
    -- Passive probe log: collects ClassicAPI verification data while playing,
    -- so nothing has to be measured by hand mid-group.
    if cmd == "probe" then
        if self.CmdProbe then self:CmdProbe(t[2])
        else msgOut("capability module not loaded.", 1, 0.5, 0.3) end
        return
    end
    -- Capability report. Guarded so a client missing the optional capability
    -- file gets a clear answer instead of a nil-call error.
    if cmd == "capi" or cmd == "classicapi" then
        if self.CmdClassicAPI then self:CmdClassicAPI()
        else msgOut("capability module not loaded.", 1, 0.5, 0.3) end
        return
    end
    -- Toggles the pet window without going through the class panel, which is
    -- also how to tell a broken window apart from a broken switch.
    if cmd == "pet" then
        if Aegis_SBR_Pet then
            local on = Aegis_SBR_Pet:Toggle()
            msgOut("pet window " .. (on and "shown" or "hidden") .. ".")
        else
            msgOut("pet window module not loaded.", 1, 0.5, 0.3)
        end
        return
    end
    if cmd == "minimap" then
        if Aegis_SBR_Minimap and Aegis_SBR_Minimap.ToggleShown then
            local hidden = Aegis_SBR_Minimap:ToggleShown()
            msgOut("minimap button " .. (hidden and "hidden" or "shown") .. ".")
        else
            msgOut("minimap button not available.", 1, 0.5, 0.3)
        end
        return
    end
    if cmd == "debug" then self:Debug(); return end
    if cmd == "talents" then self:Talents(); return end
    if cmd == "gobbo" then self:CmdGobbo(); return end
    if cmd == "trace" then
        self.trace = not self.trace
        msgOut("trace " .. (self.trace and "on (per-press log)" or "off"))
        return
    end
    if cmd == "log" then
        local sub = string.lower(t[2] or "")
        -- Read the current state WITHOUT creating the table: only "on" and
        -- "clear" may bring AegisLog into existence, so merely asking for the
        -- status never leaves a saved variable behind on a machine that has
        -- never recorded anything.
        local have = (type(AegisLog) == "table") and AegisLog or nil
        local cap = (have and have.max) or LOG_MAX
        local held = (have and have.pos) or 0
        if held > cap then held = cap end
        if sub == "on" then
            self:LogInit()
            self.logging = true
            AegisLog.enabled = true
            msgOut("press log ON - every press is recorded (chat trace is separate).")
            msgOut("Run your test, then /reload to write the file, then read it from:", 0.7, 0.7, 0.7)
            msgOut("WTF\\Account\\<ACCOUNT>\\<Realm>\\<Char>\\SavedVariables\\Aegis_SBR.lua", 0.7, 0.7, 0.7)
        elseif sub == "off" then
            self.logging = false
            if have then have.enabled = false end
            msgOut("press log OFF. " .. held .. " lines held - /reload to write them out.")
            msgOut("They are dropped on the load AFTER that, so the saved file does not keep them forever.", 0.7, 0.7, 0.7)
        elseif sub == "clear" then
            self:LogInit(true)
            msgOut("press log cleared.")
        else
            msgOut("press log is " .. (self.logging and "ON" or "off")
                .. ", holding " .. held .. " of " .. cap .. " lines"
                .. (((have and have.pos) or 0) > cap and " (oldest overwritten)" or "") .. ".")
            msgOut("usage: /sbr log on|off|clear  - NOT written to disk until /reload or logout.", 0.7, 0.7, 0.7)
        end
        return
    end
    if cmd == "ui" or cmd == "config" then
        if self.active and self.active.OpenConfig then self.active:OpenConfig()
        else msgOut("no configuration UI for this class yet.", 1, 0.5, 0.3) end
        return
    end
    -- class specific subcommands (e.g. seal, spell on the paladin). These can
    -- mutate the active profile in place, so the cached validity is dropped.
    if self.active and self.active.HandleCommand and self.active:HandleCommand(cmd, t) then
        self.validCacheName = nil
        return
    end

    -- `log` is intentionally absent from this list: it is a development aid for
    -- capturing a rotation trace to file, not something a player has any use
    -- for. It still works when typed, so it can be handed out on request when
    -- diagnosing a report ("/sbr log on, play a bit, /reload, send me the file").
    msgOut("commands: ui, list, use, off, new, del, check, reset, acquire, minimap, debug, talents, trace (plus class commands).")
end

-- ============================================================
-- Class detection and load
-- ============================================================
function Aegis_SBR:OnAddonLoaded()
    -- Phase 0 rebrand migration: adopt the old AutoRotaDB once, BEFORE InitDB
    -- can seed fresh templates over it. Both names stay listed in the .toc for
    -- the transition, so the old data still loads from disk; sharing the same
    -- table keeps the AutoRotaDB copy current as a rollback backup until the
    -- old name is dropped from the .toc a few versions from now.
    if (type(AegisDB) ~= "table" or not next(AegisDB)) and type(AutoRotaDB) == "table" then
        AegisDB = AutoRotaDB
        AegisDB._migratedFrom = "AutoRotaDB"
    end
    -- Press log: a development tool, not a player feature. It is deliberately
    -- NOT initialised here - AegisLog is created lazily, on the first /sbr log
    -- on. A player who never touches the command therefore never gets the
    -- variable created and never carries it in their saved file; the table
    -- below is only ever touched if one already exists from a previous session.
    --
    -- The log survives /reload on purpose: /reload is exactly what flushes it
    -- to disk, so clearing it there would destroy the recording at the moment
    -- the user is trying to save it. Entries are dropped one load AFTER
    -- logging is switched off, so a finished test does not linger forever.
    if type(AegisLog) == "table" then
        self.logging = AegisLog.enabled and true or false
        if not self.logging and type(AegisLog.entries) == "table" and next(AegisLog.entries) then
            self:LogInit(true)
        end
    end
    local _, class = UnitClass("player")
    self.active = self.classes[class]
    self:InitDB()
    -- Saved variables are in by now, so the preview window can restore whether
    -- it was open. Guarded because the file is optional in the load order.
    if Aegis_SBR_Preview then Aegis_SBR_Preview:Restore() end
    if Aegis_SBR_Pet then Aegis_SBR_Pet:Restore() end
    if Aegis_SBR_Range then Aegis_SBR_Range:Restore() end
end

-- Printed once at PLAYER_LOGIN, when the chat frame is ready. ADDON_LOADED
-- fires too early in the login for a banner to reliably show.
function Aegis_SBR:Banner()
    if self.Loaded then return end
    self.Loaded = true
    if not self.active then
        local _, class = UnitClass("player")
        self.active = self.classes[class]
    end
    if self.active then
        DEFAULT_CHAT_FRAME:AddMessage("Aegis SBR v" .. self.ver .. " loaded for " .. (self.active.uiTitle or "?")
            .. ". Configure with /sbr ui, run with a bare /sbr macro.", 1, 0.8, 0.0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("Aegis SBR v" .. self.ver .. " loaded, but there is no module for your class yet.", 1, 0.6, 0.3)
    end
    -- ClassicAPI is optional, so the probe runs here rather than at file load:
    -- PLAYER_LOGIN is the first point where every DLL has certainly injected
    -- and the chat frame can show the result. Guarded because the capability
    -- file is optional in the load order, exactly like Preview and Pet.
    if self.DetectClassicAPI then
        self:DetectClassicAPI()
        local line = self:ClassicAPIBannerLine()
        if self:HasClassicAPI() then
            DEFAULT_CHAT_FRAME:AddMessage("Aegis: " .. line, 0.4, 1, 0.4)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Aegis: " .. line, 0.7, 0.7, 0.7)
        end
    end
end

-- Slash commands. /sbr is primary, /aegis the long form; /ar stays as a
-- legacy alias from the AutoRota era. ONE handler key, so a command is
-- never double-processed (the paladin-era aliases are gone).
SLASH_AEGIS_SBR1 = "/sbr"
SLASH_AEGIS_SBR2 = "/aegis"
SLASH_AEGIS_SBR3 = "/ar"
SlashCmdList["AEGIS_SBR"] = function(msg) Aegis_SBR:EvalCommand(msg) end

-- Event wiring. The swing tracker runs on the active module so its state
-- stays with the class instance that reads it.
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SPELLS_CHANGED")
-- A talent point can change a spell's cost without teaching anything (Improved
-- Sinister Strike and friends are passives), so the cached costs are dropped on
-- this too rather than trusting SPELLS_CHANGED to cover it.
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
ev:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
ev:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Gear changed: the weapon a step depends on may have.
ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
-- The client's own refusal messages: the only source for line of sight.
ev:RegisterEvent("UI_ERROR_MESSAGE")
-- SuperWoW fires UNIT_CASTEVENT on every registered cast: arg1 caster GUID,
-- arg2 target GUID, arg3 event type ("START"/"CAST"/"FAIL"/...), arg4 spell id,
-- arg5 cast duration. Modules that care (e.g. Shaman totem tracking) get the
-- resolved spell NAME via OnCastEvent. Guarded so clients without SuperWoW
-- (no such event) simply never receive it.
if SpellInfo then ev:RegisterEvent("UNIT_CASTEVENT") end
-- ClassicAPI backports PLAYER_TOTEM_UPDATE, which fires when a totem is
-- dropped, expires, OR is destroyed early (killed / Totemic Recall). Vanilla
-- has no way to see the destruction case at all, which is why the shaman module
-- had to guess with a blind redrop clock. Registering an event the client does
-- not know would error, so this is gated on the capability being present.
if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("PLAYER_TOTEM_UPDATE") then
    ev:RegisterEvent("PLAYER_TOTEM_UPDATE")
end
ev:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Aegis_SBR" then
        Aegis_SBR:OnAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        Aegis_SBR:Banner()
        Aegis_SBR:HookGossip()
    elseif event == "CHARACTER_POINTS_CHANGED" then
        -- The whole index, not just the two derived caches. A talent swap
        -- unlearns and relearns talent-granted spells, so spellIndex - the one
        -- cache that decides whether a spell exists at all - is precisely the
        -- one that must not survive it. It used to: SPELLS_CHANGED was left to
        -- cover it, and until that arrived KnowsSpell still answered "yes" for
        -- a spell the client could no longer resolve.
        Aegis_SBR:InvalidateSpellIndex()
        Aegis_SBR.validCacheName = nil
        -- A talent change is also how the Goblin Brainwashing Device announces
        -- itself, since it announces itself no other way.
        Aegis_SBR:GobboApply()
    elseif event == "SPELLS_CHANGED" then
        -- learning a spell or rank invalidates the spellbook index and any
        -- cached profile validity, both rebuilt lazily on the next use
        Aegis_SBR:InvalidateSpellIndex()
        Aegis_SBR.validCacheName = nil
    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        if Aegis_SBR.active then Aegis_SBR.active:OnSwingMessage(arg1) end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" or arg1 == nil then Aegis_SBR:ClearEquipCache() end
    elseif event == "UI_ERROR_MESSAGE" then
        Aegis_SBR:OnCastError(arg1)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Aegis_SBR:ClearDebuffLedger()
        if Aegis_SBR.active then Aegis_SBR.active.lastSwing = nil end
        -- Out of combat the kill curve is meaningless, and keeping it would let
        -- the last fight's rate answer the first press of the next one.
        Aegis_SBR:ResetTTK()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        if Aegis_SBR.active and Aegis_SBR.active.OnTotemUpdate then
            Aegis_SBR.active:OnTotemUpdate(arg1)
        end
        if Aegis_SBR.ProbeOnTotem then Aegis_SBR:ProbeOnTotem(arg1) end
    elseif event == "UNIT_CASTEVENT" then
        -- Somebody else's cast starting or ending. Recorded for every unit, not
        -- just the target: you can be switched onto a mob mid-cast.
        if arg3 == "START" then Aegis_SBR:NoteEnemyCast(arg1, arg5)
        elseif arg3 == "CAST" or arg3 == "FAIL" then Aegis_SBR:ClearEnemyCast(arg1) end
        -- Only successful casts ("CAST"), and only if the active module wants them.
        if arg3 == "CAST" and Aegis_SBR.active and Aegis_SBR.active.OnCastEvent then
            local sname
            if arg4 and SpellInfo then sname = SpellInfo(arg4) end
            if sname then Aegis_SBR.active:OnCastEvent(arg1, arg2, sname) end
        end
        -- Probe log: our OWN finisher casts, to read back what duration the
        -- server actually granted for the combo points spent.
        if arg3 == "CAST" and Aegis_SBR.ProbeOnCast then
            local _, myGuid = UnitExists("player")
            if myGuid and arg1 == myGuid and arg4 and SpellInfo then
                Aegis_SBR:ProbeOnCast(SpellInfo(arg4))
            end
        end
    end
end)
