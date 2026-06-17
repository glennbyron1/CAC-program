# CAC Lab Enrollment Session Log
Date: 2026-06-16
Author: Glenn Byron

---

## Scripts Created

| Script | Location | Purpose |
|--------|----------|---------|
| `New-LabUser.ps1` | `Lab-Kit\03-DomainController\` | Create new AD user + hand off to RA phase |
| `Deploy-ScriptsToDC.ps1` | `Lab-Kit\03-DomainController\` | Copy enrollment scripts to Lab-DC01 via SMB |

---

## Issues Encountered & Fixes

### 1. OU prompt accepted bare names — AD rejected them
- **Error:** `New-ADUser: The object name has bad syntax`
- **Cause:** User typed `Users` instead of full DN `CN=Users,DC=lab,DC=local`
- **Fix:** Added `Resolve-OrgUnit` function that auto-resolves bare names via `Get-ADOrganizationalUnit` and `Get-ADObject`, with a numbered menu of known OUs

### 2. OU search returned GPO policy containers
- **Error:** Multiple matches found under `CN=Policies,CN=System`
- **Fix:** Added filter to exclude results containing `CN=Policies` or `CN=System`

### 3. Em dash characters corrupted during file copy
- **Error:** Parse error on `—` character (encoding mismatch between management machine and DC)
- **Fix:** Replaced all em dashes with plain hyphens in scripts

### 4. Array splatting passed `-Mode` as a value instead of parameter name
- **Error:** `Cannot validate argument on parameter 'Mode'. The argument "-Mode" does not belong to the set`
- **Cause:** Used `@()` array splatting — PowerShell passes array elements as positional args
- **Fix:** Switched to `@{}` hashtable splatting so named parameters are passed correctly

### 5. Smart card read-only over RDP to Hyper-V VM
- **Error:** `The smart card is read-only` during cert enrollment in certmgr.msc
- **Cause:** RDP smart card redirection is authentication-only — write operations are blocked
- **Cause:** Hyper-V Manager has no USB passthrough option for Gen2 VMs
- **Fix:** Run enrollment scripts on the Hyper-V HOST (<HYPERV-HOST>) with `-DomainController Lab-DC01`

### 6. Hyper-V USB Passthrough for PIV Cards
- **Problem:** Hyper-V has no native USB passthrough for non-storage devices (PIV/FIDO2 tokens)
- **RDP smart card redirection:** Cards come through read-only — authentication only, no write/enrollment
- **Do NOT join Hyper-V host to domain** — risks losing VM network access
- **Options (best to worst for PIV):**
  1. `usbdevicestoredirect` RDP property — low-level USB redirect, may bypass read-only restriction
  2. Certificate Enrollment Web Service (CEP/CES) on Lab-DC01 — allows non-domain host to enroll via HTTPS
  3. USB-over-IP tools (VirtualHere, AnywhereUSB) — guaranteed but adds cost/complexity
  4. Enhanced Session Mode / RemoteFX — deprecated in newer Windows, unreliable for PIV
- **Fix tried:** CEP/CES install on Lab-DC01 (in progress)

### 7. HIRSCH/Identive uTrust PIV card locked
- **Situation:** Card had unknown management key (not factory default)
- **Attempted:** OpenSC `piv-tool`, `pkcs15-init`, raw APDU reset `00:FB:00:00`
- **Result:** Card is bricked for PIV — PIN and PUK blocked, management key unknown, reset not supported
- **Note:** FIDO2 applet on same card still functional; PIV and FIDO2 are separate applets
- **Note:** RDP read-only was likely masking this issue from the start
- **Fix:** Use a new card; install uTrust minidriver (`uTrustmd_Installer_Ver1.0.0.02_01Jul2025.msi`) before attempting enrollment

### 8. WO02 console logon fails for every account ("invalid credentials, delaying next attempt")
- **Symptom:** Interactive logon at WO02 console fails for jdoe AND CardIssuer with known-good passwords (reset on the single DC; accounts enabled, not locked, BadLogonCount 0)
- **Key clue:** NETWORK logon to WO02 works (Invoke-Command as LAB\Administrator succeeded for minidriver install) but INTERACTIVE/console logon fails
- **Diagnosis:** WO02 enforces "Interactive logon: Require smart card" (`scforceoption = 1`) via GPO on the Workstations OU — this is the smart-card-enforcement lab's intended behavior. Password logon at the console is blocked by design; only a smart card with a valid mapped cert can log in. This is the chicken-and-egg: machine demands a card, but the card has no valid jdoe cert yet.
- **Earlier mistake:** Smartcard Logon cert was enrolled while logged in as CardIssuer, so the cert subject/UPN was CardIssuer, not jdoe — wrong identity for jdoe logon.
- **Fix (simplified path):**
  1. On DC: temporarily unlink the smart-card-required GPO from the Workstations OU (reversible; do NOT delete the GPO)
  2. Reboot WO02 to reapply relaxed computer policy (WinRM DC->WO02 currently down, likely Public/cross-subnet firewall profile)
  3. Log into WO02 console as LAB\jdoe with password, card inserted
  4. certmgr.msc -> request Smartcard Logon cert -> writes jdoe's cert to the card (correct identity via self-enroll, no Enrollment Agent needed)
  5. Verify with `certutil -scinfo` that jdoe's cert is on the card
  6. On DC: re-link the GPO; reboot/gpupdate WO02 to re-enforce smart card
  7. Test jdoe logon at WO02 console with card + PIN
- **Note:** EnrollmentAgent template was published to LAB-CA (`certutil -SetCATemplates +EnrollmentAgent`).

### 9. ROOT CAUSE: physical uTrust card is empty — all enrollments went to a Virtual Smart Card
- **Definitive finding (`certutil -scinfo` on WO02):** The Identive/uTrust physical card reports `Microsoft Base Smart Card Crypto Provider: Missing stored keyset` and `Microsoft Smart Card Key Storage Provider: Missing stored keyset` — i.e. NO keyset, NO certs, never written to.
- **Where everything actually landed:** A `Microsoft Virtual Smart Card 0` (TPM VSC) holds ALL enrolled certs — labtech (x2), CardIssuer, and Jane Doe (`5be8f647...`, UPN `jdoe@lab.local`, chain validates / NT_AUTH OK). The "VR card for LabTech" = this VSC, and it has been the default container silently catching every smart card enrollment.
- **Why:** uTrust PIV applet has no keyset and Windows cannot generate one without the card's PIV management key (unknown — same wall that bricked card #1). The uTrust minidriver only communicates with an already-personalized card; it does not personalize/initialize one. So Windows fell back to the VSC each time, and the `123456` PIN that "worked" was the VSC PIN, not the physical card.
- **Consequence:** jdoe's smartcard logon already WORKS — but on the VSC (software), not the physical card.
- **Options to get a cert onto a real card:**
  - A. Try the factory PIV management key on the *new* uTrust card via OpenSC (`piv-tool -A A:9B:03 -G 9A:07`). Non-destructive — if the key is rejected we stop (do NOT block PIN/PUK; that is what bricked card #1). If it works, generate key in slot 9A and write jdoe's cert.
  - B. Switch to a YubiKey 5 — known default mgmt key `0102...0708`, `ykman`, existing script `New-YubiKeyToken.ps1`. Most reliable physical-card path.
  - C. Accept the VSC for the lab demo (jdoe logon already validated on it).
- **RESULT (Option A tried on card #2):** `piv-tool -r 0 -A A:9B:03 -G 9A:07` → `admin_mode failed -1201`. Factory 3DES management key REJECTED on card #2 as well (same as card #1). No damage — only mgmt-key auth was attempted, PIN/PUK untouched.
- **CONCLUSION:** Both Identive/uTrust cards are dead ends for PIV/AD smartcard logon without the vendor personalization tool + per-card management key (vendor site QR returned 404). FIDO2 applet on the cards still works, but AD logon needs PIV/PKINIT. **Recommended path forward: YubiKey 5 (Option B) using `New-YubiKeyToken.ps1`, or use the working VSC (Option C) for the lab demo.**
- **DECISION (2026-06-16):** Identive/uTrust PIV cards are declared **NO-GO** for this lab unless the vendor's personalization software + per-card PIV management key are purchased/obtained. Do not spend more time on them. **Proceeding with YubiKey 5 via `New-YubiKeyToken.ps1`.**

### 10. YubiKey 5 provisioning via New-YubiKeyToken.ps1 — multiple script bugs fixed
- YubiKey 5 NFC, serial <YUBIKEY-SERIAL>, firmware 5.7.4. ykman 5.9.1 staged manually on WO02 (no internet): `C:\Program Files\Yubico\YubiKey Manager CLI\ykman.exe` (not auto-added to PATH).
- **Firmware 5.7 note:** default PIV management key algorithm is now **AES-192** (value still `0102...0708`). `ykman piv info` confirms.
- **Script bugs found and fixed (host copy `Lab-Kit\03-DomainController\New-YubiKeyToken.ps1`):**
  1. `finally` block referenced `$pin` before it was set → under StrictMode this masked the real error. Fixed: init `$pin = $null` before `try`.
  2. Management key generated as 24 bytes but declared AES-256 (needs 32 bytes). Fixed: `New-Object byte[] 32`.
  3. `Test-TrivialPin` did `.Count` on a possibly-`$null` `Where-Object` result → StrictMode crash on sequential PINs. Fixed: wrap results in `@()`.
  4. `Invoke-Ykman` used `2>&1` with `$ErrorActionPreference='Stop'`, so ykman's "Touch your YubiKey..." stderr prompt aborted the script. Fixed: set EAP=Continue around the native call, judge by exit code. Also changed slot 9a `TouchPolicy` to `never` (no touch needed for logon).
  5. CSR subject used OpenSSL slash format `/CN=.../emailAddress=...`; ykman 5.x needs RFC 4514. Fixed: `CN=<cn>`.
  6. `certreq -submit` was missing the template attribute. Fixed: added `-attrib "CertificateTemplate:<TemplateName>"`.
- **IDENTITY CONSTRAINT (key):** the script's `certreq` submits as the logged-in user, and the `SmartcardLogon` template builds subject + UPN SAN from that user's AD object. So the script MUST be run **as the enrollee (jdoe)** to get jdoe's UPN — running as CardIssuer would issue a CardIssuer cert. Script also requires local admin (lines ~629-631).
- **Finish path CHOSEN = Enroll-on-Behalf (preserves SoD; CardIssuer provisions for jdoe via EA cert).** Requirements specific to YubiKey:
  - YubiKey PIV management key must be **PIN-protected** (`ykman piv access change-management-key --protect --generate -m <default>`) so the Windows minidriver can generate the on-card key using only the PIN (Windows does not know the random AES-256 mgmt key).
  - **Disable the Microsoft Virtual Smart Card** (Device Manager) during enrollment so the Enroll-on-Behalf wizard targets the YubiKey, not the VSC.
  - Steps: reset YubiKey -> PIN-protect mgmt key -> disable VSC -> certmgr (as CardIssuer) Advanced Operations -> Enroll On Behalf Of -> EA cert -> Smartcard Logon template -> target jdoe -> YubiKey -> PIN 123456 -> CA issues jdoe cert (UPN from AD) -> imported. Verify with `certutil -scinfo`, re-enable VSC, jdoe changes PIN, re-enforce SmartCard Policy GPO, test logon.
- **VSC disabled successfully** (LabVSC in Device Manager) — wizard then targeted the YubiKey. **PIN-protect succeeded** (`ykman piv info` shows "Management key is stored on the YubiKey, protected by PIN", AES256).
- **BLOCKER:** Enroll-on-Behalf via certmgr fails with "The smart card is read-only." Cause is NOT RDP/VNC redirection (TightVNC does not redirect smart cards) — it's the **Windows inbox PIV minidriver not supporting on-card key generation** for the YubiKey via CryptoAPI. ykman writes (PC/SC) succeed; only the CryptoAPI enrollment path is blocked.
- **CHOSEN FIX:** Install Yubico's **YubiKey Smart Card Minidriver** on WO02 (stage offline, install, reboot) to add CryptoAPI write support, then retry Enroll-on-Behalf. (Alternative was self-enroll via the ykman script as jdoe, which writes via PC/SC and sidesteps the issue but isn't on-behalf.)
- Installed `YubiKey-Minidriver-5.0.4.273-x64.msi` on WO02 + reboot. Device then showed as "YubiKey Smart Card" (Yubico minidriver loaded). (Unrelated PCA popup about `iqvw64e.sys` = Intel Ethernet driver blocked by the vulnerable-driver blocklist; ignored.)
- First on-behalf retry still failed ("cannot perform the requested operation") because the **manually-set random PIN-protected AES-256 management key conflicted with the Yubico minidriver**, which expects to manage the key from the known **default**. Fix: `ykman piv reset --force` to restore the default management key, then let the minidriver manage it during enrollment.
- **SUCCESS:** After reset-to-default, Enroll-on-Behalf (CardIssuer EA -> Smartcard Logon -> target jdoe -> YubiKey -> PIN 123456) completed. jdoe's cert (CN=Jane Doe, UPN jdoe@lab.local) is now on the physical YubiKey (serial <YUBIKEY-SERIAL>), slot 9a, RSA2048.
- **VERIFIED + LOGON SUCCESS:** `certutil -scinfo` shows jdoe's cert (CN=Jane Doe, OU=SmartCard-Pilot) on the YubiKey reader, chaining to CN=LAB-CA. **jdoe successfully logged into WO02 with the YubiKey + PIN.** Full chain works end to end.
- **Issuer ceremony:** ran as CardIssuer (SoD passed: Administrator RA != CardIssuer). FAILED at the `Set-ADUser -SmartcardLogonRequired` step with "Insufficient access rights" — CardIssuer (even though added to Domain Admins) lacked effective rights in that session / the SmartCard-Pilot OU ACL. **Runbook fix:** delegate "Reset Password" + write `userAccountControl` on the SmartCard-Pilot OU to the Card Issuer (least privilege) instead of relying on Domain Admins.
- **Account enforcement DONE:** set as Administrator — `Set-ADUser -Identity jdoe -SmartcardLogonRequired $true` (verified True; Enabled True, not locked). This randomizes jdoe's password, so the YubiKey is now her only logon. RA flag (pager) cleared.
- **COMPLETE (2026-06-16):** jdoe logs into WO02 with the YubiKey + PIN under full enforcement (`SmartcardLogonRequired=True` + SmartCard Policy GPO re-enabled). VSC junk certs cleaned (stray CardIssuer + jdoe removed; labtech preserved and its LabVSC logon verified). Accidental CardIssuer/jdoe certs revoked in LAB-CA. jdoe removed from WO02 local Administrators. Operator runbook written: `Lab-Kit\03-DomainController\RUNBOOK-YubiKey-Enrollment.md`.

---

## FINAL STATE — SUCCESS
- **jdoe@lab.local** — enrolled on a physical **YubiKey 5 NFC** (serial <YUBIKEY-SERIAL>, slot 9a, RSA2048); smart-card logon **enforced**; logs into WO02 with card + PIN.
- **labtech** — unchanged; logs in via LabVSC.
- **Identive/uTrust cards** — abandoned for PIV (no vendor personalization tool / per-card management key).
- **Deliverables** — `RUNBOOK-YubiKey-Enrollment.md` (operator guide) + this session log.

---

## AD State

| Item | Value |
|------|-------|
| Domain | lab.local |
| DC | Lab-DC01 (Hyper-V VM on <HYPERV-HOST>) |
| New user created | `jdoe@lab.local` (Jane Doe) |
| OU | `OU=SmartCard-Pilot,DC=lab,DC=local` |
| RA phase | Complete — authorized by `LAB\Administrator` at `20260615-144958` |
| Issuer phase | Incomplete — pending card enrollment |
| Card Issuer account | `LAB\CardIssuer` |

---

## Operational Notes

- **Cert identity matters:** A smart card logon cert must carry the ENROLLEE's UPN in the SAN. Enrolling via certmgr while logged in as someone else stamps the wrong identity. Use "Enroll on behalf of" (Enrollment Agent) so the issuer can provision the enrollee's cert — OR have the enrollee self-enroll.
- **One reader vs. two:** Two readers are needed at a production enrollment station when (a) the station enforces smart-card logon AND removal behavior = Lock/Logoff (issuer's card must stay seated), and/or (b) the Enrollment Agent key lives on the issuer's card (both cards in readers during enroll-on-behalf). One reader suffices if the issuer logs in by password or the EA key is in the software store. WO02 removal behavior is currently `Lock Workstation`, confirming the two-reader requirement for production-style enforcement.

## Next Steps (corrected plan)

1. On DC, edit GPO "SmartCard Policy" (linked to OU=Workstations): set **Interactive logon: Require smart card** = **Disabled** (leave "Smart card removal behavior" = Lock Workstation alone). Security options tattoo, so must set Disabled, not just unlink.
2. Reboot WO02 to apply (WinRM DC->WO02 down; can't gpupdate remotely).
3. Log into WO02 as **LAB\CardIssuer** with password (blank card in reader).
4. certmgr.msc -> request **Enrollment Agent** cert for CardIssuer.
5. certmgr.msc -> Personal -> Certificates -> right-click -> All Tasks -> Advanced Operations -> **Enroll On Behalf Of** -> select EA cert -> **Smartcard Logon** template -> target user **jdoe** -> write to card. (Alternative: log in as jdoe and self-enroll.)
6. Enrollee jdoe sets her own PIN.
7. Set `SmartcardLogonRequired = True` on jdoe (Issuer script does this, or manual).
8. On DC, set GPO **Require smart card** back to **Enabled**; reboot WO02 to re-enforce.
9. Test: jdoe logs into WO02 with card + PIN.
10. Finish/re-run the Issuer ceremony (`New-TokenEnrollment.ps1 -Mode Issuer`) for the audit record. Check `-Mode Status` first — if the RA flag was cleared, re-run RA phase before Issuer.

---

## Tools Installed on Lab-DC01

| Tool | Version | Purpose |
|------|---------|---------|
| OpenSC | 0.27.1 | PIV card management, reader detection |
| uTrust Minidriver | 1.0.0.02 (01Jul2025) | Identive/HID uTrust card driver for Windows |
