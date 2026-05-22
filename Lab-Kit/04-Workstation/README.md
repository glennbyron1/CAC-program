# ⚙️ Group Policy Configuration Matrices

**Author:** Glenn Byron

This folder contains the Group Policy automation templates that enforce smart card identity baselines across all domain-joined Windows endpoints.

### 🛡️ Smart Card Behavior Policy Baseline


| Policy Path / Registry Key | Setting Name | Configured Value | Compliance Mapping |
| :--- | :--- | :--- | :--- |
| `System\Logon` | Require smart card for interactive logon | **Enabled** (`scforceoption = 1`) | **NIST IA-2(11)** |
| `System\Logon` | Smart card removal behavior | **Lock Workstation** (`ScRemoveOption = 1`) | **NIST AC-11** |
| `System\Logon` | Interactive logon: Machine inactivity limit | **900 Seconds** (`InactivityTimeoutSecs = 900`) | **NIST AC-11** |
| `Network\Lanman Workstation` | Enable insecure guest logons | **Disabled** | **STIG-WIN-0012** |

### 🚀 Deployment Instructions
To stage these configurations in a test environment, run the accompanying script:
```powershell
.\Enforce-SmartCard.ps1
```
