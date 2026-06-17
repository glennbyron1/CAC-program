# Manual (GUI) CAC/PIV Enrollment Walkthrough

**Document ID:** RUNBOOK-ICAM-002
**Author:** Glenn Byron
**Companion to:** `Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md` (the scripted version)

---

## What this is

This is the no-scripts version of the YubiKey/PIV enrollment workflow. Every step that `New-LabUser.ps1`, `New-TokenEnrollment.ps1`, and `New-YubiKeyToken.ps1` automate is shown here as the equivalent click path.

Use this when:

- You're learning the underlying workflow (the scripts are a black box until you've done this once by hand)
- You're in a shop that prefers GUI-driven user management
- The scripts are unavailable (locked-down workstation, no PowerShell access, lab environment without ykman installed)
- You need to verify a script result the manual way

The runbook (`RUNBOOK-YubiKey-Enrollment.md`) buys you three things over this walkthrough — an audit trail, forced separation of duties, and sequence safety. The GUI path makes you responsible for those yourself.

---

## Prerequisites (assumed already in place)

- AD CS Enterprise Issuing CA published in `lab.local` (LAB-CA)
- `Smartcard Logon` certificate template published to LAB-CA
- `Enrollment Agent` certificate template published to LAB-CA (if using the Enroll-on-Behalf path)
- `CardIssuer` AD account with the EA cert already enrolled in its Personal store (if using the Enroll-on-Behalf path)
- Yubico Smart Card Minidriver installed on the enrollment workstation (one-time per workstation; the Windows inbox minidriver does not support on-card key generation for YubiKey via CryptoAPI)
- SmartCard Policy GPO defined and linked to the Workstations OU (`scforceoption=1`, `ScRemoveOption=1`)

---

## Step 1 — Create the new user in ADUC by copying a peer

The "copy a peer" pattern: find an existing user who has the same job role / OU placement / group memberships as the new hire, right-click them, and copy. Active Directory clones the source user's OU placement and group memberships (NOT password, login script path, or some attributes) onto the new account.

This is the workflow most shops actually use day-to-day. It works because user accounts in a real org follow patterns — every accountant has the same group memberships, every smart-card pilot user lives in the same OU, every help-desk tech has the same RBAC. Copying a peer who's already correctly configured saves you from re-deriving all of that from scratch.

### How to do it

1. Open `dsa.msc` (Active Directory Users and Computers)
2. Browse to the OU where the peer lives. For a new SmartCard-Pilot enrollee, that's `lab.local → SmartCard-Pilot`. Find an existing pilot user (for example, `labtech`).
3. Right-click the peer → **Copy...**
4. The "Copy Object - User" wizard opens:
   - **First name:** `Jane`
   - **Last name:** `Doe`
   - **Full name:** auto-fills to `Jane Doe`
   - **User logon name:** `jdoe` (UPN suffix `@lab.local`)
   - **Pre-Windows 2000 logon name:** `jdoe`
   - Next
5. **Password screen:**
   - Set an initial password (e.g., `Pilot-2026!`) — this is temporary; it gets randomized in Step 5 when you flip the smart-card-required flag
   - **Uncheck "User must change password at next logon"** — important, because the enrollee may need to log in once with this password during enrollment depending on which path you pick
   - Leave "Account is disabled" unchecked
   - Next → Finish

### What got cloned, what didn't

Active Directory's user copy operation clones some attributes and not others. Worth knowing:

**Cloned automatically:**

- OU placement
- Group memberships
- Logon hours
- Account expires (if set)
- Profile path / home directory pattern (if set)
- Department, Company, Manager (job hierarchy fields)
- "User cannot change password" / "Password never expires" flags

**Not cloned (you set fresh):**

- Password (you set new)
- First/Last/Full name (you set new)
- Logon name / UPN (you set new)
- Email (often you set new)
- Description, Office, Phone, Job Title — these usually need updating to match the new person
- Any attribute that was on the source user but is identity-specific

### What you should double-check after copy

Before closing ADUC, open the new `jdoe` properties and check:

- **General tab:** description, job title, office — update to match the new person, not the peer
- **Account tab:** UPN looks right (`jdoe@lab.local`); "User must change password at next logon" is OFF; "Smart card is required for interactive logon" is OFF for now (we set it in Step 5)
- **Member Of:** matches the peer (this is the whole point of copying — verify it actually inherited)
- **Organization:** Manager field — update if the new person reports to someone different than the peer did

If the source user had stale group memberships (a common reality — people accumulate access over years), remove the stale ones from the new copy now. Copying a peer can silently propagate access creep if you don't audit the result.

---

## Step 2 — Prep the card

This step is identical whether you use scripts or GUI. The physical card has to be in a state where Windows can write to it.

### For a YubiKey 5 (NFC / FIPS / etc.)

Plug the YubiKey into the enrollment workstation. Open PowerShell as Administrator:

```powershell
ykman piv reset --force        # wipes PIV applet to factory defaults
ykman piv info                 # verify it reset
```

The `ykman piv info` output should show `PIN tries remaining: 3/3`, `PUK tries remaining: 3/3`, and a warning that "Using default management key." That warning is what you want — it confirms the management key is at the factory default, which is what the Yubico minidriver expects when it generates the on-card key during Enroll-on-Behalf.

**Why this matters:** in our v1.1 testing we found that a manually-set random AES-256 management key (via `ykman piv access change-management-key --protect --generate`) prevents the Yubico minidriver from generating the on-card key during enrollment. The workaround is to reset first, let the minidriver own the management key during the ceremony, then re-protect it after issuance if your security policy requires that.

### For a Hirsch uTrust FIDO2 FIPS card (or similar non-YubiKey PIV card)

Don't. We declared these NO-GO for PIV in v1.1 testing — both test cards rejected the factory 3DES management key, the vendor minidriver doesn't personalize cards (it expects an already-personalized card), and silent fallback to a TPM Virtual Smart Card masks the failure as success. See `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md` for the full analysis. FIDO2 on these cards works fine; PIV requires the vendor's personalization tool + per-card management key.

### For a TPM Virtual Smart Card (no physical card)

If you're enrolling for a VSC instead of a hardware token:

```powershell
tpmvscmgr.exe create /name LabVSC /AdminKey DEFAULT /PIN DEFAULT /PUK DEFAULT /generate
```

Then verify in Device Manager that "Microsoft Virtual Smart Card 0" appears under Smart Cards.

### Before any physical enrollment — disable the VSC

If a TPM VSC already exists on the workstation, **disable it in Device Manager** before doing a physical-card enrollment. Right-click the VSC entry → Disable Device. Re-enable after the ceremony if the VSC has its own purpose.

This prevents the silent fallback we documented. Windows treats the VSC and the physical reader as equivalent smart card devices, and if anything goes wrong with the physical card, the enrollment can silently land on the VSC without any error. Disabling the VSC forces Windows to fail loud.

---

## Step 3 — Enroll the cert onto the card

Pick one of two paths.

### Path A — Enroll On Behalf Of (preserves separation of duties)

This is the path the runbook uses. It requires the CardIssuer account to have an Enrollment Agent cert in its Personal store. If that's not done yet, here's the one-time setup:

**One-time: give CardIssuer an Enrollment Agent cert**

1. Log in to a workstation as `LAB\CardIssuer`
2. Open `certmgr.msc` (Current User)
3. Personal → Certificates (right-click the Certificates node) → All Tasks → **Request New Certificate**
4. Next through "Before You Begin" → Active Directory Enrollment Policy → Next
5. Check **Enrollment Agent** → Enroll
6. CardIssuer now has an EA cert in Personal\Certificates. It's good for a year (or whatever the template defines) and signs the on-behalf-of requests.

**The enrollment itself**

1. Logged in as `LAB\CardIssuer` on a workstation with the YubiKey plugged in (and the TPM VSC disabled per Step 2)
2. `certmgr.msc` → Personal → Certificates
3. Right-click on the Certificates node (or any existing cert) → **All Tasks → Advanced Operations → Enroll On Behalf Of...**
4. Wizard pages:
   - **Before You Begin** → Next
   - **Select Enrollment Agent Certificate**: Browse → pick the CardIssuer's EA cert (Enhanced Key Usage will show "Certificate Request Agent") → Next
   - **Select Certificate Enrollment Policy**: Active Directory Enrollment Policy → Next
   - **Request Certificates**: check **Smartcard Logon** → if you don't see it, the template wasn't published to LAB-CA (run `certutil -SetCATemplates +SmartcardLogon` on the CA and retry) → Next
   - **Select a user**: type `LAB\jdoe` or click Browse → pick jdoe from `SmartCard-Pilot` OU → click **Enroll**
5. Windows pops a "Select a smart card device" dialog. Pick **`Yubico YubiKey OTP+FIDO+CCID 0`**.

   > **CRITICAL:** if you see `Microsoft Virtual Smart Card 0` in this picker, you forgot to disable the VSC in Step 2. Cancel the wizard, disable the VSC, start over. This is the silent-fallback failure mode.

6. PIN prompt → enter the YubiKey PIV PIN (factory default is `123456`)
7. Wait — the wizard generates the keypair on-card, requests the cert from LAB-CA, and writes the issued cert back to the card. This takes a few seconds.
8. "Certificate Installation Results: Smartcard Logon — STATUS: Succeeded" → Finish

The cert is now on the YubiKey, slot 9a, with `CN=Jane Doe, OU=SmartCard-Pilot` as the subject and `jdoe@lab.local` as the UPN in the SAN.

### Path B — Self-enroll (simpler, no separation of duties)

If you don't need the audit trail of who issued the cert (small shop, low compliance bar, lab environment), the enrollee can request the cert themselves. This is less ceremony but requires temporarily relaxing the smart-card-required GPO so jdoe can log in with the temp password.

1. **On a domain controller**, open `gpmc.msc` → SmartCard Policy GPO linked to Workstations OU → right-click → **Edit**
2. Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → Security Options → **"Interactive logon: Require smart card"**
3. Set to **Disabled** (NOT "Not Defined" — security options tattoo onto the workstation, and "Not Defined" leaves the previous setting in place)
4. Close GPMC
5. **Reboot the enrollment workstation** (`gpupdate /force` does not reliably re-apply security options; the reboot does)
6. Log in to the workstation as `LAB\jdoe` with the temp password, YubiKey plugged in (TPM VSC still disabled from Step 2)
7. `certmgr.msc` → Personal → Certificates → right-click → All Tasks → **Request New Certificate**
8. Next → Active Directory Enrollment Policy → Next → check **Smartcard Logon** → Enroll
9. Select smart card device → **`Yubico YubiKey OTP+FIDO+CCID 0`** (same VSC-trap warning as Path A applies)
10. PIN prompt → enter `123456`
11. Status: Succeeded → Finish
12. **On the domain controller**: flip the GPO setting back to **Enabled**
13. Reboot the workstation to re-enforce

This path inherently has no audit record of who issued the cert beyond AD CS's standard issuance event. If you ever need to answer "who provisioned jdoe's card," the answer is "jdoe did, herself" — which fails most regulated-environment audit standards.

---

## Step 4 — The acceptance check (mandatory regardless of path)

This is the step that catches the silent VSC fallback failure mode. Run it after every enrollment. From an admin PowerShell on the enrollment workstation:

```powershell
certutil -scinfo
```

This walks every smart card reader the Windows smart card subsystem can see and prints what's on each card.

**What you're looking for:**

| Check | What it should say |
|---|---|
| Reader name | `Yubico YubiKey OTP+FIDO+CCID 0` — NOT `Microsoft Virtual Smart Card N` |
| Subject | `CN=Jane Doe, OU=SmartCard-Pilot, DC=lab, DC=local` |
| SAN (Subject Alternative Name) | An "Other Name" entry: `Principal Name=jdoe@lab.local` |
| EKU (Verified Application Policies) | `1.3.6.1.4.1.311.20.2.2` (Smart Card Logon) and `1.3.6.1.5.5.7.3.2` (Client Authentication) |
| Issuer | `CN=LAB-CA, DC=lab, DC=local` |
| Final line | `CertUtil: -SCInfo command completed successfully.` |

**Fail conditions — any of these means revoke the cert at the CA and start over:**

- The cert appears on `Microsoft Virtual Smart Card N` instead of the YubiKey reader → silent VSC fallback occurred
- The cert subject is `CardIssuer` (or whoever was logged in) instead of `Jane Doe` → wrong identity (probably Path B was used while logged in as the wrong account)
- The UPN in the SAN doesn't match the target user → wrong identity again
- Chain doesn't validate to LAB-CA → CA trust chain broken on the workstation
- `certutil -scinfo` reports `Missing stored keyset` on the YubiKey reader → the enrollment didn't actually land on the card

This four-check verification is the operator's last line of defense against shipping a credential that lives on the wrong factor.

---

## Step 5 — Enforce smart card on the AD account

This is the GUI equivalent of `Set-ADUser -Identity jdoe -SmartcardLogonRequired $true`.

1. In ADUC, browse to `SmartCard-Pilot` OU
2. Right-click `jdoe` → **Properties** → **Account** tab
3. In the **Account options** list, check **"Smart card is required for interactive logon"**
4. Click **Apply** → OK

**What just happened:** Windows blew away `jdoe`'s password and replaced it with a random 240-character value (the actual implementation detail varies by Windows version but the effect is the same). There is no longer any password that works for `jdoe`. The YubiKey + PIN is now her only logon method.

**Verify:** Reopen Properties → Account tab. The "Smart card is required for interactive logon" box should be checked. The password field is greyed out / shows "**" — that's the random-password state.

If you ever need to remove smart card enforcement (employee leaves, card lost), uncheck the box AND set a new temporary password before the user can log in again. Unchecking alone leaves the password in random-state.

---

## Step 6 — Enrollee changes the PIN

The YubiKey ships with PIV PIN `123456` (published in Yubico's docs). The enrollee has to change it before they leave the enrollment desk.

### Option A — at the lock screen (Windows credential UI)

1. Ctrl + Alt + Del → **Change a password**
2. The credential picker shows **Password** and **Smart card** options — pick **Smart card**
3. Old PIN: `123456`
4. New PIN: their choice
5. Confirm new PIN
6. OK

PIN rules to enforce verbally (since the GUI doesn't enforce them):

- Minimum 6 digits (YubiKey allows 6–8)
- No sequential (`123456`, `654321`)
- No repeating (`111111`)
- No date of birth, phone number, address number, last four of SSN

### Option B — from PowerShell while jdoe is logged in

```powershell
ykman piv access change-pin
```

This prompts for old PIN, new PIN, and confirmation. Same rules apply.

---

## Step 7 — Test the logon

End-to-end smoke test that everything works:

1. Lock the workstation: `Win + L`
2. Pull the YubiKey out of the reader, plug it back in (forces the lock screen to re-enumerate)
3. The lock screen should show:
   - The username `jdoe@lab.local` (or "Other user" with a Security device sign-in option)
   - A PIN field — NOT a password field
   - No "switch to password" option visible
4. Enter the new PIN → desktop appears

### Protocol-level proof

On the domain controller, open Event Viewer → Windows Logs → Security. Filter for Event ID **4768**. Find the most recent entry for `jdoe@lab.local`. The key fields:

| Field | Expected value |
|---|---|
| Account Name | `jdoe@lab.local` |
| Pre-Authentication Type | **16** (PKINIT — certificate-based pre-auth) |
| Result Code | **0x0** (success) |
| Certificate Information | The cert thumbprint matches jdoe's issued cert |

`Pre-Authentication Type: 16` is the cryptographic fingerprint that this was a smart card logon, not a password. Anything else (`2` for example) means Kerberos pre-auth ran on something other than the card.

### Lock-on-removal test

1. With jdoe logged in, pull the card out
2. Within 1–2 seconds the workstation should lock

This is the `ScRemoveOption=1` GPO behavior. If it doesn't lock, the GPO isn't applied to the workstation.

---

## Mapping: GUI clicks vs. scripts

For reference — every step above maps to a script in the kit. This table is the round-trip:

| Script step | GUI equivalent in this walkthrough |
|---|---|
| `New-LabUser.ps1` | Step 1 — Copy peer in ADUC, fill in name/UPN |
| `New-TokenEnrollment.ps1 -Mode RA` | Manually verify two forms of ID + paper attestation; no GUI equivalent for the audit log |
| `New-TokenEnrollment.ps1 -Mode Issuer` | Step 3 Path A — Enroll On Behalf Of wizard |
| `New-YubiKeyToken.ps1` | Step 2 (`ykman piv reset`) + Step 3 + Step 6 (PIN change) combined |
| `Set-ADUser -SmartcardLogonRequired $true` | Step 5 — Account tab checkbox |
| Script's verification of certutil -scinfo | Step 4 — operator runs it and reads it manually |

The scripts buy you, in priority order:

1. **An audit log.** Every script writes to `C:\Windows\Logs\TokenEnrollment.log` and the Windows Application Event Log. The GUI leaves nothing beyond AD's standard object-modification audit.
2. **Forced separation of duties.** The script structurally cannot let one person be both RA and Issuer in the same transaction (NIST SP 800-53 AC-5). The GUI relies on the operator remembering to switch accounts.
3. **Sequence safety.** The script ordering — "reset YubiKey BEFORE enrollment," "disable VSC BEFORE enrollment," "re-enable VSC AFTER," "verify cert landed on the right reader," "set SmartcardLogonRequired only after verification passes" — is enforced. The GUI lets you skip any step.

For a small shop with one or two enrollments a year, the GUI is fine. For a regulated environment where the Authorizing Official is going to ask "show me who provisioned this card," the script trail is what answers them.

---

## Troubleshooting checklist

If the manual flow fails at any step, these are the most common causes:

| Symptom | Most likely cause | Fix |
|---|---|---|
| "Smartcard Logon" template missing from the Request Certificates list | Template not published to LAB-CA | On CA: `certutil -SetCATemplates +SmartcardLogon` |
| "Enrollment Agent" template missing | Template not published to LAB-CA | On CA: `certutil -SetCATemplates +EnrollmentAgent` |
| "The smart card cannot perform the requested operation" | Yubico minidriver not installed; or YubiKey mgmt key isn't at factory default | Install `YubiKey-Minidriver-x.x.x.x-x64.msi`, reboot; `ykman piv reset --force` |
| "The smart card is read-only" (from certmgr) | Same as above (Yubico minidriver missing / mgmt key not default) | Same fix |
| Wizard shows `Microsoft Virtual Smart Card 0` instead of YubiKey | VSC wasn't disabled before enrollment | Cancel, Device Manager → disable LabVSC → retry |
| Cert ends up on the VSC after the wizard says success | Silent VSC fallback (Issue #9) | Revoke cert at CA, disable VSC, reset YubiKey, retry. See Lessons-Learned doc. |
| Cert subject says `CardIssuer` instead of the enrollee | Enrolled via Request New Certificate while logged in as CardIssuer (Path B done wrong) | Revoke cert at CA, use Enroll On Behalf Of (Path A) or log in as the enrollee for Path B |
| `Set-ADUser -SmartcardLogonRequired` fails with "Insufficient access rights" | The account running it isn't a Domain Admin / lacks delegated rights on the OU | Run as Administrator, or delegate "Write userAccountControl" + "Reset Password" on the OU to the CardIssuer role |
| Lock screen still shows password field | GPO not applied (workstation not in Workstations OU, or `gpupdate` didn't catch it) | Verify computer object is in Workstations OU; reboot the workstation |
| Card doesn't lock on removal | `ScRemoveOption` GPO not applied | Same — verify OU placement, reboot |

---

## Related documents

- `Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md` — the scripted version of this same workflow
- `Lab-Kit/Reference/Card-Test-Matrix.md` — hardware behavior matrix; YubiKey PIV row + Hirsch NO-GO finding
- `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md` — the failure mode this walkthrough's Step 4 acceptance check defends against
- `Architecture/Lessons-Learned/2026-06-16-CAC-Enrollment-Session.md` — raw forensic session log from the v1.1 enrollment work that produced these procedures
- `Architecture/RMF-Templates/SSP-Template.md` — NIST control mapping for the overall ICAM program
