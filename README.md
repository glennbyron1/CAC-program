# CAC/PIV Smart-Card Lab — Enterprise ICAM & Zero Trust Foundation

[![Secret Scan](https://github.com/glennbyron1/CAC-program/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/glennbyron1/CAC-program/actions/workflows/secret-scan.yml)
[![PowerShell Lint](https://github.com/glennbyron1/CAC-program/actions/workflows/ps-lint.yml/badge.svg)](https://github.com/glennbyron1/CAC-program/actions/workflows/ps-lint.yml)

**Author:** Glenn Byron | **GitHub:** [@glennbyron1](https://github.com/glennbyron1) | **License:** MIT
**Releases:** [v1.4](https://github.com/glennbyron1/CAC-program/releases/tag/v1.4) (2026-06-30, latest) · [v1.2](https://github.com/glennbyron1/CAC-program/releases/tag/v1.2) (2026-06-17) · [v1.1](https://github.com/glennbyron1/CAC-program/releases/tag/v1.1) (2026-06-16) · [v1.0](https://github.com/glennbyron1/CAC-program/releases/tag/v1.0) (2026-06-03)

---

A self-built CAC/PIV smart-card authentication lab — the same model the U.S. Department of Defense uses for identity and access management — automated end-to-end and documented to federal RMF standards. Three virtual machines, a two-tier PKI, hardware-backed passwordless logon, certificate-based VPN, and a full SCAP/STIG/Nessus compliance workflow. Designed as a job-portfolio demonstration of federal ICAM, RMF, DevSecOps, and Zero Trust capability — useful in any enterprise that wants to retire passwords. **New to this repo? Start with [`Project-Narrative.md`](Project-Narrative.md) for the story, or [`Portfolio/CAC-Program-Plain-English-Overview.docx`](Portfolio/CAC-Program-Plain-English-Overview.docx) for a 2-page non-technical overview.**

> 🗺️ **Where do I go first?** → **[`MAP.md`](MAP.md)** has role-based paths (**hiring manager / engineer / ISSO / deep-dive auditor**), a 2-minute quick-proof review path, project status/maturity table, and a "where's X?" lookup table for every major deliverable.

---

## How this was built — real bugs, real fixes, real evidence

This isn't a paper design. It was built, broken, debugged, and rebuilt over six weeks of hands-on lab time. The messy parts are documented on purpose:

- **[`Architecture/Lessons-Learned/`](Architecture/Lessons-Learned/)** — dated incident write-ups: the **Silent TPM Virtual Smart Card Fallback discovery** (enrollment "succeeded" but silently landed on a TPM VSC instead of the physical YubiKey — hardware-factor failure with no error), a **stale-clone-after-git-history-rewrite** recovery, and the full v1.1 enrollment session log.
- **[`Lab-Kit/03-DomainController/Bug-Fix-Logs/`](Lab-Kit/03-DomainController/Bug-Fix-Logs/)** — real debugging output from actual runs. Example excerpt from the **PKI Health Monitor** parameterized session on 2026-06-04 (five distinct bugs surfaced in one afternoon):

  ```text
  FIX 1 — CA cert store filter too broad (false positive: expired VeriSign cert)
  ------------------------------------------------------------------------------
  Problem:
    The Where-Object filter used '$_.Issuer -like "*CA*"' which matched any cert
    with "CA" anywhere in the issuer field — including old Windows built-in
    intermediates (VeriSign, Microsoft, etc.) in LocalMachine\CA since OS
    installation. This caused CRITICAL false positives for certs expired
    since 2002 and 2016.

  Fix:
    Filter now matches on the first AD domain label (e.g. "DC=lab") derived
    from $env:USERDNSDOMAIN. Scopes results to internal PKI certs only.
  ```

  Four more like it in the same file: OCSP null-guard under StrictMode, CRL binary corruption via ASCII re-encode, certutil regex mismatch (`NextUpdate:` vs `Next Update:`), and certutil `-config` format + invalid verb. All battle-tested against the live lab and fixed in one session.

- **[`Lab-Kit/Reference/Card-Test-Matrix.md`](Lab-Kit/Reference/Card-Test-Matrix.md)** — hardware evaluation with real outcomes, including the **Hirsch uTrust FIDO2 FIPS NO-GO** finding (PIV interface requires vendor-only management key; procurement blocker documented).

- **[`Project-Narrative.md`](Project-Narrative.md)** — first-person Q&A covering design decisions, hardest bug (Silent VSC Fallback), what I'd do differently (line-endings, benchmark version commitment, network topology planning), and "things I learned the hard way" that aren't elsewhere in the repo.

- **[`TODO.md`](TODO.md) Recent Wins log** — dated chronological development record from v1.0 through v1.4.

- **Operator gotchas** — [`Lab-Kit/Reference/TROUBLESHOOTING.md`](Lab-Kit/Reference/TROUBLESHOOTING.md) for the "why isn't this working?" catalog, [`WALKTHROUGH.md`](WALKTHROUGH.md) §Gotchas for build-time surprises (UTF-8 BOM on scripts, LabInternal vs External switch pitfalls, unblock-file), [`FAQ.md`](FAQ.md) §Troubleshooting for the quick-answer version.

If the docs read as too clean elsewhere, that's the federal documentation register (SSPs, SARs, POA&Ms have to look like this — those are the standards). The messy human work is in the folders above.

---

## What's new in v1.4 (2026-07-01)

**Headline: LAB-DC01 SCAP score climbed from 44.95% → 86.7% via Ansible STIG remediation. 8 CAT I findings verified closed.**

- **Ansible STIG remediation applied to LAB-DC01 — 44.95% → 86.7% SCAP.** New module at [`Lab-Kit/08-Ansible-STIG/`](Lab-Kit/08-Ansible-STIG/) using the community `ansible-lockdown/Windows-2022-STIG` role driven from a WSL2 control node on the Hyper-V host. Three severity-tagged phases (CAT I → II → III) applied with VM snapshot + `win_ping` verification between each. Per-CAT closures: CAT I Fail 9→1 · CAT II Fail 105→27 · CAT III Fail 6→1. Visual evidence in `Screenshots/08a/08b/08c-stig-dc01-*pct.png`; full SCC scan archives at [`Compliance-Reports/After-Ansible/`](Compliance-Reports/After-Ansible/).
- **8 CAT I findings verified closed in the POA&M** — POA-001/002/003 (AutoPlay), POA-007 (Windows Installer elevated), POA-009/010 (WinRM Basic), POA-013 (anonymous shares), POA-015 (LM auth) — all confirmed passing in the post-Ansible SCAP scan. POA&M Document Control updated to v1.4 with full closure narrative.
- **Phase 8 Zero Trust extension: 13 scaffolds → full implementations.** Every previously-scaffolded ZT script in `Lab-Kit/07-ZeroTrust/` shipped as a full, idempotent, parse-clean PowerShell module. Phase 8 goes from "8 full + 13 scaffolds" (v1.0) to **21 full scripts** in v1.4. Coverage spans all ZT pillars: Authorization & Least Privilege, Device Trust, Continuous & Conditional Access, Workload Identity, Network Segmentation, Visibility & Decisioning. Per-script summary: [`Lab-Kit/07-ZeroTrust/CHANGELOG-Phase8.md`](Lab-Kit/07-ZeroTrust/CHANGELOG-Phase8.md).
- **Defensive cert-audit tool — [`security/scripts/Check-SelfSignedCerts.ps1`](security/scripts/Check-SelfSignedCerts.ps1).** Scans LocalMachine + CurrentUser cert stores and optional remote TLS endpoints, with SHA-1 thumbprint protection for the offline Root CA so the known-good self-signed root is excluded from the unprotected count. Tags `PROTECTED (Offline CA)` / `SELF-SIGNED` / `CA-ISSUED`. CSV + pipeline output. Hardened pre-ship (BeginConnect/EndConnect pairing, `[CmdletBinding()]`, `-OutputPath` defaulting to `$env:TEMP`).
- **Topology change recorded: LAB-DC01 now dual-NIC** (`10.10.20.10` External + `10.10.10.10` Internal). The second NIC was added for the WSL Ansible reach path; the lab segment remains flat L2 (the "honest caveat on partitioning" framing is preserved). See [`Architecture/Lab-Topology.md`](Architecture/Lab-Topology.md).
- **Portfolio refreshed + new plain-English explainer.** All 5 active Portfolio docx files refreshed with a v1.4 milestone callout on page 1. New [`Portfolio/CAC-Program-Plain-English-Overview.docx`](Portfolio/CAC-Program-Plain-English-Overview.docx) — 2-page non-technical overview for hiring managers + recruiters.
- **Honest framing throughout.** The remaining 29 CAT-fails on LAB-DC01 are exactly what the role's `disruption_high: false` + `complexity_high: false` safety guards exclude, plus manual AUDIT items, plus four Server-2025 vs. 2022-benchmark mismatches disabled in `group_vars`. ZT extension scripts are "designed → built (parse-clean), not yet built → run." Federal documentation pattern.

Full release notes on the [v1.4 tag](https://github.com/glennbyron1/CAC-program/releases/tag/v1.4).

## What's new in v1.2 (2026-06-17)

- **Same physical YubiKey now unlocks AD AND Azure VPN.** One slot 9a cert, two authentication contexts: Kerberos PKINIT (Event 4768 Pre-Auth Type 16) for Active Directory logon, EAP-TLS for Azure Point-to-Site VPN. The credential never leaves the hardware token; both authentications validate the same chain to the same internal Lab-CA. One possession factor, one knowledge factor, two clouds — without ever provisioning a parallel "VPN credential."
- **Phase 9 Azure VPN built end-to-end** — Resource group with budget alert, VNet with `GatewaySubnet`, VpnGw1 VPN Gateway, Lab-CA cert uploaded as Azure trust anchor, jdoe's YubiKey-resident smart card cert authenticates EAP-TLS tunnel. P2S client assigned `172.16.0.2`. Full deploy → test → teardown cycle in one session (~$0.40 in gateway hours). Build guide: [`Architecture/Azure-VPN-Guide.md`](Architecture/Azure-VPN-Guide.md) (ARCH-ICAM-013).
- **Slot 5 of Demo-Walkthrough closed** — `Screenshots/05-vpn-azure-eap-cert-auth-no-password.png` shows `jdoe@lab.local` connected to `vnet-cac-lab-phase9` with EAP-TLS cert auth, no password prompt. All 8 demo-walkthrough slots are now captured.
- **PKI architecture discovery published** — design says two-tier (offline Root signs Issuing CA), deployment is single-tier (LAB-CA operating as its own root, with `Lab Root CA` cert constrained by `pathlen:0` so it cannot have signed a sub-CA per RFC 5280). Captured honestly in the Azure VPN guide as a "designed vs deployed" delta.
- **Three Azure VPN docs consolidated to one canonical guide** — the original "starter" guide + the build doc + the roadmap design folded into `Architecture/Azure-VPN-Guide.md`. Parallels the existing `Architecture/WatchGuard-IKEv2-VPN-Guide.md` for on-prem.

Full release notes on the [v1.2 tag](https://github.com/glennbyron1/CAC-program/releases/tag/v1.2).

## What's new in v1.1 (2026-06-16)

- **Silent TPM Virtual Smart Card Fallback discovery** — original DevSecOps finding: smart card enrollment can silently land on a TPM-backed VSC instead of the intended physical token, defeating hardware-factor assurance with no error. Detection methodology + four-point operator acceptance check published in [`Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`](Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md). Maps to NIST IA-2(11), IA-5(11), CM-6, AU-6.
- **YubiKey PIV enrollment validated end-to-end** — physical token + Yubico minidriver + Enroll-on-Behalf + Issuing CA + smart-card-required GPO. Lock screen, cert chain verification, and 2-second lock-on-removal screenshots captured.
- **Two operator runbooks** — [`RUNBOOK-YubiKey-Enrollment.md`](Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md) (scripted path) + [`MANUAL-Enrollment-Walkthrough.md`](Lab-Kit/Reference/MANUAL-Enrollment-Walkthrough.md) (GUI / copy-a-peer-in-ADUC path). Both runbooks cross-reference; together they show the same workflow at two automation levels.
- **Card-Test-Matrix methodology** — hardware-evaluation framework applied to YubiKey 5 NFC (✅ PIV + FIDO2 working) and Hirsch uTrust FIDO2 FIPS (❌ PIV NO-GO, vendor mgmt key required; FIDO2 works). Procurement-evaluation criterion stated explicitly for future card form factors. [`Lab-Kit/Reference/Card-Test-Matrix.md`](Lab-Kit/Reference/Card-Test-Matrix.md).
- **Scrub-Repo.ps1 hardening** — two bug fixes caught by `-WhatIf` preview before any file was touched (`_*` meta-key filter, gitignored-tool exclusion). Shipped publicly as documentation for anyone forking the scrub pattern.

Full release notes on the [v1.1 tag](https://github.com/glennbyron1/CAC-program/releases/tag/v1.1).

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

The Before/After-MFA scans establish the STIG compliance baseline. The smart card phase addressed the Identity authentication pillar — not a full STIG hardening pass. **The full STIG hardening pass shipped in v1.4** via `Lab-Kit/08-Ansible-STIG/` (ansible-lockdown Windows-2022-STIG role from a WSL2 control node), moving LAB-DC01 from **44.95% → 86.7%** in three severity-tagged phases. Full scan evidence in `Compliance-Reports/` (Before-MFA, After-MFA, After-Ansible).

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
| `Lab-Kit/03-DomainController/` | AD build, Issuing CA, GPO, cert templates, OCSP, token enrollment (RA + Issuer SoD ceremony), YubiKey PIV provisioning, AD user creation with OU resolver, SMB-based script deploy helper, audit forwarding, PKI health monitor |
| `Lab-Kit/04-Workstation/` | Smart card enforcement GPO, IKEv2/EAP-TLS VPN client |
| `Lab-Kit/05-Compliance/` | 7-layer pre-scan validator; SCAP SCC Before/After-MFA staging; `Invoke-SCAPWorkflow.ps1` automation; SCAP workflow quick reference |
| `Lab-Kit/06-PhysicalEndpoint/` | Physical laptop onboarding (WO02): domain join, vTPM/VSC creation, smart card cert enrollment, full Add-Physical-Laptop guide |
| `Lab-Kit/07-ZeroTrust/` | Phase 8 Zero Trust extension: tiered admin model, auth policy silos, device certs, Kerberos lifetime hardening, microsegmentation, ZT validator (8 full + 13 scaffolds + ZT demo walkthrough) |
| `Lab-Kit/08-Ansible-STIG/` | **v1.4 module.** ansible-lockdown Windows-2022-STIG role driven from a WSL2 control node, severity-tagged remediation, WinRM/HTTPS target prep. Applied to LAB-DC01: **44.95% → 86.7% SCAP**. Includes `utilities/` (AD health check, cert expiry report, v1.0-era hand-rolled scaffold preserved as `windows-stig-hardening_SUPERSEDED.yml`). |
| `Lab-Kit/Reference/` | Operator runbooks (scripted RUNBOOK-ICAM-001 + manual GUI walkthrough RUNBOOK-ICAM-002), `Card-Test-Matrix.md` hardware-evaluation methodology, sanitized ONBOARDING + TROUBLESHOOTING synced from the lab |
| `Tools-Kit/` | Downloads SCAP SCC, STIG Viewer, Nessus Essentials, PSPKI |
| `Architecture/` | PKI Blueprint, STIG Hardening Guide, regulatory alignment, [`WatchGuard-IKEv2-VPN-Guide.md`](Architecture/WatchGuard-IKEv2-VPN-Guide.md) (on-prem VPN), [`Azure-VPN-Guide.md`](Architecture/Azure-VPN-Guide.md) (cloud VPN with cert auth via YubiKey, ARCH-ICAM-013, v1.2), [`Lab-Topology.md`](Architecture/Lab-Topology.md) (air-gap design with NIST SC-7 / AC-4 / CM-7 mapping, ARCH-ICAM-014) |
| `Architecture/RMF-Templates/` | SSP, SAR, POA&M, ATO Letter, STIG deviation rationale, annual rescan SOP |
| `Architecture/Lessons-Learned/` | DevSecOps incident-response and discovery write-ups — Silent VSC Fallback discovery (Issue #9), stale-clone-after-history-rewrite recovery, full v1.1 enrollment session log |
| `Architecture/Zero-Trust-Reference/` | 5-paper Zero Trust series + 4 SVG architecture diagrams |
| `Architecture/Roadmap/` | Phase 8 (Zero Trust Extension), Phase 9B (On-Prem VPN appliance — optional, not planned). Note: Phase 9 (Azure VPN) shipped in v1.2 and was consolidated into [`Architecture/Azure-VPN-Guide.md`](Architecture/Azure-VPN-Guide.md). |
| `Compliance-Reports/` | Before-MFA and After-MFA SCAP SCC scan output with real scores; `Compliance-Reports/PKI-Health/` audit logs from `Monitor-PKIHealth.ps1` runs |
| `Portfolio/` | Plain-language program explainers and manager briefs |
| `Live-Servers/` | Readiness checker and compliance scripts for production deployments |
| `Screenshots/` | Real lab captures — all 8 Demo-Walkthrough slots (lock screen, PIN entry, PKINIT validation, lock-on-removal, Azure VPN Connected, PKI health dashboard, SCAP before/after, WO02 STIG) + supporting session evidence + FIDO2 webauthn credential cards + Silent VSC Fallback discovery shot |
| `security/` | `POLICY.md` (security policy), `INCIDENT_RESPONSE.md` (incident-response procedure), `security/scripts/pre-commit` (git hook). Local-only scrub tools (gitignored) live alongside: `Scan-LocalRepo.ps1` + `SCAN-README.md`. |
| `.github/workflows/` | PSScriptAnalyzer lint and secret scan CI on every push |

**Where to start:**

- **Build the lab** — `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md` for the operator-checklist build sequence, OR [`WALKTHROUGH.md`](WALKTHROUGH.md) for the long-form lab build narrative.
- **Demo the lab** — [`Demo-Walkthrough.md`](Demo-Walkthrough.md) covers all 8 captured slots (lock screen → PIN entry → PKINIT validation → lock-on-removal → Azure VPN connected → PKI health → SCAP delta → WO02 STIG).
- **Learn the concepts** — [`LAB-LEARNING-GUIDE.md`](LAB-LEARNING-GUIDE.md) covers the underlying PKI / smart card / Zero-Trust concepts the lab demonstrates.
- **Track what's open** — [`TODO.md`](TODO.md) is the living phase/milestone tracker; [`CHANGELOG.md`](CHANGELOG.md) records what shipped in each release tag.
- **Package the kit** — `Pack-LabKit.ps1` bundles the Lab-Kit folder for transfer (used when bootstrapping a new lab from this repo on a fresh host).

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
- **Build issues:** [`Lab-Kit/Reference/TROUBLESHOOTING.md`](Lab-Kit/Reference/TROUBLESHOOTING.md) — running FAQ of real problems encountered during the build, with fixes (smart card lockout, GPO scope errors, SYSVOL recovery, DSRM limitations, SCC paths, PowerShell gotchas, physical endpoint issues).
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
