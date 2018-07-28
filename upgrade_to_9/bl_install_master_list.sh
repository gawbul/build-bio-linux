#!/bin/bash
set -u

# A script to help you install a bunch of packages, quickly skipping
# those already installed.
listfile=./bl_master_package_list.txt

if ! [ -e "$listfile" ] ; then
    echo "Missing package list $listfile" ; exit 1
fi

if [ "${1:-}" = "dump" ] ; then
    cat "$listfile" | sed 's/\*$/ [--no-install-recommends]/'
    exit 0
fi

if [ `id -u` = 0 ] ; then
    echo "Running as root - will install for real."
    inst="apt-get install -y "
else
    echo "Not running as root - will just print commands."
    inst="echo sudo apt-get install"
fi

#Sort out multi-arch.
bits64=0
if [ "`dpkg --print-architecture`" = amd64 ] ; then
    bits64=1
    if [ `id -u` = 0 ] && grep -q ':i386$' "$listfile" && \
       ! dpkg --print-foreign-architectures | grep -qx i386 ; then
	# Enabling multi-arch mode
	dpkg --add-architecture i386
	apt-get update
    fi
fi

function findmissingpkgs()
{
    # Will print the names of packages not installed
    # Does this by dumping the list of known packages, then
    # grepping the list at the end of this file.
    ptmplist=`mktemp`

    if [ $bits64 = 1 ] ; then
      dpkg-query -l | grep '^ii' | awk '{print $2":"$4}' | \
	  sed 's/:.*\(:.*\)/\1/ ; s/:\(amd64\|all\)//' > "$ptmplist"
    else
      dpkg-query -l | grep '^ii' | awk '{print $2}' | sed 's/:.*//' > "$ptmplist" 
    fi
    cat "$listfile" | sed 's/\*$//' | grep -xvF -f "$ptmplist"
    grep_res=$?

    rm "$ptmplist" >&2
    [ "$grep_res" != 0 ] ; return $?
}

# Starred packages get --no-install-recommends set
starred_pkgs="`sed -n 's/\*$//p' < "$listfile"`"

for toinstall in `findmissingpkgs` ; do

    if echo "$starred_pkgs" | grep -Fqx "$toinstall" ; then
	$inst --no-install-recommends $toinstall || exit 1
    else
	$inst $toinstall || exit 1
    fi

done

# To deal with anything that was installed but not up-to-date
if [ `id -u` = 0 ] ; then
    apt-get -y dist-upgrade
fi

#Now look to see what packages didn't install
#Note use of grep just to detect if there was any output
echo
echo "Verifying that everything installed..."
findmissingpkgs | sed 's/$/ failed to install/' | grep ''

if [ $? = 1 ] ; then
    #Grep saw no output
    echo "All good!"
else
    exit 2
fi

exit 0
