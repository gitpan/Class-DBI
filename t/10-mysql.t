$|=1;
use strict;
use vars qw/$TESTS/;
BEGIN { $TESTS = 14; }

use Test::More tests => $TESTS;

SKIP: {
  eval { require Date::Simple };
  skip "Don't have Date::Simple", $TESTS if $@;

  eval { require './t/testlib/MyFoo.pm' };
  skip "Don't have MySQL: $@", $TESTS if $@;

package main;

ok(my $bar = MyFoo->create({ name => "bar", val => 10, tdate => 1 }), "bar");
ok(my $baz = MyFoo->create({ name => "baz", val => 20, tdate => 1 }), "baz");
is($baz->id, $bar->id + 1, "Auto incremented primary key");
is($bar->tdate, Date::Simple->new->format, " .. got today's date");
ok(my $wibble = $bar->copy, "Copy with auto_increment");
is($wibble->id, $baz->id + 1, " .. correct key");
ok(my $wobble = $bar->copy(6), "Copy without auto_increment");
is($wobble->id, 6, " .. correct key");
ok($wobble->tdate(1) && $wobble->commit, "Set the date of wobble");
isa_ok $wobble->tdate, "Date::Simple";
is($wobble->tdate, Date::Simple->new->format, " set OK");
my $bobble = MyFoo->retrieve($wobble->id);
is($bobble->tdate, Date::Simple->new->format, " set OK in DB too");
isa_ok $bobble->tdate, "Date::Simple";

{
	local $SIG{__WARN__} = sub {};
	eval {
		MyFoo->create({ myid => $baz->id, name => "uhoh", val => 10, tdate => 1 });
	};
	like $@, qr/Duplicate entry/, "Create error perpetuated";
}

}
