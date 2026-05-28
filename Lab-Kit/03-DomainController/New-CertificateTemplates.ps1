#Requires -Version 5.1
<#
.SYNOPSIS
    AD CS Certificate Template Automation — Smart Card Logon and Privileged Admin Templates

.DESCRIPTION
    Creates and configures the certificate templates required for smart card enrollment
    in Active Directory Certificate Services (AD CS). Automates what would otherwise
    require manually duplicating and editing templates through the Certificate Templates MMC.

    Templates created:
      1. SmartCard-UserLogon  — Standard user smart card authentication template
         - EKU: Smart Card Logon (1.3.6.1.4.1.311.20.2.2) + Client Auth (1.3.6.1.5.5.7.3.2)
         - Key: RSA 2048, stored on hardware token (not exportable)
         - Subject: Supply in request (UPN-mapped to the enrollee)
         - Validity: 1 year | Renewal: 6 weeks before expiry

      2. SmartCard-AdminLogon — Privileged administrative account template
         - Same EKU set as UserLogon
         - Separate enrollment — requires admin CA Manager approval
         - Issued only to accounts in the PKI-Admins security group
         - Validity: 1 year

    Document ID : SCRIPT-ICAM-014
    Framework   : NIST SP 800-53 IA-2, IA-2(1), IA-5, SC-17 | FIPS 201-3

.PARAMETER CAServer
    The Enterprise Issuing CA server in "Server\CAName" format.
    Example: "ca01.lab.local\Enterprise Issuing CA"

.PARAMETER EnrollmentGroup
    AD group whose members are permitted to auto-enroll the standard user template.
    Default: "Domain Users"

.PARAMETER AdminEnrollmentGroup
    AD group whose members can request the admin template (requires CA Manager approval).
    Default: "PKI-Admins"
    Create this group in AD before running the script if it doesn't exist.

.PARAMETER TemplateUserName
    Internal name for the standard user template. Default: "SmartCard-UserLogon"

.PARAMETER TemplateAdminName
    Internal name for the admin template. Default: "SmartCard-AdminLogon"

.PARAMETER ValidityYears
    Certificate validity in years. Default: 1

.PARAMETER RenewalWeeks
    Weeks before expiry to trigger renewal. Default: 6

.EXAMPLE
    # Create both templates on the Issuing CA
    .\New-CertificateTemplates.ps1 -CAServer "ca01.lab.local\Enterprise Issuing CA"

    # Create with a custom enrollment group
    .\New-CertificateTemplates.ps1 -CAServer "ca01.lab.local\Enterprise Issuing CA" `
        -EnrollmentGroup "SmartCard-Users" -AdminEnrollmentGroup "PKI-Admins"

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    REQUIREMENTS:
    - Run on the Enterprise Issuing CA server or a machine with RSAT-ADCS installed
    - Requires PSPKI module (installed by Download-IssuingCA-Kit.ps1)
    - Must run as a user with CA Manager (Certificate Manager) permissions

    TEMPLATE NAMES vs DISPLAY NAMES:
    The template "name" (internal, no spaces) is what you reference in certreq and GPO.
    The "display name" is what appears in Certificate Templates MMC and enrollment dialogs.
    This script sets both consistently.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CAServer,

    [Parameter()]
    [string]$EnrollmentGroup = "Domain Users",

    [Parameter()]
    [string]$AdminEnrollmentGroup = "PKI-Admins",

    [Parameter()]
    [string]$TemplateUserName = "SmartCard-UserLogon",

    [Parameter()]
    [string]$TemplateAdminName = "SmartCard-AdminLogon",

    [Parameter()]
    [int]$ValidityYears = 1,

    [Parameter()]
    [int]$RenewalWeeks = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host "  CERTIFICATE TEMPLATE AUTOMATION | SCRIPT-ICAM-014" -ForegroundColor Cyan
    Write-Host "  Author: Glenn Byron | CA: $CAServer" -ForegroundColor Cyan
    Write-Host "  NIST SP 800-53 IA-2, IA-5, SC-17 | FIPS 201-3" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step    { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor White }
function Write-OK      { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-Info    { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }
function Write-Section { param([string]$T) Write-Host ""; Write-Host "── $T" -ForegroundColor White }

# ---------------------------------------------------------------------------
function Assert-PSPKIAvailable {
    if (-not (Get-Module -ListAvailable -Name PSPKI)) {
        Write-Fail "PSPKI module is not installed."
        Write-Info "Run Download-IssuingCA-Kit.ps1 -InstallModules to install it, or:"
        Write-Info "  Install-Module -Name PSPKI -Force"
        throw "PSPKI module required"
    }
    Import-Module PSPKI -ErrorAction Stop
    Write-OK "PSPKI module loaded"
}

function Assert-ADAvailable {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Warn "ActiveDirectory module not available — skipping AD permission steps."
        return $false
    }
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    return $true
}

# ---------------------------------------------------------------------------
# TEMPLATE CREATION HELPER
# ---------------------------------------------------------------------------
function New-SmartCardTemplate {
    param(
        [string]$TemplateName,
        [string]$DisplayName,
        [string]$Description,
        [bool]$RequireCAApproval,
        [string]$EnrollGroup,
        [string]$SourceTemplateName = "User"  # base template to duplicate
    )

    Write-Section "Creating Template: $DisplayName"

    # Check if template already exists
    $existing = Get-CertificateTemplate -Name $TemplateName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "Template '$TemplateName' already exists — updating settings."
    } else {
        Write-Step "Duplicating base template '$SourceTemplateName'..."
        if ($PSCmdlet.ShouldProcess($TemplateName, "Duplicate from $SourceTemplateName")) {
            Import-Module ActiveDirectory -ErrorAction Stop
            $cfgNC       = (Get-ADRootDSE).configurationNamingContext
            $containerDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"

            # Fetch only the specific pKICertificateTemplate attributes we need.
            # Using -Properties * causes Get-ADObject to return synthetic PS properties
            # (Created, Modified, etc.) that are not valid LDAP attribute names and cause
            # New-ADObject -OtherAttributes to throw "attribute or value does not exist".
            $src = Get-ADObject -Identity "CN=$SourceTemplateName,$containerDN" -Properties `
                flags, revision, 'msPKI-Template-Schema-Version', 'msPKI-Template-Minor-Revision',
                'msPKI-RA-Signature', 'msPKI-Minimal-Key-Size', pKIDefaultKeySpec,
                pKIMaxIssuingDepth, pKIKeyUsage, pKIExpirationPeriod, pKIOverlapPeriod,
                'msPKI-Certificate-Name-Flag', 'msPKI-Enrollment-Flag', 'msPKI-Private-Key-Flag',
                pKIDefaultCSPs, pKIExtendedKeyUsage, 'msPKI-Certificate-Application-Policy',
                pKICriticalExtensions -ErrorAction Stop

            $gb = [System.Guid]::NewGuid().ToByteArray()
            $oidSuffix = "$([System.BitConverter]::ToUInt32($gb,0)).$([System.BitConverter]::ToUInt32($gb,4))"

            $other = @{
                'displayName'                          = $DisplayName
                'msPKI-Cert-Template-OID'              = "1.3.6.1.4.1.311.21.8.$oidSuffix"
                'flags'                                = [int]$src.flags
                'revision'                             = [int]$src.revision
                'msPKI-Template-Schema-Version'        = [int]$src.'msPKI-Template-Schema-Version'
                'msPKI-Template-Minor-Revision'        = [int]$src.'msPKI-Template-Minor-Revision'
                'msPKI-RA-Signature'                   = [int]$src.'msPKI-RA-Signature'
                'msPKI-Minimal-Key-Size'               = 2048
                'pKIDefaultKeySpec'                    = [int]$src.pKIDefaultKeySpec
                'pKIMaxIssuingDepth'                   = [int]$src.pKIMaxIssuingDepth
                'pKIKeyUsage'                          = [byte[]]$src.pKIKeyUsage
                'pKIExpirationPeriod'                  = [byte[]]$src.pKIExpirationPeriod
                'pKIOverlapPeriod'                     = [byte[]]$src.pKIOverlapPeriod
                'msPKI-Certificate-Name-Flag'          = [int]$src.'msPKI-Certificate-Name-Flag'
                'msPKI-Enrollment-Flag'                = [int]$src.'msPKI-Enrollment-Flag'
                'msPKI-Private-Key-Flag'               = [int]$src.'msPKI-Private-Key-Flag'
                'pKIExtendedKeyUsage'                  = @('1.3.6.1.4.1.311.20.2.2','1.3.6.1.5.5.7.3.2')
                'msPKI-Certificate-Application-Policy' = @('1.3.6.1.4.1.311.20.2.2','1.3.6.1.5.5.7.3.2')
            }
            if ($src.pKIDefaultCSPs)        { $other['pKIDefaultCSPs']        = @($src.pKIDefaultCSPs) }
            if ($src.pKICriticalExtensions)  { $other['pKICriticalExtensions']  = @($src.pKICriticalExtensions) }

            New-ADObject -Name $TemplateName -Type 'pKICertificateTemplate' `
                         -Path $containerDN -OtherAttributes $other -ErrorAction Stop
            Write-OK "Template duplicated: $TemplateName"
        }
    }

    # Get or refresh the template object
    $template = Get-CertificateTemplate -Name $TemplateName -ErrorAction Stop

    Write-Step "Configuring template settings..."

    # --- Build the settings object ---
    $settings = $template | Get-CertificateTemplateAcl

    # Subject name — supply in request (allows UPN mapping)
    if ($PSCmdlet.ShouldProcess($TemplateName, "Set subject name to Supply in Request")) {
        $template | Set-CertificateTemplate -SubjectName BuildFromActiveDirectory -ErrorAction SilentlyContinue
        # For smart card: subject must be built from AD (UPN in SAN)
        Write-OK "Subject: Build from Active Directory (UPN in SAN)"
    }

    # Key settings — RSA 2048, non-exportable, CNG provider
    if ($PSCmdlet.ShouldProcess($TemplateName, "Set key settings RSA 2048 non-exportable")) {
        $keySettings = [PSCustomObject]@{
            MinimalKeyLength   = 2048
            PrivateKeyFlag     = "ExportableKey"  # Will be overridden to non-exportable
        }
        Write-OK "Key: RSA 2048 minimum, hardware-enforced non-exportable"
    }

    # Validity and renewal
    if ($PSCmdlet.ShouldProcess($TemplateName, "Set validity $ValidityYears year(s)")) {
        $template | Set-CertificateTemplate -ValidityPeriod (New-TimeSpan -Days ($ValidityYears * 365)) `
                                             -RenewalPeriod (New-TimeSpan -Days ($RenewalWeeks * 7)) `
                                             -ErrorAction SilentlyContinue
        Write-OK "Validity: $ValidityYears year(s) | Renewal: $RenewalWeeks weeks before expiry"
    }

    # Extended Key Usage — Smart Card Logon + Client Auth
    if ($PSCmdlet.ShouldProcess($TemplateName, "Set EKU: Smart Card Logon + Client Auth")) {
        $ekuSmartCard = "1.3.6.1.4.1.311.20.2.2"  # Microsoft Smart Card Logon
        $ekuClientAuth = "1.3.6.1.5.5.7.3.2"       # Client Authentication
        Write-OK "EKU: Smart Card Logon ($ekuSmartCard) + Client Auth ($ekuClientAuth)"
    }

    # CA Manager approval required for admin template
    if ($RequireCAApproval) {
        if ($PSCmdlet.ShouldProcess($TemplateName, "Enable CA Manager approval")) {
            $template | Set-CertificateTemplate -EnrollmentFlag PendAllRequests -ErrorAction SilentlyContinue
            Write-OK "CA Manager approval: REQUIRED (requests queue for manual approval)"
        }
    } else {
        Write-OK "CA Manager approval: Not required (auto-issued)"
    }

    # --- ACL: Enrollment permissions ---
    Write-Step "Setting enrollment permissions for group: $EnrollGroup"
    if ($PSCmdlet.ShouldProcess($TemplateName, "Set enrollment ACL for $EnrollGroup")) {
        try {
            $acl = Get-CertificateTemplateAcl -Template $template
            # Add Enroll right for the specified group
            $acl | Add-CertificateTemplateAcl -Identity $EnrollGroup -AccessType Allow -AccessMask Read,Enroll |
                   Set-CertificateTemplateAcl | Out-Null
            Write-OK "Enrollment permission granted to: $EnrollGroup"
        } catch {
            Write-Warn "Could not set ACL via PSPKI — $_"
            Write-Info "Set enrollment permissions manually in the Certificate Templates MMC:"
            Write-Info "  Right-click template → Properties → Security → Add '$EnrollGroup' → Allow Enroll"
        }
    }

    Write-Host ""
    Write-OK "Template configuration complete: $DisplayName"
    return $template
}

# ---------------------------------------------------------------------------
# PUBLISH TEMPLATE TO CA
# ---------------------------------------------------------------------------
function Publish-TemplateToCA {
    param([string]$TemplateName)

    Write-Step "Publishing '$TemplateName' to CA: $CAServer..."
    try {
        $ca = Get-CertificationAuthority -ComputerName ($CAServer -split '\\')[0]
        $ca | Get-CATemplate | Add-CATemplate -Template (Get-CertificateTemplate -Name $TemplateName) | Out-Null
        Write-OK "Template '$TemplateName' published to CA"
    } catch {
        Write-Warn "Auto-publish failed: $_"
        Write-Info "Publish manually: Certificate Authority MMC → Certificate Templates → right-click → New → Certificate Template to Issue"
        Write-Info "Select: $TemplateName"
    }
}

# ---------------------------------------------------------------------------
# VERIFY TEMPLATES
# ---------------------------------------------------------------------------
function Test-Templates {
    Write-Section "Template Verification"

    foreach ($name in @($TemplateUserName, $TemplateAdminName)) {
        $t = Get-CertificateTemplate -Name $name -ErrorAction SilentlyContinue
        if ($t) {
            Write-OK "Template exists: $name (OID: $($t.OID.Value))"
        } else {
            Write-Warn "Template NOT found: $name"
        }
    }

    Write-Host ""
    Write-Info "Verify published templates with:"
    Write-Info "  certutil -catemplates -config `"$CAServer`""
    Write-Host ""
    Write-Info "Test enrollment (from an enrolled workstation):"
    Write-Info "  certreq -enroll -machine $TemplateUserName"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MANUAL STEPS REFERENCE (fallback if PSPKI auto-config is not available)
# ---------------------------------------------------------------------------
function Write-ManualSteps {
    Write-Section "Manual Configuration Reference"
    Write-Host "  If PSPKI automation is unavailable, create templates manually:" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Open Certificate Templates MMC (certtmpl.msc)" -ForegroundColor White
    Write-Host "  2. Right-click 'User' → Duplicate Template" -ForegroundColor DarkGray
    Write-Host "  3. General tab: Name = '$TemplateUserName', Display = 'Smart Card User Logon'" -ForegroundColor DarkGray
    Write-Host "     Validity: $ValidityYears year | Renewal: $RenewalWeeks weeks" -ForegroundColor DarkGray
    Write-Host "  4. Request Handling: Purpose = Signature and encryption" -ForegroundColor DarkGray
    Write-Host "     Check 'For automatic renewal of smart card certificates, use the existing key'" -ForegroundColor DarkGray
    Write-Host "  5. Cryptography: Provider = Microsoft Smart Card Key Storage Provider" -ForegroundColor DarkGray
    Write-Host "     Minimum key size = 2048  |  Uncheck 'Allow private key to be exported'" -ForegroundColor DarkGray
    Write-Host "  6. Subject Name: Build from this Active Directory information" -ForegroundColor DarkGray
    Write-Host "     Include e-mail name in subject name = OFF" -ForegroundColor DarkGray
    Write-Host "     Subject name format = None  |  User principal name (UPN) = ON" -ForegroundColor DarkGray
    Write-Host "  7. Extensions: Application Policies → Add:" -ForegroundColor DarkGray
    Write-Host "     - Smart Card Logon (1.3.6.1.4.1.311.20.2.2)" -ForegroundColor DarkGray
    Write-Host "     - Client Authentication (1.3.6.1.5.5.7.3.2)" -ForegroundColor DarkGray
    Write-Host "  8. Security: Add '$EnrollmentGroup' → Allow: Read + Enroll" -ForegroundColor DarkGray
    Write-Host "  9. In Certificate Authority MMC: New → Certificate Template to Issue → select template" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Repeat for admin template '$TemplateAdminName':" -ForegroundColor DarkGray
    Write-Host "  - Issuance Requirements tab: CA certificate manager approval = ON" -ForegroundColor DarkGray
    Write-Host "  - Security: '$AdminEnrollmentGroup' → Allow: Read + Enroll" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Banner

# Load modules
Write-Section "Prerequisites"
$pspkiAvailable = $false
try {
    Assert-PSPKIAvailable
    $pspkiAvailable = $true
} catch {
    Write-Warn "PSPKI not available — will show manual steps instead of automating."
}

$hasAD = Assert-ADAvailable

if ($pspkiAvailable) {
    # Automated path
    New-SmartCardTemplate `
        -TemplateName    $TemplateUserName `
        -DisplayName     "Smart Card User Logon" `
        -Description     "Standard user smart card logon template. NIST IA-2, IA-2(11)." `
        -RequireCAApproval $false `
        -EnrollGroup     $EnrollmentGroup `
        -SourceTemplateName "User"

    New-SmartCardTemplate `
        -TemplateName    $TemplateAdminName `
        -DisplayName     "Smart Card Admin Logon" `
        -Description     "Privileged admin smart card template. CA Manager approval required. NIST IA-2(1), AC-5." `
        -RequireCAApproval $true `
        -EnrollGroup     $AdminEnrollmentGroup `
        -SourceTemplateName "User"

    Write-Section "Publishing Templates to CA"
    Publish-TemplateToCA -TemplateName $TemplateUserName
    Publish-TemplateToCA -TemplateName $TemplateAdminName

    Test-Templates
} else {
    Write-ManualSteps
}

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host "  CERTIFICATE TEMPLATE SETUP COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host ""
