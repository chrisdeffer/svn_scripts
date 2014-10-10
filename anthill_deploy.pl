use lib "/opt/netcool/omnibus/probes/wfotherscripts/svn_script_modules";
use Utils;
use Netcool;
use Log::Log4perl;
use Log::Log4perl::Level;
use Env qw(OMNIHOME NCHOME R);

use strict;

####################################################################################
## - anthill_deploy.pl
##
## * script is launched with params:
## path (svn config file path)
## build (anthill build number)
## package (anthill package name)
## job type (pre or post)
## the probe/wfotherscripts directory
## log level (1 = info, 2= debug)
##
## Paths/Placement:
##
## * anthill_deploy_hook.sh: located in wfotherscripts and each '$R/<probename>/<probefolder>' directory
## * anthill_deploy.pl: located in 'wfotherscripts'
## * There should be directory 'wfotherscripts/svn_script_modules/'. This dir contains
##   the perl modules (Utils.pm/Netcool.pm) used by this program
## * log.conf in 'wfotherscripts/'
## * All individual probe conf files should be in: /opt/netcool/etc/props/svn_script_cfgs/
##
##
### <probe>.conf example
##
##  main = filename of rules file
##  path = path to rules file
##  svn_type= deploy type: 'rules' or 'wfotherscripts'
##  # 1 = delete, 0 = ignore
##  invalid_files = what to do with non-existant svn managed files (1=remove, 0=nothing)
##  # stop services/scripts
##  pre = what actions and processes to STOP during a PRE deployment
##  # start services/scripts
##  post = what actions and processes to START during a POST deployment (entry script name or processes separated by comma)
##  common = Relates to the 'include-common' directory. If deployment is exclusive to this directory,
##           certain scripts may need to be run. (UNI or TRAP)
##  nco_p_syntax = USE THE FOLLOWING FORMAT: /opt/netcool/omnibus/probes/nco_p_syntax -server <OS NAME> -rulesfile
##  # Files to ignore in svn to host comparison
##  white_list = List exact file names to ignore when script is run separated by comma(eg. wf_syslog.rules, ios.match.lookup, etc)
##
## Process:
##
##
## anthill_deploy_hook.sh $1 $2 $3 $4 $5
##
## 1. Anthill calls this script from shell script with params
##    before or after deployment (pre/post)
## 2. log.conf is parsed to setup Log4Perl logging facility
## 3. Probe host is determined (where am I being launched from?)
## 4. Parse 'svn_content.json' and build file->dir perl map
## 5. Parse <probe>.conf (<probe>.conf is in each probe dir and wfotherscripts. Used for getting rules file name)
## 7. If this run is for a probe (non wfotherscript), do syntax check and HUP probe (IF POST DEPLOYMENT)
## 8. For each directory and file listed in svn_content, build file->dir perl map
## 9. Compare hashes
## 10. Log differences
## 11. Delete files not in svn
##
##
##
##
##  UPDATES
##
##
### 09-18-14:CJM - added code to identify files that contain multiple extensions (eg .rules.DATE, .lookup.ORIG, etc)
###                These files are likely not needed in svn and are noted in the logs
### 09-29-14:CJM - added config param 'white_list' to <probe_name>.conf so user can specify filenames to ignore
### 10-07-14:CJM - added pre/post subroutines to be used for type of deployment
### 10-08-14:CJM - added ability to input log level as ARGV
####################################################################################

my $deploytype = 0;
my $path;
my $rules;
my $full_path_rules;
my $syntax_command;
my $netcool;
my $syntax_results;
my $stat;
my $common_dir;
my $svn_type;
my $name;
my $json;
my $remove;
my $temp_file;
my $remove_file;
my $ignore_files;
my $pa_name;

# Input params
my $num_args = $#ARGV + 1;

if ($num_args != 6)
{
  print "\nUsage: $0 param1 param2 param3 param4 param5\n";
  exit;
}

# Load the logging config file located in wfotherscripts/deployscripts
my $log_conf = "$OMNIHOME/probes/wfotherscripts/log.conf";

Log::Log4perl::init($log_conf);
my $conf = Log::Log4perl->get_logger();

# Set log level
if($ARGV[5] == 1)
{
    $conf->level($INFO);
}
elsif($ARGV[5] == 2)
{
    $conf->level($DEBUG);
}
else
{
}


# hook script input params
$conf->debug("Input PARAMS: @ARGV");


# Get local path from hook script

# DEBUG BELOW
#my $cd = "$R/syslog-probes/wf_syslog/";

my $cd = $ARGV[4];
# Get type
my $type = $ARGV[2];

my $info = new Utils;

# Get current host name
my $host = $info->{probe_host};

# Extract out the root folder name for this run
my @tmps = split('/',$cd);

# Get last dir name
$name = @tmps[-1];
chomp($name);

## DEBUG BELOW
#$name = 'wf_syslog';

$conf->debug("USING config file: $name.conf");

# Set up this run using the configuration file

# DEBUG BELOW
#$info->setup("$name."."conf");
$info->setup("/opt/netcool/etc/props/svn_script_cfgs/$name."."conf");

# Get "common" folder type (common snmp or common socket - if common snmp, further actions must be run to
# restart probes/scripts that depend on the common-snmp dir)
$common_dir = $info->{common_dir};

# Get "white_list" items
$ignore_files = $info->{white_list};
$info->set(white_list => "$ignore_files");

# Get pa name
$pa_name = $info->{pa_server};
# delete non-svn files(1=remove, 0=mv to tmp dir)
$remove = $info->{delete};
# Get svn type (rules or wfotherscripts)
$svn_type = $info->{svn_type};
chomp($common_dir, $ignore_files, $pa_name, $svn_type);

$conf->debug("Common rules: $common_dir");
$conf->debug("SVN type: $svn_type");
$conf->debug("Working with DIR: $cd");
$conf->debug("Folder name: $name");
$conf->debug("Will delete non-svn files (1=true, 0=false): $remove");

sub pre_deploy
{
    ################################################################################################
    # pre_deploy                                                                                   #
    # - during pre deployment, run pa processes (value of 'pre') to stop running programs          #
    ################################################################################################
    my $pre_processes = $info->{pre};
    my @procs = split(',',$pre_processes);
        my $arr_size = @procs;
    my $result;
    if ($arr_size >=1)
    {
        $conf->info("about to STOP these processes: @procs");
        $netcool = new Netcool;
        foreach my $item(@procs)
        {
            chomp($item);
            $result = $netcool->pastop($item, $pa_name);
            $conf->debug("pa stop results for $item (0=failed, 1=stopped) : $result");
            $conf->info("pa stop was run on: $item");
        }
        }
    $conf->info("######### END OF PRE Deployment process############");

}


sub post_deploy
{
        ################################################################################################
        # post_deploy                                                                                  #
        # - during post deployment:                                    #
        # compare svn_json content with items on this server                                           #
        # run syntax check if rules                                                                    #
        # run pa start on any processes shut down during pre deployment                                #
        ################################################################################################

    my $post_processes = $info->{post};
    $info->set(svn_json => "$cd"."/svn_content.json");
    $path = $cd;
    $conf->debug("Using json: " +"$cd"."/svn_content.json");
    # Get the rules file name
    $rules = $info->get('rules');

    if($rules=~/"wfotherscripts"/)
    {
        # this is a non rules file anthill deployment
        $deploytype = 1;
    }
    else
    {
        # Build correct path to main rules file
        $path = $info->get('probe_dir');
        $syntax_command = $info->get('syntax');
        chomp($rules,$path,$syntax_command);
        $full_path_rules = $cd."/$rules.rules";
        $syntax_command = "$syntax_command ". $full_path_rules;
        $conf->debug("main rules in: $path");
        $conf->debug("complete path: $full_path_rules");
        $conf->debug("syntax command: $syntax_command");
    }


    # Create a map of the content in svn_json $info->set_svnjson("$ARGV[0]");
    my %svn_ref = $info->create_svn_container($path);

    # Map local files. Now that svn_content hash is created, go through each directory in svn_content,
    # and map a comparison hash of what is on local host
    my %local_files_ref = $info->map_local_files();

    # Map file name to last merge date: This will show key/value pair of svn files to last merge date
    my %dates = $info->get_file_dates();

    if($conf->is_debug())
    {
         while ( my ( $key, $value ) = each %svn_ref )
         {
            $conf->debug("svn_content.json: $key->$value");
         }
         while ( my ( $key, $value ) = each %local_files_ref )
         {
            $conf->debug("local files container: $key->$value");
         }
         while ( my ( $key, $value ) = each %dates )
         {
            $conf->debug("dates container: $key->$value");
         }


    }

    if($deploytype == 0)
    {
        # Create netcool object to run syntax and restart
        $netcool = new Netcool;

        my @procs = split(',',$post_processes);
        my $arr_size = @procs;
        my $result;
        if ($arr_size >=1)
        {
            $conf->info("about to START these processes: @procs");
            foreach my $item(@procs)
            {
               chomp($item);
               $result = $netcool->pastart($item,$pa_name);
               $conf->debug("pa start results for $item (0=failed, 1=stopped) : $result");
            }
        }
        # set the syntax check command
        $netcool->set(syntax => $syntax_command);
        # pass in rules to syntax_check
        $syntax_results = $netcool->syntax_check();

            if($syntax_results == 1)
            {
                $conf->info("Syntax check passed for rules: $rules");
                $stat = $netcool->restart($rules);
                $conf->info("Restarted probe");
                $conf->debug("restart results: 0 = fail, 1 = good, RESULTS: $stat");
            }
            else
            {
                $conf->debug("Failed syntax check: $rules");
            }
    }
    my $local_file_cnt = 0;

    while ( my ( $key, $value ) = each %local_files_ref ) {
        $local_file_cnt+=1;
        if (exists($svn_ref{$key}))
        {
            if($conf->is_debug())
            {
                $conf->debug("Local file is also in svn: $key");
            }
        }
        else
        {
            # All the files that come out of here are not in SVN
            $temp_file = $value.$key;
            $conf->info("invalid file: $temp_file");

            # Code below will first copy invalid files and then remove
            if($remove == 1)
            {
                # Check if file is in the white list
                my $ret = $info->whitelist($key);
                # If so, disregard file
                if($ret == 1)
                {
                    $conf->debug("Encountered white list (ignore file): $key");
                }
                else
                {
                    $info->{invalid_file} = $temp_file;
                    # unlink file
                    $info->remove_file($info->{invalid_file});
                }
            }

        }

    }


my $svn_file_cnt = keys %svn_ref;
$conf->info("Local Files: $local_file_cnt");
$conf->info("SVN Files: $svn_file_cnt");
$conf->info("######### END OF POST Deployment process############");
}

if($type eq "PRE")
{
    $conf->info("#########Starting PRE Deployment process############");
        &pre_deploy;
}
elsif($type eq "POST")
{
    $conf->info("#########Starting POST Deployment process############");
        &post_deploy;
}
else
{
        $conf->info("Unable to determine deployment type (pre/post)");
        exit;
}
