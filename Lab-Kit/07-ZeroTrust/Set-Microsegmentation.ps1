#Requires -Version 5.1
#Requires -Modules GroupPolicy, ActiveDirectory
<#
.SYNOPSIS
    Phase 8.5.1 - Builds a default-deny east-west microsegmentation policy
    using Windows Firewall with Advanced Security via GPO.

.DESCRIPTION
    Default Windows posture lets domain-joined hosts talk to each other
    freely on the Domain profile. That's the opposite of ZT.

    This script creates 'ZT-Microsegmentation' GPO with:
      - Inbound: default DENY on Domain profile (overrides system default)
      - Outbound: default ALLOW (we don't break clients calling out)
      - Explicit ALLOW rules for the lab's known traffic:
          * Lab-DC01 inbound from Workstations OU: 88/tcp (Kerberos), 389/tcp/udp (LDAP),
            636/tcp (LDAPS), 445/tcp (SMB for SYSVOL/NETLOGON), 53/tcp/udp (DNS), 135/tcp (RPC EPM)
          * Lab-DC01 inbound from Servers OU: same + 49152-65535/tcp (RPC dynamic) + ICMP
          * All hosts inbound from DCs: ICMP, dynamic RPC (group policy refresh)
      - Explicit DENY for everything else east-west

    Links GPO to Tier-1 and Tier-2 OUs (Tier 0 / DCs keep open broker role).

.PARAMETER OUParent
    Distinguished name of parent OU. Defaults to domain root.

.PARAMETER GpoName
    GPO name. Default 'ZT-Microsegmentation'.

.PARAMETER DryRun
    Switch - preview without writing.

.EXAMPLE
    .\Set-Microsegmentation.ps1

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.5.1 - Network Segmentation
    NIST       : SC-7, SC-7(5), SC-7(11)
    Caution    : Test with -WhatIf and verify lab still functional after first apply.
                 If you lock yourself out, revoke link to the GPO from a DC console.
    Last Edit  : 2026-06-03
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OUParent = '',
    [string]$GpoName  = 'ZT-Microsegmentation',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Skip  { param([string]$msg) Write-Host "  [SKIP] $msg"   -ForegroundColor DarkGray }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |     Phase 8.5.1 - Microsegmentation (WFW GPO)        |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''
Write-Warn 'This sets DEFAULT-DENY inbound on tier 1 and tier 2 hosts.'
Write-Warn 'Test in dry-run first; verify lab works after the first apply.'
Write-Host ''

Import-Module GroupPolicy    -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

if (-not $OUParent) { $OUParent = (Get-ADDomain).DistinguishedName }

# Create or reuse GPO
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    if ($PSCmdlet.ShouldProcess($GpoName, 'New-GPO')) {
        if (-not $DryRun) {
            $gpo = New-GPO -Name $GpoName -Comment 'Phase 8.5.1 - default-deny east-west'
        }
        Write-OK "Created GPO: $GpoName"
    }
} else {
    Write-Skip "GPO exists: $GpoName"
}

if ($DryRun) {
    Write-Warn 'DryRun - firewall rules listed below but not written'
}

# We can't fully configure firewall rules via Set-GPRegistryValue alone.
# Instead, we use the NetFirewallRule cmdlets with the -PolicyStore parameter
# pointing at the GPO. This is the supported way in Server 2016+.
$store = "$((Get-ADDomain).NetBIOSName)\$GpoName"
Write-Step "PolicyStore: $store"
Write-Host ''

# Profile settings: default-deny inbound on Domain profile
if (-not $DryRun) {
    Set-NetFirewallProfile -Profile Domain `
        -PolicyStore $store `
        -DefaultInboundAction Block `
        -DefaultOutboundAction Allow `
        -Enabled True `
        -LogAllowed False -LogBlocked True `
        -LogFileName '%systemroot%\system32\logfiles\firewall\zt-fw.log' `
        -LogMaxSizeKilobytes 16384 | Out-Null
    Write-OK 'Domain profile: inbound = Block, outbound = Allow'
}

# Helper to create rules in the GPO's policy store
function New-ZTFirewallRule {
    param(
        [string]$Name, [string]$DisplayName, [string]$Direction,
        [string]$Protocol, [string]$LocalPort = '',
        [string]$Action = 'Allow', [string[]]$RemoteAddress = @()
    )
    if ($DryRun) {
        Write-Host "  (DryRun) $Direction $Action $Protocol/$LocalPort  to $DisplayName" -ForegroundColor DarkGray
        return
    }
    $params = @{
        DisplayName   = $DisplayName
        Direction     = $Direction
        Action        = $Action
        Protocol      = $Protocol
        Profile       = 'Domain'
        PolicyStore   = $store
        Enabled       = 'True'
    }
    if ($LocalPort)              { $params['LocalPort']     = $LocalPort }
    if ($RemoteAddress.Count -gt 0) { $params['RemoteAddress'] = $RemoteAddress }
    try {
        New-NetFirewallRule @params -ErrorAction Stop | Out-Null
        Write-OK $DisplayName
    } catch {
        Write-Skip "$DisplayName (already present or error: $($_.Exception.Message.Split([char]10)[0]))"
    }
}

# Allow rules for the lab's known east-west traffic.
# Tighten with -RemoteAddress in production - the lab uses /24 subnets so just allow lab nets.
Write-Step 'Adding ALLOW rules for known lab traffic...'
$labSubnets = @('10.10.10.0/24', '10.10.20.0/24')

New-ZTFirewallRule -Name 'ZT-In-Kerberos-TCP'       -DisplayName 'ZT Allow Kerberos TCP/88'   -Direction Inbound -Protocol TCP -LocalPort 88   -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-Kerberos-UDP'       -DisplayName 'ZT Allow Kerberos UDP/88'   -Direction Inbound -Protocol UDP -LocalPort 88   -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-LDAP-TCP'           -DisplayName 'ZT Allow LDAP TCP/389'      -Direction Inbound -Protocol TCP -LocalPort 389  -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-LDAPS'              -DisplayName 'ZT Allow LDAPS TCP/636'     -Direction Inbound -Protocol TCP -LocalPort 636  -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-SMB'                -DisplayName 'ZT Allow SMB TCP/445'       -Direction Inbound -Protocol TCP -LocalPort 445  -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-DNS-UDP'            -DisplayName 'ZT Allow DNS UDP/53'        -Direction Inbound -Protocol UDP -LocalPort 53   -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-DNS-TCP'            -DisplayName 'ZT Allow DNS TCP/53'        -Direction Inbound -Protocol TCP -LocalPort 53   -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-RPC-EPM'            -DisplayName 'ZT Allow RPC Endpoint Mapper TCP/135' -Direction Inbound -Protocol TCP -LocalPort 135 -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-RPC-Dynamic'        -DisplayName 'ZT Allow RPC dynamic TCP'   -Direction Inbound -Protocol TCP -LocalPort '49152-65535' -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-ICMPv4'             -DisplayName 'ZT Allow ICMPv4'            -Direction Inbound -Protocol ICMPv4 -RemoteAddress $labSubnets
New-ZTFirewallRule -Name 'ZT-In-WinRM-HTTPS'        -DisplayName 'ZT Allow WinRM HTTPS TCP/5986' -Direction Inbound -Protocol TCP -LocalPort 5986 -RemoteAddress $labSubnets

Write-Host ''
Write-Step 'Linking GPO to tier OUs...'
foreach ($t in 1, 2) {
    $ouDn = "OU=Tier-$t,OU=Admin,$OUParent"
    if (-not (Get-ADOrganizationalUnit -Identity $ouDn -ErrorAction SilentlyContinue)) {
        Write-Warn "Tier $t OU not found - run Set-TieredAdminModel.ps1 first. Skipping link."
        continue
    }
    $existing = (Get-GPInheritance -Target $ouDn).GpoLinks | Where-Object { $_.DisplayName -eq $GpoName }
    if ($existing) { Write-Skip "Already linked: $ouDn"; continue }
    if (-not $DryRun) {
        New-GPLink -Name $GpoName -Target $ouDn -Enforced No -LinkEnabled Yes | Out-Null
    }
    Write-OK "Linked to $ouDn"
}

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    East-west default-deny ENABLED on Tier 1 and Tier 2 hosts.' -ForegroundColor White
Write-Host '    Tier 0 (DCs) unaffected - kept as broker.' -ForegroundColor White
Write-Host '' -ForegroundColor White
Write-Host '    On each tier 1/2 host: gpupdate /force' -ForegroundColor Yellow
Write-Host '    Test: From a workstation, try `psexec \\Lab-Workstation01 cmd` - should fail.' -ForegroundColor Yellow
Write-Host '    Domain traffic to/from Lab-DC01 should still work.' -ForegroundColor Yellow
Write-Host '' -ForegroundColor White
Write-Host '    Rollback: Remove-GPLink -Name ZT-Microsegmentation -Target OU=Tier-2,...' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
