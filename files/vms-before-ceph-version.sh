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

# This function shows the utilization parmeters
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

# Loop on all the events list related to ceph-common
for YUM_HISTORY_EVENT in $YUM_HISTORY_EVENTS; do
  CEPH_INFO=$(yum history info $YUM_HISTORY_EVENT|grep ceph-common);

  # Avoid all events, such as remove, except the install and updates of ceph-common   
  if [[ ${CEPH_INFO} != *"Install"* ]] && [[ ${CEPH_INFO} != *"Updated"* ]]; then
     continue;
  fi

  # Extract the ceph version in case of a fresh install.
  # tail -1 is used here to ensure that we get the last line of ceph-common-2:xx.y.zz-0.el7.x86_64
  if [[ ${CEPH_INFO} == *"Install"* ]]; then
     CEPH_VERSION=$(yum history info $YUM_HISTORY_EVENT|grep ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  fi

  # Extract the ceph version in case of an update.
  if [[ ${CEPH_INFO} == *"Updated"* ]]; then
     CEPH_VERSION=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  fi

  # Get the date and timestamp of ceph update or install.
  CEPH_UPGRADE_DATE=$(yum history info $YUM_HISTORY_EVENT|grep '^Begin time'|awk -F' : ' '{print $2}')
  CEPH_UPGRADE_TIMESTAMP=$(date -d "$CEPH_UPGRADE_DATE" +%s)

  # Break in case that $CEPH_VERSION is lower or equal to $CEPH_VERSION_EXPECTED.
  if version_le_op $CEPH_VERSION $CEPH_VERSION_EXPECTED; then
    break
  fi

  # Save the previous information in case $CEPH_VERSION is strictly lower than $CEPH_VERSION_EXPECTED. 
  # In this case, we have to use the previous $CEPH_VERSION in the loop that has higher timestamp either is higher than $CEPH_VERSION_EXPECTED.
  PREVIOUS_CEPH_VERSION=$CEPH_VERSION
  PREVIOUS_CEPH_UPGRADE_DATE=$CEPH_UPGRADE_DATE
  PREVIOUS_CEPH_UPGRADE_TIMESTAMP=$CEPH_UPGRADE_TIMESTAMP

done

# In case that the ceph is not installed in the system. 
# No prior install or update of ceph client
if [[ -z "$CEPH_UPGRADE_TIMESTAMP" ]]; then
    echo "Ceph is not installed in the system" 1>&2
    exit 0
fi

# In case that there is no prior ceph version than $CEPH_VERSION_EXPECTED. 
# This means that the code has completed the previous loop without break.
if version_lt_op $CEPH_VERSION_EXPECTED $CEPH_VERSION; then
    echo "There is no Ceph version prior than $CEPH_VERSION_EXPECTED is installed" 1>&2
    exit 0
fi

# In case that $CEPH_VERSION is strictly lower than $CEPH_VERSION_EXPECTED, the previous $CEPH_VERSION in the loop that has higher timestamp either is higher than $CEPH_VERSION_EXPECTED should be used.
if version_lt_op $CEPH_VERSION $CEPH_VERSION_EXPECTED; then
  if [[ ${PREVIOUS_CEPH_UPGRADE_TIMESTAMP+x} ]]; then
    CEPH_VERSION=$PREVIOUS_CEPH_VERSION
    CEPH_UPGRADE_DATE=$PREVIOUS_CEPH_UPGRADE_DATE
    CEPH_UPGRADE_TIMESTAMP=$PREVIOUS_CEPH_UPGRADE_TIMESTAMP
  fi 
fi

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
