use strict;
use Test::More;

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 12);
}

INIT {
	use lib 't/testlib';
	use Film;
	Film->CONSTRUCT;
}

sub valid_rating {
	my $value = shift;
	my $ok = grep $value eq $_, qw/U Uc PG 12 15 18/;
	return $ok;
}

Film->add_constraint('valid rating', Rating => \&valid_rating);

my %info = (
	Title    => 'La Double Vie De Veronique',
	Director => 'Kryzstof Kieslowski',
	Rating   => '18',
);

{
	local $info{Title}  = "nonsense";
	local $info{Rating} = 19;
	eval { Film->create({%info}) };
	ok $@, $@;
	ok !Film->retrieve($info{Title}), "No film created";
	is(Film->retrieve_all, 1, "Only one film");
}

ok(my $ver = Film->create({%info}), "Can create with valid rating");
is $ver->Rating, 18, "Rating 18";

ok $ver->Rating(12), "Change to 12";
ok $ver->update, "And update";
is $ver->Rating, 12, "Rating now 12";

eval {
	$ver->Rating(13);
	$ver->update;
};
ok $@, $@;
is $ver->Rating, 12, "Rating still 12";
ok $ver->delete, "Delete";

# this threw an infinite loop in old versions
Film->add_constraint('valid director', Director => sub { 1 });
my $fred = Film->create({ Rating => '12' });

# this test is a bit problematical because we don't supply a primary key
# to the create() and the table doesn't use auto_increment or a sequence.
ok $fred, "Got fred";
