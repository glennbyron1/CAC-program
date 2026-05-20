🛡️ Enterprise ICAM: "CAC-Style" Identity & Access Deployment Blueprint
An end-to-end, script-driven implementation plan for deploying hardware-backed, certificate-based multi-factor authentication (MFA). This project adapts the rigorous operating model used by the U.S. DoD Common Access Card (CAC) and Federal PIV programs into a production-ready template for enterprise infrastructure running Active Directory, Active Directory Certificate Services (AD CS), WatchGuard IKEv2 VPN, and Microsoft 365 (Entra ID).
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
               Local Active Directory
               (DCs + HTTP CRL Validation)
________________________________________
🛠️ Repository Structure
•	/Architecture: Full architectural specifications, multi-site WAN failure mode matrices, and disaster recovery runbooks.
•	/Automation-Scripts: Production-ready PowerShell deployment tools (Build-CAC-Lab.ps1, Build-CA-GPO.ps1) for environment staging.
•	/Group-Policy: Backed-up GPO templates for smart-card behavior enforcement and lock-on-removal behavior.
•	/Templates: Core .INF configuration baselines for standalone root and subordinate enterprise certificate authorities.
________________________________________
🚀 Commercial Enterprise Baseline vs. Federal PIV Target State
This project outlines two distinct infrastructure baselines. The Commercial Baseline provides robust protection for a standard organization, while the Federal Upgrade Path highlights the specific changes required to meet strict federal compliance standards.
1. Token Procurement & Selection
•	Commercial Baseline (As Implemented): Utilizes cost-effective, dual-tier commercial endpoints consisting of CardLogix GIDS smart cards for standard staff and HIRSCH uTrust FIDO2 NFC+ keys for management layers (pp. 9, 21).
•	Federal Upgrade Path: All authentication tokens, security keys, and workstation readers must be explicitly procured from the official GSA FIPS 201 Approved Product List (APL) to fulfill FIPS 201-3 hardware requirements.
2. Public Key Infrastructure (PKI) Storage
•	Commercial Baseline (As Implemented): Private keys for the Root and Subordinate Certificate Authorities are isolated via a software-based Key Storage Provider (KSP) (p. 19).
•	Federal Upgrade Path: Software-based key storage is prohibited. CA private keys must be generated inside and bound to a physical, FIPS 140-2/3 Level 3 validated Hardware Security Module (HSM).
3. Trust Anchor & Cross-Certification
•	Commercial Baseline (As Implemented): Relies on a self-contained, corporate-owned two-tier PKI tree where trust is established locally via Active Directory's NTAuth store (pp. 19, 26).
•	Federal Upgrade Path: The infrastructure must cross-certify or chain back to the Federal Common Policy Certificate Authority (FBCA) to enable cross-agency federation and trust inter-operability under NIST SP 800-217 guidelines.
4. Derived Credential Issuance
•	Commercial Baseline (As Implemented): Secondary tokens (YubiKeys) are cryptographically built at an administrator issuance desk following an in-person, Registration Authority photo-ID verification event (pp. 11, 35).
•	Federal Upgrade Path: Aligned with NIST SP 800-157, mobile or secondary tokens must be issued via an automated self-service kiosk where the user's primary, physical federal PIV card serves as the automated cryptographic voucher for the derived token.
________________________________________
📊 NIST SP 800-53 Control Mapping
This architecture directly addresses and satisfies the following security controls within the NIST SP 800-53 Rev. 5 framework:
Control ID	Control Name	Deployment Implementation
IA-2	Identification and Authentication (Organizational Users)	Enforces hardware-backed cryptographic MFA via smart card / FIDO2 across all endpoints, VPN tunnels, and cloud ecosystems (pp. 6, 13).
IA-2(11)	Workstation Access Using Hardware Tokens	Leverages Windows native endpoint smart-card configuration to block standard password logins globally (pp. 6, 42).
AC-11	Session Lock	Deploys a Group Policy Object forcing an immediate interactive session lock within 2 seconds of physical token removal (pp. 33, 36, 42).
AC-5	Separation of Duties	Implements strict gatekeeping separating the Registration Authority (Identity Verification) from the Card Issuer (Technical Provisioning) (p. 8).
________________________________________
🔒 Security Statement & Sanitization
This repository is maintained completely out-of-band from any live corporate environment.
•	No production keys, active certificates, or authentic secrets are stored in Git history.
•	All committed code uses generic placeholders following the format lab.local / agency.gov; the .gitignore excludes private keys, certificates, virtual-machine artifacts, and IDE workspace state.
•	A repository sanitization tool, Scrub-Repo.ps1, performs a find-and-replace pass against an external (gitignored) patterns file before every push. Run with -WhatIf to preview replacements.
•	Run order: (1) Copy .scrub-patterns.example.json to .scrub-patterns.local.json and add your real identifiers; (2) Run .\Scrub-Repo.ps1 -WhatIf to preview; (3) Run .\Scrub-Repo.ps1 to apply; (4) git diff, git add ., git commit, git push.
________________________________________
🏷️ Topics / Tags
For GitHub topic tagging on this repository: identity-management, pki, smart-card, fido2, active-directory, certificate-authority, nist-800-53, fips-201, zero-trust, icam, ad-cs, watchguard, entra-id, powershell.
________________________________________
📜 License
Released under the MIT License. See LICENSE for full terms.
