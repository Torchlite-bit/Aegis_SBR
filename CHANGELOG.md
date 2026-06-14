# 📜 Changelog

All notable changes to **AutoRota** are documented here. Versions are listed newest first.

---

## v0.7.0b — Hunter Module & Spell-ID Debuff Detection

Adds the sixth class module, **Hunter**, and replaces the addon's icon-fragment
debuff detection with exact **SuperWoW spell-id** matching across every class.

### 🏹 Added: Hunter (Beta)
- A ranged-priority engine built around **Auto Shot**. Auto Shot is a toggle, so it is kept running rather than recast every press — a press that fires an instant never stops the shot. When Auto Shot is on an action bar it is detected via `IsAutoRepeatAction`; when it is not, an assumed-on flag per target prevents accidentally toggling it off, and leaving combat resets it.
- **Priority:** Mend Pet when the pet drops below your slider → *Aspect of the Hawk* upkeep → *Hunter's Mark* → the chosen *Sting* → AoE (*Volley* then *Multi-Shot* when `/ar aoe` is on) → melee weave → *Multi-Shot* → *Arcane Shot* → *Aimed Shot* (queued so it never clips). One GCD ability per press, off-GCD layers (pet attack, *Rapid Fire* / *Bestial Wrath*) fire and continue.
- **One sting slot** (Serpent / Scorpid / Viper / none), switchable from the panel or `/ar sting serpent|scorpid|viper|none`. Stings and *Hunter's Mark* are applied once per target and refreshed only when they fall off.
- **Melee weave (opt-in):** when the target is in melee range, melee auto-attack is started and *Raptor Strike* is used, so a mob in your face still takes hits instead of standing in the ranged dead zone.
- **Cooldown automation** (always / elite only / off) for *Rapid Fire* and *Bestial Wrath*, the same three-state model as the other classes, plus four templates: `starter`, `marksmanship`, `beastmastery`, `survival`.

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
