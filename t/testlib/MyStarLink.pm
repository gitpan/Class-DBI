package MyStarLink;

require './t/testlib/MyBase.pm';
require './t/testlib/MyStar.pm';
require './t/testlib/MyFilm.pm';
@ISA = 'MyBase';
use strict;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/linkid film star/);
__PACKAGE__->hasa(MyFilm => 'film');
__PACKAGE__->hasa(MyStar => 'star');

sub create_sql { 
  return qq{
    linkid  TINYINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    film    TINYINT NOT NULL,
    star    TINYINT NOT NULL
  };
}

1;

