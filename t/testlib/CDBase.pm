package CDBase;

use strict;
use base qw(Class::DBI);
use File::Temp qw/tempdir/;
my $dir = tempdir( CLEANUP => 1 );

__PACKAGE__->set_db('Main', "DBI:CSV:f_dir=$dir", '', '');

1;
