#Requires -Version 5.1
<#
.SYNOPSIS
    Packs the CAC-Lab-Kit into a distributable zip, ready to unpack over any
    existing copy to update it.

.DESCRIPTION
    Collects every file in the kit except large binaries (*.iso, *.vhdx) and
    generated/session-specific artifacts (.docx status reports, SCC HTML reports).
    Scan result zips (Before-MFA, After-MFA) are included - they are evidence.

    Output zip is date-stamped and placed next to the kit root by default.

.PARAMETER KitRoot
    Path to the inner CAC-Lab-Kit-20260526 folder (the one that contains
    Lab-Kit\, Tools-Kit\, Architecture\, etc.).
    Defaults to the folder this script lives in.

.PARAMETER OutputDir
    Where to write the zip. Defaults to the parent of KitRoot.

.PARAMETER Label
    Optional label appended to the zip filename, e.g. "Session3".
    Default: today's date (yyyyMMdd).

.PARAMETER IncludeScanReports
    Switch - if specified, also includes the large SCC HTML reports
    in Compliance-Reports\Before-MFA\ and Compliance-Reports\After-MFA\.
    Default: excluded (the raw .zip artifacts and XCCDF XML are always included).

.EXAMPLE
    # Basic - creates CAC-Lab-Kit-20260527.zip next to this folder
    .\Pack-LabKit.ps1

.EXAMPLE
    # With a label
    .\Pack-LabKit.ps1 -Label "AfterPhase9"

.EXAMPLE
    # Write to Desktop
    .\Pack-LabKit.ps1 -OutputDir "$env:USERPROFILE\Desktop"

.EXAMPLE
    # Include the large HTML scan reports too
    .\Pack-LabKit.ps1 -IncludeScanReports
#>

[CmdletBinding()]
param(
    [string]$KitRoot        = $PSScriptRoot,
    [string]$OutputDir      = (Split-Path $PSScriptRoot -Parent),
    [string]$Label          = (Get-Date -Format 'yyyyMMdd'),
    [switch]$IncludeScanReports
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

# -- Banner --------------------------------------------------------------------
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor DarkCyan
Write-Host "  |        CAC Lab Kit - Pack for Distribution           |" -ForegroundColor DarkCyan
Write-Host "  +======================================================+" -ForegroundColor DarkCyan
Write-Host ""

# -- Validate kit root ---------------------------------------------------------
if (-not (Test-Path $KitRoot)) {
    Write-Fatal "KitRoot not found: $KitRoot"
}

# Confirm it looks right
$expectedFolders = @('Lab-Kit', 'Tools-Kit', 'Architecture')
foreach ($f in $expectedFolders) {
    if (-not (Test-Path (Join-Path $KitRoot $f))) {
        Write-Fatal "Expected subfolder '$f' not found in KitRoot: $KitRoot`nAre you running this from inside the CAC-Lab-Kit-20260526 folder?"
    }
}

Write-Step "Kit root   : $KitRoot"
Write-Step "Output dir : $OutputDir"
Write-Step "Label      : $Label"

# -- Exclusion rules -----------------------------------------------------------
#
#   Always excluded:
#     *.iso        - Windows Server ISO, 5.7 GB, not redistributable
#     *.vhdx       - VM disk images (if any land here)
#     *.vmdk       - same
#     .git\        - version control internals
#     *.docx       - generated status reports (session-specific)
#     *.pdf        - same
#     PUT-*-HERE.txt - placeholder files (script downloads replace them)
#
#   Excluded by default (included with -IncludeScanReports):
#     Compliance-Reports\**\*.html - large SCC HTML reports (~4 MB each)
#
#   Always INCLUDED even though they look like binaries:
#     Compliance-Reports\**\*.zip  - scan result zips (evidence)
#     Compliance-Reports\**\*.xml  - XCCDF result XML
#     Compliance-Reports\**\*.ckl  - STIG Viewer checklists
#     Lab-Kit\05-Compliance\Before-MFA\*.zip - staged raw scan zips

$excludeExtensions = @('.iso', '.vhdx', '.vmdk', '.docx', '.pdf')
$excludeDirs       = @('.git', '.github', '.claude', '.idea', '.vs', '.vscode', 'node_modules')
$excludeNames      = @('PUT-SCAP-SCC-INSTALLER-HERE.txt', 'PUT-NESSUS-INSTALLER-HERE.txt')

# -- Collect files -------------------------------------------------------------
Write-Step "Scanning files..."

$allFiles = Get-ChildItem -Path $KitRoot -Recurse -File

$included  = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$skipped   = [System.Collections.Generic.List[string]]::new()

foreach ($file in $allFiles) {
    $rel = $file.FullName.Substring($KitRoot.Length).TrimStart('\', '/')

    # Skip excluded directories
    $inExcludedDir = $false
    foreach ($dir in $excludeDirs) {
        if ($rel -like "$dir\*" -or $rel -like "$dir/*" -or $rel -eq $dir) {
            $inExcludedDir = $true; break
        }
    }
    if ($inExcludedDir) { $skipped.Add("DIR  $rel"); continue }

    # Skip by extension
    if ($excludeExtensions -contains $file.Extension.ToLower()) {
        $skipped.Add("EXT  $rel  ($([math]::Round($file.Length/1MB,1)) MB)"); continue
    }

    # Skip by exact filename
    if ($excludeNames -contains $file.Name) {
        $skipped.Add("NAME $rel"); continue
    }

    # Skip large HTML scan reports unless -IncludeScanReports
    if (-not $IncludeScanReports) {
        if ($file.Extension -eq '.html' -and
            ($rel -like 'Compliance-Reports\*' -or $rel -like 'Compliance-Reports/*')) {
            $skipped.Add("HTML $rel  ($([math]::Round($file.Length/1KB,0)) KB - use -IncludeScanReports to include)"); continue
        }
    }

    $included.Add($file)
}

Write-OK "Files to include : $($included.Count)"
Write-Warn "Files excluded   : $($skipped.Count)"

if ($skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "  Excluded:" -ForegroundColor DarkGray
    foreach ($s in $skipped) {
        Write-Host "    - $s" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# -- Build zip -----------------------------------------------------------------
$zipName = "CAC-Lab-Kit-$Label.zip"
$zipPath = Join-Path $OutputDir $zipName

if (Test-Path $zipPath) {
    Write-Warn "Output zip already exists - deleting: $zipPath"
    Remove-Item $zipPath -Force
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Step "Building zip: $zipPath"

# Load BOTH compression assemblies - ZipArchive lives in System.IO.Compression,
# while ZipFile (the higher-level wrapper) lives in System.IO.Compression.FileSystem.
# PowerShell 5.1 in a fresh session needs both loaded explicitly.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream   = [System.IO.File]::Create($zipPath)
$zipArchive  = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

# Get the folder name that will be the root inside the zip
$kitFolderName = Split-Path $KitRoot -Leaf   # e.g. "CAC-Lab-Kit-20260526"

$totalBytes = 0
$fileCount  = 0

foreach ($file in $included) {
    # Relative path inside the zip, rooted at the kit folder name
    $rel = $file.FullName.Substring($KitRoot.Length).TrimStart('\', '/')
    $entryName = "$kitFolderName\$rel" -replace '/', '\'

    $entry       = $zipArchive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $entryStream = $entry.Open()
    $fileStream  = [System.IO.File]::OpenRead($file.FullName)
    $fileStream.CopyTo($entryStream)
    $fileStream.Close()
    $entryStream.Close()

    $totalBytes += $file.Length
    $fileCount++
}

$zipArchive.Dispose()
$zipStream.Dispose()

# -- Report --------------------------------------------------------------------
$zipSize     = (Get-Item $zipPath).Length
$sourceMB    = [math]::Round($totalBytes / 1MB, 1)
$zipMB       = [math]::Round($zipSize   / 1MB, 1)
$ratio       = if ($totalBytes -gt 0) { [math]::Round((1 - $zipSize/$totalBytes) * 100, 0) } else { 0 }

Write-Host ""
Write-Host "  +-----------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  ZIP CREATED SUCCESSFULLY                           |" -ForegroundColor Green
Write-Host "  +-----------------------------------------------------+" -ForegroundColor Green
Write-Host ("  |  File     : {0,-37}|" -f $zipName) -ForegroundColor Green
Write-Host ("  |  Location : {0,-37}|" -f ($OutputDir.Substring([math]::Max(0,$OutputDir.Length-37)))) -ForegroundColor Green
Write-Host ("  |  Files    : {0,-37}|" -f "$fileCount files packed") -ForegroundColor Green
Write-Host ("  |  Source   : {0,-37}|" -f "${sourceMB} MB uncompressed") -ForegroundColor Green
Write-Host ("  |  Zip size : {0,-37}|" -f "${zipMB} MB  (${ratio}% compression)") -ForegroundColor Green
Write-Host "  +-----------------------------------------------------+" -ForegroundColor Green
Write-Host ""

# -- How to use ----------------------------------------------------------------
Write-Host "  HOW TO USE THIS ZIP" -ForegroundColor Yellow
Write-Host ""
Write-Host "  To update an existing installation - extract and overwrite:" -ForegroundColor White
Write-Host "    Expand-Archive -Path '$zipPath' ``" -ForegroundColor Gray
Write-Host "                   -DestinationPath 'C:\' -Force" -ForegroundColor Gray
Write-Host ""
Write-Host "  This overwrites all scripts and docs in C:\$kitFolderName\" -ForegroundColor DarkGray
Write-Host "  It does NOT remove files that were deleted from this version." -ForegroundColor DarkGray
Write-Host "  The Windows Server ISO is NOT included - keep your existing copy." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  To do a clean install on a new machine:" -ForegroundColor White
Write-Host "    1. Copy $zipName to the new machine" -ForegroundColor Gray
Write-Host "    2. Expand-Archive to C:\ (creates C:\$kitFolderName\)" -ForegroundColor Gray
Write-Host "    3. Place Server 2025 Standard.iso in C:\$kitFolderName\Lab-Kit\01-HyperV-Host\" -ForegroundColor Gray
Write-Host "    4. Follow WALKTHROUGH.md" -ForegroundColor Gray
Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
