#Requires -Version 5.1
<#
.SYNOPSIS
    Copy enrollment scripts to Lab-DC01 for local execution.

.DESCRIPTION
    Copies New-LabUser.ps1 and New-TokenEnrollment.ps1 to a target folder on
    Lab-DC01 via the admin share (\\Lab-DC01\C$). Run this from your management
    machine, then RDP into Lab-DC01 and execute the scripts there.

.PARAMETER DC
    NetBIOS name or FQDN of the domain controller. Default: Lab-DC01

.PARAMETER DestinationFolder
    Folder on the DC to copy scripts into. Default: C:\LabScripts\Enrollment

.PARAMETER Credential
    Alternate credentials for the UNC connection. Prompts if not supplied and
    the current user does not have admin access to the DC.

.EXAMPLE
    .\Deploy-ScriptsToDC.ps1

.EXAMPLE
    .\Deploy-ScriptsToDC.ps1 -DC Lab-DC01 -Credential (Get-Credential)

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    After copying, RDP into Lab-DC01 and run:
        cd C:\LabScripts\Enrollment
        .\New-LabUser.ps1 -FirstName Jane -LastName Doe -Domain lab.local
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DC                 = "Lab-DC01",
    [string]$DestinationFolder  = "C:\LabScripts\Enrollment",
    [System.Management.Automation.PSCredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$width = 72
Write-Host ""
Write-Host ("=" * $width) -ForegroundColor DarkCyan
Write-Host "  DEPLOY ENROLLMENT SCRIPTS TO DC" -ForegroundColor Cyan
Write-Host "  Target: $DC  ->  $DestinationFolder" -ForegroundColor Cyan
Write-Host ("=" * $width) -ForegroundColor DarkCyan
Write-Host ""

# Scripts to copy (relative to this script's directory)
$scripts = @(
    "New-LabUser.ps1",
    "New-TokenEnrollment.ps1"
)

$sourceDir = $PSScriptRoot
foreach ($s in $scripts) {
    $src = Join-Path $sourceDir $s
    if (-not (Test-Path $src)) {
        Write-Host "  [FAIL] Source not found: $src" -ForegroundColor Red
        exit 1
    }
}

# Build UNC path to destination
$destRelative  = $DestinationFolder.Replace(":", "$")   # C:\Foo -> C$\Foo
$uncDest       = "\\$DC\$destRelative"

Write-Host "  [*] Connecting to $uncDest ..." -ForegroundColor White

# Map a temporary PSDrive so we can mkdir and copy cleanly
$driveParams = @{
    Name       = "DCDeploy"
    PSProvider = "FileSystem"
    Root       = "\\$DC\$(($DestinationFolder.Substring(0,1)) + '$')"   # \\DC\C$
    ErrorAction = 'Stop'
}
if ($Credential) { $driveParams['Credential'] = $Credential }

try {
    $null = New-PSDrive @driveParams
} catch {
    Write-Host ""
    Write-Host "  [!!] Could not connect to \\$DC\$($driveParams.Root.Split('\')[-1])" -ForegroundColor Yellow
    Write-Host "       $_" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Try again with explicit credentials:" -ForegroundColor White
    Write-Host "  .\Deploy-ScriptsToDC.ps1 -Credential (Get-Credential)" -ForegroundColor Cyan
    exit 1
}

try {
    # Recreate destination path under the mapped drive
    $driveDestFolder = $uncDest

    if (-not (Test-Path $driveDestFolder)) {
        Write-Host "  [*] Creating destination folder $DestinationFolder on $DC ..." -ForegroundColor White
        if ($PSCmdlet.ShouldProcess($driveDestFolder, "Create directory")) {
            New-Item -ItemType Directory -Path $driveDestFolder -Force | Out-Null
        }
        Write-Host "  [OK] Folder created." -ForegroundColor Green
    } else {
        Write-Host "  [OK] Destination folder exists." -ForegroundColor Green
    }

    foreach ($s in $scripts) {
        $src  = Join-Path $sourceDir $s
        $dest = Join-Path $driveDestFolder $s
        Write-Host "  [*] Copying $s ..." -ForegroundColor White
        if ($PSCmdlet.ShouldProcess($dest, "Copy file")) {
            Copy-Item -Path $src -Destination $dest -Force
        }
        Write-Host "  [OK] $s -> $DestinationFolder" -ForegroundColor Green
    }
} finally {
    Remove-PSDrive -Name "DCDeploy" -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("=" * $width) -ForegroundColor Green
Write-Host "  DEPLOY COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "  RDP into $DC and open PowerShell as Administrator:" -ForegroundColor White
Write-Host ""
Write-Host "    cd $DestinationFolder" -ForegroundColor Cyan
Write-Host "    .\New-LabUser.ps1 -FirstName Jane -LastName Doe -Domain lab.local" -ForegroundColor Cyan
Write-Host ""
Write-Host "  After RA phase, a DIFFERENT admin runs:" -ForegroundColor White
Write-Host "    .\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName <UPN>" -ForegroundColor Cyan
Write-Host ("=" * $width) -ForegroundColor Green
Write-Host ""
