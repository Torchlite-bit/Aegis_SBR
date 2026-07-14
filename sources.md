# Aegis_SBR — Sources & Update Ritual

The canonical list of where Aegis's game/dependency knowledge comes from, WHICH sources
Claude Code can fetch itself vs. which the user must paste, and the two commands that keep
the docs current. **Claude Code has no background process — sources are only re-checked when
the user runs one of the commands below.** Keep the "last verified" dates updated when you
refresh.

---

## Source access reality (read before trying to fetch anything)

Not every link works for an automated fetch. Don't waste effort scraping a blocked/JS site,
and don't trust the wrong source.

| Source | Fetchable by Claude Code? | Use it for | Last verified |
|---|---|---|---|
| `docs/TALENTS_1_18_1.md` | ✅ It's a committed file | **Talent trees / spec talent data — THE talent source of truth** | (repo) |
| SuperWoW **Changelog** wiki — https://github.com/balakethelock/SuperWoW/wiki/Changelog | ✅ Fetches cleanly | Dependency updates (SuperWoW versions/API) | 2026-07-15 (through 2.0; 2.1 user-provided) |
| SuperWoW **Features** wiki — https://github.com/balakethelock/SuperWoW/wiki/Features | ✅ Fetches cleanly | Dependency API surface | 2026-07-15 |
| Nampower (avitasia fork) `SCRIPTS.md` / `EVENTS.md` — gitea.com/avitasia/nampower | ✅ Search/fetch works | Dependency updates (queue API, events) | 2026-07-15 |
| SuperCleveRoidMacros wiki — https://github.com/jrc13245/SuperCleveRoidMacros/wiki | ✅ Fetches cleanly | Dependency updates (conditionals, reqs) | 2026-07-15 (repo archived/stable) |
| Turtle WoW Wiki — https://turtle-wow.fandom.com | ✅ Fetches cleanly | Confirmed custom mechanics | 2026-07-15 |
| SuperWoW **release page** — /releases/tag/Release | ⚠️ Served STALE content | Do NOT rely on — use the Changelog wiki instead | — |
| `talents.turtlecraft.gg/<class>` | ❌ Blocks bots (robots-disallowed) | USER browses; paste specifics. (Use `docs/TALENTS_1_18_1.md` instead.) | — |
| Tortoise DB **viewer** — https://xian55.github.io/tortoise-db-viewer/ | ❌ JS app, fetch returns empty shell | USER browses for exact spell/item numbers; paste specifics | — |
| `Penqle/tortoise-wow` (server DB / MaNGOS core) | ⚠️ Technically, but DON'T | Poor fit: it's an emulator with untested classes, NOT live-Turtle authoritative | — |

**Rule:** for talents, read `docs/TALENTS_1_18_1.md` — never try to scrape the calculators. For
exact spell numbers the user must paste from the DB viewer (Claude Code can't read it). Only
the ✅ rows are safe to fetch during an update check.

---

## Command 1 — Dependency refresh (fast, run when a new mod version drops)

> "Check the fetchable DEPENDENCY sources in `docs/sources.md` (SuperWoW Changelog + Features,
> Nampower SCRIPTS/EVENTS, SuperCleveRoidMacros wiki) against their last-verified dates. For
> anything new, update `docs/dependencies.md` — note new/changed functions, events, or
> requirements, flag any with rotation relevance — and bump the last-verified date in this
> table. Report what changed; don't touch rotation code."

Use this when you hear SuperWoW/Nampower/SuperCleveRoid shipped an update (e.g. a SuperWoW
2.2). It's scoped to dependencies so it stays quick.

## Command 2 — Mechanics refresh (broader, run after a Turtle patch)

> "Re-check the Turtle WoW Wiki against `docs/turtle-mechanics.md` and `docs/rotations.md` for
> class/spell changes since the last-verified date. Report a discrepancy list (what the docs
> say vs. what the wiki now says, with confidence tags). Update `docs/turtle-mechanics.md`
> where the wiki confirms a change and bump the date. For anything that would change a
> rotation PRIORITY, follow the audit-and-report rule — report it and wait, do NOT edit
> rotation code."

Use this after a Turtle content patch. Slower and more judgment-heavy than Command 1, which
is why it's separate — and it still respects the no-rotation-change-without-approval gate.

---

## Notes
- **User-provided info** (e.g. the SuperWoW 2.1 notes, or numbers pasted from the DB viewer)
  is recorded in the docs and flagged as user-provided/unverified until it also appears in a
  fetchable source. Trust it, but mark it.
- When you update a doc from a source, **bump that source's "Last verified" date** in the
  table above so the next check knows the baseline.
- If a fetch that used to work starts returning stale/empty content (as the release page
  does), note it in the table and switch to the working alternative rather than trusting the
  bad result.
