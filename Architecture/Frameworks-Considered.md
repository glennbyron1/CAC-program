# Frameworks Considered

**Document ID:** ARCH-ICAM-009
**Author:** Glenn Byron
**Last Updated:** 2026-06-15

---

## Purpose

This document explains why specific security frameworks were chosen for this lab and notes the alternatives that would apply in different deployment contexts. The lab implements DISA STIG against Windows Server 2022 and Windows 11 because the target career path is DoD / federal contractor IT. The same architecture can be deployed against CIS Benchmarks for commercial or non-DoD federal contexts without redesign.

The intent is to demonstrate competence with both major frameworks without running redundant parallel hardening passes. A single framework, deeply implemented, beats two frameworks shallowly implemented.

---

## DISA STIG (chosen for this lab)

**What it is:** Security Technical Implementation Guides published by the Defense Information Systems Agency (DISA). Mandatory configuration baselines for DoD systems.

**Used in:** DoD agencies, defense contractors under CMMC Level 2 or above, federal contractors processing CUI under NIST SP 800-171.

**Why chosen for this lab:**

- Directly relevant to the DoD / federal contractor career target
- Provides specific, prescriptive configuration requirements
- SCAP-scannable via DISA SCAP Compliance Checker (SCC) tooling
- Maps cleanly to NIST 800-53 controls
- Documented evidence (XCCDF + CKL files) is the same artifact federal RMF packages expect

**Lab evidence:** `Compliance-Reports/` — SCAP scans of DC01, WS01, and WO02 against current STIG benchmarks. Before / after hardening deltas captured per host.

---

## CIS Benchmarks (alternative for non-DoD contexts)

**What it is:** Configuration baselines published by the Center for Internet Security (CIS). Community-developed, widely adopted across commercial and non-DoD federal environments.

**Used in:** Commercial enterprises, state and local government, healthcare, financial services, federal agencies without DoD-specific requirements.

**Why not the primary choice for THIS lab:**

- The career target is DoD / federal contractor — DISA STIG is the dominant framework there
- Two parallel hardening passes against the same systems would add complexity without proportionate portfolio value

**Where CIS materials live:**

- Benchmarks and Controls: https://workbench.cisecurity.org/
- CIS Controls v8 → NIST 800-53 official mapping: https://www.cisecurity.org/controls/v8-mapping-to-nist-800-53

**Equivalents:** see `Architecture/RMF-Templates/SSP-Template.md` § 6 for the NIST 800-53 ↔ CIS Controls v8 cross-reference table populated for this lab.

**Deployment in a CIS-aligned environment:** the same Lab-Kit scripts, RMF templates, and architecture documents apply. Substitute CIS Benchmark scanning (e.g. CIS-CAT Pro) for SCAP SCC, swap CIS Controls v8 numbers into the SSP control mapping, and the artifact set remains valid. The Phase 8 Zero Trust extension is framework-agnostic and applies in either context.

---

## Other frameworks worth knowing about

| Framework | Used in | Relevance to this lab |
|---|---|---|
| **NIST SP 800-53 Rev 5** | Federal civilian agencies, FISMA-required systems | Primary control catalog used in `Architecture/RMF-Templates/SSP-Template.md`. DISA STIG and CIS Benchmarks both map back to it. |
| **NIST SP 800-171** | Non-federal organizations handling CUI; DoD contractors at CMMC Level 1+ | Subset of 800-53 controls. The Lab-Kit architecture supports either with the same RMF artifacts. |
| **CMMC** | DoD contractors | Layered on top of NIST 800-171 + extra practices. The lab's STIG evidence + RMF artifacts are CMMC-relevant. |
| **ISO 27001 / 27002** | International commercial | Not directly addressed. Equivalent control mapping possible via NIST 800-53. |
| **HITRUST** | Healthcare (HIPAA-aligned) | Not addressed. Could map via NIST 800-53. |
| **PCI DSS** | Payment card industry | Not addressed. Identity controls in this lab partially apply. |
| **CJIS Security Policy** | Law enforcement handling Criminal Justice Information | Identity / authentication controls in this lab (PKINIT, smart card MFA, replay resistance) directly apply. Map via NIST 800-53 IA family. |

---

## Multi-framework signal (and why this approach matters)

The portfolio shows competence with both DISA STIG (deeply implemented) and CIS Benchmarks (mapped and referenced) without doing redundant parallel work. This is intentional discipline:

- **Career story for DoD path:** "I deployed STIG against real systems, captured before / after hardening evidence, and produced the RMF artifact set federal contractors expect."
- **Career story for commercial / state / local path:** "Same architecture, swap the benchmark scanner and the control-mapping column, and the RMF artifact set still applies. I can speak both languages."

The single-framework-deep-plus-second-framework-mapped pattern is generally stronger than running two shallow hardening passes — it shows intentional scope discipline rather than completeness-chasing.

---

## Related documents

- `Architecture/RMF-Templates/SSP-Template.md` — primary NIST 800-53 control mapping + CIS Controls v8 cross-reference (§ 6.7)
- `Architecture/STIG-Hardening-Guide.md` — DISA STIG hardening procedures
- `Architecture/Regulatory-Alignment.md` — broader regulatory-framework alignment notes
- `Architecture/Federal-Compliance-Upgrade.md` — upgrade path from commercial PIV-style to federal PIV
- `Compliance-Reports/` — SCAP scan evidence
