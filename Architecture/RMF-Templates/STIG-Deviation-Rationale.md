# STIG Deviation Rationale

Document ID: ARCH-ICAM-010
Author: Glenn Byron
Framework: NIST SP 800-53 CA-6 | DISA RMF | DoD Instruction 8510.01

> **Purpose:** Documents the justification for every STIG finding that is being accepted
> as a risk rather than remediated. The Authorizing Official reviews this document before
> granting the ATO. Each deviation must have a clear operational reason, a risk assessment,
> and compensating controls where possible.
>
> **Deviation types:**
> - **Technical Finding** — The STIG requirement conflicts with an operational need (e.g., a
>   required service would break if the STIG setting is applied).
> - **Operational Requirement** — The requirement cannot be met due to a business process,
>   budget, or timeline constraint.
> - **Risk Accepted** — The finding is acknowledged, the risk is low enough to accept without
>   compensating controls.

---

## System Information

| Field | Value |
|-------|-------|
| System Name | Enterprise CAC/PIV ICAM System |
| Document ID | ARCH-ICAM-010 |
| Prepared By | Glenn Byron |
| Date Prepared | [FILL IN] |
| Last Updated | [FILL IN] |

---

## Pre-Populated Deviations

The following deviations are pre-documented based on known characteristics of this architecture.
Additional deviations identified during Phase 4 scanning should be added below.

---

### DEV-001 — CA Private Keys in Software KSP (Not HSM)

| Field | Value |
|-------|-------|
| STIG Reference | PKI/AD CS STIG — requirement for cryptographic module hardware protection |
| STIG Rule ID | [FILL IN from PKI STIG — e.g., PKCS-01-000010] |
| Risk Level | Moderate |
| Deviation Type | Operational Requirement |

**Finding:** The PKI/AD CS STIG requires CA private keys to be protected by a FIPS 140-2/3
Level 3 validated Hardware Security Module (HSM). This system uses the Microsoft Software Key
Storage Provider (KSP), which stores keys in software on the host operating system.

**Operational Justification:** This is a commercial enterprise lab deployment. HSMs (e.g.,
Thales Luna, nCipher) carry significant cost ($15,000–$50,000+ per unit) and require
specialized configuration and personnel. Procurement is documented as part of the Federal
Upgrade Path (see `Architecture/Blueprint.md §6.1`).

**Risk Assessment:** Software KSP provides the following protections: keys are protected by the
Windows DPAPI under the local SYSTEM account, access requires elevated administrative privileges,
and the Offline Root CA host is permanently air-gapped. The primary risk is that a kernel-level
compromise of the CA host could expose keys — this is mitigated by the controls below.

**Compensating Controls:**
- Offline Root CA is air-gapped and powered off except during scheduled signing ceremonies
- Two-person signing ceremonies (RA/Issuer separation — NIST AC-5) prevent unauthorized use
- CA server has DISA STIG hardening applied per Phase 4 scan results
- AD CS audit logging enabled (`certutil -setreg CA\AuditFilter 127`)
- Monthly PKI health monitoring (`Monitor-PKIHealth.ps1`) detects anomalies

**AO Disposition:** [ ] Accepted | [ ] Requires Remediation | [ ] Accepted with Conditions

**AO Notes:** [FILL IN]

---

### DEV-002 — Smart Card Logon: OCSP Responder Not Deployed

| Field | Value |
|-------|-------|
| STIG Reference | PKI/AD CS STIG — OCSP responder configuration requirement |
| STIG Rule ID | [FILL IN] |
| Risk Level | Low |
| Deviation Type | Operational Requirement |

**Finding:** Some STIG profiles require an OCSP (Online Certificate Status Protocol) responder
for real-time revocation checking, in addition to or instead of CRL-only distribution.

**Operational Justification:** This deployment uses CRL-based revocation only. OCSP requires an
additional server role and certificate configuration. CRL caching provides adequate revocation
coverage for the current scale and operational environment.

**Risk Assessment:** CRL-only revocation introduces a window between certificate revocation and
client CRL cache refresh (typically 1–8 hours for delta CRLs). This is acceptable because:
revocation events in this environment are expected to be rare (physical token loss or employee
departure); delta CRLs are published frequently (see Issuing CA configuration); and the
VPN gateway performs CRL validation on every connection (WatchGuard Firebox on-prem; Azure VPN Gateway with native CRL/OCSP support for the cloud/federal target).

**Compensating Controls:**
- HTTP-based CRL distribution with short delta CRL lifetime
- Immediate forced GPO refresh and smart card lock on revocation event
- OCSP deployment documented as Phase 6 deliverable (`ROADMAP.md`)

**AO Disposition:** [ ] Accepted | [ ] Requires Remediation | [ ] Accepted with Conditions

**AO Notes:** [FILL IN]

---

### DEV-003 — [Add Additional Deviations from Phase 4 Scan Results]

| Field | Value |
|-------|-------|
| STIG Reference | [FILL IN — STIG title and rule ID] |
| Risk Level | [CAT I / CAT II / CAT III] |
| Deviation Type | [Technical Finding / Operational Requirement / Risk Accepted] |

**Finding:** [FILL IN — describe what the STIG requires and what the current state is]

**Operational Justification:** [FILL IN — explain why the requirement cannot be met]

**Risk Assessment:** [FILL IN — what is the risk if this finding is not remediated?]

**Compensating Controls:**
- [FILL IN — any controls that reduce the risk]

**AO Disposition:** [ ] Accepted | [ ] Requires Remediation | [ ] Accepted with Conditions

**AO Notes:** [FILL IN]

---

## How to Add a Deviation

When Phase 4 SCAP SCC or STIG Viewer review identifies a finding that you are accepting
rather than remediating, document it here using the template above. Each entry needs:

1. The STIG title and Rule ID from your .ckl file or XCCDF results
2. Whether it's a CAT I, II, or III finding (CAT I deviations need strong justification)
3. A clear reason why you can't or won't fix it
4. At least one compensating control
5. AO sign-off

Any finding accepted here must also appear in the POA&M (`POAM-Template.md`)
Risk Acceptance Register.

---

## Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | [FILL IN] | Glenn Byron | Initial template — pre-populated with architecture-specific deviations |
| 1.0 | [FILL IN] | [FILL IN] | Completed with Phase 4 findings |

---

*Related: `POAM-Template.md` (Risk Acceptance Register), `SAR-Template.md`
(assessment findings), `SSP-Template.md` (system controls).*
