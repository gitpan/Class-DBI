package Actor;

use strict;
use base 'Class::DBI';
use File::Temp qw/tempdir/;

my $dir = tempdir( CLEANUP => 1 );

__PACKAGE__->set_db('Main', "DBI:CSV:f_dir=$dir", '', '');
__PACKAGE__->table('Actor');
__PACKAGE__->columns('All' => qw/ Name Film Salary /);

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

1;
