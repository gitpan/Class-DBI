package MyFilm;

require './t/testlib/MyBase.pm';
require './t/testlib/MyStarLink.pm';
@ISA = 'MyBase';
use strict;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/filmid title/);
__PACKAGE__->has_many(_stars => MyStarLink => 'film');

sub stars { map $_->star, shift->_stars }

sub create_sql { 
  return qq{
    filmid  TINYINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    title   VARCHAR(255)
  };
}

1;

