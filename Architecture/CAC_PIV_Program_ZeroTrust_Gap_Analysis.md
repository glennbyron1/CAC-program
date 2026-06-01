# CAC/PIV Program — Zero Trust Gap Analysis
## What you have vs. what to add to meet Zero Trust requirements

*Assessment of the CAC/PIV smart-card logon program (two-tier PKI lab) against Zero Trust requirements. Frameworks: NIST SP 800-207, DoD Zero Trust "User" pillar, CISA ZTMM, EO 14028 / OMB M-22-09 (phishing-resistant MFA), and FIPS 201 / NIST SP 800-63 for identity assurance.*

---

## Bottom line up front

Your program is an **Advanced-to-Optimal implementation of the *authentication* leg of the Identity pillar** — arguably the hardest part of Zero Trust to do correctly, and you've done it the right way: in-person proofing, hardware-bound certificates, password eliminated, an offline root, separation-of-duties enrollment, and revocation checked on every auth. That alone satisfies the phishing-resistant MFA mandate that EO 14028 and OMB M-22-09 put at the center of federal Zero Trust.

Where the program stops short of *full* Zero Trust is the same place almost every PKI program does: it proves **who you are** extremely well, but Zero Trust also requires controlling **what that proven identity can reach, on what device, and whether that's still true a minute later.** Those are the authorization, device, and continuous-evaluation layers — and notably, the "valid credential → broad access" pattern is the very gap you identified on the operational side. So the work ahead is consistent with what you already understand.

## 1. What your program already satisfies

| Zero Trust requirement | How your program meets it |
|---|---|
| **Phishing-resistant MFA** (the EO 14028 / OMB M-22-09 cornerstone) | Hardware PIV certificate on CAC / YubiKey; password removed entirely — meets the phishing-resistant, AAL3-class bar. |
| **Identity proofing before issuance** | In-person verification before any credential is issued (FIPS 201 / IAL-style assurance). |
| **Crown-key protection** | Two-tier PKI with an **offline, air-gapped Root CA** that signs only the Issuing CA, then returns to the safe — exactly the "air-gap the irreplaceable" principle from your own reference set. |
| **Separation of duties in credential issuance** | Two-person enrollment (RA phase + Issuer phase, distinct accounts) — no one can mint their own credential. |
| **Credential validation / revocation** | CRL **and** OCSP checked on every authentication event; a revoked card fails immediately. |
| **Strict enforcement, no weaker path** | GPO `scforceoption=1` — the domain will not issue a Kerberos ticket without a smart card. |
| **Cryptographic trust-chain verification before access** | DC verifies the full chain (Root → Issuing → user cert) prior to issuing the ticket; no valid chain, no access. |
| **Visibility / audit** | Audit policy + Windows Event Forwarding; PKI health monitoring (CRL/OCSP dashboard). |
| **Automation & secure SDLC** | IaC provisioning of the whole environment + CI (PSScriptAnalyzer lint, secret scanning) — repeatable and reviewed. |
| **Governance / path to authorization** | NIST SP 800-53 control mapping; RMF SSP / SAR / POA&M; STIG / SCAP / Nessus workflow. |

That column fully covers the **authentication function of the Identity pillar**, and meaningfully touches **Visibility, Automation, and Governance.** Few real programs get this far.

## 2. What to add to meet *full* Zero Trust

Zero Trust = strong identity **plus** least-privilege authorization, device trust, and continuous, policy-driven decisions. Here's the additive work, in priority order.

### A. Authorization after the ticket *(the biggest gap, and the same one as operational environments)*
- **Today:** a valid cert yields a Kerberos ticket, and from there access is governed by AD group membership / ACLs — coarse and static. Authentication is strong; authorization is broad.
- **Add:** a tiered-admin model and least-privilege AD design; RBAC moving toward ABAC; and, for sensitive resources, a policy enforcement point so access is granted **per resource**, not "you're in, find what you can." This converts "authenticated → network" into "authenticated → only what this identity needs."

### B. Device pillar
- **Today:** the program authenticates the *user* superbly; the *device* isn't part of the decision.
- **Add:** issue **machine/device certificates** from your Issuing CA so logon and the EAP-TLS VPN also prove a *known, managed* device; add posture/health checks (patch level, disk encryption, EDR) as an access signal — "comply-to-connect." Zero Trust wants user **and** device verified together.

### C. Continuous / per-session re-evaluation
- **Today:** validation happens at logon (and CRL/OCSP each auth event) — but a Kerberos TGT then lives for its full lifetime. Revoking a card stops the *next* authentication; it does not kill an already-issued ticket.
- **Add:** shorter ticket lifetimes and Continuous Access Evaluation–style re-checks so access re-validates during the session and on risk changes, not just at the front door. This is the move from "verify once" to "always verify."

### D. Policy decision/enforcement + conditional access
- **Today:** the decision logic is static AD/Kerberos (valid cert = ticket).
- **Add:** a Policy Engine that combines identity **+ device posture + context (location, time) + risk** into the decision — e.g., federating the PIV credential into an IdP with conditional access (your Azure/Entra background fits here) or a Zero Trust access broker acting as PDP/PEP. This is the NIST 800-207 PE/PA/PEP model layered on top of the credential you already issue.

### E. Non-person / workload identity *(if you want to claim the Applications & Workloads pillar)*
- **Today:** user and admin smart-card certificates.
- **Add:** extend the Issuing CA to issue **scoped, short-lived machine/service certificates** and enable **mTLS** between services (SPIFFE-style). Bring service accounts under management. Optional for a logon lab, but it's what completes "identity for everything, not just people."

### F. Network segmentation + per-application access
- **Today:** cert-based EAP-TLS VPN (a genuine strength — certificate, not password).
- **Add:** microsegment the environment and make the VPN grant **per-application** access rather than full-LAN reach (ZTNA-style), with default-deny east-west. Pairs directly with item A.

### G. Visibility → analytics that feed decisions
- **Today:** WEF audit forwarding + PKI health monitoring (a strong foundation).
- **Add:** a SIEM with behavioral analytics / risk scoring that **feeds the Policy Engine** in item D — so anomalous use can raise the bar or revoke access, closing the loop.

## 3. Two technical nuances worth being able to speak to

These show depth in an interview and are real, not nitpicks:

1. **Authentication ≠ authorization.** Your program is a textbook strong-authentication system; Zero Trust additionally demands fine-grained, dynamic *authorization*. Naming that distinction explicitly signals you understand where PKI ends and ZT begins.
2. **Kerberos ticket persistence.** Because the TGT survives until expiry, "revocation on every auth" protects new logons but not an active session. True continuous ZT shortens that window. Being able to explain this is a credibility marker.

## 4. How to position the program (lab & interviews)

Frame it accurately and it becomes a *stronger* story, not a weaker one:

> "I built a phishing-resistant, passwordless PIV authentication system — two-tier PKI with an offline root, separation-of-duties enrollment, OCSP/CRL validation, and smart-card-enforced logon, wrapped in RMF artifacts and IaC/CI. That's the Identity pillar's authentication leg at an advanced level. The roadmap to full Zero Trust from here is authorization (least privilege + a policy enforcement point), device trust (machine certs + posture), and continuous, conditional access — which I've scoped as the next phase."

Consider adding a **"Phase 8 — Zero Trust Extension"** to the lab that implements items A–D in your existing automated style. It would turn a great identity lab into a demonstrable end-to-end ZTA reference — exactly the kind of thing that stands out for a NAVAIR-side role.

## 5. Maturity snapshot (CISA stages, by function)

| Zero Trust function | Where your program sits |
|---|---|
| Identity — authentication | **Advanced / Optimal** ✅ |
| Identity — authorization / least privilege | Traditional / Initial ⬜ |
| Devices | Traditional / Initial ⬜ |
| Networks | Initial ◑ (cert-based VPN; no microsegmentation) |
| Visibility & Analytics | Initial → Advanced ◑ (logging yes; analytics-driven decisions no) |
| Automation & Orchestration | Advanced ◑ (IaC + CI strong; automated response not yet) |
| Governance | **Advanced** ✅ (RMF / 800-53 / STIG / SCAP) |

**In one line:** you've nailed *who gets in and how they prove it.* Zero Trust's remaining ask is *what they can reach, on what device, and whether it's still safe a minute later* — authorization, device trust, and continuous, policy-driven access.
