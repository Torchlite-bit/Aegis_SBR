# AutoRota ⚔️ (v0.14.0b)

**Smart, Modular Combat Automation for Turtle WoW (1.18.1)**

## 🛡️ Overview 🛡️
AutoRota is a lightweight, robust, and highly configurable combat rotation assistant designed specifically for the Turtle WoW 1.18.1 client. Moving beyond the limitations of standard 1.12 "monolithic" macros or basic script loops, AutoRota utilizes a modern, modular architecture. It leverages automated frame-by-frame management and smart, situational logic to execute precise combat sequences tailored to your class and specialization.

Whether you are leveling through the world or pushing endgame raids, AutoRota removes the guesswork from your rotation. By delegating the complexities of ability timing to our frame-perfect execution engine, you can focus on movement, positioning, and tactical awareness, confident that your optimal rotation is running flawlessly in the background


## ⚠️ Important Beta Notice ⚠️
AutoRota is currently in an **active beta state**. As such, the addon is subject to potential errors in both rotation logic and general functionality. We recommend that users monitor combat closely during use, particularly in high-stakes environments like dungeons or raids. Your feedback is instrumental in refining our modular logic and improving the addon's stability as we continue development.

---

## 🖥️ Key Features 

- **Modular, Lightweight Architecture:** A unified, low-overhead UI shell dynamically loads specialized class modules, ensuring your rotation is optimized for your specific class and talent setup without "bloat".
- **Frame-Perfect Execution:** Designed for the Turtle WoW / SuperWoW environment, the addon monitors combat frame-by-frame. Using strict single-cast priorities and zero-clipping logic, it ensures only one primary action executes per frame to prevent GCD overlap.
- **Intelligent Situational Logic:** Beyond static loops, AutoRota evaluates real-time combat conditions—such as mana, proc availability, and debuff windows—to make smart, fly-by decisions.
- **Turtle WoW & SuperWoW Optimized:** Fully compatible with custom 1.18.1 mechanics, including spell queueing (`QueueSpellByName`), weapon swing timing, and custom class expansions.
- **Locale-Proof Debuff Resolution:** Target debuffs are resolved via precise SuperWoW spell IDs, ensuring upkeep is rank- and locale-proof. Clients without SuperWoW automatically fallback to icon-texture matching.
- **High-Performance Per-Press:** By caching spellbook lookups and snapshots, the addon replaces heavy scanning with high-speed table reads, ensuring responsiveness even during button spam.
- **Flexible Target Acquisition:** By default the engine auto-acquires the nearest enemy when you have no target, but a global `/ar acquire off` (or the minimap options panel) hands targeting back to you or an assist addon — and ranged modules like the Hunter opt out of auto-acquire entirely so they never pull a random mob.
- **User-Centric Configuration:** Includes draggable minimap button control (`/armap` or `/ar minimap`) with a right-click options panel, an intuitive configuration panel, and robust profile management to seamlessly switch between *Leveling*, *PvP*, or *Raid* presets.
- **Spec-Aware Focus:** For the mode-adaptive classes (Mage, Hunter, Shaman), the configuration panel fades and locks the controls for the spec or mode you are *not* currently in — Frost dims Fire and Arcane, Ranged dims Melee, Elemental dims the melee strikes — so you only see the rotation you are actually running.

---

## ⚠️ Included Class Modules (WiP) ⚠️

### 🛡️ Paladin `(Beta)`
Engineered around an intelligent "Roleless Seal Model" optimized for low-level leveling up to high-tier raiding:
- **Debuff Upkeep:** Automatically tracks target judgement debuffs by exact spell name (SuperWoW spell ids, with texture fallback). Applies your chosen *Debuff Seal* (e.g., *Seal of the Crusader* or *Seal of Wisdom*) exactly once per mob, then switches immediately to your *Damage Seal*.
- **Low-Level Safety Guard:** Built-in safeguards automatically bypass the Judgement/Debuff loop if your Paladin is under level 10 and hasn't learned `Judgement` yet, keeping your damage seal active as a permanent auto-attack buff.
- **Hysteresis Resource Management:** Fully configurable independent health and mana safety floors. When triggered, the engine swaps to *Seal of Light* or *Seal of Wisdom* until your resource stabilizes back to your high threshold.
- **Seal Twisting Support:** If enabled, delays damage judgements until precisely `< 0.4s` before your next white swing to combine weapon procs and judgements simultaneously.
- **Talent & Weapon Aware Strikes:** A single *Strike mode* picks how *Holy Strike* and *Crusader Strike* are used — `Off`, `Auto (talent/weapon)`, `Crusader Strike`, `Holy Strike`, or `Holy then Crusader`. **Auto** reads your spec and gear: *Holy Might* is maintained only if you have *Vengeful Strike*, and the Holy-vs-Crusader lean follows *Righteous Strike* or a shield/offhand (threat lean) versus a two-hander (Crusader lean), adjusting live as you swap weapons. *Zeal* is built and kept rolling in every mode.
- **Mana Downranking (opt-in):** *Downrank when low* casts lower ranks of your strikes as raw mana drops, to keep swinging while leveling. Thresholds use absolute mana (not percent), so a full pool stays at top rank and only a near-empty pool steps down, always clamped to your highest known rank.
- **Consecration (opt-in):** An AoE filler cast on cooldown when enabled. Because the 1.12 client cannot reliably count nearby enemies, it is a manual toggle — the *Consecration (AoE)* checkbox, or `/ar aoe` for a quick keybind flip. It sits last in the priority so it never delays your strikes, *Holy Shield*, seal/Judgement upkeep, or *Hammer of Wrath*, and is held during mana recovery.
- **Exorcism (opt-in):** Cast on cooldown, but only against *Undead* and *Demon* targets (checked via creature type), and likewise paused while recovering mana.
- **Heal Mode (`/ar heal on`):** Turns the Paladin into a group healer that still DPSes between heals. It runs even with no attackable target, so it works at range. It picks the most-hurt *reachable* party/raid member (raid- and party-aware), counts its own in-flight heal so it never double-stacks on one target, and **downranks** *Flash of Light* / *Holy Light* to the size of the deficit for mana efficiency — the `+healing` bonus is read automatically from your gear (override with `/ar healpower <n>`) and *Healing Light* / *Divine Favor* talents are factored in. *Holy Shock* is used as an instant for emergencies (below a configurable %) or for a hurt unit out of melee range. The attack rotation yields the global cooldown while anyone needs healing, so a *Seal of Wisdom* judgement never steals a heal's cast. Configure it in the *Healing* panel section or via `/ar healat` and `/ar hsat`.

> **Heal-mode note:** The per-rank heal values and the talent modifiers are best-effort approximations tuned for Turtle, and live in one table at the top of `Class_Paladin.lua` — if downranking picks a rank that over- or under-heals, that is where to adjust. Targeted healing relies on SuperWoW's unit-argument `CastSpellByName`, so it heals the hurt member without dropping your attack target; worth a quick in-party sanity check on 1.18.1.

### 🥷 Rogue `(Beta)`
A refined evolution of the *ExAutoRogue* logic focused on efficient combo point generation and finishing priority:
- **Adaptive Combo Builders:** Automatically chooses your highest efficiency spec builder (*Noxious Assault* if known, falling back to *Sinister Strike*), or allows you to force a fixed weapon builder via a profile dropdown.
- **Finisher Hysteresis Engine:** Dynamically tracks *Slice and Dice* and *Envenom* buffs. It will auto-refresh them efficiently at exactly 1 Combo Point if they are about to expire, otherwise saving points to dump into maximum-damage *Eviscerates*.
- **Reactionary Counters:** Instantaneous out-of-GCD execution for abilities like *Riposte* during active parry windows.
- **Cooldown Automation:** Integrates *Adrenaline Rush* and *Blade Flurry* seamlessly, prioritizing them against Elite or Boss targets.

### ⚔️ Warrior `(Beta)`
A roleless, toggle-driven engine covering Arms, Fury, and Protection from early leveling through endgame raiding. Rather than locking to a spec, you enable the abilities you have and the priority degrades gracefully as you learn them:
- **All-Spec Roleless Design:** One profile schema serves every spec via simple toggles. Abilities you have not learned yet are skipped automatically and flagged as *(not learned)* in the panel, so the same setup keeps working as you level.
- **Stance & Rage Aware Casting:** A warrior-specific gate verifies rage, stance, and cooldown *before* committing to a cast, so a stance- or rage-locked ability can never stall the priority chain. Stance rules follow vanilla 1.12 and stay conservative if Turtle relaxes them.
- **Reactive Proc Windows:** Reads the combat log for target dodges and your own block/dodge/parry to open short windows for *Overpower* (Battle Stance) and *Revenge* (Defensive Stance), mirroring the Rogue's Riposte tracker.
- **Optional Stance Dancing:** An experimental opt-in that auto-swaps to Battle Stance for *Overpower*, then drifts back to your configured home stance, throttled by a swap cooldown to prevent thrashing.
- **Smart Rage Dump:** Queues *Heroic Strike* (or *Cleave* in AoE mode) onto your next swing only above a configurable rage floor, and suppresses it during the *Execute* phase so surplus rage funnels into *Execute*.
- **Cooldown Automation:** *Death Wish*, *Recklessness*, and *Berserker Rage* fire on cooldown, only on Elite/Boss targets, or fully manually — the same three-state model as the other classes — while *Bloodrage* tops up rage on demand, even before the pull.
- **Threat Toolkit:** Maintains *Sunder Armor* up to a chosen stack count and weaves *Shield Slam*, *Revenge*, and *Shield Block* upkeep for Protection tanking.

### 🔮 Warlock `(Beta)`

A full DoT, survival, execute, and pet kit — working from level 1:

* **DoT Priority Engine:** Keeps your enabled damage-over-time effects up in strict priority — *Immolate*, then your chosen Curse, then *Corruption*, then *Siphon Life* — detected by exact spell name (SuperWoW spell ids, with texture fallback), with a per-target landing memory so cast-time DoTs are never double-queued while still in the air.
* **Works from Level 1:** A fresh warlock's only damage is *Shadow Bolt*, so the filler **adapts** — the wand filler falls back to Shadow Bolt when no wand is equipped (and a not-yet-learned spell filler does too), then uses the wand automatically the moment you equip one. The DoTs and curse switch themselves on as they are trained.
* **Survival & Execute (each optional, by priority):** *Drain Life* self-heals when your health dips (drain-tank safety net); *Health Funnel* tops the pet when it drops, as long as your own health is safe; *Shadowburn* instant-executes under a threshold; *Drain Soul* channels in the target's last seconds to bank a Soul Shard. Toggles and percent sliders live in the panel's **Survival** and **Execute** sections.
* **Talent-Aware Nightfall:** AutoRota reads your **talent tree** to detect *Nightfall* and **auto-fires the free instant *Shadow Bolt*** the moment *Shadow Trance* procs — no toggle needed (it stays as a manual override). The proc is spent **once per proc** on the rising edge, so a lingering buff icon never triggers a wasted full-cast Shadow Bolt. Other talented abilities don't need this: *Shadowburn*, *Conflagrate*, *Siphon Life*, and *Drain Soul* appear in your spellbook only when talented, so they're detected for free.
* **Curse Selection:** One curse per target, switchable from the panel or mid-fight with `/ar curse <alias>` (`coa`, `coe`, `cos`, `cow`, `cor`, `cot`, `cod`, `none`).
* **Life Tap Integration:** Triggers *Life Tap* only when mana dips below your threshold **and** health is safely above your floor.
* **Cast Queueing & Pet Support:** Cast-time spells use SuperWoW's `QueueSpellByName` so the rotation never clips a cast (with a smart exception while wanding, where a direct cast fires immediately). A `SPELLCAST_CHANNEL_START/STOP` watcher also **protects your channels** — *Drain Life* and *Drain Soul* can't be clipped by a DoT refresh or the wand on the next press. Optionally sends your pet onto the target, with a **Pet only in melee range** toggle so an accidentally targeted far enemy doesn't pull the pet away.

### 🐾 Druid `(Beta)`

Cat (DPS), Bear (Tank), Balance (Caster/Moonkin), and now **Restoration** (group healer) in one form-adaptive engine — working from level 1:

* **Form-Adaptive Rotation:** Each press follows the form you are actually in — Cat Form runs the DPS rotation, Bear/Dire Bear runs the tank rotation, Moonkin (or a *Caster/Moonkin* preference) runs the Balance rotation, and caster form shifts you into your profile's preferred form (panel dropdown or `/ar form cat|bear|caster`). One profile, one macro, every job.
* **Level 1 and Up:** Before any combat form is learned (Bear at 10, Cat at 20), the caster rotation carries the character — Moonfire upkeep plus Wrath is exactly the right early-leveling loop — and the profile grows into its form automatically the moment it is trained.
* **Balance / Eclipse Weaving:** Keeps *Moonfire* and *Insect Swarm* up, then chain-casts your primary nuke (Wrath or Starfire) to fish for **Eclipse** procs and swaps to the empowered opposite nuke the instant one fires. Nukes are queued through SuperWoW, so spamming never clips a cast — the press during your current cast lines up the buffed spell for the moment the proc window opens. Entering Moonkin (when learned) is automatic for the mana discount.
* **Restoration (Group Healer):** A `resto` spec turns the Druid into a party/raid healer that runs **with no enemy targeted** (so it works at range) and heals via SuperWoW's unit-argument cast without dropping your current target. It picks the most-hurt *reachable* member and **downranks Healing Touch** to the size of the deficit for mana efficiency (counting its own in-flight heal so it never double-stacks, with `+healing` factored through *Gift of Nature*). The full toolkit fires by priority: *Innervate* when low on mana, **Nature's Swiftness → instant max Healing Touch** for a target in real trouble, *Swiftmend* for a no-cast top-up off your own Rejuv/Regrowth, *Regrowth* for a big single-target burst, *Rejuvenation* kept rolling at its best affordable rank, and optional *Wild Growth* (AoE) and *Lifebloom*. When the group is topped it can optionally **weave damage** to use the downtime — *Moonfire* + *Wrath*, toggled with `/ar weave` (off by default, enemy-targeted and mana-gated so it never starves heals). Select it with `/ar form resto` (or `/ar new <name> tree` for a ready-made profile). *(Heals in caster form — the rotation drops any active shapeshift first; **Tree of Life auto-shift is off for now**, pending its 1.18.1 cast rules. The **Restoration** config panel now exposes the full kit — heal threshold, heal power, per-ability toggles with their thresholds (Innervate, Nature's Swiftness, Swiftmend, Regrowth), a Wild Growth toggle + ally-count, Rejuvenation / Lifebloom, and the damage-weave toggle + mana-floor — each greying out when off-spec or not yet learned; the per-rank heal values still live in `Class_Druid.lua`.)*
* **Defensive Bear (HP Management):** Optional hysteresis safety net, same design as the Paladin's resource sliders — drop below your low threshold (default 35%) and the rotation forces Bear Form from **any** form, fires *Frenzied Regeneration* on cooldown, and keeps tanking the mob down behind bear armor; climb back over your high threshold (default 70%) and it releases you to your preferred form automatically. Off by default and inert until Bear Form is learned.
* **Two Turtle Cat Styles:** *Claw & Bleed* keeps *Rake* and *Rip* rolling and builds with *Claw* (pairs with bleed-energy talents like *Ancient Brutality*); *Shred & Powershift* builds with *Shred* and finishes with *Ferocious Bite* for bleed-immune bosses (MC/BWL). Swap mid-fight with `/ar style bleed|shred`.
* **Smart Finishers:** At your combo threshold the bleed style applies *Rip* if it is not ticking and spends *Ferocious Bite* while it is — combo points are never dumped into a redundant bleed.
* **Powershifting (opt-in):** In the Shred style, when energy bottoms out below your slider the rotation shifts to caster and straight back into Cat for a fresh energy bar — and **never while Tiger's Fury is active**, so the buff is not thrown away.
* **Stealth Opener & Upkeep:** Opens from *Prowl* with *Ravage* (auto, if known) or *Pounce*, and keeps *Faerie Fire (Feral)* and *Tiger's Fury* running.
* **Bear Tanking:** *Faerie Fire (Feral)* as the **ranged opener** (instant, 30yd — starts threat + damage on the pull before the mob reaches you), optional **Growl** taunt that grabs threat on the pull and whenever the target stops attacking you (off when you already hold aggro, so solo play never wastes it), *Demoralizing Roar* upkeep, *Maul* as the rage dump, *Swipe* leading under `/ar aoe`, and optional *Enrage* when rage-starved (in combat only — it lowers armor, so it is off by default). *(Moonfire cannot be cast in bear form, so Faerie Fire is the bear's ranged opener.)*
* **Form-Aware Auto-Attack:** The white swing is started automatically in **Cat and Bear** (and never while casting in caster/Moonkin). Note: for this to work in a form, the **Attack** ability must sit on an action-bar slot that the form bar does *not* replace (e.g. a side or bottom bar), or let *SuperCleveRoidMacros* handle attacks.

### 🏹 Hunter `(Beta)`

Reworked for Turtle WoW 1.18.1's hunter changes, with **Auto**, **Ranged**, and **Melee** playstyles selectable per profile (`/ar mode auto|ranged|melee`):

* **Auto (by distance):** The default for new profiles. Picks ranged vs melee each press from your distance to the target (a short stickiness stops it flickering at the boundary), so shots fire at range and strikes fire in melee with no cross-mode bleed. Ideal while leveling, where mobs close fast.
* **Ranged (BM / MM):** Built around the **Auto Shot** backbone with **Steady Shot** (baseline at 20) woven 1:1 after each shot — gated on the exact Auto Shot timing from SuperWoW's `UNIT_CASTEVENT` (interval fallback) so mashing never clips or starves it. *Arcane Shot* / *Multi-Shot* weave as instants. Auto Shot is kept *running* and now **self-unsticks**: if a shot is detected to have stalled it is restarted automatically, instead of needing a manual target swap. Starting Auto Shot is its own press, so it no longer blocks a same-press **Hunter's Mark** or **Sting**.
* **Lock and Load (MM capstone):** *Aimed Shot* is **not** hard-cast on cooldown (that clips Auto Shot). Instead the rotation watches for the **Lock and Load** buff — a crit from Steady/Aimed/Arcane that resets Aimed Shot, drops its cast time, and makes it cleave a line — and fires *Aimed Shot* the instant it procs. A toggle lets you also cast it on cooldown if you prefer.
* **Melee (Survival / BM-melee):** Keeps **Aspect of the Wolf** up, starts melee swings, and runs the priority **Mongoose Bite** (reactively in the window after you dodge) → **Lacerate** (maintained bleed) → **Raptor Strike** on cooldown → optional *Wing Clip*. Under `/ar aoe` it leads with **Carve** (the Survival cone cleave, up to 5 targets). Survival can drop **Immolation Trap** on cooldown (Patch 1.18.1 allows traps in combat). The mana-aspect swap to *Viper* works here too — a mana-heavy melee hunter drops to Viper when low and swaps back to Wolf once recovered.
* **Range-Correct Upkeep:** **Hunter's Mark** is maintained in *both* modes (a universal damage-amp debuff). A **Sting** (*Serpent*, *Scorpid*, or *Viper*, or none — panel or `/ar sting`) is a ranged shot, gated on *actual distance*: it lands on the pull while the target is still out of melee — so even a pure **melee** hunter opens with **Hunter's Mark + Serpent Sting** — and then stops once you close in. Both are applied once per target and refreshed exactly when they fall off (SuperWoW spell-id detection). Stings are Poison-school, so they **auto-skip poison-immune mobs** — *Mechanicals* and *Elementals* are skipped by creature type (no wasted cast), and immune *Undead* / bosses are learned after a single cast and then skipped for that fight.
* **No Errant Pulls:** Being a ranged class, the Hunter does **not** auto-acquire a target — it will not grab and pull a random nearby mob, so you always choose what you are shooting.
* **Aspect Management:** Keeps your combat aspect (Hawk ranged / Wolf melee) up, and can **swap to the mana-regenerating aspect** below a mana threshold, swapping back once recovered (hysteresis so it never flaps).
* **Pet Support:** Pet attack, *Mend Pet* below a health slider, **Kill Command** on cooldown (BM), an optional **Baited Shot** fired in the window after the pet crits, and an optional **Smart Pet Taunt** — when the mob peels onto you, the pet's *Growl* is sent to grab it back (off by default; leave it off for melee-weave builds where you want the aggro).
* **AoE & Cooldowns:** *Volley* leads then *Multi-Shot* fills under `/ar aoe`. *Rapid Fire* and *Bestial Wrath* automate on the usual three-state model — always, elite/boss only, or off.

> **Verification note:** A few 1.18.1 specifics are best-effort and gated by `KnowsSpell`, so an unknown name simply no-ops. If *Kill Command*, *Baited Shot*, the **Lock and Load** buff, or the mana aspect (tried: *Aspect of the Viper*, *Aspect of the Beast*) are not firing, run `/ar debug` and check the exact names — they drop into one place in `Class_Hunter.lua`. Auto mode uses `CheckInteractDistance` (~10yd) as its melee proxy; `/ar trace` shows the effective mode as `mode=auto/melee` or `mode=auto/ranged`.

### ⚡ Shaman `(Beta)`

Enhancement, Elemental, Tank, and now **Restoration** (group healer) in one mode-adaptive engine — working from level 1:

* **Mode-Adaptive Rotation:** Pick **Enhancement** (melee: auto-attack, Stormstrike, Lightning Strike, a shock, with a Lightning Bolt weave), **Elemental** (caster: Flame Shock + Lightning Bolt building Electrify), **Tank** (Earth Shock threat, Stormstrike, Lightning Strike, optional Earthshaker Slam taunt), or **Restoration** (group healer — see below) — panel dropdown or `/ar mode enhancement|elemental|tank|resto`.
* **Restoration (Group Healer):** A `resto` mode turns the Shaman into a party/raid healer that runs **with no enemy targeted** (so it works at range) and heals via SuperWoW's unit-argument cast without dropping your current target. It picks the most-hurt *reachable* member and **downranks Healing Wave** to the size of the deficit for mana efficiency (counting its own in-flight heal so it never double-stacks). Shaman healing is all direct — no HoTs — so the kit fires by priority: *Mana Tide Totem* when low on mana, **Nature's Swiftness-equivalent → instant Healing Wave** for emergencies, **Lesser Healing Wave** for a fast single-target save (which wins over AoE), *Chain Heal* when several are hurt, then downranked *Healing Wave* as the fill. During lulls it keeps **Water Shield** up and refreshes totems on a per-element timer — a *Mana Spring* water staple by default, with earth/fire/air pickers wired and off. It can also optionally **weave damage** in that downtime — *Lightning Bolt*, toggled with `/ar weave` (off by default, enemy-targeted and mana-gated so it never starves heals). Select it with `/ar mode resto`. *(The **Restoration** config panel now exposes the full kit — heal threshold, heal power, per-ability toggles with their thresholds (Mana Tide, Nature's Swiftness, Lesser Healing Wave, Chain Heal), a Maintain-totems master toggle with Water / Earth / Fire / Air pickers, and the damage-weave toggle + mana-floor — each greying out when off-spec or not yet learned; the per-rank heal values still live in `Class_Shaman.lua`.)*
* **Works from Level 1:** A fresh shaman only has *Lightning Bolt* and melee, so the Lightning Bolt filler carries the early levels and everything else — shocks, shields, Stormstrike, Lightning Strike, totems — switches itself on through `KnowsSpell` as it's trained.
* **Talent Automation:** *Stormstrike* and *Lightning Strike* are talent abilities that appear in the spellbook when talented, so they're auto-included when learned (Stormstrike's Nature self-buff is followed by a shock to consume it). *Elemental Focus* grants **no spell** — it's a passive crit proc (Clearcasting, 60% cheaper next spell) — so AutoRota reads the **talent tree** to detect it and surface the proc, the same approach used for the Warlock's Nightfall.
* **Shield & Shock:** Keeps your chosen shield up (*Lightning* for damage/threat, *Water* for mana) and casts one shock on the shared cooldown — *Flame Shock* maintained as a DoT, *Earth/Frost* on cooldown. Switch with `/ar shield` and `/ar shock`.
* **Totems & Cooldowns:** Optional *Searing Totem* upkeep (timer-based), plus *Elemental Mastery* and self-*Bloodlust* pops.

> **Verification note:** Buff/proc names are best-effort — confirm the **Clearcasting** proc, the **Stormstrike** self-buff, and the **Searing Totem** / **Earthshaker Slam** spell names in-game with `/ar talents` and `/ar debug` if anything isn't firing; the talent name sits in one constant in `Class_Shaman.lua`. For **Restoration**, the same applies to the **Nature's Swiftness-equivalent** (tries `Nature's Swiftness`, then `Ancestral Swiftness`), **Mana Tide Totem**, and the **totem names** in the picker tables — and the heal rank values are vanilla baselines, with the totem re-drop intervals (55s water / 110s others) likely wanting a tune to Turtle's durations.

### 🌟 Priest `(Beta)`

Shadow/leveling damage and Discipline/Holy healing in one module, switched by a single toggle — working from level 1:

* **Two Modes, One Toggle:** with *Heal mode* **off** the priest runs the **shadow/leveling damage** rotation; with it **on** (`/ar heal on`, or the panel) it becomes a **group healer that weaves damage between heals**. Heal mode runs even with no attackable target, so it works at range.
* **Leveling & the 5-Second Rule:** *Mind Blast* on cooldown (the pull and the *Shadow Weaving* trigger), *Shadow Word: Pain* and (Undead) *Devouring Plague* kept rolling, *Holy Fire* when out of Shadowform — then the **wand carries the filler while mana regenerates**. AutoRota is a rotation engine, not a HUD, so it *acts* on the five-second rule rather than drawing a timer: when mana drops below a configurable floor the filler falls back to the wand (`/ar filler wand|flay|smite`) so the priest never casts itself dry. A **Use wand** checkbox toggles wand-weaving off entirely (the priest then keeps casting and won't wand to regen), and if **no wand is equipped** it automatically fills with *Mind Flay* or *Smite* instead — so the wand is never a dead press.
* **Spirit Tap Finisher:** under a configurable target-health %, the rotation bursts with *Mind Blast* then *Smite* to **secure the killing blow** — and the experience that feeds *Spirit Tap*.
* **Mitigation, Not Over-Bubbling:** *Power Word: Shield* is cast when a mob reaches melee or you drop below half health — and it is **gated on *Weakened Soul*** in every mode, so it never wastes a cast trying to re-shield through the debuff.
* **Shadow (endgame):** hold *Shadowform* (which auto-skips every Holy cast), open *Mind Blast* for *Shadow Weaving*, keep the DoTs up, and fill with channelled *Mind Flay*. **Turn *Shadow Word: Pain* off for raids** to respect debuff-slot limits — *Mind Blast* and *Mind Flay* then carry the damage.
* **Responsive Healing (Disc/Holy):** healing is triage, not a fixed rotation. AutoRota picks the most-hurt *reachable* party/raid member and **downranks** *Heal* / *Greater Heal* / *Flash Heal* to the size of the deficit for mana efficiency (the `+healing` bonus is read from gear, override `/ar healpower <n>`; *Spiritual Healing* is factored in). *Flash Heal* is **reserved for emergencies** (a target near death, `/ar flashat <%>`), *Greater Heal* covers big deficits, *Heal* the efficient sustained healing, and *Renew* / *Power Word: Shield* maintain a mildly hurt unit. *Prayer of Healing* fires when several members are hurt, **fronted by *Inner Focus*** (when ready) to negate its mana cost.
* **Offensive Weave & Lightwell:** between heals it can weave *Smite* / *Holy Fire* as offensive support (for *Enlighten*-style talents), and place *Lightwell* when out of combat.

> **Verification note:** Heal values are tuned approximations — the rank tables sit at the top of `Class_Priest.lua`; adjust them if downranking over- or under-heals. The *Shadow Weaving* / proc behaviour and the exact *Enlighten* mechanic are best-effort, so confirm names in-game with `/ar talents` and `/ar debug` if anything isn't firing. Healing and the no-target-drop heal cast rely on SuperWoW's unit-arg casting. *(Multi-target Shadow spreads its DoTs as you tab between mobs; the engine is single-target by design and does not tab for you.)*

---

### 🪄 Mage `(Beta)`

Frost, Fire, and Arcane in one mode-adaptive module, working from level 1 to raiding — switch specs live with `/ar mode frost|fire|arcane`:

* **Three Specs, One Button:** **Frost** (the kiting / *Icicles* spec and best leveler), **Fire** (Scorch debuff + Fireball burst), or **Arcane** (Rupture upkeep + Arcane Missiles). The panel *Spec* dropdown or `/ar mode` switches between them; every ability is *KnowsSpell*-gated, so a level 1 mage (Fireball, then Frostbolt at ~4) plays correctly and each spell switches itself on as it is trained.
* **Frost — Kite & Icicles:** *Frostbolt* nuke, *Frost Nova* to root a mob that reaches melee (so you step back and wand), *Cone of Cold* as a close-range slow, and *Ice Barrier* kept up (a shield that also boosts Frost damage). *Icicles* is cast whenever its cooldown is up — the Turtle freeze-reset is handled implicitly: *Frostbite* / *Flash Freeze* keep resetting that cooldown, so the engine fires Icicles in the empowered window automatically. On freeze-immune bosses this lands as `Frost Nova ➔ Icicles ➔ Frostbolt`.
* **Fire — Debuff & Burst:** *Combustion* on cooldown, *Pyroblast* as a **pull-only opener** (gated to a near-full-health target so it is never a 6-second cast stuck mid-fight), *Scorch* to build and maintain the *Fire Vulnerability* debuff to a configurable stack count, *Fire Blast* on cooldown (the instant / movement / finisher tool), then *Fireball*. A per-target Scorch throttle means *Fireball* still fills if the debuff can't be read.
* **Arcane — Haste & Upkeep:** keep *Arcane Rupture* on the target, pop *Arcane Power* on cooldown, use *Arcane Surge* **while not hasted** (it is skipped under Arcane Power / MQG, whose haste does not scale its 1.5s GCD), and fill with *Arcane Missiles*.
* **Leveling "Nuke then Wand":** the golden rule of Vanilla mage leveling — nuke a mob to ~30–50% then **wand it to death** to conserve mana. Below a target-health threshold (default 40%, `/ar wandhp <0-100>`) or a mana floor the rotation finishes with the wand; a **Use wand** toggle and the no-wand auto-fallback mirror the Priest. The `frost` / `fire` / `arcane` presets set wand-finish to 0% for pure caster / raid play.
* **AoE Mode (`/ar aoe`):** kite-AoE — *Frost Nova* to freeze, *Cone of Cold* to snare, *Icicles*, then *Arcane Explosion* to finish. *Evocation* restores mana when low (in combat, target not about to die), and channels (*Arcane Missiles*, *Icicles*, *Blizzard*, *Evocation*) are never clipped.

> **Verification note:** Turtle's custom spells were confirmed by exact name against the client spell DB (*Icicles*, *Arcane Rupture*, *Arcane Surge*, *Flash Freeze*, *Fire Vulnerability*), but their **proc / stack behaviour is best-effort** — confirm the *Fire Vulnerability* stack debuff, the *Arcane Rupture* buff-vs-debuff, and the MQG haste-buff name in-game with `/ar debug` if something isn't firing. The precise *Frost Nova* / *Cone of Cold* weaving for maximum *Flash Freeze* procs on bosses is a manual micro-optimization the engine approximates by casting *Icicles* on cooldown. **Ground-targeted AoE (*Blizzard*, *Flamestrike*) is not auto-cast** — it needs a cursor click a one-button rotation can't place.

---

## ⚙️ Installation

1. Download the `AutoRota` folder.
2. Place the folder directly into your World of Warcraft directory under: `Interface\AddOns\`
   *(Ensure the folder name matches the `.toc` file exactly: `Interface\AddOns\AutoRota\`)*
3. Log into the game. Make sure "Load OutofDate AddOns" is checked if prompted.

> **Note:** The `AutoRota` folder includes an `Icons\` subfolder holding the addon's bundled textures (e.g. the config window's help-button icon). Keep it intact — if you copy files by hand, make sure `Icons\` and its contents come along.

### ⚠️ Required
* :crystal_ball: **`SuperWoW (v1.5.1)`**
  Unlocks advanced client capabilities and expanded Lua functionality for modern addons.
  ↳ [SuperWoW Release](https://github.com/balakethelock/SuperWoW/releases/tag/Release) | [SuperAPI Addon](https://github.com/balakethelock/SuperAPI)

* :zap: **`NamPower (v4.6.1)`**
  Handles text enhancement and native spell-queuing for smoother combat rotations.
  ↳ [Nampower Release](https://gitea.com/avitasia/nampower/releases/tag/v4.6.1) | [Nampower Addon](https://gitea.com/avitasia/nampowersettings)

* 🔋 **`UnitXP_SP3 (v89 Stable)`**
  UnitXP Service Pack 3 Allows custom addons to accurately detect if players or enemies are in your line of sight or out of range.
  ↳ [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3/releases)

* 🏗️ **`SuperCleveRoid Macros`**
  Enhanced macro addon for World of Warcraft 1.12.1 (Vanilla/Turtle WoW) with dynamic tooltips, conditional execution, and extended syntax.
  ↳ [SuperCleveRoidMacros](https://github.com/jrc13245/SuperCleveRoidMacros) | [SuperCleveRoid Macro Wiki](https://github.com/jrc13245/SuperCleveRoidMacros/wiki)

Note: It is recommended to use the `SuperCleveRoidMacros` (SCRM) addon, but this is not required.

---

## Commands & Usage

AutoRota is designed to be mapped directly to a spammable macro on your action bar.

### The Combat Macro

## ⚔️ The Ultimate Combat Macro
Because all configuration logic is handled by the visual interface and database, your in-game macro is now completely streamlined down to a single line:
```macro
/ar
```

> #### 🗡️ Melee classes: put **Attack** on an action bar
> For melee classes (Paladin, Rogue, Warrior, and Druid in Cat/Bear form), AutoRota keeps your white swing going by toggling the standard **Attack** ability — but it can only do this if that ability is on one of your action bars. Open your spellbook (**P**), find **Attack** in the *General* tab, and drag it onto any free action slot. Without it, the rotation will fire abilities but you may notice you are not auto-attacking between them.
>
> **Druids, read this:** shapeshifting into Cat or Bear form **replaces your main action bar** with the form bar, so **Attack** must sit on a bar that stays visible while shifted — the right-side vertical bars or the bottom-right bar, **not** the main bar (slots 1–12). If it is only on the main bar, you will see the rotation taunt and use abilities but the white swing will not start in form.
>
> *Exception:* if you run **SuperCleveRoidMacros**, AutoRota leaves auto-attack handling to SCRM and skips this step.

> #### 🏹 Hunter: put **Auto Shot** on an action bar
> AutoRota keeps your **Auto Shot** firing between instants. It detects the shot most reliably when **Auto Shot** is on one of your action bars, so drag it there from your spellbook (**P** → *General* tab). If you enable the **melee weave** option, also place **Attack** on a bar so *Raptor Strike* has white swings to ride.

## 🔨 Configuration & Settings
To open the comprehensive configuration interface, manage profiles, adjust resource sliders, or toggle specific spells on or off, type:
```macro
/ar ui
```
---

### Slash Command Line Interface (CLI)
You can also change profile properties dynamically via chat or macros:

| Command | Description | Example |
| :--- | :--- | :--- |
| `/ar list` | Lists all saved configuration profiles. | `/ar list` |
| `/ar use <name>` | Instantly switches to the specified profile. | `/ar use Leveling` |
| `/ar off` | Pauses/disables rotation execution. | `/ar off` |
| `/ar new <name> [template]` | Creates a new profile from a class template. | `/ar new Raid fury` |
| `/ar del <name>` | Deletes a saved profile. | `/ar del Raid` |
| `/ar check` | Reports whether the active profile is valid for your learned spells. | `/ar check` |
| `/ar reset` | Reseeds the profile list from the class templates and deactivates. | `/ar reset` |
| `/ar debug` | Dumps target debuffs (name / stacks / texture) and your player buffs. | `/ar debug` |
| `/ar talents` | Dumps every talent tab and talent with its current rank (ranked ones highlighted), to confirm exact talent names. | `/ar talents` |
| `/ar trace` | Toggles detailed combat logic debugging. | `/ar trace` |
| `/ar acquire <on/off>` | Global toggle: auto-acquire the nearest enemy when you have no target (also on the minimap right-click panel). Off lets an assist addon pick your target. | `/ar acquire off` |
| `/armap` or `/ar minimap` | Hides or shows the minimap button. Right-click the button for the options panel. | `/ar minimap` |
| `/ar cp <1-5>` | *(Rogue Only)* Sets min. finishing Combo Points. | `/ar cp 5` |
| `/ar seal <profile> <debuff/damage> <alias>` | *(Paladin Only)* Sets a seal slot on the named profile. | `/ar seal DPS damage sor` |
| `/ar strike <mode>` | *(Paladin Only)* Sets strike mode (`off`/`auto`/`cs`/`hs`/`hscs`). | `/ar strike hs` |
| `/ar heal <on/off>` | *(Paladin & Priest)* Toggles heal mode (group healer that weaves damage between heals; works at range). | `/ar heal on` |
| `/ar healat <1-100>` | *(Paladin & Priest)* Heals group members below this % health. | `/ar healat 85` |
| `/ar hsat <1-100>` | *(Paladin Only)* Health % under which *Holy Shock* is used as an instant emergency heal. | `/ar hsat 50` |
| `/ar flashat <1-100>` | *(Priest Only)* Health % under which *Flash Heal* is allowed as an emergency heal. | `/ar flashat 40` |
| `/ar filler <wand/flay/smite>` | *(Priest Only)* Sets the DPS filler — wand conserves mana (the 5-second rule); Mind Flay / Smite spend it. | `/ar filler wand` |
| `/ar healpower <n>` | *(Paladin & Priest)* Manual +healing override for downranking (0 = auto-read from gear). | `/ar healpower 0` |
| `/ar curse <alias>` | *(Warlock Only)* Switches the curse on the active profile. | `/ar curse coe` |
| `/ar mode <…>` | *(Hunter, Shaman & Mage)* Switches playstyle/spec — Hunter: `auto/ranged/melee`, Shaman: `enhancement/elemental/tank/resto`, Mage: `frost/fire/arcane`. | `/ar mode frost` |
| `/ar sting <alias>` | *(Hunter Only)* Sets the maintained sting (`serpent`/`scorpid`/`viper`/`none`). | `/ar sting serpent` |
| `/ar style <bleed/shred>` | *(Druid Only)* Switches the cat style mid-fight. | `/ar style shred` |
| `/ar form <cat/bear/caster/resto>` | *(Druid Only)* Sets the preferred form/spec (caster = Balance/Moonkin, resto = group healer). | `/ar form resto` |
| `/ar weave <on/off>` | *(Druid & Shaman, resto only)* Weave damage between heals during downtime — trades mana for DPS when nobody needs healing. | `/ar weave on` |
| `/ar aoe` | *(Warrior, Paladin, Druid, Hunter & Mage)* Toggles AoE mode (Cleave + Whirlwind / Consecration / Swipe / Volley + Multi-Shot / Frost Nova + Cone of Cold + Arcane Explosion). | `/ar aoe` |
| `/ar wandhp <0-100>` | *(Mage Only)* Target-health % under which the rotation finishes the mob with the wand (0 = off, cast to death). | `/ar wandhp 40` |
| `/ar cd <on/elite/off>` | *(Warrior & Hunter)* Sets cooldown usage mode. | `/ar cd elite` |
| `/ar dance` | *(Warrior Only)* Toggles experimental stance dancing. | `/ar dance` |
| `/ar spell <alias> <on/off>` | *(Warrior & Hunter)* Flips an ability on the active profile. Paladin uses `/ar spell <profile> <alias> <on/off>`. | `/ar spell ms on` |

### Paladin Seal Aliases
When using the /ar seal command, you can use short aliases:

  * `sotc` / `crusader` → `Seal of the Crusader`
  * `sor` / `righteousness` → `Seal of Righteousness`
  * `soc` / `command` → `Seal of Command`
  * `sow` / `wisdom` → `Seal of Wisdom`
  * `sol` / `light` → `Seal of Light`
  * `none` → `Clears slot`

# Combat Utility Macros:

## Paladin Combat Toggles:

You can maintain a single spammable combat macro while using separate keybinds to hot-swap seals during an encounter:

  * `/ar seal <profile> debuff <alias>` : Updates your current rotation debuff mid-fight.

  * `/ar seal <profile> damage <alias>` : Updates your current rotation damage seal mid-fight.

  * `/ar strike <mode>` : Switches strike mode on the active profile mid-fight — `off`, `auto`, `cs`, `hs`, or `hscs` (Holy then Crusader). Handy for binding a tank/leveling style to a key.

## Warrior Combat Toggles:

The Warrior module adds quick toggles you can bind to separate keys to adjust the rotation mid-fight without opening the panel:

  * `/ar aoe` : Toggles AoE mode (rage dump becomes *Cleave*, *Whirlwind* used on cooldown).

  * `/ar cd on|elite|off` : Sets cooldown usage to always, Elite/Boss only, or fully manual.

  * `/ar dance` : Toggles experimental stance dancing for *Overpower*.

  * `/ar spell <alias> on|off` : Flips an individual ability on the active profile (e.g., `/ar spell bt off`).

### Warrior Spell Aliases
When using the /ar spell command, you can use short aliases:

  * `ms` / `mortalstrike` → `Mortal Strike`
  * `bt` / `bloodthirst` → `Bloodthirst`
  * `ss` / `shieldslam` → `Shield Slam`
  * `ww` / `whirlwind` → `Whirlwind`, `slam` → `Slam`
  * `op` / `overpower` → `Overpower`, `rev` / `revenge` → `Revenge`, `exec` / `execute` → `Execute`
  * `sa` / `sunder` → `Sunder Armor`, `tc` / `thunderclap` → `Thunder Clap`
  * `hs` / `heroicstrike` → `Heroic Strike`, `cleave` → `Cleave`, `sweep` / `sweeping` → `Sweeping Strikes`
  * `dw` / `deathwish` → `Death Wish`, `reck` / `recklessness` → `Recklessness`, `br` / `berserkerrage` → `Berserker Rage`
  * `bld` / `bloodrage` → `Bloodrage`, `sb` / `shieldblock` → `Shield Block`

## Hunter Combat Toggles:

The Hunter module adds quick toggles you can bind to separate keys to adjust the rotation mid-fight without opening the panel:

  * `/ar mode auto|ranged|melee` : Switches the hunter playstyle. Auto picks ranged vs melee by distance to the target; ranged = BM/MM, melee = Survival/BM.

  * `/ar sting serpent|scorpid|viper|none` : Switches the maintained sting on the active profile.

  * `/ar aoe` : Toggles AoE mode (*Volley* leads, then *Multi-Shot* fills).

  * `/ar cd on|elite|off` : Sets cooldown usage (*Rapid Fire*, *Bestial Wrath*) to always, Elite/Boss only, or fully manual.

  * `/ar spell <alias> on|off` : Flips an individual ability on the active profile (e.g., `/ar spell aimed on`).

### Hunter Spell Aliases
When using the /ar spell command, you can use short aliases:

  * `mark` / `hm` → *Hunter's Mark*, `steady` / `st` → *Steady Shot*
  * `arcane` / `as` → *Arcane Shot*, `multi` / `ms` → *Multi-Shot*, `aimed` / `aim` → *Aimed Shot*
  * `volley` → *Volley*, `immolation` / `trap` → *Immolation Trap*
  * `raptor` / `rs` → *Raptor Strike*, `mongoose` / `mb` → *Mongoose Bite*, `lacerate` / `lac` → *Lacerate*, `carve` → *Carve*, `wingclip` / `wc` → *Wing Clip*
  * `aspect` → keep combat aspect up, `killcommand` / `kc` → *Kill Command*, `baited` → *Baited Shot*, `mend` → *Mend Pet*

### Hunter Sting Aliases
When using the /ar sting command, you can use short aliases:

  * `serpent` / `ss` → `Serpent Sting`
  * `scorpid` / `sco` → `Scorpid Sting`
  * `vs` / `viper` → `Viper Sting`
  * `none` → `Clears slot`

---

## 🚩 Troubleshooting & False Positives
MacroErrorChecker / UI Warning Messages
If you use macro validation addons like MacroErrorChecker, you may see a warning in chat on login stating: L3: Unknown command: /ar.

This is a false positive. External macro checkers look for a static list of default Blizzard interface commands. They cannot scan third-party custom slash engines. As long as typing /ar ui opens your addon profile window, AutoRota is working perfectly and you can safely ignore or disable the validation warning. This can be added to the whitelist with some addons like `SuperCleveRoidMacros` to avoid the chat error.

### My character casts abilities but doesn't auto-attack
On a melee class, AutoRota starts your white swing by toggling the standard **Attack** ability, which it locates by scanning your action bars. If **Attack** is not on any bar, there is nothing for it to toggle and you will fire abilities without swinging in between. Drag **Attack** from your spellbook (**P** → *General* tab) onto any action slot. (If you use **SuperCleveRoidMacros**, it manages attacks instead and AutoRota leaves this alone.)
