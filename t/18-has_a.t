use strict;
use Test::More;

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 33);
}

INIT {
	use lib 't/testlib';
	use Film;
	use Director;
	Film->CONSTRUCT;
	Director->CONSTRUCT;
	@YA::Film::ISA = 'Film';
}

ok my $btaste = Film->retrieve('Bad Taste'), "We have Bad Taste";
ok my $pj = $btaste->Director, "Bad taste has a director";
ok !ref($pj), ' ... which is not an object';

ok(Film->has_a('director' => 'Director'), "Link Director table");
ok(
	Director->create(
		{
			Name     => 'Peter Jackson',
			Birthday => -300000000,
			IsInsane => 1
		}
	),
	'create Director'
);

{
	# should output:
	# ok 9 - ID already stored
	# ok 10 -  *** Called get isinsane
	# ok 11 -  *** Need to query db
	# ok 12 - But we know he's insane

	package Director;   # SUPER won't work unless we actually switch package ...
	local *_run_query =
		sub { ::fail("Shouldn't need to query db"); shift->SUPER::_run_query(@_) };

	package main;
	ok $btaste = Film->retrieve('Bad Taste'), "Reretrieve Bad Taste";
	ok $pj = $btaste->Director, "Bad taste now hasa() director";
	isa_ok $pj => 'Director';
	is $pj->id, 'Peter Jackson', 'ID already stored';

	package Director;
	local *_run_query =
		sub { ::pass(" *** Need to query db"); shift->SUPER::_run_query(@_) };

	package main;
	local *Director::get =
		sub { ::pass(" *** Called get $_[1]"); shift->Class::DBI::get(@_) };
	ok $pj->IsInsane, "But we know he's insane";
}

# Oh no!  Its Peter Jacksons even twin, Skippy!  Born one minute after him.
my $sj = Director->create(
	{
		Name     => 'Skippy Jackson',
		Birthday => (-300000000 + 60),
		IsInsane => 1,
	}
);

{
	eval { $btaste->Director($btaste) };
	like $@, qr/is not a Director/, "Can't set film as director";
	is $btaste->Director->id, $pj->id, "PJ still the director";
}

{ # Still inflated after update
	my $btaste = Film->retrieve('Bad Taste');
	isa_ok $btaste->Director, "Director";
	$btaste->numexplodingsheep(17);
	$btaste->update;
	isa_ok $btaste->Director, "Director"; 

	$btaste->Director('Someone Else');
	$btaste->update;
	isa_ok $btaste->Director, "Director"; 
	is $btaste->Director->id, "Someone Else", "Can change director";
}

is $sj->id, 'Skippy Jackson', 'Create new director - Skippy';
Film->has_a('codirector' => 'Director');
{
	eval { $btaste->CoDirector("Skippy Jackson") };
	is $@, "", "Auto inflates";
	isa_ok $btaste->CoDirector, "Director";
	is $btaste->CoDirector->id, $sj->id, "To skippy";
}

$btaste->CoDirector($sj);
$btaste->update;
is($btaste->CoDirector->Name, 'Skippy Jackson', 'He co-directed');
is(
	$btaste->Director->Name,
	'Peter Jackson',
	"Didnt interfere with each other"
);

{    # Inheriting hasa
	my $btaste = YA::Film->retrieve('Bad Taste');
	is(ref($btaste->Director),   'Director', 'inheriting hasa()');
	is(ref($btaste->CoDirector), 'Director', 'inheriting hasa()');
	is($btaste->CoDirector->Name, 'Skippy Jackson', ' ... correctly');
}

{
	$sj = Director->retrieve('Skippy Jackson');
	$pj = Director->retrieve('Peter Jackson');

	my $fail;
	eval {
		$fail = YA::Film->create(
			{
				Title             => 'Tastes Bad',
				Director          => $sj,
				codirector        => $btaste,
				Rating            => 'R',
				NumExplodingSheep => 23
			}
		);
	};
	ok $@,    "Can't have film as codirector: $@";
	is $fail, undef, "We didn't get anything";

	my $tastes_bad = YA::Film->create(
		{
			Title             => 'Tastes Bad',
			Director          => $sj,
			codirector        => $pj,
			Rating            => 'R',
			NumExplodingSheep => 23
		}
	);
	is($tastes_bad->Director->Name, 'Skippy Jackson', 'Director');
	is(
		$tastes_bad->_director_accessor->Name,
		'Skippy Jackson',
		'director_accessor'
	);
	is($tastes_bad->codirector->Name, 'Peter Jackson', 'codirector');
	is(
		$tastes_bad->_codirector_accessor->Name,
		'Peter Jackson',
		'codirector_accessor'
	);
}

