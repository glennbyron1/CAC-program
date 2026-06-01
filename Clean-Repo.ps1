#Requires -Version 5.1
# Run once from C:\Users\labuser\Documents\GitHub\CAC-program
# Removes sensitive files, cleans up duplicates, stages everything for commit.
# Delete this script after running.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host ""
Write-Host "  Repo Cleanup" -ForegroundColor Cyan
Write-Host ""

# ---- Remove sensitive Dispatch files from git tracking ----
Write-Host "  [1] Removing sensitive files from git..." -ForegroundColor Yellow
$remove = @(
    "Dispatch\Agency-ZeroTrust-GapAnalysis.md",
    "Dispatch\Agency-ZeroTrust-GapAnalysis.docx",
    "Dispatch\ESDP-Hiring-Action-Plan.docx",
    "Dispatch\DISPATCH-LOG.md",
    "Dispatch\CONTRIBUTING.md",
    "Dispatch\FAQ.md",
    "Dispatch\LICENSE",
    "Dispatch\README-DoD-draft.md",
    "Dispatch\README-public-draft.md",
    "Dispatch\SECURITY.md"
)
foreach ($f in $remove) {
    if (Test-Path $f) {
        git rm -f $f 2>$null
        Write-Host "      removed: $f" -ForegroundColor Gray
    }
}

# ---- Remove duplicate/wrong-repo folders ----
Write-Host "  [2] Removing duplicate and wrong-repo content..." -ForegroundColor Yellow
$removeDirs = @(
    "Zero-Trust",
    "Study"
)
foreach ($d in $removeDirs) {
    if (Test-Path $d) {
        git rm -rf $d 2>$null
        Write-Host "      removed: $d\" -ForegroundColor Gray
    }
}

# ---- Remove duplicate files ----
$removeSingle = @(
    "Package-LabKit.ps1",
    "Lab-Kit\Phase-8-Zero-Trust-Extension.md"
)
foreach ($f in $removeSingle) {
    if (Test-Path $f) {
        git rm -f $f 2>$null
        Write-Host "      removed: $f" -ForegroundColor Gray
    }
}

# ---- Stage the new good content (already written by Claude) ----
Write-Host "  [3] Staging new root-level files..." -ForegroundColor Yellow
$stage = @(
    "FAQ.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "README-DoD-draft.md",
    "README-public-draft.md"
)
foreach ($f in $stage) {
    if (Test-Path $f) {
        git add $f
        Write-Host "      staged: $f" -ForegroundColor Gray
    }
}

# ---- Stage everything else that changed ----
git add -A

Write-Host ""
Write-Host "  [4] Status:" -ForegroundColor Cyan
git status --short

Write-Host ""
Write-Host "  Ready to commit. Run:" -ForegroundColor Green
Write-Host "    git commit -m ""Repo cleanup: remove sensitive Dispatch files, fix duplicates, add FAQ/CONTRIBUTING""" -ForegroundColor Gray
Write-Host "  Then push via GitHub Desktop (force push needed for history rewrite)." -ForegroundColor Gray
Write-Host ""
Write-Host "  After committing, run .\Purge-History.ps1 to scrub the sensitive files from git history." -ForegroundColor Yellow
Write-Host ""
