# Zero Trust Architecture: Organizational Hierarchy and the Core Model

*Paper 1 of 4 — Foundations*
**Author:** Glenn Byron

---

## 1. The shift away from the perimeter

Traditional network security was built like a castle: a hard outer wall (the firewall) with a trusted interior. Once a user, workstation, or server was *inside* the perimeter — on the corporate LAN, behind the VPN — it was largely trusted to talk to other internal systems. This is **implicit trust**, and it is exactly what attackers exploit. A single phished credential, a compromised laptop, or a misconfigured server lets an adversary move *laterally* across the soft interior, because everything inside already trusts everything else inside.

Zero Trust (ZT) discards that model. Its governing assumption is that the network is **already breached**, and that no actor — human or machine, internal or external — should be trusted by default. The foundational standard is **NIST Special Publication 800-207, *Zero Trust Architecture* (2020)**, which underpins both the DoD Zero Trust Strategy (2022) and CISA's Zero Trust Maturity Model (v2.0, 2023).

The principle is usually compressed to four words: **never trust, always verify.**

## 2. Reframing "hierarchy": there is no trusted interior

It is natural to picture an organization as a hierarchy of trust — employees sit on workstations, workstations talk to servers, servers talk to other servers, and trust flows down the chain. **Zero Trust deliberately flattens that hierarchy.** In a ZT model there is no privileged "inside." Instead, *every* actor is treated as an untrusted **subject** that must prove itself on *every* request to *every* **resource**.

So the useful hierarchy in Zero Trust is not "who is inside vs. outside." It is the **layered structure of how a single access decision gets made**:

```
        SUBJECT  (employee, workstation, server, service account, workload)
           │
           │  request to access a resource
           ▼
   POLICY ENFORCEMENT POINT (PEP)  ← the gate in front of every resource
           │
           │  "Should I allow this connection?"
           ▼
   POLICY DECISION POINT (PDP)      ← the brain: Policy Engine + Policy Administrator
           │  evaluates identity, device health, context, policy, risk
           │
           ▼  allow / deny / step-up
        RESOURCE (data, application, server, API, service)
```

Every arrow in your old mental hierarchy — employee→workstation, workstation→server, **server→server** — becomes a connection that must pass through this same verify-then-grant pipeline. There are no exceptions for "internal" traffic.

## 3. The entities: subjects and resources

Zero Trust collapses everything in the enterprise into two roles. Anything can be a **subject** (the thing requesting) and anything can be a **resource** (the thing being requested). The same actor is often both.

| Entity | As a subject, it must… | As a resource, it must be protected by… |
|---|---|---|
| **Employees / users** | Authenticate with strong MFA, prove they are who they claim, and be continuously evaluated for risk | N/A (users initiate access) |
| **Workstations / endpoints** | Prove device identity and report health (patch level, encryption, EDR running) before access is granted | Endpoint protection, posture checks |
| **Servers** | Authenticate to the systems they reach out to — a server is *not* trusted just because it is on the network | A PEP/gateway in front of it that authenticates every inbound connection |
| **Services / APIs / workloads** | Present a cryptographic **workload identity** (e.g., a certificate) on every call | Mutual authentication so callers are verified |
| **Service accounts / NPEs** (non-person entities) | Be issued scoped, short-lived credentials and monitored like users | Tight least-privilege scoping |
| **Data** | — | Classification, encryption, and access tied to policy at the object level |

The critical case people miss is **server-to-server (east–west) traffic.** In the old model, two servers on the same subnet trusted each other implicitly. In Zero Trust, **Server A must authenticate and be authorized to talk to Server B every time**, typically using mutual TLS (mTLS) and a machine identity — exactly as if it were an outside party. This is what shuts down lateral movement.

## 4. How one access request actually flows

1. **A subject requests a resource** — e.g., an engineer's laptop tries to open a program-data application, or a microservice calls another service's API.
2. **The PEP intercepts the request.** Nothing connects directly; the enforcement point sits in front of the resource.
3. **The PEP asks the PDP for a decision.** The Policy Engine evaluates a *bundle of signals*, not just a password: verified identity, device health/posture, location and network, time, sensitivity of the resource, and behavioral risk score.
4. **A decision is issued** — allow, deny, or "step up" (require additional verification such as re-authentication).
5. **If allowed, access is granted for that session only**, scoped to the minimum needed (least privilege). It is not a standing, reusable trust relationship.
6. **The session is continuously monitored.** If posture or behavior changes mid-session (the device drops its EDR agent, the user starts doing something anomalous), access can be revoked in real time.

Two important architectural ideas fall out of this:

- **Control plane vs. data plane.** The decision-making machinery (PEP/PDP, identity, policy) is the *control plane*. The actual subject-to-resource connection is the *data plane*. Compromising one resource does not hand the attacker the policy brain.
- **Per-session, per-request authorization.** Trust is never permanent. Yesterday's approval, or even the approval from five minutes ago, does not guarantee the next request succeeds.

## 5. The seven NIST tenets (the rules of the game)

NIST SP 800-207 defines seven tenets that any true Zero Trust implementation should satisfy:

1. All data sources and computing services are considered **resources**.
2. **All communication is secured** regardless of network location (no "trusted" subnet).
3. Access to individual resources is granted **per session**.
4. Access is determined by **dynamic policy** — identity, device state, and other behavioral/environmental attributes.
5. The enterprise **monitors and measures the integrity and security posture** of all owned and associated assets.
6. All resource authentication and authorization are **dynamic and strictly enforced before access**.
7. The enterprise **collects as much data as possible** about asset, network, and communication state and uses it to improve its posture.

## 6. The pillars at a glance

Frameworks organize ZT capabilities into "pillars." Two main ones appear in defense work:

**DoD Zero Trust Strategy — 7 pillars:** User · Device · Applications & Workloads · Data · Network & Environment · Automation & Orchestration · Visibility & Analytics. The DoD roadmap breaks these into 152 activities, with 91 "Target Level" activities required across the department by **FY2027** and the rest ("Advanced") by FY2032.

**CISA Zero Trust Maturity Model — 5 pillars + 3 cross-cutting capabilities:** Identity · Devices · Networks · Applications & Workloads · Data, with Visibility & Analytics, Automation & Orchestration, and Governance running through all of them. CISA grades each pillar across four maturity stages: **Traditional → Initial → Advanced → Optimal.**

Both descend from NIST SP 800-207. The DoD model is more prescriptive and mission-aligned; the CISA model is a flexible maturity roadmap.

## 7. Why this matters (especially in defense IT)

For systems supporting DoD programs, Zero Trust is not optional or aspirational — it is mandated policy with deadlines. Authorizing Officials increasingly evaluate a system's ZT posture *holistically*, because a weakness in any one pillar undermines the whole architecture. Understanding the model — subjects and resources, the PEP/PDP flow, per-session authorization, and the elimination of trusted east-west traffic — is the conceptual backbone everything else in these papers builds on.

---

*Next: Paper 2 expands the architecture — NIST logical components, the trust algorithm, deployment models, workload identity (mTLS/SPIFFE), microsegmentation, and the pillars in depth.*
