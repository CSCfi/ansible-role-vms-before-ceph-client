#!/bin/bash
# Managed with Ansible
# Author: Miloud Bagaa


# DEFAULTS
# Search for lanched VMs before this Ceph version
CEPH_VERSION_EXPECTED="14.2.20"

# This function compares two versions and retrun True
# if $1 is lower or equal to $2 
version_le_op() {
    [  "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}

# This function compares two versions and retrun True
# if $1 is strictly lower than $2 
version_lt_op() {
    [ "$1" = "$2" ] && return 1 || version_le_op $1 $2
}

usage() {
  echo "Usage: $0 "
  echo " [--help|-h|-?],  to show the help"
  echo "[-v|--version] 12.2.14, expected ceph version"
}

while [ $# -gt 0 ] 
do
  case "$1" in
    "--help"|"-h")
    shift
    usage
    exit 0
    ;;
    "-v"|"--version")
      shift
      CEPH_VERSION_EXPECTED="${1}"
      shift
    ;;
   *)
      message "Warning! Ignoring unknwon parameter '${1}'" show
      shift
      ;;
  esac
done

YUM_HISTORY_EVENTS=$(yum history list all|grep -Po "^\s+\d+")

for YUM_HISTORY_EVENT in $YUM_HISTORY_EVENTS; do
  CEPH_INFO=$(yum history info $YUM_HISTORY_EVENT|grep ceph-common);

  if [[ ${CEPH_INFO} != *"Dep-Install"* ]] && [[ ${CEPH_INFO} != *"Updated"* ]]; then
     continue;
  fi

  if [[ ${CEPH_INFO} == *"Dep-Install"* ]]; then
     CEPH_VERSION=$(yum history info $YUM_HISTORY_EVENT|grep ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  fi

  if [[ ${CEPH_INFO} == *"Updated"* ]]; then
     CEPH_VERSION=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  fi

  CEPH_UPGRADE_DATE=$(yum history info $YUM_HISTORY_EVENT|grep '^Begin time'|awk -F' : ' '{print $2}')
  CEPH_UPGRADE_TIMESTAMP=$(date -d "$CEPH_UPGRADE_DATE" +%s)

  if version_le_op $CEPH_VERSION $CEPH_VERSION_EXPECTED; then
    break
  fi

  PREVIOUS_CEPH_VERSION=$CEPH_VERSION
  PREVIOUS_CEPH_UPGRADE_DATE=$CEPH_UPGRADE_DATE
  PREVIOUS_CEPH_UPGRADE_TIMESTAMP=$CEPH_UPGRADE_TIMESTAMP

done

if [[ -z "$CEPH_UPGRADE_TIMESTAMP" ]]; then
    echo "There is no Ceph version prior $CEPH_VERSION_EXPECTED is installed" 1>&2
    exit 0
fi

if version_lt_op $CEPH_VERSION $CEPH_VERSION_EXPECTED; then
  if [[ ${PREVIOUS_CEPH_UPGRADE_TIMESTAMP+x} ]]; then
    CEPH_VERSION=$PREVIOUS_CEPH_VERSION
    CEPH_UPGRADE_DATE=$PREVIOUS_CEPH_UPGRADE_DATE
    CEPH_UPGRADE_TIMESTAMP=$PREVIOUS_CEPH_UPGRADE_TIMESTAMP
  fi 
fi

# Show if there are fault positive 
for YUM_EVENT in $YUM_HISTORY_EVENTS; do

  # Omit the check of previous events. Continue the loop
  if [[ ${YUM_HISTORY_EVENT} -ge ${YUM_EVENT} ]]; then
    continue
  fi 

  CEPH_INFO=$(yum history info $YUM_EVENT|grep ceph-common);

  if [[ ${CEPH_INFO} != *"Dep-Install"* ]] && [[ ${CEPH_INFO} != *"Updated"* ]]; then
     continue;
  fi

  if [[ ${CEPH_INFO} == *"Dep-Install"* ]]; then
     CEPH_VERSION_FAULT_POSITIVE=$(yum history info $YUM_EVENT|grep ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  fi

  if [[ ${CEPH_INFO} == *"Updated"* ]]; then
     CEPH_VERSION_FAULT_POSITIVE=$(yum history info $YUM_EVENT|grep -A1 ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  fi

  if version_le_op $CEPH_VERSION $CEPH_VERSION_FAULT_POSITIVE; then
    echo "There are fault positives. Thus, some VMs can be listed either have upper ceph version than $CEPH_VERSION"
    break
  fi
done

echo "+-----------------------------+"
echo "|   CEPH VERSION IS $CEPH_VERSION   |"
echo "+-----------------------------+"

# Retrieve a list of all QEMU process IDs
PIDS=$(pgrep -f "^/usr/libexec/qemu-kvm")

for PID in $PIDS; do
  # Get QEMU process start time
  QEMU_TIMESTAMP=$(date -d "$(stat -c %x /proc/$PID/stat)" +%s)
  if [[ "$QEMU_TIMESTAMP" -lt "$CEPH_UPGRADE_TIMESTAMP" ]]
  then
    # Get virsh instance ID and name
    INSTANCE_NAME=$(ps -ef -q $PID|grep -Po "(instance-\w+)"|uniq)
    INSTANCE_UUID=$(virsh dumpxml $INSTANCE_NAME|grep \/uuid|awk -F'>' "{print \$2}"|awk -F'<' "{print \$1}")
    echo $INSTANCE_UUID
  fi
done
