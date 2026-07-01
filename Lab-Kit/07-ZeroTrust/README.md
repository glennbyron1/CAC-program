# Lab-Kit / 07-ZeroTrust

**Phase 8 — Zero Trust Extension scripts.** Build on top of the baseline lab from folders `01-06`. Run in order within each sub-phase; sub-phases can be tackled in any order but `8.1` (tiered admin model) should come first because everything else references its groups.

---

## Sub-Phase Index

### 8.1 — Authorization & Least Privilege

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Set-TieredAdminModel.ps1` | ✅ Full | Lab-DC01 | Creates Tier 0/1/2 OUs + admin groups (Microsoft Securing Privileged Access model) |
| `Set-LeastPrivilegeGPO.ps1` | ✅ Full | Lab-DC01 | User Rights Assignment hardening per tier; `Deny logon` lockouts |
| `New-RBACModel.ps1` | ✅ Full | Lab-DC01 | AGDLP role→resource model (Helpdesk/FileServer/AppOwner/DBA/PKI). Edit the `$roleModel` table to add your roles |
| `Set-AuthenticationPolicySilo.ps1` | ✅ Full | Lab-DC01 | Kerberos Authentication Policy Silos that enforce tier isolation at the protocol level |
| `Deploy-ResourceGateway.ps1` | ✅ Full | Hyper-V host | IIS ARR reverse-proxy PEP: requires smart-card client cert, proxies to backend. Downloads ARR/URL-Rewrite if missing |

### 8.2 — Device Trust

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `New-DeviceCertTemplate.ps1` | ✅ Full | Lab-DC01 | Issues machine cert template from existing Issuing CA |
| `Enroll-DeviceCertificates.ps1` | ✅ Full | Lab-DC01 | Triggers autoenrollment for the new template across the fleet |
| `Set-DeviceComplianceCheck.ps1` | ✅ Full | Each endpoint | Posture gate (Defender signature age, patch level, BitLocker, firewall) → verdict to AD attribute + HKLM. Run as SYSTEM on a schedule |
| `Update-VPN-DeviceAuth.ps1` | ✅ Full | Client / NPS host | Updates the existing VPN profile to MachineCertificate+EAP (device + identity); adds the NPS policy. WatchGuard steps documented inline |

### 8.3 — Continuous & Conditional Access

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Set-KerberosTicketLifetime.ps1` | ✅ Full | Lab-DC01 | Shortens TGT (10h) and TGS (4h) lifetimes; renews continuous-evaluation posture |
| `Deploy-ConditionalAccess.ps1` | ✅ Full* | Azure / Entra | CA policies via Microsoft.Graph (device/MFA/legacy-auth/block-group), report-only by default. *Needs an Entra tenant |
| `New-RiskPolicy.ps1` | ✅ Full* | Lab-DC01 / Entra | Canonical risk→response policy file consumed by 8.6.3 + AD groups; optional Entra risk CA. *Entra parts need ID P2 |

### 8.4 — Workload / Non-Person Identity *(optional)*

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `New-WorkloadCertTemplate.ps1` | ✅ Full | Lab-DC01 | Short-lived (90-day) workload-identity cert template, Client+Server EKU for mTLS, enroll group |
| `Set-ServiceAccountHardening.ps1` | ✅ Full | Lab-DC01 | KDS root key + audit user-based SPN accounts + create gMSAs (30-day rotation). Cutover steps printed |
| `Enable-mTLS.ps1` | ✅ Full | Two lab services | IIS mutual-TLS demo (Server/Client modes) using the 8.4.1 workload certs, with no-cert negative control |

### 8.5 — Network Segmentation

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Set-Microsegmentation.ps1` | ✅ Full | Lab-DC01 | Windows Firewall GPO with default-deny east-west between lab VMs |
| `Convert-VPNToPerApp.ps1` | ✅ Full | Gateway host | Per-app IIS ARR PEP endpoints (one per app, mTLS + group), optionally flips the flat tunnel to split. Builds on 8.1.5 |

### 8.6 — Visibility → Decisioning

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Deploy-SIEM.ps1` | ✅ Full | Collector VM | Native Windows Event Collector (WEC) + WEF subscription for the ZT channel set; optional Sysmon. Sentinel/Elastic block documented |
| `New-DetectionRules.ps1` | ✅ Full | SIEM / WEC host | 7 detections (Sigma YAML, MITRE-mapped) + optional native event-triggered tasks on the WEC |
| `Connect-Analytics-To-Policy.ps1` | ✅ Full | WEC / Entra host | Loop closer: a fired detection contains the user (deny group + ticket revocation), optional Entra block |

### 8.7 — Validation & Evidence

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Invoke-ZeroTrustValidation.ps1` | ✅ Full | Lab-DC01 | Extends the 7-layer validator with ZT checks (tier model, AP silos, device certs, ticket lifetimes, segmentation) |
| `Demo-Walkthrough-ZT.md` | ✅ Doc | n/a | Demo script for the ZT-enabled lab — analogous to `Demo-Walkthrough.md` |

---

## Legend

- ✅ **Full** — Complete working PowerShell. Run with `-WhatIf` / `-DryRun` first to preview.
- ✅ **Full\*** — Complete, but the cloud-side actions need an external dependency (an Entra tenant; risk policies need Entra ID P2). The on-prem path runs as-is.
- ⚙ **Scaffold** — Skeleton with clearly-marked `# TODO` blocks where product-specific details go. Useful as a template; not turnkey. *(none remain — all sub-phases are now Full.)*
- ✅ **Doc** — Markdown reference, not executable.

All scripts are idempotent and support `-DryRun` (or `-WhatIf`). The few external-product paths (Sentinel/Elastic, WatchGuard Firebox, cloud ZTNA brokers) are kept as clearly-marked OPTIONAL blocks inside the otherwise-turnkey scripts, not as missing TODOs.

---

## Recommended Run Order (First-Time Build)

1. `Set-TieredAdminModel.ps1` — must come first; everything else references its groups
2. `Set-LeastPrivilegeGPO.ps1` — locks down rights along tier lines
3. `Set-AuthenticationPolicySilo.ps1` — enforces tier isolation at Kerberos layer
4. `New-DeviceCertTemplate.ps1` + `Enroll-DeviceCertificates.ps1` — device cert plumbing
5. `Set-KerberosTicketLifetime.ps1` — quick win, high audit value
6. `Set-Microsegmentation.ps1` — network default-deny
7. `Invoke-ZeroTrustValidation.ps1` — confirm everything took

Then iterate on scaffolds as your product choices firm up.

---

## NIST SP 800-53 Mapping

The full set covers (at minimum):
- **AC-2/3/5/6** — least privilege, separation of duties, role-based authorization (8.1)
- **IA-2(11), IA-3** — device authentication, multi-factor (8.2)
- **AC-12, IA-5(13)** — session management, dynamic credential binding (8.3)
- **SC-7, SC-7(5)** — boundary protection, default-deny (8.5)
- **AU-6, SI-4** — audit review, system monitoring (8.6)
- **CA-7** — continuous monitoring (8.7)

---

*Related: `../../Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md` for the design rationale.
`Demo-Walkthrough-ZT.md` for the demo script once everything is in place.*
