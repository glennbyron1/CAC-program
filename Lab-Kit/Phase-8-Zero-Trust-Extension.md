# Phase 8 — Zero Trust Extension
### Extends the CAC/PIV lab from strong authentication to end-to-end Zero Trust

**Author:** Glenn Byron
**Status:** Design complete — scripts are the next build phase (pending Phase 4 lab execution)
**Run these scripts on:** Lab-DC01 and Lab-Workstation01

Scripts follow the existing Verb-Noun convention and the pattern of guided, idempotent, logged execution. Sub-phases map to gaps A–G from `Zero-Trust/CAC-Program-ZeroTrust-Gap-Analysis.md` and to NIST SP 800-53 control families, so new controls drop straight into the SSP.

---

## Sub-phase map

| Sub-phase | Gap closed | Controls |
|-----------|-----------|---------|
| 8.1 — Authorization & Least Privilege | A | AC-2, AC-3, AC-5, AC-6 |
| 8.2 — Device Trust | B | IA-3, CM-6, SC-7 |
| 8.3 — Continuous & Conditional Access | C, D | AC-12, IA-2, AU-6 |
| 8.4 — Workload / Non-Person Identity | E | IA-9, SC-8, SC-23 |
| 8.5 — Network Segmentation & Per-App Access | F | SC-7, AC-4 |
| 8.6 — Visibility, Analytics → Decisioning | G | AU-6, SI-4, IR-4 |
| 8.7 — Validation & Evidence | — | CA-2, CA-7 |

---

## 8.1 — Authorization & Least Privilege
*Closes Gap A · AC-2, AC-3, AC-5, AC-6*

Turns "valid cert → broad AD access" into "valid cert → only what this identity needs."

- `Set-TieredAdminModel.ps1` — implements AD admin tiering (Tier 0/1/2); creates OUs, groups, and deny-logon rules so Tier-0 creds can't be used on Tier-2 hosts
- `Set-LeastPrivilegeGPO.ps1` — hardens User Rights Assignment, strips broad local-admin, applies "Deny log on" rights by tier
- `New-RBACModel.ps1` — defines role groups, maps roles → resources, and delegates AD rights by role (RBAC, with notes for an ABAC follow-on)
- `Set-AuthenticationPolicySilo.ps1` — Kerberos Authentication Policy Silos to constrain where privileged credentials are valid
- `Deploy-ResourceGateway.ps1` — stands up a reverse proxy / app gateway in front of one sensitive resource as a working **Policy Enforcement Point** demo

## 8.2 — Device Trust
*Closes Gap B · IA-3, CM-6, SC-7*

Adds the device as a second verified party alongside the user.

- `New-DeviceCertTemplate.ps1` — machine-authentication cert template published from the Issuing CA
- `Enroll-DeviceCertificates.ps1` — autoenrollment of device certs to domain machines
- `Set-DeviceComplianceCheck.ps1` — pre-access posture gate (Defender/AV state, patch level, BitLocker on) with pass/fail logging
- `Update-VPN-DeviceAuth.ps1` — extends the existing IKEv2/EAP-TLS profile to require **both** user and machine certificates (known user *on* a known device)

## 8.3 — Continuous & Conditional Access
*Closes Gaps C & D · AC-12, IA-2, AU-6*

Moves from "verify once at logon" toward "always verify."

- `Set-KerberosTicketLifetime.ps1` — shortens TGT/TGS lifetimes via Authentication Policies to narrow the post-revocation window
- `Deploy-ConditionalAccess.ps1` — federates the PIV credential into an IdP (Entra ID / AD FS) and applies conditional-access rules combining identity + device + location
- `New-RiskPolicy.ps1` — defines step-up-auth and deny conditions; documents Continuous Access Evaluation where supported
- Output: `ConditionalAccess-Design.md` capturing the Policy Engine logic (NIST 800-207 PE/PA/PEP mapping)

## 8.4 — Workload / Non-Person Identity *(optional)*
*Closes Gap E · IA-9, SC-8, SC-23*

Extends identity from people to machines and services.

- `New-WorkloadCertTemplate.ps1` — short-lived service/machine identity cert template
- `Set-ServiceAccountHardening.ps1` — converts static service accounts to group Managed Service Accounts (gMSA); removes stored secrets
- `Enable-mTLS.ps1` — demonstrates mutual TLS between two lab services using workload certs

## 8.5 — Network Segmentation & Per-App Access
*Closes Gap F · SC-7, AC-4*

Removes the flat interior so a foothold doesn't become free movement.

- `Set-Microsegmentation.ps1` — host-firewall / VLAN policy enforcing default-deny east-west between lab VMs, allow-listing only required flows
- `Convert-VPNToPerApp.ps1` — restricts VPN access to specific resources rather than the full lab subnet (ZTNA-style demo)

## 8.6 — Visibility, Analytics → Decisioning
*Closes Gap G · AU-6, SI-4, IR-4*

Closes the loop: telemetry you already collect now influences access.

- `Deploy-SIEM.ps1` — forwards the existing WEF stream into a lab SIEM (Sentinel or Elastic)
- `New-DetectionRules.ps1` — detections for anomalous auth, lateral movement, and policy violations
- `Connect-Analytics-To-Policy.ps1` — feeds a risk signal back into the conditional-access policy from 8.3

## 8.7 — Validation & Evidence
*Matches your RMF / compliance pattern · CA-2, CA-7*

Keeps Phase 8 measurable in the same way Phases 1–7 are.

- `Invoke-ZeroTrustValidation.ps1` — extends the 7-layer validator with ZT checks: least-privilege enforced, device cert required, ticket lifetime capped, default-deny segmentation in place, conditional access active
- `Stage-Reports.ps1` (extend) — adds a **Before-ZT / After-ZT** delta alongside the existing Before/After-MFA folders
- Docs: update SSP control mapping with new control families; refresh POA&M; add `Demo-Walkthrough-ZT.md`

---

## Suggested execution order

8.1 → 8.2 → 8.3 are the core and deliver the most ZT value (authorization, device trust, continuous/conditional access). 8.5 pairs naturally with 8.1. 8.6 depends on 8.3 (something to feed). 8.4 is optional and only needed to claim the Applications & Workloads pillar. 8.7 runs last, like the current validation/staging step.

---

## What completing Phase 8 achieves

Today the lab is a reference implementation of **Identity-pillar authentication** (Advanced/Optimal). Completing Phase 8 makes it a demonstrable **end-to-end Zero Trust Architecture** across Identity (auth *and* authorization), Devices, Networks, Visibility & Analytics, Automation, and Governance — with the same RMF evidence trail built for everything else.

---

*Related: `Zero-Trust/CAC-Program-ZeroTrust-Gap-Analysis.md`, `Lab-Kit/START-HERE.md`, `Architecture/RMF-Templates/SSP-Template.md`*
