use strict;
use Test::More;

#----------------------------------------------------------------------
# Test lazy loading
#----------------------------------------------------------------------

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 25);
}

INIT {
	use lib 't/testlib';
	use Lazy;
	Lazy->CONSTRUCT;
}

ok(eq_set([ Lazy->columns('Primary') ],   [qw/this/]),      "Pri");
ok(eq_set([ sort Lazy->columns('Essential') ], [qw/opop this/]), "Essential");
ok(eq_set([ sort Lazy->columns('things') ],    [qw/that this/]), "things");
ok(eq_set([ sort Lazy->columns('horizon') ],   [qw/eep orp/]),   "horizon");
ok(eq_set([ sort Lazy->columns('vertical') ],  [qw/oop opop/]),  "vertical");
ok(eq_set([ sort Lazy->columns('All') ], [qw/eep oop opop orp this that/]), "All");

{
	my @groups = Lazy->_cols2groups(qw/this/);
	ok eq_set([ sort @groups], [qw/things Essential Primary/]), "this (@groups)";
}

{
	my @groups = Lazy->_cols2groups(qw/that/);
	ok eq_set(\@groups, [qw/things/]), "that (@groups)";
}

Lazy->create({ this => 1, that => 2, oop => 3, opop => 4, eep => 5 });

ok(my $obj = Lazy->retrieve(1), 'Retrieve by Primary');
ok(exists $obj->{this}, "Gets primary");
ok(exists $obj->{opop}, "Gets other essential");
ok(!exists $obj->{that}, "But other things");
ok(!exists $obj->{eep},  " nor eep");
ok(!exists $obj->{orp},  " nor orp");
ok(!exists $obj->{oop},  " nor oop");

ok(my $val = $obj->eep, 'Fetch eep');
ok(exists $obj->{orp}, 'Gets orp too');
ok(!exists $obj->{oop},  'But still not oop');
ok(!exists $obj->{that}, 'nor that');

{
	Lazy->columns(All => qw/this that eep orp oop opop/);
	ok(my $obj = Lazy->retrieve(1), 'Retrieve by Primary');
	ok !exists $obj->{oop}, " Don't have oop";
	my $null = $obj->eep;
	ok !exists $obj->{oop}, " Don't have oop - even after getting eep";
}

# Test contructor breaking.

eval {    # Need a hashref
	Lazy->create(this => 10, that => 20, oop => 30, opop => 40, eep => 50);
};
ok($@, $@);

eval {    # False column
	Lazy->create({ this => 10, that => 20, theother => 30 });
};
ok($@, $@);

eval {    # Multiple false columns
	Lazy->create({ this => 10, that => 20, theother => 30, andanother => 40 });
};
ok($@, $@);

