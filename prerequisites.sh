#!/bin/bash
sudo apt-get update

sudo apt-get install -y git git-core pkg-config make autoconf libtool g++ tcl unzip libyajl-dev libyajl1 qt4-qmake libsqlite3-dev curl

sudo apt-get install -y gperf bison libglib2.0-dev libssl-dev libxi-dev libxrandr-dev libxfixes-dev libxcursor-dev libfreetype6-dev libxinerama-dev libgl1-mesa-dev libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev flex libicu-dev

sudo apt-get install -y libboost-system-dev libboost-filesystem-dev libboost-regex-dev libboost-program-options-dev liburiparser-dev libc-ares-dev libsigc++-2.0-dev libglibmm-2.4-dev libdb4.8-dev libcurl4-openssl-dev

sudo apt-get install -y xcb libx11-xcb-dev libxcb-sync0-dev libxcb1-dev libxcb-keysyms1-dev libxcb-image0-dev libxcb-render-util0-dev

LSB=`lsb_release -r`
VERSION=${LSB:(-5)}

if [ "$VERSION" == "11.04" ]; then
    sudo apt-get install -y libxcb-icccm1-dev
elif [ "$VERSION" == "12.04" ]; then
    sudo apt-get install -y libxcb-icccm4-dev
fi

sudo apt-get build-dep qt4-qmake

