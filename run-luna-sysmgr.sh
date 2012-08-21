#!/bin/bash
# @@@LICENSE
#
#      Copyright (c) 2012 Hewlett-Packard Development Company, L.P.
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

STAGING_DIR="${HOME}/luna-desktop-binaries/staging"
BIN_DIR="${STAGING_DIR}/bin"
LIB_DIR="${STAGING_DIR}/lib"
ETC_DIR="${STAGING_DIR}/etc"

if [ "$1" = "--help" ] ; then
    echo "Usage: ./run-luna-sysmgr.sh [OPTION]"
    echo "Runs the luna-sysmgr component."
    echo " "
    echo "Optional arguments:"
    echo "    --help  display this help and exit"
    echo " "
    exit
elif [ -n "$1" ] ; then
    echo "Parameter $1 not recognized"
    exit
elif [ ! -d ${STAGING_DIR} ]  || [ ! -d ${HOME}/luna-desktop-binaries/ls2/roles/prv ]; then
    echo "First build luna-sysmgr"
    exit
fi

export LD_PRELOAD=/lib/i386-linux-gnu/libSegFault.so
export LD_LIBRARY_PATH=${LIB_DIR}:${LD_LIBRARY_PATH}
export PATH=${BIN_DIR}:${PATH}

if [ -d /etc/palm ] && [ -h /etc/palm ] ; then
    echo "Starting LunaSysMgr ..."
    mkdir -p /tmp/webos
    ./usr/lib/luna/LunaSysMgr  &> /tmp/webos/LunaSysMgr.log
else
    echo "First run the install script:  sudo ./install-luna-sysmgr.sh"
fi
