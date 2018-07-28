#!/bin/bash -f
#@(#)build_process_18.04.sh  2018-07-28 S. Moss 

# 
# Changelog  2018-07-28  last modified by S. Moss
#
# Executable bash script based on "build_process_18.04.txt"
#
# Build process:
#     - Changed to "bash" syntax - zsh commands removed
#     - Indentation of commands for readability
#       This does not affect the copy/pasting of commands
#     - Doesn't have to be run from an account called 'manager'
#     - use of '~' has been replaced with $HOME
#     - added [enter chroot] and [exit chroot] with separate indentation to
#       clarify when commands are to be executed in chroot
# Bio-Linux:
#     - Updated Ubuntu base from 14.04.2 to 14.04.5
#     - Optional local .deb to stop usb maker from overlapping partitions
#     - Removed broken splash from liveUSB self checker
#     - Forced liveUSB fat partition to mount read only so that it doesn't
#       get written to or become corrupted when usb removed prematurely
#     - Added the following programs:
#         - mdadm
#         - rkhunter
#         - chkrootkit
# 
# Build process:
# 
# 1) Set up the build machine and unpack the ISO
# 2) Make some changes to the unpacked ISO 
# 3) Chroot into the unpacked ISO and install Bio-Linux
# 4) Remaster and publish
# 5) Auto-build the .ova (with Packer) - not described here, see README    
#

##
## 1) Set up the build machine and unpack the ISO
##

# check which script is running
echo "build_process: running $0"

# use $HOME instead of '~' [set automatically by Linux]
echo "build_process: HOME = $HOME"

# if $HOME isn't set for some reason exit
if [ ! -n $HOME ]; then
    echo "build_process: Error HOME not set"
    exit
fi

# check the build scripts are available
if [ ! -d $HOME/bl9bits ]; then
    echo "build_process: Error \'$HOME/bl9bits\' not available"
    exit
fi

# use a non-interactive APT front-end
export DEBIAN_FRONTEND=noninteractive

# update the host OS if necessary
if [ -z "$(find -H /var/lib/apt/lists -maxdepth 0 -mtime -1)" ]; then
    apt-get -y update
    apt-get -y dist-upgrade
    apt-get -y autoremove --purge
fi

# The following packages must be installed
sudo apt-get -y install squashfs-tools sharutils

# Ubuntu .iso image we're remastering
ISO=ubuntu-18.04.1-desktop-amd64.iso
echo "build_process: ISO = $ISO"

# download the .iso
if [ ! -f $ISO ]; then
    echo "build_process: downloading $ISO ..."
    wget -nv http://releases.ubuntu.com/18.04/$ISO
fi

# unpack the .iso
if [ ! -d reconstructor ]; then 
    mkdir reconstructor
    cd reconstructor
    mkdir initrd remaster root original_cd_image
    sudo mkdir /mnt/cdrom1
    sudo mount -t auto -o loop $HOME/$ISO /mnt/cdrom1
    rsync -av /mnt/cdrom1/ $HOME/reconstructor/remaster/
    chmod -R u+w remaster
    rsync -av /mnt/cdrom1/ $HOME/reconstructor/original_cd_image/
    chmod -R a-w original_cd_image
    sudo umount /mnt/cdrom1
    sudo rmdir  /mnt/cdrom1

    # taken from the 12.04 remaster instructions
    cd initrd
    sudo bash -c "lzcat -Slz ../remaster/casper/initrd.lz | cpio -i"

    # Unpack rootfs
    cd ../root
    mkdir ../squashmount
    sudo mount -t squashfs -o loop,ro ../remaster/casper/filesystem.squashfs ../squashmount/
    sudo rsync -av ../squashmount/ .
    sudo umount ../squashmount
    rmdir ../squashmount
    cd $HOME
fi

##
## 2) Make some changes to the unpacked ISO
##

# remove wubi and autorun [not required for Bio-Linux]
rm -f reconstructor/remaster/wubi.exe reconstructor/remaster/autorun.inf

#
# Install biolinuxfirstboot into chroot
#
# Note this is checked by recon.test.d but not auto-fixed
#
if [ ! -f reconstructor/root/etc/init.d/biolinuxfirstboot ]; then
    cd reconstructor/root/etc/init.d
    sudo cp $HOME/bl9bits/biolinuxfirstboot .
    cd ../rc1.d
    sudo ln -fs ../init.d/biolinuxfirstboot S99biolinuxfirstboot
    cd ../rc2.d
    sudo ln -fs ../init.d/biolinuxfirstboot S99biolinuxfirstboot
    cd $HOME
fi

#
# Everything after here is checked by recon.test.d and fixed automagically :-)
# Details about the changes made by recon are given in the 14.04 build process.
#

# add Ubuntu universe and multiverse repositories to the chroot
if [ ! -f reconstructor/root/etc/apt/sources.list.orig ]; then
    sudo mv reconstructor/root/etc/apt/sources.list \
        reconstructor/root/etc/apt/sources.list.orig
    sudo cp bl9bits/sources.list \
        reconstructor/root/etc/apt/sources.list
fi

# copy script needed install Bio-Linux in the chroot
if [ ! -f reconstructor/root/tmp//upgrade9.sh ]; then
    sudo cp bl9bits/upgrade_to_9/upgrade9.sh \
        reconstructor/root/tmp/
fi

# copy updated bio-linux-usb-maker package for install within chroot
if [ ! -f reconstructor/root/var/cache/apt/archives/bio-linux-usb-maker_8.2-2_all.deb ]; then
    sudo cp bl9bits/Bio-linux-usb-maker/bio-linux-usb-maker_8.2-2_all.deb \
        reconstructor/root/var/cache/apt/archives/
fi

##
## 3) Chroot into the unpacked ISO and install Bio-Linux
##

# [enter chroot]
$HOME/bl9bits/bin/openchroot <<EOF

    # update security key for Google APT repository
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1397BC53640DB551

    # dist-upgrade the chroot
    apt-get update
    apt-get -y dist-upgrade

    # make sure only the most recent Linux kernel is installed
    purge=\$(dpkg -l | awk '/linux-image-[0-9]+/{print \$2}' | head -n -1)
    if [ \$(echo \$purge | wc -w) > 1 ]; then
        apt-get -y purge \$purge
    fi

    # make sure only the most recent kernel headers are installed
    purge=\$(dpkg -l | awk '/linux-headers-[0-9]+/{print \$2}' | head -n -3)
    if [ \$(echo \$purge | wc -w) > 1 ]; then
        apt-get -y purge \$purge
    fi

    # required by "mdadm" [postfix is installed by default]
    apt-get -y install exim4

    #
    # run Steve's upgrade_to_9 script
    #
    sh /tmp/upgrade9.sh

    # post-installation fix-ups
    apt-get -y install bio-linux-fixups

    # install bio-linux-usb-maker within chroot
    apt-get -y install gdebi
    gdebi -n /var/cache/apt/archives/bio-linux-usb-maker_8.2-2_all.deb

    # required for recon.test.d, which can be hard to please...
    apt-get -y install ufw gufw

    # remove unwanted packages
    apt-get -y remove example-content aisleriot --auto-remove --purge

    # Purge any packages marked 'rc'
    apt-get -y purge \$(dpkg -l | awk '/^rc/{print \$2}') 
    apt-get -y autoremove --purge
    apt-get -y autoclean

    # [exit chroot]
    exit
EOF

##
## 4) Remaster and publish
##

# recon may need to be run a few times before it completes
echo now run '$HOME/bl9bits/bin/recon 9.0.0'

##
## 5) Auto-build the .ova (with Packer) - not described here, see README
##
