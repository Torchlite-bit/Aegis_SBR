# Feasibility Research — Poison / Weapon-Imbue Upkeep (Rogue + Shaman)

**Status:** research only, no code written (per user + the rotation-change guardrail).
**Goal:** let the rotation keep a weapon imbue (Shaman) or poison (Rogue) applied, exposed as
a **per-class UI toggle**. This doc assesses whether it's feasible on Turtle 1.12 + SuperWoW,
what the constraints are, and how it should be built — for Claude Code to implement later,
through the audit-and-report gate.

---

## Verdict up front
**Feasible for DETECTION and RE-APPLY OUT OF COMBAT. Blocked FOR RE-APPLY IN COMBAT.** The
honest shape of the feature:
- ✅ **Detecting** whether an imbue/poison is present, and its **time remaining**, is well
  supported — better than expected (see `GetWeaponEnchantInfo` below).
- ✅ **Re-applying out of combat** (or during a pre-pull / downtime lull) works via the
  normal "use imbue/poison item or cast the imbue spell" flow.
- ⛔ **Re-applying DURING combat is the hard blocker.** Applying a weapon imbue/poison in
  vanilla is a ~cast/channel that (a) can't be done mid-swing without interrupting, (b) for
  poisons is an *item use with a cast time* that's generally **not usable in combat**, and
  (c) triggers a confirmation popup when replacing an existing enchant. A one-button engine
  cannot cleanly slot this into an active rotation the way it slots a Shock or Sinister
  Strike. So the realistic feature is **"top up between pulls / warn me," not "maintain
  seamlessly mid-fight."**

This is why the recommended design is a **toggle with a conservative, out-of-combat-first
behavior**, plus an optional in-combat *warning* — not an always-on auto-recast.

---

## What the API actually supports (this is the good news)

### `GetWeaponEnchantInfo()` — the key function, and it beats `GetWeaponEnchantID`
Standard vanilla API, and **SuperWoW enhances it**. Returns:
```
hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
hasOffHandEnchant,  offHandExpiration,  offHandCharges,  offHandEnchantID = GetWeaponEnchantInfo()
```
- `hasMainHandEnchant` → 1/nil: **is there any temporary enchant/poison on the main hand.**
- `mainHandExpiration` → **time remaining in MILLISECONDS** (this is what makes real upkeep
  possible — we can re-apply when it drops below a threshold, not just when it's already
  gone).
- `mainHandCharges` → charges left. **CONFIRMED on client (2026-07-19): reads `0` for a
  time-based enchant** (imbue/oil/stone), so it is NOT a reliable "present" signal — gate on
  `has*` + `*Expiration`. Charges are only meaningful for charge-based enchants.
- `mainHandEnchantID` → the enchant's spell ID (older clients returned this as 0; on 1.12 +
  SuperWoW confirm what it returns — but we mostly need `has*` + `*Expiration`).
- Per the SuperWoW **Features** wiki: `GetWeaponEnchantInfo()` was extended so it "now can
  accept a friendly player (ex: party1)… gives the name of the temporary enchant on that
  player's mainhand & offhand. **Old functionality is preserved for own player's enchant
  duration & stacks.**" → self-query for duration/stacks is explicitly supported.
- Fires **`UNIT_INVENTORY_CHANGED`** when temporary enchants change → the engine can refresh
  its cached state on that event instead of polling every frame.

### `GetWeaponEnchantID(unit)` — SuperWoW 2.1 (wiki-confirmed 2026-07-17; on-client CONFIRMED 2026-07-19)
Returns **two values, `mh, oh`** — the main/off-hand temporary enchant **IDs**. On-client
test (`GetWeaponEnchantID("player")`) returned **`MH=29 OH=nil`**: a small-integer ID for a
filled slot, `nil` for an empty one. Strictly less useful than `GetWeaponEnchantInfo` for
this feature (no duration), but handy if we need to know *which* imbue is up (e.g. "is it
Windfury vs Rockbiter") to decide whether to overwrite. It exists on Turtle's bundled build,
but still call it presence-gated (`if GetWeaponEnchantID then …`) so a client without it
degrades; prefer `GetWeaponEnchantInfo` as the primary source and treat `GetWeaponEnchantID`
as an optional enhancement for identity.

**Bottom line on detection:** we can reliably answer "is an imbue/poison present, how long
left, how many charges, and (probably) which one" — self-only, event-driven. Detection is
NOT the blocker.

---

## The real constraints (this is what shapes the feature)

### 1. In-combat application is the blocker
- **Shaman imbues** (Rockbiter/Windfury/Flametongue/Frostbrand Weapon) are **spells with a
  cast** that enchant the weapon. Casting one mid-rotation interrupts auto-attack timing and
  competes with the actual damage rotation. They CAN be cast in combat, but doing so is a
  real DPS cost and awkward to auto-fire.
- **Rogue poisons** are **item uses with a cast/application time** and are **generally not
  applicable in combat at all** in vanilla (you apply poisons before pulling; they last 30
  min / until charges deplete). So for Rogue, "maintain in combat" is essentially impossible
  by design — the feature is really "make sure poison is up before the fight."
- **Replace-confirmation popup:** applying an imbue/poison when one is already present raises
  a `StaticPopup` ("Replace existing enchant?"). The common macro workaround is
  `/click StaticPopup1Button1`. An engine that re-applies must handle/auto-confirm this, and
  auto-clicking popups is fragile (the popup index isn't guaranteed to be `StaticPopup1`).

### 2. Application is a click-flow, not a targeted cast
On 1.12 you don't target the weapon: using the imbue spell/poison item applies to main hand
first, then (if dual-wielding and used again) off hand. SuperCleveRoid/vanilla macros do:
```
/cast Windfury Weapon        (MH first)
# or for poisons:
/use 16   (main-hand slot)   then confirm popup
```
So the engine would emit a use/cast + a slot target + a popup-confirm — more involved than
`CastSpellByName`.

### 3. GCD / rotation cost
Every re-apply is a GCD (imbue) that isn't a damage ability. Auto-firing it mid-fight visibly
lowers DPS; that's why it must be **gated to out-of-combat / lull**, or downranked to the
lowest priority, or just a warning.

---

## Recommended design (for the roadmap / Claude Code)

A **per-class toggle** with conservative behavior, built in this order:

**A. Detection helper (shared, no gate — pure plumbing).**
`M:WeaponEnchant(slot)` → returns `has, msRemaining, charges` from `GetWeaponEnchantInfo()`,
cached and refreshed on `UNIT_INVENTORY_CHANGED`. Optionally map `GetWeaponEnchantID` →
imbue/poison name if the function verifies on-client. Guard everything behind
`if GetWeaponEnchantInfo then …` so non-SuperWoW clients degrade.

**B. Toggle + behavior (per class — this part is the ROTATION change → audit-and-report gate).**
- **Shaman ("Maintain imbue"):** if enabled AND the configured imbue is missing (or
  `msRemaining` under a threshold) AND the player is **out of combat** (or in a lull, user's
  choice), cast the configured Weapon imbue at lowest priority. Default OFF. Let the user pick
  which imbue per spec (Enhancement likely Windfury MH; optional Flametongue/Frostbrand OH).
  In-combat re-imbue optionally allowed but default OFF (with a clear "costs a GCD" note).
- **Rogue ("Poison reminder"):** because poisons can't be applied in combat, this is
  primarily a **pre-combat check + warning**: if enabled and MH/OH poison is missing when
  entering combat (or on target/pull), print a chat warning / flash a UI marker. Auto-apply
  only out of combat. Default OFF.
- **Popup handling:** if auto-applying, the engine must confirm the replace popup safely
  (find the visible `StaticPopup` whose `.which` is the enchant-replace dialog rather than
  hard-coding `StaticPopup1Button1`). This is the fragile part — build defensively or restrict
  auto-apply to the "no existing enchant" case (no popup) and only *warn* when an overwrite
  would be needed.

**C. UI (per-class panel).**
A "Maintain imbue" (Shaman) / "Poison reminder" (Rogue) toggle, plus a dropdown for which
imbue (Shaman) and a threshold slider (re-apply under X minutes / warn under X). Mirrors the
existing `Row` + `Dropdown` layout.

---

## Feasibility summary table

| Capability | Rogue (poisons) | Shaman (imbues) | Notes |
|---|---|---|---|
| Detect present / time-left | ✅ | ✅ | `GetWeaponEnchantInfo()` (ms remaining); `UNIT_INVENTORY_CHANGED` |
| Identify which enchant | ⚠️ | ⚠️ | `GetWeaponEnchantID` if verified on client; else infer |
| Re-apply OUT of combat | ✅ | ✅ | Normal use/cast flow; handle replace popup |
| Re-apply IN combat | ⛔ (poisons not usable in combat) | ⚠️ (possible but a DPS/GCD cost, awkward) | Core limitation |
| Seamless mid-fight upkeep | ❌ | ❌ | Not realistic for a one-button engine |
| Pre-pull "is it up?" warning | ✅ | ✅ | The most reliable, highest-value version |

---

## What to verify in-game before building (dummy tests)
1. ✅ **CONFIRMED on client (2026-07-19).** `GetWeaponEnchantInfo()` returns sane values on
   Turtle 1.12 + SuperWoW. With an enchant applied,
   `/run local h,e,c=GetWeaponEnchantInfo(); ...` returned **`has=1 ms=2112460 chg=0`** —
   `has` present, `ms` a live countdown (~35 min). **Caveat learned:** `charges` read **0**
   for this (time-based) enchant, so **gate presence/upkeep on `has*` + `*Expiration`, NOT on
   charges** — charges is only meaningful for charge-based enchants (some poisons). Still
   worth confirming `has=nil` once the enchant is removed.
2. ✅ **CONFIRMED on client (2026-07-19).** `GetWeaponEnchantID("player")` exists and returns
   **two values** (`mh, oh`): the test returned **`MH=29 OH=nil`** — a small-integer ID for
   the filled main-hand slot, `nil` for the empty off-hand. Usable as the optional identity
   source. (Which enchant ID 29 maps to depends on what was applied; build an
   ID→meaning table only for the imbues/poisons the feature actually offers.)
3. ⬜ **STILL TO VERIFY — Replace popup behavior:** apply an imbue over an existing one and see
   what `StaticPopup` appears (and its index) — decides how/whether to auto-confirm. **Until
   this is done, the build keeps auto-apply to the no-existing-enchant case and WARNS on
   overwrite (no auto-click).**
4. ⬜ **STILL TO VERIFY — Poison-in-combat:** confirm poisons truly can't be applied in combat
   on Turtle (expected), which locks Rogue into the "warn / pre-pull" model.

---

## Roadmap placement
Add under **Phase 2 (engine robustness)** as an extension of the existing
"Weapon-enchant awareness (`GetWeaponEnchantID`)" item — but note the *primary* API is
`GetWeaponEnchantInfo()` (duration), with `GetWeaponEnchantID` as optional identity. The
detection helper (A) is ungated plumbing; the toggle behavior (B) is a rotation change and
goes through **audit-and-report** sign-off. Frame the Rogue side honestly as a
**reminder/pre-pull** feature, not in-combat maintenance.
