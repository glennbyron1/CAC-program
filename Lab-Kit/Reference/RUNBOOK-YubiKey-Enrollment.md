# YubiKey Smart Card Enrollment — Operator Runbook

**Purpose:** Issue a smart-card-logon credential on a YubiKey to a new user, start to finish.
**Audience:** enrollment operators (Registration Authority + Card Issuer). Assumes the PKI, scripts,
and workstation are already set up (see *One-Time Setup*). No script editing required.

**Document ID:** RUNBOOK-ICAM-001 · Author: Glenn Byron
**This lab's values:** Domain `lab.local` · CA `Lab-DC01.lab.local\LAB-CA` · User OU `SmartCard-Pilot`
· Enrollment workstation `WO02` · Templates `SmartcardLogon`, `EnrollmentAgent`

---

## Roles (separation of duties — two different people)

| Role | Does | Example account |
|------|------|-----------------|
| **Registration Authority (RA)** | Verifies the enrollee's identity in person | `Administrator` |
| **Card Issuer** | Provisions the physical YubiKey | `CardIssuer` |

The RA and Card Issuer **must be different accounts** — the scripts enforce this.

---

## One-Time Setup (done once for the whole environment)

1. **Publish the certificate templates on the CA** (Lab-DC01):
   ```powershell
   certutil -SetCATemplates +EnrollmentAgent
   # SmartcardLogon is already published in this lab
   ```
2. **Give the Card Issuer an Enrollment Agent (signing) certificate.** On a domain machine, logged in
   **as the Card Issuer**: `certmgr.msc` → Personal → Certificates → All Tasks → **Request New
   Certificate** → check **Enrollment Agent** → Enroll. *(Restrict who may request this template — an
   Enrollment Agent cert can enroll on behalf of anyone.)*
3. **Delegate rights to the Card Issuer on the user OU** (`SmartCard-Pilot`) so the Issuer can enable
   "smart card required" without being a Domain Admin: grant **Reset Password** and **Write
   userAccountControl** (Active Directory Users & Computers → right-click OU → Delegate Control).
4. **Prepare the enrollment workstation** (domain-joined, e.g. WO02):
   - Install **ykman** (YubiKey Manager CLI).
   - Install the **Yubico "YubiKey Smart Card Minidriver"**, then **reboot**.
   - The YubiKey must plug **directly** into this workstation. **Do enrollment at the console or over
     VNC — not over RDP** (RDP redirects the card read-only).

---

## Per-User Enrollment

### Step 1 — RA: create the account and verify identity
Logged in as the **RA**, from the scripts folder:
```powershell
.\New-LabUser.ps1 -FirstName Jane -LastName Doe -Domain lab.local
```
- Choose the target OU (e.g. `SmartCard-Pilot`).
- Complete the identity-verification checklist (two forms of government ID).
- The account is created and the RA authorization flag is set.

### Step 2 — Card Issuer: prep the YubiKey
Logged in as the **Card Issuer** at the enrollment workstation, YubiKey inserted. Reset the token so
the Yubico minidriver manages the management key:
```powershell
ykman piv reset --force
```
*(Leaves the default PIN `123456` and default management key — the minidriver uses and PIN-protects it
automatically. Do **not** manually set a custom management key; it conflicts with the minidriver.)*

If a **virtual smart card** is present on the workstation, disable it during enrollment so the wizard
targets the YubiKey: Device Manager → **Smart card readers** → right-click the VSC → **Disable**
(re-enable afterward).

### Step 3 — Card Issuer: enroll on behalf of the user
`certmgr.msc` → Personal → Certificates → All Tasks → **Advanced Operations → Enroll On Behalf Of**:
1. **Browse** → select the Card Issuer's **Enrollment Agent** cert → Next.
2. Check the **Smartcard Logon** template.
3. **Select the target user** (the enrollee, e.g. `jdoe`).
4. **Enroll** → choose the **YubiKey** device → enter the PIN (`123456`).

The CA issues the enrollee's cert — built from *their* AD identity (correct UPN) — onto the YubiKey.

### Step 4 — Verify
```powershell
certutil -scinfo | Select-String "Reader:|Subject:"
```
Confirm the **YubiKey** reader shows the enrollee (`CN=Jane Doe …`) chaining to `CN=LAB-CA`.
Re-enable any VSC you disabled in Step 2.

### Step 5 — Enrollee sets their PIN
Hand the token to the enrollee. They change the PIN off the default — Windows: `Ctrl+Alt+Del → Change a
password → Smart Card`, or `ykman piv access change-pin`. **The Card Issuer must not know the final PIN.**

### Step 6 — Enforce smart-card logon (turn off password)
- **Account level** (Card Issuer with delegated rights, or an admin):
  ```powershell
  Set-ADUser -Identity jdoe -SmartcardLogonRequired $true
  ```
  This randomizes the account password — the card becomes the only way in.
- **Machine level** (per workstation, via GPO): `Interactive logon: Require smart card` = **Enabled**,
  then reboot the workstation.

### Step 7 — Test
The enrollee logs in with the **YubiKey + their PIN**. Done.

---

## Notes & Gotchas (why the steps are the way they are)

- **Do card work on a physical domain workstation.** Hyper-V VMs (incl. the DC) have no USB
  smart-card passthrough.
- **Never enroll over RDP.** RDP redirects the smart card **read-only**, so key generation fails.
  Use the console or VNC (VNC does not redirect the card).
- **Let the Yubico minidriver manage the management key.** YubiKey firmware 5.7+ ships with an
  **AES-192** default management key. Resetting and letting the minidriver handle it "just works";
  manually setting a random/PIN-protected key causes *"cannot perform the requested operation."*
- **"The smart card is read-only"** during enrollment = either you're over RDP, or the **Yubico
  minidriver isn't installed** on the workstation.
- **Identive/uTrust PIV cards are not usable here** — they require the vendor's personalization tool
  and the per-card management key. Use YubiKeys. (Their FIDO2 applet works, but AD logon uses PIV.)
- **Separation of duties:** the Issuer phase (`New-TokenEnrollment.ps1 -Mode Issuer`) refuses to run
  under the same account that performed the RA phase — by design.
