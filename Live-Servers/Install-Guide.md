# CAC/PIV Deployment — Live Server Installation Guide

Document ID: LIVE-ICAM-001
Author: Glenn Byron
Framework: NIST SP 800-53 IA-2, AC-5, SC-17 | FIPS 201-3 | DISA RMF

> **This guide is for deploying to real servers — not the Hyper-V lab.**
> Lab setup instructions are in `Lab-Kit/START-HERE.md`.
> Run `Test-ServerReadiness.ps1` on each server first to see exactly what is
> missing before you start.

---

## Before You Touch Anything

**1. Run the readiness checker on every server.**

```powershell
# Copy Test-ServerReadiness.ps1 to the target server, then run it
.\Test-ServerReadiness.ps1 -ExportReport
```

Review the saved report. Fix every FAIL before moving to the installation steps.
WARNs are advisories — address them before you go live.

**2. Have these ready:**

| Item | Where to get it |
|------|----------------|
| Windows Server 2022 or 2025 license | Microsoft Volume Licensing / VLSC |
| Your organization's domain name | e.g., agency.gov |
| Static IP addresses for each server | Assigned by your network team |
| DNS entries for PKI hostnames | e.g., pki.agency.gov, ocsp.agency.gov |
| Smart card tokens (GIDS cards or YubiKeys) | HIRSCH, Yubico, and other vendors |
| Smart card readers | USB or built-in, CCID compliant |
| The FedCompliance-Tools folder | Built by Tools-Kit\Get-LabTools.ps1 |

**3. Adjust all placeholders before running any script.**

Every script uses `agency.gov`, `pki.agency.gov`, and `lab.local` as examples.
Replace these with your real domain and hostnames before executing.

---

## Server Roles — What Goes Where

| Server | Role | Count |
|--------|------|-------|
| Offline Root CA | Standalone CA, air-gapped, never joined to domain | 1 |
| Issuing CA | Enterprise Subordinate CA, domain-joined | 1 (or 2 for HA) |
| Domain Controller | AD DS, DNS | 1+ |
| CRL/AIA Server | IIS for HTTP CRL and AIA publishing | 1 |
| Workstations | Smart card endpoints | As many as needed |

In a small deployment, the Issuing CA and Domain Controller can be the same server.
For anything approaching production, keep them separate.

---

## Phase 1 — Offline Root CA

The Offline Root CA is built first because every other server depends on it
to issue the Issuing CA certificate. After you complete this phase, the Root CA
goes back offline and stays there except for annual CRL updates.

### 1.1 Prepare the machine

- Dedicated physical or virtual machine — no network connection ever
- Windows Server installed, local Administrator account set
- No domain join — this is a standalone machine

### 1.2 Copy the Root CA kit to the machine

From any internet-connected machine, build the kit first:

```powershell
cd Tools-Kit\
.\Get-LabTools.ps1 -OutputPath "E:\FedCompliance-Tools"   # E:\ = USB drive
```

Transfer to the offline machine via USB or (for Hyper-V) PowerShell Direct:

```powershell
$s = New-PSSession -VMName "OfflineRootCA" -Credential (Get-Credential)
Copy-Item -Path "E:\FedCompliance-Tools\09-OfflineRootCA-Kit" `
          -ToSession $s -Destination "C:\" -Recurse
Remove-PSSession $s
```

### 1.3 Install the Root CA

On the offline machine (open PowerShell as Administrator):

```powershell
# Step 1 — Place the CAPolicy.inf
Copy-Item "C:\09-OfflineRootCA-Kit\Config\CAPolicy.inf" "C:\Windows\CAPolicy.inf"

# Edit CAPolicy.inf before proceeding — update the CRL and AIA URLs to your
# real HTTP server (e.g., http://pki.agency.gov/crl/ and http://pki.agency.gov/aia/)
notepad "C:\Windows\CAPolicy.inf"

# Step 2 — Install the AD CS role
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools

# Step 3 — Configure as Standalone Root CA
Install-AdcsCertificationAuthority `
    -CAType StandaloneRootCA `
    -CACommonName "Agency Root CA" `
    -KeyLength 4096 `
    -HashAlgorithmName SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 20 `
    -Force

# Step 4 — Publish the CRL
certutil -CRL

# Step 5 — Export the Root CA certificate
certutil -ca.cert "C:\RootCA-Export\AgencyRootCA.cer"
```

### 1.4 Transfer the Root CA certificate out

Copy `AgencyRootCA.cer` to the CRL/AIA server and the Issuing CA via USB.
This certificate needs to go into three places on every domain machine:
- `Cert:\LocalMachine\Root` (trusted root)
- `Cert:\LocalMachine\CA` (intermediate — only for issuing CA cert chain)
- Active Directory NTAuth store (enables smart card logon)

```powershell
# On the domain (run as Domain Admin on any domain-joined machine):
certutil -enterprise -addstore NTAuth "C:\AgencyRootCA.cer"
certutil -addstore Root "C:\AgencyRootCA.cer"
```

---

## Phase 2 — Issuing CA (Enterprise Subordinate CA)

The Issuing CA is domain-joined. It issues all the end-user certificates
(smart card logon, admin tokens, VPN client auth).

### 2.1 Prepare the server

```powershell
# Run readiness check first
.\Test-ServerReadiness.ps1 -Role IssuingCA -ExportReport

# Install prerequisite features
Install-WindowsFeature ADCS-Cert-Authority, Web-Server -IncludeManagementTools
Install-Module PSPKI -Force
```

### 2.2 Run the Issuing CA kit

```powershell
# Copy the kit to this server
Copy-Item "E:\FedCompliance-Tools\10-IssuingCA-Kit" "C:\" -Recurse

# Place CAPolicy.inf — edit the CRL/AIA URLs to your real HTTP server first
Copy-Item "C:\10-IssuingCA-Kit\Config\CAPolicy-IssuingCA.inf" "C:\Windows\CAPolicy.inf"
notepad "C:\Windows\CAPolicy.inf"   # update pki.agency.gov URLs

# Initialize the Issuing CA (generates a CSR to send to the Root CA)
# This script walks you through each step
.\10-IssuingCA-Kit\Initialize-IssuingCA.ps1
```

### 2.3 Create certificate templates

```powershell
# Replace with your actual CA server\CA name
.\Lab-Kit\03-DomainController\New-CertificateTemplates.ps1 `
    -CAServer "ca01.agency.gov\Agency Issuing CA" `
    -EnrollmentGroup "Domain Users" `
    -AdminEnrollmentGroup "PKI-Admins"
```

### 2.4 Configure OCSP (optional, recommended)

```powershell
.\Lab-Kit\03-DomainController\Set-OCSPResponder.ps1 `
    -CAServer "ca01.agency.gov\Agency Issuing CA" `
    -OCSPHostname "ocsp.agency.gov"
```

### 2.5 Configure IIS for CRL/AIA publishing

IIS was installed in step 2.1. Configure a virtual directory that serves CRL files:

```powershell
# Create the CRL directory
New-Item -ItemType Directory -Path "C:\inetpub\pki" -Force

# Share it as a virtual directory in IIS
Import-Module WebAdministration
New-WebVirtualDirectory -Site "Default Web Site" -Name "crl" -PhysicalPath "C:\inetpub\pki"
New-WebVirtualDirectory -Site "Default Web Site" -Name "aia" -PhysicalPath "C:\inetpub\pki"

# Configure CA to publish CRLs here
certutil -config "ca01.agency.gov\Agency Issuing CA" `
         -setreg CA\CRLPublicationURLs "1:C:\inetpub\pki\%3%8%9.crl\n2:http://pki.agency.gov/crl/%3%8%9.crl"

# Restart cert services to apply
net stop certsvc && net start certsvc

# Publish CRL immediately
certutil -CRL
```

---

## Phase 3 — Domain Controller (Smart Card GPO)

If your DC is separate from the Issuing CA, run these steps on it.

### 3.1 Check readiness

```powershell
.\Test-ServerReadiness.ps1 -Role DomainController -ExportReport
```

### 3.2 Build the domain (if starting fresh)

```powershell
.\Lab-Kit\03-DomainController\Build-CAC-Lab.ps1 `
    -DomainName "agency.gov" `
    -NetBIOSName "AGENCY"
# Server reboots — wait for it, then:
.\Lab-Kit\03-DomainController\Build-CA-GPO.ps1
```

If the domain already exists, skip Build-CAC-Lab.ps1 and only apply the smart card GPO:

```powershell
.\Lab-Kit\04-Workstation\Enforce-SmartCard.ps1
gpupdate /force
```

### 3.3 Configure audit logging and event forwarding

```powershell
# Set audit policy and configure WEF source on this DC
.\Lab-Kit\03-DomainController\Set-AuditLogForwarding.ps1 `
    -Mode Source `
    -CollectorFQDN "siem.agency.gov"   # replace with your SIEM/collector server
```

---

## Phase 4 — Smart Card Enrollment

Issue smart card certificates to users one at a time through the enrollment ceremony.
The process enforces separation of duties: one person does the identity verification (RA),
a different person issues the certificate (Card Issuer).

### 4.1 Registration Authority phase (run as RA admin)

```powershell
.\Lab-Kit\03-DomainController\New-TokenEnrollment.ps1 `
    -Mode RA `
    -UserPrincipalName "jsmith@agency.gov"
```

The script walks through the identity verification checklist and sets an
authorization flag on the user's AD account.

### 4.2 Card Issuer phase (run as a DIFFERENT admin account)

```powershell
.\Lab-Kit\03-DomainController\New-TokenEnrollment.ps1 `
    -Mode Issuer `
    -UserPrincipalName "jsmith@agency.gov"
```

The script blocks you from issuing if you are the same person who did the RA phase.
Follow the prompts to enroll the certificate and guide the user through PIN setup.

---

## Phase 5 — Workstation Deployment

### 5.1 Join the domain

```powershell
Add-Computer -DomainName "agency.gov" -Credential (Get-Credential) -Restart
```

### 5.2 Apply GPO (after reboot)

```powershell
gpupdate /force
# Verify smart card enforcement applied:
.\Test-ServerReadiness.ps1 -Role Workstation
```

### 5.3 Deploy VPN client (if applicable)

```powershell
.\Lab-Kit\04-Workstation\Deploy-VPNClient.ps1 `
    -VPNServerAddress "vpn.agency.gov" `
    -VPNConnectionName "Agency VPN"
```

---

## Phase 6 — PKI Health Monitoring

Set Monitor-PKIHealth.ps1 as a scheduled task on the Issuing CA server.
It checks CRL validity, OCSP reachability, and certificate expiry on a schedule
and sends an email alert if anything is approaching a failure state.

```powershell
# Test run first
.\Lab-Kit\03-DomainController\Monitor-PKIHealth.ps1 `
    -CRLUrls @("http://pki.agency.gov/crl/RootCA.crl",
               "http://pki.agency.gov/crl/IssuingCA.crl") `
    -OCSPUrl "http://ocsp.agency.gov/ocsp" `
    -IssuingCAServer "ca01.agency.gov" `
    -AlertThresholdDays 60

# Schedule it (example: daily at 6 AM)
$trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
           -Argument "-NonInteractive -File 'C:\Scripts\Monitor-PKIHealth.ps1' ..."
Register-ScheduledTask -TaskName "PKI Health Monitor" -Trigger $trigger `
                        -Action $action -RunLevel Highest
```

---

## Verification Checklist — Before Going Live

Run this after all phases are complete on every server:

```powershell
.\Test-ServerReadiness.ps1 -ExportReport
```

Expected result: all PASS, no FAIL, warnings reviewed and accepted or resolved.

Also manually verify:

- [ ] Smart card logon works for a test account (insert card → domain logon prompt appears)
- [ ] Removing the card locks the session within 2 seconds
- [ ] VPN connects using certificate auth — no password prompt
- [ ] CRL URL is reachable from all endpoints: `certutil -verify -urlfetch <cert.cer>`
- [ ] OCSP responds: `Invoke-WebRequest http://ocsp.agency.gov/ocsp`
- [ ] Monitor-PKIHealth.ps1 reports all green
- [ ] A revoked certificate is blocked within one CRL cycle

---

## Troubleshooting Quick Reference

| Symptom | Where to look | Command |
|---------|--------------|---------|
| Smart card logon rejected | Certificate chain, NTAuth | `certutil -verify -urlfetch user.cer` |
| CRL unreachable | IIS running? DNS resolving? | `certutil -URL http://pki.agency.gov/crl/IssuingCA.crl` |
| Event 4768 failure code 0x19 | Certificate revoked | Check CRL, run `certutil -CRL` on CA |
| Event 4768 failure code 0x25 | Clock skew > 5 min | Sync time: `w32tm /resync /force` |
| GPO not applying | GP link, scope, precedence | `gpresult /r`, check OU link |
| OCSP not responding | OCSPSvc running? | `Get-Service OCSPSvc; Start-Service OCSPSvc` |
| Enrollment fails | Template published? Permissions? | Check `certutil -catemplates` on CA |

---

*Related: `Test-ServerReadiness.ps1` (run before each phase), `Lab-Kit/START-HERE.md` (lab version),*
*`Architecture/FedGov-Tools-Setup-Guide.md` (tool installation), `Architecture/Blueprint.md` (full design)*
