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

export LSM_TAG="0.824"

if [ "$1" = "clean" ] ; then
  export SKIPSTUFF=0
  set -e
elif [ "$1" = "--help" ] ; then
    echo "Usage:  ./build-luna-sysmgr.sh [OPTION]"
    echo "Builds the luna-sysmgr component and its dependencies."
    echo "    The script loads about 350MB of source code from GitHub, as needed."
    echo "    NOTE: This script creates about 2.5GB of disk space"
    echo " "
    echo "Optional arguments:"
    echo "    clean   force a rebuild of components"
    echo "    --help  display this help and exit"
    echo "    --version  display version information and exit"
    echo " "
    exit
elif [ "$1" = "--version" ] ; then
    echo "Desktop build script for luna-sysmgr ${LSM_TAG}"
    exit
elif  [ -n "$1" ] ; then
    echo "Parameter $1 not recognized"
    exit
else
  export SKIPSTUFF=1
  set -e
fi


export BASE=$HOME/luna-desktop-binaries

export LUNA_STAGING="${BASE}/staging"
mkdir -p ${BASE}/tarballs
mkdir -p ${LUNA_STAGING}

export BEDLAM_ROOT="${BASE}/staging"
export JAVA_HOME=/usr/lib/jvm/java-6-sun
export JDKROOT=${JAVA_HOME}
export SCRIPT_DIR=$PWD
export PKG_CONFIG_PATH=$LUNA_STAGING/lib/pkgconfig
export MAKEFILES_DIR=$BASE/pmmakefiles

PROCS=`grep -c processor /proc/cpuinfo`
[ $PROCS -gt 1 ] && JOBS="-j${PROCS}"

export WEBKIT_DIR="WebKit"

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
            curl -L -R -# ${GIT_SOURCE} -o "${ZIPFILE}"
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
    ##do_fetch openwebos/pbnjson $1 pbnjson submissions/
    do_fetch isis-project/pbnjson $1 pbnjson
    mkdir -p $BASE/pbnjson/build
    cd $BASE/pbnjson/build
    sed -i 's/set(EXTERNAL_YAJL TRUE)/set(EXTERNAL_YAJL FALSE)/' ../src/CMakeLists.txt
    sed -i 's/add_subdirectory(pjson_engine\//add_subdirectory(deps\//' ../src/CMakeLists.txt
    sed -i 's/-Werror//' ../src/CMakeLists.txt
    cmake ../src -DCMAKE_FIND_ROOT_PATH=${LUNA_STAGING} -DYAJL_INSTALL_DIR=${LUNA_STAGING} -DWITH_TESTS=False -DWITH_DOCS=False -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
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
    cmake .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
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
    cmake .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS
    make install
}

######################
#  Fetch and build qt4
######################
function build_qt4
{
    if [ ! -d $BASE/qt4 ] ; then
      do_fetch openwebos/qt $1 qt4
    fi
    export STAGING_DIR=${LUNA_STAGING}
    if [ ! -f $BASE/qt-build-desktop/Makefile ] ; then
        rm -rf $BASE/qt-build-desktop
    fi
    if [ ! -d $BASE/qt-build-desktop ] ; then
      mkdir -p $BASE/qt-build-desktop
      cd $BASE/qt-build-desktop
      if [ ! -e ../qt4/palm-desktop-configure.orig ] ; then
        cp -f ../qt4/palm-desktop-configure ../qt4/palm-desktop-configure.orig
        sed -i 's/-opensource/-opensource -fast -qconfig palm -no-dbus/' ../qt4/palm-desktop-configure
        sed -i 's/libs tools/libs/' ../qt4/palm-desktop-configure
      fi
      ../qt4/palm-desktop-configure
    fi
    cd $BASE/qt-build-desktop
    make $JOBS
    make install

    # Make alias to moc for BrowserServer build
    # (Could also fix w/sed in BrowserServer build for Makefile.Ubuntu)
    cd ${LUNA_STAGING}/bin
    ln -s moc-palm moc
}

################################
#  Fetch and build luna-service2
################################
function build_luna-service2
{
    do_fetch openwebos/luna-service2 $1 luna-service2 submissions/
    mkdir -p $BASE/luna-service2/build
    cd $BASE/luna-service2/build

    cmake .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
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
        --no-3d-canvas \
        --only-webkit \
        --no-webkit2 \
        --qmake="${QMAKE}" \
        --makeargs="${JOBS}" \
        --makeargs="${PARALLEL_MAKE}" \
        --qmakearg="DEFINES+=MACHINE_DESKTOP" \
        --qmakearg="DEFINES+=ENABLE_PALM_SERVICE_BRIDGE=1" \
        --qmakearg="DEFINES+=PALM_DEVICE" \
        --qmakearg="DEFINES+=XP_UNIX" \
        --qmakearg="DEFINES+=XP_WEBOS" \
        --qmakearg="DEFINES+=QT_WEBOS"

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
    cd $BASE/luna-sysmgr-ipc
    make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=release
}

###########################################
#  Fetch and build luna-sysmgr-ipc-messages
###########################################
function build_luna-sysmgr-ipc-messages
{
    do_fetch openwebos/luna-sysmgr-ipc-messages $1 luna-sysmgr-ipc-messages
    cd $BASE/luna-sysmgr-ipc-messages
    if [ -d include/public/messages ] ; then
        mkdir -p $LUNA_STAGING/include/sysmgr_ipc
        cp -f include/public/messages/*.h $LUNA_STAGING/include/sysmgr_ipc
    else
        make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=release
    fi
}

###########################################
#  Fetch and build enyo 1.0
###########################################
function build_enyo
{
    do_fetch enyojs/enyo-1.0 $1 enyo-1.0 submissions/
    cd $BASE/enyo-1.0
    mkdir -p $BASE/usr/palm/frameworks/enyo/0.10/framework
    cp -rf framework/* $BASE/usr/palm/frameworks/enyo/0.10/framework
}


###########################################
#  Fetch and build Core Apps
###########################################
function build_core-apps
{
    do_fetch openwebos/core-apps $1 core-apps
    cd $BASE/core-apps

    mkdir -p $BASE/usr/palm/applications/com.palm.app.accounts
    cp -rf com.palm.app.accounts/* $BASE/usr/palm/applications/com.palm.app.accounts
    mkdir -p $BASE/usr/palm/applications/com.palm.app.calculator
    cp -rf com.palm.app.calculator/* $BASE/usr/palm/applications/com.palm.app.calculator
    mkdir -p $BASE/usr/palm/applications/com.palm.app.calendar
    cp -rf com.palm.app.calendar/* $BASE/usr/palm/applications/com.palm.app.calendar
    mkdir -p $BASE/usr/palm/applications/com.palm.app.contacts
    cp -rf com.palm.app.contacts/* $BASE/usr/palm/applications/com.palm.app.contacts
    mkdir -p $BASE/usr/palm/applications/com.palm.app.clock
    cp -rf com.palm.app.clock/* $BASE/usr/palm/applications/com.palm.app.clock
    mkdir -p $BASE/usr/palm/applications/com.palm.app.email
    cp -rf com.palm.app.email/* $BASE/usr/palm/applications/com.palm.app.email
    mkdir -p $BASE/usr/palm/applications/com.palm.app.notes
    cp -rf com.palm.app.notes/* $BASE/usr/palm/applications/com.palm.app.notes
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

    if [ ! -e luna-desktop-build.stamp ] ; then
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
    cp -f debug-x86/LunaSysMgr $LUNA_STAGING/lib
    cp -fs $LUNA_STAGING/lib/LunaSysMgr $BASE/usr/lib/luna/LunaSysMgr

    cp -f desktop-support/service-bus.sh  $BASE/service-bus.sh
    cp -f desktop-support/run-luna-sysmgr.sh  $BASE/run-luna-sysmgr.sh
    cp -f desktop-support/install-luna-sysmgr.sh $BASE/install-luna-sysmgr.sh
    cp -f desktop-support/ls*.conf $BASE/ls2

    mkdir -p $BASE/usr/lib/luna/system/luna-applauncher
    cp -f desktop-support/appinfo.json $BASE/usr/lib/luna/system/luna-applauncher/appinfo.json

    cp -f desktop-support/com.palm.luna.json.prv $BASE/ls2/roles/prv/com.palm.luna.json
    cp -f desktop-support/com.palm.luna.json.pub $BASE/ls2/roles/pub/com.palm.luna.json
    cp -f desktop-support/com.palm.luna.service.prv $BASE/share/dbus-1/system-services/com.palm.luna.service
    cp -f desktop-support/com.palm.luna.service.pub $BASE/share/dbus-1/services/com.palm.luna.service
    mkdir -p $BASE/etc/palm/pubsub_handlers
    cp -f service/com.palm.appinstaller.pubsub $BASE/etc/palm/pubsub_handlers/com.palm.appinstaller

    cp -f conf/default-exhibition-apps.json $BASE/etc/palm/default-exhibition-apps.json
    cp -f conf/default-launcher-page-layout.json $BASE/etc/palm/default-launcher-page-layout.json
    cp -f conf/defaultPreferences.txt $BASE/etc/palm/defaultPreferences.txt
    cp -f conf/luna.conf $BASE/etc/palm/luna.conf
    cp -f conf/luna-desktop.conf $BASE/etc/palm/luna-platform.conf
    cp -f conf/lunaAnimations.conf $BASE/etc/palm/lunaAnimations.conf
    cp -f conf/notificationPolicy.conf $BASE/etc/palm//notificationPolicy.conf

    mkdir -p $BASE/usr/lib/luna/customization
    cp -f conf/default-exhibition-apps.json $BASE/usr/lib/luna/customization/default-exhibition-apps.json

    mkdir -p $BASE/usr/palm/sounds
    cp -f sounds/* $BASE/usr/palm/sounds

    mkdir -p $BASE/etc/palm/luna-applauncher
    cp -f desktop-support/appinfo.json $BASE/etc/palm/luna-applauncher

    mkdir -p $BASE/etc/palm/launcher3
    cp -rf conf/launcher3/* $BASE/etc/palm/launcher3

     mkdir -p $BASE/etc/palm/schemas
    cp -rf conf/*.schema $BASE/etc/palm/schemas

    mkdir -p $BASE/etc/palm/db-kinds
    cp -f mojodb/com.palm.securitypolicy $BASE/etc/palm/db-kinds
    cp -f mojodb/com.palm.securitypolicy.device $BASE/etc/palm/db-kinds
    mkdir -p $BASE/etc/palm/db/permissions
    cp -f mojodb/com.palm.securitypolicy.permissions $BASE/etc/palm/db/permissions/com.palm.securitypolicy

    mkdir -p $BASE/usr/palm/sysmgr/images
    cp -fr images/* $BASE/usr/palm/sysmgr/images
    mkdir -p $BASE/usr/palm/sysmgr/localization
    mkdir -p $BASE/usr/palm/sysmgr/low-memory
    cp -frad low-memory/* $BASE/usr/palm/sysmgr/low-memory
    mkdir -p $BASE/usr/palm/sysmgr/uiComponents
    cp -frad uiComponents/* $BASE/usr/palm/sysmgr/uiComponents

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
    # link fails without -rpath-link to help liblunaservice find libcjson
    export LDFLAGS="-Wl,-rpath-link $LUNA_STAGING/lib"
    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu all BUILD_TYPE=release

    # stage files
    make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu stage BUILD_TYPE=release
    #make -f Makefile.Ubuntu stage BUILD_TYPE=release

    #cp release-x86/BrowserServer $LUNA_STAGING/bin
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

    # TODO: Need to install files (maybe more than just these) in BrowserAdapterData...
    #mkdir -p $LUNA_STAGING/lib/BrowserPlugins/BrowserAdapterData
    #cp data/launcher-bookmark-alpha.png $LUNA_STAGING/lib/BrowserPlugins/BrowserAdapterData
    #cp data/launcher-bookmark-overlay.png $LUNA_STAGING/lib/BrowserPlugins/BrowserAdapterData
}

#########################
#  Fetch and build nodejs
#########################
function build_nodejs
{
    do_fetch openwebos/nodejs $1 nodejs versions/
    mkdir -p $BASE/nodejs/build
    cd $BASE/nodejs/build
    cmake .. -DNO_TESTS=True -DNO_UTILS=True -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} -DCMAKE_BUILD_TYPE=Release
    make $JOBS
    make install

    # stage
    mkdir -p ${LUNA_STAGING}/bin/nodejs/bin
    install -m 755 tools/node-waf ${LUNA_STAGING}/bin/nodejs/bin

    mkdir -p ${LUNA_STAGING}/bin/nodejs/lib/node/wafadmin
    tar cf - tools/wafadmin  | tar xf - --strip-components 2 -C ${LUNA_STAGING}/bin/nodejs/lib/node/wafadmin

    # install
    #tools/waf-light install -vv
}

###############
# build wrapper
###############
function build
{
    if [ "$1" = "webkit" ] ; then
        BUILD_DIR=$WEBKIT_DIR
    else
        BUILD_DIR=$1
    fi
    if [ $SKIPSTUFF -eq 0 ] || [ ! -d $BASE/$BUILD_DIR ] || \
       [ ! -e $BASE/$BUILD_DIR/luna-desktop-build.stamp ] ; then
        echo
        echo "Building ${BUILD_DIR} ..."
        echo
        time build_$1 $2 $3 $4
        echo
        if [ -d $BASE/$BUILD_DIR ] ; then
            touch $BASE/$BUILD_DIR/luna-desktop-build.stamp
        fi
        return
    fi
    echo
    echo "Skipping $1 ..."
    echo
}


echo ""
echo "**********************************************************"
echo "Binaries will be built in $BASE."
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

mkdir -p $BASE/etc/palm
mkdir -p $BASE/ls2/roles/prv
mkdir -p $BASE/ls2/roles/pub
mkdir -p $BASE/share/dbus-1/system-services
mkdir -p $BASE/share/dbus-1/services
mkdir -p $BASE/usr/lib/luna/system/luna-systemui
mkdir -p $BASE/usr/palm/public/accounts
mkdir -p $BASE/usr/palm/services
mkdir -p $BASE/usr/palm/smartkey
mkdir -p $BASE/var/luna
mkdir -p $BASE/var/palm
mkdir -p $BASE/var/usr/palm
set -x

if [ ! -d "$BASE/luna-sysmgr" ] || [ ! -d "$BASE/tarballs" ] || [ ! -e "$BASE/tarballs/luna-sysmgr_${LSM_TAG}.zip" ] ; then
    do_fetch openwebos/luna-sysmgr ${LSM_TAG} luna-sysmgr
fi
#if [ -d $BASE/luna-sysmgr ] ; then
#    rm -f $BASE/luna-sysmgr/luna-desktop-build.stamp
#fi

build cjson 35
build pbnjson 0.2
build pmloglib 21
build nyx-lib 58
build luna-service2 140
build qt4 0.33
build npapi-headers 0.4
build luna-webkit-api 0.90
build webkit 0.3
build luna-sysmgr-ipc 0.90
build luna-sysmgr-ipc-messages 0.90
build enyo 128.2
build core-apps 1.0
build luna-sysmgr $LSM_TAG
build WebKitSupplemental 0.4
build AdapterBase 0.2
build BrowserServer 0.4
build BrowserAdapter 0.3
build nodejs 0.4.12-webos2

echo ""
echo "Complete. "
echo ""
echo "Binaries are in $LUNA_STAGING/lib, $LUNA_STAGING/bin"
echo ""

