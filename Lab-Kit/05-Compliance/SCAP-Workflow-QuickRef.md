# SCAP Compliance Workflow — Quick Reference

**Author:** Glenn Byron
**Script location:** `Lab-Kit\05-Compliance\Invoke-SCAPWorkflow.ps1`
**Last Updated:** June 2026

---

## What It Does

Automates the full before/after SCAP compliance scan loop in one command:

1. Runs SCAP SCC (headless, no GUI) against the target
2. Stages XCCDF results → `Compliance-Reports\Before-MFA\`
3. Runs the Ansible STIG hardening playbook (via WSL)
4. Waits for Group Policy to propagate
5. Runs SCAP SCC again (post-hardening)
6. Stages results → `Compliance-Reports\After-MFA\`
7. Generates `Compliance-Reports\Delta-Report.txt` — paste into SAR

---

## Commands

```powershell
# Navigate to the compliance folder first
cd C:\path\to\CAC-program\Lab-Kit\05-Compliance

# Full automated loop — scan, harden, scan again, generate delta
.\Invoke-SCAPWorkflow.ps1 -Phase Full

# Target a specific VM by IP
.\Invoke-SCAPWorkflow.ps1 -Phase Full -TargetHost 10.10.10.10

# Target DC01 by hostname
.\Invoke-SCAPWorkflow.ps1 -Phase Full -TargetHost Lab-DC01

# Preview what would run without executing anything
.\Invoke-SCAPWorkflow.ps1 -Phase Full -WhatIf

# Baseline scan ONLY (before hardening)
.\Invoke-SCAPWorkflow.ps1 -Phase Before

# After-hardening scan ONLY (if you applied hardening manually)
.\Invoke-SCAPWorkflow.ps1 -Phase After -SkipHardening

# Skip the Ansible step (hardening already done) but still run both scans
.\Invoke-SCAPWorkflow.ps1 -Phase Full -SkipHardening
```

---

## What You Need Before Running

| Requirement | Where to Get It |
|-------------|----------------|
| SCAP SCC installed | [public.cyber.mil/stigs/scap](https://public.cyber.mil/stigs/scap/) — free, no login |
| Windows Server 2022 STIG benchmark | Same site — download the XCCDF benchmark ZIP |
| Place benchmark at | `C:\FedCompliance-Tools\00-SCAP-SCC\Benchmarks\U_MS_Windows_Server_2022_STIG_SCAP_1-0_Benchmark.xml` |
| WSL with Ansible installed | For the hardening step (or use -SkipHardening and run manually) |
| Elevated PowerShell | Run as Administrator |

---

## Output Files

After a full run you will have:

```
Compliance-Reports\
  Before-MFA\
    XCCDF-Results.xml          ← raw scan data
    Baseline-Compliance.html   ← DISA SCC HTML report (open in browser)
  After-MFA\
    XCCDF-Results.xml
    Hardened-Compliance.html
  Delta-Report.txt             ← Before vs After table — paste into SAR
```

---

## What the Delta Report Looks Like

```
==============================================================
  SCAP Compliance Delta Report
  Target   : Lab-DC01
  Generated: 2026-06-15 14:22
==============================================================

  Metric              Before          After           Change
  ----------------------------------------------------------
  Compliance %        58%             94%
  CAT I Failures      8               0
  CAT II Failures     47              6
  CAT III Failures    12              3
==============================================================
```

These numbers go directly into `Architecture\RMF-Templates\SAR-Template.md`.

---

## Tags (Run Individual Sections of the Ansible Playbook)

```powershell
# Audit policy only
ansible-playbook -i inventory.ini windows-stig-hardening.yml --tags audit_policy

# Account policy only
ansible-playbook -i inventory.ini windows-stig-hardening.yml --tags account_policy

# All tags: account_policy, audit_policy, services, firewall, rdp, legal_banner, user_rights
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `cscc.exe not found` | Install SCAP SCC from public.cyber.mil or update -SccPath parameter |
| `Benchmark not found` | Download WS2022 STIG benchmark and place at the default path |
| `No SCC result directories found` | SCC may have written to a non-default path — check %USERPROFILE%\SCC\Results |
| `Ansible not found in WSL` | `wsl pip install ansible pywinrm` then `wsl ansible-galaxy collection install ansible.windows community.windows` |
| GPO not applied after hardening | Manually run `gpupdate /force` on the target before the after-scan |

---

## Optional Enhancements (Bring In Later)

These add to the workflow but aren't required to run the core scan loop. Wire them in once you've hardened the DC and want richer evidence.

### Docker `scap-summary` for CAT I/II/III roll-up

A small containerized tool that ingests the XCCDF XML and prints a clean CAT I/II/III count summary. Lives in the Home-Lab folder today (`Home-Lab\docker\scap-summary\`). To integrate:

1. **Build the image** (one-time):
   ```powershell
   cd C:\path\to\Home-Lab\docker\scap-summary
   docker build -t scap-summary .
   ```
2. **Pre-req:** Docker Desktop must be running.
3. **Run against a finished scan:**
   ```powershell
   docker run --rm -v "${PWD}:/in" scap-summary /in/XCCDF-Results.xml
   ```
4. **Output:** `scap-summary.txt` with CAT I/II/III counts. Drop next to the XCCDF in `Compliance-Reports\Before-MFA\` or `Compliance-Reports\After-MFA\`.

Once the DC hardening is settled, decide whether to:
- Copy the `scap-summary` Dockerfile into this repo (`CAC-program\docker\scap-summary\`) so the kit is self-contained
- Or keep it in Home-Lab and reference it as an external tool

### Other future additions

- **Nessus credentialed scan** as a third evidence column in the delta report
- **STIG Viewer .ckl export** to mark CAT I false positives with rationale
- **`Compliance-Reports\Trend.csv`** for charting score-over-time once you have a few runs

---

*Script source: `Lab-Kit\05-Compliance\Invoke-SCAPWorkflow.ps1`*
*Compliance output: `Compliance-Reports\` at repo root*
*SAR template: `Architecture\RMF-Templates\SAR-Template.md`*
