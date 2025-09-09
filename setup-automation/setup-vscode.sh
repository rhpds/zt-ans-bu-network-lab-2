#!/bin/bash

USER=rhel

# --------------------------------------------------------------
# Reconfigure code-server
# --------------------------------------------------------------
sudo su - -c 'systemctl stop firewalld'
sudo su - -c 'systemctl stop code-server'
mv /home/${USER}/.config/code-server/config.yaml /home/${USER}/.config/code-server/config.bk.yaml

cat >/home/${USER}/.config/code-server/config.yaml << EOF
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF

cat >/home/${USER}/.local/share/code-server/User/settings.json <<EOL
{
  "git.ignoreLegacyWarning": true,
  "window.menuBarVisibility": "visible",
  "git.enableSmartCommit": true,
  "workbench.tips.enabled": false,
  "workbench.startupEditor": "readme",
  "telemetry.enableTelemetry": false,
  "search.smartCase": true,
  "git.confirmSync": false,
  "workbench.colorTheme": "Solarized Dark",
  "update.showReleaseNotes": false,
  "update.mode": "none",
  "ansible.ansibleLint.enabled": false,
  "ansible.ansible.useFullyQualifiedCollectionNames": true,
  "files.associations": {
      "*.yml": "ansible",
      "*.yaml": "ansible"
  },
  "files.exclude": {
    "**/.*": true
  },
  "security.workspace.trust.enabled": false
}
EOL
cat /home/${USER}/.local/share/code-server/User/settings.json

sudo su - -c 'systemctl start code-server'

# --------------------------------------------------------------
# Create facts.yml playbook
# --------------------------------------------------------------
cat >/home/${USER}/facts.yml <<EOF
---
- name: Gather information from routers
  hosts: cisco
  gather_facts: false

  tasks:
    - name: Gather router facts
      cisco.ios.ios_facts:
        gather_subset: all
      register: all_facts

    - name: Display version
      ansible.builtin.debug:
        msg: "The IOS version is: {{ ansible_net_version }}"

    - name: Display serial number
      ansible.builtin.debug:
        msg: "The serial number is:{{ ansible_net_serialnum }}"

    - name: Display all facts
      ansible.builtin.debug:
        var: all_facts
EOF

# --------------------------------------------------------------
# set ansible-navigator default settings
# --------------------------------------------------------------
tee >/home/${USER}/ansible-navigator.yml <<EOL
---
ansible-navigator:
  ansible:
    inventory:
      entries:
        - /home/${USER}/hosts
  execution-environment:
    container-engine: podman
    enabled: true
    image: quay.io/acme_corp/network-ee
    pull:
      policy: missing
  logging:
    level: debug
  playbook-artifact:
    save-as: /home/${USER}/playbook-artifacts/{playbook_name}-artifact-{time_stamp}.json

EOL
cat /home/${USER}/ansible-navigator.yml

# --------------------------------------------------------------
# create inventory hosts file
# --------------------------------------------------------------
tee > /home/${USER}/hosts << EOF
cisco ansible_connection=network_cli ansible_network_os=ios ansible_become=true ansible_user=admin ansible_password=ansible123!
vscode ansible_user=${USER} ansible_password=ansible123!
EOF
cat  /home/${USER}/hosts

# --------------------------------------------------------------
# create ansible.cfg
# --------------------------------------------------------------
cat > /home/${USER}/ansible.cfg << EOF
[defaults]
# stdout_callback = yaml
connection = smart
timeout = 60
deprecation_warnings = False
action_warnings = False
system_warnings = False
host_key_checking = False
collections_on_ansible_version_mismatch = ignore
retry_files_enabled = False
interpreter_python = auto_silent
[persistent_connection]
connect_timeout = 200
command_timeout = 200
EOF
cat /home/${USER}/ansible.cfg

# --------------------------------------------------------------
# set environment
# --------------------------------------------------------------
# Fixes an issue with podman that produces this error: "Error: error creating tmpdir: mkdir /run/user/1000: permission denied"
sudo su - -c 'loginctl enable-linger ${USER}'

# Creates playbook artifacts dir
mkdir /home/${USER}/playbook-artifacts

# --------------------------------------------------------------
# configure ssh
# --------------------------------------------------------------
mkdir /home/${USER}/.ssh
cat >/home/${USER}/.ssh/config << EOF
Host *
     StrictHostKeyChecking no
     User ansible
EOF
cat /home/${USER}/.ssh/config

# Work with old school Cisco SSH
sudo su - -c "update-crypto-policies --set LEGACY"

exit 0
