use strict;
use Test::More;

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 14);
}

INIT {
	use lib 't/testlib';
	use Film;
	Film->CONSTRUCT;
}

Film->retrieve_all->delete_all;

my @film  = (
	Film->create({ Title => 'Film 1' }),
	Film->create({ Title => 'Film 2' }),
	Film->create({ Title => 'Film 3' }),
	Film->create({ Title => 'Film 4' }),
	Film->create({ Title => 'Film 5' }),
	Film->create({ Title => 'Film 6' }),
);

{
	my $it1 = Film->retrieve_all;
	isa_ok $it1, "Class::DBI::Iterator";

	my $it2 = Film->retrieve_all;
	isa_ok $it2, "Class::DBI::Iterator";

	while (my $from1 = $it1->next) {
		my $from2 = $it2->next;
		is $from1->id, $from2->id, "Both iterators get $from1";
	}
}

{
	my $it = Film->retrieve_all;
	is $it->first->title, "Film 1", "Film 1 first";
	is $it->next->title, "Film 2", "Film 2 next";
	is $it->first->title, "Film 1", "First goes back to 1";
	is $it->next->title, "Film 2", "With 2 still next";
	$it->reset;
	is $it->next->title, "Film 1", "Reset brings us to film 1 again";
	is $it->next->title, "Film 2", "And 2 is still next;"
}
