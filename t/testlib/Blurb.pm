package Blurb;

require './t/testlib/CDBase.pm';
@ISA = 'CDBase';
use strict;

__PACKAGE__->table('Blurbs');
__PACKAGE__->columns('Primary', 'Title');
__PACKAGE__->columns('Blurb', qw/ blurb/);

sub CONSTRUCT {
  my $class = shift;
  $class->create_blurbs_table;
	# $class->make_bad_taste;
}

sub create_blurbs_table {
  my $class = shift;
  $class->db_Main->do(qq{
     CREATE TABLE Blurbs (
        title                   VARCHAR(255),
        blurb                   VARCHAR(255)
    )
  });
}

sub make_bad_taste {
  my $class = shift;
  $class->create({ 
    Title       => 'Bad Taste',
    Blurb       => 'Some interesting text about Bad Taste',
  });
}

1;
