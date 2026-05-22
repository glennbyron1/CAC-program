# System Security Plan (SSP)

Document ID: ARCH-ICAM-006
Author: Glenn Byron
Framework: NIST SP 800-53 Rev. 5 | NIST SP 800-37 Rev. 2 RMF Authorize | FIPS 199 | FIPS 201-3

> **How to use this template:** Fields marked `[FILL IN]` require real values from your environment.
> Fields marked with example content are pre-populated based on this program's architecture —
> review and adjust to match your specific deployment. This document is a Phase 5 (RMF Authorize)
> deliverable. Complete Phase 4 (STIG scans, Nessus results) before finalizing this SSP.

---

## 1. System Identification

| Field | Value |
|-------|-------|
| System Name | Enterprise CAC/PIV Identity & Access Management (ICAM) System |
| System Abbreviation | ICAM-01 |
| Document ID | ARCH-ICAM-006 |
| System Owner | [FILL IN — Name, Title, Organization] |
| Authorizing Official (AO) | [FILL IN — Name, Title] |
| Information System Security Officer (ISSO) | [FILL IN — Name, Title] |
| Prepared By | Glenn Byron |
| Date Prepared | [FILL IN] |
| Version | 1.0 |

---

## 2. System Overview

### 2.1 Purpose

This system deploys hardware-backed, certificate-based multi-factor authentication (MFA) across
enterprise infrastructure running Active Directory, Active Directory Certificate Services (AD CS),
WatchGuard IKEv2 VPN, and Microsoft 365 (Entra ID). It replaces password-based authentication
with a zero-password topology using smart cards and FIDO2 security keys.

The architecture follows the DoD Common Access Card (CAC) and Federal PIV operating model and is
designed for commercial enterprise deployment with a documented upgrade path to full
FISMA/FedRAMP authorization.

### 2.2 System Description

The ICAM system consists of the following major components:

| Component | Role | Hostname / IP |
|-----------|------|---------------|
| Offline Root CA | Trust anchor — standalone, air-gapped, permanently offline | [FILL IN] |
| Enterprise Issuing CA | Active enrollment engine — domain-joined, running AD CS | [FILL IN] |
| Domain Controller | Active Directory authentication and Kerberos PKINIT | [FILL IN] |
| HTTP CRL Server | Certificate revocation list distribution (IIS on port 80) | [FILL IN] |
| WatchGuard Firebox | IKEv2 VPN gateway with EAP-TLS smart card authentication | [FILL IN] |
| Admin Workstation | PKI administration, STIG scanning, enrollment operations | [FILL IN] |
| Enrolled Endpoints | Windows workstations with smart card logon enforced | [FILL IN — range or count] |

### 2.3 System Boundary

The authorization boundary includes:
- The two-tier PKI (Offline Root CA and Enterprise Issuing CA)
- The Active Directory domain and domain controllers
- The HTTP CRL distribution server
- The WatchGuard IKEv2 VPN gateway
- All domain-joined Windows endpoints with smart card enforcement

**Out of scope:** Microsoft 365 / Entra ID is considered a leveraged external system. Conditional
Access policy configuration is documented but Entra ID itself is not within this authorization boundary.

### 2.4 Data Types and Sensitivity

| Data Type | Sensitivity | Location |
|-----------|-------------|----------|
| CA private keys | HIGH — loss = total PKI compromise | Offline Root CA (air-gapped); Issuing CA (software KSP) |
| Issued certificates | MODERATE | AD CS database; enrolled hardware tokens |
| CRL files | LOW (public) | HTTP CRL server |
| AD user accounts | MODERATE | Active Directory |
| Audit logs | MODERATE | Windows Event Log; AD CS audit log |

---

## 3. System Categorization

### 3.1 FIPS 199 Impact Assessment

Per FIPS 199 and NIST SP 800-60, this system is categorized as follows:

| Security Objective | Potential Impact | Rationale |
|-------------------|------------------|-----------|
| Confidentiality | **HIGH** | Compromise of CA private keys would allow issuing fraudulent credentials, enabling identity fraud across the entire enterprise |
| Integrity | **HIGH** | Tampering with the PKI trust chain or CRL data could allow revoked credentials to authenticate or deny access to valid users |
| Availability | **MODERATE** | Authentication failures affect operations, but short-term outages can be tolerated if CRL caching is properly configured |

**Overall System Categorization: HIGH** (per FIPS 199 high-water mark rule)

### 3.2 CNSSI 1253 Overlay (if applicable)

[FILL IN — note any applicable CNSSI 1253 overlays, e.g., Privacy, Classified, or specific community overlays]

---

## 4. Applicable Laws, Regulations, and Standards

| Requirement | Reference |
|-------------|-----------|
| Federal Information Security Modernization Act | FISMA (44 U.S.C. § 3551) |
| Identity credential requirements | FIPS 201-3 (PIV) |
| Cryptographic standards | FIPS 140-3 |
| Security controls baseline | NIST SP 800-53 Rev. 5 |
| Risk Management Framework | NIST SP 800-37 Rev. 2 |
| PKI and certificates | NIST SP 800-57 (Key Management) |
| Derived credentials | NIST SP 800-157 |
| Zero Trust | CISA ZTMM v2.0 |
| Maryland water/wastewater (if applicable) | MD Senate Bill 871 §9-2705 |

---

## 5. Roles and Responsibilities

| Role | Responsibilities | Assigned To |
|------|-----------------|-------------|
| System Owner | Overall accountability for system security and ATO maintenance | [FILL IN] |
| Authorizing Official (AO) | Accept residual risk; grant or deny ATO | [FILL IN] |
| ISSO | Day-to-day security posture monitoring; POA&M tracking; annual reviews | [FILL IN] |
| PKI Administrator | CA operations, CRL publishing, certificate template management | [FILL IN] |
| Registration Authority (RA) | Identity verification during token enrollment (NIST AC-5) | [FILL IN] |
| Card Issuer | Technical token provisioning — separate from RA role (NIST AC-5) | [FILL IN] |
| System Administrator | AD, GPO, domain controller, and endpoint management | [FILL IN] |

---

## 6. Implemented Security Controls

This section maps implemented controls to specific artifacts in this repository. Controls are drawn
from NIST SP 800-53 Rev. 5 at the HIGH baseline, tailored for this system.

### 6.1 Access Control (AC)

| Control | Title | Implementation | Evidence |
|---------|-------|----------------|----------|
| AC-2 | Account Management | AD accounts managed through standard provisioning process; smart card logon required | AD user account records |
| AC-3 | Access Enforcement | GPO enforces smart card requirement; standard password logon blocked enterprise-wide | `Build-CA-GPO.ps1`; `Group-Policy/Enforce-SmartCard.ps1` |
| AC-5 | Separation of Duties | Registration Authority and Card Issuer are separate roles; no single administrator can perform both | `Architecture/Blueprint.md §4.1`; enrollment SOP |
| AC-11 | Session Lock | GPO triggers immediate workstation lock within 2 seconds of smart card removal | `Build-CA-GPO.ps1` (ScRemoveOption = 1); `Group-Policy/README.md` |
| AC-17 | Remote Access | WatchGuard IKEv2 VPN requires EAP-TLS certificate authentication; no password-based VPN tunnels | `Architecture/WatchGuard-IKEv2-VPN-Guide.md`; `Automation-Scripts/Deploy-VPNClient.ps1` |
| AC-17(2) | Remote Access — Protection of Confidentiality/Integrity | IKEv2 tunnel uses AES-256-GCM; all VPN traffic encrypted in transit | `Deploy-VPNClient.ps1` IPsec policy settings |

### 6.2 Audit and Accountability (AU)

| Control | Title | Implementation | Evidence |
|---------|-------|----------------|----------|
| AU-2 | Event Logging | AD CS audit logging enabled (`certutil -setreg CA\AuditFilter 127`); Windows Event Log captures smart card logon events (4768, 4769, 4776) | `Stage-Reports.ps1`; AD CS audit configuration |
| AU-9 | Protection of Audit Information | Audit logs stored on domain controllers; access restricted to administrators | AD permissions |
| AU-12 | Audit Record Generation | SCAP SCC scans generate XCCDF audit records; stored in `Compliance-Reports/` | `Compliance-Reports/After-MFA/` |

### 6.3 Security Assessment and Authorization (CA)

| Control | Title | Implementation | Evidence |
|---------|-------|----------------|----------|
| CA-2 | Security Assessments | SCAP SCC STIG scans executed before and after hardening; results staged by `Stage-Reports.ps1` | `Compliance-Reports/Before-MFA/`; `Compliance-Reports/After-MFA/` |
| CA-5 | Plan of Action and Milestones | POA&M maintained in `Architecture/POAM-Template.md`; updated after each assessment cycle | `Architecture/POAM-Template.md` |
| CA-6 | Authorization | ATO package includes this SSP, SAR, and POA&M; submitted to Authorizing Official | This document; `Architecture/SAR-Template.md` |
| CA-7 | Continuous Monitoring | Monthly SCAP re-scans planned; CRL/OCSP health monitoring; Windows Event Log review | `ROADMAP.md Phase 6`; `Automation-Scripts/Download-FedCompliance-Kit.ps1` |

### 6.4 Identification and Authentication (IA)

| Control | Title | Implementation | Evidence |
|---------|-------|----------------|----------|
| IA-2 | Identification and Authentication | Hardware-backed smart card (PIV/CAC model) required for all interactive logons; FIDO2 security keys for Microsoft 365 | `Build-CAC-Lab.ps1`; `Architecture/Blueprint.md` |
| IA-2(1) | MFA for Privileged Accounts | Administrative accounts require separate hardware token (YubiKey administrative slot); no shared admin credentials | `Architecture/Blueprint.md §4.2` |
| IA-2(11) | Workstation Logon Using Hardware Tokens | GPO sets `scforceoption = 1`; standard password logon blocked at the workstation level | `Group-Policy/Enforce-SmartCard.ps1`; `Group-Policy/README.md` |
| IA-3 | Device Identification and Authentication | VPN EAP-TLS requires both user certificate (smart card) and WatchGuard server certificate from trusted CA | `WatchGuard-IKEv2-VPN-Guide.md §3` |
| IA-5 | Authenticator Management | Token lifecycle: RA identity verification → Card Issuer provisioning → mandatory PIN change; revocation via AD CS | `Architecture/Blueprint.md §4`; `Download-IssuingCA-Kit.ps1` |
| IA-8 | Identification and Authentication (Non-Org. Users) | [FILL IN — document how contractors or visitors authenticate, if applicable] | |

### 6.5 System and Communications Protection (SC)

| Control | Title | Implementation | Evidence |
|---------|-------|----------------|----------|
| SC-8 | Transmission Confidentiality and Integrity | IKEv2 VPN encrypts all remote traffic with AES-256-GCM; TLS used for AD CS web enrollment | `Deploy-VPNClient.ps1`; `WatchGuard-IKEv2-VPN-Guide.md §4.4` |
| SC-8(1) | Transmission Confidentiality — Cryptographic Protection | IKEv2 Phase 1: AES-256-GCM, SHA-256, DH ECP384; Phase 2: AES-256-GCM, SHA-256, PFS ECP384 | `Deploy-VPNClient.ps1 Set-VpnConnectionIPsecConfiguration` |
| SC-12 | Cryptographic Key Establishment and Management | RSA 4096 Root CA key; RSA 2048/4096 Issuing CA key; non-exportable smart card keys generated on-token | `Architecture/Blueprint.md §2` |
| SC-17 | Public Key Infrastructure Certificates | Two-tier PKI with 10-year Root CA and 5-year Issuing CA certificates; SHA-256 signatures | `Download-OfflineCA-Kit.ps1`; `Download-IssuingCA-Kit.ps1` |
| SC-28 | Protection of Information at Rest | CA private keys stored in software KSP (commercial baseline); HSM planned for federal upgrade | `Architecture/Blueprint.md §6.1` |

### 6.6 Configuration Management (CM)

| Control | Title | Implementation | Evidence |
|---------|-------|----------------|----------|
| CM-6 | Configuration Settings | DISA STIG baselines applied via SCAP SCC; GPO enforces smart card and session lock settings | `Compliance-Reports/`; `Group-Policy/` |
| CM-7 | Least Functionality | HTTP CRL server configured with minimal IIS feature set; only port 80 for CRL distribution | `Download-IssuingCA-Kit.ps1 -ConfigureCRLServer` |

---

## 7. Interconnections and External Systems

| External System | Purpose | Interface | Data Exchanged | Authority |
|-----------------|---------|-----------|----------------|-----------|
| Microsoft 365 / Entra ID | Cloud authentication via FIDO2 WebAuthn | HTTPS / FIDO2 | Authentication tokens | Separate Entra ID authorization |
| Internet (public) | CRL/AIA distribution for external clients | HTTP port 80 | CRL files (public, unsigned challenge) | This SSP — HTTP CRL server |
| [FILL IN] | [FILL IN — any other connections] | | | |

---

## 8. Security Assessment Summary

> Complete after Phase 4 STIG scans and Nessus results are available.

| Assessment | Tool | Date | Score / Finding Count |
|-----------|------|------|-----------------------|
| Windows Server 2022 STIG (Before MFA) | SCAP SCC | [FILL IN] | [FILL IN] % compliance |
| Windows Server 2022 STIG (After MFA) | SCAP SCC | [FILL IN] | [FILL IN] % compliance |
| Nessus Essentials (Before hardening) | Nessus | [FILL IN] | [FILL IN] Critical / [FILL IN] High |
| Nessus Essentials (After hardening) | Nessus | [FILL IN] | [FILL IN] Critical / [FILL IN] High |

Detailed findings are in the Security Assessment Report (`Architecture/SAR-Template.md`) and
the Plan of Action & Milestones (`Architecture/POAM-Template.md`).

---

## 9. POA&M Summary

Open findings requiring remediation are tracked in `Architecture/POAM-Template.md`. The AO
accepts residual risk for findings with an accepted risk disposition before the ATO is granted.

| POA&M Item Count | Risk Level | Status |
|-----------------|------------|--------|
| [FILL IN] | Critical | [Open / Remediated / Risk Accepted] |
| [FILL IN] | High | [Open / Remediated / Risk Accepted] |
| [FILL IN] | Medium | [Open / Remediated / Risk Accepted] |

---

## 10. Authorization Decision

| Field | Value |
|-------|-------|
| Authorization Decision | [FILL IN — Authorization to Operate / Denial / Interim ATO] |
| Authorization Date | [FILL IN] |
| Authorization Expiration | [FILL IN — typically 3 years from authorization date] |
| Authorizing Official Signature | [FILL IN] |
| Conditions | [FILL IN — any conditions attached to the ATO, e.g., complete POA&M items by date X] |

---

## 11. Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | [FILL IN] | Glenn Byron | Initial draft — template created |
| 1.0 | [FILL IN] | [FILL IN] | Completed with real scan results — submitted for ATO |

---

*See `ROADMAP.md` for the full program phase plan. See `Architecture/SAR-Template.md` for the
Security Assessment Report and `Architecture/POAM-Template.md` for the Plan of Action & Milestones.*
