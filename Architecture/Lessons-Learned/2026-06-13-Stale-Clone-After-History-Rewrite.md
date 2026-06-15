# Lessons Learned: Stale Clone After History Rewrite

**Date:** 2026-06-13
**Author:** Glenn Byron
**Category:** DevSecOps / Git operations / Incident response
**Status:** Resolved safely — no compromised state pushed; remote remained clean throughout.

---

## Summary

As part of the project's DevSecOps validation, the repo's history-rewrite workflow was exercised end-to-end. Test content was intentionally committed to verify the scrubbing tooling, then purged from all git history with `git filter-repo` and the rewritten history was force-pushed to the remote. This worked correctly on the primary development machine.

A second development machine held an older clone from **before** the rewrite. When that machine connected to the remote, it saw two divergent histories ("43 ↑ 45 ↓" in the git client) and offered to merge them — which would have re-introduced the pre-rewrite commits and undone the scrub.

This document captures what happened, how it was caught, the forensic verification that followed, the defense-in-depth response, and the operational rule that prevents recurrence.

---

## The Problem

The git client on the secondary Windows machine attempted to merge and hit conflicts on four `Portfolio/*.docx` files. It also reported significant divergence:

> "Your branch and 'origin/main' have diverged, and have 43 and 45 different commits each."

The pull/merge dialog offered to reconcile by merging the two histories together.

**Why this is dangerous:** continuing the merge would have re-introduced the pre-rewrite commits (containing the test content the scrub was meant to remove) and tangled the clean linear history. The local copy and the remote copy now have **fundamentally different commit SHAs all the way back to the root**, because `git filter-repo` rebuilds the entire commit chain with new SHAs.

---

## Root Cause

`git filter-repo` doesn't edit history in place — it rebuilds the entire commit chain with new SHAs, then the force-push replaces what's on the remote. Any clone made **before** the rewrite has the old SHAs in its local `.git/objects/` store. Git has no way to tell those clones "this old history is invalid now" — it just sees that the remote and local histories disagree and tries to reconcile them by merging.

Force-push without a corresponding fleet-wide re-clone is a known operational hazard. Every clone of the repo that existed before the force-push is now stale. They look like normal repos until they try to sync.

---

## The Danger Vector

| Action | Effect |
|---|---|
| Pull from stale clone | Adds pre-rewrite commits back into local history. No remote effect yet. |
| Merge to reconcile divergence | Combines pre-rewrite + post-rewrite histories. Locally bad. No remote effect yet. |
| Push merge to remote | **Re-introduces pre-rewrite commits to the remote.** Scrub is undone. |

The push is the load-bearing step that turns local mess into public exposure. As long as the merge is aborted before any push happens, nothing is compromised on the remote.

---

## The Fix (steps taken)

1. **Aborted the merge in the git client.** This rolled back the in-progress merge without touching the remote. Pulse / Insights confirmed the repo was unchanged.
2. **Rescued gitignored local-only files** that a fresh clone would not restore:
   - `.scrub-patterns.local.json` (repo root) — local-only sensitive-pattern map
   - `security/scripts/Scan-LocalRepo.ps1` — local sensitive-pattern scanner
   - `security/scripts/SCAN-README.md` — its usage doc

   These three are intentionally gitignored so they never end up on the remote. They have to be carried by hand between clones.

3. **Discarded the stale clone:**
   - Removed the repo from the git client (this only stops the client tracking the local copy; the remote is untouched).
   - Deleted the old local repo folder entirely.

4. **Fresh clone** from the remote. This came down with the current (post-rewrite) history. No divergence, no merge prompt, no conflict.

5. **Restored the 3 gitignored files** into the fresh clone at their correct paths.

6. **Ran the local scanner** (`Scan-LocalRepo.ps1`) to verify the new clone is clean. All patterns reported `[CLEAN]`. Repo confirmed in working order.

---

## Forensic Verification (what actually happened on the remote)

Aborting the merge protected the **future**. But the question still mattered: **what about the past?** The repo had a public window prior to the rewrite. Did anyone clone the pre-rewrite history? The exercise was deliberately scoped to also test the verification methodology.

### Methodology

Three independent data sources were cross-referenced:

| Source | What it shows | Limit |
|---|---|---|
| Web archive search (e.g. Wayback Machine) | Whether any persistent public archive holds the pre-rewrite repo state | Only catches what crawlers visited; absence isn't proof of non-exposure |
| GitHub Events API (`/repos/{owner}/{repo}/events`) | Push / release / star / fork / delete events for the last ~90 days | Bounded window; ages out |
| Repository Traffic dashboard | Git clones + visitors for the last 14 days | Very short window; older data is not retained |

The Traffic dashboard alone covers only 14 days. For exposure windows longer than that, **the Events API and a web-archive check are required to triangulate**. Most engineers don't know this limit exists — Traffic looks definitive in the UI but is actually a sliding window.

### Reconstructed timeline

From the Events API:

| Date / UTC | Event |
|---|---|
| 2026-05-19 18:00 | `PublicEvent` — repo first made public |
| 2026-05-19 to 2026-06-03 | Active development pushes |
| 2026-06-04 10:46 | Last pre-rewrite push (old author identity) |
| 2026-06-04 10:54 | v1.0 release published |
| 2026-06-04 11:36 | First push under rewritten author identity — **force-push complete** |
| 2026-06-04 11:42 | `DeleteEvent` removes the pre-rewrite backup tag |
| 2026-06-08 | First external `WatchEvent` — non-developer human user stars the repo |
| 2026-06-12 to 06-13 | Further normal development pushes |

**Public window prior to rewrite: approximately 16 days and 17 hours.** This exceeds the 14-day Traffic dashboard limit, so the first ~12 days of clone activity in that window are not visible in standard GitHub Insights and had to be inferred from the events feed.

### Verification results

| Check | Result |
|---|---|
| Web-archive snapshots of repo URL | **None.** No persistent crawler-captured archive of the pre-rewrite state. |
| `git log` on rewritten history | All SHAs post-rewrite. Clean. |
| Local `Scan-LocalRepo.ps1` against working tree | All patterns `[CLEAN]`. |
| Traffic dashboard for visible window | ~50-80 git clones during the visible 4-day overlap with the public window. Most clones-per-view ratio consistent with bot / scanner activity (≈3.66 clones per view). |
| Forks of the repository | 0 |
| External human attention | At least one real (non-bot) human user starred the repo 4 days after the rewrite completed |

The "1 real human watcher" finding was the most informative piece. Their public starred-repo signature (orgs followed, topics tagged, accounts watched) matched the profile of a federal IT / DevSecOps professional — exactly the audience the portfolio is built for. They starred after the rewrite, so the state they saw was the clean one. But starring is an attention event, not a first-contact event — earlier clones during the pre-rewrite window can't be ruled out.

---

## Defense-in-depth response

Forensic verification could not definitively prove "no clone of the pre-rewrite state exists on any other machine." Web-archive search was negative, but it covers only what crawlers visited. The 16-day public window included ~12 days of unmeasurable clone activity.

Given that uncertainty, the responsible call was to **treat any credentials that were part of the test content as compromised and rotate them**, even though there was no evidence of malicious use. This is textbook defense in depth: the cost of rotation is small; the cost of relying on "probably no one cloned it" is unbounded.

The rotation was performed and the new credential was added to `.scrub-patterns.local.json` so subsequent pushes continue to be scrubbed at push time by `Scrub-Repo.ps1`.

---

## The Rule

**After a history rewrite + force-push, every other clone on every other machine is stale and must be deleted and re-cloned. Never pull or merge a stale clone.**

The technical reason is unrecoverable: every commit SHA from the rewrite forward is different on the remote. Git cannot reconcile that without merging the two histories together, which defeats the scrub.

The operational practice that follows:

1. **Maintain a list** of every machine and every clone of the repo that exists. This becomes the "fleet to re-clone" list before any history rewrite.
2. **Before force-push, freeze the fleet.** No one pulls or pushes until the re-clone is complete.
3. **Force-push.**
4. **Notify the fleet.** Each machine deletes its local clone and pulls fresh.
5. **Verify with `Scan-LocalRepo.ps1`** on each machine before normal work resumes.
6. **Run the verification triangle** (Events API + Traffic + web-archive) to bound the public exposure window. If real exposure occurred, treat affected credentials as compromised and rotate.

This sequence is documented as Step 8 in `REPO-CLEANUP.md`. This exercise is that rule showing up in real life — the secondary Windows machine had a clone that pre-dated the rewrite and was not freshened on the same cadence as the primary.

---

## Quick Checklist (for any future rewrite)

- [ ] Inventory every clone on every machine before force-push
- [ ] Pause all developer activity on the fleet
- [ ] Run `Scan-LocalRepo.ps1` and `Scrub-Repo.ps1 -WhatIf` on the primary clone — confirm clean
- [ ] Run `git filter-repo` with the scrub patterns
- [ ] `git push --force origin main` and `git push --force --tags origin`
- [ ] On every other machine: rescue gitignored local-only files, then delete the clone
- [ ] Re-clone fresh on every machine
- [ ] Restore gitignored files on each machine from local backup
- [ ] Run `Scan-LocalRepo.ps1` on each machine — confirm clean
- [ ] **Forensic verification**: Events API + Traffic + web-archive cross-reference
- [ ] **Defense-in-depth**: rotate any credentials that were in the scrubbed content, even if no exposure is proven

---

## What Worked / What I'd Do Differently

**What worked:**

- The `.gitignore` correctly excluded the local-only sensitive-pattern files. Without that, the test content would have re-appeared in the rewritten history.
- The local `Scan-LocalRepo.ps1` caught the post-clone state and confirmed clean. Tooling did its job.
- The git client surfaced the divergence rather than silently merging — UI safety net worked.
- The forensic methodology (Events API + Traffic + web-archive) produced a bounded answer to "was anything actually exposed?" in under 30 minutes.

**What I'd do differently:**

- **Maintain a clone-inventory list.** The secondary Windows clone was forgotten because it hadn't been used in weeks. Anything that touches the repo, even once, goes on a re-clone-after-rewrite list.
- **Back up gitignored local-only files immediately after first creating them**, not at fire-drill time. A 30-second `Copy-Item` to a private `Backup-LocalOnly/` folder eliminates the panic step.
- **Run the forensic triangle proactively, not reactively.** Routine portfolio repos benefit from a monthly Events-API + Traffic check just to know who's looking. The data is short-lived; capturing it in time matters.

---

## Side Observation (positive)

The forensic verification incidentally surfaced that **a real human user — not a bot — had discovered and starred the repo during the same week as the rewrite**. Their public profile signature (orgs followed, topics tagged, accounts watched) matched the audience this portfolio is intentionally built for. Building in the open is supposed to be findable; this confirmed the strategy is working.

The security side of that observation: external attention raises the stakes on every leak. The career side: external attention is the entire point. Both things are true at once. Building in public means accepting both.

---

## Frameworks Touched

- **NIST 800-53 SI-12** (Information handling and retention) — repo content lifecycle
- **NIST 800-53 CM-3** (Configuration change control) — controlled history modification
- **NIST 800-53 IR-4** (Incident handling) — the response loop documented above
- **NIST 800-53 AC-6** (Least privilege) — defense-in-depth credential rotation after potential exposure
- **CISA Zero Trust Maturity Model — Visibility & Analytics pillar** — local scanner + Insights + Events API + web-archive as layered verification telemetry

---

## Related

- `security/POLICY.md` — repository security policy
- `security/INCIDENT_RESPONSE.md` — incident response procedures
- `REPO-CLEANUP.md` — history rewrite procedure (this lessons-learned is exercise feedback)
- `security/scripts/SCAN-README.md` — local sensitive-pattern scanner usage

---

*This document captures a controlled DevSecOps exercise and the operational lessons that followed. It does not describe a real-world data exposure incident. Test content used in the exercise is not specified by design; the verification methodology and operational lessons are the publishable artifacts.*
