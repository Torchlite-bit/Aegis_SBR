# Aegis_SBR — CLAUDE.md

> Project brief for Claude Code. Read this first, every session, before touching code.

## Project Overview (WHY)
**Aegis: Single Button Rotation** (repo/folder: `Aegis_SBR`, formerly "AutoRota") is a
one-button rotation-engine addon for **Turtle WoW** — a private Vanilla+ server running a
custom **1.12 client, patch 1.18.1**. It executes exactly **one primary ability per key
press** using strict single-cast priority lists, to avoid global-cooldown clipping. It
reads combat state (mana/rage/energy, procs, debuff windows) and fires the highest-priority
ability for the player's class/spec/context. Users tune priorities in an in-game config UI
(flat-dark theme, spec tab rails, per-class ability toggles) with per-profile management.

Author tag: "Mercaius & Subtilizer (Torchlite)".

## ⛔ CRITICAL RULES (read first, never violate)
1. **NEVER change rotation or ability-priority logic without explicit user approval first.**
   The existing per-class priority lists are hand-tuned. When the research in
   `docs/rotations.md` disagrees with what a module actually does, your job is to **REPORT
   the discrepancy and ask** — produce a written diff (what the code does vs. what the
   research says, with the source/confidence tag) and WAIT for the user to decide, per
   class. Do not "fix" rotations proactively, even if you're confident. Non-rotation work
   (rebrand, UI, tooling, bug fixes that don't alter priority) does not need this gate, but
   anything that changes WHICH ability fires or in WHAT ORDER does.
2. **The Phase 0 rebrand to Aegis_SBR is DONE (v0.14.0)** — folder/.toc/files renamed,
   `/sbr` primary (+ `/aegis`, legacy `/ar`), `AutoRotaDB` → `AegisDB` migration shim in
   place. Do not reintroduce the old names; keep the shim + toc backup line until the
   deprecation window closes (see `docs/roadmap.md` Phase 0).
3. Run `python3 scripts/verify.py --all` after every edit; never hand off a failing file.

## Current State / Next Task
The rebrand shipped as **v0.14.0** (pending the user's in-game verification: profile
migration, `/sbr` + `/ar`, zero load errors). The addon is **Aegis_SBR** throughout:
core global `Aegis_SBR`, UI `Aegis_SBR_UI`, layout `Aegis_SBR_Layout`, minimap
`Aegis_SBR_Minimap`, frames `Aegis_SBR_*`/`AegisUI_*`, saved variable `AegisDB` (old
`AutoRotaDB` still toc-listed as a rollback backup — drop it + clear on PLAYER_LOGOUT a
few versions from now). **The Phase 1 audit-and-report is DELIVERED (v0.14.1)**: see
`docs/audit-phase1-rotations.md` — a per-class discrepancy report (all 9 classes) with
source/confidence/action/risk per finding, plus the roadmap-pre-authorized Hunter
sting-detection fix (the only code change; no priorities touched). **Next: the user
signs off findings per class; approved items are then implemented as their own gated,
verified batches** (Critical Rule #1 still applies to every one of them).

**Logos:** the user will provide raw logo image files LATER. They need converting to TGA
(power-of-two dimensions, 32-bit, GIMP/uncompressed export — see `docs/roadmap.md` Phase 0
step 6 and `docs/architecture.md`). The header stub is already wired: it tries
`Interface\\AddOns\\Aegis_SBR\\logo` and falls back to the sigil + wordmark while the
file is absent (1.12 `SetTexture` returns nil for a missing file). Drop the TGA in the
addon root as `logo.tga` and do a **full relog** to see it.

All 9 class panels use a unified single-row config layout; all four healer specs have
config panels; a Shaman totem system maintains totems across every spec via SuperWoW's
`UNIT_CASTEVENT`. **Phase 2 has begun (v0.15.0):** a shared weapon-enchant detection
helper (`Aegis_SBR:WeaponEnchant`/`WeaponEnchantId`, `GetWeaponEnchantInfo`-based) plus the
first gated behavior — Shaman main-hand imbue upkeep (out-of-combat auto-apply, in-combat
opt-in, default OFF) and a Rogue poison pre-pull reminder (warn-only). Off-hand imbue,
poison auto-apply, and the Shaman totem-destruction detection remain open Phase 2 items.
Current version: **0.15.0**.

## Tech Stack / Hard Constraints (WHAT — read carefully, these bite)
- **Language: Lua 5.0** (Turtle 1.12 client). Non-negotiable:
  - Use `table.getn(t)` — **NOT** `#t`.
  - Use `math.mod(a, b)` — **NOT** `a % b`.
  - `string.find` and `string.gsub` EXIST. `string.match` / `string.gmatch` **DO NOT** —
    parse with `find` + captures via `gsub`, or hand-rolled loops.
  - Available: `ipairs`, `pairs`, `pcall`, `setmetatable`, `getglobal`, `next`,
    `string.format`, `tinsert`/`tremove`, `getn`.
  - **Event handlers use the globals `event`, `arg1`, `arg2`, …** — NOT a
    `function(self, event, ...)` signature. (`this` is the frame.)
- **Single-pass loader**: each file loads top-to-bottom exactly once, in `.toc` order.
  Every local function/table must be **DEFINED BEFORE USE** within its file. This is the
  #1 source of silent load crashes. The ordering audit (below) exists to catch it.
- **Required dependency stack** (do NOT assume retail/other APIs exist) — **read
  `docs/dependencies.md` for the actual APIs/events/behaviors before writing engine code**:
  - **SuperWoW** — `CastSpellByName(name[, unit])`, `UNIT_CASTEVENT` (cast detection with
    caster GUID + spell id), `SpellInfo(id)` (id → name), unit GUIDs, combat-log owner tags.
  - **Nampower** — spell queueing / cast timing. **One GCD spell queued at a time; one
    non-GCD spell per server tick.** Maintained fork moved to gitea.com/avitasia; expanded
    Lua API (`SCRIPTS.md`) + custom events (`EVENTS.md`). Confirm the installed fork/version.
  - **SuperCleveRoidMacros** — conditional macro engine. **Requires Nampower v3.0.0+ and
    UnitXP_SP3**; reactive abilities must be on action bars for detection; 261-char macro
    limit; enemy-debuff timers need pfUI libdebuff/Cursive. (Repo is archived/stable.)
  - Target client: **Turtle WoW 1.18.1**.
- **Custom textures**: TGA, power-of-two dimensions, 32-bit (referenced WITHOUT the `.tga`
  extension in Lua paths, using double backslashes). New/renamed textures need a full
  relog to appear (not just `/reload`). Pure-code changes need only `/reload`.
- **1.12 UI quirks that have bitten us** (don't relearn the hard way):
  - CheckButton `SetCheckedTexture`/disabled-variant setters IGNORE file paths — you must
    grab the template texture OBJECT via `GetCheckedTexture`/`GetDisabledTexture` and call
    `SetTexture` on it. (`SetNormalTexture` DOES take a path.)
  - Slider thumb is a FIXED-size texture positioned by its CENTRE travelling the full
    track — a tall thumb overhangs the ends. Keep the thumb small and inset the slider
    inside a full-span groove.
- **Do NOT use**: `#`, `%`, `string.match`/`gmatch`, `C_*` namespaces, retail widget APIs,
  `SecureActionButton`/protected functions, or anything introduced after client 1.12.

## Architecture (WHAT)
- **Shared core/UI shell** + **one rotation module per class** (9 vanilla classes), each
  with a paired `*_UI.lua` config panel. See `docs/architecture.md` for the file list and
  the shared UI primitives (the `Row` layout, `BindCheck`, `SkinButton`, section cards,
  spec tab rails, the scroll system).
- **Rotation model**: on each press, the active spec's ordered priority list is evaluated;
  the first ability whose gate passes is cast, then the function returns (strict one-cast).
- **SavedVariables**: `AegisDB` after the rebrand (migrated from `AutoRotaDB` — see the
  Phase 0 migration shim in `docs/roadmap.md`).
- **Reference docs** (read the relevant one before working in that area):
  - `docs/dependencies.md` — SuperWoW / Nampower / SuperCleveRoidMacros APIs, events,
    behaviors, and gotchas. **Read before writing any casting/detection code.**
  - `docs/rotations.md` — per-class / per-spec Turtle 1.18.1 rotation priorities (the
    reference for the rotation-correctness AUDIT — see Critical Rule #1, report don't change).
  - `docs/turtle-mechanics.md` — confirmed Turtle-specific class-change facts.
  - `docs/architecture.md` — module layout, conventions, key APIs, UI primitives.
  - `docs/roadmap.md` — phased plan; the rebrand steps; what's next.
  - `docs/sources.md` — where the game/dependency knowledge comes from, which links are
    fetchable vs. paste-only, and the two update commands. **For talents, read the in-repo
    `docs/TALENTS_1_18_1.md` — do NOT try to scrape the talent calculators (they block bots).**

## Workflow (HOW — the loop, follow it every time)
1. **Run the verifier after EVERY edit**, before presenting anything:
   ```
   python3 scripts/verify.py --all
   ```
   It runs the **balance check** (bracket/string/comment balance) AND the
   **define-before-use ordering audit**. Never commit or hand off a file that fails it.
   Target a single file with `python3 scripts/verify.py Aegis_SBR.lua` while iterating.
2. **Read the actual file content before editing** — do not edit from memory of a prior
   version; the code has moved.
3. **Incremental verified batches**: make a small, coherent change; verify; then proceed.
   Roll multi-file conversions (e.g. all class panels) in small batches, not all at once.
4. **Version cut**: letter-suffix versioning (e.g. `0.13.12b` → `0.13.13b`; the rebrand
   itself is a natural cut, e.g. `0.14.0`). Bump the version in ALL canonical spots
   (`.toc`, the core `.lua` `ver = "..."`, the README H1) and prepend a `CHANGELOG.md`
   entry. Keep them in sync — grep to confirm no stale version strings remain.
5. **Preserve `.toc` load order** — reordering files can break the single-pass loader.
6. Prefer **minimal, surgical diffs**; match existing code style and naming exactly.
7. Confirm the plan with the user before large changes; the user tests in-game and reports
   back with screenshots.

## Keeping current (dependency / mechanics updates)
Source knowledge is kept in the docs, not fetched live every session — Claude Code re-checks
sources only when the user runs an update command. `docs/sources.md` lists which links are
fetchable vs. paste-only and holds the two commands:
- **Command 1 (dependency refresh)** — check the SuperWoW/Nampower/SuperCleveRoid changelogs
  against their last-verified dates and update `docs/dependencies.md`. Run when a mod ships a
  new version.
- **Command 2 (mechanics refresh)** — re-check the Turtle Wiki against `docs/turtle-mechanics.md`
  / `docs/rotations.md` and report a discrepancy list. Run after a Turtle patch. Rotation
  priority changes still go through the audit-and-report gate (Critical Rule #1).
When you update a doc from a source, bump that source's "last verified" date in
`docs/sources.md`. For talents, consult `docs/TALENTS_1_18_1.md`; the online
calculators block automated access.

## Definition of Done (per change)
- Passes `python3 scripts/verify.py --all` (balance + ordering).
- No forbidden Lua 5.1+/retail constructs (see Hard Constraints).
- If a texture was added/renamed: noted that a **full relog** is required.
- Version bumped + CHANGELOG entry added when cutting a version; all version spots in sync.
- Files ready for the user to pull and test in-game.

## House style
- Comments explain WHY, not what. Keep the flat-dark UI conventions and palette already in
  the code. Don't introduce new dependencies. Don't refactor unrelated code in a feature
  change. When you fix a class of bug, add a one-line note to this file so it isn't
  relearned.
- **Lessons already learned (don't relearn):**
  - `verify.py`'s ordering audit only flags a local defined past the calling body's END —
    a function's own inner locals (incl. closure captures) are legal, don't "fix" them
    (fixed 0.14.0; three historical false positives were exactly this).
  - When scripting bulk renames, run mechanical sweeps BEFORE inserting text that
    intentionally mentions the old name (migration shims, "formerly X" notes, legacy-alias
    comments) — or the sweep eats your own insert.
