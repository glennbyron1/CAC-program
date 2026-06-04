# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Automates the full SCAP before/after compliance scan loop for the CAC/PIV lab.

.DESCRIPTION
    Orchestrates the complete SCAP compliance workflow in one script:

    Phase 1 (Before):
        1. Runs SCAP SCC against the target host (headless, no GUI)
        2. Waits for results, then stages them to Compliance-Reports\Before-MFA\
        3. Feeds the XCCDF XML through the scap_summary Docker tool
        4. Saves the CAT I/II/III baseline report

    Phase 2 (Harden):
        5. Optionally runs the Ansible STIG hardening playbook via WSL or a control node
        6. Waits for confirmation that hardening and GPO have been applied

    Phase 3 (After):
        7. Runs SCAP SCC again against the same target
        8. Stages results to Compliance-Reports\After-MFA\
        9. Feeds XCCDF through scap_summary Docker tool
       10. Generates a side-by-side delta report (Before vs After compliance %)

    The delta report is saved as Compliance-Reports\Delta-Report.txt and is
    suitable for pasting into the SAR template.

    Run -Phase Before, -Phase After, or -Phase Full to control which stages execute.
    Use -WhatIf to preview without running scans.

.PARAMETER Phase
    Which phase(s) to run:
      Before  - run the baseline scan only
      After   - run the hardened scan only (assumes Before already done)
      Full    - run the complete Before → Harden → After loop
    Default: Full

.PARAMETER TargetHost
    Hostname or IP address of the system to scan.
    Default: localhost (scans the machine running the script)

.PARAMETER SccPath
    Full path to cscc.exe.
    Default: C:\Program Files\SCAP Compliance Checker\cscc.exe

.PARAMETER BenchmarkPath
    Full path to the SCAP benchmark XML (.xml or .zip).
    Default: C:\FedCompliance-Tools\00-SCAP-SCC\Benchmarks\U_MS_Windows_Server_2022_STIG_SCAP_1-0_Benchmark.xml

.PARAMETER SccResultsRoot
    Root directory where SCC writes its output.
    Default: $env:USERPROFILE\SCC\Results

.PARAMETER RepoRoot
    Root of the CAC-program repository.
    Default: resolved automatically from script location

.PARAMETER SkipHardening
    Skip the Ansible hardening step — useful if hardening was applied manually.

.PARAMETER DockerImage
    Name of the scap_summary Docker image.
    Default: scap-summary

.EXAMPLE
    # Full automated loop — scan, harden, scan again, generate delta
    .\Invoke-SCAPWorkflow.ps1 -Phase Full

.EXAMPLE
    # Baseline scan only against a remote target
    .\Invoke-SCAPWorkflow.ps1 -Phase Before -TargetHost 192.168.1.11

.EXAMPLE
    # After-hardening scan only (hardening was already applied manually)
    .\Invoke-SCAPWorkflow.ps1 -Phase After -SkipHardening

.EXAMPLE
    # Preview what would run without executing anything
    .\Invoke-SCAPWorkflow.ps1 -Phase Full -WhatIf

.NOTES
    Prerequisites:
      - SCAP SCC installed (download from public.cyber.mil — free, no login required)
      - Windows Server 2022 STIG benchmark downloaded and placed in BenchmarkPath
      - Docker Desktop running (for scap_summary)
      - Ansible control node reachable (for -Phase Full without -SkipHardening)
      - Run from an elevated PowerShell session on the target or scan controller

    SCAP SCC command-line reference:
      cscc.exe --noreport  -- suppress interactive report viewer
      cscc.exe --benchmark <path>
      cscc.exe --outdir    <path>
      cscc.exe --host      <hostname>    (for remote scans via WMI)

    Download SCAP SCC: https://public.cyber.mil/stigs/scap/
    Download benchmarks: https://public.cyber.mil/stigs/scap/

    Author: Glenn Byron
    Part of the CAC/PIV ICAM portfolio — Lab-Kit/05-Compliance/
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Before', 'After', 'Full')]
    [string] $Phase = 'Full',

    [string] $TargetHost = 'localhost',

    [string] $SccPath = 'C:\Program Files\SCAP Compliance Checker\cscc.exe',

    [string] $BenchmarkPath = 'C:\FedCompliance-Tools\00-SCAP-SCC\Benchmarks\U_MS_Windows_Server_2022_STIG_SCAP_1-0_Benchmark.xml',

    [string] $SccResultsRoot = "$env:USERPROFILE\SCC\Results",

    [string] $RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch] $SkipHardening,

    [string] $DockerImage = 'scap-summary'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host "`n[ $(Get-Date -Format 'HH:mm:ss') ] $Message" -ForegroundColor $Color
}

function Write-OK   { param([string]$m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Warn { param([string]$m) Write-Host "  [!!]  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  [XX]  $m" -ForegroundColor Red    }

function Assert-Tool {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) {
        Write-Fail "$Name not found at: $Path"
        Write-Host "  Download from: https://public.cyber.mil/stigs/scap/" -ForegroundColor Gray
        throw "Required tool missing: $Name"
    }
    Write-OK "$Name found"
}

function Get-LatestSccResultDir {
    param([string]$ResultsRoot)
    $dirs = Get-ChildItem -Path $ResultsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    if (-not $dirs) { throw "No SCC result directories found in: $ResultsRoot" }
    return $dirs[0].FullName
}

function Get-XccdfFile {
    param([string]$ResultDir)
    $xccdf = Get-ChildItem -Path $ResultDir -Filter '*XCCDF-Results*.xml' -Recurse -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1
    if (-not $xccdf) {
        # SCC older versions use a different naming pattern
        $xccdf = Get-ChildItem -Path $ResultDir -Filter '*results*.xml' -Recurse -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
    }
    if (-not $xccdf) { throw "No XCCDF results XML found in: $ResultDir" }
    return $xccdf.FullName
}

function Get-HtmlReport {
    param([string]$ResultDir)
    $html = Get-ChildItem -Path $ResultDir -Filter '*.html' -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    return $html?.FullName
}

function Invoke-SccScan {
    param(
        [string] $SccExe,
        [string] $Benchmark,
        [string] $OutDir,
        [string] $Target
    )

    Write-Step "Running SCAP SCC scan against: $Target"

    $sccArgs = @(
        '--noreport'          # suppress interactive viewer
        '--benchmark', $Benchmark
        '--outdir',   $OutDir
    )
    if ($Target -ne 'localhost' -and $Target -ne $env:COMPUTERNAME) {
        $sccArgs += '--host', $Target
        Write-Warn "Remote scan — ensure WMI/DCOM is allowed through the target firewall"
    }

    Write-Host "  Command: $SccExe $($sccArgs -join ' ')" -ForegroundColor Gray

    if ($PSCmdlet.ShouldProcess($Target, 'Run SCAP SCC scan')) {
        $proc = Start-Process -FilePath $SccExe -ArgumentList $sccArgs `
                              -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            throw "SCAP SCC exited with code $($proc.ExitCode). Check SCC logs in: $OutDir"
        }
        Write-OK "SCC scan completed (exit code 0)"
    }
}

function Invoke-ScapSummaryDocker {
    param(
        [string] $XccdfFile,
        [string] $OutputTxt,
        [string] $Image
    )

    Write-Step "Running scap_summary Docker tool"

    # Docker mounts the directory containing the XCCDF file into /data
    $dataDir = Split-Path -Parent $XccdfFile
    $fileName = Split-Path -Leaf   $XccdfFile

    $dockerArgs = @(
        'run', '--rm'
        '-v', "${dataDir}:/data"
        $Image
        "/data/$fileName"
        '--output', "/data/$(Split-Path -Leaf $OutputTxt)"
        '--format', 'text'
    )

    Write-Host "  Command: docker $($dockerArgs -join ' ')" -ForegroundColor Gray

    if ($PSCmdlet.ShouldProcess($XccdfFile, 'Run scap_summary Docker tool')) {
        $result = & docker @dockerArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Docker scap_summary returned non-zero exit. Output:"
            $result | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        } else {
            Write-OK "scap_summary report written to: $OutputTxt"
        }
        return $result
    }
}

function Read-ComplianceSummary {
    param([string]$ReportFile)
    # Extract pass%, CAT I/II/III counts from the scap_summary text report
    $summary = @{ PassPct = 'N/A'; CatI = 'N/A'; CatII = 'N/A'; CatIII = 'N/A' }
    if (-not (Test-Path $ReportFile)) { return $summary }

    $content = Get-Content $ReportFile -Raw
    if ($content -match 'Compliance.*?(\d+\.?\d*)\s*%')          { $summary.PassPct = $Matches[1] + '%' }
    if ($content -match 'CAT\s*I.*?(\d+)\s+fail')               { $summary.CatI    = $Matches[1] }
    if ($content -match 'CAT\s*II.*?(\d+)\s+fail')              { $summary.CatII   = $Matches[1] }
    if ($content -match 'CAT\s*III.*?(\d+)\s+fail')             { $summary.CatIII  = $Matches[1] }
    return $summary
}

function Write-DeltaReport {
    param(
        [hashtable] $Before,
        [hashtable] $After,
        [string]    $OutputFile,
        [string]    $Target
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $lines = @(
        "=" * 62
        "  SCAP Compliance Delta Report"
        "  Target  : $Target"
        "  Generated: $timestamp"
        "=" * 62
        ""
        "  Metric              Before          After           Change"
        "  " + ("-" * 58)
        "  Compliance %        $($Before.PassPct.PadRight(16))$($After.PassPct.PadRight(16))"
        "  CAT I Failures      $($Before.CatI.PadRight(16))$($After.CatI.PadRight(16))"
        "  CAT II Failures     $($Before.CatII.PadRight(16))$($After.CatII.PadRight(16))"
        "  CAT III Failures    $($Before.CatIII.PadRight(16))$($After.CatIII.PadRight(16))"
        ""
        "  Files"
        "  Before XCCDF : Compliance-Reports\Before-MFA\XCCDF-Results.xml"
        "  After  XCCDF : Compliance-Reports\After-MFA\XCCDF-Results.xml"
        "  Before Report: Compliance-Reports\Before-MFA\scap-summary.txt"
        "  After  Report: Compliance-Reports\After-MFA\scap-summary.txt"
        ""
        "  Paste these figures into Architecture\RMF-Templates\SAR-Template.md"
        "=" * 62
    )

    if ($PSCmdlet.ShouldProcess($OutputFile, 'Write delta report')) {
        $lines | Set-Content -Path $OutputFile -Encoding UTF8
        Write-OK "Delta report saved: $OutputFile"
    }
    $lines | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
}

# ─────────────────────────────────────────────────────────────────────────────
# Resolve paths
# ─────────────────────────────────────────────────────────────────────────────

$complianceDir = Join-Path $RepoRoot 'Compliance-Reports'
$beforeDir     = Join-Path $complianceDir 'Before-MFA'
$afterDir      = Join-Path $complianceDir 'After-MFA'
$deltaReport   = Join-Path $complianceDir 'Delta-Report.txt'
$sccScanOutDir = Join-Path $env:TEMP "SCC-Scan-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

foreach ($d in @($beforeDir, $afterDir, $sccScanOutDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Pre-flight checks" "White"
Assert-Tool -Path $SccPath      -Name 'SCAP SCC (cscc.exe)'
Assert-Tool -Path $BenchmarkPath -Name 'Windows Server 2022 STIG Benchmark'

# Check Docker is available (needed for scap_summary)
try {
    $null = & docker info 2>&1
    if ($LASTEXITCODE -eq 0) { Write-OK "Docker is running" }
    else { Write-Warn "Docker not reachable — scap_summary step will be skipped" }
} catch {
    Write-Warn "Docker not found — scap_summary step will be skipped"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — BEFORE SCAN
# ─────────────────────────────────────────────────────────────────────────────

if ($Phase -in @('Before', 'Full')) {

    Write-Step "PHASE 1 — Baseline scan (before hardening)" "Yellow"

    Invoke-SccScan -SccExe $SccPath -Benchmark $BenchmarkPath `
                   -OutDir $sccScanOutDir -Target $TargetHost

    $latestDir  = Get-LatestSccResultDir -ResultsRoot $SccResultsRoot
    $xccdfFile  = Get-XccdfFile -ResultDir $latestDir
    $htmlReport = Get-HtmlReport -ResultDir $latestDir

    # Copy results to repo
    $beforeXccdf = Join-Path $beforeDir 'XCCDF-Results.xml'
    $beforeHtml  = Join-Path $beforeDir 'Baseline-Compliance.html'
    $beforeTxt   = Join-Path $beforeDir 'scap-summary.txt'

    if ($PSCmdlet.ShouldProcess($beforeXccdf, 'Copy XCCDF results')) {
        Copy-Item -Path $xccdfFile -Destination $beforeXccdf -Force
        Write-OK "XCCDF results staged: $beforeXccdf"
    }
    if ($htmlReport -and $PSCmdlet.ShouldProcess($beforeHtml, 'Copy HTML report')) {
        Copy-Item -Path $htmlReport -Destination $beforeHtml -Force
        Write-OK "HTML report staged: $beforeHtml"
    }

    Invoke-ScapSummaryDocker -XccdfFile $beforeXccdf -OutputTxt $beforeTxt -Image $DockerImage
    $beforeSummary = Read-ComplianceSummary -ReportFile $beforeTxt

    Write-Host "`n  Baseline compliance: $($beforeSummary.PassPct)  " `
               "CAT I: $($beforeSummary.CatI)  " `
               "CAT II: $($beforeSummary.CatII)  " `
               "CAT III: $($beforeSummary.CatIII)" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — HARDENING
# ─────────────────────────────────────────────────────────────────────────────

if ($Phase -eq 'Full' -and -not $SkipHardening) {

    Write-Step "PHASE 2 — Apply STIG hardening" "Magenta"

    $ansiblePlaybook = Join-Path $RepoRoot 'Lab-Kit\Ansible\windows-stig-hardening.yml'
    $ansibleInventory = Join-Path $RepoRoot 'Lab-Kit\Ansible\inventory.ini'

    if (Test-Path $ansiblePlaybook) {
        Write-Host "  Ansible playbook: $ansiblePlaybook" -ForegroundColor Gray
        Write-Host "  Inventory       : $ansibleInventory" -ForegroundColor Gray

        # Ansible runs on a Linux control node — check if WSL is available
        $wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue

        if ($wslAvailable) {
            Write-Step "Running Ansible via WSL" "Magenta"
            $wslPlaybook   = ($ansiblePlaybook   -replace '\\', '/') -replace '^([A-Z]):', '/mnt/$1'.ToLower()
            $wslInventory  = ($ansibleInventory  -replace '\\', '/') -replace '^([A-Z]):', '/mnt/$1'.ToLower()

            if ($PSCmdlet.ShouldProcess($TargetHost, 'Run Ansible STIG hardening playbook')) {
                wsl ansible-playbook -i $wslInventory $wslPlaybook --limit $TargetHost
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Ansible returned non-zero exit code. Verify hardening was applied."
                } else {
                    Write-OK "Ansible hardening playbook completed"
                }
            }
        } else {
            Write-Warn "WSL not found. Run Ansible manually from your control node:"
            Write-Host "  ansible-playbook -i inventory.ini windows-stig-hardening.yml --limit $TargetHost" `
                       -ForegroundColor Gray
            Write-Host ""
            Read-Host "  Press ENTER when hardening and GPO have been applied and the system has rebooted"
        }
    } else {
        Write-Warn "Ansible playbook not found at: $ansiblePlaybook"
        Write-Host "  Apply hardening manually, then press ENTER to continue" -ForegroundColor Gray
        Read-Host "  Press ENTER to continue to the after-hardening scan"
    }

    # Always pause to allow Group Policy to apply and system to stabilize
    Write-Host "`n  Waiting 60 seconds for Group Policy to propagate..." -ForegroundColor Gray
    if (-not $WhatIfPreference) { Start-Sleep -Seconds 60 }
    Write-OK "Ready for post-hardening scan"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 — AFTER SCAN
# ─────────────────────────────────────────────────────────────────────────────

if ($Phase -in @('After', 'Full')) {

    Write-Step "PHASE 3 — Post-hardening scan" "Green"

    # New output dir for the after scan so results don't overwrite
    $sccScanOutDir = Join-Path $env:TEMP "SCC-Scan-After-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $sccScanOutDir -Force | Out-Null

    Invoke-SccScan -SccExe $SccPath -Benchmark $BenchmarkPath `
                   -OutDir $sccScanOutDir -Target $TargetHost

    $latestDir  = Get-LatestSccResultDir -ResultsRoot $SccResultsRoot
    $xccdfFile  = Get-XccdfFile -ResultDir $latestDir
    $htmlReport = Get-HtmlReport -ResultDir $latestDir

    $afterXccdf = Join-Path $afterDir 'XCCDF-Results.xml'
    $afterHtml  = Join-Path $afterDir 'Hardened-Compliance.html'
    $afterTxt   = Join-Path $afterDir 'scap-summary.txt'

    if ($PSCmdlet.ShouldProcess($afterXccdf, 'Copy XCCDF results')) {
        Copy-Item -Path $xccdfFile -Destination $afterXccdf -Force
        Write-OK "XCCDF results staged: $afterXccdf"
    }
    if ($htmlReport -and $PSCmdlet.ShouldProcess($afterHtml, 'Copy HTML report')) {
        Copy-Item -Path $htmlReport -Destination $afterHtml -Force
        Write-OK "HTML report staged: $afterHtml"
    }

    Invoke-ScapSummaryDocker -XccdfFile $afterXccdf -OutputTxt $afterTxt -Image $DockerImage
    $afterSummary = Read-ComplianceSummary -ReportFile $afterTxt

    Write-Host "`n  Hardened compliance: $($afterSummary.PassPct)  " `
               "CAT I: $($afterSummary.CatI)  " `
               "CAT II: $($afterSummary.CatII)  " `
               "CAT III: $($afterSummary.CatIII)" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# DELTA REPORT
# ─────────────────────────────────────────────────────────────────────────────

if ($Phase -eq 'Full') {

    Write-Step "Generating delta report" "White"

    $beforeSummary = Read-ComplianceSummary -ReportFile (Join-Path $beforeDir 'scap-summary.txt')
    $afterSummary  = Read-ComplianceSummary -ReportFile (Join-Path $afterDir  'scap-summary.txt')

    Write-DeltaReport -Before $beforeSummary -After $afterSummary `
                      -OutputFile $deltaReport -Target $TargetHost
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Workflow complete" "Cyan"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. Open Compliance-Reports\Before-MFA\Baseline-Compliance.html  (baseline scan)"    -ForegroundColor Gray
Write-Host "  2. Open Compliance-Reports\After-MFA\Hardened-Compliance.html   (hardened scan)"    -ForegroundColor Gray
Write-Host "  3. Review Compliance-Reports\Delta-Report.txt"                                       -ForegroundColor Gray
Write-Host "  4. Paste delta figures into Architecture\RMF-Templates\SAR-Template.md"             -ForegroundColor Gray
Write-Host "  5. Take side-by-side screenshot of both HTML reports for Demo-Walkthrough.md"       -ForegroundColor Gray
Write-Host ""
