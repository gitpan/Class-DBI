$|=1;
use strict;
use vars qw/$TESTS/;
BEGIN { $TESTS = 40; }

use Test::More tests => $TESTS;

SKIP: {
  eval { require Date::Simple };
  skip "Don't have Date::Simple", $TESTS if $@;

  eval { require './t/testlib/MyFoo.pm' };
  skip "Don't have MySQL: $@", $TESTS if $@;

package main;

ok(my $bar = MyFoo->create({ name => "bar", val => 4, tdate => "2000-01-01" }), "bar");
ok(my $baz = MyFoo->create({ name => "baz", val => 7, tdate => "2000-01-01" }), "baz");
is($baz->id, $bar->id + 1, "Auto incremented primary key");
is($bar->tdate, Date::Simple->new->format, " .. got today's date");
ok(my $wibble = $bar->copy, "Copy with auto_increment");
is($wibble->id, $baz->id + 1, " .. correct key");
ok(my $wobble = $bar->copy(6), "Copy without auto_increment");
is($wobble->id, 6, " .. correct key");
ok($wobble->tdate('2001-01-01') && $wobble->commit, "Set the date of wobble");
isa_ok $wobble->tdate, "Date::Simple";
is($wobble->tdate, Date::Simple->new->format, " but it's set to today");
my $bobble = MyFoo->retrieve($wobble->id);
is($bobble->tdate, Date::Simple->new->format, " set to today in DB too");
isa_ok $bobble->tdate, "Date::Simple";

is MyFoo->count_all, 4, "count_all()";
is MyFoo->minimum_value_of("val"), 4, "min()";
is MyFoo->maximum_value_of("val"), 7, "max()";



require './t/testlib/MyStarLink.pm';
require './t/testlib/MyFilm.pm';
require './t/testlib/MyStar.pm';

ok(my $f1 = MyFilm->create({ title => "Veronique" }), "Create Veronique");
ok(my $f2 = MyFilm->create({ title => "Red" }), "Create Red");

ok(my $s1 = MyStar->create({ name => "Irene Jacob" }), "Irene Jacob");
ok(my $s2 = MyStar->create({ name => "Jerzy Gudejko" }), "Create Jerzy");
ok(my $s3 = MyStar->create({ name => "Frédérique Feder" }), "Create Fred");

ok(my $l1 = MyStarLink->create({ film => $f1, star => $s1 }), "Link 1");
ok(my $l2 = MyStarLink->create({ film => $f1, star => $s2 }), "Link 2");
ok(my $l3 = MyStarLink->create({ film => $f2, star => $s1 }), "Link 3");
ok(my $l4 = MyStarLink->create({ film => $f2, star => $s3 }), "Link 4");

{
	my @ver_star = $f1->stars;
	is @ver_star, 2, "Veronique has 2 stars";
	isa_ok $ver_star[0] => 'MyStar';
	is((join ":", map $_->id, @ver_star),
   	(join ":", map $_->id, ($s1, $s2)), "Correct stars");
}

{
	my @irene = $s1->films;
	is @irene, 2, "Irene Jacob has 2 films";
	isa_ok $irene[0] => 'MyFilm';
	is((join ":", map $_->id, @irene),
   	(join ":", map $_->id, ($f1, $f2)), "Correct stars");
}

{
	my @jerzy = $s2->films;
	is @jerzy, 1, "Jerzy has 1 film";
	is $jerzy[0]->id, $f1->id, " Veronique";
}

# On failed create.
{
	local $SIG{__WARN__} = sub { ok(1, "Warning issued") };

	{ # default is to die
		my $s4 = eval { MyStar->create({ starid => $s1->id, name => "Fred" }) };
		like $@, qr/execute failed/, "Execute fails - so die";
		like $@, qr/Duplicate entry/, " (with Duplicate entry)";
	}

	{
		MyStar->on_failed_create(sub { ::ok(1, "We've failed our create") });
		my $s4 = eval { MyStar->create({ starid => $s1->id, name => "Fred" }) };
    is $@, "", " But we can continue";
  }

	eval { MyFilm->on_failed_create('die') };
	like $@, qr/needs a subref/, "Can't create failed create without subref";
}







}
