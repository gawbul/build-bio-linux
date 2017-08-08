#/usr/bin/perl
#This script simply makes debs of everything in the packages directory

use warnings;
use strict;

chdir ("$HOME/packages/");
print "(o)Reading list of directories\n";
opendir (SOFTWARE, "./") or die "Error in opendir: $!\n";
my @package_list = grep !/^\./, readdir SOFTWARE;
closedir (SOFTWARE) or die "Error in closedir: $!\n";

foreach (@package_list) {
my $version;
	my $package=$_;
	if ($_ =~ /bio/) {
	print "$_\n";
	open (READ, "$_/DEBIAN/control") or die "no\n";
	while (<READ>) {
		if (/^Version/) {
			($version) = $_ =~ /Version:\ (.*)/;
			}else{}
	}
	close (READ);
	my $packagename = $package."_".$version."_i386".".deb";
	`dpkg -b $package $packagename`;


#end if
}

}
