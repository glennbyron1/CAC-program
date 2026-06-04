#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.4.3 - Enables mutual TLS between two lab services so neither side trusts the network. Both ends present and validate certs from the lab Issuing CA.

.DESCRIPTION
    Enables mutual TLS between two lab services so neither side trusts the network. Both ends present and validate certs from the lab Issuing CA.

    Status: SCAFFOLD - structure in place, product-specific bits marked
    as TODO at top. See README.md for the Phase 8 plan and run order.

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.4.3 - Workload / NPI (optional)
    Run on     : Pair of lab service hosts
    Depends on : Both services have certs from Issuing CA
    NIST       : SC-8, SC-8(1), SC-23(5)
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
Write-Host '  |  Phase 8.4.3 - Enable mTLS' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Write-Step "Scaffold script - not yet a turnkey implementation."
Write-Info  "Sub-phase  : 8.4.3 (Workload / NPI (optional))"
Write-Info  "Run on     : Pair of lab service hosts"
Write-Info  "Depends on : Both services have certs from Issuing CA"
Write-Info  "NIST       : SC-8, SC-8(1), SC-23(5)"
Write-Host ""
Write-Warn "Open this script in an editor and complete the TODO at top before running in production."
Write-Warn "See Lab-Kit/07-ZeroTrust/README.md for the full Phase 8 plan."
Write-Host ""
