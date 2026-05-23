# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    First-boot configuration for a CAC lab VM. Run this INSIDE each VM
    after Windows Server is installed, before running the CAC lab scripts.

.DESCRIPTION
    Sets up each VM with the right hostname, static IP, DNS, and baseline
    settings so it's ready to receive the CAC program scripts. Run it once
    per VM and then reboot.

    Modes (select with -VMRole):
      OfflineRootCA   — Offline Root CA (no network; sets hostname only)
      DomainController — DC + Issuing CA (sets hostname, static IP, DNS)
      Workstation      — Test workstation (sets hostname, static IP, DNS)

    After running this script and rebooting:
      - Lab-OfflineRootCA: ready for Download-OfflineCA-Kit.ps1
      - Lab-DC01: ready for Build-CAC-Lab.ps1
      - Lab-Workstation01: ready to join the domain after DC is up

.PARAMETER VMRole
    Which VM is being configured: OfflineRootCA, DomainController, or Workstation.

.PARAMETER Hostname
    The hostname to set. Defaults match the names from New-LabVMs.ps1:
      OfflineRootCA    -> Lab-OfflineRootCA
      DomainController -> Lab-DC01
      Workstation      -> Lab-Workstation01

.PARAMETER IPAddress
    Static IPv4 address for this VM. Only used for DomainController and Workstation.
    Suggested defaults:
      Lab-DC01          -> 10.10.10.10
      Lab-Workstation01 -> 10.10.10.20

.PARAMETER SubnetPrefix
    Subnet prefix length. Default: 24 (255.255.255.0)

.PARAMETER DefaultGateway
    Default gateway IP. Only needed for DomainController and Workstation.
    Default: 10.10.10.1

.PARAMETER DNSServer
    DNS server IP. For Lab-Workstation01, point this at Lab-DC01 (10.10.10.10).
    For Lab-DC01 itself, defaults to 127.0.0.1 (loopback - it IS the DNS server).

.EXAMPLE
    # Configure the Domain Controller VM (run inside Lab-DC01)
    .\Set-VMPostConfig.ps1 -VMRole DomainController -IPAddress 10.10.10.10

.EXAMPLE
    # Configure the Offline Root CA (no network - sets hostname only)
    .\Set-VMPostConfig.ps1 -VMRole OfflineRootCA

.EXAMPLE
    # Configure the workstation VM (run inside Lab-Workstation01)
    .\Set-VMPostConfig.ps1 -VMRole Workstation -IPAddress 10.10.10.20 -DNSServer 10.10.10.10

.NOTES
    Author         : Glenn Byron
    Run inside     : Each VM (not on the Hyper-V host)
    Requires       : Run as Administrator
    After running  : Reboot the VM, then proceed with the CAC lab scripts
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('OfflineRootCA', 'DomainController', 'Workstation')]
    [string]$VMRole,

    [Parameter()]
    [string]$Hostname = "",

    [Parameter()]
    [string]$IPAddress = "",

    [Parameter()]
    [int]$SubnetPrefix = 24,

    [Parameter()]
    [string]$DefaultGateway = "10.10.10.1",

    [Parameter()]
    [string]$DNSServer = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Apply defaults based on role
if (-not $Hostname) {
    $Hostname = switch ($VMRole) {
        'OfflineRootCA'    { "Lab-OfflineRootCA" }
        'DomainController' { "Lab-DC01" }
        'Workstation'      { "Lab-Workstation01" }
    }
}

if (-not $IPAddress -and $VMRole -ne 'OfflineRootCA') {
    $IPAddress = switch ($VMRole) {
        'DomainController' { "10.10.10.10" }
        'Workstation'      { "10.10.10.20" }
    }
}

if (-not $DNSServer) {
    $DNSServer = switch ($VMRole) {
        'OfflineRootCA'    { "" }
        'DomainController' { "127.0.0.1" }   # Points to itself after DNS role is installed
        'Workstation'      { "10.10.10.10" }  # Points to DC
    }
}

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  VM POST-CONFIG | SCRIPT | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  Role     : $VMRole" -ForegroundColor Cyan
    Write-Host "  Hostname : $Hostname" -ForegroundColor Cyan
    if ($IPAddress) {
        Write-Host "  IP       : $IPAddress/$SubnetPrefix" -ForegroundColor Cyan
        Write-Host "  Gateway  : $DefaultGateway" -ForegroundColor Cyan
        Write-Host "  DNS      : $DNSServer" -ForegroundColor Cyan
    }
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor White }
function Write-OK   { param([string]$Msg) Write-Host "  [OK]  $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }

Write-Banner

# ---------------------------------------------------------------------------
# Step 1: Set hostname
# ---------------------------------------------------------------------------
Write-Step "Setting hostname to: $Hostname"
$current = $env:COMPUTERNAME
if ($current -eq $Hostname) {
    Write-OK "Hostname already set to $Hostname"
} else {
    if ($PSCmdlet.ShouldProcess($Hostname, "Rename computer")) {
        Rename-Computer -NewName $Hostname -Force
        Write-OK "Hostname will be $Hostname after reboot"
    }
}

# ---------------------------------------------------------------------------
# Step 2: Static IP (skip for air-gapped Root CA)
# ---------------------------------------------------------------------------
if ($VMRole -ne 'OfflineRootCA' -and $IPAddress) {

    Write-Step "Configuring static IP: $IPAddress/$SubnetPrefix"

    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $adapter) {
        Write-Warn "No active network adapter found. If this is the Offline Root CA, this is expected."
    } else {
        Write-Info "Using adapter: $($adapter.Name)"

        # Remove any existing DHCP address
        Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

        if ($PSCmdlet.ShouldProcess($adapter.Name, "Set static IP")) {
            New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                             -IPAddress $IPAddress `
                             -PrefixLength $SubnetPrefix `
                             -DefaultGateway $DefaultGateway | Out-Null
            Write-OK "Static IP set: $IPAddress/$SubnetPrefix via $DefaultGateway"
        }

        # Set DNS
        if ($DNSServer) {
            Write-Step "Setting DNS server: $DNSServer"
            if ($PSCmdlet.ShouldProcess($adapter.Name, "Set DNS")) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                                           -ServerAddresses $DNSServer
                Write-OK "DNS set to: $DNSServer"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Step 3: Common baseline settings for all VMs
# ---------------------------------------------------------------------------
Write-Step "Applying common baseline settings..."

# Disable IPv6 (keeps things simple in a lab - CAC auth uses IPv4)
Get-NetAdapter | ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
}
Write-OK "IPv6 disabled on all adapters"

# Set execution policy for scripts
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Write-OK "Execution policy: RemoteSigned"

# Enable WinRM (needed for PowerShell remoting from Hyper-V host)
Write-Step "Enabling WinRM for PowerShell Direct support..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Write-OK "WinRM enabled"

# Turn off Windows Firewall for lab (you'll want it on in production - this is lab only)
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
Write-Warn "Windows Firewall disabled - lab environment only, not for production"

# Disable hibernation (common annoyance on VMs)
powercfg /hibernate off
Write-OK "Hibernation disabled"

# Set time zone
Set-TimeZone -Id "Eastern Standard Time"
Write-OK "Time zone: Eastern Standard Time"

# ---------------------------------------------------------------------------
# Step 4: Role-specific extras
# ---------------------------------------------------------------------------
if ($VMRole -eq 'OfflineRootCA') {
    Write-Step "Offline Root CA: confirming network isolation..."
    $adapters = Get-NetAdapter
    if ($adapters.Count -eq 0) {
        Write-OK "No network adapters present - VM is properly air-gapped"
    } else {
        Write-Warn "Network adapter found on Offline Root CA!"
        Write-Warn "This VM should have NO network adapter. Disable it in Hyper-V Manager."
        Write-Info "Adapters found: $($adapters.Name -join ', ')"
    }
    Write-Info "Transfer files to this VM using PowerShell Direct from the Hyper-V host:"
    Write-Info '  $s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential (Get-Credential)'
    Write-Info '  Copy-Item -Path "C:\FedCompliance-Tools" -ToSession $s -Destination "C:\" -Recurse'
}

if ($VMRole -eq 'DomainController') {
    Write-Step "DC pre-check: confirming static IP is set before AD DS install..."
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
    Write-Info "Current IPv4: $ip"
    Write-Info ""
    Write-Info "After rebooting, run Build-CAC-Lab.ps1 to build the domain."
    Write-Info "Then run Build-CA-GPO.ps1 to deploy the CA and smart card GPO."
}

if ($VMRole -eq 'Workstation') {
    Write-Info "After rebooting, verify you can ping Lab-DC01 ($DNSServer)."
    Write-Info "Then join the domain with:"
    Write-Info '  Add-Computer -DomainName lab.local -Credential (Get-Credential) -Restart'
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  POST-CONFIG COMPLETE - REBOOT NOW" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Run this to reboot:" -ForegroundColor White
Write-Host "  Restart-Computer -Force" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host ""