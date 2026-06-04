#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.2.4 - Tightens the VPN to require BOTH the user smart card cert AND the device machine cert (issued in 8.2.1/8.2.2). Two-cert auth = device + identity.

.DESCRIPTION
    Tightens the VPN to require BOTH the user smart card cert AND the device machine cert (issued in 8.2.1/8.2.2). Two-cert auth = device + identity.

    Status: SCAFFOLD - structure in place, product-specific bits marked
    as TODO at top. See README.md for the Phase 8 plan and run order.

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.2.4 - Device Trust
    Run on     : Hyper-V host or each client
    Depends on : Working VPN, device cert template
    NIST       : IA-3, AC-17, AC-19
    Last Edit  : 2026-06-03
#>

# ============================================================
# TODO before this scaffold becomes turnkey
# ============================================================
# See README.md and the relevant Architecture/Roadmap doc.
# Fill in product-specific implementation below.
# ============================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |  Phase 8.2.4 - Update VPN DeviceAuth' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Write-Step "Scaffold script - not yet a turnkey implementation."
Write-Info  "Sub-phase  : 8.2.4 (Device Trust)"
Write-Info  "Run on     : Hyper-V host or each client"
Write-Info  "Depends on : Working VPN, device cert template"
Write-Info  "NIST       : IA-3, AC-17, AC-19"
Write-Host ""
Write-Warn "Open this script in an editor and complete the TODO at top before running in production."
Write-Warn "See Lab-Kit/07-ZeroTrust/README.md for the full Phase 8 plan."
Write-Host ""
