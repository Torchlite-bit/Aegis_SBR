# Aegis_SBR — Roadmap

Phased plan. Do phases in order; each phase ends at a verifiable benchmark and a version
cut. Items marked FUTURE are deliberately deferred.

---

## Phase 0 — Rebrand AutoRota → Aegis_SBR

> **STATUS: DONE — shipped as v0.14.0** (pending in-game verification: profiles survive
> the `AutoRotaDB` → `AegisDB` migration, `/sbr` + legacy `/ar` both work, zero load
> errors). Notes on the implementation: the saved variables are **per-character**, so the
> toc line is `## SavedVariablesPerCharacter: AegisDB, AutoRotaDB` (not account-wide
> `## SavedVariables:` as sketched in step 5 — same idea, correct storage kind). The core
> global table is **`Aegis_SBR`** (user's pick). Step 6's logo STUB is wired (falls back
> to the sigil); the **logo TGA itself is still to come**, as is the deprecation tail:
> drop `AutoRotaDB` from the toc + clear it on PLAYER_LOGOUT ~2-3 versions from now, and
> later remove `SLASH_AEGIS_SBR3` (`/ar`) per the gradual-break plan below.

Goal: rename everything to the `Aegis_SBR` prefix, migrate the slash command and saved
variables without breaking existing user profiles, and add the logo. Low-risk but
touches many files — do it as its own verified batch and cut a version (`0.14.0`).

**Ordered steps:**

1. **Folder + .toc filename.** The addon folder is `Aegis_SBR/`; the toc MUST be
   `Aegis_SBR.toc` (filename must match the folder name or the client won't load it).
   Update `## Title:` to "Aegis: Single Button Rotation", refresh `## Notes:`,
   `## Author:`, `## Version:`. Keep `## Interface:` at the current value the toc uses
   (vanilla 1.12 = `11200`).

2. **Rename Lua files** to the `Aegis_SBR` prefix where the core file is named after the
   addon (e.g. `AutoRota.lua` → `Aegis_SBR.lua`). Class module filenames
   (`Class_Warrior.lua`, etc.) can keep their names — but update the `.toc` file list to
   match any renames, **preserving load order** (single-pass loader).

3. **Internal string/name replace, BY CATEGORY** (do not blind-replace — verify each):
   - Global frame names in `CreateFrame(..., "AutoRota...")` and any XML `name="AutoRota..."`
     → `Aegis...`. Dangling `getglobal("AutoRota...")` lookups fail silently.
   - The core global table (if it's `AutoRota`) → choose `Aegis` (or `AegisSBR`); update
     every reference. This is the biggest replace; do it carefully and re-run the verifier.
   - Event-handler references looked up by string (e.g. `frameName.."_OnEvent"`).
   - Any `bindings.xml` header names + `BINDING_NAME_*` globals.
   - User-facing strings / print prefixes ("AutoRota" → "Aegis").

4. **Slash command migration (`/ar` → `/sbr`, gradual).** Register one handler serving
   multiple command strings; the client iterates `SLASH_<KEY><n>` until nil:
   ```lua
   SLASH_AEGIS1 = "/sbr"    -- primary
   SLASH_AEGIS2 = "/aegis"  -- long form (optional)
   SLASH_AEGIS3 = "/ar"     -- legacy alias, keep during transition
   SlashCmdList["AEGIS"] = function(msg) Aegis_HandleSlash(msg) end
   ```
   Consolidate to ONE SlashCmdList key (`AEGIS`) — do not also keep an old `AUTOROTA`
   key, or a command gets double-processed. Gradual break: (A) both work silently;
   (B) `/ar` prints a one-time "'/ar' is now '/sbr'" notice gated by a `db` flag;
   (C) a later version removes `SLASH_AEGIS3`.

5. **SavedVariables migration (`AutoRotaDB` → `AegisDB`).** The DB is only readable after
   `ADDON_LOADED` fires for this addon. List BOTH names in the toc during transition so
   the old file loads from disk:
   ```
   ## SavedVariables: AegisDB, AutoRotaDB
   ```
   Migration shim (vanilla 1.12 event globals; `next` tests emptiness):
   ```lua
   local f = CreateFrame("Frame")
   f:RegisterEvent("ADDON_LOADED")
   f:SetScript("OnEvent", function()
       if event ~= "ADDON_LOADED" or arg1 ~= "Aegis_SBR" then return end
       if (not AegisDB or not next(AegisDB)) and AutoRotaDB then
           AegisDB = AutoRotaDB               -- profiles preserved
           AegisDB._migratedFrom = "AutoRotaDB"
       end
       AegisDB = AegisDB or {}
       -- merge in any new default keys without clobbering user values
   end)
   ```
   Keep `AutoRotaDB` in the toc for ~2-3 versions as a backup, then drop it and clear the
   global on `PLAYER_LOGOUT`. **Do NOT rename the DB and drop the old name in the same
   version** — that orphans profiles.

6. **Logo (files arrive LATER — do not block the rebrand on this).** The user will provide
   raw logo image files at a later time; they need converting to **TGA: power-of-two
   dimensions (e.g. 128×64, 256×128), 32-bit RGBA, exported via GIMP or 32-bit uncompressed**
   to avoid Photoshop TGA header quirks. Until the files exist:
   - Wire the config header to reference `Interface\\AddOns\\Aegis_SBR\\logo` (no `.tga`
     extension, double backslashes), BUT keep it graceful if the texture is missing — e.g.
     leave the existing AR sigil/wordmark in place as the fallback, or guard the
     `SetTexture` so an absent file doesn't leave a broken/green quad. Stub it; don't remove
     the current header art.
   - When the user supplies the images, convert to TGA per the spec above, drop into
     `Icons/` (or the addon root as referenced), and confirm — remember new/renamed textures
     need a **full relog** (not just `/reload`) to appear.
   - Document the final path + dimensions in `docs/architecture.md` when wired.

**Benchmark to advance:** addon loads with zero Lua errors under the new name; existing
profiles survive the migration (test in-game); `/sbr` and `/ar` both work; logo renders.
Then cut `0.14.0`.

---

## Phase 1 — Rotation correctness AUDIT-AND-REPORT  (highest gameplay value)

> **STATUS: report DELIVERED in v0.14.1** — `docs/audit-phase1-rotations.md` covers all 9
> classes (discrepancy tables + match notes + a cross-class sign-off summary). The Serpent
> Sting icon-fallback fix below shipped with it (the one pre-authorized code change; no
> priorities touched). **Open: the user's per-class decisions**, then approved changes land
> as gated, verified batches with dummy-test verification per the benchmark below.

> ⛔ **This phase does NOT change rotation code on its own initiative.** Per CLAUDE.md
> Critical Rule #1: the existing priority lists are hand-tuned. This phase VALIDATES them
> against `docs/rotations.md` and PRODUCES A DISCREPANCY REPORT for the user to act on.
> Code changes to rotations happen only AFTER the user approves them, per class.

**Deliverable of this phase = a written audit, not edits.** For each class/spec:
1. Read the module's actual priority list and gates.
2. Compare against `docs/rotations.md` (and `docs/turtle-mechanics.md`).
3. Produce a per-class discrepancy table:
   `ability/order | what the code does | what research says | source + confidence [T]/[V]/[?]
   | recommended action | RISK if changed`.
4. Flag which items are **Turtle-confirmed [T]** (strong case to change) vs **vanilla
   assumption [V]** vs **needs in-game verification [?]** (do NOT change on paper — dummy-test).
5. **Present the report and WAIT.** The user decides, per class, what to change. Only then,
   in a fresh batch, implement the approved changes (which, being rotation changes, are the
   one place we move carefully and re-verify).

Order the audit by highest divergence from vanilla first (most likely to contain real
discrepancies):
- **Paladin** — no offensive Holy Shock; Crusader Strike + Holy Strike share ONE 6s
  cooldown; Ret keeps a Seal up and ramps Zeal; Holy is a melee-capable healer using
  Crusader Strike to reset Holy Shock (Blessed Strikes).
- **Survival Hunter** — MELEE archetype on Turtle (Raptor/Mongoose + Lacerate priority,
  Carve AoE sharing Multi-Shot CD, Wing Clip filler). Marksmanship = Steady Shot weave.
- **Elemental Shaman** — Flame Shock + Molten Blast + Lightning Bolt core (Electrify
  builds passively), NOT vanilla LB-spam.
- **Mage** — Arcane (Surge > Rupture > Missiles); Fire (4s Ignite + Hot Streak Pyroblast);
  Frost (Icicles/Flash Freeze).
- **Feral Druid** — powershift Shred is dominant over bleeds.
- Then the remaining specs.

**Non-rotation exception:** the **Hunter Serpent Sting icon fallback** bug is a display fix,
not a priority change — it can be fixed in this phase without the sign-off gate (but still
verify + version-cut normally).

**Benchmark to advance:** a complete written discrepancy report exists for all 9 classes,
the user has signed off on which changes to make, and approved changes are implemented and
dummy-verified (cast log matches intended priority; no GCD clipping). Use the profiling tool
from the polish backlog if built.

---

## Phase 2 — Engine robustness & code health

- **Shaman totem destruction detection.**
  > **STATUS: DONE and verified in v1.1.9.** It took two goes, and neither used the
  > GUID-plus-combat-log watch planned here.
  >
  > **v1.1.7** made totem upkeep read the **player's own aura** where the totem grants one
  > (`Class_Shaman.lua`, `MaintainTotem`) — one check answering expiry, destruction, Totemic
  > Recall and walking out of range at once. A totem name was trusted only once its aura had
  > actually been *seen* after a cast, so a wrong entry in the name table degraded to the
  > timer instead of spamming the slot. The same release replaced the two blanket redrop
  > constants (55s water / 110s everything else) with **per-totem** intervals, because the
  > blanket number was sized for 120s totems and left short ones missing for most of their
  > cycle. **The gap:** totems that grant no aura at all — Searing, Magma, Fire Nova,
  > Grounding — had nothing to read and still ran on a clock, which is exactly the set the
  > clock serves worst.
  >
  > **v1.1.9** closed that gap with ClassicAPI: `GetTotemInfo` reads the element slot
  > directly (no aura, no name guessing, no clock) and `PLAYER_TOTEM_UPDATE` fires on a
  > totem **killed or recalled** rather than expired. Verified in play — Totemic Recall
  > emptied two slots in the same instant and both were re-dropped 0.11s and 0.34s later.
  > Two further fixes fell out of it: the per-totem intervals were still max-rank values
  > (rank 1 Searing lasts 30s, the table said 55), now read from the spell tooltip via
  > `Aegis_SBR:SpellDuration`; and a totem on cooldown was retried every 1.5s through its
  > dead window. Both of those help players **without** ClassicAPI, who still run the
  > v1.1.7 aura-and-clock path.
  >
  > Totem aura **names remain vanilla baselines** and want confirming on Turtle via
  > `/sbr debug` — they still matter on the no-ClassicAPI path. See
  > `docs/audit-phase1-rotations.md` item S9.
- **Heal-engine dedupe**: unify the four near-identical heal engines
  (Paladin/Priest/Druid/Shaman) into one shared module; class modules pass config in.
  **Still open** — untouched as of v1.1.9.
- **Weapon-enchant awareness / poison + imbue upkeep** (Rogue + Shaman; per-class UI toggle):
  detect and optionally maintain weapon imbues (Shaman) and poisons (Rogue). **Full feasibility
  study in `docs/research-weapon-enchant-upkeep.md` — read it first.**
  > **STATUS: first cut SHIPPED in v0.15.0**, substantially extended in v1.1.7/v1.1.8.
  > Shaman imbue upkeep now runs in **every spec** (Restoration and Elemental included, not
  > just Enhancement/Tank) as two independent, either-alone routes: automatic
  > (out-of-combat auto-apply, in-combat opt-in, default OFF) and a manual clickable rebuff
  > button ported from BuffUp's item-slot-watch mode to its spell-slot-watch mode (v1.1.7).
  > The two Rogue poison buttons gained a low-charge warning state (≤5 charges: yellow,
  > blinking, shows the count) so the prompt appears **before** the poison is gone, not only
  > after (v1.1.8) — still a pre-pull-style reminder, not mid-fight automation. Found and
  > fixed alongside it: `Aegis_SBR:WeaponEnchant`'s off-hand reading was landing on the
  > wrong field (`GetWeaponEnchantInfo` returns **six** values on 1.12, not seven — a stray
  > extra return shifted `hasOH` onto the off-hand expiration), latent until v1.1.8 because
  > only the main hand had ever been wired to a caller.
  > **Still open:** off-hand imbue is explicitly deferred, not attempted-and-blocked — the
  > in-code comment calls it "a fragile weapon-click flow"; Rogue poison auto-apply beyond
  > the click-driven Quick Bar/warning button (needs the replace-popup + in-combat-
  > application dummy tests, items 3 & 4 in the research doc); and topping up an
  > imbue that's present-but-low via overwrite (blocked on the popup test — currently
  > warn-only).

  Key findings:
  - **Primary API is `GetWeaponEnchantInfo()`** (returns `has*`, **`*Expiration` in ms**,
    charges, id) — better than the 2.1 `GetWeaponEnchantID` (wiki-confirmed 2026-07-17)
    because it gives *time remaining*. `GetWeaponEnchantID(unit)` is an optional identity
    source (which imbue is up). Refresh on `UNIT_INVENTORY_CHANGED`. Guard behind
    `if GetWeaponEnchantInfo then ...`.
  - **Detection + out-of-combat re-apply are feasible.** **In-combat re-apply is the blocker:**
    poisons generally can't be applied in combat at all (→ Rogue is realistically a *pre-pull
    reminder/warning*, not mid-fight upkeep); Shaman imbues can be recast in combat but cost a
    GCD and are awkward to auto-fire, so default to out-of-combat/lull only.
  - Build order: (A) shared detection helper = ungated plumbing; (B) the per-class toggle
    behavior = a ROTATION change → **audit-and-report sign-off first**; (C) per-class UI toggle
    + imbue dropdown + threshold slider. Handle the enchant-replace `StaticPopup` defensively
    (don't hard-code `StaticPopup1Button1`) or restrict auto-apply to the no-existing-enchant
    case and only warn on overwrite.
  - Verify on live client before building (see the research doc's dummy-test list):
    `GetWeaponEnchantInfo()` values, whether `GetWeaponEnchantID` exists, popup behavior, and
    that poisons can't be applied in combat on Turtle.

**Benchmark:** one shared heal engine passes all four healers' tests; a killed totem
triggers a re-drop within one frame; the weapon-enchant helper correctly reports imbue
presence on a test character (Shaman imbue on/off, Rogue poison on/off).

---

## Phase 3 — Sharing & QoL

- **Profile import/export**: serialize a profile to a shareable string (Lua-5.0-safe:
  build with `gsub`/`format`, no `string.match`; encode to survive the chat channel).
  Deserialize with a sandboxed `pcall`/parser.
- **Resto Druid + Resto Shaman in-game tuning passes** (healer priorities are the
  least-sourced part of the research — tune live).
- Flesh out `/docs` (this folder) as features land; keep `CHANGELOG.md` current.

---

## Phase 4 — PvP & auto-defensives  (FUTURE, per user request)

- Per-spec PvP priority lists.
- **Auto-defensive cooldown usage** (Ice Block, Divine Shield, Shield Wall, Aspect of the
  Turtle, Barkskin, etc.) triggered by health thresholds and incoming-cast detection via
  `UNIT_CASTEVENT`. Build the incoming-cast detection so it's reusable for interrupts too.

---

## Landed since this file was last touched (v1.2.2 → v1.2.7)

Recorded here because several were **not on any list** — they came out of play reports and one
comparison against another addon, and the roadmap silently drifting behind the code is how a
plan stops being read.

- **Error handling, at all** (v1.2.3). The addon had none. `UI_ERROR_MESSAGE` is now read for
  the client's own refusal strings, which is the only source for line of sight and the only one
  for out-of-range after `IsSpellInRange` answered "cannot judge".
- **Movement** (v1.2.5) — `Moving()` / `StillFor()`; channels and cast-time DoTs are no longer
  attempted while running, and Consecration waits out a dwell.
- **Debuff ownership** (v1.2.6) — the second warlock on a mob used to apply nothing at all.
- **Enemy counting** (v1.2.6) — from the nameplates the client draws. This closes the standing
  assumption in several comments that "1.12 cannot count nearby enemies": true of the vanilla
  API, false of the environment the addon actually runs in.
- **Weapon and facing requirements** (v1.2.7) — *Shield Slam* without a shield, *Backstab* from
  the front.
- **Per-press memoisation** (v1.2.7) — the paladin measured the group up to six times a press.

Two backlog items below are now **partly done** and should be read as such:

- *Rotation profiling / cast-log* — the press log (`/sbr log`), the trace, and the perf sampler
  cover most of it. What is missing is the "which condition passed" half, which the `STALL` and
  `exo=` / `near=` / `hold=` trace fields have started on ad hoc, one class at a time.
- *Self-test warning about missing dependencies* — `/sbr capi` and `/sbr gobbo` report their own
  capability, and the three-state detections make absence survivable rather than fatal. A single
  consolidated "what is missing and what you lose" command still does not exist.

## Polish backlog ("make it perfect" — pull into phases as it fits)
- Cooldown-ready indicators on the UI (glow/desaturate what the engine is waiting on).
- Rotation profiling / cast-log + APM display (records what was cast and WHICH condition
  passed — this is how you verify a dummy audit).
- Interrupt automation (UNIT_CASTEVENT → Kick/Pummel/Counterspell/Earth Shock/Wind Shear).
- Trinket/racial usage in burst windows, toggle-gated.
- `/sbr debug` verbose mode dumping evaluated conditions; a self-test that warns if
  SuperWoW / Nampower / SuperCleveRoidMacros are missing.
- In-game changelog display on first load after a version bump.
- "Next spell" ghost-icon prediction.
- Buff/debuff window HUD surfacing the timers the engine tracks.
- Buff-cap safety (Turtle 32-buff / 16-debuff caps) — skip low-value debuff applications
  near the cap.
