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
__PACKAGE__->table(cdbibintest => 'cdbibintest');
__PACKAGE__->sequence('binseq');
__PACKAGE__->columns(All => qw(id bin));

# __PACKAGE__->data_type(bin => DBI::SQL_BINARY);

sub CONSTRUCT {
	my $class = shift;
	eval { Binary->db_Main->do('DROP TABLE cdbibintest') };
	$class->db_Main->do(qq{CREATE TABLE cdbibintest (id INTEGER, bin BYTEA)});
	$class->db_Main->do(qq{CREATE TEMPORARY SEQUENCE binseq});
	eval qq{ END { Binary->db_Main->do('DROP TABLE cdbibintest') }};
}

1;

