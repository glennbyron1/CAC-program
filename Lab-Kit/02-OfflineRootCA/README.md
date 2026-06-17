# Lab-Kit / 02-OfflineRootCA

**Author:** Glenn Byron
**Run these scripts on:** The Lab-OfflineRootCA VM — air-gapped, no network adapter.

---

## What This Folder Does

This folder contains the guided ceremony for building the Offline Root CA. The Root CA is the trust anchor for the entire two-tier PKI — it issues the certificate that makes the Enterprise Issuing CA trusted. Once built, it is powered off and never connected to a network again.

---

## Scripts in This Folder

| Script | What it does |
|--------|-------------|
| `Initialize-OfflineRootCA.ps1` | 8-step guided ceremony: verifies air-gap, generates CAPolicy.inf, installs the AD CS role, configures a StandaloneRootCA (4096-bit RSA / SHA-256 / 10-year validity), sets CDP and AIA URLs, publishes the CRL, exports the CA certificate and CRL, and prints the exact PowerShell Direct commands for transferring files to the DC |

---

## How to Get the Script onto the Air-Gapped VM

The OfflineRootCA VM has no network adapter — transfer files using PowerShell Direct from the Hyper-V host. This works through the Hyper-V hypervisor with no network connection required.

**From the Hyper-V host, run:**

**Step 1 — Add UTF-8 BOM to the script (required once, before first transfer)**

PowerShell 5.1 requires UTF-8 with BOM. Without it, Unicode characters in the script
(em dashes, box-drawing characters) are misread and the script fails to parse.

```powershell
$file = "C:\CAC-Lab-Kit-20260526\Lab-Kit\02-OfflineRootCA\Initialize-OfflineRootCA.ps1"
$bytes = [System.IO.File]::ReadAllBytes($file)
if ($bytes[0] -ne 0xEF) {
    [System.IO.File]::WriteAllBytes($file, [byte[]](0xEF,0xBB,0xBF) + $bytes)
    Write-Host "BOM added" -ForegroundColor Green
} else {
    Write-Host "BOM already present" -ForegroundColor Yellow
}
```

**Step 2 — Transfer scripts and tools to the VM**

```powershell
$cred = Get-Credential   # local Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred

Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }

# Copy the Lab-Kit OfflineRootCA folder and the staged tools into the VM
# (Get-LabTools.ps1 already downloaded the CA kit to C:\FedCompliance-Tools\09-OfflineRootCA-Kit)
Copy-Item -Path "C:\CAC-Lab-Kit-20260526\Lab-Kit\02-OfflineRootCA" `
          -ToSession $s -Destination "C:\Scripts\" -Recurse
Copy-Item -Path "C:\FedCompliance-Tools\09-OfflineRootCA-Kit" `
          -ToSession $s -Destination "C:\" -Recurse

Remove-PSSession $s
```

---

## Step 3 — Add Loopback Adapter Before Running (required)

`Install-AdcsCertificationAuthority` requires an active network stack even for a
Standalone Root CA. With zero network adapters the install fails with
`ERROR_NETWORK_UNREACHABLE (0x800704cf)`. Fix: attach a Hyper-V **Private** switch
(Private = no internet, no host access, fully isolated) before running the script,
then remove it after the ceremony completes.

**On the Hyper-V host (VM must be running):**
```powershell
# Create once — reuse for future runs
New-VMSwitch -Name "OfflineCA-Loopback" -SwitchType Private
Add-VMNetworkAdapter -VMName "Lab-OfflineRootCA" -SwitchName "OfflineCA-Loopback"
```

---

## Step 4 — Run the Ceremony (inside the OfflineRootCA VM)

Open PowerShell as Administrator inside the VM and run:

```powershell
cd C:\Scripts\02-OfflineRootCA
.\Initialize-OfflineRootCA.ps1
```

The script walks through 8 steps interactively:

1. **Air-gap check** — detects the loopback adapter and warns. Type `OVERRIDE` to continue (safe — Private switch has no external connectivity)
2. **CAPolicy.inf** — generates the file and opens it in Notepad. Review and close, then press Enter. No changes needed for the lab defaults
3. **AD CS role install** — installs `ADCS-Cert-Authority`. May reboot; re-run script after reboot, it skips completed steps
4. **Configure Root CA** — StandaloneRootCA, 4096-bit RSA, SHA-256, 10-year validity
5. **CDP and AIA URLs** — sets `http://pki.lab.local` as the CRL distribution point
6. **Publish CRL** — publishes initial CRL to `C:\Windows\System32\CertSrv\CertEnroll\`
7. **Export** — copies Root CA cert and CRL to `C:\OfflineCA-Export\`
8. **Transfer instructions** — prints exact commands for moving files to Lab-DC01

> **If Step 4 fails with "already installed":** The AD CS role was partially configured
> by a previous failed attempt. Uninstall it completely and reboot, then re-run:
> ```powershell
> Uninstall-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
> Restart-Computer -Force
> ```

---

## Step 5 — Transfer Exports and Remove Loopback Adapter

**On the Hyper-V host — copy the Root CA files out and remove the loopback:**
```powershell
# Remove the loopback adapter — restores true air-gap
Get-VMNetworkAdapter -VMName "Lab-OfflineRootCA" |
    Where-Object { $_.SwitchName -eq "OfflineCA-Loopback" } |
    Remove-VMNetworkAdapter

# Copy the Root CA cert and CRL to the host
$cred = Get-Credential   # Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
New-Item -ItemType Directory -Path "C:\CA-Transfer" -Force | Out-Null
Copy-Item -Path "C:\OfflineCA-Export" -FromSession $s -Destination "C:\CA-Transfer\" -Recurse
Remove-PSSession $s
```

**Verify three files are present:**
```powershell
Get-ChildItem "C:\CA-Transfer\OfflineCA-Export\"
```

Expected files:
| File | Purpose |
|------|---------|
| `LabRootCA.cer` | Root CA certificate — published to AD and local Root store on DC |
| `Lab Root CA.crl` | CRL — copied to IIS CRL distribution point on DC |
| `Lab-OfflineRootCA_Lab Root CA.crt` | AIA copy of the cert |

**Shut down Lab-OfflineRootCA** — it stays off until the next CRL renewal (every 6 months).

---

## Why the Root CA Stays Offline

The Root CA's private key is the highest-value asset in the PKI. If it were online, a compromised DC or network could reach it. Keeping it permanently air-gapped means the only way to sign something with the Root CA key is to physically power on the VM on an isolated Hyper-V host — a deliberate, auditable act. This mirrors the federal PIV architecture and NIST SP 800-57 key management guidance.

---

*Related: `Architecture/Blueprint.md`, `Lab-Kit/03-DomainController/Build-CA-GPO.ps1`, `Lab-Kit/START-HERE.md`*
