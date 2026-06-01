# Adding a Physical Laptop to the Lab Domain

**Author:** Glenn Byron
**Purpose:** Step-by-step guide for domain-joining a spare physical laptop, enrolling
a Virtual Smart Card, running SCAP scans, and getting real demo screenshots.

> **Prerequisites:** Lab VMs must be running (DC01 operational, smart card GPO applied).
> The laptop must be a spare/dedicated machine — never domain-join a daily driver.

---

## Before You Start — Checklist

- [ ] Laptop is a spare machine (not your daily driver)
- [ ] Windows 10 or 11 installed — run `winver` to confirm
- [ ] TPM chip present — press Win+R, type `tpm.msc`. Must show "The TPM is ready for use"
- [ ] USB port available (for YubiKey if using one; not needed for Virtual Smart Card)
- [ ] Lab VMs running — DC01 pingable, smart card GPO active

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

**Connect DC01 to the External switch:**
1. Hyper-V Manager → right-click Lab-DC01 → Settings → Network Adapter
2. Change the switch from `Lab-Internal` to `Lab-External`
3. Click OK

DC01 will now get an IP on your home network via DHCP, or set a static IP inside DC01:

```powershell
# Run inside DC01 (Hyper-V console)
# Find the adapter name first
Get-NetAdapter

# Set a static IP that fits your home network (e.g. 192.168.1.x)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.10 `
                 -PrefixLength 24 -DefaultGateway 192.168.1.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1
```

**On the laptop:** point DNS at DC01:
- DNS Server: `192.168.1.10` (or whatever IP DC01 got)

**Verify connectivity from the laptop:**
```powershell
ping 192.168.1.10                        # DC01 should reply
nslookup lab.local 192.168.1.10          # Should resolve
```

---

## Step 2 — Domain Join the Laptop

```powershell
# Run on the laptop as local Administrator
Add-Computer -DomainName "lab.local" `
             -Credential (Get-Credential) `   # use lab\Administrator
             -Restart
```

After reboot, log in with `lab\Administrator` (password auth still works at this point —
smart card enforcement hasn't been applied to the laptop yet).

**Verify domain join:**
```powershell
(Get-WmiObject Win32_ComputerSystem).Domain   # Should return lab.local
```

---

## Step 3 — Apply Smart Card GPO to the Laptop

Run Group Policy update so the smart card enforcement GPO applies:

```powershell
# On the laptop
gpupdate /force

# Verify scforceoption is applied (should return 1)
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" |
    Select-Object scforceoption, ScRemoveOption
```

> **Critical warning:** `scforceoption=1` must ONLY be on the workstation GPO,
> never on DC01. Verify the GPO scope before applying.

---

## Step 4 — Check TPM and Enroll Virtual Smart Card

**Verify TPM is ready:**
```powershell
# Run on the laptop as Administrator
Get-Tpm | Select-Object TpmPresent, TpmReady, TpmEnabled

# If TpmReady is False, initialize it:
Initialize-Tpm -AllowClear -AllowPhysicalPresence
# Then reboot and check BIOS to confirm TPM is enabled
```

**Create the Virtual Smart Card on the laptop:**
```powershell
# Run on the laptop as Administrator
tpmvscmgr.exe create /name "CAC Lab VSC" /pin prompt /adminkey random /generate

# Verify it was created
certutil -scinfo
```

**Enroll the smart card certificate (run on DC01 as Administrator):**
```powershell
# RA phase — run as Registration Authority account
.\New-TokenEnrollment.ps1 -Phase RA -UserName "labuser"

# Issuer phase — run as a DIFFERENT account (enforces separation of duties)
.\New-TokenEnrollment.ps1 -Phase Issuer -UserName "labuser"
```

---

## Step 5 — Test Smart Card Logon on the Laptop

1. Lock the screen (Win+L)
2. The login screen should show **only** the smart card PIN prompt — no password field
3. Enter your PIN → confirm you reach the desktop
4. Remove the VSC (via `tpmvscmgr.exe` or physical removal if using a YubiKey)
5. Session should lock **within 2 seconds**

**Take your screenshots here** — this is real hardware, not a VM screen capture:
- Lock screen showing smart card prompt only (no password field)
- PIN entry screen with certificate subject visible
- Session lock on token removal

---

## Step 6 — Run SCAP SCC Scan on the Laptop

The laptop runs Windows 10 or 11, so use the matching STIG benchmark — not the
Windows Server 2022 one used for the VMs.

**On the laptop:**
1. Copy SCC installer from `Tools-Kit\` or `FedCompliance-Tools\00-SCAP-SCC\`
2. Install SCC 5.10.2
3. Launch SCC → Options → check "Run content regardless of applicability" (CPE override)
4. Select benchmark: `MS_Windows_10_STIG` or `MS_Windows_11_STIG` (match your OS)
5. Run scan → export HTML + XCCDF XML

**Stage results:**
```powershell
# Create a laptop subfolder in Compliance-Reports
New-Item -ItemType Directory "Compliance-Reports\Laptop\Before-MFA" -Force
New-Item -ItemType Directory "Compliance-Reports\Laptop\After-MFA"  -Force

# Copy scan output manually into the appropriate folder
```

---

## Step 7 — Test VPN from the Laptop

The laptop is now on the physical network, making it the ideal "remote user" test client.

```powershell
# Install the IKEv2 VPN profile (run on the laptop)
.\Lab-Kit\04-Workstation\Deploy-VPNClient.ps1

# Connect and confirm certificate authentication
# The VPN should connect using the VSC certificate — no password prompt
```

**Take screenshot:** VPN connected status showing certificate-based authentication.

---

## Evidence to Collect

| Item | File Location | Status |
|------|--------------|--------|
| Lock screen (smart card only, no password) | `Demo-Walkthrough.md` screenshot slot | ⬜ |
| PIN entry with cert subject visible | `Demo-Walkthrough.md` screenshot slot | ⬜ |
| Session lock on card removal | `Demo-Walkthrough.md` screenshot slot | ⬜ |
| Event 4768 Pre-Auth Type 16 in Event Viewer | `Demo-Walkthrough.md` screenshot slot | ⬜ |
| VPN connected via EAP-TLS | `Demo-Walkthrough.md` screenshot slot | ⬜ |
| SCAP scan results (Windows 10/11 STIG) | `Compliance-Reports\Laptop\` | ⬜ |

---

## Troubleshooting

**TPM not ready:** Reboot → enter BIOS → Security → enable TPM 2.0. Some laptops
call it "fTPM" or "PTT" (Intel Platform Trust Technology).

**Can't ping DC01:** Check the External switch is connected to DC01 and both machines
are on the same subnet. Check Windows Firewall on DC01 allows ICMP.

**Domain join fails:** Confirm DNS is pointing to DC01 (192.168.1.10). Run
`nslookup lab.local` on the laptop — it must resolve before join will work.

**Smart card GPO not applying:** Run `gpresult /r` on the laptop and confirm the
smart card GPO appears under Computer Configuration. If not, check the OU the laptop
computer account landed in after domain join.

**VSC creation fails:** Confirm TPM is ready (`Get-Tpm`). Must be TpmReady = True.
If the TPM is managed by your organization (Intune/SCCM), it may need to be cleared first.
