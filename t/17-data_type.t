use strict;
use Test::More;
BEGIN {
	eval { require DBD::Pg; };
	plan skip_all => 'DBD::Pg not installed' if $@;
}

use lib 't/testlib';
use Binary;

eval { Binary->CONSTRUCT; };
if ($@) {
    diag <<SKIP;
Pg connection failed. Set env variables DBD_PG_DBNAME,  DBD_PG_USER,
DBD_PG_PASSWD to enable testing.
SKIP
    ;
    plan skip_all => 'Pg connection failed.';
}

plan tests => 40;

for my $id (1..10) {
	my $bin = "foo\0$id";
	my $obj = Binary->create({
		id  => $id,
		bin => $bin,
	});
	isa_ok $obj, 'Binary';
	is $obj->id, $id, "id is $id";
	is $obj->bin, $bin, "insert: bin ok";

	$obj->bin("bar\0$id");
	$obj->commit;

	is $obj->bin, "bar\0$id", "update: bin ok";
}

