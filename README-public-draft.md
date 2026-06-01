# CAC/PIV Smart-Card Lab
### A phishing-resistant authentication foundation for Zero Trust

**Author:** Glenn Byron
**License:** MIT — free to use, modify, and share. Attribution required (keep the copyright notice).
**Support this project:** If this saved you time, a tip is always appreciated but never required → [GitHub Sponsors](#) · [Ko-fi](#)

---

## What this is

A fully scripted, infrastructure-as-code lab for standing up a **CAC/PIV smart-card authentication system** on Windows Server with Hyper-V. Everything is automated — from spinning up the VMs to promoting a domain controller, building a two-tier PKI, enrolling smart card certificates, provisioning YubiKeys, and running a compliance scan workflow.

It also includes the full **Risk Management Framework (RMF)** documentation layer: a System Security Plan, SAR, and POA&M template mapped to NIST SP 800-53 Rev. 5 controls, and a SCAP/STIG compliance scan workflow.

This is a **lab and portfolio reference**, not a production deployment guide. It is designed to be honest about what it demonstrates and where the roadmap leads.

---

## What it demonstrates (Zero Trust maturity)

This lab covers the **Identity pillar — authentication leg** of Zero Trust at an Advanced/Optimal level:

- Hardware-bound certificates on CAC cards or YubiKeys (phishing-resistant, AAL3-class)
- Two-tier PKI: offline, air-gapped Root CA + online Enterprise Issuing CA
- Password eliminated entirely — GPO enforces smart-card-only logon
- Two-person enrollment ceremony (Registration Authority + Card Issuer — separation of duties enforced by code)
- CRL and OCSP validation on every authentication event
- EAP-TLS certificate-based VPN (IKEv2, no password prompt)
- Advanced Audit Policy + Windows Event Forwarding
- PKI health monitoring dashboard

**Honest scope statement:** this is the authentication leg done right. Full Zero Trust additionally requires least-privilege authorization, device trust (machine certificates + posture), conditional/continuous access, and microsegmentation. The roadmap for those layers is documented in `Phase-8-Zero-Trust-Extension.md`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Hyper-V Host (your Windows machine)                     │
│                                                          │
│  ┌─────────────────┐   ┌──────────────────────────────┐ │
│  │ Lab-OfflineRootCA│   │ Lab-DC01                     │ │
│  │ (air-gapped)     │   │ Domain Controller            │ │
│  │ Root CA          │──►│ Enterprise Issuing CA        │ │
│  │ No network       │   │ GPO enforcement              │ │
│  └─────────────────┘   │ OCSP responder               │ │
│                         │ WEF collector                │ │
│                         └──────────────────────────────┘ │
│                                    │                      │
│                         ┌──────────▼─────────────────┐   │
│                         │ Lab-Workstation01            │   │
│                         │ Smart card endpoint          │   │
│                         │ VPN client                   │   │
│                         └────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## What you need

- A Windows machine with **Hyper-V** enabled (Windows 10/11 Pro or Enterprise, or Windows Server)
- ~80 GB free disk space for the three VMs
- Windows Server 2022 ISO (evaluation edition is free from Microsoft)
- A CAC reader + card, or a **YubiKey 5** series (for the PIV provisioning path)
- `ykman` (YubiKey Manager CLI) if using YubiKeys — downloaded automatically by the Tools-Kit scripts

---

## Quick start

1. Clone the repo
   ```powershell
   git clone https://github.com/yourusername/CAC-program.git
   cd CAC-program
   ```

2. Start at `Lab-Kit/START-HERE.md` — it has the full run order from VM creation to compliance scanning.

3. The execution checklist is at `Lab-Kit/LAB-DAY-CHECKLIST.md`.

---

## Folder map

| Folder | What's in it |
|--------|-------------|
| `Lab-Kit/01-HyperV-Host/` | VM creation, post-config, snapshots |
| `Lab-Kit/02-OfflineRootCA/` | Air-gapped Root CA ceremony |
| `Lab-Kit/03-DomainController/` | AD domain, Issuing CA, GPO, enrollment, YubiKey, audit |
| `Lab-Kit/04-Workstation/` | Smart card enforcement, VPN client |
| `Lab-Kit/05-Compliance/` | Pre-scan validation, SCAP staging |
| `Tools-Kit/` | Tool downloader (SCAP SCC, STIG Viewer, Nessus) |
| `Architecture/` | Blueprint, network diagram, RMF templates |
| `Portfolio/` | Plain-language explainers for non-technical audiences |
| `Compliance-Reports/` | Before-MFA / After-MFA scan staging folders |

---

## NIST controls demonstrated

This lab addresses the following NIST SP 800-53 Rev. 5 control families:

`IA-2` `IA-2(11)` `IA-5` `IA-5(2)` `AC-5` `AC-11` `AC-17` `SC-8` `SC-17` `AU-2` `AU-9` `AU-12` `CA-7`

Full control mapping is in `Architecture/RMF-Templates/SSP-Template.md`.

---

## Compliance artifacts

- **SCAP SCC** scan workflow (Before-MFA baseline + After-MFA hardened)
- **STIG Viewer** checklists for Windows Server 2022, AD DS, AD CS, and IIS 10
- **Nessus Essentials** credentialed scan workflow
- SAR, POA&M, and SSP templates ready for real scan data

---

## Attribution

If you use this in a project, paper, course, or portfolio, please credit:

> CAC/PIV Smart-Card Lab by Glenn Byron — https://github.com/yourusername/CAC-program

That's all I ask. Enjoy the lab.

---

## Support

This project is free and always will be. If it saved you hours of research or helped you land a job, a tip is a nice way to say thanks:

- [GitHub Sponsors](#) ← set this up at github.com/sponsors
- [Ko-fi](#) ← set this up at ko-fi.com

Neither is required. The code is yours either way.

---

## License

MIT License — see `LICENSE` for the full text. In short: use it, modify it, share it, just keep the copyright notice.

---

## Disclaimer

This is a lab environment built for learning, demonstration, and portfolio purposes. It is not a production-ready deployment. Scripts are designed for isolated Hyper-V VMs; running them against production systems without modification and testing is not recommended. The author is not responsible for any damage, data loss, or security incidents resulting from the use of this software.

STIG, SCAP, and compliance scan results from this lab are for demonstration purposes and do not constitute an actual Authority to Operate (ATO).
