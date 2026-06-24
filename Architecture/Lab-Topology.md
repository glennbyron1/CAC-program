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
│                                                                         │
│   ╔═══════════════════════════════════════════════════════════════╗     │
│   ║  Wi-Fi NIC                                                    ║     │
│   ║    • Pulls software, vendor portals, OS updates, Azure portal ║     │
│   ║    • NEVER bridged to the lab segment                         ║     │
│   ║    • NOT used by any guest VM directly                        ║     │
│   ╚═══════════════════════════════════════════════════════════════╝     │
│                                                                         │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │  Hyper-V Internal vSwitch  (host ↔ Lab-DC01 only, no NAT)     │     │
│   │    Lab-DC01 (Server 2022) — Issuing CA + Domain Controller    │     │
│   │      NIC 1: 10.10.10.10/24 — Lab Internal                     │     │
│   │      NIC 2: 10.10.20.10/24 — Lab External (bridged below)     │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│   ╔═══════════════════════════════════════════════════════════════╗     │
│   ║  Physical NIC — Lab External                                  ║     │
│   ║    • Hyper-V External vSwitch on this NIC                     ║     │
│   ║    • Lab-DC01's NIC 2 bridges to this through Hyper-V         ║     │
│   ║    • NEVER bridged to the Wi-Fi NIC                           ║     │
│   ╚═══════════════════════════════════════════════════════════════╝     │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ Ethernet cable
                               ▼
                  ┌────────────────────────────┐
                  │  Dumb unmanaged switch     │
                  │  (no VLANs, no management) │
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

**Reading this diagram:** the home Wi-Fi reaches the Hyper-V host. The Hyper-V host has *two NICs that never speak to each other* — the Wi-Fi NIC (staging side) and the physical Ethernet NIC (lab side). The lab-side NIC connects through a dumb unmanaged switch to WO02. Lab-DC01 lives on the host as a Hyper-V VM with two virtual NICs — one on a Hyper-V Internal vSwitch (host-only, no external connectivity) and one on a Hyper-V External vSwitch (bridged to the physical NIC, reachable from WO02 through the dumb switch).

The Wi-Fi NIC and the physical Ethernet NIC on the host are deliberately not bridged. Windows treats them as completely separate adapters. The host can resolve and reach Azure on the Wi-Fi side; it can resolve and reach Lab-DC01 + WO02 on the Ethernet side; but no packet routes between the two sides.

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
              └────────────────────┬───────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────────────┐
              │   Lab External   10.10.20.0/24             │
              │     • Hyper-V External vSwitch              │
              │     • Lab-DC01 NIC 2                        │
              │     • WO02 (10.10.20.30)                    │
              │     • No router, no DHCP server beyond      │
              │       Hyper-V default                       │
              └────────────────────┬───────────────────────┘
                                   │ Lab-DC01 acts as the
                                   │ bridge between subnets
                                   ▼
              ┌────────────────────────────────────────────┐
              │   Lab Internal   10.10.10.0/24             │
              │     • Hyper-V Internal vSwitch              │
              │     • Lab-DC01 NIC 1 (10.10.10.10)          │
              │     • Reserved for future lab VMs           │
              │       (database, syslog collector, etc.)    │
              └─────────────────────────────────────────────┘
```

**Why two lab subnets?** The original v1.0 build used a single flat subnet. After the smart-card GPO was applied with `scforceoption=1`, an enrollment workflow needs the workstation to reach the DC for Kerberos AND the workstation to be locked out of any non-DC service. The two-subnet design lets the lab simulate enterprise segmentation: the DC bridges both subnets, but workloads on either side don't see each other directly unless the DC explicitly forwards. This is the same pattern enterprises use to separate management traffic from user traffic.

---

## Network segments — what's where and what they touch

| Segment | Address | Devices | Internet egress | Notes |
|---|---|---|---|---|
| **Home Wi-Fi** | (resident's home network) | The Hyper-V host's Wi-Fi adapter only | ✅ Yes (residential ISP) | Used for: Windows Updates on the host, Azure Portal access, vendor portal downloads, repo cloning, software staging. **Never bridged to lab.** |
| **Lab External** | `10.10.20.0/24` | Hyper-V host Ethernet NIC, Hyper-V External vSwitch, Lab-DC01 NIC 2 (`10.10.20.10`), WO02 (`10.10.20.30`) | ❌ None | This is where the workstation lives. Smart-card GPO enforced. No Wi-Fi on WO02. No outbound to home Wi-Fi (host doesn't route). |
| **Lab Internal** | `10.10.10.0/24` | Lab-DC01 NIC 1 (`10.10.10.10`), Hyper-V Internal vSwitch | ❌ None | Reserved for future lab VMs (Wazuh SIEM, syslog collector, secondary DC, etc.) — air-gapped from both Wi-Fi AND from WO02 unless the DC explicitly forwards. |

**The single chokepoint:** the Hyper-V host. Information can move between the home Wi-Fi side and the lab side *only* via deliberate operator action on the host — drag-and-drop into a Hyper-V VM via Enhanced Session, PowerShell Direct file copy, or USB transfer. There is no automated background path.

---

## The Hyper-V host's three roles (and why they don't blur)

The host plays three roles that would, in a less disciplined design, get smeared together. Keeping them distinct is the point of the design:

| Role | What it does | What it must NOT do |
|---|---|---|
| **Staging machine** | Downloads software, browses to vendor portals, accesses Azure Portal, clones the repo, runs operator-only tools | Connect any of its downloaded content to lab VMs automatically (no shared folders that auto-sync; no bridged interfaces) |
| **Hypervisor** | Runs Lab-DC01 as a Gen2 VM, manages vSwitches, snapshots, checkpoints | Provide internet routing FROM the lab VMs back through its Wi-Fi (that would defeat the air-gap) |
| **Lab-side gateway to WO02** | Bridges the physical Ethernet NIC to the External vSwitch so WO02 (on the dumb switch) can reach Lab-DC01 | Translate or NAT between lab traffic and Wi-Fi traffic |

The discipline is enforced by **not configuring any of the routing behaviors that would blur the roles**. Windows ICS (Internet Connection Sharing) is not enabled. The Hyper-V host's Windows routing table has no static routes from the Wi-Fi side into the lab subnets. The "Default Switch" Hyper-V built-in is not used (it provides NAT to internet, which is exactly what we don't want lab VMs to have). Lab-DC01's NIC 1 is on an **Internal** vSwitch (host-only, no NAT, no external) — not a Default/External vSwitch.

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
| **SC-32 (System Partitioning)** | Lab Internal (`10.10.10.0/24`) and Lab External (`10.10.20.0/24`) are partitioned via separate Hyper-V vSwitches. Lab-DC01 is the only device with NICs on both — and that bridging is explicit, not implicit, with a documented control rationale (the DC needs to issue Kerberos tickets to workstations on the External subnet while having additional internal infrastructure on the Internal subnet). |
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
