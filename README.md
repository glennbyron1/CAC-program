🛡️ Enterprise ICAM: "CAC-Style" Identity & Access Deployment Blueprint

**Author:** Glenn Byron | **GitHub:** [@glennbyron1](https://github.com/glennbyron1)

An end-to-end, script-driven blueprint for deploying hardware-backed, certificate-based MFA across an enterprise environment. This project takes the model used by the U.S. DoD Common Access Card (CAC) and Federal PIV programs and adapts it for organizations running Active Directory, AD CS, WatchGuard IKEv2 VPN, and Microsoft 365 (Entra ID).

________________________________________
🏗️ Architecture Overview
The blueprint enforces a zero-password interactive logon topology by mapping cryptographic hardware tokens to verified organizational identities. Trust is anchored by an internally managed, two-tier Public Key Infrastructure (PKI).
                 

                 +-----------------------------------+
                 |      Microsoft 365 / Entra ID     |
                 |    (Conditional Access + FIDO2)   |
                 +-----------------+-----------------+

                                   |
                           FIDO2 Web AuthN
                                   |
                 +-----------------v-----------------+

                 |          USER + TOKEN             |
                 |     (Smart Card / YubiKey)        |
                 +---+-------------+-------------+---+

                     |             |             |
         Smart Card  |   IKEv2 VPN |             | Platform SSO /
         Kerberos    |   EAP-TLS   |             | MDM Configuration

                     |             |             |
     +---------------v--+   +------v-------+   +-v------------+

     | Windows Endpoint |   |  WatchGuard  |   | macOS Client |
     | (Lock on Removal)|   |   Firewall   |   | (IT Track)   |
     +-------+----------+   +------+-------+   +--------------+

             |                     |
             +-----------+---------+
                         |
              | Local Active Directory      |
              | (DCs + HTTP CRL Validation) |
              +-----------+-----------------+
________________________________________
🛠️ Repository Structure
- `/Architecture` — System architecture documents, regulatory alignment mapping (CISA ZTMM, NIST CSF 2.0, CISA CPGs, MD SB 871), STIG hardening runbook, federal tools setup guide, and WatchGuard IKEv2 EAP-TLS VPN configuration guide.
- `/Automation-Scripts` — PowerShell scripts for lab staging, GPO deployment, VPN client setup, Offline Root CA kit, Issuing CA kit, and federal compliance tool staging.
- `/Group-Policy` — GPO templates for smart card enforcement and lock-on-removal behavior.
- `/Templates` — .INF configuration baselines for the Offline Root CA and Issuing CA.
________________________________________
🧰 Repository Automation Utilities
All scripts are production-quality PowerShell. Each one handles its own error checking, writes to a log, and is safe to re-run.

**Build-CAC-Lab.ps1** — Lab domain controller builder (Phase B). Installs the AD Domain Services role and promotes a clean Windows Server VM to a domain controller for a fresh lab forest (default `lab.local`) with integrated DNS, then triggers the required reboot. Includes guardrails that refuse to run on an existing domain controller, supports `-WhatIf`, and writes a transcript log. Pairs with `Build-CA-GPO.ps1`, which runs after the reboot. Addresses NIST SP 800-53 IA-2.

**Stage-Reports.ps1** — SCAP report harvester. Finds the most recent SCAP Compliance Checker output folder, copies the .xml and .html results into the Before-MFA or After-MFA tracking directories, and keeps the folder structure consistent for portfolio review.

**Download-OfflineCA-Kit.ps1** — Builds a self-contained USB transfer kit for the Offline Root CA. Downloads SysInternals, OpenSSL, and PSPKI to a staging folder, generates CAPolicy.inf and the CRL publication scripts, and creates a SHA-256 manifest so you can verify the kit on the air-gapped host.

**Download-IssuingCA-Kit.ps1** — Stages all prerequisites for the domain-joined Enterprise Issuing CA. Installs the AD CS Windows features, downloads PSPKI, and generates an Initialize-IssuingCA.ps1 with the full sub-CA provisioning workflow. Optionally configures IIS for HTTP CRL/AIA publishing.

**Download-FedCompliance-Kit.ps1** — Downloads and organizes all federal compliance tools in one run: DISA STIG Viewer, DISA STIG content packs, SCAP 1.3 benchmarks, Microsoft Security Compliance Toolkit, Nessus Essentials, SysInternals, and OpenSSL. Generates a TOOL-INDEX.md with RMF phase mapping.

**Deploy-VPNClient.ps1** — Deploys the IKEv2 VPN client profile to Windows endpoints. Creates the connection, applies FIPS-compliant IPsec crypto (AES-256-GCM / SHA-256 / ECP384), builds the EAP-TLS XML to force smart card authentication, and validates the config. Optionally runs a live test. Paired with Architecture/WatchGuard-IKEv2-VPN-Guide.md.
________________________________________
🚀 Commercial Enterprise Baseline vs. Federal PIV Target State
This blueprint covers two tiers. The commercial baseline is what's implemented here — solid protection for most organizations. The federal upgrade path documents the specific changes needed to meet full FISMA/FedRAMP requirements.

**1. Token Procurement**
- Commercial (As Implemented): CardLogix GIDS smart cards for staff, HIRSCH uTrust FIDO2 NFC+ keys for management. Standard commercial procurement.
- Federal Upgrade: All tokens, readers, and middleware must come from the GSA FIPS 201 Approved Product List (APL).

**2. CA Key Storage**
- Commercial (As Implemented): Root CA and Issuing CA private keys stored in a software Key Storage Provider (KSP) on the host OS.
- Federal Upgrade: Software key storage is not allowed. Keys must be generated inside and permanently bound to a FIPS 140-3 Level 3 Hardware Security Module (HSM).

**3. Trust Anchor**
- Commercial (As Implemented): Two-tier internal PKI rooted in the organization's Active Directory NTAuth store.
- Federal Upgrade: The Issuing CA must cross-certify to the Federal Common Policy Certificate Authority (FBCA) for cross-agency trust under NIST SP 800-217.

**4. Derived Credential Issuance**
- Commercial (As Implemented): Secondary tokens (YubiKeys) provisioned at an admin issuance desk after in-person Registration Authority photo-ID verification.
- Federal Upgrade: Per NIST SP 800-157, derived credentials must be issued via automated kiosk using the primary PIV card as the cryptographic voucher.
________________________________________
📊 NIST SP 800-53 Control Mapping
This architecture directly addresses and satisfies the following security controls within the NIST SP 800-53 Rev. 5 framework:

| Control ID  | Control Name                       | Deployment Implementation                                                                                              |
|---|------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| IA-2  | Identification and Authentication (Organizational Users)  | Enforces hardware-backed cryptographic MFA via smart card / FIDO2 across all endpoints, VPN tunnels, and cloud ecosystems (pp. 6, 13). |
| IA-2(11)  | Workstation Access Using Hardware Tokens | Leverages Windows native endpoint smart-card configuration to block standard password logins globally (pp. 6, 42).     |
|  AC-11 |       Session Lock                             | Deploys a Group Policy Object forcing an immediate interactive session lock within 2 seconds of physical token removal. |
|  AC-5 |      Separation of Duties                              | Implements strict gatekeeping separating the Registration Authority (Identity Verification) from the Card Issuer (Technical Provisioning) (p. 8). |
| AC-17 | Remote Access | WatchGuard IKEv2 Mobile VPN enforces certificate-based EAP-TLS authentication for all remote access sessions; no password-based tunnels permitted. |
| SC-8 | Transmission Confidentiality and Integrity | IKEv2 tunnel encrypts all VPN traffic with AES-256-GCM; Phase 1 and Phase 2 crypto policies configured to FIPS-approved algorithms only. |
________________________________________
🔒 Security Statement & Sanitization
This repository is maintained completely separate from any live production environment.
- No production keys, active certificates, or real credentials are in Git history.
- All committed code uses generic placeholders — lab.local and agency.gov — in place of real organizational identifiers. The .gitignore blocks private keys, certificates, VM artifacts, and IDE state.
- **Scrub-Repo.ps1** performs a find-and-replace pass using a local (gitignored) patterns file before every push. Run it with `-WhatIf` first to preview what would be replaced.
- Pre-push order: (1) copy `.scrub-patterns.example.json` to `.scrub-patterns.local.json` and fill in real identifiers, (2) run `.\Scrub-Repo.ps1` to sanitize, (3) review with `git diff`, then commit and push.
________________________________________

🏷️ Topics / Tags For GitHub topic tagging on this repository: identity-management, pki, smart-card, fido2, active-directory, certificate-authority, nist-800-53, fips-201, zero-trust, icam, ad-cs, watchguard, entra-id, powershell, nist-csf, cisa-cpg, regulatory-compliance.
________________________________________
📜 License
Released under the MIT License. See LICENSE for full terms.
________________________________________
👤 Maintainer
**Glenn Byron** — [@glennbyron1](https://github.com/glennbyron1). See `AUTHORS.md` for contribution guidance, `SECURITY.md` to report a vulnerability, and `MAINTAINER-SETUP.md` for first-time machine setup (noreply email, SSH signing, scrub patterns).
