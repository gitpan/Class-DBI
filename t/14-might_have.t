use strict;
use Test::More;

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 10);
}

INIT {
	use lib 't/testlib';
	use Film;
	use Blurb;
	Film->CONSTRUCT;
	Blurb->CONSTRUCT;
}

is(Blurb->primary_column, "title", "Primary key of Blurb = title");
is_deeply [ Blurb->_essential ], [ Blurb->primary_column ], "Essential = Primary";

eval { Blurb->retrieve(10) };
is $@, "", "No problem retrieving non-existent Blurb";

Film->might_have(info => Blurb => qw/blurb/);

{
	ok my $bt = Film->retrieve('Bad Taste'), "Get Film";
	isa_ok $bt, "Film";
	is $bt->info, undef, "No blurb yet";
}

{
	Blurb->make_bad_taste;
	my $bt   = Film->retrieve('Bad Taste');
	my $info = $bt->info;
	isa_ok $info, 'Blurb';

	is $bt->blurb, $info->blurb, "Blurb is the same as fetching the long way";
	ok $bt->blurb("New blurb"), "We can set the blurb";
	$bt->update;
	is $bt->blurb, $info->blurb, "Blurb has been set";
}
