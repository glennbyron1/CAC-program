# Live Servers

**Author:** Glenn Byron
**What this is:** Tools for deploying the CAC/PIV program to real production servers — not the Hyper-V test lab.

---

## Files in This Folder

| File | Purpose |
|------|---------|
| `Test-ServerReadiness.ps1` | Run on any server to see exactly what is installed, what is missing, and the exact command to fix each gap. Safe to run — read-only, changes nothing. |
| `Test-GPOCompliance.ps1` | Tell it a GPO name — it checks if the GPO is linked, applied to this machine, and verifies the actual settings are active in the registry. Includes built-in profiles for smart card, audit policy, and VPN GPOs. |
| `Install-Guide.md` | Step-by-step installation guide organized by server role and phase. |

---

## Start Here

**Step 1 — Run the readiness checker on each server:**

```powershell
.\Test-ServerReadiness.ps1 -ExportReport
```

It auto-detects the server role and checks everything required for that role. The exported report tells you exactly what to fix before you start installing.

**Step 2 — Follow Install-Guide.md.**

Work through each phase in order. The guide references scripts in `Lab-Kit/` — those scripts work on both lab and live servers; just substitute your real domain names for the `agency.gov` and `lab.local` placeholders.

---

## Lab vs Live

| | Lab-Kit | Live-Servers |
|--|---------|--------------|
| **Servers** | Hyper-V VMs (Lab-DC01, Lab-OfflineRootCA, etc.) | Real servers on your network |
| **Domain** | lab.local | agency.gov (your real domain) |
| **Scripts** | Same PowerShell scripts | Same scripts, real values substituted |
| **Readiness check** | Not needed (clean VMs) | Always run Test-ServerReadiness.ps1 first |
| **Scrubbing** | Before GitHub push | Before GitHub push |

The scripts in `Lab-Kit/` are the canonical versions — use them for live deployment too. Just change the parameter values to your real hostnames and domain.

---

*Related: `Lab-Kit/START-HERE.md`, `Tools-Kit/START-HERE.md`, `Architecture/Blueprint.md`*
