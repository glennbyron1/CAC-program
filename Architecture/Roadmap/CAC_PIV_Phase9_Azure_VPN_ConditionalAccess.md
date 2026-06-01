# Phase 9 — Cloud Identity & Conditional-Access VPN (Azure) ⬜
### Demonstrates the modern DoD remote-access pattern — Entra Conditional Access + certificate-authenticated VPN — on free commercial Azure

*Built in the same scripted/automated style as Phases 1–8. This phase extends your two-tier PKI and Phase 8 work into the cloud identity layer the DoD is moving toward: **Microsoft Entra ID + Conditional Access**, with an **Azure point-to-site VPN authenticated by certificates from your own Issuing CA.** It is the same Entra/Conditional-Access technology used in Azure Government (DoD IL5); only the accreditation boundary differs.*

---

## ⚠️ Scope & data disclaimer (read first — put this at the top of the module README too)

- This lab runs entirely in **commercial Azure**, not Azure Government, GCC High, or any IL4/IL5 environment. The DoD IL5 tenant is restricted to the DoD and approved providers and **cannot** be procured for a personal lab — and no attempt is made to access one.
- **Synthetic data only.** No CUI, no real PII, no production credentials, no real organizational names ever enter this lab.
- Framing for documentation and interviews: *"Commercial Azure demonstrating the same Microsoft Entra ID and Conditional Access remote-access pattern used in Azure Government (DoD). Feature sets and endpoints differ between commercial and GCC High/IL5; the identity and access mechanics are equivalent."*
- This is a learning/portfolio lab, not an accredited system. It has no ATO and makes no compliance claim beyond demonstrating the architecture.

### Funding & cost model — built for Azure for Students
- **Azure for Students** provides **$100 credit for 12 months, no credit card required.** Note it does **not** include the Visual Studio/MSDN monthly credit, and some Marketplace/licensing SKUs are restricted on the student plan — none of which this lab depends on.
- The **identity layer is effectively free**: pair Azure for Students with a **free Microsoft 365 Developer tenant** (Entra ID P2 — Conditional Access, risk policies). Conditional Access practice does **not** consume the $100 credit.
- The **VPN Gateway is the only meaningful cost** — billed per hour while it exists (cheapest SKU ~a few cents/hour). The model is **provision → exercise → tear down the same session**, so a full Phase 9 run costs a couple of dollars, not a standing monthly charge. Within the student credit this is comfortably free.
- **Day-one guardrail:** activate a **Cost Management budget with alerts** before provisioning anything (see 9.0). Student accounts halt at credit exhaustion rather than billing you, but the alert prevents any mid-month surprise and is a good cloud-governance habit to be able to demonstrate.

---

## What this phase proves
A remote user is admitted only when **three things** are simultaneously true: a valid **certificate** from your PKI (the VPN tunnel), a verified **identity** in Entra ID (MFA), and a **compliant/known device** (Conditional Access). That is the DoD's direction of travel — the network tunnel is no longer the trust boundary; the identity-and-device policy is.

## Prerequisites (all free / no cost)
- `Microsoft 365 Developer tenant` — free; includes **Entra ID P2** (Conditional Access, risk-based policies). The key dependency.
- `Azure free account` — $200 / 30-day credit + 12 months free tier; enough for a VPN Gateway exercise. *(VPN Gateway is not free-tier; provision, test, then deprovision — see 9.6 teardown to control cost.)*
- Your existing **Issuing CA** (Lab-DC01) from Phase 2 — issues the VPN client certificates.
- Optional: **Microsoft Learn sandbox** for credit-card-free practice of individual steps.

---

## 9.0 — Cost Guardrail & Subscription Setup  *(do this first — CM-3, SA-2)*
Stand up spending controls before a single billable resource exists.

- `Connect-AzureStudent.ps1` — connects to the Azure for Students subscription via Az PowerShell; records subscription ID and confirms the offer type
- `New-CostBudget.ps1` — creates a **Cost Management budget** (e.g., $25 / $50 alert thresholds) with email alerts, so spend is visible from day one
- `New-LabResourceGroup.ps1` — creates a single dedicated resource group (`rg-ztlab-phase9`) so every billable item lives in one place and teardown is one command
- *Doc:* `Cost-Model.md` — what each resource costs, the provision-then-destroy workflow, and a note that the M365 Developer tenant / Entra layer is free of the credit


Stand up the Entra tenant and link identity to your existing directory model.

- `Connect-EntraTenant.ps1` — connects to the M365 Developer tenant via Microsoft Graph PowerShell; records tenant ID and verifies P2 licensing
- `New-EntraTestUsers.ps1` — creates synthetic test users/groups mirroring the lab's RBAC roles from Phase 8.1 (clearly labeled non-real)
- `Set-EntraMFA.ps1` — enforces MFA registration for all test users (baseline before Conditional Access)
- *Doc:* `Identity-Mapping.md` — how the on-prem PKI identity model relates to the cloud Entra identity (federation concept, even if the lab keeps them parallel rather than hybrid-joined)

## 9.2 — PKI-Authenticated Point-to-Site VPN  *(SC-8, SC-12, IA-3, AC-17)*
The transport layer — and the direct tie to your two-tier PKI.

- `New-AzureVNetGateway.ps1` — provisions a VNet + **VPN Gateway** configured for point-to-site, OpenVPN/IKEv2
- `New-VPNClientCert.ps1` — issues a **client authentication certificate from your Issuing CA** (not Azure self-signed) and uploads the issuing chain's public cert to the gateway as the trusted root
- `Install-VPNClientProfile.ps1` — installs the P2S client profile on the lab workstation; mirrors your existing `Deploy-VPNClient.ps1` pattern (EAP-TLS / certificate auth)
- `Test-VPNCertAuth.ps1` — connects, confirms the tunnel authenticated by certificate, logs the result
- *Tie-in:* this proves your PKI extends to cloud remote access — a client cert from the same Root → Issuing chain now gates the Azure tunnel.

## 9.3 — Conditional Access (the actual DoD pattern)  *(AC-2, AC-3, IA-2, AC-17)*
The gate. This is where "VPN = you're in" becomes "policy decides on every connection."

- `New-ConditionalAccessPolicy.ps1` — creates baseline CA policies:
  - require MFA for all cloud-app access
  - require a **compliant or hybrid-joined device** for sensitive apps
  - block legacy authentication
  - optional: restrict sign-in by named location (simulating "only from the managed network")
- `New-NamedLocations.ps1` — defines trusted named locations / IP ranges for location-based rules
- `Test-ConditionalAccess.ps1` — runs the **What-If** evaluation and a live sign-in test; logs which policies applied and why (the PE/PA decision trail)
- *Doc:* `ConditionalAccess-PolicyDesign.md` — maps each CA policy to the NIST 800-207 Policy Engine logic and to the Phase 8.3 conditional-access design

## 9.4 — Device Compliance Signal  *(CM-6, IA-3, SI-4)*
Feeds the "known/healthy device" input into the policy decision (extends Phase 8.2).

- `Set-DeviceCompliancePolicy.ps1` — defines an Intune-style compliance policy (encryption on, AV healthy, min OS) — uses Intune trial if available, else documents the signal and simulates with device groups
- `Join-DeviceToEntra.ps1` — Entra-registers/joins the lab workstation so device state becomes a usable CA signal
- *Result:* Conditional Access in 9.3 can now require the device be compliant — user **and** device verified together, the core Zero Trust device requirement.

## 9.5 — Visibility & Decisioning  *(AU-6, SI-4, IR-4)*
Closes the loop, extending Phase 8.6 into the cloud.

- `Enable-EntraSignInLogs.ps1` — turns on sign-in / audit logs and (free tier permitting) routes to a Log Analytics workspace
- `New-SignInDetections.ps1` — basic detections: failed CA evaluations, risky sign-ins, impossible-travel (where licensing allows)
- `Export-AccessEvidence.ps1` — exports sign-in + CA decision logs into your `Compliance-Reports` structure as **Before-ZT / After-ZT** evidence, matching your existing staging pattern

## 9.6 — Validation, Cost Control & Teardown  *(CA-2, CA-7)*
Keeps the phase measurable and the cost at zero when idle.

- `Invoke-CloudZTValidation.ps1` — extends your validator: cert-auth VPN works, MFA enforced, CA policy blocks non-compliant device, sign-in logged with decision trail
- `Remove-AzureLabResources.ps1` — **deletes the entire `rg-ztlab-phase9` resource group** (VPN Gateway, VNet, public IP, everything billable) in one call to stop charges after each session; confirms the group is gone and reports the session's estimated cost from Cost Management
- `Stage-Reports.ps1` (extend) — adds the cloud Before/After-ZT delta
- *Docs:* update SSP/POA&M with the cloud control mappings; add `Demo-Walkthrough-Cloud.md` with the "DoD is moving to this" narrative and hiring-manager Q&A

---

## Suggested execution order
**9.0 always runs first** (cost guardrail + resource group — never provision a billable resource without the budget alert live). Then 9.1 → 9.2 → 9.3 are the core and deliver the headline result (PKI-authenticated VPN gated by Conditional Access). 9.4 strengthens 9.3 with the device signal. 9.5 adds the evidence trail. 9.6 always runs last each session — **especially `Remove-AzureLabResources.ps1`**, so the VPN Gateway isn't billing you overnight. Identity work (9.1, 9.3, 9.4) can be done freely anytime; only spin the gateway (9.2) up and down around a focused session.

## How this connects to the rest of the lab
- **Phase 2 PKI** → issues the VPN client certs in 9.2 (your Root→Issuing chain now reaches the cloud).
- **Phase 8.2 device trust** → realized concretely as the Conditional Access device-compliance signal in 9.4.
- **Phase 8.3/8.4 conditional access** → implemented for real in Entra in 9.3.
- **Phase 8.6 analytics** → extended to cloud sign-in decisioning in 9.5.

## What this turns the lab into
A portfolio that demonstrates Zero Trust **across on-prem and cloud**: passwordless PKI authentication on the ground, and the modern Entra + Conditional Access remote-access model the DoD is adopting — with your own certificate chain tying the two together. Being able to say *"my PKI issues the cert that authenticates an Azure point-to-site VPN, and a Conditional Access policy then requires a compliant device before granting access"* is a concrete, current, defensible story for a NAVAIR-side role.

## Honest framing note
Conditional Access "continuous" evaluation (CAE) and risk policies are strongest with Entra ID P2 and specific licensing; some signals (e.g., full Identity Protection risk detections, Intune compliance) may be limited in a free developer/trial setup. Document what you demonstrated live versus what you designed but couldn't fully license — that distinction is itself a sign of someone who understands the platform.
