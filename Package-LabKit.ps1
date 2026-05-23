# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Packages a fully self-contained Lab-Kit ZIP for transfer to lab machines
    or a USB drive. The archive depends on nothing from the rest of the repo.

.DESCRIPTION
    Builds a ZIP that mirrors the repo layout for ONLY the folders the kit
    actually references, so every relative link inside the Lab-Kit files
    (../../Architecture/..., ..\..\Tools-Kit\..., .\Compliance-Reports\...)
    resolves correctly once unzipped — with no edits to the kit scripts.

    The archive contains:
      Lab-Kit/             the build/operate scripts (the *.iso is excluded)
      Tools-Kit/           the tool downloaders
      Architecture/        the reference docs + RMF-Templates the kit links to
      Compliance-Reports/  an empty Before-MFA / After-MFA skeleton
      LICENSE              MIT license
      README.md            package orientation

    Output: CAC-Lab-Kit-<yyyyMMdd>.zip in the chosen destination.

.PARAMETER OutputPath
    Folder to write the ZIP into. Default: the repo root.

.PARAMETER IncludeISO
    Also include the Server 2025 ISO from Lab-Kit (off by default — the ISO is
    ~6 GB, so it is normally copied to the USB separately).

.EXAMPLE
    .\Package-LabKit.ps1

.EXAMPLE
    .\Package-LabKit.ps1 -OutputPath E:\

.NOTES
    Author : Glenn Byron
    Run on : any machine with the repo cloned. Produces a portable archive;
             it does not modify the repo.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$OutputPath = ".",
    [switch]$IncludeISO
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp    = Get-Date -Format "yyyyMMdd"
$staging  = Join-Path $env:TEMP "CAC-Lab-Kit-$stamp"
$zipName  = "CAC-Lab-Kit-$stamp.zip"
$zipPath  = Join-Path $OutputPath $zipName

Write-Host "Packaging a self-contained Lab-Kit..." -ForegroundColor Cyan

# Fresh staging area
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
if ($PSCmdlet.ShouldProcess($staging, "Create staging area")) {
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
}

# 1. Lab-Kit. Use robocopy so the multi-GB ISO can be skipped during the copy
#    (avoids copying 6 GB just to delete it). robocopy exit codes 0-7 are success.
$labSrc = Join-Path $repoRoot "Lab-Kit"
$labDst = Join-Path $staging  "Lab-Kit"
$rcArgs = @($labSrc, $labDst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
if (-not $IncludeISO) {
    $rcArgs += @("/XF", "*.iso")
    Write-Host "  ISO excluded (copy it to the USB separately)." -ForegroundColor Gray
}
robocopy @rcArgs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed copying Lab-Kit (exit $LASTEXITCODE)." }
$global:LASTEXITCODE = 0

# 2. Architecture docs + RMF templates — so the kit's ../../Architecture links resolve
$arch = Join-Path $staging "Architecture"
New-Item -ItemType Directory -Path $arch -Force | Out-Null
Copy-Item (Join-Path $repoRoot "Architecture\*.md") $arch -Force
$rmf = Join-Path $arch "RMF-Templates"
New-Item -ItemType Directory -Path $rmf -Force | Out-Null
Copy-Item (Join-Path $repoRoot "Architecture\RMF-Templates\*.md") $rmf -Force

# 3. Tools-Kit downloaders — so the kit's ..\..\Tools-Kit references resolve
Copy-Item (Join-Path $repoRoot "Tools-Kit") (Join-Path $staging "Tools-Kit") -Recurse -Force

# 4. Compliance-Reports skeleton — so Stage-Reports.ps1 has somewhere to write
$cr = Join-Path $staging "Compliance-Reports"
New-Item -ItemType Directory -Path (Join-Path $cr "Before-MFA") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $cr "After-MFA")  -Force | Out-Null
if (Test-Path (Join-Path $repoRoot "Compliance-Reports\README.md")) {
    Copy-Item (Join-Path $repoRoot "Compliance-Reports\README.md") $cr -Force
}

# 5. LICENSE + a short package README
if (Test-Path (Join-Path $repoRoot "LICENSE")) {
    Copy-Item (Join-Path $repoRoot "LICENSE") $staging -Force
}
$pkgReadme = @"
# CAC Lab Kit — Self-Contained Package

Packaged $(Get-Date -Format 'yyyy-MM-dd'). This archive is standalone — it does
not need the rest of the CAC-program repository.

Start here: ``Lab-Kit/START-HERE.md``

Contents:
- ``Lab-Kit/``            build and operate scripts (run these on the lab machines)
- ``Tools-Kit/``          downloaders for the free DoD/federal tools
- ``Architecture/``       reference docs the kit links to (PKI, STIG, VPN, RMF templates)
- ``Compliance-Reports/`` drop SCAP/Nessus before/after output here

Note: the Windows Server 2025 ISO is NOT included (it is multi-GB). Copy it to
your USB drive separately; ``Lab-Kit/01-HyperV-Host/New-LabVMs.ps1`` takes an
``-ISOPath`` parameter.

Author: Glenn Byron - MIT License (see LICENSE).
"@
Set-Content -Path (Join-Path $staging "README.md") -Value $pkgReadme -Encoding UTF8

# 6. Zip it
if ($PSCmdlet.ShouldProcess($zipPath, "Create ZIP archive")) {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "  -> Created $zipPath ($sizeMB MB)" -ForegroundColor Green
}

# 7. Clean up staging
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. The ZIP is self-contained - unzip it on the lab machine and" -ForegroundColor Cyan
Write-Host "open Lab-Kit/START-HERE.md. Copy the Server 2025 ISO over separately." -ForegroundColor Cyan
