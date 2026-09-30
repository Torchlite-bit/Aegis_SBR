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
**Current release: v1.2.39.**

### Releases publish themselves (since v1.2.39) — never push a `v*` tag by hand
`.github/workflows/release.yml` tags and publishes every version that reaches `main`. The push
run reads `## Version:` from the `.toc` and tags `vX.Y.Z` if that tag does not exist, then
starts itself again on the tag; that second run writes this version's `CHANGELOG.md` entry into
`RELEASE_NOTES.md` and packages with `BigWigsMods/packager`. **A merge that does not change the
version releases nothing**, so docs and tooling PRs are free.

The release checklist is therefore unchanged: bump the version in all three places, add the
CHANGELOG entry, merge. Three things in that workflow look redundant and are load bearing —
`docs/dev-workflow.md` says which and why. `.pkgmeta` sets `package-as: Aegis_SBR` because the
repository is still named `AutoRota` and WoW loads an addon only from the folder matching its
`.toc`.

### What v1.2.31–v1.2.39 added
Mostly core surface. Use it rather than re-implementing it:

| Area | Core API | Command |
|---|---|---|
| Learned immunity table, **account-wide** (`AegisImmune`) | `KnownImmune`, `NoteImmune`, `ForgetImmune`, `OnImmuneLine` | `/sbr immune` |
| Enemy casts, for interrupts | `EnemyIsCasting`, `EnemyCastName/Start/Duration`, `TargetCastName/Start/Duration` | — |
| Enemy count | `EnemiesNear`, `EnemiesNearCached` — one nameplate walk serves the count and the CC scan | — |
| Profiles as text | `ExportProfile`, `ImportProfile` | `/sbr export`, `/sbr import` |
| Per-tab settings layers | `TabView`, `PressModeHeld` | — |
| Other | `PickAt`, `DisarmActive`, `SpellRefusedAnySince` | — |

`AegisImmune` is the first SavedVariable that is **not** per character; every other one is.

Per class in that window: **Mage** the Arcane Missiles gap (v1.2.31 — the lesson it left is in
the Lessons list); **Warlock** four dead ends found in one log, a spell lock that left the
rotation standing, and the four-second hole after the DoTs; **Warrior** interrupts, automatic
AoE, CC respect and the swing after a disarm, contributed by **Dio**; **Rogue** the Subtlety
raid rotation ability by ability, and Rupture held off targets that will not live long enough
for it; **Paladin** the emergency that waited behind the heal; **Hunter** Beast Mastery and
Survival rewritten to their guides.

Older history is in `CHANGELOG.md` and is not summarised here — it went stale at v1.2.7 and
stayed that way for thirty-two releases, which is the argument against keeping a running
narrative in the file that is read first.

### Decisions that still bind
**Version scheme.** `1.1.0` and up; **v1.3.0 was renumbered to v1.2.3** after the fact (nothing
broke or was removed, so a minor bump overstated it) and the CHANGELOG entry carries the final
number. The user's stated preference is patch bumps unless something actually breaks or is
removed; do not reach for a minor bump because a release feels large.

**Open question, deliberately unresolved:** whether `ratioHealthy` (Paladin heal, default 60)
should move. Three logged sessions at 60/70/80 were compared and the first reading favoured 80 —
until crit counts were checked: the 80 run had 4 crits in 14 landings against 1 in each of the
others, and with crits removed the ordering reverses. **13–19 casts per setting cannot answer
this**; roughly 100 would, or a log field recording what each cast would have healed without the
crit. Do not change the default on the strength of the numbers currently in hand.

**The dev folder is on `local/integration` and stays there (since 2026-09-01).** Never
`git checkout` in it — that is what silently reverts files belonging to other branches, and the
live folder is fed only from this copy. To build a PR, use a throwaway worktree off
`origin/main`; to add to an open PR, a worktree on its existing branch. Both recipes are in
`docs/dev-workflow.md`, which is worth reading before the first commit of a session.

**Standing check, not a snapshot:** merged branches keep accumulating on the remote because
deletion needs the user (it is refused from this sandbox). Run

```
git branch -r --merged origin/main
```

at the start of a session; anything besides `origin/main` and `origin/HEAD` is landed and
deletable. `docs/dev-workflow.md` asks for deletion on merge — it is what makes GitHub retarget
anything still based on them, and what keeps that command usable as a check for what has actually
landed. **Do not restate the current list here** — a snapshot in a file that is read first goes
stale within days.

**This repository has more than one active contributor.** Re-sync at the start of every session
rather than trusting the working copy; several releases can land between sessions, and the
contributor shipping them does not update this file.

### ClassicAPI integration (shipped in v1.1.9)
ClassicAPI is now **installed and active on the dev client** (`CLASSIC_API_VERSION = 10911`,
alongside SuperWoW + Nampower + UnitXP_SP3; nothing in the Required stack broke). The `C_*`
ban is amended — see Hard Constraints; all access goes through **`Aegis_SBR_Capabilities.lua`**,
which owns every probe and wrapper and returns `nil` for "unknown".

New files: `Aegis_SBR_Capabilities.lua` (capability layer + passive probe log),
`Aegis_SBR_Range.lua` (distance window with a self-calibrating melee/dead-zone/ranged scale),
`scripts/read_probe.py` (reads the probe SavedVariable off disk). New SavedVariable
`AegisProbe`; new commands `/sbr capi`, `/sbr probe`, `/sbr range`.

**Wired into rotations (all suppress-only unless noted):** Warlock `DotRemaining` prefers the
real expiry; Shaman Flame Shock holds on a known remaining time (covers Turtle's Molten Blast
refresh, audit item **S1**); Shaman totems read the element slot directly and react to
`PLAYER_TOTEM_UPDATE` — **this closes the open Phase 2 item "totem-destruction detection"**;
Hunter sting and `DebuffUpAny` for Hunter's Mark. The `markOK` fix is the one change on the
"adds casts" side and is **flagged for play-test**.

**v1.2.28 (ClassicAPI 1.15.3, `CLASSIC_API_VERSION = 11503`):** `StartRepeating(name)` and
`StartMeleeAttack()` in the capability file wrap `CastSpellNoToggle` / `StartAttack` — starts
that can never stop. Used by Hunter Auto Shot, Mage/Priest/Warlock `Shoot` and the bar-less
branch of `EnsureAutoAttack`; the Warlock's two deliberate wand *stops* pass `stop=true` and
keep the toggle. Capabilities `notoggle` / `startattack`, probed per function. The
`StartAttack` every-press restart is on the "adds" side and **flagged for play-test**. Same
DLL: `C_AddOns` lacks `GetAddOnMetadata` (an upstream gap, not ours); everything Aegis probes
is unchanged in name and shape.

**REVERTED, do not re-apply without a play-test:** the `InMeleeRange()` melee-range
integration. Field data justifies it (49 of 128 boundary flips disagree with the 9.9yd proxy;
the bounding-radius effect confirmed on a worldboss) but it is on the "adds casts" side and
its sibling change caused the Auto Shot regression — see the Lessons list and
`docs/research-classicapi.md`.

**Verified in play (2026-08-18):** enemy debuff timers with caster; combo-point + talent
durations (Rupture at 5 CP reads 22s = 16 base + 6 from *Taste for Blood*); Warlock DoT
durations matching the module's own model to the decimal; totem destruction (Totemic Recall
emptied two slots in one instant, both back in 0.11s / 0.34s); spell range in both directions
with the bounding-radius effect on a worldboss.

**The no-ClassicAPI fallback is verified too** — Hunter and Shaman both run with
`ClassicAPI.dll` removed from `dlls.txt`: no load errors, rotation fires, totems are placed,
the range window shows a real distance. That last one only works because the distance comes
from **UnitXP_SP3** (Required), not from ClassicAPI; getting that source order wrong is what
made the window dead-on-arrival without the DLL in the first draft.

**Still open:** Shaman *Flame Shock* + *Molten Blast* refresh (audit item S1 — needs Elemental
spec, no Flame Shock cast under the probe yet); `markOK` against **another** hunter's Mark in a
raid; `C_LossOfControl` (wrapped but unused); the whole Subtlety rogue path. Also unconfirmed:
whether the tooltip-duration fix actually shortens rank-1 Searing to ~27s — it is dead code on
a ClassicAPI client, so only a no-ClassicAPI shaman exercises it, and the run so far only
confirmed that totems are placed at all.

The probe log collects most of this passively — `/sbr probe on`, play, `/reload`, then
`py scripts/read_probe.py`.

### Carried forward
- **Warrior Overpower — RESOLVED in v1.2.27, and this note used to say otherwise.** The
  defect named here was real: `Pick` answers true when the spell is KNOWN, not when the client
  accepted the cast, so the window was closed on a refusal and the proc spent on nothing. The
  fix proposed here is the fix that shipped — `SpellRefusedAnySince` now keeps the window open
  when the client refused within half a second, and only the cooldown starting (which a refused
  cast never starts) closes it as spent. See `Class_Warrior.lua`, the `overpowerAttemptAt`
  block. **One loose end:** the v1.2.32 changelog still reads "Overpower still stands: the proc
  is discarded when the cast is refused", which contradicts both v1.2.27 and the current code.
  Either that line is stale or the ORIGINAL play report (passed over for Slam/Heroic Strike) is
  separately unconfirmed. Ask before acting on either reading.
- **PR #32's `holyLightPct` — resolved, and the old note here was wrong twice.** It was NOT
  "closed unmerged, never shipped": the gate DID ship (5447c7e, v1.1.8), and was then
  deliberately **retired** in the v1.2.0 Paladin healing rebuild (014d655). The field is now
  actively cleared (`c.holyLightPct = nil`, `Class_Paladin.lua`) rather than left dormant,
  because a hidden setting that still acts is worse than a visible one. Its job is done by
  **`ratioHealthy`** (default 60) — "below this a target is hurt enough for a Holy Light, above
  it the fast heal is used whatever the deficit", which is the same sentence pointing the same
  way. So the open question ("is a slider wanted, and which way should it point?") is answered;
  do not re-raise it.
- Phase 2 leftovers: off-hand imbue, poison auto-apply beyond the Quick Bar.
- **Logos:** raw image files still pending from the user (still absent at v1.2.39). They need TGA conversion
  (power-of-two, 32-bit, uncompressed). The header stub already tries
  `Interface\AddOns\Aegis_SBR\logo` and falls back to the sigil + wordmark while absent
  (1.12 `SetTexture` returns nil for a missing file). Drop `logo.tga` in the addon root and do
  a **full relog**.
- `updatelog.md` was asked for but never created (still absent at v1.2.39); `CHANGELOG.md` currently carries the
  history. Confirm with the user whether a second, differently-scoped file is actually wanted.

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
    limit; enemy-debuff timers need pfUI libdebuff/Cursive. The user runs the **`brues-code`**
    fork (active); `jrc13245` is archived. Aegis does not depend on it, but its
    `CountEnemiesMatching` is where the nameplate-GUID enemy count was read from.
  - **UnitXP_SP3** — `UnitXP("distanceBetween", a, b)` for a distance to any unit (SuperWoW's
    positions resolve for PLAYERS only), and `UnitXP("behind", a, b)`, which is the **only**
    source of facing on this client. Both are optional here in the sense that every caller
    must handle their absence, and required in the sense that the features degrade to nothing
    without them.
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
- **Do NOT use**: `#`, `%`, `string.match`/`gmatch`, retail widget APIs,
  `SecureActionButton`/protected functions, or anything introduced after client 1.12.
- **`C_*` namespaces — banned by default, ONE carve-out** (amended 2026-08-18). They come
  from **ClassicAPI**, a DLL that is *Recommended*, never *Required*, so the addon may
  never assume they exist. The only permitted use is **through
  `Aegis_SBR_Capabilities.lua`**, which owns every probe and wrapper:
  - Never call a `C_*` function directly from the core, a class module, or the UI. Add a
    wrapper to the capability file instead, so there is exactly one guarded call site per
    function and one place to fix when a DLL version changes a signature.
  - Gate on `self:Capability("<key>")`, not on `HasClassicAPI()` — an older DLL can be
    present and still lack one function.
  - **Every wrapper returns `nil` for "unknown"**, and callers must treat unknown as "not a
    reason to act differently", falling through to the existing 1.12 path. `nil` is never
    `0` and never `false`. This is the same stance `SpellCost` and `DotRemaining` already
    take for unreadable data.
  - The fallback path is the contract, not a courtesy: a player without ClassicAPI must get
    **exactly** today's behaviour. Any change that a non-ClassicAPI player would also feel
    is a normal rotation change and needs the Rule #1 gate on its own merits.
  - Note that wiring a capability into a rotation gate changes WHEN an ability fires — that
    is a rotation change under Rule #1 even though the plumbing itself is not.

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
4. **Version cut**: `1.1.0` and up is the current scheme (pre-rebrand used letter suffixes,
   e.g. `0.13.12b`; post-rebrand ran `0.14.0`–`0.16.2` before the `v1.1.0` release cut).
   Bump the version in ALL THREE canonical spots (`.toc`, the core `.lua` `ver = "..."`,
   **and the README H1** — `# Aegis: Single Button Rotation (vX.Y.Z)`) and prepend a
   `CHANGELOG.md` entry. Keep them in sync — grep to confirm no stale version strings
   remain. **Merging that bump to `main` publishes a GitHub release** (see Current State):
   the CHANGELOG entry becomes the release body, so it is public text, not a private note.
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

## Two rules that keep being relearned

- **A detection that cannot answer must never close a gate.** Range, movement, facing, weapon,
  caster and enemy count all have a third value for "cannot tell", and every caller treats it as
  permission. This is the rule this codebase has broken most often, and the symptom is always the
  same: an ability silently stops and nothing says why. `CheckInteractDistance` asked about the
  player, `IsSpellInRange` returning `-1`, and the Holy Shock range clause that cancelled its own
  health threshold are the same defect in three costumes.
- **A capability is established, not assumed.** Where a source may simply never answer on a given
  client — nameplate GUIDs, `UNIT_CASTEVENT` confirmations, debuff-name resolution — latch the
  first real answer (`stingSeen`, `debuffSeen`, `castEventSeen`, `enemyScanSeen`) and run a safe
  fallback until then. The warlock throttle is the cautionary tale: it was stamped **only** on a
  confirmation, and on the reporter's client that confirmation never came, so the protection did
  not exist at all. Design intent that quietly evaporates on someone else's setup is worse than no
  design, because it looks correct in the source.

## House style
- **Write short, neutral and factual.** Changelog entries, PR bodies, commit messages and code
  comments state what changed, why, and what it affects. No jokes, no irony, no dramatic framing,
  no rhetorical questions, no long prose where two sentences do. Keep measured numbers and
  technical detail; cut the framing around them. Prefer a short list or a table to paragraphs.
- **Never quote a play report verbatim.** Reports reach this project as relayed Discord
  messages, and none of it belongs in `CHANGELOG.md`, `README.md`, a code comment, or a PR
  body: the person was talking in a chat, not writing for publication. Paraphrase what the
  observation ESTABLISHED — "a step to reposition contains a fraction of a second of standing
  still, so checking 'moving right now' is not enough" — and drop the wording, the name and any
  characterisation of the remark. v1.2.5 shipped a tester's throwaway joke into the changelog
  under the heading of "the sharpest review this addon has had"; it read as unprofessional to
  anyone without the context and as mockery to anyone with it, and not one word of the substance
  was in the quote. Numbers, symptoms and measurements are the useful part and carry none of
  that risk. **Named credit is the exception, and only when the user asks for it** — the v1.2.0
  thanks to Holyhollie was requested and stays.
- Comments explain WHY, not what. Keep the flat-dark UI conventions and palette already in
  the code. Don't introduce new dependencies. Don't refactor unrelated code in a feature
  change. When you fix a class of bug, add a one-line note to this file so it isn't
  relearned.
- **README badge header is USER-OWNED — preserve it verbatim.** The top of `README.md`
  carries the version in the **H1** (`# Aegis: Single Button Rotation (vX.Y.Z)` — bump this
  with every version cut, per Workflow step 4) plus two shields.io badge rows the user
  curates by hand. **Row 1 changed in v1.2.3 — re-read it from the file before touching it,
  do not restore the older three-badge version:** it is now FOUR badges, Discord (blurple
  `5865F2`) · **RavenCraft** 1.18.1 (near-black `1e1e1e`) · **CapyCraft** 1.18.1 (**brown**
  `8B5A2B`) · Octo WoW 1.18.1 (**purple** `8A2BE2`) — note Capy was also renamed and Octo
  moved to last. Row 2 = SuperWoW / Nampower / UnitXP_SP3
  (**Required**, **red** `C41E3A`) then ClassicAPI / SCRM (**Recommended**, **orange**
  `ff8c00`), all `style=flat-square&labelColor=555`. Do NOT add classes/license badges back,
  and do not reorder or re-colour the rows without being asked. Keep the Requirements
  table's Required/Recommended split in step with row 2.
- **Lessons already learned (don't relearn):**
  - `verify.py`'s ordering audit only flags a local defined past the calling body's END —
    a function's own inner locals (incl. closure captures) are legal, don't "fix" them
    (fixed 0.14.0; three historical false positives were exactly this).
  - When scripting bulk renames, run mechanical sweeps BEFORE inserting text that
    intentionally mentions the old name (migration shims, "formerly X" notes, legacy-alias
    comments) — or the sweep eats your own insert.
  - `verify.py`'s forward-reference check used `\b<name>\s*\(`, and `\b` matches between a
    dot and a letter — so `string.sub(` read as a call to a local named `sub`. Fixed in
    v1.1.6 with a `(?<![.:\w])` lookbehind. If a local ever shares a name with a stdlib
    function and the audit complains, check this before "fixing" the Lua.
  - An on/off command argument must be parsed with `Aegis_SBR:ToggleArg` (core), NOT
    `(arg or "") == "on"` — that idiom sends every unrecognised argument, the empty one
    included, to `false`, so a bare command silently disables what it was meant to toggle
    (fixed v1.1.5 in three places). Test its result with `== nil`; `false` is a valid return.
  - `GetWeaponEnchantInfo` returns **six** values on 1.12, not seven — an assumed extra
    return shifted `hasOffHand` onto the off-hand *expiration*, so the off-hand reading was
    silently wrong. Latent from v0.15.0 until v1.1.8 because only the main hand had a
    caller. When a 1.12 API's return count is assumed rather than counted, check it against
    a live call before building on the later values.
  - `AttackTarget()` is a **TOGGLE** on 1.12 — it STOPS a swing already running, and there is
    no Lua `/startattack` equivalent (that arrived in 2.0). `EnsureAutoAttack`'s no-slot branch
    called it every press, so spamming the macro flipped auto-attack on and off; it now fires
    at most once per target (v1.2.2). The branch is only reached when **Attack** is on no
    action bar, which selects for SuperCleveRoidMacros users — SCRM drives the swing with
    `/startattack`, so its users never slot Attack. Tell them to slot it: that restores the
    guarded path, which reads state and restarts the swing whenever it actually drops.
  - `Pick` / `PickQueue` return true when a spell is **known and affordable**, NOT when the
    cast was accepted — so anything stamped or cleared on their return records the attempt,
    not the outcome. Out-of-range / line-of-sight / "must be in front of you" arrive as an
    error message and never reach the combat log. Use `NoteSpellCast` + `SpellRefusedSince`
    (core) to tell them apart, as the Hunter's throttle does since v1.2.5. `Later(fn)` is NOT
    a success guard — it only skips while `Aegis_SBR.deciding` (preview mode).
  - A second detection source (ClassicAPI) wired into a gate may only ever **suppress** a
    cast, never shorten a throttle or unblock one. Letting it shorten the sting retry while
    the OLD detection still decided whether to cast re-queued a ranged shot every 1.5s and
    starved Auto Shot — the Hunter looked like it had stopped attacking (2026-08-18).
    Suppression is safe however badly the two sources disagree: worst case is a missed cast,
    never a loop. Anything on the "adds casts" side needs a play-test on that class first.
  - **A guard that stands a press down is not free — it has to be measured against what the
    player does by hand.** The mage's channel guard discarded every press for the length of an
    Arcane Missiles channel, so the first cast could only come from a press AFTER the stop
    event: the event's lateness plus a press interval, every channel. Spamming the ability
    pays neither, which is exactly what was reported, four times. Three fixes tuned the window
    AFTER the stop event and none of them removed the discarded press. Where a queue exists,
    queue behind what is in flight (the warlock's v1.2.30 rule); stall only where there is
    nothing to hold the press. And when a change makes casts chain back-to-back, re-check
    every "time since the last one ended" window — the previous channel's end can now sit
    inside the post-channel window while a NEW channel is running (v1.2.31).
  - `IsSpellInRange` **throws** for a name it cannot resolve — it does not answer `-1`. Every
    call needs a `pcall`, because a throw does not just close the gate, it aborts the rest of
    the press. Fixed v1.2.17 after a shaman respec left `KnowsSpell` answering "yes" for a
    talent-granted spell the client had already unlearned. Same release: a talent swap now
    drops the spellbook index (`CHARACTER_POINTS_CHANGED` cleared only the derived caches and
    left `spellIndex` to `SPELLS_CHANGED`, which arrives later). Assume any 1.12 API that
    takes a spell NAME can throw when the name is not in the book.
