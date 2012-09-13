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

export VERSION=7.1

if [ "$1" = "clean" ] ; then
  export SKIPSTUFF=0
  set -e
elif [ "$1" = "--help" ] ; then
    echo "Usage:  ./build-luna-sysmgr.sh [OPTION]"
    echo "Builds the luna-sysmgr component and its dependencies."
    echo "    The script loads about 500MB of source code from GitHub, as needed."
    echo "    NOTE: This script creates about 4GB of disk space"
    echo " "
    echo "Optional arguments:"
    echo "    clean   force a rebuild of components"
    echo "    --help  display this help and exit"
    echo "    --version  display version information and exit"
    echo " "
    exit
elif [ "$1" = "--version" ] ; then
    echo "Desktop build script for Open webOS #${VERSION}"
    exit
elif  [ -n "$1" ] ; then
    echo "Parameter $1 not recognized"
    exit
else
  export SKIPSTUFF=1
  set -e
fi


export BASE="${HOME}/luna-desktop-binaries"
export ROOTFS="${BASE}/rootfs"
export LUNA_STAGING="${BASE}/staging"
mkdir -p ${BASE}/tarballs
mkdir -p ${LUNA_STAGING}

export BEDLAM_ROOT="${BASE}/staging"
export JAVA_HOME=/usr/lib/jvm/java-6-sun
export JDKROOT=${JAVA_HOME}
export SCRIPT_DIR=$PWD
# old builds put .pc files in lib/pkgconfig; cmake-modules-webos puts them in usr/share/pkgconfig
export PKG_CONFIG_PATH=$LUNA_STAGING/lib/pkgconfig:$LUNA_STAGING/usr/share/pkgconfig
export MAKEFILES_DIR=$BASE/pmmakefiles

# where's cmake? we prefer to use our own, and require the cmake-modules-webos module.
if [ -x "${BASE}/cmake/bin/cmake" ] ; then
  export CMAKE="${BASE}/cmake/bin/cmake"
else
  export CMAKE="cmake"
fi

PROCS=`grep -c processor /proc/cpuinfo`
[ $PROCS -gt 1 ] && JOBS="-j${PROCS}"

export WEBKIT_DIR="WebKit"

[ -t 1 ] && curl_progress_option='-#' || curl_progress_option='-s -S'

############################################
# Optimized fetch process.
# Parameters:
#   $1 Specific component within repository, ex: openwebos/cjson
#   $2 Tag of component, ex: 35
#   $3 Name of destination folder, ex: cjson
#   $4 (Optional) Prefix for tag
#
# If the ZIP file already exists in the tarballs folder, it will not be re-fetched
#
############################################
do_fetch() {
    cd $BASE
    if [ -n "$4" ] ; then
        GIT_BRANCH="${4}${2}"
    else
        GIT_BRANCH="${2}"
    fi
    if [ -n "$3" -a -d "$3" ] ; then
        rm -rf ./$3
    fi

    if [ "$1" = "isis-project/WebKit" ] ; then
        GIT_SOURCE=https://github.com/downloads/isis-project/WebKit/WebKit_${2}s.zip
    elif [ -n “${GITHUB_USER}” ]; then
        GIT_SOURCE=https://${GITHUB_USER}:${GITHUB_PASS}@github.com/${1}/zipball/${GIT_BRANCH}
    else
        GIT_SOURCE=https://github.com/${1}/zipball/${GIT_BRANCH}

    fi

    ZIPFILE="${BASE}/tarballs/`basename ${1}`_${2}.zip"

    # if building from a tag, remove any cached "master" zipball to force it to be re-fetched
    if [ "${2}" != "master" ] ; then
      rm -f "${BASE}/tarballs/`basename ${1}`_master.zip"
    fi

    if [ -e ${ZIPFILE} ] ; then
        file_type=$(file -bi ${ZIPFILE})
        if [ "${file_type}" != "application/zip; charset=binary" ] ; then
            rm -f ${ZIPFILE}
        fi
    fi
    if [ ! -e ${ZIPFILE} ] ; then
        if [ -e ~/tarballs/`basename ${1}`_${2}.zip ] ; then
            cp -f ~/tarballs/`basename ${1}`_${2}.zip ${ZIPFILE}
            if [ $? != 0 ] ; then
                echo error
                rm -f ${ZIPFILE}
                exit 1
            fi
        else
            echo "About to fetch ${1}#${GIT_BRANCH} from github"
            curl -L -R ${curl_progress_option} ${GIT_SOURCE} -o "${ZIPFILE}"
        fi
    fi
    if [ -e ${ZIPFILE} ] ; then
        file_type=$(file -bi ${ZIPFILE})
        if [ "${file_type}" != "application/zip; charset=binary" ] ; then
            echo "FAILED DOWNLOAD: ${ZIPFILE} is ${file_type}"
            rm -f ${ZIPFILE}
            exit 1
        fi
    fi
    mkdir ./$3
    pushd $3
    unzip -q ${ZIPFILE}
    mv $(ls |head -n1)/* ./
    popd
}

########################
#  Fetch and build cmake
########################
function build_cmake
{
    CMAKE_VER="2.8.7"
    mkdir -p $BASE/cmake
    cd $BASE/cmake
    CMAKE_TARBALL="$BASE/tarballs/cmake-${CMAKE_VER}-Linux-i386.tar.gz"
    if [ ! -f "${CMAKE_TARBALL}" ] ; then
        wget http://www.cmake.org/files/v2.8/cmake-${CMAKE_VER}-Linux-i386.tar.gz -O ${CMAKE_TARBALL}
    fi
    tar zxf ${CMAKE_TARBALL} --strip-components=1
    export CMAKE="${BASE}/cmake/bin/cmake"
}

######################################
#  Fetch and build cmake-modules-webos
######################################
function build_cmake-modules-webos
{
    do_fetch openwebos/cmake-modules-webos $1 cmake-modules-webos submissions/
    cd $BASE/cmake-modules-webos
    mkdir -p BUILD
    cd BUILD
    $CMAKE .. -DCMAKE_INSTALL_PREFIX=${BASE}/cmake
    make
    mkdir -p $BASE/cmake
    make install
}

########################
#  Fetch and build cjson
########################
function build_cjson
{
    do_fetch openwebos/cjson $1 cjson submissions/
    cd $BASE/cjson
    sh autogen.sh
    mkdir -p build
    cd build
    PKG_CONFIG_PATH=$LUNA_STAGING/lib/pkgconfig \
    ../configure --prefix=$LUNA_STAGING --enable-shared --disable-static
    make $JOBS all
    make install
}

##########################
#  Fetch and build pbnjson
##########################
function build_pbnjson
{
    do_fetch openwebos/libpbnjson $1 pbnjson submissions/
    mkdir -p $BASE/pbnjson/build
    cd $BASE/pbnjson/build
    sed -i 's/set(EXTERNAL_YAJL TRUE)/set(EXTERNAL_YAJL FALSE)/' ../src/CMakeLists.txt
    sed -i 's/add_subdirectory(pjson_engine\//add_subdirectory(deps\//' ../src/CMakeLists.txt
    sed -i 's/-Werror//' ../src/CMakeLists.txt
    $CMAKE ../src -DCMAKE_FIND_ROOT_PATH=${LUNA_STAGING} -DYAJL_INSTALL_DIR=${LUNA_STAGING} -DWITH_TESTS=False -DWITH_DOCS=False -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS install
}

###########################
#  Fetch and build pmloglib
###########################
function build_pmloglib
{
    do_fetch openwebos/pmloglib $1 pmloglib submissions/
    mkdir -p $BASE/pmloglib/build
    cd $BASE/pmloglib/build
    $CMAKE .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS
    make install
}

##########################
#  Fetch and build nyx-lib
##########################
function build_nyx-lib
{
    do_fetch openwebos/nyx-lib $1 nyx-lib submissions/
    mkdir -p $BASE/nyx-lib/build
    cd $BASE/nyx-lib/build
    $CMAKE .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS
    make install
}

######################
#  Fetch and build qt4
######################
function build_qt4
{
    do_fetch openwebos/qt $1 qt4
    export STAGING_DIR=${LUNA_STAGING}
    if [ ! -f $BASE/qt-build-desktop/Makefile ] ; then
        rm -rf $BASE/qt-build-desktop
    fi
    if [ ! -d $BASE/qt-build-desktop ] ; then
      mkdir -p $BASE/qt-build-desktop
      cd $BASE/qt-build-desktop
      if [ ! -e ../qt4/palm-desktop-configure.orig ] ; then
        cp -f ../qt4/palm-desktop-configure ../qt4/palm-desktop-configure.orig
        sed -i 's/-opensource/-opensource -qpa -fast -qconfig palm -no-dbus/' ../qt4/palm-desktop-configure
        sed -i 's/libs tools/libs/' ../qt4/palm-desktop-configure
      fi
      # This export will be picked up by plugins/platforms/platforms.pro and xcb.pro
      export WEBOS_CONFIG="webos desktop"
      ../qt4/palm-desktop-configure
    fi
    cd $BASE/qt-build-desktop
    make $JOBS
    make install

    # Make alias to moc for BrowserServer build
    # (Could also fix w/sed in BrowserServer build for Makefile.Ubuntu)
    if [ ! -e ${LUNA_STAGING}/bin/moc ]; then
        cd ${LUNA_STAGING}/bin
        ln -s moc-palm moc
    fi
}

################################
#  Fetch and build luna-service2
################################
function build_luna-service2
{
    do_fetch openwebos/luna-service2 $1 luna-service2 submissions/
    mkdir -p $BASE/luna-service2/build
    cd $BASE/luna-service2/build

    #TODO: lunaservice.h no longer needs cjson (and removing the include fixes filecache build)
    sed -i 's!#include <cjson/json.h>!!' ../include/lunaservice.h

    $CMAKE .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS
    make install

    cp -f ${LUNA_STAGING}/include/luna-service2/lunaservice.h ${LUNA_STAGING}/include/
    cp -f ${LUNA_STAGING}/include/luna-service2/lunaservice-errors.h ${LUNA_STAGING}/include/

    cd $LUNA_STAGING/lib
    ln -sf libluna-service2.so liblunaservice.so
}

################################
#  Fetch and build npapi-headers
################################
function build_npapi-headers
{
    do_fetch isis-project/npapi-headers $1 npapi-headers

    ##### To build from your local clone of npapi-headers, change the following line to "cd" to your clone's location
    cd $BASE/npapi-headers
    mkdir -p $LUNA_STAGING/include/webkit/npapi
    cp -f *.h $LUNA_STAGING/include/webkit/npapi
}

##################################
#  Fetch and build luna-webkit-api
##################################
function build_luna-webkit-api
{
    do_fetch openwebos/luna-webkit-api $1 luna-webkit-api

    ##### To build from your local clone of luna-webkit-api, change the following line to "cd" to your clone's location
    cd $BASE/luna-webkit-api
    mkdir -p $LUNA_STAGING/include/ime
    if [ -d include/public/ime ] ; then
        cp -f include/public/ime/*.h $LUNA_STAGING/include/ime
    else
        cp -f *.h $LUNA_STAGING/include/ime
    fi
}

##################################
#  Fetch and build webkit
##################################
function build_webkit
{

    #if [ ! -d $BASE/$WEBKIT_DIR ] ; then
          do_fetch isis-project/WebKit $1 $WEBKIT_DIR
    #fi
    cd $BASE/$WEBKIT_DIR
    if [ ! -e Tools/Tools.pro.prepatch ] ; then
      cp -f Tools/Tools.pro Tools/Tools.pro.prepatch
      sed -i '/PALM_DEVICE/s/:!contains(DEFINES, MACHINE_DESKTOP)//' Tools/Tools.pro
    fi
    if [ ! -e Source/WebCore/platform/webos/LunaServiceMgr.cpp.prepatch ] ; then
      cp -f Source/WebCore/platform/webos/LunaServiceMgr.cpp \
        Source/WebCore/platform/webos/LunaServiceMgr.cpp.prepatch
      patch --directory=Source/WebCore/platform/webos < ${BASE}/luna-sysmgr/desktop-support/webkit-PALM_SERVICE_BRIDGE.patch
    fi
    export QTDIR=$BASE/qt4
    export QMAKE=$LUNA_STAGING/bin/qmake-palm
    export QMAKEPATH=$WEBKIT_DIR/Tools/qmake
    export WEBKITOUTPUTDIR="WebKitBuild/isis-x86"

    ./Tools/Scripts/build-webkit --qt \
        --release \
        --no-video \
        --fullscreen-api \
        --no-3d-canvas \
        --only-webkit \
        --no-webkit2 \
        --qmake="${QMAKE}" \
        --makeargs="${JOBS}" \
        --qmakearg="DEFINES+=MACHINE_DESKTOP" \
        --qmakearg="DEFINES+=ENABLE_PALM_SERVICE_BRIDGE=1" \
        --qmakearg="DEFINES+=PALM_DEVICE" \
        --qmakearg="DEFINES+=XP_UNIX" \
        --qmakearg="DEFINES+=XP_WEBOS" \
        --qmakearg="DEFINES+=QT_WEBOS" \
        --qmakearg="DEFINES+=WTF_USE_ZLIB=1"

        ### TODO: To support video in browser, change --no-video to --video and add these these two lines
        #--qmakearg="DEFINES+=WTF_USE_GSTREAMER=1" \
        #--qmakearg="DEFINES+=ENABLE_GLIB_SUPPORT=1"

    if [ "$?" != "0" ] ; then
       echo Failed to make $NAME
       exit 1
    fi
    pushd $WEBKITOUTPUTDIR/Release
    make install
    if [ "$?" != "0" ] ; then
       echo Failed to install $NAME
       exit 1
    fi
    popd
}

##################################
#  Fetch and build luna-sysmgr-ipc
##################################
function build_luna-sysmgr-ipc
{
    do_fetch openwebos/luna-sysmgr-ipc $1 luna-sysmgr-ipc

    ##### To build from your local clone of luna-sysmgr-ipc, change the following line to "cd" to your clone's location
    cd $BASE/luna-sysmgr-ipc
    make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=release
}

###########################################
#  Fetch and build luna-sysmgr-ipc-messages
###########################################
function build_luna-sysmgr-ipc-messages
{
    do_fetch openwebos/luna-sysmgr-ipc-messages $1 luna-sysmgr-ipc-messages

     ##### To build from your local clone of luna-sysmgr-ipc-messages, change the following line to "cd" to your clone's location
    cd $BASE/luna-sysmgr-ipc-messages
    if [ -d include/public/messages ] ; then
        mkdir -p $LUNA_STAGING/include/sysmgr_ipc
        cp -f include/public/messages/*.h $LUNA_STAGING/include/sysmgr_ipc
    else
        make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=release
    fi
}

#################################
# Fetch and build luna-prefs
################################# 
function build_luna-prefs
{
    do_fetch openwebos/luna-prefs $1 luna-prefs

    ##### To build from your local clone of luna-prefs, change the following line to "cd" to your clone's location
    cd $BASE/luna-prefs
    make $JOBS
    cp -d bin/lib/libluna-prefs.so* $LUNA_STAGING/lib
    cp include/lunaprefs.h $LUNA_STAGING/include

    #TODO: Switch to cmake build
    #mkdir -p $BASE/luna-prefs/build
    #cd $BASE/luna-prefs/build
    #$CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    #make $JOBS
    #make install
}

#################################
# Fetch and build luna-sysservice
################################# 
function build_luna-sysservice 
{
    do_fetch openwebos/luna-sysservice $1 luna-sysservice

    ##### To build from your local clone of luna-sysservice, change the following line to "cd" to your clone's location
    cd $BASE/luna-sysservice

    #TODO: Switch to cmake build (after pbnjson + cmake)
    #mkdir -p build
    #cd build
    #sed -i 's/REQUIRED uriparser/REQUIRED liburiparser/' ../CMakeLists.txt
    #PKG_CONFIG_PATH=$LUNA_STAGING/lib/pkgconfig \
    #$CMAKE .. -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    #$CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    #make $JOBS
    #make install

    # TODO: luna-sysservice generates a few warnings which will kill the build if we don't turn off -Werror
    sed -i 's/-Werror//' Makefile.inc
    #sed -i 's/#include "json_utils.h"//' Src/ImageServices.cpp
    # link fails without -rpath-link to help libpbnjson_cpp.so find libpbnjson_c.so
    export LDFLAGS="-Wl,-rpath-link $LUNA_STAGING/lib"
    make $JOBS -f Makefile.Ubuntu

    #cp debug-x86/LunaSysService $LUNA_STAGING/bin
    # NOTE: Make binary findable in /usr/lib/luna so ls2 can match the role file
    cp -f debug-x86/LunaSysService $ROOTFS/usr/lib/luna/
    # ls-control is used by serviceinstaller
    #chmod ugo+x ../desktop-support/ls-control
    #cp -f ../desktop-support/ls-control $ROOTFS/usr/lib/luna/

    # TODO: cmake should do this for us (after we switch)
    cp -rf files/conf/* ${ROOTFS}/etc/palm
    cp -f desktop-support/com.palm.systemservice.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.systemservice.json
    cp -f desktop-support/com.palm.systemservice.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.systemservice.json
    cp -f desktop-support/com.palm.systemservice.service.pub $ROOTFS/usr/share/ls2/services/com.palm.systemservice.service
    cp -f desktop-support/com.palm.systemservice.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.systemservice.service
    mkdir -p $ROOTFS/etc/palm/backup
    cp -f desktop-support/com.palm.systemservice.backupRegistration.json $ROOTFS/etc/palm/backup/com.palm.systemservice
}

###########################################
#  Fetch and build enyo 1.0
###########################################
function build_enyo-1.0
{
    do_fetch enyojs/enyo-1.0 $1 enyo-1.0 submissions/
    cd $BASE/enyo-1.0
    mkdir -p $ROOTFS/usr/palm/frameworks/enyo/0.10/framework
    cp -rf framework/* $ROOTFS/usr/palm/frameworks/enyo/0.10/framework
    cd $ROOTFS/usr/palm/frameworks/enyo/
    # add symlink for enyo version 1.0 (which was 0.10)
    ln -sf -T 0.10 1.0
}

###########################################
#  Fetch and build Core Apps
###########################################
function build_core-apps
{
    do_fetch openwebos/core-apps $1 core-apps

    ##### To build from your local clone of core-apps, change the following line to "cd" to your clone's location
    cd $BASE/core-apps
    # TODO: fix calculator appId:
    sed -i 's/com.palm.calculator/com.palm.app.calculator/' com.palm.app.calculator/appinfo.json

    mkdir -p $ROOTFS/usr/palm/applications
    for APP in com.palm.app.* ; do
      cp -rf ${APP} $ROOTFS/usr/palm/applications/
      cp -rf ${APP}/configuration/db/kinds/* $ROOTFS/etc/palm/db/kinds/ 2>/dev/null || true
      cp -rf ${APP}/configuration/db/permissions/* $ROOTFS/etc/palm/db/permissions/ 2>/dev/null || true
    done
}

###########################################
#  Fetch and build luna-applauncher
###########################################
function build_luna-applauncher
{
    do_fetch openwebos/luna-applauncher $1 luna-applauncher

    ##### To build from your local clone of luna-applauncher, change the following line to "cd" to your clone's location
    cd $BASE/luna-applauncher
    mkdir -p $ROOTFS/usr/lib/luna/system/luna-applauncher
    cp -rf . $ROOTFS/usr/lib/luna/system/luna-applauncher
}

###########################################
#  Fetch and build luna-systemui
###########################################
function build_luna-systemui
{
    do_fetch openwebos/luna-systemui $1 luna-systemui

    ##### To build from your local clone of luna-systemui, change the following line to "cd" to your clone's location
    cd $BASE/luna-systemui
    mkdir -p $ROOTFS/usr/lib/luna/system/luna-systemui
    cp -rf . $ROOTFS/usr/lib/luna/system/luna-systemui
}

###########################################
#  Fetch and build foundation-frameworks
###########################################
function build_foundation-frameworks
{
    do_fetch openwebos/foundation-frameworks $1 foundation-frameworks
    cd $BASE/foundation-frameworks
    mkdir -p $ROOTFS/usr/palm/frameworks/
    for FRAMEWORK in `ls -d1 foundations*` ; do
      mkdir -p $ROOTFS/usr/palm/frameworks/$FRAMEWORK/version/1.0/
      cp -rf $FRAMEWORK/* $ROOTFS/usr/palm/frameworks/$FRAMEWORK/version/1.0/
    done
}

###########################################
#  Fetch and build mojoservice-frameworks
###########################################
function build_mojoservice-frameworks
{
    do_fetch openwebos/mojoservice-frameworks $1 mojoservice-frameworks
    cd $BASE/mojoservice-frameworks
    mkdir -p $ROOTFS/usr/palm/frameworks/
    for FRAMEWORK in `ls -d1 mojoservice*` ; do
      mkdir -p $ROOTFS/usr/palm/frameworks/$FRAMEWORK/version/1.0/
      cp -rf $FRAMEWORK/* $ROOTFS/usr/palm/frameworks/$FRAMEWORK/version/1.0/
    done
}

###########################################
#  Fetch and build loadable-frameworks
###########################################
function build_loadable-frameworks
{
    do_fetch openwebos/loadable-frameworks $1 loadable-frameworks
    cd $BASE/loadable-frameworks
    mkdir -p $ROOTFS/usr/palm/frameworks/
    for FRAMEWORK in `ls -d1 calendar* contacts globalization` ; do
      mkdir -p $ROOTFS/usr/palm/frameworks/$FRAMEWORK/version/1.0/
      cp -rf $FRAMEWORK/* $ROOTFS/usr/palm/frameworks/$FRAMEWORK/version/1.0/
    done
}

###########################################
#  Fetch and build underscore
###########################################
function build_underscore
{
    do_fetch openwebos/underscore $1 underscore submissions/
    mkdir -p $ROOTFS/usr/palm/frameworks/
    mkdir -p $ROOTFS/usr/palm/frameworks/underscore/version/1.0/
    cp -rf $BASE/underscore/* $ROOTFS/usr/palm/frameworks/underscore/version/1.0/
}

###########################################
#  Fetch and build mojoloader
###########################################
function build_mojoloader
{
    #TODO: mojoloader should be moved to openwebos/loadable-frameworks
    do_fetch openwebos/build-desktop $1 mojoloader
    mkdir -p $ROOTFS/usr/palm/frameworks/
    cp -rf $BASE/mojoloader/mojoloader/mojoloader.js $ROOTFS/usr/palm/frameworks/
}

###########################################
#  Fetch and build mojoservicelauncher
###########################################
function build_mojoservicelauncher
{
    do_fetch openwebos/mojoservicelauncher $1 mojoservicelauncher submissions/
    mkdir -p $BASE/mojoservicelauncher/build
    cd $BASE/mojoservicelauncher/build
    sed -i 's!DESTINATION /!DESTINATION !' ../CMakeLists.txt
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
    # copy mojoservicelauncher files from staging to rootfs
    mkdir -p $ROOTFS/usr/palm/services/jsservicelauncher
    cp -f $LUNA_STAGING/usr/palm/services/jsservicelauncher/* $ROOTFS/usr/palm/services/jsservicelauncher
    # most services launch with run-js-service
    chmod ugo+x ../desktop-support/run-js-service
    cp -f ../desktop-support/run-js-service $ROOTFS/usr/lib/luna/
    # jslauncher is used by com.palm.service.calendar.reminders
    chmod ugo+x ../desktop-support/jslauncher
    cp -f ../desktop-support/jslauncher $ROOTFS/usr/lib/luna/
}

###########################################
#  Fetch and build app-services
###########################################
function build_app-services
{
    do_fetch openwebos/app-services $1 app-services

    ##### To build from your local clone of app-services, change the following line to "cd" to your clone's location
    cd $BASE/app-services
    rm -rf mojomail
    mkdir -p $ROOTFS/usr/palm/services

    for SERVICE in com.palm.service.* ; do
      cp -rf ${SERVICE} $ROOTFS/usr/palm/services/
      cp -rf ${SERVICE}/db/kinds/* $ROOTFS/etc/palm/db/kinds/ 2>/dev/null || true
      cp -rf ${SERVICE}/db/permissions/* $ROOTFS/etc/palm/db/permissions/ 2>/dev/null || true
      cp -rf ${SERVICE}/activities/* $ROOTFS/etc/palm/activities/ 2>/dev/null || true
      cp -rf ${SERVICE}/files/sysbus/*.json $ROOTFS/usr/share/ls2/roles/prv 2>/dev/null || true
      #NOTE: services go in $ROOTFS/usr/share/ls2/system-services, which is linked from /usr/share/ls2/system-services
      cp -rf ${SERVICE}/desktop-support/*.service $ROOTFS/usr/share/ls2/system-services 2>/dev/null || true
    done

    # accounts service is public, so install its service file in public service dir
    cp -rf com.palm.service.accounts/desktop-support/*.service $ROOTFS/usr/share/ls2/services

    # install accounts service desktop credentials db kind
    cp -rf com.palm.service.accounts/desktop/com.palm.account.credentials $ROOTFS/etc/palm/db/kinds

    # install account-templates service
    mkdir -p $ROOTFS/usr/palm/public/accounts
    cp -rf account-templates/palmprofile/com.palm.palmprofile $ROOTFS/usr/palm/public/accounts/

    # install tempdb kinds and permissions
    mkdir -p $ROOTFS/etc/palm/tempdb/kinds
    mkdir -p $ROOTFS/etc/palm/tempdb/permissions
    cp -rf com.palm.service.accounts/tempdb/kinds/* $ROOTFS/etc/palm/tempdb/kinds/ 2>/dev/null || true
    cp -rf com.palm.service.accounts/tempdb/permissions/* $ROOTFS/etc/palm/tempdb/permissions/ 2>/dev/null || true
}

###########################################
#  Fetch and build mojomail
###########################################
function build_mojomail
{
    #TODO: mojomail should live in its own repo instead of app-services...
    do_fetch openwebos/app-services $1 mojomail
    rm -rf $BASE/mojomail/com.palm.service.* $BASE/mojomail/account-templates
    cd $BASE/mojomail/mojomail
    for SUBDIR in common imap pop smtp ; do
      mkdir -p $BASE/mojomail/mojomail/$SUBDIR/build
      cd $BASE/mojomail/mojomail/$SUBDIR/build
      sed -i 's!DESTINATION /!DESTINATION !' ../CMakeLists.txt
      $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
      #make $JOBS VERBOSE=1
      make $JOBS
      make install
      mkdir -p $ROOTFS/usr/palm/public/accounts
      cp -rf ../files/usr/palm/public/accounts/* $ROOTFS/usr/palm/public/accounts/ 2>/dev/null || true
      cp -rf ../files/db8/kinds/* $ROOTFS/etc/palm/db/kinds 2> /dev/null || true
    done

    # TODO: (cmake should do this) install filecache types
    mkdir -p $ROOTFS/etc/palm/filecache_types
    cp -rf $BASE/mojomail/mojomail/common/files/etc/palm/filecache_types/* $ROOTFS/etc/palm/filecache_types

    # NOTE: Make binaries findable in /usr/lib/luna so ls2 can match the role file
    cd $BASE/mojomail/mojomail
    cp imap/build/mojomail-imap "${ROOTFS}/usr/lib/luna/"
    cp pop/build/mojomail-pop "${ROOTFS}/usr/lib/luna/"
    cp smtp/build/mojomail-smtp "${ROOTFS}/usr/lib/luna/"
    cp -f desktop-support/com.palm.imap.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.imap.json
    cp -f desktop-support/com.palm.pop.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.pop.json
    cp -f desktop-support/com.palm.smtp.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.smtp.json
    cp -f desktop-support/com.palm.imap.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.imap.service
    cp -f desktop-support/com.palm.pop.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.pop.service
    cp -f desktop-support/com.palm.smtp.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.smtp.service
}

##############################
#  Fetch and build luna-sysmgr
##############################
function build_luna-sysmgr
{
    if [ ! -d $BASE/luna-sysmgr ] || [ ! -e $BASE/luna-sysmgr/desktop-support/com.palm.luna.json.prv ] ; then
        do_fetch openwebos/luna-sysmgr $1 luna-sysmgr
    fi

    ##### To build from your local clone of luna-sysmgr, change the following line to "cd" to your clone's location
    cd $BASE/luna-sysmgr

    if [ ! -e "luna-desktop-build-${1}.stamp" ] ; then
        if [ $SKIPSTUFF -eq 0 ] && [ -e debug-x86 ] && [ -e debug-x86/.obj ] ; then
            rm -f debug-x86/LunaSysMgr
            rm -rf debug-x86/.obj/*
            rm -rf debug-x86/.moc/moc_*.cpp
            rm -rf debug-x86/.moc/*.moc
        fi
        $LUNA_STAGING/bin/qmake-palm
    fi
    make $JOBS -f Makefile.Ubuntu
    mkdir -p $LUNA_STAGING/lib/sysmgr-images
    cp -frad images/* $LUNA_STAGING/lib/sysmgr-images
    #cp -f debug-x86/LunaSysMgr $LUNA_STAGING/lib
    #cp -f debug-x86/LunaSysMgr $LUNA_STAGING/bin

    # Note: ls2/roles/prv/com.palm.luna.json refers to /usr/lib/luna/LunaSysMgr and ls2 uses that path to match role files.
    mkdir -p $ROOTFS/usr/lib/luna
    cp -f debug-x86/LunaSysMgr $ROOTFS/usr/lib/luna/LunaSysMgr

    #TODO: (temporary) remove old luna-sysmgr user scripts from $BASE
    rm -f $BASE/service-bus.sh
    rm -f $BASE/run-luna-sysmgr.sh
    rm -f $BASE/install-luna-sysmgr.sh

    mkdir -p $ROOTFS/usr/lib/luna/system/luna-applauncher
    cp -f desktop-support/appinfo.json $ROOTFS/usr/lib/luna/system/luna-applauncher/appinfo.json

    cp -f desktop-support/com.palm.luna.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.luna.json
    cp -f desktop-support/com.palm.luna.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.luna.json
    cp -f desktop-support/com.palm.luna.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.luna.service
    cp -f desktop-support/com.palm.luna.service.pub $ROOTFS/usr/share/ls2/services/com.palm.luna.service

    mkdir -p $ROOTFS/etc/palm/pubsub_handlers
    cp -f service/com.palm.appinstaller.pubsub $ROOTFS/etc/palm/pubsub_handlers/com.palm.appinstaller

    cp -f conf/default-exhibition-apps.json $ROOTFS/etc/palm/default-exhibition-apps.json
    cp -f conf/default-launcher-page-layout.json $ROOTFS/etc/palm/default-launcher-page-layout.json
    cp -f conf/defaultPreferences.txt $ROOTFS/etc/palm/defaultPreferences.txt
    cp -f conf/luna.conf $ROOTFS/etc/palm/luna.conf
    cp -f conf/luna-desktop.conf $ROOTFS/etc/palm/luna-platform.conf
    cp -f conf/lunaAnimations.conf $ROOTFS/etc/palm/lunaAnimations.conf
    cp -f conf/notificationPolicy.conf $ROOTFS/etc/palm//notificationPolicy.conf

    mkdir -p $ROOTFS/usr/lib/luna/customization
    cp -f conf/default-exhibition-apps.json $ROOTFS/usr/lib/luna/customization/default-exhibition-apps.json

    mkdir -p $ROOTFS/usr/palm/sounds
    cp -f sounds/* $ROOTFS/usr/palm/sounds

    mkdir -p $ROOTFS/etc/palm/luna-applauncher
    cp -f desktop-support/appinfo.json $ROOTFS/etc/palm/luna-applauncher

    mkdir -p $ROOTFS/etc/palm/launcher3
    cp -rf conf/launcher3/* $ROOTFS/etc/palm/launcher3

    mkdir -p $ROOTFS/etc/palm/schemas
    cp -rf conf/*.schema $ROOTFS/etc/palm/schemas

    #TODO: (temporary) remove old "db-kinds"; directory should be db_kinds (though db/kinds is also used)
    rm -rf $ROOTFS/etc/palm/db-kinds

    mkdir -p $ROOTFS/etc/palm/db_kinds
    cp -f mojodb/com.palm.securitypolicy $ROOTFS/etc/palm/db_kinds
    cp -f mojodb/com.palm.securitypolicy.device $ROOTFS/etc/palm/db_kinds
    mkdir -p $ROOTFS/etc/palm/db/permissions
    cp -f mojodb/com.palm.securitypolicy.permissions $ROOTFS/etc/palm/db/permissions/com.palm.securitypolicy

    mkdir -p $ROOTFS/usr/palm/sysmgr/images
    cp -fr images/* $ROOTFS/usr/palm/sysmgr/images
    mkdir -p $ROOTFS/usr/palm/sysmgr/localization
    mkdir -p $ROOTFS/usr/palm/sysmgr/low-memory
    cp -frad low-memory/* $ROOTFS/usr/palm/sysmgr/low-memory
    mkdir -p $ROOTFS/usr/palm/sysmgr/uiComponents
    cp -frad uiComponents/* $ROOTFS/usr/palm/sysmgr/uiComponents

}

#####################################
#  Fetch and build WebKitSupplemental
#####################################
function build_WebKitSupplemental
{
    do_fetch isis-project/WebKitSupplemental $1 WebKitSupplemental
    cd $BASE/WebKitSupplemental
    export QTDIR=$BASE/qt-build-desktop
    export QMAKE=$LUNA_STAGING/bin/qmake-palm
    export QMAKEPATH=$WEBKIT_DIR/Tools/qmake
    export QT_INSTALL_PREFIX=$LUNA_STAGING
    export STAGING_DIR=${LUNA_STAGING}
    export STAGING_INCDIR="${LUNA_STAGING}/include"
    export STAGING_LIBDIR="${LUNA_STAGING}/lib"
    $LUNA_STAGING/bin/qmake-palm
    make $JOBS -f Makefile
    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile install BUILD_TYPE=release
}

################################
#  Fetch and build AdapterBase
################################
function build_AdapterBase
{
    do_fetch isis-project/AdapterBase $1 AdapterBase
    cd $BASE/AdapterBase
    export QMAKE=$LUNA_STAGING/bin/qmake-palm
    export QMAKEPATH=$WEBKIT_DIR/Tools/qmake
    $LUNA_STAGING/bin/qmake-palm
    make $JOBS -f Makefile
    make -f Makefile install
    #make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=release
}

###########################################
#  Fetch and build isis-browser
###########################################
function build_isis-browser
{
    do_fetch isis-project/isis-browser $1 isis-browser

    ##### To build from your local clone of isis-browser, change the following line to "cd" to your clone's location
    cd $BASE/isis-browser
    mkdir -p $ROOTFS/etc/palm/db/kinds
    mkdir -p $ROOTFS/etc/palm/db/permissions
    mkdir -p $ROOTFS/usr/palm/applications/com.palm.app.browser
    cp -rf * $ROOTFS/usr/palm/applications/com.palm.app.browser/
    rm -rf $ROOTFS/usr/palm/applications/com.palm.app.browser/db/*
    cp -rf db/kinds/* $ROOTFS/etc/palm/db/kinds/ 2>/dev/null || true
    cp -rf db/permissions/* $ROOTFS/etc/palm/db/permissions/ 2>/dev/null || true
}

################################
#  Fetch and build BrowserServer
################################
function build_BrowserServer
{
    do_fetch isis-project/BrowserServer $1 BrowserServer

    # Make sure alias to moc exists for BrowserServer build
    # (Could also fix using sed on Makefile.Ubuntu)
    cd ${LUNA_STAGING}/bin
    [ -x moc ] || ln -s moc-palm moc

    cd $BASE/BrowserServer
    export QT_INSTALL_PREFIX=$LUNA_STAGING
    export STAGING_DIR=${LUNA_STAGING}
    export STAGING_INCDIR="${LUNA_STAGING}/include"
    export STAGING_LIBDIR="${LUNA_STAGING}/lib"
    # link fails without -rpath to help liblunaservice find libcjson
    # and with rpath-link it fails ar runtime
    export LDFLAGS="-Wl,-rpath $LUNA_STAGING/lib"
    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu all BUILD_TYPE=release

    # stage files
    make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu stage BUILD_TYPE=release
    #make -f Makefile.Ubuntu stage BUILD_TYPE=release

    #cp -f release-x86/BrowserServer $LUNA_STAGING/bin
}

#################################
#  Fetch and build BrowserAdapter 
#################################
function build_BrowserAdapter
{
    do_fetch isis-project/BrowserAdapter $1 BrowserAdapter
    cd $BASE/BrowserAdapter
    export QT_INSTALL_PREFIX=$LUNA_STAGING
    export STAGING_DIR=${LUNA_STAGING}
    export STAGING_INCDIR="${LUNA_STAGING}/include"
    export STAGING_LIBDIR="${LUNA_STAGING}/lib"

    # BrowserAdapter generates a few warnings which will kill the build if we don't turn off -Werror
    sed -i 's/-Werror//' Makefile.inc

    #make $JOBS -f Makefile.Ubuntu BUILD_TYPE=release
    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu all BUILD_TYPE=release

    # stage files
    make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu stage BUILD_TYPE=release

    # TODO: Might need to install files (maybe more than just these) in BrowserAdapterData...
    #mkdir -p $LUNA_STAGING/lib/BrowserPlugins/BrowserAdapterData
    #cp -f data/launcher-bookmark-alpha.png $LUNA_STAGING/lib/BrowserPlugins/BrowserAdapterData
    #cp -f data/launcher-bookmark-overlay.png $LUNA_STAGING/lib/BrowserPlugins/BrowserAdapterData
}

#########################
#  Fetch and build nodejs
#########################
function build_nodejs
{
    do_fetch openwebos/nodejs $1 nodejs submissions/
    mkdir -p $BASE/nodejs/build
    cd $BASE/nodejs/build
    $CMAKE .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS
    make install
    # NOTE: Make binary findable in /usr/palm/nodejs so ls2 can match the role file
    # role file is com.palm.nodejs.json (from nodejs-module-webos-sysbus)
    # run-js-service (from mojoservicelauncher) calls /usr/palm/nodejs/node (not /usr/lib/luna/node)
    cp -f default/node "${ROOTFS}/usr/palm/nodejs/node"
}

#################################
# Fetch and build node-addons
#################################
function build_node-addon
{
    do_fetch "openwebos/nodejs-module-webos-${1}" $2 nodejs-module-webos-${1} submissions/
    mkdir -p $BASE/nodejs-module-webos-${1}/build
    cd $BASE/nodejs-module-webos-${1}/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS VERBOSE=1
    #make $JOBS
    make install
    # NOTE: Install built node module to /usr/lib/nodejs. Names have changed; may need to be fixed.
    cp -f webos-${1}.node $ROOTFS/usr/palm/nodejs/
    if [ "${1}" = "sysbus" ] ; then
      cp -f ../desktop-support/com.palm.nodejs.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.nodejs.json
      cp -f ../desktop-support/com.palm.nodejs.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.nodejs.json
    fi
    # copy old node module names (as symlinks) from staging to ROOTFS
    cp -fd ${LUNA_STAGING}/usr/lib/nodejs/*.node $ROOTFS/usr/palm/nodejs
}

#####################
# Fetch and build db8
##################### 
function build_db8
{
    do_fetch openwebos/db8 $1 db8 submissions/

    ##### To build from your local clone of db8, change the following line to "cd" to your clone's location
    cd $BASE/db8
    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=release
    # NOTE: Make binary findable in /usr/lib/luna so ls2 can match the role file
    cp -f release-linux-x86/mojodb-luna "${ROOTFS}/usr/lib/luna/"
    # TODO: remove after switching to cmake
    cp -f desktop-support/com.palm.db.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.db.json
    cp -f desktop-support/com.palm.db.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.db.json
    cp -f desktop-support/com.palm.db.service $ROOTFS/usr/share/ls2/services/com.palm.db.service
    cp -f desktop-support/com.palm.db.service $ROOTFS/usr/share/ls2/system-services/com.palm.db.service
    cp -f desktop-support/com.palm.tempdb.service $ROOTFS/usr/share/ls2/system-services/com.palm.tempdb.service
    cp -f src/db-luna/mojodb.conf $ROOTFS/etc/palm/mojodb.conf
}

##############################
# Fetch and build configurator
##############################
function build_configurator
{
    do_fetch openwebos/configurator $1 configurator

    ##### To build from your local clone of configurator, change the following line to "cd" to your clone's location
    cd $BASE/configurator
    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
    # NOTE: Make binary findable in /usr/lib/luna so ls2 can match the role file
    cp -f configurator "${ROOTFS}/usr/lib/luna/"
    cp -f ../desktop-support/com.palm.configurator.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.configurator.json
    cp -f ../desktop-support/com.palm.configurator.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.configurator.service
}

#################################
# Fetch and build activitymanager
#################################
function build_activitymanager
{
    do_fetch openwebos/activitymanager $1 activitymanager submissions/

    ##### To build from your local clone of activitymanager, change the following line to "cd" to your clone's location
    cd $BASE/activitymanager
    mkdir -p build
    cd build
    #TODO: Remove this when db8 gets a pkgconfig file...
    sed -i "s!/include/mojodb!${LUNA_STAGING}/include/mojodb!" ../CMakeLists.txt
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
    # NOTE: Make binary findable in /usr/lib/luna so ls2 can match the role file
    cp -f activitymanager "${ROOTFS}/usr/lib/luna/"
    cp -f ../desktop-support/com.palm.activitymanager.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.activitymanager.json
    cp -f ../desktop-support/com.palm.activitymanager.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.activitymanager.json
    cp -f ../desktop-support/com.palm.activitymanager.service.pub $ROOTFS/usr/share/ls2/services/com.palm.activitymanager.service
    cp -f ../desktop-support/com.palm.activitymanager.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.activitymanager.service
    # Copy db8 files 
      cp -rf ../files/db8/kinds/* $ROOTFS/etc/palm/db/kinds/ 2>/dev/null || true
      cp -rf ../files/db8/permissions/* $ROOTFS/etc/palm/db/permissions/ 2>/dev/null || true
}

#######################################
#  Fetch and build pmstatemachineengine
#######################################
function build_pmstatemachineengine
{
    do_fetch openwebos/pmstatemachineengine $1 pmstatemachineengine submissions/
    mkdir -p $BASE/pmstatemachineengine/build
    cd $BASE/pmstatemachineengine/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install
}

################################
#  Fetch and build libpalmsocket
################################
function build_libpalmsocket
{
    do_fetch openwebos/libpalmsocket $1 libpalmsocket submissions/
    mkdir -p $BASE/libpalmsocket/build
    cd $BASE/libpalmsocket/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install
}

#############################
#  Fetch and build libsandbox
#############################
function build_libsandbox
{
    # TODO: Remove this workaround to fetch a not-yet-public zipball when github won't give it to us from the usual spot
    # That is, when tagged zipballs work from https://github.com/openwebos/libsandbox/tags, we will no longer need this:
    GIT_SOURCE=https://${GITHUB_USER}:${GITHUB_PASS}@github.com/downloads/openwebos/build-desktop/libsandbox_${1}.zip
    ZIPFILE="${BASE}/tarballs/libsandbox_${1}.zip"
    echo "About to fetch libsandbox zipball from build-desktop..."
    curl -L -R -# ${GIT_SOURCE} -o "${ZIPFILE}"

    do_fetch openwebos/libsandbox $1 libsandbox submissions/
    mkdir -p $BASE/libsandbox/build
    cd $BASE/libsandbox/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install
}

###########################
#  Fetch and build jemalloc
###########################
function build_jemalloc
{
    do_fetch openwebos/jemalloc $1 jemalloc submissions/
    mkdir -p $BASE/jemalloc/build
    cd $BASE/jemalloc/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
}

###########################
#  Fetch and build librolegen
###########################
function build_librolegen
{
    do_fetch openwebos/librolegen $1 librolegen submissions/
    
    ##### To build from your local clone of librolegen, change the following line to "cd" to your clone's location
    cd $BASE/librolegen
    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
}

###########################
#  Fetch and build serviceinstaller
###########################
function build_serviceinstaller
{
    do_fetch openwebos/serviceinstaller $1 serviceinstaller
    
    ##### To build from your local clone of serviceinstaller, change the following line to "cd" to your clone's location
    cd $BASE/serviceinstaller
    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
}

###########################
#  Fetch and build luna-universalsearchmgr
###########################
function build_luna-universalsearchmgr
{
    do_fetch openwebos/luna-universalsearchmgr $1 luna-universalsearchmgr
    
    ##### To build from your local clone of luna-universalsearchmgr, change the following line to "cd" to your clone's location
    cd $BASE/luna-universalsearchmgr
    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
    # NOTE: Make binary findable in /usr/lib/luna so luna-universalsearchmgr can match the role file
    cp -f $LUNA_STAGING/usr/sbin/luna-universalsearchmgr "${ROOTFS}/usr/lib/luna/"
    cp -f ../desktop-support/com.palm.universalsearch.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.universalsearch.json
    cp -f ../desktop-support/com.palm.universalsearch.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.universalsearch.json
    cp -f ../desktop-support/com.palm.universalsearch.service.pub $ROOTFS/usr/share/ls2/services/com.palm.universalsearch.service
    cp -f ../desktop-support/com.palm.universalsearch.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.universalsearch.service
    mkdir -p "${ROOTFS}/usr/palm/universalsearchmgr/resources/en_us"
    cp -f ../desktop-support/UniversalSearchList.json "${ROOTFS}/usr/palm/universalsearchmgr/resources/en_us"
    
}

############################
#  Fetch and build filecache
############################
function build_filecache
{
    do_fetch openwebos/filecache $1 filecache submissions/
    mkdir -p $BASE/filecache/build
    cd $BASE/filecache/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
    cp -f filecache "${ROOTFS}/usr/lib/luna/"
    cp -f ../desktop-support/com.palm.filecache.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.filecache.json
    cp -f ../desktop-support/com.palm.filecache.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.filecache.json
    cp -f ../desktop-support/com.palm.filecache.service.pub $ROOTFS/usr/share/ls2/services/com.palm.filecache.service
    cp -f ../desktop-support/com.palm.filecache.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.filecache.service
    cp -f ../files/conf/FileCache.conf $ROOTFS/etc/palm/
}

###############
# build wrapper
###############
function build
{
    if [ "$1" = "webkit" ] ; then
        BUILD_DIR=$WEBKIT_DIR
    elif [ "$1" = "node-addon" ] ; then
        BUILD_DIR="nodejs-module-webos-${2}"
    else
        BUILD_DIR=$1
    fi
    if [ $SKIPSTUFF -eq 0 ] || [ ! -d $BASE/$BUILD_DIR ] || \
       [ ! -e $BASE/$BUILD_DIR/luna-desktop-build-$2.stamp ] ; then
        echo
        echo "Building ${BUILD_DIR} ..."
        echo
        time build_$1 $2 $3 $4
        echo
        if [ -d $BASE/$BUILD_DIR ] ; then
            touch $BASE/$BUILD_DIR/luna-desktop-build-$2.stamp
        fi
        return
    fi
    echo
    echo "Skipping $1 ..."
    echo
}


echo ""
echo "**********************************************************"
echo "Binaries will be built in ${BASE}."
echo "Components will be staged in ${LUNA_STAGING}."
echo "Components will be installed in ${ROOTFS}."
echo ""
echo "If you want to change this edit the 'BASE' variable in this script."
echo ""
echo "(Checking processors: $PROCS found)"
echo ""
echo "**********************************************************"
echo ""

mkdir -p $LUNA_STAGING/lib
mkdir -p $LUNA_STAGING/bin
mkdir -p $LUNA_STAGING/include

mkdir -p ${ROOTFS}/etc/ls2
mkdir -p ${ROOTFS}/etc/palm
mkdir -p ${ROOTFS}/etc/palm/db_kinds
mkdir -p ${ROOTFS}/etc/palm/db/kinds
mkdir -p ${ROOTFS}/etc/palm/db/permissions
mkdir -p ${ROOTFS}/etc/palm/activities
# NOTE: desktop ls2 .conf files will look for services in /usr/share/ls2/*services
# NOTE: but on device they live in /usr/share/dbus-1/*services (which is used by Ubuntu dbus)
# NOTE: To avoid problems, we'll symlink from the dbus-1 path in $ROOTFS, but our install
# NOTE: script only links from /usr/share/ls2, which is where our ls2 conf files need to look.
#mkdir -p ${ROOTFS}/share/dbus-1/system-services
#mkdir -p ${ROOTFS}/share/dbus-1/services
mkdir -p ${ROOTFS}/usr/share/dbus-1
ln -sf -T ${ROOTFS}/usr/share/ls2/system-services ${ROOTFS}/usr/share/dbus-1/system-services
ln -sf -T ${ROOTFS}/usr/share/ls2/services ${ROOTFS}/usr/share/dbus-1/services

# NOTE: desktop ls2 .conf files will look for roles in /usr/share/ls2/roles (which is linked to $ROOTFS)
mkdir -p ${ROOTFS}/usr/share/ls2/roles/prv
mkdir -p ${ROOTFS}/usr/share/ls2/roles/pub
mkdir -p ${ROOTFS}/usr/share/ls2/system-services
mkdir -p ${ROOTFS}/usr/share/ls2/services

# binaries go in /usr/lib/luna so service and role files will match
# yes, it should have been called /usr/bin/luna
mkdir -p ${ROOTFS}/usr/lib/luna
# run-js-service needs to export LD_LIBRARY_PATH for nodejs; it shall export /usr/lib/luna/lib
ln -sf -T ${LUNA_STAGING}/lib ${ROOTFS}/usr/lib/luna/lib
mkdir -p ${ROOTFS}/usr/lib/luna/system/luna-systemui
mkdir -p ${ROOTFS}/usr/palm/nodejs
mkdir -p ${ROOTFS}/usr/palm/public/accounts
mkdir -p ${ROOTFS}/usr/palm/services
mkdir -p ${ROOTFS}/usr/palm/smartkey
mkdir -p ${LUNA_STAGING}/var/file-cache
mkdir -p ${ROOTFS}/var/db
mkdir -p ${ROOTFS}/var/luna
mkdir -p ${ROOTFS}/var/palm
mkdir -p ${ROOTFS}/var/usr/palm
set -x

#if [ ! -f "$BASE/build_version_${VERSION}" ] ; then
#  echo "Build script has changed.  Force a clean build"
#  export SKIPSTUFF=0
#fi

export LSM_TAG="0.901"
if [ ! -d "$BASE/luna-sysmgr" ] || [ ! -d "$BASE/tarballs" ] || [ ! -e "$BASE/tarballs/luna-sysmgr_${LSM_TAG}.zip" ] ; then
    do_fetch openwebos/luna-sysmgr ${LSM_TAG} luna-sysmgr
fi
if [ -d $BASE/luna-sysmgr ] ; then
    rm -f $BASE/luna-sysmgr/luna-desktop-build.stamp
fi

# Build a local version of cmake 2.8.7 so that cmake-modules-webos doesn't have to write to the OS-supplied CMake modules directory
build cmake
build cmake-modules-webos 9

build cjson 35
build pbnjson 2
build pmloglib 21
build nyx-lib 58
build luna-service2 140
build qt4 0.34
build npapi-headers 0.4
build luna-webkit-api 0.90
build webkit 0.3

build luna-sysmgr-ipc 0.90
build luna-sysmgr-ipc-messages 0.90
build luna-sysmgr $LSM_TAG

build luna-prefs 0.91
build luna-sysservice 0.92
build librolegen 16
##build serviceinstaller 0.90
build luna-universalsearchmgr 0.91

build luna-applauncher 0.90
build luna-systemui 0.90

build enyo-1.0 128.2
build core-apps 1.0.4
build isis-browser 0.21

build foundation-frameworks 1.0
build mojoservice-frameworks 1.0
build loadable-frameworks 1.0.1
build app-services 1.02

build underscore 8
build mojoloader 4
build mojoservicelauncher 70

build WebKitSupplemental 0.4
build AdapterBase 0.2
build BrowserServer 0.4
build BrowserAdapter 0.3

build nodejs 34
build node-addon sysbus 25
build node-addon pmlog 10
build node-addon dynaload 11

build db8 55
build configurator 1.04

build activitymanager 108
build pmstatemachineengine 13
build libpalmsocket 30
build libsandbox 15
build jemalloc 11
build filecache 54

#NOTE: mojomail depends on libsandbox, libpalmsocket, and pmstatemachine; and lives in app-services repo
build mojomail 1.03

echo ""
echo "Complete. "
touch $BASE/build_version_$VERSION
echo ""
echo "Binaries are in $LUNA_STAGING/lib, $LUNA_STAGING/bin"
echo ""

