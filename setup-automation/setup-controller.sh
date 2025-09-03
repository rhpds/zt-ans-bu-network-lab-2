#!/bin/bash

USER=rhel

## --------------------------------------------------------------
## Create sudoers using playbook
## --------------------------------------------------------------

cat > /tmp/setup-scripts/create-sudo-user.yml << EOF
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
/usr/bin/ansible-playbook /tmp/setup-scripts/create-sudo-user.yml

## --------------------------------------------------------------
## Install ansible collections
## --------------------------------------------------------------
ansible-galaxy collection install awx.awx
ansible-galaxy collection install ansible.eda
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install microsoft.ad
ansible-galaxy collection install containers.podman

# --------------------------------------------------------------
# Setup lab assets
# --------------------------------------------------------------
cat > /tmp/setup-scripts/configure-controller.yml << EOF
---
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    aap_hostname: localhost
    aap_username: admin
    aap_password: ansible123!
    aap_validate_certs: false
  tasks:
    - name: ensure tower/controller is online and working
      uri:
        url: https://{{ aap_hostname }}/api/controller/v2/ping/
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        validate_certs: false
        force_basic_auth: true
      register: _r_controller_online
      until: _r_controller_online is success
      delay: 3
      retries: 5

    - name: Add network machine credential
      ansible.controller.credential:
        name: "Network Credential"
        organization: "Default"
        credential_type: Machine
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}"      
        inputs:
          username: "admin"
          password: "ansible123!"

    - name: Add controller credential
      ansible.controller.credential:
        name: "AAP controller credential"
        organization: "Default"
        credential_type: Red Hat Ansible Automation Platform
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}"     
        inputs:
          host: "{{ ansible_default_ipv4.address }}"
          username: "admin"
          password: "ansible123!"
          verify_ssl: false

    - name: Add EE to the controller instance
      ansible.controller.execution_environment:
        name: "Network Execution Environment"
        image: quay.io/acme_corp/network-ee
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}" 

    - name: Add project
      ansible.controller.project:
        name: "Network Toolkit"
        scm_url: "https://github.com/network-automation/toolkit"
        scm_type: git
        organization: "Default"
        scm_update_on_launch: False
        scm_update_cache_timeout: 60
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}"

    - name: create inventory
      ansible.controller.inventory:
        name: "Network Inventory"
        organization: "Default"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}"     
      register: _r_workshop_inventory
      until: _r_workshop_inventory is success
      delay: 3
      retries: 5

    - name: Add cisco host
      ansible.controller.host:
        name: cisco
        description: "ios-xe csr running on GCP"
        inventory: "Network Inventory"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}" 
        variables:
            ansible_network_os: ios
            ansible_user: admin
            ansible_password: ansible123!
            ansible_host: "cisco"
            ansible_connection: network_cli
            ansible_become: true
            ansible_become_method: enable

    - name: Add backup server host
      ansible.controller.host:
        name: "backup-server"
        description: "this server is where we backup network configuration"
        inventory: "Network Inventory"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}" 
        variables:
            note: in production these passwords would be encrypted in vault
            ansible_host: "{{ ansible_default_ipv4.address }}"
            ansible_user: rhel
            ansible_password: ansible123!
            ansible_become_password: ansible123!

    - name: Add ansible-1 server host
      ansible.controller.host:
        name: "ansible-1"
        description: "this is the report server"
        inventory: "Network Inventory"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}"      
        variables:
            note: in production these passwords would be encrypted in vault
            ansible_host: "{{ ansible_default_ipv4.address }}"
            ansible_user: rhel
            ansible_password: ansible123!
            ansible_become_password: ansible123!

    - name: Add group
      ansible.controller.group:
        name: "network"
        description: "Network Group"
        inventory: "Network Inventory"
        state: present
        hosts:
          - cisco
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}"

EOF
cat /tmp/setup-scripts/configure-controller.yml
sudo su - -c "ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/ /usr/bin/ansible-playbook /tmp/setup-scripts/configure-controller.yml"

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

# Work with old school Cisco SSH
sudo su - -c "update-crypto-policies --set LEGACY"

exit 0
