# CISA CSET Assessment Guide — OT Cybersecurity Maturity Documentation

Document ID: ARCH-ICAM-012
Author: Glenn Byron
Framework: CISA CSET | MD Senate Bill 871 §9-2705(b)(3) | NIST CSF 2.0 | ICS/OT Security

> **What this is for:** Maryland Senate Bill 871 §9-2705(b)(3) requires community water systems
> and sewerage system providers to assess their operational technology (OT) cybersecurity maturity.
> The CISA Cybersecurity Evaluation Tool (CSET) is the free, federally recommended tool for this
> assessment. This guide covers running the assessment and exporting the results for compliance
> documentation.
>
> **CSET is a separate tool** from the DISA STIG scanning done in Phase 4. STIG scanning covers
> IT systems. CSET covers the OT/ICS environment (PLCs, SCADA, HMIs, field devices). Both are
> required under Maryland SB 871.

---

## 1. What CSET Evaluates

CSET assesses cybersecurity posture for industrial control systems and operational technology
using multiple recognized frameworks. For MD SB 871 compliance, the relevant frameworks are:

| Framework | Use Case |
|-----------|---------|
| NIST CSF 2.0 | General cybersecurity maturity — required reference in SB 871 §9-2702 |
| CISA ICS-CERT | Industrial control system specific controls |
| AWIA 2018 | America's Water Infrastructure Act baseline (water/wastewater sector) |
| NERC CIP (reference) | Energy sector controls — useful reference even if not directly applicable |

CSET asks a series of questions about your environment organized by framework category
(Identify, Protect, Detect, Respond, Recover for CSF). At the end, it generates a maturity
score and gap analysis.

---

## 2. Installing CSET

CSET is downloaded as part of the federal compliance kit:

```powershell
.\Automation-Scripts\Download-FedCompliance-Kit.ps1 -OutputPath "C:\FedCompliance-Tools"
```

The installer lands in `FedCompliance-Tools\08-CISA-CSET\`.

### Manual Download

If the automated download did not retrieve CSET, it is available from GitHub:
- Repository: `https://github.com/cisagov/cset`
- Releases: `https://github.com/cisagov/cset/releases`
- Download the latest `.exe` installer

### Installation Steps

1. Run the CSET installer as Administrator
2. Accept the default installation path (`C:\Program Files\CSET\`)
3. CSET runs as a local web application — it will open in your browser at `http://localhost:xxxx`
4. No internet connection is required after installation
5. All assessment data stays local on your machine

---

## 3. Creating Your Assessment

### 3.1 Start a New Assessment

1. Launch CSET (desktop shortcut or Start menu)
2. Click **Create New Assessment**
3. Enter assessment details:
   - **Assessment Name:** MD SB 871 OT Maturity Assessment — [Year]
   - **Facility Name:** [Your organization name — scrub before committing]
   - **City/State:** [Your location]
   - **Assessment Date:** [Today's date]
4. Click **Next**

### 3.2 Select Standards

On the standards selection screen, choose the frameworks relevant to your environment:

For MD SB 871 compliance, select at minimum:
- **NIST Cybersecurity Framework 2.0** (required by SB 871 §9-2702)
- **AWIA — America's Water Infrastructure Act** (if you are a community water system)
- **ICS-CERT** (recommended for OT-specific controls)

Click **Next** after selecting.

### 3.3 Define Your System

CSET asks you to describe the OT/ICS components in your environment. Answer based on
your actual operational technology setup:

| Question Area | Example Answers for Water/Wastewater |
|--------------|--------------------------------------|
| Sector | Water and Wastewater |
| Asset categories | SCADA systems, PLCs, HMIs, remote telemetry units (RTUs) |
| Network topology | IT/OT segmented? Describe how |
| Remote access | VPN to SCADA network? Jump server? |
| Connections to business network | Data historian? ERP integration? |
| Internet-facing components | Remote monitoring? Cloud telemetry? |

### 3.4 Complete the Question Set

CSET presents a series of yes/no/partially questions organized by framework category.
Answer each question honestly based on your current state, not your desired future state.

**Tips:**
- "Partially" is a valid answer — use it when you have something in place but it's not
  fully implemented or documented
- The CAC/PIV program directly answers several questions in the Identity and Access
  Management categories (see Section 4 below)
- Take notes on any "No" answers — these become the basis for your gap remediation plan
- CSET allows you to add comments to each question — use them to reference your evidence

**Time estimate:** Plan 2–4 hours for a thorough first assessment. Subsequent annual
assessments will be faster since you can import prior year results as a baseline.

---

## 4. CAC/PIV Program Answers

The CAC/PIV ICAM program directly addresses the following CSET question areas. Use
these as your answers and reference the relevant repository artifacts as evidence.

| CSET Question Category | CSET Control | CAC/PIV Answer | Evidence |
|----------------------|-------------|----------------|---------|
| Identity management | MFA for privileged accounts | Yes | `Build-CA-GPO.ps1`; `Group-Policy/Enforce-SmartCard.ps1` |
| Identity management | MFA for remote access | Yes | `WatchGuard-IKEv2-VPN-Guide.md` (on-prem); `Deploy-VPNClient.ps1`; `Architecture/Roadmap/CAC_PIV_Phase9_Azure_VPN_ConditionalAccess.md` (cloud/federal target) |
| Identity management | Phishing-resistant MFA | Yes | Hardware PKI certificates (not OTP or SMS) |
| Identity management | Credential lifecycle management | Yes | `New-TokenEnrollment.ps1` — RA/Issuer separation |
| Identity management | Privileged account separation | Yes | Separate YubiKey slot for admin accounts |
| Account management | Session lock on inactivity | Yes | GPO: `ScRemoveOption = 1` (2-second lock on removal) |
| Account management | Account provisioning process | Yes | `New-TokenEnrollment.ps1` — documented SOP |
| Access control | Least privilege | Yes | RA/Card Issuer role separation (NIST AC-5) |
| Certificate management | Internal PKI | Yes | Two-tier CA in `Architecture/Blueprint.md` |
| Certificate management | Certificate revocation | Yes | HTTP CRL endpoints; OCSP via `Set-OCSPResponder.ps1` |
| Monitoring | Security event logging | Yes | `Set-AuditLogForwarding.ps1` — Event IDs 4768/4769/4776 |
| Monitoring | Continuous monitoring | Partially | Monthly PKI health checks via `Monitor-PKIHealth.ps1` |
| Vulnerability management | STIG compliance | Yes | SCAP SCC scans in `Compliance-Reports/` |
| Incident response | Revocation capability | Yes | AD CS revocation; CRL published immediately on compromise |

---

## 5. Exporting Results

After completing all question sets:

1. Click **Reports** in the top navigation
2. Select the report types to export:
   - **Executive Summary** — one-page maturity score by framework category
   - **Detail Report** — every question with your answer and the gap analysis
   - **Site Summary** — charts and graphs suitable for management presentation
3. Export each in **PDF** format
4. Save to your evidence folder

### Naming Convention for Exports

```
CSET-Executive-Summary-YYYY.pdf
CSET-Detail-Report-YYYY.pdf
CSET-Site-Summary-YYYY.pdf
```

These files should be stored alongside your STIG scan results but do **not** commit them
to the public GitHub repository — they may contain sensitive OT system descriptions.
Store them in a secured local folder or organization document management system.

### Saving the Assessment File

CSET saves your assessment in a `.csetw` file (or similar format depending on version).
Save this file so next year's assessment can import it as a baseline:

```
CSET-Assessment-YYYY.csetw
```

---

## 6. Interpreting Your Score

CSET produces a maturity level score for each framework category. For MD SB 871 reporting:

| Score Range | Maturity Level | Meaning |
|------------|---------------|---------|
| 0–25% | Level 1 — Basic | Limited controls; significant gaps |
| 26–50% | Level 2 — Developing | Some controls; incomplete or undocumented |
| 51–75% | Level 3 — Proficient | Most controls implemented and documented |
| 76–90% | Level 4 — Advanced | Comprehensive controls with monitoring |
| 91–100% | Level 5 — Exemplary | Fully implemented with continuous improvement |

**Minimum expectation for MD SB 871 compliance:** Reaching Level 3 (Proficient) in the
Identity, Access Control, and Monitoring categories is the practical baseline. The CAC/PIV
program positions these categories at Level 4–5.

---

## 7. Documenting for MD SB 871 Compliance

Maryland SB 871 §9-2705(b)(3) requires covered utilities to assess and document OT
cybersecurity maturity. Your CSET exports satisfy this requirement when:

1. The assessment is completed annually (or after significant system changes)
2. The results are documented and available for review if requested by the Maryland Department of the Environment (MDE) or Maryland Department of Information Technology (DoIT)
3. A remediation plan exists for any identified gaps (the POA&M in `Architecture/POAM-Template.md` serves this purpose for IT systems; create a parallel OT gap remediation plan for CSET findings)

### Annual Compliance Summary Statement

After completing the assessment, complete this block for your compliance records:

| Field | Value |
|-------|-------|
| Assessment Date | [FILL IN] |
| Tool | CISA CSET v[FILL IN version] |
| Standards Assessed | NIST CSF 2.0, AWIA 2018, ICS-CERT |
| Lead Assessor | Glenn Byron |
| Overall Maturity Level | [FILL IN] |
| Identity Category Score | [FILL IN]% |
| Access Control Category Score | [FILL IN]% |
| Detect/Monitor Category Score | [FILL IN]% |
| Significant Gaps Identified | [FILL IN — or "None"] |
| Remediation Plan Reference | `Architecture/POAM-Template.md` |
| Next Assessment Due | [FILL IN — ~12 months] |

---

## 8. Annual Assessment Schedule

| Year | Planned Date | Completed | Score Summary | Notes |
|------|-------------|-----------|---------------|-------|
| 2026 | [FILL IN] | [ ] | | Initial assessment |
| 2027 | [FILL IN] | [ ] | | |
| 2028 | [FILL IN] | [ ] | | |

---

*Related: `Architecture/Regulatory-Alignment.md` (CISA ZTMM and NIST CSF mapping),
`Architecture/POAM-Template.md` (gap remediation tracking), `ROADMAP.md Phase 5`.*
