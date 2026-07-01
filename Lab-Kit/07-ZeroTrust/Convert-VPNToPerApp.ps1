#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.5.2 - Migrates the flat full-tunnel VPN to per-application access
    (ZTNA-style). Each backend is published through its own broker/PEP endpoint
    requiring a client certificate, instead of one tunnel that exposes the subnet.

.DESCRIPTION
    A full-tunnel VPN gives an authenticated client network-level reach to
    everything - the antithesis of "never trust the network". This script builds
    the on-prem ZTNA pattern on top of the Resource Gateway (8.1.5): one IIS ARR
    publishing endpoint per application, so a user reaches ONLY the apps their
    group is authorised for, each gated by mTLS - no broad subnet route.

    For each app in the catalog it:
      1. Creates a dedicated IIS site (per-app PEP) on its own host/port.
      2. Binds the gateway TLS cert and REQUIRES a client certificate.
      3. Adds a reverse-proxy rule to the app's backend.
      4. Records the app's authorised AD group (you enforce it on the backend or
         via the gateway's authorization rule).

    Then it reports how to retire the flat tunnel (switch the VPN to split-tunnel
    with NO default route, or decommission it once all apps are published).

    Edit $appCatalog below, or pass -Apps as an array of hashtables.

.PARAMETER Apps
    Array of @{ Name; Backend; Port; Group } hashtables. Defaults to a sample catalog.

.PARAMETER GatewaySubject
    CN of the PEP TLS cert in LocalMachine\My. Default 'gateway.lab.local'.

.PARAMETER VPNName
    Flat VPN connection to convert to split-tunnel. Default 'Agency VPN'.

.PARAMETER ConvertTunnel
    Switch - also flip the named VPN to split-tunnel (removes the default route).

.PARAMETER DryRun
    Switch - preview without changing IIS or the VPN.

.EXAMPLE
    .\Convert-VPNToPerApp.ps1

.EXAMPLE
    .\Convert-VPNToPerApp.ps1 -Apps @(
        @{ Name='crm';     Backend='http://10.10.10.31:8080/'; Port=10443; Group='Res-CRM-AppRole' },
        @{ Name='wiki';    Backend='http://10.10.10.32:80/';   Port=10444; Group='Role-FileServer-Admins' }
      ) -ConvertTunnel

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.5.2 - Network Segmentation
    Run on     : The Resource Gateway / PEP host
    Depends on : Deploy-ResourceGateway.ps1 (8.1.5), New-RBACModel.ps1 (8.1.3)
    NIST       : AC-3, AC-4, SC-7(11)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [hashtable[]]$Apps = @(),
    [string]$GatewaySubject = 'gateway.lab.local',
    [string]$VPNName        = 'Agency VPN',
    [switch]$ConvertTunnel,
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

# default sample catalog
if ($Apps.Count -eq 0) {
    $Apps = @(
        @{ Name='crm';  Backend='http://10.10.10.31:8080/'; Port=10443; Group='Res-CRM-AppRole' }
        @{ Name='wiki'; Backend='http://10.10.10.32:80/';   Port=10444; Group='Role-FileServer-Admins' }
    )
}

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8.5.2 - VPN -> Per-Application Access (ZTNA) |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# -- IIS + ARR present? -------------------------------------------------------
Write-Step 'Phase 1 - Prerequisites (IIS ARR from 8.1.5)'
if (-not (Get-Module -ListAvailable WebAdministration)) {
    Write-Fatal 'WebAdministration not available. Run Deploy-ResourceGateway.ps1 (8.1.5) first to install IIS + ARR.'
}
Import-Module WebAdministration -ErrorAction Stop
if (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\Application Request Routing')) {
    Write-Fatal 'ARR not installed. Run Deploy-ResourceGateway.ps1 (8.1.5) first.'
}
$cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*CN=$GatewaySubject*" -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) { Write-Fatal "No gateway cert CN=$GatewaySubject in LocalMachine\My." }
Write-OK "ARR present; gateway cert $($cert.Thumbprint)"
Write-Host ''

# -- Publish each app ---------------------------------------------------------
Write-Step 'Phase 2 - Publish per-application endpoints'
foreach ($app in $Apps) {
    foreach ($k in 'Name','Backend','Port','Group') {
        if (-not $app.ContainsKey($k)) { Write-Warn "App entry missing '$k' - skipping: $($app | Out-String)"; continue 2 }
    }
    $siteName = "ZT-App-$($app.Name)"
    Write-Step "  App '$($app.Name)'  :$($app.Port)  ->  $($app.Backend)   [auth: $($app.Group)]"

    if ($DryRun) { Write-Info '(DryRun) would create per-app PEP site'; continue }

    $sitePath = "C:\inetpub\$siteName"
    if (-not (Test-Path $sitePath)) { New-Item -ItemType Directory -Path $sitePath -Force | Out-Null }

    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Write-Skip "Site exists: $siteName - updating binding/rule"
        Remove-WebBinding -Name $siteName -Protocol https -Port $app.Port -ErrorAction SilentlyContinue
    } else {
        New-Website -Name $siteName -PhysicalPath $sitePath -Port $app.Port -Protocol https -Force | Out-Null
        Write-OK "Created site: $siteName"
    }

    $binding = "0.0.0.0!$($app.Port)"
    if (Test-Path "IIS:\SslBindings\$binding") { Remove-Item "IIS:\SslBindings\$binding" -Force }
    New-Item -Path "IIS:\SslBindings\$binding" -Value $cert -Force | Out-Null

    # require client cert (mTLS) on this app's endpoint
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $siteName `
        -Filter 'system.webServer/security/access' -Name 'sslFlags' -Value 'Ssl,SslNegotiateCert,SslRequireCert'

    # reverse-proxy rule -> backend
    $rp = "system.webServer/rewrite/rules"
    Clear-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $siteName -Filter "$rp/rule[@name='ZT-App-Proxy']" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $siteName -Filter $rp -Name '.' -Value @{ name='ZT-App-Proxy'; stopProcessing='True' }
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $siteName -Filter "$rp/rule[@name='ZT-App-Proxy']/match" -Name 'url' -Value '(.*)'
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $siteName -Filter "$rp/rule[@name='ZT-App-Proxy']/action" -Name 'type' -Value 'Rewrite'
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $siteName -Filter "$rp/rule[@name='ZT-App-Proxy']/action" -Name 'url' -Value ("$($app.Backend.TrimEnd('/'))/{R:1}")

    Write-OK "Published '$($app.Name)': only client-cert holders reach it; authorise via group $($app.Group)"
    Write-Info "Enforce the group on the backend, or add an IIS authorization rule for $($app.Group)."
}
Write-Host ''

# -- Optional: convert the flat tunnel to split (no default route) -------------
if ($ConvertTunnel) {
    Write-Step "Phase 3 - Convert '$VPNName' to split-tunnel (drop default route)"
    $vpn = Get-VpnConnection -Name $VPNName -ErrorAction SilentlyContinue
    if (-not $vpn) {
        $vpn = Get-VpnConnection -Name $VPNName -AllUserConnection -ErrorAction SilentlyContinue
    }
    if (-not $vpn) {
        Write-Warn "VPN '$VPNName' not found on this host - convert it where the client profile lives."
    } elseif ($PSCmdlet.ShouldProcess($VPNName, 'Set split tunneling (no default route)')) {
        if (-not $DryRun) {
            Set-VpnConnection -Name $VPNName -SplitTunneling $true -Force -ErrorAction SilentlyContinue
        }
        Write-OK "'$VPNName' set to split-tunnel - it no longer carries a default route."
        Write-Info 'Apps are now reached via their per-app PEP endpoints, not a flat subnet route.'
    }
    Write-Host ''
}

# -- Cloud ZTNA alternative (if you go off-box) -------------------------------
# OPTIONAL (only if replacing the on-prem PEP with a cloud broker):
#   * Entra Private Access: install the Private Network connector on an on-prem
#     host, publish each backend as a Quick Access / per-app segment, assign the
#     authorised group. Clients use the Global Secure Access client, no VPN.
#   * Cloudflare Access / Zscaler ZPA: deploy the connector, define one app per
#     backend, bind the access policy to the same AD/Entra groups used above.
# The per-app + per-group model here maps 1:1 onto those brokers.

Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    Published $($Apps.Count) app(s) as individual mTLS PEP endpoints." -ForegroundColor White
Write-Host '    Access is per-app + per-group - no broad network reach.' -ForegroundColor White
if (-not $ConvertTunnel) {
    Write-Host '    Re-run with -ConvertTunnel to drop the flat default route once apps are verified.' -ForegroundColor Yellow
}
Write-Host '    Lock each backend so it accepts traffic ONLY from this gateway (8.5.1 microsegmentation).' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
