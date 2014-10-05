#!/opt/netcool/wfperlexe/bin/perl

use lib "/users/netcool/anthill_deploy/libs";
use Test;

my $t =  new Test;

$t->set(probe_dir => 'this is fds');

print $t->get('probe_dir');
