# Federal Compliance Upgrade Path

**Author:** Glenn Byron
**Framework:** FIPS 201-3 · NIST SP 800-53 Rev. 5 · NIST SP 800-157 · NIST SP 800-217 · CISA ZTMM · DISA RMF

This document is the landing page for taking the **commercial CAC-style baseline** in this
repository and evolving it into a **federal-grade** identity program (FISMA / FedRAMP /
DoD RMF). The commercial baseline — internal two-tier PKI, smart card + FIDO2, certificate-based
VPN, lock-on-removal — already satisfies most enterprise security requirements. The federal
target state adds four hardware/trust constraints and a formal assessment regimen on top.

It deliberately does **not** repeat the detail that already lives elsewhere in the repo. Instead
it frames the upgrade and points to the deep-dive documents:

| Topic | Where the detail lives |
| :--- | :--- |
| Architecture + the four-gap analysis | [`Blueprint.md`](./Blueprint.md) §5 |
| Regulatory mapping (ZTMM, NIST CSF 2.0, CPGs, SB 871, incident reporting) | [`Regulatory-Alignment.md`](./Regulatory-Alignment.md) |
| Federal tool setup (SCAP, STIG Viewer, SCT, Nessus, CSET) | [`FedGov-Tools-Setup-Guide.md`](./FedGov-Tools-Setup-Guide.md) |
| STIG hardening + ACAS scanning runbook | [`STIG-Hardening-Guide.md`](./STIG-Hardening-Guide.md) |
| Before/after compliance evidence | [`../Compliance-Reports/`](../Compliance-Reports/) |

---

## Commercial Baseline vs. Federal Target State

| # | Area | Commercial Baseline (as implemented) | Federal Upgrade |
| :-- | :--- | :--- | :--- |
| 1 | **CA key storage** | Root + Issuing CA private keys in a software Key Storage Provider (KSP) | Keys generated in and bound to a **FIPS 140-3 Level 3 HSM** (e.g., Thales Luna, YubiHSM 2). Software KSP prohibited. |
| 2 | **Token & reader procurement** | CardLogix GIDS cards + HIRSCH uTrust FIDO2 NFC+, commercial off-the-shelf | All tokens, readers, and middleware sourced from the **GSA FIPS 201 Approved Products List (APL)**. |
| 3 | **Trust anchor** | Self-contained two-tier PKI, trusted locally via AD NTAuth | Issuing CA **cross-certifies to the Federal Common Policy CA (FBCA)** for cross-agency trust, per **NIST SP 800-217**. |
| 4 | **Derived credential issuance** | Secondary tokens issued at an admin desk after in-person RA photo-ID verification | Per **NIST SP 800-157**, derived credentials issued via automated kiosk using the primary PIV card as the cryptographic voucher. |

The four gaps are analyzed in depth in [`Blueprint.md`](./Blueprint.md) §5.

---

## The Four Technical Gaps (Summary)

### 1. Hardware-Enforced Cryptography (FIPS 140-3 Level 3)
The commercial baseline stores CA private keys with the Microsoft Software KSP — adequate for
enterprise, prohibited for federal. The federal requirement is that CA keys never leave the
physical boundary of a validated HSM. **Upgrade action:** change the `-CryptoProviderName`
parameter at CA install time to the HSM vendor's KSP string, and operate the CA against the HSM.

### 2. Supply-Chain Procurement (GSA APL)
Federal agencies cannot use arbitrary commercial smart cards. Cards, readers, and middleware must
appear on the active GSA FIPS 201 APL. **Upgrade action:** re-select the procurement SKUs against
the APL before purchase; the rest of the program (PKI, GPO, VPN) is unchanged.

### 3. Federated Trust (FBCA / NIST SP 800-217)
The commercial baseline's trust is local to one AD forest. Federal interoperability requires the
Issuing CA to chain to the Federal Common Policy CA so a credential from one agency is trusted at
another. **Upgrade action:** cross-certify the Issuing CA to the FBCA and adopt the federal
certificate policy OIDs.

### 4. Derived PIV Issuance (NIST SP 800-157)
In the commercial baseline a secondary token (e.g., a YubiKey for a manager) is issued after an RA
verifies the person in front of them. Federal derived-credential issuance instead uses the user's
**existing physical PIV card** as the automated cryptographic voucher at a kiosk. **Upgrade
action:** add a derived-credential kiosk flow where the primary PIV anchors the secondary token.

---

## Assessment & Testing Regimen

Federal compliance is proven, not asserted. The testing track in this repo lets you generate the
before/after evidence trail an RMF assessor expects, using free DoD/federal tools:

1. **CISA CSET self-assessment** — run first to find gaps cheaply. See
   [`FedGov-Tools-Setup-Guide.md`](./FedGov-Tools-Setup-Guide.md) §5.
2. **SCAP Compliance Checker (STIG config scan)** — baseline → harden → rescan. See
   [`STIG-Hardening-Guide.md`](./STIG-Hardening-Guide.md).
3. **DISA STIG Viewer** — review and document findings, export the CKL checklist. See
   [`FedGov-Tools-Setup-Guide.md`](./FedGov-Tools-Setup-Guide.md) §2.
4. **ACAS / Nessus authenticated vulnerability scan** — the vulnerability half of RMF. See
   [`STIG-Hardening-Guide.md`](./STIG-Hardening-Guide.md) §6.
5. **Stage the evidence** — `Stage-Reports.ps1` files the reports into
   [`../Compliance-Reports/`](../Compliance-Reports/) Before-MFA / After-MFA tiers.

---

## Suggested Upgrade Roadmap

| Phase | Action | Depends on |
| :-- | :--- | :--- |
| F0 | Run CISA CSET; record the baseline gap list | nothing |
| F1 | Stand up SCAP + STIG Viewer; capture the Before-MFA scan | F0 |
| F2 | Harden the lab (GPOs + MFA), rescan, capture After-MFA | F1 |
| F3 | Add ACAS/Nessus authenticated scanning | F2 |
| F4 | Procure HSM; migrate CA keys off the software KSP | budget |
| F5 | Re-procure tokens/readers against the GSA APL | budget |
| F6 | Cross-certify the Issuing CA to the FBCA (NIST SP 800-217) | F4 |
| F7 | Stand up the derived-PIV kiosk flow (NIST SP 800-157) | F5 |

Phases F0–F3 are free and can be done in the lab today; F4–F7 require budget and a federal
sponsorship context, and are the genuine "federal" steps beyond a commercial enterprise.

---

*This is an educational reference. It documents publicly available standards and free federal
tools used in an isolated lab; it contains no organizational data. Released under the MIT License —
see the repository [`LICENSE`](../LICENSE).*
