# 📜 Changelog

All notable changes to **AutoRota** are documented here. Versions are listed newest first.

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
