# CAC/PIV Program — Zero Trust Gap Analysis
## What you have vs. what to add to meet Zero Trust requirements

**Author:** Glenn Byron
*Assessment of the CAC/PIV smart-card logon program against Zero Trust requirements. Frameworks: NIST SP 800-207, DoD Zero Trust "User" pillar, CISA ZTMM, EO 14028 / OMB M-22-09, and FIPS 201 / NIST SP 800-63.*

---

## Bottom line up front

This program is an **Advanced-to-Optimal implementation of the *authentication* leg of the Identity pillar** — the hardest part of Zero Trust to do correctly, done the right way: in-person proofing, hardware-bound certificates, password eliminated, an offline root, separation-of-duties enrollment, and revocation checked on every auth. That satisfies the phishing-resistant MFA mandate that EO 14028 and OMB M-22-09 put at the center of federal Zero Trust.

Where the program stops short of *full* Zero Trust is the same place almost every PKI program does: it proves **who you are** extremely well, but Zero Trust also requires controlling **what that proven identity can reach, on what device, and whether that's still true a minute later.**

## 1. What this program already satisfies

| Zero Trust requirement | How the program meets it |
|---|---|
| **Phishing-resistant MFA** (EO 14028 / OMB M-22-09 cornerstone) | Hardware PIV certificate on CAC / YubiKey; password removed entirely — meets the phishing-resistant, AAL3-class bar |
| **Identity proofing before issuance** | In-person verification before any credential is issued (FIPS 201 / IAL-style assurance) |
| **Crown-key protection** | Two-tier PKI with an **offline, air-gapped Root CA** that signs only the Issuing CA, then returns to the safe |
| **Separation of duties in credential issuance** | Two-person enrollment (RA phase + Issuer phase, distinct accounts) — no one can mint their own credential |
| **Credential validation / revocation** | CRL **and** OCSP checked on every authentication event; a revoked card fails immediately |
| **Strict enforcement, no weaker path** | GPO `scforceoption=1` — the domain will not issue a Kerberos ticket without a smart card |
| **Cryptographic trust-chain verification** | DC verifies the full chain (Root → Issuing → user cert) prior to issuing the ticket |
| **Visibility / audit** | Audit policy + Windows Event Forwarding; PKI health monitoring (CRL/OCSP dashboard) |
| **Automation & secure SDLC** | IaC provisioning + CI (PSScriptAnalyzer lint, secret scanning) — repeatable and reviewed |
| **Governance / path to authorization** | NIST SP 800-53 control mapping; RMF SSP / SAR / POA&M; STIG / SCAP / Nessus workflow |

## 2. What to add for full Zero Trust

### A. Authorization after the ticket *(the biggest gap)*
- **Today:** a valid cert yields a Kerberos ticket; access is governed by AD group membership / ACLs — coarse and static.
- **Add:** tiered-admin model, least-privilege AD design, RBAC moving toward ABAC, and a Policy Enforcement Point so access is granted **per resource**, not "you're in, find what you can."

### B. Device pillar
- **Today:** authenticates the *user* superbly; the *device* isn't part of the decision.
- **Add:** machine/device certificates from the Issuing CA; posture/health checks (patch level, disk encryption, EDR) as an access signal — "comply-to-connect."

### C. Continuous / per-session re-evaluation
- **Today:** validation at logon and CRL/OCSP each auth event — but a Kerberos TGT then lives for its full lifetime.
- **Add:** shorter ticket lifetimes and Continuous Access Evaluation–style re-checks so access re-validates during the session, not just at the front door.

### D. Policy decision/enforcement + conditional access
- **Today:** decision logic is static AD/Kerberos (valid cert = ticket).
- **Add:** a Policy Engine combining identity + device posture + context + risk into the decision; conditional access via IdP (Azure/Entra ID with PIV federation) or a ZT access broker.

### E. Non-person / workload identity
- **Today:** user and admin smart-card certificates only.
- **Add:** scoped, short-lived machine/service certificates; mTLS between services; service accounts under management.

### F. Network segmentation + per-application access
- **Today:** cert-based EAP-TLS VPN (a strength — certificate, not password).
- **Add:** microsegmentation; VPN grants **per-application** access rather than full-LAN reach (ZTNA-style).

### G. Visibility → analytics that feed decisions
- **Today:** WEF audit forwarding + PKI health monitoring.
- **Add:** SIEM with behavioral analytics / risk scoring that **feeds the Policy Engine** — so anomalous use can raise the bar or revoke access.

## 3. Two technical nuances worth knowing

1. **Authentication ≠ authorization.** This program is a textbook strong-authentication system; Zero Trust additionally demands fine-grained, dynamic *authorization*. Naming that distinction signals you understand where PKI ends and ZT begins.
2. **Kerberos ticket persistence.** Because the TGT survives until expiry, "revocation on every auth" protects new logons but not an active session. True continuous ZT shortens that window.

## 4. Maturity snapshot (CISA stages)

| Zero Trust function | Where this program sits |
|---|---|
| Identity — authentication | **Advanced / Optimal** ✅ |
| Identity — authorization / least privilege | Traditional / Initial ⬜ |
| Devices | Traditional / Initial ⬜ |
| Networks | Initial ◑ (cert-based VPN; no microsegmentation) |
| Visibility & Analytics | Initial → Advanced ◑ (logging yes; analytics-driven decisions no) |
| Automation & Orchestration | Advanced ◑ (IaC + CI strong; automated response not yet) |
| Governance | **Advanced** ✅ (RMF / 800-53 / STIG / SCAP) |

**In one line:** the program nails *who gets in and how they prove it.* Zero Trust's remaining ask is *what they can reach, on what device, and whether it's still safe a minute later* — addressed by Phase 8.

---

*See `Lab-Kit/Phase-8-Zero-Trust-Extension.md` for the scripted roadmap closing these gaps.*
