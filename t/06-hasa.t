use strict;
use Test::More;

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 21);
}

@YA::Film::ISA = 'Film';

local $SIG{__WARN__} = sub { };

INIT {
	use lib 't/testlib';
	use Film;
	use Director;
	Film->CONSTRUCT;
	Director->CONSTRUCT;
}

ok(my $btaste = Film->retrieve('Bad Taste'), "We have Bad Taste");
ok(my $pj = $btaste->Director, "Bad taste hasa() director");
ok(!ref($pj), ' ... which is not an object');

ok(Film->hasa('Director' => 'Director'), "Link Director table");
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

ok($pj = $btaste->Director, "Bad taste now hasa() director");
ok($pj->isa('Director'), ' ... which isa->Director');
is($pj->id, 'Peter Jackson', ' ... and is the correct director');

# Oh no!  Its Peter Jacksons even twin, Skippy!  Born one minute after him.
my $sj = Director->create(
	{
		Name     => 'Skippy Jackson',
		Birthday => (-300000000 + 60),
		IsInsane => 1,
	}
);

is($sj->id, 'Skippy Jackson', 'We have a new director');

{
	eval { $btaste->Director($btaste) };
	like $@, qr/is not an object of type 'Director'/, "Need an object";
}

Film->hasa('Director' => 'CoDirector');
{
	eval { $btaste->CoDirector("Skippy Jackson") };
	like $@, qr/is not an object of type 'Director'/, "Need an object";
}

$btaste->CoDirector($sj);
$btaste->update;
is($btaste->CoDirector->Name, 'Skippy Jackson', 'He co-directed');
is(
	$btaste->Director->Name,
	'Peter Jackson',
	"Didnt interfere with each other"
);

inheriting_hasa();

{

	# Skippy directs a film and Peter helps!
	$sj = Director->retrieve('Skippy Jackson');
	$pj = Director->retrieve('Peter Jackson');

	fail_with_bad_object($sj, $btaste);
	taste_bad($sj,            $pj);
}

sub inheriting_hasa {
	my $btaste = YA::Film->retrieve('Bad Taste');
	is(ref($btaste->Director),   'Director', 'inheriting hasa()');
	is(ref($btaste->CoDirector), 'Director', 'inheriting hasa()');
	is($btaste->CoDirector->Name, 'Skippy Jackson', ' ... correctly');
}

sub taste_bad {
	my ($dir, $codir) = @_;
	my $tastes_bad = YA::Film->create(
		{
			Title             => 'Tastes Bad',
			Director          => $dir,
			CoDirector        => $codir,
			Rating            => 'R',
			NumExplodingSheep => 23
		}
	);
	is($tastes_bad->_Director_accessor, 'Skippy Jackson', 'Director_accessor');
	is($tastes_bad->Director->Name,   'Skippy Jackson', 'Director');
	is($tastes_bad->CoDirector->Name, 'Peter Jackson',  'CoDirector');
	is(
		$tastes_bad->_CoDirector_accessor,
		'Peter Jackson',
		'CoDirector_accessor'
	);
}

sub fail_with_bad_object {
	my ($dir, $codir) = @_;
	eval {
		YA::Film->create(
			{
				Title             => 'Tastes Bad',
				Director          => $dir,
				CoDirector        => $codir,
				Rating            => 'R',
				NumExplodingSheep => 23
			}
		);
	};
	ok $@, $@;
}

