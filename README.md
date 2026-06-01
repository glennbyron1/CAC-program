# CAC/PIV Smart-Card Lab — Enterprise ICAM & Zero Trust Foundation

[![Secret Scan](https://github.com/glennbyron1/CAC-program/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/glennbyron1/CAC-program/actions/workflows/secret-scan.yml)
[![PowerShell Lint](https://github.com/glennbyron1/CAC-program/actions/workflows/ps-lint.yml/badge.svg)](https://github.com/glennbyron1/CAC-program/actions/workflows/ps-lint.yml)

**Author:** Glenn Byron | **GitHub:** [@glennbyron1](https://github.com/glennbyron1) | **License:** MIT

---

## What this is

A fully scripted, infrastructure-as-code lab that builds a **CAC/PIV smart-card authentication system** from scratch — the same model the U.S. DoD runs across its enterprise. Two-tier PKI, domain controller, smart card–enforced logon, YubiKey PIV provisioning, certificate-based VPN, OCSP, Windows Event Forwarding, and a full SCAP/STIG/Nessus compliance scan workflow. Everything automated. Everything documented with NIST SP 800-53 Rev. 5 control mapping and a complete RMF evidence package.

**Built for DoD — useful for everyone.** If you're preparing for a role at a DoD program office, a defense contractor, or a federal agency, this is a direct demonstration of the tools and workflows you'll use on the job. If you're outside that world and want to implement hardware-backed, passwordless authentication in an enterprise Windows environment, everything here applies — the PKI model, the scripts, and the compliance framework work the same way regardless of sector.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Hyper-V Host (Windows 10/11 Pro or Server)                      │
│                                                                  │
│  ┌──────────────────┐    ┌───────────────────────────────────┐   │
│  │  Lab-OfflineRootCA│    │  Lab-DC01                         │   │
│  │  (air-gapped)    │    │  Domain Controller                 │   │
│  │  4096-bit RSA    │───►│  Enterprise Issuing CA (AD CS)    │   │
│  │  10-year Root CA │    │  SmartCardLogon cert templates     │   │
│  │  No network      │    │  GPO: scforceoption=1              │   │
│  └──────────────────┘    │  OCSP Responder                    │   │
│                          │  WEF Collector / Audit Policy      │   │
│                          │  PKI Health Monitor                │   │
│                          └──────────────────┬─────────────────┘   │
│                                             │                     │
│                          ┌──────────────────▼─────────────────┐   │
│                          │  Lab-Workstation01                  │   │
│                          │  Smart card enforced logon          │   │
│                          │  IKEv2 / EAP-TLS VPN client        │   │
│                          │  SCAP SCC / STIG Viewer            │   │
│                          └─────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

Trust flows: **Offline Root CA → Enterprise Issuing CA → User Certificate → Kerberos Ticket.**
Every link is verified cryptographically at authentication time. No valid chain means no access.

---

## Why this matters for DoD and defense IT

**CAC/PIV authentication, end to end.** Not "I've read about it." Built it. The lab runs the same two-tier PKI model the DoD uses: an air-gapped Offline Root CA that signs only the Issuing CA and then goes back in the safe, an Enterprise Issuing CA that issues smart card logon certificates, and a Group Policy that enforces `scforceoption=1` — the domain will not issue a Kerberos ticket without a valid certificate on a physical token. Password is removed from the equation entirely.

**Separation of duties, by code.** The enrollment ceremony splits into two phases — Registration Authority (identity verification) and Card Issuer (certificate enrollment) — enforced by the script itself. The same account cannot complete both. This directly addresses NIST AC-5 and mirrors how DoD issuance desks actually operate.

**RMF artifacts, not just scripts.** The repo includes a System Security Plan, SAR, and POA&M mapped to SP 800-53 Rev. 5, a SCAP SCC scan workflow with real Before/After-MFA evidence, STIG Viewer checklist workflow for Windows Server 2022 / AD DS / AD CS / IIS, and a Nessus Essentials credentialed scan workflow. These aren't templates downloaded from the internet — they're wired to the lab's actual controls.

**DoD Zero Trust alignment.** The DoD Zero Trust Strategy (Oct 2022) requires Target Level activities across all seven pillars by FY2027. This lab implements the **Identity pillar — authentication leg** at an Advanced/Optimal level. The roadmap to the remaining pillars is documented in `Architecture/Roadmap/`.

**DevSecOps habits.** CI pipeline (GitHub Actions) runs PSScriptAnalyzer lint and secret scanning on every push. All scripts are idempotent, logged, and support `-WhatIf`. `Scrub-Repo.ps1` ensures no real credentials or organizational identifiers enter git history.

---

## SCAP Compliance Scan Results

Tool: SCAP Compliance Checker (SCC) 5.10.2 · Benchmark: MS_Windows_Server_2022_STIG v2.3.10

| VM | Stage | Score | CAT I Fail | CAT II Fail |
|----|-------|-------|-----------|------------|
| Lab-DC01 | Before-MFA (baseline) | 44.95% | 9 | 105 |
| Lab-DC01 | After-MFA (smart card enforced) | 42.66% | 9 | 110 |
| Lab-Workstation01 | Before-MFA (baseline) | 42.20% | 9 | 111 |
| Lab-Workstation01 | After-MFA (smart card enforced) | 42.20% | 9 | 111 |

The Before/After-MFA scans establish the STIG compliance baseline. The smart card phase addressed the Identity authentication pillar — not a full STIG hardening pass. A full STIG hardening pass using `Lab-Kit/Ansible/windows-stig-hardening.yml` is the next compliance phase and would move these scores significantly. Full scan evidence is in `Compliance-Reports/`.

---

## NIST SP 800-53 Rev. 5 Controls Addressed

| Control | Name | Implementation |
|---------|------|---------------|
| IA-2 | Identification and Authentication | Hardware-backed PIV certificate required for all interactive logon and VPN |
| IA-2(11) | Remote Access — Hardware Tokens | Smart card required for all remote sessions; no password alternative |
| IA-5 | Authenticator Management | Two-person enrollment ceremony; certificate lifecycle through AD CS |
| IA-5(2) | PKI-Based Authentication | OCSP responder with AIA extension on all issued certificates |
| AC-5 | Separation of Duties | RA and Card Issuer phases enforced by script; same account blocked from both |
| AC-11 | Session Lock | GPO forces immediate lock within 2 seconds of card removal |
| AC-17 | Remote Access | IKEv2 / EAP-TLS VPN — certificate-based, no password tunnel |
| SC-8 | Transmission Confidentiality | AES-256-GCM / SHA-256 / ECP384 FIPS-compliant IPsec policy |
| SC-17 | PKI Certificates | Two-tier PKI with offline root, OCSP, CRL publication, template management |
| AU-2 | Event Logging | Advanced Audit Policy for all Kerberos, logon, and AD CS subcategories |
| AU-9 | Protection of Audit Information | Windows Event Forwarding to central collector |
| CA-7 | Continuous Monitoring | PKI health dashboard: CRL validity, OCSP reachability, cert expiry alerts |

Full mapping in `Architecture/RMF-Templates/SSP-Template.md`.

---

## Zero Trust Maturity

Per the DoD Zero Trust Strategy and CISA ZTMM v2.0:

| Pillar | Current Level |
|--------|--------------|
| Identity — authentication | **Advanced / Optimal** ✅ |
| Identity — authorization / least privilege | Initial · Phase 8 roadmap |
| Devices | Initial · Phase 8 roadmap |
| Networks | Initial — cert-based VPN in place |
| Visibility & Analytics | Initial → Advanced — WEF + PKI health monitor |
| Automation & Orchestration | Advanced — IaC + CI/CD |
| Governance | Advanced — RMF artifacts + STIG/SCAP |

Phase 8 extends the lab to full Zero Trust Architecture: least-privilege RBAC, Kerberos Authentication Policy Silos, device certificates and posture checks, conditional/continuous access, microsegmentation, and a SIEM analytics feedback loop. Design documented in `Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md`.

---

## What's in the Repo

| Folder | Contents |
|--------|----------|
| `Lab-Kit/01-HyperV-Host/` | VM creation, post-config, snapshot manager |
| `Lab-Kit/02-OfflineRootCA/` | 8-step guided air-gapped Root CA ceremony |
| `Lab-Kit/03-DomainController/` | AD build, Issuing CA, GPO, cert templates, OCSP, token enrollment, YubiKey, audit forwarding, PKI health monitor |
| `Lab-Kit/04-Workstation/` | Smart card enforcement GPO, IKEv2/EAP-TLS VPN client |
| `Lab-Kit/05-Compliance/` | 7-layer pre-scan validator; SCAP SCC Before/After-MFA staging |
| `Lab-Kit/Ansible/` | `windows-stig-hardening.yml` — automated STIG remediation playbook |
| `Tools-Kit/` | Downloads SCAP SCC, STIG Viewer, Nessus Essentials, PSPKI |
| `Architecture/` | PKI Blueprint, STIG Hardening Guide, regulatory alignment, VPN guide |
| `Architecture/RMF-Templates/` | SSP, SAR, POA&M, ATO Letter, STIG deviation rationale, annual rescan SOP |
| `Architecture/Zero-Trust-Reference/` | 5-paper Zero Trust series + 4 SVG architecture diagrams |
| `Architecture/Roadmap/` | Phase 8 (Zero Trust Extension), Phase 9 (Azure Conditional Access VPN), Phase 9B (On-Prem VPN appliance) |
| `Compliance-Reports/` | Before-MFA and After-MFA SCAP SCC scan output with real scores |
| `Portfolio/` | Plain-language program explainers and manager briefs |
| `Live-Servers/` | Readiness checker and compliance scripts for production deployments |
| `.github/workflows/` | PSScriptAnalyzer lint and secret scan CI on every push |

Start at `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`.

---

## Commercial vs. Federal PIV — Honest Scope

This lab uses software key storage and an internal root CA — correct for a lab and for most enterprise environments. Full federal PIV requires:

| Requirement | This Lab | Federal PIV |
|-------------|----------|-------------|
| Token on GSA FIPS 201 APL | ⬜ | ✅ required |
| CA keys in FIPS 140-3 Level 3 HSM | ⬜ | ✅ required |
| Cross-certification to FBCA | ⬜ | ✅ required (NIST SP 800-217) |
| Derived credential via PIV kiosk | ⬜ | ✅ required (NIST SP 800-157) |

The architecture, scripts, and RMF documentation are accurate. The gap to full federal PIV is hardware and PKI trust anchor — a procurement decision, not a design problem. `Architecture/Federal-Compliance-Upgrade.md` maps the delta.

---

## What You Need to Run It

- A Windows machine with **Hyper-V** enabled (Win 10/11 Pro/Enterprise or Windows Server)
- ~80 GB free disk space for the three VMs
- Windows Server 2022 ISO (free evaluation from Microsoft)
- A CAC reader + card, or a **YubiKey 5** series (PIV-capable, ~$50) — or use Windows Virtual Smart Card (TPM required, no hardware purchase)

---

## Quick Start

```powershell
git clone https://github.com/glennbyron1/CAC-program.git
cd CAC-program
# Follow Lab-Kit/START-HERE.md
```

---

## Security & Sanitization

No production keys, certificates, or real credentials are in this repository. All scripts use generic placeholders (`lab.local`, `Lab-DC01`, `agency.gov`). CI runs secret scanning on every push. `Scrub-Repo.ps1` performs a find-and-replace pass before any commit using a local gitignored patterns file. See `SECURITY.md` to report a vulnerability.

---

## Disclaimer

This is a **learning and portfolio lab**, not a production deployment guide and not an accredited system. It has no Authorization to Operate (ATO) and makes no compliance claim beyond demonstrating the architecture and workflows.

- **Not affiliated with the U.S. Department of Defense**, DISA, NIST, or any government agency. DoD CAC, FIPS 201, NIST SP 800-53, and related names are referenced for educational and technical accuracy only.
- **Synthetic data only.** No real credentials, certificates, CUI, PII, or organizational data are in this repository. All hostnames and identifiers are generic lab placeholders (`lab.local`, `Lab-DC01`, `agency.gov`).
- **Lab environment only.** Scripts are designed for isolated Hyper-V lab VMs. Review thoroughly before running against any production system — the author accepts no liability for use outside a lab context.
- **Not a substitute for official training.** This lab demonstrates the skills and tools; it does not replace official DoD IA training, certification programs, or accredited security assessments.

---

## Support & Getting Help

- **Common questions:** `FAQ.md` covers hardware requirements, YubiKey compatibility, middleware, and common errors.
- **Build issues:** `TROUBLESHOOTING.md` — 300+ lines of real problems encountered during the build with solutions.
- **Bugs or script errors:** Open a [GitHub Issue](https://github.com/glennbyron1/CAC-program/issues) with the script name, the error message, and your Windows version.
- **Security concerns:** See `SECURITY.md` — do not open a public issue for vulnerabilities.
- **Contributing improvements:** See `CONTRIBUTING.md`.

---

## License & Attribution

MIT License — use it, modify it, share it. Keep the copyright notice. See `LICENSE` for full terms.

**Glenn Byron** — [@glennbyron1](https://github.com/glennbyron1)

This project is free and always will be. If it saved you hours of research or helped you land a job, a tip is a nice way to say thanks:

- [GitHub Sponsors](https://github.com/sponsors/glennbyron1)
- [Ko-fi](https://ko-fi.com/glennbyron1)

Neither is required. The code is yours either way.

See `CONTRIBUTING.md` to contribute, `FAQ.md` for common questions, and `MAINTAINER-SETUP.md` for first-time clone setup.
