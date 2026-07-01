# 🧠 Lessons Learned — Index

This folder documents real bugs, dead ends, and design decisions encountered while building the CAC-program lab. Each entry links to its own file with full detail (root cause, fix, and what would be done differently).

---

## How to use this folder

Each lesson gets its own dated file: `YYYY-MM-DD-Short-Title.md`. Entries are ordered below by **severity / instructive value first**, not strict chronological order — the reader gets the most-impactful finding at the top.

Each entry answers the same four questions so they're skimmable:

- **Problem** — what broke or didn't work as expected.
- **Root Cause** — what was actually going on under the hood.
- **Fix** — what resolved it.
- **Takeaway** — what to do differently next time / what to watch for.

---

## Index

| # | Lesson | Date | Phase | Severity |
| :--- | :--- | :--- | :--- | :--- |
| 01 | [**Silent TPM VSC Fallback During PIV Enrollment**](2026-06-16-Silent-VSC-Fallback-Discovery.md) — Windows silently completed every "PIV enrollment" against a TPM-backed Virtual Smart Card while the operator believed the credential was on the physical YubiKey. Hardware-factor design silently demoted to a software-factor design with no visible signal. Detection methodology + four-point operator acceptance check published; maps to NIST IA-2(11), IA-5(11), CM-6, AU-6. **Original DevSecOps finding.** | 2026-06-16 | Phase 3 — Enrollment | 🔴 **High** |
| 02 | [**Stale Clone After History Rewrite**](2026-06-13-Stale-Clone-After-History-Rewrite.md) — Second dev machine held a pre-rewrite clone. When it connected to the remote after a `git filter-repo` history purge + force-push, it saw two divergent histories ("43 ↑ 45 ↓") and offered to merge them — which would have silently re-introduced the scrubbed commits. Documents the safe recovery path so the pre-rewrite state never touches the remote. | 2026-06-13 | DevSecOps / Git ops | 🟡 Medium |
| 03 | [**CAC Enrollment Session Log**](2026-06-16-CAC-Enrollment-Session.md) — Full session narrative of the day the PIV enrollment kit came together: scripts created (`New-LabUser.ps1`, `Deploy-ScriptsToDC.ps1`), problems hit, sequencing decisions. Session log format, not an incident write-up — kept as the "here's what a build day actually looks like" primary source. | 2026-06-16 | Phase 3 — Enrollment | 🟢 Info |

---

## Why this matters for reviewers

This folder is often the most revealing part of a portfolio project — it shows how problems were diagnosed and solved, not just that the end state worked. If you're reviewing this repo for hiring purposes, this is a good place to judge real troubleshooting depth versus copy-pasted commands.
