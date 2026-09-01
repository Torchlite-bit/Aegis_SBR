# Local development workflow (Mercaius' machine)

> Not part of the addon. Describes how the two folders and the branches relate,
> so the live game folder is never left behind or half-updated.

## The two folders

| Folder | Role |
|---|---|
| `SichOctoWoW\Aegis_SBR` | dev / git working copy — **edit here** |
| `OctoWoW\Interface\AddOns\Aegis_SBR` | live game folder — **copy target only, never edited by hand** |

Verified changes are copied dev → live without asking. The live folder is not a
git repo; it is a plain mirror.

## ⚠️ Status (checked 2026-09-01): this is NOT the workflow in use

`local/integration` **does not exist**. The dev folder sits on whichever feature branch is
current, and each release has gone `git stash` → `checkout main` → `pull` → `checkout -b` →
`stash pop`.

That has been safe so far only because **one feature has been in flight at a time**: with a
single branch, stash/pop carries the whole working copy across and nothing is silently reverted.
The failure this file describes needs two or more branches in flight, which has not happened yet.

It has still cost something adjacent. Twice the live folder ended up missing work that was
already merged (a friend's `CLAUDE.md` and `docs/architecture.md`), because the dev copy is the
only source live is fed from and a branch switch is exactly when that copy is momentarily not
"everything current".

**Decide before the next parallel feature**, and either adopt the rule below or replace it — a
rule nobody follows is worse than no rule, because it is read as a description of reality.

## The rule that makes this safe

**The dev folder stays on `local/integration` and never changes branch.**

That branch is local-only (never pushed) and holds `main` plus every feature
branch still in flight, merged in. So the dev working copy always contains
*everything current*, which is exactly what the live folder needs — a copy dev →
live is safe at any moment, no matter what state GitHub is in.

This exists because of a concrete failure mode: a git working copy only ever
holds ONE branch. Checking out a feature branch to commit it silently reverts
every file belonging to the other branches. Copy to live at that moment and the
game loses work that was already tested. `local/integration` removes the reason
to ever switch.

## Committing a feature without touching the dev folder

Work and commit on `local/integration` as usual. To turn a commit into a clean
PR branch off `main`, use a throwaway worktree instead of switching branch:

```bash
git worktree add ../_wt-feature -b feature/<name> main
git -C ../_wt-feature cherry-pick <sha>          # or several
git -C ../_wt-feature push -u origin feature/<name>
gh pr create --base main --head feature/<name> --title "..." --body "..."
git worktree remove ../_wt-feature
```

A worktree is a second checkout of the same repository in another directory. The
dev folder keeps `local/integration` the whole time, so live stays valid.

## A NEW file needs a client restart, not a reload

`/reload` re-runs the files the client already has open. It does not re-read the
`.toc`, so a file added since the client started - a new module, a new texture -
simply is not there. The addon then behaves as if the work was never done:
`Icons/Grip.tga` rendered as nothing, and `Aegis_SBR_Pet.lua` looked like a
toggle that did not work.

Editing an existing file is fine with `/reload`. Adding one is not. When a
change introduces a file, say so and restart the client before concluding
anything about whether it works.

## Never stack a PR on another PR's branch

Every branch is cut from `origin/main`, without exception. Setting a PR's base to
another open PR's branch looks tidy when two changes touch the same file, but it
has a failure mode that is silent and easy to miss.

It bit us once and cost a whole release. `#41` was based on `release/v1.1.7`
because both edited `CHANGELOG.md`, the `README` and the `.toc`. `#38` merged
`release/v1.1.7` into `main` **without deleting the branch**, so GitHub never
retargeted `#41` — GitHub only does that when the base branch is deleted on
merge. `#41` then merged into a branch that no longer flowed anywhere. Every PR
showed "merged", the work was reviewed and approved, and none of it reached
`main`. `main` sat on the previous version with a feature and a whole changelog
section missing, and nothing anywhere said so.

If two branches genuinely collide on `CHANGELOG.md` / `README.md` / the `.toc`,
resolve it by ORDER, not by stacking: leave the release files out of the feature
PR entirely and put version, changelog and README into one release PR cut from
`main` after the feature PRs have landed. A conflict you have to resolve once is
cheaper than a merge that silently does not happen.

## Delete the branch when the PR merges

Not housekeeping - it is what makes GitHub retarget anything still pointing at
that branch, and it is what keeps `git branch -r --merged origin/main` usable as
a check for what has actually landed.

## Verify the merge, do not trust the PR state

"Merged" means merged into the PR's **base**, which is not necessarily `main`.
After a batch lands, check the product rather than the pull request list:

```bash
git fetch origin
git log --oneline <previous-main>..origin/main    # are all the commits there?
git show origin/main:Aegis_SBR.toc | grep Version # did the version move?
```

## After a PR is merged

```bash
git fetch origin
git checkout local/integration        # should already be there
git merge origin/main                 # pick up the merged work
git branch -d feature/<name>          # local branch, once merged
```

Then copy dev → live as usual. `local/integration` gradually flattens back onto
`main` as PRs land, so it never drifts into a fork.

## Identity

`user.name` / `user.email` are set **repo-locally** to `Mercaius
<taxor@gmx.de>`, matching every existing commit. No global git config was
touched.
