build-desktop
=============

The scripts in this repository are used to build, install, and run Open webOS on an Ubuntu Linux desktop computer.

Supported platforms
====================

* Ubuntu Desktop 11.04 32-bit
* Ubuntu Desktop 12.04 32-bit and 64-bit

Note:  Builds on Ubuntu Server (or other non-desktop) installations are not currently supported (or working).

How to Build on Ubuntu Linux
============================

Prerequisites
-------------
  * Ensure you have a fast and reliable internet connection since you'll be downloading about 500MB
  * Ensure you have at least 4GB of available disk space
  * Install dependencies needed to build (and run) Open webOS on the desktop by running the following script:

        $ ./prerequisites.sh

Note that CMake version 2.8.7 will automatically be fetched and used for the build. There is no need to install it.


Downloading
-----------

Download the zip file and unzip it into an empty directory or better yet, "git clone" the repository.

Building Open webOS
-------------------
 
Change to the folder where you downloaded the build-desktop scripts and run the build script:

        $ ./build-webos-desktop.sh

Note: This will typically take one to three hours, depending on the speed of your system and of your internet connection. The build will go much faster on a multi-core machine.  
If you experience build errors, try the following:  
  * Verify you are on a compatible system
  * Reapply the prerequisite components
  * Run the build script with the clean parameter: "./build-webos-desktop.sh clean"

Installing Open webOS
---------------------

Change to the folder where the build-desktop scripts are located (if necessary) and run the "install" script to create expected folders and symlinks into various system directories:

        $ sudo ./install-webos-desktop.sh

In general, you should only have to run the install script once (unless you update to a newer version of the script).

You can run `sudo ./install-webos-desktop.sh remove` to remove the system folders and symlinks.


How to Run on Ubuntu Linux
==========================

Please note that this version of the build does not provide full runtime functionality.

1) Change to the folder where the build-desktop scripts are located (if necessary).

2) Start up the service bus:

        $ ./service-bus.sh start

  * The message `hub daemons started` indicates success. You can safely ignore error messages.  

3) The first time you start, you'll need to create a default account:

        $ ./service-bus.sh init
  
  * In order for the FileCache and Email to work properly, "user_xattr" attribute needs to be set on the filesystem where "luna-desktop-binaries/staging" is located. The command to set the attribute is given below.

        $ sudo mount / -o remount,user_xattr

  * Note that the above command will set the attribute temporarily on the filesystem, it will be reset to default settings when machine is rebooted. If you want to make it permenant, edit the file /etc/fstab to add the attribute. Please refer the Ubuntu documentation for more details.

4) Start up the native webOS services on the service bus:

        $ ./service-bus.sh services

  * The message `Services started!` indicates success. You can safely ignore error messages.  

5) Run luna-sysmgr  (ideally from a separate terminal shell window to keep the luna-sysmgr output separate from the service-bus logging)

        $ ./run-luna-sysmgr.sh

  * You can safely ignore the messages from LunaService.

6) When you are finished running luna-sysmgr, stop the service bus:

       $ ./service-bus.sh stop

# Known Issues

  * Error messages are generated in the LunaService log output, which can be ignored.
  * The email application may not work properly.

# Copyright and License Information

Unless otherwise specified, all content, including all source code files and
documentation files in this repository are:

 Copyright (c) 2008-2012 Hewlett-Packard Development Company, L.P.

Unless otherwise specified or set forth in the NOTICE file, all content,
including all source code files and documentation files in this repository are:
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this content except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

