# Lab-Kit / 05-Compliance

**Author:** Glenn Byron
**Run these scripts on:** Lab-DC01, after the domain and PKI are operational.

---

## Scripts in This Folder

| Script | When to run | What it does |
|--------|-------------|-------------|
| `Invoke-LabValidation.ps1` | **Before every SCAP SCC scan** | 7-layer pass/fail check confirming the lab is ready to produce valid scan results |
| `Stage-Reports.ps1` | After each SCAP SCC scan | Moves SCAP Compliance Checker output into the correct `Before-MFA` or `After-MFA` staging folder |

---

## Invoke-LabValidation.ps1

Run this before any SCAP SCC scan. A failed layer will skew your compliance score or cause the scan to miss findings — fix issues here first.

```powershell
.\Invoke-LabValidation.ps1 `
    -DomainName       "lab.local" `
    -DCHostname       "Lab-DC01" `
    -CRLUrl           "http://pki.lab.local/crl/IssuingCA.crl" `
    -OCSPUrl          "http://pki.lab.local/ocsp" `
    -VPNConnectionName "Agency VPN" `
    -TestUserUPN      "testuser@lab.local" `
    -ExportReport
```

**What it checks (7 layers):**

| Layer | Checks |
|-------|--------|
| 1 — Domain & Network | Domain membership, LDAP TCP reachability, DNS resolution, Kerberos time skew < 5 min |
| 2 — PKI | Root CA and Issuing CA in certificate stores, cert expiry, smart card logon EKU, CRL download and parse, OCSP reachability |
| 3 — Smart Card | SCardSvr service running, SmartCard device enumerator, reader present via WMI |
| 4 — GPO | `scforceoption=1`, `ScRemoveOption` set, `InactivityTimeoutSecs` ≤ 900 |
| 5 — Audit Policy | Logon, Kerberos, and Certification Services subcategories enabled; Security log ≥ 512 MB |
| 6 — VPN | IKEv2 tunnel type, EAP auth method, AES-256 IPsec policy, optional live connection test |
| 7 — Recent Auth Events | Event IDs 4624 and 4768 present in the last 24 hours |

`-ExportReport` saves a timestamped `.txt` report to the current directory. Include it in the evidence package alongside the SCAP results.

---

## Stage-Reports.ps1

Run after each SCAP SCC scan to move the results into the right folder.

```powershell
.\Stage-Reports.ps1
```

The script finds the most recent SCAP Compliance Checker output folder and asks whether to stage it as `Before-MFA` (baseline, pre-hardening) or `After-MFA` (hardened). It copies both the HTML report and the XCCDF XML into `Compliance-Reports\Before-MFA\` or `Compliance-Reports\After-MFA\` respectively.

---

## Recommended Sequence

```
1. Build and configure the lab (all of Lab-Kit/03-DomainController/)
2. Run Invoke-LabValidation.ps1         ← confirm ready, fix any failures
3. Run SCAP SCC Before-MFA scan
4. Run Stage-Reports.ps1                ← stage as Before-MFA
5. Apply smart card GPO hardening
6. Run Invoke-LabValidation.ps1 again   ← confirm GPO took effect
7. Run SCAP SCC After-MFA scan
8. Run Stage-Reports.ps1                ← stage as After-MFA
9. Record before/after scores in Architecture/RMF-Templates/SAR-Template.md
```

---

*Related: `Lab-Kit/LAB-DAY-CHECKLIST.md`, `Compliance-Reports/README.md`, `Architecture/RMF-Templates/SAR-Template.md`*
