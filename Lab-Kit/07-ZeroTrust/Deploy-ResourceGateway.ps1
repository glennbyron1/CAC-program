#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.1.5 - Stands up a reverse-proxy Policy Enforcement Point (PEP) in front of a protected resource. PEP authenticates the user with the lab smart card, then proxies the request to the backend.

.DESCRIPTION
    Stands up a reverse-proxy Policy Enforcement Point (PEP) in front of a protected resource. PEP authenticates the user with the lab smart card, then proxies the request to the backend.

    Status: SCAFFOLD - structure in place, product-specific bits marked
    as TODO at top. See README.md for the Phase 8 plan and run order.

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.1.5 - Authorization & Least Privilege
    Run on     : Hyper-V host or dedicated PEP VM
    Depends on : Issuing CA (TLS cert), backend service
    NIST       : AC-3, AC-4, SC-7(3)
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
Write-Host '  |  Phase 8.1.5 - Deploy ResourceGateway' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Write-Step "Scaffold script - not yet a turnkey implementation."
Write-Info  "Sub-phase  : 8.1.5 (Authorization & Least Privilege)"
Write-Info  "Run on     : Hyper-V host or dedicated PEP VM"
Write-Info  "Depends on : Issuing CA (TLS cert), backend service"
Write-Info  "NIST       : AC-3, AC-4, SC-7(3)"
Write-Host ""
Write-Warn "Open this script in an editor and complete the TODO at top before running in production."
Write-Warn "See Lab-Kit/07-ZeroTrust/README.md for the full Phase 8 plan."
Write-Host ""
