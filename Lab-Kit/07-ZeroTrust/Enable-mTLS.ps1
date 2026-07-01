#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.4.3 - Configures mutual TLS between two lab services using IIS, so
    neither side trusts the network: the server presents a workload cert AND
    requires the client to present one issued by the lab Issuing CA.

.DESCRIPTION
    Demonstrates workload-to-workload mTLS with in-box Windows components:

    Server side (run with -Mode Server on the host of the protected service):
      - Ensures IIS + Web-Server role is present.
      - Creates a demo site bound to HTTPS on -Port using the LocalMachine\My
        certificate whose subject matches -ServerSubject (enroll it first with
        New-WorkloadCertTemplate.ps1 / Get-Certificate).
      - Sets SslFlags = Ssl, SslRequireCert (client cert REQUIRED) so a caller
        with no cert is rejected at the TLS layer.

    Client side (run with -Mode Client on the calling service's host):
      - Locates the client workload cert by -ClientSubject in LocalMachine\My
      - Calls https://<server>:<port>/ presenting that cert and reports whether
        the mTLS handshake succeeded.

    Trust is automatic: both certs chain to the lab Issuing CA, which every
    domain member already trusts (NTAuth / enterprise root). No manual CTL needed
    inside the domain.

.PARAMETER Mode
    Server | Client.

.PARAMETER SiteName
    IIS site name (Server mode). Default 'ZT-mTLS-Demo'.

.PARAMETER Port
    HTTPS port. Default 8443.

.PARAMETER ServerSubject
    CN of the server's workload cert in LocalMachine\My. Default 'svc-server.lab.local'.

.PARAMETER ClientSubject
    CN of the client's workload cert (Client mode). Default 'svc-client.lab.local'.

.PARAMETER ServerHost
    Hostname/IP to call (Client mode). Default 'localhost'.

.PARAMETER DryRun
    Switch - preview without changing IIS or making the call.

.EXAMPLE
    # On the server host
    .\Enable-mTLS.ps1 -Mode Server -ServerSubject svc-crm.lab.local

.EXAMPLE
    # On the client host
    .\Enable-mTLS.ps1 -Mode Client -ServerHost crm.lab.local -ClientSubject svc-billing.lab.local

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.4.3 - Workload / NPI (optional)
    Run on     : Pair of lab service hosts
    Depends on : New-WorkloadCertTemplate.ps1 (both ends have workload certs)
    NIST       : SC-8, SC-8(1), SC-23(5)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Server','Client')]
    [string]$Mode,
    [string]$SiteName      = 'ZT-mTLS-Demo',
    [int]   $Port          = 8443,
    [string]$ServerSubject = 'svc-server.lab.local',
    [string]$ClientSubject = 'svc-client.lab.local',
    [string]$ServerHost    = 'localhost',
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

function Get-WorkloadCert {
    param([string]$Subject)
    Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*CN=$Subject*" -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
}

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host "  |   Phase 8.4.3 - Mutual TLS ($Mode)$((' ' * (24 - $Mode.Length)))|" -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# =========================================================================
if ($Mode -eq 'Server') {
# =========================================================================
    # Ensure IIS
    Write-Step 'Phase 1 - IIS web server role'
    $feat = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($feat -and $feat.Installed) {
        Write-Skip 'Web-Server role already installed'
    } elseif ($PSCmdlet.ShouldProcess('Web-Server', 'Install-WindowsFeature')) {
        if (-not $DryRun) { Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null }
        Write-OK 'Installed IIS (Web-Server)'
    }
    Import-Module WebAdministration -ErrorAction Stop

    # Find the server workload cert
    Write-Step "Phase 2 - Server cert (CN=$ServerSubject)"
    $cert = Get-WorkloadCert -Subject $ServerSubject
    if (-not $cert) {
        Write-Fatal "No private-key cert with CN=$ServerSubject in LocalMachine\My. Enroll it first:
       Get-Certificate -Template ZT-Workload-Identity -SubjectName 'CN=$ServerSubject' -CertStoreLocation Cert:\LocalMachine\My"
    }
    Write-OK "Found cert: $($cert.Subject)  (thumb $($cert.Thumbprint))"

    if ($DryRun) { Write-Warn 'DryRun - not creating site/binding'; return }

    # Create / reuse site
    Write-Step "Phase 3 - IIS site '$SiteName' on :$Port"
    $sitePath = "C:\inetpub\$SiteName"
    if (-not (Test-Path $sitePath)) { New-Item -ItemType Directory -Path $sitePath -Force | Out-Null }
    if (-not (Test-Path "$sitePath\index.html")) {
        Set-Content -Path "$sitePath\index.html" -Value '<h1>ZT mTLS demo backend - if you can read this, mutual TLS succeeded.</h1>' -Encoding UTF8
    }

    if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
        Write-Skip "Site '$SiteName' exists - updating binding"
        Remove-WebBinding -Name $SiteName -Protocol https -Port $Port -ErrorAction SilentlyContinue
    } else {
        New-Website -Name $SiteName -PhysicalPath $sitePath -Port $Port -Protocol https -Force | Out-Null
        Write-OK "Created site '$SiteName'"
    }

    # Bind cert to the port (idempotent: remove any existing SSL binding then add)
    $binding = "0.0.0.0!$Port"
    if (Test-Path "IIS:\SslBindings\$binding") { Remove-Item "IIS:\SslBindings\$binding" -Force }
    New-Item -Path "IIS:\SslBindings\$binding" -Value $cert -Force | Out-Null
    Write-OK "Bound server cert to :$Port"

    # Require client certificate (mutual TLS)
    Write-Step 'Phase 4 - Require client certificate (SslRequireCert)'
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
        -Location $SiteName `
        -Filter 'system.webServer/security/access' `
        -Name 'sslFlags' -Value 'Ssl,SslRequireCert'
    Write-OK 'Client certificate is now REQUIRED for this site'

    Write-Host ''
    Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
    Write-Host "    mTLS endpoint live: https://$($env:COMPUTERNAME):$Port/" -ForegroundColor White
    Write-Host '    A caller with NO client cert will be rejected at the handshake.' -ForegroundColor White
    Write-Host '    Test from the client host:' -ForegroundColor Yellow
    Write-Host "      .\Enable-mTLS.ps1 -Mode Client -ServerHost $($env:COMPUTERNAME) -Port $Port -ClientSubject <svc>" -ForegroundColor Yellow
    Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
    Write-Host ''

# =========================================================================
} else {  # Client
# =========================================================================
    Write-Step "Phase 1 - Client cert (CN=$ClientSubject)"
    $cert = Get-WorkloadCert -Subject $ClientSubject
    if (-not $cert) {
        Write-Fatal "No private-key cert with CN=$ClientSubject in LocalMachine\My. Enroll it first with New-WorkloadCertTemplate.ps1."
    }
    Write-OK "Using client cert: $($cert.Subject)  (thumb $($cert.Thumbprint))"

    $url = "https://$($ServerHost):$Port/"
    Write-Step "Phase 2 - mTLS call to $url"
    if ($DryRun) { Write-Warn 'DryRun - not making the request'; return }

    try {
        $resp = Invoke-WebRequest -Uri $url -Certificate $cert -UseBasicParsing -TimeoutSec 20
        Write-OK "Handshake OK - HTTP $($resp.StatusCode). Mutual TLS verified."
    } catch {
        Write-Warn "Request failed: $($_.Exception.Message.Split([char]10)[0])"
        Write-Info 'If you see a TLS/handshake error, confirm: server requires client cert,'
        Write-Info 'both certs chain to the lab Issuing CA, and the port is reachable.'
        exit 1
    }

    # Negative control: prove no-cert is rejected
    Write-Step 'Phase 3 - Negative control (no client cert should FAIL)'
    try {
        Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 | Out-Null
        Write-Warn 'Call with NO client cert SUCCEEDED - server is not enforcing mTLS. Re-run -Mode Server.'
    } catch {
        Write-OK 'Call with no client cert was rejected, as expected (mTLS enforced).'
    }
    Write-Host ''
}
