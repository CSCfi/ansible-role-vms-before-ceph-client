# ansible-role-vms-before-ceph-client

Ansible role in listing all the VMs launched before the upgrade or installing a Ceph client in hypervisors. This role uses the ceph_version variable to specify the exact version of a Ceph client. If the requested Ceph client version is not installed, then the role considers the latest version installed lower than the requested version ceph_version. The output of the role consists of two parts: i) The latest Ceph client version (i.e., ceph_latest_installed) that is lower or equal to ceph_version; ii) The list of VMs that have been launched before ceph_latest_installed, and hence they don't have the patch applied on ceph_latest_installed.

Role Variables
--------------

See defaults/main.yml for details.

This role mainly accepts one variable ceph_version that specifies the requested Ceph version. 


Example Playbook
----------------


* You can simply use this role like below. 

```
- hosts: servers
  become: True
  gather_facts: False
  vars:
    ceph_version: "12.2.14"
  roles:
    - { role: ansible-role-vms-before-ceph-client }
```