# ==============================================================================
# GPO BLUEPRINT: SMART CARD INTERACTIVE LOGON & HARDENING POLICIES
# Target Framework: NIST SP 800-53 Rev. 5 (AC-11, IA-2)
# ==============================================================================

Import-Module GroupPolicy

$GPO_Name = "SEC-MFA-SmartCard-Enforcement"
Write-Host "Creating secure federal compliance GPO: $GPO_Name..." -ForegroundColor Cyan

# 1. Initialize the baseline Group Policy Object
if (-not (Get-GPO -Name $GPO_Name -ErrorAction SilentlyContinue)) {
    New-GPO -Name $GPO_Name -Comment "Enforces hardware-backed multi-factor authentication and terminal session locks."
}

# 2. Configure Windows Interactive Logon settings to mandate Smart Cards
# This directly fulfills NIST IA-2(11) controls
Set-GPRegistryValue -Name $GPO_Name `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption" `
    -Type DWord `
    -Value 1

# 3. Configure Lock on Removal behavior (The "CAC Pull" action)
# This directly fulfills NIST AC-11 controls
Set-GPRegistryValue -Name $GPO_Name `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "ScRemoveOption" `
    -Type DWord `
    -Value 1  # 1 = Lock Workstation, 2 = Force Logoff

# 4. Enforce terminal idle timeouts (Max 15 minutes for secure spaces)
Set-GPRegistryValue -Name $GPO_Name `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "InactivityTimeoutSecs" `
    -Type DWord `
    -Value 900

Write-Host "🎉 GPO Blueprint successfully generated. Ready for organizational deployment." -ForegroundColor Green
