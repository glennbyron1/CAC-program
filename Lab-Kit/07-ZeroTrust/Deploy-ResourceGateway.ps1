#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.1.5 - Stands up a reverse-proxy Policy Enforcement Point (PEP) in
    front of a protected backend. The PEP authenticates the caller with a lab
    smart-card / client certificate, then proxies the request to the backend.

.DESCRIPTION
    Implements the PEP with IIS + Application Request Routing (ARR) + URL Rewrite -
    the no-license reverse proxy that ships from Microsoft. Result:

        client (smart card)  --mTLS-->  IIS PEP  --http-->  backend service

    The PEP terminates TLS, REQUIRES a client certificate chaining to the lab
    Issuing CA (so only enrolled identities reach the backend), and forwards the
    request. The backend never sees unauthenticated traffic and can live on an
    isolated segment reachable only from the PEP.

    Steps:
      1. Ensure IIS + URL Rewrite + ARR are present (ARR/Rewrite are downloaded if
         missing and internet is available; otherwise the script tells you the
         offline installer to stage).
      2. Enable ARR proxy at the server level.
      3. Create the PEP site bound to HTTPS with the gateway cert (-GatewaySubject).
      4. Require a client certificate (SslRequireCert).
      5. Write a reverse-proxy rewrite rule to -BackendUrl and forward the client
         cert subject to the backend as a header (X-Client-Cert-Subject).

    Re-running updates the rule/binding in place.

.PARAMETER SiteName
    PEP site name. Default 'ZT-ResourceGateway'.

.PARAMETER ListenPort
    HTTPS port the PEP listens on. Default 443.

.PARAMETER GatewaySubject
    CN of the PEP's server cert in LocalMachine\My. Default 'gateway.lab.local'.

.PARAMETER BackendUrl
    The backend the PEP proxies to. Default 'http://10.10.10.30:80/'.

.PARAMETER DryRun
    Switch - preview without changing IIS.

.EXAMPLE
    .\Deploy-ResourceGateway.ps1 -BackendUrl http://app01.lab.local:8080/

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.1.5 - Authorization & Least Privilege
    Run on     : Hyper-V host or a dedicated PEP VM
    Depends on : Issuing CA (gateway TLS cert), a backend service
    NIST       : AC-3, AC-4, SC-7(3)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SiteName       = 'ZT-ResourceGateway',
    [int]   $ListenPort     = 443,
    [string]$GatewaySubject = 'gateway.lab.local',
    [string]$BackendUrl     = 'http://10.10.10.30:80/',
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
Write-Host '  |   Phase 8.1.5 - Resource Gateway (IIS ARR PEP)      |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# -- Step 1: IIS --------------------------------------------------------------
Write-Step 'Phase 1 - IIS web server role'
$feat = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if ($feat -and $feat.Installed) {
    Write-Skip 'Web-Server already installed'
} elseif ($PSCmdlet.ShouldProcess('Web-Server', 'Install')) {
    if (-not $DryRun) { Install-WindowsFeature -Name Web-Server, Web-Http-Redirect -IncludeManagementTools | Out-Null }
    Write-OK 'Installed IIS'
}
Import-Module WebAdministration -ErrorAction Stop

# -- Step 2: URL Rewrite + ARR ------------------------------------------------
Write-Step 'Phase 2 - URL Rewrite + Application Request Routing'
$arrInstalled = Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\Application Request Routing'
$rewriteInstalled = Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite'

if ($arrInstalled -and $rewriteInstalled) {
    Write-Skip 'ARR + URL Rewrite already installed'
} else {
    $downloads = @(
        @{ Name='URL Rewrite'; Need=(-not $rewriteInstalled); Url='https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi' }
        @{ Name='ARR 3.0';     Need=(-not $arrInstalled);     Url='https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi' }
    )
    foreach ($d in ($downloads | Where-Object Need)) {
        if ($PSCmdlet.ShouldProcess($d.Name, 'Download + install MSI')) {
            if (-not $DryRun) {
                try {
                    $msi = Join-Path $env:TEMP ("$($d.Name -replace '\W','')_$([guid]::NewGuid().ToString('N').Substring(0,6)).msi")
                    Write-Info "Downloading $($d.Name)..."
                    Invoke-WebRequest -Uri $d.Url -OutFile $msi -UseBasicParsing
                    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
                    Remove-Item $msi -Force -ErrorAction SilentlyContinue
                    Write-OK "Installed $($d.Name)"
                } catch {
                    Write-Fatal "Could not install $($d.Name) automatically ($($_.Exception.Message.Split([char]10)[0])).
       Stage it offline from https://www.iis.net/downloads/microsoft/application-request-routing and re-run."
                }
            }
        }
    }
}

if ($DryRun) { Write-Warn 'DryRun - stopping before proxy/site config'; return }

# Enable ARR proxy at server level
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
    -Filter 'system.webServer/proxy' -Name 'enabled' -Value 'True' -ErrorAction SilentlyContinue
Write-OK 'ARR server proxy enabled'
Write-Host ''

# -- Step 3: gateway cert + site ----------------------------------------------
Write-Step "Phase 3 - PEP site (cert CN=$GatewaySubject, :$ListenPort)"
$cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*CN=$GatewaySubject*" -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) {
    Write-Fatal "No private-key cert CN=$GatewaySubject in LocalMachine\My. Enroll a Web Server cert from the lab CA first."
}
Write-OK "Gateway cert: $($cert.Subject)  (thumb $($cert.Thumbprint))"

$sitePath = "C:\inetpub\$SiteName"
if (-not (Test-Path $sitePath)) { New-Item -ItemType Directory -Path $sitePath -Force | Out-Null }

if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
    Write-Skip "Site '$SiteName' exists - updating"
    Remove-WebBinding -Name $SiteName -Protocol https -Port $ListenPort -ErrorAction SilentlyContinue
} else {
    New-Website -Name $SiteName -PhysicalPath $sitePath -Port $ListenPort -Protocol https -Force | Out-Null
    Write-OK "Created site '$SiteName'"
}

$binding = "0.0.0.0!$ListenPort"
if (Test-Path "IIS:\SslBindings\$binding") { Remove-Item "IIS:\SslBindings\$binding" -Force }
New-Item -Path "IIS:\SslBindings\$binding" -Value $cert -Force | Out-Null
Write-OK "Bound gateway cert to :$ListenPort"

# -- Step 4: require client cert ----------------------------------------------
Write-Step 'Phase 4 - Require client certificate (mutual TLS at the PEP)'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName `
    -Filter 'system.webServer/security/access' -Name 'sslFlags' -Value 'Ssl,SslNegotiateCert,SslRequireCert'
Write-OK 'Client certificate REQUIRED'
Write-Host ''

# -- Step 5: reverse-proxy rule -----------------------------------------------
Write-Step "Phase 5 - Reverse-proxy rule -> $BackendUrl"
$rulePath = "system.webServer/rewrite/rules"
# clear any prior ZT rule then add fresh (idempotent)
Clear-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName -Filter "$rulePath/rule[@name='ZT-ReverseProxy']" -ErrorAction SilentlyContinue
Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName -Filter $rulePath -Name '.' -Value @{ name='ZT-ReverseProxy'; stopProcessing='True' }
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName -Filter "$rulePath/rule[@name='ZT-ReverseProxy']/match" -Name 'url' -Value '(.*)'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName -Filter "$rulePath/rule[@name='ZT-ReverseProxy']/action" -Name 'type' -Value 'Rewrite'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName -Filter "$rulePath/rule[@name='ZT-ReverseProxy']/action" -Name 'url' -Value ("$($BackendUrl.TrimEnd('/'))/{R:1}")
Write-OK "Proxy rule -> $BackendUrl"

# Forward the authenticated client cert subject to the backend
$srPath = "system.webServer/rewrite/allowedServerVariables"
Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $SiteName -Filter $srPath -Name '.' -Value @{ name='HTTP_X_CLIENT_CERT_SUBJECT' } -ErrorAction SilentlyContinue
Write-OK 'Backend receives X-Client-Cert-Subject header from the verified cert'

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    PEP live: https://$($env:COMPUTERNAME):$ListenPort/  ->  $BackendUrl" -ForegroundColor White
Write-Host '    Only callers presenting a lab client cert reach the backend.' -ForegroundColor White
Write-Host '    Lock the backend so it accepts traffic ONLY from this PEP (firewall/segmentation).' -ForegroundColor Yellow
Write-Host '    Per-application publishing: Convert-VPNToPerApp.ps1 (8.5.2) builds on this.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
