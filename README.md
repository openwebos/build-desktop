build-desktop
=============

The scripts in this repository are used to build, install, and run Open webOS on a Linux desktop computer.
 
This is the current active development repository for the desktop build scripts.


How to Build on Linux
=====================

Note:  The build script has been successfully tested on both Ubuntu 11.04 and 12.04 in 32bit mode.

a) Prerequisites
----------------

Install components needed to build luna-sysmgr by typing the following:

        sudo apt-get update

        sudo apt-get install git git-core pkg-config cmake make autoconf \
		libtool g++ tcl unzip libyajl-dev libyajl1 qt4-qmake \
		libsqlite3-dev curl

        sudo apt-get install gperf bison libglib2.0-dev libssl-dev \
		libxi-dev libxrandr-dev libxfixes-dev libxcursor-dev \
		libfreetype6-dev libxinerama-dev libgl1-mesa-dev \
		libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev \
		flex libicu-dev

        sudo apt-get install libboost-all-dev liburiparser-dev libc-ares-dev \
		libsigc++-2.0-dev libglibmm-2.4-dev libjemalloc-dev libdb4.8-dev

        sudo apt-get build-dep qt4-qmake

  * Ensure you have a fast and reliable internet connection since you'll be downloading about 310MB
  
  * Ensure you have at least 3GB of available disk space

  * cmake 2.8.7 is required.  For Ubuntu 11.04 it must be built/installed manually.

b) Getting the code
-------------------

Get the zip file and unzip it into a known directory.
  
c) Building luna-sysmgr
-----------------------
 
Change to the folder where you downloaded the build script and run it:


        ./build-luna-sysmgr.sh

Note: This will typically take one to three hours, depending on the speed of your system and of your internet connection.

d) Installing luna-sysmgr
-------------------------

1) Change to the folder where the files are located:

        cd ~/luna-desktop-binaries

2) Install expected folders and links into /etc/palm:

        sudo ./install-luna-sysmgr.sh

How to Run on Linux
===================

Please note that this version of the build provides minimal runtime functionality.

1) Change to the folder where the files are located:

        cd ~/luna-desktop-binaries

2) Start up the service bus:

        ./service-bus.sh  start

3) Run luna-sysmgr   (ignore the messages from LunaService):

        ./run-luna-sysmgr.sh


When you are finished running luna-sysmgr, stop the service bus:

       ./service-bus.sh  stop

# Known Issues

1) Error messages are generated in the LunaService log file, which can be ignored.
2) Since the components supporting "Just Type" have not yet been released, attempting to enter text in the "Just Type" field will not work as expected.

# Copyright and License Information

All content, including all source code files and documentation files in this repository except otherwise noted are: 

 Copyright (c) 2008-2012 Hewlett-Packard Development Company, L.P.

All content, including all source code files and documentation files in this repository except otherwise noted are:
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this content except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

