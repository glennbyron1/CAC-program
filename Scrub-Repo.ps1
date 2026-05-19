# ==============================================================================
# REPOSITORY SANITIZATION & SCRUBBING TOOL
# Run this script BEFORE pushing code to public GitHub repositories.
# ==============================================================================

# 1. Define your sensitive production strings to find
$SearchPatterns = @{
    "Agency"          = "AgencyName"
    "agency.gov"      = "agency.gov"
    "10.0."          = "10.0."               # Protects internal subnet patterns
    "P@ssw0rd123!"    = "REPLACED_SAFE_PASSWORD_PLACEHOLDER"
    "glennbyron"      = "labuser_admin"        # Sanitizes your personal username
    "Byron"           = "Candidate"
    "hotmail.com"     = "example.com"
}

# 2. Target your script and document extensions
$FileExtensions = @("*.ps1", "*.txt", "*.md", "*.inf", "*.xml", "*.ini")

Write-Host "🔍 Starting repository scrubbing cycle..." -ForegroundColor Cyan

# 3. Loop through all directories recursively
Get-ChildItem -Path . -Recurse -Include $FileExtensions | ForEach-Object {
    $FilePath = $_.FullName

    # Skip this sanitization tool itself so it doesn't break its own logic
    if ($_.Name -eq "Scrub-Repo.ps1") { return }

    $FileContent = Get-Content -Path $FilePath -Raw
    $Modified = $false

    # Scan and replace matches based on the dictionary dictionary
    foreach ($Target in $SearchPatterns.Keys) {
        if ($FileContent -match [regex]::Escape($Target)) {
            Write-Host "⚠️  Found sensitive match [$Target] in file: $($_.Name)" -ForegroundColor Yellow
            $FileContent = $FileContent -replace [regex]::Escape($Target), $SearchPatterns[$Target]
            $Modified = $true
        }
    }

    # Save changes only if a replacement occurred
    if ($Modified) {
        Set-Content -Path $FilePath -Value $FileContent -NoNewline
        Write-Host "✅ Secured file: $($_.Name)" -ForegroundColor Green
    }
}

Write-Host "🎉 Scrubbing routine complete. Review changes with 'git diff' before staging." -ForegroundColor Cyan
