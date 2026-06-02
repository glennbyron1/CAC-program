# CAC Lab — Onboarding Guide

> **This file is sanitized for public distribution.**
> Real lab passwords appear as `<LAB-ADMIN-PASSWORD>`, `<LAB-LABTECH-PASSWORD>`, etc.
> See `.scrub-patterns.example.json` at the repo root for the full pattern list.
> Substitute your own values when running these commands.

Quick-start reference for new users, new machines, and day-one lab orientation.

---

## What Is This Lab?

A Hyper-V-based CAC/PIV ICAM lab running on Windows Server 2025. It demonstrates
smart card multi-factor authentication aligned to NIST SP 800-53 (IA-2, IA-2(11), AC-11).

---

## Lab Environment

### Virtual Machines

| VM | Role | IP (LabInternal) | IP (External) |
|---|---|---|---|
| Lab-OfflineRootCA | Standalone Root CA (air-gapped) | No network | No network |
| Lab-DC01 | Domain Controller + Issuing CA | 10.10.10.10 | 10.10.20.10 |
| Lab-Workstation01 | Domain workstation (VM) | 10.10.10.20 | — |
| WO02 | Physical laptop endpoint | 10.10.20.30 (static) | physical NIC |

### Host Machine

| Adapter | IP | Purpose |
|---|---|---|
| `vEthernet (LabInternal)` | 10.10.10.1 | Host ↔ VM management |
| `vEthernet (External)` | 10.10.20.1 | Host ↔ physical laptop |

### Domain

| Setting | Value |
|---|---|
| Domain name | `lab.local` |
| DNS | DC01 at 10.10.10.10 (internal) or 10.10.20.10 (external) |
| CA | `LAB-CA` on Lab-DC01 |

---

## Lab Accounts

| Account | Password | Role | Notes |
|---|---|---|---|
| `LAB\Administrator` | `<LAB-ADMIN-PASSWORD>` | Domain Admin | **Password-only. SmartcardLogonRequired = False. NEVER change this.** Use to log into any machine. |
| `LAB\CardIssuer` | `<LAB-ADMIN-PASSWORD>` | Domain Admin | **Password-only. SmartcardLogonRequired = False. NEVER change this.** Break-glass if Administrator is locked out. |
| `LAB\labtech` | `<LAB-LABTECH-PASSWORD>` | Standard user | Physical laptop test user. Smart card enrollment target. Uses VSC on WO02. |
| `.\Administrator` (local) | `<LAB-ADMIN-PASSWORD>` | Local admin | Use when domain trust is broken and domain join is needed. |

> **Rule:** LAB\Administrator and LAB\CardIssuer will NEVER have SmartcardLogonRequired set.
> They are the permanent password-based admin accounts for the lab.
> Smart card enforcement applies to standard users (labtech, etc.) on workstations only.

> **Break-glass rule:** If you cannot log in as `LAB\Administrator`, log in as `LAB\CardIssuer`.
> CardIssuer will NEVER have `SmartcardLogonRequired` set — it is the permanent break-glass account.

---

## Add a New Computer to the Domain

### Prerequisites
- Windows 11 **Pro or Enterprise** (Home cannot join a domain)
- TPM 2.0 (for Virtual Smart Card enrollment)
- Machine name must be **15 characters or fewer** (NetBIOS limit)
- DNS must point to DC01 before domain join

### Step 1 — Set static IP and DNS on the new machine

```powershell
# Run on the new machine as local Administrator
# Adjust the adapter name if needed (Get-NetAdapter to find it)
netsh interface ipv4 set address name="Ethernet" static 10.10.20.XX 255.255.255.0
netsh interface ipv4 set dns    name="Ethernet" static 10.10.20.10

# Verify DNS resolves lab.local
nslookup lab.local 10.10.20.10
```

Replace `10.10.20.XX` with an unused IP. Current assignments:
- 10.10.20.1 — Host External adapter
- 10.10.20.10 — DC01 External NIC
- 10.10.20.30 — WO02 (physical laptop)
- Use .40, .50, etc. for new machines.

### Step 2 — Rename the computer (if needed)

```powershell
Rename-Computer -NewName "MACHINENAME" -Force -Restart
```

Log back in after reboot, then proceed to Step 3.

### Step 3 — Join the domain

```powershell
Add-Computer -DomainName "lab.local" `
    -Credential (Get-Credential "LAB\Administrator") `
    -OUPath "OU=Workstations,DC=lab,DC=local" `
    -Restart -Force
```

Enter `LAB\Administrator` / `<LAB-ADMIN-PASSWORD>` when prompted.
The machine will reboot and land in `OU=Workstations` automatically.

### Step 4 — Verify from DC01

```powershell
Get-ADComputer -Filter "Name -eq 'MACHINENAME'" | Select-Object Name, DistinguishedName
```

Expected: `CN=MACHINENAME,OU=Workstations,DC=lab,DC=local`

If it landed in `CN=Computers` instead, move it:
```powershell
Get-ADComputer "MACHINENAME" |
    Move-ADObject -TargetPath "OU=Workstations,DC=lab,DC=local"
```

### Step 5 — Make user a temporary local admin for VSC setup, then remove

> **Zero trust principle:** Standard users should NOT be permanent local admins.
> Grant admin rights temporarily for VSC creation only, then remove immediately after enrollment.

```powershell
# Grant temporarily (run on the machine as IT admin)
Add-LocalGroupMember -Group "Administrators" -Member "LAB\labtech"

# ... complete VSC creation and cert enrollment ...

# Remove after enrollment is complete
Remove-LocalGroupMember -Group "Administrators" -Member "LAB\labtech"
Get-LocalGroupMember -Group "Administrators"   # verify removed
```

---

### Step 6 — Create Virtual Smart Card BEFORE pulling the GPO

> **Critical order:** Create the VSC and enroll the certificate BEFORE running
> `gpupdate /force`. Once `scforceoption=1` is active, no one can log in without
> a smart card — including local Administrator. If you run gpupdate first,
> use `Invoke-GPUpdate` from DC01 to remotely push a policy change without
> needing to log in.

```powershell
# Run on the new machine BEFORE gpupdate — Basic Session only (not Enhanced/RDP)
tpmvscmgr.exe create /name "LabVSC" /pin PROMPT /pinpolicy minlen 6 /adminkey DEFAULT /generate
# PIN: 123456
```

Then enroll the certificate (see Smart Card Enrollment section below), then run:

```powershell
gpupdate /force
```

**If you already ran gpupdate and are now locked out:**
```powershell
# On DC01 — disable scforceoption temporarily
Set-GPRegistryValue -Name "SmartCard Policy" `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption" -Type DWord -Value 0

# Push to the locked machine remotely
Invoke-GPUpdate -Computer "MACHINENAME" -Force
```

Wait 30 seconds, then log in normally. Create VSC + enroll cert, then re-enable:
```powershell
Set-GPRegistryValue -Name "SmartCard Policy" `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption" -Type DWord -Value 1
```

---

## Create a New Domain User

Run all commands on **DC01** as `LAB\Administrator`.

### Basic user

```powershell
$pw = ConvertTo-SecureString "Password123!" -AsPlainText -Force

New-ADUser `
    -Name              "username" `
    -SamAccountName    "username" `
    -UserPrincipalName "username@lab.local" `
    -GivenName         "First" `
    -Surname           "Last" `
    -AccountPassword   $pw `
    -Enabled           $true `
    -PasswordNeverExpires $true `
    -Path              "OU=Workstations,DC=lab,DC=local"

# Confirm
Get-ADUser -Identity username | Select-Object Name, UserPrincipalName, Enabled
```

### Set UPN (required for smart card certificate enrollment)

```powershell
Set-ADUser -Identity username -UserPrincipalName "username@lab.local"
```

### Add to Domain Admins

```powershell
Add-ADGroupMember -Identity "Domain Admins" -Members "username"
```

### Make local admin on a specific machine (run on that machine)

```powershell
Add-LocalGroupMember -Group "Administrators" -Member "LAB\username"
```

### Reset a user's password

```powershell
$pw = ConvertTo-SecureString "NewPassword123!" -AsPlainText -Force
Set-ADAccountPassword -Identity username -NewPassword $pw -Reset
```

### List all domain users

```powershell
Get-ADUser -Filter * |
    Select-Object Name, SamAccountName, Enabled, UserPrincipalName |
    Sort-Object Name | Format-Table -AutoSize
```

---

## Smart Card Enrollment — Complete Start-to-Finish Guide

Enrolls a domain user (e.g. `labtech`) with a TPM Virtual Smart Card on a Windows 11 Pro
endpoint. Enforces NIST AC-5 separation of duties: two different admin accounts complete
the ceremony, and the user sets their own PIN.

---

### One-Time Lab Prerequisites (DC01 — do once, not per user)

These must be done before ANY smart card enrollment will work. If already done, skip.

```powershell
# 1. Publish Kerberos Authentication template to CA (required for PKINIT)
Add-CATemplate -Name "KerberosAuthentication"

# 2. Grant Domain Controllers auto-enroll rights on the template
Import-Module PSPKI
$t   = Get-CertificateTemplate -Name "KerberosAuthentication"
$acl = $t | Get-CertificateTemplateAcl
$acl | Add-CertificateTemplateAcl -Identity "Domain Controllers" `
       -AccessType Allow -AccessMask Read,Enroll,AutoEnroll | Set-CertificateTemplateAcl

# 3. Enroll DC01 for the Kerberos Authentication cert (PKINIT requirement)
certreq -enroll -machine KerberosAuthentication

# 4. Grant Authenticated Users Read + Enroll on the SmartcardLogon template
#    (PSPKI Add-CertificateTemplateAcl only adds Read — must use AD extended rights)
$cfgNC = (Get-ADRootDSE).configurationNamingContext
$templateDN = "CN=SmartcardLogon,CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
$adAcl = Get-Acl "AD:$templateDN"
$enrollGuid = [System.Guid]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
$authUsers  = [System.Security.Principal.SecurityIdentifier]"S-1-5-11"
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $authUsers,
    [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
    [System.Security.AccessControl.AccessControlType]::Allow,
    $enrollGuid,
    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None,
    [System.Guid]::Empty
)
$adAcl.AddAccessRule($ace)
Set-Acl "AD:$templateDN" $adAcl

# 5. Restart CA to pick up template changes
Restart-Service certsvc
Write-Host "One-time prerequisites complete."
```

---

### Part 1 — Create the User (DC01 as LAB\Administrator)

Skip if the user already exists.

```powershell
$pw = ConvertTo-SecureString "<LAB-LABTECH-PASSWORD>" -AsPlainText -Force
New-ADUser `
    -Name "labtech" -SamAccountName "labtech" `
    -UserPrincipalName "labtech@lab.local" `
    -GivenName "Lab" -Surname "Tech" `
    -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true `
    -Path "OU=Workstations,DC=lab,DC=local"

# Confirm UPN is set (required for cert enrollment)
Get-ADUser -Identity labtech -Properties UserPrincipalName |
    Select-Object Name, UserPrincipalName, Enabled
```

---

### Part 2 — RA Ceremony (DC01 as LAB\Administrator)

```powershell
& "C:\Scripts\03-DomainController\New-TokenEnrollment.ps1" `
    -Mode RA -UserPrincipalName "labtech@lab.local"
```

Work through the identity checklist (passport, driver's license). The script sets the
RA authorization flag on labtech's AD account.

---

---

## Card Type Reference

Choose your card type before starting Part 3. The ceremony (Parts 1, 2, 5) is identical
for both. Only Part 3 (card setup) and the token serial number differ.

| | Virtual Smart Card (VSC) | Physical Smart Card |
|---|---|---|
| **Hardware** | TPM 2.0 chip (built into laptop) | Physical card + USB reader |
| **Card types** | Windows TPM VSC | YubiKey 5, HID Crescendo, CAC/PIV |
| **Reader shown in certutil** | `Microsoft Virtual Smart Card 0` | `Identive SCR33xx v2.0 USB SC Reader 0` |
| **Token serial (ceremony)** | `ROOT\SMARTCARDREADER\0000` | Card serial (from certutil -scinfo or printed on card) |
| **PIN reset** | `tpmvscmgr.exe destroy` + recreate | YubiKey: `ykman piv reset` / GIDS: factory reset tool |
| **Recommended for lab** | ✅ Quick, no hardware needed | ✅ Most realistic — use YubiKey 5 NFC |
| **Avoid** | — | CardLogix GIDS (admin key is random, unrecoverable if PIN blocked) |

---

> **Zero Trust Rule — applies to BOTH card types:**
> The target user (labtech) needs temporary local admin rights during Part 3 and Part 4
> so they can interact with the smart card services and certreq.
> **Remove local admin immediately after Part 4 is complete (Part 6).**
> Never leave a standard user as a permanent local admin.

### Part 3A — Virtual Smart Card Setup (TPM VSC)

### Part 3 — Machine Setup (on the endpoint as local LAB\Administrator)

> **Smart card enforcement must be OFF during setup.**
> Check DC01 first — if scforceoption=1 is active, temporarily disable it:
> ```powershell
> # On DC01
> Set-GPRegistryValue -Name "SmartCard Policy" `
>     -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
>     -ValueName "scforceoption" -Type DWord -Value 0
> ```
> Reboot the endpoint, then log in as `LAB\Administrator`.

```powershell
# 1. Start smart card services
Start-Service SCardSvr, ScDeviceEnum
Set-Service  SCardSvr, ScDeviceEnum -StartupType Automatic

# 2. Create the Virtual Smart Card (requires admin, requires console/physical session)
tpmvscmgr.exe create /name "LabVSC" /pin PROMPT /pinpolicy minlen 6 /adminkey DEFAULT /generate
# Enter PIN: 123456 when prompted (minlen 6)
# Expected output: "TPM Smart Card created. Smart Card Reader Device Instance ID = ROOT\SMARTCARDREADER\0000"

# 3. Verify VSC is visible
certutil -scinfo
# Should show "Microsoft Virtual Smart Card 0" — "Missing stored keyset" is NORMAL at this stage

# 4. Grant the target user temporary local admin rights for certreq
Add-LocalGroupMember -Group "Administrators" -Member "LAB\labtech"
```

Log out of LAB\Administrator.

---

### Part 3B — Physical Smart Card Setup (YubiKey 5 / HID Crescendo / CAC)

> Physical card reader (e.g. Identive SCR33xx) must be plugged into the endpoint.

```powershell
# Grant target user temporary local admin (required for card setup and certreq)
Add-LocalGroupMember -Group "Administrators" -Member "LAB\labtech"
# ⚠️  REMEMBER: Remove this in Part 6 after enrollment is complete
```

**YubiKey 5 NFC (recommended for lab):**
```powershell
# Verify card is visible
certutil -scinfo
# Should show reader name and card ATR

# Get the YubiKey serial number (needed for ceremony)
# Option 1: from certutil -scinfo output
# Option 2: printed on back of YubiKey
# Option 3: ykman info (if ykman is installed)

# Reset PIV applet if card was previously used (fresh state)
# ykman piv reset   ← WARNING: destroys all keys and certs on the card

# Default PIV PIN after reset: 123456
# Default PIV PUK after reset: 12345678
# Default management key:      010203040506070801020304050607080102030405060708
```

**HID Crescendo C2300 / government CAC/PIV:**
```powershell
# Verify card is detected
certutil -scinfo

# Note the serial number from the output — format varies by card type
# For government CAC: serial is printed on front of card
# For HID Crescendo: certutil -scinfo shows it in the Card section
```

**INF file for physical card** — same as VSC but use CNG provider instead:
```
ProviderName = "Microsoft Smart Card Key Storage Provider"
```
Remove the `ProviderType = 1` line (ProviderType is only for CAPI/legacy providers).

Updated INF for physical cards:
```powershell
@"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=labtech"
KeyLength = 2048
KeySpec = 1
MachineKeySet = FALSE
Exportable = FALSE
UserProtected = TRUE
ProviderName = "Microsoft Smart Card Key Storage Provider"
RequestType = PKCS10

[RequestAttributes]
CertificateTemplate = SmartcardLogon
"@ | Out-File "C:\Temp\sclogon-physical.inf" -Encoding ascii
```

Then use `C:\Temp\sclogon-physical.inf` in the certreq commands in Part 4.

Log out of LAB\Administrator.

---

### Part 4 — Certificate Enrollment (on the endpoint as LAB\labtech)

> **Critical:** Must be logged in AS the target user. The private key is generated under
> the current user's profile. Certs enrolled by admin CANNOT be used by labtech.

Log in as `LAB\labtech` / `<LAB-LABTECH-PASSWORD>`, open an elevated PowerShell, then:

```powershell
# 1. Create the certificate request INF file
New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

@"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=labtech"
KeyLength = 2048
KeySpec = 1
MachineKeySet = FALSE
Exportable = FALSE
UserProtected = TRUE
ProviderName = "Microsoft Base Smart Card Crypto Provider"
ProviderType = 1
RequestType = PKCS10

[RequestAttributes]
CertificateTemplate = SmartcardLogon
"@ | Out-File "C:\Temp\sclogon.inf" -Encoding ascii

# 2. Generate key on VSC and create request (PIN prompt will appear)
certreq -f -new C:\Temp\sclogon.inf C:\Temp\sclogon.req

# 3. Submit to the CA
certreq -submit -config "Lab-DC01\LAB-CA" C:\Temp\sclogon.req C:\Temp\sclogon.cer

# 4. Install the certificate (links cert to VSC key)
certreq -accept C:\Temp\sclogon.cer

# 5. Verify cert is in labtech's store with Smart Card Logon EKU
Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.4.1.311.20.2.2" } |
    Select-Object Subject, Thumbprint, NotAfter
```

Expected output: `CN=labtech, OU=Workstations, DC=lab, DC=local` with a valid thumbprint.

---

### Part 5 — Issuer Ceremony (DC01 as LAB\CardIssuer)

```powershell
# Open a new PowerShell as CardIssuer
$pw   = ConvertTo-SecureString "<LAB-ADMIN-PASSWORD>" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("LAB\CardIssuer", $pw)
Start-Process powershell -Credential $cred -ArgumentList "-NoExit -Command `"& 'C:\Scripts\03-DomainController\New-TokenEnrollment.ps1' -Mode Issuer -UserPrincipalName labtech@lab.local`""
```

Work through the checklist. When asked for token serial number enter: `ROOT\SMARTCARDREADER\0000`
When asked "Certificate enrolled successfully onto the token?" type: **Y**

> Note: The script will fail to set `SmartcardLogonRequired` on the AD account — this is
> a known non-fatal error (CardIssuer lacks rights to write this attribute). The ceremony
> audit record is written successfully.

---

### Part 6 — Clean Up and Enable Enforcement (endpoint as LAB\Administrator)

> ⚠️ **DO THIS FIRST — Remove local admin before anything else.**
> The user was granted temporary admin rights in Part 3 for card setup only.
> Standard users must NOT remain local admins on their workstations (Zero Trust / least privilege).

```powershell
# STEP 1 — Remove labtech from local admins (do this immediately after enrollment)
Remove-LocalGroupMember -Group "Administrators" -Member "LAB\labtech"

# Verify removed
Get-LocalGroupMember -Group "Administrators"

# Enable RDP for smart card testing (VNC does not support smart card)
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

Then on **DC01**, re-enable smart card enforcement:

```powershell
Set-GPRegistryValue -Name "SmartCard Policy" `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption" -Type DWord -Value 1
```

---

### Part 7 — Test Smart Card Logon

> **Use RDP — not VNC.** TightVNC does not support smart card PIN entry.

From the host machine, open Run (`Win+R`):
```
mstsc /v:10.10.20.30
```

- Click **More choices** → **Use a different account**
- Select the smart card tile for `labtech@lab.local`
- Enter PIN: `123456`
- Confirm you reach the desktop as `LAB\labtech`

**Lock test:** Press `Win+L`. Remove the smart card (or run `tpmvscmgr.exe remove /instance ROOT\SMARTCARDREADER\0000` in another session). The screen should lock within 2 seconds (AC-11).

---

### Enrollment Checklist Summary

| # | Step | Where | Account |
|---|---|---|---|
| Pre | One-time lab prerequisites | DC01 | LAB\Administrator |
| 1 | Create user | DC01 | LAB\Administrator |
| 2 | RA ceremony | DC01 | LAB\Administrator |
| 3 | Start services + create card + **grant labtech local admin** | Endpoint | LAB\Administrator (local) |
| 4 | certreq enrollment | Endpoint | **LAB\labtech** ← must be target user |
| 5 | Issuer ceremony | DC01 | **LAB\CardIssuer** ← different person |
| 6 | **Remove labtech local admin** + enable RDP | Endpoint | LAB\Administrator (local) |
| 6 | Re-enable scforceoption=1 | DC01 | LAB\Administrator |
| 7 | Test via RDP | Host → Endpoint | LAB\labtech + PIN |

---

## Take a Lab Checkpoint

Run on the **Hyper-V host** in elevated PowerShell.

```powershell
# Create checkpoint (replace label as appropriate)
& "C:\CAC-Lab-Kit-20260526\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1" `
    -Mode Create -Label "06-Physical-Laptop-Joined"

# List all checkpoints
& "C:\CAC-Lab-Kit-20260526\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1" -Mode List

# Restore to a checkpoint
& "C:\CAC-Lab-Kit-20260526\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1" `
    -Mode Restore -Label "05-After-Scan"
```

---

## Key File Locations

| File | Purpose |
|---|---|
| `WALKTHROUGH.md` | Full step-by-step lab build guide |
| `CHANGELOG.md` | All changes, bugs fixed, and session notes |
| `TROUBLESHOOTING.md` | Problems encountered and how to fix them |
| `ONBOARDING.md` | This file — new user and machine quickstart |
| `Lab-Kit\06-PhysicalEndpoint\Add-Physical-Laptop.md` | Physical laptop add guide |
| `Compliance-Reports\Before-MFA\` | SCAP baseline scans (before smart card) |
| `Compliance-Reports\After-MFA\` | SCAP scans after smart card enforcement |

---

*Last updated: 2026-06-02*
