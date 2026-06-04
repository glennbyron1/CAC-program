# Lab-Kit / 07-ZeroTrust

**Phase 8 — Zero Trust Extension scripts.** Build on top of the baseline lab from folders `01-06`. Run in order within each sub-phase; sub-phases can be tackled in any order but `8.1` (tiered admin model) should come first because everything else references its groups.

---

## Sub-Phase Index

### 8.1 — Authorization & Least Privilege

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Set-TieredAdminModel.ps1` | ✅ Full | Lab-DC01 | Creates Tier 0/1/2 OUs + admin groups (Microsoft Securing Privileged Access model) |
| `Set-LeastPrivilegeGPO.ps1` | ✅ Full | Lab-DC01 | User Rights Assignment hardening per tier; `Deny logon` lockouts |
| `New-RBACModel.ps1` | ⚙ Scaffold | Lab-DC01 | Role groups + role→resource mapping. Fill in your specific roles |
| `Set-AuthenticationPolicySilo.ps1` | ✅ Full | Lab-DC01 | Kerberos Authentication Policy Silos that enforce tier isolation at the protocol level |
| `Deploy-ResourceGateway.ps1` | ⚙ Scaffold | Hyper-V host | Reverse proxy as a working Policy Enforcement Point demo. Product-dependent (IIS ARR / nginx / Caddy) |

### 8.2 — Device Trust

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `New-DeviceCertTemplate.ps1` | ✅ Full | Lab-DC01 | Issues machine cert template from existing Issuing CA |
| `Enroll-DeviceCertificates.ps1` | ✅ Full | Lab-DC01 | Triggers autoenrollment for the new template across the fleet |
| `Set-DeviceComplianceCheck.ps1` | ⚙ Scaffold | Lab-DC01 | Posture gate (AV signature age, patch level, BitLocker, firewall). Product-dependent for the AV signal |
| `Update-VPN-DeviceAuth.ps1` | ⚙ Scaffold | Hyper-V host | Require user **and** machine cert on VPN. VPN-product-dependent |

### 8.3 — Continuous & Conditional Access

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Set-KerberosTicketLifetime.ps1` | ✅ Full | Lab-DC01 | Shortens TGT (10h) and TGS (4h) lifetimes; renews continuous-evaluation posture |
| `Deploy-ConditionalAccess.ps1` | ⚙ Scaffold | Azure / Entra | PIV federation + CA policies. Belongs partly to Phase 9 (Azure) |
| `New-RiskPolicy.ps1` | ⚙ Scaffold | Lab-DC01 / Entra | Step-up auth, deny on risk. Depends on which risk signals you've enabled |

### 8.4 — Workload / Non-Person Identity *(optional)*

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `New-WorkloadCertTemplate.ps1` | ⚙ Scaffold | Lab-DC01 | Short-lived service-identity cert template |
| `Set-ServiceAccountHardening.ps1` | ⚙ Scaffold | Lab-DC01 | Convert service accounts to gMSA; remove stored secrets |
| `Enable-mTLS.ps1` | ⚙ Scaffold | Two lab services | Mutual TLS demo between two app services |

### 8.5 — Network Segmentation

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Set-Microsegmentation.ps1` | ✅ Full | Lab-DC01 | Windows Firewall GPO with default-deny east-west between lab VMs |
| `Convert-VPNToPerApp.ps1` | ⚙ Scaffold | Hyper-V host | Per-resource VPN access (ZTNA-style). VPN-product-dependent |

### 8.6 — Visibility → Decisioning

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Deploy-SIEM.ps1` | ⚙ Scaffold | New SIEM VM | Forward WEF stream into Sentinel or Elastic. SIEM-choice-dependent |
| `New-DetectionRules.ps1` | ⚙ Scaffold | SIEM | Anomalous auth + lateral movement detections |
| `Connect-Analytics-To-Policy.ps1` | ⚙ Scaffold | Cross-system | Pipe risk signals into Conditional Access (closes the loop) |

### 8.7 — Validation & Evidence

| Script | Status | Run on | Purpose |
|---|---|---|---|
| `Invoke-ZeroTrustValidation.ps1` | ✅ Full | Lab-DC01 | Extends the 7-layer validator with ZT checks (tier model, AP silos, device certs, ticket lifetimes, segmentation) |
| `Demo-Walkthrough-ZT.md` | ✅ Doc | n/a | Demo script for the ZT-enabled lab — analogous to `Demo-Walkthrough.md` |

---

## Legend

- ✅ **Full** — Complete working PowerShell. Run with `-WhatIf` first to preview.
- ⚙ **Scaffold** — Skeleton with clearly-marked `# TODO` blocks where product-specific details go. Useful as a template; not turnkey.
- ✅ **Doc** — Markdown reference, not executable.

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
