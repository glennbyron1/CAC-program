#Requires -Version 5.1
<#
.SYNOPSIS
    Stages everything you need on a USB drive to set up the physical laptop:
    SCC installer, Windows 11 STIG SCAP content, the Root CA cert, the laptop
    guide, the VPN client deployer, and a generated README that explains what
    each item is for.

.DESCRIPTION
    Run this on the Hyper-V host (or wherever your FedCompliance-Tools folder
    lives). It collects the laptop-specific files into a single staging folder
    so you can drag-and-drop it to a USB drive in one move.

    What it stages:
      1. SCC 5.10.2 installer        (from FedCompliance-Tools\00-SCAP-SCC\)
      2. Windows 11 STIG SCAP content (from FedCompliance-Tools\03-SCAP-Content\)
      3. Lab Root CA certificate     (from -RootCACertPath, if provided)
      4. Add-Physical-Laptop.md      (the guide - lives next to this script)
      5. Deploy-VPNClient.ps1        (Lab-Kit\04-Workstation\)
      6. README.txt                  (auto-generated index of the USB contents)

    Items that cannot be found are logged as warnings but do not stop the run -
    that way you can see at a glance what still needs to be sourced.

    Sensitive files (the Root CA cert) are staged but the script never writes
    private keys. Confirm you're exporting the .cer (public cert) only.

.PARAMETER OutputPath
    Where to create the staging folder. Defaults to your Desktop.
    A timestamped subfolder is created inside this path.

.PARAMETER ToolsRoot
    Path to your downloaded FedCompliance-Tools folder. Defaults to
    C:\FedCompliance-Tools. Override if you keep it elsewhere.

.PARAMETER RepoRoot
    Path to the CAC-program repo root. Defaults to the repo this script lives
    in (two levels above this script: Lab-Kit\06-PhysicalEndpoint\ -> repo root).

.PARAMETER RootCACertPath
    Optional. Full path to the Lab Root CA .cer file (public cert) exported
    from the Offline Root CA VM. If not specified, the script lists the manual
    export steps in the generated README and skips that item.

.PARAMETER Zip
    Switch - also create a .zip of the staging folder for easier transfer.

.PARAMETER Force
    Overwrite an existing staging folder with the same name.

.EXAMPLE
    # Basic - stages to a timestamped folder on the Desktop
    .\Stage-LaptopUSB.ps1

.EXAMPLE
    # Custom tools location and include the Root CA cert
    .\Stage-LaptopUSB.ps1 `
        -ToolsRoot "D:\FedCompliance-Tools" `
        -RootCACertPath "C:\CA-Export\Lab-RootCA.cer"

.EXAMPLE
    # Stage and zip in one go, output direct to USB drive
    .\Stage-LaptopUSB.ps1 -OutputPath "E:\" -Zip

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program - Phase 4 Lab Execution
    Last Edit  : 2026-06-01
#>

[CmdletBinding()]
param(
    [string]$OutputPath     = (Join-Path $env:USERPROFILE 'Desktop'),
    [string]$ToolsRoot      = 'C:\FedCompliance-Tools',
    [string]$RepoRoot       = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$RootCACertPath = '',
    [switch]$Zip,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

# -- Banner -------------------------------------------------------------------
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor DarkCyan
Write-Host "  |     CAC Lab Kit - Stage Files for Physical Laptop     |" -ForegroundColor DarkCyan
Write-Host "  +======================================================+" -ForegroundColor DarkCyan
Write-Host ""

# -- Validate inputs ----------------------------------------------------------
if (-not (Test-Path $OutputPath)) { Write-Fatal "OutputPath not found: $OutputPath" }
if (-not (Test-Path $RepoRoot))   { Write-Fatal "RepoRoot not found: $RepoRoot" }

$timestamp   = Get-Date -Format 'yyyyMMdd-HHmm'
$stageName   = "Laptop-USB-$timestamp"
$stagePath   = Join-Path $OutputPath $stageName

if ((Test-Path $stagePath) -and -not $Force) {
    Write-Fatal "Staging folder already exists: $stagePath (use -Force to overwrite)"
}
if (Test-Path $stagePath) { Remove-Item $stagePath -Recurse -Force }
New-Item -ItemType Directory -Path $stagePath -Force | Out-Null

Write-Step "Staging to: $stagePath"
Write-Host ""

# -- Track results so the README can reflect what actually shipped -----------
$results = [ordered]@{
    'SCC Installer'        = 'MISSING'
    'Windows 11 STIG SCAP' = 'MISSING'
    'Lab Root CA cert'     = 'MISSING'
    'Add-Physical-Laptop'  = 'MISSING'
    'Deploy-VPNClient.ps1' = 'MISSING'
}

# -- 1. SCC Installer ---------------------------------------------------------
Write-Step '1/5  SCC installer (SCAP Compliance Checker)'
$sccSource = Join-Path $ToolsRoot '00-SCAP-SCC'
if (Test-Path $sccSource) {
    $sccDest = Join-Path $stagePath '01-SCC-Installer'
    New-Item -ItemType Directory -Path $sccDest -Force | Out-Null
    Copy-Item -Path (Join-Path $sccSource '*') -Destination $sccDest -Recurse -Force
    $sccFileCount = (Get-ChildItem $sccDest -Recurse -File).Count
    Write-OK "Copied $sccFileCount file(s) from $sccSource"
    $results['SCC Installer'] = 'OK'
} else {
    Write-Warn "Not found: $sccSource"
    Write-Info "Run Tools-Kit\Download-FedCompliance-Kit.ps1 on the Hyper-V host first."
}
Write-Host ""

# -- 2. Windows 11 STIG SCAP content -----------------------------------------
Write-Step '2/5  Windows 11 STIG SCAP content (XCCDF benchmark)'
$scapSource = Join-Path $ToolsRoot '03-SCAP-Content'
if (Test-Path $scapSource) {
    # Pull only Windows 11 files (not Server 2022, not other OS benchmarks)
    $win11Files = Get-ChildItem -Path $scapSource -Recurse -File |
                  Where-Object { $_.Name -match 'Windows[_ ]11' -or $_.Name -match 'MS_Windows_11' }

    if ($win11Files.Count -gt 0) {
        $scapDest = Join-Path $stagePath '02-Windows11-STIG-SCAP'
        New-Item -ItemType Directory -Path $scapDest -Force | Out-Null
        foreach ($f in $win11Files) {
            Copy-Item -Path $f.FullName -Destination $scapDest -Force
        }
        Write-OK "Copied $($win11Files.Count) Windows 11 benchmark file(s)"
        Write-Info "Versions found: $((($win11Files.Name | Select-String -Pattern 'V\d+R\d+').Matches.Value | Select-Object -Unique) -join ', ')"
        $results['Windows 11 STIG SCAP'] = 'OK'
    } else {
        Write-Warn "No Windows 11 benchmark files in $scapSource"
        Write-Info "Download from public.cyber.mil/stigs/scap/ - look for 'MS_Windows_11_STIG' SCAP 1.3 Benchmark"
    }
} else {
    Write-Warn "Not found: $scapSource"
    Write-Info "Run Tools-Kit\Download-FedCompliance-Kit.ps1 on the Hyper-V host first."
}
Write-Host ""

# -- 3. Lab Root CA cert -----------------------------------------------------
Write-Step '3/5  Lab Root CA certificate (.cer - public cert only)'
if ($RootCACertPath) {
    if (Test-Path $RootCACertPath) {
        # Safety check: make sure it's a .cer/.crt (public), not a .pfx (private key bundle)
        $ext = [IO.Path]::GetExtension($RootCACertPath).ToLower()
        if ($ext -in @('.pfx', '.p12')) {
            Write-Warn "Refusing to stage .pfx/.p12 - that includes the private key. Export the public .cer only."
            Write-Info "On the Root CA VM, run: certutil -ca.cert Lab-RootCA.cer"
        } else {
            $caDest = Join-Path $stagePath '03-RootCA-Cert'
            New-Item -ItemType Directory -Path $caDest -Force | Out-Null
            Copy-Item -Path $RootCACertPath -Destination $caDest -Force
            Write-OK "Copied $((Split-Path $RootCACertPath -Leaf)) ($ext public certificate)"
            $results['Lab Root CA cert'] = 'OK'
        }
    } else {
        Write-Warn "RootCACertPath specified but not found: $RootCACertPath"
    }
} else {
    Write-Warn "No -RootCACertPath specified (skipping - instructions added to README)"
    Write-Info "Export from Lab-OfflineRootCA VM via PSDirect:"
    Write-Info '  Invoke-Command -VMName Lab-OfflineRootCA { certutil -ca.cert C:\Lab-RootCA.cer }'
    Write-Info "  Then Copy-Item -FromSession to pull it back to the host"
}
Write-Host ""

# -- 4. Add-Physical-Laptop.md (the guide) -----------------------------------
Write-Step '4/5  Add-Physical-Laptop.md (the walkthrough)'
$guidePath = Join-Path $PSScriptRoot 'Add-Physical-Laptop.md'
if (Test-Path $guidePath) {
    $guideDest = Join-Path $stagePath '04-Guide'
    New-Item -ItemType Directory -Path $guideDest -Force | Out-Null
    Copy-Item -Path $guidePath -Destination $guideDest -Force
    Write-OK 'Copied Add-Physical-Laptop.md'
    $results['Add-Physical-Laptop'] = 'OK'
} else {
    Write-Warn "Not found: $guidePath"
    Write-Info "Make sure this script is in Lab-Kit\06-PhysicalEndpoint\ alongside the guide."
}
Write-Host ""

# -- 5. Deploy-VPNClient.ps1 -------------------------------------------------
Write-Step '5/5  Deploy-VPNClient.ps1 (for Step 7 VPN test)'
$vpnSource = Join-Path $RepoRoot 'Lab-Kit\04-Workstation\Deploy-VPNClient.ps1'
if (Test-Path $vpnSource) {
    $vpnDest = Join-Path $stagePath '05-VPN-Client'
    New-Item -ItemType Directory -Path $vpnDest -Force | Out-Null
    Copy-Item -Path $vpnSource -Destination $vpnDest -Force
    Write-OK 'Copied Deploy-VPNClient.ps1'
    $results['Deploy-VPNClient.ps1'] = 'OK'
} else {
    Write-Warn "Not found: $vpnSource"
    Write-Info 'Confirm $RepoRoot points at the CAC-program repo root.'
}
Write-Host ""

# -- Generate README on the USB drive ----------------------------------------
Write-Step 'Generating README.txt on the staging root'

$readmeLines = @()
$readmeLines += 'CAC LAB - PHYSICAL LAPTOP USB DROP'
$readmeLines += '===================================='
$readmeLines += ''
$readmeLines += "Created     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$readmeLines += "Created by  : Glenn Byron (Stage-LaptopUSB.ps1)"
$readmeLines += "Source host : $env:COMPUTERNAME"
$readmeLines += ''
$readmeLines += 'Use this USB on the spare laptop being added to lab.local.'
$readmeLines += 'Walk through Add-Physical-Laptop.md (folder 04-Guide).'
$readmeLines += ''
$readmeLines += 'CONTENTS'
$readmeLines += '--------'
foreach ($item in $results.Keys) {
    $status = $results[$item]
    $marker = if ($status -eq 'OK') { '[OK]     ' } else { '[MISSING]' }
    $readmeLines += ('  {0}  {1}' -f $marker, $item)
}
$readmeLines += ''
$readmeLines += 'WALKTHROUGH ORDER (matches Add-Physical-Laptop.md)'
$readmeLines += '--------------------------------------------------'
$readmeLines += '  Step 0  : Snapshot DC01/WS01 + PKI health (run on Hyper-V host, not laptop)'
$readmeLines += '  Step 1  : Create Lab-External vSwitch (Hyper-V host)'
$readmeLines += '  Step 2  : Domain-join laptop -> lab.local'
$readmeLines += '            Before: import Root CA cert (folder 03-RootCA-Cert) into'
$readmeLines += '            Trusted Root Certification Authorities on the laptop.'
$readmeLines += '  Step 3  : gpupdate /force on the laptop'
$readmeLines += '  Step 4  : tpmvscmgr.exe create  +  New-TokenEnrollment.ps1 (on DC01)'
$readmeLines += '  Step 5  : Smart card logon test - TAKE SCREENSHOTS HERE'
$readmeLines += '  Step 6  : Install SCC (folder 01-SCC-Installer)'
$readmeLines += '            Import benchmark from folder 02-Windows11-STIG-SCAP'
$readmeLines += '            Benchmark to select: MS_Windows_11_STIG-<version>'
$readmeLines += '  Step 7  : Run Deploy-VPNClient.ps1 (folder 05-VPN-Client)'
$readmeLines += ''
if ($results['Lab Root CA cert'] -ne 'OK') {
    $readmeLines += 'ROOT CA CERT - NOT STAGED'
    $readmeLines += '-------------------------'
    $readmeLines += 'Export the Lab Root CA public cert from the Offline Root CA VM:'
    $readmeLines += ''
    $readmeLines += '  # From the Hyper-V host:'
    $readmeLines += '  $cred = Get-Credential   # Lab-OfflineRootCA local admin'
    $readmeLines += '  $s    = New-PSSession -VMName Lab-OfflineRootCA -Credential $cred'
    $readmeLines += '  Invoke-Command -Session $s -ScriptBlock {'
    $readmeLines += '      certutil -ca.cert C:\Lab-RootCA.cer'
    $readmeLines += '  }'
    $readmeLines += '  Copy-Item -FromSession $s -Path C:\Lab-RootCA.cer -Destination .'
    $readmeLines += '  Remove-PSSession $s'
    $readmeLines += ''
    $readmeLines += 'Then copy Lab-RootCA.cer to this USB drive, in folder 03-RootCA-Cert.'
    $readmeLines += 'NEVER copy the private key (.pfx/.p12) - the Root CA is offline by design.'
    $readmeLines += ''
}
$readmeLines += 'SAFETY'
$readmeLines += '------'
$readmeLines += '  - This USB contains a public CA certificate and DISA SCAP content.'
$readmeLines += '  - No private keys, no credentials, no internal hostnames.'
$readmeLines += '  - If you added scan results or screenshots, sanitize before pushing'
$readmeLines += '    anything to GitHub (run Scrub-Repo.ps1 -WhatIf first).'

$readmePath = Join-Path $stagePath 'README.txt'
$readmeLines | Out-File -FilePath $readmePath -Encoding UTF8
Write-OK "README.txt written ($($readmeLines.Count) lines)"
Write-Host ""

# -- Summary -----------------------------------------------------------------
Write-Host ("  +-- Summary " + ("-" * 50)) -ForegroundColor DarkCyan
foreach ($item in $results.Keys) {
    $status = $results[$item]
    if ($status -eq 'OK') {
        Write-Host ("    [OK]      " + $item) -ForegroundColor Green
    } else {
        Write-Host ("    [MISSING] " + $item) -ForegroundColor Yellow
    }
}
Write-Host ("  +--" + ("-" * 60)) -ForegroundColor DarkCyan
Write-Host ""

$totalFiles = (Get-ChildItem $stagePath -Recurse -File).Count
$totalSize  = '{0:N1} MB' -f ((Get-ChildItem $stagePath -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Step "Staged $totalFiles file(s), total size $totalSize"
Write-Step "Folder: $stagePath"

# -- Optional zip -------------------------------------------------------------
if ($Zip) {
    Write-Host ""
    Write-Step 'Creating zip archive...'
    $zipPath = "$stagePath.zip"
    if (Test-Path $zipPath) {
        if ($Force) { Remove-Item $zipPath -Force }
        else        { Write-Fatal "Zip already exists: $zipPath (use -Force to overwrite)" }
    }
    Compress-Archive -Path "$stagePath\*" -DestinationPath $zipPath -CompressionLevel Optimal
    $zipSize = '{0:N1} MB' -f ((Get-Item $zipPath).Length / 1MB)
    Write-OK "Zip created: $zipPath ($zipSize)"
}

Write-Host ""
Write-Host "  Done. Drag the staging folder to your USB drive." -ForegroundColor Green
Write-Host ""
