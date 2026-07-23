# Aegis_SBR — Phase 1 Rotation-Correctness Audit (v0.14.0 code vs docs/rotations.md)

> ⛔ **Report only.** Per CLAUDE.md Critical Rule #1 this audit changes NO rotation code.
> Each class below gets: (1) what the module actually does, (2) a discrepancy table, (3)
> match notes (things checked that agree — so they aren't re-litigated later). The user
> decides per class what (if anything) to change; approved changes then land as their own
> verified batches.
>
> **Confidence tags** (from `docs/rotations.md`): `[T]` Turtle-confirmed · `[V]` vanilla
> assumption · `[?]` needs in-game verification (dummy-test before shipping). A `[T]` tag on
> a research *section* does not make every number in it verified — numeric parameters that
> can be checked in-game cheaply (buff stack caps, durations) are individually flagged `[?]`
> when the code disagrees, because `/sbr debug` can settle them in seconds.
>
> Audit order = roadmap divergence order: Paladin → Hunter → Shaman → Mage → Druid →
> Warrior → Rogue → Priest → Warlock. Audited at code version **0.14.0**.

---

## 1. PALADIN (`classes/Class_Paladin.lua`)

### What the code does

**Damage/tank mode** (strict single-cast, per press): `0` pre-cast opener seal while out of
melee range (never judges out of range) → `1` shared-CD strike (see ladders below) → `2`
Holy Shield when its own CD is free (held through the GCD) → `2b` Consecration on CD when
the AoE toggle is on (skipped during mana recovery) → `3` seal upkeep + Judgement
(`HandleSeals`) → `4` Hammer of Wrath at target ≤20% → `5` Repentance on CD → `6` Exorcism
vs Undead/Demon (skipped during mana recovery).

Strike ladders (both-strikes-on): **autodps** — without *Vengeful Strikes*: Crusader Strike
until Zeal at **3 stacks** and topped (renew <12s), else Holy Strike; with the talent: Holy
Strike to open/keep *Holy Might* (renew <7s), CS to ramp/hold Zeal at **3**, Zeal wins
ties, Holy Strike is the filler. **tankblock** — CS whenever the *Zealous Defense* block
buff is missing, else Holy Strike (threat). Seal logic: debuff seal judged once per target
(GUID-tracked with a 1.5s detection-dropout memory), then the damage seal is judged on CD
with reseal; optional seal-twist holds the judge until <0.4s before the next white swing;
Seal of Wisdom / Seal of Light hysteresis overrides for mana/HP management.

**Heal mode**: Blessed-Strikes CS weave to reload Holy Shock (never while anyone is under
the emergency line) → targeted heal (`DoHeal`: worst-hurt reachable member; Holy Shock for
emergencies or out-of-range; else downranked Flash of Light vs Holy Light by
least-overheal, with cast-time and Mortal-Strike-debuff compensation) → with nobody hurt:
Holy Strike splash filler (own mana floor) → Seal of Wisdom self-upkeep + optional
Judgement of Wisdom stamp.

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| P1 | **Zeal ramp target** | Ramps Crusader Strike to **3 stacks** of Zeal (`ZEAL_STACKS = 3`), renews when <12s | "ramp **Crusader Strike to 5 stacks of Zeal**" | rotations.md Ret `[T]` section — but the stack cap itself is a checkable number → treat as **[?]** | **Verify in-game first**: `/sbr debug` shows live buff stacks. If Zeal really caps at 5, raise `ZEAL_STACKS` (1-line change, gated) | If Zeal actually caps at 3 and we "fix" to 5, the ramp never completes → CS forever, Holy Might starves. If it caps at 5 and we stay at 3, we leave stacks on the table. Cheap to verify, do not change on paper |
| P2 | **Judgement vs strike order** | Strike is priority 1, Judgement (inside seal handling) is priority 3 | Ret: "Judgement on CD" listed **before** strikes | rotations.md Ret `[T]` | Probably **no change**: the module header says strikes queue on the next swing (on-next-swing = no GCD contention), which would make the order moot. **Verify [?]**: if strikes DO eat a GCD on Turtle, the order matters and should be discussed | If strikes are on-next-swing, reordering changes nothing. If they are on-GCD, swapping delays the strike a press — measurable on a dummy either way |
| P3 | **Holy Strike vs Crusader emphasis (talented Ret)** | Buff-timer alternation: HS keeps Holy Might, CS keeps Zeal, HS fills | "**Holy Strike on CD** (mana-free, mana via JoW) → ramp CS to Zeal" — HS-first emphasis | rotations.md Ret `[T]` (but self-tensioned: HS "on CD" + CS ramp can't both happen on ONE shared 6s CD) | **No change without a dummy log.** The code's alternation is a *more precise* statement of the same intent; research's phrasing can't be implemented literally | Replacing timer-driven alternation with naive "HS on CD" would drop Zeal entirely — clear regression risk |
| P4 | **Consecration role** | AoE-only manual toggle, cast on CD when on; skipped in mana recovery | Ret: "Consecration if mana allows" (single-target filler, mana-gated); Prot: "high-rank Consecration" core | rotations.md `[T]` | **User decision**: current design is deliberate (no reliable enemy count on 1.12; README documents it). If wanted for ST, that's just "toggle stays on" — a doc note, not a code change | Auto-casting Consecration ST would burn mana in leveling/5-mans; the manual toggle is the safer default |
| P5 | **Prot: Holy Shield trigger** | Cast whenever its own CD is free (toggle on) | "Holy Shield **on Redoubt proc**" | rotations.md Prot `[T]` — interplay claim, **[?]** in practice | **Report + verify**: needs in-game confirmation that holding Holy Shield for Redoubt procs is a real Turtle interaction (charges/uptime math). Do not change on paper | Holding a defensive for a proc that isn't real = uptime loss on a TANK defensive — highest-risk change in this class; demands strong evidence |
| P6 | **Prot: Bulwark of the Righteous missing** | Not referenced anywhere in the module | Row-7 Prot capstone: "Holy damage + 40% DR, 3-min CD" — part of the tank rotation | rotations.md Prot `[T]` | **Gap, report**: if the user tanks with this talent, add as an opt-in toggle (new ability = rotation change → needs sign-off + exact spell name from the client) | Low risk to add as opt-in-default-off; wrong spell name just no-ops (KnowsSpell gate) |
| P7 | **Prot: which seal** | Template: debuff *Seal of the Crusader* + damage *Seal of Righteousness*; Wisdom only via mana-management hysteresis | Prot: "judge **Seal of Wisdom**, reseal" as the core loop (mana sustain) | rotations.md Prot `[T]` | **Config-level**: the engine already supports it (set Wisdom as debuff seal / mana-manage). At most change the `prot` TEMPLATE default — still gated since templates seed rotations | Template-only change; existing profiles unaffected (NormalizeProfile never overwrites) |
| P8 | **Seal-less white swings** | `sealTwist` (hold Judgement until <0.4s pre-swing) exists but defaults **off**; after a judge, the reseal happens next press → a white swing can land seal-less | "Judgement on CD (**respect swing timer; never white-swing seal-less**)" | rotations.md Ret `[T]` | **User decision**: flipping `sealTwist` default on (or defaulting it on in the retri template) matches research; it's already implemented | Twist ON can delay Judgement up to a swing — on slow weapons that postpones JoW/JoL uptime; hand-tuned default may be deliberate |
| P9 | **Heal mode: melee-as-healing philosophy** | Strikes only weave when **nobody is hurt** (Holy Strike splash filler) or to reload Holy Shock; targeted heals always preempt | Holy min-max: "MELEE the boss — Holy Strike (AoE group heal) + CS (reset Holy Shock). **>30% of endgame healing** can come from melee" — melee is a primary healing channel, not downtime filler | rotations.md Holy `[T]` | **Discuss**: an optional "aggressive melee-holy" mode (weave Holy Strike even with moderate group damage, e.g. above the emergency line) would match the research. Significant behavior change → per-class sign-off + in-game testing | Weaving strikes while people are hurt trades targeted-heal latency for splash volume; badly tuned it drops someone. The current conservative gate is defensible |
| P10 | **Heal mode: Daybreak not tracked** | No handling of the Daybreak crit-heal buff (12s +20% healing-taken/+5% max-HP) | Daybreak capstone called out for Holy | rotations.md Holy `[T]` | **Note only**: it's a passive proc on the TARGET; possible future use is target-preference while the buff runs. Not worth logic until tuning phase | — |
| P11 | **Leveling ladder leans CS** | Pre-talent autodps: CS to 3 Zeal first, HS only after | Leveling: "Seal of Command R1 + **Holy Strike** (free) + Judgement between autos" — HS-lean while leveling | rotations.md Leveling `[T]` | **User decision**: pre-talent HS-lean is arguable (HS is mana-free at low ranks? — verify mana costs); current CS-lean is the hand-tuned ExAutoCSHS heritage | Wrong lean while leveling costs little; verify Holy Strike's actual "free" claim (code's DOWNRANK table lists nonzero HS mana ceilings — research's "mana-free" may be Turtle-wrong or rank-1-only **[?]** |

### Match notes (checked, no discrepancy)

- Strikes share ONE cooldown — code models it exactly (`ResolveSharedCD`, one pick per
  window). Matches `[T]`.
- Blessed Strikes → Holy Shock reset weave is implemented (heal mode, talent-detected,
  never over an emergency). Matches `[T]`.
- Holy Shock is heal-only in code (never cast offensively). Matches the Turtle removal
  `[T]`.
- Hammer of Wrath ≤20% = standard execute gate; Exorcism restricted to Undead/Demon with
  creature-type check. Vanilla-correct `[V]`.
- Seal choice is user-config (SoR default in templates = research's preference). ✓
- Hand spells (BoP/Freedom/Sacrifice) are Phase 4 scope — correctly absent today.

---

## 2. HUNTER (`classes/Class_Hunter.lua`)

### What the code does

Mode = ranged / melee / auto (auto picks by ~10yd `CheckInteractDistance` with 0.75s
stickiness). Off-GCD layer each press: pet attack / smart Growl / AoE Thunderstomp, burst
CDs (Rapid Fire + Bestial Wrath, always/elite/off), Kill Command on CD, Baited Shot in the
4s pet-crit window. Then strict GCD priority: `1` aspect upkeep (mana-aspect hysteresis
overrides Wolf/Hawk) → `2` **Hunter's Mark strict opener** (nothing proceeds until
confirmed) → `3` optional Aimed opener (pre-pull only) → `4` Auto Shot upkeep (ranged;
event-timed with stall restart) / melee swing start → `5a` sting upkeep (ranged-distance
only, Nampower-queued, immunity learning per target, queue-hold so lower shots can't evict
it) → `5b` Mend Pet → `5c` **Aimed Shot on Lock-and-Load proc** → `5d` Immolation Trap on
CD → melee branch: Carve (AoE lead) → Mongoose Bite (5s dodge window) → Lacerate upkeep →
Raptor Strike → Wing Clip; ranged branch: AoE (Multi-Shot → Volley) → **Steady Shot woven
1:1 in the post-Auto-Shot window** (event-timed, never clips) → Multi-Shot ST → Arcane
finisher ≤30% target HP → Arcane filler (≥50% mana or while Auto Shot is stale/moving) →
Aimed on CD only when both proc-guard and opener mode are off.

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| H1 | **Serpent Sting icon fallback (the known bug)** | Every sting/Mark detection is `TargetDebuffUp(name, nil)` — **no icon-fragment fallback**. If SuperWoW's id→name path misses (or no SuperWoW), the debuff always reads "not up" and the sting is blind-recast every throttle interval — wasted casts + debuff-slot churn | rotations.md flags it: "Known bug (Phase 1): Serpent Sting icon fallback" | rotations.md Hunter, explicit | **Fix now (pre-authorized by roadmap as a non-priority display/detection fix)**: pass the classic icon fragments as fallback (Serpent=`Ability_Hunter_Quickshot`, Scorpid=`Ability_Hunter_CriticalShot`, Viper=`Ability_Hunter_AimedShot`, Mark=`Ability_Hunter_SniperShot`). No priority change; SuperWoW clients unaffected (name path still wins) | Fragment collision with another debuff icon could false-positive "up" — fragments chosen are the stings' own 1.12 icons; name match still takes precedence |
| H2 | **AoE: Explosive Trap missing** | AoE = Carve (melee) / Multi-Shot → Volley (ranged) + Immolation Trap on CD. No Explosive Trap anywhere | Survival AoE = "**Carve + Explosive Trap**" | rotations.md Survival `[T]` | **Gap, report**: add opt-in Explosive Trap (combat traps are legal on 1.18.1). New ability = gated change; needs the exact Turtle spell name | Low — KnowsSpell-gated addition no-ops if absent; trap GCD economics need a dummy check vs Immolation |
| H3 | **Low-mana sting swap** | Sting choice is static config; only the ASPECT swaps at low mana (hysteresis) | "drop to **Viper Sting** / Aspect of the Viper at low mana" | rotations.md MM `[T]` | **User decision**: optional "auto-Viper-Sting below X% mana" mirroring the aspect hysteresis. Gated | Sting swap burns a GCD + debuff slot mid-fight; auto-swapping can churn slots near the 16-debuff cap |
| H4 | **README/code disagree on AoE order** | Code: Multi-Shot first, then Volley | README: "*Volley* leads then *Multi-Shot* fills"; rotations.md doesn't order them | README vs code — doc bug on one side | **Decide which is intended**: fixing README = ungated doc fix; reordering code = gated rotation change. (Multi-first is defensible: instant, then channel) | If Volley-first is the tuned intent, current code under-uses the channel on dense packs |
| H5 | **Lock and Load / Baited Shot / Kill Command names** | Implemented from proc-buff and spell names the research doc doesn't document (`Lock and Load`, `Baited Shot`, `Kill Command` on CD) | rotations.md MM says only "'Trueshot' renamed Steady Shot (first MM capstone)"; no L&L entry. README already flags these as best-effort | Code ahead of research — **[?]** | **Verify in-game** (`/sbr talents`, `/sbr debug`) and then document in rotations.md; wrong names are inert (KnowsSpell/HasBuff gates), so no rotation risk today | — (no-op if names wrong) |
| H6 | **Melee priority order** | Mongoose (reactive) → Lacerate → Raptor → Wing Clip | "Raptor Strike / Mongoose Bite with **Lacerate priority** → … → Wing Clip strict filler" — reads as Lacerate above the strikes | rotations.md Survival `[T]`, ordering phrasing ambiguous | **Dummy-verify [?]** whether Lacerate-before-Mongoose matters; Mongoose has a 5s reactive window so firing it first rarely costs a Lacerate tick | Swapping could waste Mongoose windows (they expire); current order is defensible — don't change on paper |
| H7 | **Wing Clip default** | `useWingClip = false` in every template | Wing Clip is the Survival "strict filler" (Phantom Strike procs on-swing effects) | rotations.md Survival `[T]` | **User decision**: template default only (existing profiles untouched). Mostly matters with Windfury Totem support | Wing Clip costs mana per filler press; solo/leveling it's waste — default-off is defensible |
| H8 | **Stinging Nettle Lacing not modeled** | Sting only applied at range; no awareness that talented Mongoose/fire traps apply reduced-duration Serpent | "Mongoose Bite + Fire traps apply your highest Serpent Sting at reduced duration" (2 pts) | rotations.md Survival `[T]` | **Note only**: melee hunters with the talent keep Serpent up implicitly; no code change needed unless sting bookkeeping starts double-counting (it keys off the debuff scan, so it self-corrects) | — |

### Match notes (checked, no discrepancy)

- Steady Shot weave is event-timed 1:1 after each Auto Shot with clip protection — exactly
  the `[T]` "Auto + Steady weave" model, more precisely than the research's `[?]`
  weapon-speed patterns (which stay unverified; don't implement on paper).
- Aimed Shot default = proc-only (never on CD) matches "often dropped / clips Auto" `[T]`.
- Survival is a real melee archetype in code (Wolf aspect, Raptor/Mongoose/Lacerate/Carve,
  Carve sharing Multi-Shot's CD comes free via the client's shared-CD IsReady). ✓
- Mark-before-sting strict opener matches the "Hunter's Mark pre-pull" note; sting is
  distance-gated so a melee hunter lands it on approach then stops. ✓
- Mana-aspect hysteresis (Viper at low, back at +15%) matches the mana-efficiency core. ✓
- Sting poison-immunity handling (Mechanical/Elemental type-block + learned per-target
  immunity) is beyond the research doc — keep.

---

## 3. SHAMAN (`classes/Class_Shaman.lua`)

### What the code does

Mode dispatch (enhancement / elemental / tank / restoration). **Enhancement**: melee swing
→ shield upkeep → Bloodlust (opt-in) → Stormstrike → Lightning Strike → chosen shock on the
shared CD (Flame Shock as maintained DoT) → totem upkeep (all four elements, one per press)
→ Lightning Bolt filler (default ON). **Elemental**: shield → Elemental Mastery on CD →
Flame Shock DoT upkeep (recast when the debuff drops; blind 12s timer without detection) or
chosen shock on CD → totems → Lightning Bolt filler. **Tank**: shield → Earthshaker Slam
taunt when the target isn't on you → Stormstrike → shock (Earth default) → Lightning Strike
→ totems → optional LB. **Restoration**: Mana Tide ≤25% mana → NS-equivalent → instant
max-rank Healing Wave (emergency ≤40%) → Lesser Healing Wave (≤50%, beats AoE) → Chain Heal
(≥3 hurt) → downranked Healing Wave → Water Shield → totems → optional LB damage weave.
Totem clocks are stamped by SuperWoW `UNIT_CASTEVENT` (manual drops reset the right slot)
with 55s water / 110s other redrop timers.

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| S1 | **Elemental: Molten Blast missing** | Flame Shock is maintained by **recasting Flame Shock** when its debuff drops; Molten Blast is nowhere in the module | Core Turtle loop: "apply Flame Shock → **maintain it by casting Molten Blast in the last ~3s of the DoT** (Rekindled Flame) → fill with Lightning Bolt" — this is THE Turtle Elemental mechanic | rotations.md + turtle-mechanics.md `[T]` | **Headline gap, report**: add Molten Blast (KnowsSpell-gated) with a "refresh window" check on Flame Shock's remaining time. Needs Flame Shock's exact Turtle duration + Molten Blast CD; gated change with dummy verification | Without exact durations the refresh window can miss and drop the DoT (worse than today's recast). Must be built with `/sbr debug` timings, not paper numbers |
| S2 | **Elemental: Chain Lightning missing** | No Chain Lightning anywhere (single LB filler) | "weave Chain Lightning only with haste/mana headroom (~3-4 LB : 1 CL)"; AoE = "spam Chain Lightning on 3+" | rotations.md `[T]` (ratio itself reads `[?]`-ish) | **Gap, report**: opt-in CL weave (mana-floor gated) + CL as the AoE spam. Gated | CL is mana-hungry; a bad ratio starves the mana pool — research itself calls Elemental bottom-tier, so headroom gating matters |
| S3 | **Shaman has no AoE mode** | No `aoeMode` in the shaman profile at all; Magma/Fire Nova exist only as fire-slot totem picks | "AoE/dungeon: **Fire Nova Totem → Magma Totem → spam Chain Lightning** on 3+" | rotations.md `[T]` | **Gap, report**: add `/sbr aoe` for shaman (swap fire-slot to Nova/Magma + CL spam), mirroring other classes' AoE toggles. Gated | Modest — AoE toggle is opt-in by design; totem swapping mid-fight churns GCDs |
| S4 | **Elemental: Earth Shock while moving** | Shock choice is static config (elemental template = flame); no movement awareness | "Earth Shock **while moving** or for a target dying before refresh" | rotations.md `[T]` | **Report**: Nampower's `PlayerIsMoving` (see docs/dependencies.md) makes this implementable; needs fork-availability check + gate | Depends on a Nampower API that must be confirmed on the live client first (`if PlayerIsMoving then`) |
| S5 | **Flame Shock snapshot timing** | DoT recast purely on "debuff missing" | "Flame Shock (**snapshots** — time with trinket/EM/Nightfall procs)" | rotations.md `[T]` claim, proc-timing value `[?]` | **Note only** for now: proc-window snapshotting is a polish-tier optimization; record in the backlog | High complexity, low payoff until Molten Blast (S1) exists |
| S6 | **Enhancement: LB filler default ON** | `lbFiller = true` in enhancement/starter templates — hardcasts LB between melee | Research Enhancement lists SS + LS + shocks + melee; no LB weave at endgame (casting stops swings) | rotations.md `[T]` silence vs code default | **User decision**: template default (leveling likes the filler; raid Enhancement probably wants it off). Existing profiles unaffected | Turning it off globally would gut low-level DPS where LB is the only button — keep it per-profile |
| S7 | **Weapon imbue upkeep missing (Windfury/Rockbiter)** | No imbue handling in any spec | Enhancement: "melee with **Windfury weapon**"; Tank: "**Rockbiter affects ALL threat**" | rotations.md + turtle-mechanics.md `[T]` | **Already roadmapped**: Phase 2 `GetWeaponEnchantID` detection helper, then a gated rotation hook. No action in Phase 1 | — |
| S8 | **Tank: Earth Shock vs Lightning Strike order** | Taunt → Stormstrike → shock → Lightning Strike | "Lightning Strike + Earth Shock for threat" (no explicit order); tank spec "in active dev" on Turtle | rotations.md `[T]`/dev-moving | **No change**: order unverifiable on paper; dummy/threat-meter test when the user plays tank | — |
| S9 | **Earthshaker Slam / NS-equivalent / totem names** | Best-effort names, KnowsSpell-gated, README flags them for in-game confirmation | Research doesn't document them | code ahead of research `[?]` | **Verify in-game** then backfill rotations.md; inert if wrong | — (no-op if names wrong) |

### Match notes (checked, no discrepancy)

- Elemental core shape (Flame Shock DoT + LB-as-Electrify-builder, Electrify never ramped
  explicitly) matches `[T]` — Electrify builds passively in code exactly as research says
  it should (no dedicated logic = correct).
- Elemental Mastery on CD when enabled ✓ (research: "on CD, weak").
- Stormstrike before shock (buff → consume) ✓; SS/LS as talent abilities auto-detected via
  KnowsSpell ✓.
- Restoration priority (Mana Tide → NS+HW → LHW emergency → Chain Heal ≥3 → downranked HW →
  Water Shield → totems) matches the `[V]` sketch; rank tables are flagged in-code as
  vanilla baselines pending the Phase 3 live tuning — consistent with research's own
  "needs `[?]` tuning".
- The cross-spec totem system with `UNIT_CASTEVENT` stamping is beyond research; Phase 2
  adds destruction detection. Redrop intervals (55s/110s) are already flagged in-code for
  Turtle-duration tuning. ✓

---

## 4. MAGE (`classes/Class_Mage.lua`)

### What the code does

Channel guard first (never acts over Missiles/Icicles/Blizzard/Evocation; 16s wedge
ceiling), then shared upkeep in every spec: Ice Barrier when ready → optional Mana Shield
(never under Ice Barrier) → emergency Evocation (<15% mana, in combat, target >30% HP).
Then per-spec: **Frost** — Frost Nova when the mob reaches melee → wand gate → Cone of Cold
(melee-gated) → Icicles whenever ready (freeze-procs keep resetting its CD, so the
empowered window is caught implicitly) → Frostbolt filler. **Fire** — Frost Nova → wand →
Combustion → **Pyroblast whenever target ≥85% HP (hardcast opener)** → Scorch until *Fire
Vulnerability* reaches the configured stacks (1.5s per-target throttle so undetectable
stacks can't spam) → Fire Blast on CD → Fireball filler. **Arcane** — Frost Nova → wand →
Arcane Rupture upkeep (target-debuff OR self-buff detection) → Arcane Power → Arcane Surge
only while NOT hasted (AP/MQG/Enlightenment buffs) → Arcane Missiles filler. **AoE** (all
specs): Frost Nova → Cone of Cold → Icicles → wand floor → Arcane Explosion; ground-target
AoE deliberately excluded.

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| M1 | **Fire: Hot Streak not modeled** | Pyroblast fires only as an opener (target ≥85% HP, full hardcast); no Hot Streak awareness | Core Fire rotation: "**Hot Streak Pyroblast (when available)** → Fire Blast → Fireball"; Hot Streak = Fireball/Fire Blast crits cut the next Pyroblast's cast 0.5s/stack (3/6/9, 30s) | rotations.md + turtle-mechanics.md `[T]` | **Headline gap, report**: add a Hot-Streak-reactive Pyroblast (buff-stack detection via `/sbr debug` first — exact buff name needed). Gated + dummy-verified | Casting Pyro on low stacks = long hardcasts mid-fight (DPS loss). Needs the real stack threshold from testing, not paper |
| M2 | **Fire: Pyroblast ≥85% re-fires on big targets** | The ≥85% gate re-queues hardcast Pyroblast until the boss drops below 85% — on raid HP pools that's several 6s casts in a row | Research has Pyro only via Hot Streak (and the opener as Fire Blast → 3× Scorch → Fireball) | rotations.md `[T]` | **Report**: likely unintended at raid scale (fine while leveling). Options: once-per-combat opener latch, or fold into M1's Hot-Streak rework | Leveling profiles genuinely want the opener Pyro; a pure once-latch is safe; removing it entirely hurts open-world play |
| M3 | **Fire: opener order (Fire Blast stacks Scorch)** | Scorch loop runs before Fire Blast; FB is just "on CD" filler | "**Fire Blast now applies Scorch stacks**"; opener: "Fire Blast → 3× Scorch → Fireball" — FB-first accelerates the Fire Vulnerability ramp | rotations.md + turtle-mechanics.md `[T]` | **Report**: consider Fire Blast before/into the Scorch ramp while stacks < target. Gated; cheap dummy test (watch stack counter) | FB on CD early delays its next use ~8s; net ramp gain needs the stack-application fact confirmed on live |
| M4 | **Arcane: Surge order + availability model** | Rupture upkeep → Arcane Power → Surge (only when un-hasted, cast when `IsReady`) | "**Arcane Surge (when available)** → Arcane Rupture → Missiles"; Surge is usable **only after one of your spells is (partially) resisted** | rotations.md `[T]` | **Report + verify [?]**: if the client leaves Surge "ready" when not resist-primed, the rotation queues an uncastable spell and wastes the press (Queue returns true). Needs in-game check of how un-primed Surge reports; then either reorder (Surge first when truly available) or add a primed-detection | If Surge-first is wrong about availability, it wastes the top priority slot every press; verify before touching |
| M5 | **Arcane: Rupture double-proc guard missing** | Rupture recast whenever its debuff/buff is missing | "**Avoid casting Rupture when BOTH Clearcasting and Temporal Convergence procs are up** — one Rupture wastes both" | rotations.md `[T]` | **Gap, report**: add the two-proc hold (buff names need `/sbr debug` confirmation). Gated | Holding Rupture too long drops its Missiles buff — the hold must be a one-press defer, not a hard block |
| M6 | **Fire: Ignite 4s window pacing** | No Ignite tracking (Fireball simply fills) | "~2-4% haste + Nampower to fit 2 Fireballs inside the 4s Ignite window" | rotations.md `[T]` mechanics, pacing `[?]` | **Note only**: cast pacing is Nampower's job; revisit with the profiling tool (polish backlog) | — |
| M7 | **Frost matches** | Ice Barrier upkeep → Icicles weave → Frostbolt, CoC/Nova melee-gated | "maintain Ice Barrier → Frostbolt → weave Icicles", Flash Freeze synergy implicit | rotations.md `[T]` | **No change** — implicit Icicles-reset handling matches research's model | — |

### Match notes (checked, no discrepancy)

- Frost = research shape exactly (M7); Icicles' freeze-empowerment is captured by casting
  on every CD reset — no explicit Flash Freeze tracking needed.
- Arcane Surge skipped while hasted (AP/MQG buffs) matches "drops out above ~30% haste"
  in spirit — a buff-proxy instead of a haste% calc; fine at current itemization.
- Channel protection (never clip Missiles/Icicles/Evocation) matches research's channel
  warnings; Evocation gated on combat + target-HP is sensible and un-contradicted.
- AoE deliberately excludes Blizzard/Flamestrike (cursor placement) — documented design
  constraint, matches README; kite-AoE chain (Nova → CoC → Icicles → AE) is the research
  leveling pattern.
- Turtle spell names (Icicles, Arcane Rupture, Arcane Surge, Flash Freeze, Fire
  Vulnerability) were name-confirmed against the client DB per module header; proc
  behaviors remain `[?]` best-effort as the README already states.

---

## 5. DRUID (`classes/Class_Druid.lua`)

### What the code does

Form-adaptive: the rotation follows the form you are IN (caster form shifts into the
profile's preferred form; unlearned forms degrade to the caster loop). **Cat**: stealth
opener (Ravage/Pounce) → Faerie Fire (Feral) upkeep → Tiger's Fury renewed when <2s left →
finisher at the CP threshold (bleed style: Rip if missing, else Ferocious Bite; shred
style: Ferocious Bite) → Rake upkeep (bleed style) → builder (Claw / Shred) → powershift
(shred style opt-in, energy <15, never while Tiger's Fury runs; shift-out lands caster,
next press shifts back). **Bear**: smart Growl (only when the target isn't on you) → Faerie
Fire as the 30yd ranged opener → Enrage when rage-starved (opt-in, combat only) →
Demoralizing Roar upkeep → Swipe when AoE-toggled → Maul rage dump. **Caster/Moonkin**:
Moonfire upkeep → Insect Swarm upkeep → Eclipse-proc reaction (empowered opposite nuke;
buff detected by name list + "Eclipse"-substring fallback) → chain the primary nuke
(default Wrath) to fish for procs. **Tree/Resto**: same heal engine family as
Shaman/Priest (Innervate low-mana → NS+instant max Healing Touch → Swiftmend off own HoTs
→ Regrowth burst → downranked Healing Touch → Rejuvenation roll → optional Wild
Growth/Lifebloom → optional damage weave).

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| D1 | **Bear: Savage Bite missing** | Not referenced anywhere in the module | "**Savage Bite** high threat (replaces MCP dependency)" — core Turtle bear threat button | rotations.md + turtle-mechanics.md `[T]` | **Headline bear gap, report**: add as a toggle in the bear priority (placement vs Maul needs a threat test; exact name/cost from the client) | Wrong placement steals rage from Maul; needs the live rage cost + threat feel, not paper |
| D2 | **Cat: default style vs raid-dominant Shred** | `starter`/`catbleed` templates default to the bleed style; `catshred` (Shred + powershift) exists but isn't the default | "**Powershift Shred is dominant** [in raids] — bleeds remain weaker / less energy-efficient (can't crit)" | rotations.md `[T]`, bleed-build viability `[?]` | **User decision, template-level**: leveling default = bleed is defensible; raiders pick `catshred`. Maybe a README/panel hint, not a logic change | None (both styles fully implemented) |
| D3 | **Cat: Tiger's Fury constant upkeep** | Renewed whenever <2s remain (permanent uptime, 30 energy each) | "Tiger's Fury **window**" — used as a damage window, not permanent upkeep | rotations.md `[T]` phrasing, energy math `[?]` | **Dummy-verify**: TF's Turtle cost/duration decides whether 100% uptime is energy-positive. Report numbers before changing | If TF upkeep is a net energy loss, current code bleeds builder energy; if it's cheap on Turtle, windowing would be a nerf — measure first |
| D4 | **Cat: powershift doesn't check Furor** | Powershift is a pure profile toggle; no talent check | Powershift works "via **Furor**" (shift-in energy) — without 5/5 it's mana + 2 GCDs for nothing | rotations.md `[T]` | **Report**: cheap safety = read Furor's talent rank and warn (or hold powershift) when untalented. Behavior-adjacent → gated | A warning is riskless; auto-blocking could surprise a player using Wolfshead-style effects instead of Furor |
| D5 | **Balance: alternate vs proc-fishing** | Alternation happens only on a detected Eclipse buff; otherwise chain-casts ONE nuke (default Wrath) | "maintain IS + MF → **alternate Wrath and Starfire**" — reads as continuous alternation | rotations.md + turtle-mechanics.md `[T]`, exact proc mechanic `[?]` | **Verify the Turtle mechanic**: if Eclipse-style procs exist (code's model), proc-fishing is right and research phrasing is loose; if the rework rewards strict alternation, the filler needs changing. `/sbr debug` during Balance play settles it | Strict alternation without a proc reason wastes the stronger nuke's ratio; don't change until the buff behavior is confirmed |
| D6 | **Balance: no AoE (Hurricane)** | No caster AoE path | "AoE via Hurricane (Gale Winds restores the slow)" | rotations.md `[T]` | **Note**: Hurricane is ground-targeted — same cursor constraint that excludes Blizzard/Flamestrike (documented design rule). Revisit only if SuperWoW 2.0's `CastSpellByName(spell, "CLICK")` is adopted (roadmap-gated) | — |
| D7 | **Resto: Tranquility missing / Wild Growth extra** | Kit = HT/Regrowth/Rejuv/Swiftmend/NS/Innervate + optional Wild Growth + Lifebloom; no Tranquility | Research sketch lists "**Tranquility** (group)"; doesn't list Wild Growth/Lifebloom (Turtle additions) | rotations.md Resto `[V]` needs-`[?]`-tuning | **Fold into Phase 3 live tuning** (healer priorities are the least-sourced): decide Tranquility's place (long channel + threat) with real play; keep WG/LB as the Turtle-native tools they are | Tranquility mid-rotation is risky (channel lock); the Phase 3 plan already owns this |
| D8 | **Sylvan Blessing / Omen of Clarity not modeled** | No handling | Balance rework lists both | rotations.md `[T]` | **Note only**: Sylvan Blessing is passive regen; Omen procs could later gate the expensive nuke — polish backlog | — |

### Match notes (checked, no discrepancy)

- Powershift loop is implemented exactly (recast form → caster → re-shift; blocked while
  Tiger's Fury runs so the buff is never tossed) — matches `[T]` powershift-Shred, with the
  correct anti-waste guard.
- Faerie Fire (Feral) armor debuff kept up in both feral forms; bear uses it as the ranged
  opener because Moonfire is uncastable in bear (documented). ✓
- Bear core = Maul dump + Swipe AoE + Demo Roar upkeep + smart Growl — matches `[T]` minus
  D1. Enrage armor-loss caution handled (opt-in, combat-only). ✓
- Moonfire + Insect Swarm upkeep matches the Balance rework's DoT-augmentation core `[T]`.
- Open Wounds-style bleed pairing (Rip + Claw) exists as the bleed style — consistent with
  research's "Turtle added a bleed build" note, with raids steered to Shred (D2).
- Barkskin (Feral) / Frenzied Regeneration / defensives = Phase 4 scope, correctly absent.

---

## 6. WARRIOR (`classes/Class_Warrior.lua`)

### What the code does

Off-GCD fire-and-continue layer: Bloodrage below 30 rage → burst CDs by pop-mode (Death
Wish; Recklessness/Berserker Rage in Berserker) → Sweeping Strikes in AoE → Shield Block in
Defensive → rage dump on next swing at ≥`dumpRage` (Cleave in AoE else Heroic Strike;
suppressed in execute phase). Then strict GCD priority: Charge opener (out of combat, out
of melee, Battle or dance-in) → Revenge in its 5s reactive window (Defensive) → Execute
≤20% → Overpower in its reactive window (Battle, dance-in optional) → primary strike
(Shield Slam → Bloodthirst → Mortal Strike; normally only one is talented) → Rend upkeep
(toggle, off by default) → Whirlwind (AoE, or ST at ≥`wwExcess` rage, Berserker) → Thunder
Clap in AoE (**Battle-stance-gated**) → Sunder upkeep to N stacks → Slam filler → drift
back to home stance. Stance requirements are vanilla-1.12-conservative by design.

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| W1 | **Battle Shout missing** | ✅ **IMPLEMENTED v0.15.3** — `useBattleShout` (default ON): refreshed when missing / <30s left, placed below the strikes so it never delays one | "Maintain **Battle Shout**" — listed for Arms AND Fury as the first rotation element | rotations.md Arms/Fury `[T]` | **DONE** (user sign-off). Buff-time gated, rage-gated, skipped in Execute | Placement resolved: below strikes = ~one GCD every 2 min, never delays a strike |
| W2 | **Prot: Thunder Clap stance gate** | `STANCE_REQ["Thunder Clap"] = Battle only` (vanilla-conservative) + prot template ships `useThunderClap = false` — a Defensive tank never TCs | "**Thunder Clap is usable in Defensive Stance** = primary AoE threat" for Turtle prot | rotations.md Prot `[T]` | **Verify in-game, then relax the stance list** and flip the prot template default. The module header explicitly says stance rules stay conservative until Turtle confirms — this is that confirmation case | If TC is NOT defensive-legal on live, the rotation burns a press on a rejected cast every AoE cycle — hence verify first |
| W3 | **Prot: Revenge fires above Shield Slam** | Priority: Revenge (reactive window) → … → Shield Slam | "**Shield Slam = top single-target threat** (Turtle: scales with AP) → Revenge when available"; Turtle note: Revenge threat is FIXED and doesn't scale | rotations.md Prot `[T]` | **Report + swap candidates**: SS-before-Revenge matches Turtle's scaling claim. One-line order swap, but it IS a priority change → sign-off + threat test | Revenge's 5s window can expire while SS + GCD resolve — the swap trades a possibly-lost Revenge for faster SS; measure, don't guess |
| W4 | **Prot: Demoralizing Shout missing** | ✅ **IMPLEMENTED v0.15.3** — `useDemoShout` (default OFF): debuff-maintained on the target like Rend, re-applied only when it falls off | "Demoralizing Shout for AoE mitigation" (prot); also in the leveling line | rotations.md Prot/Leveling `[T]`/`[V]` | **DONE** (user sign-off), opt-in. Debuff-tracked, rage-gated, skipped in Execute | Default OFF respects the 16-debuff-cap caution; the user opts in when tanking |
| W5 | **Arms: Rend default off** | `useRend = false` in the arms template (toggle fully implemented) | Arms: "keep **Rend** up (2H)" | rotations.md Arms `[T]` baseline/`[V]` rotation | **Template-level user decision**: flip arms template default on. Existing profiles unaffected | Rend on high-armor raid bosses was often skipped in vanilla practice; `[V]`-grade evidence — cheap either way |
| W6 | **Arms: Slam not swing-synced** | Slam is a plain low-priority filler; module comment admits it "resets the swing timer… may feel awkward" | "**Slam on free swings**" — swing-timer-aware usage | rotations.md Arms `[V]` | **Report**: the core already has a swing timer (`SwingTimeLeft`); gating Slam on post-swing windows (like the hunter's Steady gate) is implementable. Gated + dummy-verified | Bad windowing turns Slam into a pure swing-DPS loss; keep off/late priority until measured |
| W7 | **Shield Bash / Shield Slam dispel (Gag Order)** | No dispel logic | Prot: "Shield Bash / Shield Slam to **dispel magic** (Gag Order)" | rotations.md Prot `[T]` | **Note only**: dispel-on-buff detection is interrupt-tier logic (Phase 4 / polish interrupt work fits it better) | — |
| W8 | **Fury/Arms burst in Berserker only** | Recklessness/Berserker Rage require Berserker stance (correct); Death Wish any stance ✓; all default per-template | "Death Wish / Recklessness / trinkets in burst windows" | rotations.md Fury `[T]` | **No change** (trinkets = polish backlog item already) | — |

### Match notes (checked, no discrepancy)

- Fury/Arms templates set `dumpRage = 50` — exactly research's "~50 rage" dump line
  (starter keeps a more conservative 60). ✓
- Execute ≤20% as top strike priority, dump suppressed in execute so rage funnels ✓.
- Overpower/Revenge reactive windows from combat-log events (5s) ✓; Charge as the
  out-of-combat opener ✓; Sunder to 5 stacks with stack detection ✓ (prot core `[T]`).
- Whirlwind: AoE on CD + ST rage-excess valve matches both Arms and Fury lines ✓.
- The "Known Turtle weakness" (fixed Revenge/Sunder threat) is an expectations note, not a
  rotation change — nothing to do in code beyond W3's ordering question.

---

## 7. ROGUE (`classes/Class_Rogue.lua`)

### What the code does

Off-GCD: Adrenaline Rush + Blade Flurry by pop-mode (always/elite/off). GCD priority:
Riposte inside its parry window → build at 0 CP (auto-builder prefers *Noxious Assault* if
known, else Sinister Strike) → Slice and Dice refresh when <5s left (**at exactly 1 CP** it
casts SnD; at 2+ CP it Eviscerates first, then re-applies SnD at the next 1 CP — the
ExAutoRogue cheap-refresh model) → Envenom kept up the same way (self-buff model with its
own duration table) → Rupture at the finisher threshold when missing → Eviscerate at
`cpFinish` → build. SnD durations assume the +45% duration talent.

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| R1 | **Surprise Attack missing** | No Surprise Attack; the only reactive is Riposte (parry window) | "**Surprise Attack** (Combat 5th-row capstone): 120% weapon, 10 energy, usable **after target dodges**, can't be dodged/parried/blocked" | rotations.md + turtle-mechanics.md `[T]` | **Headline gap, report**: add a dodge-window reactive exactly like Riposte's parry tracker (the combat-log plumbing already exists; the hunter's Mongoose tracker is the same pattern) | Reactive-window ability = on-bar requirement caveat (SCRM lesson); needs the exact proc rule verified live |
| R2 | **SnD refresh model (1-CP cheap refresh)** | SnD down at 2+ CP → Eviscerate first, SnD re-applied later at 1 CP (brief SnD downtime each cycle) | "**Slice and Dice uptime = top priority**" | rotations.md Combat `[T]` | **Dummy-verify**: the 1-CP-refresh model is a deliberate, proven vanilla technique (hand-tuned heritage); measure SnD uptime with a cast log before proposing refresh-at-current-CP | Changing to refresh-at-any-CP raises uptime but burns big-CP finishers on SnD — could be a net loss; measure first |
| R3 | **Noxious Assault auto-preferred** | Auto-builder picks *Noxious Assault* over Sinister Strike whenever known | Not documented anywhere in the research docs | code ahead of research `[?]` | **Verify + document**: confirm what Noxious Assault is on Turtle (rank damage/energy vs SS) and record it in rotations.md; auto-prefer may be wrong for Combat | If NA is worse per energy for Combat builds, the auto-pick quietly lowers DPS — a config override exists (fixed builder) as the escape hatch |
| R4 | **Envenom modeled as a self-buff** | Kept up like SnD with a 12-28s duration table | Not in the research docs (vanilla has no Envenom; Turtle custom) | code ahead of research `[?]` | **Verify + document** Envenom's actual Turtle behavior (buff? finisher damage? poison interaction) | — (toggle is off by default outside the assassination template) |
| R5 | **No stealth opener** | Rotation starts at the builder; no Ambush/Garrote/Cheap Shot handling | Leveling: "Dagger: **Ambush** → Gouge → pool → Backstab"; Subtlety notes Ambush/Backstab | rotations.md Leveling/Subtlety `[T]` | **Gap, report**: optional stealth-opener step (the druid's Prowl opener is the in-repo pattern to copy) | Low — opener only fires from stealth; but Energy pooling rules differ, needs play-testing |
| R6 | **Riposte template default** | `assassination` template enables Riposte; `combat` doesn't (Riposte is a Combat-tree talent in vanilla) | — | template oddity | **User decision**: flip Riposte on in the combat template (KnowsSpell-gated anyway) | None |

### Match notes (checked, no discrepancy)

- Blade Flurry + Adrenaline Rush automated on elite/boss (or always) matches the `[T]`
  burst note; combo-point persistence on target switch needs no code (client-side).
- Rupture before Eviscerate at the threshold when missing ✓ ("Rupture / Eviscerate
  finishers"); `combat` template finishes at 5 CP ✓.
- All casts are bare max-rank `CastSpellByName` (uniform energy costs) — `/sbr trace`
  surfaces ranks to make that verifiable, per the 0.13.15b note. ✓

---

## 8. PRIEST (`classes/Class_Priest.lua`)

### What the code does

Channel guard (Mind Flay/Mana Burn) → Inner Fire upkeep (any mode). **Heal mode**
(`DoHeal`): Prayer of Healing at ≥3 hurt, fronted by off-GCD Inner Focus on the prior press
→ Flash Heal reserved for ≤40% emergencies → Greater Heal for ≥1000 deficits → downranked
Heal (→ Flash → Lesser fallbacks) → Renew upkeep → PW:Shield (Weakened-Soul-guarded); then
Lightwell out of combat and an optional Smite/Holy Fire offensive weave. **DPS mode**:
Shadowform upkeep (toggle) → PW:Shield mitigation (melee/HP<50) → Spirit-Tap execute burst
<25% (Mind Blast → Smite) → **Mind Blast on CD** → SW:Pain upkeep → Devouring Plague →
Holy Fire (out of Shadowform) → Mind Flay filler (mana-floor-gated) → chosen filler → wand
regen loop (5-second rule; wandless fallback keeps casting).

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| PR1 | **Shadow: Mind Blast before SW:Pain** | MB on CD sits above the DoT upkeep | "Maintain **Shadow Word: Pain** → Mind Blast on CD → Mind Flay" — SW:P listed first | rotations.md Shadow `[T]` | **Report**: one-position swap candidate; SW:P is one GCD per ~24s so the impact is small but the Shadow Weaving opener case (MB triggers weaving) actually argues for the CODE's order. Dummy-verify | Swapping delays MB's cooldown clock on every DoT refresh; genuinely ambiguous — needs a cast log, not opinion |
| PR2 | **Improved Mind Blast weave (2× Flay → MB)** | MB whenever ready; the channel guard means in practice: full Flay channel → MB if ready — approximately the pattern | "5/5 Improved Mind Blast → pattern is 2× Mind Flay then Mind Blast" | rotations.md Shadow `[T]` | **Verify with a cast log**: current emergent pattern may already match; only add explicit pacing if the log shows MB clipping Flay ticks | Explicit pacing logic is complexity the emergent behavior may already deliver |
| PR3 | **Holy: Renew placement** | Renew/PW:S are the LAST heal-mode tier (after direct heals) | "**Renew maintenance** (Swift Recovery: +healing on Renew'd targets) → Flash/Greater/PoH" — Renew-first, and Turtle's Swift Recovery makes Renew'd targets heal for more | rotations.md Holy `[T]` | **Discuss**: with Swift Recovery talented, pre-Renewing the triage target before the big heal is a real Turtle synergy. Gated + Phase-3-adjacent tuning | Renew-first burns a GCD before the direct heal on a crashing target — must stay below the emergency Flash tier |
| PR4 | **Proclaim Champion missing** | Not in the module | Holy capstone: "**keep on the tank** (DR, resist, mana return, hourly battle-res)" | rotations.md Holy `[T]` | **Gap, report**: tank-buff upkeep needs a tank-identification config (new concept for the engine) — design discussion, then gated build | Mis-targeted Champion is wasted on a non-tank; needs explicit target config, not heuristics |
| PR5 | **Disc support (Power Infusion / rework)** | Disc plays as "heal mode + offensive weave"; no Power Infusion | "Discipline reworked into holy-damage support DPS: tuned Smite + Holy Fire… **Power Infusion**" | rotations.md + turtle-mechanics.md Disc `[T]` | **Report**: the weave covers the Smite/Holy Fire core; PI needs a target config like PR4. Fold both into one "support-target" design decision | Same as PR4 |
| PR6 | **Vampiric Embrace absent** | Never cast | "Skip Vampiric Embrace on 16-debuff bosses" — absence IS the recommendation | rotations.md Shadow `[T]` | **No change** (deliberately listed here so nobody "adds the missing spell" later) | Adding it would eat a raid debuff slot — don't |

### Match notes (checked, no discrepancy)

- Wand-centric mana economy (floor-gated filler → wand regen → wandless fallback) is
  exactly research's "mana economy is the weakness" + leveling "wand to death" `[T]`.
- Flash Heal reserved for emergencies, Greater for big deficits, Heal as the efficient
  fill, PoH + Inner Focus pairing — all match the Holy/leveling lines ✓.
- PW:Shield castable in Shadowform on Turtle: code never stance-blocks the shield ✓
  (mitigation path works in Shadowform).
- Holy Fire correctly gated out of Shadowform; Devouring Plague upkeep for the Undead
  racial ✓; Spirit Tap kill-securing burst is a leveling-correct addition research
  doesn't contradict.

---

## 9. WARLOCK (`classes/Class_Warlock.lua`)

### What the code does

Pet send (melee-gated option) → channel guards (Drain Life/Soul + a race-protected Dark
Harvest window) → **P0 Nightfall reaction**: rising-edge-only instant Shadow Bolt the
moment Shadow Trance procs (once per proc, re-armed when the icon clears) → Drain Life
self-heal below 35% HP → Health Funnel (pet low, self healthy) → Shadowburn execute <20%
(shard-in-bag-gated) → Drain Soul <20% (with shard-target banking cap) → low-mana valve
(Life Tap if healthy, else wand) → **ordered DoT upkeep: Immolate → chosen curse →
(Malediction CoA secondary) → Corruption → Siphon Life**, each cast-confirmed via
`UNIT_CASTEVENT` → Life Tap top-up → Dark Harvest dispatch (channels on CD; pre-tops any
DoT that would fall off mid-channel using Rapid-Deterioration-scaled estimates; wand-fills
between CDs) → filler (wand with DoT-expiry stop, Shadow Bolt, or Drain Life).

### Discrepancies

| # | Ability / order | What the code does | What research says | Source + confidence | Recommended action | RISK if changed |
|---|---|---|---|---|---|---|
| L1 | **DoT order: Immolate leads; Corruption late** | Fixed order Immolate → curse → Corruption → Siphon Life (toggles choose WHICH, not the order) | Affliction core: "**Corruption + Curse of Agony + Siphon Life**" (Corruption first; Immolate isn't in the Affliction core at all); leveling: "Corruption → CoA" | rotations.md Affliction/Leveling `[T]` | **Report**: with Improved Corruption (instant), Corruption-first is the affliction convention. An order swap (or a per-profile order) is a small gated change | Immolate-first is right for Destruction (Immolate enables Conflagrate); a single fixed order can't serve both specs — that's the real design question |
| L2 | **Conflagrate missing** | Not in the module | Destruction: "Immolate + **Conflagrate**" | rotations.md Destruction `[T]` | **Gap, report**: opt-in Conflagrate (consumes Immolate — needs the interaction handled: don't Conflag right before an Immolate refresh) | Conflag eats the Immolate DoT; naive addition would fight the upkeep loop it feeds on |
| L3 | **Destruction as a config, not a mode** | "Destro" = filler:Shadow Bolt + Immolate on + DoTs off; no dedicated destro logic (Bane/Ruin are passive anyway) | "Shadow Bolt spam with Ruin + Imp SB debuff → CoE/CoS → Immolate (+ Conflagrate) → Shadowburn execute" | rotations.md Destruction `[T]` | **Doc note**: a README recipe for the destro profile config covers most of it; L2 is the only real code gap | — |
| L4 | **Soul Link / Demonology pet defensives** | Not modeled (pet send/funnel only) | Demonology: Soul Link, Master Demonologist, pet management | rotations.md Demonology `[T]` | **Phase 4 scope** (defensives) — note only | — |

### Match notes (checked, no discrepancy)

- **Nightfall P0** matches "Shadow Bolt on Nightfall proc" exactly, with rising-edge
  once-per-proc handling that's ahead of the research (and matches its "procs from
  Corruption, Dark Harvest, drains" note by being source-agnostic). ✓
- **Dark Harvest** "when up" ✓ — channel-on-CD with mid-channel DoT protection and
  Rapid-Deterioration-scaled durations (cross-checked against Cursive's tables per the
  0.13.14b changelog). Beyond research. ✓
- **Malediction** CoA-coexistence is implemented (secondary CoA upkeep, correctly skipped
  for CoA/CoD mains) ✓.
- Shadowburn execute (shard-gated) ✓; Drain Soul shard banking ✓; Life Tap valves ✓;
  16-debuff-cap pressure is answered by the per-DoT toggles (manual, as designed).

---

## Cross-class summary (headline items for sign-off)

**Most likely real, cheapest to verify** (all `/sbr debug`-checkable in minutes):
Paladin P1 (Zeal 3 vs 5), Warrior W2 (Thunder Clap in Defensive), Mage M4 (Arcane Surge
availability), Druid D5 (Eclipse proc model).

**Missing Turtle-core abilities** (each needs the live spell confirmed, then a gated
opt-in): Shaman S1 Molten Blast (biggest single gap in the audit), S2 Chain Lightning,
Warrior W1 Battle Shout, Druid D1 Savage Bite, Rogue R1 Surprise Attack, Mage M1 Hot
Streak Pyroblast, Hunter H2 Explosive Trap, Warlock L2 Conflagrate, Priest PR4/PR5
support-target buffs (design discussion first).

**Order/emphasis questions to test on a dummy, not on paper**: Paladin P2/P3, Warrior
W3 (SS vs Revenge), Priest PR1/PR2, Warlock L1, Rogue R2, Druid D3 (Tiger's Fury
economics).

**Fixed in this phase without the gate (pre-authorized)**: Hunter H1 — the Serpent Sting
icon-fragment fallback (detection/display robustness; no priority change). See CHANGELOG.

Everything else is template defaults or documentation, called out per-row above. **No
rotation code was changed by this audit.**
