# Lab-Kit Reference

## Lab Operations (live in this folder)

These were generated from real lab build experience and are kept here in the kit
because they describe *operating* the lab, not the architecture behind it. Both
are sanitized — real lab passwords appear as `<LAB-ADMIN-PASSWORD>` etc., see
`.scrub-patterns.example.json` at the repo root for the placeholder convention.

| Document | What it covers |
|---|---|
| [`ONBOARDING.md`](ONBOARDING.md) | New user / new machine quickstart - account table, domain join steps, complete smart card enrollment ceremony in 7 parts (VSC + physical card paths), checkpoint commands |
| [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Running FAQ of every real problem encountered - smart card lockout (two-mechanism root cause), GPO scope errors, SYSVOL recovery, DSRM limitations, WS01 rejoin, SCC paths, PowerShell gotchas, physical endpoint issues |

---

## Architecture Reference (canonical in `../../Architecture/`)

The reference documents live canonically in [`../../Architecture/`](../../Architecture/)
so there is a single source of truth (no duplicate copies to drift out of sync).
Read them there:

| Document | Link |
|---|---|
| PKI architecture blueprint | [`../../Architecture/Blueprint.md`](../../Architecture/Blueprint.md) |
| STIG hardening + ACAS runbook | [`../../Architecture/STIG-Hardening-Guide.md`](../../Architecture/STIG-Hardening-Guide.md) |
| Federal tools setup guide | [`../../Architecture/FedGov-Tools-Setup-Guide.md`](../../Architecture/FedGov-Tools-Setup-Guide.md) |
| WatchGuard IKEv2 VPN guide | [`../../Architecture/WatchGuard-IKEv2-VPN-Guide.md`](../../Architecture/WatchGuard-IKEv2-VPN-Guide.md) |
| Regulatory alignment (ZTMM, CSF, CPGs, SB 871) | [`../../Architecture/Regulatory-Alignment.md`](../../Architecture/Regulatory-Alignment.md) |
| Federal compliance upgrade path | [`../../Architecture/Federal-Compliance-Upgrade.md`](../../Architecture/Federal-Compliance-Upgrade.md) |
| RMF templates (SSP, POA&M, SAR, ATO, etc.) | [`../../Architecture/RMF-Templates/`](../../Architecture/RMF-Templates/) |

The lab-day checklist is kept in the kit itself: [`../LAB-DAY-CHECKLIST.md`](../LAB-DAY-CHECKLIST.md).

> Packaging note: `Package-LabKit.ps1` copies the current Architecture docs into
> a self-contained archive at package time, so a USB copy of the kit is complete
> even though the repo keeps the docs in one canonical place.
