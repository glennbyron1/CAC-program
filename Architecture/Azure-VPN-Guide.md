# Azure VPN with Lab-CA + YubiKey — Build Guide

**Document ID:** ARCH-ICAM-013
**Author:** Glenn Byron
**Frameworks:** NIST SP 800-53 IA-2, IA-2(11), IA-5(11), AC-2, AC-3, AC-17, SC-8, SC-12, SC-17, CM-3, CM-6, AU-6, SI-4 · DoD ZTRA Identity + Devices + Networks pillars · FIPS 201-3 · NIST SP 800-207 Zero Trust Architecture
**Pairs with:** [`Architecture/WatchGuard-IKEv2-VPN-Guide.md`](WatchGuard-IKEv2-VPN-Guide.md) (on-prem VPN gateway equivalent) | [`Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md`](../Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md) (where jdoe's smart card cert came from) | [`Demo-Walkthrough.md`](../Demo-Walkthrough.md) Step 5 (the slot this build closes)

> **What this is:** A complete build guide for Azure Point-to-Site VPN authenticated by the same YubiKey that unlocks Active Directory. Covers the full deploy → test → teardown cycle and the future Conditional Access / device compliance / visibility phases that extend it into a complete cloud Zero-Trust pattern.

> **The headline result:** Same physical YubiKey, same single cert in slot 9a, two authentication contexts — Windows AD logon via Kerberos PKINIT (Event 4768 Pre-Auth Type 16) AND Azure P2S VPN via EAP-TLS. The credential never leaves the hardware token; both authentications validate the same chain to the same Lab CA. From a Zero-Trust evidence perspective: one possession factor, one knowledge factor, used in two different clouds without ever provisioning a parallel "VPN credential."

---

## Scope & data disclaimer

- This lab runs entirely in **commercial Azure**, not Azure Government, GCC High, or any IL4/IL5 environment. The DoD IL5 tenant is restricted to the DoD and approved providers and **cannot** be procured for a personal lab — no attempt is made to access one.
- **Synthetic data only.** No CUI, no real PII, no production credentials, no real organizational names enter this lab.
- **Framing for documentation and interviews:** *"Commercial Azure demonstrating the same Microsoft Entra ID and EAP-TLS remote-access pattern used in Azure Government (DoD). Feature sets and endpoints differ between commercial and GCC High/IL5; the identity and access mechanics are equivalent."*
- This is a learning/portfolio lab, not an accredited system. It has no ATO and makes no compliance claim beyond demonstrating the architecture.

---

## Why Point-to-Site (P2S), not Site-to-Site

The lab's internet is typically a **phone hotspot or 5G Home connection** — both sit behind **carrier-grade NAT (CGNAT)**, which blocks *inbound* connections. So you cannot port-forward or run a classic inbound Site-to-Site (S2S) tunnel.

**P2S solves this:** the lab client dials *outbound* to the Azure VPN Gateway over an encrypted tunnel. No inbound ports, no public IP needed on your side. The lab reaches into an Azure virtual network (VNet); optionally Azure can reach back to lab subnets.

| Pattern | When to use | Lab fit |
|---|---|---|
| **P2S (this guide)** | Individual machine(s) connect out to Azure. Simplest. CGNAT-friendly. | ✅ Right call for a homelab |
| **S2S** | Whole network ↔ Azure via a gateway device. Needs a public IP / supported VPN device. | ❌ Doesn't fit CGNAT |

---

## Architecture — what you'll build

```
[YubiKey w/ jdoe's cert]                            [Azure tenant]
       |                                                   |
       | PIN unlocks the slot 9a cert                      |
       v                                                   |
[Lab workstation (WO02)]  --outbound P2S VPN-->  [Azure VPN Gateway]
   (on lab internet,            (encrypted IKEv2/         (in your subscription)
    CGNAT-friendly)              EAP-TLS)                       |
                                                                v
                                                          [Azure VNet 10.20.0.0/16]
                                                                |
                                                                v
                                                          [Azure VMs / subnets]
```

**Trust chain at connect time:**

1. Windows VPN client presents jdoe's cert (slot 9a on the YubiKey, Subject `CN=Jane Doe, OU=SmartCard-Pilot, DC=lab, DC=local`)
2. Azure VPN Gateway validates the cert chain
3. Chain root: `CN=LAB-CA, DC=lab, DC=local` — same root that signs AD logon certs
4. Azure trusts LAB-CA because we uploaded its public cert to the gateway's P2S configuration
5. EAP-TLS exchange succeeds → tunnel up → client assigned an IP from the P2S pool

---

## Cost discipline (read first)

The **Azure VPN Gateway is NOT free** and bills hourly **even when idle** — unlike a VM, you can't just "stop" it; it bills until you **delete** it.

| SKU | Cost | Notes |
|---|---|---|
| Basic | ~$0.04/hr ≈ **$27/month** | IKEv2 + cert auth supported. No OpenVPN. Microsoft is deprecating Basic — not recommended for new deployments. |
| **VpnGw1** (recommended) | ~$0.19/hr ≈ **$140/month** | Modern P2S auth, OpenVPN supported. The build below assumes this SKU. |
| VpnGw2+ | $0.49/hr+ | Production scale — not needed for a lab |

**The model for this lab is deploy → test → teardown in a single session.** A complete Phase 9 cycle costs a couple dollars. Leaving the gateway up unattended for a month costs $140. The teardown script (`Remove-AzResourceGroup -Name rg-cac-lab-phase9 -Force`) is committed to the repo so future-you cannot accidentally leave it running.

**Day-one guardrail:** activate a **Cost Management budget with email alerts** before provisioning anything (see Step 1B). Azure for Students halts at credit exhaustion rather than billing you, but the alert prevents mid-month surprise and is a good cloud-governance habit to be able to demonstrate.

---

## Prerequisites

| Item | Source / requirement |
|---|---|
| Azure subscription | Azure for Students ($100/12mo, no credit card) or personal PAYG |
| (Optional) M365 Developer tenant | Free; Entra ID P2 for future Conditional Access work (Step 9.3) |
| Lab workstation | WO02 with internet access; domain-joined to `lab.local` |
| Smart card cert on YubiKey | jdoe's cert in slot 9a, issued from LAB-CA via the v1.1 enrollment runbook |
| LAB-CA on Lab-DC01 | Internal Issuing CA from the v1.0 PKI build |
| Hyper-V access from the host | PowerShell Direct or RDP into Lab-DC01 to export the LAB-CA cert |

---

## Build sequence

### Step 1 — Resource Group + Budget Alert

**1A — Resource Group:** Azure portal → search `Resource groups` → **+ Create**
- Name: `rg-cac-lab-phase9`
- Region: closest to you (`East US 2` for Maryland)
- **Review + create**

**1B — Budget Alert ($20/month):** in the RG → left menu **Cost Management** → **Budgets** → **+ Add**
- Name: `budget-cac-lab-phase9`
- Reset period: Monthly
- Amount: `20`
- Alerts: two thresholds — `50%` and `100%` of budget, both Actual
- Alert recipients: your Azure account email

### Step 2 — Virtual Network + GatewaySubnet

Portal → **Virtual networks** → **+ Create**
- Resource group: `rg-cac-lab-phase9`
- Name: `vnet-cac-lab-phase9`
- Region: same as RG
- **IP Addresses tab:**
  - Address space: `10.20.0.0/16` (chosen to NOT overlap lab `10.10.x.x` or P2S `172.16.x.x`)
  - Subnet `snet-workloads`: `10.20.1.0/24` — for Azure-side test VMs
  - Subnet `GatewaySubnet`: `10.20.255.0/27` — **literal name required**; do NOT put VMs here

When adding `GatewaySubnet`, select **Subnet purpose: Virtual Network Gateway** in the dropdown — Azure auto-fills the name as `GatewaySubnet`.

### Step 3 — VPN Gateway (kick off — 30-45 min deploy)

Portal → **Virtual network gateways** → **+ Create**

The portal wants you to pick the VNet FIRST so it can auto-fill the resource group. Order:

1. **Subscription**: your Azure for Students subscription
2. **Name**: `vpngw-cac-lab-phase9`
3. **Region**: same as VNet
4. **Gateway type**: VPN
5. **VPN type**: Route-based
6. **SKU**: VpnGw1 (Generation 1)
7. **Virtual network**: select `vnet-cac-lab-phase9` — RG auto-fills
8. **Public IP**: Create new — `pip-cac-lab-phase9-vpngw`, **Standard** SKU, **Static** assignment
9. **Active-active mode**: Disabled · **Configure BGP**: Disabled
10. **Review + create** → **Create**

**Deploys for 30–45 minutes.** Do not wait — start the cert work in Step 4 while it runs.

### Step 4 — Export LAB-CA cert from Lab-DC01

Azure needs the public half of the trust anchor for jdoe's cert chain. The easiest path: PowerShell Direct from the Hyper-V host to Lab-DC01.

```powershell
# From host (Hyper-V host, NOT domain-joined per lab discipline) — open PSSession into Lab-DC01
$dcCred = Get-Credential -UserName "LAB\Administrator" -Message "Lab-DC01 password"
Enter-PSSession -VMName "Lab-DC01" -Credential $dcCred

# Inside Lab-DC01: discover the lab's self-signed Root CA in Trusted Root store
Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -match "Lab|LAB" -and $_.Issuer -eq $_.Subject } |
    Format-List Subject, Thumbprint, NotAfter

# Export LAB-CA cert as Base64 (replace subject with actual from above)
$labCaSubject = "CN=LAB-CA, DC=lab, DC=local"
$labCaCert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq $labCaSubject } | Select-Object -First 1
$labCaCert | Export-Certificate -FilePath "C:\Users\Public\LAB-CA.cer" -Type CERT
$b64 = [Convert]::ToBase64String($labCaCert.RawData)
$b64 | Out-File -FilePath "C:\Users\Public\LAB-CA-Base64.txt" -Encoding ASCII
Write-Host "Length: $($b64.Length) characters"
Write-Host $b64
Exit-PSSession
```

Expected output: ~1144 char Base64 string starting `MIIDVTCCAj2gAwIB...`. Copy this — you paste it into Azure in Step 6.

### Step 5 — Verify jdoe's cert is ready

On WO02 as jdoe, YubiKey inserted:

```powershell
# Same four-point acceptance check as the v1.1 enrollment runbook
certutil -scinfo
```

Look for:

| Check | Expected |
|---|---|
| Reader name | `Yubico YubiKey OTP+FIDO+CCID 0` — NOT `Microsoft Virtual Smart Card N` |
| Subject | `CN=Jane Doe, OU=SmartCard-Pilot, DC=lab, DC=local` |
| UPN | `Principal Name=jdoe@lab.local` in the SAN section |
| EKUs | Both `1.3.6.1.5.5.7.3.2 Client Authentication` AND `1.3.6.1.4.1.311.20.2.2 Smart Card Logon` |

Also confirm the cert is selectable in jdoe's session:

```powershell
Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.2" } |
    Format-List Subject, Issuer, Thumbprint, HasPrivateKey, NotAfter
```

`HasPrivateKey: True` for `CN=Jane Doe` confirms Windows sees the YubiKey-resident cert.

### Step 6 — Configure P2S on the gateway

When the gateway finishes deploying (Step 3 completion), Azure portal → `vpngw-cac-lab-phase9` → **Point-to-site configuration** → **Configure now**:

- **Address pool**: `172.16.0.0/24` (P2S client IPs — doesn't overlap lab or VNet)
- **Tunnel type**: `IKEv2 and OpenVPN (SSL)` — IKEv2 is what Windows native uses; OpenVPN is fallback
- **Authentication type**: Azure certificate
- **Root certificates** section:
  - Name: `LAB-CA`
  - Public certificate data: paste the Base64 from Step 4 (single line, no PEM headers)
- **Save** (takes ~2–5 min)

### Step 7 — Install the Azure VPN client on WO02

Download the VPN client zip from the P2S page (top of the page → **Download VPN client**).

> ⚠️ **Pitfall — and the fix:**
>
> The naive path (`WindowsAmd64/VpnClientSetupAmd64.exe` → Run as administrator) is blocked on WO02 by the `scforceoption=1` smart-card-required GPO. The elevation prompt asks for the **CardIssuer Virtual Smart Card PIN** (because CardIssuer is the local admin on WO02), and even with valid creds the installer leaves the system phonebook at 0 bytes — no VPN connection actually created.
>
> The **Azure VPN Client app from Microsoft Store** also fails — its cert picker doesn't enumerate YubiKey-resident certs, and hardcoding jdoe's thumbprint into the `azurevpnconfig.xml` `<clientauth><cert><hash>` element rejects with "client certificate must include an issuer" even when both hash and issuer are populated.
>
> **What works:** run the **`VpnProfileSetup.ps1`** script (inside the same zip, in `WindowsAmd64/` or `Generic/`) from elevated PowerShell. Microsoft's GUI installer is a wrapper around this script, but the script run directly under an elevated context sidesteps the smart-card-required elevation block.
>
> Also: set the connection's **Tunnel type to `Automatic`** instead of locking to IKEv2 — gives Windows fallback (SSTP, IKEv2, L2TP) and connects on whichever responds first.

### Step 8 — Connect

1. Insert YubiKey
2. Settings → Network & internet → VPN → click `vnet-cac-lab-phase9` → **Connect**
3. Windows Security dialog — cert picker shows all certs with Client Authentication EKU:
   - `CardIssuer`, `labtech`, `Jane Doe` (all chain to LAB-CA)
4. Select **`CN=Jane Doe`**
5. Windows prompts for **YubiKey PIN** (the same PIN jdoe uses for AD logon)
6. Tunnel up

### Step 9 — Verify the tunnel

```powershell
# Connection state
Get-VpnConnection -Name "vnet-cac-lab-phase9" |
    Format-List Name, ServerAddress, TunnelType, AuthenticationMethod, ConnectionStatus

# Assigned IP from P2S pool
ipconfig | Select-String "IPv4|PPP" -Context 0,1

# Route to Azure VNet via the tunnel
route print | Select-String "10.20"
```

Expected:
- `ConnectionStatus: Connected`
- IPv4 `172.16.0.2` (or .3, .4 — the next available from the P2S pool) on PPP adapter `vnet-cac-lab-phase9`
- Route for `10.20.0.0` via the VPN interface
- Tunnel type: IKEv2 (selected automatically by Windows)
- Authentication method: EAP (EAP-TLS via cert auth)

### Step 10 — Capture evidence

Captured in `Screenshots/`:

- `05-vpn-azure-eap-cert-auth-no-password.png` — Settings page: jdoe@lab.local, vnet-cac-lab-phase9 **Connected**, duration counter
- `05b-vpn-ipconfig-172-16-0-2.png` — `ipconfig` showing PPP adapter with IPv4 `172.16.0.2`
- `05c-vpn-caption-azure-p2s-eap-tls.png` — caption text describing the auth mechanism

These close slot 5 of [`Demo-Walkthrough.md`](../Demo-Walkthrough.md).

### Step 11 — Teardown (CRITICAL — do this same session)

The gateway bills hourly until deleted. Tear down immediately after capture:

```powershell
Connect-AzAccount
Remove-AzResourceGroup -Name "rg-cac-lab-phase9" -Force -AsJob
Get-Job   # check status
```

Or via portal: Resource group → Delete resource group → type name to confirm → check the "force delete" box for `Microsoft.Network/virtualNetworkGateways` → Delete.

Takes 5–10 minutes for the gateway to unwind. The budget alert remains in place even after RG deletion in case anything orphan-bills.

---

## Lessons learned (the failure path matters)

**Two install paths failed before the third one worked.** Worth capturing because anyone walking this same path will hit them.

| Path | Result | Reason |
|---|---|---|
| `VpnClientSetupAmd64.exe` → Run as administrator | System phonebook stayed 0 bytes after credentials accepted | Elevation prompt under `scforceoption=1` GPO requires the local admin (CardIssuer) to authenticate via smart card. Even with valid CardIssuer VSC PIN entered, the installer's silent execution didn't actually populate the phonebook. |
| Azure VPN Client app (Microsoft Store) + manual XML import | "Client certificate must include an issuer" on Save, even with both `<hash>` and `<issuer>` populated in the XML | The app's cert picker doesn't enumerate YubiKey-resident certs reliably. Hardcoding the thumbprint bypassed the picker but Save validation still failed — a known finicky behavior. |
| `VpnProfileSetup.ps1` from elevated PowerShell + Tunnel type Automatic | ✅ Works | The script bypasses the GUI elevation block. Automatic tunnel type gives Windows IKEv2/SSTP/L2TP fallback so it picks whichever the gateway responds to. |

The fix path is now baked into Step 7 above.

---

## PKI discovery (worth capturing for the Lab-CA story)

During Step 4 (LAB-CA cert export from Lab-DC01), the lab's PKI architecture surfaced an honest discrepancy between design and deployment:

- **Design** (per `Architecture/Blueprint.md`): two-tier — `Lab Root CA` (offline, air-gapped, 10-year, 4096-bit) signs `LAB-CA` (Issuing, on Lab-DC01, 5-year, 2048-bit)
- **Deployed reality** (per `Get-ChildItem Cert:\LocalMachine\Root` on Lab-DC01): `LAB-CA` is **self-signed** (Subject == Issuer), operating as its own root. The separate `Lab Root CA` cert exists (10-year, valid 2026→2036) but was not chained as the parent of LAB-CA in the deployed lab.
- The `Lab Root CA` cert has `basicConstraints CA:TRUE, pathlen:0`, which per RFC 5280 means it can only sign end-entity certs — it could not have signed a sub-CA anyway.

**For Phase 9, this is fine** — jdoe's smart card cert chains to LAB-CA, so uploading LAB-CA's public cert to Azure is what enables the trust path. But it's a real "designed two-tier, deployed single-tier" delta worth documenting for portfolio honesty.

A future remediation (Phase 9.x or a separate task) would be: regenerate the offline Root CA with `basicConstraints CA:TRUE, pathlen:1` (or no pathlen constraint), re-sign LAB-CA from it, install the new chain on Lab-DC01, and upload the new Root CA cert to Azure. That would bring deployment in line with the documented design.

---

## Control mapping

| Control | Implementation |
|---|---|
| IA-2 | Cert-based authentication enforced for the VPN; no password alternative on the tunnel |
| IA-2(11) | Hardware token authenticator (YubiKey slot 9a) |
| IA-5(11) | Authenticator binding — the same cert authenticates AD logon AND Azure VPN; verified via `certutil -scinfo` against the YubiKey reader, not a TPM VSC |
| AC-17 | Remote access via certificate-authenticated VPN |
| SC-8 | IKEv2 with AES-256 transport — confidentiality of remote sessions |
| SC-12 | Cryptographic key establishment — keys generated and bound to the hardware token |
| SC-17 | PKI certificates issued by an internal Enterprise CA (LAB-CA), uploaded as root of trust to the Azure VPN Gateway |
| CM-3 | Configuration change control — budget alert + teardown script committed BEFORE provisioning |
| AU-6 | Audit review — `certutil -scinfo` as a reader-level acceptance check (defends against Silent VSC Fallback; see `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`) |
| CISA ZTMM Identity pillar — Advanced | Phishing-resistant hardware-bound MFA, same token used on-prem AND in the cloud |
| CISA ZTMM Networks pillar — Initial | Tunnel established with cert auth; not yet wrapped in Conditional Access (Phase 9.3) |

---

## Future phases (designed, not yet built)

The build above implements Phase 9.0 (cost guardrail) and Phase 9.2 (PKI-authenticated P2S VPN). Three more phases extend this into a complete cloud Zero-Trust pattern:

### Phase 9.1 — Entra ID baseline (free)
- M365 Developer tenant (free, includes Entra ID P2)
- Synthetic test users mirroring lab RBAC
- MFA enrollment baseline before Conditional Access

### Phase 9.3 — Conditional Access (AC-2, AC-3, IA-2, AC-17)
The actual DoD pattern — where "VPN = you're in" becomes "policy decides on every connection":
- Require MFA for all cloud-app access
- Require compliant or hybrid-joined device for sensitive apps
- Block legacy authentication
- Optionally restrict sign-in to named locations
- What-If evaluation + live sign-in tests to verify the PE/PA decision trail

### Phase 9.4 — Device compliance signal (CM-6, IA-3, SI-4)
- Intune compliance policy (encryption on, AV healthy, min OS) — uses Intune trial if available
- Entra device registration so device state becomes a usable CA signal
- Result: CA can now require device be compliant — user AND device verified together, the core Zero Trust device requirement

### Phase 9.5 — Visibility & decisioning (AU-6, SI-4, IR-4)
- Entra sign-in / audit logs routed to Log Analytics
- Basic detections: failed CA evaluations, risky sign-ins, impossible-travel (where licensing allows)
- Export sign-in + CA decision logs into `Compliance-Reports/` as Before-ZT / After-ZT evidence

### Phase 9.6 — Validation + ongoing cost control
- Validator script extension: cert-auth VPN works, MFA enforced, CA policy blocks non-compliant device, sign-in logged with decision trail
- `Remove-AzureLabResources.ps1` formalized into the build kit
- SSP/POA&M updated with the cloud control mappings
- `Demo-Walkthrough-Cloud.md` with the "DoD is moving to this" narrative and hiring-manager Q&A

**Execution order:** 9.0 → 9.1 → 9.2 → 9.3 → 9.4 → 9.5 → 9.6 (teardown always last).

---

## How this connects to the rest of the lab

- **Phase 2 PKI** issues the VPN client certs (Step 4 + Step 5). Your Root → Issuing chain now reaches the cloud.
- **Phase 8.2 device trust** will be realized concretely as the Conditional Access device-compliance signal in Phase 9.4.
- **Phase 8.3/8.4 conditional access** will be implemented for real in Entra in Phase 9.3.
- **Phase 8.6 analytics** will extend to cloud sign-in decisioning in Phase 9.5.

---

## Honest framing

- **Cost discipline is the #1 gotcha** — delete the gateway when done. The build above includes the teardown command in Step 11.
- **Single-tier PKI deployment** (LAB-CA as root) — design says two-tier, reality is one-tier. Documented above. Phase 9 works either way.
- **Azure VPN Client GUI app vs PowerShell script** — GUI is finicky with YubiKey-resident certs. PowerShell script path is the working one. Lesson captured in Step 7.
- **Conditional Access continuous evaluation (CAE) and risk policies** are strongest with Entra ID P2 and specific licensing; some signals (full Identity Protection risk detections, complete Intune compliance) may be limited in a free developer/trial setup. Document what you demonstrate live versus what you design but can't fully license — that distinction is itself a sign of someone who understands the platform.
- **The Phase 9 build above is the v1.2 deliverable.** Phases 9.3–9.6 are designed (see above) but not yet built. That's an honest "what's shipped vs. what's designed" framing for the portfolio.

---

## Related artifacts

- [`Demo-Walkthrough.md`](../Demo-Walkthrough.md) Step 5 — closes slot 5 with the captures from Step 10
- [`Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md`](../Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md) (RUNBOOK-ICAM-001) — where jdoe's smart card cert came from
- [`Lab-Kit/Reference/MANUAL-Enrollment-Walkthrough.md`](../Lab-Kit/Reference/MANUAL-Enrollment-Walkthrough.md) (RUNBOOK-ICAM-002) — GUI-driven enrollment equivalent
- [`Lab-Kit/Reference/Card-Test-Matrix.md`](../Lab-Kit/Reference/Card-Test-Matrix.md) — hardware evaluation methodology; YubiKey row is the same card used here
- [`Architecture/Blueprint.md`](Blueprint.md) — two-tier PKI design (see "PKI discovery" section above for the deployment delta)
- [`Architecture/WatchGuard-IKEv2-VPN-Guide.md`](WatchGuard-IKEv2-VPN-Guide.md) — on-prem VPN gateway equivalent for the same trust chain (Phase 9B)
- [`Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`](Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md) — the acceptance check pattern this build inherits
- [`Architecture/RMF-Templates/SSP-Template.md`](RMF-Templates/SSP-Template.md) — System Security Plan, IA-2/IA-2(11)/AC-17/SC-8 mappings

---

*Build session: 2026-06-17 · ARCH-ICAM-013 · v1.2 deliverable*
