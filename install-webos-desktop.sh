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

# TODO: Put sudo (only) where needed, so we don't have to run whole script with sudo

# TODO: Consider moving ls2 conf, services, and roles files to traditional location(s):
# Directories=/usr/share/ls2/roles/pub;/var/palm/ls2/roles/pub;/var/mft/palm/ls2/roles/pub
# Directories=/usr/share/dbus-1/services;/var/palm/system-services;/var/palm/ls2/services/pub

set -x

export BASE="${HOME}/luna-desktop-binaries"
export ROOTFS="${BASE}/rootfs"

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
    echo "Desktop install script for Open webOS #3"
    exit
elif [ -n "$1" ] && [ "$1" != "remove" ] ; then
    echo "Parameter $1 not recognized"
    exit
#elif [ ! -d ${ROOTFS} ] || [ ! -d ${ROOTFS}/ls2/roles/prv ] || \
#	[ ! -d ${ROOTFS}/usr/palm/frameworks/enyo ] || [ ! -d ${ROOTFS}/usr/palm/applications ] ; then
#    # force core-apps to re-install (if missing)
#    if [ ! -d ${ROOTFS}/usr/palm/applications ] ; then
#        rm -f ${BASE}/core-apps/luna-desktop-build.stamp
#    fi
#    # force framework to re-install (if missing)
#    if [ ! -d ${ROOTFS}/usr/palm/frameworks/enyo ] ; then
#        rm -f ${BASE}/enyo-1.0/luna-desktop-build.stamp
#    fi
#    # force luna-sysmgr to re-install its files
#    rm -f ${BASE}/luna-sysmgr/luna-desktop-build.stamp
#    
#    echo "Please run build-luna-sysmgr.sh first"
#    exit
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
    
    if [ -h /var/file-cache ] ; then
     	unlink /var/file-cache
    fi
 
    if [ -h /var/usr/palm ] ; then
        rm -f /usr/share/dbus-1/services/com.palm.*
        rm -f /usr/share/dbus-1/system-services/com.palm.*
        unlink /var/usr/palm
    fi

    # everything now goes in $BASE/rootfs, so remove older dirs from $BASE
    rm -rf $BASE/etc
    rm -rf $BASE/ls2
    rm -rf $BASE/share
    rm -rf $BASE/usr
    rm -rf $BASE/var

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
echo "Installing links for luna-sysmgr in /etc/ls2, /etc/palm, /usr/palm, "
echo "    /var/luna, /var/palm, /usr/lib/luna and /usr/share/ls2"

ln -sf -T ${ROOTFS}/etc/palm /etc/palm
ln -sf -T ${ROOTFS}/etc/ls2 /etc/ls2
mkdir -p /usr/share/ls2

ln -sf -T ${ROOTFS}/usr/share/ls2/roles /usr/share/ls2/roles
# NOTE: desktop ls2 .conf files will look for services in /usr/share/ls2/*services
# NOTE: but on device they live in /usr/share/dbus-1/*services (which is used by Ubuntu dbus)
ln -sf -T ${ROOTFS}/usr/share/ls2/services /usr/share/ls2/services
ln -sf -T ${ROOTFS}/usr/share/ls2/system-services /usr/share/ls2/system-services

ln -sf ${ROOTFS}/usr/palm /usr/palm

# TODO: remove this
#mkdir -p /usr/share/dbus-1/services
#mkdir -p /usr/share/dbus-1/system-services
#cp -fs ${ROOTFS}/share/dbus-1/system-services/com.palm.* /usr/share/dbus-1/system-services

# TODO: remove files installed by previous install script.  or not.
#rm -f /usr/share/dbus-1/services/com.palm.*
#rm -f /usr/share/dbus-1/system-services/com.palm.*

ln -sf ${ROOTFS}/var/db /var/db
ln -sf ${ROOTFS}/var/luna /var/luna
ln -sf ${ROOTFS}/var/palm /var/palm

ln -sf ${ROOTFS}/usr/lib/luna /usr/lib/luna

mkdir -p /var/usr
ln -sf ${ROOTFS}/var/usr/palm /var/usr/palm

