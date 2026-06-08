# 📜 Changelog

All notable changes to **AutoRota** are documented here. Versions are listed newest first.

---

## v0.5b — Warrior Beta

The headline of this release is a brand new **Warrior** combat module, plus the
supporting commands and documentation. Paladin and Rogue behaviour is unchanged.

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

### ✨ Added
- **`/ar aoe`** *(Warrior)* — toggles AoE mode (rage dump becomes *Cleave*, *Whirlwind* used on cooldown). Bindable for mid-fight flips.
- **`/ar cd on|elite|off`** *(Warrior)* — sets cooldown usage to always, Elite/Boss only, or fully manual.
- **`/ar dance`** *(Warrior)* — toggles experimental stance dancing for *Overpower*.
- **`/ar spell <alias> on|off`** *(Warrior)* — flips an individual ability on the active profile, with short aliases (`ms`, `bt`, `ss`, `ww`, `op`, `rev`, `exec`, `sa`, `tc`, `hs`, `cleave`, `sweep`, `dw`, `reck`, `br`, `bld`, `sb`).

### 🔧 Changed
- **`.toc`** now loads `classes\Class_Warrior.lua` and `classes\Class_Warrior_UI.lua`, and the addon version is bumped to **0.5b**.
- **README** updated with the Warrior section, the new commands in the CLI table, and a Warrior toggles / spell-alias reference.

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
