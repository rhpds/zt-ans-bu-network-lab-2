#!/bin/bash

mkdir /tmp/setup-environment/
setup_env_dir=/tmp/setup-environment

cat > ${setup_env_dir}/solve_challenege_2.yml << EOF
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
    - name: Create network report job template
      ansible.controller.job_template:
        name: "Network Automation - Report"
        job_type: "run"
        organization: "Default"
        inventory: Network Inventory
        project: "Network Toolkit"
        playbook: "playbooks/network_report.yml"
        credentials:
          - "Network Credential"
        state: "present"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}" 

    - name: Launch network report job
      ansible.controller.job_launch:
        job_template: "Network Automation - Report"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "https://{{ aap_hostname }}"
        validate_certs: "{{ aap_validate_certs }}" 
EOF
sudo su - -c "ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/ /usr/bin/ansible-playbook ${setup_env_dir}/solve_challenege_2.yml"
