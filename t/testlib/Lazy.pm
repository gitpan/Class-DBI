package Lazy;

use strict;
use base qw(Class::DBI);
use File::Temp qw/tempdir/;
my $dir = tempdir( CLEANUP => 1 );

__PACKAGE__->set_db('Main', "DBI:CSV:f_dir=$dir", '', '');
__PACKAGE__->table("Lazy");
__PACKAGE__->columns('Primary', qw(this));
__PACKAGE__->columns('Essential', qw(opop));
__PACKAGE__->columns('things', qw(this that));
__PACKAGE__->columns('horizon', qw(eep orp));
__PACKAGE__->columns('vertical', qw(oop opop));

sub CONSTRUCT {
  my $class = shift;
  $class->db_Main->do(qq{
    CREATE TABLE Lazy (
        this INTEGER,
        that INTEGER,
        eep  INTEGER,
        orp  INTEGER,
        oop  INTEGER,
        opop INTEGER
    )
  });
}

1;


