package Binary;

use strict;
use base qw(Class::DBI);
use DBI;

my $db   = $ENV{DBD_PG_DBNAME} || 'template1';
my $user = $ENV{DBD_PG_USER}   || 'postgres';
my $pass = $ENV{DBD_PG_PASSWD} || '';

__PACKAGE__->set_db(
	Main => "dbi:Pg:dbname=$db",
	$user, $pass, { AutoCommit => 1 }
);
__PACKAGE__->table(bintest => 'bintest');
__PACKAGE__->columns(All   => qw(id bin));
__PACKAGE__->data_type(bin => DBI::SQL_BINARY);

sub CONSTRUCT {
	my $class = shift;
	$class->db_Main->do(<<'SQL');
CREATE TABLE bintest (id INTEGER, bin BYTEA)
SQL
	eval <<EVAL;
END {
    Binary->db_Main->do(<<'SQL');
DROP TABLE bintest
SQL
    ;
}
EVAL
}

1;

