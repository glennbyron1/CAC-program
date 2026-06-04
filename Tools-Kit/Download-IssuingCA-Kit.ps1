#Requires -Version 5.1
<#
.SYNOPSIS
    Enterprise Issuing CA & Domain Server — Prerequisite Download and Staging Utility

.DESCRIPTION
    Downloads and stages all prerequisites needed for the domain-joined Enterprise
    Subordinate (Issuing) Certificate Authority and domain controller environment.

    Unlike the Offline Root CA, the Issuing CA is domain-joined and internet-accessible
    during initial setup. This script downloads tools directly to the target server,
    or stages them to a folder for transfer if running on a workstation.

    Document ID : SCRIPT-ICAM-007
    Framework   : NIST SP 800-53 IA-2, SC-17 | FIPS 201-3 §3.3 | CISA ZTMM v2.0

.PARAMETER StagingPath
    Where to stage downloaded files. Default: C:\CAC-Staging
    Used when running on the target Issuing CA server directly.

.PARAMETER InstallModules
    Install PowerShell modules (PSPKI) directly after download. Requires internet.

.PARAMETER ConfigureCRLServer
    Also configure IIS as the HTTP CRL/AIA distribution endpoint.
    Set -CRLServerPath and -CRLDNSName when using this switch.

.PARAMETER CRLServerPath
    Local folder path to publish CRL files (served via IIS). Default: C:\CRL

.PARAMETER CRLDNSName
    DNS hostname for the CRL distribution point (e.g., crl.agency.gov)

.EXAMPLE
    .\Download-IssuingCA-Kit.ps1
    Downloads and stages all prerequisites with default settings.

.EXAMPLE
    .\Download-IssuingCA-Kit.ps1 -InstallModules -ConfigureCRLServer -CRLDNSName "crl.agency.gov"
    Downloads, installs modules, and configures IIS for CRL distribution.

.NOTES
    Author  : Glenn Byron
    Repo    : github.com/glennbyron1/CAC-program
    Version : 1.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$StagingPath = "C:\CAC-Staging",

    [Parameter()]
    [switch]$InstallModules,

    [Parameter()]
    [switch]$ConfigureCRLServer,

    [Parameter()]
    [string]$CRLServerPath = "C:\CRL",

    [Parameter()]
    [string]$CRLDNSName = "crl.agency.gov"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────
$SCRIPT_VERSION = "1.0"
$TIMESTAMP      = Get-Date -Format "yyyyMMdd-HHmm"
$LOG_FILE       = Join-Path $StagingPath "IssuingCA-Setup-$TIMESTAMP.log"
$MANUAL_DL      = Join-Path $StagingPath "MANUAL-DOWNLOADS.txt"

$DOWNLOADS = [ordered]@{
    "SysinternalsSuite" = @{
        Url      = "https://download.sysinternals.com/files/SysinternalsSuite.zip"
        DestDir  = "Tools"
        FileName = "SysinternalsSuite.zip"
        Note     = "Microsoft SysInternals Suite"
    }
    "OpenSSL-Light" = @{
        Url      = "https://slproweb.com/download/Win64OpenSSL_Light-3_3_2.exe"
        DestDir  = "Tools"
        FileName = "Win64OpenSSL_Light.exe"
        Note     = "Win64 OpenSSL Light — certificate chain verification"
    }
    "PSPKI-Module" = @{
        Url      = "https://github.com/PKISolutions/PSPKI/releases/download/v4.2.0/PSPKI.4.2.0.zip"
        DestDir  = "Modules"
        FileName = "PSPKI-4.2.0.zip"
        Note     = "PSPKI PowerShell module — CA management"
    }
    "MSSecurityComplianceToolkit" = @{
        Url      = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/Windows_10_Windows_11_Security_Baseline.zip"
        DestDir  = "SecurityBaselines"
        FileName = "MS-SecurityBaseline.zip"
        Note     = "Microsoft Security Compliance Toolkit — STIG-aligned GPO baselines"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
function Write-Step  { param([string]$Msg) Write-Host "`n  ► $Msg" -ForegroundColor Cyan;  Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] STEP: $Msg" }
function Write-OK    { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green;  Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] OK: $Msg" }
function Write-Warn  { param([string]$Msg) Write-Host "    [!!] $Msg" -ForegroundColor Yellow; Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] WARN: $Msg" }
function Write-Fail  { param([string]$Msg) Write-Host "    [FAIL] $Msg" -ForegroundColor Red;  Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] FAIL: $Msg" }

function Invoke-Download {
    param([string]$Url, [string]$Destination, [string]$Description)
    $fn = Split-Path $Destination -Leaf
    Write-Step "Downloading: $fn"
    Write-Host "    Source : $Url" -ForegroundColor DarkGray
    try {
        $destDir = Split-Path $Destination -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        if (Get-Command Start-BitsTransfer -EA SilentlyContinue) {
            Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName $fn
        } else {
            $pp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
            $ProgressPreference = $pp
        }
        $mb = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
        Write-OK "$fn ($mb MB)"
    } catch {
        Write-Fail "Download failed: $_"
        Add-Content $MANUAL_DL "[$Description]`nURL: $Url`nDest: $Destination`n"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# BANNER
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║  ENTERPRISE ISSUING CA — PREREQUISITE STAGING SCRIPT  v$SCRIPT_VERSION  ║" -ForegroundColor DarkCyan
Write-Host "  ║  SCRIPT-ICAM-007 | Author: Glenn Byron                     ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Staging Path    : $StagingPath" -ForegroundColor White
Write-Host "  Install Modules : $InstallModules" -ForegroundColor White
Write-Host "  Config CRL IIS  : $ConfigureCRLServer" -ForegroundColor White
if ($ConfigureCRLServer) {
    Write-Host "  CRL DNS Name    : $CRLDNSName" -ForegroundColor White
    Write-Host "  CRL Local Path  : $CRLServerPath" -ForegroundColor White
}
Write-Host "  Log File        : $LOG_FILE" -ForegroundColor White
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: CREATE STAGING STRUCTURE
# ──────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path $StagingPath)) { New-Item -ItemType Directory -Path $StagingPath -Force | Out-Null }
Write-Step "Creating staging directory structure"

$Dirs = @(
    "Tools",
    "Modules",
    "SecurityBaselines",
    "Config",
    "Scripts",
    "Docs"
)
foreach ($d in $Dirs) {
    $fullPath = Join-Path $StagingPath $d
    if (-not (Test-Path $fullPath)) { New-Item -ItemType Directory -Path $fullPath -Force | Out-Null }
}
Write-OK "Directory structure created at: $StagingPath"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: VERIFY / INSTALL WINDOWS FEATURES
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Verifying required Windows roles and features"

# Get-WindowsFeature / Install-WindowsFeature are Server-only cmdlets.
# ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
$osProductType = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType
if ($osProductType -eq 1) {
    Write-Warn "Skipping feature check — this machine is a Windows client (not Server)."
    Write-Warn "Re-run this script on the target Issuing CA server to install roles."
} else {
    $RequiredFeatures = @(
        @{ Name = "AD-Certificate";        Display = "Active Directory Certificate Services (AD CS)" },
        @{ Name = "ADCS-Cert-Authority";   Display = "AD CS — Certification Authority role service" },
        @{ Name = "ADCS-Web-Enrollment";   Display = "AD CS — Web Enrollment (certmgr IIS frontend)" },
        @{ Name = "ADCS-Online-Cert";      Display = "AD CS — Online Responder (OCSP)" },
        @{ Name = "Web-Server";            Display = "IIS Web Server (HTTP CRL/AIA endpoint)" },
        @{ Name = "Web-Mgmt-Console";      Display = "IIS Management Console" },
        @{ Name = "RSAT-ADCS";             Display = "RSAT — AD CS Management Tools" },
        @{ Name = "RSAT-AD-PowerShell";    Display = "RSAT — Active Directory PowerShell" }
    )

    $toInstall = @()
    foreach ($feat in $RequiredFeatures) {
        $state = (Get-WindowsFeature -Name $feat.Name -ErrorAction SilentlyContinue).InstallState
        if ($state -eq "Installed") {
            Write-OK "Already installed : $($feat.Display)"
        } else {
            Write-Warn "Not installed : $($feat.Display)"
            $toInstall += $feat.Name
        }
    }

    if ($toInstall.Count -gt 0) {
        Write-Step "Installing $($toInstall.Count) missing Windows features"
        Write-Host "    Features: $($toInstall -join ', ')" -ForegroundColor DarkGray
        if ($PSCmdlet.ShouldProcess("Windows Features: $($toInstall -join ', ')", "Install")) {
            $result = Install-WindowsFeature -Name $toInstall -IncludeManagementTools
            if ($result.Success) {
                Write-OK "All features installed successfully"
                if ($result.RestartNeeded -eq "Yes") {
                    Write-Warn "A REBOOT IS REQUIRED before continuing. Reboot and re-run this script."
                }
            } else {
                Write-Fail "Feature installation reported failures — review Install-WindowsFeature output"
            }
        }
    } else {
        Write-OK "All required Windows features are already installed"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3: INSTALL / VERIFY PSPKI MODULE
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Checking PSPKI PowerShell module"

$pspki = Get-Module -Name PSPKI -ListAvailable -ErrorAction SilentlyContinue
if ($pspki) {
    Write-OK "PSPKI already installed: version $($pspki[0].Version)"
} elseif ($InstallModules) {
    Write-Step "Installing PSPKI from PowerShell Gallery"
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
        Install-Module -Name PSPKI -Scope AllUsers -Force -AllowClobber
        Write-OK "PSPKI installed from PowerShell Gallery"
    } catch {
        Write-Warn "Gallery install failed — downloading zip for manual install: $_"
        $pspkiZip = Join-Path $StagingPath "Modules\PSPKI-4.2.0.zip"
        Invoke-Download -Url "https://github.com/PKISolutions/PSPKI/releases/download/v4.2.0/PSPKI.4.2.0.zip" `
                        -Destination $pspkiZip -Description "PSPKI module zip"
    }
} else {
    Write-Warn "PSPKI not installed. Re-run with -InstallModules to install automatically."
    Write-Host "    Manual: Install-Module -Name PSPKI -Scope AllUsers" -ForegroundColor DarkGray
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 4: DOWNLOAD THIRD-PARTY TOOLS
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Downloading supporting tools"
foreach ($key in $DOWNLOADS.Keys) {
    $item = $DOWNLOADS[$key]
    $dest = Join-Path $StagingPath "$($item.DestDir)\$($item.FileName)"
    Invoke-Download -Url $item.Url -Destination $dest -Description $item.Note
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 5: GENERATE CAPolicy.inf FOR ISSUING CA
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating CAPolicy.inf for Enterprise Issuing CA"

$caPolicyIssuing = @"
; CAPolicy.inf — Enterprise Subordinate / Issuing Certificate Authority
; Document ID : CONFIG-ICAM-ISSUING-001
; Author      : Glenn Byron
;
; Place this file at C:\Windows\CAPolicy.inf on the Issuing CA domain server
; BEFORE installing the AD CS role. Update CDP/AIA URLs to match your HTTP server.

[Version]
Signature="`$Windows NT`$"

[PolicyStatementExtension]
Policies=InternalPolicy

[InternalPolicy]
OID=1.3.6.1.4.1.99999.1.2
Notice="Enterprise Internal Issuing Certificate Authority"

[Certsrv_Server]
RenewalKeyLength=4096
RenewalValidityPeriod=Years
RenewalValidityPeriodUnits=5
CRLPeriod=Days
CRLPeriodUnits=7
CRLDeltaPeriod=Hours
CRLDeltaPeriodUnits=8
LoadDefaultTemplates=1
AlternateSignatureAlgorithm=0

[CRLDistributionPoint]
; HTTP CDP for Issuing CA CRL — update URL before installation
; LDAP removed — see Blueprint.md §3.1 WAN failure mode analysis
Empty=true

[AuthorityInformationAccess]
; HTTP AIA for Issuing CA certificate download and OCSP
Empty=true
"@

$caPolicyDest = Join-Path $StagingPath "Config\CAPolicy-IssuingCA.inf"
Set-Content -Path $caPolicyDest -Value $caPolicyIssuing -Encoding UTF8
Write-OK "Generated CAPolicy-IssuingCA.inf"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 6: GENERATE ISSUING CA SETUP SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating Initialize-IssuingCA.ps1 setup script"

$issuingScript = @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Provisions the Enterprise Subordinate (Issuing) Certificate Authority.

.DESCRIPTION
    Run this script on the DOMAIN-JOINED Issuing CA server after:
      - Domain join complete
      - Root CA certificate received from the Offline Root CA
      - CAPolicy.inf placed at C:\Windows\CAPolicy.inf

    Document ID : SCRIPT-ICAM-008
    Author      : Glenn Byron
    Reference   : NIST SP 800-53 SC-17 | CISA ZTMM Identity Pillar
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CACommonName,

    [Parameter(Mandatory)]
    [string]$RootCACertPath,

    [Parameter()]
    [string]$CRLServer = "http://crl.agency.gov",

    [Parameter()]
    [string]$CRLLocalPath = "C:\CRL",

    [Parameter()]
    [string]$OCSPUrl = "http://ocsp.agency.gov/"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Msg) Write-Host "`n  ► $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!!] $Msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║  ENTERPRISE ISSUING CA — INITIALIZATION SCRIPT              ║" -ForegroundColor DarkCyan
Write-Host "  ║  SCRIPT-ICAM-008 | Author: Glenn Byron                       ║" -ForegroundColor DarkCyan
Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  CA Name        : $CACommonName" -ForegroundColor White
Write-Host "  Root CA Cert   : $RootCACertPath" -ForegroundColor White
Write-Host "  CRL Server     : $CRLServer" -ForegroundColor White
Write-Host "  OCSP URL       : $OCSPUrl" -ForegroundColor White

# Validate prerequisites
if (-not (Test-Path $RootCACertPath)) {
    throw "Root CA certificate not found: $RootCACertPath. Copy from the Offline Root CA USB."
}
if (-not (Test-Path "C:\Windows\CAPolicy.inf")) {
    Write-Warn "CAPolicy.inf not found. Copying from staging directory..."
    $stagingConf = Join-Path (Split-Path $PSScriptRoot -Parent) "Config\CAPolicy-IssuingCA.inf"
    if (Test-Path $stagingConf) {
        Copy-Item $stagingConf "C:\Windows\CAPolicy.inf" -Force
        Write-OK "CAPolicy.inf placed at C:\Windows\CAPolicy.inf"
    } else {
        throw "CAPolicy.inf not found. Place it at C:\Windows\CAPolicy.inf before proceeding."
    }
}

# Step 1 — Install Root CA certificate into local machine + NTAuth stores
Write-Step "Publishing Root CA certificate to domain NTAuth store"
certutil -addstore Root $RootCACertPath
certutil -dspublish -f $RootCACertPath RootCA
certutil -dspublish -f $RootCACertPath NTAuthCA
Write-OK "Root CA certificate published to NTAuth store"

# Step 2 — Install AD CS Subordinate (Enterprise) CA role
Write-Step "Installing Enterprise Subordinate Certificate Authority"
Install-AdcsCertificationAuthority `
    -CAType EnterpriseSubordinateCA `
    -CACommonName $CACommonName `
    -KeyLength 4096 `
    -HashAlgorithmName SHA256 `
    -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
    -OutputCertRequestFile "C:\$CACommonName.req" `
    -Force
Write-OK "Subordinate CA installed (pending Root CA signing)"
Write-Warn "Copy C:\$CACommonName.req to the Offline Root CA via USB for signing."
Write-Warn "Return the signed .crt, then run: certutil -installcert <signed.crt>"

# Step 3 — After signing: configure CDPs and AIA (run after certutil -installcert)
Write-Host ""
Write-Host "  ─── POST-SIGNING CONFIGURATION (run after installing signed cert) ───" -ForegroundColor DarkGray
Write-Host @"
    # Remove LDAP CDP/AIA, set HTTP-only endpoints
    Get-CACRLDistributionPoint | Remove-CACRLDistributionPoint -Force
    Get-CAAuthorityInformationAccess | Remove-CAAuthorityInformationAccess -Force

    # HTTP CDP (Issuing CA CRL)
    Add-CACRLDistributionPoint -Uri "$CRLServer/crl/<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl" ``
        -AddToCertificateCDP -AddToFreshestCrl -Force

    # HTTP AIA (Issuing CA cert download)
    Add-CAAuthorityInformationAccess -Uri "$CRLServer/certs/<ServerDNSName>_<CaName><CertificateName>.crt" ``
        -AddToCertificateAia -Force

    # OCSP responder
    Add-CAAuthorityInformationAccess -Uri "$OCSPUrl" -AddToCertificateOcsp -Force

    # CRL schedule: 7-day base, 8-hour delta
    certutil -setreg CA\CRLPeriodUnits 7
    certutil -setreg CA\CRLPeriod "Days"
    certutil -setreg CA\CRLDeltaPeriodUnits 8
    certutil -setreg CA\CRLDeltaPeriod "Hours"

    # Audit logging (NIST AU-2)
    certutil -setreg CA\AuditFilter 127
    auditpol /set /subcategory:"Certification Services" /success:enable /failure:enable

    # Publish initial CRL and restart
    certutil -CRL
    Restart-Service CertSvc
"@ -ForegroundColor DarkGray

# Step 4 — Create CRL publication folder
Write-Step "Creating local CRL publication folder: $CRLLocalPath"
if (-not (Test-Path $CRLLocalPath)) {
    New-Item -ItemType Directory -Path $CRLLocalPath -Force | Out-Null
}
# Grant CertSvc write access to publish CRLs
$acl = Get-Acl $CRLLocalPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "NETWORK SERVICE", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -Path $CRLLocalPath -AclObject $acl
Write-OK "CRL folder created and permissions set: $CRLLocalPath"

Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  ISSUING CA STAGED — AWAITING ROOT CA SIGNING" -ForegroundColor Yellow
Write-Host "  ══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor White
Write-Host "  1. Copy C:\$CACommonName.req to USB" -ForegroundColor White
Write-Host "  2. Transfer to Offline Root CA — run Publish-CRL.ps1 -SubordinateCARequestPath <req>" -ForegroundColor White
Write-Host "  3. Retrieve signed .crt from USB" -ForegroundColor White
Write-Host "  4. certutil -installcert <signed.crt>" -ForegroundColor White
Write-Host "  5. Restart-Service CertSvc" -ForegroundColor White
Write-Host "  6. Run the CDP/AIA post-signing commands shown above" -ForegroundColor White
Write-Host ""
'@

$issuingDest = Join-Path $StagingPath "Scripts\Initialize-IssuingCA.ps1"
Set-Content -Path $issuingDest -Value $issuingScript -Encoding UTF8
Write-OK "Generated Initialize-IssuingCA.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 7: CONFIGURE IIS AS HTTP CRL DISTRIBUTION SERVER (optional)
# ──────────────────────────────────────────────────────────────────────────────
if ($ConfigureCRLServer) {
    Write-Step "Configuring IIS as HTTP CRL/AIA distribution server"

    if (-not (Get-WindowsFeature -Name Web-Server).InstallState -eq "Installed") {
        Write-Warn "IIS not installed — install it first with: Install-WindowsFeature Web-Server -IncludeManagementTools"
    } else {
        try {
            Import-Module WebAdministration -ErrorAction Stop

            # Create CRL publication folder
            if (-not (Test-Path $CRLServerPath)) {
                New-Item -ItemType Directory -Path $CRLServerPath -Force | Out-Null
            }

            # Remove default site, create CRL site
            $existingSite = Get-Website -Name "CRL" -ErrorAction SilentlyContinue
            if (-not $existingSite) {
                New-Website -Name "CRL" `
                            -Port 80 `
                            -PhysicalPath $CRLServerPath `
                            -HostHeader $CRLDNSName `
                            -Force
                Write-OK "IIS site 'CRL' created — serving from $CRLServerPath"
            } else {
                Write-OK "IIS site 'CRL' already exists"
            }

            # Allow double-escaping for CRL delta files (contain '+' in URL)
            Set-WebConfigurationProperty -PSPath "IIS:\Sites\CRL" `
                -Filter "system.webServer/security/requestFiltering" `
                -Name allowDoubleEscaping -Value $true

            # Disable anonymous authentication on admin paths, keep on CRL path
            Write-OK "CRL site configured — double-escaping enabled for delta CRL files"
            Write-Warn "Add DNS A record: $CRLDNSName -> this server's IP"
            Write-Warn "Add firewall rule to allow TCP 80 inbound for CRL distribution"

        } catch {
            Write-Warn "IIS configuration failed: $_"
            Write-Host "    Run: Install-WindowsFeature Web-Server, Web-Mgmt-Console" -ForegroundColor DarkGray
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 8: COPY REPO FILES TO STAGING
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Copying repository reference files to staging"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$docsToCopy = @(
    @{ Src = "Architecture\Blueprint.md";          Dst = "Docs\Blueprint.md" },
    @{ Src = "Architecture\Regulatory-Alignment.md"; Dst = "Docs\Regulatory-Alignment.md" },
    @{ Src = "Architecture\STIG-Hardening-Guide.md"; Dst = "Docs\STIG-Hardening-Guide.md" },
    @{ Src = "Templates";                          Dst = "Templates" }
)

foreach ($doc in $docsToCopy) {
    $src = Join-Path $RepoRoot $doc.Src
    $dst = Join-Path $StagingPath $doc.Dst
    if (Test-Path $src) {
        if ((Get-Item $src).PSIsContainer) {
            Copy-Item -Path $src -Destination $dst -Recurse -Force
        } else {
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -Path $src -Destination $dst -Force
        }
        Write-OK "Copied: $($doc.Src)"
    } else {
        Write-Warn "Not found: $src"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  ISSUING CA STAGING COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Staging Path : $StagingPath" -ForegroundColor White
Write-Host "  Log File     : $LOG_FILE" -ForegroundColor White
Write-Host ""
Write-Host "  CONTENTS:" -ForegroundColor White
Write-Host "    Config\CAPolicy-IssuingCA.inf   — place at C:\Windows\CAPolicy.inf" -ForegroundColor White
Write-Host "    Scripts\Initialize-IssuingCA.ps1 — run after domain join" -ForegroundColor White
Write-Host "    Tools\                           — SysInternals, OpenSSL" -ForegroundColor White
Write-Host "    Modules\                         — PSPKI module zip" -ForegroundColor White
Write-Host "    SecurityBaselines\               — Microsoft SCT GPO baselines" -ForegroundColor White
Write-Host "    Docs\                            — Architecture reference docs" -ForegroundColor White
Write-Host ""
Write-Host "  SETUP ORDER:" -ForegroundColor White
Write-Host "  1. Domain-join the server" -ForegroundColor White
Write-Host "  2. Copy Config\CAPolicy-IssuingCA.inf to C:\Windows\CAPolicy.inf" -ForegroundColor White
Write-Host "  3. Run Scripts\Initialize-IssuingCA.ps1 (installs AD CS, creates .req)" -ForegroundColor White
Write-Host "  4. Transfer .req to Offline Root CA for signing" -ForegroundColor White
Write-Host "  5. Install signed .crt, configure CDP/AIA, publish first CRL" -ForegroundColor White
Write-Host "  6. Run Build-CA-GPO.ps1 to deploy smart card enforcement GPO" -ForegroundColor White
if (Test-Path $MANUAL_DL) {
    Write-Warn "Some downloads failed — see: $MANUAL_DL"
}
Write-Host ""
