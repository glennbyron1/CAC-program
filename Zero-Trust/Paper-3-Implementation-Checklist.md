# Zero Trust Implementation Checklist

*Paper 3 of 4 — Actionable checklist*
**Author:** Glenn Byron

A working checklist for standing up (or assessing) a Zero Trust architecture, organized by the pillars from Papers 1–2. Treat the **Foundation** section as prerequisite work, then progress through the pillars. Items roughly ascend from Initial → Advanced → Optimal maturity within each section.

---

## 0. Foundation / Program

- [ ] Secure executive sponsorship and a named Zero Trust program owner
- [ ] Inventory **everything** — users, non-person entities (NPEs), devices, applications, services, and data stores
- [ ] Classify data and identify the high-value assets / "protect surfaces"
- [ ] Map transaction flows: who/what talks to what, and over which paths
- [ ] Pick a reference framework and map to it (NIST SP 800-207, CISA ZTMM v2.0, and — for defense — the DoD ZT Strategy's 7 pillars / 152 activities)
- [ ] Run a current-state maturity assessment per pillar (Traditional/Initial/Advanced/Optimal)
- [ ] Define target maturity and a phased roadmap with milestones (for DoD, Target Level by FY2027)
- [ ] Establish governance: policy authoring, change control, and mapping to RMF/compliance controls
- [ ] Define metrics and a feedback loop to measure progress

## 1. Identity / User

- [ ] Consolidate to a centralized, authoritative identity provider (IdP)
- [ ] Enforce **phishing-resistant MFA** for all users (PKI/CAC or FIDO2/WebAuthn; not SMS)
- [ ] Eliminate or vault all shared/local accounts and default credentials
- [ ] Implement role-/attribute-based access control (RBAC/ABAC) with **least privilege**
- [ ] Bring NPEs (service accounts, machine identities) under management — scoped, rotated, monitored
- [ ] Deploy Privileged Access Management (PAM): no standing admin rights; just-in-time elevation with session recording
- [ ] Enable conditional access policies (decisions based on user + device + context + risk)
- [ ] Add behavioral analytics / risk scoring (UEBA) to detect anomalous identity use
- [ ] Implement continuous authentication and real-time, risk-based session revocation
- [ ] Automate the full identity lifecycle (joiner/mover/leaver) with prompt deprovisioning

## 2. Devices / Endpoints

- [ ] Maintain a real-time, authoritative device inventory (CDM)
- [ ] Establish hardware-rooted device identity (TPM-backed certificates)
- [ ] Deploy MDM/UEM to manage and enforce configuration on all endpoints
- [ ] Require device health/posture checks **before and during** access ("comply-to-connect")
- [ ] Deploy EDR/XDR on all endpoints with centralized telemetry
- [ ] Enforce full-disk encryption and a secure baseline/hardening standard
- [ ] Block or quarantine unmanaged/non-compliant devices automatically
- [ ] Feed device posture into the Policy Engine as an access signal

## 3. Networks / Environment

- [ ] Encrypt all traffic in transit, including internal east-west traffic
- [ ] Implement macrosegmentation, then **microsegmentation** down to the workload
- [ ] Adopt a software-defined perimeter / ZTNA so resources are hidden until authorized
- [ ] Replace broad VPN access with per-application, identity-aware access
- [ ] Define and enforce default-deny network policies (allow-list, not block-list)
- [ ] Place a Policy Enforcement Point in front of every resource
- [ ] Continuously monitor and log all network flows

## 4. Applications & Workloads

- [ ] Inventory all applications, APIs, and workloads (including shadow IT)
- [ ] Issue cryptographic **workload identities** (e.g., SPIFFE/SPIRE)
- [ ] Enforce **mutual TLS (mTLS)** for all service-to-service (east-west) traffic
- [ ] Apply least-privilege authorization to every API call (default-deny)
- [ ] Integrate security into the pipeline (DevSecOps): SAST/DAST, dependency/SBOM scanning, signed artifacts
- [ ] Secure the software supply chain and verify provenance of third-party components
- [ ] Use short-lived, auto-rotated credentials/certificates for workloads
- [ ] Consider a service mesh to enforce mTLS and policy transparently
- [ ] Continuously monitor application behavior at runtime

## 5. Data

- [ ] Discover and inventory data across all repositories
- [ ] Classify and label data by sensitivity
- [ ] Encrypt data **at rest and in transit**; manage keys centrally
- [ ] Apply rights management (DRM) and enforce access at the data-object level
- [ ] Tie data access to dynamic policy (identity + device + context + sensitivity)
- [ ] Deploy Data Loss Prevention (DLP) and monitor data access patterns
- [ ] Define and enforce data retention and disposal policies

## 6. Visibility & Analytics *(cross-cutting)*

- [ ] Centralize logging from all pillars into a SIEM/analytics platform
- [ ] Establish behavioral baselines and anomaly detection
- [ ] Build risk scoring that feeds the Policy Engine in near real time
- [ ] Maintain dashboards and alerting for security posture and ZT maturity metrics
- [ ] Ensure log integrity, sufficient retention, and audit readiness

## 7. Automation & Orchestration *(cross-cutting)*

- [ ] Deploy SOAR with automated response playbooks (isolate host, revoke session, rotate creds)
- [ ] Automate policy enforcement and dynamic, risk-based access decisions
- [ ] Automate provisioning/deprovisioning across identity, device, and network
- [ ] Integrate tools via APIs so signals and actions flow without manual handoffs

## 8. Governance *(cross-cutting)*

- [ ] Codify Zero Trust policies and keep them version-controlled and auditable
- [ ] Map every control to the relevant compliance framework (NIST RMF, applicable overlays)
- [ ] Run periodic maturity reassessments and update the roadmap
- [ ] Conduct continuous control validation (e.g., breach-and-attack simulation, red teaming)
- [ ] Review and recertify access entitlements on a defined cadence

---

### How to sequence this

A pragmatic order for most organizations: **Foundation → Identity → Devices → Network/microsegmentation → Applications/Data → Visibility → Automation**, with Governance running throughout. Identity and device posture come first because nearly every other policy decision depends on those signals. Don't try to boil the ocean: pick one high-value protect surface, take it to your target maturity end-to-end, prove the model, then expand.

---

*Next: Paper 4 expands each of these checklist areas — the rationale, the how, the common pitfalls, and what "good" looks like at each maturity stage.*
