# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Packages the Lab-Kit (and the reference docs it points to) into a single
    self-contained ZIP for transfer to lab machines or a USB drive.

.DESCRIPTION
    Lab-Kit/ is the canonical home for the lab build/operate scripts, so this
    script no longer "assembles" the kit — it just packages it. To keep a USB
    copy self-contained, it also snapshots the current Architecture docs into a
    Reference-Snapshot/ folder inside the archive (the repo itself keeps those
    docs in one canonical place under Architecture/).

    Output: CAC-Lab-Kit-<yyyyMMdd>.zip in the chosen destination.

.PARAMETER OutputPath
    Folder to write the ZIP into. Default: the repo root.

.PARAMETER IncludeTools
    Also include the Tools-Kit scripts in the package (the tool *downloaders*,
    not the downloaded tools themselves).

.EXAMPLE
    .\Package-LabKit.ps1

.EXAMPLE
    .\Package-LabKit.ps1 -OutputPath E:\ -IncludeTools

.NOTES
    Author : Glenn Byron
    Run on : any machine with the repo cloned. Produces a portable archive;
             it does not modify the repo.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$OutputPath = ".",
    [switch]$IncludeTools
)

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp    = Get-Date -Format "yyyyMMdd"
$staging  = Join-Path $env:TEMP "CAC-Lab-Kit-$stamp"
$zipName  = "CAC-Lab-Kit-$stamp.zip"
$zipPath  = Join-Path $OutputPath $zipName

Write-Host "Packaging Lab-Kit..." -ForegroundColor Cyan

# Fresh staging area
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
if ($PSCmdlet.ShouldProcess($staging, "Create staging area")) {
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
}

# 1. Copy the canonical Lab-Kit
Copy-Item (Join-Path $repoRoot "Lab-Kit") (Join-Path $staging "Lab-Kit") -Recurse -Force

# 2. Snapshot the reference docs so the USB copy is self-contained
$refSnap = Join-Path $staging "Lab-Kit\Reference-Snapshot"
New-Item -ItemType Directory -Path $refSnap -Force | Out-Null
Copy-Item (Join-Path $repoRoot "Architecture\*.md") $refSnap -Force
$rmf = Join-Path $refSnap "RMF-Templates"
New-Item -ItemType Directory -Path $rmf -Force | Out-Null
Copy-Item (Join-Path $repoRoot "Architecture\RMF-Templates\*.md") $rmf -Force

# 3. Optionally include the Tools-Kit downloaders
if ($IncludeTools) {
    Copy-Item (Join-Path $repoRoot "Tools-Kit") (Join-Path $staging "Tools-Kit") -Recurse -Force
    Write-Host "  + Tools-Kit included." -ForegroundColor Gray
}

# 4. Zip it
if ($PSCmdlet.ShouldProcess($zipPath, "Create ZIP archive")) {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
    Write-Host "  -> Created $zipPath" -ForegroundColor Green
}

# 5. Clean up staging
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Copy $zipName to a USB drive and unzip it on the lab machine." -ForegroundColor Cyan
Write-Host "Reminder: run .\Scrub-Repo.ps1 -WhatIf before pushing the repo itself." -ForegroundColor Cyan
