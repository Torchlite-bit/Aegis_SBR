-- ============================================================
-- Class_Warrior_UI  -  warrior window body for Aegis_SBR
-- Builds and binds only the warrior specific controls. The shared
-- window shell and profile management live in Aegis_SBR_UI.lua.
-- Uses the shell's scroll layout (M.useScrollLayout).
-- ============================================================

local M = Aegis_SBR.classes.WARRIOR
M.useScrollLayout = true

-- Maps each boolean toggle to the spell it depends on, so the label can
-- show "(not learned)" while leveling. nil = no spell (pure behaviour flag).
local SPELL_OF = {
    useMortalStrike = "Mortal Strike", useBloodthirst = "Bloodthirst",
    useShieldSlam = "Shield Slam", useWhirlwind = "Whirlwind", useSlam = "Slam",
    useOverpower = "Overpower", useRevenge = "Revenge", useExecute = "Execute",
    useSunder = "Sunder Armor", useThunderClap = "Thunder Clap",
    useHeroicStrike = "Heroic Strike", useCleave = "Cleave",
    useCharge = "Charge", useIntercept = "Intercept", useRend = "Rend", useHamstring = "Hamstring",
    useSweeping = "Sweeping Strikes", useDeathWish = "Death Wish",
    useRecklessness = "Recklessness", useBerserkerRage = "Berserker Rage",
    useBloodrage = "Bloodrage", useShieldBlock = "Shield Block",
    useBattleShout = "Battle Shout", useDemoShout = "Demoralizing Shout",
    useMasterStrike = "Master Strike",
    useConcussionBlow = "Concussion Blow",
    usePummel = "Pummel", useShieldBash = "Shield Bash",
    stanceDance = nil, aoeMode = nil, popCDs = nil, autoCDElite = nil,
    slamCancelForExecute = nil,
}

-- ============================================================
-- build body (warrior controls)
-- ============================================================
function M:BuildBody(ui, parent)
    local L = ui:NewLayout(parent)
    self.cb = {}
    L:MacroNote()

    -- helpers: place via the layout cursor and register into self.cb for RefreshBody.
    local function set(key) return function(v) if ui.buf then ui.buf[key] = v; ui:Refresh() end end end
    -- a concept single-row toggle, registered like the old one()/pair() so the
    -- RefreshBody bind loop over self.cb keeps working unchanged.
    local function row(key, label)
        local it = L:Row{ key = key, label = label, spell = SPELL_OF[key], onToggle = set(key) }
        self.cb[key] = it
        return it
    end

    L:Header("Strikes")
    row("useMortalStrike", "Mortal Strike")
    row("useBloodthirst", "Bloodthirst")
    row("useShieldSlam", "Shield Slam")
    row("useMasterStrike", "Master Strike")
    row("useConcussionBlow", "Concussion Blow")
    row("useWhirlwind", "Whirlwind")
    row("useSlam", "Slam")
    row("useCharge", "Charge opener")
    row("useIntercept", "Intercept")
    row("useRend", "Rend bleed")
    row("useHamstring", "Hamstring (slow)")

    L:Header("Reactive & Execute")
    row("useOverpower", "Overpower")
    row("useExecute", "Execute")
    row("slamCancelForExecute", "Cancel Slam for Execute")
    row("useRevenge", "Revenge")
    row("stanceDance", "Stance dancing")
    self.stanceDD = L:Dropdown("homeStance", "Home stance", 150, set("homeStance"))

    self.intSection = L:Header("Interrupt")
    row("usePummel", "Pummel")
    row("useShieldBash", "Shield Bash")
    row("interruptHealsOnly", "Heal-only interrupt")
    -- Minimum cast length worth kicking (0 = interrupt anything). Greyed until
    -- an interrupt toggle is on, like every owning-toggle slider above.
    self.minTimeRow = L:Row{ label = "Min cast time",
        slider = { key = "interruptMinTime", min = 0, max = 3, step = 0.5, suffix = "s", onChange = set("interruptMinTime") } }
    self.waitAtRow = L:Row{ label = "Wait at cast %",
        slider = { key = "interruptWaitAt", min = 0, max = 100, step = 5, suffix = "%", onChange = set("interruptWaitAt") } }
    -- Inclusion list for heal-only: user-added spell names (Turtle custom
    -- heals) on top of the built-in vanilla heal list. Button row + fixed
    -- numbered slots, same shape as the heal-target lists on the healers.
    self.intHealAddBtn = L:Button{ label = "Add heal spell", onClick = function()
        if not ui.buf then return end
        Aegis_SBR_UI:ShowDialog({
            prompt = "Heal spell to interrupt (name only, no rank — e.g. Greater Heal)",
            withInput = true,
            onAccept = function(txt)
                if ui.buf and txt then M:IntHealAdd(ui.buf, txt); ui:Refresh() end
            end,
        })
    end }
    self.intHealClearBtn = L:Button{ label = "Clear heal list", onClick = function()
        if ui.buf then ui.buf.interruptHealList = {}; ui:Refresh() end
    end }
    self.intHealBtns = {}
    local slotY0 = L.y  -- cursor Y where the first slot row sits
    for i = 1, 8 do
        local idx = i
        self.intHealBtns[idx] = L:Button{ label = idx .. ".", onClick = function()
            if ui.buf then M:IntHealRemove(ui.buf, idx); ui:Refresh() end
        end }
    end
    self.intHealBaseY = slotY0
    self.intHealStep = (slotY0 - L.y) / table.getn(self.intHealBtns)

    L:Header("Threat / AoE")
    row("aoeMode", "AoE mode")
    -- Auto AoE carries its pack-size slider on the same row (toggle+slider,
    -- like Sunder Armor). When it flips, AoE enters/exits on the drawn enemy
    -- count instead of the manual toggle. Registered into self.cb so the
    -- RefreshBody bind loop treats it like any other toggle. Enabling clears
    -- any /sbr aoe override so the count decides until the manual line is pulled.
    self.autoAoeRow = L:Row{ key = "aoeAuto", label = "Auto AoE", spell = nil,
        onToggle = function(v) if not ui.buf then return end
            ui.buf.aoeAuto = v
            if v then ui.buf.aoeOverride = nil end
            ui:Refresh() end,
        slider = { key = "aoeThreshold", min = 2, max = 5, step = 1, suffix = "", onChange = set("aoeThreshold") } }
    self.cb.aoeAuto = self.autoAoeRow
    row("aoeCc", "Respect CC")
    row("useSweeping", "Sweeping Strikes")
    -- Sunder Armor toggle carries its stack-count slider on the same row (like the
    -- other classes' toggle+slider rows), instead of a separate slider at the foot
    -- of the section. Registered into self.cb so the RefreshBody bind loop and
    -- the "(not learned)" handling treat it like any other toggle.
    self.sunderRow = L:Row{ key = "useSunder", label = "Sunder Armor", spell = "Sunder Armor", onToggle = set("useSunder"),
        slider = { key = "sunderStacks", min = 1, max = 5, step = 1, suffix = "", onChange = set("sunderStacks") } }
    self.cb.useSunder = self.sunderRow
    row("useThunderClap", "Thunder Clap")
    row("tcSkipIfUp", "Thunder Clap: skip if the target has it")
    row("useCleave", "Cleave (AoE)")

    L:Header("Shouts")
    row("useBattleShout", "Battle Shout")
    row("useDemoShout", "Demoralizing Shout")

    L:Header("Rage dump")
    row("useHeroicStrike", "Heroic Strike")
    self.dumpRow = L:Row{ label = "Dump above rage",
        slider = { key = "dumpRage", min = 0, max = 100, step = 5, suffix = "", onChange = set("dumpRage") } }
    self.wwRow = L:Row{ label = "WW above rage",
        slider = { key = "wwExcess", min = 0, max = 100, step = 5, suffix = "", onChange = set("wwExcess") } }

    L:Header("Cooldowns")
    row("popCDs", "Pop cooldowns")
    row("autoCDElite", "Auto on elite")
    row("useDeathWish", "Death Wish")
    row("useRecklessness", "Recklessness")
    row("useBerserkerRage", "Berserker Rage")
    row("useBloodrage", "Bloodrage")
    -- Bloodrage's two thresholds were readable settings with no way to change
    -- them in game, and bloodrageHealthPct was in no preset at all - only the
    -- `or 25` fallback in the gate. Both defaults here match what the gate
    -- already resolved to, so nothing fires differently until they are moved.
    self.brRageRow = L:Row{ label = "Bloodrage below rage",
        slider = { key = "bloodrageRage", min = 0, max = 100, step = 5, suffix = "", onChange = set("bloodrageRage") } }
    self.brHpRow = L:Row{ label = "Bloodrage min HP %",
        slider = { key = "bloodrageHealthPct", min = 0, max = 100, step = 5, suffix = "%", onChange = set("bloodrageHealthPct") } }
    row("useShieldBlock", "Shield Block")
    self.burstMinHpRow = L:Row{ label = "Min target HP %",
        slider = { key = "burstMinHp", min = 0, max = 100, step = 5, suffix = "%", onChange = set("burstMinHp") } }

    L:Finish()

    -- ---- tooltips ----
    ui:Tip(self.cb.useMortalStrike.cb, "Mortal Strike", "Arms primary strike, used on cooldown.")
    ui:Tip(self.cb.useBloodthirst.cb,  "Bloodthirst",   "Fury primary strike, used on cooldown.")
    ui:Tip(self.cb.useShieldSlam.cb,   "Shield Slam",   "Protection primary strike. Requires a shield equipped.")
    ui:Tip(self.cb.useConcussionBlow.cb, "Concussion Blow", "Protection talent, opt-in and off by default. When enabled it fires on cooldown, placed just below your spec's primary strike so it never delays Shield Slam.", "Free - it costs no rage and generates 10 on use - instant, 20s cooldown, 3s stun, and it ignores armor. Appears once talented; the row greys out until then. Being free threat that funds your next Shield Slam, there is a case for placing it higher than it currently sits; say so and it moves.")
    ui:Tip(self.cb.useMasterStrike.cb, "Master Strike", "Arms talent, opt-in and off by default (it is mainly a PvP pick). When enabled it fires on cooldown, placed just below your spec's primary strike so it never delays Mortal Strike / Bloodthirst / Shield Slam.", "Appears once talented; the row greys out until then.")
    ui:Tip(self.cb.useSlam.cb, "Slam", "Filler with a cast time, for 2H builds.", "Held back in two cases: while a primary strike (Mortal Strike, Bloodthirst, Shield Slam, Whirlwind) is off cooldown and only short of rage - Slam is the cheapest ability here and used to take those presses - and when its cast would run past your next white swing. That cast is 2.5s, or 1.9s with Improved Slam, so against a slow two-hander the second gate is tight by nature. An unreadable swing timer lets Slam through.")
    ui:Tip(self.cb.useWhirlwind.cb,    "Whirlwind",     "Berserker stance. On cooldown in AoE, or as a single-target rage dump above the Whirlwind rage value.", "In AoE it is now checked BEFORE your primary strike: it hits everything in range where Mortal Strike hits one, so letting the primary take that press was a loss.")
    ui:Tip(self.cb.useSlam.cb,         "Slam",          "2H filler. Has a cast time and resets your swing, so it can feel awkward with heavy spam.")
    ui:Tip(self.cb.useCharge.cb,       "Charge opener", "Leveling opener: Charge the target from range on the pull (Battle Stance, out of combat only). Stance-dances to Battle if needed.", "The client blocks Charge once you are in combat, so it only fires on the initial gap-close.")
    ui:Tip(self.cb.useIntercept.cb,    "Intercept",     "Berserker Stance gap closer, 10 rage, generates rage on hit. Fires only when you are ALREADY in Berserker - it never stance-dances, and combat state is not part of the test, so it works on the pull and mid-fight alike. Range: any target out of your melee reach, up to its own 25 yd.", "In Berserker with 10 rage or more it takes the press before Charge, so a berserker spends the rage on the leap instead of on a dance to Battle. From any other stance it stays silent and the Charge opener remains the pull. Off by default; enable per profile.", "Refused (target out of reach) and it holds off for a few seconds instead of re-picking on every press.")
    ui:Tip(self.cb.useRend.cb,         "Rend bleed",    "Keeps Rend up on the target (Battle or Defensive stance). A leveling tool - off by default, since it is rarely used at endgame.", "Skipped during Execute so rage goes to Execute instead.")
    ui:Tip(self.cb.useOverpower.cb,    "Overpower",     "Battle stance only. Fires in the short window after the target dodges you. Enable Stance dancing to auto-swap to Battle.")
    ui:Tip(self.cb.useExecute.cb,      "Execute",       "Top single-target priority below 20% target HP. Suppresses the rage dump so rage feeds Execute.")
    ui:Tip(self.cb.slamCancelForExecute.cb, "Cancel Slam for Execute",
        "Interrupts a Slam that is still casting when Execute comes up, so the press lands the Execute instead of waiting the cast out.",
        "Only fires once Execute could actually go out. Slam starts the global cooldown when the cast starts and the cast is longer than the cooldown, so cancelling any earlier would throw the Slam away without gaining the Execute.")
    ui:Tip(self.cb.useRevenge.cb,      "Revenge",       "Defensive stance only. Fires after you block, dodge, or parry.")
    ui:Tip(self.cb.stanceDance.cb,     "Stance dancing (experimental)", "Auto-swaps to Battle for Overpower (and to Defensive for Revenge when home is Defensive), then drifts back to your home stance.", "Also swaps to Battle for a Sweeping Strikes pop while you are in Berserker, at any pack size, and holds the stance until the charges are spent. That dance needs Tactical Mastery 5/5 (below it the swap keeps too little rage to be worth a press), and it dumps a Whirlwind first when rage is above 25, since a stance swap caps what carries over.", "Costs a little rage per swap; tune in game.")
    ui:Tip(self.stanceDD,              "Home stance",   "The stance the rotation returns to when dancing. Berserker for most DPS, Defensive for tanking.")
    ui:Tip(self.cb.usePummel.cb,         "Pummel",        "Berserker Stance. Instant interrupt, off the global cooldown, 10s cooldown.", "Fires only while the target is mid-cast (needs SuperWoW cast events). If the target is not casting, the nearest casting enemy in melee range is kicked instead, without changing your target. Consumes the press for that press, but off-GCD means the next press gets the strike back immediately. No stance dance for interrupts: the stance internal CD is too slow.")
    ui:Tip(self.cb.useShieldBash.cb,     "Shield Bash",    "Any stance (needs a shield equipped). Instant interrupt, off the global cooldown, 12s cooldown.", "Fires only while the target is mid-cast (needs SuperWoW cast events). If the target is not casting, the nearest casting enemy in melee range is kicked instead, without changing your target. With Gag Order talented it silences the target for 5s after the interrupt. Off-GCD; consumes that one press only.")
    ui:Tip(self.cb.interruptHealsOnly.cb, "Heal-only interrupt", "Only interrupt when the cast in progress is a confirmed heal - every vanilla cast/channel-time heal, plus whatever you add to the list below.", "An unrecognised spell name is never interrupted in this mode; it is a filter, so unknown stops the kick rather than passing it. Instant heals (Renew, Rejuvenation) carry no cast time and are never interruptible anyway.")
    ui:Tip(self.minTimeRow.slider,         "Min cast time",      "Only interrupt casts at least this long. Short filler casts keep their interrupt cooldown for the big heal after.", "0 = interrupt anything.")
    ui:Tip(self.waitAtRow.slider, "Wait at cast %", "Hold the kick until the enemy cast reaches this progress threshold.", "0 = interrupt immediately. 50 = wait for the second half. A cast the enemy cancels on its own spends no kick, and a late interrupt delays the heal longer - the cast time already spent counts against the enemy before the cooldown starts. The cost is the risk on a short cast: the wait can end with the cast finished, which is the interrupt throwing its cooldown away to no effect on fast filler. The threshold rides on the cast event's arrival time, so a late START event lands the threshold fraction early.")
    ui:Tip(self.intHealAddBtn,             "Add heal spell",     "Add a Turtle-custom heal name to the heal-only list (name only, no rank). The built-in list already covers every vanilla heal.")
    ui:Tip(self.intHealClearBtn,           "Clear heal list",    "Remove every custom entry; the built-in vanilla heal list stays.")
    ui:Tip(self.intHealBtns[1], "Heal list slots",    "Rows appear as you add heal spells, up to 8. Click a row to remove that entry.")
    ui:Tip(self.cb.aoeMode.cb,         "AoE mode",      "Switches the rage dump to Cleave and uses Whirlwind on cooldown. Flip mid-fight with /sbr aoe.")
    ui:Tip(self.autoAoeRow.cb,         "Auto AoE",      "Decides AoE mode from the enemy count the client draws: on once the pack reaches the slider value, off again when it is back to a single mob.")
    ui:Tip(self.autoAoeRow.slider,     "AoE pack size", "Auto AoE engages when this many enemies are in Whirlwind range (8 yd).")
    ui:Tip(self.cb.aoeCc.cb,           "Respect CC",    "Stands AoE down while a control effect that breaks on damage (Polymorph in any form, Freezing Trap, Sap) is on any enemy in the pack.", "Damage breaks these, so an AoE that catches a sheeped/sapped mob undoes the control. Uses ClassicAPI (Recommended) for enemies other than your target; without it only your target is checked.")
    ui:Tip(self.cb.useSweeping.cb,     "Sweeping Strikes", "Fired on cooldown while AoE mode is on (off the global cooldown).", "Battle Stance only, so with Stance dancing on a Berserker home stance swaps to Battle to pop it and stays there until the charges are spent. The pop itself waits for 30 rage - a stance swap only carries 25 across, so it lands a press or two after the swap rather than on it.")
    ui:Tip(self.cb.useSunder.cb,       "Sunder Armor",  "Leads the rotation in single target: applied up to the stack count beside it, then left to ride. Stands down in a pack (like Slam and Rend), since it only debuffs one enemy.", "Deals no damage of its own, so in AoE the press goes to Whirlwind or Cleave instead. It comes straight back on the first press against a single target.")
    ui:Tip(self.cb.useThunderClap.cb,  "Thunder Clap",  "AoE filler in Battle or Defensive stance - only with at least the auto-AoE number of enemies within its radius, or, with no count, the target in melee range (never during a Charge).")
    ui:Tip(self.cb.tcSkipIfUp.cb, "Skip if the target has it", "No Thunder Clap while the target already carries its slow.")
    ui:Tip(self.cb.useHamstring.cb, "Hamstring", "Keeps the slow on the target (Battle or Berserker stance) - for runners and PvP. Off by default; not in AoE or the execute phase.")
    ui:Tip(self.cb.useCleave.cb,       "Cleave in AoE", "When AoE mode is on, dump rage with Cleave instead of Heroic Strike. When Whirlwind is ready the press is held for it instead, and the rage carries - Heroic Strike is never queued in a pack, since it hits one enemy.")
    ui:Tip(self.sunderRow.slider,          "Sunder stacks", "Apply Sunder Armor until the target carries this many stacks.")
    ui:Tip(self.cb.useBattleShout.cb,  "Battle Shout",  "Keeps the party attack-power buff up. Refreshed only when it is missing or about to expire, and below your strikes so it never delays one.", "Skipped during Execute so rage feeds Execute. On by default.")
    ui:Tip(self.cb.useDemoShout.cb,    "Demoralizing Shout", "Keeps the enemy attack-power reduction on your target, for mitigation (tanking). Re-applied only when it falls off the target. Off by default.", "Uses a debuff slot - mind the raid debuff cap.")
    ui:Tip(self.cb.useHeroicStrike.cb, "Rage dump",     "Queue Heroic Strike (or Cleave in AoE) on the next swing when rage is above the value below.")
    ui:Tip(self.dumpRow.slider,            "Dump above rage", "Only queue the rage dump when rage is at least this high, so you never starve your strikes.")
    ui:Tip(self.wwRow.slider,              "Whirlwind above rage", "Single-target only: also fire Whirlwind when rage is at least this high, to bleed off excess.")
    ui:Tip(self.cb.popCDs.cb,          "Always pop",    "Use the enabled cooldowns whenever they are ready.")
    ui:Tip(self.cb.autoCDElite.cb,     "Auto on elite", "Use the enabled cooldowns only against elite and boss targets. Leave both off to control them manually.")
    ui:Tip(self.burstMinHpRow.slider,  "Min target HP %", "Only pop burst cooldowns (Death Wish, Recklessness, Berserker Rage) when the target is above this health.", "0 = always pop. Prevents wasting a 2-3 min cooldown on a mob that will die in seconds. Applies when Pop cooldowns or Auto on elite is active.")
    ui:Tip(self.cb.autoCDElite.cb,     "Auto on elite", "Use the enabled cooldowns only against elite and boss targets. Leave both off to control them manually.")
    ui:Tip(self.cb.useDeathWish.cb,    "Death Wish",    "Fury cooldown. Part of the burst set governed above.")
    ui:Tip(self.cb.useRecklessness.cb, "Recklessness",  "Berserker stance. Part of the burst set governed above.")
    ui:Tip(self.cb.useBerserkerRage.cb,"Berserker Rage","Berserker stance. Part of the burst set governed above, and it also fires on its own while you are feared - that path ignores the burst settings entirely, because the immunity is a defensive tool and a DPS gate would hide it.", "On Turtle the buff is immune to fear and to incapacitate. Fear is read from ClassicAPI when the DLL is present and from a player debuff scan when it is not, so the response works either way.")
    ui:Tip(self.cb.useBloodrage.cb,    "Bloodrage",     "Fires (off the GCD) whenever rage is under the floor and health is over the floor - before the pull and mid-fight alike.", "Held on the pull press so Charge can go out first: Bloodrage flags you in combat, which disqualifies the out-of-combat Charge for the rest of the pull, and the two cannot share a frame on 1.12. That is the only ordering rule; there is no window. It needs a real attackable target, so standing idle with nothing selected does not spend it.", "Costs 5% health on this server (vanilla charged 16% of base health). That is what the HP floor is for, and it matters much more mid-fight than before the pull - raise it if you are dying.")
    ui:Tip(self.brRageRow.slider,        "Bloodrage below rage", "Only fire Bloodrage when rage is under this.")
    ui:Tip(self.brHpRow.slider,          "Bloodrage min HP %", "Never fire Bloodrage at or below this health - it costs 5% health here, so a top-up is not worth dying for. At 25 a cast can land at worst at 20.", "0 = fire at any health above zero. The default is conservative because the spell now also fires mid-fight.")
    ui:Tip(self.cb.useShieldBlock.cb,  "Shield Block",  "Defensive stance. Used on cooldown to feed Revenge and mitigate.")
end

-- ============================================================
-- refresh body (warrior binding)
-- ============================================================
function M:RefreshBody(ui, buf)
    for key, item in pairs(self.cb) do
        ui:BindCheck(item, buf[key], SPELL_OF[key] or false)
    end

    -- home stance dropdown
    local stanceOpts = {
        { label = "Berserker",    value = "berserker" },
        { label = "Battle",       value = "battle" },
        { label = "Defensive",    value = "defensive" },
        { label = "Don't manage", value = "none" },
    }
    local stanceLabel = { berserker = "Berserker", battle = "Battle", defensive = "Defensive", none = "Don't manage" }
    local cur = buf.homeStance or "berserker"
    ui:SetDropdown(self.stanceDD, stanceOpts, cur, stanceLabel[cur] or cur, ui.COL.white)

    -- sliders
    local ss = buf.sunderStacks or 5
    self.sunderRow.slider:SetValue(ss)
    if self.sunderRow.slider.valText then self.sunderRow.slider.valText:SetText(tostring(ss)) end
    -- the stacks slider follows the Sunder Armor toggle (greyed when off)
    ui:SliderEnable(self.sunderRow.slider, buf.useSunder and true or false)

    -- auto-AoE pack size slider; greyed until Auto AoE is on
    local at = buf.aoeThreshold or 2
    self.autoAoeRow.slider:SetValue(at)
    if self.autoAoeRow.slider.valText then self.autoAoeRow.slider.valText:SetText(tostring(at)) end
    ui:SliderEnable(self.autoAoeRow.slider, buf.aoeAuto and true or false)

    local dr = buf.dumpRage or 60
    self.dumpRow.slider:SetValue(dr)
    if self.dumpRow.slider.valText then self.dumpRow.slider.valText:SetText(tostring(dr)) end

    local ww = buf.wwExcess or 60
    self.wwRow.slider:SetValue(ww)
    if self.wwRow.slider.valText then self.wwRow.slider.valText:SetText(tostring(ww)) end

    -- Bloodrage thresholds; greyed until the Bloodrage toggle is on
    local br = buf.bloodrageRage or 30
    self.brRageRow.slider:SetValue(br)
    if self.brRageRow.slider.valText then self.brRageRow.slider.valText:SetText(tostring(br)) end
    ui:SliderEnable(self.brRageRow.slider, buf.useBloodrage and true or false)

    local brhp = buf.bloodrageHealthPct or 25
    self.brHpRow.slider:SetValue(brhp)
    if self.brHpRow.slider.valText then self.brHpRow.slider.valText:SetText(tostring(brhp) .. "%") end
    ui:SliderEnable(self.brHpRow.slider, buf.useBloodrage and true or false)

    -- interrupt min-time slider; greyed until an interrupt toggle is on
    local mt = buf.interruptMinTime or 0
    self.minTimeRow.slider:SetValue(mt)
    if self.minTimeRow.slider.valText then self.minTimeRow.slider.valText:SetText(tostring(mt)) end
    ui:SliderEnable(self.minTimeRow.slider, (buf.usePummel or buf.useShieldBash) and true or false)

    local waitAt = buf.interruptWaitAt or 0
    self.waitAtRow.slider:SetValue(waitAt)
    if self.waitAtRow.slider.valText then self.waitAtRow.slider.valText:SetText(tostring(waitAt) .. "%") end
    ui:SliderEnable(self.waitAtRow.slider, (buf.usePummel or buf.useShieldBash) and true or false)

    local burstHp = buf.burstMinHp or 0
    self.burstMinHpRow.slider:SetValue(burstHp)
    if self.burstMinHpRow.slider.valText then self.burstMinHpRow.slider.valText:SetText(tostring(burstHp) .. "%") end
    ui:SliderEnable(self.burstMinHpRow.slider, (buf.popCDs or buf.autoCDElite) and true or false)

    -- heal-only inclusion list slots: one row per entry, up to the built
    -- pool of 8. Hide unused rows and their hairlines, then shrink the card
    -- to the visible rows - Reflow runs after RefreshBody and re-stacks the
    -- sections below using the updated height.
    local ilist = buf.interruptHealList or {}
    local pool = table.getn(self.intHealBtns)
    local n = table.getn(ilist)
    if n > pool then n = pool end
    for i = 1, pool do
        local b = self.intHealBtns[i]
        if i <= n then
            b.value:SetText(ilist[i] or "|cff666666(empty)|r")
            b:Show()
            if b.sep then b.sep:Show() end
        else
            b:Hide()
            if b.sep then b.sep:Hide() end
        end
    end
    if self.intSection then
        local h = -self.intHealBaseY + n * self.intHealStep + 4
        if h < 4 then h = 4 end
        self.intSection.h = h
        self.intSection.cont:SetHeight(h)
    end
end

-- Open the shared window for this class.
M.OpenConfig = function(mod)
    if not Aegis_SBR_UI then
        Aegis_SBR:Throttle("UI not ready yet, try again in a moment.")
        return
    end
    Aegis_SBR_UI:Toggle()
end
