use strict;
use Test::More;
use File::Temp qw/tempdir/;

#----------------------------------------------------------------------
# Test various errors / warnings / deprecations etc
#----------------------------------------------------------------------

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 26);
}

use File::Temp qw/tempfile/;
my (undef, $DB) = tempfile();
my @DSN = ("dbi:SQLite:dbname=$DB", '', '', { AutoCommit => 1 });

END { unlink $DB if -e $DB }

package Holiday;

use base 'Class::DBI';

sub wibble { shift->croak("Croak dies") }

{    # setting DB name to not-Main causes warning:
	my $did_warn = 0;
	local $SIG{__WARN__} = sub { $did_warn++ if shift =~ /named.*Main/ };
	Holiday->set_db(Foo => @DSN);
	::is $did_warn, 1, "DB connection must be named Main";
	my $dbh = Holiday->db_Main;
	::ok $dbh->{AutoCommit}, "AutoCommit turned on";
}

{
	local $SIG{__WARN__} = sub {
		::like $_[0], qr/new.*clashes/, "Column clash warning";
	};
	Holiday->columns(Primary => 'new');
}

{
	local $SIG{__WARN__} = sub {
		::like $_[0], qr/deprecated/, "create trigger deprecated";
	};
	Holiday->add_trigger('create' => sub { 1 });
	Holiday->add_trigger('delete' => sub { 1 });
}

{
	local $SIG{__WARN__} = sub {
		::like $_[0], qr/deprecated/, "croak() deprecated";
	};

	eval { Holiday->croak("Croak dies") };
	::like $@, qr/Croak dies/, "Croak dies";

	eval { Holiday->wibble };
	::like $@, qr/Croak dies/, "Croak dies";
}

{
	eval { Holiday->add_constraint };
	::like $@, qr/needs a name/, "Constraint with no name";
	eval { Holiday->add_constraint('check_mate') };
	::like $@, qr/needs a valid column/, "Constraint needs a column";
	eval { Holiday->add_constraint('check_mate', 'jamtart') };
	::like $@, qr/needs a valid column/, "No such column";
	eval { Holiday->add_constraint('check_mate', 'new') };
	::like $@, qr/needs a code ref/, "Need a coderef";
	eval { Holiday->add_constraint('check_mate', 'new', {}) };
	::like $@, qr/not a code ref/, "Not a coderef";

	eval { Holiday->has_a('new') };
	::like $@, qr/associated class/, "has_a needs a class";

	eval { Holiday->add_constructor() };
	::like $@, qr/name/, "add_constructor needs a method name";

	eval {
		Holiday->add_trigger(on_setting => sub { 1 });
	};
	::like $@, qr/no longer exists/, "No on_setting trigger";

	{
		local $SIG{__WARN__} = sub {
			::like $_[0], qr/new.*clashes/, "Column clash warning";
		};
	}
}

package main;

eval { my $foo = Holiday->retrieve({ id => 1 }) };
like $@, qr/retrieve a reference/, "Can't retrieve a reference";

eval { my $foo = Holiday->create(id => 10) };
like $@, qr/a hashref/, "Can't create without hashref";

eval { my $foo = Holiday->construct({ id => 1 }); };
like $@, qr/protected method/, "Can't call construct";

{
	my $foo = bless {}, 'Holiday';
	local $SIG{__WARN__} = sub { die $_[0] };
	eval { $foo->has_a(date => 'Date::Simple') };
	like $@, qr/object method/, "has_a is class-level";
}

eval { Holiday->update; };
like $@, qr/class method/, "Can't call update as class method";

is(Holiday->table, 'holiday', "Default table name");

Holiday->_flesh('Blanket');

eval { Holiday->ordered_search() };
like $@, qr/order_by/, "ordered_search no longer works";

eval { Holiday->create({ yonkey => 84 }) };
like $@, qr/not a column/, "Can't create with nonsense column";

eval { Film->_require_class('Class::DBI::__::Nonsense') };
like $@, qr/Can't locate/, "Can't require nonsense class";


