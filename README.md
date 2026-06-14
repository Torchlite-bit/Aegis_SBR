# AutoRota (v0.7.0b)

AutoRota is a lightweight, robust, Configurable one-button rotation, multi class (Turtle WoW 1.12 / SuperWoW). Unlike standard "monolithic" 1.12 macros or basic script loops, AutoRota uses a modern modular architecture, automated frame-by-frame management, and smart situational logic to execute combat rotations.

Version 0.4 introduces a complete graphical configuration panel and database system, moving configuration options out of your macros and into a clean visual window.

---

## 🖥️ Features

- **Multi-Class Architecture:** A unified, lightweight UI shell dynamically swaps control panels and rotation rules based on the class you are currently playing.
- **Smart Profile Management:** Create, save, rename, and activate multiple custom setup profiles (e.g., *Starter*, *Leveling*, *PvP*, *Raid-DPS*) seamlessly in-game.
- **Turtle WoW & SuperWoW Optimized:** Fully compatible with custom SuperWoW features such as spell queueing (`QueueSpellByName`), weapon swing timing, and custom custom class expansions (e.g., Rogue's *Noxious Assault*, Paladin's *Holy Strike*).
- **Exact Debuff Detection:** Target debuffs are resolved to their precise spell name via SuperWoW spell ids (built once per press in the core), so upkeep is rank- and locale-proof for every class. Clients without SuperWoW fall back automatically to icon-texture matching.
- **Zero-Clipping Logic:** Rotations run on strict single-cast priorities with early returns. The addon ensures exactly one primary action executes per frame to prevent spell clipping or overlapping global cooldowns (GCD).
- **Lightweight Per-Press Cost:** Spellbook lookups, profile validity, the auto-attack button, player buffs, and target debuffs are all cached or snapshotted (and refreshed automatically when you learn spells or edit profiles), so spamming the macro costs a handful of table reads instead of repeated full spellbook, action-bar, buff, and debuff scans.
- **Minimap Button:** A draggable minimap button opens the configuration panel with a click (right-click runs the rotation once). Hide or show it with `/armap`.

---

## ⚠️ Included Class Modules (WiP)

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

Optimized for efficient DoT upkeep and resource management:

* **DoT Priority Engine:** Keeps your enabled damage-over-time effects up in strict priority — *Immolate*, then your chosen Curse, then *Corruption*, then *Siphon Life* — detected by exact spell name (SuperWoW spell ids, with texture fallback), with a per-target landing memory so cast-time DoTs are never double-queued while still in the air. Every curse is now tracked precisely, not just the ones with a hand-verified icon.
* **Curse Selection:** One curse per target, switchable from the panel or mid-fight with `/ar curse <alias>` (`coa`, `coe`, `cos`, `cow`, `cor`, `cot`, `cod`, `none`).
* **Life Tap Integration:** Hysteresis-style management that triggers *Life Tap* only when mana dips below your threshold **and** health is safely above your floor.
* **Configurable Filler:** When every enabled DoT is up — wand (mana-free), *Shadow Bolt*, or *Drain Life*. A *Nightfall* option fires the free instant *Shadow Bolt* the moment *Shadow Trance* procs.
* **Cast Queueing & Pet Support:** Cast-time spells use SuperWoW's `QueueSpellByName` so the rotation never clips a cast (with a smart exception while wanding, where a direct cast fires immediately). Optionally sends your pet onto the target every press.

### 🐾 Druid `(Beta)`

Cat (DPS), Bear (Tank), and Balance (Caster/Moonkin) in one form-adaptive engine — working from level 1:

* **Form-Adaptive Rotation:** Each press follows the form you are actually in — Cat Form runs the DPS rotation, Bear/Dire Bear runs the tank rotation, Moonkin (or a *Caster/Moonkin* preference) runs the Balance rotation, and caster form shifts you into your profile's preferred form (panel dropdown or `/ar form cat|bear|caster`). One profile, one macro, every job.
* **Level 1 and Up:** Before any combat form is learned (Bear at 10, Cat at 20), the caster rotation carries the character — Moonfire upkeep plus Wrath is exactly the right early-leveling loop — and the profile grows into its form automatically the moment it is trained.
* **Balance / Eclipse Weaving:** Keeps *Moonfire* and *Insect Swarm* up, then chain-casts your primary nuke (Wrath or Starfire) to fish for **Eclipse** procs and swaps to the empowered opposite nuke the instant one fires. Nukes are queued through SuperWoW, so spamming never clips a cast — the press during your current cast lines up the buffed spell for the moment the proc window opens. Entering Moonkin (when learned) is automatic for the mana discount.
* **Defensive Bear (HP Management):** Optional hysteresis safety net, same design as the Paladin's resource sliders — drop below your low threshold (default 35%) and the rotation forces Bear Form from **any** form, fires *Frenzied Regeneration* on cooldown, and keeps tanking the mob down behind bear armor; climb back over your high threshold (default 70%) and it releases you to your preferred form automatically. Off by default and inert until Bear Form is learned.
* **Two Turtle Cat Styles:** *Claw & Bleed* keeps *Rake* and *Rip* rolling and builds with *Claw* (pairs with bleed-energy talents like *Ancient Brutality*); *Shred & Powershift* builds with *Shred* and finishes with *Ferocious Bite* for bleed-immune bosses (MC/BWL). Swap mid-fight with `/ar style bleed|shred`.
* **Smart Finishers:** At your combo threshold the bleed style applies *Rip* if it is not ticking and spends *Ferocious Bite* while it is — combo points are never dumped into a redundant bleed.
* **Powershifting (opt-in):** In the Shred style, when energy bottoms out below your slider the rotation shifts to caster and straight back into Cat for a fresh energy bar — and **never while Tiger's Fury is active**, so the buff is not thrown away.
* **Stealth Opener & Upkeep:** Opens from *Prowl* with *Ravage* (auto, if known) or *Pounce*, and keeps *Faerie Fire (Feral)* and *Tiger's Fury* running.
* **Bear Tanking:** *Faerie Fire* and *Demoralizing Roar* upkeep, *Maul* as the single-target rage dump, *Swipe* leading the priority when AoE mode is toggled (`/ar aoe`), and optional *Enrage* when rage-starved (in combat only — it lowers armor, so it is off by default).

### 🏹 Hunter `(Beta)`

A ranged-priority engine built around **Auto Shot**, with optional melee weave and pet support:

* **Auto Shot Upkeep:** Auto Shot is a toggle, so the rotation keeps it *running* rather than recasting it each press — an instant fired between shots never stops it. Detected via `IsAutoRepeatAction` when it is on a bar, with an assumed-on safeguard per target when it is not, so it is never accidentally toggled off.
* **Shot Priority:** Mend Pet (below your slider) → *Aspect of the Hawk* upkeep → *Hunter's Mark* → your chosen *Sting* → AoE → *Multi-Shot* → *Arcane Shot* → *Aimed Shot*. Exactly one GCD ability per press; off-GCD cooldowns and pet attack fire and continue. *Aimed Shot* is queued through SuperWoW so it never clips the current shot.
* **One Sting Slot:** *Serpent*, *Scorpid*, or *Viper* (or none), from the panel or `/ar sting serpent|scorpid|viper|none`. Stings and *Hunter's Mark* are applied once per target and refreshed only when they fall off.
* **Melee Weave (opt-in):** When the target is in melee range, melee auto-attack starts and *Raptor Strike* is used, so a mob in your face still takes hits instead of standing in the ranged dead zone.
* **AoE & Cooldowns:** *Volley* leads then *Multi-Shot* fills when AoE mode is on (`/ar aoe`). *Rapid Fire* and *Bestial Wrath* automate on the usual three-state model — always, elite/boss only, or off.
* **Pet Support:** Sends the pet to attack each press and heals it with *Mend Pet* when it drops below your configured health percent.

---

## ⚙️ Installation

1. Download the `AutoRota` folder.
2. Place the folder directly into your World of Warcraft directory under: `Interface\AddOns\`
   *(Ensure the folder name matches the `.toc` file exactly: `Interface\AddOns\AutoRota\`)*
3. Log into the game. Make sure "Load OutofDate AddOns" is checked if prompted.

### ⚠️ Required
* :crystal_ball: **`SuperWoW (v1.5.1)`**
  Unlocks advanced client capabilities and expanded Lua functionality for modern addons.
  ↳ [SuperWoW Release](https://github.com/balakethelock/SuperWoW/releases/tag/Release) | [SuperAPI Addon](https://github.com/balakethelock/SuperAPI)

* :zap: **`NamPower (v4.6.1)`**
  Handles text enhancement and native spell-queuing for smoother combat rotations.
  ↳ [Nampower Release](https://gitea.com/avitasia/nampower/releases/tag/v4.6.1) | [Nampower Addon](https://gitea.com/avitasia/nampowersettings)

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
> For melee classes (Paladin, Rogue, Warrior), AutoRota keeps your white swing going by toggling the standard **Attack** ability — but it can only do this if that ability is on one of your action bars. Open your spellbook (**P**), find **Attack** in the *General* tab, and drag it onto any free action slot. Without it, the rotation will fire abilities but you may notice you are not auto-attacking between them.
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
| `/ar trace` | Toggles detailed combat logic debugging. | `/ar trace` |
| `/armap` | Hides or shows the minimap button. | `/armap` |
| `/ar cp <1-5>` | *(Rogue Only)* Sets min. finishing Combo Points. | `/ar cp 5` |
| `/ar seal <profile> <debuff/damage> <alias>` | *(Paladin Only)* Sets a seal slot on the named profile. | `/ar seal DPS damage sor` |
| `/ar strike <mode>` | *(Paladin Only)* Sets strike mode (`off`/`auto`/`cs`/`hs`/`hscs`). | `/ar strike hs` |
| `/ar curse <alias>` | *(Warlock Only)* Switches the curse on the active profile. | `/ar curse coe` |
| `/ar sting <alias>` | *(Hunter Only)* Sets the maintained sting (`serpent`/`scorpid`/`viper`/`none`). | `/ar sting serpent` |
| `/ar style <bleed/shred>` | *(Druid Only)* Switches the cat style mid-fight. | `/ar style shred` |
| `/ar form <cat/bear/caster>` | *(Druid Only)* Sets the preferred combat form (caster = Balance/Moonkin). | `/ar form caster` |
| `/ar aoe` | *(Warrior, Paladin, Druid & Hunter)* Toggles AoE mode (Cleave + Whirlwind / Consecration / Swipe / Volley + Multi-Shot). | `/ar aoe` |
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

  * `/ar sting serpent|scorpid|viper|none` : Switches the maintained sting on the active profile.

  * `/ar aoe` : Toggles AoE mode (*Volley* leads, then *Multi-Shot* fills).

  * `/ar cd on|elite|off` : Sets cooldown usage (*Rapid Fire*, *Bestial Wrath*) to always, Elite/Boss only, or fully manual.

  * `/ar spell <alias> on|off` : Flips an individual ability on the active profile (e.g., `/ar spell aimed on`).

### Hunter Spell Aliases
When using the /ar spell command, you can use short aliases:

  * `mark` / `hm` → `Hunter's Mark`
  * `arcane` / `as` → `Arcane Shot`, `multi` / `ms` → `Multi-Shot`, `aimed` / `aim` → `Aimed Shot`
  * `volley` → `Volley`, `aspect` / `hawk` → `Aspect of the Hawk`
  * `raptor` / `rs` → `Raptor Strike`, `mend` → `Mend Pet`

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
