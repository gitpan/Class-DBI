package MyFilm;

require './t/testlib/MyBase.pm';
@ISA = 'MyBase';
use strict;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/filmid title year sheep/);

sub create_sql { 
  return qq{
    filmid  TINYINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    title   VARCHAR(255),
    year    YEAR,
    sheep   TINYINT
  };
}

1;


