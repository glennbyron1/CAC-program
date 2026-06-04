#Requires -Version 5.1
<#
.SYNOPSIS
    Federal Compliance & Testing Tools — Download and Staging Utility

.DESCRIPTION
    Downloads, organizes, and stages all federal government compliance scanning
    and testing tools required for DISA STIG audits, SCAP compliance checks,
    CISA cybersecurity assessments, and Microsoft security baseline deployment.

    Tool Sources:
      - DISA public.cyber.mil   (STIG Viewer, SCAP content — no CAC required)
      - DISA cyber.mil          (SCAP Compliance Checker — CAC-gated; instructions provided)
      - CISA GitHub             (CSET — Cybersecurity Evaluation Tool)
      - Microsoft Download      (Security Compliance Toolkit)
      - Tenable                 (Nessus Essentials — free tier of ACAS)

    Document ID : SCRIPT-ICAM-009
    Framework   : DISA RMF | NIST SP 800-53 CA-2, CA-7 | CISA CPG 5.A | MD SB 871

.PARAMETER OutputPath
    Where to stage all tools. Default: .\FedCompliance-Tools

.PARAMETER OpenBrowserForCAC
    Open browser tabs for CAC-gated downloads (SCAP SCC, STIG content requiring login).

.EXAMPLE
    .\Download-FedCompliance-Kit.ps1
    Downloads all public tools to .\FedCompliance-Tools

.EXAMPLE
    .\Download-FedCompliance-Kit.ps1 -OutputPath "D:\FedTools" -OpenBrowserForCAC
    Stages to D:\FedTools and opens browser tabs for CAC-gated downloads.

.NOTES
    Author  : Glenn Byron
    Repo    : github.com/glennbyron1/CAC-program
    Version : 1.0

    CAC-GATED TOOLS:
    The SCAP Compliance Checker (SCC) requires a DoD CAC or ECA certificate to
    download from cyber.mil. This script provides the URL and instructions.
    All other tools in this script are publicly downloadable without authentication.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$OutputPath = ".\FedCompliance-Tools",

    [Parameter()]
    [switch]$OpenBrowserForCAC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────
$TIMESTAMP = Get-Date -Format "yyyyMMdd-HHmm"
$LOG_FILE  = Join-Path $OutputPath "Download-Log-$TIMESTAMP.log"

# PUBLIC downloads (no CAC required)
$PUBLIC_DOWNLOADS = [ordered]@{

    "STIGViewer" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_STIGViewer-3-3_Win64.zip"
        DestDir  = "01-STIG-Viewer"
        FileName = "STIGViewer-3-3.zip"
        Description = "DISA STIG Viewer 3.3 — graphical STIG checklist review tool (Windows 64-bit)"
        Source   = "DISA public.cyber.mil (no CAC required)"
    }

    "STIG-WinServer2022" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_Server_2022_V2R2_STIG.zip"
        DestDir  = "02-STIG-Content\Windows-Server-2022"
        FileName = "U_MS_Windows_Server_2022_STIG.zip"
        Description = "DISA STIG — Windows Server 2022 (XCCDF + SCAP content)"
        Source   = "DISA public.cyber.mil"
    }

    "STIG-WinServer2019" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_Server_2019_V3R2_STIG.zip"
        DestDir  = "02-STIG-Content\Windows-Server-2019"
        FileName = "U_MS_Windows_Server_2019_STIG.zip"
        Description = "DISA STIG — Windows Server 2019 (XCCDF + SCAP content)"
        Source   = "DISA public.cyber.mil"
    }

    "STIG-Win11" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_11_V2R2_STIG.zip"
        DestDir  = "02-STIG-Content\Windows-11"
        FileName = "U_MS_Windows_11_STIG.zip"
        Description = "DISA STIG — Windows 11 (XCCDF + SCAP content)"
        Source   = "DISA public.cyber.mil"
    }

    "STIG-IE-SmartCard" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Internet_Explorer_11_V2R5_STIG.zip"
        DestDir  = "02-STIG-Content\SmartCard-PKI"
        FileName = "U_MS_IE11_STIG.zip"
        Description = "DISA STIG — Internet Explorer 11 (PKI/smart card site access reference)"
        Source   = "DISA public.cyber.mil"
    }

    "SCAP-Content-Win2022" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_Server_2022_V2R2_STIG_SCAP_1-3_Benchmark.zip"
        DestDir  = "03-SCAP-Content\Windows-Server-2022"
        FileName = "U_WinServer2022_SCAP.zip"
        Description = "DISA SCAP 1.3 Benchmark — Windows Server 2022 (import into SCAP SCC)"
        Source   = "DISA public.cyber.mil"
    }

    "SCAP-Content-Win2019" = @{
        Url      = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_Server_2019_V3R2_STIG_SCAP_1-3_Benchmark.zip"
        DestDir  = "03-SCAP-Content\Windows-Server-2019"
        FileName = "U_WinServer2019_SCAP.zip"
        Description = "DISA SCAP 1.3 Benchmark — Windows Server 2019 (import into SCAP SCC)"
        Source   = "DISA public.cyber.mil"
    }

    "MSSecurityComplianceToolkit" = @{
        Url      = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/Windows_10_Windows_11_Security_Baseline.zip"
        DestDir  = "04-MS-Security-Compliance-Toolkit"
        FileName = "MS-SecurityBaseline-Win10-Win11.zip"
        Description = "Microsoft Security Compliance Toolkit — STIG-aligned GPO baselines for Windows 10/11"
        Source   = "Microsoft Download Center (public)"
    }

    "MSSecurityBaselineServer2022" = @{
        Url      = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/Windows_Server_2022_Security_Baseline.zip"
        DestDir  = "04-MS-Security-Compliance-Toolkit"
        FileName = "MS-SecurityBaseline-WinServer2022.zip"
        Description = "Microsoft Security Compliance Toolkit — Windows Server 2022 STIG baseline"
        Source   = "Microsoft Download Center (public)"
    }

    "PolicyAnalyzer" = @{
        Url      = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/PolicyAnalyzer.zip"
        DestDir  = "04-MS-Security-Compliance-Toolkit"
        FileName = "PolicyAnalyzer.zip"
        Description = "Microsoft Policy Analyzer — compare GPO baselines against current settings"
        Source   = "Microsoft Download Center (public)"
    }

    "NessusEssentials" = @{
        Url      = "https://www.tenable.com/downloads/api/v2/pages/nessus/files/Nessus-10.7.0-x64.msi"
        DestDir  = "05-Nessus-Essentials"
        FileName = "Nessus-10.7.0-x64.msi"
        Description = "Tenable Nessus Essentials — free-tier ACAS-equivalent vulnerability scanner (register at tenable.com for free activation code)"
        Source   = "Tenable.com (free tier — requires email registration for license key)"
    }

    "SysinternalsSuite" = @{
        Url      = "https://download.sysinternals.com/files/SysinternalsSuite.zip"
        DestDir  = "06-SysInternals"
        FileName = "SysinternalsSuite.zip"
        Description = "Microsoft SysInternals Suite — sigcheck (certificate chain verification), procmon, autoruns"
        Source   = "Microsoft Sysinternals (public)"
    }

    "OpenSSL" = @{
        Url      = "https://slproweb.com/download/Win64OpenSSL_Light-3_3_2.exe"
        DestDir  = "07-OpenSSL"
        FileName = "Win64OpenSSL_Light.exe"
        Description = "Win64 OpenSSL Light — manual certificate chain and CRL inspection"
        Source   = "slproweb.com Win32 OpenSSL (public)"
    }
}

# CAC-GATED downloads — cannot auto-download; provide URLs and instructions
$CAC_GATED = [ordered]@{
    "SCAP-SCC" = @{
        LoginUrl    = "https://public.cyber.mil/stigs/scap/"
        DownloadUrl = "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/scc-5.10.2_Windows_bundle.zip"
        FileName    = "SCC-Windows-Bundle.zip"
        DestDir     = "00-SCAP-SCC"
        Description = "DISA SCAP Compliance Checker (SCC) — primary STIG scanning engine"
        Note        = "The download link may require a DoD CAC. Try the public.cyber.mil URL first — SCC is sometimes available without login. If blocked, use your CAC-enabled browser."
    }
    "CSET" = @{
        LoginUrl    = "https://github.com/cisagov/cset/releases/latest"
        DownloadUrl = "https://github.com/cisagov/cset/releases/download/v12.2.1.1/CSET_12.2.1.1_Installer.exe"
        FileName    = "CSET_Installer.exe"
        DestDir     = "08-CISA-CSET"
        Description = "CISA Cybersecurity Evaluation Tool — OT/ICS/IT cybersecurity assessment"
        Note        = "Publicly available on GitHub. No CAC required. Check github.com/cisagov/cset for latest release."
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "`n  ► $Msg" -ForegroundColor Cyan;   Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] STEP: $Msg" }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green;  Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] OK: $Msg" }
function Write-Warn { param([string]$Msg) Write-Host "    [!!] $Msg" -ForegroundColor Yellow; Add-Content $LOG_FILE "[$((Get-Date -f 'HH:mm:ss'))] WARN: $Msg" }
function Write-Info { param([string]$Msg) Write-Host "         $Msg" -ForegroundColor DarkGray }

function Invoke-Download {
    param([string]$Url, [string]$Destination, [string]$Description)
    $fn = Split-Path $Destination -Leaf
    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    if (Test-Path $Destination) {
        $mb = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
        Write-OK "Already downloaded: $fn ($mb MB)"
        return $true
    }

    try {
        if (Get-Command Start-BitsTransfer -EA SilentlyContinue) {
            Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName $fn
        } else {
            $pp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
            $ProgressPreference = $pp
        }
        $mb = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
        Write-OK "Downloaded: $fn ($mb MB)"
        Add-Content $LOG_FILE "  Downloaded: $fn -> $Destination"
        return $true
    } catch {
        Write-Warn "Download failed: $fn — $($_.Exception.Message)"
        Add-Content $LOG_FILE "  FAILED: $fn — $_"
        return $false
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# BANNER
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║   FEDERAL COMPLIANCE & TESTING TOOLS — DOWNLOAD UTILITY  v1.0   ║" -ForegroundColor DarkCyan
Write-Host "  ║   SCRIPT-ICAM-009 | Author: Glenn Byron                          ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Output Path : $OutputPath" -ForegroundColor White
Write-Host "  Timestamp   : $TIMESTAMP" -ForegroundColor White
Write-Host ""
Write-Host "  TOOLS INCLUDED:" -ForegroundColor White
Write-Host "    00 — SCAP Compliance Checker (SCC)          [CAC-gated or public try]" -ForegroundColor White
Write-Host "    01 — DISA STIG Viewer 3.3                   [Public]" -ForegroundColor White
Write-Host "    02 — DISA STIG Content (Server 2022/2019, Win11, PKI)  [Public]" -ForegroundColor White
Write-Host "    03 — DISA SCAP 1.3 Benchmark Content        [Public]" -ForegroundColor White
Write-Host "    04 — Microsoft Security Compliance Toolkit  [Public]" -ForegroundColor White
Write-Host "    05 — Nessus Essentials (ACAS equivalent)    [Public — free activation]" -ForegroundColor White
Write-Host "    06 — Microsoft SysInternals Suite           [Public]" -ForegroundColor White
Write-Host "    07 — Win64 OpenSSL Light                    [Public]" -ForegroundColor White
Write-Host "    08 — CISA CSET (Cybersecurity Eval Tool)    [Public — GitHub]" -ForegroundColor White
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: CREATE DIRECTORY STRUCTURE
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Creating output directory structure"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
# Pre-create all subdirs
$allDirs = ($PUBLIC_DOWNLOADS.Values | ForEach-Object { $_.DestDir }) +
           ($CAC_GATED.Values      | ForEach-Object { $_.DestDir })
foreach ($d in $allDirs | Select-Object -Unique) {
    $full = Join-Path $OutputPath $d
    if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
}
Write-OK "Output structure created"

# Initialize log file
"Federal Compliance Tools Download Log — $TIMESTAMP" | Set-Content $LOG_FILE
"Author: Glenn Byron | SCRIPT-ICAM-009" | Add-Content $LOG_FILE
"" | Add-Content $LOG_FILE

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: TRY CAC-GATED DOWNLOADS (attempt public path first)
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Attempting CAC-gated downloads via public URL (may require login)"
Write-Host "    SCAP SCC is sometimes accessible from public.cyber.mil without CAC." -ForegroundColor DarkGray
Write-Host "    Attempting direct download..." -ForegroundColor DarkGray

$cacManualRequired = @()

foreach ($key in $CAC_GATED.Keys) {
    $item = $CAC_GATED[$key]
    $dest = Join-Path $OutputPath "$($item.DestDir)\$($item.FileName)"
    $destDir = Split-Path $dest -Parent

    Write-Host ""
    Write-Host "  ► $key : $($item.Description)" -ForegroundColor Cyan

    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $success = Invoke-Download -Url $item.DownloadUrl -Destination $dest -Description $item.Description

    if (-not $success) {
        $cacManualRequired += $item
        Write-Warn "Manual download required for: $key"
        Write-Info "Portal : $($item.LoginUrl)"
        Write-Info "Note   : $($item.Note)"

        # Write per-tool instructions
        $instrFile = Join-Path $OutputPath "$($item.DestDir)\HOW-TO-DOWNLOAD.txt"
        @"
$key — Manual Download Instructions
=============================================
Description : $($item.Description)
Portal URL  : $($item.LoginUrl)
Direct URL  : $($item.DownloadUrl)
Save As     : $dest

Instructions:
$($item.Note)

After downloading, place the file at:
  $dest
"@ | Set-Content $instrFile

        if ($OpenBrowserForCAC) {
            Start-Process $item.LoginUrl
            Write-OK "Browser opened: $($item.LoginUrl)"
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3: DOWNLOAD ALL PUBLIC TOOLS
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Downloading public federal compliance tools"

$successCount = 0
$failCount    = 0

foreach ($key in $PUBLIC_DOWNLOADS.Keys) {
    $item = $PUBLIC_DOWNLOADS[$key]
    $dest = Join-Path $OutputPath "$($item.DestDir)\$($item.FileName)"

    Write-Host ""
    Write-Host "  ► $key" -ForegroundColor Cyan
    Write-Info "$($item.Description)"
    Write-Info "Source: $($item.Source)"

    $ok = Invoke-Download -Url $item.Url -Destination $dest -Description $item.Description
    if ($ok) { $successCount++ } else { $failCount++ }
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 4: GENERATE TOOL INDEX & QUICK REFERENCE
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Generating tool index and quick reference"

$indexContent = @"
# Federal Compliance Tools — Download Index
**Generated:** $TIMESTAMP
**Author:** Glenn Byron | Document ID: SCRIPT-ICAM-009
**Reference:** STIG-Hardening-Guide.md | Architecture/FedGov-Tools-Setup-Guide.md

---

## Tool Directory

| Folder | Tool | Purpose | Auth Required |
|--------|------|---------|---------------|
| 00-SCAP-SCC\ | SCAP Compliance Checker (SCC) | Primary STIG scanning engine | CAC or public try |
| 01-STIG-Viewer\ | DISA STIG Viewer 3.3 | Graphical STIG checklist review | None (public) |
| 02-STIG-Content\ | DISA STIG Content packs | XCCDF rules for each OS | None (public) |
| 03-SCAP-Content\ | DISA SCAP 1.3 Benchmarks | Machine-readable scan input for SCC | None (public) |
| 04-MS-Security-Compliance-Toolkit\ | Microsoft SCT + Policy Analyzer | STIG-aligned GPO baselines | None (public) |
| 05-Nessus-Essentials\ | Nessus Essentials | ACAS-equivalent vulnerability scanner | None (free reg.) |
| 06-SysInternals\ | SysInternals Suite | sigcheck, procmon, autoruns | None (public) |
| 07-OpenSSL\ | Win64 OpenSSL Light | Certificate chain inspection | None (public) |
| 08-CISA-CSET\ | CISA CSET | OT/ICS/IT cyber assessment | None (public) |

---

## Quick Setup Order (after downloading)

1. **Install SCAP SCC** — extracts to %ProgramFiles%\SCAP Compliance Checker
2. **Import SCAP Content** — SCC > Options > Import SCAP Content > point to 03-SCAP-Content\
3. **Install STIG Viewer** — extract 01-STIG-Viewer\STIGViewer.jar (requires Java) or .exe
4. **Install Nessus** — run 05-Nessus-Essentials\Nessus-*.msi, activate free key from tenable.com
5. **Install CSET** — run 08-CISA-CSET\CSET_Installer.exe
6. **Extract Policy Analyzer** — 04-MS-Security-Compliance-Toolkit\PolicyAnalyzer.zip
7. **Import SCT baselines** — Policy Analyzer > File > Import > select extracted baseline .PolicyRules files

---

## NIST RMF Tool Roles

| RMF Phase | Tool |
|-----------|------|
| **Categorize** | CISA CSET (system impact assessment) |
| **Select** | STIG Viewer (review applicable controls) |
| **Implement** | Microsoft SCT Policy Analyzer (GPO baseline deployment) |
| **Assess** | SCAP SCC (STIG automated scan) + Nessus (vulnerability scan) |
| **Authorize** | SCAP SCC reports + Nessus PDF for ATO package |
| **Monitor** | Nessus continuous scan + AD CS audit logs → SIEM |

---
See **Architecture/FedGov-Tools-Setup-Guide.md** for full step-by-step procedures.
"@

$indexPath = Join-Path $OutputPath "TOOL-INDEX.md"
Set-Content -Path $indexPath -Value $indexContent -Encoding UTF8
Write-OK "Generated TOOL-INDEX.md"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 5: GENERATE NESSUS ACTIVATION INSTRUCTIONS
# ──────────────────────────────────────────────────────────────────────────────
$nessusInstr = @"
# Nessus Essentials — Activation Instructions
# Author: Glenn Byron | SCRIPT-ICAM-009 supplement

Nessus Essentials is the free tier of Tenable Nessus (the engine behind DoD ACAS).
It supports up to 16 IP addresses and performs credentialed authenticated scans.

## Activation Steps

1. Go to: https://www.tenable.com/products/nessus/nessus-essentials
2. Register with your email address to receive a free activation code
3. Install Nessus from 05-Nessus-Essentials\Nessus-*.msi (run as Administrator)
4. Open browser: https://localhost:8834
5. Select "Nessus Essentials" on the product selection screen
6. Enter your activation code from the email
7. Create an admin username and password
8. Wait for plugin download and compilation (~10-20 minutes)

## Credentialed Scan Setup (required for deep OS findings — DISA RMF mandate)

1. New Scan > Advanced Network Scan
2. Set Target: IP address of the CA/domain server
3. Credentials tab > Add > Windows:
   - Type: Password
   - Username: <domain admin account>
   - Password: <admin password>
   - Domain: lab.local (or your domain)
4. Launch scan
5. After scan: Report > PDF to export executive summary for repository

## Key Plugins for PKI/Smart Card Environment

| Plugin ID | Check |
|-----------|-------|
| 10862 | SMB signing enforcement |
| 57608 | Windows certificate store audit |
| 65821 | SSL/TLS certificate chain validation |
| 21745 | Authentication method strength |
| 73571 | Windows Update compliance |

## Exporting Results for Repository

Export > PDF (Executive Summary) — save to:
  Compliance-Reports\Before-MFA\Baseline-Vulnerability.pdf  (pre-hardening)
  Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf   (post-hardening)
"@
Set-Content -Path (Join-Path $OutputPath "05-Nessus-Essentials\ACTIVATION-INSTRUCTIONS.txt") `
            -Value $nessusInstr -Encoding UTF8
Write-OK "Generated Nessus activation instructions"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 6: GENERATE SIGCHECK CERTIFICATE VERIFICATION SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
$sigcheckScript = @'
# Verify-CertificateChain.ps1
# Uses SysInternals sigcheck to verify smart card certificate chains
# Author: Glenn Byron | Supplement to SCRIPT-ICAM-009
#
# Usage: .\Verify-CertificateChain.ps1 -SigcheckPath ".\SysInternals\sigcheck64.exe"

param(
    [string]$SigcheckPath = ".\sigcheck64.exe",
    [string]$CertStore = "Cert:\LocalMachine\My"
)

Write-Host "`n  Certificate Chain Verification" -ForegroundColor Cyan
Write-Host "  Using: $SigcheckPath`n" -ForegroundColor DarkGray

# List smart card certificates in local machine store
$certs = Get-ChildItem $CertStore | Where-Object {
    $_.EnhancedKeyUsageList.FriendlyName -contains "Smart Card Logon"
}

if ($certs.Count -eq 0) {
    Write-Host "  No Smart Card Logon certificates found in $CertStore" -ForegroundColor Yellow
} else {
    Write-Host "  Found $($certs.Count) smart card certificate(s):" -ForegroundColor White
    $certs | ForEach-Object {
        Write-Host ""
        Write-Host "  Subject    : $($_.Subject)" -ForegroundColor White
        Write-Host "  Issuer     : $($_.Issuer)" -ForegroundColor Gray
        Write-Host "  Thumbprint : $($_.Thumbprint)" -ForegroundColor Gray
        Write-Host "  Expires    : $($_.NotAfter)" -ForegroundColor Gray
        Write-Host "  Valid      : $($_.Verify())" -ForegroundColor $(if ($_.Verify()) { "Green" } else { "Red" })
    }
}

# Use certutil to verify the CA chain
Write-Host "`n  Running certutil chain verification...`n" -ForegroundColor Cyan
certutil -verify -urlfetch "$env:SystemRoot\System32\CertSrv\CertEnroll\*.crl" 2>$null

Write-Host "`n  Chain verification complete.`n" -ForegroundColor Cyan
'@

$sigCheckPath = Join-Path $OutputPath "06-SysInternals\Verify-CertificateChain.ps1"
Set-Content -Path $sigCheckPath -Value $sigcheckScript -Encoding UTF8
Write-OK "Generated Verify-CertificateChain.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  FEDERAL COMPLIANCE TOOLS DOWNLOAD COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Output Path       : $OutputPath" -ForegroundColor White
Write-Host "  Downloads OK      : $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Downloads Failed  : $failCount" -ForegroundColor Red
}
if ($cacManualRequired.Count -gt 0) {
    Write-Host "  CAC-Gated (manual): $($cacManualRequired.Count)" -ForegroundColor Yellow
}
Write-Host "  Log File          : $LOG_FILE" -ForegroundColor White
Write-Host ""
Write-Host "  KEY FILES:" -ForegroundColor White
Write-Host "    TOOL-INDEX.md             — index of all tools and setup order" -ForegroundColor White
Write-Host "    00-SCAP-SCC\              — SCAP Compliance Checker (may need manual download)" -ForegroundColor White
Write-Host "    05-Nessus-Essentials\ACTIVATION-INSTRUCTIONS.txt" -ForegroundColor White
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor White
Write-Host "  1. Install SCAP SCC and import SCAP content from 03-SCAP-Content\" -ForegroundColor White
Write-Host "  2. Install STIG Viewer and open STIG content from 02-STIG-Content\" -ForegroundColor White
Write-Host "  3. Register at tenable.com for a free Nessus Essentials key" -ForegroundColor White
Write-Host "  4. Install Nessus and configure credentialed scan per ACTIVATION-INSTRUCTIONS.txt" -ForegroundColor White
Write-Host "  5. See Architecture\FedGov-Tools-Setup-Guide.md for full step-by-step procedures" -ForegroundColor White
Write-Host ""
if ($cacManualRequired.Count -gt 0) {
    Write-Host "  MANUAL DOWNLOADS REQUIRED:" -ForegroundColor Yellow
    foreach ($item in $cacManualRequired) {
        Write-Host "    - $($item.Description)" -ForegroundColor Yellow
        Write-Host "      Portal: $($item.LoginUrl)" -ForegroundColor DarkGray
    }
    Write-Host ""
}
