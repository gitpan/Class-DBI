package MyVideo;

require './t/testlib/MyBase.pm';
@ISA = 'MyBase';
use strict;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/videoid title catno/);

sub create_sql { 
  return qq{
    videoid  TINYINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    title    VARCHAR(255),
    catno    VARCHAR(25)
  };
}

1;


