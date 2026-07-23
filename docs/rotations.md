# Aegis_SBR — Rotation & Priority Reference (Turtle WoW 1.18.1)

Source of truth for the **Phase 1 rotation-correctness audit**. For each class/spec, this
lists the intended priority order the engine should execute, per context (Raid / Dungeon /
Leveling). PvP + defensives are Phase 4 (noted only).

**Confidence tags:** `[T]` Turtle-confirmed · `[V]` vanilla assumption · `[?]` needs
in-game verification (dummy-test before shipping). Turtle publishes no official per-spec
rotation guides for most classes; endgame detail is synthesized from the Turtle Wiki
class-change notes, forum theorycrafters, and community guides. Turtle is actively patched
— re-audit after any post-1.18.1 class change.

---

## WARRIOR

### Arms / 2H (raid DPS) `[T]` baseline, `[V]` rotation
Maintain Battle Shout → keep Rend up (2H) → Mortal Strike on CD → Whirlwind → Overpower on
proc (target dodge; Improved Overpower valued) → Slam on free swings → Heroic Strike as
rage dump above ~50 rage → Execute phase <20% HP.

### Fury (raid DPS) `[T]`
Bloodthirst on CD → Whirlwind → Heroic Strike dump (queue >~50 rage) → Execute <20%.
Keep Battle Shout; Death Wish / Recklessness / trinkets in burst windows. Priority-list
model: after each cast, re-evaluate from the top.

### Protection (tank) `[T]`
Charge opener → Sunder Armor to 5 stacks → **Shield Slam = top single-target threat**
(Turtle: scales with attack power in addition to block value; Improved Shield Slam reduces
CD and grants block chance) → Revenge when available (Reprisal talent: +Revenge damage,
chance to refund its rage) → Shield Bash / Shield Slam to dispel magic (Gag Order) →
Heroic Strike rage dump. **Thunder Clap is usable in Defensive Stance** = primary AoE
threat. Demoralizing Shout for AoE mitigation.
- **Known Turtle weakness:** warrior ability threat (Revenge, Sunder) is fixed and does not
  scale with gear — factor this into threat expectations, not the rotation.

### Leveling `[V]`+forum
Arms. Charge → Rend → Demoralizing Shout/Sunder → Heroic Strike; Execute to finish. First
Aid + Cooking strongly advised (high downtime, weak self-buffs).

### PvP/defensive (Phase 4, note only)
Shield Wall (ends early if shield unequipped; Improved Shield Wall moved to row 6),
Recklessness, Retaliation, Death Wish.

---

## PALADIN — biggest Turtle rework; highest divergence from vanilla

Turtle removed offensive Holy Shock and added baseline melee **Holy Strike** + **Crusader
Strike**. Holy Strike: instant, **6s cooldown SHARED with Crusader Strike**, 43% spell-power
coefficient on damage, 5% healing-power on its heal `[T]`. **Blessed Strikes** talent:
Crusader Strike has 20/40/60/80/100% chance to reset Holy Shock's cooldown (and reduces its
GCD by 1s after a reset) `[T]`. Holy Shock is now heal-only. The old ranged "Shockadin" was
intentionally removed.

### Retribution (raid/dungeon DPS) `[T]`
Keep a Seal up at ALL times → Judgement on CD (respect swing timer; never white-swing
seal-less) → **Holy Strike on CD** (mana-free; returns mana via Judgement of Wisdom) → ramp
**Crusader Strike to 3 stacks of Zeal** (corrected — audit P1, resolved: in-game spell
description confirms the Zeal buff caps at 3, not 5 as originally recorded here; matches
Aegis_SBR's existing `ZEAL_STACKS = 3`, so no code change needed) → Consecration if mana
allows.
- Seal choice: **Seal of Righteousness preferred** in most cases (can trigger Windfury /
  Crusader enchants); Seal of Command for slow-weapon burst.
- **Judgement vs. strike order (audit P2), decided — no code change.** Confirmed in-game:
  both the strike and Judgement are plain GCD-consuming instants (the strike does not queue
  on the next swing free of the GCD, correcting a stale code comment that assumed
  otherwise). This makes the research's "Judgement on CD" ahead of the strike a real,
  actionable order question, not a moot one - but the decision is to keep the strike ahead
  of Judgement as Aegis_SBR already does: threat generation on the first Holy Strike matters
  for Protection, and Holy Might/Zeal buff upkeep matters for Retribution, both outweighing
  a Judgement/debuff refresh occasionally waiting one extra press.
- Because CS + Holy Strike share the 6s CD, the practical loop is "one strike / 6s +
  Judgement + reseal."
- **`sealTwist` default off, decided (audit P8) — no change.** The toggle (hold the damage
  seal's Judgement until <0.4s before the next white swing, so the swing never lands
  seal-less) is explicitly experimental and latency-sensitive - built as a trial with no
  guarantee it actually lands correctly on a given connection, so it stays opt-in rather than
  a safe default.

### Holy (raid/dungeon heal) `[T]` — melee-capable healer
At range: Flash of Light spam (tank), Holy Light (big heals), Holy Shock (instant,
resettable, emergencies). Min-max path: MELEE the boss — Holy Strike (AoE group heal) +
Crusader Strike (reset Holy Shock). >30% of endgame healing can come from melee. Daybreak
capstone: crit-heal leaves a 12s +20% healing-taken / +5% max-HP buff. Manage Hand spells
(BoP/Freedom/Sacrifice don't overwrite Blessings).

### Protection (tank/dungeon) `[T]`
Blessing of Sanctuary → Holy Strike (free, mana return) → judge Seal of Wisdom, reseal →
high-rank Consecration → Holy Shield kept up on cooldown. **Bulwark of the Righteous is
deliberately NOT part of the automated loop** (see note below).
- **Consecration as a single-target filler, decided (audit P4) — no code change.** Stays
  AoE-only, manual toggle. A tank wants it held in reserve for adds appearing suddenly
  rather than burning it as steady single-target chip damage; the damage-to-mana ratio
  against one target doesn't justify auto-casting it there anyway.
- **Holy Shield trigger, resolved (audit P5) — no code change.** The "Holy Shield on Redoubt
  proc" phrasing above is corrected: in-game tooltips (135 mana, instant, 10s cooldown,
  +45% block chance **for 10 sec** - Redoubt is a separate, independent 5-rank passive with
  its own proc chance) show Holy Shield's own duration exactly matches its cooldown, i.e. it
  is designed for continuous uptime, not a proc-timed hold. It is also self-sufficient
  regardless of Redoubt: each block it grants deals 35 Holy damage with **+50% extra
  threat**, valuable on its own merits. Aegis_SBR's existing behavior (recast on cooldown
  whenever ready) is correct; this was the audit's highest-risk item and needed real
  evidence before touching a tank defensive - now settled.
- **Bulwark of the Righteous, resolved (audit P6) — no code change, deliberately not
  automated.** In-game tooltip corrects the numbers above: 200 mana, instant, 5yd, **5 min
  cooldown** (not 3), 274-301 Holy damage, **30% damage reduction for 12 sec** (not 40%).
  Requires 31 Protection points (a true row-7/8 capstone, comparable depth to Noxious
  Assault's 31 Assassination points). Decided to leave it out of the automated rotation
  entirely: a 5-minute emergency defensive is meant for situational manual use during a
  spike of incoming damage, a judgment call the player should make, not the rotation - the
  same reasoning that already keeps Divine Shield/Lay on Hands/Hand of Protection manual-only
  below.
- **Prot seal-of-choice template default, decided (audit P7) — no template change.** Seal of
  Wisdom (the research's suggested "core loop" seal, for group-wide mana return) isn't even
  available before level 18, so defaulting a fresh `prot` profile to it would leave a
  leveling tank with no seal at all until they manually switch - the current Seal of the
  Crusader/Righteousness default works immediately at any level. On top of that, with
  multiple paladins in a group, Seal of Wisdom coverage needs coordinating (a second paladin
  typically runs Seal of Judgement instead of doubling up), so there is no single "correct"
  default anyway - this is left as the already-supported manual/situational choice it is.

### Leveling `[T]`
Seal of Command R1 + Judgement between autos; finish with Judgement of Command. Proc weapons
prized.
- **Pre-talent strike lean, resolved (audit P11) — no code change.** The "Holy Strike (free)"
  leveling lean above is corrected: Zeal (via Crusader Strike) works from level 1 with zero
  talent investment, while Holy Might (via Holy Strike) does not exist as a buff until the
  Vengeful Strikes talent is taken - there is nothing to gain by leaning on Holy Strike before
  that talent, since its payoff buff isn't there yet. Aegis_SBR's existing behavior (lean
  Crusader Strike pre-talent, only start tracking Holy Might once the talent is confirmed
  known) is correct as-is.

### PvP/defensive (Phase 4, note only)
Divine Shield, Lay on Hands, Hand of Protection/Freedom, Repentance.

---

## HUNTER — Survival is MELEE on Turtle

### Marksmanship (raid/dungeon ranged) `[T]`, breakpoints `[?]`
**Aimed Shot is baseline (lvl 20); "Trueshot" renamed Steady Shot** (first MM capstone).
Endgame = **Auto Shot + Steady Shot weave** (Steady as filler between autos), Multi-Shot
AoE filler; Aimed Shot often dropped on fast weapons (shares CD with Arcane Shot, long
cast). Hunter's Mark pre-pull. **Mana efficiency is the core constraint** — Steady Shot is
cheap; drop to Viper Sting / Aspect of the Viper at low mana.
- Weapon-speed weave `[?]`: <3.3s → AA-MS-AA-SS-AA-SS; >3.3s → AA-SS-MS-AA-SS. Verify.
- Piercing Shots: crit Aimed/Steady/Multi bleeds 10/20% over 8s (no threat).

### Beast Mastery (raid/dungeon) `[T]`
Auto Shot + Steady Shot; Kill Command macroed separately; pet uptime is the weakness.
Aspect of the Wolf gives melee AP and no longer blocks ranged abilities.

### Survival (MELEE — Turtle custom archetype) `[T]`
Raptor Strike / Mongoose Bite with **Lacerate priority** → **Carve** + Explosive Trap in
AoE → Immolation Trap single-target → **Wing Clip strict filler** (its "Phantom Strike"
triggers Windfury/on-swing effects without damage). Aspect of the Wolf. Resourcefulness
reduces trap/melee mana.
- **Carve**: 60% weapon dmg, up to 5 targets in a 10-yd cone, **shares CD with Multi-Shot**,
  6s CD, 8% mana, instant.
- **Stinging Nettle Lacing** (2 pts): Mongoose Bite and Fire traps apply your highest
  Serpent Sting at 80/60% reduced duration (~3/6s).

### Leveling `[T]`
Ranged BM/MM standard; Survival melee viable with pet tanking.

### PvP/defensive (Phase 4, note only)
Aspect of the Turtle, Survival of the Fittest, Exhilaration, Feign Death, Deterrence.

### Known bug (Phase 1): Serpent Sting icon fallback — FIXED in v0.14.1
(sting/Mark checks now pass the classic icon fragments as the scan fallback; see
CHANGELOG v0.14.1 and audit item H1).

---

## ROGUE

### Combat (raid/dungeon DPS — only endgame-viable spec) `[T]`
Sinister Strike (Improved SS baseline; Swift Strikes adds attack speed) to build combo
points → **Slice and Dice uptime = top priority** → Rupture / Eviscerate finishers.
- **Surprise Attack** (Combat capstone, 20 Combat points — Rank 1/1, in-game tooltip
  confirmed; supersedes the earlier "120% weapon dmg" estimate below): 10 energy, instant,
  25% of Attack Power as damage, guaranteed to land (can't be blocked/dodged/parried),
  1 combo point. Usable only after the TARGET dodges your attack. Implemented in Aegis_SBR
  as a reactive window mirroring Riposte's parry tracker, but on
  `CHAT_MSG_COMBAT_SELF_MISSES` filtered for "dodge" instead of
  `CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES` filtered for "parry" (audit R1, implemented —
  window length carried over from Riposte's 5.5s as a placeholder, **unverified for
  Surprise Attack specifically**; tune via `/sbr trace`'s `sa=` field if it proves too
  short/long in practice).
- Blade Flurry + Adrenaline Rush burst. Blade Rush scales energy-tick regen with agility.
- Combo points no longer vanish on target switch (reset fresh). Rogues can use 1H axes.
- **Noxious Assault does not apply here** (see Assassination below) — it requires 31
  Assassination points, which a Combat build never has, so Aegis_SBR's auto-builder
  preference for it over Sinister Strike is a non-issue for Combat in practice (audit R3).
- **Slice and Dice 1-CP cheap-refresh model, resolved (audit R2)**: Aegis_SBR only refreshes
  SnD immediately when combo points happen to be exactly 1 (otherwise it dumps into
  Eviscerate first and catches the refresh on a later pass) — cheap on combo points, but in
  theory risks a brief SnD downtime gap while waiting to cycle back to 1cp. **Ruthlessness**
  (Assassination, 6-8 points, 3/3 = 100% chance, in-game tooltip confirmed: "finishing moves
  have a 100% chance to add a combo point to your target") closes that gap in practice: every
  finisher (Eviscerate included) immediately regenerates to exactly 1 combo point, so the
  cheap-refresh window recurs on the very next press after every single finisher, not after
  several builder hits. Since Ruthlessness is an early, low-cost pick that most serious
  Combat/hybrid builds take regardless of final spec, the existing model needs no change for
  the practical case. A hypothetical 0-Assassination-point Combat rogue (rare, generally
  suboptimal) would still see the original gap — noted, not acted on.

### Assassination `[T]` (weaker)
Poison-focused; not endgame-competitive (Combat is the only viable PvE spec to late
AQ40/Naxx).
- **Noxious Assault** (Assassination end talent, 31 points — Rank 1/1, in-game tooltip
  confirmed): 45 energy, instant, 5yd, strikes with **both** weapons for 30 + 30% AP and
  **guarantees** poison application from both weapons; 1 combo point. Compare **Sinister
  Strike** R6 (lvl 46, tooltip confirmed): 40 energy, instant, main-hand only, +33 flat on
  top of melee damage, normal (non-guaranteed) poison proc chance; 1 combo point.
  Despite costing 5 more energy, Noxious Assault wins on total value whenever poisons are
  applied — a full second weapon hit plus two guaranteed procs (vs. one chance-based proc)
  outweighs the energy premium. Confirms Aegis_SBR's auto-builder (prefers Noxious Assault
  whenever known, else Sinister Strike) is correct; the 31-point requirement means this only
  ever applies to a deep/pure Assassination build, matching the module's own "Assassination
  flavoured" design intent (audit R3, resolved — no code change).
- **Envenom** (Assassination talent, ~21 points deep — Rank 1/1, in-game tooltip confirmed):
  20 energy, instant, **finisher** (consumes combo points, not a builder). Self-buff: +30%
  poison effectiveness and +30% poison application chance on the rogue. Duration scales by
  combo points spent at cast: 1cp=12s, 2cp=16s, 3cp=20s, 4cp=24s, 5cp=28s — matches
  Aegis_SBR's `ENV_DUR = {12, 16, 20, 24, 28}` exactly. Confirms the code's model (self-buff
  refreshed cheaply at 1 combo point, dumped into Eviscerate above that, mirroring the
  Slice-and-Dice upkeep pattern) is correct (audit R4, resolved — no code change).

### Subtlety (dungeon support) `[T]` (niche)
Ambush/Backstab; Honor Among Thieves (party crits → 5 energy); Cloaked in Shadows party
damage bubble via low-CD Vanish (Elusiveness); Serrated Blades garrote.

### Leveling `[T]`
Combat (swords or daggers). Dagger: Ambush → Gouge → pool energy → Backstab →
Eviscerate/Rupture; kite with Crippling Poison + Rupture.

### ⏸ Deferred (audit R5): no stealth opener `[?]`
Aegis_SBR's rotation never checks for Stealth — it starts straight at the normal builder
even when opening from stealth, so an Ambush-type opener is left on the table. Confirmed
**not worth adding for the two specs the addon actually targets**: Assassination (dagger)
already out-damages a stealth opener with Noxious Assault + its guaranteed double poison
proc (audit R3), and Combat (sword/axe) can't cast Ambush at all (dagger-only requirement).
The remaining case — a Subtlety or dagger-leveling player who wants a proper stealth-opener
weave (Ambush, optionally Gouge → energy-pool → Backstab per the Leveling line above) —
is real but **deliberately deferred**: neither maintainer currently plays Combat or
Subtlety, so a design (energy pooling? which opener?) can't be validated in-game right now.
Sketch discussed and available if someone picks this up: a toggle gated on a Stealth-buff
check (mirrors the existing `SelfBuffUp` helper), Ambush as priority 0 before Riposte, no
pooling logic initially. **Not implemented — pick this back up only with someone able to
test a Combat or Subtlety build.**

### PvP/defensive (Phase 4, note only)
Vanish, Blind, Evasion, Cloak, Kidney Shot, Improved Gouge.

---

## PRIEST

### Shadow (raid/dungeon DPS) `[T]`
Maintain **Shadow Word: Pain** → **Mind Blast on CD** (5/5 Improved Mind Blast → pattern is
2× Mind Flay then Mind Blast) → **Mind Flay** filler. Shadow Weaving / Curse of Shadow /
Improved Shadow Bolt amplify. **Mana economy is the weakness** (consumables; befriend a
druid for Innervate). Skip Vampiric Embrace on 16-debuff bosses (eats a slot + threat).
Silent Resolve + Fade for threat.

### Discipline (Turtle rework — holy-damage support DPS) `[T]`
Reworked into holy-damage support: tuned Smite + Holy Fire, talents integrating Holy Fire,
crit-scaling, health-cost support boons synergizing with shields. Power Infusion. PW:Shield
castable in Shadowform on Turtle.

### Holy (raid/dungeon heal) `[T]`
Renew maintenance (Swift Recovery: +healing on Renew'd targets) → Flash Heal / Greater Heal
/ Prayer of Healing (group) → Lightwell (Reservoir of Light charges). **Proclaim Champion**
(final Holy talent) — keep on the tank (its DR, magic resist, mana return to you, hourly
battle-res). Holy Nova usable in Shadowform (self-damage). Shadow Protection raid-wide.

### Leveling `[T]`
Disc/Shadow. Disc: Holy Fire → Smite → SW:Pain → wand to death. **Wand Specialization** is
the strongest early talent.

### PvP/defensive (Phase 4, note only)
PW:Shield, Fear Ward, Dispel, Psychic Scream, Desperate Prayer.

---

## SHAMAN — Turtle custom mechanics; can tank

### Elemental (raid/dungeon DPS) `[T]`
NOT vanilla LB-only. Core ST loop: drop totems → apply **Flame Shock** (snapshots — time
with trinket/EM/Nightfall procs) → maintain it by casting **Molten Blast** in the last ~3s
of the DoT (Rekindled Flame proc) → fill with **Lightning Bolt** → weave **Chain Lightning**
only with haste/mana headroom (~3-4 LB : 1 CL) → **Earth Shock** while moving or for a
target dying before refresh.
- **Electrify** (replaced Elemental Fury): LB/CL charge you +2% Nature dmg / +20% spell
  crit-damage per stack, to 5 — builds passively, do NOT ramp separately.
- **Elemental Mastery** on CD (grants Electrify stacks; weak, ~1% haste of DPS).
- Clearcasting/Elemental Focus: −60% mana on next 2 spells, crit-gated, unreliable.
- **Caveat:** bottom-tier raid DPS (Nature has no raid-amp debuff; ~18% behind fire/shadow).
  With full T3.5 haste set, players drop Molten Blast to keep the haste buff and revert
  toward LB spam — optimal ST rotation is gear-dependent.
- Totems do nothing for the Elemental's own DPS.
- **AoE/dungeon:** Fire Nova Totem → Magma Totem → spam Chain Lightning on 3+. Earthquake
  is unreliable — usually skip.

### Enhancement (raid/dungeon melee DPS) `[T]`
**Stormstrike** + **Lightning Strike** (custom capstone: 60% weapon + 20% weapon as Nature,
10s CD, consumes/empowers a shield charge) → Earth/Flame Shock instant nukes → melee with
Windfury weapon. Flurry nerfed to 7-15%. Stormstrike/Lightning Strike no longer trigger
chance-on-hit (e.g. Windfury) on Turtle. Slow weapon preferred.

### Restoration (raid/dungeon heal) `[V]`, needs `[?]` tuning
Chain Heal (group), Healing Wave / Lesser Healing Wave; totems (Mana Spring, Healing
Stream); Water Shield for mana; Nature's Swiftness + instant Healing Wave clutch. **Phase 3
in-game tuning item.**

### Shaman Tank (Turtle-unique) `[T]`, in active dev
Rockbiter affects ALL threat; Stoneskin/Strength of Earth totems; shield-charge avoidance
(Water Shield dodge stacking); Lightning Strike + Earth Shock for threat. Mitigation still
behind warriors/druids.

### Leveling `[T]`
Enhancement (Stormstrike + Lightning Strike, slow 2H, shocks; Elemental Focus for mana).
Elemental leveling is mana-starved ("a meme").

### PvP/defensive (Phase 4, note only)
Grounding/Tremor/Earthbind totems, Nature's Swiftness, Elemental Mastery burst.

### Roadmap: totem destruction detection (Phase 2).

---

## MAGE — Turtle custom Arcane/Fire/Frost

### Arcane (raid DPS — real DPS tree now) `[T]`
**Arcane Surge (when available) → Arcane Rupture (when available) → Arcane Missiles**
(filler).
- Arcane Surge: usable only after one of your spells is (partially) resisted; highest
  DPS-per-cast. Its GCD doesn't scale with haste, so it drops out above ~30% haste (burst
  windows only).
- Arcane Rupture: buffs Missiles' damage/scaling + mana cost. **Avoid casting Rupture when
  BOTH Clearcasting and Temporal Convergence procs are up** — one Rupture wastes both.
- Resonance Cascade: 20% chance to duplicate damaging Arcane spells at 50% (self-triggers
  to 4 stacks). Missiles gained +21% scaling per full channel.

### Fire (raid DPS) `[T]` — changed repeatedly; this is the 1.18.0/1.18.1 state
Ignite reverted to a **4-second window**; **Fire Blast now applies Scorch stacks** (renamed
Fire Vulnerability); Blast Wave CD shortened.
- Opener: Fire Blast → 3× Scorch (build Fire Vulnerability) → Fireball.
- Rotation: **Hot Streak Pyroblast (when available) → Fire Blast (when available) →
  Fireball** (filler). Hot Streak: Fireball/Fire Blast crits reduce next Pyroblast cast by
  0.5s/stack (to 3/6/9 stacks, 30s).
- Need ~2-4% haste + Nampower to fit 2 Fireballs inside the 4s Ignite window (cast lag).
  Ignite threat split among contributing mages.

### Frost (raid/leveling DPS) `[T]`
Turtle added **Icicles** (rotational), **Flash Freeze** (synergizes with Icicles), **Ice
Barrier damage bonus**. Core: maintain Ice Barrier → Frostbolt → weave Icicles. Best
leveling spec (Frost Nova → Blink → cast; Cone of Cold kiting AoE from 26).

### Leveling `[T]`
Frost best (control, low downtime). Fire: Fireball + Scorch finish. Arcane viable but
mana-hungry.

### PvP/defensive (Phase 4, note only)
Ice Block, Blink, Frost Nova, Counterspell, Presence of Mind + Pyroblast.

---

## WARLOCK

### Destruction (raid single-target DPS) `[T]`
**Shadow Bolt spam** with Ruin + Improved Shadow Bolt debuff (raid shadow-vuln) → apply
Curse of the Elements/Shadow → Immolate + Conflagrate → Shadowburn execute. **10% spell hit
cap is critical.** Bane reduces Shadow Bolt/Immolate/Soul Fire cast time.

### Affliction (raid multi-DoT / leveling) `[T]`
Maintain **Corruption + Curse of Agony + Siphon Life** → **Dark Harvest** (new capstone)
when up → **Shadow Bolt on Nightfall proc** → Drain Soul/Life filler. Nightfall now procs
from Corruption, Dark Harvest, and drains. **Malediction** lets Curse of Agony coexist with
another curse. Improved Corruption for instant Corruption.

### Demonology (PvP/solo, some group) `[T]`
Soul Link (splits damage with demon), reworked greater demons, Master Demonologist per-demon
bonuses; Curse + Corruption + Immolate + Shadow Bolt with pet management (Power
Overwhelming, health funnel).

### Leveling `[T]`
Affliction — Corruption → Curse of Agony → Drain Soul/Life/Dark Harvest → Shadow Bolt on
Nightfall. Voidwalker or Succubus pet; Imp in groups. Free mount at 40.

### PvP/defensive (Phase 4, note only)
Soulstone, Healthstone, Fear, Death Coil, Soul Link, Howl of Terror.

---

## DRUID

### Feral Cat (raid/dungeon DPS) `[T]`
**Powershift Shred is dominant** — Shred to 5 combo points → Ferocious Bite, powershifting
(cat→caster→cat via Furor) to regen energy; Faerie Fire (Feral) armor debuff; Tiger's Fury
window.
- Turtle added bleed interactions (Open Wounds: Rip empowers Claw; new early Ferocious Bite
  rank; Improved Shred) and a bleed build, but **bleeds remain weaker / less energy-
  efficient than Shred/Bite in raids** (bleeds can't crit). `[?]` if building a bleed mode.
- Turtle removed Manual Crowd Pummeler dependency; allowed feral consumables; added
  polearm/feral-AP itemization.

### Feral Bear (tank) `[T]`
Maul (rage dump) + Swipe (AoE threat) + Faerie Fire (Feral) + Demoralizing Roar; **Savage
Bite** high threat (replaces MCP dependency); **Barkskin (Feral)** defensive (−50% next
5/10/15 melee attacks, 12s, 10-min CD); Feral Adrenaline (dodge after a crit); Frenzied
Regeneration reworked (rage→health).

### Balance / Moonkin (raid/dungeon DPS) `[T]`
Turtle rework: **maintain Insect Swarm + Moonfire (DoTs augment your nukes) → alternate
Wrath and Starfire**. Moonfire extended to 18s. Sylvan Blessing (near-100% mana regen while
casting when chain-pulling). Omen of Clarity. Not top DPS; mana-inefficient. AoE via
Hurricane (Gale Winds restores the slow).

### Restoration (raid/dungeon heal) `[V]`, needs `[?]` tuning
Rejuvenation + Regrowth HoT maintenance → Healing Touch (big) → Swiftmend → Tranquility
(group) → Innervate (mana battery for casters). **Phase 3 in-game tuning item.**

### Leveling `[T]`
Feral (best), or Balance "moonglow" (Wrath → Moonfire → Insect Swarm → cat-weave at low
mana). Direct form-to-form shifting on Turtle smooths leveling.

### PvP/defensive (Phase 4, note only)
Barkskin, Nature's Swiftness + Healing Touch, Bash, Travel/Cat mobility.

---

## Cross-cutting audit notes
- **Verify against a target dummy** with a cast log before trusting any `[?]` item.
- **Healer priorities (Resto Druid/Shaman, Holy Priest/Paladin) are the least-sourced** —
  tune live (Phase 3).
- Turtle enforces **32-buff / 16-debuff caps** — the engine should avoid burning debuff
  slots on low-value applications near the cap (polish backlog).
- Several specs (shaman tank, paladin) are still being tuned by Turtle devs — re-check
  after any post-1.18.1 patch.
