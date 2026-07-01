# Phase 9B — On-Prem VPN Appliance (Dell OptiPlex 3080 Micro) ⏸️
### The physical counterpart to Phase 9's cloud VPN — a certificate-authenticated VPN gateway on real hardware, tied to your PKI and logging into Splunk

> **Status (v1.4, 2026-06-30): DEFERRED / NOT PLANNED.**
> Phase 9 (Azure VPN) shipped in v1.2 and closes the certificate-authenticated VPN story
> end-to-end ([`Architecture/Azure-VPN-Guide.md`](../Azure-VPN-Guide.md) — same YubiKey
> certificate unlocks AD logon and Azure P2S EAP-TLS, validated 2026-06-17). The on-prem
> hardware variant below remains as **design-only** for reference; the pattern is also
> covered architecturally in [`Architecture/WatchGuard-IKEv2-VPN-Guide.md`](../WatchGuard-IKEv2-VPN-Guide.md).
> No further development is planned for this lab. Preserved here as portfolio evidence of
> the design path that was considered.

*Built in the same phased, scripted style as the rest. This repurposes a refurb Dell 3080 Micro into a lab VPN appliance whose client/server certs come from **your existing two-tier PKI** (Phase 2 Issuing CA). It pairs with the cloud Phase 9: together you can show cert-based remote access done **both on-prem and in Azure**. Its logs also feed the **CySA+ lab's Splunk**, giving you real auth/VPN events to hunt instead of only synthetic data.*

---

## ⚠️ Scope & safety disclaimer (top of README too)
- **Lab appliance, not a production gateway.** Run it **behind your existing router**, not as the internet edge, unless you deliberately and carefully set it up as an edge firewall. Nothing sensitive routes through it.
- **Synthetic/lab data only**; keep it patched; lab network only.
- Document it as *"lab VPN appliance demonstrating certificate-based remote access integrated with a two-tier PKI"* — accurate framing, no production/ATO claim.

## Hardware reality check (read before buying parts)
- The 3080 Micro has **one onboard NIC.** A firewall/VPN ideally wants two interfaces. Pick one approach in 9B.1:
  - **Behind-router VPN server (simplest, recommended for a home lab)** — single NIC is fine; the box is just a VPN endpoint on your LAN, your router still does edge.
  - **Edge firewall+VPN** — add a second NIC (see below) for a WAN interface, or use **VLANs on the single NIC** with a managed switch.
- Specs: 10th-gen i3/i5, **16GB+ RAM** is ample, any small SSD. Low power draw — fine to leave running.

### Adding a second NIC (two routes)
The Micro form factor has no room for a standard PCIe card, so the two real options are:

| Route | What it is | Pros | Cons |
|---|---|---|---|
| **Dell Micro NIC module** (recommended if reasonably priced) | Dell's rear expansion module for the OptiPlex 3000/3080 Micro — a genuine internal second GbE port | True internal second NIC; tidy; appliance-grade reliability | Can be pricey/scarce — sometimes costs more than the used PC; confirm the **exact module for the 3080** (Dell has flex-IO variants) |
| **USB-to-Ethernet adapter** (cheap, easy) | External USB 3.0 → GbE / 2.5GbE dongle | $15–30; instant; fine for a lab WAN | A dangling dongle; USB NICs slightly less rock-solid than onboard for 24/7 routing |

**Chipset matters more than brand** — OPNsense/pfSense are **FreeBSD-based**, and that's where cheap NICs fail. Buy on chipset:
- **Best:** Intel chipset (USB or the Dell module if Intel-based)
- **Good USB:** Realtek **RTL8153** (USB GbE) or **RTL8156** (USB 2.5GbE) — solid FreeBSD/Linux support
- **Avoid:** no-name adapters and older **ASIX** USB chipsets (flaky BSD drivers)

**Verify before you commit:** check the chosen chipset against the **FreeBSD hardware/driver support** list (since OPNsense is FreeBSD). The Dell module and Intel/RTL8156 USB adapters all clear that bar; a $9 mystery dongle may not. If you go the **WireGuard-on-Linux** route instead, driver support is broader, but the same "buy a known chipset" rule still saves headaches.

**Recommendation:** genuine Dell Micro NIC module if the price is sane; otherwise an **Intel- or RTL8156-based USB 2.5GbE** adapter. Either gives you the WAN+LAN split for the edge-firewall build; neither is needed for the simpler behind-router VPN-server build.

## Platform choice (pick one in 9B.2)
| Option | Auth model | Best when | PKI fit |
|---|---|---|---|
| **OPNsense / pfSense** (recommended) | IKEv2/EAP-TLS or OpenVPN, **certificate** | You want a real firewall+VPN and cert auth | **Strong** — uses your PKI certs |
| **WireGuard on Linux** | Key pairs (not certs) | You want simple + fast | Weak — not cert/EAP-TLS based |
| **Windows Server RRAS + NPS** | Cert or AD/NPS | Mirror a Windows-shop VPN, reuse AD | Strong — AD + cert |

Default below assumes **OPNsense**, behind the router, OpenVPN/IKEv2 with EAP-TLS — the best learning + PKI-integration value.

---

## 9B.1 — Hardware & Network Prep  *(CM-8, CM-6)*
- `Document-Appliance.ps1` *(runs from your lab host)* — records the 3080's specs, NIC/MAC, assigned static lab IP into the asset inventory (same inventory discipline as the other labs)
- *Manual + checklist doc* `Appliance-Prep.md` — BIOS update, enable virtualization if needed, boot order, single-NIC decision (behind-router vs. USB-NIC vs. VLAN), and the static IP / DNS plan
- Snapshot/backup note: image the SSD after a clean install so you can reset to baseline

## 9B.2 — Base Install  *(CM-2, CM-6)*
- *Manual* — install **OPNsense** (or chosen platform) from USB; capture the install choices in `Install-Notes.md`
- `Set-ApplianceBaseline.ps1` *(lab-host helper)* — records the baseline config/version and stages a config backup into your repo's `appliance/` folder (config-as-evidence, mirroring your report-staging pattern)
- Harden: change defaults, disable WAN admin, strong admin creds, update to latest

## 9B.3 — PKI Integration (the headline tie-in)  *(IA-3, IA-5, SC-12, SC-8)*
The reason this beats a generic VPN box — the certs come from **your** CA chain.
- `New-VPNServerCert.ps1` — issues a **server/gateway certificate from your Issuing CA** (Phase 2) for the appliance; exports with chain
- `New-VPNClientCert.ps1` — issues **client auth certs from the Issuing CA** for lab user devices (reuses your enrollment pattern; SOD where you want it)
- `Export-CAChainForAppliance.ps1` — packages the Root+Issuing public chain to import into OPNsense as the trusted CA so it validates client certs against your PKI
- *Manual on appliance* — import server cert + CA chain; configure OpenVPN/IKEv2 to **require client certificate (EAP-TLS)**, no password fallback
- *Doc* `PKI-to-VPN.md` — the trust path: Root CA → Issuing CA → VPN server cert + client cert → tunnel established. This is your CAC lab's trust chain extended to a physical VPN.

## 9B.4 — VPN Profile & Client  *(AC-17)*
- `New-VPNClientProfile.ps1` — generates the client `.ovpn`/IKEv2 profile bound to the issued client cert; mirrors your existing `Deploy-VPNClient.ps1` style
- `Install-VPNClientProfile.ps1` — installs on a lab workstation
- `Test-VPNCertAuth.ps1` — connects, confirms **certificate-authenticated** tunnel (and that a device without a valid cert is refused), logs the result
- *Negative test:* attempt connect with a **revoked** cert → confirm the appliance rejects it (ties to your OCSP/CRL story; document whether the platform checks CRL)

## 9B.5 — Logging into Splunk (CySA+ tie-in)  *(AU-6, SI-4)*
Turns the appliance into a live detection source for the other lab.
- `Set-ApplianceSyslog.ps1` — configures OPNsense to forward firewall + VPN auth logs via **syslog** to the CySA+ lab's Splunk SIEM
- `New-VPNDetections.ps1` — Splunk saved searches for: repeated failed VPN auth, connection from an unexpected source, cert-rejection events, off-hours connections
- *Doc* `Appliance-Logs.md` — what the VPN/firewall events look like and what an analyst watches for (real data for Phases 4/6 of the CySA+ lab)

## 9B.6 — Validation & Evidence  *(CA-2, CA-7)*
- `Invoke-ApplianceValidation.ps1` — pass/fail: server cert from your CA in use, client cert required (no password path), revoked cert rejected, logs reaching Splunk, detections firing
- *Docs* — `Demo-Walkthrough-Appliance.md` (live demo + Q&A) and a config backup committed to `appliance/` as evidence

---

## Suggested order
9B.1 → 9B.2 stand it up. 9B.3 is the point — PKI-issued certs. 9B.4 proves cert auth (and rejection). 9B.5 wires it into Splunk so it also serves the CySA+ lab. 9B.6 validates and captures evidence.

## How it strengthens the portfolio
- **On-prem + cloud parity:** Phase 9 (Azure Conditional Access VPN) and Phase 9B (on-prem cert VPN) = "I implemented certificate-based remote access both ways."
- **PKI reaches real hardware:** your Root→Issuing chain now authenticates a physical VPN appliance — concrete proof the PKI isn't just a lab abstraction.
- **Cross-lab integration:** the appliance feeds real VPN/firewall logs into the CySA+ Splunk lab, so your two repos visibly connect.
- **Cheap and real:** a refurb micro + free OPNsense, behind your router — low cost, high signal.

## Honest framing note
Cert-revocation checking (CRL/OCSP) behavior varies by VPN platform — verify and document exactly what your chosen platform enforces rather than assuming it mirrors the Windows DC behavior in your CAC lab. And keep the box lab-only/behind-router unless you intentionally take on the edge-firewall hardening that an internet-facing appliance requires.
