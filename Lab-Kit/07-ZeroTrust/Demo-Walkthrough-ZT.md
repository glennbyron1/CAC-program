# Zero Trust Lab — Demo Walkthrough

**Author:** Glenn Byron
**Document ID:** DEMO-ZT-001
**Framework:** NIST SP 800-207 (Zero Trust Architecture), CISA Zero Trust Maturity Model v2.0
**Companion to:** [`../../Demo-Walkthrough.md`](../../Demo-Walkthrough.md) (the baseline smart-card demo)

> **What this covers:** A walkthrough of the Phase 8 ZT controls layered on top of the baseline lab — tiered admin model, authentication policy silos, device certs, shortened ticket lifetimes, microsegmentation, and the closing visibility loop. Use during a portfolio review to show ZT maturity beyond IA-2(11).

---

## What You Are Demonstrating

Phase 4 demoed identity (smart card). Phase 8 demos the rest of the Zero Trust pillars:

| Pillar | Demoed In | Control |
|---|---|---|
| **Identity** | Phase 4 + ZT.1 | Smart card + Authentication Policy Silos |
| **Devices** | ZT.2 | Per-device certs from on-prem CA |
| **Networks** | ZT.3, ZT.6 | Microsegmentation + per-app access |
| **Applications & Workloads** | ZT.4 | mTLS between services, gMSA + workload certs |
| **Data** | (Phase 9+) | Out of scope for this demo |
| **Visibility & Analytics** | ZT.5 | WEF → SIEM → CA risk loop |
| **Automation & Orchestration** | ZT.7 | `Invoke-ZeroTrustValidation.ps1` |

---

## Prerequisites Before Running the Demo

Run the Phase 4 demo first (it sets the baseline expectations). Then verify Phase 8:

```powershell
.\Lab-Kit\07-ZeroTrust\Invoke-ZeroTrustValidation.ps1 -ExportReport
```

Expect **PASS** on L8, L9, L10, L11, L12, L13. L14 (recent PKINIT events) passes after one smart card login.

---

## ZT.1 — Tiered Admin Model + Auth Policy Silos

Open Active Directory Users & Computers on Lab-DC01. Navigate to `Admin → Tier-0 / Tier-1 / Tier-2`. Show the three OUs and their admin/silo groups.

Open the Authentication Policies node (View → Advanced Features first). Show `APS-Tier-0`, `APS-Tier-1`, `APS-Tier-2` — all in **Enforce** mode.

**Live demo — cross-tier deny:**

From a Tier 2 workstation (`Lab-Workstation01`), open RunAs and try:

```cmd
runas /user:LAB\T0-Admin cmd
```

You'll see `1385: Logon failure: the user has not been granted the requested logon type at this machine.` Kerberos refused to issue the TGT because the source host is not in the Tier 0 silo.

> **What to say:** "Even if a Tier 2 admin's password was stolen and the attacker has Tier 0 credentials in their pocket, those credentials are useless on this workstation. AD enforces tier isolation at the protocol layer — not just by GPO. This satisfies NIST AC-3, AC-6, and the CISA ZT pillar on Identity."

**📸 Screenshot:** RunAs error showing 1385.

---

## ZT.2 — Per-Device Certificates

On Lab-Workstation01, open MMC → Certificates (Local Computer) → Personal → Certificates. Show the cert issued by `LAB-CA` with template `ZT-Device-Authentication`.

Run this to prove it's autoenrolled and renews:

```powershell
Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like '*Lab-Workstation01*' } |
    Select-Object Subject, NotBefore, NotAfter, Thumbprint
```

> **What to say:** "Every domain-joined device has a unique cryptographic identity issued by our internal CA — not just a hostname, not just a domain join. This cert is what the VPN, the SIEM, and Conditional Access use to identify the device. Stolen user credentials can't be replayed from an unknown device because the device cert isn't there. NIST IA-3 device authentication."

**📸 Screenshot:** Certificate detail showing template + issuer + machine SAN.

---

## ZT.3 — Microsegmentation

From Lab-Workstation01, try to ping Lab-Workstation01 → (no such host)... actually, try Lab-Workstation02 if you have one, or any other tier-2 host:

```powershell
Test-NetConnection Lab-Workstation01 -Port 445
```

Result: Connection refused / TCP failed. The Domain firewall profile blocks east-west traffic by default.

From the same workstation, ping Lab-DC01:

```powershell
Test-NetConnection Lab-DC01 -Port 88
```

Result: Connection succeeded. Workstations are allowed to talk **upward** to DCs for domain services, but not laterally to peer workstations.

> **What to say:** "Default-deny east-west. A workstation can talk to its DC for the things AD requires, and to its broker for the apps it's allowed to reach. It cannot talk to other workstations — closing the most common ransomware lateral-movement path. CISA Zero Trust Maturity Network pillar."

**📸 Screenshot:** Test-NetConnection failure on peer + success on DC.

---

## ZT.4 — Shortened Kerberos Lifetimes (continuous evaluation)

On any workstation, run `klist` to show current tickets:

```powershell
klist
```

Find a TGT — observe `Start Time` and `End Time`. The window should be ~4 hours, not 10.

> **What to say:** "Default AD posture trusts a TGT for 10 hours. A compromised session survives 10 hours before AD even rechecks. We shortened that to 4 hours. Every 4 hours, the user's credential is re-evaluated against current group membership, account state, and authentication policy. If we revoke their admin rights at 9 AM, the longest window of residual access is 4 hours — not the rest of the workday. NIST AC-12, IA-5(13)."

**📸 Screenshot:** klist output with End Time visible.

---

## ZT.5 — Visibility Loop (SIEM → Risk → Conditional Access)

This is the closing-the-loop piece. The SIEM is watching authentication events; a detection raises the user's risk score; Conditional Access reads the risk and blocks the next sign-in attempt.

**Trigger a detection:**

From a host that's NOT a normal sign-in source (e.g., over Tor browser), try to authenticate with a known account. Within ~2 minutes, the SIEM detection fires.

**Show the result in Entra:**

In the Entra admin portal → Identity Protection → At-Risk Users, find the test account. Risk Level = High.

**Attempt sign-in again:**

The user is blocked with "Access denied — sign-in risk detected. Contact your administrator."

> **What to say:** "Detection without response is just storage. We connected the SIEM directly to the access decision plane. When a detection fires, the user's risk score rises automatically, and the next access attempt is blocked or stepped up — without anyone reading an email or filing a ticket. CISA Visibility & Analytics + Automation & Orchestration pillars, fully wired."

**📸 Screenshot:** Risk-blocked sign-in error screen + Entra At-Risk Users showing the elevated risk.

---

## ZT.6 — Per-App Access (replaces flat VPN)

Demo only if `Convert-VPNToPerApp.ps1` is complete (broker product configured).

Sign in via the broker portal. The portal shows only the apps the user's tier is allowed to reach — no network-level VPN tunnel was established. The user clicks an app; broker validates identity + device cert + risk → connects to that single app.

> **What to say:** "Old VPN gave the user a /24 network. ZT gives them exactly the one app they need. No lateral discovery, no peer-to-peer, no flat network. NIST AC-3, SC-7."

**📸 Screenshot:** Broker portal showing app list + completed connection.

---

## ZT.7 — Validation Report

Finish the demo by running:

```powershell
.\Lab-Kit\07-ZeroTrust\Invoke-ZeroTrustValidation.ps1
```

Show the 7-layer pass/fail with grade A.

> **What to say:** "Continuous validation is part of the architecture. The same script we used to validate Phase 4 in 7 layers now extends to 14 layers. We can run this on demand or schedule it — it's how we maintain the ZT posture as the environment changes. NIST CA-7."

**📸 Screenshot:** Validation summary block with grade.

---

## Talking Points for Hiring Managers

| Question | Answer |
|---|---|
| "Why tiered admin model?" | Reduces blast radius of credential theft. Tier 0 admin can compromise the forest; Tier 2 admin can only compromise workstations. Auth Policy Silos enforce that at the Kerberos layer — even if creds are stolen, they're spatially limited. |
| "How is this different from MFA?" | MFA validates the human. ZT validates the human, the device, the network path, the workload, and re-validates continuously. MFA is one signal among many. |
| "What's the operational cost?" | Higher KDC traffic from shortened tickets, more cert renewals, more SIEM ingest. In a 100-user lab it's invisible; in a 10K-user enterprise, plan to benchmark. Worth it — the lab-day toil reduces because there's no "did we revoke that admin from everywhere" question — you revoke them from one group. |
| "Where does this fall short of full ZT?" | Data pillar isn't covered (DLP, sensitivity labels). Workload pillar is partial (gMSA + workload certs but no service mesh). Both are scoped for Phase 9 / Phase 10. |
| "Frameworks?" | NIST SP 800-207, NIST SP 800-53 Rev 5 (AC-2/3/5/6/12, IA-2/3/5, SC-7/8, AU-2/6/12, CA-7, SI-4), CISA Zero Trust Maturity Model v2.0 (all pillars except Data, currently at Advanced on most). |

---

## NIST SP 800-53 Controls Demonstrated

| Control | ID | Demoed By |
|---|---|---|
| Tiered access control | AC-3, AC-6 | Authentication Policy Silos (ZT.1) |
| Separation of duties | AC-5 | Tier admin model + RBAC |
| Device authentication | IA-3 | Per-device certs (ZT.2) |
| Boundary protection | SC-7, SC-7(5) | Microsegmentation (ZT.3) |
| Session termination | AC-12, IA-5(13) | Kerberos lifetimes (ZT.4) |
| System monitoring | SI-4, SI-4(4) | SIEM detections (ZT.5) |
| Continuous monitoring | CA-7 | Invoke-ZeroTrustValidation.ps1 (ZT.7) |

---

*Related: `README.md` (Phase 8 plan), `../../Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md` (design).*
