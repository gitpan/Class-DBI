use strict;
use Test::More;

#----------------------------------------------------------------------
# Test database failures
#----------------------------------------------------------------------

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 7);
}

INIT {
	use lib 't/testlib';
	use Film;
	Film->CONSTRUCT;
}

{
	my $btaste = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We have Bad Taste";
	{
		local *Ima::DBI::st::execute = sub { die "Database died" };
		eval { $btaste->delete };
		::like $@, qr/delete.*Database died/s, "We failed";
	}
	my $still = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We still have Bad Taste";
}

{
	my $btaste = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We have Bad Taste";
	$btaste->numexplodingsheep(10);
	{
		local *Ima::DBI::st::execute = sub { die "Database died" };
		eval { $btaste->update };
		::like $@, qr/update.*Database died/s, "We failed";
	}
	$btaste->discard_changes;
	my $still = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We still have Bad Taste";
	is $btaste->numexplodingsheep, 1, "with 1 sheep";
}

