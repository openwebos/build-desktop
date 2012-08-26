#!/bin/sh
# @@@LICENSE
#
#      Copyright (c) 2010 - 2012 Hewlett-Packard Development Company, L.P.
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
  #mkdir -p ${CONF_DIR}/ls2/roles
  #mkdir -p ${CONF_DIR}/ls2/services
  #mkdir -p ${CONF_DIR}/ls2/system-services
  ls-hubd --conf ${CONF_DIR}/ls2/ls-private.conf ${LOGGING} 2>&1 &
  ls-hubd --public --conf ${CONF_DIR}/ls2/ls-public.conf ${LOGGING} 2>&1 &
  sleep 1
  echo
  echo "hub daemons started!"
  echo "(Type: '${0} stop' to stop hub daemons.)"
}

hubd_monitor() {
  ls-monitor "$@"
}

#########################################################

BASE="${HOME}/luna-desktop-binaries"
ROOTFS="${BASE}/rootfs"
LUNA_STAGING="${BASE}/staging"
STAGING_DIR="${LUNA_STAGING}"
BIN_DIR="${STAGING_DIR}/bin"
LIB_DIR="${STAGING_DIR}/lib"
ETC_DIR="${STAGING_DIR}/etc"

# TODO: Consider moving ls2 dir to traditional locations (requires changes to scripts AND .conf files)
CONF_DIR="${ROOTFS}"

SRC_DIR="${HOME}/luna-desktop-binaries/luna-sysmgr/desktop-support"
#LOGGING="--pmloglib"

export LD_PRELOAD=/lib/i386-linux-gnu/libSegFault.so
export LD_LIBRARY_PATH=${LIB_DIR}:${LD_LIBRARY_PATH}
export PATH=${BIN_DIR}:${PATH}

CMD="$1"
if [ -z "$CMD" ]; then
  CMD=help
else
  shift
fi

case "$CMD" in
start)
  hubds_stop
  hubds_start
  sleep 1
  ;;
stop)
  hubds_stop ;;
status)
  hubds_status ;;
monitor)
  hubd_monitor ;;
help)
  usage ;;
*)
  usage && false ;;
esac


