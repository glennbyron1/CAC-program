<#
.SYNOPSIS
    Repository sanitization tool. Replaces real organizational identifiers
    with safe placeholders before pushing to a public GitHub repository.

.DESCRIPTION
    Loads find-and-replace patterns from .scrub-patterns.local.json (which is
    gitignored and never committed). Walks all files matching the configured
    extensions and replaces every occurrence of each pattern in-place.

    Run with -WhatIf to preview replacements without modifying any file.

.PARAMETER WhatIf
    Dry-run mode. Reports every match found and what would be replaced, but
    does not write any changes. Use this before every real run to confirm
    the scrub list is correct.

.PARAMETER PatternFile
    Path to the patterns JSON file. Defaults to .scrub-patterns.local.json
    in the current directory.

.PARAMETER Root
    Repository root to scan. Defaults to the current directory.

.EXAMPLE
    # Preview what would change
    .\Scrub-Repo.ps1 -WhatIf

.EXAMPLE
    # Apply replacements
    .\Scrub-Repo.ps1

.EXAMPLE
    # Use a different patterns file
    .\Scrub-Repo.ps1 -PatternFile .\my-patterns.json

.NOTES
    Why the patterns are loaded from an external file:
      The script itself ships to GitHub, so embedding real values in this
      file would defeat the purpose of scrubbing - anyone reading the
      committed script could read the keys and recover what was scrubbed.
      Real values live in .scrub-patterns.local.json, which is gitignored
      and stays on the local machine. A safe-to-commit template lives at
      .scrub-patterns.example.json.

    The script also explicitly walks the .idea/ folder when present, since
    IntelliJ/Rider workspace files often hold user-specific paths,
    usernames, and account ids that need to be scrubbed before push.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$PatternFile = ".scrub-patterns.local.json",
    [string]$Root        = "."
)

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
$FileExtensions = @(
    "*.ps1", "*.psm1", "*.psd1",
    "*.txt", "*.md",
    "*.inf", "*.ini",
    "*.xml", "*.json", "*.yaml", "*.yml",
    "*.html", "*.css"
)

# Files to skip entirely (in addition to the script itself)
$ExcludeNames = @(
    "Scrub-Repo.ps1",
    ".scrub-patterns.local.json"
)

# ------------------------------------------------------------------
# Load patterns
# ------------------------------------------------------------------
if (-not (Test-Path $PatternFile)) {
    Write-Host ""
    Write-Host "ERROR: Pattern file not found at $PatternFile" -ForegroundColor Red
    Write-Host ""
    Write-Host "Create one by copying the template:" -ForegroundColor Yellow
    Write-Host "  Copy-Item .scrub-patterns.example.json .scrub-patterns.local.json" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Then edit .scrub-patterns.local.json with your real organizational" -ForegroundColor Yellow
    Write-Host "identifiers. The .local.json file is gitignored and will not be" -ForegroundColor Yellow
    Write-Host "committed; the .example.json template is safe to share." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

try {
    $loaded = Get-Content -Path $PatternFile -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to parse $PatternFile as JSON." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Convert from PSCustomObject (ConvertFrom-Json default) to a hashtable
# so we can iterate keys reliably across PowerShell 5.1 and 7+.
$PatternMap = [ordered]@{}
foreach ($prop in $loaded.PSObject.Properties) {
    $PatternMap[$prop.Name] = $prop.Value
}

if ($PatternMap.Count -eq 0) {
    Write-Host "WARNING: $PatternFile contained no patterns." -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------
$mode = if ($WhatIfPreference) { "DRY-RUN (no files will be modified)" } else { "LIVE (files will be modified)" }
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Repository Scrubbing Cycle - $mode" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Pattern file : $PatternFile" -ForegroundColor Gray
Write-Host " Patterns     : $($PatternMap.Count)" -ForegroundColor Gray
Write-Host " Root         : $Root" -ForegroundColor Gray
Write-Host " Extensions   : $($FileExtensions -join ', ')" -ForegroundColor Gray
Write-Host ""

# ------------------------------------------------------------------
# Scan
# ------------------------------------------------------------------
$totalMatches = 0
$filesTouched = 0

# Walk everything matching our extensions, then drop files that are inside
# .git/ or that are explicitly on the exclude list. -Force lets us see
# dotfiles and files inside dotted folders (.idea, .vscode, etc.).
$files = Get-ChildItem -Path $Root -Recurse -File -Include $FileExtensions -Force `
    | Where-Object {
        $ExcludeNames -notcontains $_.Name `
        -and $_.FullName -notmatch '[\\/]\.git[\\/]'
    }

foreach ($file in $files) {
    $relativePath = Resolve-Path -Relative $file.FullName
    $original     = Get-Content -Path $file.FullName -Raw
    if ($null -eq $original) { continue }

    $updated     = $original
    $fileMatches = 0

    foreach ($target in $PatternMap.Keys) {
        $replacement = $PatternMap[$target]
        $escaped     = [regex]::Escape($target)
        $hits        = ([regex]::Matches($updated, $escaped)).Count

        if ($hits -gt 0) {
            $fileMatches  += $hits
            $totalMatches += $hits
            Write-Host ("  match  [{0}] x{1}  in  {2}" -f $target, $hits, $relativePath) -ForegroundColor Yellow
            $updated = $updated -replace $escaped, $replacement
        }
    }

    if ($fileMatches -gt 0 -and $updated -ne $original) {
        if ($PSCmdlet.ShouldProcess($file.FullName, "Write scrubbed content ($fileMatches replacement(s))")) {
            Set-Content -Path $file.FullName -Value $updated -NoNewline
            $filesTouched++
            Write-Host ("  wrote  {0}  ({1} replacement(s))" -f $relativePath, $fileMatches) -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Files scanned   : $($files.Count)"
Write-Host " Matches found   : $totalMatches"
if ($WhatIfPreference) {
    Write-Host ""
    Write-Host " NOTE: -WhatIf was set. No files were modified." -ForegroundColor Yellow
    Write-Host " Re-run WITHOUT -WhatIf to apply changes." -ForegroundColor Yellow
} else {
    Write-Host " Files modified  : $filesTouched"
    if ($filesTouched -gt 0) {
        Write-Host ""
        Write-Host " Review changes with:  git diff" -ForegroundColor Cyan
        Write-Host " Stage when correct:   git add ." -ForegroundColor Cyan
    }
}
Write-Host ""
