# PKI Health Check Evidence - 2026-06-04

**Host:** Lab-DC01
**Script:** `Lab-Kit/03-DomainController/Monitor-PKIHealth.ps1`
**Operator:** Administrator
**NIST Controls:** CA-7 (Continuous Monitoring), SC-17 (PKI Certificates)

---

## Artifacts

| File | What It Is |
|---|---|
| `PKIHealth-DC01-AuditLog.txt` | Immutable audit trail from the script's built-in logging. Records every run with start/end timestamps and overall pass/fail. |
| `../../../Screenshots/06-pki-health-dashboard.png` | Console screenshot of the 12:18:49 run showing the `ALL CHECKS PASSED` summary. |

## What the Audit Log Shows

Seven independent runs across the day (11:50 - 12:07 UTC-4), all reporting `Critical: False | Warning: False`. The 12:07:50 run added the explicit `HEALTH-CHECK-PASS | No issues found` line after a script update.

Visually verified at 12:18:49 with the captured screenshot - the same run pattern, summary line `ALL CHECKS PASSED - PKI environment is healthy.`

## How This Maps to RMF Artifacts

- **SAR Section 3 (Continuous Monitoring):** Cite this folder as evidence that CA-7 is operational and producing routine pulse data.
- **POAM:** Establishes the baseline pulse from which future deltas (cert expiry warnings, CRL freshness drift, OCSP responder downtime) get measured.
- **SSP Section 7 (Operational Procedures):** Demonstrates the monitoring cadence is real, not theoretical.

## How to Reproduce

On Lab-DC01 as Administrator:

```powershell
cd C:\Scripts\03-DomainController
Start-Transcript -Path "$env:USERPROFILE\Desktop\pki-health-$(Get-Date -Format yyyy-MM-dd).txt"
.\Monitor-PKIHealth.ps1
Stop-Transcript
```

For a parameterized run that exercises every check (instead of `[SKIP]` rows):

```powershell
.\Monitor-PKIHealth.ps1 `
    -CRLUrls @("http://pki.lab.local/crl/RootCA.crl",
               "http://pki.lab.local/crl/IssuingCA.crl") `
    -OCSPUrl "http://ocsp.lab.local/ocsp" `
    -IssuingCAServer "Lab-DC01" `
    -AlertThresholdDays 60
```

---

*Folder convention: `Compliance-Reports/PKI-Health/<YYYY-MM-DD>/` per scan date.*
