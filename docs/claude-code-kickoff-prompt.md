# Claude Code — Kickoff Prompt

Paste the block below into a fresh Claude Code session opened in the `Aegis_SBR` repo.
(Keep this file in the repo so you can re-paste it any time you start a new session.)

---

You are resuming development of **Aegis: Single Button Rotation** (`Aegis_SBR`), a one-button
rotation-engine addon for **Turtle WoW 1.18.1** (custom Lua 5.0 / 1.12 client; required
client mods: SuperWoW + Nampower + SuperCleveRoidMacros). The Phase 0 rebrand from the old
"AutoRota" name shipped as **v0.14.0** (core global `Aegis_SBR`, saved variable `AegisDB`
with a migration shim, `/sbr` primary + legacy `/ar`).

**Read these before doing anything**, in order: `CLAUDE.md` (especially the CRITICAL
RULES), then `docs/dependencies.md`, `docs/roadmap.md`, `docs/rotations.md`,
`docs/turtle-mechanics.md`, `docs/architecture.md`, and `docs/sources.md`. Also skim the
`.toc` to learn the file load order. (For talents, the source of truth is the in-repo
`docs/TALENTS_1_18_1.md` — the online talent calculators block automated access, so don't try to
fetch them. `docs/sources.md` lists which links are fetchable vs. paste-only and holds the
two update commands for keeping the docs current.)

**Two rules that override everything else:**
1. **The Phase 0 rebrand is DONE (v0.14.0)** — do not reintroduce the old AutoRota names.
   Keep the `AutoRotaDB` toc backup + migration shim and the legacy `/ar` alias until their
   deprecation windows close (see the STATUS note on Phase 0 in `docs/roadmap.md`).
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
- Cut versions from 0.14.0 upward (e.g. 0.14.0 -> 0.14.1; the letter-suffix 0.13.xb line
  ended at the rebrand); bump the version in the `.toc`, the core `.lua` `ver`, and the
  README H1 together, and prepend a CHANGELOG entry.
- I test in-game and report back with screenshots.

**Logos:** I will provide raw logo image files LATER; they'll need converting to TGA
(power-of-two, 32-bit, GIMP/uncompressed). The header STUB is already wired (0.14.0): it
tries `Interface\\AddOns\\Aegis_SBR\\logo` and falls back to the sigil while the file is
absent. When I hand you the art, convert it, drop `logo.tga` in the addon root, and remind
me a full relog (not `/reload`) is needed to see it.

**Your next task is Phase 1: the rotation-correctness AUDIT-AND-REPORT** (see
`docs/roadmap.md` Phase 1 for the per-class order and the report format). That phase
produces a WRITTEN discrepancy report — it does not edit rotation code until I sign off,
per class.

Start by:
1. Reading the docs above (confirm you've read the CRITICAL RULES).
2. Summarizing where the roadmap stands (Phase 0 shipped in v0.14.0; anything still open
   from its STATUS note) and presenting your Phase 1 audit plan back to me — which class
   you'll audit first and the report format.
3. Waiting for my go-ahead before producing the audit (and NEVER editing rotation code
   without my per-class sign-off).

Do not begin the audit until I confirm the plan.
