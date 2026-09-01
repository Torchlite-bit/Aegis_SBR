# Aegis_SBR — Architecture & Conventions

How the addon is put together, and the conventions to follow. Read this before working in
an area you haven't touched. (File names reflect the post-rebrand state as of v0.14.0.
Shared globals: core `Aegis_SBR`, UI `Aegis_SBR_UI`, layout `Aegis_SBR_Layout`, minimap
`Aegis_SBR_Minimap`; named frames use the `Aegis_SBR_*` prefix, UI-internal element names
the `AegisUI_*` prefix.)

## File layout (load order matters — set by the .toc)
- **Core / shell**: `Aegis_SBR.lua` (was `AutoRota.lua`) — the engine tick, event frame,
  slash handling (`/sbr`, `/aegis`, legacy `/ar`), profile management, saved-variables
  (`AegisDB`, plus the `AutoRotaDB` migration shim in `OnAddonLoaded`), shared helpers
  (`EnsureAutoAttack`, `InMeleeRange`, `KnowsSpell`, `ScanTargetDebuff`, `Queue`, etc.),
  the class-module dispatch.
- **Shared UI framework**: `Aegis_SBR_UI.lua` (was `AutoRota_UI.lua`) — the config window,
  theme/palette, all UI primitives (see below), the scroll system, header/footer, profile
  pill, spec tab rails.
- **Minimap**: `Aegis_SBR_Minimap.lua` (was `AutoRota_Minimap.lua`) — button + options
  (`/sbrmap`, legacy `/armap`).
- **Capability layer**: `Aegis_SBR_Capabilities.lua` (v1.1.9) — loads SECOND, right after the
  core, because everything below may ask it questions. Owns **every** `C_*` probe and wrapper
  (ClassicAPI is *Recommended*, never *Required*, so nothing else may call one directly — see
  CLAUDE.md's `C_*` carve-out) plus the passive probe log behind `/sbr capi` and `/sbr probe`.
  Every wrapper returns `nil` for "unknown", and `nil` is never `0` and never `false`.
- **Preview**: `Aegis_SBR_Preview.lua` — the next-ability window. Runs a module's `Rotate`
  in decide-mode (`Aegis_SBR.deciding`) so it reports the choice WITHOUT casting; modules opt
  in with `M.previewReady = true`. This is why terminal operations are two-mode: `Pick` /
  `PickQueue` record into `decidePlan` instead of casting, and `Later(fn)` skips side effects
  entirely while deciding.
- **Pet**: `Aegis_SBR_Pet.lua` — the pet window (Hunter/Warlock).
- **Range**: `Aegis_SBR_Range.lua` (v1.1.9) — the distance window, with a self-calibrating
  melee / dead-zone / ranged scale. Its distance comes from **UnitXP_SP3 (Required)**, not
  ClassicAPI — getting that source order wrong made the window dead on arrival without the
  DLL in the first draft.
- **Per-class rotation modules**: `Class_<Name>.lua` (Warrior, Paladin, Hunter, Rogue,
  Priest, Shaman, Mage, Warlock, Druid) — the priority lists + class helpers.
- **Per-class UI panels**: `Class_<Name>_UI.lua` — the config panel for that class.
- **Assets**: `Icons/` (TGA textures — toggles, sliders, buttons, pills, cards, sigil),
  `Fonts/` (PT Sans Narrow, OFL-licensed + `OFL.txt`; moved into `Fonts/` at 0.14.0 to
  match the UI's font paths). The **logo** is stubbed: the header tries
  `Interface\AddOns\Aegis_SBR\logo` (addon ROOT, `logo.tga` once it exists — power-of-two,
  32-bit) and falls back to the sigil + wordmark while absent; new textures need a full
  relog.
- **Meta**: `.toc`, `README.md`, `CHANGELOG.md`, `docs/`, `scripts/verify.py`,
  `docs/TALENTS_1_18_1.md` (talent name reference used by the modules).

## Rotation model
- Each class module exposes `M:Rotate(cfg)` (and spec sub-rotations). On each press the
  engine calls into the active module; the priority list is evaluated top-down; the FIRST
  ability whose gate passes is cast and the function RETURNS (strict single-cast, no GCD
  clipping). Gates check: known/learned, cooldown ready, resource floor, range, stance/form,
  debuff/proc windows, and the user's per-ability toggles.
- Casting primitives: `Cast(name)` (reports success if merely KNOWN — see the caveat in the
  Warrior module header), `Queue(name)` (uses Nampower queueing), `Try(name)` /
  `CanCast(name, cost, stances)` wrappers in some modules.
- Shared resource/timing helpers (core, v1.1.8+): `Aegis_SBR:SpellCost(name)` /
  `CanAfford(name)` read a spell's real cost off the spellbook **tooltip** (cached, dropped
  on `SPELLS_CHANGED`/`CHARACTER_POINTS_CHANGED`) instead of a hardcoded table, so a talent
  that shifts a cost is never fought — prefer this over a new per-class rage/energy/mana
  table. `Aegis_SBR:TargetTTK()` estimates seconds-to-kill from a rolling window of the
  target's health percent; it returns `nil` (never a guess) until it has enough samples,
  and every caller must treat `nil` as "not dying soon" — it is accurate enough to **veto**
  an action, not to **trigger** one (see the Rogue execute logic for the failure mode when
  that line was crossed: TTK briefly triggered execute and fired it on a single combo point
  against ordinary trash, since a normal mob's whole life is shorter than any sane window).
  `Aegis_SBR:SpellRadius(name)` and `Aegis_SBR:SpellDuration(name)` (v1.1.9) read the same
  way and for the same reason — both numbers are **rank dependent**, so a hardcoded table is
  wrong for every rank but one. `SpellDuration` exists because rank 1 *Searing Totem* lasts
  30s where the shaman's table said 55, leaving a levelling shaman's fire slot empty for 25
  seconds. Both return `nil` when the tooltip cannot be read, and callers keep their own
  fallback: these correct a number, they do not replace the caller's judgement.
- Movement (core, v1.2.5): `Aegis_SBR:Moving()` and `StillFor(seconds)`. The 1.12 client has
  no speed API, so position is sampled and differenced through SuperWoW's `UnitPosition`. It
  answers **"standing still" whenever it cannot tell** — "cannot judge" must never block a
  cast, the same stance every other unreadable source takes here. `StillFor` exists because
  stopping is not a commitment to stay stopped (Consecration waits out a 2s dwell).
- Cast outcome (core, v1.2.3/v1.2.5): `NoteSpellCast(name)` records the spell last sent and
  `SpellRefusedSince(name, t)` reports whether the client refused it since `t`. **Needed
  because `Pick`/`PickQueue` return true on "known and affordable", not on "accepted"** —
  out-of-range, line-of-sight and facing refusals arrive as an error message and never reach
  the combat log. Compare by timestamp, not by ordering: the error and the stamp can land in
  either order within one frame.
- Heal engines: four near-identical copies live in the healer modules
  (Paladin/Priest/Druid/Shaman) — slated for dedupe (roadmap Phase 2). Touch with care;
  changing one usually means changing all four until deduped.

## UI primitives (in the shared UI file)
- **`Row`** — the single-row layout: `[toggle] label [sub] ......... [slider] [value]` with
  hairline separators. Every class panel is built from `Row`. Uniform slider column;
  when a spell isn't learned, the row hides its slider and gives the label full width. Read
  the `Row` implementation before changing panel layout — it's shared by all 9 classes.
- **`BindCheck(item, on, spellName)`** — binds a toggle to config + appends "(not learned)"
  and greys/hides the slider when the spell is untrained. Central to every panel refresh.
- **`Dropdown`** — full-width picker with a fixed label column (boxes align across rows),
  centered box text, ink label color.
- **`SkinButton` / `SkinClose`** — rounded button/close art (layered TGA for a 1px rounded
  border; accent = filled).
- **Section cards** via `NineSlice` on `Card.tga`; **spec tab rails** via
  `BuildSpecTabs`/`SelectSpecTab` (Reflow shows only the active spec's sections);
  boolean-bound rails (Paladin Damage|Healer) use encode/decode hooks.
- **Scroll system**: `MakeScroll` + `UpdateScrollRange` — the bar hides unless overflow
  exceeds the bottom pad; the thumb is a small fixed grip inset in a full-span groove so it
  never overhangs (a hard-won 1.12 slider fix — don't revert to a proportional thumb).

## Events (core event frame)
- `ADDON_LOADED` (init + the Phase 0 DB migration), `PLAYER_LOGIN`, `SPELLS_CHANGED`
  (invalidate spell index + validity cache), `CHAT_MSG_COMBAT_SELF_HITS/MISSES` (swing
  tracking), `PLAYER_REGEN_ENABLED`, and **`UNIT_CASTEVENT`** (SuperWoW; resolved via
  `SpellInfo(arg4)` and dispatched to the active module's `OnCastEvent` if it defines one —
  currently Shaman totem tracking).
- **Before writing casting/detection code, read `docs/dependencies.md`** — the actual
  SuperWoW / Nampower / SuperCleveRoidMacros APIs, events, and limits (e.g. Nampower's
  one-GCD-queued / one-non-GCD-per-tick constraints, GUID hex-string handling).

## Conventions
- **Lua 5.0 only** — see CLAUDE.md Hard Constraints (`table.getn`, `math.mod`, no
  `string.match`, event globals `arg1…`).
- **Define before use** within each file (single-pass loader). The ordering audit in
  `verify.py` enforces this per file; cross-file order is the `.toc` order — keep it stable.
- **Comments explain WHY.** Match the existing flat-dark palette and naming.
- **Textures**: power-of-two TGA, referenced without extension, double backslashes; new/
  renamed textures need a full relog.
- **Versioning**: `1.1.0` and up as of the release cut (ran `0.14.0`–`0.16.2` post-rebrand;
  letter-suffix `0.13.xb` was the pre-rebrand scheme); bump `.toc` + core `.lua` `ver` + the
  **README H1** together and prepend a `CHANGELOG.md` entry; grep to confirm no stale
  version strings remain.
- **Profiles**: `NormalizeProfile` fills MISSING keys only (never clobbers user values) — so
  adding a config field is backward-safe. Templates per spec provide sensible defaults.

## Verifier (scripts/verify.py)
- `python3 scripts/verify.py --all` after every edit: balance check + define-before-use
  ordering audit over all `.lua`. Non-zero exit on failure (can gate a commit hook).
- It's a heuristic static check, not a Lua parser — it catches the common silent-load-crash
  classes but not semantic errors. Always still test in-game.
