package MyFoo;

require './t/testlib/MyBase.pm';
@ISA = 'MyBase';
use strict;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/myid name val tdate/);
__PACKAGE__->column_type(tdate => 'Date::Simple');

sub _column_placeholder {
  my ($self, $column) = @_;
  return $column eq "tdate" ? "IF(1, CURDATE(), ?)" : "?";
}


sub create_sql {
  return qq{
    myid mediumint not null auto_increment primary key,
    name varchar(50) not null default '',
    val  char(1) default 'A',
    tdate date not null
  };
}

1;

