# Zero Trust Architecture: A Technical Deep Dive

*Paper 2 of 4 — Expanded architecture*

This paper expands the core model from Paper 1 into the components, algorithms, and mechanisms that make Zero Trust actually work. Where Paper 1 answered *"what is the model,"* this answers *"how is it engineered."*

---

## 1. The NIST logical components in detail

NIST SP 800-207 decomposes the "decision brain" into three logical components plus a set of supporting data sources. In Paper 1 these were grouped as PDP and PEP; here is the full picture.

### Policy Decision Point (PDP) = Policy Engine + Policy Administrator

- **Policy Engine (PE).** The actual decision-maker. It runs the **trust algorithm** against incoming signals and outputs *grant, deny, or revoke* for a specific request. The PE never touches traffic directly — it only produces decisions.
- **Policy Administrator (PA).** The executor. When the PE says "grant," the PA establishes the session — generating any authentication token or credential the client needs and instructing the PEP to open the path. When the PE says "deny" or "revoke," the PA tells the PEP to tear the connection down.

### Policy Enforcement Point (PEP)

The PEP is the gate that sits in the data path in front of each resource. It **enables, monitors, and ultimately terminates** the connection between a subject and a resource, acting on the PA's instructions. Physically a PEP can be a gateway, a reverse proxy, a sidecar, an agent on the endpoint, or a cloud access broker.

```
                 ┌───────────────── CONTROL PLANE ─────────────────┐
                 │                                                  │
                 │     Policy Engine (decide)                       │
                 │            │                                     │
   data sources ─┼──► feeds ──┤                                     │
                 │            ▼                                     │
                 │     Policy Administrator (execute / issue token) │
                 │            │                                     │
                 └────────────┼─────────────────────────────────────┘
                              │ instructs
                              ▼
   SUBJECT ───────────► [ Policy Enforcement Point ] ───────────► RESOURCE
                              (DATA PLANE)
```

### The data sources that feed the Policy Engine

The PE's decision is only as good as its inputs. NIST identifies the typical feeds:

- **ICAM / ID management** — the authoritative identity store and entitlements (in DoD, this connects to CAC/PKI and enterprise identity services).
- **Enterprise PKI** — issues and validates the certificates used by users, devices, and workloads.
- **Continuous Diagnostics and Mitigation (CDM)** — real-time device inventory and posture (is this asset known, patched, compliant?).
- **Threat intelligence feeds** — known-bad indicators, emerging TTPs.
- **Activity logs / network and system telemetry** — what is actually happening right now.
- **Data access policy** — the rules describing who/what may touch which data under which conditions.
- **SIEM / security analytics** — aggregated history used to compute risk and detect anomalies.
- **Industry/compliance inputs** — applicable standards the decision must honor.

## 2. The trust algorithm

The trust algorithm is the logic the Policy Engine uses to turn signals into a decision. NIST describes two design axes:

**Criteria-based vs. score-based**
- *Criteria-based:* the request must satisfy a fixed set of qualifications (e.g., valid cert AND compliant device AND user in the right group). More predictable; easier to audit.
- *Score-based:* signals are weighted into a confidence/risk score, and access is granted if the score clears a threshold for that resource's sensitivity. More adaptive; supports "step-up" challenges.

**Singular vs. contextual**
- *Singular:* each request is judged in isolation.
- *Contextual:* the engine considers history and behavior — recent request patterns, sequence, prior anomalies. Contextual evaluation is what enables true continuous, behavior-aware authorization, at the cost of needing to retain and analyze state.

Mature implementations are typically **score-based and contextual**: sensitivity of the resource raises the bar, and anomalous behavior lowers the score mid-session, triggering re-authentication or revocation.

## 3. Deployment models (how the abstract model gets installed)

NIST outlines several deployment patterns. Real environments mix them.

- **Device agent / gateway-based.** A trusted agent on the endpoint coordinates with a gateway in front of each resource. Strong for managed-device fleets; the agent reports posture and brokers the connection.
- **Enclave-based.** A single gateway protects a *group* of resources (an "enclave") rather than one resource each. Useful for legacy systems that cannot host their own agent — you wrap the enclave instead of the app.
- **Resource portal-based.** Subjects reach resources through a portal/broker; no agent required on the device. Easier for unmanaged or BYOD/partner access, but you see less device posture detail.
- **Device application sandboxing.** Vetted applications run in isolated compartments on the endpoint, segregated from the rest of the device so a compromise elsewhere can't reach the sandboxed app.

## 4. Identity as the new perimeter (ICAM)

Because the network is no longer a trust boundary, **identity becomes the primary control plane.** Identity, Credential, and Access Management (ICAM) is the spine of a ZT program:

- **Strong authentication.** Phishing-resistant MFA is the baseline. In DoD that centers on **PKI/CAC and derived credentials**; in the commercial world, FIDO2/WebAuthn hardware keys. Passwords alone are disqualifying at any mature level.
- **Non-person entities (NPEs).** Service accounts, scripts, and machines need managed identities too — scoped, short-lived, rotated, and monitored. Long-lived static service-account secrets are a classic ZT failure.
- **Least privilege and just-in-time (JIT) access.** Grant the minimum entitlement for the minimum time. Privileged access is brokered through PAM with session recording and ephemeral elevation rather than standing admin rights.
- **Continuous authentication.** Authentication is not a one-time event at login; the session is continuously re-evaluated against posture and behavior.

## 5. Microsegmentation and east–west traffic

Segmentation is how Zero Trust contains a breach.

- **Macrosegmentation** divides the network into broad zones.
- **Microsegmentation** goes much finer — isolating individual workloads or even processes so that each can only talk to the specific peers it legitimately needs. Policy is expressed in terms of *identity and workload* ("the billing service may call the ledger API") rather than IP addresses and subnets.
- **Software-defined perimeter (SDP)** hides resources entirely until a subject is authenticated and authorized — the resource is "dark" to unauthorized scanners.

The payoff is the death of lateral movement. Even if an attacker lands on one host, microsegmentation means that host can only reach its narrowly defined neighbors, and every one of those connections still demands authentication.

## 6. Server-to-server and workload identity

This is the area engineers most often under-build. For two services to trust each other in a Zero Trust way, each needs a **cryptographic workload identity** and they must **mutually authenticate**:

- **Mutual TLS (mTLS).** Both ends present and verify certificates — not just the client trusting the server, but the server verifying the client. Every east-west call is authenticated and encrypted.
- **SPIFFE / SPIRE.** An open framework for issuing verifiable workload identities (SPIFFE IDs delivered as short-lived SVID certificates), so services authenticate by *who they are* rather than *where they run*. This decouples identity from IP/host and works across cloud, on-prem, and containers.
- **Service mesh.** A mesh (e.g., sidecar proxies) can enforce mTLS and policy for service-to-service traffic transparently, so application teams get Zero Trust east-west security without hand-rolling it per service.
- **Short-lived credentials.** Certificates and tokens are issued for minutes/hours and auto-rotated, shrinking the value of any stolen secret.

## 7. Continuous monitoring, visibility, and automation

Zero Trust is a *feedback loop*, not a one-time gate.

- **Visibility & Analytics.** Comprehensive logging and telemetry across users, devices, network, apps, and data feed the analytics layer that computes risk and detects anomalies. You cannot enforce policy on what you cannot see.
- **Automation & Orchestration (SOAR).** At scale, humans cannot evaluate every request or respond to every event. Automated playbooks revoke access, isolate hosts, and adjust policy in seconds based on analytics — this is what moves an organization from "Advanced" to "Optimal" maturity.
- **Governance.** Policy must be authored, versioned, audited, and tied to compliance frameworks (in federal work, mapped to NIST RMF controls).

## 8. The maturity journey

CISA's model makes clear that Zero Trust is incremental, assessed per pillar:

| Stage | Characteristics |
|---|---|
| **Traditional** | Static credentials, perimeter defense, manual config and response, implicit trust based on network location. |
| **Initial** | Starting automation, some cross-pillar integration, MFA introduced, beginning of least-privilege. |
| **Advanced** | Centralized visibility and identity control, cross-pillar coordination, posture-based and predefined responses, expanded least-privilege. |
| **Optimal** | Fully automated, dynamic policy, continuous monitoring and just-in-time access across all pillars; self-adjusting based on real-time analytics. |

An organization is rarely at one uniform level — it may be Advanced in Identity but Initial in Data. That's expected; the model is meant to expose gaps for prioritization.

## 9. The pillars in depth

- **User / Identity.** Authenticate and continuously evaluate every human and NPE; MFA, PAM, behavioral analytics, least privilege.
- **Device.** Only known, healthy, compliant devices get access; enforced via CDM/MDM, TPM-backed device identity, comply-to-connect, and continuous posture checks.
- **Network & Environment.** Segment everything; encrypt all traffic; software-defined networking and microsegmentation; treat every network as hostile.
- **Applications & Workloads.** Secure the software supply chain and runtime; DevSecOps, workload identity, authenticated APIs, and least-privilege service-to-service calls.
- **Data.** The ultimate object of protection: classify, label, encrypt at rest and in transit, apply rights management, and tie access to dynamic policy at the data-object level.
- **Visibility & Analytics** *(cross-cutting).* Telemetry and analytics feeding the Policy Engine and detection.
- **Automation & Orchestration** *(cross-cutting).* Machine-speed enforcement and response.
- **Governance** *(cross-cutting, CISA).* Policy authoring, oversight, and compliance alignment.

---
*Next: Paper 3 turns this architecture into an actionable implementation checklist organized by pillar.*
