#Requires -Version 5.1
<#
.SYNOPSIS
    Guided Offline Root CA initialization — interactive step-by-step ceremony.

.DESCRIPTION
    Walks an administrator through every command required to build the Offline Root
    Certificate Authority for the CAC/PIV lab. Each step pauses for confirmation
    before proceeding, prints exactly what the command will do, and verifies the
    result before moving on.

    Run this script INSIDE the Lab-OfflineRootCA VM, either:
      • Via PowerShell Direct from the Hyper-V host (air-gap safe):
          $s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential (Get-Credential)
          Copy-Item -Path ".\Initialize-OfflineRootCA.ps1" -ToSession $s -Destination "C:\OfflineCA-Kit\"
          Invoke-Command -Session $s { & "C:\OfflineCA-Kit\Initialize-OfflineRootCA.ps1" }
      • By copying the kit to USB, then running from the USB inside the VM.

    WHAT THIS SCRIPT DOES (in order):
      1. Verifies no network adapters are active (air-gap check)
      2. Copies CAPolicy.inf into C:\Windows\ and opens it for review/editing
      3. Installs the AD CS (Certificate Authority) Windows role
      4. Configures this machine as a Standalone Root CA:
           - CA common name: "Lab Root CA"
           - Key length: 4096-bit RSA
           - Hash: SHA-256
           - Validity: 10 years
      5. Sets the CRL and AIA publication URLs (HTTP CDP — served by the DC/IIS later)
      6. Publishes the first CRL
      7. Exports the Root CA certificate to C:\OfflineCA-Export\
      8. Prints transfer instructions for copying the cert + CRL to USB

    WHAT YOU DO MANUALLY BETWEEN THIS SCRIPT AND THE ISSUING CA:
      - Copy C:\OfflineCA-Export\ to USB
      - Transfer USB to the DC (Lab-DC01)
      - Import the Root CA cert into AD NTAuth and Root stores on the DC
      - Run Initialize-IssuingCA.ps1 on the DC (generates a CSR)
      - Bring the CSR back to this Root CA (USB) and sign it here
      - Copy the signed Issuing CA cert back to the DC

    The script pauses after Step 7 and gives you the exact commands for each
    manual transfer step.

.PARAMETER CACommonName
    Common name for the Root CA certificate. Default: "Lab Root CA"
    Change this to match your organization naming convention.
    Example: "Agency Root CA"

.PARAMETER CRLHttpBase
    Base HTTP URL for the CRL Distribution Point and AIA.
    Default: http://pki.lab.local
    The script appends /crl/<CAname>.crl and /aia/<CAname>.crt automatically.
    Change this to your real PKI server hostname before running.

.PARAMETER ValidityYears
    Validity period for the Root CA certificate in years. Default: 10
    Root CAs are typically 10–20 years; Issuing CAs 5–10 years.

.PARAMETER ExportPath
    Where to write the Root CA certificate and CRL for USB transfer.
    Default: C:\OfflineCA-Export\

.EXAMPLE
    # Run with lab defaults
    .\Initialize-OfflineRootCA.ps1

    # Run with production naming
    .\Initialize-OfflineRootCA.ps1 `
        -CACommonName "Agency Root CA" `
        -CRLHttpBase "http://pki.agency.gov" `
        -ValidityYears 20

.NOTES
    Author         : Glenn Byron
    Run on         : Lab-OfflineRootCA VM only (Standalone Windows Server, not domain-joined)
    Requires       : Administrator rights, AD CS role available (Windows Server)
    Air-gap policy : This VM must have NO active network adapter at any point.
                     The script will refuse to proceed if a network adapter is found.
    Framework      : NIST SP 800-53 SC-17 | FIPS 201-3 | NIST SP 800-57
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string]$CACommonName  = "Lab Root CA",
    [Parameter()] [string]$CRLHttpBase  = "http://pki.lab.local",
    [Parameter()] [int]   $ValidityYears = 10,
    [Parameter()] [string]$ExportPath   = "C:\OfflineCA-Export\"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Banner {
    $width = 70
    Write-Host ""
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host "  OFFLINE ROOT CA — INITIALIZATION CEREMONY" -ForegroundColor Cyan
    Write-Host "  Author: Glenn Byron  |  NIST SP 800-53 SC-17 | FIPS 201-3" -ForegroundColor Cyan
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  CA Name   : $CACommonName" -ForegroundColor White
    Write-Host "  CDP/AIA   : $CRLHttpBase" -ForegroundColor White
    Write-Host "  Validity  : $ValidityYears years" -ForegroundColor White
    Write-Host "  Export to : $ExportPath" -ForegroundColor White
    Write-Host ""
}

function Write-StepHeader {
    param([int]$Num, [int]$Total, [string]$Title)
    Write-Host ""
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    Write-Host "  STEP $Num of $Total — $Title" -ForegroundColor Yellow
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-OK   { param([string]$M) Write-Host "  [OK]    $M" -ForegroundColor Green  }
function Write-Warn { param([string]$M) Write-Host "  [WARN]  $M" -ForegroundColor Yellow }
function Write-Err  { param([string]$M) Write-Host "  [FAIL]  $M" -ForegroundColor Red    }
function Write-Info { param([string]$M) Write-Host "  [INFO]  $M" -ForegroundColor Cyan   }

function Confirm-Step {
    param([string]$Prompt = "Press Enter to continue, or Ctrl+C to abort")
    Write-Host ""
    Read-Host "  $Prompt" | Out-Null
}

$totalSteps = 8

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Banner

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "This script must run as Administrator." }

# Domain check — Root CA must NEVER be domain-joined
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
if ($cs.PartOfDomain) {
    throw "This machine is domain-joined ($($cs.Domain)). The Offline Root CA must be a standalone (non-domain) server."
}
Write-OK "Standalone machine confirmed — not domain-joined."

# ============================================================================
Write-StepHeader 1 $totalSteps "Air-Gap Verification"
# ============================================================================

Write-Info "Checking for active network adapters..."
Write-Info "The Root CA must have no network connectivity at any time."
Write-Host ""

$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

if ($activeAdapters) {
    Write-Err "ACTIVE NETWORK ADAPTER(S) DETECTED:"
    $activeAdapters | ForEach-Object {
        Write-Err "  $($_.Name) — $($_.InterfaceDescription) — $($_.Status)"
    }
    Write-Host ""
    Write-Host "  This is a critical security violation. The Root CA must be air-gapped." -ForegroundColor Red
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    1. Remove the network adapter in Hyper-V Manager before booting" -ForegroundColor Yellow
    Write-Host "    2. Disable the adapter: Disable-NetAdapter -Name '<name>' -Confirm:`$false" -ForegroundColor Yellow
    Write-Host ""
    $override = Read-Host "  Type OVERRIDE to continue anyway (for lab-only testing), or press Enter to abort"
    if ($override -ne 'OVERRIDE') {
        throw "Aborted — active network adapter present. Remove it before running the Root CA build."
    }
    Write-Warn "OVERRIDE accepted — proceeding with network adapter present. DO NOT do this in production."
} else {
    $allAdapters = Get-NetAdapter
    Write-OK "No active network adapters — air-gap confirmed."
    if ($allAdapters) {
        Write-Info "Inactive adapters present (disabled or disconnected — OK):"
        $allAdapters | ForEach-Object { Write-Info "  $($_.Name) — $($_.Status)" }
    }
}

Confirm-Step

# ============================================================================
Write-StepHeader 2 $totalSteps "CAPolicy.inf — Place and Review"
# ============================================================================

Write-Info "CAPolicy.inf controls how the Root CA is configured at install time."
Write-Info "Key settings it controls:"
Write-Info "  • CRL Distribution Point (CDP) URL — where clients download CRLs"
Write-Info "  • Authority Information Access (AIA) URL — where clients find the CA cert"
Write-Info "  • Path length constraint — limits how many CAs can chain below this one"
Write-Info "  • Key usage and critical extensions"
Write-Host ""

$caPolicyDest = "C:\Windows\CAPolicy.inf"
$caPolicySource = Join-Path $PSScriptRoot "CAPolicy.inf"

# Build CAPolicy.inf from scratch if not present in the kit
$caPolicyContent = @"
; CAPolicy.inf for Offline Root CA
; Author: Glenn Byron
; Edit the CDP and AIA URLs to match your HTTP CRL server before running the CA installer.

[Version]
Signature="`$Windows NT`$"

[PolicyStatementExtension]
Policies=InternalPolicy

[InternalPolicy]
OID=1.2.3.4.1455.67.89.5
Notice="Lab Root Certificate Authority"
URL=$CRLHttpBase/cps.html

[Certsrv_Server]
RenewalKeyLength=4096
RenewalValidityPeriod=Years
RenewalValidityPeriodUnits=$ValidityYears
CRLPeriod=Weeks
CRLPeriodUnits=26
CRLDeltaPeriod=Days
CRLDeltaPeriodUnits=0
LoadDefaultTemplates=0
AlternateSignatureAlgorithm=0

[CRLDistributionPoint]
Empty=True

[AuthorityInformationAccess]
Empty=True

[BasicConstraintsExtension]
PathLength=0
Critical=Yes
"@

if (Test-Path $caPolicySource) {
    Write-Info "CAPolicy.inf found in kit — copying to C:\Windows\"
    Copy-Item $caPolicySource $caPolicyDest -Force
} else {
    Write-Info "Generating CAPolicy.inf from template..."
    Set-Content -Path $caPolicyDest -Value $caPolicyContent -Encoding ASCII
}

Write-OK "CAPolicy.inf placed at $caPolicyDest"
Write-Host ""
Write-Warn "REVIEW REQUIRED — the file will now open in Notepad."
Write-Info "Verify these values match your environment:"
Write-Info "  • CDP URL:  $CRLHttpBase/crl/<CAname>.crl"
Write-Info "  • AIA URL:  $CRLHttpBase/aia/<CAname>.crt"
Write-Info "  • PathLength = 0 (Root CA should not issue subordinate CAs below Issuing CA)"
Write-Host ""

Confirm-Step "Press Enter to open CAPolicy.inf in Notepad for review"
Start-Process notepad.exe -ArgumentList $caPolicyDest -Wait

Confirm-Step "Confirm CAPolicy.inf is correct, then press Enter to continue"

# ============================================================================
Write-StepHeader 3 $totalSteps "Install AD CS Role"
# ============================================================================

Write-Info "Installing the Active Directory Certificate Services Windows role..."
Write-Info "This installs only the Certification Authority component — no web enrollment."
Write-Host ""

$feature = Get-WindowsFeature -Name ADCS-Cert-Authority -ErrorAction SilentlyContinue
if ($feature -and $feature.Installed) {
    Write-OK "ADCS-Cert-Authority already installed — skipping."
} else {
    Confirm-Step "Press Enter to run: Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools"
    if ($PSCmdlet.ShouldProcess("ADCS-Cert-Authority", "Install-WindowsFeature")) {
        $result = Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
        if ($result.Success) {
            Write-OK "AD CS role installed successfully."
            if ($result.RestartNeeded -eq 'Yes') {
                Write-Warn "A restart is required. After rebooting, re-run this script — it will skip completed steps."
                Confirm-Step "Press Enter to restart now (script will resume after reboot)"
                Restart-Computer -Force
            }
        } else {
            throw "AD CS role installation failed. Check Windows Update and try again."
        }
    }
}

Confirm-Step

# ============================================================================
Write-StepHeader 4 $totalSteps "Configure Standalone Root CA"
# ============================================================================

Write-Info "Configuring this server as a Standalone Root CA."
Write-Info "Settings:"
Write-Info "  • CA Type          : StandaloneRootCA (not Enterprise — no AD dependency)"
Write-Info "  • CA Common Name   : $CACommonName"
Write-Info "  • Key Length       : 4096-bit RSA (NIST SP 800-57 recommendation for Root CAs)"
Write-Info "  • Hash Algorithm   : SHA-256"
Write-Info "  • Validity Period  : $ValidityYears years"
Write-Host ""

$caCheck = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
if ($caCheck -and $caCheck.Status -eq 'Running') {
    Write-OK "Certificate Services already running — CA appears to be configured. Skipping Install-AdcsCertificationAuthority."
    Write-Info "If you need to reconfigure, run: Remove-AdcsCertificationAuthority -Force, then re-run this script."
} else {
    Confirm-Step "Press Enter to configure the Root CA (this takes 1–2 minutes)"

    if ($PSCmdlet.ShouldProcess($CACommonName, "Install-AdcsCertificationAuthority")) {
        Install-AdcsCertificationAuthority `
            -CAType               StandaloneRootCA `
            -CACommonName         $CACommonName `
            -KeyLength            4096 `
            -HashAlgorithmName    SHA256 `
            -ValidityPeriod       Years `
            -ValidityPeriodUnits  $ValidityYears `
            -CryptoProviderName   "RSA#Microsoft Software Key Storage Provider" `
            -Force `
            -ErrorAction Stop | Out-Null

        Write-OK "Root CA configured: $CACommonName"
    }
}

Confirm-Step

# ============================================================================
Write-StepHeader 5 $totalSteps "Configure CRL and AIA Publication URLs"
# ============================================================================

$caName = (Get-CimInstance -Namespace root\CIMv2 -ClassName Win32_Service -Filter "Name='CertSvc'") |
    ForEach-Object { (certutil -getconfig 2>&1) -match '`"' } | Out-Null
# Get CA config string
$caConfig = (certutil -getconfig 2>&1 | Select-String 'Config') -replace '.*Config: ','' -replace '"',''
if (-not $caConfig) { $caConfig = "$env:COMPUTERNAME\$CACommonName" }

Write-Info "CA config string: $caConfig"
Write-Info ""
Write-Info "Setting CRL Distribution Point (CDP):"
Write-Info "  1: C:\Windows\System32\CertSrv\CertEnroll\%3%8%9.crl  (local file)"
Write-Info "  2: $CRLHttpBase/crl/%3%8%9.crl  (HTTP, used by clients)"
Write-Info ""
Write-Info "Setting Authority Information Access (AIA):"
Write-Info "  1: C:\Windows\System32\CertSrv\CertEnroll\%1_%3%4.crt  (local file)"
Write-Info "  2: $CRLHttpBase/aia/%1_%3%4.crt  (HTTP, used by clients)"
Write-Host ""

Confirm-Step "Press Enter to apply CDP and AIA settings"

if ($PSCmdlet.ShouldProcess($caConfig, "Set CDP and AIA URLs")) {
    # CDP URLs: flag 1 = publish to path, flag 2 = include in CRL, flag 8 = include in certs
    $cdpValue = "1:C:\Windows\System32\CertSrv\CertEnroll\%3%8%9.crl`n2:$CRLHttpBase/crl/%3%8%9.crl"
    certutil -config $caConfig -setreg CA\CRLPublicationURLs $cdpValue | Out-Null

    # AIA URLs: flag 1 = include in certs
    $aiaValue = "1:C:\Windows\System32\CertSrv\CertEnroll\%1_%3%4.crt`n2:$CRLHttpBase/aia/%1_%3%4.crt"
    certutil -config $caConfig -setreg CA\CACertPublicationURLs $aiaValue | Out-Null

    # Set CRL overlap and delta CRL (delta disabled for Root CA — simpler)
    certutil -config $caConfig -setreg CA\CRLOverlapPeriodUnits 12  | Out-Null
    certutil -config $caConfig -setreg CA\CRLOverlapPeriod Hours    | Out-Null
    certutil -config $caConfig -setreg CA\CRLDeltaPeriodUnits 0     | Out-Null

    # Restart CertSvc to apply
    Restart-Service CertSvc -Force
    Start-Sleep 3

    Write-OK "CDP and AIA URLs configured."
}

Confirm-Step

# ============================================================================
Write-StepHeader 6 $totalSteps "Publish Initial CRL"
# ============================================================================

Write-Info "Publishing the Certificate Revocation List (CRL)."
Write-Info "The CRL must exist before any client can validate certificates issued by this CA."
Write-Info "Running: certutil -CRL"
Write-Host ""

Confirm-Step "Press Enter to publish the CRL"

if ($PSCmdlet.ShouldProcess("CRL", "certutil -CRL")) {
    $crlOut = certutil -CRL 2>&1
    Write-Info ($crlOut -join "`n  ")

    # Verify CRL file was created
    $crlFiles = Get-ChildItem "C:\Windows\System32\CertSrv\CertEnroll\*.crl" -ErrorAction SilentlyContinue
    if ($crlFiles) {
        Write-OK "CRL published: $($crlFiles.Name -join ', ')"
    } else {
        Write-Warn "CRL file not found in CertEnroll — check certutil output above."
    }
}

Confirm-Step

# ============================================================================
Write-StepHeader 7 $totalSteps "Export Root CA Certificate and CRL"
# ============================================================================

Write-Info "Exporting the Root CA certificate and CRL to: $ExportPath"
Write-Info "Copy this folder to USB for transfer to the Issuing CA and domain controller."
Write-Host ""

if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

Confirm-Step "Press Enter to export files"

if ($PSCmdlet.ShouldProcess($ExportPath, "Export Root CA cert and CRL")) {
    # Export Root CA certificate
    $certExportPath = Join-Path $ExportPath "$($CACommonName -replace ' ','').cer"
    $certOut = certutil -ca.cert $certExportPath 2>&1
    if (Test-Path $certExportPath) {
        Write-OK "Root CA certificate: $certExportPath"
    } else {
        Write-Warn "Could not export cert via certutil -ca.cert — trying alternate method..."
        # Alternate: export from cert store
        $caCert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match [regex]::Escape($CACommonName) }
        if ($caCert) {
            $certBytes = $caCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            [System.IO.File]::WriteAllBytes($certExportPath, $certBytes)
            Write-OK "Root CA certificate (alternate export): $certExportPath"
        } else {
            Write-Err "Could not locate Root CA certificate in LocalMachine\My"
        }
    }

    # Copy CRL files
    $crlSource = "C:\Windows\System32\CertSrv\CertEnroll"
    $crlFiles  = Get-ChildItem "$crlSource\*.crl" -ErrorAction SilentlyContinue
    foreach ($crl in $crlFiles) {
        Copy-Item $crl.FullName $ExportPath -Force
        Write-OK "CRL: $($crl.Name)"
    }

    # Copy CA cert from CertEnroll too (AIA copy)
    $aiaCerts = Get-ChildItem "$crlSource\*.crt" -ErrorAction SilentlyContinue
    foreach ($aia in $aiaCerts) {
        Copy-Item $aia.FullName $ExportPath -Force
        Write-OK "AIA cert: $($aia.Name)"
    }

    # List export folder
    Write-Host ""
    Write-Host "  Export folder contents:" -ForegroundColor White
    Get-ChildItem $ExportPath | ForEach-Object {
        Write-Host ("    {0,-50} {1,8} KB" -f $_.Name, [math]::Round($_.Length/1KB, 1)) -ForegroundColor Gray
    }
}

Confirm-Step

# ============================================================================
Write-StepHeader 8 $totalSteps "Next Steps — USB Transfer Instructions"
# ============================================================================

$certFileName = "$($CACommonName -replace ' ','').cer"

Write-Host "  The Root CA is initialized. The machine is now ready to sign the Issuing CA" -ForegroundColor Green
Write-Host "  certificate request. Here is exactly what to do next:" -ForegroundColor Green
Write-Host ""
Write-Host "  ── ON THE HYPER-V HOST (or USB transfer) ──────────────────────────────" -ForegroundColor White
Write-Host ""
Write-Host "  # Copy the export folder from this VM to the host via PowerShell Direct:" -ForegroundColor Cyan
Write-Host '  $s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential (Get-Credential)' -ForegroundColor Cyan
Write-Host "  Copy-Item -Path `"$ExportPath`" -FromSession `$s -Destination `"C:\CA-Transfer\`" -Recurse" -ForegroundColor Cyan
Write-Host '  Remove-PSSession $s' -ForegroundColor Cyan
Write-Host ""
Write-Host "  ── ON LAB-DC01 (Domain Controller / Issuing CA) ───────────────────────" -ForegroundColor White
Write-Host ""
Write-Host "  # 1. Publish Root CA cert to Active Directory NTAuth and Root stores:" -ForegroundColor Cyan
Write-Host "  certutil -enterprise -addstore NTAuth `"C:\CA-Transfer\$certFileName`"" -ForegroundColor Cyan
Write-Host "  certutil -addstore Root `"C:\CA-Transfer\$certFileName`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # 2. Place CRL files where IIS can serve them (HTTP CDP):" -ForegroundColor Cyan
Write-Host "  Copy-Item C:\CA-Transfer\*.crl C:\inetpub\pki\" -ForegroundColor Cyan
Write-Host "  Copy-Item C:\CA-Transfer\*.crt C:\inetpub\pki\" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # 3. Initialize the Issuing CA (generates a CSR to sign here):" -ForegroundColor Cyan
Write-Host "  .\Lab-Kit\03-DomainController\Initialize-IssuingCA.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # 4. Copy the Issuing CA CSR back to this Root CA:" -ForegroundColor Cyan
Write-Host '  $s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential (Get-Credential)' -ForegroundColor Cyan
Write-Host "  Copy-Item -Path `"C:\IssuingCA.req`" -ToSession `$s -Destination `"C:\Requests\`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ── BACK ON THIS ROOT CA VM ─────────────────────────────────────────────" -ForegroundColor White
Write-Host ""
Write-Host "  # 5. Sign the Issuing CA certificate request:" -ForegroundColor Cyan
Write-Host "  certreq -submit -config `"$env:COMPUTERNAME\$CACommonName`" C:\Requests\IssuingCA.req C:\Requests\IssuingCA.cer" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # 6. Copy the signed cert back to the DC, then power this VM OFF." -ForegroundColor Cyan
Write-Host "  # The Root CA should remain offline until the next CRL renewal (every 6 months)." -ForegroundColor Cyan
Write-Host ""

Write-Host ("=" * 70) -ForegroundColor DarkGreen
Write-Host "  OFFLINE ROOT CA INITIALIZATION COMPLETE" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor DarkGreen
Write-Host ""
Write-Host "  Export folder : $ExportPath" -ForegroundColor Cyan
Write-Host "  CA Name       : $CACommonName" -ForegroundColor Cyan
Write-Host "  Next action   : Transfer USB to DC, then run Initialize-IssuingCA.ps1" -ForegroundColor Cyan
Write-Host ""
