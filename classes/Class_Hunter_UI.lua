-- ============================================================
-- Class_Hunter_UI  -  hunter window body for Aegis_SBR
-- Builds and binds only the hunter specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
--
-- One tab per spec - Beast Mastery, Marksmanship, Survival - because that is
-- how a hunter is built on this server: the two shooting specs and the one
-- melee spec, no hybrid. Every tab has the same shape, top to bottom:
--   aspect (with the range switch)  ->  the spec's own attacks as a
--   single / AoE table  ->  the attacks of the other range, for when distance
--   forces them  ->  the spec's special abilities  ->  pet  ->  cooldowns.
-- Each tab edits its own layer of the profile (Class_Hunter.lua, SpecConfig),
-- so a change on one tab never reaches another.
-- ============================================================

local M = Aegis_SBR.classes.HUNTER
M.useScrollLayout = true
M.specTabs = {
    field = "spec", default = "bm",
    tabs = {
        { key = "bm",   label = "Beast Mastery", tip1 = "Ranged, built around the pet: Kill Command, Baited Shot, Bestial Wrath." },
        { key = "mm",   label = "Marksmanship",  tip1 = "Ranged: Aimed Shot, Lock and Load, Steady Shot weave." },
        { key = "surv", label = "Survival",      tip1 = "Melee: Raptor Strike, Mongoose Bite, Lacerate, traps placed in combat." },
    },
}

-- ============================================================
-- build body (hunter controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)

    -- The layer the current tab edits: the spec's own sparse set, with its own
    -- AoE set inside. Reads fall back to the base, so a tab shows the base value
    -- until it is changed there.
    local function layer(buf)
        local sp = buf.spec
        if sp ~= "bm" and sp ~= "mm" and sp ~= "surv" then sp = "bm" end
        if type(buf[sp]) ~= "table" then buf[sp] = {} end
        if type(buf[sp].aoe) ~= "table" then buf[sp].aoe = {} end
        return buf[sp]
    end
    M.layerOf = layer
    local function set(key) return function(v) if ui.buf then layer(ui.buf)[key] = v; ui:Refresh() end end end
    local function setAoe(key) return function(v) if ui.buf then layer(ui.buf).aoe[key] = v; ui:Refresh() end end end

    -- Table rows. `key` names the profile field; `id` keeps the frame names
    -- unique where the same field appears on more than one tab.
    -- The AoE column inherits the single value until it has one of its own,
    -- which is right for display and for the rotation - but it means the first
    -- flip of the SINGLE switch would drag the AoE column along with it. So the
    -- single handler first pins the AoE value at what the column was showing,
    -- and only then changes the single one: from the first edit on, the two
    -- are independent.
    local function setSingle(key)
        return function(v)
            if not ui.buf then return end
            local lay = layer(ui.buf)
            if lay.aoe[key] == nil then
                local cur = lay[key]
                if cur == nil then cur = ui.buf[key] end
                lay.aoe[key] = cur and true or false
            end
            lay[key] = v
            ui:Refresh()
        end
    end
    local function both(id, key, label, spell)
        return L:Row2{ key = id, label = label, spell = spell, onSingle = setSingle(key), onAoe = setAoe(key) }
    end
    local function singleOnly(id, key, label, spell)
        return L:Row2{ key = id, label = label, spell = spell, onSingle = set(key) }
    end
    local function aoeOnly(id, key, label, spell)
        return L:Row2{ key = id, label = label, spell = spell, onAoe = setAoe(key) }
    end

    L:MacroNote()

    L:Header("Single / AoE")
    self.smartRow = L:Row{ key = "smartAoe", label = "Smart single/AoE from", onToggle = set("smartAoe"),
        slider = { key = "smartAoeN", min = 2, max = 8, step = 1, suffix = "", onChange = set("smartAoeN") } }

    -- ---------------------------------------------------------------- 1. aspect
    L:Header("Aspect")
    self.aspectRow = L:Row{ key = "useAspect", label = "Keep the combat aspect up", onToggle = set("useAspect") }
    self.rangedAspDD = L:Dropdown("rangedAspect", "At range", 180, set("rangedAspect"))
    self.meleeAspDD = L:Dropdown("meleeAspect", "In melee", 180, set("meleeAspect"))
    self.rangeSwitchRow = L:Row{ key = "rangeSwitch", label = "Switch attacks by distance", onToggle = set("rangeSwitch") }
    self.manaAspRow = L:Row{ key = "useManaAspect", label = "Viper below",
        spell = "Aspect of the Viper", onToggle = set("useManaAspect"),
        slider = { key = "manaAspectPct", min = 0, max = 90, step = 5, suffix = "%", onChange = set("manaAspectPct") } }
    self.manaBackRow = L:Row{ label = "Back to combat at",
        slider = { key = "manaAspectBackPct", min = 5, max = 100, step = 5, suffix = "%", onChange = set("manaAspectBackPct") } }

    -- ---------------------------------------------------------------- 2. the spec's own attacks
    -- Shooting specs: the ranged table is primary.
    L:Header("Ranged attacks", { bm = true, mm = true })
    L:ColumnHeads("single", "aoe")
    self.stingDD   = L:Dropdown("sting", "Sting", 180, set("sting"))
    self.markRow   = both("r_mark", "useHuntersMark", "Hunter's Mark", "Hunter's Mark")
    self.steadyRow = both("r_steady", "useSteadyShot", "Steady Shot", "Steady Shot")
    self.arcaneRow = both("r_arcane", "useArcaneShot", "Arcane Shot", "Arcane Shot")
    self.multiRow  = both("r_multi", "useMultiShot", "Multi-Shot", "Multi-Shot")
    self.aimedRow  = both("r_aimed", "useAimedShot", "Aimed Shot", "Aimed Shot")
    self.volleyRow = both("r_volley", "useVolley", "Volley", "Volley")
    self.trapRow      = singleOnly("r_immo", "useImmolationTrap", "Immolation Trap", "Immolation Trap")
    self.explosiveRow = aoeOnly("r_expl", "useExplosiveTrap", "Explosive Trap", "Explosive Trap")
    self.aimedProcRow = L:Row{ key = "aimedOnlyOnProc", label = "Aimed only on Lock and Load", onToggle = set("aimedOnlyOnProc") }
    self.aimedOpenerRow = L:Row{ key = "useAimedOpener", label = "Aimed opener (pre-pull)", onToggle = set("useAimedOpener") }
    self.ttkMarkRow = L:Row{ key = "useDebuffTTK", label = "Mark only if the target lives", onToggle = set("useDebuffTTK"),
        slider = { key = "markMinTTK", min = 0, max = 30, step = 1, suffix = "s", onChange = set("markMinTTK") } }
    self.ttkStingRow = L:Row{ label = "Sting only if the target lives",
        slider = { key = "stingMinTTK", min = 0, max = 30, step = 1, suffix = "s", onChange = set("stingMinTTK") } }

    -- Survival: the melee table is primary.
    L:Header("Melee attacks", { surv = true })
    L:ColumnHeads("single", "aoe")
    self.raptorRow   = both("s_raptor", "useRaptorStrike", "Raptor Strike", "Raptor Strike")
    self.mongooseRow = both("s_mongoose", "useMongooseBite", "Mongoose Bite", "Mongoose Bite")
    self.lacerateRow = both("s_lacerate", "useLacerate", "Lacerate", "Lacerate")
    self.lacFirstRow = L:Row{ key = "lacerateFirst", label = "Lacerate before Mongoose Bite", spell = "Lacerate", onToggle = set("lacerateFirst") }
    self.carveRow    = both("s_carve", "useCarve", "Carve", "Carve")
    self.wingRow     = both("s_wing", "useWingClip", "Wing Clip", "Wing Clip")
    self.trapRow2      = singleOnly("s_immo", "useImmolationTrap", "Immolation Trap", "Immolation Trap")
    self.explosiveRow2 = aoeOnly("s_expl", "useExplosiveTrap", "Explosive Trap", "Explosive Trap")

    -- ---------------------------------------------------------------- 3. the other range
    -- What a shooting spec does once the mob is on it. Lacerate and Carve are
    -- Survival talents and do not appear here.
    L:Header("Melee, when closed on", { bm = true, mm = true })
    L:ColumnHeads("single", "aoe")
    self.raptorRow2   = both("m_raptor", "useRaptorStrike", "Raptor Strike", "Raptor Strike")
    self.mongooseRow2 = both("m_mongoose", "useMongooseBite", "Mongoose Bite", "Mongoose Bite")
    self.wingRow2     = both("m_wing", "useWingClip", "Wing Clip", "Wing Clip")

    -- What Survival does while the mob is still out of reach.
    L:Header("Ranged, when out of reach", { surv = true })
    L:ColumnHeads("single", "aoe")
    self.stingDD2   = L:Dropdown("sting2", "Sting", 180, set("sting"))
    self.markRow2   = both("o_mark", "useHuntersMark", "Hunter's Mark", "Hunter's Mark")
    self.arcaneRow2 = both("o_arcane", "useArcaneShot", "Arcane Shot", "Arcane Shot")
    self.multiRow2  = both("o_multi", "useMultiShot", "Multi-Shot", "Multi-Shot")
    self.ttkMarkRow2 = L:Row{ key = "useDebuffTTK2", label = "Mark only if the target lives", onToggle = set("useDebuffTTK"),
        slider = { key = "markMinTTK2", min = 0, max = 30, step = 1, suffix = "s", onChange = set("markMinTTK") } }
    self.ttkStingRow2 = L:Row{ label = "Sting only if the target lives",
        slider = { key = "stingMinTTK2", min = 0, max = 30, step = 1, suffix = "s", onChange = set("stingMinTTK") } }

    -- ---------------------------------------------------------------- 4. spec abilities
    L:Header("Beast Mastery", { bm = true })
    self.kcRow = L:Row{ key = "useKillCommand", label = "Kill Command", spell = "Kill Command", onToggle = set("useKillCommand") }
    self.baitedRow = L:Row{ key = "useBaitedShot", label = "Baited Shot on pet crit", spell = "Baited Shot", onToggle = set("useBaitedShot") }
    -- The spec's own cooldown, a talent: it belongs with the spec, not in the
    -- shared list below, where the other two tabs would only show it unlearned.
    self.bwRow = L:Row{ key = "useBestialWrath", label = "Bestial Wrath with cooldowns", spell = "Bestial Wrath", onToggle = set("useBestialWrath") }

    -- ---------------------------------------------------------------- 5. pet
    L:Header("Pet")
    self.petRow = L:Row{ key = "petAttack", label = "Send pet to attack", onToggle = set("petAttack") }
    self.petMeleeRow = L:Row{ key = "petMeleeOnly", label = "Pet only in melee range", onToggle = set("petMeleeOnly") }
    self.mendRow = L:Row{ key = "useMendPet", label = "Mend Pet", spell = "Mend Pet", onToggle = set("useMendPet"),
        slider = { key = "mendPetHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("mendPetHp") } }
    self.tauntRow = L:Row{ key = "petTaunt", label = "Pet taunt", spell = "Growl", onToggle = set("petTaunt") }
    -- A window, not a rotation setting, so it writes to the pet module directly
    -- and lives per character rather than per profile.
    self.petWinRow = L:Row{ key = "petWindow", label = "Show pet window", onToggle = function(on)
        if Aegis_SBR_Pet then Aegis_SBR_Pet:SetShown(on) end
    end }

    -- ---------------------------------------------------------------- 6. cooldowns
    -- WHEN the cooldowns fire, then WHICH ones - each listed and switchable on
    -- its own, like everything else on the tab.
    L:Header("Cooldowns")
    self.cdRow = L:Row{ key = "popCDs", label = "Pop cooldowns every press", onToggle = set("popCDs") }
    self.cdEliteRow = L:Row{ key = "autoCDElite", label = "Pop on elites and bosses", onToggle = set("autoCDElite") }
    self.rfRow = L:Row{ key = "useRapidFire", label = "Rapid Fire", spell = "Rapid Fire", onToggle = set("useRapidFire") }

    -- (7. defensive cooldowns: not built yet - its triggers are still to be
    --  decided. Feign Death cancels everything, so a wrong trigger is worse than
    --  none.)

    -- Last section on every tab: which Goblin Brainwashing Device slot this
    -- tab answers to.
    ui:BuildGobboRow(L)

    L:Finish()

    -- ---------------------------------------------------------------- tooltips
    ui:Tip(self.aspectRow.cb, "Keep the combat aspect up", "Keeps the aspect chosen below up - the ranged one at range, the melee one in melee.", "Switch it OFF and the rotation never touches your aspect at all, the mana swap included - so you can pick one yourself and it stays.")
    ui:Tip(self.rangedAspDD, "At range", "The aspect kept up while shooting. Hawk by default.")
    ui:Tip(self.meleeAspDD, "In melee", "The aspect kept up while fighting in melee. Wolf by default.")
    ui:Tip(self.rangeSwitchRow.cb, "Switch attacks by distance", "Lets your distance to the target decide, press by press: a shooting spec that has been closed on uses its melee attacks below, a melee spec kept at range uses its shots.", "Off, the spec's own range is used regardless. The aspect follows the same decision.")
    ui:Tip(self.manaAspRow.cb, "Mana aspect swap", "Swap to Aspect of the Viper when mana drops below the first value, then back to the combat aspect once mana recovers to the second.", "Needs Aspect of the Viper, learned at level 56.")
    ui:Tip(self.manaAspRow.slider, "Viper below", "Drop to Aspect of the Viper when your mana falls under this percent.")
    ui:Tip(self.manaBackRow.slider, "Back to combat at", "Swap back once mana recovers to this percent. Set it above the 'Viper below' value.")

    local function stingTip(dd) ui:Tip(dd, "Sting", "The one sting kept up. Serpent is the staple DoT; Scorpid lowers melee hit; Viper drains mana. \"Viper > Serpent\" uses Viper Sting against mana users and Serpent Sting for everything else.") end
    stingTip(self.stingDD); stingTip(self.stingDD2)
    local function markTip(row) ui:Tip(row.cb, "Hunter's Mark", "Applied once per target and refreshed when it falls off.", "Off in the AoE column by default: one mark per mob is a press each that a pack does not repay.") end
    markTip(self.markRow); markTip(self.markRow2)
    local function ttkTip(mr, sr)
        ui:Tip(mr.cb, "Mark and sting only if the target lives", "Hunter's Mark and the sting only on a target the time-to-kill estimate says lives at least the seconds on the right. Saves the mana they cost on trash that dies anyway.", "A target at full health is marked as before; one already losing health waits about three seconds for the estimate, the shots go on meanwhile. 0 = no limit.")
        ui:Tip(mr.slider, "Mark if it lives", "Seconds the target must have left for Hunter's Mark.")
        ui:Tip(sr.slider, "Sting if it lives", "Seconds the target must have left for the sting.")
    end
    ttkTip(self.ttkMarkRow, self.ttkStingRow); ttkTip(self.ttkMarkRow2, self.ttkStingRow2)
    ui:TipRow(self.steadyRow, "Steady Shot", "The 1:1 weave after each Auto Shot and the main filler. Queued so it does not clip the shot.")
    local function arcaneTip(row) ui:Tip(row.cb, "Arcane Shot", "Filler: only where it leaves a global cooldown of room before the next Auto Shot, so the Steady weave is never delayed.") end
    arcaneTip(self.arcaneRow); arcaneTip(self.arcaneRow2)
    local function multiTip(row) ui:Tip(row.cb, "Multi-Shot", "AoE: on cooldown, ahead of Steady Shot. Single target: filler below Kill Command and Steady Shot, only with room before the next Auto Shot.") end
    multiTip(self.multiRow); multiTip(self.multiRow2)
    ui:TipRow(self.aimedRow, "Aimed Shot", "Only fired when Lock and Load procs (cast time drop + line cleave), so it never clips Auto Shot.")
    ui:Tip(self.aimedProcRow.cb, "Aimed only on Lock and Load", "Recommended on. Off, Aimed Shot is also hard-cast on cooldown, which clips Auto Shot.")
    ui:Tip(self.aimedOpenerRow.cb, "Aimed Shot opener", "Open the pull with a hard-cast Aimed Shot before combat, then never clip Auto Shot during the fight.")
    ui:TipRow(self.volleyRow, "Volley", "Lands under the mouse. Hold the mouse on the feet of the pack when pressing; with the mouse off any enemy the press skips Volley.")
    local function immoTip(row) ui:Tip(row.cb, "Immolation Trap", "Dropped on cooldown against a single target.", "In combat only with the Untamed Trapper talent - that is what allows a trap to be placed while fighting. Without it, only on the pull.") end
    immoTip(self.trapRow); immoTip(self.trapRow2)
    local function explTip(row) ui:Tip(row.cb, "Explosive Trap", "Dropped on cooldown on an AoE press, alongside Carve or Volley.", "In combat only with the Untamed Trapper talent.") end
    explTip(self.explosiveRow); explTip(self.explosiveRow2)
    local function raptorTip(row) ui:Tip(row.cb, "Raptor Strike", "On-next-swing strike, sent whenever it is ready - it spends no global cooldown, so it goes out alongside the other melee attacks.") end
    raptorTip(self.raptorRow); raptorTip(self.raptorRow2)
    local function mongooseTip(row) ui:Tip(row.cb, "Mongoose Bite", "Instant melee attack, used on its cooldown.", "No dodge requirement on this client.") end
    mongooseTip(self.mongooseRow); mongooseTip(self.mongooseRow2)
    local function wingTip(row) ui:Tip(row.cb, "Wing Clip", "Optional melee slow / kite tool.") end
    wingTip(self.wingRow); wingTip(self.wingRow2)
    ui:Tip(self.smartRow.cb, "Smart single/AoE", "The single macro switches to the AoE column by itself from this many enemies, and back below it. Needs enemy nameplates shown (V): without them there is no count and the single macro stays single.", "The AoE macro still forces AoE, so two macros keep working as before.")
    ui:Tip(self.smartRow.slider, "Enemies for AoE", "Enemies near you from which the AoE column is used: in melee range for a hunter in melee, in shot range otherwise.")
    ui:Tip(self.lacFirstRow.cb, "Lacerate before Mongoose Bite", "The bleed ahead of the Bite. Worth it with strong gear (Naxxramas and above); off, Mongoose Bite leads.")
    ui:TipRow(self.lacerateRow, "Lacerate", "An 8 second bleed on a 10 second cooldown, re-applied when it falls off.", "Only usable after you critically strike the target: it is armed by a crit of yours and stands down again when the client refuses it, until the next crit.")
    ui:TipRow(self.carveRow, "Carve", "Melee cone. Leads the melee attacks on an AoE press; a single-target filler otherwise.")

    -- The AoE column, one tooltip for all of it.
    for _, row in pairs({ self.markRow, self.steadyRow, self.arcaneRow, self.multiRow, self.aimedRow, self.volleyRow,
                          self.raptorRow, self.mongooseRow, self.lacerateRow, self.carveRow, self.wingRow,
                          self.raptorRow2, self.mongooseRow2, self.wingRow2,
                          self.markRow2, self.arcaneRow2, self.multiRow2 }) do
        if row.cb2 then
            ui:Tip(row.cb2, "AoE column",
                "This switch as an AoE press reads it - /sbr aoe on, or a /sbr run aoe macro. The left column is what a single-target press reads.",
                "The AoE column belongs to this tab alone.")
        end
    end

    ui:Tip(self.kcRow.cb, "Kill Command", "Fired the moment it becomes usable: after you land a critical strike on the current target.")
    ui:Tip(self.baitedRow.cb, "Baited Shot", "Fired in the short window after your pet lands a critical strike.")
    ui:Tip(self.rfRow.cb, "Rapid Fire", "Included when cooldowns fire. At range only - it speeds up ranged attacks and nothing else, so in melee it is kept for when you step back.")
    ui:Tip(self.bwRow.cb, "Bestial Wrath", "Situational: press it yourself when the tank's aggro is safe, or for a fear, sleep or execute phase. Switched on, it fires together with the cooldowns.", "Skipped without a live pet - it grants the pet Scent of Blood.")
    ui:Tip(self.petRow.cb, "Pet attack", "Sends your pet onto the target each press.")
    ui:Tip(self.petMeleeRow.cb, "Pet only in melee range", "Only send the pet when the target is within melee range of you, so a far target does not pull it away.")
    ui:Tip(self.mendRow.cb, "Mend Pet", "Heals the pet below the slider value (HoT, refreshed ~12s).")
    ui:Tip(self.mendRow.slider, "Mend Pet below", "Pet health percent under which Mend Pet is cast.")
    ui:Tip(self.tauntRow.cb, "Smart Pet Taunt", "When the mob peels off your pet onto you, sends the pet's Growl to grab it back (throttled). Leave it off for melee builds where you want the aggro.")
    ui:Tip(self.petWinRow.cb, "Show pet window", "A small movable readout: level, experience toward the next level, and happiness.")
    ui:Tip(self.cdRow.cb, "Pop cooldowns every press", "Fires the cooldowns listed below whenever they are ready, on every target - and the spec's own, such as Bestial Wrath, where its switch is on.")
    ui:Tip(self.cdEliteRow.cb, "Pop on elites and bosses", "Fires the cooldowns listed below against elite and boss targets, without the switch above.")
end

-- ============================================================
-- refresh body (hunter binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    -- The tab's own values where set, the base otherwise.
    local lay = M.layerOf and M.layerOf(buf) or buf
    local aoe = (type(lay.aoe) == "table") and lay.aoe or {}
    local function get(k) local v = lay[k]; if v == nil then v = buf[k] end; return v end
    local function av(k) local v = aoe[k]; if v == nil then v = get(k) end; return v end

    -- sting dropdowns: None plus the stings the hunter actually knows, plus the
    -- smart "Viper > Serpent" option when both stings are known
    local o = { { label = "None", value = "" } }
    local avail = self:AvailableStingsOf()
    for i = 1, table.getn(avail) do o[i + 1] = { label = avail[i], value = avail[i] } end
    if self:KnowsSpell("Viper Sting") and self:KnowsSpell("Serpent Sting") then
        table.insert(o, { label = "Viper > Serpent", value = "Viper > Serpent" })
    end
    local cur = get("sting") or ""
    local shown, c
    if cur == "" then shown, c = "None", ui.COL.white
    elseif cur == "Viper > Serpent" then shown, c = "Viper > Serpent", ui.COL.white
    elseif self:KnowsSpell(cur) then shown, c = cur, ui.COL.white
    else shown, c = cur .. " (not learned)", ui.COL.red end
    ui:SetDropdown(self.stingDD, o, cur, shown, c)
    ui:SetDropdown(self.stingDD2, o, cur, shown, c)

    -- aspect
    ui:BindCheck(self.aspectRow, get("useAspect"))
    ui:BindCheck(self.rangeSwitchRow, get("rangeSwitch"))
    local aopts = {}
    local aavail = self:AvailableAspectsOf()
    for i = 1, table.getn(aavail) do aopts[i] = { label = aavail[i], value = aavail[i] } end
    local function aspectDD(dd, v, dflt)
        local acur = v or dflt
        local ashown, ac
        if self:KnowsSpell(acur) then ashown, ac = acur, ui.COL.white
        else ashown, ac = acur .. " (not learned)", ui.COL.red end
        ui:SetDropdown(dd, aopts, acur, ashown, ac)
    end
    aspectDD(self.rangedAspDD, get("rangedAspect"), "Aspect of the Hawk")
    aspectDD(self.meleeAspDD, get("meleeAspect"), "Aspect of the Wolf")
    ui:BindCheck(self.manaAspRow, get("useManaAspect"))
    local viperOK = self:KnowsSpell("Aspect of the Viper")
    ui:Color(self.manaBackRow.label, viperOK and ui.COL.white or ui.COL.grey)
    local map = get("manaAspectPct") or 30
    self.manaAspRow.slider:SetValue(map)
    if self.manaAspRow.slider.valText then self.manaAspRow.slider.valText:SetText(map .. "%") end
    ui:SliderEnable(self.manaAspRow.slider, (viperOK and get("useManaAspect")) and true or false)
    local mback = get("manaAspectBackPct") or (map + 15)
    self.manaBackRow.slider:SetValue(mback)
    if self.manaBackRow.slider.valText then self.manaBackRow.slider.valText:SetText(mback .. "%") end
    ui:SliderEnable(self.manaBackRow.slider, (viperOK and get("useManaAspect")) and true or false)

    -- the tables: every row of a field binds to the same value, whichever tab
    -- shows it
    local function b2(row, k) ui:BindCheck2(row, get(k), av(k)) end
    b2(self.markRow, "useHuntersMark");     b2(self.markRow2, "useHuntersMark")
    b2(self.steadyRow, "useSteadyShot")
    b2(self.arcaneRow, "useArcaneShot");    b2(self.arcaneRow2, "useArcaneShot")
    b2(self.multiRow, "useMultiShot");      b2(self.multiRow2, "useMultiShot")
    b2(self.aimedRow, "useAimedShot")
    b2(self.volleyRow, "useVolley")
    b2(self.raptorRow, "useRaptorStrike");  b2(self.raptorRow2, "useRaptorStrike")
    b2(self.mongooseRow, "useMongooseBite"); b2(self.mongooseRow2, "useMongooseBite")
    b2(self.wingRow, "useWingClip");        b2(self.wingRow2, "useWingClip")
    b2(self.lacerateRow, "useLacerate")
    b2(self.carveRow, "useCarve")
    ui:BindCheck(self.trapRow, get("useImmolationTrap"));  ui:BindCheck(self.trapRow2, get("useImmolationTrap"))
    ui:BindCheck(self.explosiveRow, av("useExplosiveTrap")); ui:BindCheck(self.explosiveRow2, av("useExplosiveTrap"))

    -- "Aimed only on Lock and Load" follows the Aimed Shot switch.
    self.aimedProcRow.cb:SetChecked(get("aimedOnlyOnProc") and true or false)
    if get("useAimedShot") then
        self.aimedProcRow.cb:Enable(); ui:Color(self.aimedProcRow.label, ui.COL.white)
    else
        self.aimedProcRow.cb:Disable(); ui:Color(self.aimedProcRow.label, ui.COL.grey)
    end
    ui:BindCheck(self.aimedOpenerRow, get("useAimedOpener"))

    -- spec abilities, pet, cooldowns
    ui:BindCheck(self.kcRow, get("useKillCommand"))
    ui:BindCheck(self.baitedRow, get("useBaitedShot"))
    ui:BindCheck(self.bwRow, get("useBestialWrath"))
    ui:BindCheck(self.petRow, get("petAttack"))
    ui:BindCheck(self.petMeleeRow, get("petMeleeOnly"))
    ui:BindCheck(self.tauntRow, get("petTaunt"))
    ui:BindCheck(self.mendRow, get("useMendPet"))
    ui:BindCheck(self.smartRow, get("smartAoe"))
    local sn = get("smartAoeN") or 3
    self.smartRow.slider:SetValue(sn)
    if self.smartRow.slider.valText then self.smartRow.slider.valText:SetText(">=" .. sn) end
    ui:SliderEnable(self.smartRow.slider, get("smartAoe") and true or false)
    ui:BindCheck(self.lacFirstRow, get("lacerateFirst"), "Lacerate")
    local ttkOn = get("useDebuffTTK") and true or false
    local mt, st = get("markMinTTK") or 8, get("stingMinTTK") or 12
    for _, pair in ipairs({ { self.ttkMarkRow, self.ttkStingRow }, { self.ttkMarkRow2, self.ttkStingRow2 } }) do
        ui:BindCheck(pair[1], ttkOn)
        pair[1].slider:SetValue(mt)
        if pair[1].slider.valText then pair[1].slider.valText:SetText(">=" .. mt .. "s") end
        pair[2].slider:SetValue(st)
        if pair[2].slider.valText then pair[2].slider.valText:SetText(">=" .. st .. "s") end
        ui:SliderEnable(pair[1].slider, ttkOn)
        ui:SliderEnable(pair[2].slider, ttkOn)
    end
    if Aegis_SBR_Pet then self.petWinRow.cb:SetChecked(Aegis_SBR_Pet:Enabled()) end
    local mhp = get("mendPetHp") or 50
    self.mendRow.slider:SetValue(mhp)
    if self.mendRow.slider.valText then self.mendRow.slider.valText:SetText(mhp .. "%") end
    ui:SliderEnable(self.mendRow.slider, get("useMendPet") and true or false)
    ui:BindCheck(self.cdRow, get("popCDs"))
    ui:BindCheck(self.cdEliteRow, get("autoCDElite"))
    ui:BindCheck(self.rfRow, get("useRapidFire") ~= false)
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI framework not loaded. Aegis_SBR_UI.lua is missing or mislabeled in your Aegis_SBR folder, reinstall the files.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
