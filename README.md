# Aegis: Single Button Rotation (v1.1.7)

**One button. Your whole rotation.**

[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/hsgPTNkSX)
[![Octo WoW](https://img.shields.io/badge/Octo%20WoW-1.18.1-8A2BE2?style=flat-square&labelColor=555)](https://octowow.st/)
[![Capy WoW](https://img.shields.io/badge/Capy%20WoW-1.18.1-8B5A2B?style=flat-square&labelColor=555)](https://capycraft.io/)

[![SuperWoW](https://img.shields.io/badge/SuperWoW-Required-C41E3A?style=flat-square&labelColor=555)](https://github.com/balakethelock/SuperWoW)
[![Nampower](https://img.shields.io/badge/Nampower-Required-C41E3A?style=flat-square&labelColor=555)](https://github.com/brues-code/nampower)
[![UnitXP_SP3](https://img.shields.io/badge/UnitXP__SP3-Required-C41E3A?style=flat-square&labelColor=555)](https://codeberg.org/konaka/UnitXP_SP3)
[![ClassicAPI](https://img.shields.io/badge/ClassicAPI-Recommended-ff8c00?style=flat-square&labelColor=555)](https://github.com/brues-code/ClassicAPI)
[![SCRM](https://img.shields.io/badge/SCRM-Recommended-ff8c00?style=flat-square&labelColor=555)](https://github.com/brues-code/SuperCleveRoidMacros)

A 1.12 rotation is a lot of buttons and a lot of bookkeeping — which debuff fell off, is
the proc up, do I have rage for that. Aegis puts the whole thing on **one key**. Every
press evaluates your class, spec, resources, procs, and debuff windows, then fires the
single best ability for that instant. No macro spaghetti, no clipping the global cooldown.

> Built for the **1.18.1** vanilla-plus servers — [Octo WoW](https://octowow.st/) and
> [Capy WoW](https://capycraft.io/) — which run the original **WoW 1.12 (vanilla)** client on
> **Lua 5.0**. Not Classic. Not retail. Real vanilla, with 1.18.1's custom class changes
> baked in.

**[💬 Join the Discord](https://discord.gg/hsgPTNkSX)** for help, bug reports, and rotation
feedback.

> ⚠️ **Active beta.** Rotation logic and general functionality can still have rough edges.
> Watch your combat closely in dungeons and raids, and tell us what misbehaves — feedback is
> what sharpens the per-class priorities.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements) — the client mods Aegis is built on
- [Install](#install)
- [Using it](#using-it) — the macro, and the one thing melee must do
- [Class modules](#class-modules) — all nine, in detail
- [Commands](#commands)
- [A few honest notes](#a-few-honest-notes)
- [Under the hood](#under-the-hood)
- [Something broken?](#something-broken)
- [Contributing](#contributing)

---

## What it does

**One press, one cast.** Each press walks your spec's priority list top-down and fires the
first ability whose conditions pass, then stops. Strict single-cast — it never tries to
stack two casts into one press and clip your own global cooldown.

**It reads the fight, not a script.** Resources, proc windows, debuff timers, combo points,
target health, stance/form, range, and your own toggles all gate the list. Target debuffs
resolve through SuperWoW **spell IDs**, so upkeep is rank- and locale-proof (clients without
SuperWoW fall back to icon matching).

**It grows with your character.** Every ability is gated on whether you've actually learned
it, so the same profile plays a level 1 character and a raider — spells switch themselves on
as you train them, and the panel marks anything untrained as *(not learned)*.

**Profiles, per character.** Keep *Leveling*, *Raid*, and *PvP* setups side by side and
switch instantly. For the classes whose rotation branches by spec, the config window shows a
**spec tab rail** and only the active spec's controls — the tab you're on *is* the mode the
rotation runs.

**Three targeting modes.** **Auto** grabs the nearest enemy when you have none, **Manual**
defers entirely to you or an assist addon, and **Assist** mirrors a party/raid member's
target — matched **by GUID**, so a same-named mob from another group is never mistaken for
theirs. Ranged modules opt out of Auto so they never pull something at random.

**A config panel, not a config file.** Flat-dark theme, class-coloured accents, bundled
*PT Sans Narrow*, one clean row per setting (toggle · label · slider · value), plus a
draggable minimap button with its own options panel.

**Upkeep monitors (opt-in).** Two independent helpers, toggled from the minimap right-click
panel. A **buff monitor** watches the self-buffs you choose and pops a clickable rebuff
button when one drops — its watch list is kept **per context (Solo / Party / Raid)**, since
what you keep up alone is not what you keep up in a raid; Party and Raid follow the Solo list
until you give them their own. Weapon slots are watched too: a shaman gets the same prompt
when a **weapon imbue** lapses, which the class panel's auto-apply cannot cover on its own
(that stands down in combat unless you opt in). A rogue **poison Quick Bar** puts up to four
poison presets on a
movable bar — left-click for main hand, right-click for off hand, with charge and
time-remaining bars — and applies whatever rank is in your bags. (Poisons need a real click,
so they're always button-driven, never fired from the rotation macro.)

**Weapon-enchant awareness (opt-in).** Reads your live temporary weapon enchant — presence
*and* time remaining — powering **Shaman imbue upkeep**: it auto-applies out of combat,
reminds you in combat, and never overwrites an existing imbue behind your back or spends a
global cooldown mid-fight unless you say so.

---

## Requirements

**SuperWoW is the one Aegis genuinely can't work without.** The rest of the stack is the
recommended 1.18.1 setup — install it all and everything behaves as documented.

| Mod | | Why, specifically |
|---|---|---|
| **[SuperWoW](https://github.com/balakethelock/SuperWoW)** | Required | The backbone. Healer specs cast on a **unit without dropping your target** (`CastSpellByName(spell, unit)`) — that's SuperWoW-only, and there's no fallback. It also supplies unit GUIDs (GUID-matched Assist targeting), `UNIT_CASTEVENT` (Auto Shot timing, Shaman totem tracking, Warlock cast confirmation), `SpellInfo` spell-ID debuff resolution, and weapon-enchant info. ↳ [Features wiki](https://github.com/balakethelock/SuperWoW/wiki/Features) |
| **[Nampower](https://github.com/brues-code/nampower)** | Required | Spell queueing and cast timing, so a press during the tail of a cast fires the instant it's legal instead of eating your latency. Every queued cast falls back to a plain cast if it's missing, so the addon still *runs* — but cast-time rotations and the Hunter's Steady Shot weave lose their clip-free timing. |
| **[UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3)** | Required | Accurate distance and line-of-sight checks. Aegis doesn't call it directly today — it's a hard requirement of SuperCleveRoidMacros' distance and enemy-count conditionals, and part of the standard stack. |
| **[SuperCleveRoidMacros](https://github.com/brues-code/SuperCleveRoidMacros)** | Recommended | Conditional macros alongside Aegis; it also takes over auto-attack handling when present. |
| **[ClassicAPI](https://github.com/brues-code/ClassicAPI)** | Recommended | A DLL backporting the modern Blizzard API to 1.12. **Aegis doesn't use it yet** — see [`docs/research-classicapi.md`](docs/research-classicapi.md) for what it could unlock (enemy debuff timers, exact spell range, profile import/export). |

---

## Install

1. Download this repo (**Code → Download ZIP**, or clone it).
2. Drop the folder into:
   ```
   World of Warcraft/Interface/AddOns/Aegis_SBR
   ```
3. **The folder must be named exactly `Aegis_SBR`** — GitHub's ZIP unpacks as
   `Aegis_SBR-main`, so rename it or the client won't load the addon.
4. Restart the client. Tick **Load out of date AddOns** if prompted.

Keep the bundled `Icons/` and `Fonts/` subfolders intact — they're the UI's textures and
typeface. (Without `Fonts/` the window silently falls back to the client's default font.)

> **After any update that adds textures, do a full relog** — log out to character select and
> back in. The 1.12 client only scans for new texture files at login, so `/reload` alone can
> leave custom art missing.

<details>
<summary><b>Upgrading from AutoRota (pre-0.14.0)?</b></summary>

The addon folder is now `Aegis_SBR`. **Delete the old `Interface\AddOns\AutoRota\` folder**
so both can never load at once.

Your per-character profiles migrate automatically on first login (`AutoRotaDB` → `AegisDB`,
with the old data kept as a rollback backup for a few versions). **Back up your `WTF\`
folder before that first login.**

If your profiles don't appear: log fully out and copy your character's old saved-variables
file — `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\AutoRota.lua` →
`Aegis_SBR.lua` in the same folder — then log back in. (Clients that keep per-character
variables in one combined `SavedVariables.lua` won't need this.)

`/sbr` is the primary command now, with `/aegis` as the long form; `/ar` still works
everywhere as a legacy alias.
</details>

---

## Using it

Your entire combat macro is one line. Put it on your bar and press it. Repeatedly.

```
/sbr
```

Open the config window with `/sbr ui` (or left-click the minimap button) to manage profiles,
flip abilities on and off, and set your thresholds.

| Do this | Get that |
|---|---|
| `/sbr` | Fire the rotation — this is your one button |
| `/sbr ui` | Open the configuration window |
| `/sbr list` · `/sbr use <name>` | See your profiles · switch to one |
| `/sbrmap` | Show/hide the minimap button (right-click it for options) |
| `/sbr debug` | Dump live buff/debuff names — the first stop when something won't fire |
| `/sbr trace` | Per-press log of what the rotation decided and why |

> ### 🗡️ Melee: put **Attack** on an action bar
> Aegis keeps your white swing going by toggling the standard **Attack** ability, which it
> finds by scanning your bars. If it isn't on one, you'll fire abilities without swinging in
> between. Drag **Attack** from your spellbook (**P** → *General*) onto any free slot.
>
> **Druids especially:** Cat/Bear form **replaces your main bar**, so **Attack** must sit on
> a bar that stays visible while shifted (a side bar or the bottom-right bar) — not slots
> 1–12.
>
> *Exception:* running **SuperCleveRoidMacros**? It manages attacks, and Aegis leaves this
> alone.

> ### 🏹 Hunters: put **Auto Shot** on an action bar
> Auto Shot detection is most reliable when the ability is on a bar (**P** → *General*). If
> you use the melee weave, put **Attack** there too so *Raptor Strike* has swings to ride.

---

## Class modules

All nine classes, each with its own rotation module and config panel. Everything below is
`(Beta)` — expand a class for the full detail.

<details>
<summary><b>🛡️ Paladin</b> — roleless seal model, melee-capable healer</summary>

Engineered around an intelligent "Roleless Seal Model" optimized for low-level leveling up to high-tier raiding:
- **Debuff Upkeep:** Automatically tracks target judgement debuffs by exact spell name (SuperWoW spell ids, with texture fallback). Applies your chosen *Debuff Seal* (e.g., *Seal of the Crusader* or *Seal of Wisdom*) exactly once per mob, then switches immediately to your *Damage Seal*.
- **Low-Level Safety Guard:** Built-in safeguards automatically bypass the Judgement/Debuff loop if your Paladin is under level 10 and hasn't learned `Judgement` yet, keeping your damage seal active as a permanent auto-attack buff.
- **Hysteresis Resource Management:** Fully configurable independent health and mana safety floors. When triggered, the engine swaps to *Seal of Light* or *Seal of Wisdom* until your resource stabilizes back to your high threshold.
- **Seal Twisting Support:** If enabled, delays damage judgements until precisely `< 0.4s` before your next white swing to combine weapon procs and judgements simultaneously.
- **Talent-Aware Strikes:** Two toggles pick which strikes you use — *Holy Strike* and *Crusader Strike*. Enable one alone to use **only** that strike; enable both to reveal a **strategy** dropdown. **Auto DPS** reads your spec: without *Vengeful Strikes*, *Crusader Strike* builds *Zeal* to 3 stacks and *Holy Strike* fills (still returning mana/health to the group); with the talent, *Holy Strike* opens for *Holy Might* and is kept up while *Zeal* is ramped — if both buffs would fall in the same 6s window, *Zeal* wins. **Tank block** keeps *Crusader Strike*'s *Zealous Defense* block buff loaded (consumed on the next block) and spends every other global on *Holy Strike* for threat (*Righteous Strikes*). Also `/sbr strike off|hs|cs|auto|tank` for a mid-fight keybind.
- **Mana Downranking (opt-in):** *Downrank when low* casts lower ranks of your strikes as raw mana drops, to keep swinging while leveling. Thresholds use absolute mana (not percent), so a full pool stays at top rank and only a near-empty pool steps down, always clamped to your highest known rank.
- **Consecration (opt-in):** An AoE filler cast on cooldown when enabled. Because the 1.12 client cannot reliably count nearby enemies, it is a manual toggle — the *Consecration (AoE)* checkbox, or `/sbr aoe` for a quick keybind flip. It sits last in the priority so it never delays your strikes, *Holy Shield*, seal/Judgement upkeep, or *Hammer of Wrath*, and is held during mana recovery.
- **Exorcism (opt-in):** Cast on cooldown, but only against *Undead* and *Demon* targets (checked via creature type), and likewise paused while recovering mana.
- **Heal Mode (`/sbr heal on`):** Turns the Paladin into a group healer that still DPSes between heals. It runs even with no attackable target, so it works at range. It picks the most-hurt *reachable* party/raid member (raid- and party-aware), counts its own in-flight heal so it never double-stacks on one target, and **downranks** *Flash of Light* / *Holy Light* to the size of the deficit for mana efficiency — the `+healing` bonus is read automatically from your gear (override with `/sbr healpower <n>`) and *Healing Light* / *Divine Favor* talents are factored in. *Holy Shock* is used **only as an instant heal** here (never for damage), for emergencies (below a configurable %) or for a hurt unit out of melee range. **Melee-holy weaving** is split into two independent toggles, since each strike is a global. **Reload Holy Shock (CS):** with *Blessed Strikes* talented (auto-detected — 100% at 5/5), *Crusader Strike* is woven between heals to **reset Holy Shock**, keeping the emergency instant loaded — but never over an emergency; anyone under the Holy Shock line is healed first. **Holy Strike filler:** in downtime *Holy Strike* is woven so its splash heal tops the melee group, gated by its own **mana floor** so it never starves a heal. A heal-mode **Mana management** section keeps *Seal of Wisdom* on you for **self mana**, with an optional **Judge Wisdom** that stamps *Judgement of Wisdom* on the mob for **group-wide mana** (a global you cannot heal during, so it is opt-in and off by default). The **Tank / Damage | Healer tabs** switch the mode (same as `/sbr heal`), and the tab you are on **is** the active mode — the other tab's settings are ignored. The attack rotation yields the global cooldown while anyone needs healing, so a judgement never steals a heal's cast. Configure it in the *Healing* panel section or via `/sbr healat` and `/sbr hsat`.

> **Heal-mode note:** The per-rank heal values and the talent modifiers are best-effort approximations tuned for Turtle, and live in one table at the top of `Class_Paladin.lua` — if downranking picks a rank that over- or under-heals, that is where to adjust. Targeted healing relies on SuperWoW's unit-argument `CastSpellByName`, so it heals the hurt member without dropping your attack target; worth a quick in-party sanity check on 1.18.1.
</details>

<details>
<summary><b>⚔️ Warrior</b> — roleless Arms / Fury / Protection, stance- and rage-aware</summary>

A roleless, toggle-driven engine covering Arms, Fury, and Protection from early leveling through endgame raiding. Rather than locking to a spec, you enable the abilities you have and the priority degrades gracefully as you learn them:
- **All-Spec Roleless Design:** One profile schema serves every spec via simple toggles. Abilities you have not learned yet are skipped automatically and flagged as *(not learned)* in the panel, so the same setup keeps working as you level.
- **Stance & Rage Aware Casting:** A warrior-specific gate verifies rage, stance, and cooldown *before* committing to a cast, so a stance- or rage-locked ability can never stall the priority chain. Stance rules follow vanilla 1.12 and stay conservative if Turtle relaxes them.
- **Reactive Proc Windows:** Reads the combat log for target dodges and your own block/dodge/parry to open short windows for *Overpower* (Battle Stance) and *Revenge* (Defensive Stance), mirroring the Rogue's Riposte tracker.
- **Optional Stance Dancing:** An experimental opt-in that auto-swaps to Battle Stance for *Overpower*, then drifts back to your configured home stance, throttled by a swap cooldown to prevent thrashing.
- **Smart Rage Dump:** Queues *Heroic Strike* (or *Cleave* in AoE mode) onto your next swing only above a configurable rage floor, and suppresses it during the *Execute* phase so surplus rage funnels into *Execute*.
- **Cooldown Automation:** *Death Wish*, *Recklessness*, and *Berserker Rage* fire on cooldown, only on Elite/Boss targets, or fully manually — the same three-state model as the other classes — while *Bloodrage* tops up rage on demand, even before the pull.
- **Threat Toolkit:** Maintains *Sunder Armor* up to a chosen stack count and weaves *Shield Slam*, *Revenge*, and *Shield Block* upkeep for Protection tanking.
- **Shout Upkeep:** *Battle Shout* (on by default) is kept up as the party attack-power buff — refreshed only when it's missing or about to expire and placed **below your strikes**, so it costs a global cooldown only about once every two minutes and never delays a strike. *Demoralizing Shout* (off by default) keeps the enemy attack-power reduction on your target for tanking, re-applied only when it drops. Both yield during *Execute* and are rage-gated.
- **Optional Master Strike:** The Arms talent *Master Strike* is available as an opt-in toggle (off by default, since it's mainly a PvP pick). Enabled, it fires on cooldown from a slot **directly below your spec's primary strike**, so it fills the gaps while *Mortal Strike* / *Bloodthirst* / *Shield Slam* are cooling down and never delays them. It appears once talented and shows *(not learned)* until then.
- **Leveling Toggles (off by default):** *Charge* opens a pull from range in Battle Stance — self-limiting, since the client blocks it once you're in combat, so it only ever fires on the initial gap-close. *Rend* keeps its bleed up in Battle or Defensive Stance and yields during *Execute* so rage funnels there instead. Neither toggle is meant for endgame play.
- **Reliable Auto-Attack:** If *Attack* isn't placed on an action bar, the addon falls back to starting the swing directly, so melee always engages without a manual `/startattack`.
</details>

<details>
<summary><b>🥷 Rogue</b> — combo-point economy and finisher priority</summary>

A refined evolution of the *ExAutoRogue* logic focused on efficient combo point generation and finishing priority:
- **Adaptive Combo Builders:** Automatically chooses your highest efficiency spec builder (*Noxious Assault* if known, falling back to *Sinister Strike*), or allows you to force a fixed weapon builder via a profile dropdown.
- **Finisher Hysteresis Engine:** Dynamically tracks *Slice and Dice* and *Envenom* buffs. It will auto-refresh them efficiently at exactly 1 Combo Point if they are about to expire, otherwise saving points to dump into maximum-damage *Eviscerates*.
- **Reactionary Counters:** Instantaneous out-of-GCD execution for abilities like *Riposte* during active parry windows.
- **Cooldown Automation:** Integrates *Adrenaline Rush* and *Blade Flurry* seamlessly, prioritizing them against Elite or Boss targets.
- **Execute Low-HP Targets (opt-in, off by default):** Below a configurable health threshold (default 10%), *Eviscerate* fires with whatever combo points are on hand rather than waiting for your normal threshold, so points aren't left on a corpse. *Ruthlessness* guarantees at least one point after any finisher, so it's rarely blocked. Adds an `exec=` field to `/sbr trace`.
- **Poison Quick Bar:** Poison control lives in the **Poisons** section of the panel and the movable Quick Bar (part of the [upkeep monitors](#what-it-does)) — up to four presets, left-click for main hand, right-click for off hand, each button showing charge and time-remaining bars. Enter just the poison *type* (e.g. "Instant Poison", **no rank**) and whatever rank is in your bags is applied.
</details>

<details>
<summary><b>🏹 Hunter</b> — Auto / Ranged / Melee, reworked for Turtle's Survival</summary>

Reworked for Turtle WoW 1.18.1's hunter changes, with **Auto**, **Ranged**, and **Melee** playstyles selectable per profile (`/sbr mode auto|ranged|melee`):

* **Auto (by distance):** The default for new profiles. Picks ranged vs melee each press from your distance to the target (a short stickiness stops it flickering at the boundary), so shots fire at range and strikes fire in melee with no cross-mode bleed. Ideal while leveling, where mobs close fast.
* **Ranged (BM / MM):** Built around the **Auto Shot** backbone with **Steady Shot** (baseline at 20) woven 1:1 after each shot — gated on the exact Auto Shot timing from SuperWoW's `UNIT_CASTEVENT` (interval fallback) so mashing never clips or starves it. *Arcane Shot* / *Multi-Shot* weave as instants. Auto Shot is kept *running* and now **self-unsticks**: if a shot is detected to have stalled it is restarted automatically, instead of needing a manual target swap. Starting Auto Shot is its own press, so it no longer blocks a same-press **Hunter's Mark** or **Sting**.
* **Lock and Load (MM capstone):** *Aimed Shot* is **not** hard-cast on cooldown (that clips Auto Shot). Instead the rotation watches for the **Lock and Load** buff — a crit from Steady/Aimed/Arcane that resets Aimed Shot, drops its cast time, and makes it cleave a line — and fires *Aimed Shot* the instant it procs. A toggle lets you also cast it on cooldown if you prefer.
* **Melee (Survival / BM-melee):** Keeps **Aspect of the Wolf** up, starts melee swings, and runs the priority **Mongoose Bite** (reactively in the window after you dodge) → **Lacerate** (maintained bleed) → **Raptor Strike** on cooldown → optional *Wing Clip*. Under `/sbr aoe` it leads with **Carve** (the Survival cone cleave, up to 5 targets). Survival can drop **Immolation Trap** on cooldown (Patch 1.18.1 allows traps in combat). The mana-aspect swap to *Viper* works here too — a mana-heavy melee hunter drops to Viper at your lower threshold and swaps back to Wolf at your upper one.
* **Range-Correct Upkeep:** **Hunter's Mark** leads the whole rotation — it is the first thing the hunter does to a target, ahead of even aspect upkeep, and nothing else is cast until it is on. It costs a press only *once* per target, so the aspect follows immediately after. Maintained in *both* modes (a universal damage-amp debuff). A **Sting** (*Serpent*, *Scorpid*, *Viper*, the smart **Viper > Serpent** mode, or none — panel or `/sbr sting`) is a ranged shot, gated on *actual distance*: it lands on the pull while the target is still out of melee — so even a pure **melee** hunter opens with **Hunter's Mark + Serpent Sting** — and then stops once you close in. Both are applied once per target and refreshed exactly when they fall off (SuperWoW spell-id detection). Stings are Poison-school, so they **auto-skip poison-immune mobs** — *Mechanicals* and *Elementals* are skipped by creature type (no wasted cast), and immune *Undead* / bosses are learned after a single cast and then skipped for that fight.
* **Smart Sting (`Viper > Serpent`):** One sting setting that reads the target — *Viper Sting* against anything with a mana bar (draining casters), *Serpent Sting* for everything else. Pick it in the panel or with `/sbr sting smart`.
* **No Errant Pulls:** Being a ranged class, the Hunter does **not** auto-acquire a target — it will not grab and pull a random nearby mob, so you always choose what you are shooting.
* **Aspect Management:** Keeps your combat aspect (Hawk ranged / Wolf melee) up, and can **swap to Aspect of the Viper** when mana runs low, swapping back once you've recovered. Both edges are **your own sliders** — *Viper below* (e.g. 20%) and *Back to combat at* (e.g. 70%) — so you choose how deep the drain goes and how full you refill before returning to DPS. A guard keeps the upper value above the lower one so the aspect can never flap between the two.
* **Pet Support:** Pet attack, *Mend Pet* below a health slider, **Kill Command** on cooldown (BM), an optional **Baited Shot** fired in the window after the pet crits, and an optional **Smart Pet Taunt** — when the mob peels onto you, the pet's *Growl* is sent to grab it back (off by default; leave it off for melee-weave builds where you want the aggro).
* **AoE & Cooldowns:** *Volley* leads then *Multi-Shot* fills under `/sbr aoe`. *Rapid Fire* and *Bestial Wrath* automate on the usual three-state model — always, elite/boss only, or off.

> **Verification note:** A few 1.18.1 specifics are best-effort and gated by `KnowsSpell`, so an unknown name simply no-ops. If *Kill Command*, *Baited Shot*, the **Lock and Load** buff, or the mana aspect (tried: *Aspect of the Viper*, *Aspect of the Beast*) are not firing, run `/sbr debug` and check the exact names — they drop into one place in `Class_Hunter.lua`. Auto mode uses `CheckInteractDistance` (~10yd) as its melee proxy; `/sbr trace` shows the effective mode as `mode=auto/melee` or `mode=auto/ranged`.
</details>

<details>
<summary><b>⚡ Shaman</b> — Enhancement / Elemental / Tank / Restoration, with totem upkeep</summary>

* **Weapon imbue (all four specs):** Two independent routes to keep a main-hand imbue up —
  let the rotation apply it automatically out of combat, or take a **click-to-cast rebuff
  button** when it drops and decide yourself. The button is the only one that covers an imbue
  lapsing *mid-fight*. Available to Elemental and Restoration too, not just the melee specs.
  Main hand only — off-hand application is a fragile weapon-click flow.

Enhancement, Elemental, Tank, and **Restoration** (group healer) in one mode-adaptive engine — working from level 1:

* **Mode-Adaptive Rotation:** Pick **Enhancement** (melee: auto-attack, Stormstrike, Lightning Strike, a shock, with a Lightning Bolt weave), **Elemental** (caster: Flame Shock + Lightning Bolt building Electrify), **Tank** (Earth Shock threat, Stormstrike, Lightning Strike, optional Earthshaker Slam taunt), or **Restoration** (group healer — see below) — panel dropdown or `/sbr mode enhancement|elemental|tank|resto`.
* **Restoration (Group Healer):** A `resto` mode turns the Shaman into a party/raid healer that runs **with no enemy targeted** (so it works at range) and heals via SuperWoW's unit-argument cast without dropping your current target. It picks the most-hurt *reachable* member and **downranks Healing Wave** to the size of the deficit for mana efficiency (counting its own in-flight heal so it never double-stacks). Shaman healing is all direct — no HoTs — so the kit fires by priority: *Mana Tide Totem* when low on mana, **Nature's Swiftness-equivalent → instant Healing Wave** for emergencies, **Lesser Healing Wave** for a fast single-target save (which wins over AoE), *Chain Heal* when several are hurt, then downranked *Healing Wave* as the fill. During lulls it keeps **Water Shield** up and maintains the full totem set. It can also optionally **weave damage** in that downtime — *Lightning Bolt*, toggled with `/sbr weave` (off by default, enemy-targeted and mana-gated so it never starves heals).
* **Works from Level 1:** A fresh shaman only has *Lightning Bolt* and melee, so the Lightning Bolt filler carries the early levels and everything else — shocks, shields, Stormstrike, Lightning Strike, totems — switches itself on through `KnowsSpell` as it's trained.
* **Talent Automation:** *Stormstrike* and *Lightning Strike* are talent abilities that appear in the spellbook when talented, so they're auto-included when learned (Stormstrike's Nature self-buff is followed by a shock to consume it). *Elemental Focus* grants **no spell** — it's a passive crit proc (Clearcasting, 60% cheaper next spell) — so Aegis reads the **talent tree** to detect it and surface the proc, the same approach used for the Warlock's Nightfall.
* **Shield & Shock:** Keeps your chosen shield up (*Lightning* for damage/threat, *Water* for mana) and casts one shock on the shared cooldown — *Flame Shock* maintained as a DoT, *Earth/Frost* on cooldown. Switch with `/sbr shield` and `/sbr shock`.
* **Weapon Imbue Upkeep (opt-in, all four specs):** The *Weapon imbue* section keeps a **main-hand** imbue up (*Rockbiter / Flametongue / Frostbrand / Windfury*), and offers two independent routes — use either, or both. **Maintain imbue (automatic)** lets the rotation cast it for you: only when the weapon is bare and you are **out of combat** (or on approach); **in combat** it holds off unless *Apply in combat* is on (that costs a global cooldown), otherwise it just reminds you. **Rebuff button (manual)** puts a click-to-cast button on screen the moment the imbue is gone — nothing fires without your click, and it is the only route that covers an imbue lapsing *mid-fight*. While the button is on, the chat reminder is suppressed. Not restricted to the melee specs: an Elemental or Restoration shaman still swings between casts, and Rockbiter's threat matters to a healer holding aggro. Off by default; main-hand only for now.
* **Totems (every spec) & Cooldowns:** A shared **Totems** section maintains a full four-element set — Water, Earth, Fire, Air pickers, each with sensible per-spec defaults (Enhancement: Windfury / Searing / Strength / Mana Spring; Elemental: Grace of Air / Searing / Mana Spring; Tank: Stoneskin / Grounding / Mana Spring) — during a lull in **every** mode, not just Restoration. Where a totem grants an aura, **that aura is what's watched**, not a clock: a totem stays where you dropped it, so walking out of its radius silently ends the benefit long before the duration does — and the same read also catches a totem destroyed or recalled for mana. Totems that grant no aura (*Searing*, *Magma*, *Fire Nova*, *Grounding*) keep a timer, one **per totem** rather than a blanket number, since the fire slot alone spans 20s to 120s. An optional **AoE fire pair** takes over the fire slot for pull-clearing: *Fire Nova Totem* every time its cooldown is up, *Magma Totem* in between — they share one slot in game, so Magma is held back while a Nova is still standing. *Elemental Mastery* and self-*Bloodlust* round out the cooldowns.

> **Verification note:** Buff/proc names are best-effort — confirm the **Clearcasting** proc, the **Stormstrike** self-buff, and the **Searing Totem** / **Earthshaker Slam** spell names in-game with `/sbr talents` and `/sbr debug` if anything isn't firing. For **Restoration**, the same applies to the **Nature's Swiftness-equivalent** (tries `Nature's Swiftness`, then `Ancestral Swiftness`), **Mana Tide Totem**, and the **totem names** in the picker tables — and the heal rank values are vanilla baselines. The **totem aura names** are vanilla baselines too: a wrong one is self-correcting (the totem falls back to its timer rather than being re-dropped forever), but it does cost you the range/destruction detection for that totem, so it is worth checking with `/sbr debug`.
</details>

<details>
<summary><b>🐾 Druid</b> — Cat / Bear / Balance / Restoration, form-adaptive</summary>

Cat (DPS), Bear (Tank), Balance (Caster/Moonkin), and **Restoration** (group healer) in one form-adaptive engine — working from level 1:

* **Form-Adaptive Rotation:** Each press follows the form you are actually in — Cat Form runs the DPS rotation, Bear/Dire Bear runs the tank rotation, Moonkin (or a *Caster/Moonkin* preference) runs the Balance rotation, and caster form shifts you into your profile's preferred form (panel dropdown or `/sbr form cat|bear|caster`). One profile, one macro, every job.
* **Level 1 and Up:** Before any combat form is learned (Bear at 10, Cat at 20), the caster rotation carries the character — Moonfire upkeep plus Wrath is exactly the right early-leveling loop — and the profile grows into its form automatically the moment it is trained.
* **Balance / Eclipse Weaving:** Keeps *Moonfire* and *Insect Swarm* up, then chain-casts your primary nuke (Wrath or Starfire) to fish for **Eclipse** procs and swaps to the empowered opposite nuke the instant one fires. Nukes are queued through SuperWoW, so spamming never clips a cast. Entering Moonkin (when learned) is automatic for the mana discount.
* **Restoration (Group Healer):** A `resto` spec turns the Druid into a party/raid healer that runs **with no enemy targeted** and heals via SuperWoW's unit-argument cast without dropping your current target. It picks the most-hurt *reachable* member and **downranks Healing Touch** to the size of the deficit (counting its own in-flight heal, with `+healing` factored through *Gift of Nature*). The kit fires by priority: *Innervate* when low on mana, **Nature's Swiftness → instant max Healing Touch** for a target in real trouble, *Swiftmend* for a no-cast top-up off your own Rejuv/Regrowth, *Regrowth* for a big single-target burst, *Rejuvenation* kept rolling at its best affordable rank, and optional *Wild Growth* (AoE) and *Lifebloom*. When the group is topped it can optionally **weave damage** — *Moonfire* + *Wrath*, toggled with `/sbr weave`. Select it with `/sbr form resto` (or `/sbr new <name> tree` for a ready-made profile). *(Heals in caster form — the rotation drops any active shapeshift first; **Tree of Life auto-shift is off for now**, pending its 1.18.1 cast rules.)*
* **Defensive Bear (HP Management):** Optional hysteresis safety net — drop below your low threshold (default 35%) and the rotation forces Bear Form from **any** form, fires *Frenzied Regeneration* on cooldown, and keeps tanking behind bear armor; climb back over your high threshold (default 70%) and it releases you to your preferred form. Off by default and inert until Bear Form is learned.
* **Two Turtle Cat Styles:** *Claw & Bleed* keeps *Rake* and *Rip* rolling and builds with *Claw* (pairs with bleed-energy talents like *Ancient Brutality*); *Shred & Powershift* builds with *Shred* and finishes with *Ferocious Bite* for bleed-immune bosses (MC/BWL). Swap mid-fight with `/sbr style bleed|shred`.
* **Smart Finishers:** At your combo threshold the bleed style applies *Rip* if it is not ticking and spends *Ferocious Bite* while it is — combo points are never dumped into a redundant bleed.
* **Powershifting (opt-in):** In the Shred style, when energy bottoms out below your slider the rotation shifts to caster and straight back into Cat for a fresh energy bar — and **never while Tiger's Fury is active**, so the buff is not thrown away.
* **Stealth Opener & Upkeep:** Opens from *Prowl* with *Ravage* (auto, if known) or *Pounce*, and keeps *Faerie Fire (Feral)* and *Tiger's Fury* running.
* **Bear Tanking:** *Faerie Fire (Feral)* as the **ranged opener** (instant, 30yd), optional **Growl** taunt that grabs threat on the pull and whenever the target stops attacking you, *Demoralizing Roar* upkeep, *Maul* as the rage dump, *Swipe* leading under `/sbr aoe`, and optional *Enrage* when rage-starved (in combat only — it lowers armor, so it is off by default). *(Moonfire cannot be cast in bear form, so Faerie Fire is the bear's ranged opener.)*
* **Form-Aware Auto-Attack:** The white swing is started automatically in **Cat and Bear** (and never while casting in caster/Moonkin) — see the action-bar note in [Using it](#using-it).
</details>

<details>
<summary><b>🔮 Warlock</b> — DoT priority, Dark Harvest, Nightfall procs</summary>

A full DoT, survival, execute, and pet kit — working from level 1:

* **DoT Priority Engine:** Keeps your enabled damage-over-time effects up in strict priority — *Immolate*, then your chosen Curse, then *Siphon Life*, then *Corruption* (the order puts the effect that loses least by going last, last) — detected by exact spell name (SuperWoW spell ids, with texture fallback). With **Malediction** talented, the secondary *Curse of Agony* that rides alongside a non-Agony main curse is tracked and refreshed on its own too (skipped when the main curse already is Agony or Doom). Recasts are confirmed via SuperWoW's `UNIT_CASTEVENT` rather than assumed successful the instant they're sent — a cast that silently fails retries on the very next press instead of stalling for the rest of the throttle window.
* **Works from Level 1:** A fresh warlock's only damage is *Shadow Bolt*, so the filler **adapts** — the wand filler falls back to Shadow Bolt when no wand is equipped (and a not-yet-learned spell filler does too), then uses the wand automatically the moment you equip one. The DoTs and curse switch themselves on as they are trained.
* **Dark Harvest, DoT-Aware:** *Dark Harvest* channels the instant it comes off cooldown and wand-fills the gap between channels (falling back to *Shadow Bolt* with no wand equipped) instead of leaving the rotation idle. Before committing to a channel it tops up any enabled DoT that would fall off partway through — the channel's own length and the required buffer are scaled by *Rapid Deterioration* and Dark Harvest's own 30% tick-rate boost, so the check reflects your actual talents rather than a flat number.
* **Survival & Execute (each optional, by priority):** *Drain Life* self-heals when your health dips (drain-tank safety net); *Health Funnel* tops the pet when it drops, as long as your own health is safe; *Shadowburn* instant-executes under a threshold (skipped with zero Soul Shards in the bag, so it can never stall the rotation on a doomed cast); *Drain Soul* channels in the target's last seconds to bank a Soul Shard, optionally stopping early once you're holding enough shards.
* **Talent-Aware Nightfall & Rapid Deterioration:** Aegis reads your **talent tree** to detect *Nightfall* and **auto-fires the free instant *Shadow Bolt*** the moment *Shadow Trance* procs — checked ahead of every other priority (including Drain Life) so a longer action started first can never burn through the whole proc window unused. The proc is spent **once per proc** on the rising edge, so a lingering buff icon never triggers a wasted full-cast Shadow Bolt. *Rapid Deterioration* (2 ranks, 3% shorter *Corruption* / *Curse of Agony* / *Siphon Life* / *Dark Harvest* duration per rank) is likewise read from your talent rank and scales every duration estimate the rotation makes.
* **Curse Selection:** One curse per target, switchable from the panel or mid-fight with `/sbr curse <alias>` (`coa`, `coe`, `cos`, `cow`, `cor`, `cot`, `cod`, `none`).
* **Life Tap & Low-Mana Safety:** Triggers *Life Tap* only when mana dips below your threshold **and** health is safely above your floor. A separate, lower mana floor is a last-resort safety valve — below it, a DoT that needs recasting but can't be afforded no longer gets queued and left to fail; the rotation prefers Life Tap if safe, otherwise drops to the wand.
* **Cast Queueing & Pet Support:** Cast-time spells use SuperWoW's `QueueSpellByName` so the rotation never clips a cast. The wand also stops itself **ahead of** a tracked DoT expiring (within 1.5s) rather than reactively trying to interrupt a shot that may already be mid-flight. A channel watcher **protects your channels** — *Drain Life*, *Drain Soul*, and *Dark Harvest* can't be clipped by a DoT refresh or the wand on the next press. Optionally sends your pet onto the target, with a **Pet only in melee range** toggle.
</details>

<details>
<summary><b>🌟 Priest</b> — Shadow/leveling damage and Disc/Holy healing in one toggle</summary>

Shadow/leveling damage and Discipline/Holy healing in one module, switched by a single toggle — working from level 1:

* **Two Modes, One Toggle:** with *Heal mode* **off** the priest runs the **shadow/leveling damage** rotation; with it **on** (`/sbr heal on`, or the panel) it becomes a **group healer that weaves damage between heals**. Heal mode runs even with no attackable target, so it works at range.
* **Leveling & the 5-Second Rule:** *Mind Blast* on cooldown (the pull and the *Shadow Weaving* trigger), *Shadow Word: Pain* and (Undead) *Devouring Plague* kept rolling, *Holy Fire* when out of Shadowform — then the **wand carries the filler while mana regenerates**. Aegis is a rotation engine, not a HUD, so it *acts* on the five-second rule rather than drawing a timer: when mana drops below a configurable floor the filler falls back to the wand (`/sbr filler wand|flay|smite`) so the priest never casts itself dry. A **Use wand** checkbox toggles wand-weaving off entirely, and if **no wand is equipped** it automatically fills with *Mind Flay* or *Smite* instead — so the wand is never a dead press.
* **Spirit Tap Finisher:** under a configurable target-health %, the rotation bursts with *Mind Blast* then *Smite* to **secure the killing blow** — and the experience that feeds *Spirit Tap*.
* **Mitigation, Not Over-Bubbling:** *Power Word: Shield* is cast when a mob reaches melee or you drop below half health — and it is **gated on *Weakened Soul*** in every mode, so it never wastes a cast trying to re-shield through the debuff.
* **Shadow (endgame):** hold *Shadowform* (which auto-skips every Holy cast), open *Mind Blast* for *Shadow Weaving*, keep the DoTs up, and fill with channelled *Mind Flay*. **Turn *Shadow Word: Pain* off for raids** to respect debuff-slot limits.
* **Responsive Healing (Disc/Holy):** healing is triage, not a fixed rotation. Aegis picks the most-hurt *reachable* party/raid member and **downranks** *Heal* / *Greater Heal* / *Flash Heal* to the size of the deficit (the `+healing` bonus is read from gear, override `/sbr healpower <n>`; *Spiritual Healing* is factored in). *Flash Heal* is **reserved for emergencies** (`/sbr flashat <%>`), *Greater Heal* covers big deficits, *Heal* the efficient sustained healing, and *Renew* / *Power Word: Shield* maintain a mildly hurt unit. *Prayer of Healing* fires when several members are hurt, **fronted by *Inner Focus*** (when ready) to negate its mana cost.
* **Offensive Weave & Lightwell:** between heals it can weave *Smite* / *Holy Fire* as offensive support, and place *Lightwell* when out of combat.

> **Verification note:** Heal values are tuned approximations — the rank tables sit at the top of `Class_Priest.lua`; adjust them if downranking over- or under-heals. The *Shadow Weaving* / proc behaviour and the exact *Enlighten* mechanic are best-effort, so confirm names in-game with `/sbr talents` and `/sbr debug`. *(Multi-target Shadow spreads its DoTs as you tab between mobs; the engine is single-target by design and does not tab for you.)*
</details>

<details>
<summary><b>🪄 Mage</b> — Frost / Fire / Arcane, with Turtle's custom spells</summary>

Frost, Fire, and Arcane in one mode-adaptive module, working from level 1 to raiding — switch specs live with `/sbr mode frost|fire|arcane`:

* **Three Specs, One Button:** **Frost** (the kiting / *Icicles* spec and best leveler), **Fire** (Scorch debuff + Fireball burst), or **Arcane** (Rupture upkeep + Arcane Missiles). The panel *Spec* dropdown or `/sbr mode` switches between them; every ability is *KnowsSpell*-gated, so a level 1 mage plays correctly and each spell switches itself on as it is trained.
* **Frost — Kite & Icicles:** *Frostbolt* nuke, *Frost Nova* to root a mob that reaches melee, *Cone of Cold* as a close-range slow, and *Ice Barrier* kept up (a shield that also boosts Frost damage). *Icicles* is cast whenever its cooldown is up — the Turtle freeze-reset is handled implicitly: *Frostbite* / *Flash Freeze* keep resetting that cooldown, so the engine fires Icicles in the empowered window automatically.
* **Fire — Debuff & Burst:** *Combustion* on cooldown, *Pyroblast* as a **pull-only opener** (gated to a near-full-health target so it is never a 6-second cast stuck mid-fight), *Scorch* to build and maintain the *Fire Vulnerability* debuff to a configurable stack count, *Fire Blast* on cooldown, then *Fireball*. A per-target Scorch throttle means *Fireball* still fills if the debuff can't be read.
* **Arcane — Haste & Upkeep:** keep *Arcane Rupture* on the target, pop *Arcane Power* on cooldown, use *Arcane Surge* **while not hasted** (it is skipped under Arcane Power / MQG, whose haste does not scale its 1.5s GCD), and fill with *Arcane Missiles*.
* **Leveling "Nuke then Wand":** the golden rule of Vanilla mage leveling — nuke a mob to ~30–50% then **wand it to death** to conserve mana. Below a target-health threshold (default 40%, `/sbr wandhp <0-100>`) or a mana floor the rotation finishes with the wand. The `frost` / `fire` / `arcane` presets set wand-finish to 0% for pure caster / raid play.
* **AoE Mode (`/sbr aoe`):** kite-AoE — *Frost Nova* to freeze, *Cone of Cold* to snare, *Icicles*, then *Arcane Explosion* to finish. *Evocation* restores mana when low, and channels (*Arcane Missiles*, *Icicles*, *Blizzard*, *Evocation*) are never clipped.

> **Verification note:** Turtle's custom spells were confirmed by exact name against the client spell DB (*Icicles*, *Arcane Rupture*, *Arcane Surge*, *Flash Freeze*, *Fire Vulnerability*), but their **proc / stack behaviour is best-effort** — confirm with `/sbr debug` if something isn't firing. **Ground-targeted AoE (*Blizzard*, *Flamestrike*) is not auto-cast** — it needs a cursor click a one-button rotation can't place.
</details>

---

## Commands

The primary command is `/sbr` (long form `/aegis`); `/ar` still works everywhere as a legacy
alias from the AutoRota era, so old macros keep functioning.

### Everyone

| Command | What it does |
|---|---|
| `/sbr` | Fire the rotation (your one button) |
| `/sbr ui` | Open the configuration window |
| `/sbr list` | List your saved profiles |
| `/sbr use <name>` | Switch to a profile |
| `/sbr new <name> [template]` | Create a profile from a class template |
| `/sbr del <name>` | Delete a profile |
| `/sbr off` | Stop running any profile |
| `/sbr check` | Report whether the active profile suits your learned spells |
| `/sbr reset` | Reseed profiles from the class templates |
| `/sbr acquire on\|off\|assist <name>` | Targeting mode — auto / manual / mirror an ally's target by GUID |
| `/sbrmap` or `/sbr minimap` | Show/hide the minimap button |
| `/sbr debug` | Dump target debuffs and your buffs (names, stacks, textures) |
| `/sbr talents` | Dump every talent and its rank, to confirm exact talent names |
| `/sbr trace` | Toggle the per-press rotation log |

### Per class

| Command | Class | What it does |
|---|---|---|
| `/sbr mode <…>` | Hunter · Shaman · Mage | Playstyle/spec — `auto/ranged/melee` · `enhancement/elemental/tank/resto` · `frost/fire/arcane` |
| `/sbr aoe` | Warrior · Paladin · Druid · Hunter · Mage | Toggle AoE mode |
| `/sbr spell <alias> [on/off]` | Warrior · Hunter | Flip one ability on the active profile. **With no `on`/`off` it toggles**, like `/sbr aoe` — so a single keybind turns an ability on and off, and prints the new state each press. Pass `on` or `off` to force a state instead (useful in a macro that must be idempotent). Paladin form: `/sbr spell <profile> <alias> [on/off]` |
| `/sbr cd <on/elite/off>` | Warrior · Hunter | Cooldown usage mode |
| `/sbr heal <on/off>` | Paladin · Priest | Toggle heal mode |
| `/sbr healat <1-100>` | Paladin · Priest | Heal group members below this % health |
| `/sbr healpower <n>` | Paladin · Priest | Manual +healing override for downranking (0 = auto from gear) |
| `/sbr weave <on/off>` | Druid · Shaman (resto) | Weave damage between heals during downtime |
| `/sbr seal <profile> <debuff/damage> <alias>` | Paladin | Set a seal slot |
| `/sbr strike <off/hs/cs/auto/tank>` | Paladin | Set which strikes are used |
| `/sbr hsat <1-100>` | Paladin | Health % for the *Holy Shock* emergency heal |
| `/sbr flashat <1-100>` | Priest | Health % for the *Flash Heal* emergency |
| `/sbr filler <wand/flay/smite>` | Priest | DPS filler choice |
| `/sbr cp <1-5>` | Rogue | Minimum combo points before finishing |
| `/sbr curse <alias>` | Warlock | Switch the curse (`coa`, `coe`, `cos`, `cow`, `cor`, `cot`, `cod`, `none`) |
| `/sbr sting <alias>` | Hunter | Maintained sting (`serpent`/`scorpid`/`viper`/`smart`/`none`) — `smart` = Viper on mana users, Serpent otherwise |
| `/sbr style <bleed/shred>` | Druid | Cat style |
| `/sbr form <cat/bear/caster/resto>` | Druid | Preferred form/spec |
| `/sbr dance` | Warrior | Toggle experimental stance dancing |
| `/sbr wandhp <0-100>` | Mage | Target-health % to finish with the wand |

<details>
<summary><b>Ability aliases</b> for <code>/sbr spell</code>, seals, stings and curses</summary>

**Warrior** — `ms`/`mortalstrike`, `bt`/`bloodthirst`, `ss`/`shieldslam`, `ww`/`whirlwind`,
`slam`, `op`/`overpower`, `rev`/`revenge`, `exec`/`execute`, `sa`/`sunder`,
`tc`/`thunderclap`, `hs`/`heroicstrike`, `cleave`, `sweep`/`sweeping`, `dw`/`deathwish`,
`reck`/`recklessness`, `br`/`berserkerrage`, `bld`/`bloodrage`, `sb`/`shieldblock`,
`charge`, `rend`, `bshout`/`battleshout`, `demo`/`demoshout`, `mstrike`/`masterstrike`

**Hunter** — `mark`/`hm`, `steady`/`st`, `arcane`/`as`, `multi`/`ms`, `aimed`/`aim`,
`volley`, `trap`/`immolation`, `raptor`/`rs`, `mongoose`/`mb`, `lac`/`lacerate`, `carve`,
`wc`/`wingclip`, `opener`/`aimedopener`, `aspect`, `kc`/`killcommand`, `baited`, `mend`

> **Toggling Hunter's Mark:** `/sbr spell mark` (or `/sbr spell hm`). Bind that to a key and
> each press flips it, reporting `Hunters Mark on.` / `Hunters Mark off.` in chat — the same
> feel as `/sbr aoe`. `/sbr spell mark on` and `/sbr spell mark off` still set it absolutely.

**Paladin seals** — `sotc`/`crusader`, `sor`/`righteousness`, `soc`/`command`,
`sow`/`wisdom`, `sol`/`light`, `none`

**Hunter stings** — `ss`/`serpent`, `sco`/`scorpid`, `vs`/`viper`, `smart`/`vs>ss` (Viper on
mana users, else Serpent), `none`

**Warlock curses** — `coa`, `coe`, `cos`, `cow`, `cor`, `cot`, `cod`, `none`
</details>

---

## A few honest notes

- **The priorities are hand-tuned, and audited in the open.** `docs/rotations.md` holds the
  researched Turtle 1.18.1 priority for every spec, and
  `docs/audit-phase1-rotations.md` is a per-class report of **where the code and that
  research disagree** — each with a recommendation and the risk of changing it. Nothing is
  quietly "fixed" on paper; changes get tested.
- **Some Turtle spell and proc names are best-effort.** Turtle adds and renames things, and
  a talent's *buff* often has a different name than the talent. Everything is gated, so a
  wrong name simply no-ops rather than erroring — if something never fires, `/sbr debug` and
  `/sbr talents` show you the real strings.
- **AoE is a manual toggle, deliberately.** The 1.12 client can't reliably count nearby
  enemies, so `/sbr aoe` is a keybind rather than a guess.
- **Ground-targeted spells aren't auto-cast** (Blizzard, Flamestrike, Hurricane). They need a
  cursor placement a one-button rotation can't make for you.
- **Mind the debuff cap.** Turtle enforces 32 buffs / 16 debuffs per unit. On raid bosses,
  turn off low-value debuff upkeep (that's why *Shadow Word: Pain* and *Demoralizing Shout*
  have toggles).
- **Imbues and poisons stay off the rotation macro.** Re-imbuing costs a global cooldown, so
  Shaman imbue upkeep auto-applies out of combat and only *reminds* you in combat. Poisons
  need a real click to apply, so they live on the Quick Bar's buttons rather than being cast
  by the rotation.
- **PvP and auto-defensives aren't here yet.** No Ice Block, Shield Wall, or Divine Shield
  automation — that's a planned phase, not a shipped feature.

---

## Under the hood

```
Aegis_SBR/
├── Aegis_SBR.lua           core engine: rotation entry, profiles, targeting,
│                           shared helpers (spell index, buff/debuff snapshots,
│                           swing timer, weapon enchants)
├── Aegis_SBR_UI.lua        config window shell, flat-dark theme, layout
│                           primitives (rows, dropdowns, sliders, spec tabs)
├── Aegis_SBR_BuffUp.lua    optional upkeep monitors: buff watch + rebuff
│                           buttons, and the rogue poison Quick Bar
├── Aegis_SBR_Minimap.lua   minimap button + addon options panel
├── classes/                one rotation module + one config panel per class
│   ├── Class_Warrior.lua      the priority list and its gates
│   ├── Class_Warrior_UI.lua   that class's panel
│   └── …                      ×9 classes
├── Icons/                  flat-dark UI textures (TGA)
├── Fonts/                  PT Sans Narrow (OFL)
├── docs/                   rotation reference, Turtle mechanics, dependency
│                           stack, roadmap, and the per-class rotation audit
└── scripts/verify.py       Lua 5.0 static verifier
```

**One cast per press** is enforced by structure: each priority step returns immediately after
it fires, so a press can never issue two casts and clip itself.

**Everything is Lua 5.0 and 1.12 API only** — no `string.match`, no `#`, no `%` operator, no
secure hooks, and every file must load top-to-bottom in one pass. `scripts/verify.py` checks
bracket balance and define-before-use ordering across the addon; it runs after every change,
because these break at *runtime*, not at load. [`CLAUDE.md`](CLAUDE.md) has the full ruleset
and the reasoning behind each rule.

---

## Something broken?

1. Check the **version** — it's on the config window header and in the `.toc`. Quote it.
2. Run **`/sbr debug`** (live buff/debuff names) and **`/sbr trace`** (per-press decisions).
   Between them, most "why won't it cast X" questions answer themselves.
3. Tell us on **[Discord](https://discord.gg/hsgPTNkSX)** or open an
   [issue](https://github.com/Torchlite-bit/Aegis_SBR/issues). Screenshots help enormously,
   especially for anything layout-related.

<details>
<summary><b>"Unknown command: /sbr"</b> from MacroErrorChecker and friends</summary>

That's a false positive. Macro validation addons check against a static list of Blizzard's
built-in slash commands and can't see third-party slash engines. If `/sbr ui` opens the
window, everything is working — ignore the warning, or whitelist the command (SCRM supports
this).
</details>

<details>
<summary><b>My character uses abilities but doesn't auto-attack</b></summary>

On a melee class, Aegis starts your white swing by toggling the standard **Attack** ability,
which it finds by scanning your action bars. If **Attack** isn't on any bar, there's nothing
to toggle. Drag it from your spellbook (**P** → *General*) onto any slot — and for Druids,
onto a bar that survives shapeshifting. (With **SuperCleveRoidMacros** installed, it manages
attacks instead and Aegis stays out of the way.)
</details>

---

## Contributing

PRs welcome — come say hi on **[Discord](https://discord.gg/hsgPTNkSX)** first if you're
planning something big.

Four requests:

1. Keep inside the 1.12 / Lua 5.0 rules in [`CLAUDE.md`](CLAUDE.md) — they're there because
   breaking them fails at *runtime*, not at load.
2. Run `python3 scripts/verify.py --all` before you push. It must pass.
3. **Don't change a rotation priority without saying why.** The per-class lists are
   hand-tuned; if research disagrees with the code, that belongs in
   `docs/audit-phase1-rotations.md` as a discussion, not a silent edit.
4. Bump the version in **all three** spots (`.toc`, `ver` in `Aegis_SBR.lua`, the README
   version badge) and add a line to [`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).

---

<div align="center">

**[💬 Discord](https://discord.gg/hsgPTNkSX)** · **[📜 Changelog](CHANGELOG.md)** · **[🐛 Issues](https://github.com/Torchlite-bit/Aegis_SBR/issues)**

*Aegis: Single Button Rotation is part of the Aegis addon series. One key. Go fight something.* ⚔️

</div>
