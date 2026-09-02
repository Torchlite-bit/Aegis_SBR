-- ============================================================
-- Class_Paladin_UI  -  paladin window body for Aegis_SBR
-- Builds and binds only the paladin specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.PALADIN

local function setBlockEnabled(cbItem, sLow, sHigh, on, reason)
    if on then
        cbItem.cb:Enable()
        sLow:EnableMouse(true); sHigh:EnableMouse(true); sLow:SetAlpha(1); sHigh:SetAlpha(1)
        cbItem.label:SetTextColor(0.91, 0.90, 0.88); cbItem.label:SetText(cbItem.baseText)
    else
        cbItem.cb:Disable()
        sLow:EnableMouse(false); sHigh:EnableMouse(false); sLow:SetAlpha(0.35); sHigh:SetAlpha(0.35)
        cbItem.label:SetTextColor(0.55, 0.55, 0.55); cbItem.label:SetText(cbItem.baseText .. (reason and (" - " .. reason) or ""))
    end
end

M.useScrollLayout = true
-- Tank | Retribution | Healer rail.
--
-- The tab writes `spec`, and `healMode` is derived from it at the top of the
-- rotation - so every existing `cfg.healMode` branch keeps working untouched
-- while the panel gains a third page.
--
-- STEP ONE, deliberately: Tank, Solofarming and DPS show the SAME sections.
-- Nothing about the rotation differs between them yet. Splitting the pages first
-- and the behaviour second means the layout can be judged on its own, before any
-- rotation change is in the way of reading it.
--
-- The internal key for the DPS page stays "retri", so profiles written before
-- the rename keep working; only the label changed.
M.specTabs = {
    field = "spec", default = "retri",
    tabs = {
        { key = "tank",  label = "Tank",
          sub  = "This tab is also the active mode. Protection: threat, mitigation, block.",
          tip1 = "Protection melee rotation.", tip2 = "Selecting this tab also makes it the active mode. All three melee pages are still identical - the differences come next." },
        { key = "solo",  label = "Solofarming",
          sub  = "This tab is also the active mode. Solo: kill things without a healer behind you.",
          tip1 = "Questing and farming on your own.", tip2 = "Selecting this tab also makes it the active mode. All three melee pages are still identical - the differences come next." },
        { key = "retri", label = "DPS",
          sub  = "This tab is also the active mode. Group damage: seals, judgement, strikes.",
          tip1 = "Group damage melee rotation.", tip2 = "Selecting this tab also makes it the active mode. All three melee pages are still identical - the differences come next." },
        { key = "heal",  label = "Healer",
          sub  = "This tab is also the active mode. While it is active, the melee settings are ignored.",
          tip1 = "Holy one-button group healing.", tip2 = "Selecting this tab also makes it the active mode." },
    },
}

-- ============================================================
-- build body (paladin controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    local function set(field)  return function(v) if ui.buf then ui.buf[field] = v; ui:Refresh() end end end
    local function sset(key)   return function(v) if ui.buf then ui.buf.spells[key] = v; ui:Refresh() end end end

    -- Tank: Lay on Hands only. A bubble drops every point of threat, so it is
    -- not offered here at all - see the tooltip.
    L:Header("Emergency", "tank")
    self.lohRow = L:Row{ label = "Lay on Hands below", spell = "Lay on Hands",
        slider = { key = "tankLohPct", min = 0, max = 50, step = 5, suffix = "%", onChange = set("tankLohPct") } }

    -- DPS: both, each with its own threshold and either one usable alone. The
    -- bubble goes first because five minutes is a far cheaper cooldown than an
    -- hour; Lay on Hands takes over while it is down. That order is the
    -- rotation's, not this panel's - the two steps simply run in it.
    --
    -- The same two profile fields as the tank and healer pages, so a profile
    -- carries one threshold per spell no matter which page set it.
    L:Header("Emergency", { retri = true, solo = true })
    self.panicDpsRow = L:Row{ label = "Divine Shield below", spell = "Divine Shield",
        slider = { key = "panicPct", min = 0, max = 60, step = 5, suffix = "%", onChange = set("panicPct") } }
    self.lohDpsRow = L:Row{ label = "Lay on Hands below", spell = "Lay on Hands",
        slider = { key = "tankLohPct", min = 0, max = 50, step = 5, suffix = "%", onChange = set("tankLohPct") } }
    self.panicHealRow = L:Row{ label = "Under the bubble, heal to",
        slider = { key = "panicHealTo", min = 0, max = 100, step = 5, suffix = "%", onChange = set("panicHealTo") } }

    -- Solofarming keeps itself alive with the same heal engine the healer page
    -- uses, aimed at nobody but you - so the controls are the same ones, and
    -- they write the same profile fields.
    L:Header("Self-healing", "solo")
    self.selfSoloRow = L:Row{ label = "Heal yourself below",
        slider = { key = "healSelfPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healSelfPct") } }
    self.hsSoloRow = L:Row{ key = "useHolyShock", label = "Holy Shock below", spell = "Holy Shock", onToggle = set("useHolyShock"),
        slider = { key = "holyShockPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("holyShockPct") } }
    self.ratioSoloRow = L:Row{ label = "Holy Light below",
        slider = { key = "ratioHealthy", min = 0, max = 100, step = 5, suffix = "%", onChange = set("ratioHealthy") } }
    self.reloadSoloRow = L:Row{ key = "healReloadCS", label = "Strike only to reset Holy Shock", onToggle = set("healReloadCS") }

    L:Header("Seals", { tank = true, solo = true, retri = true })
    self.debuffDD = L:Dropdown("seal_debuff", "Debuff", 200, function(v) if ui.buf then ui.buf.seals.debuff = v; ui:Refresh() end end)
    self.damageDD = L:Dropdown("seal_damage", "Damage", 200, function(v) if ui.buf then ui.buf.seals.damage = v; ui:Refresh() end end)

    L:Header("Strikes", { tank = true, solo = true, retri = true })
    self.spellCB = {}
    -- Two toggles drive the strikes. One alone means exactly that strike; both
    -- on reveals the strategy dropdown below.
    self.spellCB.holyStrike = L:Row{ key = "holyStrike", label = "Holy Strike", spell = "Holy Strike", onToggle = sset("holyStrike") }
    self.spellCB.crusaderStrike = L:Row{ key = "crusaderStrike", label = "Crusader Strike", spell = "Crusader Strike", onToggle = sset("crusaderStrike") }
    self.strikeStyleDD, self.strikeStyleLbl = L:Dropdown("strikeStyle", "Both on", 190, set("strikeStyle"))
    self.downrankRow = L:Row{ key = "strikeDownrank", label = "Downrank when low", onToggle = set("strikeDownrank") }

    L:Header("Spells", { tank = true, solo = true, retri = true })
    self.spellCB.holyShield = L:Row{ key = "holyShield", label = "Holy Shield", spell = "Holy Shield", onToggle = sset("holyShield") }
    self.spellCB.hammerOfWrath = L:Row{ key = "hammerOfWrath", label = "Hammer of Wrath", spell = "Hammer of Wrath", onToggle = sset("hammerOfWrath") }
    self.spellCB.repentance = L:Row{ key = "repentance", label = "Repentance", spell = "Repentance", onToggle = sset("repentance") }
    self.spellCB.consecration = L:Row{ key = "consecration", label = "Consecration", spell = "Consecration", onToggle = sset("consecration") }
    self.consecManaRow = L:Row{ key = "consecInMana", label = "Consecration also in mana recovery", onToggle = set("consecInMana") }
    self.consecStillRow = L:Row{ key = "consecStill", label = "Only while standing still", onToggle = set("consecStill") }
    self.consecCountRow = L:Row{ label = "Only with this many enemies",
        slider = { key = "consecMinTargets", min = 0, max = 5, step = 1, suffix = "", onChange = set("consecMinTargets") } }
    self.spellCB.exorcism = L:Row{ key = "exorcism", label = "Exorcism", spell = "Exorcism", onToggle = sset("exorcism") }
    self.twistRow = L:Row{ key = "sealTwist", label = "Seal twisting", onToggle = set("sealTwist") }

    L:Header("Mana management", { tank = true, solo = true, retri = true })
    self.manaRow = L:Row{ key = "manaManage", label = "Mana management", spell = "Seal of Wisdom", onToggle = set("manaManage") }
    self.manaLowRow = L:Row{ label = "Switch below",
        slider = { key = "manaLow", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaLow") } }
    self.manaHighRow = L:Row{ label = "Back above",
        slider = { key = "manaHigh", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaHigh") } }
    self.weaveRow = L:Row{ key = "manaWeave", label = "Judgement weaving", onToggle = set("manaWeave"),
        slider = { key = "manaWeaveMin", min = 0, max = 100, step = 5, suffix = "%", onChange = set("manaWeaveMin") } }
    self.wisdomRow = L:Row{ key = "manaWisdomDebuff", label = "Wisdom debuff in mana mode", onToggle = set("manaWisdomDebuff") }

    L:Header("HP management", { tank = true, solo = true, retri = true })
    self.hpRow = L:Row{ key = "hpManage", label = "HP management", spell = "Seal of Light", onToggle = set("hpManage") }
    self.hpLowRow = L:Row{ label = "Switch below",
        slider = { key = "hpLow", min = 0, max = 100, step = 5, suffix = "%", onChange = set("hpLow") } }
    self.hpHighRow = L:Row{ label = "Back above",
        slider = { key = "hpHigh", min = 0, max = 100, step = 5, suffix = "%", onChange = set("hpHigh") } }

    -- Every section below is tagged "heal". They were untagged when first added
    -- and therefore showed up on the Tank/Damage tab as well, which is exactly
    -- the noise the tab rail exists to prevent.
    L:Header("Healing", "heal")
    self.panicRow = L:Row{ label = "Emergency bubble below",
        slider = { key = "panicPct", min = 0, max = 60, step = 5, suffix = "%", onChange = set("panicPct") } }
    self.healAtRow = L:Row{ label = "Heal members below",
        slider = { key = "healThreshold", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healThreshold") } }
    self.selfRow = L:Row{ label = "Heal yourself below",
        slider = { key = "healSelfPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("healSelfPct") } }
    -- The one knob that decides Flash of Light against Holy Light, and the
    -- button that drives it to either end.
    self.ratioHealthyRow = L:Row{ label = "Holy Light below",
        slider = { key = "ratioHealthy", min = 0, max = 100, step = 5, suffix = "%", onChange = set("ratioHealthy") } }
    self.hpsBtn = L:Button{ label = "Toggle HPS mode", onClick = function()
        if ui.buf then M:ToggleHPS(ui.buf); ui:Refresh() end
    end }


    L:Header("Dispel", "heal")
    self.cureRow = L:Row{ key = "useCure", label = "Cure afflictions", spell = "Cleanse", onToggle = set("useCure") }
    self.curePctRow = L:Row{ label = "Cure first above",
        slider = { key = "curePct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("curePct") } }

    L:Header("Ranks", { heal = true, solo = true })
    self.folMaxRow = L:Row{ label = "Flash of Light max rank",
        slider = { key = "folMaxRank", min = 1, max = 7, step = 1, suffix = "", onChange = set("folMaxRank") } }
    self.folMinRow = L:Row{ label = "Flash of Light min rank",
        slider = { key = "folMinRank", min = 1, max = 7, step = 1, suffix = "", onChange = set("folMinRank") } }
    self.hlMaxRow = L:Row{ label = "Holy Light max rank",
        slider = { key = "hlMaxRank", min = 1, max = 9, step = 1, suffix = "", onChange = set("hlMaxRank") } }
    self.hlMinRow = L:Row{ label = "Holy Light min rank",
        slider = { key = "hlMinRank", min = 1, max = 9, step = 1, suffix = "", onChange = set("hlMinRank") } }

    L:Header("Overheal", "heal")
    self.ohRow = L:Row{ label = "Cancel cast at",
        slider = { key = "overhealCancel", min = 0, max = 100, step = 5, suffix = "%", onChange = set("overhealCancel") } }
    self.ohDelayRow = L:Row{ label = "not before",
        slider = { key = "overhealCancelDelay", min = 0, max = 2, step = 0.5, suffix = "s", onChange = set("overhealCancelDelay") } }

    L:Header("Holy Shock", "heal")
    self.holyShockRow = L:Row{ key = "useHolyShock", label = "Holy Shock emergencies", spell = "Holy Shock", onToggle = set("useHolyShock"),
        slider = { key = "holyShockPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("holyShockPct") } }
    self.healReloadRow = L:Row{ key = "healReloadCS", label = "Reload with Crusader Strike", onToggle = set("healReloadCS") }

    -- Holy Strike: the switch and its two thresholds together. The switch used
    -- to sit three sections further down, away from the numbers governing it.
    L:Header("Holy Strike", "heal")
    self.healSplashRow = L:Row{ key = "healSplashHS", label = "Use Holy Strike", onToggle = set("healSplashHS") }
    self.hsMinHPRow = L:Row{ label = "Group member below",
        slider = { key = "hsMinHP", min = 50, max = 100, step = 1, suffix = "%", onChange = set("hsMinHP") } }
    self.hsMinTargetsRow = L:Row{ label = "and at least this many",
        slider = { key = "hsMinTargets", min = 1, max = 5, step = 1, suffix = "", onChange = set("hsMinTargets") } }
    self.hsPriorityRow = L:Row{ key = "hsPriority", label = "Before healing", onToggle = set("hsPriority") }

    L:Header("Damage fillers", "heal")
    self.fillerHoWRow = L:Row{ key = "healFillerHoW", label = "Hammer of Wrath", spell = "Hammer of Wrath", onToggle = set("healFillerHoW") }
    self.fillerConsecRow = L:Row{ key = "healFillerConsec", label = "Consecration", spell = "Consecration", onToggle = set("healFillerConsec") }
    -- Same field as the row in Spells: one setting, shown on whichever tab you
    -- happen to be looking at.
    self.consecStillHealRow = L:Row{ key = "consecStill", label = "Only while standing still", onToggle = set("consecStill") }
    self.fillerExoRow = L:Row{ key = "healFillerExo", label = "Exorcism", spell = "Exorcism", onToggle = set("healFillerExo") }
    self.fillerManaRow = L:Row{ label = "Stop below",
        slider = { key = "healFillerMana", min = 0, max = 90, step = 5, suffix = "%", onChange = set("healFillerMana") } }

    -- The switches that reorder the queue, cheapest to explain first. "Use
    -- priority list" sits LAST because the block it unfolds docks directly
    -- beneath it: a switch and the thing it reveals belong next to each other,
    -- not with three unrelated rows in between.
    L:Header("Heal priority", "heal")
    self.prioTargetRow = L:Row{ key = "healPrioTarget", label = "Your target first", onToggle = set("healPrioTarget") }
    self.aggroRow = L:Row{ key = "healAggro", label = "Prefer who is under attack", onToggle = set("healAggro") }
    self.precastRow = L:Row{ key = "healPrecast", label = "Pre-heal who has aggro", onToggle = set("healPrecast") }
    self.petPrioRow = L:Row{ label = "Pet priority",
        slider = { key = "petPriority", min = 0, max = 2, step = 1, suffix = "", onChange = set("petPriority") } }
    self.prioRow = L:Row{ key = "healPrio", label = "Use priority list", onToggle = set("healPrio") }

    -- Seven rows, every one of them meaningless while the switch above is off -
    -- so they only exist while it is on.
    L:Header("Priority list", "heal", function()
        return ui.buf and ui.buf.healPrio and true or false
    end)
    self.prioAddBtn = L:Button{ label = "Add target", onClick = function()
        if ui.buf then M:PrioAdd(ui.buf, UnitName("target")); ui:Refresh() end
    end }
    self.prioClearBtn = L:Button{ label = "Clear", onClick = function()
        if ui.buf then ui.buf.healPrioList = {}; ui:Refresh() end
    end }
    -- Five slots is a party plus one; a raid MT/OT pair fits in the top two,
    -- which are the only positions that carry their own handicap anyway.
    self.prioBtns = {}
    for i = 1, 5 do
        local idx = i
        self.prioBtns[idx] = L:Button{ label = idx .. ".", onClick = function()
            if ui.buf then M:PrioRemove(ui.buf, idx); ui:Refresh() end
        end }
    end

    -- Raid settings get their own area rather than riding along with the
    -- priority switches: subgroups are a raid concept and mean nothing in a
    -- party, so they should not add a row to a five-man player's window.
    --
    -- The open/closed state is UI-only and deliberately NOT stored in the
    -- profile: which blocks you have expanded is not a setting, and it has no
    -- business in a saved profile or an export.
    L:Header("Raid", "heal")
    self.groupsBtn = L:Button{ label = "Subgroups", onClick = function()
        M.groupsOpen = not M.groupsOpen
        ui:Refresh()
    end }

    L:Header("Subgroups", "heal", function() return M.groupsOpen and true or false end)
    self.groupBtns = {}
    for i = 1, 8 do
        local idx = i
        self.groupBtns[idx] = L:Button{ label = "Group " .. idx, onClick = function()
            if not ui.buf then return end
            if type(ui.buf.raidGroupSkip) ~= "table" then ui.buf.raidGroupSkip = {} end
            if ui.buf.raidGroupSkip[idx] then ui.buf.raidGroupSkip[idx] = nil
            else ui.buf.raidGroupSkip[idx] = true end
            ui:Refresh()
        end }
    end

    L:Header("Mana management", "heal")
    self.healManaSelfRow  = L:Row{ key = "healManaSelf",  label = "Seal of Wisdom (self mana)",  spell = "Seal of Wisdom", onToggle = set("healManaSelf") }
    self.healManaJudgeRow = L:Row{ key = "healManaJudge", label = "Judge Wisdom (group mana)",   spell = "Seal of Wisdom", onToggle = set("healManaJudge") }
    self.healJudgeHLRow   = L:Row{ key = "healJudgeHL",   label = "Pre-load Holy Judgement",     spell = "Judgement", onToggle = set("healJudgeHL") }

    -- Last section on every tab: which Goblin Brainwashing Device slot this
    -- tab answers to. Untagged, so it shows on all of them and always reports
    -- the tab you are looking at.
    ui:BuildGobboRow(L)

    L:Finish()

    ui:Tip(self.cureRow.cb, "Cure afflictions", "Remove curses, poisons, diseases and magic from the group with whatever your class has for it - here: Poison, Disease and Magic (Cleanse), or Poison and Disease (Purify).", "Off by default. A dispel costs a global cooldown that would otherwise be a heal, and only what you can actually remove is ever considered.")
    ui:Tip(self.curePctRow.slider, "Cure first above", "The crossover between curing and healing, read off the WORST-HURT member. Above it the affliction comes first; below it the heal does.", "At 90 the group is cleansed first and topped up from 90 to 100 afterwards - the right order when the affliction is doing more damage than the missing tenth of a bar. 0 makes curing always yield, 100 makes it always come first.")

    ui:Tip(self.panicDpsRow.slider, "Divine Shield below", "Below this share of your health, everything stops and Divine Shield goes up. 0 is off.", "Tried first, because five minutes is a far cheaper cooldown than an hour. Skipped while Forbearance is on you or one is already up, and Lay on Hands below then takes over. Note it drops your threat - which is a feature here and the reason the tank page does not offer it.")
    ui:Tip(self.panicHealRow.slider, "Under the bubble, heal to", "While Divine Shield holds, heal yourself until you reach this much health, then carry on fighting. 0 is off.", "Ten seconds of immunity is the only completely safe casting time a paladin gets - no damage, so no pushback and no dying mid-cast. Reaching the goal ends it, and so does the bubble dropping; nothing is carried over into the moment you can be hit again. Lay on Hands is never used on top of a bubble at all - there is nothing to heal against while nothing can hurt you.")
    ui:Tip(self.lohDpsRow.slider, "Lay on Hands below", "Below this share of your health, Lay on Hands is cast on yourself. 0 is off.", "The deeper of the two: it heals you to full and costs no threat, but drains all your mana and runs on an hour's cooldown. Set it lower than the shield above, so it is only reached once the cheap answer is unavailable.")
    ui:Tip(self.lohRow.slider, "Lay on Hands below", "Below this share of your own health, Lay on Hands is cast on yourself before anything else. 0 is off.", "The tank's version of the healer's emergency bubble, and deliberately a different spell: a bubble drops every point of threat you have built, which hands the pull to somebody who cannot survive it. Lay on Hands costs no threat - it does cost all your mana, which is why it sits behind a threshold you set yourself.")
    ui:Tip(self.selfSoloRow.slider, "Heal yourself below", "Below this share of your health the rotation heals you instead of hitting things. 0 never heals.", "The same engine the healer page uses, aimed at nobody but you - so Holy Shock, Flash of Light and Holy Light are all chosen the same way, Holy Judgement's speed-up included.")
    ui:Tip(self.hsSoloRow.cb, "Holy Shock below", "Holy Shock as the instant self-heal, for when a cast would arrive too late.", "It cannot be pushed back, which is what makes it the answer while four things are hitting you. The strike setting below exists to keep it coming back.")
    ui:Tip(self.ratioSoloRow.slider, "Holy Light below", "Holy Light is only used under this health, and only when no Flash of Light is big enough to cover the deficit.", "Your talents cut pushback by most of it, so a cast heal is a real option here rather than a gamble.")
    ui:Tip(self.reloadSoloRow.cb, "Strike only to reset Holy Shock", "Crusader Strike is used when - and only when - Holy Shock is on cooldown and Blessed Strikes can bring it back.", "Farming, the strikes are not a damage source: Holy Strike's returns to you are halved and both strikes share one cooldown, so spending it on anything but the reset costs you the self-heal it would have bought. The damage comes from Consecration, the aura proc and your blocks.")
    ui:Tip(self.debuffDD, "Debuff seal", "Judged once to apply its debuff to the target.", "Autoattacks keep the debuff up afterwards.")
    ui:Tip(self.damageDD, "Damage seal", "Judged continuously for damage.", "Leaves no debuff, so it never overwrites the one above.")

    ui:Tip(self.spellCB.holyShield.cb,     "Holy Shield",     "Cast right after the strike, before seals.", "Fires whenever its own cooldown is ready.")
    ui:Tip(self.spellCB.hammerOfWrath.cb,  "Hammer of Wrath", "Execute, used only at or below 20 percent target HP.")
    ui:Tip(self.spellCB.repentance.cb,     "Repentance",      "Two spells wearing one name: a 6s crowd control where it lands, and 20 seconds of holy damage on every melee swing where the target is IMMUNE to that control - which bosses generally are.", "Which one a creature gives cannot be known in advance, so it is learned once per creature type and remembered between sessions. Immune: cast on cooldown, it is a damage cooldown there. Not immune: only to stop a cast, since any damage breaks the control instantly in a group. The one probing cast is spent only on elites, bosses, or something measurably long-lived - the damage pays out over 20 seconds of swings, which a mob dying in five cannot do.")
    ui:Tip(self.spellCB.consecration.cb,   "Consecration (AoE)", "AoE filler, cast on cooldown while this is on (also /sbr aoe).", "Held during mana recovery unless the option below is on. The two rows under it can restrict it further: a minimum enemy count, and standing still.")
    -- One setting, two rows (Spells on the melee tabs, Damage fillers on the
    -- healer tab), so the text is written once.
    local csTip1 = "Holds Consecration until you have been standing still for a couple of seconds."
    local csTip2 = "When you are moving the mobs usually are too, so the patch lands on ground everybody is about to leave: the mana is spent and the damage is not dealt. It waits for a short DWELL rather than the instant you stop, because stopping is not the same as staying - a step to reposition is a fraction of a second of standing still. Turn it off to have it on cooldown regardless; a tank who repositions constantly may prefer that, since a held Consecration is threat not made. Without SuperWoW movement cannot be measured and this never blocks anything."
    ui:Tip(self.consecStillRow.cb, "Only while standing still", csTip1, csTip2)
    ui:Tip(self.consecCountRow.slider, "Only with this many enemies", "How many enemies must be standing in the patch before it is worth casting. Off at 0, which casts on cooldown as before.",
        "1.12 has no API for this, so the count comes from the NAMEPLATES the client is drawing - SuperWoW turns each one into a unit that can be asked its distance. With nameplates switched off there is nothing to enumerate, and rather than read that as zero and silently stop casting, the count is treated as unknown and Consecration goes out. Enemies you cannot see are not counted; this is not a radar.")
    ui:Tip(self.consecStillHealRow.cb, "Only while standing still", csTip1, csTip2)
    ui:Tip(self.consecManaRow.cb, "Consecration also in mana recovery", "Keeps casting Consecration even while mana recovery is running, instead of holding it until mana is back up.", "Mana recovery LATCHES - on below 'Switch below', off only at 'Back above' - so with a wide band it can stay on all fight and keep Consecration suppressed. If yours never fires, this is why.")
    ui:Tip(self.spellCB.exorcism.cb,       "Exorcism",        "Strong nuke, used on cooldown but only against Undead and Demon targets.", "Held during mana recovery.")
    ui:Tip(self.spellCB.holyStrike.cb, "Holy Strike", "Shares the 6s strike cooldown with Crusader Strike.", "With Vengeful Strikes it grants Holy Might. Even untalented it returns mana and heals the group.")
    ui:Tip(self.spellCB.crusaderStrike.cb, "Crusader Strike", "Shares the 6s strike cooldown with Holy Strike.", "Builds Zeal. Tank: with Righteous Strikes it also loads the block buff Zealous Defense.")
    ui:Tip(self.strikeStyleDD, "Both-on strategy", "Used only when BOTH strikes are enabled. Enable a single strike alone to force just that one.", "Auto DPS keeps Zeal and, if talented, Holy Might up. Tank block keeps Zealous Defense loaded, else strikes for aggro.")
    ui:Tip(self.downrankRow.cb, "Downrank when low", "Use lower ranks of Holy/Crusader Strike as raw mana drops, to keep swinging while leveling.", "Full rank until mana nears a rank's cost. A large pool rarely downranks.")

    ui:Tip(self.manaRow.cb, "Mana management", "Below the lower value, hold Seal of Wisdom to recover mana.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.hpRow.cb, "HP management", "Below the lower value, hold Seal of Light to recover health.", "Above the upper value, return to normal damage seals.")
    ui:Tip(self.weaveRow.cb, "Judgement weaving", "During mana recovery, weave the DAMAGE seal in and judge it for extra damage.", "This does NOT put Seal of Wisdom on the target - that is the 'Wisdom debuff' option below.")
    ui:Tip(self.weaveRow.slider, "Skip weaving below", "Below this mana, no new weave is started.", "A weave already started always finishes, so leave room for one full cycle.")
    ui:Tip(self.twistRow.cb, "Seal twisting (experimental)", "Holds the damage seal judge until just before the next swing.", "Needs a damage seal. Tune in game, timing depends on latency.")
    ui:Tip(self.wisdomRow.cb, "Wisdom debuff in mana mode", "During mana recovery, judge Seal of Wisdom onto the TARGET (Judgement of Wisdom) instead of your configured debuff.", "The target then returns mana to everyone attacking it, so the whole group recovers.")

    ui:Tip(self.panicRow.slider, "Emergency bubble below", "Below this share of YOUR health, everything stops and Divine Shield goes up - Divine Protection if you have not learned it yet.", "0 is off, and off is the default: a five minute cooldown that also cuts your damage by 60% is not a decision to make for you. Skipped while Forbearance is on you, since the cast would only fail.")
    ui:Tip(self.healAtRow.slider, "Heal members below", "Members below this health get healed; the attack rotation yields while anyone is below it.", "Also /sbr healat <1-100>.")
    ui:Tip(self.holyShockRow.cb, "Holy Shock emergencies", "Use the instant Holy Shock for an emergency or a hurt unit out of melee range.")
    ui:Tip(self.holyShockRow.cb, "Holy Shock emergencies", "In heal mode Holy Shock is used ONLY as an instant heal, never for damage.", "Fires for an emergency or a hurt unit out of melee range, below the health value on the right.")
    ui:Tip(self.holyShockRow.slider, "Holy Shock below", "Health under which Holy Shock is used as an instant emergency heal.", "Below this same line, Flash of Light is also kept over Holy Light even for a big deficit - faster beats fuller when it's this close. Also /sbr hsat <1-100>. +healing auto-reads from gear; override with /sbr healpower <n>.")
    ui:Tip(self.healReloadRow.cb, "Reload with Crusader Strike", "When Holy Shock is on cooldown, use Crusader Strike to reset it (Blessed Strikes, auto-detected), keeping the emergency instant loaded.", "Uses a GCD, but never fires while anyone is below the Holy Shock line - the heal comes first. Not limited by the filler mana floor.")
    ui:Tip(self.healSplashRow.cb, "Use Holy Strike", "Holy Strike splash-heals everyone near you, so it is used on a HEADCOUNT: enough people scratched, rather than one person hurt badly.", "Used in the quiet moments between heals, once the two thresholds below are met, and never while somebody is under the Holy Shock emergency line. No mana floor: it returns mana rather than costing it.")
    ui:Tip(self.fillerHoWRow.cb, "Hammer of Wrath", "Used in heal mode when a press is left over: nobody needs healing, the seal is up, and the target is inside the execute window.", "Last in the order, below everything the Healer tab is for. Instant and on its own cooldown, so it can never be a heal you gave up - the window simply closes if unused.")
    ui:Tip(self.fillerExoRow.cb, "Exorcism", "Used in heal mode when a press is left over and your target is Undead or Demon.", "On its own cooldown and gated on creature type, so it competes with nothing - the window is either there or it is not.")
    ui:Tip(self.fillerManaRow.slider, "Stop below", "Below this share of mana no filler is used at all and the rest is kept for healing.", "A spare press is not spare mana. The fillers are free only while mana is not what limits you; the moment it is, every point belongs to the group. 0 disables the line and lets the fillers run at any mana.")
    ui:Tip(self.fillerConsecRow.cb, "Consecration", "Used in heal mode when a press is left over and you are standing in melee range.", "The one filler with a real cost: it spends mana that would have been heals, and it makes threat on everything standing in it, which as a healer is a decision rather than a bonus. Held during mana recovery unless the Tank tab's opt-out is set.")
    ui:Tip(self.hsPriorityRow.cb, "Before healing", "Puts Holy Strike ahead of the healing itself: on cooldown, whenever you are in melee range.", "It splash-heals the group and returns mana in the same swing, which a direct heal does not - so a paladin casting only Flash of Light and Holy Light gives both away. The cost is real: a strike takes the global cooldown a heal wanted, so somebody occasionally waits a beat longer. Your control is where you stand. Step out of melee and this switches itself off.")

    ui:Tip(self.hsMinHPRow.slider, "Group member below", "Health at or under which a group member counts toward the Holy Strike trigger. 100% means anyone not at full health counts.", "These two RESTRICT Holy Strike. At the defaults it simply goes out on cooldown, which is what it is for - a damage ability whose splash heal is a bonus. Tighten them only if you want it held back.")
    ui:Tip(self.hsMinTargetsRow.slider, "and at least this many", "How many group members within 10 yards must be under that health before Holy Strike is used. 1 means it is effectively unrestricted.", "Raise it in a raid, where a splash on three scratched people is worth more than a swing. It always yields to direct healing, and never fires while somebody is below the emergency line.")
    ui:Tip(self.hpsBtn, "Toggle HPS mode", "Flips the slider above between its two ends, for switching playstyle in one click.", "High HPS (0%): Holy Light never used - the geared paladin who heals everything with Flash of Light. Normal HPS (100%): Holy Light whenever no Flash of Light can cover the deficit - the levelling paladin, for whom a Flash barely moves the bar.")
    ui:Tip(self.folMaxRow.slider, "Flash of Light max rank", "Highest rank the downranking may reach for. Lower it to force cheaper, smaller heals.")
    ui:Tip(self.folMinRow.slider, "Flash of Light min rank", "Lowest rank that may be chosen, whenever mana allows it. Raise it when the small ranks no longer move the bar.")
    ui:Tip(self.hlMaxRow.slider, "Holy Light max rank", "Highest rank the downranking may reach for.")
    ui:Tip(self.hlMinRow.slider, "Holy Light min rank", "Lowest rank that may be chosen, whenever mana allows it.")
    ui:Tip(self.prioRow.cb, "Use priority list", "On a near tie, heal the listed players first: position 1 before position 2, both before anyone unlisted.", "A handicap, not a strict order: position 2 reads 20% healthier, unlisted players 35%. A dps at 20% still outranks a tank at 90%; a tank at 60% now beats a dps at 45%. Danger always reads real health.")
    ui:Tip(self.precastRow.cb, "Pre-heal who has aggro", "Somebody a mob is attacking is worth topping off even while they are above the heal threshold.", "The damage is already coming; catching it early is cheaper than catching them after. Never fires on a unit at full health - there is nothing to heal.")
    ui:Tip(self.petPrioRow.slider, "Pet priority", "0 never heal pets, 1 only when no player needs healing, 2 treat pets like players.", "A pet you have targeted is always considered, whatever this is set to.")
    ui:Tip(self.ohRow.slider, "Cancel cast at", "Abandon a heal already in flight once this share of it would be pure overheal - somebody else healed first, or the target stopped taking damage.", "0 is off: a started cast always finishes. Cancelling is visible and surprising, so it is opt-in. The mana is saved either way.")
    ui:Tip(self.ohDelayRow.slider, "not before", "Grace period before a cancel may fire, so a cast is never cut the instant it starts.")
    ui:Tip(self.prioTargetRow.cb, "Your target first", "While you have a friendly target selected, it is treated as position 1 - ahead of the list.", "Selecting somebody is the clearest statement of intent there is, so it overrides the list rather than adding to it.")
    ui:Tip(self.aggroRow.cb, "Prefer who is under attack", "A group member something is actually attacking outranks one who is merely sitting at a low bar.", "Aggro is read by chaining unit tokens: the mob a group member is fighting, and who that mob is hitting back. A member losing health also counts, which covers a mob nobody has targeted. It only ever pushes the SAFE down the order.")
    ui:Tip(self.selfRow.slider, "Heal yourself below", "Your own health is only worth a cast below this. 0 treats you like any other group member.", "A healer has more ways out of trouble than anyone else - stepping out of a cleave is often enough - so 70% on yourself is rarely worth the cast that somebody else needs.")
    ui:Tip(self.groupsBtn, "Subgroups", "Folds out a row per raid subgroup, each switching between healed and skipped.", "Only meaningful in a raid; a party has no subgroups. Folded away by default because eight rows is a lot of window for something most runs never touch. Whether it is folded is not saved - it is not a setting.")
    ui:Tip(self.prioAddBtn, "Add target", "Adds your current target to the end of the priority list.", "Names, not raid slots, so the list survives a regroup. Typically the main tank first and yourself second.")
    ui:Tip(self.prioClearBtn, "Clear", "Empties the priority list.")
    ui:Tip(self.ratioHealthyRow.slider, "Holy Light below", "Holy Light is only used on a target under this health, and only when no Flash of Light is big enough to cover the deficit.", "60% is the recommended value. At 0 Holy Light is never used; at 100 it is used whenever the fast heal cannot cover the need. The Holy Judgement buff overrides it either way.")
    ui:Tip(self.healManaSelfRow.cb, "Seal of Wisdom (self mana)", "In melee downtime, keep Seal of Wisdom up so your own swings return mana to you.", "Only fires when nobody needs healing, so it never delays a heal.")
    ui:Tip(self.healManaJudgeRow.cb, "Judge Wisdom (group mana)", "Also judge Seal of Wisdom onto the mob (Judgement of Wisdom), so everyone attacking it gets mana back.", "Judgement uses a GCD and you cannot heal during that global, so it only fires when nobody needs healing.")
    ui:Tip(self.healJudgeHLRow.cb, "Pre-load Holy Judgement", "With the Holy Judgement talent, casting Judgement makes your NEXT Holy Light one second faster. This casts it during downtime so the speed-up is already banked when the next big heal is needed.", "Downtime only. Judging to speed up a heal already due would cost a global cooldown: 1.5s + 1.5s is slower than the plain 2.5s heal. 'Judge Wisdom' above grants the same buff anyway.")
end

-- ============================================================
-- refresh body (paladin binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    local function sealDD(dd, list, cur)
        cur = cur or ""
        local o = { { label = "(none)", value = "" } }
        local avail = self:AvailableSealsOf(list)
        for i = 1, table.getn(avail) do o[i + 1] = { label = avail[i], value = avail[i] } end
        local shown, c
        if cur == "" then shown, c = "(none)", ui.COL.white
        elseif self:KnowsSpell(cur) then shown, c = cur, ui.COL.white
        else shown, c = cur .. " (not learned)", ui.COL.red end
        ui:SetDropdown(dd, o, cur, shown, c)
    end
    sealDD(self.debuffDD, self.DEBUFF_SEALS, buf.seals.debuff)
    sealDD(self.damageDD, self.DAMAGE_SEALS, buf.seals.damage)

    local function setCB(key) ui:BindCheck(self.spellCB[key], buf.spells[key]) end
    setCB("holyStrike"); setCB("crusaderStrike")
    setCB("holyShield"); setCB("hammerOfWrath"); setCB("repentance")
    setCB("consecration"); setCB("exorcism")

    -- The mana-recovery override only means anything while Consecration itself
    -- is on, so it greys out with it.
    ui:BindCheck(self.consecManaRow, buf.consecInMana)
    ui:BindCheck(self.consecStillRow, buf.consecStill ~= false)
    ui:BindCheck(self.consecStillHealRow, buf.consecStill ~= false)
    if not buf.spells.consecration then
        self.consecManaRow.cb:Disable()
        ui:Color(self.consecManaRow.label, ui.COL.grey)
        self.consecStillRow.cb:Disable()
        ui:Color(self.consecStillRow.label, ui.COL.grey)
    end
    if not buf.healFillerConsec then self.consecStillHealRow.cb:Disable() end

    -- Both-on strategy: only meaningful when BOTH strikes are enabled. With a
    -- single strike on it is used exclusively, so the box is greyed and its text
    -- explains why.
    local styleOpts = {
        { label = "Auto DPS",   value = "autodps" },
        { label = "Tank block", value = "tankblock" },
    }
    local styleLabel = { autodps = "Auto DPS", tankblock = "Tank block" }
    local scur = buf.strikeStyle or "autodps"
    local bothOn = (buf.spells.holyStrike and buf.spells.crusaderStrike) and true or false
    if bothOn then
        ui:SetDropdown(self.strikeStyleDD, styleOpts, scur, styleLabel[scur] or scur, ui.COL.white)
        self.strikeStyleDD:Enable(); self.strikeStyleDD:SetAlpha(1)
        ui:Color(self.strikeStyleLbl, ui.COL.white)
    else
        ui:SetDropdown(self.strikeStyleDD, styleOpts, scur, "enable both strikes", ui.COL.grey)
        self.strikeStyleDD:Disable(); self.strikeStyleDD:SetAlpha(0.5)
        ui:Color(self.strikeStyleLbl, ui.COL.grey)
    end

    self.downrankRow.cb:SetChecked(buf.strikeDownrank and true or false)

    -- seal twisting needs a damage seal to time the judge against
    local twistOK = buf.seals.damage ~= "" and self:KnowsSpell(buf.seals.damage)
    self.twistRow.cb:SetChecked(buf.sealTwist and true or false)
    if twistOK then
        self.twistRow.cb:Enable()
        self.twistRow.label:SetText("Seal twisting"); ui:Color(self.twistRow.label, ui.COL.white)
    else
        self.twistRow.cb:Disable()
        self.twistRow.label:SetText("Seal twisting - needs damage seal"); ui:Color(self.twistRow.label, ui.COL.grey)
    end

    local manaOK = self:KnowsSpell("Seal of Wisdom")
    local manaReason = "not learned"
    setBlockEnabled(self.manaRow, self.manaLowRow.slider, self.manaHighRow.slider, manaOK, manaReason)
    self.manaRow.cb:SetChecked(buf.manaManage and true or false)
    self.manaLowRow.slider:SetValue(buf.manaLow or 0);  self.manaLowRow.slider.valText:SetText((buf.manaLow or 0) .. "%")
    self.manaHighRow.slider:SetValue(buf.manaHigh or 0); self.manaHighRow.slider.valText:SetText((buf.manaHigh or 0) .. "%")

    -- Judgement weaving: only meaningful when mana management is on and a damage seal exists
    local dmg = buf.seals.damage
    local weaveOK = manaOK and buf.manaManage and dmg ~= "" and self:KnowsSpell(dmg)
    self.weaveRow.cb:SetChecked(buf.manaWeave and true or false)
    self.weaveRow.slider:SetValue(buf.manaWeaveMin or 0)
    self.weaveRow.slider.valText:SetText((buf.manaWeaveMin or 0) .. "%")
    if weaveOK then
        self.weaveRow.cb:Enable()
        ui:Color(self.weaveRow.label, ui.COL.white)
        self.weaveRow.slider:EnableMouse(true); self.weaveRow.slider:SetAlpha(1)
    else
        self.weaveRow.cb:Disable()
        ui:Color(self.weaveRow.label, ui.COL.grey)
        self.weaveRow.slider:EnableMouse(false); self.weaveRow.slider:SetAlpha(0.35)
    end

    -- Wisdom debuff in mana mode: meaningful when mana management is on and SoW is known
    local wisdomOK = manaOK and buf.manaManage
    self.wisdomRow.cb:SetChecked(buf.manaWisdomDebuff and true or false)
    if wisdomOK then
        self.wisdomRow.cb:Enable()
        self.wisdomRow.label:SetText("Wisdom debuff in mana mode"); ui:Color(self.wisdomRow.label, ui.COL.white)
    else
        self.wisdomRow.cb:Disable()
        self.wisdomRow.label:SetText("Wisdom debuff - enable mana management"); ui:Color(self.wisdomRow.label, ui.COL.grey)
    end

    local hpOK = self:KnowsSpell("Seal of Light")
    local hpReason = "not learned"
    setBlockEnabled(self.hpRow, self.hpLowRow.slider, self.hpHighRow.slider, hpOK, hpReason)
    self.hpRow.cb:SetChecked(buf.hpManage and true or false)
    self.hpLowRow.slider:SetValue(buf.hpLow or 0);  self.hpLowRow.slider.valText:SetText((buf.hpLow or 0) .. "%")
    self.hpHighRow.slider:SetValue(buf.hpHigh or 0); self.hpHighRow.slider.valText:SetText((buf.hpHigh or 0) .. "%")

    -- Healing section
    self.healAtRow.slider:SetValue(buf.healThreshold or 75); self.healAtRow.slider.valText:SetText((buf.healThreshold or 75) .. "%")
    -- Holy Shock emergencies. The stored preference defaults on so it just works
    -- the moment Holy Shock is trained; but while the spell is not learned the
    -- toggle is shown OFF (not a misleading lit "on") and greyed. The saved value
    -- stays untouched, so learning the spell lights it up automatically.
    local hsKnown = self:KnowsSpell("Holy Shock")
    ui:BindCheck(self.holyShockRow, buf.useHolyShock and hsKnown, "Holy Shock")
    self.holyShockRow.slider:SetValue(buf.holyShockPct or 50); self.holyShockRow.slider.valText:SetText((buf.holyShockPct or 50) .. "%")
    -- 0 means "no restriction" and must survive: an `or` fallback would turn a
    -- deliberate 0 into whatever default sat on the right of it.
    -- The heal controls live in the heal-only "Healing" card, which the tab rail
    -- hides entirely on the Damage tab, so no mode gating is needed here.
    if not hsKnown then
        self.holyShockRow.cb:Disable()
    end

    -- Reload Holy Shock (CS): greyed unless Blessed Strikes plus both spells are
    -- present, since the reset cannot happen otherwise.
    local reloadOK = self:BlessedReloadUsable()
    ui:BindCheck(self.healReloadRow, (buf.healReloadCS ~= false) and reloadOK)
    if reloadOK then
        self.healReloadRow.label:SetText("Reload with Crusader Strike"); ui:Color(self.healReloadRow.label, ui.COL.white)
    else
        self.healReloadRow.cb:Disable()
        self.healReloadRow.label:SetText("Reload with Crusader Strike - needs Blessed Strikes"); ui:Color(self.healReloadRow.label, ui.COL.grey)
    end

    ui:BindCheck(self.healSplashRow, buf.healSplashHS ~= false)
    ui:BindCheck(self.hsPriorityRow, buf.hsPriority)
    ui:BindCheck(self.fillerHoWRow, buf.healFillerHoW, "Hammer of Wrath")
    ui:BindCheck(self.fillerConsecRow, buf.healFillerConsec, "Consecration")
    ui:BindCheck(self.fillerExoRow, buf.healFillerExo, "Exorcism")
    local fmv = buf.healFillerMana or 40
    self.fillerManaRow.slider:SetValue(fmv)
    if self.fillerManaRow.slider.valText then
        self.fillerManaRow.slider.valText:SetText(fmv > 0 and ("<" .. fmv .. "%") or "off")
    end
    -- Only means anything while at least one filler is on.
    local anyFiller = (buf.healFillerHoW or buf.healFillerConsec or buf.healFillerExo) and true or false
    ui:SliderEnable(self.fillerManaRow.slider, anyFiller)
    -- BindCheck re-enables every box it binds, so the greying has to follow it.
    if buf.healSplashHS == false then self.hsPriorityRow.cb:Disable() end
    local cmt = buf.consecMinTargets or 0
    self.consecCountRow.slider:SetValue(cmt)
    if self.consecCountRow.slider.valText then
        self.consecCountRow.slider.valText:SetText(cmt > 0 and (">=" .. cmt) or "off")
    end
    ui:SliderEnable(self.consecCountRow.slider, buf.spells.consecration and true or false)

    -- Heal-mode mana upkeep. Both need Seal of Wisdom; shown OFF and greyed while
    -- it is not learned, without touching the stored value.
    local sowKnown = self:KnowsSpell("Seal of Wisdom")
    ui:BindCheck(self.healManaSelfRow,  buf.healManaSelf  and sowKnown, "Seal of Wisdom")
    ui:BindCheck(self.healManaJudgeRow, buf.healManaJudge and sowKnown, "Seal of Wisdom")
    ui:BindCheck(self.healJudgeHLRow, buf.healJudgeHL)

    local hsv = buf.hsMinHP or 100
    self.hsMinHPRow.slider:SetValue(hsv)
    if self.hsMinHPRow.slider.valText then self.hsMinHPRow.slider.valText:SetText("<=" .. hsv .. "%") end
    ui:SliderEnable(self.hsMinHPRow.slider, buf.healSplashHS ~= false)

    local hstv = buf.hsMinTargets or 1
    self.hsMinTargetsRow.slider:SetValue(hstv)
    if self.hsMinTargetsRow.slider.valText then self.hsMinTargetsRow.slider.valText:SetText(hstv > 1 and (">=" .. hstv) or "any") end
    ui:SliderEnable(self.hsMinTargetsRow.slider, buf.healSplashHS ~= false)

    ui:BindCheck(self.prioRow, buf.healPrio)
    ui:BindCheck(self.prioTargetRow, buf.healPrioTarget)
    ui:BindCheck(self.aggroRow, buf.healAggro)
    ui:BindCheck(self.precastRow, buf.healPrecast)

    local pp = buf.petPriority or 1
    self.petPrioRow.slider:SetValue(pp)
    if self.petPrioRow.slider.valText then
        local lbl = "never"
        if pp == 1 then lbl = "spare only" elseif pp >= 2 then lbl = "like players" end
        self.petPrioRow.slider.valText:SetText(lbl)
    end

    local phc = buf.panicHealTo or 0
    self.panicHealRow.slider:SetValue(phc)
    if self.panicHealRow.slider.valText then
        self.panicHealRow.slider.valText:SetText(phc > 0 and (phc .. "%") or "off")
    end
    ui:SliderEnable(self.panicHealRow.slider, (buf.panicPct or 0) > 0)

    local ohv = buf.overhealCancel or 0
    self.ohRow.slider:SetValue(ohv)
    if self.ohRow.slider.valText then
        self.ohRow.slider.valText:SetText(ohv > 0 and (">=" .. ohv .. "%") or "off")
    end
    local ohd = buf.overhealCancelDelay or 0.5
    self.ohDelayRow.slider:SetValue(ohd)
    if self.ohDelayRow.slider.valText then
        self.ohDelayRow.slider.valText:SetText(string.format("%.1fs", ohd))
    end
    ui:SliderEnable(self.ohDelayRow.slider, ohv > 0)

    self.groupsBtn.value:SetText(M.groupsOpen and "|cff9fd8ffhide|r" or "|cff9fd8ffshow|r")
    local skip = buf.raidGroupSkip or {}
    for i = 1, table.getn(self.groupBtns) do
        self.groupBtns[i].value:SetText(skip[i] and "|cffff8844skipped|r" or "|cff44ff44healed|r")
    end
    -- Two rows per field: the tank page and the DPS page write the same profile
    -- values, so both copies follow it.
    local lohv = buf.tankLohPct or 0
    local lohRows = { self.lohRow, self.lohDpsRow }
    for i = 1, table.getn(lohRows) do
        local row = lohRows[i]
        row.slider:SetValue(lohv)
        if row.slider.valText then
            row.slider.valText:SetText(lohv > 0 and ("<" .. lohv .. "%") or "off")
        end
    end

    local pv = buf.panicPct or 0
    local panicRows = { self.panicRow, self.panicDpsRow }
    for i = 1, table.getn(panicRows) do
        local row = panicRows[i]
        row.slider:SetValue(pv)
        if row.slider.valText then
            row.slider.valText:SetText(pv > 0 and ("<" .. pv .. "%") or "off")
        end
    end

    ui:BindCheck(self.hsSoloRow, buf.useHolyShock, "Holy Shock")
    ui:BindCheck(self.reloadSoloRow, buf.healReloadCS)
    local hsp = buf.holyShockPct or 50
    self.hsSoloRow.slider:SetValue(hsp)
    if self.hsSoloRow.slider.valText then self.hsSoloRow.slider.valText:SetText("<" .. hsp .. "%") end
    local rhs = buf.ratioHealthy or 60
    self.ratioSoloRow.slider:SetValue(rhs)
    if self.ratioSoloRow.slider.valText then self.ratioSoloRow.slider.valText:SetText("<" .. rhs .. "%") end

    local selfv = buf.healSelfPct or 40
    self.selfSoloRow.slider:SetValue(selfv)
    if self.selfSoloRow.slider.valText then
        self.selfSoloRow.slider.valText:SetText(selfv > 0 and ("<" .. selfv .. "%") or "off")
    end
    self.selfRow.slider:SetValue(selfv)
    if self.selfRow.slider.valText then
        self.selfRow.slider.valText:SetText(selfv > 0 and ("<" .. selfv .. "%") or "off")
    end
    local plist = buf.healPrioList or {}
    for i = 1, table.getn(self.prioBtns) do
        local nm = plist[i]
        self.prioBtns[i].value:SetText(nm or "|cff666666(empty)|r")
    end

    local ranks = {
        { self.folMaxRow, buf.folMaxRank or 7 },
        { self.folMinRow, buf.folMinRank or 1 },
        { self.hlMaxRow,  buf.hlMaxRank or 9 },
        { self.hlMinRow,  buf.hlMinRank or 1 },
    }
    for i = 1, table.getn(ranks) do
        local row, v = ranks[i][1], ranks[i][2]
        row.slider:SetValue(v)
        if row.slider.valText then row.slider.valText:SetText(v) end
    end

    local rhv = buf.ratioHealthy or 60
    self.ratioHealthyRow.slider:SetValue(rhv)
    if self.ratioHealthyRow.slider.valText then
        self.ratioHealthyRow.slider.valText:SetText(rhv > 0 and ("<" .. rhv .. "%") or "never")
    end
    if not sowKnown then
        self.healManaSelfRow.cb:Disable()
        self.healManaJudgeRow.cb:Disable()
    end

    ui:BindCheck(self.cureRow, buf.useCure, "Cleanse")
    local cpv = buf.curePct or 90
    self.curePctRow.slider:SetValue(cpv)
    if self.curePctRow.slider.valText then self.curePctRow.slider.valText:SetText(">" .. cpv .. "%") end
    ui:SliderEnable(self.curePctRow.slider, buf.useCure and true or false)

end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
