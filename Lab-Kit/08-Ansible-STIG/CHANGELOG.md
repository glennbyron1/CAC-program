# Changelog — 08-Ansible-STIG

## 2026-06-30 — Built the module and hardened LAB-DC01 (44.95% → 86.7%)

I added this `08-Ansible-STIG` module and used it to STIG-harden LAB-DC01 (Windows
Server 2025) with the community ansible-lockdown Windows-2022-STIG role, driven from
a WSL control node. Here's everything I created and changed, and why.

### New files I added
- `Setup-AnsibleControlNode.ps1` — installs WSL2 + Ubuntu on the host and bootstraps Ansible.
- `bootstrap-wsl.sh` — venv + `ansible` + `pywinrm` + `ansible-galaxy install -r requirements.yml`.
- `Enable-WinRM-ForAnsible.ps1` — HTTPS WinRM listener (5986) + NTLM + firewall on the DC.
- `inventory.ini`, `ansible.cfg`, `requirements.yml` — target, config, Galaxy content.
- `group_vars/dc/main.yml` (+ `vault.yml.example`) — connection settings and tuning.
- `audit-stig.yml`, `remediate-stig.yml` — the plays.
- `GUIDE.md`, `CHANGELOG.md` — this guide and history.

### Infrastructure fixes I made along the way
- **Pointed the inventory at the right host.** I first set `10.10.10.10`, but that's the
  Hyper-V host's own `vEthernet (External)` IP. The DC answers on `10.10.10.10`
  (LabInternal) and `10.10.20.10` (External). I settled on `10.10.10.10` reached via
  LabInternal.
- **Resolved a host/DC IP conflict.** The host was holding the DC's `10.10.10.10`, so
  traffic to the DC looped back to the host. I freed it:
  ```powershell
  Remove-NetIPAddress -IPAddress 10.10.10.10 -InterfaceAlias 'vEthernet (External)' -Confirm:$false
  ```

### Server-2025 / ansible-core 2.21 compatibility fixes
Your DC is Server 2025 and your Ansible is core 2.21 — both newer than this role
targets. I made these changes. **If you ever run `ansible-galaxy install -r
requirements.yml --force`, the role edits below revert — re-apply them with the
commands shown.**

1. **Callback** — ansible-core 2.21 removed the `yaml` stdout callback. In `ansible.cfg`
   I switched to `stdout_callback = default` + `result_format = yaml`.

2. **Non-boolean conditionals** — 2.21 errors on them; the role relies on the old
   lenient behavior. In `ansible.cfg`: `allow_broken_conditionals = True` (and I also
   exported `ANSIBLE_ALLOW_BROKEN_CONDITIONALS=True` as a belt-and-suspenders).

3. **OS gate** — the role hard-required Server 2022. I widened it to accept 2025:
   `roles/Windows-2022-STIG/tasks/main.yml`, the `Check OS Version and Family` assert →
   `regex_search('(Microsoft Windows Server 2022|Microsoft Windows Server 2025)')`.

4. **Skipped-variable crashes** — many AUDIT tasks read `.stdout`/`.stderr_lines` from
   gather tasks that skip on a DC, which crashed the run. I added `default()` guards
   across the role's task files. Re-apply with:
   ```powershell
   $enc = New-Object System.Text.UTF8Encoding($false)
   $base = 'C:\path\to\CAC-program\Lab-Kit\08-Ansible-STIG\roles\Windows-2022-STIG\tasks'
   foreach ($name in 'cat1.yml','cat2.yml','cat3.yml','prelim.yml') {
     $f = Join-Path $base $name; $t = [IO.File]::ReadAllText($f)
     $t = [regex]::Replace($t, '\.stdout_lines\b(?!\s*\|\s*default)', '.stdout_lines | default([])')
     $t = [regex]::Replace($t, '\.stderr_lines\b(?!\s*\|\s*default)', '.stderr_lines | default([])')
     $t = [regex]::Replace($t, '\.stdout\b(?!\s*\|\s*default)', ".stdout | default('')")
     $t = [regex]::Replace($t, '\.stderr\b(?!\s*\|\s*default)', ".stderr | default('')")
     # parenthesize guards that are followed by a method/index call
     $t = [regex]::Replace($t, "(?<![\w.])([A-Za-z_]\w*(?:\.\w+)+) \| default\((''|\[\])\)(?=[.\[])", '($1 | default($2))')
     [IO.File]::WriteAllText($f, $t, $enc)
   }
   ```

5. **Controls that don't apply to Server 2025** — disabled in `group_vars/dc/main.yml`:
   - `wn22_00_000090` — TPM check runs `wmic`, removed from Server 2025.
   - `wn22_00_000340` — removes the PNRP feature, which doesn't exist on 2025.
   - `wn22_00_000420` / `wn22_00_000430` — FTP audits; FTP/IIS not installed (N/A).

6. **Safety toggles** — in `group_vars/dc/main.yml` I set `win2022stig_disruption_high:
   false` and `win2022stig_complexity_high: false` so service-disrupting / complex
   remediations are left off. (I initially set the wrong `audit_*` display flags, which
   broke a gather task; corrected to these real toggles.)

### Remediation results
Applied in severity order, snapshotting and re-scanning (SCAP SCC) each tier:

| Stage | Controls changed | SCAP % |
|-------|------------------|--------|
| Baseline | — | 44.95 |
| CAT I (`--tags prelim_tasks,CAT1`) | 8 | 45.41 |
| CAT II (`--tags prelim_tasks,CAT2`) | 96 | 84 |
| CAT III (`--tags prelim_tasks,CAT3`) | 9 | 86.7 |

All three tiers finished with `failed=0` and the DC remained reachable throughout.

### Known limitations
- This role isn't check-mode-safe, so `--check` (in `audit-stig.yml`) breaks; measure
  with SCAP instead.
- The remaining compliance gap is manual AUDIT controls, the disruptive/complex items
  left off by design, and a few 2025-vs-2022 benchmark mismatches.
