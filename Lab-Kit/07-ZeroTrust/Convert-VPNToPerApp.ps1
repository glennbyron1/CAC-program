#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.5.2 - Migrates the full-tunnel VPN to per-application access (ZTNA-style). Each backend is reached through its own broker/PEP rather than a flat tunnel.

.DESCRIPTION
    Migrates the full-tunnel VPN to per-application access (ZTNA-style). Each backend is reached through its own broker/PEP rather than a flat tunnel.

    Status: SCAFFOLD - structure in place, product-specific bits marked
    as TODO at top. See README.md for the Phase 8 plan and run order.

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.5.2 - Network Segmentation
    Run on     : Cloud admin console + on-prem connector
    Depends on : Resource Gateway (8.1.5) or chosen broker
    NIST       : AC-3, AC-4, SC-7(11)
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
Write-Host '  |  Phase 8.5.2 - Convert VPNToPerApp' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Write-Step "Scaffold script - not yet a turnkey implementation."
Write-Info  "Sub-phase  : 8.5.2 (Network Segmentation)"
Write-Info  "Run on     : Cloud admin console + on-prem connector"
Write-Info  "Depends on : Resource Gateway (8.1.5) or chosen broker"
Write-Info  "NIST       : AC-3, AC-4, SC-7(11)"
Write-Host ""
Write-Warn "Open this script in an editor and complete the TODO at top before running in production."
Write-Warn "See Lab-Kit/07-ZeroTrust/README.md for the full Phase 8 plan."
Write-Host ""
