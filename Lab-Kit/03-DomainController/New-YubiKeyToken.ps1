#Requires -Version 5.1
<#
.SYNOPSIS
    YubiKey PIV Token Provisioning — PIN/PUK/Management Key Setup + Certificate Enrollment

.DESCRIPTION
    Provisions a YubiKey for smart card (PIV) use in a CAC/PIV environment.
    Wraps the YubiKey Manager CLI (ykman) to perform every step of the provisioning
    ceremony in the correct order, with enforced standards and a full audit trail.

    What this script does:
      1. Verifies ykman is installed; offers to install it if missing
      2. Detects the connected YubiKey (serial, firmware, form factor)
      3. Resets the PIV application to a known-good state (optional, with confirmation)
      4. Generates a new Management Key (AES-256) and stores it securely
      5. Sets a compliant PIN and PUK — operator never sees them in plaintext
      6. Loads or generates keys in the PIV slots you select:
           9a — PIV Authentication    (smart card logon to Windows)
           9c — Digital Signature     (document signing, code signing)
           9d — Key Management        (email encryption, key exchange)
           9e — Card Authentication   (physical access, CMS)
      7. For each loaded slot: generates a CSR, submits to the Issuing CA
         via certreq.exe, and imports the issued certificate back to the token
      8. Verifies the end-to-end chain for every issued certificate
      9. Writes a full audit record (serial, slots provisioned, operator, timestamp)
         to the local log and Windows Application Event Log

    Document ID : SCRIPT-ICAM-016
    Framework   : NIST SP 800-53 IA-2, IA-2(11), IA-5, AC-5 | FIPS 201-3 | SP 800-73-4

.PARAMETER Mode
    Provision  — Full provisioning ceremony (default)
    Status     — Show current PIV state of a connected YubiKey (read-only)
    Reset      — Reset PIV application only (clears all certs and keys)
    Verify     — Verify certificate chains on all occupied slots

.PARAMETER UserPrincipalName
    UPN of the account being enrolled (e.g., jsmith@lab.local).
    Required for Provision mode.

.PARAMETER CAServer
    CA server\CA name for certificate enrollment (e.g., "ca01.lab.local\Lab Issuing CA").
    Required for Provision mode. Used with certreq.exe.

.PARAMETER Slots
    Which PIV slots to provision. Default: 9a (Authentication only).
    Accepted values: 9a, 9c, 9d, 9e  (one or more, comma-separated)

.PARAMETER KeyAlgorithm
    Key algorithm and length for generated key pairs.
    Accepted values: ECCP256 (default), ECCP384, RSA2048
    ECCP256 and ECCP384 are preferred for new deployments (smaller, faster).
    RSA2048 required if your CA or legacy apps do not support ECC.

.PARAMETER TemplateName
    Certificate template name on the Issuing CA.
    Default: "SmartCardLogon" (matches New-CertificateTemplates.ps1 output).

.PARAMETER SkipReset
    Do not offer to reset the PIV application before provisioning.
    Use when adding additional certificates to an already-initialized token.

.PARAMETER LogPath
    Path for the provisioning audit log.
    Default: C:\Windows\Logs\YubiKeyProvisioning.log

.PARAMETER WorkDir
    Temporary directory for CSR and certificate files during the ceremony.
    Cleaned up automatically on exit.
    Default: a randomly-named folder under $env:TEMP

.EXAMPLE
    # Full provisioning — slot 9a only (most common)
    .\New-YubiKeyToken.ps1 -Mode Provision -UserPrincipalName jsmith@lab.local `
        -CAServer "ca01.lab.local\Lab Issuing CA"

    # Provision slots 9a and 9d (logon + key management)
    .\New-YubiKeyToken.ps1 -Mode Provision -UserPrincipalName jsmith@lab.local `
        -CAServer "ca01.lab.local\Lab Issuing CA" -Slots 9a,9d

    # Check what is currently on the token without changing anything
    .\New-YubiKeyToken.ps1 -Mode Status

    # Verify certificate chains on all occupied slots
    .\New-YubiKeyToken.ps1 -Mode Verify

    # Reset PIV and re-provision with ECC P-384 keys
    .\New-YubiKeyToken.ps1 -Mode Provision -UserPrincipalName jsmith@lab.local `
        -CAServer "ca01.lab.local\Lab Issuing CA" -KeyAlgorithm ECCP384

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    PREREQUISITES:
    - YubiKey Manager CLI (ykman) installed. The script offers to download and install
      it from Yubico if not found. Download page: https://developers.yubico.com/yubikey-manager/
    - certreq.exe (built into Windows) for CA enrollment
    - Must run as Administrator
    - YubiKey must be inserted before running

    SECURITY NOTES:
    - The Management Key is generated randomly (AES-256, 48 hex chars) and displayed
      ONCE at provisioning time. The operator MUST record it in a password manager
      or secure vault before continuing. There is no recovery mechanism.
    - PIN and PUK are entered interactively via Read-Host -AsSecureString.
      They are never written to disk or logged.
    - Temporary CSR and certificate files are written to a randomly-named TEMP folder
      and deleted immediately after use.
    - PIV PIN requirements enforced: 6-8 digits, no trivial sequences.
    - PIV PUK requirements enforced: 8 digits.

    FIPS 201-3 PIV SLOT MAPPING:
    Slot  Alias               Purpose
    9a    PIV Authentication  Windows smart card logon, SSH authentication
    9c    Digital Signature   Document signing, email S/MIME signing
    9d    Key Management      Email encryption, key escrow
    9e    Card Authentication Physical access systems, CMS authentication
    f9    Attestation         Built-in Yubico attestation (read-only, do not provision)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('Provision','Status','Reset','Verify')]
    [string]$Mode = 'Provision',

    [Parameter()]
    [string]$UserPrincipalName,

    [Parameter()]
    [string]$CAServer,

    [Parameter()]
    [ValidateSet('9a','9c','9d','9e')]
    [string[]]$Slots = @('9a'),

    [Parameter()]
    [ValidateSet('ECCP256','ECCP384','RSA2048')]
    [string]$KeyAlgorithm = 'ECCP256',

    [Parameter()]
    [string]$TemplateName = 'SmartCardLogon',

    [Parameter()]
    [switch]$SkipReset,

    [Parameter()]
    [string]$LogPath = 'C:\Windows\Logs\YubiKeyProvisioning.log',

    [Parameter()]
    [string]$WorkDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Slot metadata
# ---------------------------------------------------------------------------
$SlotInfo = @{
    '9a' = @{ Name = 'PIV Authentication';  Purpose = 'Windows smart card logon, SSH'; TouchPolicy = 'never'  }
    '9c' = @{ Name = 'Digital Signature';   Purpose = 'Document / email signing';       TouchPolicy = 'always' }
    '9d' = @{ Name = 'Key Management';      Purpose = 'Email encryption, key escrow';   TouchPolicy = 'cached' }
    '9e' = @{ Name = 'Card Authentication'; Purpose = 'Physical access, CMS';           TouchPolicy = 'never'  }
}

$PinPolicy = 'once'    # require PIN once per session (NIST SP 800-73-4 recommended)

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
function Write-Banner {
    $width = 72
    Write-Host ""
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host "  YUBIKEY PIV PROVISIONING — $($Mode.ToUpper()) MODE" -ForegroundColor Cyan
    Write-Host "  SCRIPT-ICAM-016 | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  NIST SP 800-53 IA-2, IA-5 | FIPS 201-3 | SP 800-73-4" -ForegroundColor Cyan
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step { param([string]$Text)
    Write-Host ""
    Write-Host "  ── $Text" -ForegroundColor Yellow
}

function Write-OK  { param([string]$Text) Write-Host "    [OK]   $Text" -ForegroundColor Green }
function Write-Warn{ param([string]$Text) Write-Host "    [WARN] $Text" -ForegroundColor Yellow }
function Write-Err { param([string]$Text) Write-Host "    [FAIL] $Text" -ForegroundColor Red }
function Write-Info{ param([string]$Text) Write-Host "    [INFO] $Text" -ForegroundColor Cyan }

function Write-AuditLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $operator = "$env:USERDOMAIN\$env:USERNAME"
    $line = "[$ts] [$operator] $Message"

    # Append to file
    try {
        $logDir = Split-Path $LogPath
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch {
        Write-Warn "Could not write to log file: $_"
    }

    # Windows Application Event Log (Source: YubiKeyProvisioning, Event ID: 7200)
    try {
        $srcName = "YubiKeyProvisioning"
        if (-not [System.Diagnostics.EventLog]::SourceExists($srcName)) {
            [System.Diagnostics.EventLog]::CreateEventSource($srcName, "Application")
        }
        Write-EventLog -LogName Application -Source $srcName -EventId 7200 `
            -EntryType Information -Message $Message
    } catch {
        # Non-fatal — log file already written
    }
}

function Invoke-Ykman {
    param([string[]]$Arguments)
    # ykman writes prompts/warnings (e.g. "Touch your YubiKey...") to stderr. With the script's
    # $ErrorActionPreference='Stop', capturing stderr via 2>&1 can turn those informational lines
    # into terminating errors before we ever check the exit code. Force Continue locally and
    # judge success solely by the process exit code.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & ykman @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $eap
    }
    if ($LASTEXITCODE -ne 0) {
        throw "ykman $($Arguments -join ' ') failed (exit $LASTEXITCODE): $result"
    }
    return $result
}

function Test-TrivialPin {
    param([string]$Pin)
    # Reject all-same digit, sequential ascending/descending
    if ($Pin -match '^(\d)\1+$') { return $true }
    $digits = $Pin.ToCharArray() | ForEach-Object { [int]::Parse($_) }
    # Wrap in @() so an empty pipeline result is an empty array (.Count = 0) rather than
    # $null, which would throw under Set-StrictMode when we read .Count below.
    $ascending  = @(0..($digits.Count-2) | Where-Object { $digits[$_+1] - $digits[$_] -ne 1 })
    $descending = @(0..($digits.Count-2) | Where-Object { $digits[$_] - $digits[$_+1] -ne 1 })
    if ($ascending.Count -eq 0)  { return $true }   # e.g. 123456
    if ($descending.Count -eq 0) { return $true }   # e.g. 654321
    return $false
}

function Get-SecurePin {
    param([string]$Prompt, [int]$MinLength = 6, [int]$MaxLength = 8, [bool]$IsPuk = $false)
    $label = if ($IsPuk) { "PUK" } else { "PIN" }
    while ($true) {
        $ss1 = Read-Host -Prompt "    Enter $Prompt" -AsSecureString
        $ss2 = Read-Host -Prompt "    Confirm $Prompt" -AsSecureString

        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
              [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
              [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss2))

        if ($p1 -ne $p2) {
            Write-Warn "Values do not match — try again."
            continue
        }
        if ($p1 -notmatch '^\d+$') {
            Write-Warn "$label must contain digits only."
            continue
        }
        if ($p1.Length -lt $MinLength -or $p1.Length -gt $MaxLength) {
            Write-Warn "$label must be $MinLength–$MaxLength digits."
            continue
        }
        if (-not $IsPuk -and (Test-TrivialPin -Pin $p1)) {
            Write-Warn "PIN is too predictable (sequential or all-same). Choose a stronger PIN."
            continue
        }
        # Return the plain value — used only within ykman call, then discarded
        return $p1
    }
}

# ---------------------------------------------------------------------------
#  Prerequisite: ykman
# ---------------------------------------------------------------------------
function Assert-Ykman {
    Write-Step "Checking YubiKey Manager CLI (ykman)"

    if (Get-Command ykman -ErrorAction SilentlyContinue) {
        $ver = (ykman --version 2>&1) -join ""
        Write-OK "ykman found — $ver"
        return
    }

    Write-Warn "ykman is not installed or not in PATH."
    Write-Info "Download: https://developers.yubico.com/yubikey-manager/"
    Write-Info "Windows installer: YubiKey-Manager-<version>-win64.msi"
    Write-Host ""
    $ans = Read-Host "    Do you want to open the Yubico download page now? (Y/N)"
    if ($ans -match '^[Yy]') {
        Start-Process "https://developers.yubico.com/yubikey-manager/Releases/"
    }
    throw "ykman is required. Install it and re-run the script."
}

# ---------------------------------------------------------------------------
#  Detect YubiKey
# ---------------------------------------------------------------------------
function Get-YubiKeyInfo {
    Write-Step "Detecting connected YubiKey"

    try {
        $info = Invoke-Ykman @('info')
    } catch {
        throw "No YubiKey detected or ykman cannot communicate with it. " +
              "Insert the token and try again."
    }

    $serial   = ($info | Where-Object { $_ -match 'Serial number' }) -replace '.*:\s*',''
    $firmware = ($info | Where-Object { $_ -match 'Firmware' })      -replace '.*:\s*',''
    $form     = ($info | Where-Object { $_ -match 'Form factor' })   -replace '.*:\s*',''
    $device   = ($info | Where-Object { $_ -match 'Device type' })   -replace '.*:\s*',''

    Write-OK "Device    : $device"
    Write-OK "Serial    : $serial"
    Write-OK "Firmware  : $firmware"
    Write-OK "Form      : $form"

    # Confirm the operator is looking at the right token
    Write-Host ""
    $confirm = Read-Host "    Is this the correct YubiKey for this enrollment? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        throw "Operator aborted — wrong token inserted."
    }

    return @{ Serial = $serial.Trim(); Firmware = $firmware.Trim(); Form = $form.Trim() }
}

# ---------------------------------------------------------------------------
#  Status Mode
# ---------------------------------------------------------------------------
function Show-Status {
    Write-Step "PIV Application State"
    try {
        $pivInfo = Invoke-Ykman @('piv','info')
        $pivInfo | ForEach-Object { Write-Info $_ }
    } catch {
        Write-Err "Could not read PIV info: $_"
    }

    Write-Step "Slot Certificate Summary"
    foreach ($slot in '9a','9c','9d','9e') {
        try {
            $cert = Invoke-Ykman @('piv','certificates','export',$slot,'-') 2>&1
            if ($LASTEXITCODE -eq 0 -and $cert -match 'BEGIN CERTIFICATE') {
                # Parse the cert for subject/expiry
                $certObj = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    [System.Text.Encoding]::ASCII.GetBytes(($cert -join "`n")))
                Write-OK "Slot $slot ($($SlotInfo[$slot].Name))"
                Write-Info "        Subject : $($certObj.Subject)"
                Write-Info "        Expires : $($certObj.NotAfter.ToString('yyyy-MM-dd'))"
                Write-Info "        Issuer  : $($certObj.Issuer)"
            } else {
                Write-Info "Slot $slot ($($SlotInfo[$slot].Name)) — empty"
            }
        } catch {
            Write-Info "Slot $slot ($($SlotInfo[$slot].Name)) — empty or unreadable"
        }
    }
}

# ---------------------------------------------------------------------------
#  Reset Mode
# ---------------------------------------------------------------------------
function Invoke-PivReset {
    Write-Step "PIV Application Reset"
    Write-Warn "This will DELETE all certificates and keys from the PIV application."
    Write-Warn "The PIN, PUK, and Management Key will be reset to factory defaults."
    Write-Host ""
    $confirm = Read-Host "    Type RESET to confirm, or anything else to abort"
    if ($confirm -ne 'RESET') {
        Write-Info "Reset aborted."
        return $false
    }
    Invoke-Ykman @('piv','reset','--force') | Out-Null
    Write-OK "PIV application reset to factory state."
    Write-AuditLog "PIV RESET performed on token. All keys and certificates cleared."
    return $true
}

# ---------------------------------------------------------------------------
#  Generate Management Key
# ---------------------------------------------------------------------------
function Set-ManagementKey {
    Write-Step "Setting Management Key (AES-256)"

    # Generate 32 random bytes = 64 hex chars (AES-256 for PIV management key).
    # AES-256 requires a 32-byte key; 24 bytes is only valid for TDES/AES-192.
    $bytes   = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $mgmtKey = ($bytes | ForEach-Object { $_.ToString('X2') }) -join ''

    # The default management key used after reset
    $defaultKey = '010203040506070801020304050607080102030405060708'

    Invoke-Ykman @('piv','access','change-management-key',
        '--management-key', $defaultKey,
        '--new-management-key', $mgmtKey,
        '--algorithm', 'AES256') | Out-Null

    Write-OK "Management key set (AES-256)."
    Write-Host ""
    Write-Host "    ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "    ║  MANAGEMENT KEY — RECORD AND STORE IN SECURE VAULT NOW      ║" -ForegroundColor Red
    Write-Host "    ║  This is the ONLY time this key will be displayed.           ║" -ForegroundColor Red
    Write-Host "    ║                                                              ║" -ForegroundColor Red
    Write-Host "    ║  $mgmtKey  ║" -ForegroundColor Yellow
    Write-Host "    ║                                                              ║" -ForegroundColor Red
    Write-Host "    ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Read-Host "    Press Enter ONLY after you have recorded the management key"

    Write-AuditLog "Management key changed to AES-256 (key value not logged)."
    return $mgmtKey
}

# ---------------------------------------------------------------------------
#  Set PIN and PUK
# ---------------------------------------------------------------------------
function Set-PinAndPuk {
    param([string]$MgmtKey)

    Write-Step "Setting PIN (6–8 digits)"
    Write-Info "The PIN is what the user enters each time they log in."
    Write-Info "Do not choose: 123456, 654321, 111111, or similar patterns."
    Write-Host ""
    $pin = Get-SecurePin -Prompt "new PIN (6–8 digits)" -MinLength 6 -MaxLength 8

    Write-Step "Setting PUK (8 digits)"
    Write-Info "The PUK is used to unblock the PIN if it is entered incorrectly too many times."
    Write-Info "Keep the PUK separate from the PIN. Store it in the same vault as the management key."
    Write-Host ""
    $puk = Get-SecurePin -Prompt "new PUK (8 digits)" -MinLength 8 -MaxLength 8 -IsPuk $true

    # Default factory PIN is '123456', default PUK is '12345678'
    $defaultPin = '123456'
    $defaultPuk = '12345678'

    Invoke-Ykman @('piv','access','change-pin',
        '--pin', $defaultPin, '--new-pin', $pin) | Out-Null
    Write-OK "PIN set."

    Invoke-Ykman @('piv','access','change-puk',
        '--puk', $defaultPuk, '--new-puk', $puk) | Out-Null
    Write-OK "PUK set."

    Write-AuditLog "PIN and PUK changed. Values not logged (entered interactively)."

    # Return PIN for use during certificate import — caller is responsible for clearing
    return $pin
}

# ---------------------------------------------------------------------------
#  Generate key + CSR for one slot, submit to CA, import cert
# ---------------------------------------------------------------------------
function Invoke-SlotProvisioning {
    param(
        [string]$Slot,
        [string]$MgmtKey,
        [string]$Pin,
        [string]$UPN,
        [string]$CAServer,
        [string]$TemplateName,
        [string]$WorkDir,
        [hashtable]$TokenInfo
    )

    $slotMeta  = $SlotInfo[$Slot]
    $slotLabel = "Slot $Slot ($($slotMeta.Name))"

    Write-Step "Provisioning $slotLabel"
    Write-Info "Purpose : $($slotMeta.Purpose)"
    Write-Info "Algorithm: $KeyAlgorithm | Touch: $($slotMeta.TouchPolicy) | PIN: $PinPolicy"

    # ── 1. Generate key pair on token ──────────────────────────────────────
    $pubKeyFile = Join-Path $WorkDir "pubkey-$Slot.pem"
    Write-Info "Generating $KeyAlgorithm key pair on token..."
    Invoke-Ykman @(
        'piv','keys','generate',
        '--algorithm',     $KeyAlgorithm,
        '--pin-policy',    $PinPolicy,
        '--touch-policy',  $slotMeta.TouchPolicy,
        '--management-key',$MgmtKey,
        $Slot, $pubKeyFile
    ) | Out-Null
    Write-OK "Key pair generated."

    # ── 2. Generate CSR ────────────────────────────────────────────────────
    $csrFile  = Join-Path $WorkDir "csr-$Slot.req"
    $cn       = ($UPN -split '@')[0]
    # ykman 5.x requires an RFC 4514 subject (e.g. "CN=jdoe"), not the OpenSSL slash format.
    # The enterprise template builds the real subject + UPN SAN from AD, so a minimal CN is fine.
    $subject  = "CN=$cn"

    Write-Info "Generating Certificate Signing Request..."
    Invoke-Ykman @(
        'piv','certificates','request',
        '--subject', $subject,
        '--pin',     $Pin,
        $Slot, $pubKeyFile, $csrFile
    ) | Out-Null

    if (-not (Test-Path $csrFile)) {
        throw "CSR file not created at $csrFile"
    }
    Write-OK "CSR created: $csrFile"

    # ── 3. Build certreq .inf for template enrollment ──────────────────────
    $infFile  = Join-Path $WorkDir "enroll-$Slot.inf"
    $certFile = Join-Path $WorkDir "cert-$Slot.cer"

    $infContent = @"
[NewRequest]
Subject = "CN=$cn,emailAddress=$UPN"
RequestType = PKCS10
ExistingKeySet = FALSE

[RequestAttributes]
CertificateTemplate = $TemplateName
SAN = upn=$UPN

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "upn=$UPN&"
"@
    Set-Content -Path $infFile -Value $infContent -Encoding ASCII

    # ── 4. Submit CSR to CA and retrieve certificate ───────────────────────
    Write-Info "Submitting CSR to $CAServer (template: $TemplateName)..."
    Write-Host ""
    Write-Warn "certreq will prompt for CA credentials if required."
    Write-Host ""

    $certreqOut = & certreq -submit -attrib "CertificateTemplate:$TemplateName" "-config" $CAServer $csrFile $certFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "certreq output:"
        $certreqOut | ForEach-Object { Write-Info $_ }
        throw "Certificate request failed (exit $LASTEXITCODE). Check CA connectivity and template permissions."
    }

    if (-not (Test-Path $certFile)) {
        throw "Certificate file not found after certreq — CA may require manual approval."
    }
    Write-OK "Certificate issued: $certFile"

    # ── 5. Import certificate to token ────────────────────────────────────
    Write-Info "Importing certificate to $slotLabel..."
    Invoke-Ykman @(
        'piv','certificates','import',
        '--management-key', $MgmtKey,
        '--pin',            $Pin,
        '--verify',
        $Slot, $certFile
    ) | Out-Null
    Write-OK "Certificate imported to token."

    # ── 6. Verify ─────────────────────────────────────────────────────────
    Write-Info "Verifying certificate on token..."
    $verifyOut = Invoke-Ykman @('piv','certificates','export', $Slot, '-')
    if ($verifyOut -match 'BEGIN CERTIFICATE') {
        Write-OK "$slotLabel — certificate verified on token."
    } else {
        throw "Verification failed — certificate not readable from token after import."
    }

    # ── 7. Scrub temp files ───────────────────────────────────────────────
    Remove-Item $pubKeyFile,$csrFile,$infFile,$certFile -ErrorAction SilentlyContinue

    Write-AuditLog "Slot $Slot provisioned | Algorithm: $KeyAlgorithm | UPN: $UPN | CA: $CAServer | Template: $TemplateName | Serial: $($TokenInfo.Serial)"
    Write-OK "$slotLabel provisioning complete."
}

# ---------------------------------------------------------------------------
#  Verify Mode — chain validation for all occupied slots
# ---------------------------------------------------------------------------
function Invoke-VerifyAll {
    Write-Step "Certificate Chain Verification"
    $tmpDir = Join-Path $env:TEMP "yk-verify-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    foreach ($slot in '9a','9c','9d','9e') {
        $certFile = Join-Path $tmpDir "verify-$slot.cer"
        try {
            $pemData = Invoke-Ykman @('piv','certificates','export', $slot, '-') 2>&1
            if ($pemData -notmatch 'BEGIN CERTIFICATE') {
                Write-Info "Slot $slot — empty, skipping"
                continue
            }
            # Write PEM, convert to DER, verify with certutil
            Set-Content -Path "$certFile.pem" -Value ($pemData -join "`n") -Encoding ASCII
            & certutil -encode "$certFile.pem" $certFile | Out-Null
            $verifyOut = & certutil -verify -urlfetch $certFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Slot $slot ($($SlotInfo[$slot].Name)) — chain valid"
            } else {
                Write-Err "Slot $slot ($($SlotInfo[$slot].Name)) — chain FAILED"
                $verifyOut | Where-Object { $_ -match 'ERROR|FAILED|Expired' } |
                    ForEach-Object { Write-Warn "  $_" }
            }
        } catch {
            Write-Warn "Slot $slot — could not verify: $_"
        }
    }
    Remove-Item $tmpDir -Recurse -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
function Main {
    Write-Banner

    # Admin check
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must run as Administrator."
    }

    Assert-Ykman
    $tokenInfo = Get-YubiKeyInfo

    switch ($Mode) {
        'Status'  {
            Show-Status
            return
        }
        'Verify'  {
            Invoke-VerifyAll
            return
        }
        'Reset'   {
            Invoke-PivReset | Out-Null
            return
        }
        'Provision' {
            # Validate required params
            if (-not $UserPrincipalName) { throw "-UserPrincipalName is required for Provision mode." }
            if (-not $CAServer)          { throw "-CAServer is required for Provision mode."          }

            # Work directory
            if (-not $WorkDir) {
                $WorkDir = Join-Path $env:TEMP "ykprov-$(Get-Random)"
            }
            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

            Write-AuditLog "PROVISIONING STARTED | Token Serial: $($tokenInfo.Serial) | UPN: $UserPrincipalName | Slots: $($Slots -join ',') | Operator: $env:USERDOMAIN\$env:USERNAME"

            # Initialize so the finally-block cleanup never trips Set-StrictMode if we fail
            # before the PIN is set (otherwise the real error gets masked by an unset-$pin error).
            $pin = $null

            try {
                # Optional PIV reset
                if (-not $SkipReset) {
                    Write-Host ""
                    Write-Warn "STEP 1 of 4 — PIV Reset (recommended for a fresh token)"
                    Write-Info "Resetting clears any pre-existing data and ensures a known-good state."
                    $doReset = Read-Host "    Reset PIV application before provisioning? (Y/N)"
                    if ($doReset -match '^[Yy]') {
                        Invoke-PivReset | Out-Null
                    } else {
                        Write-Info "Skipping reset — proceeding with current PIV state."
                    }
                }

                # Management key
                Write-Host ""
                Write-Info "STEP 2 of 4 — Management Key"
                $mgmtKey = Set-ManagementKey

                # PIN + PUK
                Write-Host ""
                Write-Info "STEP 3 of 4 — PIN and PUK"
                $pin = Set-PinAndPuk -MgmtKey $mgmtKey

                # Slot provisioning
                Write-Host ""
                Write-Info "STEP 4 of 4 — Key Generation and Certificate Enrollment"
                Write-Info "Provisioning $($Slots.Count) slot(s): $($Slots -join ', ')"

                foreach ($slot in $Slots) {
                    Invoke-SlotProvisioning `
                        -Slot       $slot `
                        -MgmtKey    $mgmtKey `
                        -Pin        $pin `
                        -UPN        $UserPrincipalName `
                        -CAServer   $CAServer `
                        -TemplateName $TemplateName `
                        -WorkDir    $WorkDir `
                        -TokenInfo  $tokenInfo
                }

                Write-AuditLog "PROVISIONING COMPLETE | Token Serial: $($tokenInfo.Serial) | Slots: $($Slots -join ',') | UPN: $UserPrincipalName"

                Write-Host ""
                Write-Host ("=" * 72) -ForegroundColor DarkGreen
                Write-Host "  PROVISIONING COMPLETE" -ForegroundColor Green
                Write-Host ("=" * 72) -ForegroundColor DarkGreen
                Write-Host ""
                Write-OK "YubiKey serial : $($tokenInfo.Serial)"
                Write-OK "UPN enrolled   : $UserPrincipalName"
                Write-OK "Slots          : $($Slots -join ', ')"
                Write-OK "Algorithm      : $KeyAlgorithm"
                Write-Host ""
                Write-Info "Next step: hand the token and PIN to the enrollee."
                Write-Info "Verify smart card logon with: .\New-TokenEnrollment.ps1 -Mode Status -UserPrincipalName $UserPrincipalName"
                Write-Host ""

            } finally {
                # Always clean up temp work dir
                if (Test-Path $WorkDir) {
                    Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                # Clear PIN variable from memory
                if ($pin) { $pin = $null }
            }
        }
    }
}

Main
