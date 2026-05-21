# Regulatory Alignment: CAC/PIV Program

Document ID: ARCH-ICAM-003
Author: Glenn Byron
Framework Alignment: CISA Zero-Trust Maturity Model | NIST CSF 2.0 | CISA Cross-Sector CPGs | MD Senate Bill 871

---

## Overview

This document maps the CAC/PIV identity program to three regulatory frameworks
cited in **Maryland Senate Bill 871** (Water and Wastewater Cybersecurity,
introduced January 28, 2025) and to the bill's incident reporting requirements.
The bill mandates zero-trust adoption aligned with the CISA Zero-Trust Maturity
Model, cybersecurity standards meeting or exceeding CISA Cross-Sector
Cybersecurity Performance Goals, and education referencing NIST CSF 2.0.

---

## 1. CISA Zero-Trust Maturity Model (ZTMM) Alignment

The CISA ZTMM organizes zero-trust adoption across five pillars. The CAC/PIV
program directly addresses the Identity and Devices pillars — the two pillars
that are prerequisites for all others.

### 1.1 Identity Pillar

| ZTMM Capability | CAC/PIV Implementation | Maturity Stage |
|---|---|---|
| Enterprise-wide MFA | Smart card / FIDO2 enforced via GPO for all interactive and remote logons | Advanced |
| Phishing-resistant MFA | Hardware-backed PIV/CAC certificates — not OTP, push, or SMS | Optimal |
| Identity governance | Registration Authority / Card Issuer separation of duties (NIST AC-5) | Advanced |
| Privileged identity management | Separate YubiKey slot for administrative accounts; no shared admin credentials | Advanced |
| Continuous identity validation | OCSP real-time revocation checking; card removal triggers immediate session lock (AC-11) | Advanced |
| Derived credentials | Secondary tokens (YubiKey) issued via in-person RA photo-ID verification; federal path: NIST SP 800-157 automated derivation | Advanced (commercial) / Optimal (federal) |

### 1.2 Devices Pillar

| ZTMM Capability | CAC/PIV Implementation | Maturity Stage |
|---|---|---|
| Device authentication | Workstations must present a valid domain certificate and smart card simultaneously for VPN EAP-TLS | Advanced |
| Endpoint compliance enforcement | DISA STIG hardening applied via SCAP Compliance Checker; before/after audit trail in Compliance-Reports/ | Advanced |
| Hardware token binding | Certificates are generated inside the hardware token and are non-exportable | Optimal |
| Supply chain assurance | Federal upgrade path: all tokens sourced from GSA FIPS 201 Approved Product List (APL) | Optimal (federal path) |

**ZTMM References:** CISA Zero Trust Maturity Model v2.0 (April 2023),
[cisa.gov/zero-trust-maturity-model](https://www.cisa.gov/zero-trust-maturity-model)

---

## 2. NIST Cybersecurity Framework 2.0 Function Mapping

Senate Bill 871 Section 2 requires education referencing NIST CSF 2.0. The
table below maps CAC/PIV program components to the six CSF 2.0 functions.

| CSF 2.0 Function | Category | CAC/PIV Implementation |
|---|---|---|
| **Govern (GV)** | Cybersecurity Policy | Blueprint.md defines PKI policy, separation of duties, and token lifecycle governance |
| **Govern (GV)** | Roles and Responsibilities | Registration Authority / Card Issuer split; PKI Admin role separate from Domain Admin |
| **Identify (ID)** | Asset Management | Hardware token inventory; certificate lifecycle tracked in AD CS database |
| **Identify (ID)** | Risk Assessment | Federal Compliance Gap Analysis documents risk delta between commercial and federal posture |
| **Protect (PR)** | Identity Management and Access Control | Hardware-backed MFA enforced via GPO; zero-password interactive logon topology |
| **Protect (PR)** | Awareness and Training | Operator certification cybersecurity components (per SB 871 §9-2702); STIG Hardening Guide |
| **Protect (PR)** | Data Security | Non-exportable private keys; FIPS 140-2/3 HSM for CA keys (federal upgrade path) |
| **Protect (PR)** | Platform Security | DISA STIG baseline applied; SCAP before/after audit in Compliance-Reports/ |
| **Protect (PR)** | Technology Infrastructure Resilience | HTTP CRL/OCSP HA endpoints; WAN failure mode matrix in Blueprint.md |
| **Detect (DE)** | Adverse Event Analysis | AD CS audit logging (certutil -setreg CA\AuditFilter 127); SIEM-ready event logs |
| **Respond (RS)** | Incident Management | See Section 4: Incident Reporting Procedure |
| **Respond (RS)** | Incident Analysis | Certificate revocation workflow; immediate CRL publish on confirmed compromise |
| **Recover (RC)** | Incident Recovery Plan | CA backup and DR procedure; Issuing CA rebuild from Root CA signing ceremony |

**NIST CSF 2.0 Reference:** [nist.gov/cyberframework](https://www.nist.gov/cyberframework)

---

## 3. CISA Cross-Sector Cybersecurity Performance Goals (CPG) Mapping

Senate Bill 871 §9-2702 and §9-2705 require cybersecurity standards that meet
or exceed CISA's Cross-Sector CPGs. The CAC/PIV program directly satisfies the
following goals:

| CPG ID | Goal Description | CAC/PIV Implementation | Status |
|---|---|---|---|
| 2.A | Phishing-resistant MFA for all users | Hardware PIV/CAC certificate — not OTP or push | ✅ Satisfied |
| 2.B | Phishing-resistant MFA for remote access | EAP-TLS smart card authentication on WatchGuard IKEv2 VPN | ✅ Satisfied |
| 2.C | MFA for privileged accounts | Separate YubiKey administrative slot; privileged accounts cannot log in without hardware token | ✅ Satisfied |
| 2.D | MFA for IT systems management | All AD, AD CS, and PKI management requires authenticated admin smart card session | ✅ Satisfied |
| 4.A | Separation of privileges | RA / Card Issuer role separation; PKI Admin ≠ Domain Admin | ✅ Satisfied |
| 4.B | Revocation capabilities | OCSP real-time revocation; delta CRL published every 1–8 hours | ✅ Satisfied |
| 5.A | Basic incident detection | AD CS audit log; Windows Event Log forwarding | ✅ Satisfied (basic) |
| 5.B | Centralized log collection | Architecture supports SIEM ingestion; implementation site-dependent | ⚠️ Architecture-ready |
| 6.A | Incident response plan | See Section 4 of this document | ✅ Documented |
| 6.B | Incident reporting to authorities | See Section 4 of this document | ✅ Documented |

**CISA CPG Reference:** CISA Cross-Sector Cybersecurity Performance Goals
(October 2022, updated 2023), [cisa.gov/cross-sector-cybersecurity-performance-goals](https://www.cisa.gov/cross-sector-cybersecurity-performance-goals)

---

## 4. Incident Reporting Procedure

Senate Bill 871 §9-2707 requires community water system and sewerage system
providers to report cybersecurity incidents to the **State Security Operations
Center (SOC)** in the Department of Information Technology. This section
documents the reporting procedure aligned with that requirement.

### 4.1 What Must Be Reported

Report any of the following to the State Security Operations Center
immediately upon discovery:

- Confirmed or suspected unauthorized access to any information technology (IT)
  or operational technology (OT) system
- Ransomware infection or encryption of systems
- Compromise of any identity credential, including smart card private keys or
  CA private keys
- Denial-of-service attack affecting authentication, certificate validation, or
  network access
- Loss or theft of a hardware token (smart card, YubiKey) assigned to a
  privileged account
- Any event resulting in root-level or CA-level compromise

### 4.2 Reporting Timeframes

| Severity | Definition | Reporting Deadline |
|---|---|---|
| Critical | Root CA compromise, ransomware, confirmed unauthorized access to OT systems | Immediately — within 1 hour of discovery |
| High | Issuing CA compromise, domain-level credential theft, service-affecting DoS | Within 4 hours of discovery |
| Medium | Individual token loss/theft (privileged account), suspicious authentication anomalies | Within 24 hours of discovery |
| Low | Individual token loss/theft (standard user), policy violations with no confirmed compromise | Within 72 hours of discovery |

### 4.3 Who to Notify

| Recipient | Contact Method | Authority |
|---|---|---|
| State Security Operations Center (MD DoIT) | Maryland Cyber Incident Reporting Portal or CISO hotline | MD Senate Bill 871 §9-2707 |
| Maryland Department of Emergency Management — Cyber Preparedness Unit | Via State SOC notification chain | MD Public Safety Article §14-104.1 |
| Maryland Information Sharing and Analysis Center (MD-ISAC) | If member: direct reporting channel | MD Senate Bill 871 §9-2703 |
| Internal PKI Administrator | Direct — revoke affected certificate immediately | Internal policy |
| CISA (if federal-scope incident) | [cisa.gov/report](https://www.cisa.gov/report) | CIRCIA (federal) |

### 4.4 Immediate Technical Response Steps

Upon discovery of any Critical or High severity incident:

1. **Isolate** the affected system from the network immediately.
2. **Revoke** any potentially compromised certificates via the Issuing CA:
   ```powershell
   # Revoke certificate by serial number
   certutil -revoke <SerialNumber> 3   # reason code 3 = Key Compromise
   # Immediately publish updated CRL
   certutil -CRL
   ```
3. **Preserve** system state — do not reboot or wipe before imaging.
4. **Notify** the State SOC within the timeframe specified in Section 4.2.
5. **Document** a timeline of events for the incident report.
6. If the Issuing CA private key is compromised: power on the Offline Root CA,
   revoke the Issuing CA certificate, and follow the CA rebuild procedure
   in `Architecture/Blueprint.md`.

### 4.5 Post-Incident Reporting

Per Senate Bill 871 §9-2707(d), the Office of Security Management in the
Department of Information Technology publishes an annual aggregated report of
cybersecurity incidents reported by water and wastewater systems. Maintain
internal records of all reported incidents for at least three years.

---

## 5. Senate Bill 871 Reference Summary

| Bill Section | Requirement | CAC/PIV Program Response |
|---|---|---|
| §9-2702(3)(ii) | Adopt cybersecurity standards meeting or exceeding CISA CPGs | Section 3: CPG Mapping |
| §9-2705(b)(2) | Adopt CISA Zero-Trust Maturity Model approach | Section 1: ZTMM Alignment |
| §9-2705(b)(3) | Annual third-party assessment of IT/OT devices | Architecture supports SCAP/ACAS assessments; see STIG-Hardening-Guide.md |
| §9-2707 | Report cybersecurity incidents to State SOC | Section 4: Incident Reporting Procedure |
| Section 2(b)(2) | Reference NIST CSF 2.0 | Section 2: CSF 2.0 Function Mapping |
| Section 2(b)(5) | Reference CISA "Top Cyber Actions for Securing Water Systems" | Addressed via CPG mapping and zero-trust posture |

---

*This document is maintained as part of the CAC/PIV Program compliance track.
For the federal compliance gap analysis, see `Architecture/Blueprint.md §5`.
For STIG hardening procedures, see `Architecture/STIG-Hardening-Guide.md`.*
