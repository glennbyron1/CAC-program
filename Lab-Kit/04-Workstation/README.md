# Lab-Kit / 04-Workstation

**Author:** Glenn Byron
**Run these scripts on:** Lab-Workstation01 (the smart card test endpoint), after it is domain-joined.

---

## Scripts in This Folder

| Script | What it does |
|--------|-------------|
| `Enforce-SmartCard.ps1` | Applies smart card enforcement registry settings directly (for machines that cannot receive Group Policy) |
| `Deploy-VPNClient.ps1` | Creates the IKEv2 VPN profile with EAP-TLS certificate authentication and FIPS-compliant IPsec crypto |

---

## Smart Card Reader & Middleware

Before running `Enforce-SmartCard.ps1` or testing smart card logon, the workstation needs to be able to communicate with the smart card reader and read the certificate on the card.

### Reader driver

Most USB CCID smart card readers (including the ones that ship with CardLogix GIDS cards and most YubiKey models) are plug-and-play on Windows 10, Windows 11, and Windows Server 2022/2025. Windows ships with a built-in USB CCID driver. Plug in the reader, wait a few seconds, and it should appear in Device Manager under **Smart card readers** with no additional driver needed.

If the reader does not appear, download the driver from the manufacturer's website and install it before continuing.

### Card middleware

Windows ships with a built-in **Base Smart Card Cryptographic Service Provider (CSP)** and a **minidriver** that handles GIDS-compliant cards (the standard used by CardLogix GIDS cards) and PIV-compliant cards (the standard used by YubiKey PIV). For this lab you **do not need to install ActivClient or any third-party middleware** — the Windows built-in minidriver handles everything.

Summary by token type:

| Token | Middleware needed |
|-------|-------------------|
| CardLogix GIDS smart card | None — Windows GIDS minidriver handles it |
| YubiKey (PIV mode) | None — Windows PIV minidriver handles it |
| DoD CAC (physical) | ActivClient or OpenSC required |
| Other proprietary cards | Check manufacturer documentation |

To verify Windows recognizes the card after inserting it, open PowerShell and run:

```powershell
Get-SmartCard   # or check Device Manager > Smart card readers
```

Or run the lab validation script from the compliance folder, which checks the reader and card in Layer 3:

```powershell
..\05-Compliance\Invoke-LabValidation.ps1 -DomainName "lab.local" -DCHostname "Lab-DC01"
```

---

## GPO Settings Applied

`Enforce-SmartCard.ps1` sets the same registry values that `Build-CA-GPO.ps1` delivers via Group Policy. Use this script on workstations that cannot receive GPO (e.g., standalone machines or during initial testing before the domain GPO propagates).

| Registry Key | Value | Effect | NIST Control |
|---|---|---|---|
| `System\Logon\scforceoption` | `1` | Removes password logon option — card required | IA-2(11) |
| `System\Logon\ScRemoveOption` | `1` | Locks workstation immediately on card removal | AC-11 |
| `System\Logon\InactivityTimeoutSecs` | `900` | 15-minute inactivity timeout | AC-11 |
| `Network\Lanman Workstation\AllowInsecureGuestAuth` | `0` | Blocks insecure guest logons | STIG-WIN-0012 |

---

## Run Order

Run these after the workstation is domain-joined and has received certificates:

```
1. Verify smart card reader and card are recognized (see above)
2. Enforce-SmartCard.ps1      ← apply smart card enforcement settings
3. Deploy-VPNClient.ps1       ← configure IKEv2 VPN profile
4. Test smart card logon       ← lock screen, insert card, enter PIN
5. Test session lock           ← pull card, confirm lock in < 2 seconds
```

For the full demo sequence, see `Demo-Walkthrough.md` in the repo root.
