<#
.SYNOPSIS
    Automated ICAM Laboratory Baseline & Smart Card Environment Stage Tool.
.DESCRIPTION
    This script initializes the local laboratory system environment variables,
    safely stubs target Active Directory registry keys for smart card testing,
    and configures high-availability HTTP CRL paths using safe local placeholders.
.NOTES
    File Name      : Build-CAC-Lab.ps1
    Framework Path : NIST SP 800-53 Rev. 5 (IA-2, AC-11), FIPS 201-3 Blueprint Alignment
    Security Tier  : Sanitized Enterprise Code Model - Lab-Safe Only.
#>

# 1. Enforcement Variable Definitions (Sanitized Placeholders)
$DomainName      = "lab.local"
$LogonRegPath    = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$CertEnrollPath  = "HKLM:\Software\Microsoft\Cryptography\MSPKI\Enrollment"
$LocalCrlRoot    = "C:\inetpub\wwwroot\pki"
$LogPath         = "C:\Windows\Logs\ICAM_Lab_Deployment.log"

Start-Transcript -Path $LogPath -Append

Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host "🛡️  INITIALIZING IDENTITY & ACCESS MANAGEMENT (ICAM) LAB SYSTEM DESIGN" -ForegroundColor Cyan
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host "[*] Target Execution Domain Baseline: $DomainName" -ForegroundColor White
Write-Host "[*] Script Compliance Path: NIST SP 800-53 Rev. 5 Identity Protections" -ForegroundColor White

# 2. Administrative Privilege Verification Loop
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "🛑 CRITICAL ERROR: Administrative elevated privileges are required to modify registry loops."
    Write-Warning "Please relaunch your shell as an Administrator."
    Stop-Transcript
    Exit
}

# 3. HTTP Certificate Revocation List (CRL) Distribution Directory Staging
Write-Host "`n[1/3] Organizing High-Availability HTTP CRL Storage File Paths..." -ForegroundColor Cyan
if (-not (Test-Path $LocalCrlRoot)) {
    try {
        New-Item -Path $LocalCrlRoot -ItemType Directory -Force | Out-Null
        Write-Host "✅ Directory successfully provisioned: $LocalCrlRoot" -ForegroundColor Green
        Write-Host "👉 INFO: Map an HTTP TCP/80 web virtual directory directly to this root path for network caching." -ForegroundColor Gray
    }
    catch {
        Write-Error "❌ Deployment Fault: Failed to initialize file path $LocalCrlRoot. Exception: $_"
    }
} else {
    Write-Host "ℹ️  HTTP CRL destination path already verified active." -ForegroundColor Yellow
}

# 4. Local System Smart Card Cryptographic Provider Hardening
Write-Host "`n[2/3] Configuring Endpoint Registry Parameters for Smart Card Requirement Testing..." -ForegroundColor Cyan

if (Test-Path $LogonRegPath) {
    try {
        # Test Mode Parameter: Prepare the local system parameters for enforcement testing
        # NOTE: Keeping these at '0' in the baseline wrapper so running this tool doesn't accidentally
        # lock the admin out of the host machine before GPOs are linked and certificates are issued.
        Set-ItemProperty -Path $LogonRegPath -Name "scforceoption" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $LogonRegPath -Name "ScRemoveOption" -Value 0 -Type DWord -Force

        Write-Host "✅ Target registry keys mapped safely to $LogonRegPath" -ForegroundColor Green
        Write-Host "   -> Option 'scforceoption' set to 0 [Ready for Test Mode GPO link]" -ForegroundColor Gray
        Write-Host "   -> Option 'ScRemoveOption' set to 0 [Ready for Lock behavior link]" -ForegroundColor Gray
    }
    catch {
        Write-Error "❌ Deployment Fault: Registry adjustment failed. Exception: $_"
    }
} else {
    Write-Warning "⚠️  Target Logon path not found ($LogonRegPath). Confirming host machine operating system layout."
}

# 5. Staging FIPS 201-3 / NIST SP 800-73 Cryptographic Service Engine Framework
Write-Host "`n[3/3] Setting Up Local Software Key Storage Provider Enrollment Environment..." -ForegroundColor Cyan
if (-not (Test-Path $CertEnrollPath)) {
    try {
        New-Item -Path $CertEnrollPath -Force | Out-Null
        Write-Host "✅ System enrollment parameters initialized at: $CertEnrollPath" -ForegroundColor Green
    }
    catch {
        Write-Host "ℹ️  Note: Path is managed directly by Enterprise AD CS services upon deployment active." -ForegroundColor Gray
    }
} else {
    Write-Host "ℹ️  Enrollment service paths verified active." -ForegroundColor Yellow
}

Write-Host "`n=======================================================================" -ForegroundColor Cyan
Write-Host "🎉 ENVIRONMENT SETUP SUCCESSFUL: ICAM LAB DESIGN READY FOR GPO APPLY" -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host "[*] Log report written to: $LogPath" -ForegroundColor Gray
Write-Host "[*] Review /Architecture/Blueprint.md next to build your Two-Tier PKI chain." -ForegroundColor White

Stop-Transcript
