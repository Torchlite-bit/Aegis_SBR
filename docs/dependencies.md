# Aegis_SBR — Dependency Stack (SuperWoW, Nampower, SuperCleveRoidMacros)

Aegis_SBR is built on three client mods. This documents what each one actually provides —
APIs, events, behaviors, and gotchas — so rotation code targets them correctly instead of
assuming vanilla or retail behavior. **Verify against the versions actually installed on the
user's client**; all three projects have moved forks and changed APIs over time (notes
below). Last researched: 2026-07-17 (SuperWoW refreshed through 2.2).

---

## 1. SuperWoW  (balakethelock/SuperWoW)
A client DLL that extends the 1.12 Lua API with unit GUIDs, cast events, and spell
metadata. This is the backbone of Aegis's targeting and cast detection.

**What Aegis relies on:**
- **Unit GUIDs** — every unit has a stable GUID. Functions accept a GUID where a unitID is
  expected, enabling "soft" targeting (act on a unit without changing your target). GUIDs
  are also returned by many queries (e.g. `UnitExists("player")` returns `exists, guid`).
- **`CastSpellByName(name[, unit])`** — SuperWoW adds the optional second arg so you can
  cast at a specific unit/GUID without targeting it. Core to acting on off-target units.
- **`UNIT_CASTEVENT`** — fires on cast activity for any unit. Args (1.12 globals):
  `arg1` = caster GUID, `arg2` = target GUID, `arg3` = event type
  (`"START"` / `"CAST"` / `"CHANNEL"` / `"FAIL"`, plus **`"MAINHAND"` / `"OFFHAND"` for
  auto-attack swings** — Features wiki, verified 2026-07-17), `arg4` = spell ID,
  `arg5` = cast duration (ms). Aegis registers this and dispatches `"CAST"` events to the
  active module's `OnCastEvent(caster, target, spellName)` after resolving the ID → name
  via `SpellInfo`. (Used today for Shaman totem-drop tracking; the basis for future
  interrupt/defensive detection.) ⭐ **The swing events are rotation-relevant:** an exact
  event-driven swing timer could replace the combat-log text parsing behind seal twisting
  and on-next-swing windows (audit items P8 / W6) — verify they fire on Turtle's bundled
  build first; any adoption that changes ability timing goes through the audit gate.
- **`SpellInfo(spellID)`** → per the Features wiki returns **name, rank, texture file, and
  min/max range to the target** (verified 2026-07-17). Aegis currently uses only the name
  (ID → name for `UNIT_CASTEVENT` matching); the range returns are a future option for
  range gating without `CheckInteractDistance`.
- **Combat-log / owner tagging** — SuperWoW exposes the owner of pets/totems/guardians in
  combat-log context, which is what makes **totem destruction detection** feasible
  (roadmap Phase 2): tag a totem's GUID on cast, watch for its death with owner = player.
  A **`RAW_COMBATLOG`** event (raw versions of all combat-log events; Features wiki) exists
  as a lower-level hook if the parsed log proves lossy for that detection.

**Gotchas:**
- GUIDs are large numbers — be careful never to compare them as truncated Lua numbers where
  precision could be lost; treat them as opaque tokens. (Nampower returns GUIDs as hex
  strings for this exact reason — see below.)
- SuperWoW's presence is the gate for `UNIT_CASTEVENT` and `SpellInfo`; Aegis already guards
  registration with `if SpellInfo then ...` so a client without SuperWoW degrades instead of
  erroring. Keep that pattern.

**Version detection:** SuperWoW exposes globals **`SUPERWOW_VERSION`** and
**`SUPERWOW_STRING`** (added in 1.2). Gate any version-specific function (e.g. the 2.1
`GetWeaponEnchantID` below) behind a presence check on the FUNCTION itself
(`if GetWeaponEnchantID then ...`) rather than trusting a version string — Turtle bundles its
own SuperWoW build and the number may not track upstream exactly. Aegis targets Turtle
1.18.1's bundled SuperWoW; **confirm which functions actually exist on the live client before
relying on them.**

**Version history relevant to Aegis** (from the SuperWoW wiki Changelog, re-verified
**2026-07-17**; the wiki's newest entry is **2.2, 16/07/2026**):

*2.0 (10/07/2026) — confirmed from wiki Changelog:*
- `CastSpellByName(spell, "CLICK")` — second arg `"CLICK"` instantly casts a reticle/ground
  spell at the mouseover location, bypassing the targeting-circle step. (Useful later for
  ground-targeted totems/traps/AoE without a manual click — but a rotation change, so gated.)
- `TrackUnit` / `UntrackUnit` split (was one function); `UntrackUnit("all")` clears all unit
  tracking.
- `UnitNameplate("unit")` → returns the nameplate frame for a unit.
- `CanLootUnit("unit")` → whether a unit has loot.
- Player-state helpers: **`IsSwimming()`, `IsMounted()`, `IsIndoors()`, `GetSpeed()`**
  (`GetSpeed` returns run/swim speed in yards/sec; 7 yds = 100% move speed). Potentially handy
  for gating (e.g. don't try to melee while mounted/swimming) — non-rotation gates are fine to
  use; anything altering ability priority is gated.
- World/cursor position: `CursorPosition()`, `GetWorldLocMapPosition`, `GetMapPositionWorldLoc`,
  `GetMapBoundaries`. (Not combat-relevant for Aegis.)
- Nameplate/chat-bubble CVars (`NameplateRange`, `NameplateMotion` 0/1/2, `ChatBubbleRange`,
  `HealingText`, etc.) and `CREATE_CHATBUBBLE` event. (Not combat-relevant.)

*2.1 (15/07/2026) — wiki-CONFIRMED 2026-07-17 (matches the earlier user-provided notes;
still presence-gate every function on Turtle's bundled build before relying on it):*
- **`GetWeaponEnchantID(unit)` → mainhand, offhand temporary enchant IDs.** ⭐ **This is the
  rotation-relevant one.** It lets the engine detect whether a *temporary* weapon enchant is
  currently active — Windfury/Rockbiter/Flametongue/Frostbrand imbues (Shaman), sharpening/
  weightstones and mana/wizard oils, and poisons-as-enchant (Rogue). Candidate uses (all
  gated behind the rotation-audit sign-off): Enhancement Shaman imbue-uptime checks, Rogue
  poison-uptime awareness, Warrior/any-class stone/oil upkeep. See roadmap "Weapon-enchant
  awareness" item. Returns an ID (not a name) — Aegis would map known imbue/poison enchant IDs
  to meaning, or just test presence/change. **On-client CONFIRMED 2026-07-19:**
  `GetWeaponEnchantID("player")` exists and returns TWO values (`mh, oh`) — a small-integer
  ID for a filled slot, `nil` for an empty one (test: `MH=29 OH=nil`).
- **NOTE (feasibility research + Features wiki): the standard `GetWeaponEnchantInfo()` is
  usually the BETTER function for upkeep**, because it returns **time remaining (ms)** and
  charges, not just an ID — `hasMH, mhExpirationMs, mhCharges, mhEnchantID, hasOH, ohExpMs,
  ohCharges, ohEnchantID = GetWeaponEnchantInfo()` (the `*EnchantID` returns were 0 on older
  clients — confirm what Turtle's build returns; `has*` + `*Expiration` are what upkeep
  needs). **On-client CONFIRMED 2026-07-19:** returned `has=1 ms=2112460 chg=0` for an
  applied enchant — `has`/`ms` work, but **`charges` reads 0 for a time-based enchant**, so
  gate upkeep on `has*` + `*Expiration`, never on charges. SuperWoW extends it: accepts a friendly player unit (e.g. `"party1"`) for the
  enchant *NAME* on that player's main/offhand, with "old functionality preserved for own
  player's enchant duration & stacks" (Features wiki, verified 2026-07-17; extension version
  not stated — presence-gate it). Refresh cached state on `UNIT_INVENTORY_CHANGED`. Use
  `GetWeaponEnchantInfo` as the primary detection source and `GetWeaponEnchantID` as
  optional identity. Full study: `docs/research-weapon-enchant-upkeep.md`. **In-combat
  re-apply is a hard limitation** (poisons can't be applied in combat; imbues cost a GCD) —
  the feature is out-of-combat / pre-pull-reminder shaped, not seamless mid-fight upkeep.
- `GetSendMailItemLink()`, `GetInboxItemLink(itemIndex)` — mail item hyperlinks. (Not
  combat-relevant.)
- `GetQuestID(questIndex)`, `GetQuestLink(questID)` — questlog ID + hyperlink (fills client
  cache from server, fires `QUEST_LOG_UPDATE` on a cache miss). Tooltip `SetHyperlink` now
  supports quest links. (Not combat-relevant; **renamed in 2.2 — see below, use the 2.2
  names.**)
- NameplateMotion Smart Spread improvements.

*2.2 (16/07/2026) — confirmed from wiki Changelog:*
- NameplateMotion smart-spread improvements + a new compact spread mode. (Not
  combat-relevant.)
- **Quest functions refactored/renamed**: `GetQuestIDForLogIndex(questIndex)`,
  `GetQuestLinkForLogIndex(questIndex)`, `GetQuestLinkForID(questID)` replace 2.1's
  short-lived `GetQuestID`/`GetQuestLink`. If anything ever touches these, presence-gate
  and prefer the 2.2 names. (Not combat-relevant.)

- Feature reference: https://github.com/balakethelock/SuperWoW/wiki/Features ·
  Changelog: https://github.com/balakethelock/SuperWoW/wiki/Changelog

---

## 2. Nampower  (spell queueing / cast efficiency DLL)
Solves a core 1.12 design flaw: the client won't start a second spell until the server
acknowledges the previous one completed, which wastes time equal to your latency every cast.
Nampower stops the client from waiting, and adds spell queueing so a press during the tail
of the current cast fires the instant it's legal.

**Fork/version note (IMPORTANT):**
- The widely-used **pepopo978/nampower has CEASED development**; the maintained line moved to
  **gitea.com/avitasia/nampower**. Other active forks (Emyrk, Dusk-92, gralle mirrors) expose
  an **expanded Lua API documented in `SCRIPTS.md` and events in `EVENTS.md`** in-repo.
- **SuperCleveRoidMacros requires Nampower v3.0.0+** (see §3), so assume a modern Nampower is
  present, but **verify the exact fork/version** before relying on any specific function —
  the API surface differs between the classic pepo build and the newer avitasia/Emyrk line.

**Behaviors that affect rotation logic:**
- **Queueing window**: pressing a spell within the queue window before the current cast ends
  queues it to fire immediately on completion. **Only ONE GCD spell can be queued at a time**
  (a new GCD press REPLACES the queued one); up to **5 non-GCD spells** can queue.
- **Server-tick buffer**: there's a ~50 ms server tick; Nampower uses a small buffer
  (default ~55 ms) to avoid rejections. As of a 2025 update the tick is subtracted from the
  GCD timer, so for cast-time spells ≥ ~ the GCD no buffer is generally needed. Non-GCD
  spells may need `NP_NonGcdBufferTimeMs` spacing (only one non-GCD spell processes per
  server tick). **Implication for a one-button engine:** firing two non-GCD abilities in the
  same press/tick may drop one — space them across ticks/presses rather than stacking.
- **CVar toggles** exist to control queueing (`NP_QueueCastTimeSpells`,
  `NP_QueueInstantSpells`) — some rotations deliberately toggle these off around specific
  casts. Don't assume queueing is always on.

**Expanded Lua API (newer forks — confirm availability before use; from `SCRIPTS.md`):**
- Casting/queue: `QueueSpellByName`, `QueueScript`, `CastSpellByNameNoQueue`,
  `CastSpellNoQueue`.
- Cast info: `GetCastInfo`, `GetCurrentCastingInfo`.
- Cooldowns: `GetSpellIdCooldown`, `GetItemIdCooldown` (with item metadata),
  `GetTrinketCooldown`, `GetTrinkets`, `GetAmmo`.
- Auras: `GetPlayerAuraDuration`, `CancelPlayerAuraSlot`, `CancelPlayerAuraSpellId`,
  `IsAuraHidden`; `GetSpellDuration` (channel duration / first aura effect duration);
  `GetSpellRangeData(rangeIndex)` → minRange, maxRange, flags, name.
- Movement/state: `PlayerIsMoving`, `PlayerIsRooted`, `PlayerIsSwimming`.
- **GUIDs as hex strings**: newer Nampower returns object GUIDs as hex strings (e.g.
  `"0xF5300000000000A5"`) because 1.12 Lua can't hold full 64-bit ints — match/compare
  accordingly if mixing Nampower GUIDs with SuperWoW ones.
- **Custom events (`EVENTS.md`)**: `SPELL_CAST_EVENT` (fires when you start a cast, before
  it's sent to server), `SPELL_START_SELF/OTHER`, `SPELL_GO_SELF/OTHER`,
  `SPELL_DAMAGE_EVENT_SELF/OTHER`, buff/debuff events (`BUFF_ADDED_SELF`,
  `BUFF_REMOVED_SELF`, `BUFF_UPDATE_DURATION_SELF`), `AURA_CAST_ON_SELF/OTHER` (includes an
  aura-cap bitfield for the 32-buff/16-debuff slots — useful for the buff-cap-safety idea).

**Gotcha:** queueing can conflict with other addons that manage casting (QuickHeal/Healbot/
Quiver historically). Aegis IS a casting manager — if a specific interaction misbehaves,
suspect queue timing first.

---

## 3. SuperCleveRoidMacros  (jrc13245/SuperCleveRoidMacros)
Enhanced macro engine for 1.12.1 (Vanilla/Turtle): conditional execution, dynamic
tooltips/icons, extended `/cast` syntax, count-based AoE conditionals, soft-target scanning.
Based on CleverMacro + Roid-Macros. **NOTE: the repo is now a public archive** (development
ceased) — behavior is stable but won't get new features; verify installed behavior.

**Hard requirements (from the wiki):**
- **Nampower v3.0.0+** — required (spell queueing, DBC data, auto-attack events).
- **UnitXP_SP3** — required for distance checks and `[multiscan]` enemy scanning / count-mode
  conditionals.
- **Reactive abilities MUST be on the action bars** for `[reactive]`-style detection to work
  (Revenge, Overpower, Riposte, etc.). *(A future Nampower-based update was planned to lift
  this, but treat the on-bar requirement as current.)* This mirrors Aegis's own
  `EnsureAutoAttack` lesson — some detections depend on the ability being slotted.
- **Unique macro names** required (no blanks/duplicates/spell-name collisions).
- **Macro line length: 261 characters max** (longer can crash without MacroLengthWarn).

**Conditional/behavior facts relevant to the engine:**
- A macro must start with `#showtooltip` (or `#showtooltip spell/item/id`) for dynamic
  icon/tooltip; the icon updates to the **first true condition's action, evaluated left→
  right, top→bottom** — the same "first passing branch wins" model Aegis uses internally.
- Rich conditionals: `[mod:...]`, `[stance:#]` (Shadowform/Stealth = stance 1), `[stealth]`,
  `[combat]`, `[channeling]`, `[combo:#]`, `[cooldown/nocooldown]` (GCD NOT ignored),
  `[cdgcd:...]` (CD incl. GCD), `[hp:...]`, `[stat:...]` (str/agi/ap/rap/healing/spell-power/
  resistances/etc.), `[equipped:...]`, `[known:...]` (spell/talent, optional rank),
  `[reactive]`, `[buff:/nobuff:]`, `[debuff:/nodebuff:]` (own debuffs only unless pfUI
  libdebuff or Cursive provides data), `[casting:...]` on `@unit`.
- **Count-mode / AoE conditionals** (need UnitXP_SP3): `meleerange:>N`, `behind:>=N`,
  `facing:>N`, `inrange:Spell>N`, `insight:>0`, `distance:30>N` — count enemies for
  "AoE-if-N-targets" decisions. Filter qualifiers avoid false positives when combining checks.
- **`[multiscan:...]`** soft-casts at scanned enemies without changing target (needs
  UnitXP_SP3; scanned targets must be in combat with the player). Modifiers like `[mouseuse]`
  auto-place ground-target circles.
- Extra slash verbs with conditionals: `/use`, `/equip`, `/target` (3D scan), `/castsequence`
  (`reset=` options), `/castpet`, `/startattack`, `/stopattack`, `/stopcasting`, `/stopmacro`.
- Flags: `!Spell` (spammable), `~Spell` (toggle buff/aura on/off), `?` (hide icon/tooltip),
  `#` (hide) — prefix semantics matter if Aegis ever emits macro text.

**Debuff-timer caveat:** debuff time-left conditionals only read YOUR OWN debuffs unless
pfUI libdebuff or Cursive is present with data — don't assume enemy-debuff timers are
available for gating without one of those.

**Docs:** https://github.com/jrc13245/SuperCleveRoidMacros/wiki (Conditionals, Slash-
Commands, Reference-Tables pages).

---

## How this maps to Aegis
- Aegis executes rotations **in Lua directly** (priority lists calling `CastSpellByName` /
  Nampower queue functions), rather than emitting SuperCleveRoid macro text. The
  SuperCleveRoid detail matters because (a) the user runs it alongside Aegis, (b) its
  conditional model and its "reactive abilities must be on bars" / debuff-timer-source rules
  describe the same client constraints Aegis's own detections face, and (c) future features
  (interrupts, AoE-target-count decisions) will want the same UnitXP_SP3 count-mode data.
- **Practical rules for rotation code:**
  1. Cast off-target via `CastSpellByName(name, guidOrUnit)` (SuperWoW) rather than
     retargeting.
  2. Detect casts via `UNIT_CASTEVENT` + `SpellInfo` (SuperWoW) — already wired; prefer this
     over blind timers.
  3. Respect Nampower's **one-GCD-queued-at-a-time** and **one-non-GCD-per-tick** limits —
     don't try to fire two GCD/non-GCD abilities in a single press expecting both to land.
  4. Any detection that needs an ability "known & ready" may depend on it being **on a bar**
     (reactive abilities) — mirror the `EnsureAutoAttack` fallback approach where relevant.
  5. Enemy-debuff-timer gating needs a data source (pfUI libdebuff/Cursive) — don't assume it.
  6. Watch the **32-buff / 16-debuff caps**; Nampower's `AURA_CAST_ON_*` cap bitfield can
     drive buff-cap-safety logic later.
