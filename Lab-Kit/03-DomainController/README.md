# Lab-Kit / 03-DomainController

**Author:** Glenn Byron
**Run these scripts on:** Lab-DC01 — the domain controller and Enterprise Issuing CA VM.

---

## Scripts in This Folder

Run in the order listed. Each script sets up what the next one needs.

| # | Script | What it does | NIST Control |
|---|--------|-------------|--------------|
| 1 | `Build-CAC-Lab.ps1` | Installs the AD DS role and promotes the VM to a domain controller for `lab.local`. Triggers a reboot. | IA-2 |
| 2 | `Build-CA-GPO.ps1` | Installs the Enterprise Issuing CA, creates and links the smart card enforcement GPO (`scforceoption=1`, `ScRemoveOption=1`). Run after reboot from step 1. | IA-2(11), AC-11 |
| 3 | `New-CertificateTemplates.ps1` | Creates SmartCardLogon and AdminSmartCardLogon certificate templates on the Issuing CA using PSPKI. Includes a manual fallback guide. | SC-17, IA-5 |
| 4 | `Set-OCSPResponder.ps1` | Installs the Windows Online Responder role, requests an OCSP signing cert, and updates the CA's AIA extension with the OCSP URL. | SC-17, IA-5(2) |
| 5 | `New-TokenEnrollment.ps1` | Two-phase smart card enrollment ceremony. Run in `-Mode RA` first (Registration Authority — identity verification), then `-Mode Issuer` from a different account (Card Issuer — cert enrollment). Blocks the same account from completing both phases. | AC-5, IA-2, IA-5 |
| 6 | `New-YubiKeyToken.ps1` | YubiKey PIV provisioning. Generates AES-256 management key, sets PIN/PUK, generates keys in PIV slots, submits CSR to the CA, imports the cert, and writes an audit log (EventID 7200). | AC-5, IA-2, IA-5 |
| 7 | `Set-AuditLogForwarding.ps1` | Configures Advanced Audit Policy for all Kerberos, Logon, and AD CS subcategories. Sets up Windows Event Forwarding subscriptions to pull Event IDs 4624, 4768, 4886–4890, and others to a central collector. | AU-2, AU-9, AU-12 |
| 8 | `Monitor-PKIHealth.ps1` | PKI health monitor. Checks CRL validity windows, OCSP reachability, CA and smart card cert expiry. Outputs a color-coded dashboard. Run anytime, or schedule as a recurring task. | CA-7, SC-17 |

---

## Run Order

```
Build-CAC-Lab.ps1              ← promotes DC, triggers reboot
  [reboot]
Build-CA-GPO.ps1               ← Issuing CA + smart card GPO
New-CertificateTemplates.ps1   ← SmartCardLogon and Admin cert templates
Set-OCSPResponder.ps1          ← OCSP role and signing cert (optional but recommended)
New-TokenEnrollment.ps1        ← enrollment ceremony (RA phase, then Issuer phase)
New-YubiKeyToken.ps1           ← YubiKey provisioning (if using YubiKeys)
Set-AuditLogForwarding.ps1     ← audit policy and WEF
Monitor-PKIHealth.ps1          ← confirm PKI is healthy before scanning
```

---

## Prerequisites

Before running anything in this folder:

- The VM must have a static IP and be reachable on the network (`Set-VMPostConfig.ps1` handles this)
- Run everything as **Administrator** inside the VM
- Scripts are transferred from the Hyper-V host via PowerShell Direct — see `Lab-Kit/01-HyperV-Host/README.md`
- `New-CertificateTemplates.ps1` requires the **PSPKI** PowerShell module. `Download-IssuingCA-Kit.ps1` from Tools-Kit installs it automatically with internet access

---

## Key Parameters

**`Build-CAC-Lab.ps1`**
```powershell
.\Build-CAC-Lab.ps1 -DomainName "lab.local" -NetBIOSName "LAB"
```

**`New-TokenEnrollment.ps1`** — run twice, from two different accounts
```powershell
# Phase 1: Registration Authority (identity verification)
.\New-TokenEnrollment.ps1 -Mode RA -UserPrincipalName target@lab.local

# Phase 2: Card Issuer (cert enrollment) — must be a different account
.\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName target@lab.local
```

**`New-YubiKeyToken.ps1`**
```powershell
.\New-YubiKeyToken.ps1 -Mode Provision -UserPrincipalName target@lab.local -CAServer "Lab-DC01"
.\New-YubiKeyToken.ps1 -Mode Verify    -UserPrincipalName target@lab.local
```

**`Monitor-PKIHealth.ps1`**
```powershell
.\Monitor-PKIHealth.ps1 `
    -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
    -OCSPUrl "http://pki.lab.local/ocsp" `
    -IssuingCAServer "Lab-DC01" `
    -AlertThresholdDays 60
```

---

*Related: `Lab-Kit/START-HERE.md`, `Lab-Kit/LAB-DAY-CHECKLIST.md`, `Architecture/Blueprint.md`*
