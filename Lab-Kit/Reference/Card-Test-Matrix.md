# Card Test Matrix

**Author:** Glenn Byron
**Last Updated:** 2026-06-16
**Purpose:** Evidence-based comparison of smart card / hardware token form factors tested against the lab's CAC/PIV ICAM architecture. Hardware behavior only — no vendor pricing, roadmap, or commercial-engagement detail.

---

## Test scope

Card testing is ongoing — this matrix grows as new form factors are evaluated. Cards tested so far:

| Card | Form factor | Reader required | Tested against |
|---|---|---|---|
| YubiKey 5 NFC | USB-A token with NFC | None (built-in USB) | webauthn.io, Lab-DC01 Issuing CA |
| Hirsch uTrust FIDO2 FIPS card | ID-1 card (credit-card form factor) | Identive SCR33xx v2.0 USB SC Reader | webauthn.io, Lab-DC01 Issuing CA |

**On deck for testing (cards on hand or queued):**

- GIDS PKI smart cards (Generic Identity Device Specification — Windows has a built-in GIDS minidriver, so PIV enrollment may work without a vendor minidriver install)
- Additional smart-card form factors (vendor / implementation TBD)
- Any future YubiKey models added to the lab (e.g., 5 NFC FIPS for higher-assurance comparison)

Each new card form factor gets a row added to every section below.

---

## Detection (working tree, `certutil -scinfo`)

| Card | Detected by Windows | Reader ATR | PIV applet present | Notes |
|---|---|---|---|---|
| YubiKey 5 NFC | ✅ Yes — `Yubico YubiKey OTP+FIDO+CCID 0` | `3b fd 13 00 00 81 31 fe 15 80 73 c0 21 c0 57 59 75 62 69 4b 65 79 40` (ASCII tail: `ubiKey@`) | ✅ `Identity Device (NIST SP 800-73 [PIV])` | Fresh, no cert enrolled; `NTE_BAD_KEYSET` expected on first scan |
| Hirsch uTrust FIDO2 FIPS | ✅ Yes — `Identive SCR33xx v2.0 USB SC Reader 0` | `3b f6 96 00 00 91 01 31 fe 45 75 54 72 75 73 74 5b` (ASCII tail: `uTrust[`) | ✅ `Identity Device (NIST SP 800-73 [PIV])` | Confirms PIV applet IS loaded on the FIDO2 SKU — answers an open question from v1.0 TODO |

---

## FIDO2 / WebAuthn (webauthn.io)

| Card | Registration | Authentication | Reported transports | Credential type | AAGUID via webauthn.io | PIN prompted? | Touch required? |
|---|---|---|---|---|---|---|---|
| YubiKey 5 NFC | ✅ Success (`glenntest-yubikey`, both `none` and `direct` attestation) | ✅ Success | `nfc`, `usb` | device-bound passkey | `00000000-...` even with `Attestation: direct` — Windows anonymizes attestation data | ✅ Yes — required to set FIDO2 PIN on first registration; required to enter PIN on subsequent operations | ✅ Yes — touch on gold disc |
| Hirsch uTrust FIDO2 FIPS | ✅ Success (`glenntest-hirsch`, both `none` and `direct` attestation) | ✅ Success | `ble`, `nfc`, `usb` | device-bound passkey | `00000000-...` even with `Attestation: direct` — Windows anonymizes attestation data | ✅ Yes — PIN prompted (FIPS card behavior — required for every operation) | N/A (contact card, no touch sensor) |

**Observations:**

- **Hirsch advertises BLE transport in addition to NFC and USB** — relevant for mobile / no-USB-port use cases. The YubiKey 5 NFC model does not have BLE (separate YubiKey models — 5Ci, 5C NFC FIPS — add BLE).
- Both registered as `device-bound passkey` — hardware-bound credential, cannot be exported. This rules out "sync to phone" workflows but is the right model for high-assurance.
- **AAGUID is anonymized by Windows even with `Attestation: direct` requested.** This is by design — Windows strips identifying attestation data for privacy/fingerprinting resistance. To retrieve real AAGUIDs, use device-side CLI tools (e.g., `ykman fido info` for YubiKey) or vendor metadata services. Enterprise IdP allowlisting works through enrollment attestation chains, not web-anonymized AAGUIDs.
- **PIN behavior differs:** YubiKey required PIN setup on first FIDO2 registration, then prompts for entry on subsequent operations. Hirsch FIDO2 FIPS prompts for PIN every operation (FIPS behavior — required for every cryptographic operation).
- **Browser passkey-manager conflict** observed: Bitwarden browser extension intercepted the WebAuthn flow and offered to create a software passkey before the hardware authenticator. Workaround: close / disable Bitwarden's WebAuthn handler temporarily. Real UX issue for any FIDO2 deployment in environments where users have password managers with passkey support.
- Each card tested individually (cards swapped between tests, not simultaneous).

---

## PIV enrollment (Lab Issuing CA)

| Card | PIV applet reset | Keypair generation slot 9a | CSR generation | Cert issued by LAB-CA | Imported back to card | `certutil -scinfo` shows cert | AD UPN mapping | Smart-card logon to lab.local |
|---|---|---|---|---|---|---|---|---|
| YubiKey 5 NFC | ✅ `ykman piv reset --force` | ✅ RSA2048 in slot 9a (Yubico minidriver via Enroll-on-Behalf) | ✅ via certmgr / `certreq` | ✅ `CN=Jane Doe, OU=SmartCard-Pilot` from LAB-CA | ✅ written to card | ✅ chain validates on `Yubico YubiKey OTP+FIDO+CCID 0` reader | ✅ UPN `jdoe@lab.local` via Smartcard Logon template SAN | ✅ logged into WO02 with card + PIN under `SmartcardLogonRequired=True` |
| Hirsch uTrust FIDO2 FIPS (n=2) | ❌ factory 3DES mgmt key rejected on both cards (OpenSC `admin_mode failed -1201`) | ❌ blocked — no usable mgmt key | n/a | n/a | n/a | n/a — silent fallback to TPM VSC observed (see Lessons-Learned) | n/a | n/a |

**PIV enrollment observations:**

- **YubiKey path that worked:** reset PIV applet → install Yubico Smart Card Minidriver on workstation → disable TPM VSC in Device Manager → Enroll-on-Behalf from CardIssuer with Enrollment Agent cert → write to YubiKey slot 9a → re-enable VSC → enrollee changes PIN → `Set-ADUser -SmartcardLogonRequired $true`.
- **Why the Yubico minidriver was required:** the Windows inbox PIV minidriver does not support on-card key generation for the YubiKey via the CryptoAPI enrollment path. Without the Yubico minidriver, certmgr returns `The smart card is read-only`.
- **Why mgmt key must be PIN-protected OR factory-default during enrollment:** the Yubico minidriver expects to manage the key from the known default. A manually-generated random AES-256 mgmt key (set via `ykman piv access change-management-key --protect --generate`) prevents the minidriver from generating the on-card key during Enroll-on-Behalf. Fix: `ykman piv reset --force` before the ceremony, let the minidriver own the key, then re-protect post-issuance if required.
- **Hirsch n=2 finding (both cards):** the uTrust PIV applet is present (`Identity Device (NIST SP 800-73 [PIV])` returned by `certutil -scinfo`) but the factory 3DES management key is rejected. The vendor minidriver assumes an already-personalized card; it does not personalize one. Conclusion: the Hirsch uTrust FIDO2 FIPS card is a **NO-GO** for PIV/AD smart-card logon without the vendor's per-card management key + personalization tool. FIDO2 applet on the same card works fine.
- **Silent VSC fallback during Hirsch attempts:** every "successful" enrollment landed on `Microsoft Virtual Smart Card 0` (TPM-backed), not the physical card. Detected via `certutil -scinfo`. See `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md` for full analysis and detection methodology.

---

## VPN EAP-TLS (WatchGuard / Azure VPN Gateway when ready)

> Test pending — slot 5 capture queued. YubiKey is enrolled and ready; Hirsch is NO-GO for PIV so EAP-TLS is not applicable for that form factor.

| Card | VPN profile import | Cert selected by EAP-TLS | Tunnel established | DNS resolution through tunnel |
|---|---|---|---|---|
| YubiKey 5 NFC | ⬜ | ⬜ | ⬜ | ⬜ |
| Hirsch uTrust FIDO2 FIPS | n/a (PIV NO-GO) | n/a | n/a | n/a |

---

## Reset / lifecycle behavior

> Test pending — captures the "what if user forgets PIN" workflow.

| Card | PIN retry counter behavior | PUK unblock procedure | Factory reset procedure | Recovery if PUK exhausted |
|---|---|---|---|---|
| YubiKey 5 NFC | (default: 3 PIN attempts, then PUK; PUK 3 attempts, then card unusable for PIV until factory reset via management key) | `ykman piv access unblock-pin` | `ykman piv reset` | Reset wipes all PIV data; card remains functional |
| Hirsch uTrust FIDO2 FIPS | [TBD — FIPS cards typically more restrictive] | [TBD] | [TBD] | [TBD] |

---

## Compliance / certification claims (vendor-stated; verified where possible)

| Card | FIPS 140-3 level | TAA-compliant | NIST AAL claim | CJIS-aligned claim | Notes |
|---|---|---|---|---|---|
| YubiKey 5 NFC | Level 1 (5 series); FIPS 140-3 Level 2 available on Yubico's separate FIPS SKU | Yes (Yubico TAA-compliant SKU available) | AAL3 capable (with PIN + presence) | Yes — Yubico publishes CJIS guidance | The non-FIPS 5 NFC is the most common consumer SKU; for federal use cases the YubiKey 5 NFC FIPS SKU is the right line |
| Hirsch uTrust FIDO2 FIPS | FIPS 140-3 (vendor-stated) | Yes (vendor-stated) | AAL3 capable | Vendor materials reference CJIS alignment | FIPS certification is the primary differentiator vs. standard FIDO2 cards |

> Verification of vendor claims requires checking the published CMVP certificate at https://csrc.nist.gov/projects/cryptographic-module-validation-program. Update this row with the verified CMVP cert number after lookup.

---

## Summary observations (will expand as more cards are tested)

1. **Both cards advertise PIV applets.** The Hirsch advertising itself primarily as FIDO2 doesn't mean PIV is absent — confirmed via `certutil -scinfo` showing `Identity Device (NIST SP 800-73 [PIV])` on both. "PIV applet present" and "PIV applet usable" are not the same thing.
2. **Dual-applet support is the architectural fit for hybrid AD + cloud environments.** PIV for AD/Windows smart-card logon (Kerberos PKINIT). FIDO2 for cloud/passwordless (WebAuthn). One card, two protocols, one credential body. Worth verifying on every new card form factor.
3. **Transport differences matter.** Hirsch's BLE advertisement opens mobile pairing scenarios that the YubiKey 5 NFC (non-Ci) does not support without an adapter.
4. **Both registered as device-bound passkeys** — appropriate for high-assurance environments where credential portability (cross-device sync) is undesirable.
5. **Vendor personalization tooling is the critical procurement question.** A card whose PIV applet ships with an unknown per-card management key requires the vendor's personalization software and a per-card management-key lookup — that's an operational cost that's often invisible in vendor marketing. The Hirsch uTrust NO-GO finding turned on exactly this. Next card to test should be evaluated against the same question early: can it be brought to a known-management-key state with off-the-shelf tooling (ykman, OpenSC, GIDS minidriver), or does it require vendor-specific software?

---

## Open items to fill in

- [x] ~~PIN-prompt behavior on YubiKey FIDO2~~ — confirmed: required on first registration (set PIN) and on subsequent operations (enter PIN)
- [x] ~~PIN-prompt behavior on Hirsch FIDO2 FIPS~~ — confirmed: prompted for PIN, FIPS card behavior
- [x] ~~Touch-required behavior on YubiKey~~ — confirmed: touch on gold disc required
- [x] ~~AAGUID via webauthn.io with direct attestation~~ — captured, anonymized to all-zero by Windows; need device-side CLI for real AAGUID
- [ ] Real AAGUID values via `ykman fido info` (YubiKey) and equivalent for Hirsch
- [x] ~~PIV enrollment workflow for YubiKey~~ — complete, see PIV row above; runbook at `Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md`
- [x] ~~PIV enrollment workflow for Hirsch~~ — declared NO-GO; requires vendor personalization tool + per-card management key
- [x] ~~Smart-card logon to lab.local with YubiKey~~ — `jdoe` logs into WO02 with card + PIN
- [x] ~~Lock screen, session-lock-on-removal screenshots (slots 1, 4)~~ — captured (`01-lockscreen-smartcard-only.png`, `04-session-lock-on-card-removal.png`)
- [ ] VPN EAP-TLS test with YubiKey (slot 5, depends on VPN config)
- [ ] Slot 5 VPN-connected screenshot
- [ ] Verified CMVP FIPS certificate numbers (cross-reference with NIST CMVP database)

---

*Related: `Lab-Kit/Reference/ONBOARDING.md`, `Lab-Kit/Reference/TROUBLESHOOTING.md`, `Portfolio/Federal_Upgrade_Path.docx`*
