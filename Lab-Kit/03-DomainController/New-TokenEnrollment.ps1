#Requires -Version 5.1
<#
.SYNOPSIS
    Smart Card / Hardware Token Enrollment — Guided RA/Issuer Separation-of-Duties Workflow

.DESCRIPTION
    Guides two authorized administrators through the token enrollment ceremony, enforcing
    the separation of duties required by NIST SP 800-53 AC-5: the Registration Authority (RA)
    verifies identity, and the Card Issuer performs technical provisioning. One person cannot
    fulfill both roles in the same transaction.

    Workflow:
      1. RA logs in, verifies the enrollee's identity (two forms of ID), records attestation
      2. RA authorizes the enrollment in Active Directory (sets flag on user account)
      3. RA logs off — the session is handed to the Card Issuer
      4. Card Issuer logs in, confirms RA authorization flag is set before proceeding
      5. Card Issuer runs the technical provisioning (certificate request + token issuance)
      6. Enrollee sets PIN — administrator never knows the PIN
      7. Audit record written to log file and Windows Event Log

    Document ID : SCRIPT-ICAM-011
    Framework   : NIST SP 800-53 AC-5, IA-2, IA-2(11), IA-5 | FIPS 201-3 §2.2

.PARAMETER Mode
    RA        — Registration Authority identity verification phase
    Issuer    — Card Issuer technical provisioning phase
    Status    — Show enrollment status for a user account
    AuditLog  — Display the enrollment audit log

.PARAMETER UserPrincipalName
    UPN of the account being enrolled (e.g., jsmith@lab.local)

.PARAMETER LogPath
    Path for the enrollment audit log. Default: C:\Windows\Logs\TokenEnrollment.log

.PARAMETER DomainController
    Domain controller to query/update. Default: auto-detected.

.EXAMPLE
    # Step 1 — RA phase (run as Registration Authority admin)
    .\New-TokenEnrollment.ps1 -Mode RA -UserPrincipalName jsmith@lab.local

    # Step 2 — Issuer phase (run as Card Issuer admin — different person)
    .\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName jsmith@lab.local

    # Check enrollment status
    .\New-TokenEnrollment.ps1 -Mode Status -UserPrincipalName jsmith@lab.local

    # View audit log
    .\New-TokenEnrollment.ps1 -Mode AuditLog

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    SEPARATION OF DUTIES ENFORCEMENT:
    The RA and Issuer MUST be two different Active Directory accounts. The script reads the
    current logged-on user and rejects the Issuer phase if the same account performed the RA phase.
    This is logged to both the local log file and Windows Application Event Log (Source: TokenEnrollment).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('RA','Issuer','Status','AuditLog')]
    [string]$Mode,

    [Parameter()]
    [string]$UserPrincipalName,

    [Parameter()]
    [string]$LogPath = "C:\Windows\Logs\TokenEnrollment.log",

    [Parameter()]
    [string]$DomainController = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# AD attribute used to carry RA authorization flag and RA identity between phases
# Uses the extensionAttribute1 field (available in most AD environments without schema changes)
# Format: "RA-AUTHORIZED|<RA-samAccountName>|<timestamp>"
$RA_ATTR = "extensionAttribute1"
$RA_PREFIX = "RA-AUTHORIZED"

# ---------------------------------------------------------------------------
function Write-Banner {
    $width = 72
    Write-Host ""
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host "  TOKEN ENROLLMENT SYSTEM — $Mode PHASE" -ForegroundColor Cyan
    Write-Host "  SCRIPT-ICAM-011 | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  NIST SP 800-53 AC-5 | Separation of Duties Enforced" -ForegroundColor Cyan
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[*] $Message" -ForegroundColor $Color
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Write-AuditLog {
    param(
        [string]$Event,
        [string]$UPN = "",
        [string]$PerformedBy = "",
        [string]$Details = ""
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $machine   = $env:COMPUTERNAME
    $line = "$timestamp | $Event | UPN: $UPN | By: $PerformedBy | Host: $machine | $Details"

    # Append to log file
    try {
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch {
        Write-Warn "Could not write to log file: $LogPath — $_"
    }

    # Write to Windows Application Event Log
    $source = "TokenEnrollment"
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
        }
        Write-EventLog -LogName Application -Source $source -EventId 4200 -EntryType Information -Message $line
    } catch {
        Write-Warn "Could not write to Windows Event Log — $_"
    }
}

function Get-CurrentUser {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Get-ADUserObject {
    param([string]$UPN)
    try {
        $filter = "UserPrincipalName -eq '$UPN'"
        $props  = @("DisplayName","SamAccountName","UserPrincipalName","DistinguishedName",$RA_ATTR,"SmartcardLogonRequired","LockedOut","Enabled")
        if ($DomainController) {
            $user = Get-ADUser -Filter $filter -Properties $props -Server $DomainController
        } else {
            $user = Get-ADUser -Filter $filter -Properties $props
        }
        if (-not $user) { throw "User '$UPN' not found in Active Directory." }
        return $user
    } catch {
        throw "AD lookup failed for '$UPN': $_"
    }
}

function Confirm-Prompt {
    param([string]$Prompt)
    do {
        $ans = Read-Host "$Prompt [Y/N]"
    } while ($ans -notin @('Y','y','N','n'))
    return ($ans -in @('Y','y'))
}

# ---------------------------------------------------------------------------
# MODULE: RA PHASE
# ---------------------------------------------------------------------------
function Invoke-RAPhase {
    if (-not $UserPrincipalName) {
        throw "UserPrincipalName is required for RA mode."
    }

    $raOperator = Get-CurrentUser

    Write-Host ""
    Write-Host "REGISTRATION AUTHORITY — IDENTITY VERIFICATION" -ForegroundColor Yellow
    Write-Host "Performing identity verification for: $UserPrincipalName" -ForegroundColor White
    Write-Host "RA Operator (this account): $raOperator" -ForegroundColor White
    Write-Host ""
    Write-Host "The enrollee must be physically present. Verify TWO forms of government-issued" -ForegroundColor White
    Write-Host "photo identification before proceeding." -ForegroundColor White
    Write-Host ""

    # --- Identity verification checklist ---
    Write-Host "IDENTITY VERIFICATION CHECKLIST" -ForegroundColor Cyan
    Write-Host "Answer Y to confirm each item. Answer N to abort the enrollment." -ForegroundColor DarkGray
    Write-Host ""

    $checks = @(
        "Enrollee is physically present in front of me",
        "I have examined a valid government-issued PHOTO ID (driver's license, passport, or state ID)",
        "I have examined a SECOND form of identification (employee badge, SSN card, birth certificate, or second photo ID)",
        "The name on both IDs matches the Active Directory account: $UserPrincipalName",
        "I have verified the enrollee's face matches the photo on the ID",
        "The enrollee is authorized by their manager or HR to receive this credential"
    )

    foreach ($check in $checks) {
        if (-not (Confirm-Prompt "  [ ] $check")) {
            Write-Fail "Identity verification failed — enrollment aborted."
            Write-AuditLog -Event "RA-ABORTED" -UPN $UserPrincipalName -PerformedBy $raOperator -Details "RA checklist item failed: $check"
            return
        }
    }

    # --- Collect ID document details for audit record ---
    Write-Host ""
    Write-Host "DOCUMENT RECORD (for audit log)" -ForegroundColor Cyan
    $idType1     = Read-Host "  Primary ID type (e.g., Passport, Driver's License)"
    $idIssuer1   = Read-Host "  Primary ID issuing authority (e.g., Maryland MVA, US State Dept)"
    $idType2     = Read-Host "  Secondary ID type"

    # --- Look up user in AD ---
    Write-Step "Looking up '$UserPrincipalName' in Active Directory..."
    $user = Get-ADUserObject -UPN $UserPrincipalName

    Write-OK "Found: $($user.DisplayName) ($($user.SamAccountName))"
    Write-Host ""

    if (-not $user.Enabled) {
        Write-Fail "Account is DISABLED. Enable the account before enrolling."
        Write-AuditLog -Event "RA-ABORTED" -UPN $UserPrincipalName -PerformedBy $raOperator -Details "Account disabled"
        return
    }

    # --- Check for existing RA flag (prevent double-enrollment without Issuer completing) ---
    if ($user.$RA_ATTR -like "$RA_PREFIX*") {
        Write-Warn "This account already has a pending RA authorization:"
        Write-Host "  $($user.$RA_ATTR)" -ForegroundColor DarkYellow
        Write-Host ""
        if (-not (Confirm-Prompt "Override the existing RA authorization and re-authorize?")) {
            Write-Warn "Enrollment cancelled — existing authorization preserved."
            return
        }
    }

    # --- Set RA authorization flag on the account ---
    $raOperatorSam = ($raOperator -split '\\')[-1]
    $timestamp     = Get-Date -Format "yyyyMMdd-HHmmss"
    $flagValue     = "$RA_PREFIX|$raOperatorSam|$timestamp"

    Write-Step "Setting RA authorization flag on AD account..."
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Set RA authorization flag")) {
        if ($DomainController) {
            Set-ADUser -Identity $user.SamAccountName -Replace @{$RA_ATTR = $flagValue} -Server $DomainController
        } else {
            Set-ADUser -Identity $user.SamAccountName -Replace @{$RA_ATTR = $flagValue}
        }
        Write-OK "Authorization flag set: $flagValue"
    }

    Write-AuditLog -Event "RA-AUTHORIZED" -UPN $UserPrincipalName -PerformedBy $raOperator `
        -Details "ID1: $idType1 ($idIssuer1) | ID2: $idType2"

    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Green
    Write-Host "  RA PHASE COMPLETE" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Enrollee:  $($user.DisplayName)" -ForegroundColor White
    Write-Host "  Account:   $UserPrincipalName" -ForegroundColor White
    Write-Host "  Authorized by: $raOperator" -ForegroundColor White
    Write-Host "  Timestamp: $timestamp" -ForegroundColor White
    Write-Host ""
    Write-Host "  NEXT STEP: Log off this workstation." -ForegroundColor Yellow
    Write-Host "  The Card Issuer (a DIFFERENT person) must now log in and run:" -ForegroundColor Yellow
    Write-Host "  .\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName $UserPrincipalName" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MODULE: CARD ISSUER PHASE
# ---------------------------------------------------------------------------
function Invoke-IssuerPhase {
    if (-not $UserPrincipalName) {
        throw "UserPrincipalName is required for Issuer mode."
    }

    $issuerOperator    = Get-CurrentUser
    $issuerOperatorSam = ($issuerOperator -split '\\')[-1]

    Write-Host ""
    Write-Host "CARD ISSUER — TECHNICAL PROVISIONING" -ForegroundColor Yellow
    Write-Host "Provisioning token for: $UserPrincipalName" -ForegroundColor White
    Write-Host "Issuer (this account): $issuerOperator" -ForegroundColor White
    Write-Host ""

    # --- Verify user in AD and check RA flag ---
    Write-Step "Checking RA authorization in Active Directory..."
    $user = Get-ADUserObject -UPN $UserPrincipalName

    if ($user.$RA_ATTR -notlike "$RA_PREFIX*") {
        Write-Fail "No RA authorization found for '$UserPrincipalName'."
        Write-Fail "The Registration Authority must complete the RA phase first."
        Write-AuditLog -Event "ISSUER-BLOCKED-NO-RA" -UPN $UserPrincipalName -PerformedBy $issuerOperator -Details "RA flag not present"
        return
    }

    # --- Parse RA flag: extract who authorized ---
    $parts       = $user.$RA_ATTR -split '\|'
    $raWho       = if ($parts.Count -ge 2) { $parts[1] } else { "unknown" }
    $raTimestamp = if ($parts.Count -ge 3) { $parts[2] } else { "unknown" }

    Write-OK "RA authorization confirmed: authorized by '$raWho' at $raTimestamp"

    # --- ENFORCE SEPARATION OF DUTIES ---
    if ($issuerOperatorSam -ieq $raWho) {
        Write-Host ""
        Write-Fail "SEPARATION OF DUTIES VIOLATION DETECTED"
        Write-Fail "The RA and Card Issuer cannot be the same account."
        Write-Fail "RA was: $raWho | Current account: $issuerOperatorSam"
        Write-Host ""
        Write-Host "  This transaction has been blocked and logged." -ForegroundColor Red
        Write-AuditLog -Event "SOD-VIOLATION-BLOCKED" -UPN $UserPrincipalName -PerformedBy $issuerOperator `
            -Details "RA and Issuer are the same account: $raWho — BLOCKED per NIST AC-5"
        return
    }

    Write-OK "Separation of duties verified — RA ($raWho) ≠ Issuer ($issuerOperatorSam)"
    Write-Host ""

    # --- Pre-issuance checklist ---
    Write-Host "PRE-ISSUANCE CHECKLIST" -ForegroundColor Cyan
    $issuerChecks = @(
        "The physical token (smart card or security key) is in my hand and has not been pre-initialized",
        "The token serial number has been recorded (see audit log entry below)",
        "I have confirmed with the RA that the enrollee identity was verified in person",
        "The enrollee is present to set their own PIN — I will NOT know or record the PIN"
    )
    foreach ($check in $issuerChecks) {
        if (-not (Confirm-Prompt "  [ ] $check")) {
            Write-Fail "Pre-issuance check failed — provisioning aborted."
            Write-AuditLog -Event "ISSUER-ABORTED" -UPN $UserPrincipalName -PerformedBy $issuerOperator -Details "Pre-issuance checklist failed: $check"
            return
        }
    }

    $tokenSerial = Read-Host "`n  Enter token serial number (printed on card/key)"
    $tokenType   = Read-Host "  Token type (e.g., CardLogix GIDS, YubiKey 5 NFC)"

    # --- Certificate enrollment ---
    Write-Host ""
    Write-Host "CERTIFICATE ENROLLMENT" -ForegroundColor Cyan
    Write-Step "Requesting Smart Card Logon certificate from Enterprise CA..."
    Write-Host ""
    Write-Host "  Run the following on the Issuing CA or from an enrollment workstation:" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    certreq -enroll -machine -policyserver <CA-Server> SmartCardLogon" -ForegroundColor White
    Write-Host ""
    Write-Host "  Alternatively, use the Certificates MMC snap-in:" -ForegroundColor DarkGray
    Write-Host "  certmgr.msc → Personal → Certificates → All Tasks → Request New Certificate" -ForegroundColor White
    Write-Host "  Select the 'Smart Card Logon' or 'Smart Card User' template." -ForegroundColor White
    Write-Host ""
    Write-Host "  The certificate will be written directly to the hardware token." -ForegroundColor DarkGray
    Write-Host "  Ensure the token is inserted before proceeding." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Confirm-Prompt "Certificate enrolled successfully onto the token?")) {
        Write-Warn "Provisioning paused — complete certificate enrollment and re-run Issuer phase."
        Write-AuditLog -Event "ISSUER-PAUSED" -UPN $UserPrincipalName -PerformedBy $issuerOperator -Details "Certificate enrollment not confirmed"
        return
    }

    # --- Enable smart card logon on the AD account ---
    Write-Step "Enabling SmartcardLogonRequired on AD account..."
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Enable SmartcardLogonRequired")) {
        if ($DomainController) {
            Set-ADUser -Identity $user.SamAccountName -SmartcardLogonRequired $true -Server $DomainController
        } else {
            Set-ADUser -Identity $user.SamAccountName -SmartcardLogonRequired $true
        }
        Write-OK "SmartcardLogonRequired = True set on account"
    }

    # --- PIN change reminder ---
    Write-Host ""
    Write-Host "PIN INITIALIZATION" -ForegroundColor Cyan
    Write-Host "  Hand the token to the enrollee. They must set their own PIN now." -ForegroundColor Yellow
    Write-Host "  Default GIDS card admin key: 010203040506070801020304050607080102030405060708" -ForegroundColor DarkGray
    Write-Host "  YubiKey default PIN: 123456  |  Default PUK: 12345678" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  The enrollee changes their PIN using:" -ForegroundColor DarkGray
    Write-Host "  Windows: Ctrl+Alt+Del → Change a password → select the Smart Card" -ForegroundColor White
    Write-Host "  YubiKey: ykman piv change-pin" -ForegroundColor White
    Write-Host ""

    if (-not (Confirm-Prompt "Enrollee has set their own PIN and confirmed the token works?")) {
        Write-Warn "PIN setup not confirmed — mark token as incomplete until resolved."
        Write-AuditLog -Event "ISSUER-PIN-INCOMPLETE" -UPN $UserPrincipalName -PerformedBy $issuerOperator `
            -Details "Enrollee did not confirm PIN setup — Token: $tokenSerial"
        return
    }

    # --- Clear RA authorization flag now that provisioning is complete ---
    Write-Step "Clearing RA authorization flag (enrollment complete)..."
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Clear RA authorization flag")) {
        if ($DomainController) {
            Set-ADUser -Identity $user.SamAccountName -Clear $RA_ATTR -Server $DomainController
        } else {
            Set-ADUser -Identity $user.SamAccountName -Clear $RA_ATTR
        }
        Write-OK "RA authorization flag cleared"
    }

    Write-AuditLog -Event "ENROLLMENT-COMPLETE" -UPN $UserPrincipalName -PerformedBy $issuerOperator `
        -Details "Token: $tokenType | Serial: $tokenSerial | RA: $raWho | PIN confirmed by enrollee"

    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Green
    Write-Host "  ENROLLMENT COMPLETE" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Enrollee:      $($user.DisplayName) ($UserPrincipalName)" -ForegroundColor White
    Write-Host "  Token type:    $tokenType" -ForegroundColor White
    Write-Host "  Serial number: $tokenSerial" -ForegroundColor White
    Write-Host "  RA:            $raWho" -ForegroundColor White
    Write-Host "  Card Issuer:   $issuerOperator" -ForegroundColor White
    Write-Host "  Completed:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    Write-Host ""
    Write-Host "  SmartcardLogonRequired is now ENABLED on the account." -ForegroundColor Green
    Write-Host "  The enrollee must use their token to log in going forward." -ForegroundColor Green
    Write-Host ("=" * 72) -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MODULE: STATUS CHECK
# ---------------------------------------------------------------------------
function Invoke-StatusCheck {
    if (-not $UserPrincipalName) {
        throw "UserPrincipalName is required for Status mode."
    }

    $user = Get-ADUserObject -UPN $UserPrincipalName

    Write-Host ""
    Write-Host "ENROLLMENT STATUS: $UserPrincipalName" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Display Name:           $($user.DisplayName)"
    Write-Host "  SAM Account:            $($user.SamAccountName)"
    Write-Host "  Account Enabled:        $($user.Enabled)"
    Write-Host "  Account Locked:         $($user.LockedOut)"
    Write-Host "  SmartcardLogonRequired: $($user.SmartcardLogonRequired)"
    Write-Host ""

    if ($user.$RA_ATTR -like "$RA_PREFIX*") {
        $parts = $user.$RA_ATTR -split '\|'
        Write-Host "  RA Authorization:  PENDING — authorized by '$($parts[1])' at $($parts[2])" -ForegroundColor Yellow
        Write-Host "  Awaiting Card Issuer provisioning phase." -ForegroundColor Yellow
    } elseif ($user.SmartcardLogonRequired) {
        Write-Host "  Enrollment Status: COMPLETE — smart card logon is required" -ForegroundColor Green
    } else {
        Write-Host "  Enrollment Status: NOT ENROLLED — RA phase has not been run" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MODULE: AUDIT LOG VIEWER
# ---------------------------------------------------------------------------
function Invoke-AuditLog {
    if (-not (Test-Path $LogPath)) {
        Write-Warn "No audit log found at: $LogPath"
        return
    }

    Write-Host ""
    Write-Host "ENROLLMENT AUDIT LOG — $LogPath" -ForegroundColor Cyan
    Write-Host ""

    if ($UserPrincipalName) {
        Get-Content $LogPath | Where-Object { $_ -like "*$UserPrincipalName*" } | ForEach-Object {
            Write-Host "  $_"
        }
    } else {
        Get-Content $LogPath | Select-Object -Last 50 | ForEach-Object {
            Write-Host "  $_"
        }
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Banner

# Verify RSAT AD module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host ""
    Write-Fail "ActiveDirectory PowerShell module is not installed."
    Write-Host "  Install RSAT: Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'" -ForegroundColor DarkGray
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

switch ($Mode) {
    'RA'       { Invoke-RAPhase }
    'Issuer'   { Invoke-IssuerPhase }
    'Status'   { Invoke-StatusCheck }
    'AuditLog' { Invoke-AuditLog }
}
