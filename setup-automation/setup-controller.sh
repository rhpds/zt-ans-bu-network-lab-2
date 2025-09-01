#!/bin/bash

USER=rhel

## --------------------------------------------------------------
## Create sudoers using playbook
## --------------------------------------------------------------
cat > /tmp/create_sudoers_user.yml << EOF
---
- name: Setup sudoers
  hosts: localhost
  become: true
  gather_facts: false
  vars:
    ansible_become_password: ansible123!
  tasks:
    - name: Create sudo file
      copy:
        dest: /etc/sudoers.d/rhel_sudoers
        content: "%rhel ALL=(ALL:ALL) NOPASSWD:ALL"
        owner: root
        group: root
        mode: 0440
EOF
/usr/bin/ansible-playbook /tmp/create_sudoers_user.yml
# remove seetup playbook
rm /tmp/create_sudoers_user.yml

## --------------------------------------------------------------
## Manage services
## --------------------------------------------------------------
# sudo systemctl stop systemd-tmpfiles-setup.service
# sudo systemctl disable systemd-tmpfiles-setup.service

## --------------------------------------------------------------
## Install ansible collections
## --------------------------------------------------------------
ansible-galaxy collection install awx.awx
ansible-galaxy collection install ansible.eda
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install microsoft.ad


# --------------------------------------------------------------
# Setup lab assets
# --------------------------------------------------------------
cat > /home/rhel/playbook.yml << EOF
---
### Automation Controller setup 
###
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    GUID: "{{ lookup('env', 'GUID') | default('GUID_NOT_FOUND', true) }}"
    DOMAIN: "{{ lookup('env', 'DOMAIN') | default('DOMAIN_NOT_FOUND', true) }}"

  tasks:
    - name: (EXECUTION) add App machine credential
      ansible.controller.credential:
        name: 'Application Nodes'
        organization: Default
        credential_type: Machine
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false
        inputs:
          username: rhel
          password: ansible123!

    - name: ensure tower/controller is online and working
      uri:
        url: https://localhost/api/v2/ping/
        method: GET
        user: "{{ username }}"
        password: "{{ admin_password }}"
        validate_certs: false
        force_basic_auth: true
      register: controller_online
      until: controller_online is success
      delay: 3
      retries: 5

    - name: set base url
      awx.awx.settings:
        name: AWX_COLLECTIONS_ENABLED
        value: "false"
        <<: *login

    # - name: Add EE to the controller instance
    #   awx.awx.execution_environment:
    #     name: "Network Execution Environment"
    #     image: quay.io/acme_corp/network-ee
    #     <<: *login

    - name: create inventory
      awx.awx.inventory:
        name: "Network Inventory"
        organization: "Default"
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"
        validate_certs: false      
      register: workshop_inventory
      until: workshop_inventory is success
      delay: 3
      retries: 5

    - name: Add cisco host
      awx.awx.host:
        name: cisco
        description: "ios-xe csr running on GCP"
        inventory: "Network Inventory"
        state: present
        <<: *login
        variables:
            ansible_network_os: ios
            ansible_user: ansible
            ansible_host: "cisco"
            ansible_connection: network_cli
            ansible_become: true
            ansible_become_method: enable

    - name: Add backup server host
      awx.awx.host:
        name: "backup-server"
        description: "this server is where we backup network configuration"
        inventory: "Network Inventory"
        state: present
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"
        validate_certs: false      
        variables:
            note: in production these passwords would be encrypted in vault
            ansible_user: rhel
            ansible_password: ansible123!
            ansible_host: "{{ ansible_default_ipv4.address }}"
            ansible_become_password: ansible123!

    - name: Add group
      awx.awx.group:
        name: "network"
        description: "Network Group"
        inventory: "Network Inventory"
        state: present
        validate_certs: false      
        hosts:
          - cisco
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"

    - name: Add network machine credential
      awx.awx.credential:
        name: "Network Credential"
        organization: "Default"
        credential_type: Machine
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"
        validate_certs: false      
        inputs:
          ssh_key_data: "{{ lookup('file', '/root/.ssh/private_key') }}"

    - name: Add controller credential
      awx.awx.credential:
        name: "AAP controller credential"
        organization: "Default"
        credential_type: Red Hat Ansible Automation Platform
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"
        validate_certs: false      
        inputs:
          host: "{{ ansible_default_ipv4.address }}"
          password: "ansible123!"
          username: "admin"
          verify_ssl: false

    - name: Add project
      awx.awx.project:
        name: "Network Toolkit"
        scm_url: "https://github.com/network-automation/toolkit"
        scm_type: git
        organization: "Default"
        scm_update_on_launch: False
        scm_update_cache_timeout: 60
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"
        validate_certs: false  

    - name: Add ansible-1 server host
      awx.awx.host:
        name: "ansible-1"
        description: "this is the report server"
        inventory: "Network Inventory"
        state: present
        controller_username: "{{ username }}"
        controller_password: "{{ admin_password }}"
        controller_host: "https://{{ ansible_host }}"
        validate_certs: false      
        variables:
            note: in production these passwords would be encrypted in vault
            ansible_user: rhel
            ansible_password: ansible123!
            ansible_host: "{{ ansible_default_ipv4.address }}"
            ansible_become_password: ansible123!

EOF
cat /home/rhel/playbook.yml

# --------------------------------------------------------------
# Create facts.yml playbook
# --------------------------------------------------------------
cat >/home/rhel/facts.yml <<EOF
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
/usr/bin/ansible-playbook /home/rhel/playbook.yml

# --------------------------------------------------------------
# set ansible-navigator default settings
# --------------------------------------------------------------
cat >/home/$USER/ansible-navigator.yml <<EOL
---
ansible-navigator:
  ansible:
    inventory:
      entries:
      - /home/rhel/hosts
  execution-environment:
    container-engine: podman
    enabled: true
    image: quay.io/acme_corp/network-ee
    pull:
      policy: never
  logging:
    level: debug
  playbook-artifact:
    save-as: /home/rhel/playbook-artifacts/{playbook_name}-artifact-{time_stamp}.json

EOL
cat /home/$USER/ansible-navigator.yml


# --------------------------------------------------------------
# create inventory hosts file
# --------------------------------------------------------------
cat > /home/rhel/hosts << EOF
cisco ansible_connection=network_cli ansible_network_os=ios ansible_become=true ansible_user=admin ansible_password=ansible123!
vscode ansible_user=rhel ansible_password=ansible123!
EOF
cat  /home/rhel/hosts


# --------------------------------------------------------------
# set environment
# --------------------------------------------------------------
# fix podman issues
loginctl enable-linger $USER
# Pull network-ee latest
# su - $USER -c 'podman pull quay.io/acme_corp/network-ee'

# Creates playbook artifacts dir
mkdir /home/$USER/playbook-artifacts


# --------------------------------------------------------------
# configure ssh
# --------------------------------------------------------------
# Creates ssh dir
mkdir /home/$USER/.ssh

tee /home/rhel/.ssh/config << EOF
Host *
     StrictHostKeyChecking no
     User ansible
EOF

# --------------------------------------------------------------
# create ansible.cfg
# --------------------------------------------------------------
tee /home/rhel/ansible.cfg << EOF
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

# Fix DNS on RHEL9
echo "search $_SANDBOX_ID.svc.cluster.local." >> /etc/resolv.conf

# Work with old school Cisco SSH
update-crypto-policies --set LEGACY

exit 0
