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

**From the Hyper-V host (internet-connected), run:**

```powershell
# 1. Stage any prerequisite tools on the host first (needs internet, run once)
.\Tools-Kit\Download-OfflineCA-Kit.ps1 -OutputPath "C:\OfflineCA-Kit"

# 2. Open a direct session to the air-gapped VM
$cred = Get-Credential   # local Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred

# 3. Copy the Lab-Kit OfflineRootCA folder and the staged tools into the VM
Copy-Item -Path ".\Lab-Kit\02-OfflineRootCA" -ToSession $s -Destination "C:\Scripts\" -Recurse
Copy-Item -Path "C:\OfflineCA-Kit"           -ToSession $s -Destination "C:\"         -Recurse

Remove-PSSession $s
```

---

## Run Order (inside the OfflineRootCA VM)

Open PowerShell as Administrator inside the VM and run:

```powershell
cd C:\Scripts\02-OfflineRootCA
.\Initialize-OfflineRootCA.ps1
```

The script walks through 8 steps interactively. It will:

1. Check for active network adapters and require you to confirm air-gap (type `OVERRIDE` only in a lab environment)
2. Generate `CAPolicy.inf` and open it in Notepad for review
3. Install the AD CS Windows role (triggers a restart if needed)
4. Configure the Root CA as a StandaloneRootCA with 4096-bit RSA and SHA-256
5. Set the CDP and AIA publication URLs pointing to `http://pki.lab.local`
6. Publish the CRL
7. Export the Root CA certificate and CRL to `C:\OfflineCA-Export\`
8. Print the exact PowerShell Direct commands to transfer the cert and CRL back to Lab-DC01

---

## After the Ceremony

Once `Initialize-OfflineRootCA.ps1` completes, run the transfer commands it prints (from the Hyper-V host) to copy the Root CA certificate and CRL to Lab-DC01. Then on Lab-DC01:

```powershell
# Publish the Root CA cert to Active Directory and the local Root store
certutil -enterprise -addstore NTAuth "C:\CA-Transfer\<RootCA>.cer"
certutil -addstore Root             "C:\CA-Transfer\<RootCA>.cer"

# Copy the CRL to the IIS CRL distribution point
Copy-Item "C:\CA-Transfer\<RootCA>.crl" "C:\inetpub\wwwroot\crl\"
```

After this, **power off the Root CA VM and keep it off**. It only needs to come back online when the Issuing CA certificate is due for renewal (typically every 5 years).

---

## Why the Root CA Stays Offline

The Root CA's private key is the highest-value asset in the PKI. If it were online, a compromised DC or network could reach it. Keeping it permanently air-gapped means the only way to sign something with the Root CA key is to physically power on the VM on an isolated Hyper-V host — a deliberate, auditable act. This mirrors the federal PIV architecture and NIST SP 800-57 key management guidance.

---

*Related: `Architecture/PKI-Blueprint.md`, `Lab-Kit/03-DomainController/Build-CA-GPO.ps1`, `Lab-Kit/START-HERE.md`*
