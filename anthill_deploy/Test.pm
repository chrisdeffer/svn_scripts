package Test;


sub new
{
    my $class = shift;
    my $self = {};
    my $probe_host = shift;
    my $rules = shift; # main rules file for probe
    my $probe_dir = shift; # contains the absolute dir name hoabsolute_pathing main rules file
    
    $self->{probe_host} = $probe_host;
    $self->{rules} = $rules;
    $self->{probe_dir} = $probe_dir;
    bless $self, $class;
}

sub get
{
    my $self = shift;
    my $field = shift;
    return $self->{$field};
}

sub set
{
    my $self = shift;
    my $field = shift;
    $self->{$field} = shift;
}
1;

