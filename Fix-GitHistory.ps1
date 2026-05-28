#Requires -Version 5.1
# Run once from C:\Users\labuser\Documents\GitHub\CAC-program
# After success: delete this file, commit the deletion.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OldEmail = "NNNNNN+glennbyron1@users.noreply.github.com"
$NewEmail = "286100841+glennbyron1@users.noreply.github.com"
$NewName  = "glennbyron1"

Set-Location $PSScriptRoot

Write-Host ""
Write-Host "  Git History Scrub" -ForegroundColor Cyan
Write-Host "  Replacing: $OldEmail" -ForegroundColor Gray
Write-Host "  With:      $NewEmail" -ForegroundColor Gray
Write-Host ""

# ---- 1. Remove stale lock ------------------------------------------------
$lock = Join-Path $PSScriptRoot ".git\index.lock"
if (Test-Path $lock) {
    Write-Host "  [1] Removing stale index.lock..." -ForegroundColor Yellow
    Remove-Item $lock -Force
    Write-Host "      OK" -ForegroundColor Green
} else {
    Write-Host "  [1] No lock file -- OK" -ForegroundColor Green
}

# ---- 2. Set noreply email for future commits -----------------------------
Write-Host "  [2] Configuring git user.email..." -ForegroundColor Cyan
git config user.email $NewEmail
git config user.name  $NewName
Write-Host "      Set to: $NewEmail" -ForegroundColor Green

# ---- 3. Commit pending changes -------------------------------------------
Write-Host "  [3] Checking for pending changes..." -ForegroundColor Cyan
$dirty = git status --porcelain 2>&1
if ($dirty) {
    Write-Host "      Staging all changes..." -ForegroundColor Yellow
    git add -A
    git commit -m "Add Before-MFA scan results and lab doc updates"
    Write-Host "      Committed." -ForegroundColor Green
} else {
    Write-Host "      Nothing to commit." -ForegroundColor Green
}

# ---- 4. Rewrite history --------------------------------------------------
Write-Host "  [4] Checking history for old email..." -ForegroundColor Cyan
$found = @(git log --all --format="%ae" 2>&1 | Where-Object { $_ -eq $OldEmail })

if ($found.Count -eq 0) {
    Write-Host "      Already clean -- no old email in history." -ForegroundColor Green
} else {
    Write-Host "      Found in $($found.Count) commit(s). Rewriting history..." -ForegroundColor Yellow

    # Write the POSIX sh filter to a temp file to avoid PowerShell escaping issues
    $tmpSh = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "git-email-filter.sh")

    $lines = @(
        'OLD_EMAIL="NNNNNN+glennbyron1@users.noreply.github.com"',
        'NEW_EMAIL="286100841+glennbyron1@users.noreply.github.com"',
        'NEW_NAME="glennbyron1"',
        'if [ "$GIT_COMMITTER_EMAIL" = "$OLD_EMAIL" ]; then',
        '    export GIT_COMMITTER_EMAIL="$NEW_EMAIL"',
        '    export GIT_COMMITTER_NAME="$NEW_NAME"',
        'fi',
        'if [ "$GIT_AUTHOR_EMAIL" = "$OLD_EMAIL" ]; then',
        '    export GIT_AUTHOR_EMAIL="$NEW_EMAIL"',
        '    export GIT_AUTHOR_NAME="$NEW_NAME"',
        'fi'
    )
    [System.IO.File]::WriteAllLines($tmpSh, $lines, [System.Text.UTF8Encoding]::new($false))

    $filterScript = [System.IO.File]::ReadAllText($tmpSh)

    $env:FILTER_BRANCH_SQUELCH_WARNING = "1"
    git filter-branch --env-filter $filterScript --tag-name-filter cat -- --branches --tags

    # Clean up backup refs
    git for-each-ref --format="%(refname)" refs/original/ |
        ForEach-Object { git update-ref -d $_ }
    git reflog expire --expire=now --all
    git gc --prune=now --quiet

    Remove-Item $tmpSh -Force -ErrorAction SilentlyContinue
    Write-Host "      Rewrite complete." -ForegroundColor Green
}

# ---- 5. Verify -----------------------------------------------------------
Write-Host "  [5] Verifying..." -ForegroundColor Cyan
$remaining = @(git log --all --format="%ae" 2>&1 | Where-Object { $_ -eq $OldEmail })
if ($remaining.Count -gt 0) {
    Write-Host "  ERROR: Old email still found in $($remaining.Count) commit(s)." -ForegroundColor Red
    Write-Host "  Do NOT push. Investigate before continuing." -ForegroundColor Red
    exit 1
}
Write-Host "      Clean -- old email gone from all commits." -ForegroundColor Green

# ---- 6. Force push -------------------------------------------------------
Write-Host ""
Write-Host "  [6] Ready to force-push to origin/main." -ForegroundColor Yellow
Write-Host "      This overwrites GitHub history. Press Enter to continue or Ctrl+C to abort."
Read-Host "  Continue?"

git push origin main --force
Write-Host ""
Write-Host "  Done. GitHub history is now clean." -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    Remove-Item .\Fix-GitHistory.ps1" -ForegroundColor Gray
Write-Host "    git add -A" -ForegroundColor Gray
Write-Host "    git commit -m 'Remove one-time history scrub script'" -ForegroundColor Gray
Write-Host "    git push" -ForegroundColor Gray
Write-Host "    GitHub Settings -> Emails -> enable both privacy options" -ForegroundColor Gray
Write-Host ""
