use strict;
use Test::More tests => 15;
use File::Temp qw/tempdir/;

package Holiday;

use base 'Class::DBI';

{ # setting DB name to not-Main causes warning:
	local $SIG{__WARN__} = sub { ::like $_[0], qr/Main/, "DB name warning" };

	my $dir = ::tempdir( CLEANUP => 1 );
	Holiday->set_db('Foo', "DBI:CSV:f_dir=$dir", '', '', { AutoCommit => 1 });

	my $dbh = Holiday->db_Main;
	::is $dbh->{AutoCommit}, 1, "AutoCommit turned on";
}

{
	local $SIG{__WARN__} = sub { 
		::like $_[0], qr/new.*clashes/, "Column clash warning"
	};
	Holiday->columns(Primary => 'new');
}

{ 
	eval { Holiday->add_constraint };
	::like $@, qr/needs a name/, "Constraint with no name";
	eval { Holiday->add_constraint('check_mate') };
	::like $@, qr/needs a column/, "Constraint needs a column";
	eval { Holiday->add_constraint('check_mate', 'jamtart') };
	::like $@, qr/not a column/, "No such column";
	eval { Holiday->add_constraint('check_mate', 'new') };
	::like $@, qr/needs a code ref/, "Need a coderef";
	eval { Holiday->add_constraint('check_mate', 'new', {}) };
	::like $@, qr/not a code ref/, "Not a coderef";

	eval { Holiday->has_a('new') };
	::like $@, qr/associated class/, "has_a needs a class";

	eval { Holiday->make_filter() };
	::like $@, qr/needs a method/, "make_filter needs a method name";
	{ 
		local $SIG{__WARN__} = sub { 
			::like $_[0], qr/new.*clashes/, "Column clash warning"
		};
	}
}

package main;

eval { my $foo = Holiday->retrieve({ id => 1 }) };
like $@, qr/retrieve a reference/, "Can't retrieve a reference";

eval { my $foo = Holiday->create(id => 10) };
like $@, qr/must be a hashref/, "Can't create without hashref";

eval { my $foo = Holiday->construct({ id => 1 }); };
like $@, qr/protected method/, "Can't call construct";

eval { Holiday->commit; };
like $@, qr/class method/, "Can't call commit as class method";

is (Holiday->table, 'holiday', "Default table name");

Holiday->_flesh('Blanket');
