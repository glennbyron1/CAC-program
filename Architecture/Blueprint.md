🗺️ System Architecture Blueprint: Smart Card Identity Infrastructure
Document ID: ARCH-ICAM-001
Author: Glenn Byron
Target System: Enterprise Cryptographic Multi-Factor Authentication (MFA) Baseline
Framework Alignment: NIST SP 800-53 Rev. 5, FIPS 201-3, DISA STIG, NIST CSF 2.0, CISA ZTMM, MD SB 871

> For full regulatory mapping (CISA Zero-Trust Maturity Model, NIST CSF 2.0,
> CISA Cross-Sector CPGs, and incident reporting), see
> [`Regulatory-Alignment.md`](Regulatory-Alignment.md).
________________________________________
1. Executive Summary & Intent
This document defines the production engineering baseline for migrating from password-based legacy authentication to a zero-password, hardware-backed Identity, Credential, and Access Management (ICAM) system.
The baseline architecture satisfies commercial high-security requirements using enterprise tools (Active Directory, AD CS, IKEv2 VPN gateways — WatchGuard Firebox for on-prem or Azure VPN Gateway for cloud/federal alignment, Entra ID) while creating a clear engineering roadmap to achieve full Federal Information Security Management Act (FISMA) and FedRAMP authorization tiers.
________________________________________
2. Public Key Infrastructure (PKI) Topology
To ensure security boundaries are maintained, a two-tier Public Key Infrastructure topology is mandated. Software-isolated environments are utilized for testing, with hardware integration planned for the federal target state.

```
                +-----------------------------------+
                |        Offline Root CA            |
                |   (Standalone / Non-Domain)       |
                |   RSA 4096 · 10-year validity     |
                |   No network adapter              |
                +-----------------+-----------------+
                                  |
                   Sneakernet Root Certificate
                   (Issuing CA cert renewal only)
                                  |
                                  v
                +-----------------------------------+
                |       Enterprise Sub-CA           |
                |   (Domain-Joined / Issuing)       |
                |   RSA 2048-4096 · Online AD CS    |
                |   HTTP CRL + OCSP + AIA           |
                +-----------------+-----------------+
                                  |
        +-------------------------+-------------------------+
        |                                                   |
        v                                                   v
+-------------------+                            +----------------------+
|  Workstation Auth |                            |   VPN / Network      |
|  Certificates     |                            |   Certificates       |
|  (SmartCardLogon) |                            |   (EAP-TLS / IKEv2)  |
+-------------------+                            +----------------------+
```
2.1 Tier 1: Standalone Offline Root CA
•	Role: Root of Trust anchor.
•	Operating Status: Permanently Offline. The host virtual machine is powered down and disconnected from virtual switches except during scheduled Issuing CA certificate renewals (every 5–10 years).
•	Key Specifications: RSA 4096-bit private key utilizing the Microsoft Software Key Storage Provider for the commercial baseline.
•	CRL Validity Interval: 6 months.
2.2 Tier 2: Enterprise Subordinate / Issuing CA
•	Role: Active enrollment engine handling automated registration, issuance, and revocation checking.
•	Operating Status: Domain-joined, running Active Directory Certificate Services (AD CS).
•	Key Specifications: RSA 2048-bit or 4096-bit private key.
•	Publishing Protocols: Configured for high-availability HTTP Certificate Revocation List (CRL) endpoints.
________________________________________
3. Real-Time Revocation & High-Availability Architecture
A major vulnerability in smart card programs is authentication failure due to network isolation. If a domain controller cannot reach a CRL endpoint, smart card logons fail across the entire enterprise.
3.1 HTTP vs. LDAP Distribution Points
This architecture strictly mandates HTTP-based CRL Distribution Points (CDPs) over traditional Active Directory LDAP endpoints.
•	The WAN Failure Mode: Remote sites, DMZs, or clients authenticating across an IKEv2 VPN tunnel (WatchGuard Firebox on-prem or Azure VPN Gateway in cloud) often face strict port restrictions or temporary routing dropouts that block LDAP (TCP/UDP 389).
•	The Resolution: HTTP (TCP 80) CRL files are cached naturally by local client machines and edge proxy clusters. This minimizes network traffic overhead and ensures authentication survives cross-site WAN brownouts.
3.2 Authority Information Access (AIA) Configuration
Workstations must quickly resolve the parent trust chain without polling the internet. AIA fields in all issued certificates must point exclusively to high-availability local HTTP endpoints hosting the subordinate CA root certificate (.crt).
________________________________________
4. Hardware Token Lifecycle Management
[Identity Verification] --> [Registration Authority Verification] --> [Token Issuance]

         |                                                       |
         v                                                       v
  Present 2 Forms                                         Enforce Mandatory
    of Valid ID                                             User PIN Change
4.1 Separation of Duties (NIST AC-5)
The token enrollment cycle strictly separates administrative roles:
1.	The Registration Authority (RA): Verifies the legal physical identity of the employee via two forms of valid identification and checks the authorization flag in the Active Directory identity store.
2.	The Card Issuer: Executes the technical provisioning script, issues the smart card profile, and initializes the hardware token. An administrator cannot act as both the RA and the Issuer for the same transaction.
4.2 Security Key & Smart Card Profile Matrix
•	Standard Enterprise Profile: Physical GIDS smart card mapping User Principal Names (UPN) to standard interactive desktops.
•	Privileged Administrative Profile: Dual-interface cryptographic security token (e.g., YubiKey 5 Series). Enforces a hard separation between a user's standard account and their administrative directory account by requiring separate hardware slots for each identity tier.
________________________________________
5. Physical Access Control Integration

CAC/PIV smart cards are dual-use credentials — the same hardware token used for
Windows logon and VPN authentication can simultaneously serve as a physical
access control (PACS) credential for door readers, turnstiles, and secure
facility entry.

Maryland Senate Bill 871 §9-2701(E)(2) explicitly classifies "physical access
control mechanisms" as Operational Technology (OT). This classification means
that organizations subject to the bill's cybersecurity requirements must treat
PACS infrastructure with the same rigor as IT systems.

**Logical + Physical Convergence Model**

| Credential Use | Protocol | Infrastructure |
|---|---|---|
| Windows interactive logon | Kerberos PKINIT (smart card TLS) | Active Directory + AD CS |
| Remote VPN access | EAP-TLS | WatchGuard IKEv2 (on-prem) or Azure VPN Gateway (cloud / federal target) |
| Cloud / SaaS (Entra ID) | FIDO2 WebAuthn | Microsoft Entra ID |
| Physical door/facility access | PACS card reader (125 kHz / 13.56 MHz contactless) | Physical access control system |

**Implementation Notes**
- Standard PIV/CAC cards carry a CHUID (Cardholder Unique Identifier) used by
  compliant PACS readers. No separate credential or separate enrollment is
  required.
- FIPS 201-3 specifies PACS authentication assurance levels (LAK-1 through
  LAK-4). Federal deployments require LAK-3 (biometric + PIN + card) for
  high-security areas.
- Commercial deployments can start with LAK-1 (card-only) and upgrade to
  LAK-2 (card + PIN) without replacing cards.
- PACS readers must be sourced from the GSA FIPS 201 APL for federal
  compliance (see Federal Compliance Gap Analysis §6.2 below).

---

6. Federal Compliance Gap Analysis
To scale this blueprint from a local commercial enterprise to a certified federal environment, four architectural changes must be addressed:
6.1 Cryptographic Storage (FIPS 140-3 Level 3)
•	Commercial Infrastructure: CA private keys are stored in a software-based Key Storage Provider (KSP), which relies on the host OS for protection.
•	Federal Requirement: CA private keys must be generated inside and permanently bound to a FIPS 140-3 Level 3 Hardware Security Module (HSM). The keys never leave the physical boundary of the HSM.
6.2 Supply Chain Procurement (GSA APL)
•	Commercial Infrastructure: Open procurement — cost-effective commercial smart cards, readers, and tokens are acceptable.
•	Federal Requirement: All hardware must be sourced from the GSA FIPS 201 Approved Product List (APL), which ensures certified PIV-compliant cards, middleware drivers, and readers are used.
6.3 Root Trust Federation (NIST SP 800-217)
•	Commercial Infrastructure: Trust is contained within the internal Active Directory forest NTAuth store.
•	Federal Requirement: The internal Issuing CA must cross-certify or chain to the Federal Common Policy Certificate Authority (FBCA) to enable cross-agency identity trust under NIST SP 800-217.
________________________________________

