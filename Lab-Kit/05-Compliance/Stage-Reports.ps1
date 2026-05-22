# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Copies the most recent SCAP Compliance Checker (SCC) scan output into the
    repository's Compliance-Reports tracking folders (Before-MFA / After-MFA).

.DESCRIPTION
    Locates the latest SCC results directory, lets you choose whether to stage
    it as the pre-hardening baseline or the post-hardening hardened state, and
    copies the summary HTML report and the XCCDF results XML into the matching
    Compliance-Reports tier with standardized file names.

    Run with -WhatIf to preview the copy operations without changing any files.

.PARAMETER Stage
    Which tier to stage into: "Before" or "After". If omitted, the script
    prompts interactively.

.PARAMETER SccResultsHome
    Root of the SCC results output. Defaults to %USERPROFILE%\SCC\Results.

.EXAMPLE
    .\Stage-Reports.ps1 -WhatIf

.EXAMPLE
    .\Stage-Reports.ps1 -Stage Before

.EXAMPLE
    .\Stage-Reports.ps1            # prompts for tier

.NOTES
    Part of the optional Federal Compliance / Testing track. See
    Architecture/STIG-Hardening-Guide.md for the full workflow.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet("Before","After")]
    [string]$Stage,
    [string]$SccResultsHome = "$env:USERPROFILE\SCC\Results"
)

$RepoBeforeDest = ".\Compliance-Reports\Before-MFA"
$RepoAfterDest  = ".\Compliance-Reports\After-MFA"

# ------------------------------------------------------------------
# 1. Locate the most recent SCC scan directory
# ------------------------------------------------------------------
Write-Host "Locating the latest SCAP Compliance Checker run..." -ForegroundColor Cyan

if (-not (Test-Path $SccResultsHome)) {
    Write-Error "No SCC results directory found at $SccResultsHome. Run a scan first, or pass -SccResultsHome."
    exit 1
}

$LatestSccFolder = Get-ChildItem -Path $SccResultsHome -Directory |
                   Sort-Object LastWriteTime -Descending |
                   Select-Object -First 1

if (-not $LatestSccFolder) {
    Write-Error "No scan folders found under $SccResultsHome."
    exit 1
}

Write-Host "Source: $($LatestSccFolder.FullName)" -ForegroundColor White

# ------------------------------------------------------------------
# 2. Determine destination tier
# ------------------------------------------------------------------
if (-not $Stage) {
    Write-Host ""
    Write-Host "Select the destination tier for this report:" -ForegroundColor White
    Write-Host " [1] Before-MFA (initial baseline snapshot)" -ForegroundColor Yellow
    Write-Host " [2] After-MFA  (post-hardening compliant state)" -ForegroundColor Green
    $selection = Read-Host "Enter choice [1 or 2]"
    switch ($selection) {
        "1" { $Stage = "Before" }
        "2" { $Stage = "After" }
        default { Write-Warning "Invalid choice. Aborting."; exit 1 }
    }
}

if ($Stage -eq "Before") {
    $TargetDest = $RepoBeforeDest
    $FileLabel  = "Baseline"
} else {
    $TargetDest = $RepoAfterDest
    $FileLabel  = "Hardened"
}

# ------------------------------------------------------------------
# 3. Locate the summary HTML and XCCDF XML in the latest scan
# ------------------------------------------------------------------
$HtmlReport = Get-ChildItem -Path $LatestSccFolder.FullName -Filter "*_All_Summary.html" -Recurse |
              Select-Object -First 1
$XmlResults = Get-ChildItem -Path $LatestSccFolder.FullName -Filter "*_All_XCCDF_Results.xml" -Recurse |
              Select-Object -First 1

if (-not ($HtmlReport -and $XmlResults)) {
    Write-Warning "Could not find the standard summary files in the latest scan directory."
    Write-Warning "Confirm the main summary outputs were enabled in the SCC configuration."
    exit 1
}

# ------------------------------------------------------------------
# 4. Stage the files (honors -WhatIf)
# ------------------------------------------------------------------
if (-not (Test-Path $TargetDest)) {
    if ($PSCmdlet.ShouldProcess($TargetDest, "Create destination folder")) {
        New-Item -Path $TargetDest -ItemType Directory -Force | Out-Null
    }
}

$htmlOut = Join-Path $TargetDest "$FileLabel-Report.html"
$xmlOut  = Join-Path $TargetDest "$FileLabel-Results.xml"

if ($PSCmdlet.ShouldProcess($htmlOut, "Copy SCAP summary HTML")) {
    Copy-Item -Path $HtmlReport.FullName -Destination $htmlOut -Force
    Write-Host "Staged: $htmlOut" -ForegroundColor Green
}
if ($PSCmdlet.ShouldProcess($xmlOut, "Copy XCCDF results XML")) {
    Copy-Item -Path $XmlResults.FullName -Destination $xmlOut -Force
    Write-Host "Staged: $xmlOut" -ForegroundColor Green
}

Write-Host ""
if ($WhatIfPreference) {
    Write-Host "DRY-RUN complete. No files were copied. Re-run without -WhatIf to apply." -ForegroundColor Yellow
} else {
    Write-Host "Done. Review with 'git status', then add/commit when ready." -ForegroundColor Cyan
    Write-Host "Remember to run .\Scrub-Repo.ps1 -WhatIf before pushing." -ForegroundColor Cyan
}
