use strict;
use Test::More;
use File::Temp qw/tempdir/;

#----------------------------------------------------------------------
# Test various errors / warnings / deprecations etc
#----------------------------------------------------------------------

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 22);
}

use File::Temp qw/tempfile/;
my (undef, $DB) = tempfile();
my @DSN = ("dbi:SQLite:dbname=$DB", '', '', { AutoCommit => 1 });

END { unlink $DB if -e $DB }

package Holiday;

use base 'Class::DBI';

sub wibble { shift->croak("Croak dies") }

{    # setting DB name to not-Main causes warning:
	local $SIG{__WARN__} = sub { ::like $_[0], qr/Main/, "DB name warning" };
	Holiday->set_db(Foo => @DSN);
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
	::like $@, qr/method/, "make_filter needs a method name";

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

eval { Holiday->update; };
like $@, qr/class method/, "Can't call update as class method";

is(Holiday->table, 'holiday', "Default table name");

Holiday->_flesh('Blanket');

