# ==============================================================================
# AUTOMATED SCC REPORT ARCHIVAL AND STAGING UTILITY
# Run this script to copy your latest SCC scans into your GitHub portfolio.
# ==============================================================================

# 1. Define source and destination path structures
$SccResultsHome  = "$env:USERPROFILE\SCC\Results"
$RepoBeforeDest  = ".\Compliance-Reports\Before-MFA"
$RepoAfterDest   = ".\Compliance-Reports\After-MFA"

# 2. Grab the most recent scan directory from the default SCC data dump
Write-Host "🔍 Locating your latest SCAP Compliance Checker run outputs..." -ForegroundColor Cyan
$LatestSccFolder = Get-ChildItem -Path $SccResultsHome -Directory |
                   Sort-Object LastWriteTime -Descending |
                   Select-Object -First 1

if (-not $LatestSccFolder) {
    Write-Error "🛑 Failure: No historical SCC scan folders found at $SccResultsHome."
    Exit
}

Write-Host "📂 Active Source Directory Identified: $($LatestSccFolder.FullName)" -ForegroundColor White

# 3. Prompt the user to log the target tracking stage
Write-Host "`nSelect the destination portfolio tier for this report archive:" -ForegroundColor White
Write-Host " [1] Before-MFA (Initial Baseline Snapshot)" -ForegroundColor Yellow
Write-Host " [2] After-MFA  (Post-Hardening Compliant State)" -ForegroundColor Green
$Selection = Read-Host "Enter Choice [1 or 2]"

if ($Selection -eq "1") {
    $TargetDest = $RepoBeforeDest
    $FileLabel  = "Baseline"
} elseif ($Selection -eq "2") {
    $TargetDest = $RepoAfterDest
    $FileLabel  = "Hardened"
} else {
    Write-Warning "❌ Invalid input sequence. Aborting copy utility tracker."
    Exit
}

# 4. Execute file parsing and copy loop
Write-Host "`n🚀 Transferring and staging files to $TargetDest..." -ForegroundColor Cyan

# Locate the primary summary HTML report and raw XML results file
$HtmlReport = Get-ChildItem -Path $LatestSccFolder.FullName -Filter "*_All_Summary.html" | Select-Object -First 1
$XmlResults = Get-ChildItem -Path $LatestSccFolder.FullName -Filter "*_All_XCCDF_Results.xml" | Select-Object -First 1

if ($HtmlReport -and $XmlResults) {
    # Ensure target folder architectures exist
    if (-not (Test-Path $TargetDest)) { New-Item -Path $TargetDest -ItemType Directory | Out-Null }

    # Copy files while cleanly mapping standard names for your GitHub repo
    Copy-Item -Path $HtmlReport.FullName -Destination "$TargetDest\$FileLabel-Report.html" -Force
    Copy-Item -Path $XmlResults.FullName -Destination "$TargetDest\$FileLabel-Results.xml" -Force

    Write-Host "✅ Staged: $FileLabel-Report.html" -ForegroundColor Green
    Write-Host "✅ Staged: $FileLabel-Results.xml" -ForegroundColor Green
    Write-Host "`n🎉 Storage cycle complete. Run 'git status' inside Git Bash to verify tracking." -ForegroundColor Cyan
} else {
    Write-Warning "⚠️  Could not extract standard summary files from the targeted scan directory."
    Write-Warning "Verify you selected the main summary generation options inside the SCC tool configuration."
}
