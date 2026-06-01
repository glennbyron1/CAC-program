#Requires -Version 5.1
# Run AFTER Clean-Repo.ps1 and committing.
# Rewrites git history to remove sensitive files from all past commits.
# Then force-pushes to GitHub. Delete this script after running.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host ""
Write-Host "  Git History Purge" -ForegroundColor Cyan
Write-Host "  Removing sensitive files from all past commits..." -ForegroundColor Gray
Write-Host ""

# Files to purge from history
$filesToPurge = @(
    "Dispatch/Agency-ZeroTrust-GapAnalysis.md",
    "Dispatch/Agency-ZeroTrust-GapAnalysis.docx",
    "Dispatch/ESDP-Hiring-Action-Plan.docx",
    "Dispatch/DISPATCH-LOG.md"
)

# Check for stale lock
$lock = ".git\index.lock"
if (Test-Path $lock) {
    Remove-Item $lock -Force
    Write-Host "  Removed stale index.lock" -ForegroundColor Yellow
}

$env:FILTER_BRANCH_SQUELCH_WARNING = "1"

foreach ($file in $filesToPurge) {
    Write-Host "  Purging: $file" -ForegroundColor Yellow
    $escaped = $file -replace '/', '\/'
    git filter-branch --force --index-filter `
        "git rm --cached --ignore-unmatch `"$file`"" `
        --prune-empty --tag-name-filter cat -- --all 2>&1 | Out-Null
    Write-Host "      Done." -ForegroundColor Green
}

# Clean up backup refs
Write-Host "  Cleaning up backup refs..." -ForegroundColor Cyan
git for-each-ref --format="%(refname)" refs/original/ |
    ForEach-Object { git update-ref -d $_ }
git reflog expire --expire=now --all
git gc --prune=now --quiet

Write-Host ""
Write-Host "  Verifying — checking if sensitive files still appear in history..." -ForegroundColor Cyan
$found = git log --all --full-history -- "Dispatch/Agency*" "Dispatch/ESDP*" 2>&1
if ($found) {
    Write-Host "  WARNING: Files may still appear in some refs. Check manually." -ForegroundColor Red
} else {
    Write-Host "  Clean — sensitive files purged from history." -ForegroundColor Green
}

Write-Host ""
Write-Host "  [!] Ready to force-push. Press Enter to continue or Ctrl+C to abort." -ForegroundColor Yellow
Read-Host "  Continue?"

git push origin main --force

Write-Host ""
Write-Host "  Done. Delete this script and Clean-Repo.ps1:" -ForegroundColor Green
Write-Host "    Remove-Item .\Purge-History.ps1, .\Clean-Repo.ps1" -ForegroundColor Gray
Write-Host "    git add -A" -ForegroundColor Gray
Write-Host "    git commit -m ""Remove cleanup scripts""" -ForegroundColor Gray
Write-Host "    git push" -ForegroundColor Gray
Write-Host ""
