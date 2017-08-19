#!/bin/bash
# This is the Bio-Linux 8 update script.  It depends on a few files which can
# be included by packit.perl, which also ensures the script runs as root in a
# temporary directory.

# To make a self-contained version with dependencies:
# $ packit.perl upgrade_to_8.sh > upgrade8.sh

#==I root

# Message to users when they run the script...
#==F message1.txt

# Deb file with keyrings in...
#==F bio-linux-keyring.deb

# New sources.list
#==F sources.list.clean

# CRAN mirror pickerer
#==F pick_cran_mirror.py

# Master package list
#==F bl_master_package_list.txt
#==F bl_install_master_list.sh

# Pseudo-orphans list for pinning
#==F pseudo_orphans.txt

anykey() {
    read -p "Press any key to continue..." -n1
    echo ; echo
}

echo `yes = | head -c 80` $'\n'
cat message1.txt
echo `yes = | head -c 80`
anykey

# Guess who really ran the script - not authoritative but likely right.
REALUSER=$(stat -c%U `tty 2>/dev/null` 2>/dev/null)

# Pull some procedures out into functions for readability
reset_sources_list() {
    bfname="sources.list.`date +%Y%m%d`.tar.gz"

    if ! [ -e "/etc/apt/$bfname" ] ; then
    ( cd /etc/apt ; \
      tar -cvaf "$bfname" sources.list sources.list.d )
      echo "Old configuration saved as /etc/apt/$bfname"
    fi

    rm -f /etc/apt/sources.list.d/*.list

    #Infer what mirror this user is using.

    # I could ask the user to pick from /usr/share/update-manager/mirrors.cfg but this list looks weird and
    # doesn't mention gb.archive.ubuntu.com etc. plus doing a tree picker is a PITA.

    mirrr="`apt-cache policy coreutils | grep -o '^ \{8\}[0-9]\+ [a-z]\+://[^[:space:]]\+' | awk '{print $NF}' | uniq`"
    if [ -z "$mirrr" ] || [ `echo "$mirrr" | wc -l` != 1 ] ; then
	echo "Cannot infer default mirror.  Will keep default of http://gb.archive.ubuntu.com."
	echo "You can change this under \"Download from...\" in the software sources preferences before"
	echo "running the upgrade."
	# Install the list.  Leave it to the Ubuntu installer to update the release name.
	cat sources.list.clean > /etc/apt/sources.list
    else
      sed "s,http://gb.archive.ubuntu.com/ubuntu/,`echo "$mirrr" | sed 's/[,\/&]/\\\\&/g'`," \
	  sources.list.clean > /etc/apt/sources.list
    fi
}

# I tried to get R to pick a CRAN mirror, but it refuses to do that interactively.  But then I
# realised I could make my own fun picker...
infer_cran_mirror() {
    cmirrr="`python pick_cran_mirror.py`"

    if [ -z "$cmirrr" ] || [ "$cmirrr" != "${cmirrr%% *}" ] ; then
	echo "http://www.stats.bris.ac.uk/R/"
    else
	echo "$cmirrr"
    fi
}

# A generic countdown function
countdown()
{
    from=$(( "$1" + 0 ))
    for s in `seq $from -1 1` ; do
	echo -n "$s " ; sleep 1
    done ; echo 0
}

#### Actual update starts here...

# Is this machine updated to 14.04?
# As before, use Python version to infer update status.
# I should probably use lsb-release but I'm not sure exactly when it gets set.
PYVERS=`dpkg -s python | sed -n 's/^Version: \(.*\)/\1/p'`
if ! dpkg --compare-versions 2.7.5-0 le $PYVERS ; then
    echo "Your Python package version is $PYVERS (ie. less than 2.7.5) which indicates"
    echo "that your computer has not yet been updated to Ubuntu 14.04 (Trusty)."
    echo
    echo "The first part of the update process uses the Ubuntu graphical update manager to"
    echo "upgrade the core of your system.  The updater will be launched for you now."
    echo "Follow all instructions, then after rebooting run this update script again."
    echo
    anykey

    #Ensure that the update manager is going to prompt for upgrades.
    # Not necessary if I run do-release-upgrade directly!
#     if [ -f /etc/update-manager/release-upgrades ] ; then
#  	echo " * Ensuring that upgrades are enabled in /etc/update-manager/release-upgrades * "
#  	( grep -v "^#set by bio-linux-prevent-upgrade\|^[Pp]rompt=" /etc/update-manager/release-upgrades ;
#  	  echo "Prompt=lts"
#  	) > /etc/update-manager/release-upgrades.new
#
#  	mv -f /etc/update-manager/release-upgrades.new /etc/update-manager/release-upgrades
#  	echo DONE
#     fi

    #Unpack a minimal/standardised sources.list
    echo " * Cleaning up APT configuration * "
    reset_sources_list
    #apt-get -y update
    echo DONE

    echo " * Removing some troublesome packages * "
    apt-get -y remove python-ubuntuone-control-panel
    #This jams the update, as noted in /var/log/dist-upgrade/main.log
    apt-get -y remove postgresql-plperl-8.4 postgresql-plpython-8.4

    #This will be replaced by r-bioc-qvalue.  Also remove galaxy-server-all
    #but we put it back later.
    dpkg -r --force-all galaxy-server-all
    apt-get -y --purge remove r-cran-qvalue
    apt-get -y --purge remove tigr-glimmer

    'do-release-upgrade' -p -f DistUpgradeViewGtk3

    # Do I care about crud in /var/crash?  Hell no.  All it does is nag the user, then
    # tell them they can't report the error after all.
    rm -rf /var/crash/*

    echo "***"
    echo "The upgrade to Bio-Linux 8 is not yet complete - please reboot, then run this script again."
    echo "***"
    echo "I repeat..."
    echo "The upgrade is NOT YET COMPLETE - please REBOOT, then RUN THIS SCRIPT AGAIN."
    echo "***"
    exit 1
fi

# OK, so now proceed as we did for BL7.  Add the various repos:
# 2 - Bio-Linux PPA
# 3 - c2d4u
# 5 - Bio-Linux @nebc (or at ibiblio?? mirror less important now we use PPA, and I want the stats!)
# 1 - CRAN @ Bris (now mandatory!)
# 6 - Google Chrome and Talk Plugin (repos only)
# 4 - x2go PPA (as opposed to FreeNX PPA)
# 7 - The MATE Desktop, hopefully a drop-in replacement for Gnome for x2go users.

# Ensure we have all keys.  For people who didn't start with BL they lack the keyring,
# so just manually install it here.
dpkg -EGi ./bio-linux-keyring.deb

# Tony pointed out we need this
apt-get -y install software-properties-common
if ! which add-apt-repository >/dev/null ; then
    echo "Can't proceed as add-apt-repository command is not available"
    exit 1
fi

# Note that the BL8 image has /etc/apt/sources.list.d/bl8.installed.save
# so it should be fine to run this script on a BL8 box.

if [ ! -e /etc/apt/sources.list.d/bl8.installed.save ] ; then
    mkdir -p /etc/apt/sources.list.d
#>>>> I can't indent heredocs

# 1 - since my attempts to infer the correct mirror were rubbish, pick it
echo "Trying to run graphical R mirror chooser.  If this fails we'll default to the Bristol one."
cmirrr="`infer_cran_mirror`"
cat >/etc/apt/sources.list.d/cran-latest-r.list <<.
#Latest R-cran packages
deb $cmirrr/bin/linux/ubuntu trusty/
deb-src $cmirrr/bin/linux/ubuntu trusty/
.

# 2 and 3 and 4
echo "Adding PPA repository sources.  If this fails it may indicate a web proxy configuration issue."
{
  set -o errexit
  apt-add-repository -y ppa:nebc/bio-linux
  apt-add-repository -y ppa:marutter/c2d4u
  apt-add-repository -y ppa:x2go/stable
}

# 5
cat >/etc/apt/sources.list.d/bio-linux-legacy.list <<"."
# Bio-Linux legacy packages (manually built, there is no deb-src)
# But there is an alternative mirror you can use.
# deb http://distro.ibiblio.org/bio-linux/packages/ unstable bio-linux
deb http://nebc.nerc.ac.uk/bio-linux/ unstable bio-linux
.

# 6 - to reiterate, we don't install chrome, just make it available.
cat >/etc/apt/sources.list.d/google-chrome.list <<"."
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.
deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main
.
cat >/etc/apt/sources.list.d/google-talkplugin.list <<"."
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.
deb http://dl.google.com/linux/talkplugin/deb/ stable main
.

# 7
#cat >/etc/apt/sources.list.d/mate-desktop.list <<"."
# # MATE is a fork of the Gnome destop.  It provides a suitable environment for
# # non-accelerated graphics diaplays like x2go.
# deb http://repo.mate-desktop.org/archive/1.8/ubuntu trusty main
# deb-src http://repo.mate-desktop.org/archive/1.8/ubuntu trusty main
# .
# TODO - put this into bio-linux-keyring package... Except the MATE repo is unsigned!
#wget -qO - http://mirror1.mate-desktop.org/debian/mate-archive-keyring.gpg | apt-key add -

#<<<<
fi

# Done, now update and upgrade (on a vanilla system this won't do much)
# Some packages need persuasion to upgrade, hence the pinning (see notes in ofile):
ofile=./pseudo_orphans.txt
pfile=./pseudo_orphans.pin
for p in `grep -v "^ *#" $ofile` ; do
    for l in "Package: $p" 'Pin: origin ?*' 'Pin-Priority: 1001' '' ; do echo "$l" ; done
done > $pfile

# If this was run on a Vanilla Ubuntu 14.04 box then Universe/Multiverse sources
# will not be active.  Tell the user about it.
if grep -qw universe   /etc/apt/sources.list && \
   grep -qw multiverse /etc/apt/sources.list ; then
    true
else
    echo "**** Warning:"
    echo "You do not seem to have the Universe and Multiverse components enabled."
    echo "Not all Bio-Linux software will install without these."
    echo "To continue, run 'software-properties-gtk' in another window, select both"
    echo "of these sources to activate them, and click 'Apply' before re-running this"
    echo "script."
    echo "Alternatively you can simply edit /etc/apt/sources.list in an editor."
    exit 1
fi

apt-get -y update
echo "Updating packages.  You may see a warning about downgrades - this is normal."
apt-get -y --force-yes -o "Dir::Etc::Preferences=$pfile" upgrade
apt-get -y --force-yes -o "Dir::Etc::Preferences=$pfile" dist-upgrade

# Remove NX server.  How can I tell if it is in use?
# Or will NX even work after the upgrade from 12.04?
if [ "`dpkg-query -f '${Status}\n' -W freenx 2>/dev/null`" = "install ok installed" ] ; then
  if [ -n "$NXSESSIONID" ] ; then
    echo "You seem to be running an NX session.  But NX server is going to be removed"
    echo "and replaced by x2go.  You are advised to close NX and re-run this script"
    echo "at the console or via regular SSH to complete the update."
    echo
    echo "Update will continue regardless in 7 seconds"
    countdown 7
  fi

  apt-get -y remove --purge freenx freenx-rdp freenx-server freenx-smb freenx-vnc \
                    nx-common nxagent libxcompext3 libnx-xorg
fi

# Special handling for bio-linux-cruft-killer - TODO check it
apt-get -y install bio-linux-cruft-killer || exit 1

#After this point, don't re-write sources.list
date >/etc/apt/sources.list.d/bl8.installed.save

# And now all the stuff that makes BL.  Note that this does need some updating.
# Also, after update, check for dangling symlinks in /usr/local/bioinf
chmod +x ./bl_install_master_list.sh
./bl_install_master_list.sh
if [ $? != 0 ] ; then
    echo "Not all packages installed properly - exiting."
    exit 1
fi

echo "Scrubbing Java6 packages now we have 7 as default"
apt-get remove -y --purge openjdk-6-jre{,-lib,-headless}

echo "Scrubbing HAL as it is obsolete and triggers ugly errors"
apt-get remove -y --purge hal

echo "Removing unity-2d dummy packages."
apt-get remove -y --purge unity-2d{,-common,-panel,-shell,-spread}

# also, we really don't need this
apt-get remove -y --purge python-software-properties

# Purge themes-v7 config and do an autoremove
dpkg -P bio-linux-themes-v7 || true
apt-get -y autoremove

# Yes, this really does seem to best way to infer a VirtualBox envronment
if lspci -n | grep -q '80ee:beef' ; then
    echo "You seem to be in VirtualBox - ensuring drivers are installed"

    apt-get -y install virtualbox-guest-{dkms,source,utils,x11}
fi

echo "Giving Google-Chrome a prod, if you have it installed"
for gc in `dpkg -l 'google-chrome-*' | grep ^ii | awk '{print$2}'` ; do
    dpkg-reconfigure $gc
done

# Ensure zsh has all completion options loaded.
if [ ! -e /etc/zsh/zshrc.ubuntu ] ; then
    echo "Restoring /etc/zsh/zshrc.ubuntu"
    apt-get install --reinstall -o "Dpkg::Options::=--force-confmiss" zsh-common
fi

# Also, this, to ensure you see the right boot screen...
dpkg-reconfigure bio-linux-plymouth-theme

# Aptitude remembers selections, and these will now be invalid
[ -x /usr/bin/aptitude ] && /usr/bin/aptitude keep-all

# Clear /var/crash for reasons given above
rm -rf /var/crash/*

# And finally set the new backdrop by invoking gconf on $REALUSER
# The image should be set up by the bio-linux-themes-v8 package, which is installed as part
# of the master package list.
WALLPAPER=/var/spool/BL_auto_cycling_background.jpg
#echo "DEBUG - WALLPAPER is $WALLPAPER, REALUSER is $REALUSER"
# if [ -e "$WALLPAPER" -a -n "$REALUSER" ] ; then
#     sudo -u "$REALUSER" gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER" >&/dev/null
# fi
# Actually, do it for all users! And account for new quirks in DBUS (Yeah, this is nasty...)
for ahome in /home/* ; do
    auser=`stat -c%U "$ahome"`
    if [ -e "$WALLPAPER" -a -d "$ahome"/.local ] ; then
	sudo -Hu "$auser" dbus-launch gsettings set \
	    org.gnome.desktop.background picture-uri "file://$WALLPAPER" >&/dev/null
	sudo -Hu "$auser" sh -c '. `( ls ~/.cache/upstart/dbus-session 2>/dev/null ;
	                              ls -t ~/.dbus/session-bus/* 2>/dev/null ;
				      echo /dev/null ) | head -n1` && export DBUS_SESSION_BUS_ADDRESS \
		&& '"gsettings set org.gnome.desktop.background picture-uri 'file://$WALLPAPER' >/dev/null 2>&1"
    fi
done

echo
echo
echo "All done - your system is updated to Bio-Linux 8!";
