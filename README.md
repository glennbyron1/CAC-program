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

The repository is organized so each script and document has exactly one home. Two kits hold everything you run:

- `/Lab-Kit` — **Canonical home for every script you run to build and operate the lab**, organized by where you run it: `01-HyperV-Host/` (create the VMs), `02-OfflineRootCA/` (manual air-gapped Root CA build), `03-DomainController/` (DC, CA, GPO, cert templates, token enrollment, OCSP, audit forwarding, PKI health), `04-Workstation/` (smart-card enforcement, VPN client), `05-Compliance/` (stage SCAP reports). Start at `Lab-Kit/START-HERE.md`. `Reference/` links back to the canonical docs in `/Architecture`.
- `/Tools-Kit` — **Canonical home for the tool-acquisition scripts** that download and stage the free DoD/federal tools (`Get-LabTools.ps1` master downloader plus the three `Download-*-Kit.ps1` scripts). Start at `Tools-Kit/START-HERE.md`.
- `/Architecture` — System design and compliance documents: PKI Blueprint, STIG Hardening Guide, NIST/CISA regulatory alignment, WatchGuard IKEv2 VPN guide, federal compliance upgrade path, and `RMF-Templates/` (SSP, POA&M, SAR, ATO Letter, STIG Deviation Rationale, Annual STIG Re-Assessment SOP, CSET Assessment Guide).
- `/Compliance-Reports` — Staging area for SCAP SCC scan output (Before-MFA / After-MFA) and evidence files.
- `/Portfolio` — Recruiter-facing deliverables: program showcase, sanitized full blueprint, and sample manager brief (`.docx`).
- Root: `Scrub-Repo.ps1` (sanitizer) and `Package-LabKit.ps1` (zips Lab-Kit + a docs snapshot for USB transfer).
- `/security` — Repository security policy (`POLICY.md`), secure contribution guide (`CONTRIBUTING.md`), incident-response runbook (`INCIDENT_RESPONSE.md`), and the pre-commit hook (`scripts/pre-commit`) that blocks keys, certs, CA databases, and VM images before they can be committed. Backed by `.github/workflows/secret-scan.yml`, which re-runs the same checks server-side on every push and pull request.
________________________________________
🛡️ DevSecOps Controls
This repository defends against accidental secret exposure in four layers: (1) `.gitignore` excludes sensitive types; (2) the `security/scripts/pre-commit` hook blocks them locally before commit (install once per clone — see `security/CONTRIBUTING.md`); (3) the `secret-scan.yml` GitHub Action re-checks on the server; and (4) `Scrub-Repo.ps1` replaces real identifiers with placeholders before any push. Policy lives in `security/POLICY.md`; vulnerability reporting is in the root `SECURITY.md`.
________________________________________
🧰 Repository Automation Utilities
All scripts are production-quality PowerShell. Each one handles its own error checking, writes to a log, and is safe to re-run.

**Build-CAC-Lab.ps1** — Lab domain controller builder (Phase B). Installs the AD Domain Services role and promotes a clean Windows Server VM to a domain controller for a fresh lab forest (default `lab.local`) with integrated DNS, then triggers the required reboot. Includes guardrails that refuse to run on an existing domain controller, supports `-WhatIf`, and writes a transcript log. Pairs with `Build-CA-GPO.ps1`, which runs after the reboot. Addresses NIST SP 800-53 IA-2.

**Stage-Reports.ps1** — SCAP report harvester. Finds the most recent SCAP Compliance Checker output folder, copies the .xml and .html results into the Before-MFA or After-MFA tracking directories, and keeps the folder structure consistent for portfolio review.

**Download-OfflineCA-Kit.ps1** — Builds a self-contained USB transfer kit for the Offline Root CA. Downloads SysInternals, OpenSSL, and PSPKI to a staging folder, generates CAPolicy.inf and the CRL publication scripts, and creates a SHA-256 manifest so you can verify the kit on the air-gapped host.

**Download-IssuingCA-Kit.ps1** — Stages all prerequisites for the domain-joined Enterprise Issuing CA. Installs the AD CS Windows features, downloads PSPKI, and generates an Initialize-IssuingCA.ps1 with the full sub-CA provisioning workflow. Optionally configures IIS for HTTP CRL/AIA publishing.

**Download-FedCompliance-Kit.ps1** — Downloads and organizes all federal compliance tools in one run: DISA STIG Viewer, DISA STIG content packs, SCAP 1.3 benchmarks, Microsoft Security Compliance Toolkit, Nessus Essentials, SysInternals, and OpenSSL. Generates a TOOL-INDEX.md with RMF phase mapping.

**Deploy-VPNClient.ps1** — Deploys the IKEv2 VPN client profile to Windows endpoints. Creates the connection, applies FIPS-compliant IPsec crypto (AES-256-GCM / SHA-256 / ECP384), builds the EAP-TLS XML to force smart card authentication, and validates the config. Optionally runs a live test. Paired with Architecture/WatchGuard-IKEv2-VPN-Guide.md.

**New-TokenEnrollment.ps1** — Smart card enrollment ceremony manager. Enforces NIST AC-5 separation of duties by splitting the process into two distinct, audited phases. The Registration Authority phase documents in-person ID verification and sets a signed authorization flag in Active Directory. The Card Issuer phase reads that flag, hard-blocks the same person from issuing their own card, runs the pre-issuance checklist, and guides the technician through certificate enrollment and PIN setup. Every ceremony step is written to a log file and the Windows Application Event Log (EventID 4200). Addresses NIST SP 800-53 AC-5, IA-2, IA-5.

**Monitor-PKIHealth.ps1** — PKI infrastructure health monitor. Fetches each CRL URL, parses the Next Update timestamp via certutil, and raises CRIT or WARN alerts before the window closes. Also checks OCSP endpoint reachability, Issuing CA certificate expiry, VPN gateway certificate expiry, and enrolled user smart card certificate expiry against configurable thresholds. Outputs a color-coded summary dashboard to the console and optionally sends an alert email. Designed to run as a scheduled task. Addresses NIST SP 800-53 CA-7, SC-17.

**Set-AuditLogForwarding.ps1** — Audit policy and Windows Event Forwarding configurator. Runs in Collector mode (on the SIEM-side server) or Source mode (on each monitored host). Applies Advanced Audit Policy via auditpol for all smart card and Kerberos subcategories, sets the AD CS audit filter to log all certificate operations, and configures WEF subscriptions that pull the complete set of authentication and PKI event IDs (4624, 4625, 4768, 4769, 4776, 4886–4890, 4896, 4898) into the forwarded events channel. Addresses NIST SP 800-53 AU-2, AU-9, AU-12.

**New-CertificateTemplates.ps1** — AD CS certificate template builder. Creates two smart card templates on the Enterprise Issuing CA using the PSPKI module: a standard user logon template (RSA 2048, auto-issue) and a privileged admin logon template (CA Manager approval required, restricted enrollment group). Includes a full nine-step manual fallback guide printed to the console if PSPKI is unavailable. Publishes both templates to the CA after creation. Addresses NIST SP 800-53 SC-17, IA-5.

**Set-OCSPResponder.ps1** — Online Certificate Status Protocol (OCSP) setup script. Installs the Windows Online Responder role, requests an OCSP Response Signing certificate from the Issuing CA, and adds the OCSP URL to the CA's Authority Information Access (AIA) extension so all newly issued certificates carry the endpoint. Provides detailed MMC walkthrough instructions for the revocation configuration step and runs a live endpoint reachability test. Addresses NIST SP 800-53 SC-17, IA-5(2).
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
🎬 Lab Demonstration Walkthrough

> **Coming after Phase 4 lab work.** This section will document the full end-to-end demonstration with screenshots showing the before and after states. Placeholder sections are below — replace each [screenshot] block with actual captures from the lab VMs.

**Step 1 — Baseline (password-only login)**
Walk the reviewer through logging in with a standard domain password. Show that no smart card is required and document the SCAP SCC before-hardening compliance score.

[screenshot: standard domain login prompt — no smart card required]
[screenshot: SCAP SCC before-hardening scan results — compliance score and open findings count]

**Step 2 — Run hardening scripts**
Execute `Build-CAC-Lab.ps1` to build the domain, then `Build-CA-GPO.ps1` to deploy the smart card enforcement GPOs. Show the GPO summary output.

[screenshot: Build-CAC-Lab.ps1 console output — domain promotion complete]
[screenshot: Build-CA-GPO.ps1 console output — GPOs applied]

**Step 3 — Token enrollment ceremony**
Run `New-TokenEnrollment.ps1` in RA mode as the Registration Authority, then switch accounts and run it in Issuer mode as the Card Issuer. Show the separation of duties enforcement (the script blocks the same account from completing both phases).

[screenshot: RA phase — identity verification checklist and AD flag set]
[screenshot: Issuer phase — SOD block if same account attempts to issue]
[screenshot: Issuer phase — certificate enrolled, SmartcardLogonRequired set]

**Step 4 — Smart card-enforced login**
Remove the password and attempt to log in without the card — show the access denial. Then log in with the card inserted. Show the 2-second session lock when the card is pulled.

[screenshot: password login rejected — smart card required]
[screenshot: smart card login prompt with certificate selection]
[screenshot: session lock triggered on card removal]

**Step 5 — VPN with EAP-TLS**
Run `Deploy-VPNClient.ps1` to configure the IKEv2 profile. Connect to the WatchGuard VPN using the smart card certificate. Show the authentication log on the firewall confirming EAP-TLS and the certificate subject.

[screenshot: Deploy-VPNClient.ps1 output — profile created and validated]
[screenshot: VPN connected — certificate auth confirmed, no password prompt]

**Step 6 — After-hardening SCAP SCC scan**
Run the post-hardening SCAP SCC scan and export results. Stage them with `Stage-Reports.ps1`. Show the compliance score improvement.

[screenshot: SCAP SCC after-hardening scan results — improved score and reduced CAT I findings]
[screenshot: Stage-Reports.ps1 output — reports staged to Compliance-Reports/After-MFA/]

**Step 7 — PKI health monitor**
Run `Monitor-PKIHealth.ps1` to confirm all CRLs and certificates are within validity windows. Show the CRIT/WARN/OK status dashboard.

[screenshot: Monitor-PKIHealth.ps1 output — all checks green]
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
