#!/bin/bash

tee /home/rhel/solve_challenege_2.yml << EOF
---
- name: solve lab2 challenge 2
  hosts: localhost
  gather_facts: false
  become: true
  tasks:
    - name: Create network report job template
      awx.awx.job_template:
        name: "Network Automation - Report"
        job_type: "run"
        organization: "Default"
        inventory: Network Inventory
        project: "Network Toolkit"
        playbook: "playbooks/network_report.yml"
        credentials:
          - "Network Credential"
        state: "present"
        controller_config_file: "/tmp/setup-scripts/controller.cfg"

    - name: Launch network report job
      awx.awx.job_launch:
        job_template: "Network Automation - Report"
        controller_config_file: "/tmp/setup-scripts/controller.cfg"
EOF

sudo chown rhel:rhel /home/rhel/solve_challenege_2.yml

su - rhel -c 'ansible-playbook /home/rhel/solve_challenege_2.yml'

