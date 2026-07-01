#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8 add-on - Configures WinRM over HTTPS on LAB-DC01 so the WSL Ansible
    control node can manage it for STIG remediation.

.DESCRIPTION
    Ansible drives Windows over WinRM, not SSH. This script prepares the TARGET
    (LAB-DC01) - run it ON LAB-DC01 (transfer it in via PowerShell Direct like the
    other kit scripts). It:

      1. Ensures the WinRM service is running and quick-configured.
      2. Creates/uses a server certificate for an HTTPS listener:
           - default: a self-signed cert for the DC's FQDN (lab-grade), OR
           - -Thumbprint <hash> to use an existing cert from the lab Issuing CA.
      3. Creates the HTTPS (5986) WinRM listener bound to that cert.
      4. Opens the firewall for 5986 from the lab subnets only.
      5. Enables NTLM auth (matches ansible_winrm_transport: ntlm) and sane shell
         limits. Leaves HTTP/5985 and Basic auth OFF.

    Idempotent: re-running reuses the listener/cert and skips existing rules.

    SECURITY: self-signed means the control node uses
    ansible_winrm_server_cert_validation: ignore. For a cleaner setup, enroll a
    Server Authentication cert from the lab CA and pass its -Thumbprint; then you
    can turn validation back on.

.PARAMETER Thumbprint
    Thumbprint of an existing LocalMachine\My cert (Server Auth EKU) to bind. If
    omitted, a self-signed cert for the DC FQDN is created.

.PARAMETER AllowedSubnets
    Remote subnets allowed to reach 5986. Default the lab nets.

.PARAMETER DryRun
    Switch - preview without changing WinRM/firewall.

.EXAMPLE
    # On LAB-DC01 (self-signed, lab-grade)
    .\Enable-WinRM-ForAnsible.ps1

.EXAMPLE
    # Use a CA-issued cert instead
    .\Enable-WinRM-ForAnsible.ps1 -Thumbprint 1A2B3C...

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 add-on (Ansible STIG)
    Run on     : LAB-DC01 (the Ansible target)
    NIST       : CM-6, AC-17, SC-8
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]  $Thumbprint     = '',
    [string[]]$AllowedSubnets = @('10.10.10.0/24','10.10.20.0/24'),
    [switch]  $DryRun
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
Write-Host '  |   Phase 8 add-on - WinRM for Ansible (target prep)   |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# elevation check
$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $me.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Fatal 'Run elevated (Administrator) on LAB-DC01.'
}

$fqdn = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME)).HostName
Write-Step "Target host : $fqdn"
Write-Step "Mode        : $(if ($DryRun) { 'DRY RUN' } else { 'APPLY' })"
Write-Host ''

# -- Step 1: WinRM service ----------------------------------------------------
Write-Step 'Phase 1 - WinRM service'
if ($PSCmdlet.ShouldProcess('WinRM', 'Ensure running + quickconfig')) {
    if (-not $DryRun) {
        Set-Service WinRM -StartupType Automatic
        Start-Service WinRM
        # quickconfig without touching network profile prompts
        & winrm quickconfig -quiet -transport:http 2>&1 | Out-Null
    }
    Write-OK 'WinRM service running'
}
Write-Host ''

# -- Step 2: server certificate ----------------------------------------------
Write-Step 'Phase 2 - HTTPS listener certificate'
if ($Thumbprint) {
    $cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) { Write-Fatal "Cert $Thumbprint not found in LocalMachine\My." }
    Write-OK "Using provided cert: $($cert.Subject)"
} else {
    $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -eq "CN=$fqdn" -and $_.NotAfter -gt (Get-Date) -and
                           $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.1' } |
            Sort-Object NotAfter -Descending | Select-Object -First 1
    if ($cert) {
        Write-Skip "Reusing existing self-signed cert for $fqdn"
    } elseif ($PSCmdlet.ShouldProcess($fqdn, 'Create self-signed Server Auth cert')) {
        if (-not $DryRun) {
            $cert = New-SelfSignedCertificate -DnsName $fqdn -CertStoreLocation Cert:\LocalMachine\My `
                        -KeyLength 2048 -NotAfter (Get-Date).AddYears(3) `
                        -FriendlyName 'WinRM-Ansible (self-signed, lab)'
        }
        Write-OK "Created self-signed cert for $fqdn"
        Write-Warn 'Control node must use ansible_winrm_server_cert_validation: ignore (already set).'
    }
}
$thumb = if ($cert) { $cert.Thumbprint } else { 'WHATIF' }
Write-Host ''

# -- Step 3: HTTPS listener ---------------------------------------------------
Write-Step 'Phase 3 - HTTPS listener on 5986'
$httpsListener = & winrm enumerate winrm/config/listener 2>$null | Select-String 'Transport = HTTPS'
if ($httpsListener) {
    Write-Skip 'HTTPS listener already present (recreating to bind current cert)'
    if (-not $DryRun) { & winrm delete "winrm/config/Listener?Address=*+Transport=HTTPS" 2>&1 | Out-Null }
}
if ($PSCmdlet.ShouldProcess('5986', 'Create HTTPS WinRM listener')) {
    if (-not $DryRun) {
        & winrm create "winrm/config/Listener?Address=*+Transport=HTTPS" `
            "@{Hostname=`"$fqdn`";CertificateThumbprint=`"$thumb`"}" 2>&1 | Out-Null
    }
    Write-OK "HTTPS listener bound to cert $thumb"
}
Write-Host ''

# -- Step 4: auth + shell limits ----------------------------------------------
Write-Step 'Phase 4 - Auth (NTLM on, Basic off) + shell limits'
if ($PSCmdlet.ShouldProcess('WinRM', 'Set auth + limits')) {
    if (-not $DryRun) {
        & winrm set winrm/config/service/auth '@{Negotiate="true";Basic="false";CredSSP="false"}' 2>&1 | Out-Null
        & winrm set winrm/config/service '@{AllowUnencrypted="false"}' 2>&1 | Out-Null
        & winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024";MaxShellsPerUser="30"}' 2>&1 | Out-Null
    }
    Write-OK 'Negotiate/NTLM enabled, Basic + unencrypted disabled, shell limits raised'
}
Write-Host ''

# -- Step 5: firewall ---------------------------------------------------------
Write-Step 'Phase 5 - Firewall (5986 from lab subnets only)'
$ruleName = 'WinRM-HTTPS-Ansible'
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    Write-Skip "Firewall rule exists: $ruleName"
} elseif ($PSCmdlet.ShouldProcess($ruleName, 'Create inbound 5986 rule')) {
    if (-not $DryRun) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort 5986 -RemoteAddress $AllowedSubnets -Profile Domain | Out-Null
    }
    Write-OK "Allowed 5986 inbound from: $($AllowedSubnets -join ', ')"
}
Write-Host ''

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    LAB-DC01 ready for Ansible over WinRM HTTPS (5986)." -ForegroundColor White
Write-Host '    From the WSL control node, test:' -ForegroundColor Yellow
Write-Host '      ansible dc -m ansible.windows.win_ping --ask-vault-pass' -ForegroundColor Yellow
Write-Host '    Expect: LAB-DC01 | SUCCESS => "ping": "pong"' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
