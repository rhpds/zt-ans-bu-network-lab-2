#!/bin/bash

cat >/tmp/setup-scripts/check_challenege_1.yml << EOF
---
- name: setup controller for network use cases
  hosts: localhost
  connection: local
  gather_facts: false
  collections:
    - ansible.controller
  vars:
    aap_hostname: localhost
    aap_username: admin
    aap_password: ansible123!
    aap_validate_certs: false
  tasks:
    - name: Get job templates from Automation Controller
      uri:
        url: https://{{ aap_hostname }}/api/controller/v2/job_templates/
        method: GET
        validate_certs: "{{ aap_validate_certs }}"
        user: "{{ aap_username }}"
        password: "{{ aap_password}}"
        force_basic_auth: yes
      register: job_templates

    - name: Print job template names
      debug:
        msg: "{{ job_templates.json.results | map(attribute='name') | list }}"
    
    - name: Extract job template names
      set_fact:
        template_names: "{{ job_templates.json.results | map(attribute='name') | list }}"

    - name: Fail template Network Automation - Report is not found
      fail:
        msg: "Job template 'Network Automation - Report' does not exist in Automation Controller!"
      when: "'Network Automation - Report' not in template_names"

EOF

/usr/bin/ansible-playbook /tmp/setup-scripts/check_challenege_1.yml

if [ $? -ne 0 ]; then
    echo "You have not created the 'Network Automation - Report' job template"
    exit 1
fi