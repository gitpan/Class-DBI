package Actor;

require './t/testlib/CDBase.pm';
@ISA = 'CDBase';
use strict;

__PACKAGE__->table('Actor');
__PACKAGE__->columns('All' => qw/ Name Film Salary /);

sub mutator_name { "set_$_[1]" }
  
sub CONSTRUCT {
  my $class = shift;
  $class->create_actors_table;
}

sub create_actors_table {
  my $class = shift;
  $class->db_Main->do(qq{
     CREATE TABLE Actor (
        name            CHAR(40),
        film            VARCHAR(255),   
        salary          INT
     )
  });
}

sub salary_between { 
  my ($class, $low, $high) = @_;
  $class->between(salary => $low, salary => $high);
}

1;
