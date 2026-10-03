# Aegis_SBR — Turtle WoW 1.18.1 Custom Mechanics

Confirmed Turtle-specific facts that DIVERGE from vanilla 1.12 and therefore change
rotations. Keep this separate from `rotations.md` so the audit can cite mechanics
directly. Turtle has shipped two major "Class Change" batches (CC1, CC2/1.17.2) plus
1.18.0/1.18.1 tuning. Verify against the live client for edge cases; Turtle's custom
client can differ from stock 1.12.

## Talent trees (reference)
- Warrior: https://talents.turtlecraft.gg/warrior
- Paladin: https://talents.turtlecraft.gg/paladin
- Hunter: https://talents.turtlecraft.gg/hunter
- Rogue: https://talents.turtlecraft.gg/rogue
- Priest: https://talents.turtlecraft.gg/priest
- Shaman: https://talents.turtlecraft.gg/shaman
- Mage: https://talents.turtlecraft.gg/mage
- Warlock: https://talents.turtlecraft.gg/warlock
- Druid: https://talents.turtlecraft.gg/druid

Primary sources: Turtle WoW Wiki (turtle-wow.fandom.com), forum.turtle-wow.org /
forum.turtlecraft.gg theorycraft threads, r/turtlewow, community class guides.

**Spell / talent / item database (for exact IDs, ranks, cooldowns, coefficients):**
- Tortoise-WoW DB viewer: https://xian55.github.io/tortoise-db-viewer/ (a JS single-page app —
  browse it in a browser; a raw fetch only returns the empty shell).
- Backing data repos (static files — fetchable/greppable directly, better for pulling exact
  numbers into code/docs): database `https://github.com/Penqle/tortoise-wow`, viewer source
  `https://github.com/Xian55/tortoise-db-viewer`.
- Use these to replace `[?]` "needs verification" numbers in `docs/rotations.md` with exact
  values (spell IDs for `SpellInfo` matching, cooldowns, DoT durations, spell-power
  coefficients) — but Turtle rebalances via patches, so confirm against the live client for
  anything the engine depends on.

## Paladin (largest divergence)
- **Offensive Holy Shock REMOVED**; Holy Shock is heal-only (row 5). Old ranged "Shockadin"
  intentionally removed.
- New baseline melee abilities: **Holy Strike** and **Crusader Strike**, sharing ONE **6s
  cooldown**. Holy Strike: instant, 43% spell-power coefficient (damage), 5% healing-power
  (heal — it's an AoE group heal).
- **Blessed Strikes** talent: Crusader Strike has 20/40/60/80/100% chance to reset Holy
  Shock's cooldown; after such a reset, Holy Shock's GCD is reduced by 1s.
- Holy is a **melee-capable healer**: melee + Holy Strike (group heal) + Crusader Strike
  (reset Holy Shock for instant, un-silenceable heals). Can be >30% of endgame healing.
- Ret: keep a Seal up always; **Seal of Righteousness generally preferred** (triggers
  Windfury/Crusader enchants). Holy Strike is mana-free and returns mana with Judgement of
  Wisdom.
- Hand spells (BoP/Freedom/Sacrifice) no longer overwrite normal Blessings.

## Hunter
- **Survival is a MELEE archetype** (dev-branded "Melee Hunter"). Carve = 10-yd cone AoE,
  up to 5 targets, **shares cooldown with Multi-Shot**. Stinging Nettle Lacing: Mongoose
  Bite + Fire traps apply reduced-duration Serpent Sting. Wing Clip's "Phantom Strike"
  triggers on-swing effects (Windfury etc.) without damage.
- **Aimed Shot is baseline (lvl 20)**; **"Trueshot" renamed Steady Shot** (first MM
  capstone). MM endgame = Auto Shot + Steady Shot weave; Aimed Shot often dropped.
- Aspect of the Wolf now grants melee AP and no longer blocks ranged abilities.
- Piercing Shots: crit Aimed/Steady/Multi bleeds (no threat).

## Warrior
- **Sunder Armor costs 10 rage** and is the first GCD for damage and threat builds. The
  addon now uses the Turtle cost and leads with Sunder when enabled.
- **Flurry shortens Slam cast time**: Turtle's Flurry implementation applies its haste to
  Slam, reducing 2.5s to about 1.92s at the maximum confirmed haste. `SlamCastTime()` now
  applies the live Flurry modifier; autoattack timing continues to use `UnitAttackSpeed`.
- **Pummel works in Battle or Berserker stance** (vanilla restricted it to Berserker).
  Confirmed by the user in play; a Battle-stance warrior with Pummel on was passing up
  89 Chain Lightning kicks in a single captured `/sbr log` because the code held the
  vanilla-only stance gate. `STANCE_REQ["Pummel"]` carries both stances today.
- **Berserker Rage grants immunity to fear and incapacitate.** Confirmed by the user
  on 1.18.1 from the spell tooltip. Two consequences the rotation has to respect: the
  player cannot be feared or incapacitated while it is up, so anything reacting to it
  is necessarily PRE-emptive (there is no "break the fear now" case, because the client
  refuses casts during loss of control — see `Aegis_SBR.lua:1948`, "Can't do that while
  stunned"). And it is an active cast on this server, not the vanilla passive proc,
  which is why the addon drives it with `PickExtra` and reads it with `HasBuff`.

## Shaman
- **Elemental core is Flame Shock + Molten Blast + Lightning Bolt**, not LB-spam. Molten
  Blast (Rekindled Flame) refreshes Flame Shock. **Electrify** (replaced Elemental Fury):
  LB/CL stack +2% Nature dmg / +20% spell crit-damage, to 5, passively.
- Nature damage has **no raid-amplification debuff** → Elemental is bottom-tier raid DPS.
- **Lightning Strike** (Enhancement custom capstone): 60% weapon + 20% weapon as Nature,
  10s CD, consumes/empowers a shield charge. Stormstrike + Lightning Strike **no longer
  trigger chance-on-hit effects** (e.g. Windfury) on Turtle.
- **Shaman can TANK** (Turtle-unique, in active dev): Rockbiter affects ALL threat;
  shield-charge avoidance builds; Stoneskin/Strength totems.
- Water Shield exists (mana return / dodge-stacking builds).

## Mage
- **Arcane is a real DPS tree**: Arcane Surge (post-resist proc), Arcane Rupture (buffs
  Missiles), Resonance Cascade (spell duplication), Temporal Convergence (buffs Rupture).
  Arcane Surge GCD doesn't scale with haste (drops off >~30% haste).
- **Fire (1.18.0/1.18.1): Ignite = 4s window**; **Fire Blast applies Scorch stacks**
  (renamed Fire Vulnerability); Blast Wave CD shortened. **Hot Streak**: Fireball/Fire Blast
  crits reduce next Pyroblast cast time.
- **Frost gained Icicles + Flash Freeze + an Ice Barrier damage bonus** (breaks
  Frostbolt-only monotony).

## Rogue
- Combat is the only endgame-viable PvE spec. **Surprise Attack** (Combat capstone): usable
  after dodge, unblockable. **Combo points reset (not lost) on target switch.** Blade Rush
  scales energy regen with agility. Rogues can wield 1H axes.

### Finisher numbers (in-game tooltips, confirmed)
All three upkeep finishers cost **20 energy** — do NOT assume the vanilla 25/35 values.
- **Slice and Dice** (Rank 2): +30% melee attack speed. Base 9/12/15/18/21s for 1-5 CP.
- **Envenom** (Assassination talent): +30% poison effectiveness **and** +30% application
  chance. 12/16/20/24/28s for 1-5 CP. **Not** extended by Improved Blade Tactics.
- **Rupture** (Rank 6): 272/380/504/644/**800** damage over 8/10/12/14/**16**s for 1-5 CP.
- **Eviscerate**: cost not yet captured; assumed higher than the 20 above.

### Improved Blade Tactics (Assassination) — Turtle's SnD duration talent
There is **no "Improved Slice and Dice"** in Turtle; the equivalent is **Improved Blade
Tactics**, 3 ranks, **+45% duration** at 3/3 on *Slice and Dice and Flourish* (tooltip
confirmed). The spell tooltip shows BASE durations, so the talent is invisible there.
At 3/3 the real SnD durations are **13.05 / 17.4 / 21.75 / 26.1 / 30.45s** for 1-5 CP.
Easy to miss because the talent name gives no hint, and it changes the upkeep maths
completely — a 5-CP refresh lasts more than twice a 1-CP one.

### Taste for Blood (Assassination, 2 ranks) — tooltip confirmed at 2/2
Extends Rupture's duration by **6s** and grants **+2% melee damage per combo point** for
that full duration, *"regardless of successful application"* (so a resisted/dodged Rupture
still buffs). At 5 CP that is **+10% melee damage for 22s**. Note **melee** — it does not
touch poison damage, which is where a poison build's damage actually lives (below).

### Measured damage split (full dungeon, lvl-60 Assassination/poison build)
1,209,897 damage, 388.4 DPS. Instant Poison VI **66.2%** · Auto Hit **13.8%** · Noxious
Assault **10.9%** · Eviscerate **7.5%** · Rupture **0.8%** · rest negligible.
Consequences for rotation design on this kind of build:
- **Poisons are two thirds of the damage.** Anything that adds weapon swings or poison
  application is a multiplier on the main damage source: Slice and Dice (+30% swings),
  Envenom (+30% effectiveness and application), and **Noxious Assault, which guarantees
  poison application from BOTH weapons** — its real contribution is far larger than the
  10.9% the meter credits it, because the procs it forces are booked under the poison.
- **Taste for Blood can only lift the melee buckets** (Auto Hit + Noxious Assault +
  Eviscerate ~ 32%), so even at 100% uptime it is worth ~3% overall — and Rupture's own
  DoT measured 0.8%. On short-lived trash, where the 16s DoT never ticks out, Rupture is
  not worth its 5-CP peak; on a boss it is a different calculation.
- Profile used for the measurement: builder Noxious Assault, cpFinish 5, ruptureCP 5,
  `evisExecuteOnly` ON, execute at 20%, SnD + Envenom + Rupture all maintained, cooldowns
  off. Keep this as the baseline when A/B testing rotation changes.

## Priest
- **Discipline reworked into holy-damage support DPS** (Smite/Holy Fire focus). **PW:Shield
  castable in Shadowform.** **Proclaim Champion** (Holy capstone): tank buff (DR, resist,
  mana return to priest, hourly battle-res).

## Warlock
- **Dark Harvest** (Affliction capstone). **Nightfall** procs from Corruption, Dark Harvest,
  and drains. **Malediction** lets Curse of Agony coexist with another curse.
- **Channel lengths are NOT the vanilla ones, and Rapid Deterioration scales them.**
  Dark Harvest is 8s base, Drain Soul **6s** base (vanilla: 15s). The talent shortens the
  channel by the same 3%/rank it takes off Corruption / Curse of Agony / Siphon Life, so at
  2/2 they read **7.52s** and **5.64s** — both confirmed against in-game tooltips. Any code
  reasoning about "can I fit this channel in" must scale by the rank actually taken.

## Druid
- **Powershift Shred** dominant for Feral DPS (bleeds weaker, can't crit). **Savage Bite**
  high threat (removes MCP dependency). **Barkskin (Feral)** defensive.
- **Balance rework**: Insect Swarm + Moonfire DoTs augment Wrath/Starfire nukes; Moonfire
  18s; Sylvan Blessing mana regen; boomkin itemization added (T2.5/AQ40).
- Direct form-to-form shifting; feral consumables allowed.

## Global caps
- **32 buffs / 16 debuffs** per unit — avoid burning debuff slots on low-value applications
  near the cap.

## Required addon stack (recap)
- **SuperWoW**: `CastSpellByName(name[, unit])`, `UNIT_CASTEVENT`, `SpellInfo(id)`, GUIDs.
- **Nampower**: cast queueing/timing (matters for Fire mage Ignite window, hunter shot
  clipping).
- **SuperCleveRoidMacros**: macro conditionals.
