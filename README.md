# AutoRota (v0.5b)

AutoRota is a lightweight, robust, Configurable one-button rotation, multi class (Turtle WoW 1.12 / SuperWoW). Unlike standard "monolithic" 1.12 macros or basic script loops, AutoRota uses a modern modular architecture, automated frame-by-frame management, and smart situational logic to execute combat rotations.

Version 0.4 introduces a complete graphical configuration panel and database system, moving configuration options out of your macros and into a clean visual window.

---

## 🖥️ Features

- **Multi-Class Architecture:** A unified, lightweight UI shell dynamically swaps control panels and rotation rules based on the class you are currently playing.
- **Smart Profile Management:** Create, save, rename, and activate multiple custom setup profiles (e.g., *Starter*, *Leveling*, *PvP*, *Raid-DPS*) seamlessly in-game.
- **Turtle WoW & SuperWoW Optimized:** Fully compatible with custom SuperWoW features such as spell queueing (`QueueSpellByName`), weapon swing timing, and custom custom class expansions (e.g., Rogue's *Noxious Assault*, Paladin's *Holy Strike*).
- **Zero-Clipping Logic:** Rotations run on strict single-cast priorities with early returns. The addon ensures exactly one primary action executes per frame to prevent spell clipping or overlapping global cooldowns (GCD).
- **Minimap Button:** A draggable minimap button opens the configuration panel with a click (right-click runs the rotation once). Hide or show it with `/armap`.

---

## ⚠️ Included Class Modules (WiP)

### 🛡️ Paladin 
Engineered around an intelligent "Roleless Seal Model" optimized for low-level leveling up to high-tier raiding:
- **Debuff Upkeep:** Automatically tracks target debuffs via texture fragments. Applies your chosen *Debuff Seal* (e.g., *Seal of the Crusader* or *Seal of Wisdom*) exactly once per mob, then switches immediately to your *Damage Seal*.
- **Low-Level Safety Guard:** Built-in safeguards automatically bypass the Judgement/Debuff loop if your Paladin is under level 10 and hasn't learned `Judgement` yet, keeping your damage seal active as a permanent auto-attack buff.
- **Hysteresis Resource Management:** Fully configurable independent health and mana safety floors. When triggered, the engine swaps to *Seal of Light* or *Seal of Wisdom* until your resource stabilizes back to your high threshold.
- **Seal Twisting Support:** If enabled, delays damage judgements until precisely `< 0.4s` before your next white swing to combine weapon procs and judgements simultaneously.
- **Strike Priority Sync:** Coordinates *Holy Strike* and *Crusader Strike* cooldowns to intelligently maintain *Holy Might* and stack *Zeal* dynamically.
- **Consecration (opt-in):** An AoE filler cast on cooldown when enabled. Because the 1.12 client cannot reliably count nearby enemies, it is a manual toggle — the *Consecration (AoE)* checkbox, or `/ar aoe` for a quick keybind flip. It sits last in the priority so it never delays your strikes, *Holy Shield*, seal/Judgement upkeep, or *Hammer of Wrath*, and is held during mana recovery.
- **Exorcism (opt-in):** Cast on cooldown, but only against *Undead* and *Demon* targets (checked via creature type), and likewise paused while recovering mana.

### 🥷 Rogue 
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

### 🔮 Warlock 

Optimized for efficient DoT (Damage over Time) multi-dotting and resource management:

* **Curse/DoT Upkeep:** Dynamically prioritizes debuff application based on target health percentage and remaining DoT duration, ensuring minimal GCD waste.
* **Life Tap Integration:** Hysteresis-based management that automatically triggers *Life Tap* when mana dips below your defined threshold and health is safely above your safety floor.
* **Pet Management:** Automated support for pet attack commands on primary target engagement and conditional health-monitoring for *Health Funnel* usage.
* **Drain-Tanking Logic:** Specialized rotation mode that intelligently switches to *Drain Life* or *Drain Soul* when the target is below execution health thresholds or when player health requires stabilization.

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
| `/ar reset` | Resets active profile positions and layout variables. | `/ar reset` |
| `/ar trace` | Toggles detailed combat logic debugging. | `/ar trace` |
| `/armap` | Hides or shows the minimap button. | `/armap` |
| `/ar cp <1-5>` | *(Rogue Only)* Sets min. finishing Combo Points. | `/ar cp 5` |
| `/ar seal <slot> debuff/damage <alias>` | *(Paladin Only)* Modifies profile seals. | `/ar seal DPS damage sor` |
| `/ar aoe` | *(Warrior & Paladin Only)* Toggles AoE mode (Cleave + Whirlwind / Consecration). | `/ar aoe` |
| `/ar cd <on/elite/off>` | *(Warrior Only)* Sets cooldown usage mode. | `/ar cd elite` |
| `/ar dance` | *(Warrior Only)* Toggles experimental stance dancing. | `/ar dance` |
| `/ar spell <alias> <on/off>` | *(Warrior & Paladin)* Flips an ability on the active profile. | `/ar spell ms on` |

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

---

## 🚩 Troubleshooting & False Positives
MacroErrorChecker / UI Warning Messages
If you use macro validation addons like MacroErrorChecker, you may see a warning in chat on login stating: L3: Unknown command: /ar.

This is a false positive. External macro checkers look for a static list of default Blizzard interface commands. They cannot scan third-party custom slash engines. As long as typing /ar ui opens your addon profile window, AutoRota is working perfectly and you can safely ignore or disable the validation warning. This can be added to the whitelist with some addons like `SuperCleveRoidMacros` to avoid the chat error.
