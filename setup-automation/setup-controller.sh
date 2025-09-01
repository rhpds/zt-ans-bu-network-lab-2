#!/bin/bash

USER=rhel


# --------------------------------------------------------------
# Setup Sudoers 
# # --------------------------------------------------------------
# echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
# chmod 440 /etc/sudoers.d/rhel_sudoers


# --------------------------------------------------------------
# Setup lab assets
# --------------------------------------------------------------
# Write a new playbook to create a template from above playbook
cat > /home/rhel/playbook.yml << EOF
---
- name: setup controller for network use cases
  hosts: localhost
  gather_facts: true
  become: true
  vars:

    username: admin
    admin_password: ansible123!
    login: &login
      controller_username: "{{ username }}"
      controller_password: "{{ admin_password }}"
      controller_host: "https://{{ ansible_host }}"
      validate_certs: false

  tasks:

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

    - name: Add EE to the controller instance
      awx.awx.execution_environment:
        name: "Network Execution Environment"
        image: quay.io/acme_corp/network-ee
        <<: *login

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

# Write a new playbook to create a template from above playbook
cat > /home/rhel/debug.yml << EOF
---
- name: print debug
  hosts: localhost
  gather_facts: no
  connection: local

  tasks:

    - name: ensure that the desired snmp strings are present
      ansible.builtin.debug:
        msg: "print to terminal"

EOF
cat /home/rhel/debug.yml

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
cat /home/rhel/facts.yml

/usr/local/bin/ansible-playbook /home/rhel/playbook.yml

cat > /home/rhel/hosts << EOF
cisco ansible_connection=network_cli ansible_network_os=ios ansible_become=true ansible_user=admin ansible_password=ansible123!
vscode ansible_user=rhel ansible_password=ansible123!
EOF
cat  /home/rhel/hosts

# set vscode default settings
cat >/home/$USER/.local/share/code-server/User/settings.json <<EOL
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
  "window.autoDetectColorScheme": true,
  "security.workspace.trust.enabled": false
}
EOL
cat /home/$USER/.local/share/code-server/User/settings.json

# set ansible-navigator default settings
cat >/home/$USER/ansible-navigator.yml <<EOL
---
ansible-navigator:
  ansible:
    inventories:
    - /home/$USER/hosts
  execution-environment:
    container-engine: podman
    image: ee-supported-rhel8
    enabled: True
    pull-policy: never

  playbook-artifact:
    save-as: /home/rhel/playbook-artifacts/{playbook_name}-artifact-{ts_utc}.json

  logging:
    level: debug

EOL
cat /home/$USER/ansible-navigator.yml

# Fixes an issue with podman that produces this error: "Error: error creating tmpdir: mkdir /run/user/1000: permission denied"
loginctl enable-linger $USER

# Creates playbook artifacts dir
mkdir /home/$USER/playbook-artifacts

# Creates playbook artifacts dir
mkdir /home/$USER/.ssh

cat >/home/rhel/.ssh/id_rsa <<EOF
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAACFwAAAAdzc2gtcn
NhAAAAAwEAAQAAAgEAujxd5jdqF9YOsrZQDDX7Io907po4RHXqUT/lrQyVuwEhvmvH+2W5
YKI7W0NlFQlObkfHrmP6IxEQB6lrWLVbQFb2n4WuATDTlYrl7USf/8NWLf+uACi/evwMNx
HO9YCFhXSm2rc0Oi0X4skT+cJYP1Ux62Mulc6CQgceceuMcBXSXuoQsP6/3cK1jhyXikBH
HIm084Z7hJNcGelGadYA2FuplItsgI0IowvmXV6XuDPX43EWJ3SgbPRc0tpTDIr2xNvKfr
JWA9thjLuguk98pw+xBzEo/5YGmmm8IrjZEAN6m/zjNN44U7iEiwTcIUENd18xwA0+Zq4d
jeRRwduJOJt6jppWu4NpvhAZYNvlqmuhqtH76o80FEyZ7thwPfZfKBJVMLucnzM3j3+10/
oFMcEPjZEcCoP7Du+GC9z+DZSk1v8KcbMpyIh1QNJyLRRwGwO0cLhKSkLri/FaJjzjSLRg
MKlEMCto7OJgWjT40zN8xT3EquhhATld7BsLjm1QJgQQuuF3DA8KtPyfPkyJMCd6NrtB02
mjGvwARjVr4411B6nqRHVcv8YdIHZUpT8gBm1utK9HOt76ZroxN93z25QCKoKzn39HI4lM
yhgo+i/BE0UVUrTa9gL73jvWjV/0NyQcZKQgDTt5w3eO4MzXAo6xPWU8djx7VqG5kRk/g+
sAAAdQuEM1nrhDNZ4AAAAHc3NoLXJzYQAAAgEAujxd5jdqF9YOsrZQDDX7Io907po4RHXq
UT/lrQyVuwEhvmvH+2W5YKI7W0NlFQlObkfHrmP6IxEQB6lrWLVbQFb2n4WuATDTlYrl7U
Sf/8NWLf+uACi/evwMNxHO9YCFhXSm2rc0Oi0X4skT+cJYP1Ux62Mulc6CQgceceuMcBXS
XuoQsP6/3cK1jhyXikBHHIm084Z7hJNcGelGadYA2FuplItsgI0IowvmXV6XuDPX43EWJ3
SgbPRc0tpTDIr2xNvKfrJWA9thjLuguk98pw+xBzEo/5YGmmm8IrjZEAN6m/zjNN44U7iE
iwTcIUENd18xwA0+Zq4djeRRwduJOJt6jppWu4NpvhAZYNvlqmuhqtH76o80FEyZ7thwPf
ZfKBJVMLucnzM3j3+10/oFMcEPjZEcCoP7Du+GC9z+DZSk1v8KcbMpyIh1QNJyLRRwGwO0
cLhKSkLri/FaJjzjSLRgMKlEMCto7OJgWjT40zN8xT3EquhhATld7BsLjm1QJgQQuuF3DA
8KtPyfPkyJMCd6NrtB02mjGvwARjVr4411B6nqRHVcv8YdIHZUpT8gBm1utK9HOt76Zrox
N93z25QCKoKzn39HI4lMyhgo+i/BE0UVUrTa9gL73jvWjV/0NyQcZKQgDTt5w3eO4MzXAo
6xPWU8djx7VqG5kRk/g+sAAAADAQABAAACAD/jCYs6I0j+A5jG9fraYcZfVAuuF/NUSAeL
VezhTlQSdVLvgnD5WniN7rLGEdz/jkpCkXt/jIWPCuK1+b86p40QyBW9NA3whATe2zVjv0
dr6RpqhXREhjtYT5BsqYSKjENV2w9Yna//XBxOQm4Bf2hqf29yXL7DUuf3rTgDR/ADbGFn
BkbRfVxDuSiBInMozbw6eTq5PZIjQwsYfTE9WpjeCPSOR7BpsTbNlD8ffgiQsFSzrJfoaE
g4I8epYagB29l4VKTV5K/6CCLRErgXIHnm5iHDeX8EJku+Te3TX5MgvmTYgdDXEpeVytIt
3p4BxO7YVya85FUxEa5lTq6j8xRD3orDIvCnHChlcX/os2YDE40hxRdWcy1dl9PMe6kmdn
32Vq/osNGvECbrSL7z57Q8j5AvfGtJSS3+UaVhrjCm412eocjduTzEPABwP7fqPAAkGQKo
MBozkjmyV+tyxjn00fhjnpDRg6XfKovFn4oBv/bPFJ/IStZQsPbpbWfFLuCFQY2fHdL9Vd
C004MK2lLq6EJh3V6xuVNwtzo4+I6nPUgE6DC57Rdv2elpU+cscdwaIrMFtkW20HW2a5a9
2BUilBd8ryHLViWXtVOWDFYG9eDQwc3CDoin/yd7PbS81D4NEYL0wMK90AUXYtemb4xj2S
UcTMvvOA3zvYTsGbJhAAABAQDljXbMa1H76JhV1VpQU3BoM+TKsFQ9BsH0RLj3xnOb4YTR
onR1HK33JO3kL+48GyHTKSZRyj7Mwwx4IxgCZvydvSRKULEL604e8Vzpg9ws63/iDMQ1jH
/VMITaYDPWebNszjYPD0tr4YTU8ryqLtnBdqFoiaVTyv8W8mP8Y8Fcop7VukmvZK2ZBsut
DATA4y3RCnqBdKcOahIbDKkvC7qDsYrVqFBuqv/tXhQF9g8jnQrF211Af1g0HZntO7TXR7
lNl+VDvgIHeAZGPlJtfNRpRY83pOIsVHVebDhMhoGdS0/fENUhIYAPXGCK5S1LhtgkeIjV
plYjZHnKQMRNl9f3AAABAQDtQxAzgBWFZ1BS1sF2XxZOTz7F116s1L5aGzwuURSOEQwKdf
QkrDjBoxU0qdsfrDgF/omu+EiKSfXAzEF5Ia8bsLTN4vuGFddRKCfl2wBjXseUbiT2aBUa
OdTI2w4sHvB2rg9a6VOs6tH5Hoz7bynIh6DKRbHE0unbYZWzJvpWsSn6+pABeMLdfe3D29
nZRkq57k9BImMbEeUqOhdz9hbxp96IyP1P4jCYGSiJivBC6W6inIT/mtSywZSfWPJ39qRl
H1VobA8iOshJN0MVsfDrG/gcj0WNRDZVrd7kWBDiMao9+1YfrSPC2mdR7RjJD07jg4G+Rl
XSfXTTrJ7Xq0vjAAABAQDI8amEIQHWmgQ7ohMtGaS75pX7T3ZeR1WS99aqlVbLTomQKmj7
l0Jk5ZkczAscLdciZLNGZ92DIE+YQ3YigUUolbUsibDNJ1Ew0x0FRofg3uxcBIREqi4C/6
2thb8OxD7KcEcAWAhJg/cIf3ZdGG9Opm4LSianOdgbYW9Q3W/Hv4JDOimu4GfPouQdRdeR
SMwW5tNApQX2tK2zOhco6ZuxXnFpRmFtDw0y9v7s112TVAh/7obEuXR8Lb8lpcS10xh/1T
aFIIYzdspdf1HRNMlT0DgqM6w7JfEuXaYh5NT2Fd6efOFand582Ylh6jZ/ogwg/h/6HArT
BkWxaD0kAvZZAAAAGmFuc2libGUtbmV0d29ya0ByZWRoYXQuY29t
-----END OPENSSH PRIVATE KEY-----
EOF

chmod 600 /home/rhel/.ssh/id_rsa

# sudo chown rhel:rhel /home/rhel/.ssh/id_rsa


tee /home/rhel/.ssh/config << EOF
Host *
     StrictHostKeyChecking no
     User ansible
EOF

# sudo chown rhel:rhel /home/rhel/.ssh/config

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

/usr/local/bin/ansible-playbook /home/rhel/debug.yml
