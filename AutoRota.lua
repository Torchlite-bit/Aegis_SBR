-- ============================================================
-- AutoRota  -  configurable one-button rotation, multi class
-- Turtle WoW 1.12 (SuperWoW).
-- ============================================================
-- The core holds everything that is not class specific. Each class
-- ships a module (Class_<Name>.lua) that registers itself here. On
-- login the player class is detected and the matching module becomes
-- active, providing its templates, profile rules, rotation and UI.
-- ============================================================
-- Run with a bare macro, spam it:   /ar
-- Configure per character:          /ar ui
-- Other commands: list, use <name>, off, new <name> [template],
--   del <name>, check, reset, debug, trace, plus class commands.
-- /pa, /paladinauto and /autopala stay as aliases for old macros.
-- ============================================================

AutoRota = {
    ver = "0.6.0b",
    classes = {},     -- token -> module table
    active = nil,      -- the module for this character's class
    Loaded = false,
    lastMsg = 0,
}

-- A class module inherits every shared helper through __index, so inside
-- a module "self:Cast(...)" resolves to the core while "self.weaving" and
-- the like stay private to the module instance.
function AutoRota:NewClassModule(token)
    local m = setmetatable({ classToken = token }, { __index = self })
    self.classes[token] = m
    return m
end

-- Shared chat output, inherited by every class module (so modules use
-- self:Msg(...) instead of redefining their own local printer).
function AutoRota:Msg(text, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage("AutoRota: " .. text, r or 1, g or 0.8, b or 0.0)
end

local function msgOut(text, r, g, b) AutoRota:Msg(text, r, g, b) end

-- ============================================================
-- Shared rotation and utility helpers (class independent)
-- ============================================================

-- One pass over the spellbook builds a name -> slot index (last slot wins, so
-- the highest rank is kept, same as the old linear scan) plus a name -> max
-- rank table. Every later lookup is then a table read instead of a full scan.
-- The index is built lazily and dropped on SPELLS_CHANGED, so learning a spell
-- or a new rank triggers a rebuild on the next lookup.
function AutoRota:BuildSpellIndex()
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
    AutoRota.spellIndex = idx
    AutoRota.spellRanks = ranks
end

function AutoRota:InvalidateSpellIndex()
    AutoRota.spellIndex = nil
    AutoRota.spellRanks = nil
end

function AutoRota:FindSpellSlot(name)
    if not AutoRota.spellIndex then AutoRota:BuildSpellIndex() end
    return AutoRota.spellIndex[name]
end

-- Highest known rank number of a spell (0 if unknown). Used for downranking.
function AutoRota:MaxRank(name)
    if not AutoRota.spellRanks then AutoRota:BuildSpellIndex() end
    return AutoRota.spellRanks[name] or 0
end

function AutoRota:KnowsSpell(name)
    return self:FindSpellSlot(name) ~= nil
end

function AutoRota:Cast(name)
    if self:KnowsSpell(name) then CastSpellByName(name); return true end
    return false
end

function AutoRota:IsReady(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return false end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 then return true end
    return (start + dur - GetTime()) <= 0
end

-- Human readable cooldown state for tracing
function AutoRota:CDInfo(name)
    local slot = self:FindSpellSlot(name)
    if not slot then return "unknown" end
    local start, dur = GetSpellCooldown(slot, BOOKTYPE_SPELL)
    if start == 0 then return "ready" end
    local rem = start + dur - GetTime()
    if dur <= 1.55 then return string.format("gcd %.1fs", rem) end   -- only the global cooldown
    return string.format("cd %.1fs", rem)
end

-- True if the spell's OWN cooldown is free, ignoring the global cooldown.
-- A short reported duration (<= ~1.5s) means only the GCD is active, which
-- we treat as "ready" so a held priority spell does not lose the GCD-edge
-- race to the unconditional seal recast.
function AutoRota:OwnCDReady(name)
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
function AutoRota:OnSwingMessage(msg)
    if not msg then return end
    if string.find(msg, "^Your ") then return end   -- a named ability or seal, not a white swing
    if string.find(msg, "^You ") then
        self.lastSwing = GetTime()
        local mh = UnitAttackSpeed("player")
        if mh and mh > 0 then self.swingSpeed = mh end
    end
end

-- Predicted seconds until the next white swing, or nil if unknown.
function AutoRota:SwingTimeLeft()
    if not self.lastSwing or not self.swingSpeed or self.swingSpeed <= 0 then return nil end
    local elapsed = GetTime() - self.lastSwing
    return self.swingSpeed - math.mod(elapsed, self.swingSpeed)
end

-- Throttled per-press trace, toggled with /ar trace. Accepts any number of
-- lines; the throttle is checked once so multi-line traces are never half
-- swallowed (Lua 5.0 packs varargs into the implicit `arg` table).
function AutoRota:Trace(...)
    if not self.trace then return end
    local now = GetTime()
    if now - (self.traceT or 0) < 0.4 then return end
    self.traceT = now
    for i = 1, arg.n do
        if arg[i] then DEFAULT_CHAT_FRAME:AddMessage("AR: " .. arg[i], 0.6, 0.8, 1.0) end
    end
end

-- One pass over the player's buffs per rotation press. Every HasBuff/BuffTime
-- in the same press then reads this table instead of rescanning all 32 slots.
-- Keyed by GetTime(), which is constant within a frame, so the snapshot can
-- never be read stale.
function AutoRota:SnapshotBuffs()
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

function AutoRota:ScanBuff(name)
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

function AutoRota:HasBuff(name)
    local tl = self:ScanBuff(name)
    return tl ~= nil
end

function AutoRota:BuffTime(name)
    local tl, st = self:ScanBuff(name)
    return tl or 0, st or 0
end

function AutoRota:ManaPct()
    local mx = UnitManaMax("player")
    if mx and mx > 0 then return UnitMana("player") / mx * 100 end
    return 100
end

function AutoRota:PlayerHPPct()
    local mx = UnitHealthMax("player")
    if mx and mx > 0 then return UnitHealth("player") / mx * 100 end
    return 100
end

function AutoRota:TargetHPPct()
    local mx = UnitHealthMax("target")
    if mx and mx > 0 then return UnitHealth("target") / mx * 100 end
    return 100
end

-- The Attack action's bar slot is cached: one IsAttackAction call verifies it
-- each press, and the full 1..172 scan only runs when the cache is empty or
-- the button was moved/removed.
function AutoRota:EnsureAutoAttack()
    local slot = self.attackSlot
    if not (slot and IsAttackAction(slot)) then
        slot = nil
        for z = 1, 172 do
            if IsAttackAction(z) then slot = z; break end
        end
        self.attackSlot = slot
    end
    if slot and not IsCurrentAction(slot) then UseAction(slot) end
end

-- A stable id for the current target. SuperWoW returns the GUID as the second
-- value of UnitExists, which lets us tell apart two mobs that share a name.
function AutoRota:TargetId()
    local _, guid = UnitExists("target")
    if guid then return guid end
    return UnitName("target") or ""
end

-- Best effort melee proximity. CheckInteractDistance index 3 is about 9.9
-- yards, a practical proxy for "close enough to fight". Used only to decide
-- whether we are still running in, so we can pre-cast the seal on the way.
function AutoRota:InMeleeRange()
    if not UnitExists("target") then return false end
    return CheckInteractDistance("target", 3) and true or false
end

function AutoRota:Throttle(text)
    local now = GetTime()
    if (now - (self.lastMsg or 0)) > 3 then
        DEFAULT_CHAT_FRAME:AddMessage("AutoRota: " .. text, 1, 0.5, 0.3)
        self.lastMsg = now
    end
end

-- ============================================================
-- Debug dump
-- ============================================================
function AutoRota:Debug()
    DEFAULT_CHAT_FRAME:AddMessage("--- AutoRota debug ---", 1, 0.8, 0.0)
    if UnitExists("target") then
        DEFAULT_CHAT_FRAME:AddMessage("Target debuff textures:", 1, 0.8, 0.0)
        local any = false
        for i = 1, 40 do
            local t = UnitDebuff("target", i)
            if t then any = true; DEFAULT_CHAT_FRAME:AddMessage("  [" .. i .. "] " .. t) end
        end
        if not any then DEFAULT_CHAT_FRAME:AddMessage("  (none)") end
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

function AutoRota:Tokenize(msg)
    local t = {}
    for w in string.gfind(msg or "", "%S+") do table.insert(t, w) end
    return t
end

-- ============================================================
-- Saved variables and profiles (generic, schema comes from the module)
-- ============================================================
function AutoRota:DeepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = self:DeepCopy(v) end
    return r
end

-- A full copy of a profile, then normalized by the active module. Every UI
-- save/activate commits through here, so the cached validity is dropped.
function AutoRota:CopyProfile(p)
    self.validCacheName = nil
    local c = self:DeepCopy(p)
    if self.active and self.active.NormalizeProfile then self.active:NormalizeProfile(c) end
    return c
end

function AutoRota:InitDB()
    if type(AutoRotaDB) ~= "table" then AutoRotaDB = {} end
    if type(AutoRotaDB.profiles) ~= "table" then AutoRotaDB.profiles = {} end
    if not self.active or not self.active.templates then return end
    if not next(AutoRotaDB.profiles) then
        for name, tpl in pairs(self.active.templates) do
            AutoRotaDB.profiles[name] = self:CopyProfile(tpl)
        end
    end
    -- migrate any already-stored profiles to the current format
    for _, cfg in pairs(AutoRotaDB.profiles) do self.active:NormalizeProfile(cfg) end
end

function AutoRota:GetActiveProfile()
    if not AutoRotaDB or not AutoRotaDB.active then return nil end
    return AutoRotaDB.profiles[AutoRotaDB.active]
end

-- Validity is a class rule. Without a module nothing is missing.
function AutoRota:Validity(cfg)
    if self.active and self.active.ProfileValidity then return self.active:ProfileValidity(cfg) end
    return true, {}
end

-- ============================================================
-- Generic profile commands (the text interface, UI is primary)
-- ============================================================
function AutoRota:CmdList()
    msgOut("Profiles:")
    local active = AutoRotaDB.active
    local any = false
    for name, cfg in pairs(AutoRotaDB.profiles) do
        any = true
        local ok, missing = self:Validity(cfg)
        local mark = (name == active) and " [active]" or ""
        local valid = ok and "valid" or ("INVALID, missing " .. table.concat(missing, ", "))
        msgOut("  " .. name .. mark .. " - " .. valid)
    end
    if not any then msgOut("  (none, use /ar reset)") end
    if not active then msgOut("No profile is active.") end
end

function AutoRota:CmdUse(name)
    local cfg = name and AutoRotaDB.profiles[name]
    if not cfg then msgOut("profile '" .. tostring(name) .. "' not found.", 1, 0.5, 0.3); return end
    local ok, missing = self:Validity(cfg)
    if not ok then msgOut("cannot activate '" .. name .. "', missing " .. table.concat(missing, ", "), 1, 0.5, 0.3); return end
    AutoRotaDB.active = name
    msgOut("activated '" .. name .. "'.")
end

function AutoRota:CmdOff()
    AutoRotaDB.active = nil
    msgOut("deactivated. No profile active.")
end

function AutoRota:CmdNew(name, template)
    if not self.active or not self.active.templates then msgOut("no class module loaded.", 1, 0.5, 0.3); return end
    if not name then msgOut("usage: /ar new <name> [template]", 1, 0.5, 0.3); return end
    if AutoRotaDB.profiles[name] then msgOut("'" .. name .. "' already exists.", 1, 0.5, 0.3); return end
    local tpl = self.active.templates[template or "starter"]
    if not tpl then msgOut("unknown template '" .. tostring(template) .. "'.", 1, 0.5, 0.3); return end
    AutoRotaDB.profiles[name] = self:CopyProfile(tpl)
    msgOut("created '" .. name .. "' from template '" .. (template or "starter") .. "'.")
end

function AutoRota:CmdDel(name)
    if not name or not AutoRotaDB.profiles[name] then msgOut("profile not found.", 1, 0.5, 0.3); return end
    AutoRotaDB.profiles[name] = nil
    if AutoRotaDB.active == name then AutoRotaDB.active = nil end
    msgOut("deleted '" .. name .. "'.")
end

function AutoRota:CmdCheck()
    local cfg = self:GetActiveProfile()
    if not cfg then msgOut("no profile active."); return end
    local ok, missing = self:Validity(cfg)
    if ok then msgOut("active profile '" .. AutoRotaDB.active .. "' is valid.")
    else msgOut("active profile invalid, missing " .. table.concat(missing, ", "), 1, 0.5, 0.3) end
end

function AutoRota:CmdReset()
    if not self.active or not self.active.templates then msgOut("no class module loaded.", 1, 0.5, 0.3); return end
    AutoRotaDB.profiles = {}
    for n, tpl in pairs(self.active.templates) do AutoRotaDB.profiles[n] = self:CopyProfile(tpl) end
    AutoRotaDB.active = nil
    msgOut("profile list reseeded from templates, nothing active.")
end

-- ============================================================
-- Rotation entry point
-- ============================================================
function AutoRota:RunRotation()
    if not self.active then self:Throttle("no module for your class yet."); return end
    local cfg = self:GetActiveProfile()
    if not cfg then
        self:Throttle("no profile active. Open /ar ui or use /ar use <name>.")
        return
    end
    -- Validity is cached per active profile, not recomputed every press: it only
    -- changes when a spell is learned (SPELLS_CHANGED clears it) or the active
    -- profile switches/saves (those paths clear it too).
    if self.validCacheName ~= AutoRotaDB.active then
        local ok, missing = self:Validity(cfg)
        self.validCacheName = AutoRotaDB.active
        self.validCacheOK = ok
        self.validCacheMissing = missing
    end
    if not self.validCacheOK then
        self:Throttle("active profile incomplete, missing " .. table.concat(self.validCacheMissing, ", ") .. ". Running with what is available.")
    end

    if not UnitExists("target") or UnitIsDead("target") then TargetNearestEnemy() end
    if not UnitCanAttack("player", "target") then return end

    if self.active.meleeAutoAttack ~= false and not IsAddOnLoaded("SuperCleveRoidMacros") then self:EnsureAutoAttack() end

    self:SnapshotBuffs()
    self.active:Rotate(cfg)
    UIErrorsFrame:Clear()
end

-- ============================================================
-- Command dispatch
-- ============================================================
function AutoRota:EvalCommand(msg)
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
    if cmd == "debug" then self:Debug(); return end
    if cmd == "trace" then
        self.trace = not self.trace
        msgOut("trace " .. (self.trace and "on (per-press log)" or "off"))
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

    msgOut("commands: ui, list, use, off, new, del, check, reset, debug, trace (plus class commands).")
end

-- ============================================================
-- Class detection and load
-- ============================================================
function AutoRota:OnAddonLoaded()
    local _, class = UnitClass("player")
    self.active = self.classes[class]
    self:InitDB()
end

-- Printed once at PLAYER_LOGIN, when the chat frame is ready. ADDON_LOADED
-- fires too early in the login for a banner to reliably show.
function AutoRota:Banner()
    if self.Loaded then return end
    self.Loaded = true
    if not self.active then
        local _, class = UnitClass("player")
        self.active = self.classes[class]
    end
    if self.active then
        DEFAULT_CHAT_FRAME:AddMessage("AutoRota v" .. self.ver .. " loaded for " .. (self.active.uiTitle or "?")
            .. ". Configure with /ar ui, run with a bare /ar macro.", 1, 0.8, 0.0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("AutoRota v" .. self.ver .. " loaded, but there is no module for your class yet.", 1, 0.6, 0.3)
    end
end

-- Slash commands. /ar is primary, the paladin era names stay as aliases.
SLASH_AUTOROTA1 = "/ar"
SLASH_AUTOROTA2 = "/autorota"
SLASH_AUTOROTA3 = "/paladinauto"
SLASH_AUTOROTA4 = "/pa"
SLASH_AUTOROTA5 = "/autopala"
SlashCmdList["AUTOROTA"] = function(msg) AutoRota:EvalCommand(msg) end

-- Event wiring. The swing tracker runs on the active module so its state
-- stays with the class instance that reads it.
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
ev:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "AutoRota" then
        AutoRota:OnAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        AutoRota:Banner()
    elseif event == "SPELLS_CHANGED" then
        -- learning a spell or rank invalidates the spellbook index and any
        -- cached profile validity, both rebuilt lazily on the next use
        AutoRota:InvalidateSpellIndex()
        AutoRota.validCacheName = nil
    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        if AutoRota.active then AutoRota.active:OnSwingMessage(arg1) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if AutoRota.active then AutoRota.active.lastSwing = nil end
    end
end)
