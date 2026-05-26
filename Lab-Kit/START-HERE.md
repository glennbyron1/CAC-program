# CAC Lab Kit — Start Here

**Author:** Glenn Byron
**What this is:** Everything you need to build and run the CAC/PIV smart card lab. Files are organized by where you run them.

---

## Folder Map

| Folder | Run these on... |
|--------|----------------|
| `01-HyperV-Host/` | Your main Windows machine (the Hyper-V host) |
| `02-OfflineRootCA/` | The Lab-OfflineRootCA VM (air-gapped, no network) |
| `03-DomainController/` | The Lab-DC01 VM (domain controller + issuing CA) |
| `04-Workstation/` | The Lab-Workstation01 VM (smart card test endpoint) |
| `05-Compliance/` | Lab-DC01 (after scanning — stages SCAP reports) |
| `Reference/` | Read these anywhere — checklists and guides |

---

## Run Order

### On Your Hyper-V Host Machine
```
01-HyperV-Host\New-LabVMs.ps1          ← Creates the three lab VMs
01-HyperV-Host\Set-VMPostConfig.ps1    ← Run inside each VM after OS install
01-HyperV-Host\New-LabSnapshot.ps1     ← Take/restore/manage Hyper-V checkpoints
```

### On Your Hyper-V Host (internet-connected, before transferring to VMs)
```
Tools-Kit\Get-LabTools.ps1                       ← Downloads all tools to C:\FedCompliance-Tools\
  (or run the individual scripts below)
Tools-Kit\Download-IssuingCA-Kit.ps1             ← Stages Issuing CA prerequisites + PSPKI
Tools-Kit\Download-FedCompliance-Kit.ps1         ← Downloads SCAP SCC, STIG Viewer, Nessus
```
Then transfer `C:\FedCompliance-Tools\` to Lab-DC01 via PowerShell Direct (see `01-HyperV-Host\README.md`).

### On Lab-DC01 (Domain Controller)
Run these in order — each one sets up what the next one needs:
```
03-DomainController\Build-CAC-Lab.ps1            ← Builds the AD domain, reboots
03-DomainController\Build-CA-GPO.ps1             ← CA + smart card GPO (after reboot)
03-DomainController\New-CertificateTemplates.ps1 ← Creates smart card cert templates
03-DomainController\Set-OCSPResponder.ps1        ← Sets up OCSP (optional, after PKI is up)
03-DomainController\New-TokenEnrollment.ps1      ← Smart card enrollment ceremony (RA then Issuer)
03-DomainController\New-YubiKeyToken.ps1         ← YubiKey PIV provisioning (key gen, CA enroll,
                                                    cert import, PIN/PUK setup, audit log)
03-DomainController\Set-AuditLogForwarding.ps1   ← Audit policy + WEF logging
03-DomainController\Monitor-PKIHealth.ps1        ← Run anytime to check PKI health
```

### On Lab-OfflineRootCA (Air-Gapped Root CA)
Transfer files to this VM using PowerShell Direct from the Hyper-V host (no network needed):
```powershell
$cred = Get-Credential   # local Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
Copy-Item -Path "C:\path\to\Lab-Kit\02-OfflineRootCA" -ToSession $s -Destination "C:\" -Recurse
Remove-PSSession $s
```
Then inside the VM:
```
02-OfflineRootCA\Download-OfflineCA-Kit.ps1      ← Stages Root CA config files and scripts
02-OfflineRootCA\Initialize-OfflineRootCA.ps1    ← 8-step guided ceremony: installs CA role,
                                                    configures StandaloneRootCA, publishes CRL,
                                                    exports cert+CRL for transfer to DC
```

### On Lab-Workstation01
After the workstation is domain-joined:
```
04-Workstation\Enforce-SmartCard.ps1             ← Applies smart card GPO
04-Workstation\Deploy-VPNClient.ps1              ← Sets up IKEv2 VPN profile
```

### Compliance Scanning (run on Lab-DC01 after scans complete)
```
05-Compliance\Invoke-LabValidation.ps1           ← Run this BEFORE scanning — 7-layer pass/fail
                                                    check (domain, PKI, smart card, GPO, audit,
                                                    VPN, recent auth events); exports a report
05-Compliance\Stage-Reports.ps1                  ← Moves SCAP SCC results into the right folders
```

---

## Key Reference Docs

| File | When to use it |
|------|---------------|
| `Reference\LAB-DAY-CHECKLIST.md` | Step-by-step Phase 4 checklist — work through this top to bottom |
| `Reference\STIG-Hardening-Guide.md` | How to run SCAP SCC scans and export results |
| `Reference\FedGov-Tools-Setup-Guide.md` | How to install DISA tools (STIG Viewer, Nessus, CSET) |
| `Reference\WatchGuard-IKEv2-VPN-Guide.md` | VPN configuration if testing EAP-TLS |
| `Reference\Blueprint.md` | Full architecture reference |

---

## Quick Reminders

- **Run everything as Administrator** inside the VMs
- **Lab-OfflineRootCA has no network** — transfer files via PowerShell Direct from the Hyper-V host
- **Boot order after Build-CAC-Lab.ps1:** it reboots the DC automatically — wait for it to come back up, then run Build-CA-GPO.ps1
- **Smart card enrollment** uses two separate accounts (RA phase, then Issuer phase) — the script blocks you from doing both as the same person
- **Before pushing anything to GitHub:** run Scrub-Repo.ps1 from the main repo folder first

---

*Full repo: `C:\Users\[you]\Documents\GitHub\CAC-program`*
