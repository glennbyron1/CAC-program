# After-Ansible — LAB-DC01 SCAP scan evidence (v1.4)

**Author:** Glenn Byron
**Scan date:** 2026-06-30
**Driven by:** `Lab-Kit/08-Ansible-STIG/` (ansible-lockdown Windows-2022-STIG role via WSL2 control node)

This folder holds the SCAP Compliance Checker (SCC) 5.10.2 scan evidence captured
after the v1.4 Ansible STIG remediation pass on LAB-DC01. Two SCC session archives
are preserved as point-in-time evidence of the score climb:

| Archive | Stage | SCAP Score | When |
|---|---|---|---|
| `LAB-DC01_SCAP_CAT-II_84.4pct.zip`  | After CAT II remediation (interim) | 84.40% | 2026-06-30 06:08 |
| `LAB-DC01_SCAP_CAT-III_86.7pct.zip` | After CAT III remediation (**final**)  | **86.70%** | 2026-06-30 06:13 |

Each archive is a full SCC session folder:

```
<archive>.zip
└── 2026-06-30_NNNNNN/
    ├── SCC_Summary_Viewer_2026-06-30_NNNNNN.html        <-- top-level viewer
    ├── Logs/                                            <-- scan error/warning log
    └── Results/SCAP/
        ├── *_All-Settings_MS_Windows_Server_2022_STIG-2.3.10.html
        ├── *_Non-Compliance_MS_Windows_Server_2022_STIG-2.3.10.html
        ├── Checklists/*.ckl                             <-- STIG Viewer checklist
        └── XML/                                         <-- XCCDF / OVAL / OCIL result XML
```

## What the numbers mean

Baseline (Before-MFA) for LAB-DC01 was **44.95%** with 9 CAT I / 105 CAT II / 6 CAT III
failures. After the v1.4 Ansible pass:

| Severity | Before-MFA Fail | After-Ansible Fail (final) | Closed |
|---|---:|---:|---:|
| CAT I (High)    | 9   | **1**  | 8  |
| CAT II (Medium) | 105 | **27** | 78 |
| CAT III (Low)   | 6   | **1**  | 5  |
| **Total** | **120** | **29** | **91** |

The remaining 29 failures are predominantly:

- Controls left off **by design** — `win2022stig_disruption_high: false` and
  `win2022stig_complexity_high: false` in `group_vars/dc/main.yml` skip
  service-disrupting and complex auto-remediations.
- Manual AUDIT controls — items that require human review (no automatable check).
- Four controls disabled for Server-2025 vs. 2022-benchmark mismatches:
  `wn22_00_000090` (TPM/wmic), `wn22_00_000340` (PNRP), `wn22_00_000420`/`000430` (FTP).

The 55 "other" results (Not Checked / Not Applicable / Informational) account for
the SCAP **manual questions** that need to be filled in via the SCC Manual Question
Auto-Answer template — they are valid checks deferred to STIG Viewer review.

## See also

- Playbook + bootstrap that produced these results: `Lab-Kit/08-Ansible-STIG/`
- Honest framing on what was deliberately left off: `Lab-Kit/08-Ansible-STIG/group_vars/dc/main.yml`
- Per-tier results narrative: `Lab-Kit/08-Ansible-STIG/CHANGELOG.md`
- Visual evidence of the climb: `Screenshots/08a-stig-dc01-CAT1-45.41pct.png`, `08b-…CAT2-84.4pct.png`, `08c-…CAT3-86.7pct.png`
- POA&M closures recorded against this scan: `Architecture/RMF-Templates/POAM-Template.md`
