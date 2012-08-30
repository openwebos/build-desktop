build-desktop
=============

The scripts in this repository are used to build, install, and run Open webOS on a Linux desktop computer.
 
This is the current active development repository for the desktop build scripts for Open webOS.


How to Build on Linux
=====================

Note:  The build script has been successfully tested on both Ubuntu 11.04 and 12.04 in 32-bit mode, using a full _Desktop_ installation (_not_ Server).

Note:  Ubuntu Server (or other non-desktop) installations are not currently working.

Note:  Builds on 64-bit machines are not currently supported (or working).

a) Prerequisites
----------------

  * Ensure you have a fast and reliable internet connection since you'll be downloading about 500MB

  * Ensure you have at least 4GB of available disk space

  * Install the following components needed to build (and run) Open webOS on the desktop by typing the following:

        sudo apt-get update

        sudo apt-get install git git-core pkg-config make autoconf \
		libtool g++ tcl unzip libyajl-dev libyajl1 qt4-qmake \
		libsqlite3-dev curl

        sudo apt-get install gperf bison libglib2.0-dev libssl-dev \
		libxi-dev libxrandr-dev libxfixes-dev libxcursor-dev \
		libfreetype6-dev libxinerama-dev libgl1-mesa-dev \
		libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev \
		flex libicu-dev

        sudo apt-get install libboost-system-dev libboost-filesystem-dev \
		libboost-regex-dev libboost-program-options-dev liburiparser-dev \
		libc-ares-dev libsigc++-2.0-dev libglibmm-2.4-dev libdb4.8-dev \
		libcurl4-openssl-dev

        sudo apt-get build-dep qt4-qmake

  * cmake version 2.8.7 will be fetched and used for the build; there is no need to install it.


b) Getting the code
-------------------

Get the build-desktop zip file and unzip it into a known directory or better yet, "git clone" the repository.
  
c) Building Open webOS
----------------------
 
Change to the folder where you downloaded the build-desktop scripts and run the build script:

        ./build-webos-desktop.sh

Note: This will typically take one to three hours, depending on the speed of your system and of your internet connection. The build will go much faster on a multi-core machine.

d) Installing Open webOS
------------------------

Change to the folder where the build-desktop scripts are located (if necessary) and run the "install" script to create expected folders and symlinks into various system directories:

        sudo ./install-webos-desktop.sh

In general, you should only have to run the install script once (unless you update to a newer version).

You can run "sudo ./install-webos-desktop.sh remove" to remove the system folders and symlinks.

How to Run on Linux
===================

Please note that this version of the build provides minimal runtime functionality.

1) Change to the folder where the build-desktop scripts are located (if necessary).

2) Start up the service bus:

        ./service-bus.sh start  

    The message __hub daemons started__ indicates success.  You can safely ignore error messages.  

3) Start up the native webOS services on the service bus:

        ./service-bus.sh services  

    The message __Services started!__ indicates success.  You can safely ignore error messages.  

4) The first time you start, you'll need to create a default account: 

        ./service-bus.sh init

5) Run luna-sysmgr  (ideally from a separate terminal shell window to keep the luna-sysmgr output separate from the service-bus logging)

        ./run-luna-sysmgr.sh

    You can safely ignore the messages from LunaService.

6) When you are finished running luna-sysmgr, stop the service bus:

       ./service-bus.sh stop

# Known Issues

  * Error messages are generated in the LunaService log output, which can be ignored.
  * Since the components supporting "Just Type" have not yet been released, attempting to enter text in the "Just Type" field will not work as expected.
  * The email application may not work properly.

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

