$| = 1;
use strict;

use Test::More;

eval { require Date::Simple };
plan skip_all => "Need Date::Simple for this test" if $@;

eval { require 't/testlib/MyFoo.pm' };
plan skip_all => "Need MySQL for this test" if $@;

plan tests => 40;

package main;

ok(
	my $bar = MyFoo->create({ name => "bar", val => 4, tdate => "2000-01-01" }),
	"bar"
);
ok(
	my $baz = MyFoo->create({ name => "baz", val => 7, tdate => "2000-01-01" }),
	"baz"
);
is($baz->id, $bar->id + 1, "Auto incremented primary key");
is($bar->tdate, Date::Simple->new->format, " .. got today's date");
ok(my $wibble = $bar->copy, "Copy with auto_increment");
is($wibble->id, $baz->id + 1, " .. correct key");
ok(my $wobble = $bar->copy(6), "Copy without auto_increment");
is($wobble->id, 6, " .. correct key");
ok($wobble->tdate('2001-01-01') && $wobble->update, "Set the date of wobble");
isa_ok $wobble->tdate, "Date::Simple";
is($wobble->tdate, Date::Simple->new->format, " but it's set to today");
my $bobble = MyFoo->retrieve($wobble->id);
is($bobble->tdate, Date::Simple->new->format, " set to today in DB too");
isa_ok $bobble->tdate, "Date::Simple";

is MyFoo->count_all, 4, "count_all()";
is MyFoo->minimum_value_of("val"), 4, "min()";
is MyFoo->maximum_value_of("val"), 7, "max()";

{
	local $SIG{__WARN__} = sub { };
	require './t/testlib/MyStarLink.pm';
	require './t/testlib/MyFilm.pm';
	require './t/testlib/MyStar.pm';
}

ok(my $f1 = MyFilm->create({ title => "Veronique" }), "Create Veronique");
ok(my $f2 = MyFilm->create({ title => "Red" }),       "Create Red");

ok(my $s1 = MyStar->create({ name => "Irene Jacob" }),      "Irene Jacob");
ok(my $s2 = MyStar->create({ name => "Jerzy Gudejko" }),    "Create Jerzy");
ok(my $s3 = MyStar->create({ name => "Frédérique Feder" }), "Create Fred");

ok(my $l1 = MyStarLink->create({ film => $f1, star => $s1 }), "Link 1");
ok(my $l2 = MyStarLink->create({ film => $f1, star => $s2 }), "Link 2");
ok(my $l3 = MyStarLink->create({ film => $f2, star => $s1 }), "Link 3");
ok(my $l4 = MyStarLink->create({ film => $f2, star => $s3 }), "Link 4");

my $to_ids = sub { join ":", sort map $_->id, @_ };

{
	my @ver_star = $f1->stars;
	is @ver_star, 2, "Veronique has 2 stars ";
	isa_ok $ver_star[0] => 'MyStar';
	is $to_ids->(@ver_star), $to_ids->($s1, $s2), "Correct stars";
}

{
	my @irene = $s1->films;
	is @irene, 2, "Irene Jacob has 2 films";
	isa_ok $irene[0] => 'MyFilm';
	is $to_ids->(@irene), $to_ids->($f1, $f2), "Correct films";
}

{
	my @jerzy = $s2->films;
	is @jerzy, 1, "Jerzy has 1 film";
	is $jerzy[0]->id, $f1->id, " Veronique";
}

{
	ok MyStar->has_many(filmids => [ MyStarLink => 'film', 'id' ] => 'star'),
		"**** Multi-map";
	my @filmid = $s1->filmids;
	ok !ref $filmid[0], "Film-id is not a reference";

	my $first = $s1->filmids->first;
	ok !ref $first, "First is not a reference";
	is $first, $filmid[0], "But it's the same as filmid[0]";
}

{
	ok my $f0 = MyFilm->create({ filmid => 0, title => "Year 0" }),
		"Create with explicit id = 0";
	isa_ok $f0 => 'MyFilm';
	is $f0->id, 0, "ID of 0";
}
