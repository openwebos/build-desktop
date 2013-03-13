#!/bin/bash
# @@@LICENSE
#
#      Copyright (c) 2010 - 2013 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# LICENSE@@@

#set -x

usage() {
  cat <<-EOF
	Starts or stops local (ls2) ls-hubd sessions

	Usage: ${0} [--help] [command] [args...]

	Options:
	    --help    Show this help message

	Commands:
	    start                      Starts the pub/priv ls-hubd instances
	    services                   Starts the static native services
                                       (LunaSysService, filecache, activitymanager, mojodb-luna)
                                       (services can also be started individually by name)
	    init                       Perform first-time initialization (db and local account)
	    send                       Sends a service bus request (using luna-send)
	    stop                       Stops currently running ls-hubd and services
	    status                     Displays status of pub/priv ls-hubd instances
	    monitor [...]              Invokes ls-monitor
	EOF
	echo

#	    log [public]               Show ls-hubd output (default=private)
#	    add <svc1> [<svc2> ...]    Register one or more ls2 services
#	    remove <svc1> [<svc2> ...] Unregister one or more ls2 services
#	    purge                      Unregister all ls2 services
#	    dir <svcsDir>              Register all ls2 services in <svcsDir>
#	    list                       Lists all registered ls2 services

}

get_pidfile() {
  echo "/tmp/webos/ls2/ls-hubd.${1}.pid"
}

hubd_status() {
  if [ -e "`get_pidfile ${1}`" ] ; then
    echo "${1} hubd is running."
  else
    echo "${1} hubd is NOT running."
  fi
}

hubds_status() {
  hubd_status public
  hubd_status private
}

hubd_stop() {
  PID_FILE="/tmp/webos/ls2/ls-hubd.${1}.pid"
  if [ -e "${PID_FILE}" ] ; then
    echo "Stopping ${1} hub daemon"
    kill -9 `cat ${PID_FILE}`
    rm ${PID_FILE}
  fi
}

hubds_stop() {
  hubd_stop public
  hubd_stop private
}

hubds_start() {
  ls-hubd --conf ${CONF_DIR}/ls2/ls-private.conf ${LOGGING} 2>&1 &
  ls-hubd --public --conf ${CONF_DIR}/ls2/ls-public.conf ${LOGGING} 2>&1 &
  sleep 1
  echo
  echo "hub daemons started!"
  echo "(Type: '${0} stop' to stop hub daemons.)"
}

services_stop() {
  echo
  for SERVICE in ${STATIC_SERVICES} ; do
    killall ${SERVICE} && echo "Killed ${SERVICE}"
  done
  killall mojomail-imap && echo "Killed ${SERVICE}"
  killall mojomail-pop && echo "Killed ${SERVICE}"
  killall mojomail-smtp && echo "Killed ${SERVICE}"
}

service_start() {
    SERVICE=${1}
    shift
    if [ -x ${SERVICE_BIN_DIR}/${SERVICE} ] ; then
      echo
      echo "Starting service: ${SERVICE} ..."
      ${SERVICE_BIN_DIR}/${SERVICE} "$@" &
      sleep 1
    else
      echo
      echo "ERROR: ${SERVICE} not present in ${SERVICE_BIN_DIR}"
      echo
      exit 1
    fi
}

services_start() {
  for SERVICE in ${STATIC_SERVICES} ; do
    case "${SERVICE}" in
    mojodb-luna)
      service_start mojodb-luna -c /etc/palm/mojodb.conf /var/db
      ;;
    *)
      service_start ${SERVICE}
      ;;
    esac
  done
  sleep 1
  echo
  echo "Services started!"
  echo "(Type: '${0} stop' to stop services and hub daemons.)"
}

hubd_monitor() {
  ls-monitor "$@"
}

check_fs_attribute() {
  echo
  echo "Checking filesystem attribute on ${LUNA_STAGING}"

  varfs=`df ${LUNA_STAGING} | tail -1 | awk '{print $6}'`
  echo " ${LUNA_STAGING} appears to be mounted on $varfs "

  mountline=`cat /proc/mounts | grep -E "[[:graph:]]+[[:blank:]]+${varfs}[[:blank:]]+" | grep -v rootfs`
  echo
  echo "found it in /proc/mounts:"
  echo "  $mountline"
  #  returns something like: /dev/disk/by-uuid/f652a09b-f52a-4735-98b7-14da6c42ebd2 / ext3 rw,relatime,errors=remount-ro,data=ordered 0 0

  mountedflags=`echo $mountline | awk '{print $4}'`
  echo
  echo "current attributes from /proc/mounts:"
  echo "  $mountedflags"
  #  returns something like: rw,relatime,errors=remount-ro,data=ordered
  #                      or: defaults

  if ! `echo $mountedflags | grep -qs user_xattr` ; then
    echo
    echo "user_xattr is NOT curently set!"
    echo "without this attribute, FileCache and Email won't work properly."
    echo "remount $varfs with extended attributes by typing:"
    echo “sudo mount -o remount,user_xattr $varfs”
    echo
    sleep 1;
  fi
  echo
}


#########################################################

export SCRIPT_DIR=$PWD

source ./webos-desktop-common.sh

ROOTFS="${BASE}/rootfs"
LUNA_STAGING="${BASE}/staging"
STAGING_DIR="${LUNA_STAGING}"
BIN_DIR="${STAGING_DIR}/bin"
LIB_DIR="${STAGING_DIR}/lib"
USR_LIB_DIR="${STAGING_DIR}/usr/lib"
USR_BIN_DIR="${STAGING_DIR}/usr/bin"
USR_SBIN_DIR="${STAGING_DIR}/usr/sbin"
ETC_DIR="${STAGING_DIR}/etc"
# NOTE: this links to ROOTFS/usr/lib/luna which is what the role and service files refer to
SERVICE_BIN_DIR="/usr/lib/luna"
STATIC_SERVICES="LunaSysService filecache activitymanager mojodb-luna LunaUniversalSearchMgr com.palm.smartkey"

# TODO: Consider moving ls2 dir to traditional locations (requires changes to scripts AND .conf files)
CONF_DIR="${ROOTFS}/etc"
mkdir -p ${ROOTFS}/etc/ls2
if [ ! -f "${ROOTFS}/etc/ls2/ls-private.conf" ] || grep -qs dbus ${ROOTFS}/etc/ls2/ls-private.conf ; then
  cp -f ls2/ls-private.conf ${ROOTFS}/etc/ls2
fi
if [ ! -f "${ROOTFS}/etc/ls2/ls-public.conf" ] || grep -qs dbus ${ROOTFS}/etc/ls2/ls-public.conf ; then
  cp -f ls2/ls-public.conf ${ROOTFS}/etc/ls2
fi


SRC_DIR="${BASE}/luna-sysmgr/desktop-support"
#LOGGING="--pmloglib"

DEB_BUILD_MULTIARCH=$(dpkg-architecture -qDEB_BUILD_MULTIARCH)
export LD_PRELOAD=/lib/${DEB_BUILD_MULTIARCH}/libSegFault.so
export LD_LIBRARY_PATH=${LIB_DIR}:${USR_LIB_DIR}:${LD_LIBRARY_PATH}
export PATH=${SERVICE_BIN_DIR}:${USR_BIN_DIR}:${USR_SBIN_DIR}:${BIN_DIR}:${PATH}

CMD="$1"
if [ -z "$CMD" ]; then
  CMD=help
else
  shift
fi

echo

case "$CMD" in
start)
  echo "Halting old services..."
  services_stop
  hubds_stop
  hubds_start
  echo
  ;;
stop)
  echo "Halting services..."
  services_stop
  echo
  hubds_stop
  echo
  ;;

services)
  echo "Halting old services..."
  services_stop
  echo
  check_fs_attribute
  services_start
  echo
  ;;
LunaSysService)
  service_start LunaSysService ;;
filecache)
  check_fs_attribute
  service_start filecache ;;
activitymanager)
  service_start activitymanager ;;
mojodb|mojodb-luna|db8)
  service_start mojodb-luna -c /etc/palm/mojodb.conf /var/db
  ;;
LunaUniversalSearchMgr)
  service_start LunaUniversalSearchMgr ;;
  
send)
  luna-send "$@"
  ;;
init)
  service_start filecache
  service_start mojodb-luna -c /etc/palm/mojodb.conf /var/db
  luna-send -n 1 palm://com.palm.configurator/run '{"types":["dbkinds","filecache"]}'
  luna-send -n 1 palm://com.palm.configurator/run '{"types":["dbpermissions"]}'
  service_start LunaSysService
  service_start activitymanager
  luna-send -n 1 palm://com.palm.service.accounts/createLocalAccount '{}'
  sleep 2
  luna-send -n 1 palm://com.palm.configurator/run '{"types":["activities"]}'
  services_stop
  ;;

status)
  hubds_status ;;
monitor)
  hubd_monitor ;;
help)
  usage ;;
*)
  usage && false ;;
esac


