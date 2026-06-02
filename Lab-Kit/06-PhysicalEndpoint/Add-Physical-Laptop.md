# Adding a Physical Laptop to the Lab Domain

**Author:** Glenn Byron
**Purpose:** Step-by-step guide for domain-joining a spare physical laptop (Windows 11,
TPM 2.0), enrolling a Virtual Smart Card, running SCAP scans, and capturing real demo
screenshots. This is the primary source of portfolio-grade evidence for the lab.

> **Prerequisites:** Lab VMs must be running (DC01 operational, smart card GPO applied).
> The laptop must be a spare/dedicated machine — never domain-join a daily driver.

---

## Before You Start — Checklist

- [x] Laptop is a spare machine (not your daily driver)
- [x] **Windows 11 Pro or Enterprise** confirmed (`winver`)
      > Windows 11 **Home** cannot join a domain. Must be Pro or Enterprise.
- [x] **TPM 2.0** confirmed (`tpm.msc` → "The TPM is ready for use")
- [x] Lab VMs running — DC01 and WS01 up, smart card GPO active
- [x] VM snapshots taken (Step 0 below — do this before any network changes)
- [ ] USB staging folder built on the Hyper-V host:
      ```powershell
      .\Lab-Kit\06-PhysicalEndpoint\Stage-LaptopUSB.ps1 `
          -RootCACertPath "C:\CA-Export\Lab-RootCA.cer" `
          -Zip
      ```
      Produces a single timestamped folder on your Desktop containing the SCC
      installer, Windows 11 SCAP content, Root CA cert, walkthrough, and VPN
      client — drag to your USB drive in one move.

---

## Step 0 — Pre-Flight: Snapshot VMs and Check PKI Health

**Take a checkpoint of DC01 and WS01 before touching the network.**
Changing to an External switch modifies DC01's adapter — you want a rollback point.

```powershell
# On the Hyper-V host
.\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1 -Label "05-Pre-Laptop-Network"
```

**Run PKI health check to confirm everything is green before adding a new endpoint:**

```powershell
# On DC01 (via Hyper-V console or PowerShell Direct)
.\Lab-Kit\03-DomainController\Monitor-PKIHealth.ps1
```

All checks should pass (CRL valid, OCSP reachable, no certs near expiry) before proceeding.

---

## Step 1 — Network: Create an External Virtual Switch in Hyper-V

An External virtual switch connects the Hyper-V VMs directly to your physical NIC,
putting them on the same network as your dumb switch. The result:

```
Laptop → dumb switch → Hyper-V host physical NIC → External vSwitch → DC01 / WS01
```

**On your Hyper-V host, run in PowerShell as Administrator:**

```powershell
# Find your physical NIC name
Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription

# Create the External virtual switch (replace "Ethernet" with your NIC name)
New-VMSwitch -Name "Lab-External" -NetAdapterName "Ethernet" -AllowManagementOS $true
```

**Connect BOTH DC01 and WS01 to the External switch:**
1. Hyper-V Manager → right-click **Lab-DC01** → Settings → Network Adapter
2. Change switch from `Lab-Internal` to `Lab-External` → OK
3. Repeat for **Lab-Workstation01**

**Set a static IP on DC01** (inside the DC01 console):

```powershell
# Run inside DC01
Get-NetAdapter   # find the adapter name

New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.20.10 `
                 -PrefixLength 24 -DefaultGateway 10.10.20.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1
```

> **Lab IP plan (current state, see `Lab-Kit/Reference/ONBOARDING.md`):**
> - `10.10.10.0/24` — LabInternal switch (VM↔VM management): DC01 NIC1 `.10`, WS01 `.20`, host `.1`
> - `10.10.20.0/24` — External switch (host↔physical laptop): DC01 NIC2 `.10`, WO02 `.30`, host `.1`

**On the laptop** — set DNS to point at DC01:
- Open Network Settings → IPv4 → DNS: `10.10.20.10`

**Verify connectivity from the laptop:**

```powershell
ping 10.10.20.10                          # DC01 External NIC should reply
nslookup lab.local 10.10.20.10            # Should resolve lab.local
```

If ping fails: check Windows Firewall on DC01 allows ICMP, and confirm both are on
the same subnet.

---

## Step 2 — Domain Join the Laptop

```powershell
# Run on the laptop as local Administrator
Add-Computer -DomainName "lab.local" `
             -Credential (Get-Credential) `   # enter lab\Administrator credentials
             -Restart
```

After reboot, log in with `lab\Administrator` using password — smart card enforcement
hasn't been applied to the laptop yet, so password still works at this point.

**Verify domain join:**

```powershell
(Get-WmiObject Win32_ComputerSystem).Domain   # Should return lab.local
```

**Check the computer account OU** — the GPO won't apply if the laptop lands in the
wrong OU. On DC01, verify:

```powershell
# Run on DC01
Get-ADComputer -Filter {Name -eq "LAPTOP-HOSTNAME"} | Select-Object DistinguishedName
```

The laptop should be in the same OU as Lab-Workstation01. If it landed in `CN=Computers`
instead, move it:

```powershell
# Move to the correct OU (match your lab's OU structure)
Move-ADObject -Identity "CN=LAPTOP-HOSTNAME,CN=Computers,DC=lab,DC=local" `
              -TargetPath "OU=Workstations,DC=lab,DC=local"
```

---

## Step 3 — Apply Smart Card GPO to the Laptop

```powershell
# On the laptop
gpupdate /force

# Confirm GPO applied
gpresult /r | Select-String "SmartCard\|scforce"

# Verify registry values (scforceoption should be 1, ScRemoveOption should be 1)
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" |
    Select-Object scforceoption, ScRemoveOption
```

> **Critical:** `scforceoption=1` belongs ONLY on workstation GPOs — never on DC01.
> If you see it on DC01 it locks all password-based login including the Hyper-V console.

---

## Step 4 — Create Virtual Smart Card and Enroll Certificate

**Create the Virtual Smart Card on the laptop (TPM 2.0 confirmed):**

```powershell
# Run on the laptop as Administrator
tpmvscmgr.exe create /name "CAC Lab VSC" /pin prompt /adminkey random /generate

# Verify it was created — should show a smart card reader
certutil -scinfo
```

**Enroll the certificate** — run on DC01 as Administrator, targeting the laptop user:

```powershell
# RA phase — run as Registration Authority account
.\New-TokenEnrollment.ps1 -Phase RA -UserName "labuser"

# Issuer phase — run as a DIFFERENT account (enforces AC-5 separation of duties)
.\New-TokenEnrollment.ps1 -Phase Issuer -UserName "labuser"
```

**Verify the certificate landed on the laptop:**

```powershell
# On the laptop
Get-ChildItem Cert:\CurrentUser\My | Where-Object {
    $_.EnhancedKeyUsageList -match "Smart Card Logon"
} | Select-Object Subject, NotAfter, Thumbprint
```

---

## Step 5 — Test Smart Card Logon and Take Screenshots

This is the payoff — real hardware, not a VM. Take all screenshots now.

1. Lock the screen: **Win+L**
2. The login screen should show **only** the smart card PIN prompt — no password field
3. Enter your PIN → confirm you reach the desktop
4. Remove the card (or run `tpmvscmgr.exe remove` if using VSC) — session locks within 2 seconds

**📸 Screenshots to capture:**

| # | What to capture | How |
|---|----------------|-----|
| 1 | Lock screen — smart card prompt only, no password field | Screenshot before PIN entry |
| 2 | PIN entry screen — certificate subject (CN=labuser) visible | Screenshot during PIN prompt |
| 3 | Session lock on card removal | Screenshot showing locked screen after removal |
| 4 | Event 4768 with Pre-Auth Type 16 | Event Viewer → Windows Logs → Security → filter 4768 |
| 5 | VPN connected (Step 7) | Screenshot of VPN status |
| 6 | PKI health monitor green dashboard | Run Monitor-PKIHealth.ps1 and screenshot |

**Capture Event 4768 on DC01:**

```powershell
# On DC01 — filter for the smart card Kerberos pre-auth event
Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4768
} | Where-Object { $_.Message -match "Pre-Authentication Type.*16" } |
    Select-Object -First 3 | Format-List TimeCreated, Message
```

Pre-Auth Type 16 = Kerberos PKINIT with a certificate. This is the proof that smart
card authentication worked at the protocol level.

---

## Step 6 — Download Windows 11 STIG Benchmark and Run SCAP Scan

**Download the Windows 11 STIG benchmark** (if not already in FedCompliance-Tools):

```powershell
# On the Hyper-V host
.\Tools-Kit\Download-FedCompliance-Kit.ps1
# Select the Windows 11 STIG content pack — downloads to FedCompliance-Tools\03-SCAP-Content\
```

Transfer the SCC installer and benchmark to the laptop (USB or network share).

**On the laptop:**
1. Install SCC 5.10.2
2. Launch SCC → Options → check **"Run content regardless of applicability"** (CPE override)
3. Select benchmark: **`MS_Windows_11_STIG-<version>`** (current DISA release is V1R7+ — NOT the Server 2022 one)
4. Run scan → export HTML and XCCDF XML

**Stage results in the repo:**

```powershell
# On the Hyper-V host — create laptop evidence folders
New-Item -ItemType Directory "Compliance-Reports\Laptop\Before-SmartCard" -Force
New-Item -ItemType Directory "Compliance-Reports\Laptop\After-SmartCard"  -Force

# Copy scan output into the appropriate folder
# Before = scan before smart card GPO applied
# After  = scan after GPO + VSC enrollment
```

---

## Step 7 — Test VPN from the Laptop

The laptop on the physical network is the ideal "remote user" test client — it's
connecting from outside the Hyper-V internal switch, just like a real remote user would.

```powershell
# On the laptop — install the IKEv2 VPN profile
.\Lab-Kit\04-Workstation\Deploy-VPNClient.ps1

# Connect — should authenticate with the VSC certificate, no password prompt
```

**📸 Screenshot:** VPN connected status showing EAP-TLS / certificate authentication.
Confirm no password was entered — the cert did the work.

---

## Evidence Summary

| # | Item | Destination | Status |
|---|------|-------------|--------|
| 1 | Lock screen (smart card prompt, no password) | `Demo-Walkthrough.md` | ⬜ |
| 2 | PIN entry (cert subject visible) | `Demo-Walkthrough.md` | ⬜ |
| 3 | Session lock on card removal | `Demo-Walkthrough.md` | ⬜ |
| 4 | Event 4768 Pre-Auth Type 16 | `Demo-Walkthrough.md` | ⬜ |
| 5 | VPN connected via EAP-TLS | `Demo-Walkthrough.md` | ⬜ |
| 6 | PKI health monitor green dashboard | `Demo-Walkthrough.md` | ⬜ |
| 7 | SCAP SCC scan — Windows 11 STIG | `Compliance-Reports\Laptop\` | ⬜ |

---

## Troubleshooting

**Windows 11 Home — can't join domain:** Must be Pro or Enterprise. Home edition does
not support Active Directory domain join. Upgrade the license or get a different machine.

**Can't ping DC01 after switching to External:** Check DC01 got a valid IP on the
physical network (`Get-NetIPAddress` inside DC01). Check Windows Firewall allows ICMP.
Confirm both machines are on the same subnet (`10.10.20.x` for External).

**Domain join fails:** `nslookup lab.local` must succeed on the laptop before join will
work. If it fails, DNS isn't pointing at DC01. Set DNS manually to DC01's IP.

**GPO not applying after join:** Run `gpresult /r` and confirm the smart card GPO
appears. If the laptop computer account landed in `CN=Computers` instead of the correct
OU, move it with `Move-ADObject` then run `gpupdate /force` again.

**VSC creation fails on TPM 2.0:** Confirm `Get-Tpm` shows TpmReady = True. If the
TPM shows as present but not ready, run `Initialize-Tpm -AllowClear` (this clears any
existing TPM state — do NOT do this on a work machine).

**Certificate not appearing after enrollment:** Confirm the laptop can reach DC01 on
port 135 (RPC) and 443 (if using HTTPS enrollment). Check the AD CS event log on DC01
for enrollment errors. Confirm the user account `labuser` exists and is in the correct
enrollment security group.

**Event 4768 not showing Type 16:** Smart card auth didn't complete via PKINIT. Check
the cert has the Smart Card Logon EKU, the trust chain is valid on DC01, and OCSP/CRL
is reachable from the laptop (`certutil -verify -urlfetch <thumbprint>`).
