use strict;

use vars qw/$TESTS/;
BEGIN { $TESTS = 8; }

use Test::More tests => $TESTS;

SKIP: {
  my $dbh = DBI->connect('dbi:mysql:test');
  skip "Don't have MySQL test DB", $TESTS unless $dbh;
  eval { require Date::Simple };
  skip "Don't have Date::Simple", $TESTS if $@;
  my $table = create_test_table($dbh) or
    skip "Can't create MySQL test DB", $TESTS;

  package Foo;
  use base 'Class::DBI';
  __PACKAGE__->set_db('Main', "dbi:mysql:test", '', '');
  __PACKAGE__->table($table);
  __PACKAGE__->columns(All => qw/id name val tdate/);

  sub _column_placeholder {
    my ($self, $column) = @_;
    if ($column eq "tdate") {
      return "IF(1, CURDATE(), ?)";
    }
    return "?";
  }

  package main;
  ok(my $bar = Foo->create({ name => "bar", val => 10, tdate => 1 }), "Create bar");
  ok(my $baz = Foo->create({ name => "baz", val => 20, tdate => 1 }), "Create baz");
  is($baz->id, $bar->id + 1, "Auto incremented primary key");
  is($bar->tdate, Date::Simple->new, " .. got today's date");
  ok(my $wibble = $bar->copy, "Copy with auto_increment");
  is($wibble->id, $baz->id + 1, " .. correct key");
  ok(my $wobble = $bar->copy(6), "Copy without auto_increment");
  is($wobble->id, 6, " .. correct key");

  $dbh->do("DROP TABLE $table");
  $dbh->disconnect;
}

sub create_test_table {
  my $dbh = shift;
  my $table_name = next_available_table($dbh);
  eval {
    my $create = qq{
      CREATE TABLE $table_name (
        id mediumint not null auto_increment primary key,
        name varchar(50) not null default '',
        val  char(1) default 'A',
        tdate date not null
      )
    };
    $dbh->do($create);
  };
  return $@ ? 0 : $table_name;
}

sub next_available_table {
  my $dbh = shift;
  my @tables = sort @{ $dbh->selectcol_arrayref(qq{
    SHOW TABLES
  })};
  my $table = $tables[-1] || "aaa";
  return "z$table";
}

