use strict;
use Test::More tests => 9;

require './t/testlib/Lazy.pm';
Lazy->CONSTRUCT;

ok( eq_array([sort Lazy->columns('All')], 
             [sort qw(this that eep orp oop opop)]), 
    'autogen columns("All")' );

Lazy->new({this => 1, that => 2, oop => 3, opop => 4, eep => 5});

ok (my $obj = Lazy->retrieve(1), 'Retrieve by Primary');
ok( exists $obj->{this} && exists $obj->{opop} && !exists $obj->{eep}
    && !exists $obj->{oop},  'Lazy fetch' );

ok( my $val = $obj->eep, 'Fetch eep');
ok( exists $obj->{orp},  ' ... gets orp too' );
ok( !exists $obj->{oop}, ' ... but still not oop' );

# Need a hashref
eval {
  Lazy->new(this => 10, that => 20, oop => 30, opop => 40, eep => 50);
};
ok($@, $@);

# False column
eval {
  Lazy->new({this => 10, that => 20, theother => 30});
};
ok($@, $@);

# Multiple false columns
eval {
  Lazy->new({this => 10, that => 20, theother => 30, andanother => 40});
};
ok($@, $@);

