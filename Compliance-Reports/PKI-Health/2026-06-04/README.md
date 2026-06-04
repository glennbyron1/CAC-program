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
| `../../../Screenshots/06-pki-health-dashboard-parameterized.jpg` | **Primary capture.** Console screenshot of the 13:59:25 parameterized run — real `[OK]` rows for CRL Endpoint and Issuing CA Certificate Expiry against the lab's actual PKI. Summary: `ALL CHECKS PASSED`. |
| `../../../Screenshots/06-pki-health-dashboard.png` | **Supplementary baseline.** 12:18:49 run with no optional parameters; every row `[SKIP]` to demonstrate the script's defensive defaults. |

## What the Captures Show

**Parameterized run (13:59:25) — real PKI exercise:**

- CRL Distribution: `http://pki.lab.local/crl/LAB-CA.crl` reachable, valid, expires 2026-12-05 (184 days out at capture time)
- Issuing CA Certificate (`LAB-CA`, thumbprint `E7DCA2DB...`): healthy, expires 2031-05-26 (1817 days out at capture time)
- OCSP / VPN cert / enrolled smart cards: `[SKIP]` — those optional checks aren't part of this run's scope

**Baseline run (12:18:49) — defensive defaults:**

Script invoked with no optional parameters. Every check `[SKIP]`s rather than crashing. Demonstrates that the same script can be used as a smoke test during lab build (when those endpoints might not exist yet) without producing false alarms.

**Audit log:** Seven independent runs across 2026-06-04 (11:50 - 12:07), all reporting `Critical: False | Warning: False`. The 12:07:50 run added the explicit `HEALTH-CHECK-PASS | No issues found` line after a script update.

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
