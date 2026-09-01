# 📜 Changelog

All notable changes to **Aegis: Single Button Rotation** (formerly **AutoRota**) are documented here. Versions are listed newest first. Entries up to v0.13.15b predate the rebrand and keep their original AutoRota/`/ar` wording.

---

## v1.2.5 — Druid: Rake and Rip stop on bleed-immune targets

### 🐛 Fixed — the Rend bug from v1.1.4, in the cat rotation

**Same shape, different class.** Mechanical and Elemental mobs are immune to bleeds, so Rake
and Rip never land on them, so the "not already on the target" test stays true and the upkeep
is re-attempted on **every press** — a wasted global cooldown and the energy each time, for
the whole fight. The Warrior's Rend was fixed for exactly this in v1.1.4; the druid's two
bleeds have the identical pattern and were not covered.

`M:TargetIsBleedImmune()` is ported from `Class_Warrior.lua` unchanged, cache and reasoning
included: one `UnitCreatureType` call per target rather than one per press, keyed on the
target id so a swap re-reads at once instead of answering stale, and an **unknown** type still
allows the cast, because failing open only risks today's behaviour while failing closed would
silently disable the bleeds against ordinary mobs. Same *Localisation note* as the Warrior fix
— the comparison is against English strings, so a non-enUS client degrades to "never immune",
which is the safe direction.

**No priority ORDER was altered — this adds a gate.** The immunity check is deliberately kept
out of the `bleed` variable, which also selects the builder: folding it in there would turn
Claw into Shred on an immune target, and that is a priority decision rather than part of this
fix. On an immune target the finisher now falls through to Ferocious Bite, which is the point
— Rip can never land there.

The cat trace line carries `immune=Y/N` so a play report says which branch ran.
## v1.2.5 — Knowing whether you are moving

The client has no speed API, so nothing in the addon ever knew. Two classes were paying for that
in different ways, and one play report named both.

### ✨ Movement detection, in the core

Measured the way the movement-speed addons measure it: our own position, sampled every 0.2s and
differenced, through SuperWoW's `UnitPosition`. The sample interval is what makes it usable —
two presses can be a tenth of a second apart, and over that gap a walking character barely
moves, so differencing every press reads as standing still half the time.

It answers **"standing still" when it cannot tell** (no SuperWoW, no reading yet). "Cannot
judge" must never block a cast; the same rule the range checks follow.

There is a second question next to it, and the difference between them turned out to matter:
`StillFor(seconds)` asks how long you have been stationary. Stopping is not a commitment to stay
stopped — a step to reposition puts a fraction of a second of stillness in the middle of moving.

### 🐛 Fixed — the warlock stalled while moving, and the DoT never landed

Both halves of that report are one defect. `ApplyDot` sends the DoT and answers *"cast"*, on
which the caller returns from the **whole** rotation. For *Corruption* or *Immolate* that is a
spell with a cast time, movement breaks it, and the next press does the same thing again: every
press spent on a cast that cannot finish, the DoT never applied, and nothing else ever reached.

A DoT that is not instant **for this character** is now skipped while moving, and the chain
carries on to the ones that are instant and then to the filler. Reported as *"up"* rather than
*"wait"* deliberately — *"wait"* returns from the rotation, which is the stall being fixed.

Cast times include the talents: *Corruption* 2.0s less 0.4s per rank of **Improved Corruption**,
so instant at 5/5 — exactly the line described from play as *"an affliction warlock uses nothing
but instant DoTs from about level 30"*. *Immolate* 2.0s less 0.1s per rank of **Bane**, never
instant.

### ✨ Channels are not attempted while moving

Movement breaks a channel outright, so starting one while running is not a slightly worse cast —
it is a global cooldown spent on nothing. *Drain Life*, *Drain Soul*, *Dark Harvest* and *Health
Funnel* are refused while moving and the caller falls through to whatever it would have done
otherwise.

Refused in `Queue` rather than at each decision, because there are **six** channel sites and one
of them would eventually be forgotten. That exposed a second, older problem on the way: seven
call sites cast a spell and returned **without checking whether the cast was accepted**. Each of
those would have spent the press on nothing. They all fall through now.

### ✨ Consecration only while standing still (all four tabs)

From play: *"when you are moving the mobs are moving too, so dropping AoE might be a bad idea"*.
The patch lands on ground everybody is about to leave — the mana is spent, the damage is not
dealt, and the threat lands on nothing.

**On by default**, which is this file's exception to "new switches start off": the behaviour it
replaces is the accident, not the feature. Off restores casting on cooldown regardless, which a
tank who repositions constantly may well prefer, since a held Consecration is threat not made.

It waits for a **dwell of two seconds**, not for the instant you stop. That correction came from
the sharpest review this addon has had: *"rotation going: ah, this person hasn't moved for one
second, seems like a good time to fart gold"*. Two seconds against an eight second patch is long
enough that a step is not mistaken for a stand, and short enough that a real fight never waits —
you are stationary the moment melee starts.

One setting, shown on all four tabs, because it is one decision.

### ✨ Damage fillers for heal mode

Three switches, all off by default, all **last** in the order — below the healing, the seal, the
judgement, the splash and the Holy Shock reload. A press that reaches them was wanted by nothing
else.

- **Hammer of Wrath** — instant, own cooldown, only legal inside the execute window, so it can
  never have been a heal you gave up.
- **Exorcism** — one strong nuke against Undead and Demon targets, gated on creature type.
- **Consecration** — the one with a real cost: mana that would have been heals, and threat on
  everything standing in it. As a healer that is a decision, hence its own switch.

None of them is gated on the Tank/DPS spell toggles. A checkbox on the Healer tab that silently
does nothing because of a setting on another page is a trap.

### ✨ Fillers stop below a mana line

Asked for in the same report, and the right shape: a spare press is not spare mana. Below **Stop
below** (default 40%) no filler runs at all and what is left is kept for healing. Independent of
the melee tabs' mana management, which latches and is about pacing a damage rotation; this is one
line doing one thing. 0 disables it.

### 🐛 Fixed — Hunter's Mark and Serpent Sting were not retried when the first one failed

Reported as *"now and then Hunter's Mark and Serpent Sting are not tried again when they miss at
the start"*. Two separate faults, and the question that found the real one was **"why don't you
just read the debuffs off the target?"**

It does. `MaintainDebuff` and `MaintainSting` check the target first, through two independent
detections. The throttle underneath them only applies when the debuff is **not** up, and exists
for one narrow purpose: the beat between a cast being sent and the debuff appearing.

The wait for that beat was **110 seconds** for Hunter's Mark and **15** for Serpent Sting —
each spell's own duration. That is the correct answer only on a client that *cannot* read the
debuff back, where the timer is the whole knowledge. Where it can be read, the read is the
authority, and waiting out the full duration after it reports "not up" leaves the target
unmarked for most of two minutes.

The stings already carried the correction; **Hunter's Mark and Lacerate never got it**, though
they run through the same function and use the same detection. Now all of them work the same
way: reading the debuff once is the proof that reading works, after which the throttle waits out
the registration beat and nothing more.

### 🐛 Fixed — a cast the client threw away counted as a cast

The second fault, and the reason a throttle could be standing at all. `Pick` and `Queue` report
success as soon as a spell is known and affordable, so the throttle was stamped on the attempt,
not on the outcome. Resists and misses were already handled through the combat log — but **out
of range, no line of sight and "target needs to be in front of you" arrive as an error message
and never appear in the combat log at all.** For a hunter that is the normal case when opening:
Hunter's Mark reaches 100 yards, Serpent Sting 35.

The core now records the spell it last sent and exposes `SpellRefusedSince(spell, when)`, and a
throttle stamped at or before a refusal is discarded. Deliberately compared by **timestamp
rather than ordering**: the error and the stamp can land in either order within one frame, and
both must give the same answer.

Which combat-log channel carries a missed shot depends on how the client classifies it — a sting
is a ranged attack that applies a debuff, and the two channels split on exactly that distinction.
Rather than assume, **both are read** with the same narrow matcher: only a line naming one of our
own tracked shots does anything. If the message never arrives on one of them, listening costs
nothing.

The hunter trace now carries `hold=` for both, the one piece of state that can keep a debuff
missing while every other field looks correct.

### 🔍 The warlock says when it is standing still and why

Three places can hold the whole rotation without casting: a running channel, the Dark Harvest
guard, and a DoT answering *"wait"*. All three now write a `STALL` line to `/sbr trace` naming
which one it was and for how long — including which of the two DoT waits it is, a cast awaiting
confirmation or the interval after a confirmed cast whose debuff is not visible yet.

---

## v1.2.4 — The talent slot picks the tab

### ✨ New — bind a spec tab to a Goblin Brainwashing Device slot

Every spec tab now ends with a **Talent slot** row: four numbered buttons, one of which can be
lit. Press `2` on the Healer tab and switching to your device's second specialization switches
the rotation to that tab, on its own. Press it again to unbind. Six classes have spec tabs and
all six get the row.

What is stored is the **profile and the tab together**, so it works whichever way you organise
yourself: a separate `heal` profile comes back as that profile, and one profile with four tabs
comes back on the right tab.

**How the slot is recognised.** The device fires no event and there is no API that names the
active slot. It does not need one — the device is an ordinary gossip NPC, and the option you
click reads *"Activate 2nd Specialization"*. The number is in the text. So the gossip click is
hooked and the number read from it, which is exactly what ItemRack does; the hook is **chained
rather than replaced**, since ItemRack hooks the same global and both have to keep working.

Two details taken from that implementation because both are load-bearing:

- **"Save …" is ignored.** That option writes your *current* build into a slot and changes
  nothing about what you are wearing. Acting on it would switch the rotation to a spec you never
  entered.
- **Renamed specs fall back to names.** Rename a spec and the number disappears from the text;
  the spec-naming addon's table is then matched by position instead.

**A second source, which the reference implementation does not have.** Every confirmed switch
teaches the addon what that slot's talents look like, so a change with **no gossip click** — a
login, most obviously — is recognised from the build alone. The fingerprint is exact per talent
rank rather than a per-tree total, because two different builds can share 31/0/20.

Both sources only ever act on a match. An unrecognised build changes nothing: spending a single
talent point fires the same event, and a guess would swap your rotation mid-fight. `/sbr gobbo`
lists the bindings and reports whether the hook is installed and how many builds are known.

Binding costs nothing but pressing the number — you do not have to be wearing that spec, because
the number is the binding and the build behind it is learned later.

---

## v1.2.3 — Holy Strike before the heal, and three defects a log made visible

A conversation with a level 60 holy paladin, four play reports, and a captured session log
that settled every one of them with a number.

### ✨ New — "Before healing", a switch under Holy Strike

Off by default, because it is a real trade rather than a free win.

On, *Holy Strike* goes out on cooldown **ahead of the healing itself**, whenever you are in
melee range. The case for it, from a paladin who healed at 60 with it: Holy Strike is not a
damage ability that happens to splash — it heals the group **and** returns mana through *Seal of
Wisdom* in the same swing, and a paladin casting only *Flash of Light* and *Holy Light* gives
both away. The rotation it produces is Holy Strike, then a *Holy Light* under *Holy Judgement*
or two *Flashes of Light* while the strike comes back.

Deliberately **without** an emergency guard, unlike every other step. The control is where you
stand: the strike requires melee range, so stepping back turns the switch off in practice and
leaves an ordinary healing rotation. Its own two thresholds still apply — those are restrictions
you set yourself.

The cost, stated plainly because it is real: a strike takes a global cooldown a direct heal
wanted, so somebody occasionally waits a beat longer.

### ⚡ Seal of Wisdom and its judgement moved above the heal

Not a preference — they were unreachable. From a captured session: with the heal threshold at
95%, somebody was under it on **98% of presses**, the heal claimed **99%** of them, and the
entire block of "quiet moment" steps below it ran **once in 1267 presses**. In a dungeon there
are lulls. In a battleground there are none, and every step down there starves completely. The
same log shows 17% of presses under 10% mana and seven at zero, which is what that starvation
costs.

Both still yield when somebody is under the *Holy Shock* emergency line. Holy Strike does not,
because Holy Strike is itself a heal; the seal is not.

### 🐛 Fixed — Holy Shock ignored its own threshold

**Measured: 38 of 85 casts fired above the configured line, one at 94% health.** The decision
line logged immediately before each of them reads `emg=N` — the emergency test said no, and the
cast went out anyway.

The condition had a second way in, joined by `or`: *"...or the target is standing more than ten
yards away"*, on the reasoning that only an instant heal reaches somebody out of **melee**
range. That reasoning does not survive contact with a healer — *Flash of Light* and *Holy Light*
both reach forty yards, so melee range has nothing to do with whether a normal heal lands. What
the clause actually meant was "anybody more than ten yards away", which in a party is most
people and in a raid is nearly everybody: the emergency instant fired on any hurt group member
at any health, and the slider meant nothing.

An earlier round of the same report was answered by narrowing that clause to exclude the player.
That was treating the symptom. The clause itself was the fault, and it is gone — the threshold
is now the only gate, exactly as the panel promises.

### 🐛 Fixed — a refused cast repeated forever

There was **no error handling anywhere in the addon**. When the client refused a cast for line
of sight, nothing changed: the same person was still the worst hurt on the next press, so they
were picked again, refused again, indefinitely. Reported from Alterac Valley, where a raid is
spread across a whole zone and both line of sight and range are the normal case.

The core now listens for the client's own refusal messages — compared against its own strings,
so it holds in any locale — and stands that unit down for five seconds. Never yourself. It
covers every healer and the mage's decursing.

Line of sight is the one answer no API gives in advance: `IsSpellInRange` measures distance and
knows nothing about the hill in between, and it returns "cannot judge" often enough that a heal
target can be chosen who was never castable.

### 🐛 Fixed — pets were never dispelled

Pets carry poisons, diseases and curses like anybody else, and a hunter's pet dying to a poison
is a third of that hunter's damage gone. They were simply never in the list: the roster helpers
are shared with the healing engines, where healing a pet is its own opt-in decision. All five
dispelling classes now include them, appended after the players — within one affliction type the
order decides who is cured first, and a player outranks a pet there.

### 🐛 Fixed — the raid dispel optimisation had never run

`Aegis_SBR.lua` contained a 120-line region **twice**. Three of the four functions were
identical; the fourth, `PickCure`, was not — the second copy was the **old** version, the one
that reads every unit's debuffs inside the affliction-type loop. Lua keeps the last definition,
so the old one is what ran.

The raid-scale fix written for it — one debuff pass instead of four, thousands of API calls per
second saved in a forty-man group — had been dead code since the day it was added. Same class of
defect as the duplicated paladin module, and invisible for the same reason: the file was
perfectly valid Lua. The duplicate scan now covers every file in the addon; no other is
affected.

---

## v1.2.2 — Auto-attack that stays on

**Bug fix from a play report: spamming the macro toggled auto-attack on and off.** No ability
priority changed — this is the white swing, not the rotation.

`EnsureAutoAttack` has two paths. When **Attack** sits on an action bar it reads the swing
state (`IsCurrentAction`) and only starts what is not already running — correct, and
untouched. When Attack is on **no** bar there is no slot to read state from, and it fell
through to a bare `AttackTarget()` on every press.

`AttackTarget()` is a **toggle** on 1.12 — it *stops* a swing that is already running. There
is no Lua `/startattack` equivalent; that arrived in 2.0. So the fallback flipped auto-attack
off as often as on, once per press. The comment above it claimed the opposite, which is why it
survived this long.

It now fires **at most once per target** — enough to open the swing, never enough to
flip-flop. If something else stops the swing afterwards it deliberately does not retry: from
that branch "not swinging" and "swinging" are indistinguishable, and a blind retry is the bug
being removed.

**Who this hit:** Warrior, Rogue and Paladin (the three classes that use the core's swing
path), and especially anyone running **SuperCleveRoidMacros** — SCRM drives the swing with
`/startattack`, so its users are precisely the people who never bother slotting Attack, which
is what selects the broken branch.

**The better fix is one you make yourself:** put **Attack** on an action bar, in any slot the
stance/form bar does not overwrite. That switches you to the guarded path, which can read the
swing state and restart it whenever it actually drops — self-healing, where the fallback can
only ever open the swing once.

Docs: `docs/dependencies.md` now records SuperCleveRoidMacros as **`brues-code/…`**, the
active fork the user runs, rather than the archived `jrc13245` repo the section was originally
written against — with a note that the behavioural detail there was verified against the old
fork and wants re-checking. `/startattack` and `/stopattack` are confirmed present on the new
wiki; whether they toggle or are start-only is not stated there.

---

## v1.2.1 — Emergencies that wait for an emergency

All four from a play report, and three of them were the addon doing something rather than
failing to.

### 🐛 Fixed — the paladin bubbled itself out of combat

The emergency read your health and nothing else, so a low bar between pulls burned a five
minute cooldown for lunch. Both emergency spells now require you to actually be in combat.

### 🐛 Fixed — Divine Shield and Lay on Hands, one after the other

Both thresholds can be crossed at once. The shield fires first, and on the very next press it
declined to fire again — being already invulnerable — which let *Lay on Hands* through: an hour
of cooldown spent healing somebody who cannot currently be damaged.

Lay on Hands is now blocked while a bubble holds. When it drops and the health is still low, it
fires on its own.

### ✨ Under the bubble, heal to

Ten seconds of immunity is the only completely safe casting time a paladin ever gets: no damage,
so no pushback and no dying mid-cast. The rotation used to spend it fighting on with the same
health bar it went in with.

Set a health goal and it heals you to it, then carries on. **A goal rather than a number of
casts**, which is what it started as: three casts means something entirely different at rank 1
with +40 healing than at rank 9 with +900, while "get me to 80%" means the same thing to
everybody. It also removes the state — the health bar *is* the progress, so nothing has to be
counted or reset when the bubble ends.

### ✨ Hammer of Wrath waits for Zeal in melee

*Zeal*, stacked by Crusader Strike, shortens the hammer's cast — which in melee is the
difference between the cast landing and the mob dying under it. In melee it now waits for three
stacks as well as *Judgement of the Crusader*.

At range neither applies and it stays priority one: there is nothing else to do at thirty yards,
nobody is pushing the cast back, and holding it for a buff you can only build in melee would
mean not casting it at all.

### 🐛 Fixed — the warlock stalled for two seconds

`ApplyDot` answers *"wait"* while a cast it sent has not been confirmed, and the caller returns
from the **whole** rotation on that answer — deliberately, because Nampower's queue holds one
spell and anything else would evict it. But when the confirmation never arrived, that guess cost
two full seconds of doing nothing while the button was being spammed.

The end of a cast now comes from the client's own `SPELLCAST_STOP` / `FAILED` / `INTERRUPTED`
instead of a timer. Same correction the paladin got in v1.2.0, for the same reason: measure the
end of a cast, never guess it.

### ⚡ Exorcism moved up the priority

From a play report: a whole Sunken Temple run, plenty of eligible targets, two casts.

*Exorcism* sat **last** in the damage chain — below the strike, *Holy Shield*, *Consecration*,
the seals, *Hammer of Wrath* and *Repentance* — so it only ever got a press when all of those
were on cooldown at the same moment. That is the wrong place for a rare, strong spell with a
cooldown of its own: what it competes with is a strike that comes back in three seconds, and it
loses that trade every time.

It now sits directly behind *Hammer of Wrath*, whenever the target is Undead or Demon. On the
Solofarming tab it stays behind the self-heal and *Holy Shield*, where staying alive outranks
any nuke.

Two things it is **not**, both of which can look identical from the outside:

- **Mana recovery still suppresses it**, and that suppression is silent. The recovery flag
  latches — on below *Mana low*, off only at *Mana high* — so on a wide band it can stay engaged
  for an entire fight with mana sitting comfortably in between. *Consecration* has an opt-out for
  exactly this; Exorcism has none.
- **Creature type.** The check is *Undead* or *Demon* and nothing else, so a zone that reads as
  undead by atmosphere rather than by type never qualifies.

The `/sbr trace` line now answers both directly, naming the target's creature type and the exact
reason a press was skipped — `exo=wrong type`, `exo=MANA MODE`, `exo=cd`, `exo=range`,
`exo=ready` — instead of leaving "it is off cooldown and simply not firing" to guesswork.

---

## v1.2.0 — Paladin healing rebuilt, dispelling, and DoTs that survive a resist

### 🙏 Thanks

**Holyhollie** play-tested every step of this, in real runs, with a real group — and paid for
it. Several of the bugs below did not merely waste a cast: they left her healing into nothing
while the party died around her. She kept reporting anyway, in detail, mid-run, and almost
every fix in this release exists because of a line she wrote down. The rotation is hers as
much as anyone's, and the wipes were on us.

### ✨ Paladin healing, rebuilt around the established heal ladder

Spell and rank are now chosen in two steps: **which spell**, then **which rank**. Holy Light is
used when the target is below the healthy line *and* no Flash of Light is big enough to cover
the deficit — otherwise the fast heal carries it. Within a spell, the ladder keeps the largest
rank that still lands *under* the deficit, so a cast falls just short rather than spilling over.

The previous selection did the opposite in both halves: it reached for Holy Light on *healthy*
targets, and it picked the smallest rank that would **cover** the deficit, which overheals by
construction. Measured afterwards: **every cast in a 13-minute capture landed inside 0–24%
overheal**, against 41 casts at 100% waste before.

New: minimum and maximum rank per spell, and a one-click **HPS toggle** between "Flash of Light
only" and "Holy Light whenever it is the bigger heal".

### ✨ Who gets the heal

- **Your target outranks everything**, pets included.
- **Aggro** is read for real — chained unit tokens give who a mob is actually attacking, no
  threat addon and no retargeting — and losing health counts too, which covers a mob nobody has
  targeted.
- **A self threshold**, so a healer with ways out of trouble does not spend the group's cast on
  themselves — but only while somebody else could use it.
- **Pets** with the usual three settings, **raid subgroup filters**, and incoming heals from
  other healers folded into the deficit where a heal-prediction library is present.
- **Emergency bubble**: below a health share you choose, everything stops and Divine Shield goes
  up. Off by default.

Priority is expressed as a **health handicap**, and the rule it now obeys is that a handicap may
reorder the queue but never remove somebody from it — eligibility reads real health, ranking
reads adjusted health.

### 🐛 Fixed — Mongoose Bite almost never fired

It was gated on a five second window after **dodging** an enemy attack, which is the vanilla
rule and not this client's: here it is an ordinary instant melee attack on a five second
cooldown, with no condition attached. It goes out on cooldown now, and the tooltip says so —
including that the dodge requirement does *not* apply, so nobody rebuilds it from vanilla
knowledge.

The dodge tracker went with it: it existed for this one gate, and it was subscribing to
`CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES`, which fires on every enemy attack you avoid.

### ✨ Paladin: four pages instead of two

**Tank · Solofarming · DPS · Healer.** The panel writes a `spec` field and `healMode` is derived
from it, so every rotation branch that reads `healMode` kept working untouched.

**Solofarming** is the new one, for the Holy/Protection hybrid that keeps itself alive while
killing several things at once. It is not a fourth rotation: it is the melee chain with two
steps folded in ahead of the damage, because both are what let a paladin stand in the middle of
four mobs.

- **Self-healing through the ordinary heal engine**, aimed at nobody but the player. Rank
  choice, Holy Shock, the Holy Judgement speed-up and the overheal cancel all behave exactly as
  they do for a healer — one engine, not a second one written to look like it.
- **Holy Shield is kept up** rather than used on cooldown: the block chance is the survival, and
  the blocks are their own damage.
- **The strikes stop being a damage source.** Holy Strike's returns to the paladin are halved,
  and both strikes share one cooldown — so spending it on anything but bringing Holy Shock back
  costs the self-heal it would have bought. The damage comes from Consecration, the aura proc
  and the blocks.

**Emergency buttons.** Below a health share you choose, everything stops: *Divine Shield* on the
DPS and Solofarming pages, *Lay on Hands* on Tank and DPS. The tank page deliberately does not
offer the bubble — it drops every point of threat, so the emergency that saves the tank hands
the pull to somebody who cannot survive it. On DPS both are available and the shield goes first,
five minutes being a far cheaper cooldown than an hour.

### ✨ Hammer of Wrath, and a rotation that stopped swinging at thirty yards

Hammer of Wrath now leads the priority once the target is inside the execute window: it has a
hard health gate and its own cooldown, so a missed window is simply gone. Out of melee reach it
fires immediately. In melee it first asks whether *Judgement of the Crusader* is on the target,
since that amplifies the holy damage — and takes the detour to apply it **only** when the
measured time to kill exceeds the setup, counted honestly: Judgement's remaining cooldown, the
global cooldowns for the seal, the judgement and putting the damage seal back, and the hammer's
own cast. The judgement lasts ten seconds, so on a normal mob that arithmetic never closes,
which is correct — the path is for elites by construction rather than by a special case.

Underneath it, **the whole damage chain learned about range.** Nothing between the strike and
Exorcism had checked it, and `Pick` reports success as soon as a spell is known and affordable,
so at thirty yards every press was spent on a swing that could not land — with the ranged
abilities below never reached at all. Two of them were doing it silently: *Consecration* takes
no target but burns the ground around **you**, and *Judgement* reaches about ten yards while the
seal in front of it is a self buff that always went up.

### ✨ Buffs before the pull

A paladin no longer waits for a target to put its seal on. The core holds a melee module back
until there is something to hit, and the module's own opener sat behind that same guard — so the
seal went up **on contact**, costing a global cooldown at the one moment it is worth the most.

A separate `Prebuff` hook now runs with nobody targeted. Deliberately separate from
`RunsWithoutTarget`, which also decides whether auto-acquire fires: answering "yes, run me"
there would stop a melee class picking up a target at all.

*Holy Shield* is pre-cast too, and that one is free rather than merely useful: its cooldown
equals its duration, so arriving inside the ten seconds finds it up, and arriving later finds
the cooldown expired with it. The only thing that breaks the symmetry is blocks being consumed
early, which cannot happen while nobody is hitting you.

### ✨ Priority lists for every healer, and the mage

The paladin's heal priority is now shared: **Priest, Druid and Shaman** get the same list, and
the **Mage** gets it for decursing. The list lives in the core so five classes cannot drift apart
on what "priority" means.

Each module keeps its own way of choosing, and the handicap is expressed in that module's own
currency — the priest ranks by percentage and is padded in points, the druid and shaman rank by
absolute deficit and have that deficit discounted. Everywhere the same rule holds: **eligibility
reads real health, only the order is adjusted.** A handicap may move somebody down the queue; it
can never remove them from it.

The Mage's decursing is new in itself: *Remove Lesser Curse* on a cursed group member, above the
damage rotation, cast without changing your target. No health threshold there — a curse is on
somebody or it is not.

### 🐛 Fixed — two loops that only hurt at raid size

Both were invisible in a five-man and ruinous in a forty-man, which is exactly how they were
found:

- `PickCure` read every group member's debuffs **once per affliction type** — four full passes
  over the raid, better than six thousand `UnitDebuff` calls per press, four times a second. It
  reads them once now.
- `ScanAggro` compared every enemy's victim against every group member with `UnitIsUnit`, more
  than three thousand comparisons per scan. Each unit is identified once by GUID and the victim
  looked up directly — same precision, a fortieth of the work.

### 🔧 `/sbr probe` now records frame rate and rotation cost

`fps=62 presses=23 (4.6/s) rot_avg=0.31ms rot_max=1.20ms group=40`, one line every five seconds,
summarised by `scripts/read_probe.py`. It answers the only question worth asking when frames
collapse: is the addon slow, or is everything slow? Built because reproducing a forty-man raid
to test something is not a thing anybody can do on request — so the measurement rides along on a
raid you were going to run anyway.

### ✨ Dispelling, for all four healers

A **Dispel** section in the Paladin, Priest, Druid and Shaman panels: one switch, and a
**Cure first above** slider.

The slider is a **crossover**, not an on/off. It is read off the worst-hurt group member: above
it the affliction outranks the missing health, below it the heal wins. At 90 the group is
cleansed first and topped up from 90 to 100 afterwards — the order that matters when the
affliction is doing more damage than the missing tenth of a bar. 0 makes curing always yield,
100 makes it always come first.

Only what your character has actually learned is considered, best spell first: *Cleanse* before
*Purify*, *Abolish* before *Cure*. Off by default, because a dispel spends a global cooldown
that would otherwise be a heal.

| | removes |
|---|---|
| Paladin | Poison, Disease, Magic (*Cleanse*) · Poison, Disease (*Purify*) |
| Priest | Disease (*Abolish* / *Cure Disease*) · Magic (*Dispel Magic*) |
| Druid | Poison (*Abolish* / *Cure Poison*) · Curse (*Remove Curse*) |
| Shaman | Poison · Disease |

Three things worth naming, because each is a trap avoided rather than a feature added. The
dispel **type** is the third return of `UnitDebuff` and has been available all along — no
tooltip scanning, no icon list. A unit is **left alone for a few seconds after a cure that did
not take**, so a dispel that cannot work is not retried every press. And **Magic is never
stripped from a charmed ally**: the charm *is* the magic, and removing it is the one dispel that
hands the enemy its damage dealer back.

### 🐛 Fixed — Health Funnel into a dead pet, and Immolate on immune mobs (Warlock)

A dead pet still **exists** as a unit and reads zero health, so `PetHPPct` returned 0 — under
every threshold — and the warlock funnelled his own health into a corpse indefinitely. The fix
is in `PetHPPct` itself, so every pet-health gate in the module is right at once.

Immolate had no immunity handling at all: on a fire-immune mob the debuff never lands, the check
reports it missing, and the same cast went out every three seconds for the whole fight. 1.12
offers no way to *ask* whether a mob resists a school, so the only honest source is the client
saying so — `"Your Immolate failed. X is immune."` is now read and remembered per target and per
spell, relearned each fight. Same pattern the hunter already used for stings.

### 🐛 Fixed — a resisted DoT stalled the whole rotation (Warlock, Priest)

A resist is not a cast failure: the cast completes and the spell is thrown away on landing, so
nothing in the cast path can see it. The reapply throttle was stamped as though the DoT were up,
and every press until it expired answered "wait, still landing" — which returns from the rotation
without doing anything. On an unreadable curse that interval is **20 seconds**. The combat log is
read for resists and misses now, and the same bug was found and fixed in the Priest.

### 🐛 Fixed — the paladin healed himself at full health, forever

Three separate defects, all found from logs rather than argued:

- A self fallback returned the player as a heal target at **100% health with a deficit of zero**,
  and the rank ladder then cast its floor rank at him, press after press. 293 of 343 self
  selections in one capture were at full health.
- `CheckInteractDistance` gives no usable answer about the player, so "or out of melee reach"
  read as true **on yourself** and cancelled Holy Shock's health threshold outright. The same
  defect was leaving the paladin out of his own Holy Strike headcount.
- The overheal cancel compared against zero instead of against how wasteful the heal already was
  when chosen, so on a nearly-full group it cancelled its own decision, re-made it, and repeated —
  visible as a rotation doing nothing until an *instant* heal slipped through.

### 🐛 Fixed — the rotation fought over Flash of Light versus Holy Light

A 0.4s timeout released casts that were merely **queued** behind a global cooldown. The next press
re-decided, the target's health had drifted across the spell-choice line, a different spell was
chosen and it clipped the one already flying. The end of a cast is now taken from the client's own
`SPELLCAST_STOP` / `FAILED` / `INTERRUPTED` instead of a timer. Measured: 39 spell flips inside two
seconds in one capture, 5 in the next — four of which were ordinary sequencing.

### 🐛 Fixed — Seal of Wisdom needed an enemy

Refreshing Seal of Wisdom required a hostile target in melee range, and sat behind the rotation's
"no attackable target, stop here" guard. It is a **self buff**: a healer standing back with nothing
targeted never refreshed it at all. Only the *judgement* needs a target; the two are separate now.

### 🐛 Fixed — Retribution ran out of mana and could not climb out

The paladin module never asked whether it could pay for a spell. At low mana the rotation kept
choosing a strike, the cast failed silently, and the press was spent — every press. It falls
through and keeps swinging now. Mana management is on in the Retribution template, and strike
downranking in the levelling templates.

### 🔧 Measured, not assumed

- **Divine Favor is a crit talent** and was being applied as a flat healing multiplier, inflating
  every Holy Shock prediction by 5% per rank. Model 724 against three non-crit landings of
  587 / 576 / 567; without it, 579 against 576. A rank choice may never count on a crit.
- Heal sizes are logged against what the server actually landed (`/sbr log on`), which is how the
  above was found and how the remaining ~22-point flat offset across all heals will be settled.
- Holy Strike fires **on cooldown** again. Its 93% / 3-target gate came from a manually pressed
  macro, where the question is "is this press worth it as a group heal" — a rotation asks
  something else entirely.

### 🔧 Under the hood

- `Aegis_SBR:SpellReaches` — only an explicit "out of range" may block. `IsSpellInRange` also
  answers −1 for "cannot judge", and reading that as out of range is how a healer silently drops
  somebody standing next to them. Applied across Paladin, Priest, Druid and Shaman.
- Tooltips wrap. The wrap flag was missing, so a long line rendered at full width and ran off the
  screen; the longest was 482 characters. Nothing exceeds 241 now.
- A heal-path trace at last: before this release a healing paladin produced no trace output at
  all, which is why half of the reports above had to be argued from theory.

---

## v1.1.9 — ClassicAPI support, a range window, and a Subtlety rogue

**Two strands.** The first makes Aegis use **ClassicAPI** where it is installed, for the three
things a 1.12 client genuinely cannot do. The second adds a **Subtlety** rogue path, which is
written from research and has **not been played** — see its warning below.

Everything ClassicAPI-related is optional. Without the DLL, every path falls back to exactly
the previous behaviour; that is a contract, not a courtesy, and `/sbr capi` reports what was
actually found.

### ✨ Enemy debuff timers, with a caster

1.12 tells an addon that a debuff is *there* and how many stacks it has — never how long it
has left, and never whose it is. Aegis worked around that everywhere: the Warlock inferred DoT
time from its own cast bookkeeping, the Hunter re-applied stings on a blind interval, the
Shaman re-shocked on a blind 12s clock.

With ClassicAPI the real expiry is available, and it is the **caster-modified** one. Measured
in game: Rupture at 5 combo points reads **22s**, not the tooltip's 16 — because Turtle's
*Taste for Blood* adds 6s, which no client-side arithmetic could have known. The Warlock's DoT
durations came back matching the module's own model to the decimal (Corruption 16.9, Curse of
Agony 22.6, Siphon Life 28.2 at *Rapid Deterioration* rank 2), so the estimate was right — but
it no longer depends on bookkeeping that goes stale on a target swap or an outside refresh.

The caster matters as much as the clock: in a group, another warlock's *Corruption* used to
read as yours. It doesn't now.

### 🐛 Fixed — the Hunter stopped shooting (found and fixed during this release)

The first attempt let ClassicAPI *shorten* the sting retry interval while the old detection
still decided whether to cast. Whenever the two disagreed the sting was re-queued every 1.5s,
and a sting is a ranged shot — so it clipped **Auto Shot** on every press and the hunter looked
like it had stopped attacking.

The fix inverts the direction, and it is now a rule for the whole project: a second detection
source may only ever **suppress** a cast, never shorten a throttle or unblock a gate.
Suppression is safe however badly the two sources disagree — the worst case is a missed cast,
never a loop.

### ✨ Shaman — totems that notice being destroyed

`GetTotemInfo` reads the element slot directly, which replaces both the buff-name guessing and
the blind re-drop clock. `PLAYER_TOTEM_UPDATE` covers the case vanilla cannot see at all: a
totem **killed or recalled**, rather than expired.

Verified in game — Totemic Recall emptied two slots in the same instant and both were back
**0.11s and 0.34s later**. This closes the long-standing open item *"Shaman
totem-destruction detection"*.

### 🐛 Fixed — a levelling shaman's totem sat dead for 25 seconds (no ClassicAPI needed)

Totem durations are **rank dependent**. The re-drop table held max-rank values, so rank 1
*Searing Totem* — which lasts 30s — was not re-dropped until 55s had passed. That is exactly
the *"totem upkeep doesn't work"* report the table's own comment records.

Durations are now read from the spell tooltip (the same approach *SpellCost* and *SpellRadius*
already use, so it is right for any rank on any server), applied as a **ceiling**: a tooltip
read can only ever make the re-drop earlier, never later.

This one is worth calling out because it fixes the addon for players who do **not** run
ClassicAPI. It was only *found* because ClassicAPI reported the real duration and contradicted
the table.

### 🐛 Fixed — a totem on cooldown was retried every 1.5s

*Grounding* and *Fire Nova* have a 15s cooldown, *Stoneclaw* 30s against a 15s duration. The
drop attempt never checked readiness, so the slot was retried throughout the dead window. The
casts failed harmlessly, but each stamped the retry clock — delaying the first attempt that
could actually have worked.

### ✨ Hunter's Mark is treated as a shared debuff

It does not stack and its bonus helps every attacker, so any hunter's copy counts: Aegis no
longer marks over a raid mate's, and — more importantly — a Mark it could not previously read
no longer blocks the sting behind it. Stings and *Lacerate* stay owner-filtered; those are your
own damage. Rank is deliberately ignored (it can only matter while levelling).

### ✨ A range window

`/sbr range`, or the *Range window* box in the minimap right-click panel. Shows the distance to
your target on a scale banded into **melee · dead zone · ranged**, with the frame border
carrying the same verdict so it reads from peripheral vision.

The dead zone is the point: a hunter has three zones, not two, and the gap where neither melee
nor ranged reaches is invisible in a text label. The band edges **calibrate themselves** by
watching where the engine's own range verdict flips, because melee reach includes the target's
hitbox and therefore differs per mob.

There is always a real number, with or without ClassicAPI, because **UnitXP_SP3** is required
anyway and resolves mobs. The source order took two corrections before release, both from play
reports: leading with SuperWoW's `UnitPosition` showed `?` against every mob (it resolves for
players only), and then leading with UnitXP silently changed the *metric* — it measures
hitbox-adjusted where ClassicAPI measures centre-to-centre, so the number stopped matching the
scale's own tick labels. Centre-to-centre wins, because that is the model the ticks and the
client's spell ranges use. The learned edges are keyed to the metric and discarded if the
source changes. ClassicAPI now sharpens only the band *edges*, which fall back to flat
thresholds and say so with a trailing dot.

### ✨ Subtlety rogue — raid support

Spec tabs split the rogue panel four ways — Starter, Assassination, Combat, Subtlety. The tab
is a **view**: the rotation does not branch on it, so a setting stays on even while a tab does
not show it. The Subtlety path ranks *Expose Armor* as upkeep rather than an opener, gates *Shadow of
Death* at five combo points, treats *Mark for Death* as a builder with a maximum-CP gate since
it awards two points, and puts *Preparation* last. *Ghostly Strike* rides on its cooldown on top
of the chosen builder.

> ⚠️ **This spec has not been played.** Neither maintainer runs Subtlety; every existing profile
> is Assassination, which is the spec the rotation was actually measured on. The Subtlety path
> is written from `docs/rotations.md` with **no in-game verification** — the ability choices,
> their order, and the combo-point gates are all first-draft judgement. Check it with
> `/sbr trace` before trusting it, and please report what it does.

### 🔧 Under the hood

- All ClassicAPI access goes through one file, `Aegis_SBR_Capabilities.lua`, which owns every
  probe and wrapper. Each returns **nil for "unknown"**, and callers must treat unknown as "not
  a reason to act differently". Capabilities are probed per *function*, so an older DLL missing
  one call still provides the rest.
- `/sbr probe` records verification data passively into its own saved variable while you play,
  read back with `scripts/read_probe.py`. Added because measurements are not practical in a
  group — the rest of the party does not wait.
- New core helper `Aegis_SBR:SpellDuration(name)`, tooltip-based and rank-aware.
- `CLAUDE.md`'s blanket `C_*` ban is replaced by a single carve-out routed through the
  capability file.

---

## v1.1.8 — Rogue combo-point and energy economy, Holy Light gate, poison warning

**Driven by a press log, not by theory.** The rogue trace can be written to SavedVariables, and
this release is what came out of replaying 2000 logged presses per configuration against the
priority list. Several conclusions contradicted what the code assumed — including two of our own
earlier changes, which are reverted here together with the measurements that killed them.

### 🐛 Fixed — time to kill was allowed to *start* the execute phase

The new estimator was wired in as a second execute trigger. That is wrong on any normal mob,
whose entire life is shorter than a sensible window, so *"dies within 3 seconds"* read true from
the first measurement onward: **355 of 394** presses with a known TTK fired execute, at any
target health, mostly on a single combo point.

Target health is once again the only thing that starts the execute phase. Time may only ever
take it **away**, and only below the finisher threshold, so a full-value finisher is never held
back and *Eviscerate only in execute* keeps working on a boss.

The estimate does not justify anything stronger. Measured against how long fights actually ran,
**more than half** of its "dies within 3s" calls were still being fought six seconds later. That
is good enough to veto an action and nowhere near good enough to trigger one.

### ✨ Rogue — a combo-point ceiling for the maintained buffs

Only the *duration* of *Slice and Dice* and *Envenom* scales with combo points, and duration past
the end of the fight is thrown away. Over 28 dungeon pulls: a fight runs ~20s, the gap to the next
~20s more, and the buff carries into the next pull a median of **0.0 seconds**.

**Spend at most** caps what a refresh may spend; the surplus goes into *Eviscerate* and the buff is
refreshed on the next press with the point *Ruthlessness* returns. At 1 the buffs went out at one
combo point in **83 of 88** refreshes and **not once** at four or five. It belongs at 5 (off) in a
raid, where the buff runs its full length.

Note the direction, because the opposite was tried first. A combo-point **floor** was built on the
theory that a longer buff is cheaper per second of uptime. Measured over 1355 presses: Envenom
uptime fell from **84% to 61%** and the rotation pinned itself at two combo points, because
reaching a floor costs a builder global cooldown during which the buff is simply down. The floor is
gone, and the code carries a comment saying why so it does not come back.

Short energy no longer falls through to an expensive refresh — that produced exactly the five-point
buff the ceiling exists to prevent, at 21 energy against a cost of 30, which is under a second of
regeneration. The press is held instead, with the buff itself as the valve: once it has actually
dropped there is nothing left to protect.

### ✨ Rogue — a floor for the execute dump, and an energy check on Cold Blood

Unspent combo points are not a loss when the target dies with them, while a 1-point *Eviscerate*
costs a full finisher's energy for less damage than the builder it displaces. **Use from** sets a
floor: raising it to 3 removed 36 of 38 such presses and lost a median of **0 combo points** on
kills.

*Cold Blood* is free and off the global cooldown so it always "succeeds"; the *Eviscerate* behind it
does not, and one that fails leaves a three-minute cooldown to be eaten by the next builder. Of ten
presses where it was ready at the finisher threshold, **five** could not have paid for the
*Eviscerate*.

### 🔧 Rogue panel — grouped by feature

Reported as confusing, and it had earned it: one section named *Finishers* had grown to nine rows
carrying **four** combo-point sliders — one ceiling and three floors — every one labelled "... CP"
with nothing to tell them apart. A ceiling had already been mistaken for a floor once.

Now grouped as **Attacks · Buffs · Eviscerate · Rupture · Execute · Cooldowns · Poisons**, so the
header carries the context and each row states only what is specific to it. Three rules hold
throughout: the value column shows direction (`>=` for a floor, `<=` for a ceiling); a slider whose
toggle is off is greyed (*Rupture at CP* was the one that was not — fully settable and completely
inert for anyone playing without Rupture); and the neutral position always reads "off", whichever
end of the scale it happens to sit on.

### ✨ Paladin heal — optional Holy Light health gate

A player reported that above the emergency line the heal mode essentially always casts *Holy Light*.
Confirmed, and not a matter of taste: the efficiency comparison meant to favour *Flash of Light*
only runs where **both** heals cover the deficit. Flash tops out at 428 base healing against Holy
Light's 1680, and healing does not start until a unit is 25% down — so Flash is disqualified before
the comparison ever happens.

**Holy Light only below** (0 = off, default) reserves the big heal for units under a set health
percent. It bypasses the coverage logic rather than tuning it, because the problem is that coverage
decides at all, and it applies only while *Flash of Light* is actually castable, so it can never
leave someone unhealed. The reporting player has since run it at 75-80 and reported a clear drop in
mana usage.

### 🐛 Fixed — an out-of-range shock swallowed the press (Shaman)

Reported from play at **level 4**, where Earth Shock plus Lightning Bolt is the whole rotation:
beyond 20 yards nothing happened at all. The rotation puts the shock first, which is correct — but a
shock reaches 20 yards and Lightning Bolt reaches 30, so in between the shock was chosen, failed
silently, and the press did nothing even though the filler underneath it would have landed. All
three shock gates (Enhancement, Elemental, Tank) now require the shock to be in range. Confirmed
fixed in game.

### ✨ Poisons warn before the weapon runs dry

A poison does not fade, it is used up, and the rebuff button only appeared once it was already gone
— which in practice means noticing mid-pull. At **five charges or fewer** the button now turns
yellow, blinks slowly and shows the count, and clicking it tops the weapon up; once the poison is
gone it is **red** rather than purple.

The blink is a triangle wave over 1.4s that never fades below 35% opacity — deliberately slow and
never fully dark, because this is a heads-up and not an alarm. The warning still requires the poison
to be in your bags (a blinking button whose click does nothing is worse than no button), and
requires charges above zero, since a *time*-based weapon enchant reports zero charges on Turtle and
would otherwise blink "0 left" for its whole duration. The shaman's imbue prompt is untouched and
stays purple.

### 🔧 Under the hood

**Spell costs are read from the spellbook tooltip**, not from a table — talents change costs and
Turtle rebalances them, so a constant that is wrong by five energy is worse than no check at all.
Cached per spell and dropped when spells or talents change. Only successful reads are cached, so a
tooltip that failed to populate once cannot freeze the wrong answer in place. An unreadable cost
counts as affordable and can never be the reason an ability does not fire.

**A time-to-kill estimate** in the core: percent of maximum health per second over a rolling
eight-second window, per target, discarded when health goes up or when combat ends. Deliberately a
plain window rather than the recursive least squares the *TimeToKill* addon uses — that earns its
keep over a multi-minute boss with phase changes, while the only question asked here is "under a few
seconds?". It returns nothing until it has four samples over three seconds, and see the warning
above about how far it can be trusted even then.

**`GetWeaponEnchantInfo` was read with seven return values and a gap** in the core, while
`Aegis_SBR_BuffUp` reads six. Six is correct on 1.12 — BuffUp's charge counts are confirmed right in
game — so the core was putting the off-hand flag on the off-hand *expiration* and
`WeaponEnchant("off")` returned nonsense. Latent, because its only caller asks for the main hand,
where both readings agree.

---

## v1.1.7 — Shaman totem + imbue overhaul, per-context buff lists, Paladin melee heal margin

**Two player reports, and what they uncovered.** A shaman reported that a lapsed **Rockbiter**
gave no warning, unlike a rogue's poison; another that **totem upkeep did not work properly**,
to the point of using a macro instead. Both were real, both had a single concrete cause, and
chasing them turned up three further gaps in the same area.

### 🐛 Fixed — a lapsed weapon imbue was invisible

The weapon-slot watch has two modes, `item` (rogue poisons) and `spell` (shaman imbues) — the
same slot check, differing only in how you put it back. **Only the item half was built**, and
the watch sat behind a hard rogue gate, so no shaman ever saw a prompt.
The generic buff monitor cannot substitute: it scans `UnitBuff`, and a weapon enchant is not a
player buff, so the imbue could not simply be added to the watch list instead.

There is now a **"Rebuff button (manual)"** toggle in the Shaman panel's *Weapon imbue*
section. It shows the same on-screen prompt rogues get for a lapsed poison and casts whichever
imbue is selected above it. Its own setting rather than a reuse of the poison flags, because
those are only reachable from the Rogue panel and hang off a switch labelled "(rogue)".

Worth stating plainly: the previous integration note claimed the class panel's auto-apply was
*"superior to a manual button"*. It is not a substitute — `maintainImbue` is **off by default**
and, unless *Apply in combat* is opted in, stands down in combat entirely. An imbue lapsing
mid-fight was covered by neither mechanism. **Chat warnings are suppressed while the button is
on**: several players reported simply not noticing that line in a fight, which is the whole
reason the button exists; printing both would only add noise. With the button off, the chat
warning remains as the fallback.

### 🔧 Weapon imbue: automatic and manual are now clearly two routes

The section read as one feature with confusing extras. It is now two named alternatives —
**"Maintain imbue (automatic)"** and **"Rebuff button (manual)"** — either of which works on
its own, which the tooltips now say outright.

**The "Warn under X minutes" slider is gone.** It only ever printed a chat line, never acted,
and it was interactive *only while the automation was on* — precisely when nobody needs a
warning, since the rotation is already handling it. Its threshold logic (`imbueThresholdMin`
and the `"warn"` state) is removed from the rotation with it.

The same trap was found one field higher: the **imbue picker** was also gated on the
automation, so anyone who wanted only the manual button could not choose which imbue that
button casts. It is now live whenever *either* route is enabled. *Apply in combat* stays tied
to the automation, since it genuinely only qualifies that one.

### ✨ Weapon imbues available to every Shaman spec

The *Weapon imbue* section was gated to Enhancement and Tank. It is now shown for all four —
an Elemental or Restoration shaman still melees between casts, and Rockbiter's threat matters
to a healer holding aggro.

Removing the gate exposed that the upkeep behind it was **not uniform**: Restoration never ran
it at all (the dispatcher returns to the heal rotation before reaching the imbue branch), and
Elemental only pre-pull, never once a fight was under way. Both now match the melee specs.
*(Approved rotation change.)* Placement is deliberately lowest-priority — in Restoration it
sits below every heal and totem, so an imbue can never take a global cooldown away from a
heal, but above the optional damage weave, since a bare weapon degrades every later swing
while a single filler nuke leaves nothing behind.

Defaults are unchanged, so nobody who does not switch it on notices anything.

### 🐛 Fixed — totem upkeep re-dropped on a clock that could not see reality

Reported from play as totem upkeep simply "not working properly", to the point of using a
macro instead. Two separate faults, and the second is the interesting one.

**The clock was wrong.** Redrop came from two blanket constants — 55s water, **110s everything
else** — while durations vary far more *within* an element slot than between slots:

| Totem | Duration | Redropped after | Gap |
|---|---|---|---|
| Magma Totem | 20s | 110s | **90s with no totem** |
| Grounding Totem | 45s | 110s | 65s |
| Searing Totem | 60s | 110s | 50s |
| Windfury / Stoneskin / … | 120s | 110s | fine |

The 120-second totems the constant was sized for worked, which is why this read as an
intermittent, personal problem.

**But a clock is the wrong instrument regardless.** A totem stays where it was dropped. The
group moves on, walks out of its radius, and the aura is gone while the timer happily counts
down — the same for a totem destroyed, or recalled for mana. None of that is visible to a
timer.

So where a totem grants an aura, **the aura is now what is read**, and it answers expiry,
destruction, recall and range in a single check. Totems that grant no aura — *Searing*,
*Magma*, *Fire Nova*, *Grounding* — have nothing to read and keep the timer, which is exactly
why the per-totem durations above still matter: those are the short-lived ones.

A wrong aura name would otherwise be the worst possible failure, reading as permanently
missing and re-dropping forever, so a name is only trusted **once it has actually been seen**
after a cast. If a totem is dropped and its aura never appears, that name is written off for
the session and the totem falls back to the timer — degrading to the old behaviour instead of
spamming. The names are vanilla baselines and worth confirming on Turtle with `/sbr debug`.

**Restoration also carried its own duplicated copy of the four totem calls** instead of the
shared helper, so anything added centrally would have skipped that spec entirely. All four
specs now go through one path.

### ✨ AoE fire pair: Fire Nova on cooldown, Magma between

Requested for lasher farming, where the pull is a cluster of low-health mobs and the fire slot
*is* the damage plan. New **"AoE fire pair (Nova + Magma)"** toggle, which takes over the fire
slot and greys out the single-totem picker.

Deliberately not another entry in that picker: the point is to **alternate** the two, not
choose one. Fire Nova is not upkeep at all — it detonates after a few seconds and then waits on
a cooldown, behaving like a cooldown ability, while Magma is the sustained tick that fills the
gap. Since both occupy the one fire totem slot in game, Magma is held back while a Nova is
still standing, rather than replacing the detonation it was just cast for.

Off by default.

### ✨ Buff watch lists are now per context (Solo / Party / Raid)

The buff monitor's config window gained three tabs. What you keep up alone is not what you keep
up in a raid, and that was the one BuffUp setting with a genuine context need — presets, weapon
watches and the Quick Bar are the same everywhere and stay global.

Party and Raid carry a **"use Solo list"** tick, on by default. An explicit flag rather than
"empty means inherit", so deliberately watching *nothing* in a raid stays expressible. While a
tab inherits, its list is shown read-only and the add-a-buff list is hidden, so a click cannot
quietly edit another tab's contents. The tab you are currently in is marked in class colour
even when a different one is open, so it is always clear which list is in force.

**Existing watch lists are migrated into the Solo slot** and inherited by the other two, so a
setup made before this keeps working untouched. Nothing switches at runtime; the monitor simply
reads a different table.

### 🔧 Paladin — Flash of Light margin widens in melee

When both heals cover the deficit, Holy Light had to overheal 10% less than Flash of Light to
be chosen. In **melee range** that margin is now 25%; at range it stays 10%.

Reported from play while testing the downrank-penalty fix: once the rotation stopped chaining
Holy Lights, the paladin kept Seal of Wisdom running, meleed far more often and regained
noticeably more mana. A 2.5s cast in melee costs more than time — it costs swings, and with
Seal of Wisdom up those swings are mana coming back. At range, on a raid boss, there are no
swings to lose, so the plain overheal comparison stands; `InMeleeRange` doubles as the
dungeon/raid tell, needing no mode toggle of its own.

Narrow in effect by design: this branch only runs when **both** heals cover the deficit, which
is the rarer case — Flash of Light usually cannot cover it and Holy Light wins without any
comparison. Edge-case tuning, not the lever against Holy Light dominance.

---

## v1.1.6 — Hunter's Mark leads the rotation; readable toggle messages

**Approved priority change (Hunter) + command polish.**

- **Hunter's Mark now leads everything**, ahead of aspect upkeep — the first thing the hunter
  does to a target, with nothing else cast until it lands. *(Approved priority-order change;
  it is the only ORDER move in this version.)* It sits above the aspect on purpose: Mark
  costs a press exactly **once per target** — `MaintainDebuff` stops consuming the press the
  moment the debuff is up — whereas the aspect is upkeep that loses nothing by waiting one
  press, the mana swap to *Viper* included, since that is a threshold rather than a deadline.
  The off-GCD layer (pet attack, taunt, burst cooldowns, Kill Command) still runs first
  because it is fire-and-continue and never eats the press.
  **Auto Shot ordering is deliberately unchanged** — the *Aimed Shot* opener remains the
  designed pull action, and it is gated on Auto Shot not having started, so moving Auto Shot
  ahead of it would have silently disqualified it for the whole pull.
- **Toggle messages now name the ability, not the config key.** `/sbr spell mark` prints
  `Hunters Mark on.` instead of `useHuntersMark = on (active profile).`, matching the
  `/sbr aoe` feel — bind it to a key, press it, read the state. Labels are derived from the
  key (strip `use`, split camel case, capitalise) rather than kept in a lookup table, because
  there are **47** spell toggles across the three classes with the command and a table would
  be one more place to forget when an ability is added.
- **README:** the `/sbr spell` row now documents that the on/off argument is **optional and
  toggles when omitted**, with a callout giving the Hunter's Mark command explicitly
  (`/sbr spell mark`, or `/sbr spell hm`). The Hunter section records Mark's new lead
  position, and the missing `opener`/`aimedopener` alias was added to the Hunter alias list.
- **`scripts/verify.py`: fixed a false ordering failure.** The forward-reference check used
  `\b<name>\s*\(`, and `\b` matches between a dot and a letter — so `string.sub(` registered
  as a call to a local named `sub`, and any local sharing a name with a stdlib function
  (`sub`, `find`, `insert`, `format`…) could fail the audit for no reason. The pattern now
  refuses a dotted or colon-qualified match. Genuine forward references are still caught
  (verified against a deliberately broken file).

---

## v1.1.5 — `/sbr spell <name>` now toggles instead of silently switching off

**Command fix, all classes that have the command (Hunter, Warrior, Paladin).** No rotation
logic touched — this is purely how the command reads its argument.

- **`/sbr spell <alias>` with no on/off argument now TOGGLES**, the way `/sbr aoe` and the
  other bare commands already do. Previously the argument was read as
  `(onoff or "") == "on"`, which sent *every* unrecognised argument — including the empty
  one — to **false**. So a bare `/sbr spell mark` did not toggle Hunter's Mark: it turned it
  **off**, every time, whatever the previous state, and then reported "off" as though that
  was what you had asked for. Pressing it twice looked identical to pressing it once, which
  is what made it read as "only enables, never disables" from a keybind.
- **A mistyped argument no longer silently disables the spell.** `/sbr spell mark of` used to
  be indistinguishable from `off`; it now prints usage and changes nothing.
- **Explicit `on` / `off` behave exactly as before**, so any macro that passes one stays
  idempotent however often it fires — worth keeping for a macro you want to force a state
  rather than flip it.
- Applies to **every** spell alias on each class, not just Hunter's Mark — it is one shared
  command (17 toggles on Hunter, 23 on Warrior, 7 on the Paladin's per-profile form
  `/sbr spell <profile> <alias>`). The parsing now lives in one place,
  `Aegis_SBR:ToggleArg`, rather than three copies of the same faulty expression.

---

## v1.1.4 — Warrior: Charge no longer lost to Bloodrage, Rend stops on bleed-immune targets

**Two Warrior fixes, both reported from play and both approved before the change.** No
priority ORDER was altered: one removes a *disqualification*, the other adds a *gate*.

- **Charge is no longer killed by Bloodrage on the pull.** Bloodrage sits in the off-GCD
  layer and fired on any pull press where rage was under the threshold — and out of combat
  rage is always 0, so it fired on *every* pull press. That didn't merely go first: Bloodrage
  puts you in combat, and the Charge gate is `not inCombat`, so from the next press onward
  Charge was unreachable for the whole pull. The symptom in game was Charge never firing even
  at perfect range. (The two also both issued a `CastSpellByName` in the same frame, which is
  unreliable on 1.12 — a later call can override an earlier one.) Bloodrage now holds while a
  Charge opener is pending, which costs nothing: **Charge generates the rage itself**, and
  Bloodrage is still available the moment you land. The hold deliberately persists while
  stance-dancing to Battle, since the opener is still pending during the dance.
- **Rend is no longer spammed at targets that cannot bleed.** Mechanical and Elemental mobs
  are immune, so the debuff never lands, so the "not already on the target" test stayed true
  and Rend was re-attempted on **every press** — a wasted GCD and 10 rage each time, for the
  whole fight. Rend now checks creature type first, cached per target id on the pattern the
  Paladin already uses for Exorcism (one API call per target, not per press; a target swap
  re-reads immediately rather than answering stale). An **unknown** creature type still allows
  the cast — `UnitCreatureType` returns nil for some units, and failing open is only today's
  behaviour, where failing closed would silently disable Rend against ordinary mobs.
  *Localisation note:* the check compares English strings, so on a non-enUS client it
  degrades to "never immune" — the safe direction, but it means the fix is enUS-only for now.

*Still open in the Warrior module:* an Overpower report (the proc being passed over for Slam
and Heroic Strike) is **not** addressed here. Overpower already sits above the strikes and
Slam in the priority list, so the cause is something else — most likely the Battle Stance
gate with stance-dancing off, or the proc window being cleared before a failed cast. Awaiting
a `/sbr log` capture to tell those apart rather than guessing at a hand-tuned list.

---

## v1.1.3 — Rogue tuning + press log, Paladin Consecration & heal-rank fixes, Warlock fillers

**First code release after the v1.1.0 cut.** Four merges land here: Rogue tuning with a
development press log (#30), a Paladin Consecration opt-out plus a creature-type cache
(#31), a Paladin downranked-heal estimate fix (#33), and the Warlock filler upgrades (#34).
No priority ORDER changed in any class — every rotation-affecting item below is either
opt-in and default-off, or a correction to a *value* the existing list already used.

### Rogue

- **Buff-renew window is now a per-profile slider (0–2s, default 1)** in place of the old
  hard-coded 5s. That 5 was sized for an era when the remaining time on Slice and Dice /
  Envenom was *estimated*; reading the real timer removed the reason for the padding, so the
  old value was throwing away up to 4s of buff — and the combo points that bought it — on
  every refresh. The new default is measured, not guessed: a two-minute press log showed an
  average 0.64s left at refresh, Slice and Dice never dropped, and Envenom lapsed three times
  for ~2.4s total (≈2% downtime). Set it to **0** to refresh only once a buff has actually
  lapsed; the test is `<=`, and the UI reads the field without an `or` fallback, so a
  deliberate 0 is never silently turned back into 1.
- **Cold Blood** (*opt-in, default OFF*). When enabled it fires in the **same press**,
  immediately before Eviscerate — deliberately not a priority step of its own, because the
  buff is consumed by whatever you cast next, and that would usually be a builder (Noxious
  Assault included) rather than the finisher it was saved for. Costs no GCD (confirmed in
  game), and it is gated on your **Finisher CP** setting so the 3-minute cooldown isn't
  spent on the low-CP execute finisher. Adds a `cb=` field to the rogue trace line.
- **`docs/turtle-mechanics.md` gains a Rogue section** recording what Turtle actually does:
  all three upkeep finishers cost **20 energy** (not vanilla's 25/35), the real Slice and
  Dice / Rupture / Envenom duration tables, and **Improved Blade Tactics** — Turtle's Slice
  and Dice duration talent (+45% at 3/3), whose tooltip shows only the *base* duration, so a
  talented Slice and Dice actually runs 13.05–30.45s. Also a measured dungeon damage split
  (Instant Poison 66.2%, auto-attack 13.8%, Noxious Assault 10.9%, Eviscerate 7.5%,
  Rupture 0.8%) for future tuning arguments.

### Paladin

- **Consecration can now opt out of the mana-recovery hold** (*Consecrate in mana mode*,
  default OFF — behaviour is unchanged unless you turn it on). The recovery flag **latches**:
  it switches on below your *Mana low* threshold and only switches off again at *Mana high*,
  so a wide band (a tank on 60/90, say) can keep it on for an entire fight with mana sitting
  comfortably in between. Nothing in the UI surfaces that state, so the symptom was
  Consecration reading as "off cooldown, full mana, still never casts" — found in a live
  protection profile. The toggle exempts Consecration alone; Exorcism deliberately keeps the
  old behaviour, being the far more expensive spell. The tooltip explains the latch.
- **Downranked Holy Light no longer scales with +healing as if the low-rank penalty didn't
  exist.** Ranks learnt below level 20 receive only `1 - (20 - levelLearnt) * 0.0375` of the
  gear bonus, and the estimate applied the full coefficient to every rank — an error that
  grows with gear, which is exactly where it hurts. At a routine +900 healing, Holy Light
  rank 1 was estimated at 693 and actually landed ~235 (3.0× over), rank 2 at 726 vs ~388,
  rank 3 at 816 vs ~671. Since the rank picker takes the **smallest** rank whose estimate
  covers the deficit, an inflated low rank wins outright: a 600 deficit picked rank 1
  expecting 693 and healed ~235. It also fed the Flash of Light vs Holy Light comparison, so
  this partly explains the community report that Holy Light crowds out Flash of Light above
  the emergency line. Only Holy Light needs the correction (ranks 1/2/3 come at level 1/6/14;
  Flash of Light starts at 20 and Holy Shock at 40, both at a factor of 1). Verified against
  the stated formula rather than a derived one.
- **Creature type is now cached per target** instead of calling `UnitCreatureType` on every
  press — `TargetIsUndeadOrDemon()` sits in the hot path and a target's type never changes.
- *Not shipped:* a `holyLightPct` health-percentage gate for the same Flash of Light problem
  (#32) was **closed unmerged** in favour of the fix above. It treated the symptom rather
  than the cause, and pointed the opposite way to the established approach, which reserves *Flash of Light*
  for units in real danger rather than reserving Holy Light for them. Whether a slider is
  wanted at all — and which direction it should point — is worth re-measuring in game now
  that the rank estimate is correct.

### Warlock

**Warlock Rotation & Filler Upgrades**

• **Custom "Between Channels" Filler:** When using Dark Harvest as your filler, you can now customize what spell fills the gap while it's on cooldown. Choose between **Shoot (Wand)**, **Shadow Bolt**, **Drain Life**, or **Drain Soul**!
• **Drain Soul as Main Filler:** Drain Soul can now be selected directly as your primary filler spell in the class dropdown menu.
• **Smart Channel Safeguards:** The rotation now intelligently tracks channel durations alongside your active DoTs and cooldowns. It won't start channeling if a DoT is about to expire or if Dark Harvest is coming ready mid-channel, ensuring maximum DoT uptime and seamless cooldown usage.
• **Cleaned-Up Execute UI:** When Drain Soul is selected as your main filler, the Execute setting automatically greys out to reflect that it's already active, keeping your UI clean while preserving your saved settings.

### Development tooling

- **`/sbr log on|off|clear` — a press log to file.** Records one line per rotation press into
  a new `AegisLog` saved variable, written to `WTF\...\SavedVariables\Aegis_SBR.lua` on
  `/reload` or logout. The 1.12 sandbox has no file access whatsoever — no `io`, no `os`, and
  neither SuperWoW nor Nampower adds any — so a saved variable is the only route to get a
  trace off the client for analysis. Kept **out of `AegisDB`** so a large log can never bloat
  or endanger profile data, and so it can be cleared on its own. Built as a true ring buffer
  (wrapping write index, 2000 lines) rather than append-and-trim, because `table.remove(t, 1)`
  would shift every entry on every press, inside the rotation's hot path; each line carries a
  timestamp relative to the log start so ordering survives the wrap.
- **Trace-guard fix — the part that made the log actually work.** Every class module builds
  its trace string behind `if self.trace then`, to skip the concatenation when nobody is
  listening, so hooking the log inside `Trace()` was dead code unless the chat trace happened
  to be on as well. New `Aegis_SBR:Tracing()` (true when chat trace **or** logging is active)
  now backs all 18 guards. It only affects *when the string is built* — no rotation behaviour
  changes.
- Chat trace and the log stay independent: the chat line keeps its 0.4s throttle so it stays
  readable while playing, while the log takes **every** press, since a throttled sample would
  bias exactly the distributions it exists to measure. Only the first trace line is logged —
  the supplementary ones (the rogue's `rank: ...`, for instance) are static for a whole
  session and were doubling both file size and ring slots for nothing.
- Zero footprint if unused: `AegisLog` is created lazily on the first `/sbr log on` and never
  at load, so a player who never touches the command never carries the variable, and entries
  are dropped one load after logging is switched off. `log` is intentionally left out of the
  `/sbr` command list — it's a development aid, to hand out on request when diagnosing a
  report.

---

## v1.1.0 — Release: README overhaul, dependency accuracy pass

**Docs-only release cut.** No rotation or engine code changed since v0.16.2 — this version
marks the README reaching release quality: restructured, verified against the actual
dependency stack, and carrying the project's real community links.

- **README rewritten top to bottom**, in a scannable, badge-led format: a Contents table,
  each of the nine class modules collapsed into its own `<details>` section (full detail
  preserved), a *Requirements* table, a command reference split into general/per-class, an
  *A few honest notes* section (hand-tuned priorities + the open audit, best-effort Turtle
  names, manual AoE, no ground-target casting, the debuff cap, enchants as pre-pull-only
  tools), an *Under the hood* file-tree + Lua 5.0 rationale, and a *Contributing* section
  that states the no-silent-rotation-changes rule.
- **Badge header** (Discord · Octo WoW · Capy WoW · the required/recommended dependency
  stack) is now user-curated — see `CLAUDE.md` for the exact rows/colours to preserve on
  future edits.
- **Requirements table corrected against the actual source**, not assumed convention:
  SuperWoW is the one true hard dependency (the four healer engines call
  `CastSpellByName(spell, unit)` with no fallback — unit-targeted healing breaks without it);
  Nampower's queue calls already fall back to a plain cast, so the addon *runs* without it
  but loses clip-free cast timing; UnitXP_SP3 is SCRM's requirement, not one Aegis calls
  directly; ClassicAPI is listed as not-yet-used, with a pointer to the new research doc.
- **New `docs/research-classicapi.md`** — a deep-dive on the ClassicAPI DLL (250+ backported
  Blizzard API functions for 1.12): what it could unlock for Aegis (enemy debuff *durations*
  — the one gap the required stack can't fill — exact spell range, and a near-free profile
  import/export via `C_EncodingUtil`), what it can't replace, the `CLAUDE.md` rule conflict
  it raises (the blanket `C_*` ban predates this DLL), and an in-game verification checklist
  before any of it is built.
- **CHANGELOG history repaired.** A prior merge had left two version numbers each used
  twice (`0.15.4` and `0.15.5`, one pair a literal duplicated header, the other a genuine
  collision between two different features). Renumbered using each commit's own recorded
  version bump as the source of truth: the BuffUp-integration entry is now correctly
  `v0.16.0` (its commit cut the `.toc` to 0.16.0; that number was lost in a later rebase),
  with the Sunder-slider and Master-Strike entries following it as `v0.16.1` / `v0.16.2`.
  Every version number below is now used exactly once.

---

## v0.16.2 — Warrior Master Strike (opt-in) + README refresh

**Feature + docs.**

- **Warrior: optional *Master Strike*** (*Strikes* section, **default OFF**). The Arms talent
  is normally skipped as a PvP pick; enable the toggle and it fires on cooldown from a slot
  **directly below your spec's primary strike**, filling the windows while *Mortal Strike* /
  *Bloodthirst* / *Shield Slam* cool down — so turning it on never delays your main strike.
  It's a talent-granted spell, so it's detected once talented and shows *(not learned)* until
  then. Also `/sbr spell masterstrike|mstrike on|off`.
  *Its rage cost is estimated (25) — Turtle's exact value isn't documented in the in-repo
  talent reference. If it ever skips casts it could afford, or attempts one it can't, that
  single number in `Class_Warrior.lua` is the tuning knob; report the tooltip cost and it can
  be set exactly. It is likewise not stance-gated, since the stance rule is unverified.*
- **README refresh:** a new **Links & Community** section (source/releases, issue tracker,
  the [Discord](https://discord.gg/hsgPTNkSX), in-repo docs), a Key Features entry for the opt-in
  weapon-enchant awareness (Shaman imbue upkeep + Rogue poison reminder), the Hunter aspect
  section rewritten for the two independent Viper/combat thresholds, the new Warrior Master
  Strike bullet, and the shout + Master Strike spell aliases added to the Warrior alias list.

---

## v0.16.1 — Warrior UI: Sunder stacks slider folded into the Sunder Armor toggle

**UI polish.** The Warrior *Sunder stacks* slider is now part of the *Sunder Armor* toggle
row (a combined toggle+slider, matching the Hunter Mend Pet / Shaman Mana Tide rows) instead
of sitting as a separate slider at the bottom of the Threat/AoE section. The slider follows
the toggle (greyed when off) and hides when Sunder Armor isn't learned. No behavior change.

---

## v0.16.0 — Upkeep monitor (buffs + rogue poison Quick Bar), Rogue execute, Paladin double-heal fix

**Feature + fixes.** Adds an optional upkeep monitor for buffs and rogue poisons, a rogue execute finisher, and fixes a Paladin double-heal.

### ✨ Upkeep monitor (new `Aegis_SBR_BuffUp.lua`)
Two **independent** features, each toggled in the minimap right-click panel (new "Upkeep monitors" section), so one can run without the other:
- **Buff monitor** (all classes): watch chosen self-buffs; when one is missing, a clickable rebuff button appears on screen to recast it. Its own config window (class-coloured frame) opens from the minimap panel's **Configure** button — scan your current buffs and click to watch, click a watched entry to remove. Buff detection is name-based (rank/locale proof) with an icon-texture fallback; a `SPELLS_CHANGED` rescan keeps a newly-learned rank matched.
- **Poison control** (rogue): a movable **Quick Bar** of up to 4 poison presets — left-click a preset for mainhand, right-click for offhand — plus optional rebuff buttons when a poison falls off. Presets are configured in the **Rogue class panel** (Poisons section): enter just the poison *type* (e.g. "Instant Poison", **no rank**) and whatever rank is in your bags is found and applied automatically. Each Quick Bar button shows charge and remaining-time bars (mainhand left, offhand right), captured on first apply. Applying a poison needs a real click, so it is always button-driven, never cast from the rotation macro. The bar auto-sizes to the number of configured presets, and preset labels abbreviate elegantly (drop the redundant "Poison", keep the rank).
- Poison presets / buff watch list are stored per character (`AegisDB.buffup`), shared across profiles.
- New shared UI primitive `Aegis_SBR_Layout:Button` (a clickable label+value row) backs the preset editors.
- **Deliberately not carried over:** a manual button for shaman weapon imbues. The class panel's Weapon-imbue upkeep already auto-casts them, which is better than a button to click.

### ✨ Added
- **Rogue — Execute low-HP targets** (opt-in, default OFF; Finishers section). Below a configurable health threshold (default 10%), Eviscerate fires with whatever combo points are on hand instead of waiting for the normal threshold, so points aren't wasted on a kill. Ruthlessness guarantees at least one combo point after any finisher, so this is rarely blocked. Adds an `exec=` field to `/sbr trace`.

### 🔧 Changed
- **Rogue — pre-pull poison reminder retired.** The chat warning is superseded by the poison Quick Bar / rebuff buttons, which surface a missing poison on screen. (Poisons *can* be applied in combat via those buttons; the old reminder's "pre-pull only" assumption is gone.)

### 🐛 Fixed
- **Paladin — double heal on a topped-off target.** Two causes: (1) `StillCasting` now reads the client's real cast bar (`CastingBarFrame`) instead of a cast-time estimate, so a spammed press during a Holy Light cast (2.5s, longer than the 1.5s GCD) can't start a second heal before the first lands — this also correctly accounts for Nampower's queue starting the cast slightly later than the call. (2) The in-flight-heal prediction no longer discards itself when an actively-tanked target dips below its commit-time health during the post-cast latency window; the prediction is additive and capped, so it self-corrects for real new damage without re-healing a target the first heal already covered.

---

## v0.15.3 — Warrior shout upkeep: Battle Shout + Demoralizing Shout (audit W1 + W4)

**Feature (rotation, user-approved).** Implements the two shout gaps the Phase 1 audit
flagged — Battle Shout was missing from the Warrior module entirely despite being the first
line of the Arms/Fury rotation. Each is its own toggle.

- **Battle Shout** (*Shouts* section, **default ON**): keeps the party attack-power buff up.
  Refreshed only when it's **missing or under ~30s left**, and placed **below your strikes**
  so it never delays one — it costs a global cooldown only about once every two minutes.
  Any stance, rage-gated, and skipped during the Execute phase so rage feeds Execute. The
  time-left read is guarded so an unreadable duration can't spam it. Because Battle Shout
  now defaults on, existing warrior profiles will start maintaining it after you update
  (toggle it off in the panel if you don't want it).
- **Demoralizing Shout** (*Shouts* section, **default OFF**): keeps the enemy attack-power
  reduction on your target for mitigation (tanking). Debuff-maintained exactly like Rend —
  re-applied only when it falls off the target. Any stance, rage-gated, skipped in Execute.
  Opt-in, since it spends a debuff slot (mind the raid debuff cap).
- Also adds `/sbr spell` aliases: `battleshout`/`bshout`, `demoshout`/`demo`.

---

## v0.15.2 — Minimap button click fix, take 2 (strata, for pfUI)

**Fix.** Follow-up to the 0.15.1 minimap fix, which wasn't enough. pfUI layers its minimap
border / click-catcher on a **higher frame strata** than the minimap, and the 0.15.1 change
only raised the button's frame *level* — which orders frames within the same strata, so
pfUI's overlay still intercepted the clicks. The button is now on a higher strata than that
overlay, so the whole button is clickable (the adaptive edge-hugging radius from 0.15.1 is
kept). If it's still finicky under a specific pfUI config, that points to click-vs-drag or
button collection rather than layering — report back and it can be tuned further.

---

## v0.15.1 — Hunter dual mana-aspect thresholds + minimap button clickable under pfUI

**Tuning + fix.**

- **Hunter: two mana-aspect sliders.** The single "swap to the mana aspect below X%" (with a
  fixed +15% swap-back) is now **two independent thresholds**: *Viper below* (drop to Aspect
  of the Viper when mana falls under this) and *Back to combat at* (swap back to Aspect of
  the Hawk/Wolf once mana recovers to this). Set them wherever you like — e.g. Viper at 20%,
  back at 70%. Existing profiles keep their old behavior exactly (the back mark defaults to
  the previous low + 15%); a guard keeps the back mark above the low mark so the aspect never
  flaps. Which abilities fire is unchanged — only *when* the mana-regen aspect is worn.
- **Minimap button: clickable under pfUI.** The button was placed at a fixed radius from the
  minimap centre, so pfUI's smaller/reshaped minimap left it floating over pfUI's border
  where only a sliver was clickable. The radius is now derived from the minimap's actual
  size (so it hugs whatever minimap is present) and the button's frame level is raised above
  the minimap cluster so clicks aren't intercepted. It also stays draggable.

---

## v0.15.0 — Phase 2: weapon-enchant detection + Shaman imbue upkeep + Rogue poison reminder

**Feature (gated, conservative, default OFF).** The first Phase 2 batch: a shared
weapon-enchant detection helper and two per-class upkeep features built on it. Detection is
ungated plumbing; the class behaviors were implemented against an explicit sign-off for
exactly the conservative design in `docs/research-weapon-enchant-upkeep.md` — nothing fires
unless you turn it on.

- **Shared detection helper (core).** `Aegis_SBR:WeaponEnchant(slot)` returns
  `has, msRemaining, charges` from `GetWeaponEnchantInfo()` (read live each call, because
  `msRemaining` is a running countdown); `Aegis_SBR:WeaponEnchantId(slot)` returns the
  enchant id via `GetWeaponEnchantID`. Both presence-gated, so a client without SuperWoW's
  enchant API degrades cleanly. Confirmed on Turtle 1.12 (charges reads 0 for a time-based
  enchant, so upkeep gates on `has`/`ms`, never charges).
- **Shaman — main-hand weapon-imbue upkeep** (config: *Weapon imbue* section, default OFF).
  Pick an imbue (Rockbiter / Flametongue / Frostbrand / Windfury). When the main hand is
  **bare**, it auto-casts the imbue **out of combat** (or on approach); **in combat** it only
  re-imbues with the *Apply in combat* opt-in (a GCD cost), otherwise it just reminds you.
  When an imbue is present but under the *Warn under* minute threshold, it **warns rather
  than overwriting** (the replace popup is untested and re-imbuing costs a GCD). Pre-pull
  upkeep runs even with no target selected, and never auto-acquires a mob. **Which ability
  fires in the actual combat rotation, and in what order, is unchanged** — this is a
  lowest-priority self-buff step above the Lightning Bolt filler. Main-hand only; off-hand
  imbue is deferred (a fragile weapon-click flow).
- **Rogue — poison pre-pull reminder** (config: *Poisons* section, default OFF). Because
  poisons can't be applied in combat, this never auto-applies: on entering combat, if a
  weapon poison is missing it prints a warning (off-hand only when an off-hand weapon is
  equipped). No rotation change.
- Imbue/poison spell names are best-effort and `KnowsSpell`-gated — confirm with `/sbr debug`
  if an imbue isn't recognized.

Still open in Phase 2: off-hand imbue, Rogue poison auto-apply (needs the replace-popup and
in-combat-application tests), and Shaman totem-destruction detection.

---

## v0.14.1 — Phase 1 rotation audit report + Hunter sting-detection fix

**Audit + one pre-authorized fix.** The Phase 1 rotation-correctness audit is complete:
`docs/audit-phase1-rotations.md` holds a per-class discrepancy report (all 9 classes; what
the code does vs. `docs/rotations.md`, with source, confidence tag, recommended action, and
risk). **No rotation priorities were changed** — every finding waits for per-class
sign-off, per the project's audit-and-report rule. The one code change is the known Hunter
bug the roadmap pre-authorized as a non-priority fix:

- **Hunter — sting/Mark detection icon fallback.** Every Serpent/Scorpid/Viper Sting and
  Hunter's Mark check passed no icon fragment to the debuff scanner, so on a client where
  SuperWoW's id→name resolution is unavailable (or misses an id) the debuff always read
  "not up": the sting was blind-recast every throttle interval, and an Undead target was
  wrongly learned as sting-immune after 2.5s. The classic 1.12 icons are now supplied as
  the scan fallback (Serpent=`Ability_Hunter_Quickshot`, Scorpid=`Ability_Hunter_CriticalShot`,
  Viper=`Ability_Hunter_AimedShot`, Mark=`Ability_Hunter_SniperShot`); exact-name matching
  still wins whenever SuperWoW resolves the id. Which ability fires, and in what order, is
  unchanged. (Lacerate keeps name-only detection — its custom Turtle icon is unconfirmed.)

---

## v0.14.0 — Rebrand: AutoRota → Aegis: Single Button Rotation (Aegis_SBR)

**Rebrand (roadmap Phase 0).** The addon is now **Aegis: Single Button Rotation** — folder, files, commands, and saved variables. Rotations, priority lists, and panels are deliberately untouched; this release only renames and migrates.

- **Folder + files:** install as `Interface\AddOns\Aegis_SBR\` (`Aegis_SBR.toc`; core files renamed to `Aegis_SBR.lua` / `Aegis_SBR_UI.lua` / `Aegis_SBR_Minimap.lua`; class modules keep their names and load order). **Remove the old `AutoRota` folder when installing this version** so both never load at once.
- **Slash commands:** `/sbr` is the primary command (long form `/aegis`), and **`/ar` keeps working as a legacy alias** so existing macros don't break — all on one handler key, so nothing double-fires. The minimap toggle is `/sbrmap` (legacy `/armap` kept). The paladin-era aliases (`/autorota`, `/paladinauto`, `/pa`, `/autopala`) are removed.
- **Profiles migrate automatically:** per-character saved variables move from `AutoRotaDB` to `AegisDB` on first login (the shim only adopts the old data when `AegisDB` is empty, and tags it `_migratedFrom`). `AutoRotaDB` stays listed in the `.toc` as a live rollback backup for a few versions. **Back up your `WTF\` folder before the first login on 0.14.0.** If your profiles don't appear: while logged out, copy `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\AutoRota.lua` → `Aegis_SBR.lua` in the same folder, then log in again.
- **Fonts packaging fix:** the bundled *PT Sans Narrow* faces (and `OFL.txt`) now actually ship inside `Fonts\`, where the UI's font paths and the README always pointed — fresh installs no longer silently fall back to the client font. New/renamed files mean a **full relog**, not just `/reload` (the folder rename forces one anyway).
- **Logo header stub:** the config window tries `Interface\AddOns\Aegis_SBR\logo` at build time and falls back to the sigil + `AEGIS SBR` wordmark while the file is absent (1.12 `SetTexture` returns nil for a missing file, so no broken quad). The real TGA lands in a later cut.
- **Tooling:** `scripts/verify.py`'s define-before-use audit no longer flags a function's own inner locals (e.g. locals captured by closures) — three long-standing false positives cleared, and the `--all` baseline is green again.
- **Versioning:** this cut supersedes the drifted 0.13.13b (core `ver`) / 0.13.14b (`.toc`, README) / 0.13.15b (changelog) stamps; all version spots now read 0.14.0.

---

## v0.13.15b — Paladin heal-mode gating and heal-rank selection, Rogue rank trace, Assist fix for support modules

**Fix + tuning.** Closes a heal-mode gating gap in the Paladin's damage rotation, reworks the heal-spell/rank choice around an efficiency comparison, and fixes the new Assist targeting mode being silently inert for any support module (currently only the paladin heal mode). Developed and tested in-game on a Holy Paladin.

- **Rogue: max-rank trace.** `/ar trace` now reports the max known rank for every ability the rotation casts. All Rogue casts are bare `CastSpellByName(name)`, which vanilla already resolves to the highest known rank, so this line exists to make that fact verifiable in-game rather than assumed.
- **Fix — Paladin damage/tank rotation steps leaking into heal mode.** *Strike*, *Holy Shield*, *Consecration*, *Hammer of Wrath*, *Repentance*, and *Exorcism* were missing a `not cfg.healMode` guard, so a toggle left on from the Damage tab (most visibly *Crusader Strike*) kept firing in heal mode outside its intended purpose (the Blessed Strikes Holy Shock reload), contradicting the Healer tab's own "Tank / Damage settings are ignored" description. All six steps are now gated consistently.
- **Paladin: heal-rank selection reworked**:
  - Healing-reduction debuffs (Mortal Strike and the like) inflate the effective deficit used for rank selection, then the committed/predicted heal is scaled back down since the extra healing never lands.
  - In-combat cast-time compensation pads the deficit before rank selection, since the target keeps losing health while the cast is in flight.
  - Below the Holy Shock emergency threshold, Flash of Light is kept over Holy Light even for a deficit it cannot fully cover — a fast partial heal beats risking the target dying mid-cast on a slow Holy Light.
  - Outside the emergency case, Flash of Light and Holy Light are now compared by their actual landing heal (post-debuff-modifier) and whichever wastes less overheal wins, replacing a fixed threshold that forced Holy Light too early and could waste close to half the cast as overheal.
- **Paladin UI**: the Holy Shock threshold slider's tooltip now mentions its secondary role gating the Flash of Light vs. Holy Light choice.
- **Fix — Assist targeting mode was inert for support modules.** `/ar acquire assist <name>` reused the same guard that keeps `auto` from force-pulling a target for a healer, which also suppressed `assist` — mirroring an ally's already-selected target is not a fresh pull, so it never should have been gated the same way. Assist now runs unconditionally, which is also what lets a melee-holy healer's strike weaving (which needs an actual target) follow the tank hands-free.

---

## v0.13.14b — Warlock: Dark Harvest overhaul, cast-confirmed DoT tracking, and a three-way targeting mode

**Feature + fix.** A deep pass over the Warlock's Dark Harvest handling and DoT recast reliability, plus a new global targeting mode with GUID-based assist. Cross-checked against SuperCleveRoidMacros' and Cursive's own Dark Harvest / duration tables during development, so the base durations and the 30%-tick-boost math are no longer guesses.

- **Dark Harvest restored as a filler, DoT-aware.** Dark Harvest channels the instant it is off cooldown and wand-fills (falling back to *Shadow Bolt* with no wand equipped) between channels instead of leaving the rotation idle. Before committing to a channel it checks every enabled DoT's estimated remaining time and tops up anything that would fall off mid-channel — the channel's own length is Rapid-Deterioration-scaled (confirmed in-game: 8s base → 7.52s at rank 2, the same 6% cut the talent applies to Corruption / Curse of Agony / Siphon Life), and the required buffer accounts for Dark Harvest's own 30% tick-rate boost eating the DoT's remaining life faster than real time. The 30%-boost math (tick-boundary alignment, one active-channel window) is a direct port of Cursive's verified `curses:TrackDarkHarvest` / `GetLastTickTime` / `GetDarkHarvestReduction`, adapted for the fact AutoRota only ever evaluates it once a channel has already ended.
- **Cast-confirmed DoT tracking.** DoT recasts are now confirmed via SuperWoW's `UNIT_CASTEVENT` (`CAST` vs `FAIL`) instead of being stamped as successful the instant they are sent. A cast that silently fails (most commonly the GCD still being active while the wand fires) used to blank out the recast window for the full throttle interval doing nothing; it now retries on the very next press. `DotRemaining()` (used only to gate the Dark Harvest start) rides the same confirmed timestamp.
- **Wand stops itself ahead of a DoT expiring**, instead of reactively trying to interrupt a shot that may already be mid-flight the instant the DoT falls off — a tracked DoT within 1.5s of expiring pauses (or does not start) the wand, trading a small bounded gap for eliminating the recast-vs-shot race.
- **Rapid Deterioration talent support.** The Turtle-specific Affliction talent (2 ranks, 3% shorter Corruption / Curse of Agony / Siphon Life duration per rank, more damage per tick) is read from the talent tree and scales every duration estimate — including Dark Harvest's own channel length — by the rank actually taken, not just its presence.
- **Malediction secondary curse restored.** With that talent, Curse of Agony rides alongside your main curse (skipped when the main curse already is Agony or Doom) and is now tracked and refreshed on its own again.
- **Soul shard farming restored**, folded into the Drain Soul execute finisher rather than duplicating it: with *Stop early to keep shards* on, Drain Soul stops finishing targets once your shard count reaches the target, instead of draining every kill regardless of how many shards you're already holding.
- **Low-mana wand fallback.** Below a configurable mana floor (default 15%), the rotation prefers Life Tap if it's safe to use, otherwise drops to the wand — previously a DoT that needed recasting but couldn't be afforded would still be queued, fail in-game, and stall the rotation for nothing.
- **Nightfall moved to the top priority.** The free instant Shadow Bolt on a Shadow Trance proc is now checked before Drain Life / Health Funnel / Shadowburn / Drain Soul, since a longer-running channel started first could burn through the whole proc window before the rotation got back around to it.
- **Fix — Shadowburn no longer stalls at zero shards.** It now checks your actual Soul Shard count before casting; previously, at 0 shards near the execute threshold, the cast failed in-game every press while the addon believed it had succeeded, stalling instead of falling through to Drain Soul or the filler.

**New global targeting mode: Assist.**
- The minimap right-click panel's single "auto target" checkbox is now three mutually exclusive radios: **Auto** (acquire the nearest enemy when you have none, unchanged default), **Manual** (defer entirely to you or a separate assist addon), and **Assist** (continuously mirror a chosen party/raid member's target). A "P" picker button next to the Assist name field lists your current group/raid live.
- Assist matches **only by GUID**, re-resolved every press via SuperWoW's `UnitExists`/`TargetUnit` — never by name. A prior addon's name-only matching couldn't tell two different mobs with the same name apart (e.g. one already tapped by a different nearby group), which in practice meant silently attacking the wrong group's mob without ever noticing; GUID matching makes that class of bug structurally impossible.
- `AutoRotaDB.acquire` (boolean) is migrated transparently to the new `AutoRotaDB.targetMode` the first time it's read after upgrading — no action needed on existing installs.
- `/ar acquire on|off|assist <name>` covers the new mode from the command line as well as the panel.

All Lua files pass the balance check; the define-before-use ordering audit is clean.

---

## v0.13.13b — Paladin: strike-toggle rework, heal-mode mana + split weaves, and a tab-switch fix

**Feature + fix.** A pass over the Paladin's Damage/Tank strikes and Healer mode, plus a shared-shell fix that made the Damage tab unreachable once Healer was selected. Confirmed in-game on the 1.18.1 client.

- **Fix — the Healer → Damage tab was stuck.** The boolean tab rail (paladin `healMode`) computed its stored value through `st.encode and st.encode(key) or key`. When `encode` returned `false` (the Damage tab) the and/or idiom fell through to the string `"damage"`, which is truthy, so the rotation kept healing and the tab could never switch back — only `/ar heal off` worked. `SelectSpecTab` now assigns the encoded value directly, and `healMode` is coerced to a strict boolean in NormalizeProfile, repairing any profile the old bug corrupted. String rails are unaffected.
- **Live tab/edit apply.** Editing the **active** profile now applies immediately — a tab (or any control) is a live switch with no separate Activate step — so you can flip Healer ↔ Damage or re-tune mid-fight by clicking. Untrained spells no longer block anything: the rotation skips what isn't learned, so a profile is always usable and always applies (Save/Activate and the live apply are no longer gated on validity; missing spells show as an amber note only). The footer reads `Active profile — changes apply live` for the running profile.
- **Strikes — two toggles + a both-on strategy (replaces the Strike-mode dropdown).** *Holy Strike* and *Crusader Strike* are back as two toggles: enable one alone to use **only** that strike; enable both to reveal a strategy dropdown. This also fixes a regression where the single-strike modes were ignored — the old shared-cooldown resolver ran its Zeal/Holy-Might weave regardless of mode, so "Holy Strike only" still fired Crusader Strike.
  - **Auto DPS (talent-aware).** Without *Vengeful Strikes*, *Crusader Strike* builds *Zeal* to 3 stacks, then *Holy Strike* fills (which still returns mana/health to the group). With the talent, *Holy Strike* opens for *Holy Might* and is kept up while *Zeal* is ramped; if both buffs would fall in the same 6s window, *Zeal* wins — three stacks cost more than a one-GCD Holy Might refresh.
  - **Tank block.** Keeps *Crusader Strike*'s *Zealous Defense* block buff loaded (it is consumed on the next block) and spends every other global on *Holy Strike* for threat (*Righteous Strikes*).
  - The old weapon-lean and *Prioritize Zeal* toggle are retired (their behaviour now lives in Auto DPS). New command: `/ar strike off|hs|cs|auto|tank`.
- **Heal mode — dedicated mana upkeep.** Heal mode no longer borrows the damage seal engine. A heal-only **Mana management** section adds **Seal of Wisdom (self mana)** — keep the seal up so your melee swings return mana to you — and **Judge Wisdom (group mana)** — judge *Seal of Wisdom* onto the mob (*Judgement of Wisdom*) so everyone attacking it gets mana back. The group judge is a global you cannot heal during, so it is opt-in and defaults off; both run only in melee downtime and never over a heal.
- **Heal mode — the melee-holy weave split in two.** The single *Weave strikes* toggle is replaced by two, since each strike is a global. **Reload Holy Shock (CS)** weaves *Crusader Strike* to reset Holy Shock (*Blessed Strikes*), keeping the emergency instant loaded — greyed unless the talent plus both spells are present, and not limited by the filler mana floor. **Holy Strike filler** uses *Holy Strike* in downtime for its splash heal, gated by its own **mana floor**. The Blessed-Strikes weave is also decoupled from the Damage-tab strike toggles, so the default Healer profile weaves as intended.
- **UI clarity.** Tabs renamed **Tank / Damage** and **Healer**, each with a subtitle line noting the tab **is** the active mode and the other tab's settings are ignored (the tab framework gained optional per-tab subtitles). *Mana management* and *HP management* are now Damage-only, so they no longer appear on the Healer tab. *Holy Shock emergencies* shows OFF and greyed until the spell is trained (its saved value is untouched), with a tooltip clarifying it is used only as a heal in heal mode. The *Judgement weaving* and *Wisdom debuff in mana mode* tooltips were rewritten so they are no longer confused with each other.

All Lua files pass the balance check; the define-before-use ordering audit is clean.

---

## v0.13.12b — Shaman totems in every spec, cast-event-driven re-drops, Warrior fixes

**Feature.** Totem maintenance is no longer Restoration-only, and re-drop timing is upgraded from a blind clock to real cast confirmation. A Warrior auto-attack bug is also fixed, with two new leveling toggles.

- **Totems across every spec.** Enhancement, Elemental, and Tank now maintain the full four-element totem set during a lull, exactly like Restoration always has. The picker section moved out of the Restoration-only card into a shared **Totems** section visible on every tab.
- **Searing Totem folded into the fire-totem picker.** The old standalone *Searing Totem* toggle is retired — it was a second system fighting the fire-totem selector over the same slot. Damage specs now default their fire pick to Searing (Enhancement, Elemental), so nothing is lost, and the double-drop risk is gone. New per-spec totem defaults: Enhancement (Windfury / Searing / Strength / Mana Spring), Elemental (Grace of Air / Searing / Mana Spring), Tank (Stoneskin / Grounding / Mana Spring).
- **Cast-event-driven re-drop timing.** Totem upkeep now listens for SuperWoW's `UNIT_CASTEVENT`, which fires the instant a cast registers, and timestamps each element slot from the actual cast rather than assuming Queue succeeded. A manual re-drop, or Mana Tide bumping the water slot, now correctly resets that slot's clock. Falls back cleanly on clients without the event.
- **Warrior: reliable auto-attack.** `EnsureAutoAttack` required the *Attack* ability to be placed on an action bar to detect and toggle it — if it wasn't, no swing ever started. It now falls back to starting the swing directly when no Attack slot is found, so melee always engages without a manual `/startattack`.
- **Warrior: Charge and Rend leveling toggles (both off by default).** *Charge* opens a pull from range in Battle Stance; the client blocks it once you're in combat, so it only ever fires as the initial gap-close, never mid-fight. *Rend* keeps its bleed up in Battle or Defensive Stance and steps aside during *Execute* so rage funnels there instead. Both are registered `/ar spell` aliases (`charge`, `rend`).

All Lua files pass the balance check; the define-before-use ordering audit is clean.

---

## v0.13.11b — Single-row layout across every class, uniform sliders, aligned dropdowns

**Layout.** The concept's single-row anatomy — piloted on Druid in 0.13.10b — is now the layout for **all nine class panels**. Every setting sits on one line: toggle, label, an optional muted sub-label, a right-aligned slider, and a fixed right-hand value column, with hairline separators between rows. Confirmed in-game on the 1.18.1 client.

- **All classes converted.** Druid (all forms + Defense), Rogue, Warrior, Hunter, Mage, Paladin, Priest, Warlock, and Shaman now use the shared row primitive. Toggle-plus-threshold pairs that used to span two rows (Innervate + its mana %, Mend Pet + its HP %, Life Tap, Shadowburn, Mana Tide, and many more) are single rows. Spec/seal/totem pickers stay full-width.
- **Uniform slider column.** Every slider is the same width and right-anchored, so they line up in one clean vertical rail with the value column fixed at the far right — matching the concept.
- **Unlearned spells hide their slider.** When a spell isn't trained, its row hides the (unusable) slider and gives the full width to the "(not learned)" label, so long names like *Lesser Healing Wave* read in full instead of clipping. The slider returns automatically once the spell is learned.
- **Aligned, centered dropdowns.** Dropdown boxes (Sting, Shield, Shock, Seals, Strike mode, the four Shaman totems, etc.) now share a fixed label column so every box lines up to the same left edge, with centered box text and a consistent ink label colour (previously some inherited a stray gold).
- Sub-labels trimmed only where a slider genuinely left no room; the detail lives in the tooltip.

**Note on Shaman totems.** The four totem selectors remain on the Restoration tab, because only the healing rotation currently maintains a full totem set (damage specs drop Searing Totem via its own toggle). Extending totem upkeep to Enhancement / Elemental / Tank is a rotation feature planned for a future update.

All Lua files pass the balance check; the define-before-use ordering audit is clean.

---

## v0.13.10b — UI polish: concept-accurate header, rounded art, and the single-row layout (Druid pilot)

**Feature.** A close pass to bring the window in line with the design concept — the header, control art, and a new single-row settings layout. Confirmed in-game on the 1.18.1 client.

- **Rebuilt header.** An "AR" sigil square in the class colour (with a top-to-bottom accent fade), an uppercase **AUTOROTA** wordmark, and a version chip; a hairline closes the row. The profile sits on its own panel-tinted band as a **content-width pill** (it hugs the profile name instead of a fixed-width box) with a live dot, and New / Rename / Delete are right-aligned ghosts beside it.
- **Rounded everything.** Buttons, dropdowns, the profile pill, and the ?/× became rounded via new bundled art (`Btn.tga`, `Pill.tga`, `RoundSq.tga`), and section cards got true rounded corners (`Card.tga`, nine-sliced).
- **Single-row settings layout.** A new row primitive puts each setting on one line — toggle, label, inline muted sub-label, right-aligned slider, and a fixed right-hand value column, with hairline separators between rows. **Piloted on the Druid Restoration + Downtime cards**; the remaining classes keep the previous two-column layout for now and will convert in follow-up updates.
- **Footer.** A round state dot with neutral text (`● Profile valid`), and Save/Activate sized to the concept's compact proportions.
- **Crisper text.** The skin now zeroes the template drop-shadow on every FontString it styles, so small bold text renders cleanly.

**Fixes.**
- **Card corners** were reading square because the texture's baked corner radius was far smaller than the nine-slice sample window — the texture was regenerated with the radius filling the corner, and the slice size matched to it.
- **Scrollbar thumb overhang** — the 1.12 slider uses a fixed-size thumb, so on short scroll ranges it hung past the ends of the rail. The thumb is now sized proportionally to the visible fraction each time the body reflows, clamped so it always sits within the track.

New bundled art: `Icons\Btn.tga`, `Icons\Pill.tga`, `Icons\RoundSq.tga`, `Icons\Card.tga` (32-bit uncompressed, power-of-two). A **full relog** is needed on first install so the client picks up the new files. All Lua files pass the balance check.

---

## v0.13.9b — Paladin: Damage | Healer tabs + the melee-holy weave

**Feature.** The Paladin joins the tab rail with a **Damage | Healer** pair, and heal mode is aligned to Turtle's melee-holy playstyle. Confirmed in-game on the 1.18.1 client.

- **Damage | Healer tabs.** The rail binds to the rotation's one real branch (heal mode) — Retribution and Protection both live on Damage, differing by the seals/strikes below, so the spec names live in the tab **tooltips** rather than over-promising labels. Seals and Spells show only on Damage; the Healing card only on Healer; Mana and HP management stay shared. The old "Heal mode" checkbox is gone — the tab (or `/ar heal`) is the switch. Under the hood the tab framework gained optional **encode/decode** hooks so a rail can bind a boolean field; the four string rails are untouched.
- **Blessed Strikes engine.** With the talent (auto-detected by exact name; 100% reset at 5/5), **Crusader Strike is woven between heals to reload Holy Shock**, keeping the emergency instant permanently available — even while people are hurt, but *never* while anyone is under the Holy Shock line: a critical member always gets the heal first.
- **Holy Strike downtime weave.** When nobody needs a direct heal, the rotation strikes with the heal policy — Holy Strike first (its splash heal tops the melee group, doubled by Blessed Strikes), Crusader Strike as fallback.
- **Safety gate.** Both weaves require an attackable target in melee range, a free GCD, the strike cooldown ready, and mana above a new **weave mana floor** (default 40%), so weaving can never starve a heal. New Healing-card controls: a *Weave strikes (melee holy)* toggle (default on) and the mana-floor slider.
- Priorities now match the Turtle melee-holy list end to end: Seal of Wisdom upkeep + judgement (existing seal/mana config), Holy Strike weave, Crusader Strike → Holy Shock reset, downranked Flash of Light / Holy Light for spikes.

All Lua files pass the balance check.

---

## v0.13.8b — UI skin, Phase 3: spec tabs + compact header

**Feature.** The final structural piece of the redesign — the spec dropdown becomes a **tab rail**, and only the active spec's sections exist on screen. The window now matches the concept end to end. Confirmed in-game on the 1.18.1 client.

- **Spec tabs.** Classes that branch on a spec field get a class-accented tab rail (active tab underlined in the class colour, muted labels otherwise, hover feedback, per-tab tooltips). Clicking a tab writes the same profile field the old dropdown did, so rotations and saved profiles are unchanged.
  - **Druid:** Feral (Cat) / Feral (Bear) / Balance / Restoration.
  - **Shaman:** Elemental / Enhance (DPS) / Enhance (Tank) / Restoration. (DPS and Tank share config but run different rotations, so they stay separate tabs.)
  - **Hunter:** Auto / Ranged / Melee — Auto shows both the Ranged and Melee sections, since it chooses by distance at cast time.
  - **Mage:** Frost / Fire / Arcane.
  - **Paladin and Warrior keep no rail** — Paladin has no spec field (it is seal/toggle driven), and Warrior's dropdown selects a home *stance*, not a spec.
- **Only the active spec is shown.** Each config section is now its own container; switching tabs hides the off-spec sections and reflows the rest, so the window is far shorter and most tabs need no scrolling. Sections that apply to every spec (Druid's Defense, Shaman's Shield/Casting/Cooldowns, Hunter's Targeting/Aspect/Pet, Mage's General) stay visible on all tabs.
- **Compact header + footer.** The subtitle and "Profile being edited" label are gone; the profile sits as a pill with a **green dot when it is the active profile**, New/Rename/Delete right-aligned beside it. Validity moved to the footer-left, with **Save (ghost) + Activate (accent)** at the footer-right; the redundant Close button was removed (the top-right **×** closes). This buys back roughly two rows of body height.
- **`?` button** restyled to match the flat **×** — a ghost square with an ink glyph — replacing the old gold icon. Frame strata raised to HIGH so world nameplates no longer bleed through the window.

Classes without a rail flow through the same new container code with untagged sections, so they render as before. All Lua files pass the balance check.

---

## v0.13.7b — UI skin, Phase 2b: toggle switches, slider art, flat close buttons

**Feature.** The final slice of the config-window redesign — with this, the window contains **no stock Blizzard art**. Confirmed in-game on the 1.18.1 client.

- **Toggle switches** replace the gold checkboxes: off is a dark pill with the knob left, on is a **class-coloured** pill with a dark knob right. The ON art ships pure white in `Icons\ToggleOn.tga` and is tinted with the class colour at runtime, so one texture serves all nine classes; hover adds a faint additive glow, and the disabled states keep the pill art (a locked-on toggle shows a muted accent pill instead of the template's old grey checkmark).
- **Sliders** lose the grooved template track: a slim dark rail, a **class-accent fill that tracks the thumb**, and a round ink-coloured thumb (`Icons\SliderThumb.tga`).
- **Close buttons** (main window and help panel) are flat ghost squares with an ink "×" glyph and a faint red hover tint.
- Label columns re-clamped for the wider toggles, and the window's frame strata raised to HIGH so world nameplates no longer bleed through it.
- **Fix (caught by in-game screenshot).** The 1.12 client's CheckButton silently ignores file paths on `SetCheckedTexture` and the disabled variants — only `SetNormalTexture` takes a path — which left the template's checkmark stretched over checked toggles. The skin now grabs the template's texture **objects** and repoints their files directly.

New bundled art: `Icons\ToggleOff.tga`, `Icons\ToggleOn.tga`, `Icons\SliderThumb.tga` (32-bit uncompressed, power-of-two). A **full relog** is needed on first install so the client picks up the new files. All Lua files pass the balance check.

---

## v0.13.6b — UI skin, Phase 2a: flat buttons, dropdowns, and scrollbar

**Feature.** The first control-art slice of the redesign — and it needed **no texture files**: buttons, dropdowns, and the scrollbar are re-skinned entirely in code. Confirmed in-game on the 1.18.1 client.

- **Buttons.** The red-gold template art is gone. **Activate** (and the dialog's confirm) is the one accent-filled primary, in the class colour with text that auto-picks dark or light by the accent's luminance; New / Rename / Delete / Save / Close / Cancel are quiet ghosts (hairline border, faint fill, ink text). All buttons get hover feedback, a 1px press-nudge, and skin-aware Enable/Disable (dimmed fill + grey text).
- **Dropdowns.** The same ghost treatment for every picker; selection-text colouring stays with SetDropdown, so state colours like the red "(not learned)" on totem picks still work.
- **Scrollbar.** The template's floating knob and arrow buttons are gone — mousewheel and thumb-drag cover scrolling — replaced by a slim dark groove and a flat 6px thumb.
- **Hover chaining.** A dropdown in a config row stacks three hover behaviours (its own feedback, the row highlight, the tooltip); wireHover now chains like Tip so all three fire together.
- **Fix.** A define-before-use crash caught in testing (`classColor` was defined below its new caller, so the window failed to open) — the class-colour table now sits above the button skinner, and an ordering audit over every file-local confirms no other case exists.

Stock art remaining for **Phase 2b**: checkboxes (toggle switches), slider rails and thumbs, and the close button. All Lua files pass the balance check.

---

## v0.13.5b — UI skin, Phase 1: flat dark surfaces, bundled fonts, class accent

**Feature.** The first phase of the config-window redesign, applied through the shared framework so **all nine class panels re-skin at once**. Confirmed in-game on the 1.18.1 client.

- **Bundled typeface.** The window now renders in **PT Sans Narrow** (regular + bold), shipped in a new `Fonts\` folder with its OFL license. Every framework-created FontString picks the face up by role; if the folder is missing, everything falls back to the client's default font so text can never vanish. Requires a full relog (not `/reload`) on first install, like all new bundled files.
- **Flat dark surfaces.** The parchment dialog art is gone: near-black window with a crisp 1px hairline border, and each config section now sits on its own **card** — a flat panel with hairline edges that replaces the old divider lines. Cards fade with their section when a block dims off-spec.
- **Class accent.** A 2px class-colour strip runs along the window's top edge, matching the class name in the title — the window automatically wears Paladin pink, Druid orange, Shaman blue.
- **Skinned everywhere.** Section headers became small uppercase eyebrows; dropdown popups, the confirm/input dialog, the help panel, and the minimap options panel all share the dark surface; the row hover was retuned for the cards.
- **Fix.** Long checkbox labels (e.g. "Hammer of Wrath (not learned)") no longer run across a card's right edge — labels are clamped to their column and clip inside the card.

Stock Blizzard art intentionally remains on checkboxes, sliders, buttons, and the scrollbar — that is **Phase 2**, the custom control-art pass. All Lua files pass the balance check.

---

## v0.13.4b — Full heal-config panels for the Druid & Shaman healers (plus UI polish)

**Feature.** The **Restoration Druid** and **Restoration Shaman** now have **complete config panels**, matching every other spec — every knob the heal rotation reads is a slider, toggle, or dropdown, so the healers are no longer command-line-plus-defaults. This closes the last big configurability gap.

- **Restoration Druid — all controls.** A master **Heal threshold** and **Heal power** (your `+healing` for downranks), then on/off toggles with their thresholds for **Innervate** (mana %), **Nature's Swiftness** (HP %), **Swiftmend** (HP %), and **Regrowth** (HP %); a **Wild Growth** toggle + ally-count, the **damage-weave** toggle + mana floor, and **Rejuvenation** / **Lifebloom** toggles.
- **Restoration Shaman — all controls.** The same **Heal threshold** + **Heal power**, then toggles with thresholds for **Mana Tide** (mana %), **Nature's Swiftness** (HP %), **Lesser Healing Wave** (HP %), and **Chain Heal** (ally-count); the **damage-weave** toggle + mana floor; a **Maintain totems** master toggle; and the four **totem pickers** (Water / Earth / Fire / Air) populated from the real totem tables.
- **Honest about what will actually fire.** Checkboxes reflect the *rotation's* defaults, not just the stored value — abilities that default on show checked even on a profile that never saved them. Each slider and totem picker greys out unless you are on-spec, its toggle is on, **and** the spell is learned (including the dual-named **Nature's / Ancestral Swiftness**, and a red "(not learned)" on any totem you have picked but cannot cast yet).
- **Off-spec stays out of the way.** The whole Restoration section dims and locks unless the profile's spec is Restoration (Druid form = Restoration, Shaman mode = Restoration), exactly as before — the controls just fill it in now.

**UI polish (all nine panels).** Two shared touches that ride along on every class window:

- **Engraved section dividers.** The flat grey separators are now a soft two-tone hairline with a thin shadow beneath, for a bit of depth.
- **Row hover.** Moving over a config control lights a faint full-width highlight on its row. It is a background tint that never takes mouse input (so it can never block a click), and tooltips now chain onto it rather than replacing it.

**Fix.** `/ar new <name>` without a template argument now correctly creates the profile from the starter template — the command dispatcher was passing an empty string instead of nothing, which failed the template lookup with "unknown template ''". (The UI's New button was unaffected.)

The per-rank heal values and thresholds remain the vanilla-baseline approximations from the earlier resto work — the panels make them tunable; whether they *feel* right is still an in-game call (the rank tables live at the top of `Class_Druid.lua` / `Class_Shaman.lua`). All 21 Lua files pass the balance check.

---

## v0.13.3b — Custom help-button icon + an Icons folder for bundled art

**Change.** The config window's "?" help button now uses a **bundled custom icon** instead of stock UI art — a gold "?" that reads cleanly beside the close button. Custom textures now live in the addon's new **`Icons\`** subfolder.

- **`Icons\Help.tga`** — the help button pulls its texture from `Interface\AddOns\AutoRota\Icons\Help`. The file is **32×32** because the 1.12 client only loads power-of-two textures (the original art was resized to fit).
- **Convention going forward.** Any future custom icon drops into `Icons\` and is referenced as `Interface\AddOns\AutoRota\Icons\<Name>` (no file extension). No `.toc` entry is needed — textures load by path at runtime, so only `.lua`/`.xml` files ever go in the `.toc`.
- **Install note.** The `Icons\` folder ships inside the `AutoRota` addon folder and must travel with it; keep it intact when copying files by hand.

UI/asset only. All 21 Lua files pass the balance check.

---

## v0.13.2b — Weave toggle (and Restoration spec) in the config panels

**Feature.** The Restoration Druid and Restoration Shaman are now selectable from the config window, and the **damage-weave toggle** has a checkbox there — no command required to set it up.

- **Spec in the dropdown.** "Restoration (Heal)" joins the Druid's **Preferred form** dropdown and "Restoration" joins the Shaman's **Spec** dropdown, so you can switch into the healer from the panel instead of `/ar form resto` / `/ar mode resto`.
- **Weave checkbox.** A new **Restoration (Heal)** section on each panel carries a "Weave damage between heals" checkbox bound to the same setting as `/ar weave` — flip it either way and the two stay in sync. It is dimmed and locked unless the profile's spec is Restoration, matching how the Druid's Powershift greys out outside Shred style.
- **Cleaner focus.** Selecting Restoration on the Shaman now fades the Melee-strikes section too (a healer does not melee), as Elemental already did.

The rest of the heal tuning (heal threshold, Nature's Swiftness %, Swiftmend/Regrowth thresholds, the weave mana-floor, totem pickers) is still command/default-only — the full heal-config panels are still ahead. UI-only patch. All 21 Lua files pass the balance check.

---

## v0.13.1b — Optional damage-weaving for the Druid & Shaman healers

**Feature.** The Restoration Druid and Restoration Shaman can now **weave damage between heals**, matching how the Priest and Paladin heal modes already behave. It is a per-profile toggle (`/ar weave on|off`, default **off**), so the player decides whether downtime goes to DPS or to conserving mana.

- **Only in true downtime.** The weave fires only when **nobody is below the heal threshold** — healing always comes first. On the Shaman it also yields to Water Shield and totem upkeep, so those are never skipped for a nuke.
- **Enemy-targeted + mana-gated.** It casts only when you have an attackable enemy targeted and your mana is above a floor (`weaveManaFloor`, default 40%), so it can never starve your heals. With no enemy targeted it stays pure-heal.
- **Per class:** the Druid weaves **Moonfire** (kept up as a DoT) then **Wrath**; the Shaman weaves **Lightning Bolt**. Both are `KnowsSpell`-gated.
- **Toggle anywhere:** `/ar weave on`, `off`, or bare to flip it. The config panels will expose it as a checkbox plus a mana-floor slider when they land.

Patch bump. All 21 Lua files pass the balance check.

---

## v0.13.0b — Restoration Shaman: the last healer spec

**Feature.** The Shaman gains a fourth mode alongside Enhancement, Elemental, and Tank — a **Restoration** group healer on the same triage engine as the Priest, Paladin, and Druid healers. With it, **every class that can heal now has a one-button healing spec.** Like the others it runs **with no enemy targeted** and heals through SuperWoW's unit-argument cast, so your current target is never dropped.

- **Worst-hurt triage + downranking.** Each press finds the most-hurt *reachable* group member and **downranks Healing Wave** to the size of the deficit, counting its own in-flight heal so it never double-stacks on one unit. Shaman healing is all direct — no HoTs — so this is the leanest of the four heal engines.
- **Toolkit by priority.** *Mana Tide Totem* when low on mana → **Nature's Swiftness-equivalent → instant max Healing Wave** for a target in trouble → **Lesser Healing Wave** for a fast single-target emergency (this wins over AoE) → *Chain Heal* when several are hurt → downranked *Healing Wave* as the fill. Each step is toggle- or threshold-gated.
- **Water Shield + totems on autopilot.** Water Shield is kept up (reusing the shield system — the template sets `shield = "water"`), and totems are refreshed on a per-element timer during lulls so upkeep never steals a heal GCD: a **Mana Spring** water staple by default, with earth/fire/air pickers wired and off.
- **Selectable today.** Pick it with `/ar mode resto` (or `/ar new <name> restoration` for a ready-made profile). A dedicated **config panel** for the heal toggles, sliders, and totem pickers is the next step, alongside the Druid's; until then the template defaults are sensible and the thresholds live in `Class_Shaman.lua`.

> **Heal-tuning note:** As with the Druid, the Healing Wave / Lesser Healing Wave / Chain Heal rank values are vanilla baselines in one block at the top of the Restoration section in `Class_Shaman.lua`. A few names couldn't be confirmed from outside the game and have safe fallbacks: the **NS-equivalent** spell (tries `Nature's Swiftness`, then `Ancestral Swiftness`), **Mana Tide Totem**, and the **totem names** in the picker tables — confirm with `/ar debug` / `/ar talents` if a step isn't firing. Totem re-drop is timer-based (55s water / 110s others — adjust if Turtle durations differ), `HealMods` is ~neutral since the resto tree has no flat +healing% talent (gear `+healing` is the lever), and reach uses the ~28yd proxy.

New spec — minor version bump. All 21 Lua files pass the balance check.

---

## v0.12.0b — Restoration Druid: a group-healer spec in caster form

**Feature.** The Druid gains a fourth playstyle alongside Cat, Bear, and Balance — a **Restoration** spec that heals the party/raid, built on the same triage engine as the Priest and Paladin healers. Like them it runs **with no enemy targeted**, so it works at range, and it heals through SuperWoW's unit-argument cast so your current target is never dropped.

- **Worst-hurt triage + downranking.** Each press finds the most-hurt *reachable* group member and **downranks Healing Touch** to the size of the deficit for mana efficiency, counting its own in-flight heal so it never double-stacks on one unit. The `+healing` bonus is a profile value, factored through *Gift of Nature*.
- **Full Resto toolkit, by priority.** *Innervate* yourself when low on mana → **Nature's Swiftness → instant max Healing Touch** for a target in real trouble → *Swiftmend* for a no-cast top-up when your Rejuv/Regrowth is already on the unit → *Wild Growth* when several are hurt (off by default) → *Regrowth* for a big single-target burst → *Rejuvenation* kept rolling at its best affordable rank → *Lifebloom* (off by default) → downranked *Healing Touch* as the fill. Each step is toggle- or threshold-gated.
- **Caster-form healing.** Heals only cast in caster form, so the rotation drops any active shapeshift first. **Tree of Life auto-shift is intentionally left off** until its 1.18.1 cast rules are confirmed — it heals in caster form for now.
- **Selectable today.** Pick it with `/ar form resto` (or `/ar new <name> tree` for a ready-made profile from the Restoration template). A dedicated **config panel** for the heal toggles and sliders is the next step; until then the template defaults are sensible and the thresholds are adjustable in `Class_Druid.lua`.

> **Heal-tuning note:** The per-rank Healing Touch / Regrowth / Rejuvenation values are vanilla baselines and live in one block at the top of the Restoration section in `Class_Druid.lua` — the downranker only needs the ranks ordered roughly right, but adjust them there if a pick over- or under-heals on 1.18.1. HoT upkeep rides a per-unit reapply timer rather than a buff read (raid buff readback is unreliable on this client), and healing range uses the ~28yd interact-distance proxy. Worth a quick in-party sanity check.

New spec — minor version bump. All 21 Lua files pass the balance check.

---

## v0.11.2b — Hunter Serpent Sting now fires and stays up

**Fix.** Serpent Sting was unreliable-to-nonexistent in the ranged rotation — the Hunter would apply Hunter's Mark, fire Arcane Shot and Auto Shot, and skip the sting, only landing it at random. Several stacked causes, now all addressed:

- **Cast path.** The sting was the only ranged ability dispatched through the instant `CastSpellByName`; every other shot uses the Nampower shot queue. Nampower silently drops an instant ranged cast while a global cooldown is up, so the sting never went out. It now routes through the same `QueueSpellByName` path as Steady / Multi / Arcane / Aimed.
- **Queue eviction.** Nampower's queue holds one pending shot, so the moment the rotation fell through to Steady/Arcane on the next press it overwrote the still-pending sting before it fired — which is exactly what made it "occasionally work." After the sting is queued, the lower-priority shots now hold for about one shot-cycle so they can't evict it; Auto Shot keeps firing through the hold.
- **False immunity.** The "cast but never landed → immune" guard was branding ordinary mobs (a level-6 Beast) poison-immune, because the Serpent Sting debuff can't be read back on this client. That guess now only applies to **Undead**, the one type where some members are genuinely immune and aren't already hard-blocked (Mechanical / Elemental stay deterministically blocked).
- **Priority + HP gate.** Serpent Sting is now the top of the GCD priority so the DoT is kept up, and the old 30%-HP gate is gone — it maintains at range for the whole fight instead of cutting out on a low target. The instant Arcane Shot finisher below 30% stays as its own step, and the sting is still range-only (skipped in melee).

**Note.** Upkeep currently rides the sting's own duration as a blind reapply timer, because the Serpent Sting debuff doesn't resolve to a readable name on this client (Hunter's Mark does). It stays up correctly; a later pass can add icon-texture detection so the addon reads the live DoT and the trace shows it.

Patch bump. All 21 Lua files pass the balance check.

---

## v0.11.1b — Active-spec focus: the spec you're not playing dims out (Mage / Hunter / Shaman)

**Feature.** The mode-adaptive classes now fade and lock the controls for the spec or stance you are *not* currently in, so the panel highlights your active rotation and greys the rest. This is the **active-mode dimming** that was planned next; the collapsible-sections idea was prototyped alongside it and set aside, so this is dimming only — nothing folds, moves, or re-flows.

- **Mage.** Pick a spec and the other two blocks dim — Frost greys Fire and Arcane, and so on. The shared **General** block (wand, Evocation, Frost Nova, the sliders) always stays lit.
- **Hunter.** Ranged and Melee fade by **Mode**: Ranged play greys the Melee block, Melee play greys the Ranged Shots block, and **Auto** (which picks ranged vs melee by distance) keeps both lit. Targeting, Aspect, Pet, and Cooldowns are shared and never dim.
- **Shaman.** The melee strikes (Stormstrike, Lightning Strike) grey out in **Elemental**, where you are casting; **Enhancement** and **Tank** are both melee, so they stay lit. To do that cleanly, the old "Abilities" block was split into **Melee strikes** and **Casting & totems** (Lightning Bolt + Searing Totem, used in every mode).
- A dimmed block is also **locked** — to edit a spec's settings, switch to it first. The `(not learned)` red-out for untrained abilities still shows through underneath.

**Fix.** The configuration window could throw `attempt to call method 'SetVerticalScroll' (a nil value)` when opened. The scrollbar's `UIPanelScrollBarTemplate` default `OnValueChanged` was firing against the window (its parent) instead of the scroll frame during the initial `SetValue(0)`; our own handler is now attached *before* that call, with a nil-guard, so the template's handler never runs against the wrong frame.

Dimming is purely additive: each section header tracks the controls placed under it, and a single `SetDimmed` fades the group and blocks its mouse — no collapsible/fold machinery, no re-flow, so the layout is byte-for-byte where it was. Patch bump. All 21 Lua files pass the balance check.

---

## v0.11.0b — Config UI overhaul: scrolling, compact window, and an auto-layout engine (all nine classes)

**Feature.** The configuration window is rebuilt on a new layout system. It is now a compact, fixed-size panel with a **scrollbar** instead of a tall window sized per class — the same controls, the same bindings, and the same saved profiles as before, just easier to read and to fit on screen.

- **Compact, scrolling window.** Fixed at 480px tall (down from the old per-class 628–680px). The class body lives in a scroll frame you can pan with the **mouse wheel**, the **scrollbar thumb**, or its **arrow buttons**, and the scrollbar hides itself when a panel already fits.
- **Auto-flow layout engine.** The per-class bodies no longer hand-place every checkbox at an absolute pixel offset, and no longer hard-code a `uiHeight`. A small cursor-based layout API — `Header`, `Check` / `CheckPair`, `Slider` / `SliderPair`, `Dropdown`, `DropdownCheck` — flows controls down the panel and computes the content height itself, so spacing is consistent and the scroll range is always right. Adding or reordering a control is now a one-line change.
- **Cleaner presentation.** Section titles are gold headers with automatic dividers between them, and long control labels were shortened — the full explanation moved into the hover tooltip (every control has one).
- **All nine classes migrated.** Prototyped on the Mage, then rolled out to Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Druid, and Warlock. Each class behaves exactly as before — only the window's layout and size changed — and the densest panels (Hunter, Paladin, Priest) benefit the most.
- **Dropdown fix.** Dropdown pop-out lists are now parented to the window rather than their button, so the scroll frame can never clip them.

All within the 1.12 client (a real `ScrollFrame` + `UIPanelScrollBarTemplate`, mouse wheel via `OnMouseWheel`). The opt-in flag `useScrollLayout` is now set on all nine class UIs; the older absolute-offset path remains in the shell as an unused fallback. Minor version bump for a significant UI feature. All 21 Lua files pass the balance check.

*Next (Phase 2): collapsible sections and active-mode dimming, to tame the densest panels further.*

---

## v0.10.1b — Hunter: stop casting Serpent Sting on poison-immune mobs

**Fix.** Serpent / Scorpid / Viper Sting are Poison-school effects, so they never land on poison-immune targets — but the rotation was re-applying the sting on a wasted "immune" cast every cycle (once the ~15s upkeep throttle expired) on Mechanicals, Elementals, and the specific immune Undead / bosses. Two layers now prevent that:

- **By creature type (deterministic):** *Mechanical* and *Elemental* are immune to Poison on 1.12, so the sting is skipped outright via `UnitCreatureType` — **zero wasted casts** on golems, clockwork mobs, all fire/water/earth/air elementals, etc. *Undead is **not** blanket-blocked* — only specific undead are poison-immune, so type-blocking the whole type would wrongly skip the many valid undead targets.
- **Learned (per target, per combat):** if the sting is cast but never shows up on the target, that mob is marked immune and the sting is not re-cast. This automatically catches the immune *Undead* and immune bosses (e.g. Baron Aquanis in Blackfathom Deeps) after a single cast. The learned list is cleared when you leave combat, so it never goes stale.

`/ar trace` now shows `sting=Serpent Sting(immune)` when the current target is being skipped, so you can confirm it's working. *(Note: the creature-type block keys off the English type names, matching the addon's English-locale spell strings; on a localized client the learn layer still covers it after one cast.)*

---

## v0.10.0b — New class: Mage (Frost / Fire / Arcane) — all nine classes complete 🎉

The ninth and final class lands, so AutoRota now covers every class in the game. The Mage is mode-adaptive (like the Shaman and Hunter) and runs from level 1 to raiding, switching specs live with `/ar mode frost|fire|arcane`.

**Three specs, one button:**
- **Frost** — the kiting and Turtle *Icicles* spec, and the best leveler. Frostbolt nuke, *Frost Nova* root when a mob reaches melee, *Cone of Cold* close-range slow, *Ice Barrier* upkeep, and *Icicles* cast whenever its cooldown is up. The Turtle freeze-reset is handled implicitly: *Frostbite* / *Flash Freeze* keep resetting the Icicles cooldown, so the engine fires it in the empowered window automatically (`Frost Nova ➔ Icicles ➔ Frostbolt` on bosses).
- **Fire** — *Combustion* on cooldown, *Pyroblast* as a pull-only opener (gated to a near-full-health target so it is never a 6s cast mid-fight), *Scorch* to build and maintain the *Fire Vulnerability* debuff to a configurable stack count, *Fire Blast* on cooldown, then *Fireball*. A per-target Scorch throttle means Fireball still fills if the debuff cannot be read.
- **Arcane** — *Arcane Rupture* upkeep on the target, *Arcane Power* burst, *Arcane Surge* while **not** hasted (skipped under Arcane Power / MQG, whose haste does not scale its GCD), and *Arcane Missiles* as the filler.

**Leveling "nuke then wand":** below a target-health threshold (the golden rule, default 40%) or below a mana floor, the rotation finishes the mob with the **wand** to conserve mana. A **Use wand** toggle and the missing-wand auto-fallback mirror the Priest; set wand-finish to 0% (the `frost`/`fire`/`arcane` presets do) for pure caster / raid play. Quick knob: `/ar wandhp <0-100>`.

**AoE mode** (`/ar aoe`): kite-AoE — *Frost Nova* freeze, *Cone of Cold* snare, *Icicles*, then *Arcane Explosion*. Ground-targeted AoE (*Blizzard*, *Flamestrike*) is intentionally **not** auto-cast, since it needs a cursor click a one-button rotation cannot place.

**Everything KnowsSpell-gated** so a level 1 mage (Fireball, then Frostbolt at ~4) plays correctly and each ability switches itself on as it is trained; the profile is never flagged for a not-yet-learned spell. Channels (*Arcane Missiles*, *Icicles*, *Blizzard*, *Evocation*) are protected by a channel watcher, and *Evocation* fires when low on mana, in combat, and the target is not about to die.

All Turtle custom spells were confirmed by exact name against the client spell DB (*Icicles*, *Arcane Rupture*, *Arcane Surge*, *Flash Freeze*, *Fire Vulnerability*). Ships as two files (`Class_Mage.lua`, `Class_Mage_UI.lua`); all 21 Lua files pass the balance check.

---

## v0.9.1b — Priest wand controls: "Use wand" toggle + wandless fallback

Two refinements to the Priest's 5-second-rule filler.

- **"Use wand for mana regen" checkbox** (next to the Filler dropdown): a master switch for wand-weaving. On (default) keeps the existing behaviour — the filler drops to the wand below the mana floor to let mana regenerate. Off makes the priest **never wand**: it keeps casting its filler (and can run dry, by choice). Cleaner than the old filler-dropdown + mana-floor-0 workaround.
- **Wandless fallback (no more empty presses):** the wand is now used only when it is both enabled *and* a wand is actually equipped (the new `WandUsable` check). When it is not, the rotation casts a damage spell instead — **Mind Flay** if known (so it still fills in **Shadowform**, where Smite is blocked), otherwise **Smite** out of Shadowform. This closes the gap where a wandless priest in Shadowform with the filler left on *Wand* did nothing on the filler press.
- **UI feedback:** the checkbox label greys to *"Use wand (none)"* when no wand is equipped, so it is obvious the wand path is inactive and the spell fallback is carrying the filler.
- The `starter` and `shadow` templates seed `useWand = true`, and existing profiles default to on via `NormalizeProfile`. The now-redundant `DpsFiller` helper was folded into the filler tail. README updated; all 19 Lua files pass the balance check.

---

## v0.9.0b — New class: Priest (Shadow / leveling + Disc/Holy healing)

The ninth class module. One toggle switches a priest between a **shadow/leveling damage** rotation and a **Discipline/Holy group-healing** engine. Built against in-game-verified spell names and talent trees (the `/ar talents` dump plus a full SuperWoW spell-DB extraction), so abilities switch themselves on through `KnowsSpell` as they are trained and one profile scales from 1 to 60.

### 🌟 Shadow / leveling (DPS mode)
- **The 5-second-rule loop:** *Mind Blast* on cooldown, *Shadow Word: Pain* + (Undead) *Devouring Plague* upkeep, *Holy Fire* out of Shadowform, then the **wand carries the filler while mana regenerates**. The filler (`/ar filler wand|flay|smite`) drops to the wand below a configurable mana floor so the priest never casts itself dry — AutoRota *acts* on the five-second rule rather than drawing a HUD timer.
- **Spirit Tap finisher:** under a configurable target-health %, bursts *Mind Blast* → *Smite* to secure the killing blow (and the experience that feeds Spirit Tap).
- **Shadowform** (optional, held): while active, every Holy cast (*Smite*, *Holy Fire*, heals) is auto-skipped.
- **Raid debuff control:** *Shadow Word: Pain* is a toggle, so it can be dropped in raids to respect debuff-slot limits; *Mind Blast* and channelled *Mind Flay* then carry the damage.
- **Mitigation:** *Power Word: Shield* on melee contact or below half health, **gated on *Weakened Soul*** so it never wastes a cast.

### ⛑️ Discipline / Holy (heal mode)
- **Responsive downranking triage** (self-contained, mirrors the paladin heal engine): the most-hurt *reachable* party/raid member is healed with the **smallest rank that covers the deficit**. The `+healing` bonus is read from gear (`/ar healpower <n>` to override) and *Spiritual Healing* is factored in.
- **Emergency Flash Heal:** reserved for a target near death (`/ar flashat <%>`) so it does not drain the pool on routine damage; *Greater Heal* covers big deficits, *Heal* the efficient sustained healing.
- **No over-bubbling:** *Renew* and *Power Word: Shield* maintain a mildly hurt unit, both throttle / *Weakened-Soul*-gated.
- **AoE:** *Prayer of Healing* when several members are hurt, **fronted by *Inner Focus*** (when ready) to negate its mana cost.
- **Offensive weave & Lightwell:** between heals, optional *Smite* / *Holy Fire* support (for *Enlighten*-style talents) and *Lightwell* placement out of combat. Heal mode runs with no attackable target, so it works at range (the core's `RunsWithoutTarget` hook).

### Wiring & docs
- Registered in the `.toc`; templates seeded as `starter` (leveling/shadow DPS), `shadow` (endgame), and `heal` (Disc/Holy). Channel-clip protection for *Mind Flay* and a combat-state flag (1.12 has no `UnitAffectingCombat`) are included. New commands: `/ar heal`, `/ar healat`, `/ar flashat`, `/ar filler`, `/ar healpower`. README gains a Priest section; all 19 Lua files pass the balance check.

### ⚠️ Caveats
- Heal-value tables are **tuned approximations** (top of `Class_Priest.lua`) — adjust if downranking over- or under-heals. *Shadow Weaving* / proc behaviour and the exact *Enlighten* mechanic are best-effort (confirm with `/ar talents` / `/ar debug`). Healing and the no-target-drop heal cast rely on SuperWoW's unit-arg casting. Multi-target Shadow spreads DoTs as you tab between mobs; the engine is single-target by design and does not tab for you.

---

## v0.8.9b — Branch merge (step 4): Paladin healing support

Merged the modified branch's healing system into the Paladin. The branch's ret/prot base was an older lineage (it had even lost the verified `Vengeful/Righteous Strikes` talent names and the strikeMode downranking), so the current ret/prot was kept untouched and only the self-contained heal engine was grafted on.

### ✨ Paladin heal mode
- **Heal mode** (`/ar heal on|off`, or the panel): the Paladin heals the party/raid and DPSes between heals. Runs even with no attackable target (via the core's `RunsWithoutTarget` hook from step 1), so it works at range.
- **Smart target + downranking:** picks the most-hurt *reachable* group member (raid- and party-aware), counts its own in-flight heal so it never double-stacks a heal on one target, and **downranks** Flash of Light / Holy Light to the deficit for mana efficiency. The `+healing` bonus is read automatically from gear (override with `/ar healpower <n>`), and Healing Light / Divine Favor talents are factored in.
- **Holy Shock** is used as an instant for emergencies (below a configurable %) or for a hurt unit out of melee range; **Holy Light** covers large deficits, **Flash of Light** the rest.
- The attack rotation **yields the GCD** while anyone needs healing, so a Seal of Wisdom judgement never steals a heal's cast; the opener seal is skipped in heal mode so a range healer keeps the GCD free.
- New commands: `/ar heal`, `/ar healat <1-100>`, `/ar hsat <1-100>`, `/ar healpower <n>`. New "Healing" panel section, and the `heal` template now turns heal mode on.

### Kept (ret/prot untouched)
- The current Paladin's strikeMode dropdown + downranking, Consecration AoE lead, Exorcism, mana/HP management, seal twisting, and the confirmed `Vengeful Strikes` / `Righteous Strikes` talent names — all preserved. The heal engine uses the core's `MaxRank` rather than the branch's local copy.

---

## v0.8.8b — Branch merge (step 3): Warlock channel/Nightfall/pet refinements

Reviewed the modified branch's Rogue and Warlock against the current modules and merged only what was genuinely better.

### 🔮 Warlock (merged from the branch)
- **Channel-clip protection:** a `SPELLCAST_CHANNEL_START/STOP` watcher now blocks the rotation while a channel runs, so **Drain Life** and **Drain Soul** can no longer be clipped by a DoT refresh or the filler on the next press (16s ceiling guards a missed stop event).
- **Nightfall single-use:** the free **Shadow Bolt** from a Shadow Trance proc now fires once per proc on the rising edge, instead of re-firing every press while the icon lingers (which cast a full-cast Shadow Bolt and clipped the rotation). Rearms when the icon clears.
- **Pet only in melee range** (`petMeleeOnly`): optional gate so the pet is sent only when the target is within melee range, mirroring the melee auto-attack gate — keeps the pet from running off to an accidentally targeted far enemy. New checkbox in the Filler & pet section.

### 🗡️ Rogue (reviewed, no change)
- The branch's Rogue was an older revision: no **Rupture** upkeep, reverted the shared `Msg`, reverted the `OpenConfig` nil-guard, and re-introduced the leveling validity nag the current build deliberately removed. The current module is superior on every axis, so nothing was taken.

### Kept (not regressed by the merge)
- The current Warlock's strengths were all preserved: SuperWoW name-based DoT detection, the Drain Life / Health Funnel / Shadowburn / Drain Soul survival toolkit, `ResolveFiller` (level-1 wand→Shadow Bolt fallback), Nightfall talent auto-detect, and no-nag profile validity.

---

## v0.8.7b — Branch merge (steps 1-2): core acquire toggle + minimap options panel

Reviewed the modified branch's core and minimap. The branch core was an older lineage missing every current optimization, so the current core was kept as the base and only its genuinely-new pieces were merged in.

### ⚙️ Core (merged from the branch)
- **Global self-targeting toggle** — `/ar acquire on|off` (also on the minimap right-click), persisted in `AutoRotaDB.acquire`. Targeting now respects **both** this global toggle and the existing per-module opt-out (`autoAcquireTarget`, e.g. the Hunter), and drops a dead corpse so an assist addon can reassign you.
- **`RunsWithoutTarget` support hook** — lets a module run with no attackable target (scaffolding for the upcoming Paladin heal mode).
- **`/ar minimap`** command to toggle the button; melee auto-attack is now gated on `InMeleeRange()` so a far accidental target never starts a swing.
- Kept all current core optimizations the branch lacked: spell-index cache + `MaxRank`, per-press buff/target-debuff snapshots, validity cache, shared `Msg`, vararg `Trace`, and `/ar talents`.

### 🗺️ Minimap (merged from the branch)
- The current minimap already had the **dynamic class-crest icon** (the branch had regressed it to a fixed cog), so that was kept. Added the branch's **right-click options panel** (the self-targeting toggle + a config shortcut) and a `ToggleShown` hook so `/ar minimap` works. `/armap` kept as a convenience alias.

---

## v0.8.6b — Hunter: rotation refactor (opener, mana efficiency, BM weave, AoE)

A pass over the whole Hunter rotation for clean, mana-efficient play from level 1 to 60. Priority order was restructured and several leveling/BM behaviors added; all of it stays `KnowsSpell`-gated so it scales as abilities are trained.

### 🏹 Strict opener (the level-6 inconsistency)
- **Hunter's Mark now always leads.** It's the first GCD action, and the rotation will not advance to Serpent Sting or any shot until Mark is confirmed on the target. Serpent Sting carries an explicit "Mark is up" gate on top of the ordering, so the opener is deterministic.

### 🏹 Mana-efficient leveling rotation
- **Low-HP execute:** Serpent Sting is no longer applied to a target below `30%` HP (it can't tick its full DoT) — the rotation finishes with **Arcane Shot** instead of wasting the cast.
- **Arcane Shot is no longer spammed.** As a mana-hungry filler it now only fires when mana is above `50%` *or* when Auto Shot can't fire (you're moving / out of range, detected by stale shot timing). Stationary, it stays out of the way so **Auto Shot** carries the damage and conserves mana.
- **Aimed Shot opener (optional toggle):** open the pull with a hard-cast Aimed Shot before Auto Shot starts. Fires exactly once at the start (panel checkbox under Aimed Shot, or `/ar spell opener`).
- Aspect handling already covers Hawk (ranged), Wolf (melee, arrow/mana conservation), and the dynamic Viper swap when low — in both stances.

### 🏹 BM ranged weave & burst
- The **1:1 Auto Shot ↔ Steady Shot weave** is the primary loop (Steady is swing-gated so it never clips, with the stale-timing fallback from 0.8.4b). **Multi-Shot** then weaves into the post-Steady downtime (Auto → Steady → Multi) for single-target burst when GCDs allow.

### 🏹 AoE rotation + pet cleave
- AoE order is now **Multi-Shot on cooldown → Volley** (channel for dense packs); **Carve** leads the *melee* branch under AoE.
- **Pet cleave:** while AoE mode is on, the pet's **Thunderstomp** is driven automatically (off the GCD, throttled, no-op if the pet lacks it), on top of the pet attacking the primary target.

### 🏹 Dynamic talent integration (1–60)
- Talent-granted abilities slot in automatically as they're learned (they appear in the spellbook, so `KnowsSpell` detects them): **Carve / Lacerate** (Survival), **Kill Command / Baited Shot** (BM, Baited fired in the window after a pet crit), **Steady Shot** (MM). Defaults are set per spec template; everything no-ops cleanly when untrained, so the same profile works from level 1 up.

### 🧹 Internals
- `Rotate` reorganized into clear numbered phases (off-GCD → aspect → Mark → opener → backbone → GCD priority → melee/ranged branches); added `PetCleave`, `STING_HP_FLOOR`, `ARCANE_MANA_FLOOR`; trace now shows target `hp=`. No duplicate or orphaned code. Panel grew two rows (Aimed opener, earlier Carve) with the height adjusted to match.

---

## v0.8.5b — Hunter: Carve (Survival melee AoE)

### 🏹 Added: Carve
- **Carve** is now in the melee branch — the Survival cone AoE (up to 5 targets in a 10yd cone, instant, shares its cooldown with Multi-Shot). It leads the melee branch when AoE is toggled on (`/ar aoe`), mirroring how Volley/Multi-Shot lead ranged AoE. On by default in the Survival/melee templates, toggle in the panel or `/ar spell carve`; `KnowsSpell`-gated so it no-ops if untrained.
- Sits in priority above Mongoose Bite / Lacerate / Raptor Strike while AoE is on, so multi-target melee pulls open with the cleave.

---

## v0.8.4b — Hunter: the weave actually weaves, plus melee opener & Lacerate

### 🏹 Fixed: Steady Shot now weaves 1:1 with Auto Shot
The weave gate had a fatal edge: it computed the window purely from the last Auto Shot time, so the moment that timestamp went **stale** (Auto Shot paused during a Steady cast, or a shot event was missed) the window went negative and the gate read "wait" **forever** — which is why Steady stopped weaving while the instant shots kept firing. Three fixes:
- **Stale fallback:** if the last-shot time isn't fresh, the gate falls back to a simple one-per-swing interval instead of locking to "wait". The weave can no longer get stuck.
- **One Steady per shot cycle:** a guard ensures exactly one Steady between Auto Shots (it can't re-fire until the next shot lands), so it's a true 1:1 weave with no chaining.
- **Steady is now the *primary* filler**, tried before Arcane/Multi-Shot; when its post-shot window is closed the instants fill the gap instead. Also clamps a minimum post-shot weave window so a fast ranged weapon still gets a Steady in rather than never weaving.
- `/ar trace` still shows `steady=ready/precise` vs `wait/interval` to confirm the path live.
- *Note:* Steady Shot is baseline at level 20 — below that there's nothing to weave (the gate is moot).

### 🏹 Melee opener & priority (range-gated, not mode-gated)
- **Serpent Sting and Hunter's Mark now open the pull in every mode** — Sting is gated on *actual distance* (applied while the target is still out of melee), so even a pure **melee** hunter lands Hunter's Mark + Serpent Sting on the pull, then stops stinging once you close to melee. (Or just use **Auto** mode, which does the same range handoff automatically.)
- **Lacerate** added to the melee branch as a maintained bleed (Survival), slotted Mongoose Bite → Lacerate → Raptor Strike → Wing Clip. On by default in the Survival/melee templates, toggle in the panel or `/ar spell lacerate`. KnowsSpell-gated, so it no-ops if untrained.

### 🏹 Aspects in melee
- The **mana aspect swap (Viper)** now applies in melee too, not just ranged: a mana-heavy melee hunter drops to Viper below the threshold and swaps back to Aspect of the Wolf once recovered (same hysteresis). Aspect of the Monkey (dodge) remains a manual situational choice.

### ❓ Does it range-check melee vs ranged?
Yes — **Auto** mode (the default for new profiles, `/ar mode auto`) picks ranged vs melee each press from your distance to the target, so it opens at range with Mark + Sting + shots and switches to strikes as you close. `/ar trace` shows `mode=auto/ranged` or `mode=auto/melee`.

---

## v0.8.3b — Hunter: range-state fixes, auto mode & smart pet taunt

A pass on the Hunter module fixing the range-vs-melee state confusion and the Auto Shot stall, plus two requested features.

### 🏹 Fixed: range-vs-melee state confusion
- **Hunter's Mark and Serpent Sting failing in ranged mode** — in ranged mode the rotation started Auto Shot with `CastSpellByName` in the *same press* as Mark/Sting, and vanilla won't land two casts in one frame, so the instant lost (it only ever worked in melee mode, where Auto Shot isn't cast). Starting Auto Shot is now its own press and returns, so once it's running, Mark and Sting fire normally.
- **Serpent Sting firing in melee** — Mark and Sting used to run before the melee/ranged split, so a sting (a ranged shot) fired mid-melee. Sting is now maintained in the **ranged branch only**; **Hunter's Mark stays universal** (it amps damage in both states).
- **Errant auto-targeting** — the Hunter no longer auto-acquires a target (new per-module opt-out honored by the core), so the rotation can't grab and pull a random nearby mob and instantly sting it. You pick your targets.

### 🏹 Fixed: Auto Shot stall
- Auto Shot could get stuck and only resume after a manual target swap: the old per-target "assumed on" flag was never cleared, so a stalled shot was never restarted. It now uses the SuperWoW `UNIT_CASTEVENT` shot timing to detect a stall (no shot for the ranged swing + ~2s) and restarts automatically, with a self-re-poking fallback when no event data is present. No more target-swap to unstick.

### ⚡ Added: Auto mode (distance-based switching)
- A third playstyle, **Auto**, picks ranged vs melee each press from your distance to the target (`CheckInteractDistance`, ~10yd, with a short stickiness so it doesn't flicker at the boundary). Shots fire at range, strikes fire in melee, with no cross-mode bleed — which is also the clean fix for the whole state-confusion class of bugs. It's the **default for new profiles** (great for leveling). Switch with the panel dropdown or `/ar mode auto|ranged|melee`; `/ar trace` shows the effective mode as `mode=auto/melee` or `mode=auto/ranged`.

### ⚡ Added: Smart pet taunt (opt-in)
- When the mob peels off the pet onto you (target's target is you), the pet's **Growl** is sent to grab it back — found by scanning the pet action bar, throttled to respect its cooldown. Off by default (leave it off for melee-weave builds where you want the aggro); toggle in the Pet section of the panel.

### 🧹 Cleanup
- Removed the now-unused `inMelee` local from the rotation; no duplicate function definitions or orphaned fields introduced by the change. Melee auto-attack start is unchanged and still depends on **Attack** being on an action bar (documented) since vanilla has no API to force the white swing otherwise.

---

## v0.8.2b — Hunter: frame-accurate Steady Shot weave (SuperWoW)

Builds on 0.8.1b's swing gate with exact timing from SuperWoW (a hard requirement for this addon anyway).

### 🏹 Improved: precise Auto Shot weave via UNIT_CASTEVENT
- 0.8.1b gated Steady Shot on the ranged-swing *interval* (`UnitRangedDamage`), which kept Auto Shot firing but couldn't see the actual swing phase. This release hooks SuperWoW's **UNIT_CASTEVENT** to record the exact moment each Auto Shot launches and Steady Shot's real, haste-adjusted cast time.
- Steady Shot now weaves only when it will **finish before the next Auto Shot's windup** (with a margin for the ~0.5s shot windup plus latency) — frame-accurate: weave immediately after a shot lands, then hold for the next one. No clipping, no starvation, maximum Steady uptime in the gap.
- Robust fallback: if no Auto Shot event has been seen yet (or SuperWoW is somehow absent), it falls back to the 0.8.1b interval throttle automatically. `/ar trace` now shows `steady=ready/precise` or `steady=wait/interval` so you can confirm which path is live.
- Implementation detail: events are filtered by the player's GUID before the spell-name lookup, so it stays cheap even with many units casting nearby; Steady's cast time is measured live from the event rather than assumed.

---

## v0.8.1b — Hunter: Steady Shot weave fix

### 🏹 Fixed: Steady Shot starving Auto Shot
- Steady Shot was queued on every press with no timing gate. Steady Shot has a cast time and, with Nampower, casting it pauses the Auto Shot swing — so mashing the macro chained Steady Shots back to back and Auto Shot was delayed or never fired.
- Steady Shot is now **swing-gated**: it fires at most once per ranged-swing cycle (`UnitRangedDamage` gives the interval, ranged haste included) and is locked out for the rest of the cycle, leaving Auto Shot a clear window. This produces the intended 1:1 weave — Steady, gap-with-Auto-Shot, Steady — instead of a Steady chain. The weave timer resets on leaving combat, and `/ar trace` now shows `steady=ready|wait` so you can see the gate working.
- Instant weaves (Arcane Shot, Multi-Shot) and the Lock-and-Load Aimed Shot reaction are unaffected; only the cast-time Steady Shot needed gating.

---

## v0.8.0b — Shaman

Adds the **Shaman** as a full mode-adaptive class module — the eighth class — built to the same standards as the rest: usable from level 1, talent-aware, and with its mechanics matched to Turtle 1.18.1. Minor version bump for a new class.

### ⚡ Added: Shaman module (Enhancement / Elemental / Tank)
- **Three modes**, switchable in the panel or with `/ar mode <enhancement|elemental|tank>`:
  - **Enhancement** (melee): auto-attack, Stormstrike, Lightning Strike, a shock on its shared cooldown, with a Lightning Bolt weave.
  - **Elemental** (caster): Flame Shock DoT and a Lightning Bolt filler (which builds Electrify), with Elemental Mastery on cooldown.
  - **Tank**: Earth Shock threat on cooldown, Stormstrike for the Nature-damage self-buff, Lightning Strike, and an optional Earthshaker Slam taunt (cast only when the target isn't already on you).
- **Works from level 1:** a fresh shaman has only *Lightning Bolt* and melee, so the Lightning Bolt filler carries the early levels and everything else — shocks, shields, Stormstrike, Lightning Strike, Searing Totem — enables itself through `KnowsSpell` as it is trained. Profile validity never flags a not-yet-learned ability.
- **Shield & shock management:** keeps your chosen shield up (Lightning for damage/threat, Water for mana, Earth) and casts one shock on the shared cooldown — Flame Shock maintained as a DoT (name/texture detection with a blind-timer fallback), Earth/Frost on cooldown. `/ar shield` and `/ar shock` to switch.
- **Stormstrike → shock ordering:** Turtle's Stormstrike grants a +20% Nature-damage self-buff for your next two Nature hits, so the rotation casts it before the shock to consume the buff.
- Optional Searing Totem upkeep (timer-based, since 1.12 has no totem-state API), plus Elemental Mastery and self-Bloodlust pops. Full config panel with mode/shield/shock dropdowns and per-ability toggles.

### 🌙 Talent automation
- **Stormstrike**, **Lightning Strike**, and **Elemental Mastery** are talent-granted abilities that appear in the spellbook when talented, so `KnowsSpell` auto-includes them in the rotation when present — no scan needed.
- **Elemental Focus** grants no spell (it's a passive crit proc — Clearcasting, making the next spell 60% cheaper), so it can't be seen via `KnowsSpell`. AutoRota reads the **talent tree** (`GetTalentInfo`, cached and refreshed on respec) to detect it and surface the Clearcasting proc in the trace — the same approach used for the Warlock's Nightfall. The discount applies to your next spell automatically; spending it specifically on Chain Lightning is a planned follow-up (no AoE/Chain Lightning option in this build yet).

### 📝 Notes
- In-game verification (flagged in the README): confirm the **Clearcasting** proc buff name, the **Stormstrike** self-buff, and the **Searing Totem** / **Earthshaker Slam** spell names with `/ar talents` and `/ar debug`. The talent name sits in one constant (`TALENT_CLEARCAST`) in `Class_Shaman.lua`.
- Not yet covered (candidate follow-ups): AoE (Chain Lightning / Magma / Fire Nova totems), weapon-imbue automation (Rockbiter/Windfury/Flametongue/Frostbrand), and spending the Clearcasting proc on a high-mana nuke.

---

## v0.7.4b — Talent-Name Fixes, Rogue Rupture & a Talent Dump

A talent-tree cross-reference pass against Turtle 1.18.1, plus the tooling to verify talent and buff names in-game.

### 🛡️ Fixed: Paladin talent names (the strikes now work as designed)
- The talent scan looked for `"Vengeful Strike"` and `"Righteous Strike"` (singular), but the actual in-game talents are **"Vengeful Strikes"** (Retribution → Holy Strike grants the Holy Might Strength buff) and **"Righteous Strikes"** (Protection → Holy Strike threat), both **plural**. A name mismatch makes `GetTalentInfo` return rank 0, which silently disabled `HolyMightWorthwhile()` — so a Ret paladin's Holy Might maintenance never fired, and Prot lost its talent-based threat lean (only the equipped-shield half still worked).
- Both constants corrected to the exact in-game strings (verified with the new `/ar talents` dump). Holy Might upkeep (Ret) and the Holy Strike threat lean (Prot) now activate correctly.

### 🗡️ Added: Rogue Rupture upkeep (Taste for Blood)
- Rupture is now applied as a finisher at your combo-point threshold when it falls off the target, slotted before the Eviscerate dump. Toggle in the panel's Finishers section (on by default in the `assassination` template, off elsewhere), detected on the target by name/texture.
- Turtle's **Taste for Blood** (Assassination) makes a maintained Rupture a stacking damage buff on top of the bleed; Rupture is baseline, so the talent just sweetens an already-worthwhile DoT and a simple toggle is enough (no talent gate needed).

### 🔍 Added: `/ar talents` debug dump
- Prints every talent tab and talent with its current rank (ranked talents highlighted), so you can confirm the exact in-game name of any talent — useful for the proc-style talents the rotations read (Paladin's strikes, Warlock's Nightfall) where the string must match `GetTalentInfo` precisely. Sits alongside `/ar debug`.

### 📝 Cross-reference notes (no code change needed)
- **Hunter:** already correct — the rotation reacts to the real **Lock and Load** proc buff for Aimed Shot and fires **Kill Command** on cooldown (the game gates its after-a-crit requirement). Verify the buff is named "Lock and Load" in-game with `/ar talents`-style checking if a proc ever seems missed.
- **Druid:** already optimal for **Open Wounds** — the bleed rotation keeps Rake (and Rip) up before Claw, which is exactly what the talent rewards. Feral Adrenaline / Blood Frenzy are defensive or flat passives that don't change button priority.

---

## v0.7.3b — Warlock Toolkit & Talent-Aware Nightfall

Expands the Warlock from a DoT-and-filler loop into a full survival / execute /
pet kit, and adds the project's first **talent-tree read** for rotation logic.

### 🔮 Added: Warlock survival, execute, and pet tools
Each is optional, gated by `KnowsSpell`, and slots into the rotation by priority (survival → execute → DoTs → Life Tap → filler):
- **Drain Life self-heal** — channels Drain Life when your health drops below a set percent (the drain-tank safety net). Highest priority, because staying alive comes first.
- **Health Funnel** — tops the pet when it drops below a threshold, but only while your *own* health stays above a floor (it transfers your health to the pet).
- **Shadowburn execute** — instant finish under an execute percent (costs a Soul Shard, respects its cooldown).
- **Drain Soul finisher** — channels in the target's last seconds to bank a Soul Shard and regen mana. If both Shadowburn and Drain Soul are enabled, Shadowburn fires first when ready and Drain Soul fills otherwise.
- New **Execute** and **Survival** sections in the config panel with per-feature toggles and percent sliders; the `starter` template enables Drain Life + Health Funnel + Drain Soul for leveling, and `destruction` enables Shadowburn.

### 🌙 Added: talent-aware Nightfall (the talent-scan question)
- The rotation now reads the **talent tree** (`GetTalentInfo`, cached like the paladin) to detect **Nightfall**, and **auto-enables the free-instant-Shadow-Bolt reaction** when the talent is present — no manual toggle needed. The toggle remains as a manual override.
- Why a talent read here specifically: Nightfall grants no spell, so `KnowsSpell` cannot see it — same situation as the paladin's Holy Might (Holy Strike exists, but only the talent makes it apply the buff). **Most warlock talent abilities do *not* need a talent scan** — Shadowburn, Conflagrate, Siphon Life, and Drain Soul all appear in the spellbook only when talented, so `KnowsSpell` already detects them. Only proc-style passives like Nightfall need the tree read.
- Added the matching **talent-cache invalidation** (cleared at login and on `CHARACTER_POINTS_CHANGED`) so a respec into or out of Nightfall is picked up.

### 🩹 Fixed
- Filler dropdown and rotation already fall back to Shadow Bolt for a level 1 warlock (carried from 0.7.2b); this release builds the survival/execute kit on top so a leveling warlock drain-tanks and banks shards out of the box.

---

## v0.7.2b — Stability Pass: Druid Swing, Hunter & Warlock Leveling

A correctness release from a full project review. No new features — two
targeted bug fixes and a version cleanup (the core banner had jumped ahead to
`0.8.0b`; everything is now back in sync at `0.7.2b`).

### 🐾 Fixed: Druid auto-attack dropping (form changes + with/without SCRM)
- The core caches the Attack action's bar slot for speed and only re-scans when that slot stops being an attack action. But shapeshifting swaps the entire action bar **and** stops the current swing, so after a Cat↔Bear change the cached slot could point at the wrong bar position and the white swing would silently fail to restart — the intermittent "auto-attack sometimes stops" report.
- The Druid now **drops the cached slot on every form change**, forcing one fresh scan on the first press in the new form, which re-finds Attack on the now-current bars and restarts the swing the shift halted. Same-form returns (e.g. a Cat→caster→Cat powershift) were already self-healed by the existing "use only if not current" guard; this closes the melee→melee gap.
- **Auto-attack now works whether or not SuperCleveRoidMacros is loaded.** Previously, when SCRM was present, AutoRota skipped its own auto-attack handling entirely and deferred to SCRM — but a bare `/ar` macro gives SCRM no `/startattack` to hook, so the swing never started (you would see the rotation taunt and use abilities but not auto-attack). The skip is removed in both the Druid module and the core: `EnsureAutoAttack` only toggles Attack when you are *not* already swinging, so it is a no-op if SCRM already started the swing and fills the gap if nothing did — conflict-free for both player populations. This core change applies the same robustness to Paladin, Rogue, and Warrior.
- Reminder unchanged, and **now documented for Druids in the README**: Attack must sit on a bar slot the Cat/Bear form bar does not replace (a side or bottom bar), since shifting replaces your main bar.

### 🏹 Fixed: Hunter now reads as usable from level 1
- The rotation already ran at level 1 (Auto Shot, plus Raptor Strike in melee, with everything else enabling itself as it is learned), but the `starter` profile defaulted its sting to **Serpent Sting** — which a hunter does not have until level 4 — so the profile-validity check nagged "incomplete, missing Serpent Sting" on every pull and made it *look* broken.
- Hunter profile validity is now **tolerant of not-yet-learned abilities**, the same way the Druid does not flag a not-yet-learned form. A fresh hunter reads as a clean, usable profile and simply Auto Shots until each ability (Serpent Sting L4, Hunter's Mark / Arcane Shot L6, Aspect of the Hawk L10, Steady Shot L20) trains and switches itself on. The misleading "valid from level 1" template comment was corrected to list real learn levels.

### 🔮 Fixed: Warlock now works from level 1
- A fresh warlock's only damage spell is **Shadow Bolt**, but the `starter` profile's filler is the **wand** (`Shoot`) — and a level 1 warlock has no wand. The DoT loop skipped every not-yet-learned effect, the wand filler did nothing without a wand, and **Shadow Bolt was never reached**, so the rotation cast nothing useful while leveling.
- The filler now **adapts** (`ResolveFiller`): the wand filler falls back to **Shadow Bolt** when no wand is equipped, and a spell filler that is not learned yet also falls back to Shadow Bolt. The moment a wand is equipped it is used again automatically — no settings change — preserving the mana-efficient drain-tank leveling style while never leaving a low-level warlock idle.
- Profile validity is now **tolerant of not-yet-learned abilities** (same as the hunter and druid), so the leveling profile no longer nags about Immolate / Corruption / Curse of Agony before they are trained.

### 🔢 Changed
- Version set to **0.7.2b** across the core banner, `.toc`, README, and changelog. The core banner had been bumped to `0.8.0b` ahead of the docs; since this release is bug-fix-only it is a patch bump from 0.7.1b, not a minor.

---

## v0.7.1b — Hunter Reworked for 1.18.1 & Druid Tank Pull

Rebuilds the Hunter around **Turtle WoW 1.18.1's** hunter changes (the earlier
module was vanilla-1.12 based), and sharpens the Druid bear opener and
auto-attack.


### 🐾 Improved: Druid bear pull & auto-attack
- **Faerie Fire (Feral)** is the bear's **ranged opener** — instant, 30yd, threat + damage on the pull before the mob arrives. (Moonfire cannot be cast in bear form, so this is its bear analog.)
- New optional **Growl** taunt: grabs threat on the pull and whenever the target is not focused on you, and stays quiet while you already hold aggro (so solo play never wastes it). Toggle in the Bear panel, on by default.
- **Form-aware auto-attack:** the white swing is now started in **Cat and Bear** and no longer attempted while casting in caster/Moonkin. (Attack must be on a bar slot the form bar does not replace, or let SuperCleveRoidMacros manage it.)

---

## v0.7.0b — Hunter Module & Spell-ID Debuff Detection

Adds the sixth class module, **Hunter**, and replaces the addon's icon-fragment
debuff detection with exact **SuperWoW spell-id** matching across every class.

### 🏹 Reworked: Hunter (Turtle 1.18.1)
- **Two playstyles per profile**, switchable with `/ar mode ranged|melee`:
  - **Ranged (BM / MM):** Auto Shot backbone with **Steady Shot** (baseline at 20) as the 1:1 weave, plus *Arcane Shot* / *Multi-Shot* instants. All shots are queued through SuperWoW/Nampower so the weave never clips the shot in progress.
  - **Melee (Survival / BM-melee):** keeps **Aspect of the Wolf** up, starts melee swings, uses **Raptor Strike** on cooldown and **Mongoose Bite** reactively after a dodge, optional *Wing Clip*, and drops **Immolation Trap** on cooldown (1.18.1 allows in-combat traps).
- **Lock and Load capstone:** *Aimed Shot* is no longer hard-cast on cooldown (it clips Auto Shot). The rotation watches for the **Lock and Load** buff and fires *Aimed Shot* the moment it procs; a per-profile toggle can re-enable cast-on-cooldown.
- **Aspect management:** keeps Hawk (ranged) / Wolf (melee) up and can **swap to the mana aspect** below a threshold with hysteresis so it does not flap.
- **Pet:** attack, *Mend Pet* below a slider, **Kill Command** on cooldown (BM), and an optional **Baited Shot** in the window after the pet crits.
- New panel (mode, sting, ranged shots with the Lock-and-Load guard, AoE/Survival, melee, aspect + mana swap, pet, cooldowns) and templates: `starter`, `beastmastery`, `marksmanship`, `survival`, `melee`. New command `/ar mode`; refreshed spell aliases.
- **Honesty note:** a few 1.18.1 names are best-effort and gated by `KnowsSpell` (so an unknown name no-ops). The mana aspect tries *Aspect of the Viper* then *Aspect of the Beast*; *Kill Command*, *Baited Shot*, and the *Lock and Load* buff name are the items to confirm with `/ar debug` if they do not fire.

### 🎯 Changed: Exact Debuff Detection (all classes)
- Target debuffs are now resolved to their exact **spell name** through SuperWoW's spell id (the same id path the player-buff snapshot already used), built once per press into a shared snapshot in the core. The previous **icon-texture fragment** match is kept as an automatic fallback for clients without SuperWoW, so detection degrades to the old behaviour rather than breaking.
- This makes upkeep exact and rank/locale-proof everywhere: the **Warlock** now tracks *every* curse precisely instead of blind-timer reapplying any curse without a hand-verified texture (the old "Add more textures once confirmed" limitation is gone when SuperWoW is present); the **Paladin** judgement debuffs, **Druid** bleeds/DoTs, and **Warrior** *Sunder Armor* stacks all read from the same exact source.
- `/ar debug` now prints each target debuff as **name / stacks / texture**, so any remaining unmapped effect is easy to identify.

### 📝 Notes
- The spell-id path requires SuperWoW (already a hard requirement). Without it, every class falls back to the prior texture-fragment behaviour automatically.
- Hunter sting/Hunter's Mark icon textures are intentionally not hard-coded: with SuperWoW the exact name is used, and without it a short reapply timer keeps them up.

---

## v0.6.2b — Druid Defensive Bear

Adds an adaptive **HP-managed defensive form switch** to the Druid, built on
the same hysteresis pattern as the Paladin's mana/HP sliders. Other classes
are unchanged.

### 🛡️ Added: Defensive Bear (HP Management)
- New **Defense (HP management)** section in the Druid panel: a checkbox plus the familiar two sliders — *switch below* (default **35%**) and *back above* (default **70%**).
- Drop under the low threshold and the rotation **forces Bear Form from any form** — Cat, Moonkin, or caster; form-to-form shifts are direct one-cast moves in 1.12 — and holds it. Climb back over the high threshold and it **releases you to your preferred form automatically**. The two-threshold hysteresis prevents form-flapping when HP hovers near a single boundary.
- While turtled up it keeps fighting: **Frenzied Regeneration** fires on cooldown when known (rage → health), then the full bear rotation runs — Faerie Fire, Demoralizing Roar, Maul/Swipe — so the mob still dies behind 4× armor while you stabilize.
- **Safety rails:** off by default (a mid-fight form swap should be opt-in), and completely inert — logic and UI both — until a bear form is learned, so it cannot misfire on a low-level character. The bear trace line gains a `def=Y/N` flag and the shift itself logs `DEFENSE: hp NN%, shifting to Bear Form`.

### 📝 Notes
- Expectation setting: bear form does not regenerate health quickly by itself — *Frenzied Regeneration* and out-of-combat regen do the recovering. The practical loop is: dip low → bear up → kill the mob behind the armor → regen → release. Leveling insurance, not a healing replacement.
- The hysteresis pattern is portable; a Warrior Defensive-Stance/Shield-Wall or Rogue Evasion equivalent can ride the same design if wanted.

---

## v0.6.1b — Druid Balance & Level 1+

The Druid module gains the **Balance (Caster/Moonkin)** rotation and now
works **from level 1** — a fresh druid no longer stares at "learn Bear Form
first" until level 10. Also hardens the UI entry points after a field report.

### 🌙 Added: Balance / Caster Rotation
- New rotation branch, run in **Moonkin Form** or with the new *Caster / Moonkin* form preference (`/ar form caster`, aliases `moonkin`, `balance`). When Moonkin Form is learned, the rotation enters it automatically for the inherent mana discount.
- **Priority:** *Moonfire* upkeep → *Insect Swarm* upkeep → **Eclipse reaction** (Lunar proc → empowered *Starfire*; Solar proc → empowered *Wrath*) → chain-cast the primary nuke (dropdown: *Wrath* default, *Starfire* once learned) to fish for the next proc.
- **Proc-window timing:** nukes are queued through SuperWoW's `QueueSpellByName`, so spamming never clips the cast in progress — and the press made *during* a cast queues the Eclipse-buffed nuke to fire the instant the window opens, the macro equivalent of the manual cast-cancel trick without `SpellStopCasting` risk.
- **AoE multi-dotting needs no toggle:** tab-target and the priority Moonfires/Swarms the fresh target first. *Hurricane* stays manual (ground-targeted, needs a click).
- New UI section (nuke dropdown, Moonfire / Insect Swarm / Eclipse-reaction toggles) and a new `balance` template.

### 🌱 Fixed: Works From Level 1
- If no combat form is learned yet (Bear trains at 10, Cat at 20), the rotation now **falls back to the caster loop** instead of refusing — at level 3 that is Moonfire upkeep plus Wrath, exactly the right early-leveling rotation. The same applies between 10 and 19 for a cat-preference profile (bear fallback still wins if learned).
- The default `starter` profile therefore works out of the box at level 1 and **grows into its form automatically** the moment it is trained — no profile edits needed at 10 or 20.
- Profile validity no longer flags a not-yet-learned combat form as "missing": an unlearned form is a life stage, not a configuration error.

### 🛡️ Fixed: UI Entry Hardening (field report)
- The minimap button and every class `OpenConfig` now guard against the UI framework being absent instead of throwing `attempt to index global 'AutoRotaUI' (a nil value)`.
- The guard message is **diagnostic, not misleading**: it names the actual cause ("AutoRota_UI.lua is missing or mislabeled in your AutoRota folder, reinstall the files") rather than suggesting a wait that will not help. Root cause in the reported case was a mislabeled file on disk — the file named `AutoRota_UI.lua` contained core code, so the framework chunk never loaded. A clean reinstall of correctly-labeled files resolves it; saved profiles in `WTF\...\AutoRotaDB.lua` are unaffected.

### 📝 Notes
- **All class modules are flagged `(Beta)`** in the README while Turtle-specific details are field-verified. Known open verification items: Druid Eclipse buff names (`ECLIPSE_LUNAR` / `ECLIPSE_SOLAR` lists in `Class_Druid.lua`, check with `/ar debug` while a proc is up), the Druid debuff textures, the Cat Form recast vs custom powershift spell question, and Warlock curse textures beyond *Curse of Agony*.

---

## v0.6.0b — Feral Druid Beta

Adds the fifth class module: **Druid (Feral)**, covering both Cat (DPS) and
Bear (Tank) in a single form-adaptive engine built for Turtle WoW's custom
feral balance. Other classes are unchanged.

### 🐾 Added: Druid (Feral) Module
- **Form-adaptive rotation:** each press follows the form you are actually in — Cat Form runs the DPS rotation, Bear/Dire Bear Form runs the tank rotation, and caster form shifts you into the profile's preferred form (panel dropdown, or `/ar form cat|bear`). One profile and one macro cover both jobs, and the design closes the powershift loop for free: shifting out lands in caster form, the next press shifts straight back into Cat with a fresh energy bar.
- **Two cat styles**, matching the two competitive Turtle WoW playstyles, switchable from the panel or mid-fight with `/ar style bleed|shred`:
  - **Claw & Bleed** *(default)* — keeps *Rake* and *Rip* rolling and builds with *Claw*; pairs with bleed-energy talents like *Ancient Brutality*.
  - **Shred & Powershift** — builds with *Shred*, finishes with *Ferocious Bite* (no bleed globals), for bleed-immune raid targets (Molten Core / BWL).
- **Smart finishers:** at the combo threshold (slider, 1–5) the bleed style applies *Rip* when it is not ticking and spends *Ferocious Bite* while it is, so combo points never refresh a bleed that is already running. If the finisher is not yet affordable the rotation waits rather than wasting a builder at full points.
- **Powershifting (opt-in, Shred style):** when energy falls below the slider, shift out and back in for a fresh energy bar — **never while Tiger's Fury is active**, so the buff is not thrown away; the shift waits for it to expire. Each re-shift costs mana; the tooltip says to watch the blue bar.
- **Stealth opener:** while *Prowl* is up the first press uses *Ravage* (auto, when known) or *Pounce*, or can be disabled; an unaffordable opener falls through and the builder breaks stealth instead of stalling.
- **Upkeep:** *Faerie Fire (Feral)* and *Tiger's Fury* are maintained ahead of the builders in Cat.
- **Bear tanking:** *Faerie Fire* and *Demoralizing Roar* upkeep, *Maul* queued as the single-target rage dump, **Swipe leading the priority when AoE mode is on** (`/ar aoe`, the same toggle Warriors and Paladins use), and optional *Enrage* when rage-starved — in combat only and off by default, since it lowers armor.
- New slash commands: `/ar style <bleed|shred>`, `/ar form <cat|bear>`, and `/ar aoe` now also serves the Druid (Swipe).

### 🔧 Changed
- `.toc` loads `classes\Class_Druid.lua` / `Class_Druid_UI.lua`; version bumped to **0.6.0b** (login banner matches).
- The minimap button shows the Druid class crest automatically (its class table already included it).

### 📝 Notes & Tips
- **Bleed-immune bosses:** keep a shred profile (template `catshred`) or just hit `/ar style shred` on the pull and `/ar style bleed` after — your Plan A / Plan B switch.
- A vanilla casting trap is handled internally: `Faerie Fire (Feral)` contains parentheses, which `CastSpellByName` would misparse as a rank spec; the module appends `()` to such names.
- **Please verify on Turtle and report:** (1) the four debuff texture fragments (*Faerie Fire*, *Rake*, *Rip*, *Demoralizing Roar*) — if an upkeep misfires, run `/ar debug` with the debuff applied; (2) whether recasting Cat Form still shifts **out** (vanilla behaviour) or Turtle's custom powershift spell should be used instead — if the latter, its name drops into the module in one place; (3) energy costs, if Turtle rebalanced any (table at the top of `Class_Druid.lua`).

---

## v0.5.3b — Core Optimization Pass

A performance and cleanup release. No rotation behaviour changes — every class
should play exactly as before, just cheaper per press. All changes are in the
shared core and UI framework, so every class benefits at once.

### ⚡ Performance
- **Spellbook index:** spell lookups (`KnowsSpell`, `Cast`, `IsReady`, cooldown checks, max-rank queries) now read a cached name→slot / name→rank index instead of scanning the entire spellbook every call. A single rotation press used to trigger a dozen-plus full spellbook scans; each lookup is now a table read. **Fixed alongside it:** the index was never being invalidated — `SPELLS_CHANGED` is now wired up, so learning a spell or a new rank refreshes the cache immediately instead of requiring a `/reload`.
- **Profile validity is cached**, not recomputed on every press. The cache clears when you learn a spell, switch or save a profile, or run any class slash command that can modify the active profile (`/ar seal`, `/ar strike`, ...). The throttled "profile incomplete" warning still appears — it just reads the cached result.
- **Attack-button slot is cached.** Keeping auto-attack up used to scan all 172 action slots every press; it now verifies the remembered slot with a single call and only rescans if the button was moved or removed.
- **Per-press buff snapshot.** Player buffs are scanned once per rotation press; every buff check inside that press (seals, *Zeal*, *Holy Might*, *Slice and Dice*, ...) reads the snapshot instead of rescanning all 32 buff slots. Outside the rotation (UI refresh, slash commands) the old full scan still runs, so nothing else changes.
- **Paladin downranking** now reads max ranks from the shared index instead of its own per-cast spellbook scan.

### 🔧 Cleanup
- **Shared chat printer:** `AutoRota:Msg()` lives in the core; the identical local copies in the Paladin, Rogue, and Warrior modules are now one-line shims.
- **Shared checkbox binder:** the "set checked + grey/red *(not learned)* label" routine each class UI re-implemented is now a single `AutoRotaUI:BindCheck()` in the framework, used by all three class panels.
- **Multi-line trace:** the core `Trace` accepts several lines under one throttle check, so multi-line traces are never half-swallowed. The Paladin's hand-rolled double-print from 0.5.2b is gone; its two trace lines now go through the shared path.
- **Login banner version** finally bumped — it had been reading 0.4 since the multi-class rewrite.

### 🔮 Warlock Module Included
- The **Warlock module ships in this release** (`Class_Warlock.lua` / `Class_Warlock_UI.lua`), restoring the class the `.toc` and README already referenced. DoT-priority rotation: *Immolate* → chosen Curse → *Corruption* → *Siphon Life*, detected by target debuff texture with a per-target landing memory so cast-time DoTs are never double-queued; then optional *Life Tap* (mana-low / health-high thresholds) and a configurable filler (wand, *Shadow Bolt*, or *Drain Life*). Optional pet send, and a *Nightfall* reaction that spends the free instant *Shadow Bolt* when *Shadow Trance* procs. Cast-time spells go through SuperWoW's `QueueSpellByName` so the rotation never clips a cast — except while wanding, where a direct cast fires immediately instead of waiting out the wand shot. `/ar curse <alias>` switches the curse on the active profile mid-fight.
- The module was brought up to this release's standards on arrival: shared chat printer, shared checkbox binder, and a **cached wand slot** — the wand check used to scan up to 120 action slots as many as twice per press; while wanding it is now a single call, matching the attack-button caching above.

---

## v0.5.2b — Paladin Strike Overhaul

A focused pass on the **Paladin** strike engine (*Holy Strike* / *Crusader Strike*),
making it talent- and weapon-aware, adding mana-based downranking, and folding the
old per-strike checkboxes into a single control. Logic is informed by the proven
*ExAutoCSHS* addon. Warrior and Rogue behaviour is unchanged.

### 🛡️ Paladin: Strike Engine Rework
- **Strike Mode dropdown** replaces the separate *Holy Strike* and *Crusader Strike* checkboxes. One control both **enables** the strikes and picks the **style**: `Off`, `Auto (talent/weapon)`, `Crusader Strike`, `Holy Strike`, and `Holy then Crusader`. Existing profiles migrate automatically — both strikes on → *Auto*, one on → that one, both off → *Off*.
- **Talent + weapon aware Auto:** *Auto* reads both your talents and your equipped weapon, for two separate decisions:
  - *Holy Might* is maintained **only if you have Vengeful Strike** — the talent that makes *Holy Strike* apply the buff. A leveling paladin without it never wastes a global chasing a buff it cannot get.
  - The *Holy*-vs-*Crusader* **lean** is set by **Righteous Strike** (deep Protection) **or** a shield/offhand equipped → *Holy* lean for threat; a two-hander with no threat talent → *Crusader* lean. Swapping weapons changes the lean live.
- **Zeal upkeep is universal:** *Zeal* is built to 3 stacks and refreshed in **every** mode and on **every** weapon, above the filler choice — so it is always maintained, whether you are tanking with a 1H or leveling with a 2H.
- **Per-target opener:** the first strike on each new target follows your opener (Auto gets *Holy Might* rolling if the talent makes it work, otherwise opens by the tanking lean), then normal maintenance takes over.
- **Prioritize Zeal (opt-in):** builds *Zeal* to 3 stacks before anything else, then follows the selected mode.
- **Mana downranking (opt-in):** *Downrank when low* casts lower ranks of *Holy*/*Crusader Strike* as your raw mana drops, to keep swinging while leveling. Thresholds mirror the *ExAutoCSHS* tables — **absolute mana, not percent** — so a large mana pool stays at full rank and only a nearly-empty pool steps down. The chosen rank is always clamped to your highest known rank.
- **Consecration now leads AoE:** when enabled, *Consecration* is cast right after the strike (priority 2b) instead of last, so it is a primary AoE source rather than a leftover filler. It is still a manual toggle and still held during mana recovery.

### ✨ Added
- **`/ar strike off|auto|cs|hs|hscs`** *(Paladin)* — sets the strike mode on the active profile, bindable for mid-fight changes.

### 🔧 Changed
- **Paladin config panel reorganised:** *Strike mode* now leads the **Spells** section, with *Prioritize Zeal* and *Downrank when low* beside it. The two per-strike checkboxes are gone, so the panel is slightly shorter.
- **`.toc`** version bumped to **0.5.2b**. *(The login-banner string in `AutoRota.lua` is a separate one-line `ver` field; bump it to match if you want the banner to read 0.5.2b.)*

### 🐛 Fixed
- **Downranking now actually engages.** A Lua quirk — `string.gsub` returning *two* values, with the replacement count being read as a numeric base — made rank parsing fail for ranks 5 and up, silently pinning everything to full rank. Rank detection is fixed.
- **Trace output restored.** The second Paladin trace line (strike / downrank diagnostics) was landing inside the 0.4s trace throttle and being dropped every press; both lines now print together. The line reports `mode`, each strike's `R=used/max`, `lean`, offhand `oh`, `dr`, raw `mana`, and your `veng`/`rght` talent ranks.
- Removed dead strike-related profile-validity checks, so a not-yet-learned strike never blocks activating a profile — it simply degrades gracefully, the same way the Rogue handles its level-gated abilities.

### 📝 Notes & Tips
- In **Crusader** mode, a Vengeful-talented paladin will still weave the occasional *Holy Strike* to keep *Holy Might* up (a damage gain even for a CS-focused player), matching *ExAutoCSHS*. If you want a strict no-HS option, that would be a separate toggle.
- **Leveling on a 2H and want *Holy Strike* in the mix** (for its holy damage / heal)? Set the mode to **Holy Strike** — it still builds and refreshes *Zeal* with *Crusader Strike* and fills with *Holy Strike*. *Auto* deliberately leans *Crusader* on a two-hander for DPS, which is why it does not weave HS there unless you are Vengeful-talented.
- Talent names live as constants at the top of `Class_Paladin.lua` (`Vengeful Strike`, `Righteous Strike`); if Turtle renames a talent, that is the single place to adjust. The downrank mana thresholds are editable in the same file.

---

## v0.5b — Warrior Beta

The headline of this release is a brand new **Warrior** combat module, plus a
minimap button and a couple of **Paladin** additions. Rogue behaviour is unchanged.

### ⚔️ New: Warrior Module `(Beta)`
A roleless, toggle-driven engine covering **Arms, Fury, and Protection** from early
leveling through endgame raiding. Enable the abilities you have and the priority
degrades gracefully as you learn the rest.

- **All-Spec Roleless Design:** One profile schema serves every spec via toggles. Unlearned abilities are skipped automatically and flagged *(not learned)* in the panel, so a single setup keeps working as you level.
- **Stance & Rage Aware Casting:** A warrior-specific gate verifies rage, stance, and cooldown *before* committing to a cast, so a stance- or rage-locked ability can never stall the priority chain. Stance rules follow vanilla 1.12 and stay conservative if Turtle relaxes them.
- **Reactive Proc Windows:** Reads the combat log for target dodges and your own block/dodge/parry to open short windows for *Overpower* (Battle Stance) and *Revenge* (Defensive Stance), mirroring the Rogue's Riposte tracker.
- **Optional Stance Dancing:** Experimental opt-in (off by default) that auto-swaps to Battle Stance for *Overpower*, then drifts back to your configured home stance, throttled by a swap cooldown to prevent thrashing.
- **Smart Rage Dump:** Queues *Heroic Strike* (or *Cleave* in AoE mode) onto your next swing only above a configurable rage floor, and suppresses it during the *Execute* phase so surplus rage funnels into *Execute*.
- **Cooldown Automation:** *Death Wish*, *Recklessness*, and *Berserker Rage* fire on cooldown, only on Elite/Boss targets, or fully manually — the same three-state model used by the other classes — while *Bloodrage* tops up rage on demand, even before the pull.
- **Threat Toolkit:** Maintains *Sunder Armor* up to a chosen stack count and weaves *Shield Slam*, *Revenge*, and *Shield Block* upkeep for Protection tanking.
- **Starter Templates:** Ships with `starter`, `fury`, `arms`, and `prot` presets. Create one with `/ar new <name> <template>`.

### 🛡️ Paladin Updates
- **Consecration (opt-in):** New AoE filler, cast on cooldown when enabled. Because the 1.12 client cannot reliably count nearby enemies, it is a manual toggle — the *Consecration (AoE)* checkbox, or `/ar aoe` for a quick keybind flip. It sits last in the priority so it never delays strikes, *Holy Shield*, seal/Judgement upkeep, or the execute, and it is held during mana recovery.
- **Exorcism (opt-in):** New on-cooldown nuke, used only against *Undead* and *Demon* targets (checked via creature type). Also held during mana recovery.
- Both default to off, are flagged *(not learned)* in the panel until trained, and gain `/ar spell` aliases (`consec` / `cons`, `exo`). `/ar aoe` now works for Paladins too, toggling Consecration.

### ✨ Added
- **Minimap Button:** A draggable minimap button (`AutoRota_Minimap.lua`) that wears your character's class crest (paladin, rogue, warrior, etc., with a cog fallback). Left-click opens the configuration panel, right-click runs the rotation once, and dragging moves it around the minimap edge. Its position is saved per character; toggle visibility with **`/armap`**.
- **`/ar aoe`** *(Warrior)* — toggles AoE mode (rage dump becomes *Cleave*, *Whirlwind* used on cooldown). Bindable for mid-fight flips.
- **`/ar cd on|elite|off`** *(Warrior)* — sets cooldown usage to always, Elite/Boss only, or fully manual.
- **`/ar dance`** *(Warrior)* — toggles experimental stance dancing for *Overpower*.
- **`/ar spell <alias> on|off`** *(Warrior)* — flips an individual ability on the active profile, with short aliases (`ms`, `bt`, `ss`, `ww`, `op`, `rev`, `exec`, `sa`, `tc`, `hs`, `cleave`, `sweep`, `dw`, `reck`, `br`, `bld`, `sb`).

### 🔧 Changed
- **`.toc`** now loads `AutoRota_Minimap.lua` plus `classes\Class_Warrior.lua` and `classes\Class_Warrior_UI.lua`, and the addon version is bumped to **0.5b**.
- **README** updated with the Warrior section, the Paladin Consecration/Exorcism notes, the new commands in the CLI table, and the toggle / spell-alias references.
- The **Paladin config window** grew slightly to fit the two new ability checkboxes (mana/HP sections shifted down to match).

### 📝 Notes & Known Limitations
- **AoE is a manual toggle.** SuperWoW exposes no reliable "enemies in range" count on the 1.12 client, so AoE mode is flipped by you (`/ar aoe` or the checkbox) rather than auto-detected.
- **Stance dancing is experimental** and disabled by default. With it off, *Overpower* only fires while already in Battle Stance and *Revenge* only in Defensive Stance. With it on, expect a little rage loss per swap (Tactical Mastery dependent) and tune to taste in game.
- **Stance assumptions are vanilla 1.12** (e.g. *Whirlwind* is Berserker-only, *Thunder Clap* is Battle-only). If Turtle has relaxed a restriction the module simply stays safe rather than misfiring. Rage costs and stance requirements live as constants at the top of `Class_Warrior.lua` for easy tuning.
- **`Heroic Strike` / `Cleave` queueing relies on Nampower** (a required dependency), which avoids the classic re-toggle flicker when the on-next-swing ability is re-issued.
- **`Shield Slam`** requires a shield equipped; enable it only on a Protection setup.

---

## v0.4 — Configuration Panel & Database

- **Graphical Configuration Panel:** Introduced a complete in-game UI shell (`/ar ui`) for managing the rotation visually, replacing macro-embedded configuration.
- **Profile Database:** Added saved, per-character profiles you can create, rename, activate, and delete, seeded from per-class templates.
- **Multi-Class Architecture:** Reworked the core into a shared engine that dynamically loads the module matching your class, with the **Paladin** ("Roleless Seal Model") and **Rogue** (combo-point priority) modules.
- **Zero-Clipping Logic:** Standardised the strict single-cast-per-press priority with early returns across modules to prevent GCD clipping.
- `/pa`, `/paladinauto`, and `/autopala` retained as aliases for `/ar` so older paladin-era macros keep working.
