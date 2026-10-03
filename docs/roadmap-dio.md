# Dio's roadmap — parked ideas

> Ideas held open pending a design decision, kept with the research already done so it is
> not re-derived. Nothing here is a commitment, and nothing here is a rotation change: each
> entry still goes through the Rule #1 gate when it is picked up.
>
> Entries are dated and state what is still unanswered. If a parked idea turns out to matter
> on its own — a live bug, a broken gate — it is not parked, it is a defect.

## Open

### Disarm gating: which enemies actually carry a weapon

**Parked 2026-09-28.** Wanted on any spec for damage reduction, but not as a rotation yet.
Research done; implementation not.

**Nothing can introspect a mob's gear on 1.12.** No `UnitWeaponInfo`, no tooltip equipment.
`UnitCreatureType` is a weak correlation, and `GetWeaponEnchantInfo(unit)` is a near-useless
positive — a mob with a temporary weapon enchant certainly has a weapon, but almost no mob is
enchanted. Both rejected.

**Three detection signals, in descending order of trust:**

1. `CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS` / `..._MISSES` — 1.12 channels that are
   *specifically* creature **melee** attacks on the player, so a caster-only mob produces
   neither. **Already registered** (`Class_Warrior.lua:2164-2165`, Revenge window) and proven
   in production, so this needs no new dependency.
2. `UNIT_CASTEVENT` with `arg3 == "MAINHAND"` / `"OFFHAND"`, `arg1` = mob GUID, `arg2` = player
   GUID — GUID-exact, but the swing types are wiki-verified and **not confirmed on Turtle's
   bundled SuperWoW** (`dependencies.md:30`), and the core discards them today via
   `arg1 == myGuid` (`Aegis_SBR.lua:3619-3627`).
3. `SPELLCAST_FAILED` after a Disarm send, via `NoteSpellCast` + `SpellRefusedSince` — the
   negative signal, same per-target backoff shape as Intercept (`Class_Warrior.lua:1638`).
   Likely the *faster* one: a caster mob casts within seconds and may never swing, so signal 2
   is absent for exactly the mobs most likely to be undisarmable.

**The constraint that decides the design: the signal is retrospective.** A mob reads as armed
only *after* it has swung, and as undisarmable only *after* a Disarm has been spent. At pull
time every mob is unknown, and unknown must never close a gate (standing rule 1), so unknown
has to mean ALLOW — or Disarm never fires. The feature is therefore structurally "try once,
then remember", not "know and decide".

**Unanswered, and blocking:**

- Turtle's real Disarm rage cost. `SpellCost` (`Aegis_SBR.lua:137`) reads it live — do not
  assume vanilla; Sunder already costs 10 rage here.
- Whether a non-Protection warrior has Disarm at all. `Improved Disarm` is Protection-only
  per `TALENTS_1_18_1.md:70`; base Disarm unconfirmed.
- Which Turtle mobs are disarmable at all.
- Whether a failed Disarm raises `SPELLCAST_FAILED` or fails silently.

Also note Disarm costs a GCD and deals no damage, so on a Fury DPS in raid every press is a
lost GCD. The answer to "which mobs did you actually want disarmed, and why" decides whether
the priority is worth having at all.

**If picked up: instrument before building.** Add `arg2` to the existing `UNIT_CASTEVENT` log
line (`Aegis_SBR.lua:3595` logs the caster GUID but not the target), trace the two
creature-melee channels, dump `KnowsSpell` / `SpellCost` for Disarm, then `/sbr log clear` and
test on a pack holding a swinger, a caster-only mob and a no-weapon beast. Choose the priority
from the log under the Rule #1 gate.

**No Disarm exists in the rotation today** — no `useDisarm` toggle, no `Pick("Disarm")`, no
`RAGE["Disarm"]`. `DisarmActive()` (`Aegis_SBR.lua:2302`) only *reads* the debuff to keep
auto-attack alive. This is a new opt-in ability, not a gate on an existing one.

## Answered

_None yet._
