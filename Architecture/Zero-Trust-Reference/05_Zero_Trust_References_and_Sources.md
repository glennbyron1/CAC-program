# Zero Trust: References & Authoritative Sources

*Companion to Papers 1–4 — federal, DoD, and State of Maryland sources*

These are the authoritative documents behind the Zero Trust series. They are grouped by issuing authority. Federal and Maryland government publications are public-domain U.S./state government works. Where a precise identifier exists (SP number, chapter number, memo number), it is given so the citation can be verified directly.

---

## A. Foundational federal standards (NIST)

1. **NIST SP 800-207, *Zero Trust Architecture*** (National Institute of Standards and Technology, August 2020).
   The foundational definition of Zero Trust. Establishes the seven tenets and the logical architecture (Policy Engine, Policy Administrator, Policy Enforcement Point) used throughout Papers 1–2. *csrc.nist.gov/pubs/sp/800/207/final*

2. **NIST SP 800-53, Rev. 5, *Security and Privacy Controls for Information Systems and Organizations*** (September 2020).
   The control catalog that Zero Trust capabilities are mapped to under the federal Risk Management Framework (RMF). Cited as the baseline for Maryland's 2026 policy suite.

3. **NIST Cybersecurity Framework (CSF) 2.0** (February 2024).
   The risk-management framework Maryland's modernized policy suite is aligned to.

4. **NIST SP 1800-35, *Implementing a Zero Trust Architecture*** (NIST National Cybersecurity Center of Excellence).
   Practical, vendor-neutral build guides demonstrating reference ZT implementations — useful supplement to the checklist in Paper 3.

## B. Department of Defense

5. **DoD Zero Trust Strategy** (DoD Chief Information Officer, October 2022).
   The department's commitment to a ZT framework with seven pillars: User, Device, Applications & Workloads, Data, Network & Environment, Automation & Orchestration, and Visibility & Analytics. *dodcio.defense.gov*

6. **DoD Zero Trust Reference Architecture, v2.0** (DISA / NSA, July 2022).
   The technical reference architecture underpinning the strategy; grounded in NIST SP 800-207.

7. **DoD Zero Trust Capability Execution Roadmap (COA 1)** (DoD CIO, 2022).
   Breaks the seven pillars into **152 activities**: **91 "Target Level"** activities required department-wide by the end of **FY2027** (September 30, 2027) and **61 "Advanced Level"** activities targeted by FY2032.

8. **Introduction to DoD Zero Trust — Student Guide (CS125)** (Center for Development of Security Excellence, CDSE, 2024).
   Training material that maps the NIST seven tenets to the DoD pillars. Freely available and a strong study aid for someone entering DoD-side IT. *cdse.edu*

## C. CISA (Cybersecurity and Infrastructure Security Agency)

9. **CISA Zero Trust Maturity Model, v2.0** (April 2023).
   Five pillars — Identity, Devices, Networks, Applications & Workloads, Data — plus three cross-cutting capabilities (Visibility & Analytics, Automation & Orchestration, Governance), each assessed across four maturity stages: Traditional → Initial → Advanced → Optimal. *cisa.gov/zero-trust-maturity-model*

## D. Executive / policy mandates

10. **Executive Order 14028, *Improving the Nation's Cybersecurity*** (May 12, 2021).
    Directed federal agencies to advance toward Zero Trust architecture; the policy catalyst for the federal ZT push.

11. **OMB Memorandum M-22-09, *Moving the U.S. Government Toward Zero Trust Cybersecurity Principles*** (Office of Management and Budget, January 26, 2022).
    Set specific federal Zero Trust objectives; CISA's ZTMM v2.0 is explicitly aligned to it.

## E. State of Maryland

12. **Maryland SB 871 / HB 1062 (2025 Regular Session) — *Department of the Environment – Community Water and Sewerage Systems – Cybersecurity Planning and Assessments.*** The Senate bill, **SB 871**, was the enacted vehicle: **approved by the Governor May 13, 2025 as Chapter 495**, **effective October 1, 2025.** **HB 1062** is its cross-filed House companion (same text).
    The "new bill." It requires community water and sewerage systems to adopt a **zero-trust cybersecurity approach** for on-premises and cloud services, conduct maturity assessments, and report incidents, and it assigns coordinating roles to the Department of the Environment, the Department of Information Technology, and the Maryland Department of Emergency Management. Notably for Pax River–area work, it codifies into *state law* the same "no implicit trust; access must be continually evaluated" principle the DoD applies to its own systems. *mgaleg.maryland.gov — bill HB1062 / SB871, 2025RS.*

13. **Maryland Cybersecurity and Privacy Policy Suite** (Maryland Department of Information Technology, Office of Security Management; announced February 24, 2026).
    A modernized, 31-module policy suite that shifts the state executive branch from "trust but verify" to a **zero-trust framework**, with 22 Cabinet agencies required to adopt within 18 months. Aligned to **NIST CSF 2.0** and **NIST SP 800-53 Rev. 5**. (CISO: James Saunders.) *doit.maryland.gov.* Not a statute, but the operational companion to the legislation above and evidence of statewide direction.

14. **Maryland Cybersecurity Council — Biennial Activities Report** (July 1, 2025; published via UMGC).
    Documents the Council's involvement in shaping Maryland cybersecurity legislation, including zero-trust implementation language. *umgc.edu.*

---

## How these map to the series

- **Papers 1–2 (model + deep dive):** NIST SP 800-207 (#1) for the architecture and tenets; the DoD Strategy and Reference Architecture (#5–6) for the seven pillars; CISA ZTMM (#9) for the maturity stages.
- **Papers 3–4 (checklist + guidance):** DoD Capability Execution Roadmap (#7) and NIST SP 1800-35 (#4) for concrete activities; SP 800-53 Rev. 5 (#2) for control mapping.
- **Governance / "why it's mandatory":** EO 14028 (#10), OMB M-22-09 (#11) at the federal level; Maryland Ch. 495 (#12) and the state policy suite (#13) at the state level.

## A note on verifying citations
Bill status, chapter numbers, and effective dates were confirmed against the Maryland General Assembly's legislation tracker for the 2025 Regular Session. Federal document identifiers (SP numbers, EO/memo numbers, publication dates) are stable; the landing pages listed are the official issuing-agency domains. Always cite the primary document rather than a secondary summary when submitting formal work.
