# CAC Lab Tools Kit — Start Here

**Author:** Glenn Byron
**What this is:** Everything needed to download and stage the compliance and PKI tools for the CAC/PIV lab. Run `Get-LabTools.ps1` on any internet-connected machine, then copy the output folder to your lab VMs.

---

## One-Command Download

Open PowerShell as Administrator and run:

```powershell
cd C:\path\to\Tools-Kit\
.\Get-LabTools.ps1
```

This downloads everything it can automatically and creates `C:\FedCompliance-Tools\` ready to copy into your VMs.

To stage to a different location (e.g., directly onto a USB drive):

```powershell
.\Get-LabTools.ps1 -OutputPath "E:\FedCompliance-Tools"
```

---

## What Downloads Automatically

| Tool | Folder | Notes |
|------|--------|-------|
| DISA STIG Viewer 3.3 | `01-STIG-Viewer\` | Java required to run |
| DISA STIG Content — WS2022, WS2019, Win11 | `02-STIG-Content\` | Import into STIG Viewer |
| DISA SCAP 1.3 Benchmarks — WS2022, WS2019 | `03-SCAP-Content\` | Import into SCAP SCC or OpenSCAP |
| Microsoft Security Compliance Toolkit | `04-MS-Security-Compliance-Toolkit\` | STIG GPO baselines |
| Tenable Nessus Essentials installer | `05-Nessus-Essentials\` | **Needs free activation code** (see below) |
| Microsoft SysInternals Suite | `06-SysInternals\` | sigcheck, procmon, autoruns |
| OpenSSL for Windows | `07-OpenSSL\` | CRL parsing, cert verification |
| CISA CSET | `08-CISA-CSET\` | OT cybersecurity assessment (MD SB 871) |
| Offline Root CA config kit | `09-OfflineRootCA-Kit\` | CAPolicy.inf, CRL scripts, manifest |
| Enterprise Issuing CA kit | `10-IssuingCA-Kit\` | Prereqs and init script for the Issuing CA |

---

## What Needs a Manual Step

### SCAP Compliance Checker (SCC) — CAC/ECA Required
The SCAP SCC is behind a DoD authentication wall. Two options:

**Option A — You have a CAC:** Log in at `https://public.cyber.mil/stigs/scap/` and download the Windows 64-bit installer. Place it in `FedCompliance-Tools\00-SCAP-SCC\`.

**Option B — No CAC:** Use **OpenSCAP Workbench** instead — free, open-source, reads the same SCAP content, produces the same ARF results. Download from `https://github.com/OpenSCAP/scap-workbench/releases`. Both are SCAP 1.3 conformant.

See `Manual-Downloads\SCAP-SCC-Instructions.txt` for full details.

### Nessus Essentials — Free Activation Code
The installer downloads automatically, but Nessus won't run scans until you activate it with a free code from Tenable. Quick process:
1. Go to `https://www.tenable.com/products/nessus/nessus-essentials`
2. Register (free) — Tenable emails you an activation code
3. Enter the code during install

---

## Copy Tools to Lab VMs

**Option A — USB drive:**
Copy the entire `FedCompliance-Tools\` folder to a USB and plug it into the lab machine.

**Option B — PowerShell Direct (from Hyper-V host, no USB needed):**
```powershell
$cred = Get-Credential   # local Administrator on the target VM
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Copy-Item -Path "C:\FedCompliance-Tools" -ToSession $s -Destination "C:\" -Recurse
Remove-PSSession $s
```

For the air-gapped Offline Root CA, PowerShell Direct is the only option (no network).

---

## Tool to VM Mapping

| Tool Folder | Which VM Uses It |
|-------------|-----------------|
| `00-SCAP-SCC\` | Lab-DC01 (run scans against itself and other VMs) |
| `01-STIG-Viewer\` | Lab-DC01 (review .ckl checklists) |
| `02-STIG-Content\` | Lab-DC01 (import into STIG Viewer) |
| `03-SCAP-Content\` | Lab-DC01 (import benchmarks into SCC/OpenSCAP) |
| `05-Nessus-Essentials\` | Lab-DC01 (run credentialed scans from here) |
| `08-CISA-CSET\` | Lab-Workstation01 or your main machine |
| `09-OfflineRootCA-Kit\` | **Lab-OfflineRootCA** (transfer via PowerShell Direct) |
| `10-IssuingCA-Kit\` | Lab-DC01 |

---

## After Tools Are Staged

Go to `Reference\LAB-DAY-CHECKLIST.md` in the Lab-Kit folder and pick up at Phase 4.1 (SCAP SCC scanning).

---

*Related: `Lab-Kit\START-HERE.md` (scripts), `Architecture\FedGov-Tools-Setup-Guide.md` (tool usage)*
