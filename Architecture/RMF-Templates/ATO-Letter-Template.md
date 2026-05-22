# Authorization to Operate (ATO) — Letter Template

Document ID: ARCH-ICAM-009
Author: Glenn Byron
Framework: NIST SP 800-37 Rev. 2 RMF Authorize | NIST SP 800-53 CA-6

> **Instructions:** This template is completed and signed by the Authorizing Official (AO)
> after reviewing the System Security Plan, Security Assessment Report, and POA&M. Replace
> all [FILL IN] fields with real values before submission. The AO signature (wet or digital)
> is what formally grants the Authorization to Operate.

---

[ORGANIZATION LETTERHEAD]

---

**MEMORANDUM**

**TO:** [FILL IN — System Owner Name, Title]

**FROM:** [FILL IN — Authorizing Official Name, Title]

**DATE:** [FILL IN]

**SUBJECT:** Authorization to Operate — Enterprise CAC/PIV Identity and Access Management System (ICAM-01)

---

## Authorization Decision

After reviewing the security documentation package for the Enterprise CAC/PIV Identity and
Access Management (ICAM) System, including the System Security Plan (ARCH-ICAM-006), Security
Assessment Report (ARCH-ICAM-008), and Plan of Action & Milestones (ARCH-ICAM-007), I have
determined that the residual risk to organizational operations, assets, and individuals is
**[FILL IN: Acceptable / Not Acceptable]**.

Based on this determination, I am granting an **Authorization to Operate (ATO)** for the
Enterprise CAC/PIV ICAM System, subject to the conditions listed below.

---

## System Details

| Field | Value |
|-------|-------|
| System Name | Enterprise CAC/PIV Identity & Access Management (ICAM) System |
| System Identifier | ICAM-01 |
| System Owner | [FILL IN] |
| ISSO | [FILL IN] |
| FIPS 199 Categorization | HIGH (C: High / I: High / A: Moderate) |
| Assessment Date | [FILL IN] |

---

## Authorization Terms

**Authorization Period:** This ATO is valid from [FILL IN date] through [FILL IN date —
typically 3 years from authorization date].

**Authorization Conditions:** This authorization is granted with the following conditions:

1. All CAT I (Critical) findings identified in the Security Assessment Report must be remediated
   or have a documented risk acceptance within [FILL IN — e.g., 30 days] of this authorization.

2. The POA&M (`Architecture/POAM-Template.md`) must be updated with remediation status within
   [FILL IN — e.g., 60 days] of this authorization and reviewed quarterly thereafter.

3. Monthly PKI health monitoring must be maintained per `Automation-Scripts/Monitor-PKIHealth.ps1`.

4. Annual STIG re-assessment must be completed and results submitted to the ISSO before the
   ATO expiration date.

5. Any significant configuration change to the PKI, Active Directory, or VPN infrastructure
   must be reviewed by the ISSO before implementation.

6. [FILL IN — any additional conditions specific to your environment]

---

## Residual Risk Acceptance

The following findings were identified during assessment and are accepted as residual risk
for the duration of this authorization:

| Finding | Risk Level | Rationale for Acceptance |
|---------|-----------|--------------------------|
| CA private keys stored in software KSP (not HSM) | Moderate | Acceptable at commercial baseline; HSM migration documented in Federal Upgrade Path (Blueprint.md §6.1) |
| [FILL IN — any additional accepted findings] | | |

---

## Continuous Monitoring Requirements

During the authorization period, the following continuous monitoring activities are required:

| Activity | Frequency | Responsible Party |
|---------|-----------|------------------|
| PKI health check (CRL, OCSP, cert expiry) | Monthly | [FILL IN] |
| SCAP SCC STIG delta scan | Monthly | [FILL IN] |
| POA&M review and update | Quarterly | ISSO |
| Smart card audit log review (Event IDs 4768, 4769, 4776) | Monthly | [FILL IN] |
| Annual STIG full re-assessment | Annual (before ATO expiration) | [FILL IN] |

---

## Authorizing Official Signature

By signing below, I acknowledge that I have reviewed the complete security documentation
package and accept the residual risk associated with operating this system.

&nbsp;

_______________________________________________

[FILL IN — Authorizing Official Name]
[FILL IN — Title]
[FILL IN — Organization]
Date: ___________________________

---

*This document is part of the ICAM program ATO package. Related documents:
`Architecture/SSP-Template.md`, `Architecture/SAR-Template.md`, `Architecture/POAM-Template.md`.*
