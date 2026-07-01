# Lab Topology — Deliberate Air-Gap Design

**Document ID:** ARCH-ICAM-014
**Author:** Glenn Byron
**Frameworks:** NIST SP 800-53 SC-7 (Boundary Protection), AC-4 (Information Flow Enforcement), CM-7 (Least Functionality), SC-32 (System Partitioning), PE-3 (Physical Access Control) · CISA Zero-Trust Maturity Model Networks pillar · NIST SP 800-82 ICS air-gap principles
**Pairs with:** [`Architecture/Blueprint.md`](Blueprint.md) (PKI design) · [`Architecture/Azure-VPN-Guide.md`](Azure-VPN-Guide.md) (the only sanctioned cloud egress, on a separate trust path) · [`Architecture/Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md`](Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md) (why information-flow discipline matters)

> **What this is:** The deliberate physical and logical network design of the CAC/PIV lab. The lab segment is air-gapped from the internet; the only path between the lab and outside connectivity is the Hyper-V host's staging role. This document explains the design, the rationale, and the NIST-control rationale behind every flow.

> **What this is NOT:** A how-to-build-a-homelab guide. The build itself is in `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`. This document is the design rationale a security reviewer or hiring manager would expect to read alongside the build evidence.

---

## Why the air-gap matters — the design intent

Federal and defense networks at IL4 / IL5 / IL6 and many classified environments use a **staging-host + isolated-production-segment pattern**. The staging host has limited, controlled internet egress for software downloads, vendor portals, and operator-driven research. The production segment has no internet and is reached only through a discipline-enforced transfer path. This lab is a deliberate homelab analog of that pattern — scaled down to a Hyper-V host + a dumb switch + a single physical workstation, but the discipline is identical to enterprise practice.

The reason to bother with the discipline at homelab scale is that a homelab without air-gap discipline is just a small enterprise network. It teaches nothing about boundary engineering. A homelab WITH discipline teaches the exact operator habits a SCIF, an IL5 contractor program office, or a classified development environment runs on every day:

- **Outbound is staging-mediated.** No machine in the lab segment reaches the internet directly.
- **Inbound is impossible.** No port-forward, no inbound NAT, no exposed service.
- **Transfers are operator-driven.** Files arrive in the lab via deliberate action on the host, not via background sync.
- **The trust path is documented.** Every flow has a control rationale. Anything not documented is implicitly denied.

A federal interviewer who asks "how would you isolate a production network from a staging environment in a development homelab" has a name for the right answer: **the staging-host pattern**. This document is the artifact that proves you can articulate it.

---

## Physical topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          HOME WIFI / RESIDENTIAL ISP                    │
│                  (the ONLY internet egress in the design)               │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ WiFi (staging only)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       HYPER-V HOST  (the staging host)                  │
│                       Lab IP: 10.10.10.1                               │
│                                                                         │
│   ╔═══════════════════════════════════════════════════════════════╗     │
│   ║  Wi-Fi NIC                                                    ║     │
│   ║    • Pulls software, vendor portals, OS updates, Azure portal ║     │
│   ║    • NEVER bridged to the lab segment                         ║     │
│   ║    • NOT used by any guest VM directly                        ║     │
│   ╚═══════════════════════════════════════════════════════════════╝     │
│                                                                         │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │  Hyper-V External vSwitch  (bound to physical Ethernet NIC)   │     │
│   │    Lab-DC01 (Server 2025) — Issuing CA + Domain Controller    │     │
│   │      NIC 1: 10.10.20.10/24 — Lab External (v1.0)              │     │
│   │      NIC 2: 10.10.10.10/24 — Lab Internal (added v1.4 for     │     │
│   │              the WSL-Ansible reach path)                      │     │
│   │    Lab-Workstation01 (Server 2025 VM, for SCAP baseline scans)│     │
│   │      Single NIC: 10.10.10.20/24 — Lab Internal                │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│   ╔═══════════════════════════════════════════════════════════════╗     │
│   ║  Physical NIC — Ethernet                                      ║     │
│   ║    • Bound to Hyper-V External vSwitch                        ║     │
│   ║    • Carries BOTH 10.10.10.x and 10.10.20.x to the lab switch ║     │
│   ║    • NEVER bridged to the Wi-Fi NIC                           ║     │
│   ╚═══════════════════════════════════════════════════════════════╝     │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ Ethernet cable
                               ▼
                  ┌────────────────────────────┐
                  │  Dumb unmanaged switch     │
                  │  (no VLANs, no management) │
                  │  Flat layer-2 segment      │
                  │  carrying both subnets     │
                  └────────────────┬───────────┘
                                   │
                                   ▼
                  ┌────────────────────────────┐
                  │  WO02 (physical workstation)│
                  │   10.10.20.30/24            │
                  │   Windows 11 + YubiKey      │
                  │   Smart-card-required GPO   │
                  │   No Wi-Fi adapter enabled  │
                  └────────────────────────────┘
```

**Reading this diagram:** the home Wi-Fi reaches the Hyper-V host. The Hyper-V host has *two NICs that never speak to each other* — the Wi-Fi NIC (staging side) and the physical Ethernet NIC (lab side). The host's lab-side IP is `10.10.10.1`. The Ethernet NIC is bound to a Hyper-V External vSwitch and connects through a dumb unmanaged switch to WO02. **Lab-DC01 (dual-NIC as of v1.4 — `10.10.20.10` on Lab External + `10.10.10.10` on Lab Internal)** and Lab-Workstation01 (single NIC at `10.10.10.20`) both live on the host as Hyper-V VMs, attached to that same External vSwitch — so all four devices (host, DC01, WS01, WO02) share one flat layer-2 broadcast domain via the dumb switch and the External vSwitch. The Internal-range and External-range IP labels are operator-mental-model groupings, not L2 isolation.

The Wi-Fi NIC and the physical Ethernet NIC on the host are deliberately not bridged. Windows treats them as completely separate adapters. The host can resolve and reach Azure on the Wi-Fi side; it can resolve and reach Lab-DC01 + WS01 + WO02 on the Ethernet side; but no packet routes between the two sides.

> **Air-gap validation from Nessus (2026-06-25):** A credentialed Nessus scan from WS01 using `LAB\CardIssuer` (Domain Admin) discovered the Hyper-V host at `10.10.10.1` but the credentialed auth **FAILED** against it. This is the air-gap discipline working as designed — the host is deliberately NOT domain-joined per this topology, so Domain Admin creds cannot authenticate to it. The auth boundary held. Lab-DC01 and WO02 (both domain-joined) authenticated successfully or unsuccessfully based on other factors (Remote Registry, local Administrators group membership), but the **host's "Fail auth" result is the deliberate outcome** — not a configuration error.

---

## Logical topology

```
                ┌─────────────────────────────────────────┐
                │   Home Wi-Fi  (untrusted, internet)     │
                └──────────────────┬──────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────────────┐
              │   Hyper-V HOST  (dual-homed, no routing)   │
              │     • Wi-Fi adapter   ── internet only      │
              │     • Ethernet NIC    ── lab segment only   │
              │     • Windows routing table: no entry that  │
              │       sends lab traffic via Wi-Fi or vice   │
              │       versa                                 │
              │     • Host's own lab-side IP: 10.10.10.1   │
              └────────────────────┬───────────────────────┘
                                   │ Hyper-V External vSwitch
                                   │ bound to physical Ethernet NIC
                                   ▼
              ┌────────────────────────────────────────────┐
              │   Lab segment (flat layer-2)                │
              │   Carried over one cable to the dumb switch │
              │                                             │
              │   Logical IP groupings on the same wire:    │
              │     • 10.10.10.0/24 — "Internal" range      │
              │         host (.1), DC01 NIC2 (.10, v1.4),   │
              │         WS01 (.20)                          │
              │     • 10.10.20.0/24 — "External" range      │
              │         DC01 NIC1 (.10), WO02 (.30)         │
              │                                             │
              │   Same broadcast domain; ARP works across   │
              │   both ranges (devices on either range can  │
              │   reach devices on the other directly).     │
              │                                             │
              │   No router, no DHCP server beyond the      │
              │   Hyper-V vSwitch default.                  │
              └─────────────────────────────────────────────┘
```

**Why two IP ranges on one flat segment?** The IP grouping is **logical**, not physical. `10.10.10.x` and `10.10.20.x` share the same broadcast domain via the dumb switch and the Hyper-V External vSwitch — devices can ARP each other directly across the two ranges. The split is for documentation and operator-mental-model purposes ("Internal range" = host + lab VMs; "External range" = DC + physical workstation) rather than for layer-2 isolation. Real enterprise segmentation would use VLANs (a managed switch) or separate physical wires; this lab keeps a single flat L2 segment for simplicity and to avoid the managed-switch attack surface (see "The dumb switch" section below).

> **Topology change log — v1.4 (2026-06-30):** Lab-DC01 gained a second NIC at `10.10.10.10` (Lab Internal) so the WSL Ansible control node on the host could reach it without crossing range boundaries. **This is still NOT SC-32 partitioning** — the two ranges share the same flat L2 segment via the External vSwitch + dumb switch. The change is purely an administrative reachability convenience for the Ansible STIG remediation work in `Lab-Kit/08-Ansible-STIG/`; the lab segment is still a single broadcast domain with logical IP groupings.
>
> **Host-IP conflict during the v1.4 change:** the host's `vEthernet (External)` adapter was holding `10.10.10.10`, so traffic from WSL to the DC's new NIC looped back to the host. Resolved by `Remove-NetIPAddress -IPAddress 10.10.10.10 -InterfaceAlias 'vEthernet (External)' -Confirm:$false`. After that, the host reaches the DC via `10.10.20.10` (DC NIC1, original) AND via `10.10.10.10` (DC NIC2, new), and WSL/Ansible specifically uses `10.10.10.10`. The host's own lab-side IP stayed `10.10.10.1`.
>
> **Honest caveat on partitioning (preserved):** an earlier draft of this document claimed Lab-DC01 had dual NICs bridging two physically isolated subnets (an SC-32 "system partitioning" claim). That was design-doc thinking. The deployed reality before v1.4 was single-NIC + flat L2; the deployed reality at v1.4 is dual-NIC + still flat L2 (both NICs sit on the same broadcast domain). Real SC-32 partitioning would require a managed switch with VLANs OR an L3 router between segments — neither is in this build.

---

## Network segments — what's where and what they touch

| Segment | Address | Devices | Internet egress | Notes |
|---|---|---|---|---|
| **Home Wi-Fi** | (resident's home network) | The Hyper-V host's Wi-Fi adapter only | ✅ Yes (residential ISP) | Used for: Windows Updates on the host, Azure Portal access, vendor portal downloads, repo cloning, software staging. **Never bridged to lab.** |
| **Lab segment (flat L2)** — "Internal" IP range | `10.10.10.0/24` | Hyper-V host (`10.10.10.1`) · **Lab-DC01 NIC2 (`10.10.10.10`, v1.4)** · Lab-Workstation01 VM (`10.10.10.20`) | ❌ None | Host's own lab-side IP, the DC's secondary NIC (v1.4 — added for the WSL/Ansible reach path), and any VMs that the operator considers "infrastructure" (WS01 used for SCAP baseline scans; future Wazuh / syslog / database VMs would land here). |
| **Lab segment (flat L2)** — "External" IP range | `10.10.20.0/24` | **Lab-DC01 NIC1 (`10.10.20.10`)** · WO02 physical laptop (`10.10.20.30`) | ❌ None | Where the DC's primary NIC and the physical workstation live. Smart-card GPO enforced on WO02. No Wi-Fi on WO02. Both ranges share the same broadcast domain via the dumb switch; the "Internal" / "External" labels are operator-mental-model groupings, not L2 isolation. As of v1.4, Lab-DC01 appears in **both** range rows because it has one NIC in each range. |

**The single chokepoint:** the Hyper-V host. Information can move between the home Wi-Fi side and the lab side *only* via deliberate operator action on the host — drag-and-drop into a Hyper-V VM via Enhanced Session, PowerShell Direct file copy, or USB transfer. There is no automated background path. (The lab-side flat L2 segment is fully accessible from any device on the segment, so this chokepoint is at the Wi-Fi/Lab boundary on the host, NOT at the Internal/External range boundary inside the lab.)

---

## The Hyper-V host's three roles (and why they don't blur)

The host plays three roles that would, in a less disciplined design, get smeared together. Keeping them distinct is the point of the design:

| Role | What it does | What it must NOT do |
|---|---|---|
| **Staging machine** | Downloads software, browses to vendor portals, accesses Azure Portal, clones the repo, runs operator-only tools | Connect any of its downloaded content to lab VMs automatically (no shared folders that auto-sync; no bridged interfaces) |
| **Hypervisor** | Runs Lab-DC01 as a Gen2 VM, manages vSwitches, snapshots, checkpoints | Provide internet routing FROM the lab VMs back through its Wi-Fi (that would defeat the air-gap) |
| **Member of the lab segment at `10.10.10.1`** | Connects its physical Ethernet NIC to the Hyper-V External vSwitch and joins the flat L2 lab segment alongside DC01, WS01, and WO02. Reaches Lab-DC01 directly via ARP on the shared broadcast domain. | Translate or NAT between lab traffic and Wi-Fi traffic |

The discipline is enforced by **not configuring any of the routing behaviors that would blur the roles**. Windows ICS (Internet Connection Sharing) is not enabled. The Hyper-V host's Windows routing table has no static routes from the Wi-Fi side into the lab segment. The "Default Switch" Hyper-V built-in is not used (it provides NAT to internet, which is exactly what we don't want lab VMs to have). The Hyper-V External vSwitch the lab uses is bound to the physical Ethernet NIC — NOT to the Default Switch and NOT in NAT mode.

These are negative-space controls: the discipline is what's **not** configured. That's what makes the design defensible — the misconfigurations that would break the air-gap are all explicit operator actions, not defaults.

---

## The dumb switch — why a managed switch would be the wrong choice here

A standard homelab instinct is to install a managed switch (UniFi, Mikrotik, etc.) with VLANs to "do this right." For this design that's actually wrong. A managed switch:

- Introduces a configuration surface area that has to be hardened, audited, and STIG'd
- Provides VLAN-based separation that's a downgrade from physical separation (VLAN hopping attacks are real and documented)
- Adds a management interface that's another thing to firewall and password-rotate
- Would offer features (port-mirroring, syslog forwarding) that could accidentally bridge the staging and lab sides

A **dumb unmanaged switch** has none of those concerns. It's a layer-2 hub: it learns MAC addresses and forwards frames. It has no IP, no management interface, no configuration. The only thing it can do wrong is fail (and you replace it). Physical separation between the staging Wi-Fi NIC and the Ethernet NIC + dumb switch + WO02 is **stronger isolation than a VLAN-segmented managed switch would provide**, and it's defensible to a security reviewer in one sentence: "the switch has no management interface, no IP, no configuration."

This is the same reasoning a classified environment uses for hardware-isolated network drops: simpler isolation primitives have smaller attack surfaces.

---

## Transfer pattern — the only sanctioned way in or out of the lab

Files cross the air-gap only via deliberate operator action on the host. There is no automatic sync, no shared folder, no scheduled task, no agent. Three sanctioned transfer paths:

| Path | When to use | What it transfers |
|---|---|---|
| **Hyper-V Enhanced Session clipboard / drive redirect** | Operator-driven, file-by-file, into Lab-DC01 only | Small files (scripts, certs, configs); manual drag-and-drop |
| **PowerShell Direct** (`Copy-VMFile`, `Invoke-Command -VMName`) | Operator-driven, scripted, into Lab-DC01 only | Any size; works over the hypervisor channel without any network routing |
| **USB drive** (encrypted) | Operator-driven, host → WO02 | Anything that needs to land on WO02; physical token-passing |

What's deliberately **not** sanctioned:

- ❌ SMB share on the host that's reachable from lab VMs
- ❌ HTTP server on the host serving installers
- ❌ Shared Hyper-V folder mapping
- ❌ Windows Internet Connection Sharing
- ❌ Outbound proxy on the host that routes lab traffic to Wi-Fi

Each of those would create an automated background channel. The whole design relies on transfer being a deliberate operator action that produces an audit moment ("I copied X from staging to lab at time Y for purpose Z"). Background channels destroy that audit property.

This is also how classified development environments operate at scale — content arrives via deliberate review and signing, not via background sync.

---

## NIST control rationale (the reviewer-facing version)

| Control | How the topology satisfies it |
|---|---|
| **SC-7 (Boundary Protection)** | Two hardware boundaries: (1) the Hyper-V host's separation of Wi-Fi NIC and Ethernet NIC; (2) the dumb switch as a physical layer-2 isolation between WO02 and any other physical network. No layer-3 routing between zones; no proxied access from lab to internet. |
| **AC-4 (Information Flow Enforcement)** | All flows between the staging side and the lab side are operator-driven (Enhanced Session, PowerShell Direct, USB). No automated background flows. Each flow produces an explicit operator action that can be logged. |
| **CM-7 (Least Functionality)** | Hyper-V Default Switch (which provides NAT to internet) is deliberately not used for any lab VM. Internet Connection Sharing is not enabled. The Hyper-V host's routing table has no static routes that would connect the two sides. Each of these is a configuration NOT made — the design is enforced by negative space. |
| **SC-32 (System Partitioning) — partial / logical only** | The lab side is a **single flat L2 segment** with two logical IP ranges (`10.10.10.x` and `10.10.20.x`) sharing the same broadcast domain via the dumb switch. The IP grouping is an operator-mental-model partition, not an L2 partition. **True system partitioning** (VLANs on a managed switch, or a routed L3 boundary at the host) is a queued enhancement — design-documented here, not yet deployed. The honest portfolio framing is: "I documented what an SC-32-compliant partitioning would look like AND noted the current deployment is single-segment with logical IP grouping. The remediation path (managed switch + VLANs, or host-side routing) is the next iteration." This is consistent with the "designed vs deployed" honesty pattern used elsewhere in the portfolio (Phase 8 ZT scaffolds, two-tier PKI design vs single-tier deployment). |
| **PE-3 (Physical Access Control)** | The dumb switch and the physical workstation are in a single physical location under operator control. No external port-forward exposes the lab. No exposed service on any non-loopback interface of any lab VM. |
| **SC-39 (Process Isolation)** | Hyper-V provides type-1 hypervisor isolation between Lab-DC01 (guest VM) and the host. The host's staging-machine role runs in the host OS process space; the lab VMs run in their own VM process spaces. A compromise of the host's browser does not directly compromise Lab-DC01. |
| **CISA Zero-Trust Maturity Model — Networks pillar** | Partitioned segments with explicit ingress/egress rationale. Not "trust the network because it's behind a firewall"; rather, "every flow has been documented as a control decision." |

---

## What this design is honest about NOT being

For portfolio-honesty framing, the design is not:

- **A SCIF or classified facility.** It's a homelab with discipline modeled on classified-environment practice. There is no TEMPEST shielding, no physical SCIF construction, no facility security officer. The discipline is the deliverable; the physical security is residential.
- **A multi-zone enterprise.** A real enterprise would use managed switches with VLANs, a dedicated jump host, hardware HSMs, and a SIEM. This design demonstrates the trust-boundary thinking at homelab scale.
- **An ATO'd system.** The lab has no Authorization to Operate. The design rationale here is portfolio evidence, not an accreditation artifact.

What it IS:

- A **defensible isolation design** — every flow has a written rationale; every misconfiguration that would break the design is an explicit operator action, not a default
- A **scaled-down version of the staging-host pattern** — the same boundary engineering used at scale in defense and classified environments, applied to a homelab
- A **forcing function** — the discipline shapes operator habits (deliberate file transfers, explicit audit moments) that translate directly to enterprise practice

---

## How this design supports the rest of the lab

| Lab capability | How the topology enables it |
|---|---|
| Two-tier PKI (offline Root CA + Issuing CA) | The offline Root CA can be air-gapped indefinitely — it lives on a checkpointed VM that's only started during the signing ceremony, then immediately suspended. The host's staging side never touches it; the lab side reaches it only when the ceremony is active. |
| Smart-card-required AD logon on WO02 | WO02 is physically isolated from any internet path. Even if a phishing attack landed on the host's Wi-Fi side, it has no network path to reach WO02. |
| YubiKey enrollment ceremony | The enrollment workflow (RA + Issuer separation, `New-TokenEnrollment.ps1`) happens entirely inside the lab segment. The cert lands on the YubiKey via the lab network and is then physically carried (in the YubiKey, by the enrollee) to wherever it's used. |
| Phase 9 Azure VPN | The ONE sanctioned cloud egress, on a separate trust path. The Azure VPN tunnel is initiated FROM the host's Wi-Fi side, using the YubiKey-resident cert. The tunnel reaches into the Azure VNet, not back into the lab. This is the deliberate exception that proves the rule: cloud egress is a separate trust path with its own documented controls. |

---

## Operator habits the design enforces

| Habit | Why it's enforced |
|---|---|
| "Download here, transfer there" | The host is the only machine with internet. Everything else has to come from the host explicitly. There's no other path. |
| Audit-by-paper-trail | Each transfer is a deliberate operator action — a Hyper-V drag-drop, a `Copy-VMFile`, a USB plug. These are visible moments. Background sync would erase them. |
| "Nothing in the lab can call home" | Lab VMs have no path to the internet. No agent, no telemetry, no auto-update. Every change is deliberate. |
| "If you connect it, it goes to Do-Not-Publish" | Any file that touches the host's Wi-Fi side has to be triaged before it can land in the public repo. The Desktop\CAC\Do-Not-Publish folder is the artifact of this habit. |

---

## Future iterations

These are queued, not blocking:

- **Diagram in Visio / drawio format** rendered as PNG and embedded — the ASCII diagrams above carry the load, but a portfolio reviewer expects a visual. Would commit alongside this doc.
- **Out-of-band management** — when a second lab VM is added (Wazuh SIEM, syslog collector), document whether it lives on Lab Internal or Lab External and what control rationale shapes that decision.
- **Hardware token-based transfer** — formalize the USB encryption pattern (BitLocker To Go on the staging USB) into a small operator runbook.
- **Wireless lab segment** — currently no Wi-Fi inside the lab. If a mobile-test scenario ever needs to land (testing CAC on a mobile device), the Wi-Fi access point would terminate on Lab External, not on home Wi-Fi.

---

## Related documents

- [`Architecture/Blueprint.md`](Blueprint.md) — PKI design that runs on top of this topology
- [`Architecture/Azure-VPN-Guide.md`](Azure-VPN-Guide.md) — the one sanctioned cloud egress, with its own trust path
- [`Architecture/WatchGuard-IKEv2-VPN-Guide.md`](WatchGuard-IKEv2-VPN-Guide.md) — on-prem VPN pattern (design only)
- [`Architecture/RMF-Templates/SSP-Template.md`](RMF-Templates/SSP-Template.md) — SC-7, AC-4, CM-7 control mappings consolidated
- [`Architecture/Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md`](Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md) — what happens when transfer discipline slips
- [`Lab-Kit/START-HERE.md`](../Lab-Kit/START-HERE.md) — the build sequence that produces this topology
- [`Lab-Kit/LAB-DAY-CHECKLIST.md`](../Lab-Kit/LAB-DAY-CHECKLIST.md) — daily operator checklist that enforces the discipline

---

*ARCH-ICAM-014 · v1.2.x · "The shape of the network IS the security model."*
