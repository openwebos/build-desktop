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

export LSM_TAG="0.823"

export BASE="${HOME}/luna-desktop-binaries"
export BASE_DIR="${BASE}/luna-sysmgr"

if [ "$1" = "--help" ] ; then
    echo "Usage: sudo ./install-luna-sysmgr.sh [OPTION]"
    echo "Installs the luna-sysmgr component and its dependencies."
    echo "    NOTE:  This script requires sudo privileges"
    echo " "
    echo "Optional arguments:"
    echo "    remove  Remove the existing install and exit"
    echo "    --help  display this help and exit"
    echo "    --version  display version information and exit"
    echo " "
    exit
elif [ "$1" = "--version" ] ; then
    echo "Install build script for luna-sysmgr ${LSM_TAG}"
    exit
elif [ -n "$1" ] && [ "$1" != "remove" ] ; then
    echo "Parameter $1 not recognized"
    exit
elif [ ! -d ${BASE} ] || [ ! -d ${BASE}/ls2/roles/prv ] || [ ! -d ${BASE}/usr/palm/ ] ; then
    echo "First build luna-sysmgr"
    exit
fi

###############################
do_remove_folder() {

    if [ -h "$1" ] ; then
        unlink "$1"
    elif [ -d "$1" ] ; then
        rm -rf "$1"/*
        rmdir "$1"
    fi
}


### First we remove any prior luna-sysmgr install
### The remove option will remove installs from 0.820 and 0.822
###     plus this streamlined install script
if [ -d /etc/palm ] ; then
    if [ -h /etc/palm ] ; then
        unlink /etc/palm
    else
        # Support remove of 0.822 install
        if [ -h /etc/palm/luna-applauncher ] ; then
            unlink /etc/palm/luna-applauncher
            unlink /etc/palm/luna.conf
            unlink /etc/palm/luna-platform.conf
            unlink /etc/palm/defaultPreferences.txt
            unlink /etc/palm/luna-sysmgr
            unlink /etc/palm/launcher3
            unlink /etc/palm/schemas
        fi
        if [ -d /etc/palm/pubsub_handlers ] ; then
            unlink /etc/palm/pubsub_handlers/com.palm.appinstaller
            rmdir  /etc/palm/pubsub_handlers
        fi
        rm -rf /etc/palm/*
        rmdir /etc/palm
    fi
    if [ "$1" == "remove" ] ; then
        echo "Removed support files for luna-sysmgr from /etc/palm"
    fi
    if [ -h /usr/share/ls2/roles ] ; then
        unlink /usr/share/ls2/roles
        if [ -d /etc/ls2 ] && [ ! -h /etc/ls2 ] ; then
            # Support remove of 0.822 install
            unlink /etc/ls2/ls-public.conf
            unlink /etc/ls2/ls-private.conf
            rmdir /etc/ls2
        elif [ -h /etc/ls2 ] ; then
            unlink /etc/ls2
        fi
        if [ "$1" == "remove" ] ; then
            echo "Removed support files for luna-sysmgr from /usr/share/ls2 and /etc/ls2"
        fi
    fi
    
    do_remove_folder /usr/palm
    do_remove_folder /var/palm
    do_remove_folder /var/luna
    do_remove_folder /usr/lib/luna
    
    if [ -h /var/usr/palm ] ; then
        rm -f /usr/share/dbus-1/services/com.palm.*
        rm -f /usr/share/dbus-1/system-services/com.palm.*
        unlink /var/usr/palm
    fi

    if [ "$1" == "remove" ] ; then
        echo "Removed support files for luna-sysmgr from /usr/palm, /usr/share and /var/usr"
        exit
    fi
elif [ "$1" == "remove" ] ; then
    echo "Nothing to remove"
    exit
fi

## Verify clean environment
if [ -d /etc/palm ] || [ -d /usr/palm ] || [ -d /var/usr/palm ] || [ -d /var/palm ] ; then
    echo "ERR: Previous partial installs remain.  Re-run with 'remove' option or "
    echo "    manually remove links and folders."
    exit
fi

### Install the links from restricted folders
### For consistency, creates a few folders which should already exist
echo "Install links for luna-sysmgr in /etc/ls2, /etc/palm, /usr/palm, "
echo "    /var/luna, /var/palm, /usr/lib/luna and /usr/share/ls2"

ln -sf ${BASE}/etc/palm /etc/palm

mkdir -p /usr/share/ls2
ln -sf ${BASE}/ls2/roles /usr/share/ls2/roles
ln -sf -T ${BASE}/ls2 /etc/ls2

ln -sf ${BASE}/usr/palm /usr/palm

mkdir -p /usr/share/dbus-1/services
cp -fs ${BASE}/share/dbus-1/services/com.palm.* /usr/share/dbus-1/services
mkdir -p /usr/share/dbus-1/system-services
cp -fs ${BASE}/share/dbus-1/system-services/com.palm.* /usr/share/dbus-1/system-services

ln -sf ${BASE}/var/palm /var/palm
ln -sf ${BASE}/var/luna /var/luna
ln -sf ${BASE}/usr/lib/luna /usr/lib/luna
mkdir -p /var/usr
ln -sf ${BASE}/var/usr/palm /var/usr/palm

