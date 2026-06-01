# CAC/PIV Smart-Card Lab — Enterprise ICAM for DoD Environments

[![Secret Scan](https://github.com/glennbyron1/CAC-program/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/glennbyron1/CAC-program/actions/workflows/secret-scan.yml)
[![PowerShell Lint](https://github.com/glennbyron1/CAC-program/actions/workflows/ps-lint.yml/badge.svg)](https://github.com/glennbyron1/CAC-program/actions/workflows/ps-lint.yml)

**Author:** Glenn Byron | **GitHub:** [@glennbyron1](https://github.com/glennbyron1)
**License:** MIT — free to use with attribution. Tips welcome but never required.

---

## What this is

A fully scripted, infrastructure-as-code lab that builds a **CAC/PIV smart-card authentication system** from scratch — the same model the DoD runs across its enterprise. Two-tier PKI, domain controller, smart card–enforced logon, YubiKey PIV provisioning, certificate-based VPN, OCSP, Windows Event Forwarding, and a full SCAP/STIG/Nessus compliance scan workflow. Everything automated. Everything documented with NIST SP 800-53 Rev. 5 control mapping.

This project was built as a portfolio demonstration of the skills that matter for IT, cybersecurity, and IA roles supporting DoD programs — particularly in environments where CAC authentication, RMF compliance, and DISA STIG hardening are part of the daily job.

---

## Why this matters for DoD and defense IT

If you're hiring for a role at or around **NAS Patuxent River** — or anywhere CAC cards, STIGs, and the RMF are part of the job — here is what this project demonstrates:

**CAC/PIV authentication, end to end.**
Not "I've read about it." Built it. The lab runs the same two-tier PKI model the DoD uses: an air-gapped Offline Root CA that signs only the Issuing CA and then goes back in the safe, an Enterprise Issuing CA that issues smart card logon certificates, and a Group Policy that enforces `scforceoption=1` so the domain will not issue a Kerberos ticket without a valid certificate on a physical token. Password is removed from the equation entirely.

**Separation of duties, by code.**
The enrollment ceremony splits into two phases — Registration Authority (identity verification) and Card Issuer (certificate enrollment) — enforced by the script itself. The same account cannot complete both. This directly addresses NIST AC-5 and mirrors how DoD issuance desks actually operate.

**RMF artifacts, not just scripts.**
The repo includes a System Security Plan, SAR, and POA&M mapped to SP 800-53 Rev. 5, a SCAP SCC scan workflow with Before-MFA / After-MFA staging, STIG Viewer checklist workflow for Windows Server 2022 / AD DS / AD CS / IIS, and a Nessus Essentials credentialed scan workflow. These aren't templates downloaded from the internet — they're wired to the lab's actual controls.

**DoD Zero Trust alignment.**
The DoD Zero Trust Strategy (Oct 2022) requires Target Level activities across all seven pillars by FY2027. This lab implements the **Identity pillar — authentication leg** at an Advanced/Optimal level: phishing-resistant hardware credentials, PKI trust chain, revocation on every auth event, and audit logging mapped to the ZT Visibility pillar. The roadmap to the remaining pillars (authorization, device trust, conditional/continuous access) is documented in `Phase-8-Zero-Trust-Extension.md`.

**DevSecOps habits.**
CI pipeline (GitHub Actions) runs PSScriptAnalyzer lint and secret scanning on every push. All scripts are idempotent, logged, and support `-WhatIf`. A `Scrub-Repo.ps1` sanitizer ensures no real credentials or organizational identifiers go into git history.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Hyper-V Host (Windows 10/11 Pro or Server)                   │
│                                                               │
│  ┌──────────────────┐    ┌─────────────────────────────────┐  │
│  │  Lab-OfflineRootCA│    │  Lab-DC01                       │  │
│  │  (air-gapped)    │    │  Domain Controller               │  │
│  │  4096-bit RSA    │───►│  Enterprise Issuing CA (AD CS)  │  │
│  │  10-year Root CA │    │  SmartCardLogon cert templates   │  │
│  │  No network      │    │  GPO: scforceoption=1            │  │
│  └──────────────────┘    │  OCSP Responder                  │  │
│                          │  WEF Collector / Audit Policy    │  │
│                          │  PKI Health Monitor              │  │
│                          └────────────────┬────────────────┘  │
│                                           │                    │
│                          ┌────────────────▼────────────────┐  │
│                          │  Lab-Workstation01               │  │
│                          │  Smart card enforced logon       │  │
│                          │  IKEv2 / EAP-TLS VPN client      │  │
│                          │  SCAP SCC / STIG Viewer          │  │
│                          └─────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

Trust flows: **Offline Root CA → Enterprise Issuing CA → User Certificate → Kerberos Ticket**. Every link is verified cryptographically at authentication time. No valid chain means no access.

---

## NIST SP 800-53 Rev. 5 controls addressed

| Control | Name | How it's implemented |
|---------|------|----------------------|
| IA-2 | Identification and Authentication | Hardware-backed PIV certificate required for all interactive logon and VPN |
| IA-2(11) | Remote Access — Hardware Tokens | Smart card required for all remote sessions; no password alternative |
| IA-5 | Authenticator Management | Two-person enrollment ceremony; certificate lifecycle managed through AD CS |
| IA-5(2) | PKI-Based Authentication | OCSP responder with AIA extension on all issued certificates |
| AC-5 | Separation of Duties | RA and Card Issuer phases enforced by script; same account blocked from both |
| AC-11 | Session Lock | GPO forces immediate lock within 2 seconds of card removal |
| AC-17 | Remote Access | IKEv2 / EAP-TLS VPN — certificate-based, no password tunnel |
| SC-8 | Transmission Confidentiality | AES-256-GCM / SHA-256 / ECP384 FIPS-compliant IPsec policy |
| SC-17 | PKI Certificates | Two-tier PKI with offline root, OCSP, CRL publication, template management |
| AU-2 | Event Logging | Advanced Audit Policy for all Kerberos, logon, and AD CS subcategories |
| AU-9 | Protection of Audit Information | Windows Event Forwarding to central collector |
| AU-12 | Audit Record Generation | Event IDs 4624, 4768, 4886–4890 and others forwarded and monitored |
| CA-7 | Continuous Monitoring | PKI health dashboard: CRL validity, OCSP reachability, cert expiry alerts |

Full mapping is in `Architecture/RMF-Templates/SSP-Template.md`.

---

## What's in the repo

| Folder | What it contains |
|--------|----------------|
| `Lab-Kit/01-HyperV-Host/` | VM creation with drive selection and preflight checks, post-config, snapshot manager |
| `Lab-Kit/02-OfflineRootCA/` | 8-step guided air-gapped Root CA ceremony; enforces air-gap, exports cert + CRL |
| `Lab-Kit/03-DomainController/` | AD domain build, Issuing CA, smart card GPO, cert templates, OCSP, token enrollment, YubiKey provisioning, audit forwarding, PKI health monitor |
| `Lab-Kit/04-Workstation/` | Smart card enforcement GPO, IKEv2/EAP-TLS VPN client, middleware reference |
| `Lab-Kit/05-Compliance/` | 7-layer pre-scan validation; SCAP SCC Before/After-MFA staging |
| `Tools-Kit/` | Downloads SCAP SCC, STIG Viewer, Nessus Essentials, PSPKI to a staging folder |
| `Architecture/` | PKI Blueprint, network diagram, regulatory alignment, WatchGuard VPN guide |
| `Architecture/RMF-Templates/` | SSP, SAR, POA&M, ATO Letter template, STIG deviation rationale, CSET guide |
| `Compliance-Reports/` | Before-MFA and After-MFA scan output staging |
| `Portfolio/` | Plain-language explainers for non-technical audiences and hiring managers |
| `.github/workflows/` | PSScriptAnalyzer lint and secret scan CI on every push |

Start at `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`.

---

## Compliance scan workflow

The lab includes a full before/after SCAP SCC scan workflow:

1. `Invoke-LabValidation.ps1` — 7-layer pass/fail check before every scan (domain, PKI, smart card, GPO, audit, VPN, recent auth events)
2. Run **SCAP SCC Before-MFA** baseline scan
3. Apply smart card GPO hardening
4. Run **SCAP SCC After-MFA** hardened scan
5. `Stage-Reports.ps1` — moves results into the correct Before/After-MFA evidence folders
6. Record delta (compliance % and CAT I counts) in the SAR template

STIG Viewer checklists: Windows Server 2022, Active Directory Domain Services, AD CS, IIS 10.0.

---

## Commercial vs. federal PIV — honest scope statement

This lab uses software key storage and an internal root CA — which is correct for a lab and for most commercial environments. Full federal PIV requires:

| Requirement | This lab | Federal PIV |
|-------------|----------|-------------|
| Token on GSA FIPS 201 APL | ⬜ | ✅ required |
| CA keys in FIPS 140-3 Level 3 HSM | ⬜ | ✅ required |
| Cross-certification to FBCA | ⬜ | ✅ required (NIST SP 800-217) |
| Derived credential via PIV kiosk | ⬜ | ✅ required (NIST SP 800-157) |

The architecture, scripts, and RMF documentation are accurate. The gap to full federal PIV is hardware and PKI trust anchor — not a design problem, a procurement one.

---

## Zero Trust maturity

Per the DoD Zero Trust Strategy and CISA ZTMM v2.0:

| Pillar | Level |
|--------|-------|
| Identity — authentication | Advanced / Optimal ✅ |
| Identity — authorization / least privilege | Roadmap (Phase 8) |
| Devices | Roadmap (Phase 8) |
| Networks | Initial — cert-based VPN in place |
| Visibility & Analytics | Initial → Advanced — WEF + PKI health |
| Automation & Orchestration | Advanced — IaC + CI/CD |
| Governance | Advanced — RMF artifacts + STIG/SCAP |

Phase 8 extends the lab to full ZTA: least-privilege RBAC, Kerberos Authentication Policy Silos, device certificates + posture, conditional/continuous access, microsegmentation, and a SIEM feedback loop. Design is documented; scripts are the next build phase.

---

## What you need to run it

- A Windows machine with **Hyper-V** enabled (Win 10/11 Pro/Enterprise or Windows Server)
- ~80 GB free disk space for the three VMs
- Windows Server 2022 ISO (free evaluation from Microsoft)
- A CAC reader + card, or a **YubiKey 5** series (PIV-capable, ~$50)
- `ykman` CLI if using YubiKeys — downloaded automatically by `Tools-Kit/Download-IssuingCA-Kit.ps1`

---

## Quick start

```powershell
git clone https://github.com/glennbyron1/CAC-program.git
cd CAC-program
# Then follow Lab-Kit/START-HERE.md
```

---

## Attribution

MIT License — use it, modify it, share it. Keep the copyright notice.

> Built by Glenn Byron — https://github.com/glennbyron1/CAC-program

If this helped you prep for an interview, pass a certification, or build something real — a tip is always appreciated: [GitHub Sponsors] · [Ko-fi]

---

## Security and sanitization

No production keys, certificates, or real credentials are in this repository. All scripts use generic placeholders (`lab.local`, `Lab-DC01`). CI runs secret scanning on every push. `Scrub-Repo.ps1` performs a find-and-replace pass before any commit. See `SECURITY.md` to report a vulnerability.
