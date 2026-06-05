# AutoRota (v0.4)

AutoRota is a lightweight, robust, highly configurable combat automation framework built for **Turtle WoW (1.12 / SuperWoW)**. Unlike standard "monolithic" 1.12 macros or basic script loops, AutoRota uses a modern modular architecture, automated frame-by-frame management, and smart situational logic to execute combat rotations.

Version 0.4 introduces a complete graphical configuration panel and database system, moving configuration options out of your macros and into a clean visual window.

---

## 🖥️ Features

- **Multi-Class Architecture:** A unified, lightweight UI shell dynamically swaps control panels and rotation rules based on the class you are currently playing.
- **Smart Profile Management:** Create, save, rename, and activate multiple custom setup profiles (e.g., *Starter*, *Leveling*, *PvP*, *Raid-DPS*) seamlessly in-game.
- **Turtle WoW & SuperWoW Optimized:** Fully compatible with custom SuperWoW features such as spell queueing (`QueueSpellByName`), weapon swing timing, and custom custom class expansions (e.g., Rogue's *Noxious Assault*, Paladin's *Holy Strike*).
- **Zero-Clipping Logic:** Rotations run on strict single-cast priorities with early returns. The addon ensures exactly one primary action executes per frame to prevent spell clipping or overlapping global cooldowns (GCD).

---

## ⚠️ Included Class Modules (WiP)

### 🛡️ Paladin 
Engineered around an intelligent "Roleless Seal Model" optimized for low-level leveling up to high-tier raiding:
- **Debuff Upkeep:** Automatically tracks target debuffs via texture fragments. Applies your chosen *Debuff Seal* (e.g., *Seal of the Crusader* or *Seal of Wisdom*) exactly once per mob, then switches immediately to your *Damage Seal*.
- **Low-Level Safety Guard:** Built-in safeguards automatically bypass the Judgement/Debuff loop if your Paladin is under level 10 and hasn't learned `Judgement` yet, keeping your damage seal active as a permanent auto-attack buff.
- **Hysteresis Resource Management:** Fully configurable independent health and mana safety floors. When triggered, the engine swaps to *Seal of Light* or *Seal of Wisdom* until your resource stabilizes back to your high threshold.
- **Seal Twisting Support:** If enabled, delays damage judgements until precisely `< 0.4s` before your next white swing to combine weapon procs and judgements simultaneously.
- **Strike Priority Sync:** Coordinates *Holy Strike* and *Crusader Strike* cooldowns to intelligently maintain *Holy Might* and stack *Zeal* dynamically.

### 🥷 Rogue 
A refined evolution of the *ExAutoRogue* logic focused on efficient combo point generation and finishing priority:
- **Adaptive Combo Builders:** Automatically chooses your highest efficiency spec builder (*Noxious Assault* if known, falling back to *Sinister Strike*), or allows you to force a fixed weapon builder via a profile dropdown.
- **Finisher Hysteresis Engine:** Dynamically tracks *Slice and Dice* and *Envenom* buffs. It will auto-refresh them efficiently at exactly 1 Combo Point if they are about to expire, otherwise saving points to dump into maximum-damage *Eviscerates*.
- **Reactionary Counters:** Instantaneous out-of-GCD execution for abilities like *Riposte* during active parry windows.
- **Cooldown Automation:** Integrates *Adrenaline Rush* and *Blade Flurry* seamlessly, prioritizing them against Elite or Boss targets.

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

## 🚩 Troubleshooting & False Positives
MacroErrorChecker / UI Warning Messages
If you use macro validation addons like MacroErrorChecker, you may see a warning in chat on login stating: L3: Unknown command: /ar.

This is a false positive. External macro checkers look for a static list of default Blizzard interface commands. They cannot scan third-party custom slash engines. As long as typing /ar ui opens your addon profile window, AutoRota is working perfectly and you can safely ignore or disable the validation warning.
