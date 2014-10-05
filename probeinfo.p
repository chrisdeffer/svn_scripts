#!/opt/netcool/wfperlexe/bin/perl

use strict;
use lib "/users/netcool/anthill_deploy/libs"; 
use ProbeInfo;
my $pi = new ProbeInfo;
my $svn_probe = "socket";
my $main_rules = $pi->get_probe_rules($svn_probe);
print "Main rules file: $main_rules\n";
