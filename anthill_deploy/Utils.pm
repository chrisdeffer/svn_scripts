package Utils;
use File::Copy;
use Env qw(OMNIHOME NCHOME R);

sub new
{
    my $class = shift;
    my $self = {};
    my $probe_map = shift || ""; # complete probe cfg file
    my $probe_host = shift || `/bin/hostname`;
    my $rules = shift || ""; # main rules file for probe
    my $svn_json = shift || ""; # json cfg file ( found in all probe dirs )
    my $json = shift || ""; # Line from svn_content that specifies where the svn_content file is located
    my $svn_probe_type = shift || ""; # $svn_probe_type = socket, trap, etc
    my $probe_dir = shift || ""; # contains the absolute dir name hoabsolute_pathing main rules file
    my $next_probe_dir = shift || "";
    my $absolute_path = shift || "";
    my %svn_file_map = (); # hash ref contain key/val pair of $svn_json
    my %host_file_map = ();
    my %filedate = ();
    my $svnentry_timestamp = shift || "";
    my $syntax = shift || "";
    my $common_dir = shift || "";
    my $svn_type = shift || "";
    my $save_dir = shift || "";
    my $invalid_file = shift || "";
    my $pre = shift || "";
    my $post = shift || "";
    my $white_list = shift || "";
    my $pa_server = shift || "";
    $self->{pre} = $pre;
    $self->{post} = $post;
    $self->{svnref} = $svnref;
    $self->{invalid_file} = $invalid_file;
    $self->{svn_json} = $svn_json;
    $self->{probe_host} = $probe_host;
    $self->{svn_file_map} = %svn_file_map;
    $self->{host_file_map} = %host_file_map;
    $self->{filedate} = %filedate;
    $self->{rules} = $rules;
    $self->{svnentry_timestamp} = $svnentry_timestamp;
    $self->{probe_dir} = $probe_dir;
    $self->{syntax} = $syntax;
    $self->{common_dir} = $common_dir;
    $self->{svn_type} = $svn_type;
    $self->{json} = $svn_type;
    $self->{white_list} = $white_list;
    $self->{pa_server} = $pa_server;
    bless $self, $class;
    return $self;
}

sub set
{
    my $self = shift;
    my $field = shift;
    $self->{$field} = shift;
}

sub get
{
    my $self = shift;
    my $field = shift;
    return $self->{$field};
}

sub create_svn_container
{
    #######################################################
    # create_svn_container: returns hash
    #
    # This method reads the svn_content.json file and
    # converts the svn path to the path on the server.
    # Also creates a hash (filename->dir) to be used
    # to compare against the local files hash.
    #######################################################


    my $self = shift;
    my $inpath = shift;
    my $json = $self->{svn_json};
    open SVN, "$json" or die "Can't open : $!";
    my @svn = <SVN>;
    foreach my $svnentry (@svn)
    {
      if($svnentry =~/\.[a-zA-Z]/ || $svnentry =~ m/"time": (.*),/)
      {

        if($svnentry =~/svn_content.json/)
        {
        }
        else
        {
          chomp($1);
          $svnentry_timestamp = scalar(localtime($1));
          # Convert paths like: /netcool/probes/rules/test-probes/trunk/svn_content.json
          # to actual paths on proe host
          $svnentry =~ s/^.*trunk\//$inpath/g;
          $svnentry =~ s/rules\/.*?\/.*?\/\///g;
          # /syslog-probes/wf_syslog/
          my $tempval = clean_string($svnentry);
          my $corrected_path = $tempval;
          chomp($corrected_path);
          if($corrected_path=~/\..*\..*/)
          {
            # tmp array to separate the directory from the svnentry
            my @tmps = split('/',$corrected_path);

            # Get last element (corrected_path)
            my $tmpfile = @tmps[-1];
            chomp($tmpfile);

            # remove filename from corrected path
            $corrected_path =~ s/$tmpfile//g;
            chomp($corrected_path);
            $corrected_path = "/opt/netcool/etc/rules".$corrected_path;
            $svn_file_map{$tmpfile} = "$corrected_path";
            $filedate{$tmpfile} = "$svnentry_timestamp";
          }
         # Check if file in svn contains multiple file extensions (eg .rules.orig.020314 - these files likely DO NOT belong in SVN)
          if($svnentry=~/(\.lookup\.|\.rules\.|\.pl\.)/)
          {
            print "Invalid file?: $svnentry\n";
          }
        }

      }
  }
    return %svn_file_map;
}

sub clean_string
{
    #######################################################
    # clean_string: returns correct server path to files
    #
    # Removes/replaces the "svn_content.json" paths
    # and replaces with meaningful path on this server
    #######################################################

    my @string = @_;
    my $tmp;
    $tmp = $string[0];
    $tmp =~s/\r//g;
    $tmp =~s/\s//g;
    $tmp =~ s/.*?\/rules//g;
    $tmp =~ s/\/trunk//g;
    $tmp =~ s/://g;
    $tmp =~ s/"//g;
    $tmp =~ s/{//g;
    chomp($tmp);
    return $tmp;
}

sub remove_file
{
    #######################################################
    # remove_file: method is void
    #
    # If invalid_file flag is set to "1", this method
    # copies the invalid file to /tmp and then removes
    # the file from the svn managed directory
    #######################################################
    my $self = shift;

    # Invalid file name
    my $file_to_remove = shift;

    # $remove value (1 or 0)
    my $tmp = shift;

    # Where to place the copied files
    my $ext = "/tmp";
    copy($file_to_remove, $ext);

    # Get remove flag
    # If remove == 1, trash it
        if($tmp == 1)
        {
            #unlink $file_to_remove;
            print "removed $file_to_remove\n";
        }
   return $self;
}

sub map_local_files
{
    #######################################################
    # map_local_files: returns local file hash
    #
    # This method takes all the paths ($value) from the
    # svn container and slurps in all the file names
    # n the path on local host. This creates the "host_file_map"
    # container to be used for comparison against svn_file_map.
    #
    ######################################################

    my $self = shift;

    my @local_files;
    while ( my ( $key, $value ) = each %svn_file_map ) {
      if ( -e $value )
      {
        opendir( DIR, $value );
        @local_files = readdir(DIR);
        foreach (@local_files)
        {
           if ( $_ =~ /^[\w-]+\..*/ )
           {
             chomp($value,$_);
             $host_file_map{$_} = "$value";
           }
         }
        }

    }
    return %host_file_map;
}

sub whitelist
{

    my $self = shift;
    # File to check against white list
    my $file_wl = shift;
    my $tmp = $self->{white_list};
    my @wl = split(',',$tmp);
    my $ret = 0;

    if( grep(/.*$file_wl.*/, @wl ))
    {
        $ret = 1;
    }

    return $ret;

}

sub get_file_dates
{
    my $self = shift;
  return %filedate;
}

sub setup
{
    #######################################################
    # set up: populates instance variables
    #
    # This method populates the instance vars defined in
    # Utils.pm. The source is the probe.conf file.
    #######################################################
    my $self = shift;
    my $cfg = shift;
    my ($param1,$param2);
    open CFGFILE, "$cfg" or die "Problems opening : $!";
    foreach my $line (<CFGFILE>)
    {
        #GET line: main: "<rules_file_name.rules>"
        if($line =~ m/main/)
        {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{rules} = $tmp;
        }
        # GET line: example-> "path:/opt/netcool/etc/rules/socket-probes/wfndm_svt_au/"
        if($line =~ m/path/)
        {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{probe_dir} = $tmp;
        }
        if($line =~ m/nco_p_syntax/)
        {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{syntax} = $tmp;
        }
        if($line =~ m/common/)
        {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{common_dir} = $tmp;
        }
        if($line =~ m/svn_type/)
        {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{svn_type} = $tmp;
        }
        if($line =~ m/json/)
        {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{json} = $tmp;
        }
       if($line =~ m/invalid_files/)
       {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{invalid_file} = $tmp;
       }
       if($line =~ m/pre/)
       {
           ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{pre} = $tmp;

       }
       if($line =~ m/post/)
       {
       ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{post} = $tmp;

       }
       if($line =~ m/white_list/)
       {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{white_list} = $tmp;
       }
           if($line =~ m/pa_name/)
       {
            ($param1, $param2) = split(':',$line);
            $tmp = $param2;
            chomp($tmp);
            $self->{pa_server} = $tmp;
       }
    }
    return $self;
}

1;
