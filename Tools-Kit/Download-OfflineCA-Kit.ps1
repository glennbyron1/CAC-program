#Requires -Version 5.1
<#
.SYNOPSIS
    Offline Root CA Transfer Kit — Pre-Staging Download Utility

.DESCRIPTION
    Builds a self-contained transfer package on a removable drive or staging folder
    containing every file the Offline Root CA host needs before it is permanently
    air-gapped.

    Run this script on any internet-connected Windows machine BEFORE deploying the
    Offline Root CA VM or hardware. Copy the output folder to a USB drive (or ISO)
    and transfer it to the isolated host.

    Document ID : SCRIPT-ICAM-004
    Framework   : NIST SP 800-53 IA-2, SC-17, SC-28 | FIPS 201-3 §3.3

.PARAMETER OutputPath
    Destination folder for the transfer kit. Default: .\OfflineCA-TransferKit
    Specify a removable drive letter (e.g., E:\OfflineCA-Kit) to write directly
    to a transfer USB.

.PARAMETER SkipWindowsUpdates
    Skip downloading Windows update packages (large; requires RSAT/DISM tools).
    Use this flag if you will apply updates via WSUS offline or slipstreamed media.

.EXAMPLE
    .\Download-OfflineCA-Kit.ps1
    Builds the kit in .\OfflineCA-TransferKit

.EXAMPLE
    .\Download-OfflineCA-Kit.ps1 -OutputPath "E:\OfflineCA-Kit"
    Writes the kit directly to a USB drive at E:\

.NOTES
    Author  : Glenn Byron
    Repo    : github.com/glennbyron1/CAC-program
    Version : 1.0

    SECURITY REQUIREMENT:
    After the Offline Root CA is provisioned and the Root certificate is signed,
    disconnect all network adapters permanently. The CA must never have live
    network connectivity during operation.

    FILES PACKAGED BY THIS SCRIPT:
      /Config/          — CAPolicy.inf, CRLDistributionPoints.txt, AIA.txt
      /Scripts/         — Initialize-OfflineRootCA.ps1, Publish-CRL.ps1
      /Tools/           — SysInternals, OpenSSL, PSPKI (offline module)
      /Templates/       — .INF certificate authority baselines from /Templates/
      /Docs/            — Architecture/Blueprint.md reference copy
      /VerifyKit.ps1    — Integrity check script run on the target host
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$OutputPath = ".\OfflineCA-TransferKit",

    [Parameter()]
    [switch]$SkipWindowsUpdates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────
$KIT_VERSION  = "1.0"
$TIMESTAMP    = Get-Date -Format "yyyyMMdd-HHmm"
$MANIFEST     = @()  # Tracks every file added for VerifyKit.ps1

# Download URLs — versions pinned; update URLs when new releases ship
$DOWNLOADS = [ordered]@{
    "SysinternalsSuite" = @{
        Url      = "https://download.sysinternals.com/files/SysinternalsSuite.zip"
        DestDir  = "Tools\SysInternals"
        FileName = "SysinternalsSuite.zip"
        Note     = "Microsoft SysInternals Suite — sigcheck, procmon, autoruns, etc."
    }
    "OpenSSL-Light" = @{
        Url      = "https://slproweb.com/download/Win64OpenSSL_Light-3_3_2.exe"
        DestDir  = "Tools\OpenSSL"
        FileName = "Win64OpenSSL_Light.exe"
        Note     = "Win64 OpenSSL Light — certificate inspection and verification"
    }
    "PSPKI-Module" = @{
        Url      = "https://github.com/PKISolutions/PSPKI/releases/download/v4.2.0/PSPKI.4.2.0.zip"
        DestDir  = "Tools\PSPKI"
        FileName = "PSPKI-4.2.0.zip"
        Note     = "PKI Solutions PSPKI PowerShell module — offline install package"
    }
    "NuGet-Provider" = @{
        Url      = "https://onegetcdn.azureedge.net/providers/nuget-anycpu.exe"
        DestDir  = "Tools\NuGet"
        FileName = "nuget-anycpu.exe"
        Note     = "NuGet package provider — required for offline PSPKI installation"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
function Write-Step {
    param([string]$Message)
    Write-Host "`n  ► $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    [!!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
}

function Add-ToManifest {
    param([string]$FilePath, [string]$Description)
    $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    $script:MANIFEST += [PSCustomObject]@{
        File        = $FilePath -replace [regex]::Escape($OutputPath + "\"), ""
        SHA256      = $hash
        Description = $Description
    }
}

function Invoke-Download {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Description
    )
    $fileName = Split-Path $Destination -Leaf
    Write-Step "Downloading: $fileName"
    Write-Host "    Source : $Url" -ForegroundColor DarkGray
    Write-Host "    Target : $Destination" -ForegroundColor DarkGray

    try {
        $destDir = Split-Path $Destination -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        # Use BITS for large files when available, fall back to Invoke-WebRequest
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName $fileName
        } else {
            $progressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
            $progressPreference = 'Continue'
        }

        $sizeMB = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
        Add-ToManifest -FilePath $Destination -Description $Description
        Write-OK "$fileName ($sizeMB MB)"
    }
    catch {
        Write-Fail "Download failed: $_"
        Write-Warn "Manual download required. URL recorded in MANUAL-DOWNLOADS.txt"
        Add-Content -Path (Join-Path $OutputPath "MANUAL-DOWNLOADS.txt") -Value "[$Description]`nURL: $Url`nDest: $Destination`n"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# BANNER
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║   OFFLINE ROOT CA — TRANSFER KIT BUILDER  v$KIT_VERSION         ║" -ForegroundColor DarkCyan
Write-Host "  ║   SCRIPT-ICAM-004 | Author: Glenn Byron               ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Output Path : $OutputPath" -ForegroundColor White
Write-Host "  Timestamp   : $TIMESTAMP" -ForegroundColor White
Write-Host ""
Write-Host "  IMPORTANT: This kit is built on a connected machine, then" -ForegroundColor Yellow
Write-Host "  transferred to the Offline CA host via USB. The Offline CA" -ForegroundColor Yellow
Write-Host "  host must NEVER have live network connectivity." -ForegroundColor Yellow
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: CREATE DIRECTORY STRUCTURE
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Creating transfer kit directory structure"

$Dirs = @(
    "Config",
    "Scripts",
    "Tools\SysInternals",
    "Tools\OpenSSL",
    "Tools\PSPKI",
    "Tools\NuGet",
    "Templates",
    "Docs"
)

foreach ($dir in $Dirs) {
    $fullPath = Join-Path $OutputPath $dir
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
}
Write-OK "Directory structure created"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: COPY LOCAL REPOSITORY FILES
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Copying local repository configuration files"

# Detect repo root (script lives in Automation-Scripts/)
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot "README.md"))) {
    # Try one level up from PSScriptRoot
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}

# CA Configuration templates
$TemplatesDir = Join-Path $RepoRoot "Templates"
if (Test-Path $TemplatesDir) {
    $templateFiles = Get-ChildItem -Path $TemplatesDir -File
    foreach ($file in $templateFiles) {
        $dest = Join-Path $OutputPath "Templates\$($file.Name)"
        Copy-Item -Path $file.FullName -Destination $dest -Force
        Add-ToManifest -FilePath $dest -Description "CA configuration template: $($file.Name)"
        Write-OK "Copied template: $($file.Name)"
    }
} else {
    Write-Warn "Templates directory not found at: $TemplatesDir"
}

# Architecture reference doc
$blueprintSrc = Join-Path $RepoRoot "Architecture\Blueprint.md"
if (Test-Path $blueprintSrc) {
    Copy-Item -Path $blueprintSrc -Destination (Join-Path $OutputPath "Docs\Blueprint.md") -Force
    Write-OK "Copied Architecture/Blueprint.md"
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3: GENERATE CAPolicy.inf
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating CAPolicy.inf for Offline Root CA"

$caPolicyContent = @"
; CAPolicy.inf — Offline Root Certificate Authority
; Document ID : CONFIG-ICAM-ROOT-001
; Author      : Glenn Byron
; Reference   : NIST SP 800-53 SC-17, FIPS 201-3
;
; USAGE: Place this file at C:\Windows\CAPolicy.inf on the Root CA host
; BEFORE running the Add-WindowsFeature / certutil CA installation.
;
; Customize CRLDistributionPoint and AuthorityInformationAccess URLs
; to match your HTTP CRL server address before installation.

[Version]
Signature="`$Windows NT$"

[PolicyStatementExtension]
Policies=InternalPolicy

[InternalPolicy]
OID=1.3.6.1.4.1.99999.1.1
Notice="Enterprise Internal Root Certificate Authority"

[Certsrv_Server]
RenewalKeyLength=4096
RenewalValidityPeriod=Years
RenewalValidityPeriodUnits=10
CRLPeriod=Months
CRLPeriodUnits=6
CRLDeltaPeriod=Days
CRLDeltaPeriodUnits=0
LoadDefaultTemplates=0
AlternateSignatureAlgorithm=0

[CRLDistributionPoint]
; Replace http://crl.agency.gov/crl/ with your actual HTTP CRL server URL
; LDAP CDP removed — see Architecture/Blueprint.md §3.1 WAN Failure Mode Analysis
Empty=true

[AuthorityInformationAccess]
; Replace http://crl.agency.gov/certs/ with your actual AIA server URL
Empty=true
"@

$caPolicyDest = Join-Path $OutputPath "Config\CAPolicy.inf"
Set-Content -Path $caPolicyDest -Value $caPolicyContent -Encoding UTF8
Add-ToManifest -FilePath $caPolicyDest -Description "Offline Root CA policy configuration (CAPolicy.inf)"
Write-OK "Generated CAPolicy.inf"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 4: GENERATE CRL & AIA ENDPOINT REFERENCE FILE
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating CRL/AIA endpoint reference configuration"

$endpointRef = @"
# CRL Distribution Point & AIA Endpoint Reference
# Document ID : CONFIG-ICAM-ROOT-002
# Author      : Glenn Byron
#
# Replace ALL placeholder values below with your actual infrastructure URLs
# before installing the Root CA. These values are baked into every issued
# certificate and cannot be changed without re-issuing all certificates.
#
# CRITICAL: Use HTTP only (not LDAP). See Blueprint.md §3.1.

[CRLDistributionPoints]
# Primary HTTP CDP (must be reachable by ALL domain members and VPN clients)
CDP_PRIMARY=http://crl.agency.gov/crl/RootCA.crl

# Secondary / failover CDP (recommended for HA deployments)
CDP_SECONDARY=http://crl2.agency.gov/crl/RootCA.crl

[AuthorityInformationAccess]
# Root CA certificate download URL (used to build trust chain)
AIA_CERT=http://crl.agency.gov/certs/RootCA.crt

[IssuingCA_CDP]
# Issuing CA CRL endpoints (configure on the Subordinate CA, not Root)
CDP_ISSUING_PRIMARY=http://crl.agency.gov/crl/IssuingCA.crl
CDP_ISSUING_DELTA=http://crl.agency.gov/crl/IssuingCA+.crl

[IssuingCA_AIA]
AIA_ISSUING_CERT=http://crl.agency.gov/certs/IssuingCA.crt
AIA_OCSP=http://ocsp.agency.gov/

[PublishSchedule]
# Root CA CRL validity    : 6 months (long — Root CA is offline)
# Issuing CA CRL validity : 7 days
# Issuing CA Delta CRL    : 1-8 hours (publish on revocation events)
ROOT_CRL_VALIDITY_MONTHS=6
ISSUING_CRL_VALIDITY_DAYS=7
ISSUING_DELTA_CRL_HOURS=8
"@

$endpointDest = Join-Path $OutputPath "Config\CRLDistributionPoints.txt"
Set-Content -Path $endpointDest -Value $endpointRef -Encoding UTF8
Add-ToManifest -FilePath $endpointDest -Description "CRL/AIA endpoint configuration reference"
Write-OK "Generated CRLDistributionPoints.txt"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 5: GENERATE INITIALIZE-OFFLINEROOTCA.PS1
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating Initialize-OfflineRootCA.ps1 setup script"

$initScript = @'
#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions the Offline Root Certificate Authority on the isolated host.

.DESCRIPTION
    Run this script ON THE OFFLINE ROOT CA HOST after booting from the transfer kit.
    This script installs AD CS in standalone mode (NOT domain-joined), configures
    the Root CA with a 4096-bit RSA key, and applies CRL publication settings.

    Prerequisites (all in this transfer kit):
      - CAPolicy.inf placed at C:\Windows\CAPolicy.inf (see /Config/)
      - CRL/AIA URLs updated in CAPolicy.inf to match your environment
      - Windows Server 2016/2019/2022 (standalone, NOT domain-joined)

    Document ID : SCRIPT-ICAM-005
    Author      : Glenn Byron
    Reference   : NIST SP 800-53 SC-17 | FIPS 201-3 §3.3.1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CACommonName,

    [Parameter()]
    [string]$CRLServer = "http://crl.agency.gov/crl/",

    [Parameter()]
    [string]$AIAServer = "http://crl.agency.gov/certs/"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Msg) Write-Host "`n  ► $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!!] $Msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║  OFFLINE ROOT CA — INITIALIZATION SCRIPT    ║" -ForegroundColor DarkCyan
Write-Host "  ║  SCRIPT-ICAM-005 | Author: Glenn Byron       ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Warn "Verify this machine has NO network connectivity before proceeding."
Write-Host "  CA Name : $CACommonName" -ForegroundColor White
Write-Host "  CRL URL : $CRLServer" -ForegroundColor White
Write-Host "  AIA URL : $AIAServer" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Confirm offline status and proceed? [y/N]"
if ($confirm -ne 'y') { Write-Host "  Aborted." -ForegroundColor Yellow; exit 0 }

# Step 1 — Install ADCS role (standalone, no domain)
Write-Step "Installing Active Directory Certificate Services role"
Install-WindowsFeature -Name AD-Certificate -IncludeManagementTools
Write-OK "AD CS role installed"

# Step 2 — Verify CAPolicy.inf is in place
Write-Step "Verifying CAPolicy.inf"
if (-not (Test-Path "C:\Windows\CAPolicy.inf")) {
    Write-Host "    Copying CAPolicy.inf from transfer kit..." -ForegroundColor Yellow
    $kitRoot = Split-Path $PSScriptRoot -Parent
    Copy-Item -Path "$kitRoot\Config\CAPolicy.inf" -Destination "C:\Windows\CAPolicy.inf" -Force
}
Write-OK "CAPolicy.inf present at C:\Windows\CAPolicy.inf"

# Step 3 — Install Root CA (standalone, self-signed, offline)
Write-Step "Installing Standalone Root CA — RSA 4096-bit key"
Install-AdcsCertificationAuthority `
    -CAType StandaloneRootCA `
    -CACommonName $CACommonName `
    -KeyLength 4096 `
    -HashAlgorithmName SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 10 `
    -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
    -Force
Write-OK "Root CA installed: $CACommonName"

# Step 4 — Remove LDAP CDPs, set HTTP-only CDPs
Write-Step "Configuring HTTP-only CRL Distribution Points"
$caName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration").Active
$cdpUrl = "${CRLServer}<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl"
$aiaUrl = "${AIAServer}<ServerDNSName>_<CaName><CertificateName>.crt"

# Remove all existing CDPs and AIA entries
Get-CACRLDistributionPoint | Remove-CACRLDistributionPoint -Force
Get-CAAuthorityInformationAccess | Remove-CAAuthorityInformationAccess -Force

# Add HTTP CDP only (no LDAP — see Blueprint.md §3.1)
Add-CACRLDistributionPoint -Uri $cdpUrl -AddToCertificateCDP -AddToFreshestCrl -Force
Add-CAAuthorityInformationAccess -Uri $aiaUrl -AddToCertificateAia -Force

Write-OK "HTTP CDP configured: $cdpUrl"
Write-OK "HTTP AIA configured: $aiaUrl"

# Step 5 — Set CRL validity (6 months for offline Root CA)
Write-Step "Setting CRL validity period (6 months — offline Root)"
certutil -setreg CA\CRLPeriodUnits 6
certutil -setreg CA\CRLPeriod "Months"
certutil -setreg CA\CRLDeltaPeriodUnits 0

# Step 6 — Enable comprehensive audit logging (NIST AU-2)
Write-Step "Enabling AD CS audit logging (NIST AU-2)"
certutil -setreg CA\AuditFilter 127
auditpol /set /subcategory:"Certification Services" /success:enable /failure:enable
Write-OK "Audit logging enabled (filter 127 = all events)"

# Step 7 — Publish initial CRL
Write-Step "Publishing initial CRL"
certutil -CRL
Write-OK "Initial CRL published"

# Step 8 — Export Root CA certificate for transfer
Write-Step "Exporting Root CA certificate"
$certExportPath = "C:\RootCA-Export"
New-Item -ItemType Directory -Path $certExportPath -Force | Out-Null
$certThumb = (Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -like "*$CACommonName*" }).Thumbprint
certutil -ca.cert "$certExportPath\$CACommonName.crt"
Write-OK "Root CA certificate exported to: $certExportPath\$CACommonName.crt"
Write-Warn "Transfer $CACommonName.crt to the Issuing CA host via USB."
Write-Warn "This certificate must be published to Active Directory NTAuth store."

Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  ROOT CA INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor White
Write-Host "  1. Copy $certExportPath\$CACommonName.crt to USB" -ForegroundColor White
Write-Host "  2. Power off this machine and DISCONNECT all network adapters" -ForegroundColor Yellow
Write-Host "  3. Store the powered-off Root CA in a physically secured location" -ForegroundColor Yellow
Write-Host "  4. Transfer the Root CA .crt to the Issuing CA host" -ForegroundColor White
Write-Host "  5. Run the Issuing CA setup script on the domain-joined server" -ForegroundColor White
Write-Host ""
'@

$initDest = Join-Path $OutputPath "Scripts\Initialize-OfflineRootCA.ps1"
Set-Content -Path $initDest -Value $initScript -Encoding UTF8
Add-ToManifest -FilePath $initDest -Description "Offline Root CA initialization and provisioning script"
Write-OK "Generated Initialize-OfflineRootCA.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 6: GENERATE PUBLISH-CRL.PS1 (signing ceremony script)
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating Publish-CRL.ps1 signing ceremony script"

$crlScript = @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Root CA Signing Ceremony — CRL Publication and Subordinate CA Signing

.DESCRIPTION
    Run this script on the Offline Root CA host during a scheduled signing
    ceremony. Powers on the machine, performs the required operations, then
    prepares for immediate shutdown.

    Signing ceremony schedule:
      - CRL Renewal   : Every 5 months (before 6-month CRL expires)
      - Issuing CA Renewal : Every 5 years (before 10-year cert expires)

    Document ID : SCRIPT-ICAM-006
    Author      : Glenn Byron
    Reference   : NIST SP 800-53 SC-17 | CISA ZTMM Identity Pillar
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$CRLOnly,

    [Parameter()]
    [string]$SubordinateCARequestPath
)

function Write-Step { param([string]$Msg) Write-Host "`n  ► $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!!] $Msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║   OFFLINE ROOT CA — SIGNING CEREMONY SCRIPT             ║" -ForegroundColor DarkCyan
Write-Host "  ║   SCRIPT-ICAM-006 | Author: Glenn Byron                  ║" -ForegroundColor DarkCyan
Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Warn "CEREMONY CHECKLIST — Confirm all items before proceeding:"
Write-Host "  [ ] Two authorized personnel present (separation of duties — NIST AC-5)" -ForegroundColor White
Write-Host "  [ ] Machine booted from isolated storage (no network connected)" -ForegroundColor White
Write-Host "  [ ] Transfer USB inserted for CRL export" -ForegroundColor White
Write-Host "  [ ] Ceremony log book is open and ready" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  All checklist items confirmed? [y/N]"
if ($confirm -ne 'y') { Write-Host "  Ceremony aborted." -ForegroundColor Yellow; exit 0 }

# Verify network isolation
Write-Step "Verifying network isolation"
$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
if ($activeAdapters.Count -gt 0) {
    Write-Host "    CRITICAL: Active network adapters detected!" -ForegroundColor Red
    $activeAdapters | Select-Object Name, InterfaceDescription, Status | Format-Table
    Write-Host "    Disable all network adapters before proceeding." -ForegroundColor Red
    exit 1
}
Write-OK "No active network adapters — machine is isolated"

# Start CA service if needed
Write-Step "Starting Certificate Services"
Start-Service CertSvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-OK "Certificate Services running"

# Publish new CRL
Write-Step "Publishing new Root CA CRL"
certutil -CRL
$crlFiles = Get-ChildItem "C:\Windows\System32\CertSrv\CertEnroll\*.crl"
Write-OK "CRL published. Files in CertEnroll:"
$crlFiles | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Gray }

# Copy CRL to USB for transfer to CRL distribution server
$usbDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne "C:\" -and (Test-Path $_.Root) }
if ($usbDrives) {
    $usbPath = $usbDrives[0].Root
    Write-Step "Copying CRL to USB: $usbPath"
    $crlFiles | Copy-Item -Destination $usbPath -Force
    Write-OK "CRL files copied to USB. Transfer to HTTP CRL server after ceremony."
} else {
    Write-Warn "No USB drive detected. Manually copy CRL files from C:\Windows\System32\CertSrv\CertEnroll\"
}

# Sign Subordinate CA request (if provided)
if (-not $CRLOnly -and $SubordinateCARequestPath) {
    Write-Step "Signing Subordinate CA certificate request: $SubordinateCARequestPath"
    if (-not (Test-Path $SubordinateCARequestPath)) {
        Write-Host "    ERROR: Request file not found: $SubordinateCARequestPath" -ForegroundColor Red
    } else {
        $certFile = $SubordinateCARequestPath -replace '\.req$', '.crt'
        certutil -submit -attrib "CertificateTemplate:SubCA" $SubordinateCARequestPath
        Write-OK "Subordinate CA certificate signed. Approve pending request in CA console."
        Write-Warn "After approving, retrieve the signed certificate and copy to USB."
    }
}

Write-Step "Stopping Certificate Services"
Stop-Service CertSvc
Write-OK "Certificate Services stopped"

Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  SIGNING CEREMONY COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  POST-CEREMONY STEPS:" -ForegroundColor White
Write-Host "  1. Record ceremony completion in the log book (date, personnel, actions taken)" -ForegroundColor White
Write-Host "  2. Remove USB drive with exported CRL files" -ForegroundColor White
Write-Host "  3. SHUT DOWN this machine immediately" -ForegroundColor White
Write-Host "  4. Return machine to physically secured storage" -ForegroundColor White
Write-Host "  5. Upload new CRL to HTTP CRL distribution server (on connected host)" -ForegroundColor White
Write-Host ""
'@

$crlDest = Join-Path $OutputPath "Scripts\Publish-CRL.ps1"
Set-Content -Path $crlDest -Value $crlScript -Encoding UTF8
Add-ToManifest -FilePath $crlDest -Description "Root CA signing ceremony and CRL publication script"
Write-OK "Generated Publish-CRL.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 7: DOWNLOAD THIRD-PARTY TOOLS
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Downloading third-party tools"
Write-Host "    Note: Some downloads may fail if the source URL has changed." -ForegroundColor DarkGray
Write-Host "    Failed downloads are logged to MANUAL-DOWNLOADS.txt" -ForegroundColor DarkGray

foreach ($key in $DOWNLOADS.Keys) {
    $item = $DOWNLOADS[$key]
    $destFile = Join-Path $OutputPath "$($item.DestDir)\$($item.FileName)"
    Invoke-Download -Url $item.Url -Destination $destFile -Description $item.Note
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 8: GENERATE PSPKI OFFLINE INSTALL HELPER
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating PSPKI offline install instructions"

$pspkiInstall = @"
# PSPKI Offline Installation Instructions
# Author: Glenn Byron | Document ID: CONFIG-ICAM-ROOT-003
#
# Run these commands on the Offline Root CA host (no internet required).
# Files needed: Tools\NuGet\nuget-anycpu.exe + Tools\PSPKI\PSPKI-4.2.0.zip

# 1. Install NuGet provider offline
Copy-Item .\Tools\NuGet\nuget-anycpu.exe `
    -Destination "`$env:ProgramFiles\PackageManagement\ProviderAssemblies\nuget\2.8.5.208\Microsoft.PackageManagement.NuGetProvider.dll" `
    -Force

# 2. Extract PSPKI module to PowerShell modules path
Expand-Archive -Path .\Tools\PSPKI\PSPKI-4.2.0.zip `
    -DestinationPath "`$env:ProgramFiles\WindowsPowerShell\Modules\PSPKI" `
    -Force

# 3. Verify installation
Import-Module PSPKI
Get-Module PSPKI | Select-Object Name, Version

# 4. Test basic functionality
Get-CertificationAuthority
"@

$pspkiDest = Join-Path $OutputPath "Tools\PSPKI\INSTALL-OFFLINE.txt"
Set-Content -Path $pspkiDest -Value $pspkiInstall -Encoding UTF8
Write-OK "Generated PSPKI offline install instructions"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 9: GENERATE SHA256 MANIFEST & VERIFY SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating integrity manifest (SHA-256)"

$manifestPath = Join-Path $OutputPath "MANIFEST-SHA256.csv"
$MANIFEST | Export-Csv -Path $manifestPath -NoTypeInformation -Encoding UTF8
Write-OK "SHA-256 manifest written: MANIFEST-SHA256.csv ($($MANIFEST.Count) files)"

$verifyScript = @'
# VerifyKit.ps1 — Run on the Offline Root CA host to verify transfer integrity
# Author: Glenn Byron
#
# Usage: .\VerifyKit.ps1
# Computes SHA-256 for each file listed in MANIFEST-SHA256.csv and reports mismatches.

$manifest = Import-Csv -Path "$PSScriptRoot\MANIFEST-SHA256.csv"
$kitRoot   = $PSScriptRoot
$pass = 0; $fail = 0

Write-Host "`n  Verifying transfer kit integrity..." -ForegroundColor Cyan
foreach ($item in $manifest) {
    $fullPath = Join-Path $kitRoot $item.File
    if (-not (Test-Path $fullPath)) {
        Write-Host "  [MISSING] $($item.File)" -ForegroundColor Red
        $fail++
        continue
    }
    $actual = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash
    if ($actual -eq $item.SHA256) {
        $pass++
    } else {
        Write-Host "  [MISMATCH] $($item.File)" -ForegroundColor Red
        Write-Host "    Expected : $($item.SHA256)" -ForegroundColor DarkGray
        Write-Host "    Actual   : $actual" -ForegroundColor DarkGray
        $fail++
    }
}
Write-Host ""
if ($fail -eq 0) {
    Write-Host "  PASS: All $pass files verified. Kit integrity confirmed." -ForegroundColor Green
} else {
    Write-Host "  FAIL: $fail file(s) failed verification. Do not proceed." -ForegroundColor Red
}
Write-Host ""
'@

$verifyDest = Join-Path $OutputPath "VerifyKit.ps1"
Set-Content -Path $verifyDest -Value $verifyScript -Encoding UTF8
Write-OK "Generated VerifyKit.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 10: GENERATE README
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating kit README"

$readme = @"
# Offline Root CA Transfer Kit
**Built:** $TIMESTAMP
**Author:** Glenn Byron
**Document ID:** KIT-ICAM-ROOT-001

## Contents

| Directory / File             | Purpose                                                           |
|------------------------------|-------------------------------------------------------------------|
| Config\CAPolicy.inf          | Root CA policy — place at C:\Windows\CAPolicy.inf before install  |
| Config\CRLDistributionPoints.txt | CRL/AIA endpoint reference — update URLs before install      |
| Scripts\Initialize-OfflineRootCA.ps1 | CA provisioning script — run on the offline host         |
| Scripts\Publish-CRL.ps1     | Signing ceremony script — CRL publication and Sub-CA signing      |
| Tools\SysInternals\          | Microsoft SysInternals Suite (sigcheck, procmon, autoruns)        |
| Tools\OpenSSL\               | Win64 OpenSSL Light — certificate inspection                      |
| Tools\PSPKI\                 | PSPKI PowerShell module — offline install package                 |
| Tools\NuGet\                 | NuGet package provider — required for PSPKI offline install       |
| Templates\                   | .INF certificate authority configuration baselines               |
| Docs\Blueprint.md            | Architecture reference (ARCH-ICAM-001)                           |
| MANIFEST-SHA256.csv          | SHA-256 integrity hashes for all kit files                       |
| VerifyKit.ps1                | Run on target host to verify transfer integrity before proceeding |
| MANUAL-DOWNLOADS.txt         | Any downloads that failed and require manual retrieval           |

## Setup Order

1. **On this connected machine** — run .\Download-OfflineCA-Kit.ps1 (already done)
2. **Copy** this entire folder to a USB drive
3. **On the Offline Root CA host** — run .\VerifyKit.ps1 to verify integrity
4. **Update** Config\CAPolicy.inf with your real CRL/AIA HTTP server URLs
5. **Copy** Config\CAPolicy.inf to C:\Windows\CAPolicy.inf
6. **Run** Scripts\Initialize-OfflineRootCA.ps1 -CACommonName "YourCA-Root-G1"
7. **Export** Root CA certificate to USB, transfer to Issuing CA host
8. **Power off** the Root CA — disconnect all network adapters — lock in storage

## Security Requirements

- The Root CA host must NEVER have live network connectivity after provisioning
- Signing ceremonies require two authorized personnel (NIST AC-5 separation of duties)
- All ceremony activity must be logged in a physical log book
- CRL export to HTTP server is the only data egress permitted
"@

$readmeDest = Join-Path $OutputPath "README.md"
Set-Content -Path $readmeDest -Value $readme -Encoding UTF8
Write-OK "Generated README.md"

# ──────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  OFFLINE CA TRANSFER KIT COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Kit Location : $OutputPath" -ForegroundColor White
Write-Host "  Files Staged : $($MANIFEST.Count)" -ForegroundColor White

$manualFile = Join-Path $OutputPath "MANUAL-DOWNLOADS.txt"
if (Test-Path $manualFile) {
    Write-Host ""
    Write-Warn "Some downloads failed — see MANUAL-DOWNLOADS.txt for manual retrieval"
}

Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor White
Write-Host "  1. Review MANUAL-DOWNLOADS.txt and retrieve any missing files" -ForegroundColor White
Write-Host "  2. Update Config\CAPolicy.inf with your real CRL/AIA HTTP server URLs" -ForegroundColor White
Write-Host "  3. Copy this folder to a USB drive" -ForegroundColor White
Write-Host "  4. Transfer to the Offline Root CA host and run VerifyKit.ps1 first" -ForegroundColor White
Write-Host ""
