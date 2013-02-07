#!/bin/bash
# @@@LICENSE
#
#      Copyright (c) 2012 - 2013 Hewlett-Packard Development Company, L.P.
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

VERSION=8.0

PROCS=`grep -c processor /proc/cpuinfo`

usage() {
    cat <<EOF
Usage:  ./build-webos-desktop.sh [OPTION]...
Builds the version of Open webOS for the Desktop.
    The script loads about 500MB of source code from GitHub, as needed.
    NOTE: This script creates files which use about 4GB of disk space

Optional arguments:
    clean   force a rebuild of components
    -j N, --jobs=N  run N simultaneous make jobs (default: ${PROCS})
    --help  display this help and exit
    --version  display version information and exit

EOF
}

if ! ARGS=`getopt -o j: -l jobs:,help,version -n build-webos-desktop.sh -- "$@"` ; then
    exit 2
fi

eval set -- "$ARGS"

while true ; do
    case "$1" in
        -j|--jobs)
            PROCS=$2
            shift 2 ;;
        --help)
            usage
            exit ;;
        --version)
            echo "Desktop build script for Open webOS #${VERSION}"
            exit ;;
        --)
            shift
            break ;;
        *)
            break ;;
    esac
done

if [ "$1" = "clean" ] ; then
  export SKIPSTUFF=0
  set -e
  shift
elif  [ -n "$1" ] ; then
    echo "Parameter $1 not recognized"
    exit 1
else
  export SKIPSTUFF=1
  set -e
fi

export SCRIPT_DIR=$PWD

source ./webos-desktop-common.sh

if [ -d customize ] ; then
    if [ ! -e customize/locations.sh ] ; then
        cp -f locations.sh.default customize/locations.sh
    fi
    source ./customize/locations.sh
fi

mkdir -p ${BASE}/tarballs
mkdir -p ${LUNA_STAGING}
mkdir -p ${LUNA_STAGING}/usr/lib

export BEDLAM_ROOT="${BASE}/staging"
export JAVA_HOME=/usr/lib/jvm/java-6-sun
export JDKROOT=${JAVA_HOME}
# old builds put .pc files in lib/pkgconfig; cmake-modules-webos puts them in usr/share/pkgconfig
export PKG_CONFIG_PATH=$LUNA_STAGING/lib/pkgconfig:$LUNA_STAGING/usr/share/pkgconfig
export MAKEFILES_DIR=$BASE/pmmakefiles

# where's cmake? we prefer to use our own, and require the cmake-modules-webos module.
if [ -x "${BASE}/cmake/bin/cmake" ] ; then
  export CMAKE="${BASE}/cmake/bin/cmake"
else
  export CMAKE="cmake"
fi

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
    elif [ -n "${GITHUB_USER}" ]; then
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

####################################
#  Change source dir to $2 if valid, otherwise to $1
#
#  First parameter is the standard source location
#      (mandatory parameter)
#
#  Second parameter (if not empty) is the custom source location for the component.
#      This is loaded from the "customize/locations.sh" file.
#      Note: This file will be created when the build script is first run if not present
#
####################################
function set_source_dir
{
    if [ -n "$2" ] ; then
        if [ -d "$2" ] ; then
            cd $2
        else
            echo "Folder $2 invalid or doesn't exist"
            exit 1
        fi
    else
        cd $1
    fi
}

####################################
#  Fetch and unpack (or build) cmake
####################################
function build_cmake
{
    CMAKE_VER="2.8.7"
    mkdir -p $BASE/cmake
    cd $BASE/cmake
    CMAKE_MACHINE="Linux-`uname -i`"
    CMAKE_TARBALL="$BASE/tarballs/cmake-${CMAKE_VER}-${CMAKE_MACHINE}.tar.gz"
    CMAKE_SRCBALL="$BASE/tarballs/cmake-${CMAKE_VER}.tar.gz"
    if [ ! -f "${CMAKE_TARBALL}" ] && [ ! -f "${CMAKE_SRCBALL}" ] ; then
        wget http://www.cmake.org/files/v2.8/cmake-${CMAKE_VER}-${CMAKE_MACHINE}.tar.gz -O ${CMAKE_TARBALL} || true
        if [ ! -s ${CMAKE_TARBALL} ] ; then
            # no pre-built binary for this machine (e.g. amd64); force source build
            rm -f ${CMAKE_TARBALL}
        fi
    fi
    if [ -f "${CMAKE_TARBALL}" ] ; then
        # got pre-built binary (e.g. i386) so unpack it
        tar zxf ${CMAKE_TARBALL} --strip-components=1
    else
        if [ ! -f "${CMAKE_SRCBALL}" ] ; then
            wget http://www.cmake.org/files/v2.8/cmake-${CMAKE_VER}.tar.gz -O ${CMAKE_SRCBALL}
        fi
        # no pre-built binary for this machine; build from source instead
        tar zxf ${CMAKE_SRCBALL} --strip-components=1
        cd $BASE/cmake
        ./bootstrap --prefix=${BASE}/cmake
        make
        make install
    fi
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
    set_source_dir $BASE/cjson  $CJSON_DIR

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
    set_source_dir $BASE/pbnjson  $PBNJSON_DIR

    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install

    # remove lib files from old location
    cd ${LUNA_STAGING}
    rm -f lib/libpbnjson*.so
    # remove header files from old location
    cd include
    rm -rf pbnjson
    rm -f pbnjson*.h*
}

###########################
#  Fetch and build pmloglib
###########################
function build_pmloglib
{
    do_fetch openwebos/pmloglib $1 pmloglib submissions/
    set_source_dir $BASE/pmloglib  $PMLOGLIB_DIR

    mkdir -p build
    cd build
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

    set_source_dir $BASE/nyx-lib $NYX_LIB_DIR

    mkdir -p build
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
    do_fetch openwebos/qt $1 qt4 submissions/
    export STAGING_DIR=${LUNA_STAGING}
    if [ ! -f $BASE/qt-build-desktop/Makefile ] || [ ! -e $BASE/qt4/luna-desktop-build-$1.stamp ] ; then
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
    if [ ! -x ${LUNA_STAGING}/bin/moc ]; then
        cd ${LUNA_STAGING}/bin
        ln -sf moc-palm moc
    fi
}

####################################
#  Fetch and checkout a qt module
####################################
function fetch_qt5_module
{
    cd $BASE
    if [ ! -e ${BASE}/${1} ] ; then
        echo "Cloning ${1} from gitorious"
        git clone git://qt.gitorious.org/qt/${1}
    fi
    cd $BASE/${1}
    if [ -n "$2" ] ; then
        git fetch
        echo "Checking ${2} of ${1}"
        git checkout ${2}
    else
        echo "Using top of 'stable' branch from ${1}"
    fi

    if [ -e ${SCRIPT_BASE_DIR}/${1} ] ; then
        echo "Patching qtmodule ${1} ..."
        for file in ${SCRIPT_BASE_DIR}/${1}/*
        do
            echo "-- Applying patch ${file}"
            git am ${file}
        done
    fi
    cd $BASE
}

####################################
#  Fetch and build a qt module
####################################
function build_qt5_module
{
    QT_MODULE_STAMP="$BASE/$1/qt-module-build-$2.stamp"
    if [ ! -e ${QT_MODULE_STAMP} ] ; then
        fetch_qt5_module $1 $2
        echo "Building ${1}"
        cd $BASE/${1}
        if [ "$1" == "qtbase" ] ; then
            # The qtbase needs special attention as it is the core
            if [ -e Makefile ] ; then
                make $JOBS confclean
            fi
            ./configure -v -prefix ${LUNA_STAGING} -release -opengl \
                        -nomake docs -nomake examples -nomake demos -nomake tests \
                        -no-cups -no-javascript-jit -no-gtkstyle -no-neon -opensource -confirm-license
            export QMAKE=${LUNA_STAGING}/bin/qmake
        else
            # The other modules will just be qmake'd
            if [ -e Makefile ] ; then
                make $JOBS distclean
            fi
            $QMAKE
        fi
        make $JOBS
        make $JOBS install
        rm -f $BASE/$1/qt-module-build-*.stamp
        touch $BASE/$1/qt-module-build-$2.stamp
    elif [ "$1" == "qtbase" ] ; then
        export QMAKE=${LUNA_STAGING}/bin/qmake
        echo "Qt module ${1} already built -> setting up qmake $QMAKE"
    else
        echo "Qt module ${1} already built -> skipping"
    fi
}

function build_qt5
{
    ##############################
    ## Build dependencies are according to Digia
    ##  http://qt.gitorious.org/qt/qt5/blobs/14b6752894a4760929852d8969d70324d5d19812/build.dependencies
    ##############################

    ## Build dependencies: "qtbase" => "",
    build_qt5_module qtbase 4eac2c4728da85a5cdf91ec25170b3417f7deb68

    ## Build dependencies: "qtjsbackend" => "qtbase",
    build_qt5_module qtjsbackend b41c2151fdfca3f63a6cd45f6c69ae678694b63e

    ## Build dependencies: "qtxmlpatterns" => "qtbase
    build_qt5_module qtxmlpatterns d42b8e30e8ac2a33a877d37bd0ffbf616580d7fc

    ## Build dependencies: "qtscript" => "qtbase",
    build_qt5_module qtscript e27e5bade2407e022f1814eaaf6cea8bb6741465

    ## Build dependencies: "qtquick1" => "qtbase,qtscript,qtxmlpatterns,...
    build_qt5_module qtquick1 a1ebb0367d8dd02ead0abe4ab9a82c379428666d

    ## Build dependencies: "qtdeclarative" => "qtbase,qtxmlpatterns,qtjsbackend,...
    build_qt5_module qtdeclarative 5e4cc79e0669b76f8f5bf5192a0b7001ff8f4d58

    ## Build dependencies: "qtsensors" => "qtbase,qtdeclarative",
    build_qt5_module qtsensors 6323be3e2fc1b69145f37cda1d0214ec5fa3cb44

    ## Build dependencies: "qt3d" => "qtbase,qtdeclarative",
    build_qt5_module qt3d d723769d90331f4cde8dcb5aa3973e5c6bad8753

    ## Build dependencies: "qtlocation" => "qtbase,qtdeclarative,qt3d,...
    build_qt5_module qtlocation 0ad2be463848898235abd8ebeebc076042cf398f

    ## Build dependencies: "qtwebkit" => "qtbase,qtscript,qtdeclarative,qtquick1,qtlocation",
    build_qt5_module qtwebkit 1ced62033ffe82134c2f5707b6ef197fa3e85375

    ## Build dependencies: "qtwebkit-examples-and-demos" => "qtwebkit",

    ## Build dependencies: "qtwayland" => "qtbase,qtdeclarative"

}

################################
#  Fetch and build luna-service2
################################
function build_luna-service2
{
    do_fetch openwebos/luna-service2 $1 luna-service2 submissions/

    set_source_dir $BASE/luna-service2 $LUNA_SERVICE2_DIR

    mkdir -p build
    cd build

    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install

    # TODO: Fix for luna-sysmgr, which doesn't know about staging/usr/include/luna-service2
    cp -f ${LUNA_STAGING}/usr/include/luna-service2/lunaservice.h ${LUNA_STAGING}/include/
    mkdir -p ${LUNA_STAGING}/include/luna-service2/
    cp -f ${LUNA_STAGING}/usr/include/luna-service2/lunaservice-errors.h ${LUNA_STAGING}/include/luna-service2/
    # TODO: Fix for activitymanager which includes MojLunaService.h which can't find lunaservice.h
    cp -f ${LUNA_STAGING}/usr/include/luna-service2/lunaservice.h ${LUNA_STAGING}/usr/include/
    # TODO: Fix for webkit tests which don't look in /usr/lib for luna-service library.
    # (Figure out if we can pass -rpath into build for libQtWebKit.so to fix WebKit/qt/tests link.)
    cd ${LUNA_STAGING}/lib
    ln -sf ../usr/lib/libluna-service2.so libluna-service2.so
    ln -sf ../usr/lib/libluna-service2.so libluna-service2.so.3
    # TODO: This is for keyboard-efigs which links against lunaservice instead of luna-service2
    ln -sf ../usr/lib/libluna-service2.so liblunaservice.so
}

################################
#  Fetch and build npapi-headers
################################
function build_npapi-headers
{
    do_fetch isis-project/npapi-headers $1 npapi-headers

    set_source_dir $BASE/npapi-headers  $NPAPI_HEADERS_DIR

    mkdir -p $LUNA_STAGING/include/webkit/npapi
    cp -f *.h $LUNA_STAGING/include/webkit/npapi
}

################################
#  Fetch and build isis-fonts
################################
function build_isis-fonts
{
    do_fetch isis-project/isis-fonts $1 isis-fonts

    set_source_dir $BASE/isis-fonts  $ISIS_FONTS_DIR

    mkdir -p $ROOTFS/usr/share/fonts
    cp -f *.xml $ROOTFS/usr/share/fonts
    cp -f *.ttf $ROOTFS/usr/share/fonts
}

##################################
#  Fetch and build luna-webkit-api
##################################
function build_luna-webkit-api
{
    do_fetch openwebos/luna-webkit-api $1 luna-webkit-api submissions/

    set_source_dir $BASE/luna-webkit-api  $LUNA_WEBKIT_API_DIR

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

    # TODO: Can we pass -rpath linker flags to webkit build (for staging/usr/lib)?
    # If not, then we might want/need to prevent webkit from building Source/WebKit/qt/tests, e.g.:
    # sed -i '/SOURCES.*$/a LIBS += -Wl,-rpath $$(LUNA_STAGING)/usr/lib -L$$(LUNA_STAGING)/usr/lib' Source/WebKit/qt/tests.pri
    # In the mean time, we can add symlinks to end of luna-service2 build to put libs in staging/lib.

    # gcc 4.5.2 fails to compile WebCore module with "internal compiler error" when using -O2 or better
    GCC_VERSION=$(gcc -v 2>&1 | tail -1 | awk '{print $3}')
    if [ "$GCC_VERSION" == "4.5.2" ] ; then
        sed -i 's/enable_fast_mobile_scrolling: DEFINES += ENABLE_FAST_MOBILE_SCROLLING=1/enable_fast_mobile_scrolling: DEFINES += ENABLE_FAST_MOBILE_SCROLLING=1\nQMAKE_CXXFLAGS_RELEASE-=-O2\nQMAKE_CXXFLAGS_RELEASE+=-O0\n/' Source/WebCore/WebCore.pri
    fi

    export QTDIR=$BASE/qt4
    export QMAKEPATH=$WEBKIT_DIR/Tools/qmake
    export WEBKITOUTPUTDIR="WebKitBuild/isis-x86"

    ./Tools/Scripts/build-webkit --qt \
        --release \
        --no-video \
        --fullscreen-api \
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
    do_fetch openwebos/luna-sysmgr-ipc $1 luna-sysmgr-ipc submissions/

    set_source_dir $BASE/luna-sysmgr-ipc  $LUNA_SYSMGR_IPC_DIR

    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install

    ## support components which don't use pkgconfig
    mkdir -p $LUNA_STAGING/include/sysmgr-ipc
    cp -f $LUNA_STAGING/usr/include/sysmgr-ipc/*.h $LUNA_STAGING/include/sysmgr-ipc/
}

###########################################
#  Fetch and build luna-sysmgr-ipc-messages
###########################################
function build_luna-sysmgr-ipc-messages
{
    do_fetch openwebos/luna-sysmgr-ipc-messages $1 luna-sysmgr-ipc-messages submissions/

    set_source_dir $BASE/luna-sysmgr-ipc-messages  $LUNA_SYSMGR_IPC_MESSAGES_DIR

    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install

    ## support components which don't use pkgconfig
    mkdir -p $LUNA_STAGING/include/sysmgr-ipc
    cp -f $LUNA_STAGING/usr/include/sysmgr-ipc/*.h $LUNA_STAGING/include/sysmgr-ipc/
}

#################################
# Fetch and build luna-prefs
#################################
function build_luna-prefs
{
    do_fetch openwebos/luna-prefs $1 luna-prefs submissions/

    set_source_dir $BASE/luna-prefs $LUNA_PREFS_DIR

    mkdir -p $BASE/luna-prefs/build
    cd $BASE/luna-prefs/build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install

}

#################################
# Fetch and build luna-init
#################################
function build_luna-init
{
    do_fetch openwebos/luna-init $1 luna-init submissions/

    set_source_dir $BASE/luna-init $LUNA_INIT_DIR

    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..

    make $JOBS
    make install
    cp -f ../files/conf/*.json $ROOTFS/usr/palm/

    if [ -e ../files/conf/fonts/fonts.tgz ]; then
        mkdir -p $ROOTFS/usr/share/fonts
        tar xvzf ../files/conf/fonts/fonts.tgz --directory=${ROOTFS}/usr/share/fonts
        cp -f ../files/conf/fonts/*.xml $ROOTFS/usr/share/fonts/
    fi
}

#################################
# Fetch and build luna-sysservice
#################################
function build_luna-sysservice
{
    do_fetch openwebos/luna-sysservice $1 luna-sysservice submissions/

    set_source_dir $BASE/luna-sysservice  $LUNA_SYSSERVICE_DIR

    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} ..
    make $JOBS
    make install

    # NOTE: Make binary findable in /usr/lib/luna so ls2 can match the role file
    cp -f LunaSysService $ROOTFS/usr/lib/luna/

    # TODO: cmake should do this for us (once we have configurable-for-desktop files)
    cp -rf ../files/conf/* ${ROOTFS}/etc/palm
    cp -f ../desktop-support/com.palm.systemservice.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.systemservice.json
    cp -f ../desktop-support/com.palm.systemservice.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.systemservice.json
    cp -f ../desktop-support/com.palm.systemservice.service.pub $ROOTFS/usr/share/ls2/services/com.palm.systemservice.service
    cp -f ../desktop-support/com.palm.systemservice.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.systemservice.service
    mkdir -p $ROOTFS/etc/palm/backup
    cp -f ../desktop-support/com.palm.systemservice.backupRegistration.json $ROOTFS/etc/palm/backup/com.palm.systemservice
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
    do_fetch openwebos/core-apps $1 core-apps submissions/

    set_source_dir $BASE/core-apps  $CORE_APPS_DIR

    mkdir -p $ROOTFS/usr/palm/applications
    for APP in com.palm.app.* ; do
      cp -rf ${APP} $ROOTFS/usr/palm/applications/
      cp -rf ${APP}/configuration/db/kinds/* $ROOTFS/etc/palm/db/kinds/ 2>/dev/null || true
      cp -rf ${APP}/configuration/db/permissions/* $ROOTFS/etc/palm/db/permissions/ 2>/dev/null || true
      cp -rf ${APP}/configuration/activities/* $ROOTFS/etc/palm/activities/ 2>/dev/null || true
    done
}

###########################################
#  Fetch and build luna-applauncher
###########################################
function build_luna-applauncher
{
    do_fetch openwebos/luna-applauncher $1 luna-applauncher submissions/

    set_source_dir $BASE/luna-applauncher  $LUNA_APPLAUNCHER_DIR

    mkdir -p $ROOTFS/usr/lib/luna/system/luna-applauncher
    cp -rf . $ROOTFS/usr/lib/luna/system/luna-applauncher
}

###########################################
#  Fetch and build luna-systemui
###########################################
function build_luna-systemui
{
    do_fetch openwebos/luna-systemui $1 luna-systemui submissions/

    set_source_dir $BASE/luna-systemui $LUNA_SYSTEMUI_DIR

    mkdir -p $ROOTFS/usr/lib/luna/system/luna-systemui
    cp -rf . $ROOTFS/usr/lib/luna/system/luna-systemui
    if [ -e images/wallpaper.tar ]; then
        mkdir -p $ROOTFS/usr/lib/luna/system/luna-systemui/images
        tar xf images/wallpaper.tar --directory=${ROOTFS}/usr/lib/luna/system/luna-systemui/images
    fi
}

###########################################
#  Fetch and build foundation-frameworks
###########################################
function build_foundation-frameworks
{
    do_fetch openwebos/foundation-frameworks $1 foundation-frameworks

    set_source_dir $BASE/foundation-frameworks  $FOUNDATION_FRAMEWORKS_DIR

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

    set_source_dir $BASE/mojoservice-frameworks $MOJOSERVICE_FRAMEWORKS_DIR

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

    set_source_dir $BASE/loadable-frameworks  $LOADABLE_FRAMEWORKS_DIR

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
    do_fetch openwebos/mojoloader $1 mojoloader submissions/
    mkdir -p $ROOTFS/usr/palm/frameworks/
    cp -rf $BASE/mojoloader/mojoloader.js $ROOTFS/usr/palm/frameworks/
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
#  Fetch and build mojolocation-stub
###########################################
function build_mojolocation-stub
{
    do_fetch openwebos/mojolocation-stub $1 mojolocation-stub submissions/

    set_source_dir $BASE/mojolocation-stub  $MOJOLOCATION_DIR

    mkdir -p $ROOTFS/usr/palm/services/com.palm.location
    cp -rf *.json *.js $ROOTFS/usr/palm/services/com.palm.location
    cp -rf files/sysbus/*.json $ROOTFS/usr/share/ls2/roles/prv
    cp -rf files/sysbus/*.json $ROOTFS/usr/share/ls2/roles/pub
    #NOTE: services go in $ROOTFS/usr/share/ls2/system-services, which is linked from /usr/share/ls2/system-services
    cp -rf desktop-support/*.service $ROOTFS/usr/share/ls2/system-services
    cp -rf desktop-support/*.service $ROOTFS/usr/share/ls2/services
}

###########################################
#  Fetch and build pmnetconfigmanager-stub
###########################################
function build_pmnetconfigmanager-stub
{
    do_fetch openwebos/pmnetconfigmanager-stub $1 pmnetconfigmanager-stub submissions/

    set_source_dir $BASE/pmnetconfigmanager-stub  $PMNETCONFIGMANAGER_DIR

    mkdir -p $ROOTFS/usr/palm/services/com.palm.connectionmanager
    cp -rf *.json *.js $ROOTFS/usr/palm/services/com.palm.connectionmanager
    cp -rf files/sysbus/*.json $ROOTFS/usr/share/ls2/roles/prv
    cp -rf files/sysbus/*.json $ROOTFS/usr/share/ls2/roles/pub
    #NOTE: services go in $ROOTFS/usr/share/ls2/system-services, which is linked from /usr/share/ls2/system-services
    cp -rf desktop-support/*.service $ROOTFS/usr/share/ls2/system-services
    cp -rf desktop-support/*.service $ROOTFS/usr/share/ls2/services
}

###########################################
#  Fetch and build app-services
###########################################
function build_app-services
{
    do_fetch openwebos/app-services $1 app-services

    set_source_dir $BASE/app-services $APP_SERVICES_DIR

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
    do_fetch openwebos/mojomail $1 mojomail submissions/

    set_source_dir $BASE/mojomail  $MOJOMAIL_DIR

    for SUBDIR in common imap pop smtp ; do
      mkdir -p $BASE/mojomail/$SUBDIR/build
      cd $BASE/mojomail/$SUBDIR/build
      sed -i 's!DESTINATION /!DESTINATION !' ../CMakeLists.txt
      $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
      #make $JOBS VERBOSE=1
      make $JOBS
      make install
      mkdir -p $ROOTFS/usr/palm/public/accounts
      cp -rf ../files/usr/palm/public/accounts/* $ROOTFS/usr/palm/public/accounts/ 2>/dev/null || true
      cp -rf ../files/db8/kinds/* $ROOTFS/etc/palm/db/kinds 2> /dev/null || true
      cd ../..
    done

    # TODO: (cmake should do this) install filecache types
    mkdir -p $ROOTFS/etc/palm/filecache_types
    cp -rf common/files/filecache_types/* $ROOTFS/etc/palm/filecache_types

    # NOTE: Make binaries findable in /usr/lib/luna so ls2 can match the role file
    cp -f imap/build/mojomail-imap "${ROOTFS}/usr/lib/luna/"
    cp -f pop/build/mojomail-pop "${ROOTFS}/usr/lib/luna/"
    cp -f smtp/build/mojomail-smtp "${ROOTFS}/usr/lib/luna/"
    cp -f desktop-support/com.palm.imap.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.imap.json
    cp -f desktop-support/com.palm.pop.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.pop.json
    cp -f desktop-support/com.palm.smtp.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.smtp.json
    cp -f desktop-support/com.palm.imap.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.imap.service
    cp -f desktop-support/com.palm.pop.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.pop.service
    cp -f desktop-support/com.palm.smtp.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.smtp.service
}

##############################
#  Fetch and build luna-sysmgr-common
##############################
function build_luna-sysmgr-common
{
    do_fetch openwebos/luna-sysmgr-common $1 luna-sysmgr-common submissions/

    set_source_dir $BASE/luna-sysmgr-common  $LUNA_SYSMGR_COMMON_DIR

    if [ ! -e "luna-desktop-build-${1}.stamp" ] ; then
        if [ $SKIPSTUFF -eq 0 ] && [ -e debug-x86 ] && [ -e debug-x86/.obj ] ; then
            rm -f debug-x86/libLunaSysMgrCommon.so
            rm -rf debug-x86/.obj/*
            rm -rf debug-x86/.moc/moc_*.cpp
            rm -rf debug-x86/.moc/*.moc
        fi
        export STAGING_LIBDIR="${LUNA_STAGING}/lib"
        ${QMAKE}
        make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu install BUILD_TYPE=debug
        mkdir -p $LUNA_STAGING/include/luna-sysmgr-common
        cp include/* $LUNA_STAGING/include/luna-sysmgr-common/
    fi
}



##############################
#  Fetch and build webappmanager
##############################
function build_webappmanager
{
    do_fetch openwebos/webappmanager $1 webappmanager submissions/

    set_source_dir $BASE/webappmanager $WEBAPPMANAGER_DIR

    if [ ! -e "luna-desktop-build-${1}.stamp" ] ; then
        if [ $SKIPSTUFF -eq 0 ] && [ -e debug-x86 ] && [ -e debug-x86/.obj ] ; then
            rm -f debug-x86/WebAppMgr
            rm -rf debug-x86/.obj/*
            rm -rf debug-x86/.moc/moc_*.cpp
            rm -rf debug-x86/.moc/*.moc
        fi
        $QMAKE
    fi
    make $JOBS -f Makefile.Ubuntu
    mkdir -p $ROOTFS/usr/lib/luna
    cp -f debug-x86/WebAppMgr $ROOTFS/usr/lib/luna/WebAppMgr

    cp -f desktop-support/com.palm.webappmgr.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.webappmgr.json
    cp -f desktop-support/com.palm.webappmgr.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.webappmgr.json
    cp -f desktop-support/com.palm.webappmgr.service.prv $ROOTFS/usr/share/ls2/system-services/com.palm.webappmgr.service
    cp -f desktop-support/com.palm.webappmgr.service.pub $ROOTFS/usr/share/ls2/services/com.palm.webappmgr.service
}

##############################
#  Fetch and build luna-sysmgr
##############################
function build_luna-sysmgr
{
    if [ ! -d $BASE/luna-sysmgr ]  || [ ! -e "$BASE/tarballs/luna-sysmgr_${1}.zip" ] ; then
        do_fetch openwebos/luna-sysmgr $1 luna-sysmgr submissions/
    fi

    set_source_dir $BASE/luna-sysmgr  $LUNA_SYSMGR_DIR

    if [ ! -e "luna-desktop-build-${1}.stamp" ] ; then
        if [ $SKIPSTUFF -eq 0 ] && [ -e debug-x86 ] && [ -e debug-x86/.obj ] ; then
            rm -f debug-x86/LunaSysMgr
            rm -rf debug-x86/.obj/*
            rm -rf debug-x86/.moc/moc_*.cpp
            rm -rf debug-x86/.moc/*.moc
        fi
        $QMAKE
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


##############################
#  Fetch and build keyboard-efigs
##############################
function build_keyboard-efigs
{
    do_fetch openwebos/keyboard-efigs $1 keyboard-efigs submissions/

    set_source_dir $BASE/keyboard-efigs  $KEYBOARD_EFIGS_DIR

    $QMAKE
    make $JOBS -f Makefile.Ubuntu
    make install -f Makefile.Ubuntu
}

#####################################
#  Fetch and build WebKitSupplemental
#####################################
function build_WebKitSupplemental
{
    do_fetch isis-project/WebKitSupplemental $1 WebKitSupplemental

    set_source_dir $BASE/WebKitSupplemental  $WEBKITSUPPLEMENTAL_DIR

    export QTDIR=$BASE/qt-build-desktop
    export QMAKEPATH=$WEBKIT_DIR/Tools/qmake
    export QT_INSTALL_PREFIX=$LUNA_STAGING
    export STAGING_DIR=${LUNA_STAGING}
    export STAGING_INCDIR="${LUNA_STAGING}/include"
    export STAGING_LIBDIR="${LUNA_STAGING}/lib"
    $QMAKE
    make $JOBS -f Makefile
    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile install BUILD_TYPE=release
}

################################
#  Fetch and build AdapterBase
################################
function build_AdapterBase
{
    do_fetch isis-project/AdapterBase $1 AdapterBase

    set_source_dir $BASE/AdapterBase  $ADAPTERBASE_DIR

    export QMAKEPATH=$WEBKIT_DIR/Tools/qmake
    $QMAKE
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

    set_source_dir $BASE/isis-browser  $ISIS_BROWSER_DIR

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
}

#################################
#  Fetch and build BrowserAdapter
#################################
function build_BrowserAdapter
{
    do_fetch isis-project/BrowserAdapter $1 BrowserAdapter

    set_source_dir $BASE/BrowserAdapter  $BROWSERADAPTER_DIR

    export QT_INSTALL_PREFIX=$LUNA_STAGING
    export STAGING_DIR=${LUNA_STAGING}
    export STAGING_INCDIR="${LUNA_STAGING}/include"
    export STAGING_LIBDIR="${LUNA_STAGING}/lib"

    # BrowserAdapter generates a few warnings which will kill the build if we don't turn off -Werror
    sed -i 's/-Werror//' Makefile.inc

    # Set TARGET_DESKTOP in CFLAGS, rather than ISIS_DESKTOP
    # This is needed for the Browser app to run in the Open WebOS desktop build
    sed -i 's/ISIS_DESKTOP/TARGET_DESKTOP/' Makefile.Ubuntu

    make $JOBS -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu all BUILD_TYPE=release

    # stage files
    make -e PREFIX=$LUNA_STAGING -f Makefile.Ubuntu stage BUILD_TYPE=release

    # install plugin
    mkdir -p ${ROOTFS}/usr/lib/BrowserPlugins
    cp -f ${LUNA_STAGING}/lib/BrowserPlugins/BrowserAdapter.so "${ROOTFS}/usr/lib/BrowserPlugins/"

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

    set_source_dir $BASE/nodejs $NODEJS_DIR

    mkdir -p build
    cd build
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

#########################
# Fetch and build LevelDB
#########################
function build_leveldb
{
    LIB_VER=$1
    LIB_REL=$2
    LIB_NAME="leveldb"

    mkdir -p $BASE/$LIB_NAME
    cd $BASE/${LIB_NAME}
    LIB_TARBALL="$BASE/tarballs/${LIB_NAME}-${LIB_VER}.${LIB_REL}.tar.gz"

    [ ! -f "${LIB_TARBALL}" ] && {
        wget http://${LIB_NAME}.googlecode.com/files/${LIB_NAME}-${LIB_VER}.${LIB_REL}.tar.gz -O ${LIB_TARBALL} || {
            echo "Unable to download leveldb"
            exit 1
        }
    }

    tar -xzf ${LIB_TARBALL}
    cd ${LIB_NAME}-${LIB_VER}.${LIB_REL}
    make $JOBS

    cp -rf include/${LIB_NAME} ${LUNA_STAGING}/include

    cp -f lib${LIB_NAME}.a ${LUNA_STAGING}/lib
    cp -f lib${LIB_NAME}.so.${LIB_VER} ${LUNA_STAGING}/lib
    ln -sf ${LUNA_STAGING}/lib/lib${LIB_NAME}.so.${LIB_VER} ${LUNA_STAGING}/lib/lib${LIB_NAME}.so
    ln -sf ${LUNA_STAGING}/lib/lib${LIB_NAME}.so.${LIB_VER} ${LUNA_STAGING}/lib/lib${LIB_NAME}.so.1
}

#####################
# Fetch and build db8
#####################
function build_db8
{
    do_fetch openwebos/db8 $1 db8 submissions/

    set_source_dir $BASE/db8 $DB8_DIR

    mkdir -p build
    cd build

    # db8 needs luna-service2, which needs cjson, and we need -rpath-link to locate that properly
    export LDFLAGS="-Wl,-rpath-link $LUNA_STAGING/lib"

    $CMAKE .. -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install

    # The (cmake) "make install" (above) installs headers/libs (and everything else) into LUNA_STAGING.
    # Here, we install the executable and (desktop) ls2 files into $ROOTFS:
    set_source_dir $BASE/db8 $DB8_DIR
    cp -f build/mojodb-luna "${ROOTFS}/usr/lib/luna/"
    cp -f desktop-support/com.palm.db.json.pub $ROOTFS/usr/share/ls2/roles/pub/com.palm.db.json
    cp -f desktop-support/com.palm.db.json.prv $ROOTFS/usr/share/ls2/roles/prv/com.palm.db.json
    cp -f desktop-support/com.palm.db.service $ROOTFS/usr/share/ls2/services/com.palm.db.service
    cp -f desktop-support/com.palm.db.service $ROOTFS/usr/share/ls2/system-services/com.palm.db.service
    cp -f desktop-support/com.palm.tempdb.service $ROOTFS/usr/share/ls2/system-services/com.palm.tempdb.service
    cp -f src/db-luna/mojodb.conf $ROOTFS/etc/palm/mojodb.conf

    # copy lib and include files to from old location
    rm -f ${LUNA_STAGING}/lib/libmojo*.so
    ln -sf ${LUNA_STAGING}/usr/lib/libmojodb.so ${LUNA_STAGING}/lib/libmojodb.so
    ln -sf ${LUNA_STAGING}/usr/lib/libmojocore.so ${LUNA_STAGING}/lib/libmojocore.so
    ln -sf ${LUNA_STAGING}/usr/lib/libmojoluna.so ${LUNA_STAGING}/lib/libmojoluna.so
    cp -fr ${LUNA_STAGING}/usr/include/mojodb ${LUNA_STAGING}/include
}

##############################
# Fetch and build configurator
##############################
function build_configurator
{
    do_fetch openwebos/configurator $1 configurator submissions/

    set_source_dir $BASE/configurator  $CONFIGURATOR_DIR

    mkdir -p build
    cd build
    export LDFLAGS="-Wl,-rpath-link $LUNA_STAGING/lib"
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

    set_source_dir $BASE/activitymanager $ACTIVITYMANAGER_DIR

    mkdir -p build
    cd build
    export LDFLAGS="-Wl,-rpath-link $LUNA_STAGING/lib"
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

    set_source_dir $BASE/pmstatemachineengine  $PMSTATEMACHINEENGINE_DIR

    mkdir -p build
    cd build
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

    set_source_dir $BASE/libpalmsocket  $LIBPALMSOCKET_DIR

    mkdir -p build
    cd build
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

    set_source_dir $BASE/librolegen  $LIBROLEGEN_DIR

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
    do_fetch openwebos/serviceinstaller $1 serviceinstaller submissions/

    set_source_dir $BASE/serviceinstaller  $SERVICEINSTALLER_DIR

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
    do_fetch openwebos/luna-universalsearchmgr $1 luna-universalsearchmgr submissions/

    set_source_dir $BASE/luna-universalsearchmgr  $LUNA_UNIVERSALSEARCHMGR_DIR

    mkdir -p build
    cd build
    $CMAKE -D WEBOS_INSTALL_ROOT:PATH=${LUNA_STAGING} -DCMAKE_INSTALL_PREFIX=${LUNA_STAGING} ..
    make $JOBS
    make install
    # NOTE: Make binary findable in /usr/lib/luna so luna-universalsearchmgr can match the role file
    cp -f $LUNA_STAGING/usr/sbin/LunaUniversalSearchMgr $ROOTFS/usr/lib/luna/LunaUniversalSearchMgr
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

    set_source_dir $BASE/filecache  $FILECACHE_DIR

    mkdir -p build
    cd build
    export LDFLAGS="-Wl,-rpath-link $LUNA_STAGING/lib"
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

pre_build

export LSM_TAG="9"
if [ ! -d "$BASE/luna-sysmgr" ] || [ ! -d "$BASE/tarballs" ] || [ ! -e "$BASE/tarballs/luna-sysmgr_${LSM_TAG}.zip" ] ; then
    do_fetch openwebos/luna-sysmgr ${LSM_TAG} luna-sysmgr submissions/
fi
if [ -d $BASE/luna-sysmgr ] ; then
    rm -f $BASE/luna-sysmgr/luna-desktop-build*.stamp
fi

## TODO: Remove this temporary fix once pbnjson incremented past 7
if [ -d "$BASE/pbnjson" ] && [ -e "$BASE/pbnjson/luna-desktop-build-7.stamp" ] ; then
    rm -f $BASE/pbnjson/luna-desktop-build-7.stamp
fi

# Build a local version of cmake 2.8.7 so that cmake-modules-webos doesn't have to write to the OS-supplied CMake modules directory
build cmake
build cmake-modules-webos 12

build cjson 35
build pbnjson 7
build pmloglib 21
build nyx-lib 58
build luna-service2 147
#build qt4 4
build_qt5
build npapi-headers 0.4
build luna-webkit-api 1.01
#build webkit 0.54

build luna-sysmgr-ipc 2
build luna-sysmgr-ipc-messages 2
build luna-sysmgr-common 4
build luna-sysmgr $LSM_TAG
build keyboard-efigs 1.02

build webappmanager 4
build luna-init 1.03
build luna-prefs 1.01
build luna-sysservice 3
build librolegen 16
##build serviceinstaller 1.01
build luna-universalsearchmgr 1.00

build luna-applauncher 1.00
build luna-systemui 1.02

build enyo-1.0 128.2
build core-apps 2
#build isis-browser 0.21
build isis-fonts v0.1

build foundation-frameworks 1.0
build mojoservice-frameworks 1.0
build loadable-frameworks 1.0.1
build app-services 1.02
build mojolocation-stub 2
build pmnetconfigmanager-stub 3

build underscore 8
build mojoloader 8
build mojoservicelauncher 71

#build WebKitSupplemental 0.4
#build AdapterBase 0.2
## BrowserServer 0.7.1 includes (only) desktop-specific changes to build with libpbnjson 7
#build BrowserServer 0.7.1
## BrowserAdapter 0.4.1 includes (only) desktop-specific changes to build with libpbnjson 7
#build BrowserAdapter 0.4.1

build nodejs 34
build node-addon sysbus 25
build node-addon pmlog 10
build node-addon dynaload 11

build leveldb 1.9 0
build db8 63
build configurator 49

build activitymanager 110
build pmstatemachineengine 13
build libpalmsocket 30
build libsandbox 15
build jemalloc 11
build filecache 55

#NOTE: mojomail depends on libsandbox, libpalmsocket, and pmstatemachine;
build mojomail 99

post_build

echo ""
echo "Complete. "
touch $BASE/build_version_$VERSION
echo ""
echo "Binaries are in $LUNA_STAGING/lib, $LUNA_STAGING/bin"
echo ""

