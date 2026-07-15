# 📜 Changelog

All notable changes to **Aegis: Single Button Rotation** (formerly **AutoRota**) are documented here. Versions are listed newest first. Entries up to v0.13.15b predate the rebrand and keep their original AutoRota/`/ar` wording.

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

**Fix + tuning.** Closes a heal-mode gating gap in the Paladin's damage rotation, reworks the heal-spell/rank choice with a QuickHeal-inspired efficiency comparison, and fixes the new Assist targeting mode being silently inert for any support module (currently only the paladin heal mode). Developed and tested in-game on a Holy Paladin.

- **Rogue: max-rank trace.** `/ar trace` now reports the max known rank for every ability the rotation casts. All Rogue casts are bare `CastSpellByName(name)`, which vanilla already resolves to the highest known rank, so this line exists to make that fact verifiable in-game rather than assumed.
- **Fix — Paladin damage/tank rotation steps leaking into heal mode.** *Strike*, *Holy Shield*, *Consecration*, *Hammer of Wrath*, *Repentance*, and *Exorcism* were missing a `not cfg.healMode` guard, so a toggle left on from the Damage tab (most visibly *Crusader Strike*) kept firing in heal mode outside its intended purpose (the Blessed Strikes Holy Shock reload), contradicting the Healer tab's own "Tank / Damage settings are ignored" description. All six steps are now gated consistently.
- **Paladin: heal-rank selection reworked**, inspired by QuickHeal's approach:
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
