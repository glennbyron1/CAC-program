# Phase 8 (Zero Trust) — Scaffold Completion Changelog

**Date:** 2026-06-29
**Author:** Glenn Byron
**Scope:** Completed all 13 ⚙ Scaffold scripts in `Lab-Kit/07-ZeroTrust/` into full,
idempotent implementations. No previously-Full scripts were modified.

All new code follows the existing house style: `#Requires` headers, comment-based
help, `[CmdletBinding(SupportsShouldProcess)]`, `Set-StrictMode`, the
`Write-Step/OK/Warn/Skip/Fatal` helpers, banner + summary blocks, idempotent
re-runs, and a `-DryRun` (or `-WhatIf`) preview path. All 13 files parse clean
(`[System.Management.Automation.Language.Parser]`).

---

## What changed (⚙ Scaffold → ✅ Full)

### 8.1 — Authorization & Least Privilege
- **New-RBACModel.ps1** — AGDLP model. Data-driven `$roleModel` table maps Global
  role groups (Helpdesk-L1, FileServer-Admins, AppOwner-CRM, DBA, PKI-Operators)
  into Domain Local resource groups under `OU=ResourceAccess`. Idempotent group
  creation + nesting; optional `-ExportCsv` access-control matrix.
- **Deploy-ResourceGateway.ps1** — IIS + ARR + URL Rewrite reverse-proxy Policy
  Enforcement Point. Auto-downloads ARR/Rewrite MSIs if absent, binds the gateway
  TLS cert, requires a client certificate (`SslRequireCert`), and rewrites to a
  `-BackendUrl`, forwarding the verified cert subject as `X-Client-Cert-Subject`.

### 8.2 — Device Trust
- **Set-DeviceComplianceCheck.ps1** — Posture gate using in-box signals: Defender
  signature age + real-time protection, patch recency, BitLocker on the OS volume,
  all firewall profiles. Writes a COMPLIANT/NONCOMPLIANT verdict + JSON detail to
  an AD computer attribute (default `extensionAttribute10`) and an HKLM cache;
  exit code reflects posture for schedulers.
- **Update-VPN-DeviceAuth.ps1** — `-Mode Client` updates the EXISTING VPN profile
  in place to `AuthenticationMethod = MachineCertificate, Eap` (device + identity)
  and re-applies the EAP-TLS smart-card profile; `-Mode NPSServer` adds an NPS
  network policy requiring the machine cert. WatchGuard Firebox steps documented
  inline.

### 8.3 — Continuous & Conditional Access
- **Deploy-ConditionalAccess.ps1** — Microsoft.Graph CA policies (require
  compliant/hybrid device, require MFA, block legacy auth, block the
  ZT-Blocked-Users response group). Report-only by default (`-Enable` to enforce),
  with a break-glass group always excluded. *Requires an Entra tenant.*
- **New-RiskPolicy.ps1** — Decision layer. Writes the canonical
  `risk-policy.json` (Low→StepUp, Medium→Contain, High→Block + rule→risk map)
  consumed by 8.6.3, ensures the referenced AD groups, and optionally deploys
  Entra risk-based CA policies. *Entra parts require Entra ID P2.*

### 8.4 — Workload / Non-Person Identity
- **New-WorkloadCertTemplate.ps1** — Clones a short-lived (90-day) workload cert
  template with Client+Server EKU (mTLS-ready), enrollee-supplied subject, granted
  to a `Workload-Identities` group.
- **Set-ServiceAccountHardening.ps1** — Ensures the KDS root key, audits enabled
  user accounts carrying SPNs, and creates gMSAs (30-day rotation) for the named
  services. Prints the per-service cutover commands; does not auto-retire accounts.
- **Enable-mTLS.ps1** — IIS mutual-TLS demo. `-Mode Server` stands up a
  client-cert-required HTTPS site bound to a workload cert; `-Mode Client` calls it
  with the client cert and runs a no-cert negative control to prove enforcement.

### 8.5 — Network Segmentation
- **Convert-VPNToPerApp.ps1** — ZTNA-style per-app publishing on the ARR gateway:
  one client-cert-required PEP site per app (name/backend/port/group), optionally
  flips the flat tunnel to split-tunnel (drops the default route). Cloud-broker
  (Entra Private Access / Cloudflare / Zscaler) mapping documented.

### 8.6 — Visibility → Decisioning
- **Deploy-SIEM.ps1** — Native Windows Event Collector: `wecutil qc`, resizes
  ForwardedEvents, creates a source-initiated WEF subscription for the ZT channel
  set (logon/Kerberos/group-change/service/task/AD CS/PowerShell), optional Sysmon.
  Sentinel/Elastic alternative documented as an OPTIONAL block.
- **New-DetectionRules.ps1** — 7 MITRE ATT&CK-mapped detections emitted as portable
  Sigma YAML (ZT-001…ZT-007), plus optional native event-triggered scheduled tasks
  on the WEC that invoke the loop closer.
- **Connect-Analytics-To-Policy.ps1** — Loop closer. Maps a fired detection to a
  response severity, resolves the implicated user (from event data if WEC),
  contains them (deny group; Block also revokes Kerberos tickets), audits to a
  custom event log, and optionally propagates the block to Entra.

---

## Notes / follow-ups
- **Not executed** — these target Lab-DC01 / the gateway / endpoints, not the
  build host. They parse-check clean; run them in the lab and validate with
  `Invoke-ZeroTrustValidation.ps1`.
- **Dangling doc link (pre-existing)** — `README.md` references
  `../../Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md`, which does
  not exist. Left as-is pending a decision to create the design doc or drop the link.
- **External-product paths** kept as clearly-marked OPTIONAL blocks inside otherwise
  turnkey scripts (Sentinel/Elastic, WatchGuard Firebox, cloud ZTNA brokers).
