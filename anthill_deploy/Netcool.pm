package Netcool;
use strict;
use warnings;

sub new
{

    my $class = shift;
    my $self = {};
    my $syntax = shift || "/opt/netcool/omnibus/probes/nco_p_syntax -server WF_COL_P1 -rulesfile"; 
    $self->{syntax} = $syntax;
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

sub syntax_check
{
    my $self = shift;
    # status = 1 -> passed syntax check
    my $status = 1;
    #print "About to run syntax on: " . $self->{syntax} . "\n";
    my $command = `$self->{syntax}`;
    if ( $command =~ /Rules file syntax OK/ )
    {
        $status = $status;
    }
    else
    {
        $status = 0;
    }

    return $status;
}

sub restart {
    
    my $self = shift;
    my $rules = shift;
    $rules =~ s/\.rules//g;
    chomp($rules);
    my $result;	
    my $proc = `/bin/ps -ef | grep -e "$rules.props" | grep -v grep`;
    my(@tmp,$hupit);
    if(length( $proc )>1) 
    {
        chomp($proc);
	    @tmp = split( /\s+/, $proc );
        chomp($tmp[1]);
        system("/bin/kill -HUP $tmp[1]");
        #print $? . "\n";
        if($? == 0)
        {
            #print "success: reloaded process id :$tmp[1]\n";
            $result = 1;
        }
        else
        {
            #print "failed: reloaded process id :$tmp[1]\n";
            $result = 0;
        }
    }
    else
    {
        $result ="unable to find a process name containing $rules.props";

    }
    return $result;

}


sub start {

}

sub stop {

}

1;

