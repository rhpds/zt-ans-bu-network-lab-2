#!/bin/bash

tower-cli config verify_ssl false
tower-cli login admin --password ansible123!


if ! tower-cli job_template list -f json | jq -e '.results[] | select(.name | match("Network Automation - Report";"i"))'; then
    echo "You have not launched the 'Network Automation - Report' job template"
    exit 1
fi


cat >/tmp/setup-scripts/check_challenege_2.yml << EOF
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

    - name: Get job from Automation Controller
      uri:
        url: https://{{ aap_hostname }}/api/controller/v2/jobs/
        method: GET
        validate_certs: "{{ aap_validate_certs }}"
        user: "{{ aap_username }}"
        password: "{{ aap_password}}"
        force_basic_auth: yes
      register: jobs

    - name: Extract job names
      set_fact:
        job_names: "{{ jobs.json.results | map(attribute='name') | list }}"

    - name: Fail Job Network Automation - Report is not found
      fail:
        msg: "Job template 'Network Automation - Report' does not exist in Automation Controller!"
      when: "'Network Automation - Report' not in job_names"

EOF

/usr/bin/ansible-playbook /tmp/setup-scripts/check_challenege_2.yml

if [ $? -ne 0 ]; then
    echo "You have not launched the 'Network Automation - Report' job template"
    exit 1
fi