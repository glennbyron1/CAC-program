# Physical Lab Setup — Dell Hardware Path

**Author:** Glenn Byron
**Last Updated:** 2026-05-29

This guide covers setting up the CAC/PIV lab on physical Dell hardware instead of (or alongside) Hyper-V VMs. Everything in this path is production-realistic — the same hardware families, management tools, and network patterns you will encounter in a DoD environment.

---

## Hardware Checklist — Before You Wipe Anything

### 1. Pull the Service Tag

Every Dell machine has a service tag on the chassis (usually a white sticker on the rear or top). Go to [dell.com/support](https://www.dell.com/support) and enter it. Confirm:

- **Windows Server 2022 support** — listed under "Supported OS"
- **iDRAC version** — PowerEdge servers include iDRAC; desktops do not
- **Firmware updates available** — download Lifecycle Controller firmware before you begin; it makes OS installation much smoother

### 2. Check iDRAC Presence and Version

| iDRAC Version | Common PowerEdge Models | Notes |
|---------------|------------------------|-------|
| iDRAC 7 | R620, R720, R320 | Functional; web UI is older |
| iDRAC 8 | R730, R630, R430 | Solid; virtual console works well |
| iDRAC 9 | R740, R640, R540, R750+ | Best experience; REST API support |

iDRAC is a separate management processor — it runs even when the server is powered off. It gives you:
- Remote console (KVM over IP — keyboard, video, mouse without being in the room)
- Virtual media (mount an ISO from your workstation — no USB drive needed)
- Power control (power on/off/reset remotely)
- Hardware health alerts (fan failure, drive failure, temperature)
- Lifecycle Controller for firmware and OS installation

**Desktop note:** OptiPlex and Precision desktops do not have iDRAC. They are still good lab machines for workstation and member server roles — you just manage them directly.

### 3. Verify TPM

TPM 2.0 is required for BitLocker and device certificate testing. Check in BIOS setup (F2 at POST) under Security → TPM. Enable it if present but disabled. Most PowerEdge servers from the R720 generation onward and OptiPlex desktops from ~2015 onward have TPM 2.0.

### 4. Memory and Storage Minimums

| Role | RAM | Storage |
|------|-----|---------|
| Offline Root CA | 8 GB | 60 GB |
| Domain Controller + Issuing CA | 16 GB | 120 GB |
| Member Server / Workstation | 8 GB | 80 GB |

ECC RAM in PowerEdge servers is normal — Server 2022 supports it and prefers it.

### 5. NICs

- At least one NIC per machine — two is better on the DC (one for management, one for lab traffic)
- PowerEdge servers typically have 4 onboard 1GbE ports — more than enough
- A cheap managed switch (Cisco SG series, Netgear GS series) lets you set up VLANs between machines

---

## Recommended Role Assignment

Two topology options are documented here. Use whichever matches your hardware.

---

### Option A — All Physical

```
┌─────────────────────────────────────────────────────────────────┐
│                         LAB NETWORK                             │
│                                                                 │
│  ┌───────────────┐    ┌───────────────┐    ┌────────────────┐  │
│  │  PowerEdge    │    │  PowerEdge    │    │  Desktop or    │  │
│  │  Server A     │    │  Server B     │    │  Laptop        │  │
│  │               │    │               │    │                │  │
│  │  DC01         │    │  MEMBER01     │    │  WORKSTATION01 │  │
│  │  Domain Ctrl  │    │  Member Srvr  │    │  Domain-joined │  │
│  │  Issuing CA   │    │  SCAP/STIG    │    │  CAC logon     │  │
│  │  OCSP/CRL     │    │  testing      │    │  testing       │  │
│  └───────────────┘    └───────────────┘    └────────────────┘  │
│                                                                 │
│  ┌───────────────┐                                             │
│  │  ANY machine  │  ← Air-gapped (no network cable)           │
│  │  OFFLINECA    │    Used only to sign the Issuing CA cert    │
│  │  Offline Root │    Powered off when not in use             │
│  │  CA           │    Transfer via USB only                   │
│  └───────────────┘                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

### Option B — Hybrid (Recommended if you already have a working VM DC)

This is the practical starting point if you have an existing Hyper-V DC VM on your laptop and a mix of old physical machines. The VM and physical machines coexist on the same network via a bridged virtual switch.

```
┌──────────────────────────────────────────────────────────────────────┐
│                          ETHERNET SWITCH                             │
│                                                                      │
│  ┌─────────────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │  YOUR LAPTOP        │    │  Old Laptop  │    │  Old Laptop    │  │
│  │                     │    │  (physical)  │    │  (physical)    │  │
│  │  ┌───────────────┐  │    │              │    │                │  │
│  │  │  Hyper-V VM   │  │    │  MEMBER01    │    │  WORKSTATION01 │  │
│  │  │  DC01         │  │    │  Server 2022 │    │  Win 10/11     │  │
│  │  │  Domain Ctrl  │  │    │  SCAP/STIG   │    │  CAC logon     │  │
│  │  │  Issuing CA   │  │    │  testing     │    │  testing       │  │
│  │  └───────────────┘  │    │              │    │                │  │
│  │  (External vSwitch  │    └──────────────┘    └────────────────┘  │
│  │   on ethernet NIC)  │                                            │
│  └─────────────────────┘                                            │
│                                                                      │
│  ┌───────────────┐                                                   │
│  │ OptiPlex 3080 │ ← Air-gapped — NO network cable ever             │
│  │ Micro         │   Powers on only for the CA ceremony              │
│  │ OFFLINECA     │   Transfer Root CA cert+CRL via USB only         │
│  │ Offline Root  │   Powers off and stays off afterward             │
│  │ CA            │                                                   │
│  └───────────────┘                                                   │
└──────────────────────────────────────────────────────────────────────┘
```

#### Making the VM visible to physical machines

The critical step is switching the Hyper-V virtual switch from Internal or NAT to **External**, bound to your laptop's ethernet port. This puts the DC VM on the same broadcast domain as the physical machines on the switch.

**Steps:**

1. Connect your laptop to the switch with an ethernet cable
2. Open **Hyper-V Manager** on your laptop
3. Click **Virtual Switch Manager** in the right panel
4. Select your existing virtual switch → change type to **External**
5. In the dropdown, select your **ethernet adapter** (not WiFi — not "Microsoft Wi-Fi Direct Virtual Adapter")
6. Click Apply — brief network interruption is normal
7. The VM now gets an IP on your lab subnet and is reachable from physical machines

```powershell
# Verify from inside the DC VM — should show a lab-subnet IP, not 169.x or NAT
Get-NetIPAddress -AddressFamily IPv4 | Select-Object IPAddress, InterfaceAlias
```

#### What each machine does in the hybrid setup

| Machine | Role | OS | Notes |
|---------|------|----|-------|
| Your laptop (VM) | DC01 — Domain Controller + Issuing CA | Server 2022 (VM) | Keep existing VM; just change to External vSwitch |
| OptiPlex 3080 Micro | OFFLINECA — Offline Root CA | Server 2022 (physical) | Air-gapped; powers on for ceremony only |
| Old laptop 1 | MEMBER01 — Member server | Server 2022 (physical) | SCAP scanning, STIG checklist, AD testing |
| Old laptop 2 | WORKSTATION01 — Workstation | Windows 10 or 11 (physical) | CAC smart card logon, PIN, card removal lock |

#### Laptop NIC note

Most modern laptops have a single ethernet port or need a USB-C adapter. Either works — just confirm it shows up as a dedicated NIC in Device Manager before trying to bind it to the Hyper-V external switch. USB-C docking stations with ethernet also work if the dock's NIC shows up in Windows.

**Do not bridge WiFi.** Hyper-V will let you bind an external switch to a WiFi adapter but it is unreliable and not supported for domain traffic. Always use wired ethernet for the lab network.

---

---

### Option C — All Infrastructure on Laptop VMs, Physical Machines as Clients (Simplest)

Keep everything that requires Server 2022 infrastructure (DC, Issuing CA, OCSP, CRL) running as Hyper-V VMs on your laptop. Physical machines join the domain and pull certificates from the VM-hosted CA. The OptiPlex 3080 Micro still handles the Offline Root CA ceremony, then goes on the shelf.

This is the easiest path if your existing VM setup is already working — you change almost nothing about the infrastructure and just add physical clients.

```
┌──────────────────────────────────────────────────────────────────────┐
│                          ETHERNET SWITCH                             │
│                                                                      │
│  ┌──────────────────────────────┐                                    │
│  │  YOUR LAPTOP                 │                                    │
│  │                              │                                    │
│  │  ┌──────────┐  ┌──────────┐  │    ┌──────────────┐               │
│  │  │  VM      │  │  VM      │  │    │  Old Laptop  │               │
│  │  │  DC01    │  │  (opt.)  │  │    │  (physical)  │               │
│  │  │  Domain  │  │  Member  │  │    │              │               │
│  │  │  Ctrl +  │  │  Server  │  │    │  MEMBER01    │               │
│  │  │  Issuing │  │  VM      │  │    │  Server 2022 │               │
│  │  │  CA +    │  └──────────┘  │    │  SCAP/STIG   │               │
│  │  │  OCSP    │                │    │  testing     │               │
│  │  └──────────┘                │    └──────────────┘               │
│  │  (External vSwitch on        │                                    │
│  │   ethernet NIC)              │    ┌──────────────┐               │
│  └──────────────────────────────┘    │  Old Laptop  │               │
│                                      │  (physical)  │               │
│  ┌───────────────┐                   │              │               │
│  │ OptiPlex 3080 │ ← Air-gapped      │  WORKSTATION │               │
│  │ Micro         │   No network      │  Win 10/11   │               │
│  │ OFFLINECA     │   cable ever      │  CAC logon   │               │
│  │ Offline Root  │   USB only        │  testing     │               │
│  │ CA            │                   └──────────────┘               │
│  └───────────────┘                                                   │
└──────────────────────────────────────────────────────────────────────┘
```

#### What each machine does in Option C

| Machine | Role | OS | Notes |
|---------|------|----|-------|
| Your laptop (VM) | DC01 — Domain Controller + Issuing CA + OCSP | Server 2022 (VM) | All infrastructure stays here |
| OptiPlex 3080 Micro | OFFLINECA — Offline Root CA | Server 2022 (physical) | Air-gapped; ceremony only; then shelf |
| Old laptop 1 | MEMBER01 — Member server | Server 2022 (physical) | Domain-joined; SCAP scanning, STIG testing |
| Old laptop 2 | WORKSTATION01 — Workstation | Windows 10 or 11 (physical) | Domain-joined; CAC smart card logon testing |

#### What you need to do to make it work

1. **External vSwitch on your laptop** — same as Option B. Hyper-V Manager → Virtual Switch Manager → change to External → bind to your ethernet port. This is the only infrastructure change required.

2. **Verify VM is reachable from the switch** — plug your laptop into the switch, plug an old laptop into the switch, and ping the DC VM from the old laptop. If it responds, domain join will work.

3. **Domain-join the physical machines** — on each physical machine: System Properties → Computer Name → Change → Domain → enter `lab.local` (or whatever your domain is) → enter DC admin credentials. Reboot.

4. **Certificate autoenrollment** — once domain-joined, the physical machines pick up certificates from the Issuing CA automatically via Group Policy (if autoenrollment is configured). No manual steps needed per machine.

#### One thing to be aware of

If your laptop goes to sleep, closes the lid, or the VMs stop running, the physical machines lose domain connectivity until the VMs come back up. This is normal for a lab — just keep the laptop awake and VMs running during test sessions.

To prevent the laptop from sleeping while VMs are active:
```powershell
# Run on your laptop — prevents sleep while plugged in
powercfg /change standby-timeout-ac 0
```

---

---

### Option D — Everything on the Laptop (Full VM Lab)

Run all four roles as Hyper-V VMs on your laptop. No physical machines required. The Offline Root CA is isolated using a Hyper-V **Private virtual switch** to simulate the air-gap. Physical machines can be added later as clients whenever you're ready — the infrastructure doesn't change.

This is the right starting point if you want to get the full lab running before you have physical hardware sorted out.

```
┌──────────────────────────────────────────────────────────────────────┐
│  YOUR LAPTOP — ALL HYPER-V VMs                                       │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  PRIVATE vSwitch (isolated — no external network access)    │     │
│  │                                                             │     │
│  │   ┌─────────────────────┐                                   │     │
│  │   │  VM: OFFLINECA      │  ← Powered OFF after ceremony     │     │
│  │   │  Offline Root CA    │    Only NIC is on Private switch   │     │
│  │   │  (air-gap simulated)│    Never touches External switch   │     │
│  │   └─────────────────────┘                                   │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  EXTERNAL vSwitch (laptop ethernet → lab network)           │     │
│  │                                                             │     │
│  │   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │     │
│  │   │  VM: DC01    │   │  VM:         │   │  VM:         │   │     │
│  │   │  Domain Ctrl │   │  MEMBER01    │   │  WORKSTATION │   │     │
│  │   │  Issuing CA  │   │  Server 2022 │   │  Win 10/11   │   │     │
│  │   │  OCSP/CRL    │   │  SCAP/STIG   │   │  CAC logon   │   │     │
│  │   └──────────────┘   └──────────────┘   └──────────────┘   │     │
│  └─────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
```

#### Setting up the Private vSwitch for the Offline Root CA

1. Open **Hyper-V Manager** on your laptop
2. Click **Virtual Switch Manager**
3. Select **New virtual network switch** → choose **Private** → click Create Virtual Switch
4. Name it something clear: `OfflineCA-Isolated`
5. On the Offline Root CA VM settings → Network Adapter → connect to `OfflineCA-Isolated`
6. Never add an External NIC to this VM

The Private switch has zero path to the physical network, internet, or any other VM on the External switch. It is network-isolated by design.

#### The CA ceremony with a Private vSwitch

During the ceremony you need to transfer the Issuing CA certificate request from DC01 to the Offline Root CA, and then transfer the signed cert and CRL back. Since they're on different switches you do this via a shared folder or a second NIC — the cleanest method for a lab is a temporary Internal switch:

```
Step 1 — Create a temporary Internal vSwitch named "CA-Transfer"
Step 2 — Add a second NIC on the Offline Root CA VM → connect to "CA-Transfer"
Step 3 — Add a second NIC on DC01 → connect to "CA-Transfer"
Step 4 — Set static IPs on both VMs on the CA-Transfer NICs (e.g., 172.16.0.1 and 172.16.0.2)
Step 5 — Transfer the cert request file, sign it, copy back the signed cert + CRL
Step 6 — Remove the CA-Transfer NICs from both VMs
Step 7 — Delete or disable the CA-Transfer vSwitch
Step 8 — Power off the Offline Root CA VM — leave it off
```

Alternatively, you can use the Hyper-V **guest file copy** feature (PowerShell Direct) to move files between VMs without any network connection at all:

```powershell
# Copy cert request from DC01 into the Offline Root CA VM
Copy-VMFile -VMName "OFFLINECA" -SourcePath "C:\CARequest\IssuingCA.req" `
            -DestinationPath "C:\CARequest\IssuingCA.req" -CreateFullPath -FileSource Host

# Copy signed cert back out to host, then into DC01
Copy-Item -Path "\\OFFLINECA\C$\CA\IssuingCA.crt" -Destination "C:\Temp\"
Copy-VMFile -VMName "DC01" -SourcePath "C:\Temp\IssuingCA.crt" `
            -DestinationPath "C:\Temp\IssuingCA.crt" -CreateFullPath -FileSource Host
```

PowerShell Direct works through the hypervisor layer, not the network — the VM doesn't need any NIC at all. This is the cleanest simulation of physical USB transfer in a VM environment.

#### What to tell an interviewer

> "In a production environment, the Offline Root CA runs on air-gapped physical hardware stored in a secure location — no network interfaces, accessed only for CA ceremonies. In my lab I simulated this using a Hyper-V Private virtual switch, which has no path to the physical network or other VMs, and PowerShell Direct for file transfer instead of USB. The VM stays powered off between ceremonies."

That's accurate, honest, and shows you understand why air-gapping matters — which is what the question is actually testing.

#### VM resource requirements for Option D

| VM | RAM | vCPUs | Disk |
|----|-----|-------|------|
| OFFLINECA | 2 GB | 1 | 40 GB |
| DC01 | 4 GB | 2 | 80 GB |
| MEMBER01 | 4 GB | 2 | 60 GB |
| WORKSTATION01 | 4 GB | 2 | 60 GB |
| **Total** | **14 GB** | **7** | **240 GB** |

16 GB RAM in the laptop is workable. 32 GB is comfortable. You can run OFFLINECA and WORKSTATION01 with Dynamic Memory and let them share RAM since they're rarely active at the same time.

---

**Offline Root CA — all options:** whether physical (OptiPlex 3080 Micro) or virtual (Private vSwitch), the principle is the same. It powers on for the ceremony, stays isolated from all networks, and powers off when done. The VM approach is a legitimate lab simulation; physical hardware is production practice.

---

## iDRAC Initial Configuration

### Step 1: Access the iDRAC Web Interface

By default iDRAC gets a DHCP address on its dedicated management port (the port labeled "iDRAC" on the back, separate from the regular NICs). Check your router's DHCP table to find it, or connect directly with a laptop on a crossover cable.

Default credentials (change these immediately):
- Username: `root`
- Password: `calvin` (older iDRAC 7/8) or printed on the pull tag inside the chassis (iDRAC 9)

Navigate to `https://<iDRAC-IP>` in a browser. Accept the self-signed cert warning.

### Step 2: Set a Static IP

**iDRAC 9:** iDRAC Settings → Network → IPv4 Settings → set static IP, subnet, gateway.
**iDRAC 7/8:** iDRAC Settings → Network/Security → Network → uncheck DHCP, set static IP.

Use an IP outside your DHCP range so it never conflicts. Example: if your lab is `192.168.1.x` and DHCP hands out `.100–.200`, put iDRAC on `.20`–`.30`.

### Step 3: Change the Default Password

iDRAC Settings → Users → root → change password. Use a strong password and record it somewhere safe. DoD guidance (STIG) requires this before any other configuration.

### Step 4: Update Firmware

**Lifecycle Controller method (recommended):**
1. Boot the server and press F10 at POST to enter Lifecycle Controller
2. Go to Firmware Update → Launch Firmware Update
3. Use FTP or HTTPS to pull updates from Dell's catalog

**Manual method:**
1. Download the iDRAC firmware `.exe` from dell.com/support using the service tag
2. Upload via iDRAC web UI: Maintenance → System Update → Manual Update

Update iDRAC firmware before the OS — some older iDRAC versions have bugs that interfere with virtual console during installation.

### Step 5: Mount the Server 2022 ISO

1. Download the Windows Server 2022 ISO from Microsoft's evaluation center
2. In the iDRAC web UI: Configuration → Virtual Media → Connect Virtual Media
3. Browse to the ISO on your workstation
4. Boot the server and press F11 for boot menu → Virtual CD/DVD

The server installs as if a physical disc is inserted — no USB drive needed.

### Step 6: Key iDRAC Features to Learn

| Feature | Where to Find It | Why It Matters |
|---------|-----------------|----------------|
| Virtual Console | Dashboard → Launch | Remote KVM — manage without being in the room |
| Virtual Media | Configuration → Virtual Media | Mount ISOs remotely |
| Hardware Health | Dashboard → Hardware Health | Fan, temp, drive status |
| Power Control | Dashboard → Power | Remote on/off/reset/graceful shutdown |
| System Event Log | Maintenance → System Event Log | Hardware fault history |
| RACADM CLI | SSH to iDRAC IP | Scriptable management — used in DoD automation |

**RACADM** is the command-line interface for iDRAC. DoD sysadmins use it to configure multiple servers from scripts. Example:
```powershell
# SSH to iDRAC and run RACADM commands
ssh root@192.168.1.20
racadm get iDRAC.Network
racadm set iDRAC.Users.2.Password "NewPassword123!"
```

---

## Network Setup — Physical Switch

### Minimum Setup (Single Switch)

Any unmanaged switch works for basic connectivity. Plug all machines in and they can communicate on the same subnet.

### Recommended Setup (Managed Switch + VLANs)

A managed switch lets you segment traffic — this is how DoD environments are built and it makes microsegmentation testing realistic.

**Suggested VLANs for the lab:**

| VLAN ID | Name | Purpose |
|---------|------|---------|
| 1 | Management | iDRAC interfaces, switch management |
| 10 | Lab-LAN | DC01, member servers, workstations — normal lab traffic |
| 20 | OT-Sim | Future: simulated OT/SCADA segment (isolated) |
| 99 | Quarantine | Default untagged — nothing trusted here |

Budget managed switches that work well for this:
- **Cisco SG series** (SG110, SG250, SG350) — common in small DoD shops, good for resume
- **Netgear GS series** (GS308E, GS724T) — cheaper, still VLAN-capable
- **TP-Link TL-SG** series — budget option, adequate for lab use

---

## OS Installation on Physical Hardware

### Server 2022 vs. Server 2025

| Factor | Server 2022 | Server 2025 |
|--------|-------------|-------------|
| DoD adoption | Current standard in most shops | Emerging — not yet widespread |
| Older Dell support | Excellent (R620 onward) | Limited on pre-2018 hardware |
| STIG availability | Full DISA STIG published | STIG in progress |
| Recommendation | **Use this for the lab** | Good to know, not required yet |

### Post-Install Steps (Same as VM Path)

After OS installation, the physical path merges with the existing lab scripts:

1. **Skip** `Lab-Kit/01-HyperV-Host/` — those are VM-only
2. **Start here:** `Lab-Kit/01-HyperV-Host/Set-VMPostConfig.ps1` covers post-OS config that also applies to physical machines — rename the computer, set static IP, configure Windows Update
3. **Continue normally** from `Lab-Kit/02-OfflineRootCA/` onward — all scripts are hardware-agnostic

### Dell OpenManage (Recommended)

Install Dell OpenManage Server Administrator (OMSA) on each PowerEdge after the OS is up. It gives you:
- Hardware health monitoring from within Windows (not just iDRAC)
- RAID controller management
- Predictive failure alerts
- Integration with iDRAC alerts

Download from dell.com/support using the service tag. Install the "Server Administrator Managed Node" component.

---

## Physical Lab — Day One Checklist

```
[ ] Pull service tags and confirm Server 2022 support for each machine
[ ] Update iDRAC firmware on all PowerEdge servers
[ ] Set static IPs and change default passwords on all iDRAC interfaces
[ ] Download Server 2022 evaluation ISO
[ ] Install Server 2022 on DC01 (via iDRAC virtual media or USB)
[ ] Install Server 2022 on MEMBER01
[ ] Install desktop OS (Windows 10/11 Pro or Server) on WORKSTATION01
[ ] Plug in managed switch; configure VLANs if using them
[ ] Install Dell OpenManage on each server
[ ] Verify TPM 2.0 is enabled on all machines
[ ] Take baseline photos of hardware setup (good for portfolio)
[ ] Proceed to Lab-Kit/02-OfflineRootCA/ — the script path from here is identical
```

---

## iDRAC STIG Notes

DISA publishes a STIG for iDRAC 9. Key items DoD shops enforce:

- Change default `root` password immediately (V-225472)
- Disable Telnet — use SSH only (V-225480)
- Set session timeout to 15 minutes or less (V-225483)
- Enable TLS 1.2 or higher only; disable TLS 1.0 and 1.1 (V-225490)
- Enable audit logging for all iDRAC login attempts (V-225496)
- Restrict iDRAC access to the management VLAN only

Applying these is good lab practice and something you can document in your portfolio as operational security hardening.

---

## What This Adds to Your Portfolio

| Skill Demonstrated | How |
|-------------------|-----|
| iDRAC / server management | Configured remote management on real PowerEdge hardware |
| Physical network segmentation | VLANs on a managed switch, not just virtual switches |
| Bare-metal OS deployment | Server 2022 installed via iDRAC virtual media |
| Hardware-level security | TPM verified, iDRAC STIG items applied |
| DoD-realistic environment | Same hardware families and management tools used on base |

---

*Next step after hardware is ready: `Lab-Kit/LAB-DAY-CHECKLIST.md` — pick up at the Offline Root CA ceremony.*
*iDRAC STIG: search "iDRAC9" at [public.cyber.mil/stigs](https://public.cyber.mil/stigs/)*
*Dell OpenManage download: [dell.com/support](https://www.dell.com/support) → Drivers & Downloads → search "OpenManage Server Administrator"*
