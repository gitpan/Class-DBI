package Director;

use strict;
use base qw(Class::DBI);
use File::Temp qw/tempdir/;

my $dir = tempdir( CLEANUP => 1 );

__PACKAGE__->set_db('Main', "DBI:CSV:f_dir=$dir", '', '');
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
