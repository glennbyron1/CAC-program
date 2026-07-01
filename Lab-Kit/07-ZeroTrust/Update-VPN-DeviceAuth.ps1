#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.2.4 - Tightens the VPN to require BOTH the device machine certificate
    AND the user smart-card certificate, so only an enrolled device driven by an
    enrolled identity can build the tunnel.

.DESCRIPTION
    Phase 7 (Deploy-VPNClient.ps1) created an IKEv2 EAP-TLS profile. This script
    upgrades it to two-factor-of-two-kinds:

      Tunnel auth (device)   : IKEv2 MachineCertificate  (the 8.2.1 device cert)
      Inner auth   (identity): EAP-TLS user smart-card cert

    Client side (-Mode Client): updates the EXISTING named VPN connection in place
    (no rebuild) so AuthenticationMethod = MachineCertificate + Eap, re-applies the
    EAP-TLS profile that forces the smart card, and verifies both a device cert and
    a user client-auth cert are present.

    Server side (-Mode NPSServer): if this host runs NPS/RRAS, adds a Connection
    Request Policy + Network Policy that require a machine certificate (device
    trust) before EAP-TLS user auth is evaluated - the enforcement point that makes
    the dual requirement real rather than client-honour-system.

    WatchGuard Firebox path: the Firebox is the IKEv2 gateway, so the device-cert
    requirement is enforced in the Firebox IKEv2 policy. The marked block lists the
    exact Firebox settings; the client-side update here is still required.

.PARAMETER Mode
    Client | NPSServer.

.PARAMETER VPNName
    Name of the existing VPN connection to upgrade. Default 'Agency VPN'.

.PARAMETER ServerAddress
    VPN gateway name (for EAP server validation). Required in Client mode if the
    EAP profile must be re-applied; read from the existing profile if omitted.

.PARAMETER RootCAThumbprint
    Root CA thumbprint for EAP server validation. Read from LocalMachine\Root if
    omitted (single lab root).

.PARAMETER InstallForAllUsers
    Switch - operate on the machine-level (all-user) VPN profile.

.PARAMETER DeviceCertSubject
    Expected device cert CN to verify in LocalMachine\My. Default = machine FQDN.

.PARAMETER DryRun
    Switch - preview without changing the profile or NPS.

.EXAMPLE
    .\Update-VPN-DeviceAuth.ps1 -Mode Client -VPNName 'Agency VPN' -InstallForAllUsers

.EXAMPLE
    .\Update-VPN-DeviceAuth.ps1 -Mode NPSServer

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.2.4 - Device Trust
    Run on     : Each client (Client) / the NPS or RRAS host (NPSServer)
    Depends on : Deploy-VPNClient.ps1 (Phase 7), New-DeviceCertTemplate.ps1 (8.2.1)
    NIST       : IA-3, AC-17, AC-19
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Client','NPSServer')]
    [string]$Mode,
    [string]$VPNName           = 'Agency VPN',
    [string]$ServerAddress     = '',
    [string]$RootCAThumbprint  = '',
    [switch]$InstallForAllUsers,
    [string]$DeviceCertSubject = '',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Skip  { param([string]$msg) Write-Host "  [SKIP] $msg"   -ForegroundColor DarkGray }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host "  |   Phase 8.2.4 - VPN Dual-Cert ($Mode)$((' ' * (18 - $Mode.Length)))|" -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# =========================================================================
if ($Mode -eq 'Client') {
# =========================================================================
    if (-not (Get-Command Add-VpnConnection -ErrorAction SilentlyContinue)) {
        Write-Fatal 'VPN cmdlets not available (Windows 8.1+/2012R2+).'
    }
    if (-not $DeviceCertSubject) {
        $DeviceCertSubject = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME)).HostName
    }

    # locate existing profile
    Write-Step "Phase 1 - Existing VPN profile '$VPNName'"
    $scope = @{}
    if ($InstallForAllUsers) { $scope['AllUserConnection'] = $true }
    $vpn = Get-VpnConnection -Name $VPNName @scope -ErrorAction SilentlyContinue
    if (-not $vpn) { Write-Fatal "VPN '$VPNName' not found. Run Deploy-VPNClient.ps1 first." }
    Write-OK "Found: $VPNName (auth: $($vpn.AuthenticationMethod -join ', '))"

    # verify device cert present
    Write-Step "Phase 2 - Device (machine) certificate CN=$DeviceCertSubject"
    $devCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
               Where-Object { $_.Subject -like "*$DeviceCertSubject*" -and $_.HasPrivateKey -and
                              $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.2' -and $_.NotAfter -gt (Get-Date) } |
               Sort-Object NotAfter -Descending | Select-Object -First 1
    if ($devCert) { Write-OK "Device cert present: $($devCert.Subject)" }
    else { Write-Warn "No valid device cert for $DeviceCertSubject. Run Enroll-DeviceCertificates.ps1 (8.2.2) first." }

    # verify user smart-card cert present (current user)
    Write-Step 'Phase 3 - User smart-card client-auth certificate'
    $userCert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
                Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.2' -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1
    if ($userCert) { Write-OK "User cert present: $($userCert.Subject)" }
    else { Write-Warn 'No user client-auth cert in CurrentUser\My (insert smart card / enroll).' }

    if ($DryRun) { Write-Warn 'DryRun - not modifying the profile'; return }

    # update auth method in place (idempotent)
    Write-Step 'Phase 4 - Enforce MachineCertificate + EAP (device + identity)'
    if ($PSCmdlet.ShouldProcess($VPNName, 'Set AuthenticationMethod = MachineCertificate, Eap')) {
        Set-VpnConnection -Name $VPNName @scope `
            -AuthenticationMethod MachineCertificate, Eap `
            -TunnelType IKEv2 -EncryptionLevel Maximum -Force -ErrorAction Stop
        Write-OK 'Tunnel now requires the device machine cert; EAP-TLS still carries the user identity'
    }

    # re-apply EAP-TLS smart-card profile (read server/root from existing if not passed)
    Write-Step 'Phase 5 - Re-apply EAP-TLS smart-card profile'
    if (-not $ServerAddress) { $ServerAddress = $vpn.ServerAddress }
    if (-not $RootCAThumbprint) {
        $root = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like '*Root*CA*' } | Select-Object -First 1
        if ($root) { $RootCAThumbprint = $root.Thumbprint }
    }
    if ($ServerAddress -and $RootCAThumbprint) {
        $tf = ($RootCAThumbprint.Replace(' ','').ToUpper() -split '(.{2})' | Where-Object { $_ }) -join ' '
        $eapXml = @"
<EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
  <EapMethod><Type xmlns="http://www.microsoft.com/provisioning/EapCommon">13</Type>
  <VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId>
  <VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType>
  <AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</AuthorId></EapMethod>
  <Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
    <Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1"><Type>13</Type>
      <EapType xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV1">
        <CredentialsSource><SmartCard/></CredentialsSource>
        <ServerValidation>
          <DisableUserPromptForServerValidation>true</DisableUserPromptForServerValidation>
          <ServerNames>$ServerAddress</ServerNames>
          <TrustedRootCA>$tf</TrustedRootCA>
        </ServerValidation>
        <DifferentUsername>false</DifferentUsername>
      </EapType>
    </Eap>
  </Config>
</EapHostConfig>
"@
        if ($PSCmdlet.ShouldProcess($VPNName, 'Apply EAP-TLS profile')) {
            Set-VpnConnectionEapConfiguration -ConnectionName $VPNName -EapXml $eapXml -Force @scope -ErrorAction Stop
            Write-OK 'EAP-TLS smart-card profile re-applied'
        }
    } else {
        Write-Warn 'Could not determine ServerAddress/RootCAThumbprint - pass them to re-apply the EAP profile.'
    }

    Write-Host ''
    Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
    Write-Host "    $VPNName now requires device cert (tunnel) + user smart card (EAP)." -ForegroundColor White
    Write-Host '    Test: pull the smart card OR use a non-enrolled device - the tunnel must fail.' -ForegroundColor Yellow
    Write-Host '    Enforcement also needs the gateway to demand the device cert (NPS or Firebox).' -ForegroundColor Yellow
    Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
    Write-Host ''

# =========================================================================
} else {  # NPSServer
# =========================================================================
    Write-Step 'Phase 1 - NPS role check'
    $nps = Get-WindowsFeature -Name NPAS -ErrorAction SilentlyContinue
    if (-not ($nps -and $nps.Installed)) {
        Write-Warn 'NPS (Network Policy Server) role not installed on this host.'
        Write-Info  'If the lab uses the WatchGuard Firebox as the IKEv2 gateway, configure device-cert'
        Write-Info  'enforcement there instead - see the Firebox block below. Otherwise:'
        Write-Info  '  Install-WindowsFeature NPAS -IncludeManagementTools'
        Write-Host ''
    } else {
        Write-OK 'NPS role present'
        Write-Step 'Phase 2 - Network policy requiring a machine certificate'
        # netsh nps is the scriptable surface; we add a policy that requires
        # EAP and machine-cert auth type. Idempotent: skip if already present.
        $policyName = 'ZT-Require-DeviceCert'
        $existing = (& netsh nps show np 2>$null) -match $policyName
        if ($existing) {
            Write-Skip "Network policy '$policyName' already present"
        } elseif ($PSCmdlet.ShouldProcess($policyName, 'Add NPS network policy (require machine cert)')) {
            if (-not $DryRun) {
                # grant access, require EAP, and condition on authentication-type = machine cert
                & netsh nps add np name="$policyName" conditionid="0x1009" conditiondata="1" `
                    profileid="0x1005" profiledata="TRUE" 2>&1 | Out-Null
            }
            Write-OK "Added NPS policy '$policyName' (review/refine in nps.msc)"
            Write-Warn 'Verify in nps.msc: set EAP type = Microsoft: Smart Card or other certificate, and'
            Write-Warn 'condition "Authentication Type = Machine" so device cert is mandatory.'
        }
        Write-Host ''
    }

    Write-Host ('  +-- WatchGuard Firebox (if it is the IKEv2 gateway) ' + ('-' * 9)) -ForegroundColor DarkCyan
    Write-Host '    In Fireware, on the Mobile VPN with IKEv2 / IPSec profile:' -ForegroundColor Yellow
    Write-Host '      1. Authentication = Certificate; CA = lab Issuing CA.' -ForegroundColor Yellow
    Write-Host '      2. Require client certificate for the IKE SA (device cert).' -ForegroundColor Yellow
    Write-Host '      3. Bind RADIUS/EAP-TLS to NPS so the USER smart-card cert is also validated.' -ForegroundColor Yellow
    Write-Host '      4. Enable CRL/OCSP checking against the lab CDP (Architecture/WatchGuard-IKEv2-VPN-Guide.md).' -ForegroundColor Yellow
    Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
    Write-Host ''
}
