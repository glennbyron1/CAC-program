# Project Narrative — CAC/PIV Lab

**Author:** Glenn Byron
**Last Updated:** 2026-06-30 (v1.4)
**Purpose:** The story of this project in my own words. Doubles as interview prep
and as a re-orientation guide for me when I come back to this repo in 6 months
and need to remember why I made every decision I made.

This is intentionally informal and first-person. The formal write-ups live in
`Portfolio/`. The technical reference lives in `Architecture/` and the
runbooks live in `Lab-Kit/`. This doc is the one you read if you want the
story behind the artifacts.

---

## Quick orientation if I'm coming back to this in 6 months

If I open this repo cold and need to remember what I was doing, the path is:

1. Read this file's "Tell me about this project" answer below — it covers the
   whole arc in 4 paragraphs.
2. Open `TODO.md` and scroll to the latest **Recent Wins** block. The most
   recent block is what I shipped most recently and is the freshest context.
3. Open `Architecture/Lab-Topology.md` — it tells me which VMs are on which
   network and what changed when.
4. Open `Lab-Kit/START-HERE.md` if I'm about to rebuild the lab.
5. The five Portfolio `.docx` files have a v1.4 milestone callout on page 1 — fastest
   way to remember what the latest release was about.

If I'm trying to figure out a specific past decision, search `Architecture/Lessons-Learned/`
or the dated `Bug-Fix-Logs/` folders — those are where I wrote down the
"why" at the moment, not after the fact.

---

## Interview-style Q&A

### 1. Tell me about this project. What is it?

I built a working model of the same secure-login system the U.S. Department
of Defense uses across its enterprise — Common Access Cards (CAC) and PIV
smart cards instead of passwords. It runs on Hyper-V virtual machines on my
own hardware, with a two-tier Public Key Infrastructure (an offline Root CA
plus an Enterprise Issuing CA), Active Directory with smart-card-required
Group Policy, hardware tokens (YubiKey 5), certificate-based VPN, OCSP
revocation, Windows Event Forwarding, and a full DISA STIG/SCAP/Nessus
compliance scan workflow. Around 80 PowerShell scripts, all idempotent and
parse-checked, version-controlled with CI lint on every push.

On top of the build, I documented it the way a federal program would — System
Security Plan, Security Assessment Report, Plan of Action & Milestones
(POA&M), Risk Acceptance Register, NIST SP 800-53 control mapping. The
documentation is in `Architecture/RMF-Templates/`. The scan evidence is in
`Compliance-Reports/` with real SCAP scores (44.95% before hardening, 86.7%
after the v1.4 Ansible STIG remediation pass).

I also built a Phase 8 Zero Trust extension — 21 PowerShell modules covering
RBAC with AGDLP nesting, Kerberos authentication policy silos, device
posture checks, conditional access via Microsoft.Graph, workload mTLS,
microsegmentation, and a SIEM analytics feedback loop using native Windows
Event Collector. That extension layers Zero Trust controls onto the hardened
STIG substrate the v1.4 Ansible pass produced — not as a replacement for
baseline hardening, but as overlays that assume one.

The whole thing is published at github.com/glennbyron1/CAC-program under MIT
license.

### 2. Why did you build this?

Federal agencies and DoD contractors are required to retire passwords and
move to phishing-resistant MFA — usually via CAC or PIV. The technology
itself isn't a secret. What's a secret to anyone outside the federal world is
how the program documentation, the RMF workflow, and the STIG/SCAP toolchain
all fit together in practice. Most job postings in this space ask for
"experience with CAC/PIV programs" or "RMF artifact development." You
typically get that experience by working inside an existing federal program.
I wanted to short-circuit the catch-22: build it at home, produce evidence
artifacts a hiring manager would recognize, and document it in the same
register a federal program would.

That's also why I treat the documentation as deliverables on the same
footing as the code. The POA&M, the SAR, the Risk Acceptance Register — they
look like federal artifacts because they ARE federal artifacts. If I gave
this repo to a contractor's project manager, the documents would slot into
their workflow without rewriting.

### 3. What was the hardest thing you debugged?

The Silent TPM Virtual Smart Card Fallback (Issue #9, June 2026). I was
enrolling user certificates from the Issuing CA onto a physical YubiKey. The
enrollment ceremony showed `Status: Success` and the certificate landed in
the user's personal store. But when I tried to log in, the lock screen
refused the card. After hours of looking at the wrong things, I ran
`certutil -scinfo` and found that the certificate had been silently routed
to a Windows TPM-backed Virtual Smart Card called `Microsoft Virtual Smart
Card 0` — not the physical YubiKey at all. There was no warning. No error.
The enrollment process succeeded against a software-emulated card even
though a physical reader and card were both present.

This is a hardware-factor assurance failure. The whole point of CAC/PIV is
that the private key lives on a tamper-resistant physical device the user
carries. If the OS silently rolls over to a VSC, you've got a `Success`
status on enrollment but you no longer have a hardware MFA factor — you have
software MFA backed by the TPM. That distinction matters for NIST IA-2(11)
compliance.

I wrote up the discovery, the detection methodology (a four-point operator
acceptance check that pulls the AAGUID from the slot 9a certificate and
confirms it matches the physical token's vendor AAGUID), and the remediation
in `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`.
That doc maps the issue to NIST IA-2(11), IA-5(11), CM-6, and AU-6. It's
also the artifact I'd point any hiring manager toward if they asked "show me
a real DevSecOps finding you've made."

A close runner-up: the PKI Health Monitor parameterized run that surfaced
five separate bugs in one session on 2026-06-04 (documented in
`Lab-Kit/03-DomainController/Bug-Fix-Logs/PKIHealth-2026-06-04-five-fixes.txt`).
I had been running the script in baseline mode with no parameters, where
every check gracefully returned `[SKIP]`. The first parameterized run hit
real CRL endpoints and real Issuing CA cert paths, and that's when the bugs
came out — string-vs-array comparison failures, missing AIA extension
parser, wrong CRL fetch path. I fixed all five in one session and the audit
log proves it (seven script invocations across the day, all clean by
evening).

### 4. What would you do differently next time?

Three things.

First, I'd commit to a single benchmark version earlier. I built against
Windows Server 2022 STIG 2.3.10, then started using Server 2025 ISOs because
that's what Microsoft was shipping. The community ansible-lockdown role I
used for v1.4 hard-required Server 2022. I had to patch the role's OS-gate
regex to accept Server 2025 AND disable four controls that don't apply to
2025 (TPM/wmic, PNRP, FTP audits). All of that is documented in
`Lab-Kit/08-Ansible-STIG/CHANGELOG.md` and re-applyable, but the friction
came from mixing benchmark versions. Next time I'd standardize on the
benchmark version first and pick the OS to match it.

Second, I'd plan the network topology more carefully. I started with the DC
on Lab External (10.10.20.10) as a single NIC. When I went to do the v1.4
Ansible work, I needed the WSL control node on the Hyper-V host to reach the
DC, and the host's own 10.10.10.1 IP on Lab Internal made that path
awkward. I added a second NIC to the DC at 10.10.10.10 — but the host's
`vEthernet (External)` adapter was already holding that address, so my first
attempt looped back to the host. I had to free the IP with
`Remove-NetIPAddress` and then the path worked. Fine outcome, but if I'd
sketched the reach paths up front, that NIC plan would have been there from
the start.

Third, I'd be more disciplined about line endings. The repo lives on a
Windows machine, but I do a lot of editing through tools that don't preserve
the original CRLF. After every editing session I have a `git status` that
shows 150+ "modified" files when only 15 actually changed. The fix is a
proper `.gitattributes` `* text=auto eol=lf` rule and a `git add
--renormalize .` once, but I should have set that up on day one rather than
fighting it every commit.

### 5. How did you decide on the architecture?

I followed the DoD reference architecture verbatim where it made sense and
documented the gap honestly where it didn't.

The two-tier PKI (offline Root CA + Enterprise Issuing CA) is the federal
canonical model. It's how every CAC/PIV program is structured. The Root CA's
job is to sign exactly one thing — the Issuing CA's certificate — and then
go back in the safe. That structure means even if my Issuing CA's private
key is compromised, the Root remains uncompromised and I can re-issue from a
new Issuing CA. That's why the Root is air-gapped (no network adapter at
all), the ceremony is operator-driven, and the cert has a 10-year validity
with `pathlen:0` so it can't be used to sign any further sub-CAs.

The smart-card-required GPO (`scforceoption=1`) is also canonical. It tells
the Local Security Authority to refuse Kerberos pre-authentication unless
the request comes from a smart card. Combined with `ScRemoveOption=1`
(force lock on card removal), that's the policy combination that produces a
"no card, no session" workstation.

Where I deviated honestly: the lab is a single flat L2 segment with logical
IP groupings ("Internal" 10.10.10.x and "External" 10.10.20.x) carried over
one Hyper-V External vSwitch to a dumb unmanaged switch. That's NOT NIST
SC-32 system partitioning — partitioning requires VLANs (managed switch) or
an L3 router between segments. I documented that gap explicitly in
`Architecture/Lab-Topology.md` as the "honest caveat on partitioning." A
hiring manager who reads the doc sees "Glenn knows the difference between a
designed control and a deployed one." That's the federal documentation
pattern.

### 6. How do you know it actually works?

I have evidence at three layers.

**Behavior evidence (screenshots in `Screenshots/`).** Eight demo-walkthrough
slots are captured: the lock screen showing "Sign-in options: Smart card,"
the PIN entry, the Event 4768 record showing Pre-Auth Type 16 (PKINIT)
against the user's certificate, the workstation locking within 2 seconds of
YubiKey removal, the Azure Point-to-Site VPN showing "Connected" via EAP-TLS
without a password prompt, the PKI health dashboard showing all green, and
the SCAP score climb (44.95% → 86.7%).

**Compliance evidence (`Compliance-Reports/`).** Real SCAP SCC scan archives
preserved at every checkpoint. Before-MFA baseline (May 27). After-MFA (May
28). After-Ansible CAT II interim (84.4%, June 30). After-Ansible CAT III
final (86.7%, June 30). The XCCDF XML for each is in the archive — I can
cross-check any STIG rule's pass/fail against the actual finding.

**Audit evidence (PKI Health Monitor logs at `Compliance-Reports/PKI-Health/`).**
Seven separate `Monitor-PKIHealth.ps1` invocations across 2026-06-04, all
returning `Critical: False | Warning: False`. That's the NIST CA-7 continuous
monitoring pulse — not "I checked once and walked away," but a script that
runs on a schedule and produces dated audit log entries.

The POA&M (`Architecture/RMF-Templates/POAM-Template.md`) ties each finding
to its evidence. POA-001 says "AutoPlay must be turned off for non-volume
devices." Its Document Control row 1.4 says "verified passing in post-Ansible
SCAP scan 2026-06-30, evidence at Compliance-Reports/After-Ansible/." That's
an auditor-ready closure trail, not a check-the-box claim.

### 7. What's the federal-employment angle?

Three roles are realistic targets given what this lab demonstrates:

- **ICAM Engineer / PKI Engineer** at a federal agency, defense contractor,
  or DISA. The two-tier PKI build, certificate template lifecycle, OCSP/CRL
  publication, and smart-card enrollment ceremony are the bread and butter of
  that role.
- **DevSecOps Engineer** with a federal-compliance bend. The CI pipeline,
  PSScriptAnalyzer lint, secret scanning, idempotent scripts, and the
  ansible-lockdown remediation pipeline are direct evidence of the
  "automate the security controls" practice that role asks for.
- **RMF / Compliance Analyst / ISSE** on a federal program. The SSP, SAR,
  POA&M, Risk Acceptance Register, and STIG/SCAP/Nessus workflow are the
  artifacts that role produces every day.

What I don't yet have: production federal-program experience, an active
clearance, or a CISSP/Security+/CAP cert. The lab is the way I close the
"experience" gap on paper.

### 8. What's NOT in this lab that a real DoD program would have?

The honest list:

- **Hardware Security Module for the CA private keys.** Federal PIV requires
  CA keys in a FIPS 140-3 Level 3 HSM. This lab uses software key storage,
  which is correct for a lab and most enterprises but not for a federal
  trust anchor.
- **Cross-certification to the Federal Bridge CA (FBCA)** per NIST SP 800-217.
  The lab's `lab.local` Root CA is not trusted by anything outside the lab.
- **Tokens on the GSA FIPS 201 Approved Products List.** YubiKey 5 is a PIV
  device but it's not on the GSA APL — that list is reserved for tokens that
  have gone through a specific federal evaluation pipeline.
- **Derived PIV credentials via a federal-grade kiosk** per NIST SP 800-157.
  Useful for mobile and other-form-factor authenticators; out of scope for a
  laptop-based lab.
- **A real Authorizing Official.** I self-assessed as the AO for the lab and
  signed the SSP/SAR. A real ATO requires an actual federal AO and a formal
  RMF package submission.

`Architecture/Federal-Compliance-Upgrade.md` maps the delta between this lab
and a full federal PIV program. None of these gaps are design defects;
they're procurement decisions and program-level prerequisites. The
architecture, scripts, and RMF documentation already in place would carry
over to a federal-grade upgrade.

### 9. How would this scale to a real organization?

The scripts are written to scale, but the operational model would have to
change.

At lab scale (3 VMs, one user, one card), I'm the operator, the issuer, the
auditor, and the AO. At organization scale, those roles split. The
Registration Authority and Card Issuer separation is already enforced in the
enrollment script (`AC-5 Separation of Duties` — the same account is blocked
from completing both phases). At org scale you'd staff each role with
different people and tie the script's `RA-User` and `Card-Issuer-User`
parameters to AD security groups.

Certificate template lifecycle would extend from manual review to automated
template publishing via a configuration-management system (Ansible, DSC). The
PKI Health Monitor would move from `Compliance-Reports/PKI-Health/` text logs
to a SIEM with alerts. The single SCAP scan workflow would parallelize
across N hosts. The Ansible STIG remediation would run from a CI runner, not
a WSL control node on the Hyper-V host.

`Portfolio/CAC-Scaling-50-to-500.docx` walks through the operational scaling
math (key tracking, card issuance throughput, helpdesk impact) for a typical
agency 50-to-500-user expansion.

### 10. What did this teach you beyond what's in the artifacts?

Three things that don't fit neatly into a script comment or a POA&M entry:

**Honest documentation is a competitive advantage.** Most lab portfolios
claim 100% compliance and zero failures. Mine has a Hirsch uTrust NO-GO
finding documented in the `Card-Test-Matrix.md`, a "design says two-tier,
deployment is single-tier" PKI architecture discovery in the Azure VPN guide,
a Silent VSC Fallback discovery in the Lessons-Learned folder, and a
"remaining gap is by design" disposition for every open POA&M finding. That
honesty is the federal documentation pattern. Hiring managers who've worked
in federal programs recognize it on sight.

**The hard part of compliance is the diff between baseline and target.**
Anyone can run a SCAP scan. The expertise is in dispositioning each finding
(remediate / risk-accept / mark N/A / defer to manual review) with a
defensible rationale, then producing the evidence trail that shows the
remediation was actually applied. That's why the POA&M Document Control rows
1.0 → 1.4 each include the headline finding count plus the disposition
narrative.

**Iteration is the work.** Looking at the GitHub release history (v1.0 →
v1.4 across six weeks), each release is a real shift: v1.0 baseline,
v1.1 smart-card enrollment + Silent VSC Fallback discovery, v1.2 Azure VPN
+ "same card unlocks AD AND VPN," v1.4 Ansible STIG 44.95% → 86.7%. Nothing
was big-bang. Every release built on a specific working piece from the
previous one.

---

## Things I learned the hard way that aren't elsewhere in the repo

- `Scrub-Repo.ps1` treats every key in `.scrub-patterns.local.json` as a
  pattern. If you put a `_README` comment key in the JSON, you'll get
  spurious hits everywhere. Patched the script to skip `_*` keys.
- The Yubico minidriver and the Microsoft inbox minidriver fight if both
  load. Yubico wins as long as it's installed first.
- `New-LabSnapshot.ps1` checkpoints break if the VM has dynamic memory
  enabled and the host is under memory pressure — the snapshot creates but
  the rollback fails silently. I now check `Get-VM | ?{$_.DynamicMemoryEnabled}`
  before snapshotting.
- The PSScriptAnalyzer lint rule `PSAvoidUsingReservedParams` flagged
  `-Host` as a parameter name on `New-Finding` in the cert-audit script.
  PowerShell's `$Host` is an automatic variable. Renamed to `-Hostname`.
- The community ansible-lockdown role's check-mode is not safe — running
  with `--check` crashes on state-gather tasks because they're written
  assuming the gather already ran. Measure with SCAP, not Ansible
  `--check`.

---

*If something here is wrong or stale and I'm reading this in 6 months,
trust the `TODO.md` Recent Wins log and the POA&M Document Control history
over this narrative. Those are the dated, evidence-backed records. This doc
is the orientation map.*
