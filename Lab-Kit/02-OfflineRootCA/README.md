# 02 — Offline Root CA

The Offline Root CA is built **manually** and kept permanently air-gapped — there
is no auto-build script here by design, because the Root CA must never be exposed
to automation that could connect it to a network.

## What to do

1. **Get the tools first.** The prerequisites for the Offline Root CA are
   downloaded by the tools kit, not stored here. On an internet-connected
   machine run:
   ```powershell
   ..\..\Tools-Kit\Download-OfflineCA-Kit.ps1
   ```
   Copy the resulting transfer kit to USB and carry it to the air-gapped host.

2. **Build the Root CA by hand.** Follow the step-by-step procedure in the Lab
   Build Guide / [`../../Architecture/STIG-Hardening-Guide.md`](../../Architecture/STIG-Hardening-Guide.md)
   and the PKI topology in [`../../Architecture/Blueprint.md`](../../Architecture/Blueprint.md):
   install AD CS as a Standalone Root CA, set the CAPolicy.inf, configure the
   HTTP CDP/AIA, publish the CRL, and export the Root certificate + CRL to USB.

3. **Sign the Issuing CA** request brought over from `03-DomainController`, then
   power the Root CA off and store it offline.

## Why no script here

Air-gap integrity is a security control. A pull-the-NIC, USB-only transfer
workflow is intentionally manual so the Root CA's isolation can be visually
verified at each step. See the air-gap notes in the Lab Build Guide.
