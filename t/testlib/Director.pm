package Director;

require './t/testlib/CDBase.pm';
@ISA = 'CDBase';
use strict;

__PACKAGE__->table('Directors');
__PACKAGE__->columns('All' => qw/ Name Birthday IsInsane /);

sub CONSTRUCT {
  my $class = shift;
  $class->create_directors_table;
}

sub create_directors_table {
  my $class = shift;
  $class->db_Main->do(qq{
     CREATE TABLE Directors (
        name                    VARCHAR(80),
        birthday                INTEGER,
        isinsane                INTEGER
     )
  });
}

1;
