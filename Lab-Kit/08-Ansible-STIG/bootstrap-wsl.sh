#!/usr/bin/env bash
# Phase 8 add-on - provision Ansible + STIG content inside the WSL control node.
# Invoked by Setup-AnsibleControlNode.ps1 as root, with the project path as $1.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

PROJ="${1:-$(cd "$(dirname "$0")" && pwd)}"
VENV="$HOME/ansible-venv"

echo "[*] Project: $PROJ"
echo "[*] apt update + base packages"
apt-get update -y
apt-get install -y python3 python3-venv python3-pip git rsync ca-certificates

echo "[*] Python venv: $VENV"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip wheel >/dev/null

echo "[*] Installing Ansible + WinRM libraries"
"$VENV/bin/pip" install ansible pywinrm requests-ntlm pyspnego

export PATH="$VENV/bin:$PATH"
export ANSIBLE_CONFIG="$PROJ/ansible.cfg"

# persist PATH + ANSIBLE_CONFIG for interactive shells
if ! grep -q 'ansible-venv/bin' "$HOME/.bashrc" 2>/dev/null; then
  {
    echo "export PATH=\"$VENV/bin:\$PATH\""
    echo "export ANSIBLE_CONFIG=\"$PROJ/ansible.cfg\""
  } >> "$HOME/.bashrc"
fi

echo "[*] Installing Galaxy roles + collections into the project"
cd "$PROJ"
ansible-galaxy install   -r requirements.yml -p ./roles --force
ansible-galaxy collection install ansible.windows community.windows -p ./collections

echo
echo "[OK] Control node ready."
echo "     ansible          : $("$VENV/bin/ansible" --version | head -n1)"
echo "     STIG role        : ./roles/Windows-2022-STIG"
echo
echo "Next steps (in WSL):"
echo "   export ANSIBLE_CONFIG=$PROJ/ansible.cfg"
echo "   cd $PROJ"
echo "   # after Enable-WinRM-ForAnsible.ps1 has run on LAB-DC01:"
echo "   ansible dc -m ansible.windows.win_ping --ask-vault-pass"
echo "   ansible-playbook audit-stig.yml --check --diff --ask-vault-pass"
