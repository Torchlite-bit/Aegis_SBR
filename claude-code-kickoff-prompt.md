# Claude Code — Kickoff Prompt

Paste the block below into a fresh Claude Code session opened in the `Aegis_SBR` repo.
(Keep this file in the repo so you can re-paste it any time you start a new session.)

---

You are resuming development of **Aegis: Single Button Rotation** (`Aegis_SBR`), a one-button
rotation-engine addon for **Turtle WoW 1.18.1** (custom Lua 5.0 / 1.12 client; required
client mods: SuperWoW + Nampower + SuperCleveRoidMacros). The repo currently still uses the
old "AutoRota" name internally.

**Read these before doing anything**, in order: `CLAUDE.md` (especially the CRITICAL
RULES), then `docs/dependencies.md`, `docs/roadmap.md`, `docs/rotations.md`,
`docs/turtle-mechanics.md`, `docs/architecture.md`, and `docs/sources.md`. Also skim the
`.toc` to learn the file load order. (For talents, the source of truth is the in-repo
`docs/TALENTS_1_18_1.md` — the online talent calculators block automated access, so don't try to
fetch them. `docs/sources.md` lists which links are fetchable vs. paste-only and holds the
two update commands for keeping the docs current.)

**Two rules that override everything else:**
1. **The #1 priority is the rebrand to `Aegis_SBR` — commands and file names — and it is
   your FIRST task** (Phase 0 in `docs/roadmap.md`). Do it before anything else, as its own
   verified batch, and cut a version when done.
2. **NEVER change rotation or ability-priority logic without my explicit approval first.**
   The per-class priority lists are hand-tuned. When the research in `docs/rotations.md`
   disagrees with the code, you REPORT the discrepancy (a written diff: what the code does
   vs. what the research says, with source + confidence tag) and WAIT for my decision — you
   do not "fix" it, even if confident. This applies to anything that changes WHICH ability
   fires or in WHAT ORDER. Non-rotation work (rebrand, UI, tooling, non-priority bug fixes)
   does not need this gate.

Hard Lua constraints (from CLAUDE.md — breaking these causes silent load crashes):
`table.getn` not `#`; `math.mod` not `%`; NO `string.match`/`gmatch` (use `find`/`gsub`);
event handlers use the globals `event`, `arg1`, `arg2`... (not a `self, event` signature);
single-pass loader means every local must be DEFINED BEFORE USE within its file.

Dependency awareness (from `docs/dependencies.md` — target these correctly):
- SuperWoW: `CastSpellByName(name[, unit])` for off-target casting; `UNIT_CASTEVENT` +
  `SpellInfo(id)` for cast detection (already wired to modules' `OnCastEvent`); GUIDs;
  combat-log owner tags (basis for totem-death detection).
- Nampower: spell queueing -- **only ONE GCD spell queued at a time, one non-GCD spell per
  server tick**; don't expect two GCD/non-GCD abilities in one press to both land.
  Maintained fork moved to gitea.com/avitasia; confirm installed fork/version before using
  its expanded API.
- SuperCleveRoidMacros: **requires Nampower v3.0.0+ and UnitXP_SP3**; reactive abilities must
  be on action bars for detection; enemy-debuff timers need pfUI libdebuff/Cursive; 261-char
  macro limit. (Aegis casts in Lua directly, not via macro text -- but these are the same
  client constraints its detections face.)

Workflow (follow every time):
- After EVERY edit, run `python3 scripts/verify.py --all` (balance check + define-before-use
  ordering audit). Never hand me a file that fails it.
- Work in small, verified batches. Read the actual file before editing it.
- Cut versions with letter suffixes (e.g. 0.13.12b -> 0.14.0 for the rebrand); bump the
  version in the `.toc`, the core `.lua` `ver`, and the README H1 together, and prepend a
  CHANGELOG entry. (Ask me if you want to keep the b-suffix line instead of 0.14.0.)
- I test in-game and report back with screenshots.

**Logos:** I will provide raw logo image files LATER; they'll need converting to TGA
(power-of-two, 32-bit, GIMP/uncompressed). For now, wire the header to reference
`Interface\\AddOns\\Aegis_SBR\\logo` but keep it graceful if the texture is absent (leave the
existing sigil as fallback). Do NOT block the rebrand waiting on the logo.

**Your first task is Phase 0: the rebrand to `Aegis_SBR`** -- folder/.toc rename to the
`Aegis_SBR` prefix, `/sbr` primary slash command with `/ar` kept as a legacy alias, the
`AutoRotaDB` -> `AegisDB` SavedVariables migration shim (so my existing profiles survive), and
stubbing the logo header. Follow the exact ordered steps in `docs/roadmap.md` Phase 0.

Start by:
1. Reading the docs above (confirm you've read the CRITICAL RULES).
2. Summarizing the current module structure, then presenting the Phase 0 rebrand plan back
   to me -- the exact files you'll rename, the internal string categories you'll replace, how
   the `/sbr` + `/ar` registration will work, and how you'll verify my profiles survive the
   `AutoRotaDB` -> `AegisDB` migration.
3. Waiting for my go-ahead before writing any code.

Do not begin coding until I confirm the plan.
