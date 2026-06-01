# Frequently Asked Questions

**Author:** Glenn Byron

---

## General

**Is this free?**
Yes, completely. MIT license — use it, modify it, share it. The only requirement is that you keep the copyright notice (credit Glenn Byron). If you want to say thanks, there's a tip link in the README, but it's entirely optional.

**Can I use this at work / in a course / in my own portfolio?**
Yes. MIT lets you use and modify this for any purpose. Just keep the copyright notice and don't misrepresent it as your own original work.

**Does this work in a virtual machine on my laptop?**
It's built for Hyper-V on a Windows host. You need Hyper-V enabled (Windows 10/11 Pro or Enterprise, or Windows Server) and enough disk space (~80 GB) and RAM (~12–16 GB free is comfortable). A nested virtualization setup may work but isn't tested.

---

## Smart cards and hardware

**Do I need a real CAC card?**
No. The lab's enrollment scripts work with **YubiKey 5** series devices, which support PIV and cost around $50. A real DoD CAC works too if you have one and a compatible reader. The `New-TokenEnrollment.ps1` path issues certificates from your lab CA, so no real DoD CAC infrastructure is needed.

**What YubiKey model do I need?**
Any YubiKey 5 series (5 NFC, 5C, 5Ci, 5C NFC, or the Nano variants). The key needs to support PIV — all YubiKey 5 models do.

**Do I need ActivClient or any middleware?**
Not for YubiKeys or CardLogix GIDS cards. Windows has a built-in PIV/GIDS minidriver that handles both. For a real DoD CAC you'd need ActivClient or OpenSC — see `Lab-Kit/04-Workstation/README.md` for the middleware table.

**What kind of card reader do I need?**
Any CCID-compliant USB reader. Windows plug-and-play handles the driver automatically — no extra software. $15–30 readers from Amazon work fine.

---

## The PKI and certificates

**Why is there an offline Root CA? Can I skip it?**
The offline Root CA is the trust anchor for the whole system. Skipping it means your Issuing CA would be self-signed, which changes how trust is established. The ceremony (`Initialize-OfflineRootCA.ps1`) is guided and takes about 30 minutes — it's worth doing once to understand why the architecture is built this way. If you truly want to skip it, you can configure a standalone Root CA online, but it's not how the scripts are sequenced.

**Can I use this lab's CA to issue real certificates for production systems?**
No. The `lab.local` CA is self-signed and not trusted by anything outside the lab. Use it only inside your lab environment.

**What's the difference between SmartCardLogon and AdminSmartCardLogon templates?**
SmartCardLogon is for standard users. AdminSmartCardLogon is for privileged accounts — it requires a separate physical card (separation of duties). The templates are created by `New-CertificateTemplates.ps1`.

---

## Compliance and RMF

**Does this give me a real Authority to Operate (ATO)?**
No. The SCAP SCC scans, STIG checklists, and Nessus workflow demonstrate the compliance scan process and produce evidence artifacts, but an ATO requires an actual system, a real Authorizing Official, and a formal RMF package submission. This lab prepares you to do that; it doesn't do it for you.

**Can I use the RMF templates in a real SSP or SAR?**
Yes, as a starting point. The SSP, SAR, and POA&M templates in `Architecture/RMF-Templates/` follow the NIST SP 800-18 / DoD RMF structure. Populate them with your real system data and have your AO/ISSO review before submission.

**What NIST controls does this lab address?**
The primary controls are `IA-2`, `IA-2(11)`, `IA-5`, `IA-5(2)`, `AC-5`, `AC-11`, `AC-17`, `SC-8`, `SC-17`, `AU-2`, `AU-9`, `AU-12`, and `CA-7`. Full mapping is in the SSP template.

---

## Zero Trust

**Is this a Zero Trust implementation?**
It implements the **authentication leg of the Identity pillar** at an Advanced/Optimal level. Full Zero Trust additionally requires least-privilege authorization, device trust, conditional/continuous access, and microsegmentation — those layers are documented in `Phase-8-Zero-Trust-Extension.md` as the roadmap. The lab is honest about what it does and doesn't cover.

**What's the difference between phishing-resistant MFA and regular MFA?**
Regular MFA (SMS codes, authenticator app push notifications) can be phished — an attacker can trick you into approving a fake login. Phishing-resistant MFA (hardware PIV certificates, FIDO2 keys) uses public-key cryptography tied to a specific hardware device, so there's no code to intercept. This is the baseline EO 14028 and OMB M-22-09 require for federal systems.

---

## Troubleshooting

**The script says Hyper-V isn't installed but I'm sure it is.**
Run `New-LabVMs.ps1` as Administrator. It checks for the Hyper-V PowerShell module and the `vmms` service state — both need to be present. If the feature is installed but the service isn't running, try `Start-Service vmms` first.

**git add fails with index.lock error.**
Close VS Code, GitHub Desktop, or any other git GUI that might be holding the lock. Then run `git add -A` again from PowerShell.

**PSScriptAnalyzer CI is failing on my PR.**
Run `Invoke-ScriptAnalyzer -Path . -Recurse` locally and fix the errors (not warnings) before pushing. The workflow fails on hard errors only — warnings are advisory.

**I can't find a script that's listed in START-HERE.md.**
Check that you've cloned the full repo (not just downloaded a zip of an older snapshot). If a script was added in a recent commit, `git pull` should bring it in.

---

*Have a question not answered here? Open an issue on GitHub.*
