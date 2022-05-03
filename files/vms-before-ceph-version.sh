#!/bin/bash
# Managed with Ansible

# DEFAULTS
# Search for lanched VMs before this Ceph version
CEPH_VERSION_EXPECTED="12.2.14"

versionlte() {
    [  "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
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
  CEPH_VERSION=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'-' '{print $1}')
  if versionlte $CEPH_VERSION $CEPH_VERSION_EXPECTED; then
    CEPH_UPGRADE_DATE=$(yum history info $YUM_HISTORY_EVENT|grep '^Begin time'|awk -F' : ' '{print $2}')
    CEPH_UPGRADE_TIMESTAMP=$(date -d "$CEPH_UPGRADE_DATE" +%s)
    break
  fi
done

if [[ -z "$CEPH_UPGRADE_TIMESTAMP" ]]; then
    echo "There is no Ceph version prior $CEPH_VERSION_EXPECTED is installed" 1>&2
    exit 0
fi

echo "+-----------------------------+"
echo "|   CEPH VERSION IS $CEPH_VERSION   |"
echo "+-----------------------------+"

# Retrieve a list of all QEMU process IDs
PIDS=$(pgrep -f /usr/libexec/qemu-kvm)

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