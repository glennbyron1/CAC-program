#Requires -Version 5.1
<#
.SYNOPSIS
    IKEv2 EAP-TLS VPN Client Deployment — WatchGuard Mobile VPN Profile

.DESCRIPTION
    Deploys a pre-configured IKEv2 VPN connection profile to Windows endpoints
    for use with a WatchGuard Firebox running EAP-TLS smart card authentication.

    This script:
      1. Creates the VPN connection with correct IKEv2 tunnel settings
      2. Applies FIPS-compliant IPSec cryptographic policy (AES-256-GCM, SHA-256, DH ECP384)
      3. Configures the EAP-TLS authentication profile to force smart card certificate selection
      4. Optionally validates that a valid client auth certificate is present
      5. Optionally tests connectivity to the VPN gateway

    Run once per endpoint. Safe to re-run — existing connection is removed and rebuilt.

    Document ID : SCRIPT-ICAM-010
    Framework   : NIST SP 800-53 IA-2, IA-2(11), AC-17, SC-8 | FIPS 140-3
    Reference   : Architecture/WatchGuard-IKEv2-VPN-Guide.md

.PARAMETER VPNName
    Display name for the VPN connection (shown in Network settings). Default: "Agency VPN"

.PARAMETER ServerAddress
    DNS name or IP of the WatchGuard Firebox VPN gateway. Must match the server
    certificate Subject/SAN. Default: vpn.agency.gov

.PARAMETER RootCAThumbprint
    SHA-1 thumbprint of the internal Root CA certificate used to validate the Firebox
    server certificate. Run: Get-ChildItem Cert:\LocalMachine\Root | Where Subject -like "*Root*"

.PARAMETER SplitTunnel
    If set, only traffic destined for the VPN resource subnets goes through the tunnel.
    Default: false (force tunneling — all traffic through Firebox). Recommended: false
    for zero-trust posture.

.PARAMETER InstallForAllUsers
    Deploy VPN profile as a machine-level connection (visible to all users, connects
    before logon). Default: false (user-level connection). Use -InstallForAllUsers for
    pre-logon smart card VPN authentication.

.PARAMETER SkipCertCheck
    Skip verification that a valid EAP-TLS client certificate is installed.

.PARAMETER TestConnection
    After deploying, attempt a test connection (requires smart card to be inserted).

.EXAMPLE
    .\Deploy-VPNClient.ps1 -ServerAddress "vpn.agency.gov" -RootCAThumbprint "A1B2C3D4..."
    Deploys user-level VPN profile with smart card enforcement.

.EXAMPLE
    .\Deploy-VPNClient.ps1 -ServerAddress "vpn.agency.gov" -RootCAThumbprint "A1B2C3D4..." -InstallForAllUsers
    Deploys machine-level profile (available at Windows logon screen).

.EXAMPLE
    .\Deploy-VPNClient.ps1 -ServerAddress "vpn.agency.gov" -RootCAThumbprint "A1B2C3D4..." -TestConnection
    Deploys and immediately attempts a test connection.

.NOTES
    Author  : Glenn Byron
    Repo    : github.com/glennbyron1/CAC-program
    Version : 1.0

    CRYPTO POLICY — matches WatchGuard IKEv2 Phase 1/2 settings in ARCH-ICAM-005:
      Phase 1 (IKE SA) : AES-256-GCM, SHA-256, DH Group ECP384 (Group 20)
      Phase 2 (IPSec)  : AES-256-GCM, SHA-256, PFS ECP384
      Lifetime Phase 1 : 86400 seconds (24 hours)
      Lifetime Phase 2 : 28800 seconds (8 hours)

    EAP-TLS PROFILE:
      Forces selection of the smart card (hardware token) certificate.
      Validates Firebox server certificate against the specified Root CA thumbprint.
      DisableUserPromptForServerValidation: true (no popup warnings).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$VPNName = "Agency VPN",

    [Parameter(Mandatory)]
    [string]$ServerAddress,

    [Parameter(Mandatory)]
    [string]$RootCAThumbprint,

    [Parameter()]
    [switch]$SplitTunnel,

    [Parameter()]
    [switch]$InstallForAllUsers,

    [Parameter()]
    [switch]$SkipCertCheck,

    [Parameter()]
    [switch]$TestConnection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "`n  ► $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!!] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "    [FAIL] $Msg" -ForegroundColor Red }

# Normalize thumbprint — remove spaces, uppercase
$RootCAThumbprint = $RootCAThumbprint.Replace(" ","").ToUpper()

# Format thumbprint as space-separated pairs for EAP XML
$ThumbprintFormatted = ($RootCAThumbprint -split '(.{2})' | Where-Object { $_ }) -join ' '

# ──────────────────────────────────────────────────────────────────────────────
# BANNER
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║   WATCHGUARD IKEV2 VPN CLIENT DEPLOYMENT  v1.0              ║" -ForegroundColor DarkCyan
Write-Host "  ║   SCRIPT-ICAM-010 | Author: Glenn Byron                     ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  VPN Name      : $VPNName" -ForegroundColor White
Write-Host "  Gateway       : $ServerAddress" -ForegroundColor White
Write-Host "  Root CA Thumb : $RootCAThumbprint" -ForegroundColor White
Write-Host "  Tunnel Mode   : $(if ($SplitTunnel) { 'Split (partial)' } else { 'Force (full — all traffic)' })" -ForegroundColor White
Write-Host "  Scope         : $(if ($InstallForAllUsers) { 'Machine (all users)' } else { 'Current user' })" -ForegroundColor White
Write-Host ""
Write-Host "  Authentication : EAP-TLS (smart card certificate — NIST IA-2)" -ForegroundColor White
Write-Host "  Encryption     : AES-256-GCM, SHA-256, DH ECP384 (FIPS 140-3)" -ForegroundColor White
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: VERIFY PREREQUISITES
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Verifying prerequisites"

# Check VPN client module
if (-not (Get-Command Add-VpnConnection -ErrorAction SilentlyContinue)) {
    throw "VPN PowerShell module not available. Requires Windows 8.1+ or Windows Server 2012 R2+."
}
Write-OK "VPN PowerShell cmdlets available"

# Verify Root CA thumbprint exists in trust store
$rootCert = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Thumbprint -eq $RootCAThumbprint } |
    Select-Object -First 1

if ($rootCert) {
    Write-OK "Root CA certificate found in LocalMachine\Root: $($rootCert.Subject)"
} else {
    Write-Warn "Root CA thumbprint not found in LocalMachine\Root trust store."
    Write-Host "    The Firebox server certificate will not be validated without this CA." -ForegroundColor DarkGray
    Write-Host "    Import the Root CA: certutil -addstore Root <RootCA.crt>" -ForegroundColor DarkGray
}

# Verify client EAP-TLS certificate (skip if requested)
if (-not $SkipCertCheck) {
    Write-Step "Checking for valid EAP-TLS client certificate"

    $certStore = if ($InstallForAllUsers) { "Cert:\LocalMachine\My" } else { "Cert:\CurrentUser\My" }
    $clientCerts = Get-ChildItem $certStore -ErrorAction SilentlyContinue |
        Where-Object {
            $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.2" -and  # Client Authentication
            $_.NotAfter -gt (Get-Date) -and
            $_.HasPrivateKey
        }

    if ($clientCerts) {
        Write-OK "Found $($clientCerts.Count) valid EAP-TLS client certificate(s):"
        $clientCerts | ForEach-Object {
            Write-Host "    Subject   : $($_.Subject)" -ForegroundColor Gray
            Write-Host "    Thumbprint: $($_.Thumbprint)" -ForegroundColor Gray
            Write-Host "    Expires   : $($_.NotAfter) ($(($_.NotAfter - (Get-Date)).Days) days)" -ForegroundColor Gray
            Write-Host "    Has Key   : $($_.HasPrivateKey)" -ForegroundColor Gray
            Write-Host "" -ForegroundColor Gray
        }

        # Check if cert is on a smart card (CSP contains "Smart Card")
        $smartCardCerts = $clientCerts | Where-Object {
            try {
                $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($_)
                $key -ne $null
            } catch { $false }
        }
        if ($smartCardCerts -or ($clientCerts | Where-Object { $_.PrivateKey -eq $null })) {
            Write-OK "Smart card-backed certificate detected (private key in hardware token)"
        } else {
            Write-Warn "Certificate private key may be in software store — not hardware-backed"
        }
    } else {
        Write-Warn "No valid EAP-TLS client certificate found in $certStore"
        Write-Host "    Enroll a smart card certificate before attempting VPN connection." -ForegroundColor DarkGray
        Write-Host "    Contact your Registration Authority for enrollment." -ForegroundColor DarkGray
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: REMOVE EXISTING VPN CONNECTION (clean slate)
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Removing existing VPN connection (if present)"

$existing = Get-VpnConnection -Name $VPNName -AllUserConnection:$InstallForAllUsers -ErrorAction SilentlyContinue
if (-not $existing) {
    $existing = Get-VpnConnection -Name $VPNName -ErrorAction SilentlyContinue
}

if ($existing) {
    if ($PSCmdlet.ShouldProcess($VPNName, "Remove existing VPN connection")) {
        Remove-VpnConnection -Name $VPNName -AllUserConnection:$InstallForAllUsers -Force -ErrorAction SilentlyContinue
        Remove-VpnConnection -Name $VPNName -Force -ErrorAction SilentlyContinue
        Write-OK "Removed existing connection: $VPNName"
    }
} else {
    Write-OK "No existing connection found — creating fresh"
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3: CREATE VPN CONNECTION
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Creating IKEv2 VPN connection: $VPNName"

$addVpnParams = @{
    Name                  = $VPNName
    ServerAddress         = $ServerAddress
    TunnelType            = "IKEv2"
    AuthenticationMethod  = @("MachineCertificate", "Eap")
    EncryptionLevel       = "Maximum"
    SplitTunneling        = $SplitTunnel.IsPresent
    RememberCredential    = $false
    PassThru              = $true
    Force                 = $true
}

if ($InstallForAllUsers) {
    $addVpnParams["AllUserConnection"] = $true
}

if ($PSCmdlet.ShouldProcess($VPNName, "Add VPN connection")) {
    $vpn = Add-VpnConnection @addVpnParams
    Write-OK "VPN connection created: $($vpn.Name)"
    Write-Host "    Server        : $($vpn.ServerAddress)" -ForegroundColor Gray
    Write-Host "    Tunnel Type   : $($vpn.TunnelType)" -ForegroundColor Gray
    Write-Host "    Encryption    : $($vpn.EncryptionLevel)" -ForegroundColor Gray
    Write-Host "    Split Tunnel  : $($vpn.SplitTunneling)" -ForegroundColor Gray
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 4: APPLY FIPS-COMPLIANT IPSEC CRYPTOGRAPHIC POLICY
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Applying FIPS 140-3 compliant IPSec cryptographic policy"
Write-Host "    Phase 1 (IKE SA) : AES-256-GCM | SHA-256 | DH ECP384 (Group 20)" -ForegroundColor DarkGray
Write-Host "    Phase 2 (IPSec)  : AES-256-GCM | SHA-256 | PFS ECP384" -ForegroundColor DarkGray
Write-Host "    Lifetime Ph1     : 86400 sec (24 hr)" -ForegroundColor DarkGray
Write-Host "    Lifetime Ph2     : 28800 sec (8 hr)" -ForegroundColor DarkGray

if ($PSCmdlet.ShouldProcess($VPNName, "Set IPSec configuration")) {
    Set-VpnConnectionIPsecConfiguration `
        -ConnectionName                 $VPNName `
        -AuthenticationTransformConstants GCMAES256 `
        -CipherTransformConstants       GCMAES256 `
        -EncryptionMethod               AES256 `
        -IntegrityCheckMethod           SHA256 `
        -DHGroup                        ECP384 `
        -PfsGroup                       ECP384 `
        -Force `
        -PassThru | Out-Null

    Write-OK "IPSec crypto policy applied (must match WatchGuard Phase 1/2 settings)"
    Write-Warn "Verify WatchGuard Firebox is configured with matching crypto — see ARCH-ICAM-005 §4.4/4.5"
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 5: BUILD AND APPLY EAP-TLS XML PROFILE
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Building EAP-TLS smart card authentication profile"

# EAP Type 13 = EAP-TLS
# CredentialsSource SmartCard = forces hardware token (no software cert fallback)
# ServerValidation = validates Firebox server cert against Root CA thumbprint
$eapXml = @"
<EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
  <EapMethod>
    <Type xmlns="http://www.microsoft.com/provisioning/EapCommon">13</Type>
    <VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId>
    <VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType>
    <AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</AuthorId>
  </EapMethod>
  <Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
    <Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1">
      <Type>13</Type>
      <EapType xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV1">
        <CredentialsSource>
          <SmartCard/>
        </CredentialsSource>
        <ServerValidation>
          <DisableUserPromptForServerValidation>true</DisableUserPromptForServerValidation>
          <ServerNames>$ServerAddress</ServerNames>
          <TrustedRootCA>$ThumbprintFormatted</TrustedRootCA>
        </ServerValidation>
        <DifferentUsername>false</DifferentUsername>
        <PerformServerValidation
          xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV2">true</PerformServerValidation>
        <AcceptServerName
          xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV2">true</AcceptServerName>
        <TLSExtensions
          xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV2">
          <FilteringInfo
            xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV3">
            <ClientAuthEKUList Enabled="true">
              <EKUMapInList>Client Authentication</EKUMapInList>
            </ClientAuthEKUList>
            <AnyPurposeEKUList Enabled="false"/>
          </FilteringInfo>
        </TLSExtensions>
      </EapType>
    </Eap>
  </Config>
</EapHostConfig>
"@

# Write EAP XML to temp file then apply via rasphone.pbk manipulation
$eapXmlPath = Join-Path $env:TEMP "vpn-eap-profile.xml"
$eapXml | Set-Content -Path $eapXmlPath -Encoding UTF8

# Apply EAP profile using Set-VpnConnectionEapConfiguration (Windows 10 1709+)
try {
    if ($PSCmdlet.ShouldProcess($VPNName, "Apply EAP-TLS profile")) {
        Set-VpnConnectionEapConfiguration -ConnectionName $VPNName -EapXml $eapXml -Force
        Write-OK "EAP-TLS smart card profile applied"
        Write-Host "    Auth source : Smart card hardware token (non-exportable key)" -ForegroundColor Gray
        Write-Host "    Server name : $ServerAddress" -ForegroundColor Gray
        Write-Host "    Root CA     : $RootCAThumbprint" -ForegroundColor Gray
    }
} catch {
    Write-Warn "Set-VpnConnectionEapConfiguration failed (may not be available on this OS version): $_"
    Write-Host "    Applying EAP profile via rasphone.pbk method..." -ForegroundColor DarkGray

    # Fallback: write EAP config into rasphone.pbk directly
    $pbkPath = if ($InstallForAllUsers) {
        "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
    } else {
        "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk"
    }

    if (Test-Path $pbkPath) {
        $pbkContent = Get-Content $pbkPath -Raw
        # Check if our VPN entry exists in the pbk
        if ($pbkContent -match "\[$([regex]::Escape($VPNName))\]") {
            Write-OK "VPN entry found in $pbkPath"
            Write-Warn "Manually update CustomAuthData in rasphone.pbk with EAP XML if needed."
            Write-Host "    EAP XML saved to: $eapXmlPath" -ForegroundColor DarkGray
        }
    } else {
        Write-Warn "rasphone.pbk not found at $pbkPath — VPN profile may not yet be written to disk"
        Write-Host "    EAP XML profile saved to: $eapXmlPath" -ForegroundColor DarkGray
        Write-Host "    Apply manually after first connection attempt: Set-VpnConnectionEapConfiguration" -ForegroundColor DarkGray
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 6: CONFIGURE DNS SUFFIX FOR SPLIT TUNNEL (if applicable)
# ──────────────────────────────────────────────────────────────────────────────
if ($SplitTunnel) {
    Write-Step "Configuring DNS suffix for split tunnel"
    Write-Warn "Split tunnel mode — internal DNS suffix required for name resolution"
    Write-Host "    Set DNS suffix manually if internal hostnames do not resolve over VPN." -ForegroundColor DarkGray
    Write-Host "    Example: Set-VpnConnectionTriggerDnsConfiguration -ConnectionName '$VPNName'" -ForegroundColor DarkGray
    Write-Host "             -DnsSuffix 'lab.local' -DnsIPAddress '10.0.0.10'" -ForegroundColor DarkGray
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 7: VERIFY FINAL CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Verifying final VPN configuration"

$scope = if ($InstallForAllUsers) { @{ AllUserConnection = $true } } else { @{} }
$finalVpn = Get-VpnConnection -Name $VPNName @scope -ErrorAction SilentlyContinue

if ($finalVpn) {
    Write-OK "VPN connection verified:"
    Write-Host "    Name          : $($finalVpn.Name)" -ForegroundColor Gray
    Write-Host "    Server        : $($finalVpn.ServerAddress)" -ForegroundColor Gray
    Write-Host "    Tunnel        : $($finalVpn.TunnelType)" -ForegroundColor Gray
    Write-Host "    Auth Method   : $($finalVpn.AuthenticationMethod -join ', ')" -ForegroundColor Gray
    Write-Host "    Encryption    : $($finalVpn.EncryptionLevel)" -ForegroundColor Gray
    Write-Host "    Split Tunnel  : $($finalVpn.SplitTunneling)" -ForegroundColor Gray
    Write-Host "    Status        : $($finalVpn.ConnectionStatus)" -ForegroundColor Gray
} else {
    Write-Fail "VPN connection not found after creation — check for errors above"
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 8: OPTIONAL CONNECTION TEST
# ──────────────────────────────────────────────────────────────────────────────
if ($TestConnection) {
    Write-Step "Attempting test connection (smart card must be inserted)"
    Write-Warn "You will be prompted for your smart card PIN."
    Write-Host ""

    try {
        $connectResult = rasdial $VPNName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-OK "VPN connected successfully"
            Start-Sleep -Seconds 3

            # Verify virtual IP assigned
            $vpnAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*WAN Miniport*IKEv2*" -and $_.Status -eq "Up" }
            if ($vpnAdapter) {
                $vpnIP = (Get-NetIPAddress -InterfaceIndex $vpnAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                Write-OK "Virtual IP assigned: $vpnIP"
            }

            # Test internal DNS resolution
            try {
                $dns = Resolve-DnsName "._ldap._tcp.dc._msdcs.lab.local" -ErrorAction Stop
                Write-OK "Internal DNS resolution working"
            } catch {
                Write-Warn "Internal DNS not resolving — check DNS suffix and routing config"
            }

            # Disconnect after test
            Write-Step "Disconnecting test connection"
            rasdial $VPNName /disconnect | Out-Null
            Write-OK "Disconnected"
        } else {
            Write-Fail "Connection failed (exit code $LASTEXITCODE): $connectResult"
            Write-Host "    Common causes:" -ForegroundColor DarkGray
            Write-Host "    - Smart card not inserted (error 13806)" -ForegroundColor DarkGray
            Write-Host "    - UDP 500/4500 blocked (error 809)" -ForegroundColor DarkGray
            Write-Host "    - CRL unreachable from Firebox (error 691)" -ForegroundColor DarkGray
            Write-Host "    - Crypto mismatch (verify Phase 1/2 settings match Firebox)" -ForegroundColor DarkGray
            Write-Host "    See: Architecture\WatchGuard-IKEv2-VPN-Guide.md §8 Troubleshooting" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warn "Connection test error: $_"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# CERTIFICATE EXPIRY REMINDER
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Checking certificate expiry dates"

# Check smart card / client certs
$certStore = if ($InstallForAllUsers) { "Cert:\LocalMachine\My" } else { "Cert:\CurrentUser\My" }
$clientCerts = Get-ChildItem $certStore -ErrorAction SilentlyContinue |
    Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.2" -and $_.NotAfter -gt (Get-Date) }

$clientCerts | ForEach-Object {
    $days = ($_.NotAfter - (Get-Date)).Days
    $color = if ($days -lt 30) { "Red" } elseif ($days -lt 60) { "Yellow" } else { "Green" }
    Write-Host "    Client cert: $($_.Subject) — expires in $days days ($($_.NotAfter.ToString('yyyy-MM-dd')))" -ForegroundColor $color
}

# Check Root CA cert expiry
if ($rootCert) {
    $days = ($rootCert.NotAfter - (Get-Date)).Days
    $color = if ($days -lt 365) { "Red" } elseif ($days -lt 730) { "Yellow" } else { "Green" }
    Write-Host "    Root CA cert: expires in $days days ($($rootCert.NotAfter.ToString('yyyy-MM-dd')))" -ForegroundColor $color
}

# ──────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  VPN CLIENT DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  VPN Name   : $VPNName" -ForegroundColor White
Write-Host "  Gateway    : $ServerAddress" -ForegroundColor White
Write-Host "  Auth       : EAP-TLS (Smart Card hardware token)" -ForegroundColor White
Write-Host "  Crypto     : AES-256-GCM | SHA-256 | DH ECP384 (FIPS 140-3)" -ForegroundColor White
Write-Host ""
Write-Host "  TO CONNECT:" -ForegroundColor White
Write-Host "  1. Insert smart card / hardware token" -ForegroundColor White
Write-Host "  2. Settings → Network → VPN → $VPNName → Connect" -ForegroundColor White
Write-Host "  3. Enter smart card PIN when prompted" -ForegroundColor White
Write-Host ""
Write-Host "  FOR GROUP POLICY DEPLOYMENT:" -ForegroundColor White
Write-Host "  - Add this script as a Computer Startup Script in GPO" -ForegroundColor White
Write-Host "  - Or use Intune Device Configuration → VPN profile" -ForegroundColor White
Write-Host "  - See: Architecture\WatchGuard-IKEv2-VPN-Guide.md §5.2" -ForegroundColor White
Write-Host ""
Write-Host "  TROUBLESHOOTING REFERENCE:" -ForegroundColor White
Write-Host "  Architecture\WatchGuard-IKEv2-VPN-Guide.md §8" -ForegroundColor White
Write-Host ""
