package MyBase;

use strict;
use base qw(Class::DBI);

use vars qw/$dbh/;

my @connect = ("dbi:mysql:test", "", ""); 

$dbh = DBI->connect(@connect) or die DBI->errstr;

__PACKAGE__->set_db('Main', @connect);

sub set_table {
  my $class = shift;
  $class->table($class->create_test_table);
}

sub create_test_table {
  my $self = shift;
  my $table_name = $self->next_available_table;
  my $create = sprintf "CREATE TABLE $table_name ( %s )", $self->create_sql;
  $dbh->do($create);
  eval "END { $self->clean_up }";
  return $table_name;
}

sub next_available_table {
  my $self = shift;
  my @tables = sort @{ $dbh->selectcol_arrayref(qq{
    SHOW TABLES
  })};
  my $table = $tables[-1] || "aaa";
  return "z$table";
}

sub clean_up { 
  my $class = shift;
  my $table = $class->table;
  $dbh->do("DROP TABLE $table");
}

1;
