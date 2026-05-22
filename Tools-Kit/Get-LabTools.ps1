# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Master tool downloader for the CAC/PIV lab. Downloads all compliance
    and PKI tools to a single organized folder in one run.

.DESCRIPTION
    Runs the three download kit scripts in sequence to build a complete
    FedCompliance-Tools\ staging area on this machine. After it finishes,
    copy the FedCompliance-Tools\ folder to a USB drive or directly into
    the lab VMs using PowerShell Direct.

    What gets downloaded automatically:
      - DISA STIG Viewer 3.3
      - DISA STIG content (Windows Server 2022, 2019, Windows 11)
      - DISA SCAP 1.3 benchmarks (Windows Server 2022, 2019)
      - Microsoft Security Compliance Toolkit (Windows 10/11, Server 2022)
      - Tenable Nessus Essentials installer (.msi)
      - Microsoft SysInternals Suite
      - OpenSSL for Windows (Light build)
      - CISA CSET (from GitHub releases)
      - Offline Root CA configuration kit (CAPolicy.inf, CRL scripts, manifest)
      - Enterprise Issuing CA prerequisites and initialization script

    What requires a manual step:
      - SCAP Compliance Checker (SCC) — CAC/ECA certificate required to
        download from cyber.mil. See Manual-Downloads\SCAP-SCC-Instructions.txt

.PARAMETER OutputPath
    Where to stage all tools. Default: C:\FedCompliance-Tools\
    This folder is what you copy to your lab VMs.

.PARAMETER SkipOfflineCAKit
    Skip generating the Offline Root CA configuration files.
    Use this if you only need the compliance scanning tools.

.PARAMETER SkipIssuingCAKit
    Skip generating the Issuing CA prerequisite files.

.EXAMPLE
    # Download everything to the default location
    .\Get-LabTools.ps1

.EXAMPLE
    # Download to a specific drive (e.g., USB at D:\)
    .\Get-LabTools.ps1 -OutputPath "D:\FedCompliance-Tools"

.NOTES
    Author  : Glenn Byron
    Run on  : Any internet-connected Windows machine
    After   : Copy FedCompliance-Tools\ to your lab VMs or USB drive
              See Manual-Downloads\SCAP-SCC-Instructions.txt for SCAP SCC
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$OutputPath = "C:\FedCompliance-Tools",

    [Parameter()]
    [switch]$SkipOfflineCAKit,

    [Parameter()]
    [switch]$SkipIssuingCAKit
)

$ErrorActionPreference = 'Continue'
$scriptRoot = $PSScriptRoot

function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  LAB TOOL DOWNLOADER | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  Output : $OutputPath" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Section { param([string]$T) Write-Host ""; Write-Host "── $T" -ForegroundColor White }
function Write-OK      { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Info    { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }

Write-Banner

# Create output folder
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-OK "Created: $OutputPath"
}

# ---------------------------------------------------------------------------
# Step 1 — Federal Compliance Tools (STIG Viewer, benchmarks, Nessus, CSET…)
# ---------------------------------------------------------------------------
Write-Section "Step 1 — Federal Compliance Tools"
$fedScript = Join-Path $scriptRoot "Download-FedCompliance-Kit.ps1"
if (Test-Path $fedScript) {
    Write-Host "  Running Download-FedCompliance-Kit.ps1..." -ForegroundColor White
    & $fedScript -OutputPath $OutputPath
    Write-OK "Federal compliance tools complete"
} else {
    Write-Warn "Download-FedCompliance-Kit.ps1 not found in $scriptRoot"
}

# ---------------------------------------------------------------------------
# Step 2 — Offline Root CA Kit
# ---------------------------------------------------------------------------
if (-not $SkipOfflineCAKit) {
    Write-Section "Step 2 — Offline Root CA Kit"
    $rootCAScript = Join-Path $scriptRoot "Download-OfflineCA-Kit.ps1"
    $rootCAOutput = Join-Path $OutputPath "09-OfflineRootCA-Kit"
    if (Test-Path $rootCAScript) {
        Write-Host "  Running Download-OfflineCA-Kit.ps1..." -ForegroundColor White
        & $rootCAScript -OutputPath $rootCAOutput
        Write-OK "Offline Root CA kit complete → $rootCAOutput"
    } else {
        Write-Warn "Download-OfflineCA-Kit.ps1 not found in $scriptRoot"
    }
} else {
    Write-Info "Skipping Offline Root CA kit (-SkipOfflineCAKit)"
}

# ---------------------------------------------------------------------------
# Step 3 — Issuing CA Kit
# ---------------------------------------------------------------------------
if (-not $SkipIssuingCAKit) {
    Write-Section "Step 3 — Enterprise Issuing CA Kit"
    $issuingScript = Join-Path $scriptRoot "Download-IssuingCA-Kit.ps1"
    $issuingOutput = Join-Path $OutputPath "10-IssuingCA-Kit"
    if (Test-Path $issuingScript) {
        Write-Host "  Running Download-IssuingCA-Kit.ps1..." -ForegroundColor White
        & $issuingScript -StagingPath $issuingOutput
        Write-OK "Issuing CA kit complete → $issuingOutput"
    } else {
        Write-Warn "Download-IssuingCA-Kit.ps1 not found in $scriptRoot"
    }
} else {
    Write-Info "Skipping Issuing CA kit (-SkipIssuingCAKit)"
}

# ---------------------------------------------------------------------------
# Step 4 — Manual download reminder (SCAP SCC)
# ---------------------------------------------------------------------------
Write-Section "Step 4 — Manual Download Required: SCAP SCC"

$sccDest = Join-Path $OutputPath "00-SCAP-SCC"
if (-not (Test-Path $sccDest)) { New-Item -ItemType Directory -Path $sccDest -Force | Out-Null }

$placeholder = Join-Path $sccDest "PUT-SCAP-SCC-INSTALLER-HERE.txt"
Set-Content -Path $placeholder -Value @"
SCAP Compliance Checker (SCC) — Manual Download Required

The SCC installer requires a DoD CAC or ECA certificate to access the
download page at cyber.mil. See the full instructions in:
  Tools-Kit\Manual-Downloads\SCAP-SCC-Instructions.txt

After you download SCC, place the installer (.exe or .zip) in this folder:
  $sccDest

Then install it on your lab VMs by running the installer as Administrator.
"@

Write-Warn "SCAP SCC requires manual download — see Manual-Downloads\SCAP-SCC-Instructions.txt"
Write-Info "Placeholder file created at: $sccDest"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  DOWNLOAD COMPLETE" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Tool staging folder: $OutputPath" -ForegroundColor White
Write-Host ""
Write-Host "  To take these tools to a lab VM:" -ForegroundColor White
Write-Host "  Option A — USB: copy the entire FedCompliance-Tools\ folder to a drive" -ForegroundColor DarkGray
Write-Host "  Option B — PowerShell Direct from Hyper-V host:" -ForegroundColor DarkGray
Write-Host "    `$s = New-PSSession -VMName 'Lab-DC01' -Credential (Get-Credential)" -ForegroundColor Cyan
Write-Host "    Copy-Item -Path '$OutputPath' -ToSession `$s -Destination 'C:\' -Recurse" -ForegroundColor Cyan
Write-Host ""
Write-Host "  STILL NEEDED: SCAP SCC installer — see Manual-Downloads\SCAP-SCC-Instructions.txt" -ForegroundColor Yellow
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host ""
