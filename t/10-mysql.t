use strict;

use vars qw/$TESTS/;
BEGIN { $TESTS = 7; }

use Test::More tests => $TESTS;

SKIP: {
  my $dbh = DBI->connect('dbi:mysql:test');
  skip "Don't have MySQL test DB", $TESTS unless $dbh;
  my $table = create_test_table($dbh) or
    skip "Can't create MySQL test DB", $TESTS;

  package Foo;
  use base 'Class::DBI';
  __PACKAGE__->set_db('Main', "dbi:mysql:test", '', '');
  __PACKAGE__->table($table);
  __PACKAGE__->columns(All => qw/id name val/);
  
  package main;
  ok(my $bar = Foo->create({ name => "bar", val => 10 }), "Create bar");
  ok(my $baz = Foo->create({ name => "baz", val => 20 }), "Create baz");
  is($baz->id, $bar->id + 1, "Auto incremented primary key");
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
        val  char(1) default 'A'
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

